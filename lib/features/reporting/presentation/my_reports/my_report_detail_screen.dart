import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/enums/priority_level.dart';
import '../../../../core/enums/report_status.dart';
import '../../../../core/routing/route_paths.dart';
import '../../../../core/utils/display_id.dart';
import '../../../../core/utils/relative_time.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/person_avatar.dart';
import '../../../../core/widgets/priority_chip.dart';
import '../../../../shells/requestor/requestor_shell.dart';
import '../../../../shells/requestor/requestor_title_row.dart';
import '../../data/models/damage_report.dart';
import '../../data/models/status_change.dart';
import 'my_reports_providers.dart';
import 'report_timeline.dart';
import 'widgets/report_pills.dart';

/// One of the requestor's reports and how it is progressing, live
/// (Figma `169:1355`, Objective 3.B): its number and stage, the three-step
/// progress, the report, who is assigned, and the updates timeline.
///
/// The design draws a work order ("Work Order Details", "WO-2023-0892",
/// "Linked Report"). A report has no work order until it is assigned, so
/// until then the page is the report's own; from assignment on it reads
/// as drawn. What the requestor submitted — description, photos, their
/// urgency and suggested type — is not in the frame and follows the
/// timeline, in the 3.A detail page's style.
class MyReportDetailScreen extends ConsumerWidget {
  const MyReportDetailScreen({required this.reportId, super.key});

  final String reportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(myReportProvider(reportId));
    final hasWorkOrder = report.value?.fold(
      (report) => report.workOrderId != null,
      (_) => false,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RequestorTitleRow(
          title: hasWorkOrder ?? false
              ? 'Work Order Details'
              : 'Report Details',
          onBack: () => context.canPop()
              ? context.pop()
              : context.go(RoutePaths.staffMyReports),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              requestorBottomInset(context),
            ),
            children: [
              AsyncValueView<DamageReport>(
                value: report,
                onRetry: () => ref
                  ..invalidate(myReportProvider(reportId))
                  ..invalidate(myReportHistoryProvider(reportId)),
                data: (report) => _Tracking(report: report),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Tracking extends ConsumerWidget {
  const _Tracking({required this.report});

  final DamageReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(myReportHistoryProvider(report.id));
    final workOrderId = report.workOrderId;
    final progress = report.status.progress;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          workOrderId == null
              ? DisplayId.report(report.id)
              : DisplayId.workOrder(workOrderId),
          textAlign: TextAlign.center,
          style: AppTextStyles.trackingNumber,
        ),
        const SizedBox(height: 8),
        Center(child: _StatusPill(status: report.status)),
        const SizedBox(height: 24),
        if (progress == ReportProgress.closedOut)
          _ClosedNotice(report: report)
        else
          _ProgressSteps(progress: progress),
        const SizedBox(height: 24),
        _ReportCard(report: report),
        AsyncValueView<List<StatusChange>>(
          value: history,
          loadingHeight: 120,
          onRetry: () => ref.invalidate(myReportHistoryProvider(report.id)),
          data: (changes) {
            final timeline = ReportTimeline.of(report, changes);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (timeline.assignment case final assignment?) ...[
                  const SizedBox(height: 24),
                  _StaffCard(assignment: assignment),
                ],
                const SizedBox(height: 24),
                _UpdatesTimeline(report: report, timeline: timeline),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        _SubmittedCard(report: report),
        if (progress == ReportProgress.completed) ...[
          const SizedBox(height: 24),
          const _RateButton(),
        ],
      ],
    );
  }
}

/// "In Progress" in navy, under the number (`169:995`).
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final ReportStatus status;

  @override
  Widget build(BuildContext context) {
    final progress = status.progress;
    final (label, icon) = switch (progress) {
      ReportProgress.pending => (progress.label, Icons.pending_actions),
      ReportProgress.inProgress => (progress.label, Icons.pending_actions),
      ReportProgress.completed => (progress.label, Icons.task_alt),
      ReportProgress.closedOut => (
        status.timelineLabel,
        Icons.do_not_disturb_on_outlined,
      ),
    };

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.white),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: AppTextStyles.trackingStatus,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Submitted, Active, Finished (`169:1000`): the requestor's three stages,
/// gold up to where the report is.
class _ProgressSteps extends StatelessWidget {
  const _ProgressSteps({required this.progress});

  final ReportProgress progress;

  static const _steps = [
    ('Submitted', Icons.check),
    ('Active', Icons.handyman_outlined),
    ('Finished', Icons.done_all),
  ];

  int get _current => switch (progress) {
    ReportProgress.pending || ReportProgress.closedOut => 0,
    ReportProgress.inProgress => 1,
    ReportProgress.completed => 2,
  };

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final children = <Widget>[];
    for (var i = 0; i < _steps.length; i++) {
      if (i > 0) {
        children.add(
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Container(
                height: 4,
                color: i <= current
                    ? AppColors.accentGold
                    : AppColors.trackingRail,
              ),
            ),
          ),
        );
      }
      final (label, icon) = _steps[i];
      children.add(
        _Step(
          label: label,
          icon: icon,
          reached: i <= current,
          isCurrent: i == current,
        ),
      );
    }

