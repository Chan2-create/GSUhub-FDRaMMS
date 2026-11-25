import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/utils/display_id.dart';
import '../../../core/utils/result.dart';
import '../../../core/widgets/status_chip.dart';
import '../../damage_reports/data/models/damage_report.dart';
import '../../damage_reports/presentation/report_review_controller.dart';
import '../domain/duplicate_detector.dart';
import 'classification_providers.dart';

/// Reports that may describe the same damage as this one, and what an
/// administrator can do about each: merge them, or keep them separate
/// (manuscript §3.4; Objective 4.C).
///
/// On a report already merged, says which report it was merged into.
///
/// **Compact since 2026-11-26.** It sits in the report page's narrow side
/// column, folded: "2 possible duplicates", opening to the list and its
/// actions. With none found, or while they are being looked for, it takes
/// no space at all. [gapBelow] is the space it leaves under itself when
/// it shows, so the column needs no gap of its own for it.
class PossibleDuplicatesCard extends ConsumerWidget {
  const PossibleDuplicatesCard({
    required this.report,
    super.key,
    this.gapBelow = 16,
  });

  final DamageReport report;
  final double gapBelow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (report.duplicateOf case final parentId?) {
      return Padding(
        padding: EdgeInsets.only(bottom: gapBelow),
        child: _Frame(
          child: Row(
            children: [
              const Icon(
                Icons.call_merge,
                size: 18,
                color: AppColors.duplicateFlag,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Merged as a duplicate of ${DisplayId.report(parentId)}.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              TextButton(
                onPressed: () =>
                    context.go(RoutePaths.adminReportDetailFor(parentId)),
                child: const Text('Open'),
              ),
            ],
          ),
        ),
      );
    }
    if (!DuplicateDetector.isFlaggable(report)) return const SizedBox.shrink();

    return switch (ref.watch(duplicateCandidatesProvider(report.id))) {
      AsyncData(value: Success(:final value)) when value.isNotEmpty => Padding(
        padding: EdgeInsets.only(bottom: gapBelow),
        child: _FoldedDuplicates(report: report, candidates: value),
      ),
      // Could not be looked for: one line, with a way to try again.
      AsyncData(value: Error(:final failure)) => Padding(
        padding: EdgeInsets.only(bottom: gapBelow),
        child: _Frame(
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Possible duplicates could not be checked: '
                  '${failure.message}',
                  style: AppTextStyles.bodySmall,
                ),
              ),
              TextButton(
                onPressed: () => ref
                  ..invalidate(duplicateDetectionConfigProvider)
                  ..invalidate(duplicateFlagsProvider),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
      // None, or not known yet: nothing to take room for.
      _ => const SizedBox.shrink(),
    };
  }
}

/// The card's border, smaller than a section card's.
class _Frame extends StatelessWidget {
  const _Frame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.surface,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: child,
  );
}

/// "2 possible duplicates", folded; open, the list and what can be done
/// with each.
class _FoldedDuplicates extends StatefulWidget {
  const _FoldedDuplicates({required this.report, required this.candidates});

  final DamageReport report;
  final List<DuplicateCandidate> candidates;

  @override
  State<_FoldedDuplicates> createState() => _FoldedDuplicatesState();
}

class _FoldedDuplicatesState extends State<_FoldedDuplicates> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final count = widget.candidates.length;
    final label = '$count possible duplicate${count == 1 ? '' : 's'}';
    return _Frame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _open,
            label: label,
            excludeSemantics: true,
            child: InkWell(
              key: const ValueKey('possible-duplicates-toggle'),
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.content_copy_outlined,
                      size: 18,
                      color: AppColors.duplicateFlag,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        style: AppTextStyles.fieldValue.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      _open ? Icons.expand_less : Icons.expand_more,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_open) ...[
            const Text(
              'Same place, filed close together, with the same damage type '
              'or similar wording. Nothing is merged until you decide.',
              style: AppTextStyles.bodySmall,
            ),
            for (final candidate in widget.candidates) ...[
              const SizedBox(height: 10),
              _CandidateRow(report: widget.report, candidate: candidate),
            ],
            const SizedBox(height: 10),
          ],
        ],
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
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
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
                StatusChip.report(other.status),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              other.title,
              style: AppTextStyles.fieldValue,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              '${other.reporterName} · ${reasons.join(' · ')}',
              style: AppTextStyles.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
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
