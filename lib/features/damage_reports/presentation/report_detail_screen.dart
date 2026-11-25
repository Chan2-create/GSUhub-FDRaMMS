import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/breakpoints.dart';
import '../../../core/constants/damage_categories.dart';
import '../../../core/enums/priority_level.dart';
import '../../../core/enums/report_status.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/utils/display_id.dart';
import '../../../core/utils/result.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/priority_chip.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_chip.dart';
import '../../audit/data/models/audit_log_entry.dart';
import '../../classification/domain/duplicate_detector.dart';
import '../../classification/presentation/possible_duplicates_card.dart';
import '../../classification/presentation/report_assessment_panel.dart';
import '../data/models/damage_report.dart';
import 'report_providers.dart';
import 'report_review_controller.dart';
import 'widgets/report_archive.dart';
import 'widgets/report_assignment_section.dart';

/// One damage report in full.
///
/// No Figma frame exists for this view — the design file has the table but
/// not the record behind it — so it is composed from the components 2.A
/// established rather than invented from scratch.
///
/// Read-only apart from the review decisions: the status moves (2.B), and
/// the damage type, priority criteria and official priority, with any
/// possible duplicates (Objectives 4.A–4.C).
///
/// **2026-11-26** (the adviser's consultation): a report is handled from
/// start to finish here. Pending → Start review (Under Review) → confirm
/// the type and official priority → Approve or Reject → assign personnel
/// of its trade, or reschedule, on this page → Assigned → In Progress →
/// Completed. Task Assignment and Work Orders stay, for reassigning and
/// following the work later, and are no longer a required step.
class ReportDetailScreen extends ConsumerWidget {
  const ReportDetailScreen({required this.reportId, super.key});

  final String reportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SingleChildScrollView(
    padding: EdgeInsets.all(Breakpoints.gutter(context)),
    child: AsyncValueView<DamageReport>(
      value: ref.watch(reportByIdProvider(reportId)),
      onRetry: () => ref.invalidate(reportByIdProvider(reportId)),
      data: (report) => _Detail(report: report),
    ),
  );
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.report});

  final DamageReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateFormat = DateFormat('MMM d, y · h:mm a');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: () => context.go(RoutePaths.adminReports),
          icon: const Icon(Icons.arrow_back, size: 16),
          label: const Text(
            'All damage reports',
            style: AppTextStyles.linkText,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DisplayId.report(report.id),
                    style: AppTextStyles.monoIdentifier.copyWith(
                      color: AppColors.textFaint,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(report.title, style: AppTextStyles.pageTitle),
                ],
              ),
            ),
            const SizedBox(width: 24),
            Wrap(
              spacing: 8,
              children: [
                StatusChip.report(report.status),
                PriorityChip(
                  level: report.effectivePriority,
                  confirmed: report.isPriorityConfirmed,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        _ReviewSteps(report: report),
        const SizedBox(height: 16),
        _ReviewActions(report: report),
        // Approved: the assignment comes next, right here.
        if (report.awaitsAssignment) ...[
          const SizedBox(height: 24),
          ReportAssignmentSection(report: report),
        ] else if (report.workOrderId case final workOrderId?) ...[
          const SizedBox(height: 24),
          _AssignedNotice(report: report, workOrderId: workOrderId),
        ],
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
            final main = Column(
              children: [
                SectionCard(
                  title: 'Description',
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      report.description,
                      style: AppTextStyles.fieldValue,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _PhotoEvidence(report: report),
                // The manuscript has the administrator weigh the score
                // "together with the report description, photo evidence,
                // facility or location details" (§3.4), so the review sits
                // below them.
                if (report.duplicateOf != null ||
                    DuplicateDetector.isFlaggable(report)) ...[
                  const SizedBox(height: 16),
                  PossibleDuplicatesCard(report: report),
                ],
                // The type and priority are confirmed once the review has
                // started (2026-11-26); until then the page says how.
                if (report.canBeAssessed &&
                    report.status != ReportStatus.submitted) ...[
                  const SizedBox(height: 16),
                  ReportAssessmentPanel(report: report),
                ] else if (report.canBeAssessed) ...[
                  const SizedBox(height: 16),
                  const _StartReviewNote(),
                ],
                const SizedBox(height: 16),
                _HistoryCard(reportId: report.id, report: report),
              ],
            );
            final side = Column(
              children: [
                _ClassificationCard(report: report),
                const SizedBox(height: 16),
                _LocationCard(report: report),
                const SizedBox(height: 16),
                _ReporterCard(report: report, dateFormat: dateFormat),
              ],
            );

            if (constraints.maxWidth >= 1000) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: main),
                  const SizedBox(width: 16),
                  Expanded(child: side),
                ],
              );
            }
            // Stacked on a narrower window. The columns are not wrapped in
            // Expanded here: the page scrolls, so a Column has no height
            // to share out.
            return Column(children: [main, const SizedBox(height: 16), side]);
          },
        ),
      ],
    );
  }
}

