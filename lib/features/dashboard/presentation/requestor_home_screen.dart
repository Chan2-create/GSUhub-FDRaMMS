import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/utils/relative_time.dart';
import '../../../core/utils/result.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../shells/requestor/requestor_shell.dart';
import '../../reporting/data/models/damage_report.dart';
import '../../reporting/presentation/my_reports/my_reports_providers.dart';
import '../../reporting/presentation/my_reports/widgets/report_pills.dart';
import '../../user_management/presentation/profile_providers.dart';

/// The faculty and staff home screen (Figma `170:2050`, Objective 3.A):
/// greeting, two quick actions, the reports overview, and the three most
/// recent reports.
///
/// Every figure is the signed-in requestor's own, read once — the mockup's
/// "James Landoy" and "8 Active • 2 In-Progress • 10 Completed" are
/// placeholders. Pull down to read again; live updates are 3.B's.
class RequestorHomeScreen extends ConsumerWidget {
  const RequestorHomeScreen({super.key});

  /// How many recent reports the home screen lists, as drawn.
  static const int recentCount = 3;

  Future<void> _refresh(WidgetRef ref) async {
    ref
      ..invalidate(myReportsProvider)
      ..invalidate(signedInProfileProvider);
    await ref.read(myReportsProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(myReportsProvider);

    return RefreshIndicator(
      onRefresh: () => _refresh(ref),
      child: ListView(
        padding: EdgeInsets.fromLTRB(9, 7, 11, requestorBottomInset(context)),
        children: [
          const _GreetingCard(),
          const SizedBox(height: 16),
          const _QuickActions(),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.only(left: 3, right: 2),
            child: _OverviewBanner(reports: reports),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 13, right: 2),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Recent Reports',
                    style: AppTextStyles.homeSectionTitle,
                  ),
                ),
                TextButton(
                  onPressed: () => context.go(RoutePaths.staffMyReports),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'View All',
                    style: AppTextStyles.homeViewAll,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: AsyncValueView<List<DamageReport>>(
              value: reports,
              isEmpty: (list) => list.isEmpty,
              emptyIcon: Icons.assignment_outlined,
              emptyMessage: 'No reports yet. Tap + to report facility damage.',
              onRetry: () => ref.invalidate(myReportsProvider),
              data: (list) => Column(
                children: [
                  for (final report in list.take(recentCount))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: _RecentReportRow(report: report),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
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

/// Submit Damage Report (gold) and My Reports (navy), `169:628`/`169:629`.
class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 116,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _ActionTile(
            label: 'Submit Damage\nReport',
            icon: Icons.warning_rounded,
            color: AppColors.accentGold,
            onTap: () => context.push(RoutePaths.staffSubmitReport),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionTile(
            label: 'My Reports',
            icon: Icons.assignment_rounded,
            color: AppColors.primary,
            onTap: () => context.go(RoutePaths.staffMyReports),
          ),
        ),
      ],
    ),
  );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: color,
    borderRadius: BorderRadius.circular(14),
    elevation: 2,
    shadowColor: const Color(0x40000000),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // The design's translucent white disc behind the glyph.
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Color(0x33FFFFFF),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: AppTextStyles.homeTile,
          ),
        ],
      ),
    ),
  );
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
                        const SizedBox(height: 7),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            if (category != null)
                              HomeCategoryPill(category: category),
                            StatusChip.requestor(report.status),
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
    const placeholder = ColoredBox(color: AppColors.reportThumbPlaceholder);
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
