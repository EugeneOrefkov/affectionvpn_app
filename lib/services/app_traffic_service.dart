import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AppTrafficInfo {
  AppTrafficInfo({
    required this.uid,
    required this.packageName,
    required this.label,
    required this.iconBytes,
    required this.rxBytes,
    required this.txBytes,
  });

  final int uid;
  final String packageName;
  final String label;
  final Uint8List? iconBytes;
  final int rxBytes;
  final int txBytes;

  factory AppTrafficInfo.fromMap(dynamic map) {
    final m = map as Map<dynamic, dynamic>;
    final iconStr = m['icon'] as String? ?? '';
    Uint8List? icon;
    if (iconStr.isNotEmpty) {
      try {
        icon = base64Decode(iconStr);
      } catch (_) {}
    }
    return AppTrafficInfo(
      uid: m['uid'] as int,
      packageName: m['packageName'] as String,
      label: m['label'] as String,
      iconBytes: icon,
      rxBytes: (m['rxBytes'] as num).toInt(),
      txBytes: (m['txBytes'] as num).toInt(),
    );
  }

  int get totalBytes => rxBytes + txBytes;
}

/// Known domain → package name mapping for associating xray access-log
/// entries with the originating Android app.
const domainToPackage = <String, String>{
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
  'jtvnw.net': 'tv.twitch.android.app',
  'twitchcdn.net': 'tv.twitch.android.app',
  'spotify.com': 'com.spotify.music',
  'scdn.co': 'com.spotify.music',
  'soundcloud.com': 'com.soundcloud.android',
  'pinterest.com': 'com.pinterest',
  'pin.it': 'com.pinterest',
  'tumblr.com': 'com.tumblr',
  '4chan.org': 'com Playboy.4chan',
  '4cdn.org': 'com Playboy.4chan',
  'twitch.tv': 'tv.twitch.android.app',
};

class AppTrafficService extends ChangeNotifier {
  AppTrafficService._();
  static final AppTrafficService instance = AppTrafficService._();

  static const _channel = MethodChannel('flutter_vless');

  List<AppTrafficInfo> _activeApps = [];
  List<AppTrafficInfo> get activeApps => _activeApps;

  Timer? _timer;
  bool _enabled = false;

  void start() {
    if (_enabled) return;
    _enabled = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  void stop() {
    _enabled = false;
    _timer?.cancel();
    _timer = null;
    _activeApps = [];
    notifyListeners();
  }

  Future<void> _poll() async {
    try {
      final result = await _channel.invokeMethod<List>('getAppTrafficStats');
      if (result == null || !_enabled) return;
      _activeApps = result
          .map((e) => AppTrafficInfo.fromMap(e))
          .where((a) => a.totalBytes > 0)
          .toList()
        ..sort((a, b) => b.totalBytes.compareTo(a.totalBytes));
      notifyListeners();
    } catch (_) {}
  }

  /// Try to resolve a package name from a URL target (host).
  static String? resolvePackage(String target) {
    var host = target.toLowerCase();
    // Strip port
    final colon = host.lastIndexOf(':');
    if (colon > 0) host = host.substring(0, colon);
    // Strip leading dots
    host = host.replaceAll(RegExp(r'^\.+'), '');

    // Try full domain first, then peel off subdomains
    for (var i = 0; i < 3; i++) {
      final pkg = domainToPackage[host];
      if (pkg != null) return pkg;
      final dot = host.indexOf('.');
      if (dot < 0) break;
      host = host.substring(dot + 1);
    }
    return null;
  }
}
