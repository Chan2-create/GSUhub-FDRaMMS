import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/firestore_paths.dart';
import '../../../core/enums/notification_type.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/utils/relative_time.dart';
import '../../../core/utils/result.dart';
import '../../../core/widgets/priority_chip.dart';
import '../../reporting/data/models/damage_report.dart';
import '../../reporting/presentation/report_providers.dart';
import '../data/models/app_notification.dart';
import 'notification_providers.dart';

/// Which notices the filter bar shows (Figma `202:5653`).
enum AdminNoticeFilter {
  all('All'),
  unread('Unread'),
  reports('Reports'),
  system('System');

  const AdminNoticeFilter(this.label);

  final String label;
}

/// The console's notification centre (Objective 7.A, Figma `202:5608`).
///
/// The administrator's own notices (supabase/migrations/
/// *_admin_notifications.sql): a report filed, work started, work ready
/// for sign-off, materials requested, a sign-up waiting, a material at its
/// minimum. Newest first, live; a notice opens what it is about and is
/// marked read. "Reports" are the notices about reports and work orders,
/// "System" the rest: stock, requests and accounts.
class AdminNotificationsScreen extends ConsumerStatefulWidget {
  const AdminNotificationsScreen({super.key});

  /// How many notices a page adds.
  static const int pageSize = 50;

  @override
  ConsumerState<AdminNotificationsScreen> createState() =>
      _AdminNotificationsScreenState();
}

class _AdminNotificationsScreenState
    extends ConsumerState<AdminNotificationsScreen> {
  AdminNoticeFilter _filter = AdminNoticeFilter.all;
  DateTimeRange? _range;
  int _limit = AdminNotificationsScreen.pageSize;

  static final DateFormat _day = DateFormat('MMM d, y');

  bool _passes(AppNotification notice) {
    final shown = switch (_filter) {
      AdminNoticeFilter.all => true,
      AdminNoticeFilter.unread => !notice.isRead,
      AdminNoticeFilter.reports => _isAboutReports(notice),
      AdminNoticeFilter.system => !_isAboutReports(notice),
    };
    if (!shown) return false;
    final range = _range;
    if (range == null) return true;
    final created = notice.createdAt.toLocal();
    final from = DateTime(range.start.year, range.start.month, range.start.day);
    final to = DateTime(range.end.year, range.end.month, range.end.day + 1);
    return !created.isBefore(from) && created.isBefore(to);
  }

  static bool _isAboutReports(AppNotification notice) =>
      notice.relatedEntityType == FirestorePaths.damageReports ||
      notice.relatedEntityType == FirestorePaths.workOrders;

  Future<void> _pickRange() async {
    final now = clock.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: _range,
      helpText: 'Show notifications from',
    );
    if (picked != null && mounted) setState(() => _range = picked);
  }

  Future<void> _markAllRead() async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(notificationActionsProvider).markAllRead();
    if (result case Error(:final failure)) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(failure.message),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final notices = ref.watch(adminNotificationsProvider(_limit));
    final reports = switch (ref.watch(reportsStreamProvider)) {
      AsyncData(value: Success(:final value)) => {
        for (final report in value) report.id: report,
      },
      _ => const <String, DamageReport>{},
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Figma 202:5643.
          Padding(
            padding: const EdgeInsets.only(bottom: 40),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Notifications', style: AppTextStyles.pageTitle),
                      SizedBox(height: 4),
                      Text(
                        'System-wide notification logs and alerts',
                        style: AppTextStyles.pageSubtitle,
                      ),
                    ],
                  ),
                ),
                _MarkAllReadButton(onPressed: _markAllRead),
              ],
            ),
          ),
          _FilterBar(
            filter: _filter,
            onFilter: (filter) => setState(() => _filter = filter),
            rangeLabel: switch (_range) {
              null => 'All dates',
              final range =>
                '${_day.format(range.start)} - ${_day.format(range.end)}',
            },
            hasRange: _range != null,
            onPickRange: _pickRange,
            onClearRange: () => setState(() => _range = null),
          ),
          const SizedBox(height: 24),
          switch (notices) {
            AsyncData(value: Success(:final value)) => _List(
              notices: value.where(_passes).toList(growable: false),
              reports: reports,
              emptyMessage: value.isEmpty
                  ? 'No notifications yet. You will be told here when a '
                        'report is filed, work starts or waits for sign-off, '
                        'materials are requested, stock runs low, or someone '
                        'signs up.'
                  : 'No notifications match this filter.',
              canLoadOlder: value.length >= _limit,
              onLoadOlder: () =>
                  setState(() => _limit += AdminNotificationsScreen.pageSize),
            ),
            AsyncData(value: Error(:final failure)) => _Message(
              'The notifications could not be loaded. ${failure.message}',
            ),
            AsyncError(:final error) => _Message(
              'The notifications could not be loaded. $error',
            ),
            _ => const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            ),
          },
        ],
      ),
    );
  }
}

