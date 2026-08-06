import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../state/app_state.dart';

class PowerButton extends StatefulWidget {
  const PowerButton({super.key, required this.size});

  final double size;

  @override
  State<PowerButton> createState() => _PowerButtonState();
}

class _PowerButtonState extends State<PowerButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = context.watch<AppState>().connectionStatus;

    final connected = status == ConnectionStatus.connected;
    final busy =
        status == ConnectionStatus.connecting ||
            status == ConnectionStatus.disconnecting;

    if (connected && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!connected && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final scale = connected ? 1.0 + _pulse.value * 0.03 : 1.0;
        final glow = connected
            ? AppColors.glowGreen
            : AppColors.glowPrimary;

        return GestureDetector(
          onTap: context.read<AppState>().toggleConnection,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: AnimatedScale(
              scale: scale,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutBack,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 600),
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: connected
                            ? AppColors.success.withValues(alpha: 0.35)
                            : AppColors.primary.withValues(alpha: 0.35),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: glow,
                          blurRadius: connected ? 70 : 46,
                          spreadRadius: connected ? 8 : 2,
                        ),
                      ],
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 600),
                    width: widget.size * 0.74,
                    height: widget.size * 0.74,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: connected
                          ? AppColors.gradientSuccess
                          : AppColors.gradient,
                      boxShadow: [
                        BoxShadow(
                          color: connected ? AppColors.glowGreen : AppColors.glowPrimary,
                          blurRadius: 40,
                          spreadRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  if (busy)
                    SizedBox(
                      width: widget.size * 0.9,
                      height: widget.size * 0.9,
                      child: const CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white70,
                      ),
                    )
                  else
                    Icon(
                      Icons.power_settings_new,
                      color: Colors.white,
                      size: widget.size * 0.28,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
