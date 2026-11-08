import 'package:flutter/widgets.dart';

import '../constants/breakpoints.dart';

/// A page's title block and its action: side by side, as the designs draw
/// them, or the action under the title on a phone, so the title is never
/// squeezed into breaking mid-word.
class PageHeader extends StatelessWidget {
  const PageHeader({required this.heading, required this.action, super.key});

  /// The page title and its subtitle.
  final Widget heading;

  /// The page's button, at the right of the title.
  final Widget action;

  @override
  Widget build(BuildContext context) => Breakpoints.isCompact(context)
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [heading, const SizedBox(height: 16), action],
        )
      : Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: heading),
            action,
          ],
        );
}
