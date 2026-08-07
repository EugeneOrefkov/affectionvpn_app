import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

const double _kWindowTitleBarHeight = 38;

/// Initializes the desktop window (currently Linux) using window_manager.
///
/// Call this before [runApp] on desktop platforms.
Future<void> initializeAppWindow() async {
  if (!Platform.isLinux) return;

  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(1024, 700),
    minimumSize: Size(380, 600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}

/// Wraps the app content with resize handles and a custom title bar on Linux.
class WindowFrame extends StatelessWidget {
  const WindowFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isLinux) return child;

    return Column(
      children: [
        const WindowTitleBar(),
        Expanded(child: child),
      ],
    );
  }
}

/// Draggable, custom title bar for a frameless Linux window.
class WindowTitleBar extends StatefulWidget {
  const WindowTitleBar({super.key});

  @override
  State<WindowTitleBar> createState() => _WindowTitleBarState();
}

class _WindowTitleBarState extends State<WindowTitleBar> with WindowListener {
  final ValueNotifier<bool> _isMaximized = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _syncMaximized();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _isMaximized.dispose();
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    _isMaximized.value = true;
  }

  @override
  void onWindowUnmaximize() {
    _isMaximized.value = false;
  }

  @override
  void onWindowResize() {
    _syncMaximized();
  }

  Future<void> _syncMaximized() async {
    _isMaximized.value = await windowManager.isMaximized();
  }

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: _kWindowTitleBarHeight,
      child: Material(
        color: colorScheme.surface,
        child: Stack(
          children: [
            // Draggable area. The DragToResizeArea above handles resize
            // edges, so only a drag region is needed here.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (_) => windowManager.startDragging(),
                onDoubleTap: _toggleMaximize,
              ),
            ),
            // Visible content.
            Row(
              children: [
                const SizedBox(width: 12),
                Image.asset(
                  'assets/app_icon.png',
                  width: 20,
                  height: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  'Affection VPN',
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.9),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                _WindowButton(
                  icon: Icons.remove,
                  onPressed: windowManager.minimize,
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: _isMaximized,
                  builder: (_, maximized, _) => _WindowButton(
                    icon: maximized ? Icons.filter_none : Icons.crop_square,
                    onPressed: _toggleMaximize,
                  ),
                ),
                _WindowButton(
                  icon: Icons.close,
                  onPressed: () => windowManager.hide(),
                  hoverColor: const Color.fromARGB(255, 238, 44, 60),
                  hoverIconColor: Colors.white,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.icon,
    required this.onPressed,
    this.hoverColor,
    this.hoverIconColor,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final Color? hoverColor;
  final Color? hoverIconColor;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final defaultHoverColor = colorScheme.onSurface.withValues(alpha: 0.08);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 46,
          height: _kWindowTitleBarHeight,
          color: _hovered ? (widget.hoverColor ?? defaultHoverColor) : Colors.transparent,
          child: Center(
            child: Icon(
              widget.icon,
              size: 18,
              color: _hovered && widget.hoverIconColor != null
                  ? widget.hoverIconColor
                  : colorScheme.onSurface.withValues(alpha: 0.85),
            ),
          ),
        ),
      ),
    );
  }
}
