import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/routing/route_paths.dart';
import '../../../../core/utils/display_id.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../../shells/requestor/requestor_shell.dart';
import '../../../../shells/requestor/requestor_title_row.dart';
import '../../data/models/damage_report.dart';
import 'my_reports_providers.dart';
import 'widgets/report_pills.dart';

/// One of the requestor's reports, read-only: what they submitted
/// (Objective 3.A).
///
/// Not in the design, which has no such page for faculty and staff; laid
/// out from My Reports' own card and type, and flagged. The status history
/// timeline is Objective 3.B's.
class MyReportDetailScreen extends ConsumerWidget {
  const MyReportDetailScreen({required this.reportId, super.key});

  final String reportId;

  static final DateFormat _when = DateFormat('MMM d, y · h:mm a');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(myReportProvider(reportId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RequestorTitleRow(
          title: 'Report Details',
          onBack: () => context.canPop()
              ? context.pop()
              : context.go(RoutePaths.staffMyReports),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              24,
              16,
              24,
              requestorBottomInset(context),
            ),
            children: [
              AsyncValueView<DamageReport>(
                value: report,
                onRetry: () => ref.invalidate(myReportProvider(reportId)),
                data: (report) => _Details(report: report),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.report});

  final DamageReport report;

  @override
  Widget build(BuildContext context) {
    final coordinates = report.coordinates;
    final suggested = report.requestorCategory;
    final confirmed = report.category;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          children: [
            Text(reportPlaceOf(report), style: AppTextStyles.myReportsLocation),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                if (shownCategoryOf(report) case final category?)
                  MyReportsCategoryPill(category: category),
                StatusChip.requestor(report.status, large: true),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Submitted: '
              '${MyReportDetailScreen._when.format(report.submittedAt.toLocal())}',
              style: AppTextStyles.myReportsSubmitted,
            ),
            Text(
              'Report ${DisplayId.report(report.id)}',
              style: AppTextStyles.myReportsSubmitted,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Card(
          children: [
            _Field(label: 'TITLE', value: report.title),
            _Field(label: 'DESCRIPTION', value: report.description),
            _Field(
              label: 'URGENCY YOU GAVE',
              value: _sentence(report.requestorPriority.label),
            ),
            if (suggested != null)
              _Field(
                label: 'DAMAGE TYPE YOU SUGGESTED',
                value: suggested.label,
              ),
            if (confirmed != null)
              _Field(label: 'CONFIRMED DAMAGE TYPE', value: confirmed.label),
            if (report.facilityName case final facility?)
              _Field(label: 'BUILDING', value: facility),
            if (coordinates != null)
              _Field(
                label: 'GPS LOCATION',
                value:
                    'Lat: ${coordinates.latitude.toStringAsFixed(4)}, '
                    'Long: ${coordinates.longitude.toStringAsFixed(4)}',
              ),
          ],
        ),
        if (report.photoUrls.isNotEmpty) ...[
          const SizedBox(height: 16),
          _Card(
            children: [
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
          ),
        ],
      ],
    );
  }

  static String _sentence(String text) =>
      text[0] + text.substring(1).toLowerCase();
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  // Clipped rather than given a border radius: Flutter draws a one-sided
  // border only on a square box.
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: AppColors.accentGold, width: 4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
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
