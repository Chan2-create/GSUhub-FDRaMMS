import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/breakpoints.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/utils/display_id.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/category_chip.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/priority_chip.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_chip.dart';
import '../../damage_reports/data/models/damage_report.dart';
import 'report_map.dart';
import 'report_map_providers.dart';

/// Map View: the geo-tagged damage reports, each a pin where its phone
/// said it was when the report was filed.
///
/// The manuscript has no Map View section, so this page does only what
/// its geo-tagging passages describe (§1.5; §2 "Geo-Tagging and
/// Location-Based Reporting"): coordinates captured at submission help
/// administrators "pinpoint concerns across large campus areas or when a
/// written description is unclear", and are "combined with the facility
/// name, location description, photo evidence, and QR code identification"
/// as "a supplementary reference for verification and response". A pin
/// therefore opens exactly those details and leads to the report, where
/// the review and the assignment already happen. No density, routes,
/// live positions or anything else the manuscript does not name.
///
/// No design was consulted for the layout (docs/architecture_decisions.md
/// §25): it is built from the console's shared widgets.
class ReportMapScreen extends ConsumerWidget {
  const ReportMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final includeFinished = ref.watch(mapIncludesFinishedProvider);
    return SingleChildScrollView(
      padding: EdgeInsets.all(Breakpoints.gutter(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            heading: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Map View', style: AppTextStyles.pageTitle),
                SizedBox(height: 4),
                Text(
                  'Where geo-tagged damage reports were filed, to help '
                  'locate a concern on campus.',
                  style: AppTextStyles.pageSubtitle,
                ),
              ],
            ),
            action: FilterChip(
              label: const Text('Finished reports'),
              tooltip: includeFinished
                  ? 'Back to open reports only'
                  : 'Also show completed, closed and rejected reports',
              selected: includeFinished,
              onSelected: ref.read(mapIncludesFinishedProvider.notifier).set,
            ),
          ),
          const SizedBox(height: 24),
          AsyncValueView<ReportMapData>(
            value: ref.watch(reportMapProvider),
            loadingHeight: 320,
            data: (data) =>
                _MapAndReports(data: data, includeFinished: includeFinished),
          ),
        ],
      ),
    );
  }
}

class _MapAndReports extends ConsumerWidget {
  const _MapAndReports({required this.data, required this.includeFinished});

  final ReportMapData data;
  final bool includeFinished;

  /// From this width the reports sit beside the map instead of under it.
  static const double _sideBySide = 1000;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedMapReportProvider);
    // A selection that has left the map (finished, archived, or the
    // filter changed) is no selection.
    final selected = data.located
        .where((report) => report.id == selectedId)
        .firstOrNull;
    final selection = ref.read(selectedMapReportProvider.notifier);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _sideBySide;
        final height = wide ? 600.0 : 380.0;

        final map = _MapCard(
          height: height,
          child: data.located.isEmpty
              ? _NothingOnTheMap(includeFinished: includeFinished)
              : ReportMap(
                  reports: data.located,
                  selectedId: selected?.id,
                  onSelect: (report) => selection.select(report.id),
                ),
        );
        final panel = data.located.isEmpty
            ? null
            : selected == null
            ? _ReportList(
                reports: data.located,
                includeFinished: includeFinished,
                scrolls: wide,
                onSelect: (report) => selection.select(report.id),
              )
            : _SelectedReport(
                report: selected,
                scrolls: wide,
                onBack: () => selection.select(null),
              );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (panel == null)
              map
            else if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: map),
                  const SizedBox(width: 24),
                  SizedBox(width: 380, height: height, child: panel),
                ],
              )
            else ...[
              map,
              const SizedBox(height: 24),
              panel,
            ],
            const SizedBox(height: 16),
            _Notes(data: data, includeFinished: includeFinished),
          ],
        );
      },
    );
  }
}

/// The map's frame: the console's card border around the tiles.
class _MapCard extends StatelessWidget {
  const _MapCard({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

class _NothingOnTheMap extends StatelessWidget {
  const _NothingOnTheMap({required this.includeFinished});

  final bool includeFinished;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.map_outlined, size: 40, color: AppColors.textFaint),
          const SizedBox(height: 12),
          Text(
            includeFinished
                ? 'No report has a geo-tag to show yet.'
                : 'No open report has a geo-tag to show.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall,
          ),
        ],
      ),
    ),
  );
}

String _countLabel(int count, {required bool includeFinished}) {
  final kind = includeFinished ? 'report' : 'open report';
  return '$count $kind${count == 1 ? '' : 's'} with a geo-tag';
}

/// Every report on the map, newest first. Choosing one selects its pin.
class _ReportList extends StatelessWidget {
  const _ReportList({
    required this.reports,
    required this.includeFinished,
    required this.scrolls,
    required this.onSelect,
  });

  final List<DamageReport> reports;
  final bool includeFinished;