/// Start review / Approve / Reject.
///
/// Only the moves the lifecycle allows from here are offered, so the
/// buttons match what the repository would accept. The repository still
/// checks — this is the convenience, not the guard.
class _ReviewActions extends ConsumerStatefulWidget {
  const _ReviewActions({required this.report});

  final DamageReport report;

  @override
  ConsumerState<_ReviewActions> createState() => _ReviewActionsState();
}

class _ReviewActionsState extends ConsumerState<_ReviewActions> {
  /// The move being made, while the database is being asked: its button
  /// shows it, and none of them can be pressed again until it answers.
  ReportStatus? _moving;

  bool get _busy => _moving != null;

  /// Whether the review below has confirmed the damage type and the
  /// official priority, which approving waits for.
  bool get _reviewed =>
      widget.report.category != null && widget.report.isPriorityConfirmed;

  /// Makes a move and says how it went: [done] once the database has
  /// confirmed it, or why not, with a way to try again. By then the page
  /// already shows what the database holds.
  Future<void> _run(
    ReportStatus to,
    Future<Result<void>> Function() action, {
    required String done,
  }) async {
    // One move at a time, whatever the buttons looked like when pressed.
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _moving = to);
    final result = await action();
    if (mounted) setState(() => _moving = null);

    result.fold(
      (_) => messenger.showSnackBar(SnackBar(content: Text(done))),
      (failure) => messenger.showSnackBar(
        SnackBar(
          content: Text(failure.message),
          backgroundColor: AppColors.error,
          action: SnackBarAction(
            label: 'Try again',
            textColor: AppColors.textOnDark,
            onPressed: () {
              if (mounted) unawaited(_run(to, action, done: done));
            },
          ),
        ),
      ),
    );
  }

  /// [label], or a spinner while that move is being made.
  Widget _label(ReportStatus to, String label) => _moving == to
      ? const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : Text(label);

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final controller = ref.read(reportReviewControllerProvider);
    final status = report.status;

    final actions = <Widget>[
      if (status.canTransitionTo(ReportStatus.underReview))
        FilledButton(
          onPressed: _busy
              ? null
              : () => _run(
                  ReportStatus.underReview,
                  () => controller.startReview(report.id),
                  done:
                      'Review started: the report is Under Review. Confirm '
                      'its type and priority below.',
                ),
          child: _label(ReportStatus.underReview, 'Start review'),
        ),
      // Approved once the type and official priority are confirmed in the
      // review below (2026-11-26): assigning needs both, and it comes next.
      if (status.canTransitionTo(ReportStatus.approved))
        _HintWhen(
          !_reviewed,
          'Confirm the damage type and official priority in the review '
          'below first.',
          FilledButton(
            key: const ValueKey('approve-report'),
            onPressed: _busy || !_reviewed
                ? null
                : () => _run(
                    ReportStatus.approved,
                    () => controller.approve(report.id),
                    done:
                        'Report approved. Assign personnel or reschedule it '
                        'below.',
                  ),
            child: _label(ReportStatus.approved, 'Approve'),
          ),
        ),
      if (status.canTransitionTo(ReportStatus.rejected))
        OutlinedButton(
          onPressed: _busy ? null : _promptReject,
          child: _label(ReportStatus.rejected, 'Reject'),
        ),
      // Reports are archived, never deleted (2026-11-08).
      if (report.isArchived || report.canBeArchived)
        OutlinedButton.icon(
          onPressed: _busy ? null : () => confirmReportArchive(context, report),
          icon: Icon(
            report.isArchived
                ? Icons.unarchive_outlined
                : Icons.archive_outlined,
            size: 18,
          ),
          label: Text(report.isArchived ? 'Restore from archive' : 'Archive'),
        ),
    ];

    if (actions.isEmpty) return const SizedBox.shrink();

    return Wrap(spacing: 12, runSpacing: 12, children: actions);
  }

  Future<void> _promptReject() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _RejectDialog(),
    );
    if (reason == null || !mounted) return;
    await _run(
      ReportStatus.rejected,
      () => ref
          .read(reportReviewControllerProvider)
          .reject(widget.report.id, reason),
      done: 'Report rejected.',
    );
  }
}

