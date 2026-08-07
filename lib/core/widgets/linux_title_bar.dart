import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../utils/linux_window_bridge.dart';

/// Custom sliver of the OS window. Used instead of the GTK title bar so the
/// branding matches the in-app home page top-left rather than a bulky system
/// header. On non-Linux platforms it falls back to an empty box (Android
/// already shows its own status bar, etc.).
///
/// Drag area: left/center strip fires [LinuxWindowBridge.drag] on pointer
/// down, which hands off to `gtk_window_begin_move_drag` natively.
/// Right cluster: minimize + close buttons, both wired through the same
/// MethodChannel bridge.
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
    // Skip on every non-Linux target so Android/iOS/Windows live render
    // unchanged (they have their own decorations or status bar handled by
    // SafeArea).
    if (!Platform.isLinux) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: height,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.background,
          border: const Border(
            bottom: BorderSide(color: AppColors.borderSoft, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              // Drag handle: native begin_move_drag on the *first* pointer
              // down so the WM performs the actual move (correct aero-snap,
              // correct edge resistance). The Listener ignores children so
              // the underlying padding area keeps working as a drag region
              // even when the brand text takes the full width on narrow
              // windows.
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => LinuxWindowBridge.drag(),
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
      // Optional; ignored if the native side does not implement it (older
      // builds kept before the channel was extended).
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
