import 'package:flutter/material.dart';

import '../../core/routing/route_paths.dart';
import '../mobile/mobile_header.dart';

/// The faculty and staff app's header: the GSUhub mark, the help button,
/// and the gold rule beneath (Figma `165:137`, top 77px). Since Objective
/// 5 the personnel app draws the same [MobileHeader], with its bell.
///
/// **Help in place of the bell (2026-11-26):** the notifications are a tab
/// of the bar again, so the header's corner opens Help.
class RequestorHeader extends StatelessWidget {
  const RequestorHeader({super.key});

  /// The header's height in the design, rule excluded.
  static const double height = MobileHeader.height;

  @override
  Widget build(BuildContext context) =>
      const MobileHeader.help(helpPath: RoutePaths.staffHelp);
}
