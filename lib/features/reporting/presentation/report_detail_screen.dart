import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/enums/report_status.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/utils/display_id.dart';
import '../../../core/utils/result.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/priority_chip.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_chip.dart';
import '../../audit/data/models/audit_log_entry.dart';
import '../data/models/damage_report.dart';
import 'report_providers.dart';
import 'report_review_controller.dart';

/// One damage report in full.
///
/// No Figma frame exists for this view — the design file has the table but
/// not the record behind it — so it is composed from the components 2.A
/// established rather than invented from scratch.
///
/// Read-only apart from the review decisions. Confirming category and
/// priority is Objective 4.C; the slot for those controls is marked below
/// so they drop in without rearranging this screen.
class ReportDetailScreen extends ConsumerWidget {
  const ReportDetailScreen({required this.reportId, super.key});

  final String reportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SingleChildScrollView(
    padding: const EdgeInsets.all(32),
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
        _ReviewActions(report: report),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = <Widget>[
              Expanded(
                flex: 2,
                child: Column(
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
                    const SizedBox(height: 16),
                    _HistoryCard(reportId: report.id, report: report),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    _ClassificationCard(report: report),
                    const SizedBox(height: 16),
                    _LocationCard(report: report),
                    const SizedBox(height: 16),
                    _ReporterCard(report: report, dateFormat: dateFormat),
                  ],
                ),
              ),
            ];

            if (constraints.maxWidth >= 1000) {
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: columns,
                ),
              );
            }
            return Column(
              children: [
                columns.first,
                const SizedBox(height: 16),
                columns.last,
              ],
            );
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
  bool _busy = false;

  Future<void> _run(Future<Result<void>> Function() action) async {
    setState(() => _busy = true);
    final result = await action();
    if (!mounted) return;
    setState(() => _busy = false);

    result.fold((_) => null, (failure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(failure.message),
          backgroundColor: AppColors.error,
        ),
      );
    });
  }

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
              : () => _run(() => controller.startReview(report.id)),
          child: const Text('Start review'),
        ),
      if (status.canTransitionTo(ReportStatus.approved))
        FilledButton(
          onPressed: _busy
              ? null
              : () => _run(() => controller.approve(report.id)),
          child: const Text('Approve'),
        ),
      if (status.canTransitionTo(ReportStatus.rejected))
        OutlinedButton(
          onPressed: _busy ? null : _promptReject,
          child: const Text('Reject'),
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
      () => ref
          .read(reportReviewControllerProvider)
          .reject(widget.report.id, reason),
    );
  }
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

class _ClassificationCard extends StatelessWidget {
  const _ClassificationCard({required this.report});

  final DamageReport report;

  @override
  Widget build(BuildContext context) => SectionCard(
    title: 'Classification',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Field(
          label: 'Damage type',
          value: report.category?.label ?? 'Unclassified',
        ),
        const SizedBox(height: 16),
        _Field(
          label: 'Priority',
          child: PriorityChip(
            level: report.effectivePriority,
            confirmed: report.isPriorityConfirmed,
          ),
        ),
        // Objective 4.C adds the controls that confirm or override these
        // two values. They slot in here, below what they change.
        if (!report.isPriorityConfirmed) ...[
          const SizedBox(height: 8),
          const Text(
            'Shown as submitted by the requestor. An administrator confirms '
            'the official priority before work is scheduled.',
            style: AppTextStyles.bodySmall,
          ),
        ],
        if (report.rejectionReason != null) ...[
          const SizedBox(height: 16),
          _Field(label: 'Rejection reason', value: report.rejectionReason!),
        ],
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

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.title,
    required this.timestamp,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final String timestamp;

  @override
  Widget build(BuildContext context) => Padding(
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
              if (subtitle != null)
                Text(subtitle!, style: AppTextStyles.bodySmall),
            ],
          ),
        ),
        Text(timestamp, style: AppTextStyles.bodySmall),
      ],
    ),
  );
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
