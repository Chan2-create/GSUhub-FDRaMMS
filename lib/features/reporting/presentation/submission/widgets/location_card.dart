import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_text_styles.dart';
import '../../../../../core/utils/result.dart';
import '../../../../../core/widgets/filter_select.dart';
import '../../../../facilities/data/models/facility.dart';
import '../../../../facilities/presentation/facility_directory.dart';
import '../report_form_controller.dart';
import '../report_form_state.dart';
import 'form_parts.dart';
import 'geo_tag_map.dart';

/// The gold location panel (Figma `169:800`): BUILDING and ROOM, then the
/// GPS geo-tag with its map.
class LocationCard extends ConsumerWidget {
  const LocationCard({required this.form, super.key});

  final ReportFormState form;

  /// Appended to the building on the place line — "Engineering Building,
  /// DOrSU" (`169:773`). Every registered facility is on the one campus.
  static const String campus = 'DOrSU';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(reportFormControllerProvider.notifier);
    final directory = ref.watch(facilityDirectoryProvider);
    final enabled = !form.isLocked;

    return FormCard(
      color: AppColors.accentGold,
      padding: const EdgeInsets.fromLTRB(9, 12, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FacilitySelects(
            directory: directory,
            form: form,
            enabled: enabled,
            onBuilding: controller.selectBuilding,
            onRoom: controller.selectRoom,
            onRetry: () => ref.invalidate(facilityDirectoryProvider),
          ),
          const SizedBox(height: 24),
          _GpsRow(
            enabled: form.geoTagEnabled,
            onChanged: enabled
                ? (on) => controller.setGeoTag(enabled: on)
                : null,
          ),
          ..._geoTag(context, ref, controller, enabled),
        ],
      ),
    );
  }

  List<Widget> _geoTag(
    BuildContext context,
    WidgetRef ref,
    ReportFormController controller,
    bool enabled,
  ) {
    switch (form.geoTagStatus) {
      case GeoTagStatus.off:
        return const [];
      case GeoTagStatus.locating:
        return const [SizedBox(height: 12), GeoTagLocating()];
      case GeoTagStatus.unavailable:
        return [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              form.geoTagMessage ?? "Couldn't read your location.",
              style: AppTextStyles.coordinates.copyWith(
                color: AppColors.errorOnGold,
              ),
            ),
          ),
          if (enabled)
            _Link(label: 'Try again', onTap: controller.refreshLocation),
        ];
      case GeoTagStatus.attached:
        final point = form.coordinates!;
        Future<void> adjust() async {
          final moved = await ref.read(mapPinLauncherProvider)(context, point);
          if (moved != null) controller.pinLocation(moved);
        }

        final building = form.building;
        return [
          const SizedBox(height: 12),
          GeoTagMapPreview(point: point, onTap: enabled ? adjust : null),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (building != null) ...[
                  Text('$building, $campus', style: AppTextStyles.placeName),
                  const SizedBox(height: 4),
                ],
                Text(
                  'Lat: ${point.latitude.toStringAsFixed(4)}, '
                  'Long: ${point.longitude.toStringAsFixed(4)}',
                  style: AppTextStyles.coordinates,
                ),
              ],
            ),
          ),
          if (enabled)
            _Link(label: 'Tap to adjust location on map', onTap: adjust),
        ];
    }
  }
}

class _FacilitySelects extends StatelessWidget {
  const _FacilitySelects({
    required this.directory,
    required this.form,
    required this.enabled,
    required this.onBuilding,
    required this.onRoom,
    required this.onRetry,
  });

  final AsyncValue<Result<FacilityDirectory>> directory;
  final ReportFormState form;
  final bool enabled;
  final ValueChanged<String> onBuilding;
  final ValueChanged<Facility> onRoom;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    // Loading, failed, empty and ready all keep the two selects in place,
    // so the panel does not jump as the list arrives.
    final loaded = switch (directory) {
      AsyncData(value: Success(:final value)) => value,
      _ => null,
    };
    final failed = switch (directory) {
      AsyncData(value: Error(:final failure)) => failure.message,
      AsyncError() => "Couldn't load the buildings.",
      _ => null,
    };
    final isLoading = directory.isLoading && loaded == null && failed == null;

    final buildingHint = isLoading
        ? 'Loading…'
        : failed != null
        ? 'Unavailable'
        : loaded != null && loaded.isEmpty
        ? 'None registered'
        : 'Select Building';

    final building = form.building;
    final rooms = loaded == null || building == null
        ? const <Facility>[]
        : loaded.roomsIn(building);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldPair(
          left: LabelledField(
            label: 'Building',
            labelColor: Colors.black,
            errorColor: AppColors.errorOnGold,
            error: form.errorFor(ReportField.building),
            field: FilterSelect<String>(
              style: FilterSelectStyle.form,
              placeholder: buildingHint,
              enabled: enabled && loaded != null && !loaded.isEmpty,
              value: building,
              options: [
                // A building a QR scan chose is kept even when the list has
                // not loaded, so the field never shows less than is known.
                for (final name in {...?loaded?.buildings, ?building})
                  FilterOption(value: name, label: name),
              ],
              onChanged: (name) {
                if (name != null) onBuilding(name);
              },
            ),
          ),
          right: LabelledField(
            label: 'Room',
            labelColor: Colors.black,
            errorColor: AppColors.errorOnGold,
            error: form.errorFor(ReportField.room),
            field: FilterSelect<Facility>(
              style: FilterSelectStyle.form,
              placeholder: 'Select Room',
              enabled: enabled && rooms.isNotEmpty,
              value: form.facility,
              options: [
                for (final room in {...rooms, ?form.facility})
                  FilterOption(
                    value: room,
                    label: FacilityDirectory.roomLabelOf(room),
                  ),
              ],
              onChanged: (room) {
                if (room != null) onRoom(room);
              },
            ),
          ),
        ),
        if (failed != null) ...[
          FieldError(failed, color: AppColors.errorOnGold),
          Align(
            alignment: Alignment.centerLeft,
            child: _Link(label: 'Try again', onTap: onRetry),
          ),
        ],
        if (form.asset case final asset?)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 6),
            child: Text(
              'Equipment: ${asset.name}',
              style: AppTextStyles.coordinates.copyWith(color: Colors.black),
            ),
          ),
      ],
    );
  }
}

class _GpsRow extends StatelessWidget {
  const _GpsRow({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SvgPicture.asset('assets/icons/report_gps.svg', width: 16, height: 20),
      const SizedBox(width: 8),
      const Expanded(
        child: Text('GPS LOCATION', style: AppTextStyles.gpsLabel),
      ),
      Semantics(
        toggled: enabled,
        label: 'Auto-capture GPS location',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onChanged == null ? null : () => onChanged!(!enabled),
          child: Row(
            children: [
              const Text('AUTO-CAPTURE', style: AppTextStyles.autoCaptureLabel),
              const SizedBox(width: 8),
              _Toggle(on: enabled),
            ],
          ),
        ),
      ),
    ],
  );
}

/// The design's 40 x 20 switch (`169:764`).
class _Toggle extends StatelessWidget {
  const _Toggle({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 150),
    width: 40,
    height: 20,
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: on ? AppColors.toggleOnTrack : AppColors.toggleOffTrack,
      borderRadius: BorderRadius.circular(9999),
    ),
    child: AnimatedAlign(
      duration: const Duration(milliseconds: 150),
      alignment: on ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: 16,
        height: 16,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    ),
  );
}

/// An underlined action line (`169:777`).
class _Link extends StatelessWidget {
  const _Link({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(label, style: AppTextStyles.mapLink),
      ),
    ),
  );
}
