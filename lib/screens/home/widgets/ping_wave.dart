import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Sonar-style ripple animation shown while a measurement is in progress
/// (server ping, IP lookup, speed test).
class PingWave extends StatefulWidget {
  const PingWave({
    super.key,
    this.size = 34,
    this.color = AppColors.primary,
    this.strokeWidth = 2.4,
  });

  final double size;
  final Color color;
  final double strokeWidth;

  @override
  State<PingWave> createState() => _PingWaveState();
}

class _PingWaveState extends State<PingWave> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _PingWavePainter(
              _controller.value,
              widget.color,
              widget.strokeWidth,
            ),
          ),
        );
      },
    );
  }
}

class _PingWavePainter extends CustomPainter {
  const _PingWavePainter(this.progress, this.color, this.strokeWidth);

  final double progress;
  final Color color;
  final double strokeWidth;

  static const _waveCount = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final dot = Paint()..color = color;
    for (var i = 0; i < _waveCount; i++) {
      final p = (progress + i / _waveCount) % 1.0;
      ring.color = color.withValues(alpha: (1 - p) * 0.6);
      canvas.drawCircle(center, 3 + p * (maxRadius - 3), ring);
    }
    canvas.drawCircle(center, 3.2, dot);
  }

  @override
  bool shouldRepaint(covariant _PingWavePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}
