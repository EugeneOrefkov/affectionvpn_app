import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

enum RequestLogKind {
  /// A request the app itself made (IP lookup, speed test, ...).
  app,

  /// A connection that went through the Xray tunnel (from the core's access
  /// log): the site the user visited and the inbound -> outbound path.
  tunnel,
}

class RequestLogEntry {
  RequestLogEntry({
    required this.time,
    required this.kind,
    required this.target,
    required this.via,
    this.status,
    this.durationMs,
    this.bytes,
    this.error,
    this.appPackage,
  });

  final DateTime time;
  final RequestLogKind kind;

  /// Host (or URL) the request went to.
  final String target;

  /// How the traffic was carried: `direct`/`socks` for app requests, or the
  /// `inbound -> outbound` pair for tunnel connections.
  final String via;

  /// HTTP status for app requests, or `accepted`/`rejected` for tunnel lines.
  final String? status;
  final int? durationMs;
  final int? bytes;
  final String? error;

  /// Resolved Android package name when the domain maps to a known app.
  final String? appPackage;

  /// Reverse-DNS hostname when [target] is a bare IP address.
  String? dnsName;

  /// Base64-decoded app icon bytes (WebP), null until fetched.
  Uint8List? appIcon;
}

/// Collects request logging: the app's own requests (through [TunnelHttp])
/// and every connection that crossed the Xray tunnel, parsed from the core's
/// access log file.
///
/// The access log lives in the app's data directory:
///  - Android: `<files>/access.log` (the vendored plugin points `log.access`
///    there when it sanitizes the runtime config);
///  - Linux: `<app support>/xray/access.log` (injected by
///    [LinuxVlessPlatform.prepareRuntime]).
///
/// The tunnel lines are picked up by polling the file once a second and only
/// reading the bytes appended since the last poll, so nothing is ever
/// re-emitted across sessions.
class RequestLogService extends ChangeNotifier {
  RequestLogService._();
  static final RequestLogService instance = RequestLogService._();

  static const _maxEntries = 500;
  static const _tailInterval = Duration(seconds: 1);
  static const _channel = MethodChannel('flutter_vless');

  final List<RequestLogEntry> _entries = [];
  bool _enabled = false;
  String? _accessLogPath;
  Timer? _tailTimer;
  int _filePosition = 0;

  /// Package name → cached icon bytes (avoid repeated IPC calls).
  final Map<String, Uint8List?> _iconCache = {};

  bool get enabled => _enabled;

  List<RequestLogEntry> get entries => List.unmodifiable(_entries);

  /// Resolves the access log path for the current platform. Call once during
  /// app startup; the path cannot change afterwards.
  Future<void> init() async {
    _accessLogPath = await _resolveAccessLogPath();
  }

  Future<String?> _resolveAccessLogPath() async {
    if (Platform.isAndroid) {
      final dir = await getApplicationSupportDirectory();
      return '${dir.path}/access.log';
    }
    if (Platform.isLinux) {
      final dir = await getApplicationSupportDirectory();
      return '${dir.path}/xray/access.log';
    }
    return null;
  }

  /// Enables or disables logging. Enabling clears the current log and resumes
  /// tailing from the end of the access file; disabling stops the tailer.
  void setEnabled(bool value) {
    if (value == _enabled) {
      return;
    }
    _enabled = value;
    if (value) {
      _entries.clear();
      _filePosition = _fileLength();
      _tailTimer?.cancel();
      _tailTimer = Timer.periodic(_tailInterval, (_) => _pollAccessLog());
    } else {
      _tailTimer?.cancel();
      _tailTimer = null;
      _entries.clear();
    }
    notifyListeners();
  }

  /// Records an app-level request. No-op when logging is disabled; never
  /// throws so low-level HTTP paths can call it freely.
  void logAppRequest({
    required String target,
    required String via,
    String? status,
    int? durationMs,
    int? bytes,
    String? error,
  }) {
    if (!_enabled) {
      return;
    }
    _add(
      RequestLogEntry(
        time: DateTime.now(),
        kind: RequestLogKind.app,
        target: target,
        via: via,
        status: status,
        durationMs: durationMs,
        bytes: bytes,
        error: error,
      ),
    );
  }