/// "Mark All as Read" (Figma `202:5649`).
class _MarkAllReadButton extends StatelessWidget {
  const _MarkAllReadButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      side: const BorderSide(color: AppColors.primary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.asset('assets/icons/notification_mark_all_read.svg'),
        const SizedBox(width: 8),
        const Text('Mark All as Read', style: AppTextStyles.notificationAction),
      ],
    ),
  );
}

/// The pills and the date range (Figma `202:5653`).
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filter,
    required this.onFilter,
    required this.rangeLabel,
    required this.hasRange,
    required this.onPickRange,
    required this.onClearRange,
  });

  final AdminNoticeFilter filter;
  final ValueChanged<AdminNoticeFilter> onFilter;
  final String rangeLabel;
  final bool hasRange;
  final VoidCallback onPickRange;
  final VoidCallback onClearRange;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      border: Border.all(color: AppColors.borderStrong),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 12,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in AdminNoticeFilter.values)
              _Pill(
                label: option.label,
                selected: option == filter,
                onTap: () => onFilter(option),
              ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'FILTER BY DATE',
              style: AppTextStyles.notificationFilterLabel,
            ),
            const SizedBox(width: 12),
            Material(
              color: AppColors.surfaceMuted,
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: AppColors.borderStrong),
                borderRadius: BorderRadius.circular(4),
              ),
              child: InkWell(
                onTap: onPickRange,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SvgPicture.asset(
                        'assets/icons/notification_calendar.svg',
                      ),
                      const SizedBox(width: 8),
                      Text(
                        rangeLabel,
                        style: AppTextStyles.notificationDateRange,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (hasRange)
              IconButton(
                tooltip: 'Show all dates',
                onPressed: onClearRange,
                icon: const Icon(Icons.close, size: 16),
                color: AppColors.iconMuted,
              ),
          ],
        ),
      ],
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: selected ? AppColors.primary : AppColors.statusNeutralBackground,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Text(
            label,
            style: AppTextStyles.notificationFilter.copyWith(
              color: selected
                  ? AppColors.surface
                  : AppColors.statusNeutralForeground,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    ),
  );
}

/// The notices, and "View Older Notifications" (Figma `202:5670`,
/// `202:5739`).
class _List extends StatelessWidget {
  const _List({
    required this.notices,
    required this.reports,
    required this.emptyMessage,
    required this.canLoadOlder,
    required this.onLoadOlder,
  });

  final List<AppNotification> notices;
  final Map<String, DamageReport> reports;
  final String emptyMessage;
  final bool canLoadOlder;
  final VoidCallback onLoadOlder;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (notices.isEmpty)
        _Message(emptyMessage)
      else
        for (final notice in notices) ...[
          _NoticeRow(
            notice: notice,
            report: notice.relatedEntityType == FirestorePaths.damageReports
                ? reports[notice.relatedEntityId]
                : null,
          ),
          const SizedBox(height: 16),
        ],
      if (canLoadOlder)
        Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0D000000),
                    offset: Offset(0, 1),
                    blurRadius: 1,
                  ),
                ],
              ),
              child: OutlinedButton(
                onPressed: onLoadOlder,
                style: OutlinedButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  side: const BorderSide(color: AppColors.borderStrong),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
                child: const Text(
                  'View Older Notifications',
                  style: AppTextStyles.notificationOlder,
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: AppColors.surface,
      border: Border.all(color: AppColors.borderStrong),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(text, style: AppTextStyles.pageSubtitle),
  );
}

/// One notice (Figma `202:5671` unread, `202:5686` read).
class _NoticeRow extends ConsumerWidget {
  const _NoticeRow({required this.notice, required this.report});

  final AppNotification notice;

  /// The report a report's notice is about, when the console has it: its
  /// priority goes on the notice while it is unread.
  final DamageReport? report;

  /// The tile's icon and colour (DERIVED from the six kinds the design
  /// draws): a bell for a report, green for work, blue for a request,
  /// orange for an account, red for stock.
  (String, Color, Color?) get _tile {
    final unread = !notice.isRead;
    return switch (notice.type) {
      NotificationType.workStarted => (
        'assets/icons/notification_tools.svg',
        AppColors.notificationTileGreen,
        null,
      ),
      NotificationType.reviewRequested ||
      NotificationType.maintenanceCompleted => (
        'assets/icons/notification_check.svg',
        AppColors.notificationTileGreen,
        null,
      ),
      NotificationType.materialsRequested => (
        'assets/icons/notification_message.svg',
        AppColors.notificationTileBlue,
        null,
      ),
      NotificationType.accountRequested => (
        'assets/icons/notification_person_add.svg',
        AppColors.notificationTileOrange,
        null,
      ),
      NotificationType.lowStockAlert => (
        'assets/icons/notification_warning.svg',
        AppColors.notificationTileRed,
        null,
      ),
      NotificationType.reportSubmitted ||
      NotificationType.reportAcknowledged ||
      NotificationType.workOrderAssigned ||
      NotificationType.taskAssigned ||
      NotificationType.statusUpdate => (
        'assets/icons/notification_bell.svg',
        unread ? AppColors.notificationAccent : AppColors.notificationTileBlue,
        unread ? null : AppColors.notificationAccent,
      ),
    };
  }

