class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.apkUrl,
    this.tagName,
    this.changelog,
    this.publishedAt,
    this.size,
  });

  final String version;
  final String apkUrl;
  final String? tagName;
  final String? changelog;
  final DateTime? publishedAt;
  final int? size;
}
