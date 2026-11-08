import 'package:flutter/widgets.dart';

/// Lays [child] out at [minWidth] and scrolls it sideways when there is
/// less room than that (a tablet or a phone); otherwise it fills the
/// width as usual. For tables: their columns keep their size, no cell is
/// clipped, and the page itself never scrolls sideways.
class ScrollWhenNarrow extends StatelessWidget {
  const ScrollWhenNarrow({
    required this.minWidth,
    required this.child,
    super.key,
  });

  final double minWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (!constraints.hasBoundedWidth || constraints.maxWidth >= minWidth) {
        return child;
      }
      // The platform's scroll behaviour draws the scrollbar on the web.
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(width: minWidth, child: child),
      );
    },
  );
}
