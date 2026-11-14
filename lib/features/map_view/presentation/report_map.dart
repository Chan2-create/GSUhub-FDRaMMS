import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_colors.dart';
import '../../damage_reports/data/models/damage_report.dart';
import 'widgets/geo_tag_map.dart';

/// Where a report says it is: its facility, then the requestor's own
/// words for the spot. The geo-tag is read together with these
/// (manuscript §2), never instead of them.
String placeOf(DamageReport report) {
  final parts = [
    if (report.facilityName case final name? when name.trim().isNotEmpty) name,
    if (report.locationDescription case final where?
        when where.trim().isNotEmpty && where != report.facilityName)
      where,
  ];
  return parts.isEmpty ? 'No location details given' : parts.join(' · ');
}

/// Geo-tagged damage reports as pins on the campus map: the same
/// OpenStreetMap tiles the faculty and staff app shows a geo-tag on, one
/// pin per report, at the coordinates its phone gave at submission.
///
/// Every report in [reports] must carry coordinates. With [interactive]
/// off the map is a still preview: no panning, no controls.
class ReportMap extends ConsumerStatefulWidget {
  const ReportMap({
    required this.reports,
    super.key,
    this.selectedId,
    this.onSelect,
    this.interactive = true,
  });

  final List<DamageReport> reports;

  /// The report whose pin is drawn selected; the map moves to it when
  /// this changes.
  final String? selectedId;

  /// Called with the report whose pin was pressed.
  final ValueChanged<DamageReport>? onSelect;

  final bool interactive;

  /// Close enough to tell one building from the next.
  static const double _closeZoom = 17;

  @override
  ConsumerState<ReportMap> createState() => _ReportMapState();
}

class _ReportMapState extends ConsumerState<ReportMap> {
  final _controller = MapController();

  static LatLng _pointOf(DamageReport report) =>
      LatLng(report.coordinates!.latitude, report.coordinates!.longitude);

  List<LatLng> get _points => [
    for (final report in widget.reports) _pointOf(report),
  ];

  /// Every pin in view. Null when they all share one point: there is no
  /// area to fit, so the map opens on that point instead.
  CameraFit? get _fitAll {
    final points = _points;
    if (points.toSet().length < 2) return null;
    return CameraFit.coordinates(
      coordinates: points,
      padding: const EdgeInsets.all(56),
      maxZoom: ReportMap._closeZoom,
    );
  }

  @override
  void didUpdateWidget(ReportMap old) {
    super.didUpdateWidget(old);
    final selected = widget.selectedId;
    if (selected == null || selected == old.selectedId) return;
    for (final report in widget.reports) {
      if (report.id != selected) continue;
      _controller.move(
        _pointOf(report),
        math.max(_controller.camera.zoom, ReportMap._closeZoom),
      );
      return;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showAll() {
    final fit = _fitAll;
    if (fit != null) {
      _controller.fitCamera(fit);
    } else if (_points.isNotEmpty) {
      _controller.move(_points.first, ReportMap._closeZoom);
    }
  }

  void _zoomBy(double steps) => _controller.move(
    _controller.camera.center,
    (_controller.camera.zoom + steps).clamp(_minZoom, _maxZoom),
  );

  static const double _minZoom = 3;
  static const double _maxZoom = 19;

  @override
  Widget build(BuildContext context) {
    final fit = _fitAll;
    final selectedId = widget.selectedId;
    // The selected pin is drawn last, over any pin it shares a spot with.
    final ordered = [
      for (final report in widget.reports)
        if (report.id != selectedId) report,
      for (final report in widget.reports)
        if (report.id == selectedId) report,
    ];

    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          // A still preview cannot be panned to a new pin, so it is
          // rebuilt around them whenever they change.
          key: widget.interactive ? null : ValueKey(_points.join('|')),
          mapController: _controller,
          options: MapOptions(
            initialCenter: _points.first,
            initialZoom: ReportMap._closeZoom,
            initialCameraFit: fit,
            minZoom: _minZoom,
            maxZoom: _maxZoom,
            interactionOptions: InteractionOptions(
              flags: widget.interactive
                  ? InteractiveFlag.all & ~InteractiveFlag.rotate
                  : InteractiveFlag.none,
            ),
          ),
          children: [
            ref.watch(mapTileLayerProvider),
            MarkerLayer(
              markers: [
                for (final report in ordered)
                  Marker(
                    point: _pointOf(report),
                    width: _Pin.width,
                    height: _Pin.height,
                    // The whole marker sits above its point, so the
                    // pin's tip, not its middle, marks the spot.
                    alignment: Alignment.topCenter,
                    child: _Pin(
                      report: report,
                      selected: report.id == selectedId,
                      onTap: widget.onSelect == null
                          ? null
                          : () => widget.onSelect!(report),
                    ),
                  ),
              ],
            ),
            const OsmAttribution(),
          ],
        ),
        if (widget.interactive)
          Positioned(
            top: 12,
            right: 12,
            child: _MapControls(
              onZoomIn: () => _zoomBy(1),
              onZoomOut: () => _zoomBy(-1),
              onShowAll: _showAll,
            ),
          ),
      ],
    );
  }
}

/// One report's pin: the design's map pin (`169:770`) in the console's
/// navy, gold and larger when selected, with a white edge so it reads
/// against the map either way.
class _Pin extends StatelessWidget {
  const _Pin({required this.report, required this.selected, this.onTap});

  final DamageReport report;
  final bool selected;
  final VoidCallback? onTap;

  static const double width = 44;
  static const double height = 50;

  @override
  Widget build(BuildContext context) {
    final pinHeight = selected ? 44.0 : 34.0;
    final pinWidth = pinHeight * 24 / 30;
    Widget pin(Color color, double grow) => SvgPicture.asset(
      'assets/icons/map_pin.svg',
      width: pinWidth + grow,
      height: pinHeight + grow,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );

    final drawn = Align(
      alignment: Alignment.bottomCenter,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          pin(AppColors.surface, 5),
          Padding(
            padding: const EdgeInsets.only(bottom: 2.5),
            child: pin(selected ? AppColors.accentGold : AppColors.primary, 0),
          ),
        ],
      ),
    );

    final label = '${report.title}, ${placeOf(report)}';
    if (onTap == null) {
      return Semantics(label: label, image: true, child: drawn);
    }
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: 'Report on the map: $label',
        excludeSemantics: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: drawn,
          ),
        ),
      ),
    );
  }
}

/// Zoom in, zoom out, and back to every pin: the map answers the mouse
/// wheel and a drag too, but not everyone has either.
class _MapControls extends StatelessWidget {
  const _MapControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onShowAll,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    elevation: 2,
    borderRadius: BorderRadius.circular(8),
    clipBehavior: Clip.antiAlias,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Zoom in',
          onPressed: onZoomIn,
          icon: const Icon(Icons.add, color: AppColors.textSecondary),
        ),
        const SizedBox(
          width: 28,
          child: Divider(height: 1, color: AppColors.border),
        ),
        IconButton(
          tooltip: 'Zoom out',
          onPressed: onZoomOut,
          icon: const Icon(Icons.remove, color: AppColors.textSecondary),
        ),
        const SizedBox(
          width: 28,
          child: Divider(height: 1, color: AppColors.border),
        ),
        IconButton(
          tooltip: 'Show every pin',
          onPressed: onShowAll,
          icon: const Icon(
            Icons.zoom_out_map,
            size: 20,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    ),
  );
}
