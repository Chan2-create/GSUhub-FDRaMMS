import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/firestore_paths.dart';
import '../../../core/enums/notification_type.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/utils/relative_time.dart';
import '../../../core/utils/result.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../shells/requestor/requestor_shell.dart';
import '../../../shells/requestor/requestor_title_row.dart';
import '../data/models/app_notification.dart';
import 'notification_providers.dart';

/// The Alerts tab: the requestor's notifications, live, grouped Today and
/// Earlier (Figma `169:1459`, Objective 3.B). Replaces 3.A's placeholder.
///
/// Unread notices are pale gold with a gold edge, read ones white, as
/// drawn. Tapping one marks it read and opens its report. Not in the
/// design, and flagged: "Mark all as read", the empty state, and the
/// prompt to allow notifications on the phone — which this list never
/// depends on, since it reads Firestore, not the push.
class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  // Coming back from the phone's settings may have changed the permission.
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onResume: () => ref.read(pushPermissionProvider.notifier).refresh(),
  );

  @override
  void initState() {
    super.initState();
    _lifecycle;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _markAllRead() async {
    final result = await ref.read(notificationActionsProvider).markAllRead();
    if (!mounted) return;
    if (result case Error(:final failure)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifications = ref.watch(myNotificationsProvider);
    final hasUnread = notifications.value?.fold(
      (list) => list.any((notice) => !notice.isRead),
      (_) => false,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RequestorTitleRow(
          title: 'Notifications',
          onBack: () => context.go(RoutePaths.staffHome),
          trailing: hasUnread ?? false
              ? TextButton(
                  onPressed: _markAllRead,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.trackingAccentText,
                    minimumSize: const Size(48, 48),
                  ),
                  child: const Text('Mark all as read'),
                )
              : null,
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              requestorBottomInset(context),
            ),
            children: [
              const _PermissionPrompt(),
              AsyncValueView<List<AppNotification>>(
                value: notifications,
                isEmpty: (list) => list.isEmpty,
                emptyIcon: Icons.notifications_none,
                emptyMessage:
                    'No notifications yet. You will be told here when a '
                    'report you filed moves along.',
                onRetry: () => ref.invalidate(myNotificationsProvider),
                data: (list) => _Grouped(notifications: list),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Today first, then Earlier, each newest first.
class _Grouped extends StatelessWidget {
  const _Grouped({required this.notifications});

  final List<AppNotification> notifications;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todays = <AppNotification>[];
    final earlier = <AppNotification>[];
    for (final notice in notifications) {
      (notice.createdAt.toLocal().isBefore(today) ? earlier : todays).add(
        notice,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (todays.isNotEmpty) ..._section('Today', todays),
        if (earlier.isNotEmpty) ..._section('Earlier', earlier),
      ],
    );
  }

  static List<Widget> _section(String title, List<AppNotification> notices) => [
    Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 12),
      child: Text(title, style: AppTextStyles.alertsSection),
    ),
    for (final notice in notices)
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _AlertCard(notice: notice),
      ),
  ];
}

class _AlertCard extends ConsumerWidget {
  const _AlertCard({required this.notice});

  final AppNotification notice;

  (IconData, Color) get _icon {
    final unread = !notice.isRead;
    return switch (notice.type) {
      NotificationType.maintenanceCompleted => (
        Icons.check_circle_outline,
        AppColors.alertCompleted,
      ),
      NotificationType.workOrderAssigned || NotificationType.taskAssigned => (
        Icons.person_outline,
        unread ? AppColors.linkIndigo : AppColors.warmMuted,
      ),
      NotificationType.reportAcknowledged ||
      NotificationType.statusUpdate ||
      NotificationType.lowStockAlert => (
        Icons.notifications_none,
        unread ? AppColors.trackingAccentText : AppColors.warmMuted,
      ),
    };
  }

  void _open(BuildContext context, WidgetRef ref) {
    if (!notice.isRead) {
      ref.read(notificationActionsProvider).markRead(notice.id);
    }
    final reportId = notice.relatedEntityId;
    if (notice.relatedEntityType == FirestorePaths.damageReports &&
        reportId != null) {
      context.push(RoutePaths.staffReportDetailFor(reportId));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = !notice.isRead;
    final (icon, color) = _icon;
    final when = RelativeTime.ago(notice.createdAt);

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notice.body,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: unread
                      ? AppTextStyles.alertsUnread
                      : AppTextStyles.alertsRead,
                ),
                const SizedBox(height: 4),
                Text(when, style: AppTextStyles.alertsTime),
              ],
            ),
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      label:
          '${unread ? 'Unread. ' : ''}${notice.title}. ${notice.body}. $when',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Material(
            color: unread ? AppColors.trackingNoteFill : Colors.white,
            child: InkWell(
              onTap: () => _open(context, ref),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: unread
                      ? const Border(
                          left: BorderSide(
                            color: AppColors.accentGold,
                            width: 4,
                          ),
                        )
                      : null,
                ),
                child: Padding(
                  padding: EdgeInsets.only(left: unread ? 0 : 4),
                  child: content,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for notification permission when the phone has not given it, and
/// says the list here still works either way (conflict 4 of the 3.B brief:
/// a refusal must not break in-app notifications). Not in the design.
class _PermissionPrompt extends ConsumerWidget {
  const _PermissionPrompt();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The faculty app ships on Android. In a browser it is a development
    // view with web push off (no VAPID key), so there is nothing to allow.
    if (kIsWeb) return const SizedBox.shrink();
    final permission = ref.watch(pushPermissionProvider).value;
    if (permission == null || permission == PushPermission.granted) {
      return const SizedBox.shrink();
    }
    final controller = ref.read(pushPermissionProvider.notifier);
    final forGood = permission == PushPermission.permanentlyDenied;

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.trackingRail),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.notifications_off_outlined,
                    size: 22,
                    color: AppColors.warmMuted,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      forGood
                          ? 'Notifications are turned off for GSUhub in your '
                                "phone's settings. Updates still appear here."
                          : 'Allow notifications to hear when your reports '
                                'move, even with GSUhub in the background. '
                                'Updates appear here either way.',
                      style: AppTextStyles.alertsRead,
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: forGood
                      ? controller.openSettings
                      : controller.request,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.trackingAccentText,
                    minimumSize: const Size(48, 48),
                  ),
                  child: Text(forGood ? 'Open settings' : 'Allow'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
