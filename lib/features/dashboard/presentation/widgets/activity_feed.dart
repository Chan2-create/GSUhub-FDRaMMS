import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/enums/audit_action.dart';
import '../../../audit/data/models/audit_log_entry.dart';

/// "Recent Activity" — a vertical timeline of lifecycle events
/// (Figma node `196:622`).
class ActivityFeed extends StatelessWidget {
  const ActivityFeed({required this.entries, super.key});

  final List<AuditLogEntry> entries;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < entries.length; i++)
        _ActivityRow(
          entry: entries[i],
          // The connecting line runs between dots, so the last entry
          // does not trail one into empty space.
          showConnector: i < entries.length - 1,
        ),
    ],
  );
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry, required this.showConnector});

  final AuditLogEntry entry;
  final bool showConnector;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            const SizedBox(height: 6),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _dotColor(entry.action),
                shape: BoxShape.circle,
              ),
            ),
            if (showConnector)
              const Expanded(
                child: SizedBox(
                  width: 1,
                  child: ColoredBox(color: AppColors.border),
                ),
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: showConnector ? 24 : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_title(entry.action), style: AppTextStyles.activityTitle),
                const SizedBox(height: 2),
                Text(entry.description, style: AppTextStyles.activityBody),
                const SizedBox(height: 4),
                Text(
                  _relativeTime(entry.timestamp).toUpperCase(),
                  style: AppTextStyles.captionUpper,
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  static Color _dotColor(AuditAction action) => switch (action) {
    AuditAction.created => AppColors.activityInfo,
    AuditAction.statusChanged => AppColors.activityPositive,
    AuditAction.assigned => AppColors.activityInfo,
    AuditAction.merged ||
    AuditAction.updated ||
    AuditAction.deleted => AppColors.activityNeutral,
  };

  static String _title(AuditAction action) => switch (action) {
    AuditAction.created => 'New Record',
    AuditAction.statusChanged => 'Status Updated',
    AuditAction.assigned => 'Work Assigned',
    AuditAction.merged => 'Reports Merged',
    AuditAction.updated => 'Record Updated',
    AuditAction.deleted => 'Record Removed',
  };

  /// Coarse relative time, matching the design's "10 MINS AGO" style.
  ///
  /// Deliberately not `intl`'s date formatting: the design wants elapsed
  /// time, and precision beyond "4 hours ago" is noise in an activity
  /// feed.
  static String _relativeTime(DateTime timestamp) {
    final elapsed = DateTime.now().toUtc().difference(timestamp.toUtc());

    if (elapsed.inMinutes < 1) return 'just now';
    if (elapsed.inMinutes < 60) {
      final value = elapsed.inMinutes;
      return '$value min${value == 1 ? '' : 's'} ago';
    }
    if (elapsed.inHours < 24) {
      final value = elapsed.inHours;
      return '$value hour${value == 1 ? '' : 's'} ago';
    }
    final value = elapsed.inDays;
    return '$value day${value == 1 ? '' : 's'} ago';
  }
}
