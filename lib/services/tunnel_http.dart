import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'request_log_service.dart';

/// Minimal SOCKS5 + HTTP/1.1 client used to reach the internet through the
/// app's local Xray tunnel (current IP lookup, download speed test) without
/// relying on the native plugin, which only exposes a HEAD probe.
///
/// Both endpoints are plain HTTP on port 80, which keeps the client free of
/// TLS while still traversing the tunnel.
class TunnelHttp {
  TunnelHttp({
    required this.host,
    required this.port,
    this.username,
    this.password,
  }) : direct = false;

  /// Direct client: connects straight to the target host, skipping the local
  /// SOCKS proxy. Used when the tunnel is off, e.g. to show the real IP and
  /// measure the plain internet speed.
  TunnelHttp.direct()
      : host = '',
        port = 0,
        username = null,
        password = null,
        direct = true;

  final String host;
  final int port;
  final String? username;
  final String? password;
  final bool direct;

  static const _connectTimeout = Duration(seconds: 6);
  static const _ipUrl = 'http://checkip.amazonaws.com';
  static const _speedUrl = 'http://speed.cloudflare.com/__down?bytes=50000000';

  /// Fetches the public IP address visible through the tunnel. Returns null on
  /// any failure (not connected, tunnel not up, ...).
  Future<String?> fetchIp() async {
    try {
      final response = await _request(_ipUrl);
      final body = response.body.trim();
      return body.isEmpty ? null : body;
    } catch (_) {
      return null;
    }
  }

  /// Downloads a test payload through the tunnel for up to [duration] and
  /// returns the average speed in megabits per second. Returns null on failure.
  Future<double?> measureMbps({
    Duration duration = const Duration(seconds: 5),
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final conn = await _connect(_speedUrl);
      final socket = conn.socket;
      final reader = conn.reader;
      try {
        final request = _url(_speedUrl);
        _sendRequest(socket, 'GET', request.path, host: request.host);
        await reader.readLine();
        while (true) {
          final line = await reader.readLine();
          if (line.isEmpty) {
            break;
          }
        }
        final bytes = await reader.readToEnd(timeout: duration);
        stopwatch.stop();
        final seconds = stopwatch.elapsedMilliseconds / 1000.0;
        final mb = bytes.length / (1024 * 1024);
        _logRequest(
          _speedUrl,
          status: '200',
          durationMs: stopwatch.elapsedMilliseconds,
          bytes: bytes.length,
        );
        return seconds > 0 ? (mb * 8) / seconds : null;
      } finally {
        socket.destroy();
      }
    } catch (_) {
      _logRequest(_speedUrl, error: 'speed test failed');
      return null;
    }
  }

  Future<_Response> _request(String url) async {
    final stopwatch = Stopwatch()..start();
    final uri = _url(url);
    final conn = await _connect(url);
    final socket = conn.socket;
    final reader = conn.reader;
    try {
      _sendRequest(socket, 'GET', uri.path, host: uri.host);
      final statusLine = await reader.readLine();
      final status = statusLine.split(' ').elementAtOrNull(1);
      final headers = <String, String>{};
      while (true) {
        final line = await reader.readLine();
        if (line.isEmpty) {
          break;
        }
        final idx = line.indexOf(':');
        if (idx > 0) {
          headers[line.substring(0, idx).trim().toLowerCase()] =
              line.substring(idx + 1).trim();
        }
      }
      final length = int.tryParse(headers['content-length'] ?? '') ?? 0;
      final bodyBytes = await reader.read(length);
      _logRequest(
        url,
        status: status,
        durationMs: stopwatch.elapsedMilliseconds,
        bytes: bodyBytes.length,
      );
      return _Response(
        status: status,
        body: utf8.decode(bodyBytes, allowMalformed: true),
      );
    } finally {
      socket.destroy();
    }
  }

  void _logRequest(
    String url, {
    String? status,
    int? durationMs,
    int? bytes,
    String? error,
  }) {
    try {
      RequestLogService.instance.logAppRequest(
        target: url,
        via: direct ? 'direct' : 'socks',
        status: status,
        durationMs: durationMs,
        bytes: bytes,
        error: error,
      );
    } catch (_) {}
  }

  _Url _url(String url) {
    final uri = Uri.parse(url);
    final path = uri.path.isEmpty ? '/' : uri.path;
    final query = uri.query.isEmpty ? '' : '?${uri.query}';
    return _Url(host: uri.host, path: '$path$query');
  }

  void _sendRequest(Socket socket, String method, String path,
      {required String host}) {
    socket.add(utf8.encode(
        '$method $path HTTP/1.1\r\n'
        'Host: $host\r\n'
        'User-Agent: AffectionVPN/1.0\r\n'
        'Accept: */*\r\n'
        'Connection: close\r\n'
        '\r\n'));
  }

  /// Opens the connection to the target host of [url]. In [direct] mode it is
  /// a plain TCP connection; otherwise a SOCKS5 connection through the local
  /// tunnel. The caller owns the returned socket and must close it; [reader]
  /// stays attached for the whole lifetime of the socket (sockets cannot be
  /// re-listened after cancel).
  Future<({Socket socket, _BufferedReader reader})> _connect(String url) async {
    final uri = Uri.parse(url);
    final targetPort = uri.hasPort ? uri.port : 80;
    final socket = await Socket.connect(
      direct ? uri.host : host,
      direct ? targetPort : port,
      timeout: _connectTimeout,
    );
    try {
      final reader = _BufferedReader(socket);
      if (!direct) {
        await _socksHandshake(socket, reader, uri.host, targetPort);
      }
      return (socket: socket, reader: reader);
    } catch (_) {
      socket.destroy();
      rethrow;
    }
  }

