import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_text_styles.dart';
import '../../../../../core/utils/result.dart';
import '../../../../../core/widgets/filter_select.dart';
import '../../../../facilities/data/models/facility.dart';
import '../../../../facilities/presentation/facility_directory.dart';
import '../../../../map_view/presentation/widgets/geo_tag_map.dart';
import '../report_form_controller.dart';
import '../report_form_state.dart';
import 'form_parts.dart';

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

  static const String _noneRegistered =
      'No buildings or rooms are registered yet, so a report cannot be '
      'filed. Please ask the GSU office to add them.';

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
    final noneRegistered = loaded != null && loaded.isEmpty;

    // Why a select will not open, said when it is pressed: a control
    // that ignored the press read as broken (2026-11-13, when the live
    // system's only room had been deleted). Null while it works, and
    // while the form is sending.
    final buildingBlocked = !enabled
        ? null
        : isLoading
        ? 'The buildings are still loading.'
        : failed != null
        ? "The buildings couldn't be loaded. Try again below."
        : noneRegistered
        ? _noneRegistered
        : null;
    final roomBlocked = !enabled || rooms.isNotEmpty
        ? null
        : buildingBlocked ??
              (building == null
                  ? 'Choose the building first.'
                  : 'No rooms are registered for $building.');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldPair(
          left: LabelledField(
            label: 'Building',
            labelColor: Colors.black,
            errorColor: AppColors.errorOnGold,
            error: form.errorFor(ReportField.building),
            field: _SaysWhyWhenBlocked(
              reason: buildingBlocked,
              child: FilterSelect<String>(
                style: FilterSelectStyle.form,
                placeholder: buildingHint,
                enabled: enabled && loaded != null && !loaded.isEmpty,
                value: building,
                options: [
                  // A building a QR scan chose is kept even when the list
                  // has not loaded, so the field never shows less than is
                  // known.
                  for (final name in {...?loaded?.buildings, ?building})
                    FilterOption(value: name, label: name),
                ],
                onChanged: (name) {
                  if (name != null) onBuilding(name);
                },
              ),
            ),
          ),
          right: LabelledField(
            label: 'Room',
            labelColor: Colors.black,
            errorColor: AppColors.errorOnGold,
            error: form.errorFor(ReportField.room),
            field: _SaysWhyWhenBlocked(
              reason: roomBlocked,
              child: FilterSelect<Facility>(
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
        ),
        // A report needs a registered room, so with none there is nothing
        // the requestor can do here: said plainly, not left to a greyed
        // box.
        if (noneRegistered) ...[
          const FieldError(_noneRegistered, color: AppColors.errorOnGold),
          Align(
            alignment: Alignment.centerLeft,
            child: _Link(label: 'Check again', onTap: onRetry),
          ),
        ],
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

/// A select that cannot open says why when it is pressed. With no
/// [reason] the select works, and this adds nothing.
class _SaysWhyWhenBlocked extends StatelessWidget {
  const _SaysWhyWhenBlocked({required this.reason, required this.child});

  final String? reason;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final why = reason;
    if (why == null) return child;
    return Semantics(
      button: true,
      hint: why,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(why))),
        child: child,
      ),
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
