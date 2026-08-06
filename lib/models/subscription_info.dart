class SubscriptionInfo {
  const SubscriptionInfo({
    this.upload,
    this.download,
    this.total,
    this.expireDate,
    this.username,
    this.trafficUsedPercent,
  });

  /// Bytes uploaded since subscription start.
  final int? upload;

  /// Bytes downloaded since subscription start.
  final int? download;

  /// Total allowed traffic in bytes.
  final int? total;

  /// Subscription expiry date (unix seconds).
  final DateTime? expireDate;

  final String? username;
  final double? trafficUsedPercent;

  int get used => (upload ?? 0) + (download ?? 0);

  bool get hasTraffic => total != null && total! > 0;

  factory SubscriptionInfo.fromUserInfoHeader(String header) {
    final values = <String, int>{};
    for (final part in header.split(';')) {
      final pair = part.trim().split('=');
      if (pair.length != 2) {
        continue;
      }
      final key = pair[0].trim().toLowerCase();
      final value = int.tryParse(pair[1].trim());
      if (value != null) {
        values[key] = value;
      }
    }
    final total = values['total'];
    final used = (values['upload'] ?? 0) + (values['download'] ?? 0);
    double? usedPercent;
    if (total != null && total > 0) {
      usedPercent = (used / total * 100).clamp(0, 100);
    }
    return SubscriptionInfo(
      upload: values['upload'],
      download: values['download'],
      total: total,
      expireDate: values['expire'] != null && values['expire']! > 0
          ? DateTime.fromMillisecondsSinceEpoch(
              values['expire']! * 1000,
              isUtc: true,
            )
          : null,
      trafficUsedPercent: usedPercent,
    );
  }
}