  void clear() {
    if (_entries.isEmpty) {
      return;
    }
    _entries.clear();
    notifyListeners();
  }

  void _add(RequestLogEntry entry) {
    _entries.add(entry);
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
    notifyListeners();
    // Enrich asynchronously: DNS lookup for IPs + app icon fetch.
    _enrich(entry);
  }

  /// Enriches a single entry with DNS name and app icon, then notifies.
  Future<void> _enrich(RequestLogEntry entry) async {
    final futures = <Future<void>>[];

    // DNS reverse lookup when target is a bare IP.
    if (entry.dnsName == null && _isIp(entry.target)) {
      futures.add(_resolveDns(entry));
    }

    // App icon fetch when package is known.
    if (entry.appPackage != null && entry.appIcon == null) {
      futures.add(_fetchIcon(entry));
    }

    if (futures.isEmpty) return;
    await Future.wait(futures);
    if (_entries.contains(entry)) {
      notifyListeners();
    }
  }

  static bool _isIp(String target) {
    // Strip port if present.
    var host = target;
    final colon = host.lastIndexOf(':');
    if (colon > 0 && !host.contains('://')) host = host.substring(0, colon);
    return InternetAddress.tryParse(host) != null;
  }

  Future<void> _resolveDns(RequestLogEntry entry) async {
    try {
      var host = entry.target;
      final colon = host.lastIndexOf(':');
      if (colon > 0 && !host.contains('://')) host = host.substring(0, colon);
      final result = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 2));
      if (result.isNotEmpty && result.first.type == InternetAddressType.IPv4) {
        // We want the hostname; lookup by IP returns the IP, so use raw lookup.
      }
      // Actually: reverse lookup via raw DNS.
      final ptr = await _reverseLookup(host);
      if (ptr != null) {
        entry.dnsName = ptr;
      }
    } catch (_) {}
  }

  static Future<String?> _reverseLookup(String ip) async {
    try {
      final addr = await InternetAddress.lookup(ip).timeout(
        const Duration(seconds: 2),
      );
      if (addr.isNotEmpty) {
        final host = addr.first.host;
        // Only use if it actually resolved to a different name.
        if (host != ip) return host;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _fetchIcon(RequestLogEntry entry) async {
    final pkg = entry.appPackage;
    if (pkg == null) return;
    if (_iconCache.containsKey(pkg)) {
      entry.appIcon = _iconCache[pkg];
      return;
    }
    try {
      final b64 = await _channel.invokeMethod<String>(
        'getAppIcon',
        {'packageName': pkg},
      );
      if (b64 != null && b64.isNotEmpty) {
        entry.appIcon = base64Decode(b64);
        _iconCache[pkg] = entry.appIcon;
      } else {
        _iconCache[pkg] = null;
      }
    } catch (_) {
      _iconCache[pkg] = null;
    }
  }

  int _fileLength() {
    final path = _accessLogPath;
    if (path == null) {
      return 0;
    }
    try {
      final file = File(path);
      return file.existsSync() ? file.lengthSync() : 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _pollAccessLog() async {
    final path = _accessLogPath;
    if (path == null || !_enabled) {
      return;
    }
    try {
      final file = File(path);
      if (!file.existsSync()) {
        _filePosition = 0;
        return;
      }
      final length = file.lengthSync();
      // The core may have rotated/truncated the file between polls.
      if (length < _filePosition) {
        _filePosition = 0;
      }
      if (length == _filePosition) {
        return;
      }
      final raf = file.openSync();
      try {
        raf.setPositionSync(_filePosition);
        final bytes = raf.readSync(length - _filePosition);
        _filePosition = length;
        final text = utf8.decode(bytes, allowMalformed: true);
        for (final line in text.split('\n')) {
          final entry = parseAccessLine(line);
          if (entry != null) {
            _add(entry);
          }
        }
      } finally {
        raf.closeSync();
      }
    } catch (_) {}
  }

  /// Parses one line of the Xray access log, e.g.
  ///
  /// ```
  /// 2026/08/07 08:46:15.370176 from 127.0.0.1:37148 accepted http://example.com/ [http >> direct]
  /// 2026/08/07 08:46:15.451468 from 127.0.0.1:37150 accepted //example.com:443 [http >> direct]
  /// ```
  ///
  /// The core always renders lines as
  /// `from <client> <accepted|rejected> <target> [inbound >> outbound]`,
  /// optionally followed by a `reason:`/`email:` tail. The `<target>` is the
  /// sniffed host (an `http(s)://` URL, a bare `//host:port` CONNECT, or a
  /// `tcp:`/`udp:` destination). Returns null for anything else.
  /// Known domain → Android package name mapping.
  static const domainToPackage = <String, String>{
    'youtube.com': 'com.google.android.youtube',
    'googlevideo.com': 'com.google.android.youtube',
    'ytimg.com': 'com.google.android.youtube',
    'youtu.be': 'com.google.android.youtube',
    'twitter.com': 'com.twitter.android',
    'x.com': 'com.twitter.android',
    'twimg.com': 'com.twitter.android',
    'facebook.com': 'com.facebook.katana',
    'fbcdn.net': 'com.facebook.katana',
    'instagram.com': 'com.instagram.android',
    'cdninstagram.com': 'com.instagram.android',
    'tiktok.com': 'com.zhiliaoapp.musically',
    'tiktokcdn.com': 'com.zhiliaoapp.musically',
    'reddit.com': 'com.reddit.frontpage',
    'redd.it': 'com.reddit.frontpage',
    'redditstatic.com': 'com.reddit.frontpage',
    'discord.com': 'com.discord',
    'discord.gg': 'com.discord',
    'discordapp.com': 'com.discord',
    'telegram.org': 'org.telegram.messenger',
    't.me': 'org.telegram.messenger',
    'telegram.me': 'org.telegram.messenger',
    'whatsapp.com': 'com.whatsapp',
    'whatsapp.net': 'com.whatsapp',
    'vk.com': 'com.vkontakte.android',
    'vkuseraudio.net': 'com.vkontakte.android',
    'ok.ru': 'com.odnoklassniki.android',
    'yandex.ru': 'ru.yandex.searchplugin',
    'yandex.net': 'ru.yandex.searchplugin',
    'ya.ru': 'ru.yandex.searchplugin',
    'mail.ru': 'ru.mail.mail',
    'google.com': 'com.google.android.googlequicksearchbox',
    'googleapis.com': 'com.google.android.googlequicksearchbox',
    'gstatic.com': 'com.google.android.googlequicksearchbox',
    'maps.google.com': 'com.google.android.apps.maps',
    'drive.google.com': 'com.google.android.apps.docs',
    'docs.google.com': 'com.google.android.apps.docs',
    'meet.google.com': 'com.google.android.apps.tachyon',
    'photos.google.com': 'com.google.android.apps.photos',
    'calendar.google.com': 'com.google.android.calendar',
    'play.google.com': 'com.android.vending',
    'music.youtube.com': 'com.google.android.apps.youtube.music',
    'music.yandex.ru': 'ru.yandex.music',
    'kinopoisk.ru': 'com.yandex.android.kinopoisk',
    'dzen.ru': 'ru.yandex.browser',
    'pikabu.ru': 'ru.pikabu.android',
    'boosty.to': 'ru.boosty.app',
    'twitch.tv': 'tv.twitch.android.app',
    'jtvnw.net': 'tv.twitch.android.app',
    'twitchcdn.net': 'tv.twitch.android.app',
    'spotify.com': 'com.spotify.music',
    'scdn.co': 'com.spotify.music',
    'soundcloud.com': 'com.soundcloud.android',
    'pinterest.com': 'com.pinterest',
    'pin.it': 'com.pinterest',
  };

  /// Short human-readable label derived from a package name.
  static String appLabel(String pkg) {
    const overrides = <String, String>{
      'com.google.android.youtube': 'YouTube',
      'com.twitter.android': 'Twitter/X',
      'com.facebook.katana': 'Facebook',
      'com.instagram.android': 'Instagram',
      'com.zhiliaoapp.musically': 'TikTok',
      'com.reddit.frontpage': 'Reddit',
      'com.discord': 'Discord',
      'org.telegram.messenger': 'Telegram',
      'com.whatsapp': 'WhatsApp',
      'com.vkontakte.android': 'VK',
      'com.odnoklassniki.android': 'OK.ru',
      'ru.yandex.searchplugin': 'Яндекс',
      'ru.mail.mail': 'Mail.ru',
      'com.google.android.googlequicksearchbox': 'Google',
      'com.google.android.apps.youtube.music': 'YT Music',
      'ru.yandex.music': 'Я.Музыка',
      'com.yandex.android.kinopoisk': 'Кинопоиск',
      'ru.yandex.browser': 'Яндекс.Браузер',
      'ru.pikabu.android': 'Pikabu',
      'ru.boosty.app': 'Boosty',
      'tv.twitch.android.app': 'Twitch',
      'com.spotify.music': 'Spotify',
      'com.soundcloud.android': 'SoundCloud',
      'com.pinterest': 'Pinterest',
      'com.google.android.apps.maps': 'Google Maps',
      'com.google.android.apps.docs': 'Google Docs',
      'com.google.android.apps.tachyon': 'Google Meet',
      'com.google.android.apps.photos': 'Google Photos',
    };
    return overrides[pkg] ?? pkg.split('.').last;
  }

  /// Resolves an Android package name from a URL target (host).
  static String? resolvePackage(String target) {
    var host = target.toLowerCase();
    final colon = host.lastIndexOf(':');
    if (colon > 0) host = host.substring(0, colon);
    host = host.replaceAll(RegExp(r'^\.+'), '');

    for (var i = 0; i < 3; i++) {
      final pkg = domainToPackage[host];
      if (pkg != null) return pkg;
      final dot = host.indexOf('.');
      if (dot < 0) break;
      host = host.substring(dot + 1);
    }
    return null;
  }

  @visibleForTesting
  static RequestLogEntry? parseAccessLine(String line) {
    final match = _accessLine.firstMatch(line);
    if (match == null) {
      return null;
    }
    final time = _parseTime(match.group(1) ?? '');
    final action = match.group(2) ?? '';
    final target = match.group(3) ?? '';
    final via = match.group(4) ?? '';
    final normalized = _normalizeTarget(target);
    return RequestLogEntry(
      time: time,
      kind: RequestLogKind.tunnel,
      target: normalized,
      via: via,
      status: action,
      appPackage: resolvePackage(normalized),
    );
  }

  static final _accessLine = RegExp(
    r'^(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)?)\s+from\s+\S+\s+'
    r'(accepted|rejected)\s+(.+?)(?:\s+\[([^\]]+)\])?(?:\s+.+)?$',
  );

  /// Extracts a displayable host[:port] from the raw `<target>` segment:
  /// strips an `http(s)://` scheme, a leading `//` (CONNECT), a `tcp:`/`udp:`
  /// prefix, and any URL path.
  static String _normalizeTarget(String raw) {
    var target = raw.trim();
    final scheme = _targetScheme.firstMatch(target);
    if (scheme != null) {
      target = target.substring(scheme.end);
    } else if (target.startsWith('//')) {
      target = target.substring(2);
    } else {
      target = target.replaceFirst(_targetProtocol, '');
    }
    final slash = target.indexOf('/');
    if (slash >= 0) {
      target = target.substring(0, slash);
    }
    return _hostOf(target);
  }

  static final _targetScheme =
      RegExp(r'^(?:https?|tcp|udp|tls|kcp|quic|ws|wss)://');

  static final _targetProtocol = RegExp(r'^(?:tcp|udp):');

  static String _hostOf(String target) {
    if (target.startsWith('[')) {
      final end = target.indexOf(']');
      if (end > 0) {
        return target.substring(1, end);
      }
    }
    return target;
  }

  static DateTime _parseTime(String raw) {
    try {
      return DateTime.parse(raw).toLocal();
    } catch (_) {
      return DateTime.now();
    }
  }
}