    return Semantics(
      label: 'Step ${current + 1} of 3: ${_steps[current].$1}',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.label,
    required this.icon,
    required this.reached,
    required this.isCurrent,
  });

  final String label;
  final IconData icon;
  final bool reached;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 68,
    child: Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: reached
                ? AppColors.accentGold
                : AppColors.trackingUpcomingFill,
            border: reached ? null : Border.all(color: AppColors.trackingRail),
            boxShadow: reached
                ? const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            size: 16,
            color: reached ? Colors.white : AppColors.trackingUpcomingIcon,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: isCurrent
              ? AppTextStyles.trackingStep.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.trackingAccentText,
                )
              : AppTextStyles.trackingStep,
        ),
      ],
    ),
  );
}

/// In place of the steps, for a report that ended without the work being
/// done. Not drawn in the design; it borrows the timeline's note card.
class _ClosedNotice extends StatelessWidget {
  const _ClosedNotice({required this.report});

  final DamageReport report;

  @override
  Widget build(BuildContext context) {
    final reason = report.rejectionReason;
    final parent = report.duplicateOf;
    final (body, quoted) = switch (report.status) {
      ReportStatus.rejected when reason != null && reason.isNotEmpty => (
        reason,
        true,
      ),
      ReportStatus.rejected => ('GSU did not give a reason.', false),
      ReportStatus.merged when parent != null => (
        'GSU is tracking this damage under report '
            '${DisplayId.report(parent)}, filed earlier.',
        false,
      ),
      ReportStatus.merged => (
        'GSU is tracking this damage under a report filed earlier.',
        false,
      ),
      _ => ('GSU closed this report without further work.', false),
    };

    return _NoteCard(
      label: report.status.timelineLabel,
      body: body,
      quoted: quoted,
    );
  }
}

/// The report in brief (`169:1025`): title, priority, where, and type.
class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report});

  final DamageReport report;

  @override
  Widget build(BuildContext context) {
    final building = report.facilityName;
    final room = roomOf(report);
    final category = confirmedCategoryOf(report);

    return _GoldEdgeCard(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    report.workOrderId == null
                        ? 'Your Report'
                        : 'Linked Report',
                    style: AppTextStyles.trackingCardLabel,
                  ),
                  Text(report.title, style: AppTextStyles.trackingTitle),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _PriorityBadge(report: report),
          ],
        ),
        if (building != null || room != null) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: building == null
                    ? const SizedBox.shrink()
                    : _Place(icon: Icons.apartment_outlined, text: building),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: room == null
                    ? const SizedBox.shrink()
                    : _Place(icon: Icons.meeting_room_outlined, text: room),
              ),
            ],
          ),
        ],
        if (category != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.warmFill,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: AppColors.trackingRail),
            ),
            child: Text(category.label, style: AppTextStyles.trackingCategory),
          ),
        ],
      ],
    );
  }
}

