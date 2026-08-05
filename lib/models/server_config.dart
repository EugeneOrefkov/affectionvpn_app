import 'package:flutter_vless/flutter_vless.dart';

class ServerConfig {
  ServerConfig({
    required this.link,
    required this.remark,
    required this.address,
    required this.port,
    required this.protocol,
    required this.config,
    this.delayMs,
    this.delayCheckedAt,
  });

  final String link;
  final String remark;
  final String address;
  final int port;
  final String protocol;
  final String config;
  int? delayMs;
  DateTime? delayCheckedAt;

  String get displayName {
    if (remark.trim().isNotEmpty) {
      return remark.trim();
    }
    return address;
  }

  String get countryCode {
    final letters = <String>[];
    for (final rune in remark.runes) {
      final ch = String.fromCharCode(rune);
      final code = _regionalIndicatorCode(ch);
      if (code != null) {
        letters.add(code);
      }
      if (letters.length == 2) {
        break;
      }
    }
    return letters.join().toUpperCase();
  }

  bool get hasFlag => countryCode.isNotEmpty;

  static ServerConfig? fromLink(String link) {
    try {
      return fromProfile(FlutterVless.parseFromURL(link));
    } catch (_) {
      return null;
    }
  }

  static ServerConfig? fromProfile(FlutterVlessURL profile) {
    try {
      final outbound = profile.outbound1;
      final address = _outboundAddress(outbound) ?? profile.address;
      final port = _outboundPort(outbound) ?? profile.port;
      final protocol = (outbound['protocol'] as String?) ??
          _protocolFromLink(profile.url) ??
          'xray';
      return ServerConfig(
        link: profile.url,
        remark: profile.remark,
        address: address,
        port: port,
        protocol: protocol,
        config: profile.getFullConfiguration(),
      );
    } catch (_) {
      return null;
    }
  }

  static String? _protocolFromLink(String link) {
    final separator = link.indexOf('://');
    if (separator <= 0) {
      return null;
    }
    return link.substring(0, separator).toLowerCase();
  }

  static Object? _firstField(Object? value, String key) {
    if (value is List) {
      for (final item in value) {
        if (item is Map) {
          final field = item[key];
          if (field != null) {
            return field;
          }
        }
      }
    } else if (value is Map) {
      final field = value[key];
      if (field != null) {
        return field;
      }
    }
    return null;
  }

  static String? _outboundAddress(Map<String, dynamic> outbound) {
    final direct = outbound['address'];
    if (direct is String && direct.isNotEmpty) {
      return direct;
    }
    final settings = outbound['settings'];
    if (settings is Map) {
      final vnext = _firstField(settings['vnext'], 'address');
      if (vnext is String && vnext.isNotEmpty) {
        return vnext;
      }
      final server = _firstField(settings['servers'], 'address');
      if (server is String && server.isNotEmpty) {
        return server;
      }
    }
    return null;
  }

  static int? _outboundPort(Map<String, dynamic> outbound) {
    final direct = outbound['port'];
    if (direct is num && direct > 0) {
      return direct.toInt();
    }
    final settings = outbound['settings'];
    if (settings is Map) {
      final vnext = _firstField(settings['vnext'], 'port');
      if (vnext is num && vnext > 0) {
        return vnext.toInt();
      }
      final server = _firstField(settings['servers'], 'port');
      if (server is num && server > 0) {
        return server.toInt();
      }
    }
    return null;
  }

  String? _regionalIndicatorCode(String char) {
    const offset = 0x1F1E6; // 🇦
    const base = 0x41; // 'A'
    final code = char.runes.isNotEmpty ? char.runes.first : 0;
    if (code >= offset && code < offset + 26) {
      return String.fromCharCode(base + (code - offset));
    }
    return null;
  }

  ServerConfig copyWith({
    String? link,
    String? remark,
    String? address,
    int? port,
    String? protocol,
    String? config,
    int? delayMs,
    DateTime? delayCheckedAt,
    bool clearDelay = false,
  }) {
    return ServerConfig(
      link: link ?? this.link,
      remark: remark ?? this.remark,
      address: address ?? this.address,
      port: port ?? this.port,
      protocol: protocol ?? this.protocol,
      config: config ?? this.config,
      delayMs: clearDelay ? null : (delayMs ?? this.delayMs),
      delayCheckedAt:
          clearDelay ? null : (delayCheckedAt ?? this.delayCheckedAt),
    );
  }
}
