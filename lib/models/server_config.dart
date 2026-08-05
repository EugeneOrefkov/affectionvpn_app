import 'dart:convert';

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

  /// Xray config prepared for the native runtime.
  ///
  /// Remnawave load-balancer nodes carry `routing.balancers`, but the native
  /// plugin injects its own local SOCKS/HTTP inbounds that are not matched by
  /// the original routing rules. Without extra rules the balancer is bypassed
  /// and device traffic always sticks to the first outbound (which may be a
  /// dead/unreliable member of the pool, making the whole node look broken).
  /// This adds routing rules so every local proxy inbound (the config's own,
  /// the plugin-injected `socks`/`http`, and the auth proxy inbound) is
  /// balanced across the balancer's selector.
  String get runtimeConfig => prepareRuntimeConfig(config);

  static String prepareRuntimeConfig(String config) {
    try {
      final map = jsonDecode(config) as Map<String, dynamic>;
      final routing = map['routing'];
      if (routing is! Map) {
        return config;
      }
      final balancers = routing['balancers'];
      if (balancers is! List || balancers.isEmpty) {
        return config;
      }
      String? balancerTag;
      for (final balancer in balancers) {
        if (balancer is Map) {
          final tag = balancer['tag'];
          if (tag is String && tag.isNotEmpty) {
            balancerTag = tag;
            break;
          }
        }
      }
      if (balancerTag == null) {
        return config;
      }
      final rules = (routing['rules'] as List? ?? []).toList();
      final existingTags = <String>{
        for (final rule in rules)
          if (rule is Map)
            for (final tag in (rule['inboundTag'] as List? ?? const []))
              if (tag is String) tag,
      };
      final tags = <String>{
        'socks',
        'http',
        'socks-auth',
        // The native plugin injects its own local SOCKS/HTTP inbounds when its
        // fixed ports are free. Those are tagged `socks`/`http`, or
        // `socks_1`/`http_1` (and up) when the imported config already uses the
        // base tags. tun2socks always feeds the plugin-provided inbound, so the
        // generated tags need balancer rules too.
        for (var i = 1; i <= 5; i++) 'socks_$i',
        for (var i = 1; i <= 5; i++) 'http_$i',
      };
      final inbounds = map['inbounds'];
      if (inbounds is List) {
        for (final inbound in inbounds) {
          if (inbound is Map) {
            final protocol = inbound['protocol'];
            if (protocol == 'socks' || protocol == 'http') {
              final tag = inbound['tag'];
              if (tag is String && tag.isNotEmpty) {
                tags.add(tag);
              }
            }
          }
        }
      }
      for (final tag in tags) {
        if (existingTags.contains(tag)) {
          continue;
        }
        rules.add({
          'type': 'field',
          'inboundTag': [tag],
          'balancerTag': balancerTag,
        });
      }
      routing['rules'] = rules;
      return jsonEncode(map);
    } catch (_) {
      return config;
    }
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