/// "HIGH PRIORITY" once an administrator has set the official priority;
/// before that, while the report is still with GSU for review, a neutral
/// "AWAITING REVIEW" — so the requestor's own urgency is never shown as
/// GSU's decision. Nothing once a review ended without a priority (turned
/// down, merged, archived): there is nothing left to await. The design
/// draws only HIGH, in red; the other levels take the admin console's
/// priority colours.
class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({required this.report});

  final DamageReport report;

  @override
  Widget build(BuildContext context) {
    final level = report.officialPriority;
    if (level == null && report.status.progress != ReportProgress.pending) {
      return const SizedBox.shrink();
    }
    final (background, foreground, text) = switch (level) {
      null => (AppColors.warmFill, AppColors.warmText, 'AWAITING REVIEW'),
      PriorityLevel.high => (
        AppColors.error,
        Colors.white,
        '${level.label} PRIORITY',
      ),
      _ => (
        PriorityChip.paletteFor(level).$1,
        PriorityChip.paletteFor(level).$2,
        '${level.label} PRIORITY',
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        text,
        style: AppTextStyles.trackingBadge.copyWith(color: foreground),
      ),
    );
  }
}

class _Place extends StatelessWidget {
  const _Place({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 16, color: AppColors.warmText),
      const SizedBox(width: 8),
      Flexible(child: Text(text, style: AppTextStyles.trackingBody)),
    ],
  );
}

/// "Assigned Maintenance Personnel" (`169:1048`). The design shows a photo;
/// accounts carry none, so the shared avatar shows initials.
class _StaffCard extends StatelessWidget {
  const _StaffCard({required this.assignment});

  final TimelineEntry assignment;

  static final DateFormat _sameYear = DateFormat('MMM d');
  static final DateFormat _otherYear = DateFormat('MMM d, y');

