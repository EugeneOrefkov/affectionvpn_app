import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../utils/linux_window_bridge.dart';

class LinuxTitleBar extends StatelessWidget {
  const LinuxTitleBar({
    super.key,
    this.height = 36,
    this.showBrand = true,
  });

  final double height;
  final bool showBrand;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isLinux) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: height,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.borderSoft, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: height,
                child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: showBrand
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.asset(
                                  'assets/app_icon.png',
                                  width: 22,
                                  height: 22,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Affection VPN',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          )
                        : const SizedBox.shrink(),
                ),
              ),
            ),
            _WindowButton(
              icon: Icons.remove,
              onPressed: _minimize,
            ),
            _WindowButton(
              icon: Icons.close,
              onPressed: () => LinuxWindowBridge.close(),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  static void _minimize() {
    if (!Platform.isLinux) {
      return;
    }
    const channel = MethodChannel('dev.affection.affection_vpn/window');
    channel.invokeMethod<void>('minimizeWindow').catchError((_) {
    });
  }
}

class _WindowButton extends StatefulWidget {
  const _WindowButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          color: _hovered
              ? AppColors.surfaceAlt.withValues(alpha: 0.6)
              : Colors.transparent,
          child: Icon(
            widget.icon,
            size: 14,
            color: _hovered ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
