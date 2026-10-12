import 'package:flutter/material.dart';

import '../../core/routing/route_paths.dart';
import '../mobile/mobile_header.dart';

/// The faculty and staff app's header: the GSUhub mark, the bell, and the
/// gold rule beneath (Figma `165:137`, top 77px). Since Objective 5 the
/// personnel app draws the same [MobileHeader]; this one's bell opens the
/// faculty Alerts tab (3.B).
class RequestorHeader extends StatelessWidget {
  const RequestorHeader({super.key});

  /// The header's height in the design, rule excluded.
  static const double height = MobileHeader.height;

  @override
  Widget build(BuildContext context) =>
      const MobileHeader(alertsPath: RoutePaths.staffAlerts);
}