  @override
  Widget build(BuildContext context) {
    final name = assignment.personnelName ?? 'GSU maintenance personnel';
    final trade = assignment.personnelSpecialization;
    final assignedOn = assignment.at.toLocal();
    final format = assignedOn.year == DateTime.now().year
        ? _sameYear
        : _otherYear;

    return _PlainCard(
      children: [
        const Text(
          'Assigned Maintenance Personnel',
          style: AppTextStyles.trackingCardLabel,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            PersonAvatar(
              fullName: name,
              size: 48,
              ringColor: AppColors.accentGold,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: AppTextStyles.trackingPersonName),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (trade != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(17),
                          ),
                          child: Text(
                            trade.label.toUpperCase(),
                            style: AppTextStyles.trackingBadge,
                          ),
                        ),
                      Text(
                        'Assigned ${format.format(assignedOn)}',
                        style: AppTextStyles.trackingMeta,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// "Updates Timeline" (`169:1064`): one entry per status change, newest
/// first, on a rail.
class _UpdatesTimeline extends StatelessWidget {
  const _UpdatesTimeline({required this.report, required this.timeline});

  final DamageReport report;
  final ReportTimeline timeline;

  @override
  Widget build(BuildContext context) {
    final entries = timeline.entries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Icon(Icons.history, size: 20, color: AppColors.accentGold),
            SizedBox(width: 8),
            Text('Updates Timeline', style: AppTextStyles.trackingSectionTitle),
          ],
        ),
        const SizedBox(height: 16),
        Stack(
          children: [
            Positioned(
              left: 12,
              top: 8,
              bottom: 0,
              child: Container(width: 2, color: AppColors.trackingRail),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < entries.length; i++)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: i == entries.length - 1 ? 0 : 24,
                    ),
                    child: _TimelineItem(
                      report: report,
                      entry: entries[i],
                      // The design greys the oldest dot: where it began.
                      isOldest: i == entries.length - 1,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.report,
    required this.entry,
    required this.isOldest,
  });

  final DamageReport report;
  final TimelineEntry entry;
  final bool isOldest;

  String get _text {
    final label = entry.status.timelineLabel;
    final parent = report.duplicateOf;
    return switch (entry.status) {
      ReportStatus.assigned when entry.personnelName != null =>
        '$label: ${entry.personnelName}',
      ReportStatus.merged when parent != null =>
        '$label (${DisplayId.report(parent)})',
      _ => label,
    };
  }

  @override
  Widget build(BuildContext context) {
    final note = entry.note;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                RelativeTime.dayAndTime(entry.at),
                style: AppTextStyles.trackingWhen,
              ),
              const SizedBox(height: 4),
              if (note != null && note.isNotEmpty)
                _NoteCard(label: entry.status.timelineLabel, body: note)
              else
                _PlainCard(
                  children: [Text(_text, style: AppTextStyles.trackingBody)],
                ),
            ],
          ),
        ),
        Positioned(
          left: 5,
          top: 0,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isOldest ? AppColors.trackingRail : AppColors.accentGold,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [
                BoxShadow(color: Color(0x1F000000), blurRadius: 2),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// What the requestor filed, beyond the title and place above: not in the
/// design frame, kept from the 3.A detail page.
class _SubmittedCard extends StatelessWidget {
  const _SubmittedCard({required this.report});

  final DamageReport report;

  static final DateFormat _when = DateFormat('MMM d, y · h:mm a');

  @override
  Widget build(BuildContext context) {
    final coordinates = report.coordinates;
    final suggested = report.requestorCategory;

    return _GoldEdgeCard(
      children: [
        const Text(
          'What you reported',
          style: AppTextStyles.trackingSectionTitle,
        ),
        const SizedBox(height: 12),
        _Field(
          label: 'SUBMITTED',
          value: _when.format(report.submittedAt.toLocal()),
        ),
        _Field(label: 'DESCRIPTION', value: report.description),
        _Field(
          label: 'URGENCY YOU GAVE',
          value: _sentence(report.requestorPriority.label),
        ),
        if (suggested != null)
          _Field(label: 'DAMAGE TYPE YOU SUGGESTED', value: suggested.label),
        if (coordinates != null)
          _Field(
            label: 'GPS LOCATION',
            value:
                'Lat: ${coordinates.latitude.toStringAsFixed(4)}, '
                'Long: ${coordinates.longitude.toStringAsFixed(4)}',
          ),
        if (report.photoUrls.isNotEmpty) ...[
          const Text('PHOTO EVIDENCE', style: AppTextStyles.signUpLabel),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final url in report.photoUrls)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    url,
                    width: 88,
                    height: 88,
                    fit: BoxFit.cover,
                    semanticLabel: 'Photo of the damage',
                    errorBuilder: (_, _, _) => const SizedBox.square(
                      dimension: 88,
                      child: ColoredBox(
                        color: AppColors.reportThumbPlaceholder,
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  static String _sentence(String text) =>
      text[0] + text.substring(1).toLowerCase();
}

/// "Rate this Service" (`169:1094`), on a completed report. The rating
/// screen itself is Objective 3.C.
class _RateButton extends StatelessWidget {
  const _RateButton();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      boxShadow: const [
        BoxShadow(
          color: Color(0x33000000),
          blurRadius: 8,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: FilledButton.icon(
      onPressed: () => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Rating the service arrives with the feedback screen in '
              'Objective 3.C.',
            ),
          ),
        ),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accentGold,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: const Icon(Icons.star_border, size: 22),
      label: const Text(
        'Rate this Service',
        style: AppTextStyles.trackingAction,
      ),
    ),
  );
}

/// A note from GSU on the timeline (`169:1081`, "ADMIN FOLLOW-UP"): pale
/// gold behind, a gold edge, the label above, the note quoted.
class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.label,
    required this.body,
    this.quoted = true,
  });

  final String label;
  final String body;

  /// Whether [body] is the administrator's own words, shown in quotes.
  final bool quoted;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.trackingNoteFill,
        border: Border(left: BorderSide(color: AppColors.accentGold, width: 4)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(), style: AppTextStyles.trackingNoteLabel),
            const SizedBox(height: 4),
            Text(
              quoted ? '"$body"' : body,
              style: quoted
                  ? AppTextStyles.trackingNote
                  : AppTextStyles.trackingBody,
            ),
          ],
        ),
      ),
    ),
  );
}

/// White, rounded, softly lifted — the staff card and timeline entries.
class _PlainCard extends StatelessWidget {
  const _PlainCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: const [
        BoxShadow(
          color: Color(0x14000000),
          blurRadius: 6,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}

/// White with a gold left edge — the report card.
class _GoldEdgeCard extends StatelessWidget {
  const _GoldEdgeCard({
    required this.children,
    this.padding = const EdgeInsets.all(16),
  });

  final List<Widget> children;
  final EdgeInsets padding;

  @override
  // Clipped rather than given a border radius: Flutter draws a one-sided
  // border only on a square box.
  Widget build(BuildContext context) => DecoratedBox(
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
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            left: BorderSide(color: AppColors.accentGold, width: 4),
          ),
        ),
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ),
    ),
  );
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.signUpLabel),
        const SizedBox(height: 2),
        Text(value, style: AppTextStyles.myReportsSearch),
      ],
    ),
  );
}