/// Where the report is on the way from Pending to Assigned (2026-11-26),
/// so the next step on this page is plain.
class _ReviewSteps extends StatelessWidget {
  const _ReviewSteps({required this.report});

  final DamageReport report;

  static const _steps = [
    'Start review',
    'Confirm type and priority',
    'Approve or reject',
    'Assign or reschedule',
  ];

  /// The step to do now, 0–3; 4 once assigned; null for a report that
  /// left this way (rejected, merged, archived).
  int? get _current {
    final status = report.status;
    if (report.workOrderId != null ||
        status.index >= ReportStatus.assigned.index &&
            status.index <= ReportStatus.closed.index) {
      return 4;
    }
    return switch (status) {
      ReportStatus.submitted => 0,
      ReportStatus.underReview =>
        report.category != null && report.isPriorityConfirmed ? 2 : 1,
      ReportStatus.approved => 3,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    if (current == null) return const SizedBox.shrink();
    return Semantics(
      label: current >= _steps.length
          ? 'Review done: the report is assigned'
          : 'Step ${current + 1} of ${_steps.length}: ${_steps[current]}',
      child: ExcludeSemantics(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final (index, step) in _steps.indexed)
              _StepChip(
                number: index + 1,
                label: step,
                done: index < current,
                current: index == current,
              ),
          ],
        ),
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({
    required this.number,
    required this.label,
    required this.done,
    required this.current,
  });

  final int number;
  final String label;
  final bool done;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final color = current
        ? AppColors.primary
        : done
        ? AppColors.presenceActiveText
        : AppColors.textFaint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: current ? AppColors.statusInProgressBackground : null,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: current ? AppColors.primary : AppColors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            done ? Icons.check_circle : Icons.circle_outlined,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            '$number. $label',
            style: AppTextStyles.bodySmall.copyWith(
              color: color,
              fontWeight: current ? FontWeight.w600 : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// [child], with [message] on hover only while [show]: a Tooltip with an
/// empty message still opens an empty bubble.
class _HintWhen extends StatelessWidget {
  const _HintWhen(this.show, this.message, this.child);

  final bool show;
  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      show ? Tooltip(message: message, child: child) : child;
}

/// In place of the review panel on a report not yet under review.
class _StartReviewNote extends StatelessWidget {
  const _StartReviewNote();

  @override
  Widget build(BuildContext context) => const SectionCard(
    title: 'Classification and priority review',
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        'Press Start review to check the classification and confirm or '
        'change the official priority here.',
        style: AppTextStyles.bodySmall,
      ),
    ),
  );
}

/// Once assigned: who has the work, and the way to its work order, where
/// it is followed and reassigned.
class _AssignedNotice extends StatelessWidget {
  const _AssignedNotice({required this.report, required this.workOrderId});

  final DamageReport report;
  final String workOrderId;