  void _open(BuildContext context, WidgetRef ref) {
    if (!notice.isRead) {
      ref.read(notificationActionsProvider).markRead(notice.id);
    }
    final id = notice.relatedEntityId;
    final router = GoRouter.of(context);
    switch (notice.relatedEntityType) {
      case FirestorePaths.damageReports when id != null:
        router.go(RoutePaths.adminReportDetailFor(id));
      case FirestorePaths.workOrders when id != null:
        router.go(RoutePaths.adminWorkOrderDetailFor(id));
      case FirestorePaths.materialRequests || FirestorePaths.inventoryItems:
        router.go(RoutePaths.adminInventory);
      case FirestorePaths.users:
        router.go(RoutePaths.adminUsers);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = !notice.isRead;
    final (icon, tileColor, iconColor) = _tile;
    final level = report?.effectivePriority;

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: tileColor,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: SvgPicture.asset(
            icon,
            colorFilter: iconColor == null
                ? null
                : ColorFilter.mode(iconColor, BlendMode.srcIn),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      notice.title,
                      style: AppTextStyles.notificationTitle.copyWith(
                        color: unread
                            ? AppColors.primary
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    RelativeTime.ago(notice.createdAt, now: clock.now()),
                    style: AppTextStyles.notificationTime.copyWith(
                      color: unread
                          ? AppColors.notificationBody
                          : AppColors.textFaint,
                      fontWeight: unread ? FontWeight.w500 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text.rich(_body(unread)),
              if (unread)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (level != null)
                        _Tag(
                          '${level.label} PRIORITY',
                          background: PriorityChip.paletteFor(level).$1,
                          foreground: PriorityChip.paletteFor(level).$2,
                        ),
                      const _Tag(
                        'UNREAD',
                        background: AppColors.surface,
                        foreground: AppColors.notificationBody,
                        bordered: true,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    final radius = BorderRadius.circular(8);
    return Semantics(
      button: true,
      label: unread ? 'Unread: ${notice.title}' : notice.title,
      child: unread
          ? DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0D000000),
                    offset: Offset(0, 1),
                    blurRadius: 1,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: Material(
                  color: AppColors.notificationUnreadFill,
                  child: InkWell(
                    onTap: () => _open(context, ref),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            width: 4,
                            color: AppColors.notificationAccent,
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                20,
                                20,
                                20,
                              ),
                              child: content,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            )
          : Material(
              color: AppColors.surface,
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: AppColors.borderStrong),
                borderRadius: radius,
              ),
              child: InkWell(
                onTap: () => _open(context, ref),
                borderRadius: radius,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: content,
                ),
              ),
            ),
    );
  }

  /// The words, with the record number ("#DR-ABC123", "#W-1") in bold.
  TextSpan _body(bool unread) {
    final base = AppTextStyles.notificationBody.copyWith(
      color: unread ? AppColors.notificationBody : AppColors.textMuted,
    );
    final number = base.copyWith(
      fontWeight: FontWeight.w700,
      color: unread ? AppColors.notificationAccent : AppColors.textMuted,
    );
    final spans = <TextSpan>[];
    var at = 0;
    for (final match in _recordNumber.allMatches(notice.body)) {
      if (match.start > at) {
        spans.add(TextSpan(text: notice.body.substring(at, match.start)));
      }
      spans.add(TextSpan(text: match.group(0), style: number));
      at = match.end;
    }
    if (at < notice.body.length) {
      spans.add(TextSpan(text: notice.body.substring(at)));
    }
    return TextSpan(style: base, children: spans);
  }

  static final RegExp _recordNumber = RegExp(r'#[A-Z0-9][A-Z0-9-]*');
}

/// "HIGH PRIORITY", "UNREAD" (Figma `202:5682`, `202:5684`).
class _Tag extends StatelessWidget {
  const _Tag(
    this.text, {
    required this.background,
    required this.foreground,
    this.bordered = false,
  });

  final String text;
  final Color background;
  final Color foreground;
  final bool bordered;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: background,
      border: bordered ? Border.all(color: AppColors.borderStrong) : null,
      borderRadius: BorderRadius.circular(2),
    ),
    child: Text(
      text,
      style: AppTextStyles.notificationTag.copyWith(color: foreground),
    ),
  );
}