  Future<void> _socksHandshake(
    Socket socket,
    _BufferedReader reader,
    String targetHost,
    int targetPort,
  ) async {
    final hasAuth =
        (username?.isNotEmpty ?? false) && (password?.isNotEmpty ?? false);
    socket.add(hasAuth ? [0x05, 0x02, 0x00, 0x02] : [0x05, 0x01, 0x00]);
    final greeting = await reader.read(2);
    final method = greeting[1];
    if (method == 0xFF) {
      throw SocketException('SOCKS: no acceptable auth method');
    }
    if (method == 0x02) {
      final u = utf8.encode(username!);
      final p = utf8.encode(password!);
      socket.add([0x01, u.length, ...u, p.length, ...p]);
      final authReply = await reader.read(2);
      if (authReply[1] != 0) {
        throw SocketException('SOCKS: authentication failed');
      }
    }
    final hostBytes = utf8.encode(targetHost);
    socket.add([
      0x05, 0x01, 0x00, 0x03, hostBytes.length, ...hostBytes,
      (targetPort >> 8) & 0xFF,
      targetPort & 0xFF,
    ]);
    final header = await reader.read(4);
    if (header[1] != 0) {
      throw SocketException('SOCKS: connect failed (${header[1]})');
    }
    switch (header[3]) {
      case 0x01:
        await reader.read(6);
      case 0x04:
        await reader.read(18);
      default:
        final len = (await reader.read(1))[0];
        await reader.read(len + 2);
    }
  }

  Future<String> downloadFile(
    String url,
    String destPath, {
    void Function(int received, int total)? onProgress,
  }) async {
    final conn = await _connect(url);
    final socket = conn.socket;
    final reader = conn.reader;
    try {
      final uri = Uri.parse(url);
      socket.write('GET ${uri.path} HTTP/1.0\r\n'
          'Host: ${uri.host}\r\n'
          'User-Agent: AffectionVPN/1.0\r\n'
          'Connection: close\r\n\r\n');
      final statusLine = await reader.readLine();
      if (statusLine == null || !statusLine.contains('200')) {
        throw Exception('HTTP ${statusLine?.split(' ')[1] ?? 'error'}');
      }
      int? total;
      while (true) {
        final header = await reader.readLine();
        if (header == null || header.isEmpty) {
          break;
        }
        final colon = header.indexOf(':');
        if (colon > 0 &&
            header.substring(0, colon).trim().toLowerCase() ==
                'content-length') {
          total = int.tryParse(header.substring(colon + 1).trim());
        }
      }
      final file = File(destPath);
      final sink = file.openWrite();
      var received = 0;
      try {
        final data = await reader.readToEnd(
          timeout: const Duration(seconds: 60),
        );
        received = data.length;
        sink.add(data);
        onProgress?.call(received, total ?? received);
      } finally {
        await sink.flush();
        await sink.close();
      }
      if (total != null && received < total) {
        await file.delete();
        throw Exception('Download incomplete: $received/$total');
      }
      return destPath;
    } finally {
      socket.destroy();
    }
  }
}

class _Response {
  const _Response({this.status, required this.body});

  final String? status;
  final String body;
}

class _Url {
  const _Url({required this.host, required this.path});

  final String host;
  final String path;
}

/// Persistent buffered reader over a socket that never drops bytes that arrive
/// ahead of the reads, so pipelined HTTP responses are consumed correctly.
/// The subscription is kept alive until [readToEnd] finishes or the caller
/// destroys the socket.
class _BufferedReader {
  _BufferedReader(Socket socket) {
    _sub = socket.listen(_onData, onError: _onError, onDone: _onDone);
  }

  StreamSubscription<List<int>>? _sub;
  final List<int> _buffer = [];
  Completer<void>? _available;
  bool _done = false;
  Object? _error;

  void _onData(List<int> data) {
    _buffer.addAll(data);
    _available?.complete();
  }

  void _onError(Object e, StackTrace _) {
    _error = e;
    _available?.complete();
  }

  void _onDone() {
    _done = true;
    _available?.complete();
  }

  Future<void> _ensure() async {
    if (_buffer.isEmpty && !_done && _error == null) {
      _available = Completer<void>();
      await _available!.future;
      _available = null;
    }
  }

  Future<String> readLine() async {
    final buf = BytesBuilder(copy: false);
    while (true) {
      await _ensure();
      if (_buffer.isEmpty) {
        throw SocketException('connection closed');
      }
      final byte = _buffer.removeAt(0);
      if (byte == 0x0A) {
        break;
      }
      if (byte != 0x0D) {
        buf.addByte(byte);
      }
    }
    return utf8.decode(buf.takeBytes(), allowMalformed: true);
  }

  Future<Uint8List> read(int n) async {
    final out = <int>[];
    while (out.length < n) {
      await _ensure();
      if (_buffer.isEmpty) {
        break;
      }
      final take = math.min(n - out.length, _buffer.length);
      out.addAll(_buffer.sublist(0, take));
      _buffer.removeRange(0, take);
    }
    return Uint8List.fromList(out);
  }

  /// Reads until the remote closes or [timeout] elapses. Returns all bytes.
  Future<Uint8List> readToEnd({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final timer = Timer(timeout, () => _available?.complete());
    final builder = BytesBuilder(copy: false);
    final sw = Stopwatch()..start();
    try {
      while (!_done && _error == null) {
        if (_buffer.isNotEmpty) {
          builder.add(_buffer);
          _buffer.clear();
        } else if (sw.elapsedMilliseconds >= timeout.inMilliseconds) {
          break;
        } else {
          await _ensure();
        }
      }
      if (_buffer.isNotEmpty) {
        builder.add(_buffer);
        _buffer.clear();
      }
      return builder.takeBytes();
    } finally {
      timer.cancel();
      _sub?.cancel();
    }
  }
}
