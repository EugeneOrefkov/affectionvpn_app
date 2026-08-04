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
      final parsed = FlutterVless.parseFromURL(link);
      return ServerConfig(
        link: link,
        remark: parsed.remark,
        address: parsed.address,
        port: parsed.port,
        protocol: link.split('://').first.toLowerCase(),
        config: parsed.getFullConfiguration(),
      );
    } catch (_) {
      return null;
    }
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
