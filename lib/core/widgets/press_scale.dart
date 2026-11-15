import 'package:flutter/material.dart';

/// Shrinks its child a little while a finger is on it (§38), so the
/// phone's buttons and tiles answer the touch at once, before the ripple
/// has spread. A listener, not a gesture: the button underneath still
/// gets its tap. Nothing moves under reduced motion.
class PressScale extends StatefulWidget {
  const PressScale({required this.child, this.scale = 0.97, super.key});

  final Widget child;

  /// How small it gets while pressed.
  final double scale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down && mounted) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down && !reduced ? widget.scale : 1,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
