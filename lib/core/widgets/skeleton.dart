import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Skeletons: the shape of what is about to appear, in grey, with a soft
/// sheen moving across it, in place of a spinner (§38). A list keeps its
/// height and its rhythm while its rows load, so nothing jumps when they
/// arrive. Drawn with the framework alone, one ticker per skeleton, and
/// still under reduced motion.
///
/// To a screen reader the whole skeleton is one thing, "Loading"; its
/// boxes say nothing.
class Skeleton extends StatefulWidget {
  const Skeleton({required this.child, super.key});

  /// A list of [count] cards, each [height] tall, [gap] apart, the usual
  /// stand-in for a list of cards.
  factory Skeleton.cards({
    int count = 3,
    double height = 96,
    double gap = 12,
    double radius = 12,
    Key? key,
  }) => Skeleton(
    key: key,
    child: Column(
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) SizedBox(height: gap),
          SkeletonBox(height: height, radius: radius),
        ],
      ],
    ),
  );

  /// A block of [lines] text lines, the last one shorter, as a paragraph
  /// or a details card loads.
  factory Skeleton.lines({int lines = 3, double gap = 10, Key? key}) =>
      Skeleton(
        key: key,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < lines; i++) ...[
              if (i > 0) SizedBox(height: gap),
              SkeletonLine(widthFactor: i == lines - 1 ? 0.6 : 1),
            ],
          ],
        ),
      );

  /// Built from [SkeletonBox]es and [SkeletonLine]s, in the layout of the
  /// real content.
  final Widget child;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sheen = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _sheen.stop();
    } else if (!_sheen.isAnimating) {
      _sheen.repeat();
    }
  }

  @override
  void dispose() {
    _sheen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading',
    liveRegion: true,
    excludeSemantics: true,
    child: AnimatedBuilder(
      animation: _sheen,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) {
          // A pale band a third of the width wide, sweeping left to right
          // and starting over; the grey shows through on either side.
          final x = _sheen.value * 2 - 0.5;
          return LinearGradient(
            begin: Alignment(x - 0.5, 0),
            end: Alignment(x + 0.5, 0),
            // Transparent *white* at the ends: fading to transparent
            // black drew a grey band either side of the sheen.
            colors: const [
              Color(0x00FFFFFF),
              Color(0xB3FFFFFF),
              Color(0x00FFFFFF),
            ],
          ).createShader(bounds);
        },
        child: child,
      ),
    ),
  );
}

/// A grey block the size of the card, photo or control to come.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    required this.height,
    this.width = double.infinity,
    this.radius = 8,
    super.key,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(radius),
      ),
    ),
  );
}

/// A grey bar the height of a line of text, [widthFactor] of the width.
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({this.widthFactor = 1, this.height = 12, super.key});

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    alignment: Alignment.centerLeft,
    widthFactor: widthFactor,
    child: SkeletonBox(height: height, radius: height / 2),
  );
}
