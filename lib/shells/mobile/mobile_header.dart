import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';

/// A red bubble with a number: the bell's unread count.
class _CountBubble extends StatelessWidget {
  const _CountBubble({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 16),
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
    decoration: BoxDecoration(
      color: AppColors.notificationBadge,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      count > 99 ? '99+' : '$count',
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
    ),
  );
}

/// The mobile app's header: the GSUhub mark, the bell, and the gold rule
/// beneath (Figma `165:137`, top 77px). The faculty and staff app (3.A)
/// and the personnel app (Objective 5, Figure 24) draw the same one.
class MobileHeader extends StatelessWidget {
  const MobileHeader({
    required this.alertsPath,
    super.key,
    this.unreadCount = 0,
  });

  /// The header's height in the design, rule excluded.
  static const double height = 76;

  /// Where the bell leads: the app's notifications.
  final String alertsPath;

  /// Unread notifications, as a number on the bell (2026-11-26; until
  /// then a red dot, as the personnel dashboard draws it, Figure 24). The
  /// bell opens the whole list.
  final int unreadCount;

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
                    message: unreadCount > 0
                        ? 'Notifications, $unreadCount unread'
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
                          if (unreadCount > 0)
                            Positioned(
                              top: -7,
                              right: -11,
                              child: _CountBubble(count: unreadCount),
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
