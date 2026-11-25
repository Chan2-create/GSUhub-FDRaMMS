import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/enums/notification_type.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/utils/result.dart';
import '../data/models/app_notification.dart';
import 'notification_providers.dart';

// The navigation's numbered badges (2026-11-26, the adviser's
// consultation). Each item of the console's sidebar and the phones' bottom
// bars counts the unread notices about its section, as a number; opening
// the section reads them, which clears it. The whole list stays a press
// of the header's bell away.

/// Which navigation section a notice belongs to, by the path of the item
/// that opens it; null for one no item shows.
typedef NoticeSection = String? Function(AppNotification notice);

/// The console: reports to Damage Reports, work orders (started, ready
/// for sign-off) to Work Order Management, materials, stock and tools to
/// Inventory Management, sign-ups to User Accounts.
String? adminSectionOf(AppNotification notice) =>
    switch (notice.relatedEntityType) {
      'damage_reports' => RoutePaths.adminReports,
      'work_orders' => RoutePaths.adminWorkOrders,
      'material_requests' ||
      'inventory_items' ||
      'tool_requests' ||
      'tools' ||
      'tool_loans' => RoutePaths.adminInventory,
      'users' => RoutePaths.adminUsers,
      _ => notice.type.isAboutTools ? RoutePaths.adminInventory : null,
    };

/// The faculty and staff app: every notice is about one of their reports,
/// which the Reports tab holds.
String? requestorSectionOf(AppNotification notice) =>
    notice.relatedEntityType == 'damage_reports'
    ? RoutePaths.staffMyReports
    : null;

/// The maintenance app: tasks to Tasks; tools, and GSU's answers to a
/// material request ("Materials approved", "Materials request declined",
/// as the database titles them), to Materials; the rest (new, sent back,
/// signed off or reassigned work) to Home, where the work orders are.
String? personnelSectionOf(AppNotification notice) {
  if (notice.type == NotificationType.taskAssigned) {
    return RoutePaths.personnelTasks;
  }
  if (notice.type.isAboutTools || notice.title.startsWith('Materials')) {
    return RoutePaths.personnelMaterials;
  }
  return notice.relatedEntityType == null
      ? null
      : RoutePaths.personnelDashboard;
}

/// How many unread notices each section has, by its path.
Map<String, int> badgeCountsOf(
  Iterable<AppNotification> unread,
  NoticeSection sectionOf,
) {
  final counts = <String, int>{};
  for (final notice in unread) {
    if (notice.isRead) continue;
    final section = sectionOf(notice);
    if (section != null) counts[section] = (counts[section] ?? 0) + 1;
  }
  return counts;
}

/// The signed-in person's unread notices, live, or none while they load
/// or could not be read: a badge is a convenience, never an error.
List<AppNotification> unreadNoticesOf(WidgetRef ref) =>
    switch (ref.watch(unreadNoticesProvider).value) {
      Success(:final value) => value,
      _ => const [],
    };

/// Reads the notices of the section [location] is in, as it opens: what
/// clears the section's badge. Wraps a shell's page. [sectionFor] names
/// the section of a location, as the navigation does.
class NavBadgeClearer extends ConsumerStatefulWidget {
  const NavBadgeClearer({
    required this.location,
    required this.sectionOf,
    required this.sectionFor,
    required this.child,
    super.key,
  });

  final String location;
  final NoticeSection sectionOf;
  final String? Function(String location) sectionFor;
  final Widget child;

  @override
  ConsumerState<NavBadgeClearer> createState() => _NavBadgeClearerState();
}

class _NavBadgeClearerState extends ConsumerState<NavBadgeClearer> {
  /// Asked to be read already: not asked again while the answer is on its
  /// way.
  final _asked = <String>{};

  @override
  Widget build(BuildContext context) {
    final section = widget.sectionFor(widget.location);
    if (section != null) {
      final ids = [
        for (final notice in unreadNoticesOf(ref))
          if (!notice.isRead &&
              widget.sectionOf(notice) == section &&
              !_asked.contains(notice.id))
            notice.id,
      ];
      if (ids.isNotEmpty) {
        _asked.addAll(ids);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(
            ref.read(notificationActionsProvider).markManyRead(ids).then((
              result,
            ) {
              // Refused or unreached: asked again the next time round.
              if (result.isFailure && mounted) _asked.removeAll(ids);
            }),
          );
        });
      }
    }
    return widget.child;
  }
}