  /// Beside the map the list scrolls inside its card; under it, the page
  /// scrolls.
  final bool scrolls;
  final ValueChanged<DamageReport> onSelect;

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (final (index, report) in reports.indexed) ...[
        if (index > 0) const Divider(height: 1, color: AppColors.borderSubtle),
        _ReportRow(report: report, onTap: () => onSelect(report)),
      ],
    ];
    return SectionCard(
      title: 'Reports on the map',
      subtitle: _countLabel(reports.length, includeFinished: includeFinished),
      dividerUnderHeader: true,
      contentPadding: EdgeInsets.zero,
      child: scrolls
          ? ListView(children: rows)
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.report, required this.onTap});

  final DamageReport report;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Show ${report.title} on the map',
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              report.title,
              style: AppTextStyles.tableCellStrong,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              placeOf(report),
              style: AppTextStyles.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusChip.report(report.status),
                PriorityChip(
                  level: report.effectivePriority,
                  confirmed: report.isPriorityConfirmed,
                  dense: true,
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// What the manuscript reads a geo-tag together with (§2): the facility,
/// the requestor's location description and the photo evidence, with the
/// way into the report itself.
class _SelectedReport extends StatelessWidget {
  const _SelectedReport({
    required this.report,
    required this.scrolls,
    required this.onBack,
  });

  final DamageReport report;
  final bool scrolls;
  final VoidCallback onBack;

  static final _filed = DateFormat('MMM d, y · h:mm a');

  @override
  Widget build(BuildContext context) {
    final coordinates = report.coordinates!;
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(DisplayId.report(report.id), style: AppTextStyles.bodySmall),
        const SizedBox(height: 2),
        Text(report.title, style: AppTextStyles.sectionTitle),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatusChip.report(report.status),
            PriorityChip(
              level: report.effectivePriority,
              confirmed: report.isPriorityConfirmed,
              dense: true,
            ),
            if (report.category case final category?)
              CategoryChip(category: category),
          ],
        ),
        const SizedBox(height: 20),
        _Field(
          label: 'Facility',
          value: report.facilityName ?? 'Not given',
          note: report.assetId == null
              ? null
              : 'Identified by its QR code on the equipment.',
        ),
        const SizedBox(height: 14),
        _Field(
          label: 'Location description',
          value: report.locationDescription ?? 'Not given',
        ),
        const SizedBox(height: 14),
        _Field(
          label: 'Geo-tag',
          value:
              '${coordinates.latitude.toStringAsFixed(5)}, '
              '${coordinates.longitude.toStringAsFixed(5)}',
        ),
        const SizedBox(height: 14),
        _Field(
          label: 'Reported',
          value:
              '${report.reporterName} · '
              '${_filed.format(report.submittedAt.toLocal())}',
        ),
        const SizedBox(height: 14),
        const Text('PHOTO EVIDENCE', style: AppTextStyles.fieldLabel),
        const SizedBox(height: 6),
        _Photos(urls: report.photoUrls),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () =>
                context.go(RoutePaths.adminReportDetailFor(report.id)),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textOnDark,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: const Text('Open report', style: AppTextStyles.ctaLabel),
          ),
        ),
      ],
    );

    return SectionCard(
      title: 'Selected report',
      dividerUnderHeader: true,
      trailing: TextButton.icon(
        onPressed: onBack,
        icon: const Icon(Icons.arrow_back, size: 16),
        label: const Text('All reports'),
      ),
      contentPadding: scrolls ? EdgeInsets.zero : const EdgeInsets.all(24),
      child: scrolls
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: details,
            )
          : details,
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value, this.note});

  final String label;
  final String value;
  final String? note;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label.toUpperCase(), style: AppTextStyles.fieldLabel),
      const SizedBox(height: 4),
      Text(value, style: AppTextStyles.fieldValue),
      if (note != null) ...[
        const SizedBox(height: 2),
        Text(note!, style: AppTextStyles.bodySmall),
      ],
    ],
  );
}

/// The first photos of the report, small: enough to recognise the spot.
/// The report page shows them all.
class _Photos extends StatelessWidget {
  const _Photos({required this.urls});

  final List<String> urls;

  static const int _shown = 2;

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) {
      return const Text(
        'No photos were attached to this report.',
        style: AppTextStyles.bodySmall,
      );
    }
    final more = urls.length - _shown;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final url in urls.take(_shown))
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              url,
              width: 120,
              height: 90,
              fit: BoxFit.cover,
              semanticLabel: 'Photo evidence',
              errorBuilder: (context, error, stack) => Container(
                width: 120,
                height: 90,
                color: AppColors.surfaceMuted,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.broken_image_outlined,
                  color: AppColors.textFaint,
                ),
              ),
            ),
          ),
        if (more > 0) Text('+$more more', style: AppTextStyles.bodySmall),
      ],
    );
  }
}

/// How far to trust a pin, in the manuscript's terms, and what is not on
/// the map at all.
class _Notes extends StatelessWidget {
  const _Notes({required this.data, required this.includeFinished});

  final ReportMapData data;
  final bool includeFinished;

  @override
  Widget build(BuildContext context) {
    final missing = data.withoutGeoTag;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: 1, right: 8),
              child: Icon(
                Icons.info_outline,
                size: 16,
                color: AppColors.textMuted,
              ),
            ),
            Expanded(
              child: Text(
                'A pin is the phone\'s location when the report was filed. '
                'It can be off inside buildings or where the signal is '
                'weak, so read it together with the facility, the location '
                'description and the photos.',
                style: AppTextStyles.bodySmall,
              ),
            ),
          ],
        ),
        if (missing > 0) ...[
          const SizedBox(height: 8),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 24),
                child: Text(
                  '$missing ${includeFinished ? '' : 'open '}'
                  'report${missing == 1 ? ' was' : 's were'} filed without '
                  'a geo-tag and ${missing == 1 ? 'is' : 'are'} not on the '
                  'map.',
                  style: AppTextStyles.bodySmall,
                ),
              ),
              TextButton(
                onPressed: () => context.go(RoutePaths.adminReports),
                child: const Text('See all reports'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
