import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/utils/relative_time.dart';
import '../../../core/utils/result.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../shells/requestor/requestor_shell.dart';
import '../../damage_reports/data/models/damage_report.dart';
import '../../damage_reports/presentation/my_reports/my_reports_providers.dart';
import '../../damage_reports/presentation/my_reports/widgets/report_pills.dart';
import '../../user_management/presentation/profile_providers.dart';

/// The faculty and staff home screen (Figma `170:2050`, Objective 3.A):
/// greeting, the reports overview, and the three most recent reports.
///
/// **2026-11-26:** no more Submit Damage Report and My Reports tiles, and
/// no View All: the bar's gold + opens the report form and its Reports tab
/// opens My Reports, so they were the same buttons twice. The overview
/// follows the greeting directly, with no gap where the tiles were.
///
/// Every figure is the signed-in requestor's own and live (3.B) — the
/// mockup's "James Landoy" and "8 Active • 2 In-Progress • 10 Completed"
/// are placeholders.
class RequestorHomeScreen extends ConsumerWidget {
  const RequestorHomeScreen({super.key});

  /// How many recent reports the home screen lists, as drawn.
  static const int recentCount = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(myReportsProvider);

    return ListView(
      // One gutter, 16, as every other phone page has, and one rhythm:
      // 16 between blocks, 8 within (2026-11-15, §39). The frame's own
      // offsets (9 and 11 at the edges, then 3, 13 and 2 more per block,
      // and gaps of 6, 7, 8 and 14) set this page's edges a few pixels
      // apart from each other.
      padding: EdgeInsets.fromLTRB(16, 12, 16, requestorBottomInset(context)),
      children: [
        const _GreetingCard(),
        const SizedBox(height: 16),
        _OverviewBanner(reports: reports),
        const SizedBox(height: 16),
        const Text('Recent Reports', style: AppTextStyles.homeSectionTitle),
        const SizedBox(height: 8),
        AsyncValueView<List<DamageReport>>(
          value: reports,
          isEmpty: (list) => list.isEmpty,
          emptyIcon: Icons.assignment_outlined,
          emptyMessage: 'No reports yet. Tap + to report facility damage.',
          onRetry: () => ref.invalidate(myReportsProvider),
          loading: Skeleton.cards(height: 72, gap: 8),
          data: (list) => Column(
            children: [
              for (final report in list.take(recentCount))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _RecentReportRow(report: report),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Hello, James Landoy / Faculty" beside a gold rule (`169:410`).
///
/// The design's second line reads "Faculty", but accounts do not record
/// faculty versus staff. It shows the person's department when they have
/// one — as an earlier version of this frame did — and "Faculty & Staff"
/// otherwise.
class _GreetingCard extends ConsumerWidget {
  const _GreetingCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = switch (ref.watch(signedInProfileProvider).value) {
      Success(:final value) => value,
      _ => null,
    };
    final name = person?.fullName;
    final department = person?.department?.trim();

    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 11),
          const SizedBox(
            width: 3,
            height: double.infinity,
            child: ColoredBox(color: AppColors.accentGold),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name == null ? 'Hello' : 'Hello, $name',
                  style: AppTextStyles.homeGreeting,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  department == null || department.isEmpty
                      ? 'Faculty & Staff'
                      : department,
                  style: AppTextStyles.homeRole,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

/// "Reports Overview" over the campus photo (`169:659`), with the
/// requestor's own counts.
///
/// The photo (`image 9`) has not been exported from Figma yet, so the
/// banner stands on the design's navy-to-purple wash alone until it is.
class _OverviewBanner extends StatelessWidget {
  const _OverviewBanner({required this.reports});

  final AsyncValue<Result<List<DamageReport>>> reports;

  @override
  Widget build(BuildContext context) {
    final summary = switch (reports.value) {
      Success(:final value) => ReportOverview.of(value).summary,
      Error() => 'Counts unavailable — pull down to try again.',
      null => 'Loading your reports…',
    };

    return Container(
      height: 165,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.primary, AppColors.bannerWash],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      alignment: Alignment.bottomLeft,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Reports Overview', style: AppTextStyles.bannerTitle),
          Text(summary, style: AppTextStyles.bannerCounts),
        ],
      ),
    );
  }
}

/// One recent report (`169:426`): the photo, where it is, its damage type
/// and stage, and how long ago it was filed. Opens the report.
class _RecentReportRow extends StatelessWidget {
  const _RecentReportRow({required this.report});

  final DamageReport report;

  @override
  Widget build(BuildContext context) {
    final category = shownCategoryOf(report);
    final accent = StatusChip.requestorColorOf(report.status);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => context.push(RoutePaths.staffReportDetailFor(report.id)),
        child: SizedBox(
          height: 73,
          child: Stack(
            children: [
              Row(
                children: [
                  const SizedBox(width: 12),
                  // The design's rule is a different colour on each row;
                  // here it follows the report's stage, like its chip.
                  SizedBox(
                    width: 3,
                    height: double.infinity,
                    child: ColoredBox(color: accent),
                  ),
                  const SizedBox(width: 10),
                  _Thumbnail(report: report),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 56),
                          child: Text(
                            reportPlaceOf(report),
                            style: AppTextStyles.homeRowLocation,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // 3, not the design's 7: the row is a fixed 73 tall,
                        // and the larger text of 2026-11-25 needs the room.
                        const SizedBox(height: 3),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            if (category != null)
                              HomeCategoryPill(category: category),
                            StatusChip.requestor(
                              report.status,
                              rescheduled: report.isRescheduled,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 11),
                ],
              ),
              Positioned(
                top: 5,
                right: 11,
                child: Text(
                  RelativeTime.stamp(report.submittedAt),
                  style: AppTextStyles.homeRowTime,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The report's first photo in the design's 43px square, or the square
/// alone when it has none.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.report});

  final DamageReport report;

  @override
  Widget build(BuildContext context) {
    // A faint picture mark, so a report with no photo (or one still
    // loading) does not read as a blank hole in the row.
    const placeholder = ColoredBox(
      color: AppColors.reportThumbPlaceholder,
      child: Center(
        child: Icon(Icons.image_outlined, size: 20, color: AppColors.textFaint),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox.square(
        dimension: 43,
        child: report.photoUrls.isEmpty
            ? placeholder
            : Image.network(
                report.photoUrls.first,
                fit: BoxFit.cover,
                semanticLabel: 'Photo of the damage',
                errorBuilder: (_, _, _) => placeholder,
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : placeholder,
              ),
      ),
    );
  }
}
