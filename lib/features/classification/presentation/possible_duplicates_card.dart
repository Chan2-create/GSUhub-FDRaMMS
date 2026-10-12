import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/utils/display_id.dart';
import '../../../core/utils/result.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_chip.dart';
import '../../reporting/data/models/damage_report.dart';
import '../../reporting/presentation/report_review_controller.dart';
import '../domain/duplicate_detector.dart';
import 'classification_providers.dart';

/// Reports that may describe the same damage as this one, and what an
/// administrator can do about each: merge them, or keep them separate
/// (manuscript §3.4; Objective 4.C).
///
/// On a report already merged, says which report it was merged into.
class PossibleDuplicatesCard extends ConsumerWidget {
  const PossibleDuplicatesCard({required this.report, super.key});

  final DamageReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (report.duplicateOf case final parentId?) {
      return SectionCard(
        title: 'Merged as a duplicate',
        child: Row(
          children: [
            Expanded(
              child: Text(
                'GSU is tracking this damage under '
                '${DisplayId.report(parentId)}.',
                style: AppTextStyles.fieldValue,
              ),
            ),
            TextButton(
              onPressed: () =>
                  context.go(RoutePaths.adminReportDetailFor(parentId)),
              child: Text('Open ${DisplayId.report(parentId)}'),
            ),
          ],
        ),
      );
    }
    if (!DuplicateDetector.isFlaggable(report)) return const SizedBox.shrink();

    final candidates = ref.watch(duplicateCandidatesProvider(report.id));
    final count = switch (candidates) {
      AsyncData(value: Success(:final value)) => value.length,
      _ => 0,
    };

    return SectionCard(
      title: count == 0
          ? 'Possible duplicates'
          : 'Possible duplicates ($count)',
      child: AsyncValueView<List<DuplicateCandidate>>(
        value: candidates,
        loadingHeight: 60,
        onRetry: () => ref
          ..invalidate(duplicateDetectionConfigProvider)
          ..invalidate(duplicateFlagsProvider),
        isEmpty: (list) => list.isEmpty,
        emptyIcon: Icons.content_copy_outlined,
        emptyMessage:
            'None found. No other open report at the same place, filed '
            'within the detection window, shares this damage type or '
            'wording.',
        data: (list) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Flagged by the duplicate rules: the same place, filed close '
              'together, with the same damage type or similar wording. '
              'Nothing is merged until you decide.',
              style: AppTextStyles.bodySmall,
            ),
            for (final candidate in list) ...[
              const SizedBox(height: 16),
              _CandidateRow(report: report, candidate: candidate),
            ],
          ],
        ),
      ),
    );
  }
}

class _CandidateRow extends ConsumerStatefulWidget {
  const _CandidateRow({required this.report, required this.candidate});

  final DamageReport report;
  final DuplicateCandidate candidate;

  @override
  ConsumerState<_CandidateRow> createState() => _CandidateRowState();
}

class _CandidateRowState extends ConsumerState<_CandidateRow> {
  bool _busy = false;

  Future<void> _run(
    Future<Result<void>> Function() action,
    String success,
  ) async {
    setState(() => _busy = true);
    final result = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    final messenger = ScaffoldMessenger.of(context);
    result.fold(
      (_) => messenger.showSnackBar(SnackBar(content: Text(success))),
      (failure) => messenger.showSnackBar(
        SnackBar(
          content: Text(failure.message),
          backgroundColor: AppColors.error,
        ),
      ),
    );
  }

  Future<void> _merge(MergePlan plan) async {
    final duplicateId = DisplayId.report(plan.duplicate.id);
    final parentId = DisplayId.report(plan.parent.id);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Merge as a duplicate?'),
        content: Text(
          '$duplicateId will be closed as a duplicate of $parentId, and its '
          'requestor told that GSU is tracking the damage under $parentId. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Merge'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => ref
          .read(reportReviewControllerProvider)
          .merge(parentId: plan.parent.id, duplicateId: plan.duplicate.id),
      '$duplicateId merged into $parentId.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final candidate = widget.candidate;
    final other = candidate.report;
    final plan = DuplicateDetector.mergePlanFor(report, other);
    final earlier = other.submittedAt.isBefore(report.submittedAt);

    final reasons = [
      if (candidate.sameCategory) 'same damage type (${other.category!.label})',
      '${(candidate.similarity * 100).round()}% similar wording',
      'filed ${_describe(candidate.apart)} ${earlier ? 'earlier' : 'later'}',
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TextButton(
                  onPressed: () =>
                      context.go(RoutePaths.adminReportDetailFor(other.id)),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    DisplayId.report(other.id),
                    style: AppTextStyles.monoIdentifier.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(other.title, style: AppTextStyles.fieldValue),
                ),
                StatusChip.report(other.status),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${other.reporterName} · ${reasons.join(' · ')}',
              style: AppTextStyles.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (plan != null)
                  FilledButton(
                    onPressed: _busy ? null : () => _merge(plan),
                    child: Text(
                      plan.duplicate.id == report.id
                          ? 'Merge this report into '
                                '${DisplayId.report(other.id)}'
                          : 'Merge ${DisplayId.report(other.id)} into this '
                                'report',
                    ),
                  )
                else
                  const Tooltip(
                    message:
                        'Both reports are past review, so neither can be '
                        'closed as a duplicate.',
                    child: FilledButton(onPressed: null, child: Text('Merge')),
                  ),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => ref
                              .read(reportReviewControllerProvider)
                              .keepSeparate(report.id, other.id),
                          'Kept separate from ${DisplayId.report(other.id)}.',
                        ),
                  child: const Text('Keep separate'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _describe(Duration apart) {
    if (apart.inMinutes < 60) {
      final minutes = apart.inMinutes;
      return minutes == 1 ? '1 minute' : '$minutes minutes';
    }
    if (apart.inHours < 48) {
      final hours = apart.inHours;
      return hours == 1 ? '1 hour' : '$hours hours';
    }
    return '${apart.inDays} days';
  }
}
