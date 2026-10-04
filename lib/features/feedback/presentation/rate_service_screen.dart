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
import '../../../core/widgets/person_avatar.dart';
import '../../../shells/requestor/requestor_shell.dart';
import '../../../shells/requestor/requestor_title_row.dart';
import '../../reporting/data/models/damage_report.dart';
import '../../reporting/data/models/status_change.dart';
import '../../reporting/presentation/my_reports/my_reports_providers.dart';
import '../../reporting/presentation/my_reports/report_timeline.dart';
import '../../reporting/presentation/my_reports/widgets/report_pills.dart';
import '../data/models/service_feedback.dart';
import 'rating_controller.dart';
import 'widgets/rating_summary.dart';
import 'widgets/star_rating.dart';

/// Ratings: the requestor rates the service on their completed report
/// (Figma 169:1797, Objective 3.C).
///
/// The design draws one star row. The manuscript asks for three judgements —
/// response time, service quality and overall satisfaction (§1.5, §1.7) —
/// so, as Chris chose, the screen asks each in the drawn style. Submitting
/// closes the report; Skip leaves it completed, and the detail page keeps
/// offering the rating.
class RateServiceScreen extends ConsumerWidget {
  const RateServiceScreen({required this.reportId, super.key});

  final String reportId;

  void _leave(BuildContext context) => context.canPop()
      ? context.pop()
      : context.go(RoutePaths.staffReportDetailFor(reportId));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(
      ratingControllerProvider(reportId).select((state) => state.submitted),
      (_, submitted) {
        if (!submitted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Thank you. Your rating was sent to GSU.'),
            ),
          );
        _leave(context);
      },
    );

    final report = ref.watch(myReportProvider(reportId));
    final feedback = ref.watch(reportFeedbackProvider(reportId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RequestorTitleRow(title: 'Ratings', onBack: () => _leave(context)),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              14,
              16,
              14,
              requestorBottomInset(context),
            ),
            children: [
              AsyncValueView<DamageReport>(
                value: report,
                onRetry: () => ref.invalidate(myReportProvider(reportId)),
                data: (report) => AsyncValueView<ServiceFeedback?>(
                  value: feedback,
                  onRetry: () =>
                      ref.invalidate(reportFeedbackProvider(reportId)),
                  data: (rating) => _Body(
                    report: report,
                    rating: rating,
                    onLeave: () => _leave(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.report,
    required this.rating,
    required this.onLeave,
  });

  final DamageReport report;
  final ServiceFeedback? rating;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(myReportHistoryProvider(report.id));
    final changes = switch (history.value) {
      Success(:final value) => value,
      _ => const <StatusChange>[],
    };
    final timeline = ReportTimeline.of(report, changes);

    final rating = this.rating;
    final Widget below;
    if (rating != null) {
      below = _AlreadyRated(rating: rating, onLeave: onLeave);
    } else if (report.status != ReportStatus.completed) {
      below = _NotYet(report: report, onLeave: onLeave);
    } else {
      below = _RatingForm(reportId: report.id, onSkip: onLeave);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _JobCard(report: report, timeline: timeline),
        const SizedBox(height: 28),
        below,
      ],
    );
  }
}

/// The finished job (`169:1797`, top card): work order and date, the
/// building, the room and type, and who did the work.
class _JobCard extends StatelessWidget {
  const _JobCard({required this.report, required this.timeline});

  final DamageReport report;
  final ReportTimeline timeline;

  static final DateFormat _date = DateFormat('MMM d, y');

  @override
  Widget build(BuildContext context) {
    final workOrderId = report.workOrderId;
    final finished = timeline.entries
        .where((entry) => entry.status == ReportStatus.completed)
        .firstOrNull;
    final room = roomOf(report);
    final category = confirmedCategoryOf(report);
    final place = [?room, ?category?.label].join(' • ');
    final assignment = timeline.assignment;
    final person = assignment?.personnelName;
    final trade = assignment?.personnelSpecialization;

    return DecoratedBox(
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
              top: BorderSide(color: AppColors.accentGold, width: 4),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        workOrderId == null
                            ? DisplayId.report(report.id)
                            : DisplayId.workOrder(workOrderId),
                        style: AppTextStyles.ratingMeta,
                      ),
                    ),
                    Text(
                      _date.format(
                        (finished?.at ?? report.updatedAt).toLocal(),
                      ),
                      style: AppTextStyles.ratingMeta,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  report.facilityName ?? report.title,
                  style: AppTextStyles.trackingTitle,
                ),
                if (place.isNotEmpty)
                  Text(place, style: AppTextStyles.ratingRoom),
                if (person != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      PersonAvatar(fullName: person, size: 32),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(person, style: AppTextStyles.ratingPerson),
                      ),
                      if (trade != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.linkIndigo,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.handyman_outlined,
                                size: 11,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                trade.label,
                                style: AppTextStyles.ratingTrade,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RatingForm extends ConsumerStatefulWidget {
  const _RatingForm({required this.reportId, required this.onSkip});

  final String reportId;
  final VoidCallback onSkip;

  @override
  ConsumerState<_RatingForm> createState() => _RatingFormState();
}

class _RatingFormState extends ConsumerState<_RatingForm> {
  final _comments = TextEditingController();

  @override
  void dispose() {
    _comments.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = ratingControllerProvider(widget.reportId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final error = state.errorMessage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'How would you rate the service?',
          textAlign: TextAlign.center,
          style: AppTextStyles.ratingQuestion,
        ),
        for (final dimension in RatingDimension.values) ...[
          const SizedBox(height: 20),
          Text(
            dimension.label,
            textAlign: TextAlign.center,
            style: AppTextStyles.ratingDimension,
          ),
          const SizedBox(height: 4),
          Center(
            child: StarRating(
              value: state.starsFor(dimension),
              label: dimension.label,
              onChanged: (stars) => controller.setStars(dimension, stars),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            state.starsFor(dimension) == 0
                ? dimension.hint
                : ratingWord(state.starsFor(dimension)),
            textAlign: TextAlign.center,
            style: state.starsFor(dimension) == 0
                ? AppTextStyles.ratingComment.copyWith(
                    color: AppColors.warmMuted,
                  )
                : AppTextStyles.ratingWord,
          ),
        ],
        const SizedBox(height: 28),
        const Text('Comments', style: AppTextStyles.ratingCommentsLabel),
        const SizedBox(height: 8),
        TextField(
          controller: _comments,
          onChanged: controller.setComments,
          enabled: !state.isSubmitting,
          minLines: 4,
          maxLines: 6,
          maxLength: RatingController.commentLimit,
          textCapitalization: TextCapitalization.sentences,
          style: AppTextStyles.ratingComment,
          decoration: InputDecoration(
            hintText: 'Share your feedback...',
            hintStyle: AppTextStyles.ratingComment.copyWith(
              color: AppColors.warmMuted,
            ),
            filled: true,
            fillColor: AppColors.ratingCommentFill,
            contentPadding: const EdgeInsets.all(16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          Text(
            error,
            style: AppTextStyles.ratingComment.copyWith(color: AppColors.error),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: state.isComplete && !state.isSubmitting
              ? controller.submit
              : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accentGold,
            disabledBackgroundColor: AppColors.accentGold.withValues(
              alpha: 0.45,
            ),
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: state.isSubmitting
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : const Text('Submit Rating', style: AppTextStyles.ratingSubmit),
        ),
        if (!state.isComplete) ...[
          const SizedBox(height: 6),
          Text(
            'Rate all three to submit.',
            textAlign: TextAlign.center,
            style: AppTextStyles.ratingMeta.copyWith(
              color: AppColors.warmMuted,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: state.isSubmitting ? null : widget.onSkip,
            style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
            child: const Text('Skip', style: AppTextStyles.ratingSkip),
          ),
        ),
      ],
    );
  }
}

/// The report was rated already: what was given, read-only.
class _AlreadyRated extends StatelessWidget {
  const _AlreadyRated({required this.rating, required this.onLeave});

  final ServiceFeedback rating;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'You rated this service',
        textAlign: TextAlign.center,
        style: AppTextStyles.ratingQuestion,
      ),
      const SizedBox(height: 16),
      RatingSummary(rating: rating),
      const SizedBox(height: 16),
      Center(
        child: TextButton(
          onPressed: onLeave,
          style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
          child: const Text('Back', style: AppTextStyles.ratingSkip),
        ),
      ),
    ],
  );
}

/// Opened for a report that is not finished — a stale notification, or a
/// link. Nothing to rate yet.
class _NotYet extends StatelessWidget {
  const _NotYet({required this.report, required this.onLeave});

  final DamageReport report;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        'Only completed work can be rated. This report is '
        '${report.status.timelineLabel.toLowerCase()}.',
        textAlign: TextAlign.center,
        style: AppTextStyles.ratingComment,
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: onLeave,
        style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
        child: const Text('Back', style: AppTextStyles.ratingSkip),
      ),
    ],
  );
}
