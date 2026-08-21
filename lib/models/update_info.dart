class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.apkUrl,
    this.tagName,
    this.changelog,
    this.publishedAt,
    this.size,
    this.sha256,
    this.assetKey,
    this.requiresManualReinstall = false,
  });

  final String version;
  final String apkUrl;
  final String? tagName;
  final String? changelog;
  final DateTime? publishedAt;
  final int? size;

  /// SHA-256 of the APK, from the release manifest. The downloaded file must
  /// match before it is handed to the installer.
  final String? sha256;

  /// Which asset was picked from the manifest: an ABI key (arm64-v8a,
  /// armeabi-v7a, x86_64, x86) or "universal" as the fallback.
  final String? assetKey;

  /// True when the manifest's `min_supported_version` is newer than the
  /// running client. This happens after a breaking protocol/channel change
  /// (e.g. moving off GitHub Releases): older clients can no longer
  /// auto-update and must reinstall manually.
  final bool requiresManualReinstall;
}