  @override
  Widget build(BuildContext context) => SectionCard(
    title: 'Assigned',
    subtitle:
        'Work order ${DisplayId.workOrder(workOrderId)} was raised for this '
        'report. Follow it, or reassign it, from the work order.',
    trailing: OutlinedButton.icon(
      onPressed: () =>
          context.go(RoutePaths.adminWorkOrderDetailFor(workOrderId)),
      icon: const Icon(Icons.open_in_new, size: 18),
      label: const Text('Open work order'),
    ),
    child: const SizedBox.shrink(),
  );
}

/// Rejection needs a reason: a dismissed report with no recorded why tells
/// the requestor nothing and leaves the next reviewer guessing.
class _RejectDialog extends StatefulWidget {
  const _RejectDialog();

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Reject this report'),
    content: Form(
      key: _formKey,
      child: TextFormField(
        controller: _controller,
        autofocus: true,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Reason',
          hintText: 'Why is this report being dismissed?',
        ),
        validator: (value) => (value ?? '').trim().isEmpty
            ? 'Give a reason for rejecting this report.'
            : null,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_formKey.currentState?.validate() ?? false) {
            Navigator.of(context).pop(_controller.text.trim());
          }
        },
        child: const Text('Reject report'),
      ),
    ],
  );
}

/// The report's classification and priority, each said three ways and
/// kept apart (2026-11-16): what the **requestor** chose when filing,
/// which never changes; what the **system** suggests or recommends; and
/// what the **administrator** made official, or that it is still awaiting
/// their review. The summary beside the review panel, and all there is
/// once the report is past review.
class _ClassificationCard extends StatelessWidget {
  const _ClassificationCard({required this.report});

  final DamageReport report;

  static final DateFormat _when = DateFormat('MMM d, y · h:mm a');

  /// "Awaiting administrative review" while the report can still get one;
  /// what became of it once it cannot.
  String get _noOfficialValue => report.canBeAssessed
      ? 'Awaiting administrative review'
      : 'None: the report ended without one';

  @override
  Widget build(BuildContext context) {
    final official = report.officialCategory;
    final chosen = report.requestorCategory;
    final suggested = report.suggestedCategory;
    final officialPriority = report.officialPriority;
    final recommended = report.recommendedPriority;
    final score = report.priorityScore;
    final reviewedAt = report.reviewedAt;

    return SectionCard(
      title: 'Classification',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (report.awaitsAssessment) ...[
            const _AwaitingReviewNote(),
            const SizedBox(height: 16),
          ],
          const _GroupLabel("Requestor's submission"),
          const SizedBox(height: 8),
          _Field(
            label: 'Initial classification',
            value: chosen?.label ?? 'Not chosen',
          ),
          const SizedBox(height: 12),
          _Field(
            label: 'Initial priority',
            child: _SourcedPriority(
              level: report.requestorPriority,
              confirmed: false,
              source: 'Requestor-selected',
            ),
          ),
          const _CardDivider(),
          const _GroupLabel("Administrator's review"),
          const SizedBox(height: 8),
          _Field(
            label: 'Official classification',
            value: official?.label ?? _noOfficialValue,
          ),
          if (_classificationNote(official, chosen, suggested) case final note?)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(note, style: AppTextStyles.bodySmall),
            ),
          const SizedBox(height: 12),
          _Field(
            label: 'Official priority',
            value: officialPriority == null ? _noOfficialValue : null,
            child: officialPriority == null
                ? null
                : _SourcedPriority(
                    level: officialPriority,
                    confirmed: true,
                    source: 'Administrator-confirmed',
                  ),
          ),
          if (_priorityNote(officialPriority) case final note?)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(note, style: AppTextStyles.bodySmall),
            ),
          if (officialPriority != null && reviewedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Reviewed ${_when.format(reviewedAt.toLocal())}. Who, and '
                'any reason given, are in the history.',
                style: AppTextStyles.bodySmall,
              ),
            ),
          const _CardDivider(),
          const _GroupLabel('System recommendation'),
          const SizedBox(height: 8),
          _Field(
            label: 'Recommended priority',
            value: recommended == null
                ? 'Computed when the four criteria are rated in the review'
                : null,
            child: recommended == null
                ? null
                : _SourcedPriority(
                    level: recommended,
                    confirmed: true,
                    source: score == null
                        ? 'System-recommended'
                        : 'System-recommended · score '
                              '${score.toStringAsFixed(2)}',
                  ),
          ),
          if (report.rejectionReason != null) ...[
            const _CardDivider(),
            _Field(label: 'Rejection reason', value: report.rejectionReason!),
          ],
        ],
      ),
    );
  }

  /// How the official damage type came about, or what stands in for it
  /// until there is one.
  String? _classificationNote(
    DamageCategory? official,
    DamageCategory? chosen,
    DamageCategory? suggested,
  ) {
    if (official == null) {
      if (suggested != null) {
        return 'The keywords suggest ${suggested.label}: a suggestion until '
            'an administrator confirms it.';
      }
      return report.canBeAssessed && report.category == null
          ? 'No keyword matched, so an administrator classifies it.'
          : null;
    }
    if (chosen == null) return 'The requestor did not choose a type.';
    return official == chosen
        ? "Confirms the requestor's choice."
        : "Changed from the requestor's ${chosen.label}, which is kept above.";
  }

  /// How the official priority stands against what the requestor chose.
  String? _priorityNote(PriorityLevel? official) {
    if (official == null) {
      return report.canBeAssessed
          ? "Until then the report is listed under the requestor's own "
                'urgency, marked as unconfirmed.'
          : null;
    }
    final initial = report.requestorPriority;
    if (official == initial) return "Confirms the requestor's choice.";
    return '${official.index > initial.index ? 'Raised' : 'Lowered'} from the '
        "requestor's ${initial.title}, which is kept above.";
  }
}

