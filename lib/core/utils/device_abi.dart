import 'package:device_info_plus/device_info_plus.dart';

/// Primary device ABI key used to pick the matching build (split APK asset,
/// Xray-core bundle, ...). Falls back to "universal" when detection fails.
Future<String> deviceAbiKey() async {
  try {
    final abis = (await DeviceInfoPlugin().androidInfo).supportedAbis;
    if (abis.isNotEmpty) {
      final first = abis.first.toLowerCase();
      if (first.startsWith('arm64')) {
        return 'arm64-v8a';
      }
      if (first.startsWith('arm')) {
        return 'armeabi-v7a';
      }
      if (first.startsWith('x86_64')) {
        return 'x86_64';
      }
      if (first.startsWith('x86')) {
        return 'x86';
      }
    }
  } catch (_) {
    // Detection failed; callers fall back to a universal build.
  }
  return 'universal';
}
