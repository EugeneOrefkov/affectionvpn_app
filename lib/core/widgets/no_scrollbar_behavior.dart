import 'package:flutter/material.dart';

/// Desktop scroll behavior that keeps wheel scrolling but does not render
/// the default right-edge scrollbar.
class NoScrollbarScrollBehavior extends MaterialScrollBehavior {
  const NoScrollbarScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