/// A heading for one of the card's three sources.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppTextStyles.fieldValue.copyWith(fontWeight: FontWeight.w600),
  );
}

class _CardDivider extends StatelessWidget {
  const _CardDivider();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 16),
    child: Divider(height: 1, color: AppColors.border),
  );
}

/// A priority and where it came from: requestor-selected,
/// system-recommended or administrator-confirmed.
class _SourcedPriority extends StatelessWidget {
  const _SourcedPriority({
    required this.level,
    required this.confirmed,
    required this.source,
  });

  final PriorityLevel level;
  final bool confirmed;
  final String source;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      PriorityChip(level: level, confirmed: confirmed),
      Text(source, style: AppTextStyles.bodySmall),
    ],
  );
}

/// Says, at the top of the card, that nothing on it is official yet.
class _AwaitingReviewNote extends StatelessWidget {
  const _AwaitingReviewNote();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(
            Icons.hourglass_top_outlined,
            size: 16,
            color: AppColors.textFaint,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Awaiting administrative review. The values below are the '
            "requestor's own until an administrator confirms or changes "
            'them.',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    ),
  );
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.report});

  final DamageReport report;

  @override
  Widget build(BuildContext context) {
    final coordinates = report.coordinates;

    return SectionCard(
      title: 'Location',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Field(label: 'Facility', value: report.facilityName ?? '—'),
          const SizedBox(height: 16),
          _Field(
            label: 'Description',
            value: report.locationDescription ?? '—',
          ),
          const SizedBox(height: 16),
          _Field(
            label: 'Geo-tag',
            value: coordinates == null
                ? 'Not captured'
                : '${coordinates.latitude.toStringAsFixed(5)}, '
                      '${coordinates.longitude.toStringAsFixed(5)}',
          ),
        ],
      ),
    );
  }
}

class _ReporterCard extends StatelessWidget {
  const _ReporterCard({required this.report, required this.dateFormat});

  final DamageReport report;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) => SectionCard(
    title: 'Submission',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Field(label: 'Reported by', value: report.reporterName),
        const SizedBox(height: 16),
        _Field(
          label: 'Submitted',
          value: dateFormat.format(report.submittedAt.toLocal()),
        ),
        const SizedBox(height: 16),
        _Field(
          label: 'Last updated',
          value: dateFormat.format(report.updatedAt.toLocal()),
        ),
        if (report.workOrderId != null) ...[
          const SizedBox(height: 16),
          _Field(
            label: 'Work order',
            value: DisplayId.workOrder(report.workOrderId!),
          ),
        ],
      ],
    ),
  );
}

class _PhotoEvidence extends StatelessWidget {
  const _PhotoEvidence({required this.report});

  final DamageReport report;

