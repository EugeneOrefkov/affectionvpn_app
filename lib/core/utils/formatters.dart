class Formatters {
  Formatters._();

  static String bytes(int bytes) {
    if (bytes < 0) {
      bytes = 0;
    }
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    if (unit == 0) {
      return '${value.round()} ${units[unit]}';
    }
    return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unit]}';
  }

  static String speed(int bytesPerSecond) {
    if (bytesPerSecond <= 0) {
      return '0 B/s';
    }
    return '${bytes(bytesPerSecond)}/s';
  }

  static String duration(int seconds) {
    if (seconds < 0) {
      seconds = 0;
    }
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    if (h > 0) {
      return '${two(h)}:${two(m)}:${two(s)}';
    }
    return '${two(m)}:${two(s)}';
  }

  static String percent(int used, int total) {
    if (total <= 0) {
      return '—';
    }
    final p = (used / total * 100).clamp(0, 100);
    return '${p.round()}%';
  }
}
