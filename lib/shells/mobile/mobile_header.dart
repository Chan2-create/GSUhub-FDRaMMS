import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';

/// The mobile app's header: the GSUhub mark, the bell, and the gold rule
/// beneath (Figma `165:137`, top 77px). The faculty and staff app (3.A)
/// and the personnel app (Objective 5, Figure 24) draw the same one.
class MobileHeader extends StatelessWidget {
  const MobileHeader({
    required this.alertsPath,
    super.key,
    this.hasUnread = false,
  });

  /// The header's height in the design, rule excluded.
  static const double height = 76;

  /// Where the bell leads: the app's notifications.
  final String alertsPath;

  /// Unread notifications: a red dot on the bell, as the personnel
  /// dashboard draws it (Figure 24).
  final bool hasUnread;

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
                    message: hasUnread
                        ? 'Notifications, some unread'
                        : 'Notifications',
                    child: IconButton(
                      onPressed: () => context.go(alertsPath),
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                      constraints: const BoxConstraints(),
                      icon: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          SvgPicture.asset(
                            'assets/icons/topbar_bell.svg',
                            width: 16,
                            height: 20,
                            colorFilter: const ColorFilter.mode(
                              AppColors.mobileBell,
                              BlendMode.srcIn,
                            ),
                          ),
                          if (hasUnread)
                            const Positioned(
                              top: -2,
                              right: -3,
                              child: SizedBox.square(
                                dimension: 8,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: AppColors.notificationBadge,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // A 3px gold rule.
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