  @override
  Widget build(BuildContext context) => SectionCard(
    title: 'Photo evidence',
    child: report.photoUrls.isEmpty
        ? const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'No photos were attached to this report.',
              style: AppTextStyles.bodySmall,
            ),
          )
        : Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final url in report.photoUrls)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    url,
                    width: 160,
                    height: 120,
                    fit: BoxFit.cover,
                    // Storage can refuse or the file can be gone; a broken
                    // image icon says more than a blank rectangle.
                    errorBuilder: (context, error, stack) => Container(
                      width: 160,
                      height: 120,
                      color: AppColors.surfaceMuted,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.broken_image_outlined,
                        color: AppColors.textFaint,
                      ),
                    ),
                  ),
                ),
            ],
          ),
  );
}

class _HistoryCard extends ConsumerWidget {
  const _HistoryCard({required this.reportId, required this.report});

  final String reportId;
  final DamageReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateFormat = DateFormat('MMM d, y · h:mm a');

    return SectionCard(
      title: 'Status history',
      child: AsyncValueView<List<AuditLogEntry>>(
        value: ref.watch(reportHistoryProvider(reportId)),
        onRetry: () => ref.invalidate(reportHistoryProvider(reportId)),
        loadingHeight: 80,
        data: (entries) {
          // Submission is not an audit entry — it happens in the requestor
          // app — but it is the first thing that happened to this report,
          // so the timeline starts from the record itself.
          final rows = <Widget>[
            _HistoryRow(
              title: 'Submitted by ${report.reporterName}',
              timestamp: dateFormat.format(report.submittedAt.toLocal()),
            ),
            for (final entry in entries.reversed)
              _HistoryRow(
                title: entry.description,
                subtitle: entry.actorName,
                details: reviewDetailsOf(entry),
                timestamp: dateFormat.format(entry.timestamp.toLocal()),
              ),
          ];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: rows,
          );
        },
      ),
    );
  }
}

/// What a review changed, as the history spells it out under the entry:
/// the classification and the official priority from what they were to
/// what they became, and what the requestor had chosen. Empty for an
/// entry that is not a review.
@visibleForTesting
List<String> reviewDetailsOf(AuditLogEntry entry) {
  final changes = entry.changes;
  if (changes == null || changes['officialPriority'] is! Map) return const [];

  String category(Object? id) {
    if (id is! String) return 'unclassified';
    for (final type in DamageCategory.values) {
      if (type.id == id) return type.label;
    }
    return id;
  }

  String priority(Object? id) {
    if (id is! String) return 'none';
    for (final level in PriorityLevel.values) {
      if (level.id == id) return level.title;
    }
    return id;
  }

  String change(String what, Object? pair, String Function(Object?) label) {
    final from = pair is Map ? pair['from'] : null;
    final to = pair is Map ? pair['to'] : null;
    return from == null || from == to
        ? '$what: ${label(to)}'
        : '$what: ${label(from)} → ${label(to)}';
  }

  final requestor = changes['requestor'];
  return [
    change('Classification', changes['category'], category),
    change('Official priority', changes['officialPriority'], priority),
    if (requestor is Map)
      'The requestor chose: '
          '${requestor['category'] == null ? 'no damage type' : category(requestor['category'])}, '
          '${priority(requestor['priority'])} priority',
  ];
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.title,
    required this.timestamp,
    this.subtitle,
    this.details = const [],
  });

  final String title;
  final String? subtitle;

  /// Further lines under the entry: what a review changed.
  final List<String> details;
  final String timestamp;

  @override
  Widget build(BuildContext context) {
    // On a phone the time goes under the entry: beside it, a long stamp
    // ("Nov 12, 2026 · 10:42 PM") left the entry no room at all.
    final compact = Breakpoints.isCompact(context);
    final stamp = Text(timestamp, style: AppTextStyles.bodySmall);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6, right: 12),
            child: Icon(Icons.circle, size: 8, color: AppColors.textFaint),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.fieldValue),
                for (final line in details)
                  Text(line, style: AppTextStyles.bodySmall),
                if (subtitle != null)
                  Text(subtitle!, style: AppTextStyles.bodySmall),
                if (compact) stamp,
              ],
            ),
          ),
          if (!compact) stamp,
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, this.value, this.child});

  final String label;
  final String? value;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label.toUpperCase(), style: AppTextStyles.fieldLabel),
      const SizedBox(height: 4),
      child ?? Text(value ?? '—', style: AppTextStyles.fieldValue),
    ],
  );
}
