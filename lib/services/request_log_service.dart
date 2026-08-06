import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum RequestLogKind {
  /// A request the app itself made (IP lookup, speed test, ...).
  app,

  /// A connection that went through the Xray tunnel (from the core's access
  /// log): the site the user visited and the inbound -> outbound path.
  tunnel,
}

class RequestLogEntry {
  const RequestLogEntry({
    required this.time,
    required this.kind,
    required this.target,
    required this.via,
    this.status,
    this.durationMs,
    this.bytes,
    this.error,
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

  final List<RequestLogEntry> _entries = [];
  bool _enabled = false;
  String? _accessLogPath;
  Timer? _tailTimer;
  int _filePosition = 0;

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
  /// 2026/08/06 12:34:56.123 [Info] [Access] tcp:example.com:443 accepted tcp:127.0.0.1:53210 [socks-app -> proxy]
  /// ```
  ///
  /// Returns null for lines that do not describe an accepted/rejected
  /// connection with an inbound -> outbound path (e.g. `connection from ...`).
  @visibleForTesting
  static RequestLogEntry? parseAccessLine(String line) {
    final header = _accessHeader.firstMatch(line);
    if (header == null) {
      return null;
    }
    final time = _parseTime(header.group(1) ?? '');
    final message = header.group(2) ?? '';
    final body = _accessBody.firstMatch(message);
    if (body == null) {
      return null;
    }
    final target = body.group(1) ?? '';
    final action = body.group(2) ?? '';
    final via = body.group(3) ?? '';
    return RequestLogEntry(
      time: time,
      kind: RequestLogKind.tunnel,
      target: _hostOf(target),
      via: via,
      status: action,
    );
  }

  static final _accessHeader = RegExp(
    r'^(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)?)\s+\[Info\]\s+\[Access\]\s+(.*)$',
  );

  /// `tcp:<target>:<port> accepted <local> [inbound -> outbound]`. The target
  /// host may be a sniffed domain or an IPv6 literal in brackets, so the host
  /// group is greedy up to the final port.
  static final _accessBody = RegExp(
    r'^(?:udp|tcp):(.+):\d+\s+(accepted|rejected)\s+.*?\[([^\]]+)\]$',
  );

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
