import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/constants/app_colors.dart';

/// The faculty and staff app's header: the GSUhub mark, the bell, and the
/// gold rule beneath (Figma `165:137`, top 77px).
///
/// Its own widget rather than part of one screen because every requestor
/// frame in the file carries the same header; 3.C builds the first of
/// them.
class RequestorHeader extends StatelessWidget {
  const RequestorHeader({super.key});

  /// The header's height in the design, rule excluded.
  static const double height = 76;

  @override
  Widget build(BuildContext context) => Container(
    color: AppColors.mobilePageBackground,
    child: SafeArea(
      bottom: false,
      child: Column(
        children: [
          SizedBox(
            height: height,
            child: Stack(
              children: [
                // The exported mark carries transparent margins, which is
                // why the design places its 123px box above the top edge.
                const Positioned(
                  left: 4,
                  top: -24,
                  width: 123,
                  height: 123,
                  child: Image(
                    image: AssetImage('assets/images/gsuhub_logo.png'),
                    fit: BoxFit.cover,
                    semanticLabel: 'GSUhub',
                  ),
                ),
                Positioned(
                  top: 18,
                  right: 11,
                  child: Tooltip(
                    message: 'Notifications arrive in a later objective.',
                    child: IconButton(
                      // The notification centre is not built yet (as on the
                      // admin console's bell).
                      onPressed: null,
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                      constraints: const BoxConstraints(),
                      icon: SvgPicture.asset(
                        'assets/icons/topbar_bell.svg',
                        width: 16,
                        height: 20,
                        colorFilter: const ColorFilter.mode(
                          AppColors.mobileBell,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Line 16: a 3px gold rule.
          const SizedBox(
            height: 3,
            width: double.infinity,
            child: ColoredBox(color: AppColors.accentGold),
          ),
        ],
      ),
    ),
  );
}
