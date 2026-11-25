import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/breakpoints.dart';
import '../../../core/data/geo_coordinates.dart';
import '../../../core/di/repository_providers.dart';
import '../../../core/enums/item_condition.dart';
import '../../../core/errors/failures.dart';
import '../../../core/utils/result.dart';
import '../../../core/widgets/app_data_table.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/confirm_delete_dialog.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/section_card.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../../inventory/presentation/widgets/inventory_widgets.dart';
import '../../map_view/presentation/widgets/geo_tag_map.dart';
import '../../qr_codes/presentation/qr_label.dart';
import '../../qr_codes/presentation/qr_label_actions.dart';
import '../data/models/asset.dart';
import '../data/models/building.dart';
import '../data/models/facility.dart';
import '../data/models/facility_draft.dart';
import 'facility_directory.dart';

/// Every room, inactive ones included, by building then room.
final facilitiesProvider = StreamProvider.autoDispose<Result<List<Facility>>>(
  (ref) => ref.watch(facilityRepositoryProvider).watchFacilities(),
);

/// Every piece of equipment, inactive included.
final assetsProvider = StreamProvider.autoDispose<Result<List<Asset>>>(
  (ref) => ref.watch(facilityRepositoryProvider).watchAssets(),
);

/// Facilities & Equipment (Objective 6.C, Chris's decision 2026-10-13):
/// the rooms reports are filed against and the equipment in them, each
/// with the code on its sticker, and those stickers printed.
///
/// No Figma frame: built from the console's page title, section cards and
/// table, and flagged as such. Until this page, rooms were added to
/// Firestore by hand (docs/manual_deploy.md).
///
/// **2026-11-26:** the buildings are kept here too, each with its pin on
/// the map; a room is added to one, on a floor, with a pin of its own if
/// wanted. The report form lists them as entered here, and the Damage
/// Reports map draws the buildings' pins. Nothing is entered for the
/// administrator: the campus's buildings and rooms are theirs to add.
class FacilitiesScreen extends ConsumerWidget {
  const FacilitiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facilities = ref.watch(facilitiesProvider);
    final assets = ref.watch(assetsProvider);
    final buildingsValue = ref.watch(buildingsProvider);
    final buildings = switch (buildingsValue) {
      AsyncData(value: Success(:final value)) => value,
      _ => const <Building>[],
    };
    // The live database without the buildings migration (2026-11-26):
    // said plainly, and nothing offered that would fail the same way.
    final notUpdated = switch (buildingsValue) {
      AsyncData(value: Error(failure: DatabaseUpdateFailure())) => true,
      _ => false,
    };
    final rooms = switch (facilities) {
      AsyncData(value: Success(:final value)) => value,
      _ => const <Facility>[],
    };
    final equipment = switch (assets) {
      AsyncData(value: Success(:final value)) => value,
      _ => const <Asset>[],
    };
    final roomsById = {for (final room in rooms) room.id: room};

    return SingleChildScrollView(
      padding: EdgeInsets.all(Breakpoints.gutter(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: 'Facilities & Equipment',
            subtitle:
                'The buildings and rooms reports are filed against, the '
                'equipment in them, and the codes on their stickers.',
            action: PageActionButton(
              outlined: true,
              icon: const Icon(Icons.print_outlined, size: 18),
              label: 'Print all labels',
              onPressed: () => downloadQrLabels(
                context,
                ref,
                labels: [
                  for (final room in rooms)
                    if (room.isActive) QrLabel.facility(room),
                  for (final asset in equipment)
                    if (asset.isActive)
                      QrLabel.asset(asset, room: roomsById[asset.facilityId]),
                ],
                fileName: 'gsuhub-room-and-equipment-labels.pdf',
              ),
            ),
          ),
          const SizedBox(height: PageHeader.gapBelow),
          SectionCard(
            title: 'Buildings',
            subtitle:
                'The campus buildings, each with its pin on the Damage '
                'Reports map. Rooms are added to one.',
            trailing: FilledButton.icon(
              key: const ValueKey('add-building'),
              onPressed: notUpdated
                  ? null
                  : () => showBuildingFormDialog(context, buildings: buildings),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Building'),
              style: _consoleButton,
            ),
            contentPadding: EdgeInsets.zero,
            child: notUpdated
                ? _DatabaseUpdateNotice(
                    onRetry: () => ref.invalidate(buildingsProvider),
                  )
                : AsyncValueView<List<Building>>(
                    value: buildingsValue,
                    loadingHeight: 120,
                    onRetry: () => ref.invalidate(buildingsProvider),
                    data: (buildings) => buildings.isEmpty
                        ? const _Empty(
                            'No buildings yet. Add the campus’s buildings here, '
                            'then their rooms.',
                          )
                        : _BuildingsTable(buildings: buildings, rooms: rooms),
                  ),
          ),
          const SizedBox(height: 32),
          SectionCard(
            title: 'Rooms',
            subtitle:
                'Faculty and staff pick these on the report form, by '
                'building and room, or scan their stickers. An inactive room '
                'is left off the form.',
            // A room goes into a building, so the buildings come first.
            trailing: buildings.isEmpty
                ? Tooltip(
                    message: 'Add a building first.',
                    child: FilledButton.icon(
                      key: const ValueKey('add-room'),
                      onPressed: null,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Room'),
                      style: _consoleButton,
                    ),
                  )
                : FilledButton.icon(
                    key: const ValueKey('add-room'),
                    onPressed: () =>
                        showFacilityFormDialog(context, buildings: buildings),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Room'),
                    style: _consoleButton,
                  ),
            contentPadding: EdgeInsets.zero,
            child: AsyncValueView<List<Facility>>(
              value: facilities,
              loadingHeight: 200,
              onRetry: () => ref.invalidate(facilitiesProvider),
              data: (rooms) => rooms.isEmpty
                  ? const _Empty('No rooms yet. Add the campus’s rooms here.')
                  : _RoomsTable(
                      rooms: rooms,
                      buildings: buildings,
                      equipmentCount: {
                        for (final room in rooms)
                          room.id: equipment
                              .where((a) => a.facilityId == room.id)
                              .length,
                      },
                    ),
            ),
          ),
          const SizedBox(height: 32),
          SectionCard(
            title: 'Equipment',
            subtitle:
                'Installed equipment a report can name by its sticker: '
                'aircon units, projectors, fans.',
            trailing: FilledButton.icon(
              onPressed: rooms.isEmpty
                  ? null
                  : () => showAssetFormDialog(context, rooms: rooms),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Equipment'),
              style: _consoleButton,
            ),
            contentPadding: EdgeInsets.zero,
            child: AsyncValueView<List<Asset>>(
              value: assets,
              onRetry: () => ref.invalidate(assetsProvider),
              data: (equipment) => equipment.isEmpty
                  ? const _Empty('No equipment registered yet.')
                  : _EquipmentTable(assets: equipment, rooms: rooms),
            ),
          ),
        ],
      ),
    );
  }
}

/// The console's primary button, as Personnel's Add Personnel draws it.
final ButtonStyle _consoleButton = FilledButton.styleFrom(
  backgroundColor: AppColors.primary,
  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
);

/// In place of the buildings when the database has not had the update
/// that adds them (2026-11-26): what is wrong and who fixes it, not
/// PostgREST's "schema cache" wording.
class _DatabaseUpdateNotice extends StatelessWidget {
  const _DatabaseUpdateNotice({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('buildings-need-update'),
    padding: const EdgeInsets.all(24),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.system_update_alt, color: AppColors.accountPending),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Buildings are not set up on this system yet',
                style: AppTextStyles.fieldValue,
              ),
              const SizedBox(height: 4),
              const Text(
                'They need the latest database update, which has not been '
                'applied here. Until it is, buildings cannot be listed or '
                'added, and rooms cannot be added to them. The system '
                'administrator applies it with "npx supabase db push".',
                style: AppTextStyles.bodySmall,
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: onRetry, child: const Text('Check again')),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Text(
      message,
      style: AppTextStyles.pageSubtitle,
      textAlign: TextAlign.center,
    ),
  );
}

Widget _statusChip(bool active) => InventoryBadge(
  label: active ? 'ACTIVE' : 'INACTIVE',
  background: active ? AppColors.inventoryInStockFill : AppColors.surfaceSunken,
  foreground: active
      ? AppColors.inventoryInStockText
      : AppColors.inventoryLabel,
);

class _RoomsTable extends ConsumerWidget {
  const _RoomsTable({
    required this.rooms,
    required this.buildings,
    required this.equipmentCount,
  });

  final List<Facility> rooms;
  final List<Building> buildings;
  final Map<String, int> equipmentCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AppDataTable<Facility>(
    rows: rooms,
    columns: [
      AppTableColumn(
        label: 'Building',
        flex: 3,
        cell: (room) =>
            Text(room.buildingName, style: AppTextStyles.tableCellStrong),
      ),
      AppTableColumn(
        label: 'Room',
        flex: 3,
        cell: (room) =>
            Text(room.roomIdentifier ?? '—', style: AppTextStyles.tableCell),
      ),
      AppTableColumn(
        label: 'Floor',
        flex: 2,
        cell: (room) => Text(room.floor ?? '—', style: AppTextStyles.tableCell),
      ),
      AppTableColumn(
        label: 'Equipment',
        flex: 2,
        cell: (room) => Text(
          '${equipmentCount[room.id] ?? 0}',
          style: AppTextStyles.tableCell,
        ),
      ),
      AppTableColumn(
        label: 'Code',
        flex: 3,
        cell: (room) =>
            SelectableText(room.qrCode, style: AppTextStyles.monoIdentifier),
      ),
      AppTableColumn(
        label: 'Status',
        flex: 2,
        cell: (room) => _statusChip(room.isActive),
      ),
      AppTableColumn(
        label: 'Actions',
        flex: 3,
        alignment: Alignment.centerRight,
        cell: (room) => _RowActions(
          name: [room.buildingName, ?room.roomIdentifier].join(', '),
          active: room.isActive,
          onEdit: () =>
              showFacilityFormDialog(context, room: room, buildings: buildings),
          onLabel: () => showQrLabelDialog(context, QrLabel.facility(room)),
          onActive: (active) => ref
              .read(inventoryControllerProvider)
              .setFacilityActive(room.id, active: active),
          onDelete: () => _confirmDelete(
            context,
            name: [room.buildingName, ?room.roomIdentifier].join(', '),
            kind: 'room',
            // A report needs a registered room: with the last one gone
            // the report form has nothing to choose, and no report can
            // be filed (it happened on the live system, 2026-11-13).
            warning:
                room.isActive &&
                    rooms.where((other) => other.isActive).length == 1
                ? 'This is the only active room. Until another is added, '
                      'faculty and staff cannot file a report.'
                : null,
            delete: () =>
                ref.read(inventoryControllerProvider).deleteFacility(room.id),
          ),
        ),
      ),
    ],
  );
}

class _EquipmentTable extends ConsumerWidget {
  const _EquipmentTable({required this.assets, required this.rooms});

  final List<Asset> assets;
  final List<Facility> rooms;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roomsById = {for (final room in rooms) room.id: room};
    String roomName(String id) => switch (roomsById[id]) {
      final room? => [room.buildingName, ?room.roomIdentifier].join(', '),
      null => 'Unknown room',
    };
    return AppDataTable<Asset>(
      rows: assets,
      columns: [
        AppTableColumn(
          label: 'Equipment',
          flex: 3,
          cell: (asset) =>
              Text(asset.name, style: AppTextStyles.tableCellStrong),
        ),
        AppTableColumn(
          label: 'Room',
          flex: 3,
          cell: (asset) =>
              Text(roomName(asset.facilityId), style: AppTextStyles.tableCell),
        ),
        AppTableColumn(
          label: 'Condition',
          flex: 2,
          cell: (asset) =>
              Text(asset.condition.label, style: AppTextStyles.tableCell),
        ),
        AppTableColumn(
          label: 'Code',
          flex: 3,
          cell: (asset) =>
              SelectableText(asset.qrCode, style: AppTextStyles.monoIdentifier),
        ),
        AppTableColumn(
          label: 'Status',
          flex: 2,
          cell: (asset) => _statusChip(asset.isActive),
        ),
        AppTableColumn(
          label: 'Actions',
          flex: 3,
          alignment: Alignment.centerRight,
          cell: (asset) => _RowActions(
            name: asset.name,
            active: asset.isActive,
            onEdit: () =>
                showAssetFormDialog(context, rooms: rooms, asset: asset),
            onLabel: () => showQrLabelDialog(
              context,
              QrLabel.asset(asset, room: roomsById[asset.facilityId]),
            ),
            onActive: (active) => ref
                .read(inventoryControllerProvider)
                .setAssetActive(asset.id, active: active),
            onDelete: () => _confirmDelete(
              context,
              name: asset.name,
              kind: 'equipment',
              delete: () =>
                  ref.read(inventoryControllerProvider).deleteAsset(asset.id),
            ),
          ),
        ),
      ],
    );
  }
}

/// Edit, the sticker, deactivate or reactivate, and delete.
class _RowActions extends StatelessWidget {
  const _RowActions({
    required this.name,
    required this.active,
    required this.onEdit,
    required this.onLabel,
    required this.onActive,
    required this.onDelete,
  });

  final String name;
  final bool active;
  final VoidCallback onEdit;
  final VoidCallback onLabel;
  final Future<Result<void>> Function(bool active) onActive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        tooltip: 'Edit $name',
        onPressed: onEdit,
        icon: const Icon(Icons.edit_outlined, size: 20),
      ),
      IconButton(
        tooltip: 'QR label for $name',
        onPressed: onLabel,
        icon: const Icon(Icons.qr_code_2_outlined, size: 20),
      ),
      IconButton(
        tooltip: active ? 'Deactivate $name' : 'Reactivate $name',
        onPressed: () async {
          final result = await onActive(!active);
          if (context.mounted) {
            showInventoryOutcome(
              context,
              result,
              active ? 'Deactivated $name.' : 'Reactivated $name.',
            );
          }
        },
        icon: Icon(
          active ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          size: 20,
        ),
      ),
      IconButton(
        tooltip: 'Delete $name',
        onPressed: onDelete,
        icon: const Icon(Icons.delete_outline, size: 20),
      ),
    ],
  );
}

/// Asks before deleting a room or piece of equipment named [name], and
/// deletes it with [delete]. Refusals (open reports, equipment still in
/// the room) show in the dialog.
Future<bool> _confirmDelete(
  BuildContext context, {
  required String name,
  required String kind,
  required Future<Result<void>> Function() delete,
  String? warning,
}) => showConfirmDeleteDialog(
  context: context,
  title: 'Delete $name?',
  message:
      'It leaves the $kind list, the report form and the scanner. Reports '
      'about it keep its name, and its code can go on another $kind.'
      '${warning == null ? '' : '\n\n$warning'}',
  doneMessage: 'Deleted $name.',
  onConfirm: delete,
);

/// The buildings, with how many rooms each has and its pin (2026-11-26).
class _BuildingsTable extends ConsumerWidget {
  const _BuildingsTable({required this.buildings, required this.rooms});

  final List<Building> buildings;
  final List<Facility> rooms;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    int roomsIn(Building building) =>
        rooms.where((room) => room.buildingId == building.id).length;
    return AppDataTable<Building>(
      rows: buildings,
      columns: [
        AppTableColumn(
          label: 'Building',
          flex: 4,
          cell: (building) =>
              Text(building.name, style: AppTextStyles.tableCellStrong),
        ),
        AppTableColumn(
          label: 'Rooms',
          flex: 2,
          cell: (building) =>
              Text('${roomsIn(building)}', style: AppTextStyles.tableCell),
        ),
        AppTableColumn(
          label: 'Map pin',
          flex: 3,
          cell: (building) => Text(switch (building.coordinates) {
            final point? =>
              '${point.latitude.toStringAsFixed(5)}, '
                  '${point.longitude.toStringAsFixed(5)}',
            null => 'No pin',
          }, style: AppTextStyles.tableCell),
        ),
        AppTableColumn(
          label: 'Description',
          flex: 4,
          cell: (building) =>
              Text(building.description ?? '—', style: AppTextStyles.tableCell),
        ),
        AppTableColumn(
          label: 'Actions',
          flex: 2,
          alignment: Alignment.centerRight,
          cell: (building) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Edit ${building.name}',
                onPressed: () => showBuildingFormDialog(
                  context,
                  buildings: buildings,
                  building: building,
                ),
                icon: const Icon(Icons.edit_outlined, size: 20),
              ),
              IconButton(
                tooltip: 'Delete ${building.name}',
                onPressed: () => showConfirmDeleteDialog(
                  context: context,
                  title: 'Delete ${building.name}?',
                  message:
                      'It leaves the building list, the report form and the '
                      'map. A building is deleted once its rooms are: '
                      'delete them, or move them to another building, first. '
                      'Reports about it keep its name.',
                  doneMessage: 'Deleted ${building.name}.',
                  onConfirm: () => ref
                      .read(inventoryControllerProvider)
                      .deleteBuilding(building.id),
                ),
                icon: const Icon(Icons.delete_outline, size: 20),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Latitude and longitude fields with a "Pick on map" button, for a
/// building's or a room's pin. [start] is where the map opens.
class _PinFields extends ConsumerWidget {
  const _PinFields({
    required this.latitude,
    required this.longitude,
    required this.start,
    required this.enabled,
    required this.onPicked,
  });

  final TextEditingController latitude;
  final TextEditingController longitude;
  final GeoCoordinates Function() start;
  final bool enabled;
  final VoidCallback onPicked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget field(TextEditingController controller, String label) => TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))],
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: field(latitude, 'Latitude (optional)')),
            const SizedBox(width: 12),
            Expanded(child: field(longitude, 'Longitude (optional)')),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('pick-on-map'),
            onPressed: enabled
                ? () async {
                    final point = await ref.read(mapPinLauncherProvider)(
                      context,
                      start(),
                    );
                    if (point == null) return;
                    latitude.text = point.latitude.toStringAsFixed(6);
                    longitude.text = point.longitude.toStringAsFixed(6);
                    onPicked();
                  }
                : null,
            icon: const Icon(Icons.place_outlined, size: 18),
            label: const Text('Pick on map'),
          ),
        ),
      ],
    );
  }
}

/// The numbers in a pin's two fields, or why they cannot be read.
({double? latitude, double? longitude, String? problem}) _readPin(
  TextEditingController latitude,
  TextEditingController longitude,
) {
  double? number(TextEditingController controller) =>
      double.tryParse(controller.text.trim());
  if ((latitude.text.trim().isNotEmpty && number(latitude) == null) ||
      (longitude.text.trim().isNotEmpty && number(longitude) == null)) {
    return (
      latitude: null,
      longitude: null,
      problem: 'Enter the coordinates as numbers.',
    );
  }
  return (
    latitude: number(latitude),
    longitude: number(longitude),
    problem: null,
  );
}

/// Adds a building, or edits [building] (2026-11-26).
Future<void> showBuildingFormDialog(
  BuildContext context, {
  required List<Building> buildings,
  Building? building,
}) => showDialog<void>(
  context: context,
  builder: (_) => _BuildingFormDialog(buildings: buildings, building: building),
);

class _BuildingFormDialog extends ConsumerStatefulWidget {
  const _BuildingFormDialog({required this.buildings, this.building});

  final List<Building> buildings;
  final Building? building;

  @override
  ConsumerState<_BuildingFormDialog> createState() =>
      _BuildingFormDialogState();
}

class _BuildingFormDialogState extends ConsumerState<_BuildingFormDialog> {
  late final _name = TextEditingController(text: widget.building?.name);
  late final _description = TextEditingController(
    text: widget.building?.description,
  );
  late final _latitude = TextEditingController(
    text: widget.building?.coordinates?.latitude.toString(),
  );
  late final _longitude = TextEditingController(
    text: widget.building?.coordinates?.longitude.toString(),
  );
  String? _error;
  bool _busy = false;

  bool get _editing => widget.building != null;

  @override
  void dispose() {
    for (final controller in [_name, _description, _latitude, _longitude]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final pin = _readPin(_latitude, _longitude);
    if (pin.problem case final problem?) {
      setState(() => _error = problem);
      return;
    }
    final draft = BuildingDraft(
      name: _name.text,
      description: _description.text,
      latitude: pin.latitude,
      longitude: pin.longitude,
    );
    if (draft.problem case final problem?) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final controller = ref.read(inventoryControllerProvider);
    final result = _editing
        ? await controller.updateBuilding(widget.building!.id, draft)
        : await controller.createBuilding(draft);
    if (!mounted) return;
    switch (result) {
      case Success():
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${_editing ? 'Saved' : 'Added'} ${draft.normalized().name}.',
            ),
          ),
        );
      case Error(:final failure):
        setState(() {
          _busy = false;
          _error = failure.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_editing ? 'Edit building' : 'Add building'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('building-name'),
              controller: _name,
              enabled: !_busy,
              autofocus: !_editing,
              maxLength: BuildingDraft.nameLimit,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Engineering Building',
                counterText: '',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              enabled: !_busy,
              maxLength: BuildingDraft.descriptionLimit,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'e.g. Beside the gymnasium',
                counterText: '',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            _PinFields(
              latitude: _latitude,
              longitude: _longitude,
              enabled: !_busy,
              onPicked: () => setState(() => _error = null),
              start: () {
                final pin = _readPin(_latitude, _longitude);
                return pinPickerStart(
                  current: pin.latitude == null || pin.longitude == null
                      ? null
                      : GeoCoordinates(
                          latitude: pin.latitude!,
                          longitude: pin.longitude!,
                        ),
                  buildings: widget.buildings,
                );
              },
            ),
            if (_error case final message?) ...[
              const SizedBox(height: 12),
              Text(
                message,
                style: AppTextStyles.inventoryStatNote.copyWith(
                  color: AppColors.error,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('save-building'),
        onPressed: _busy ? null : _save,
        child: Text(_busy ? 'Saving…' : (_editing ? 'Save' : 'Add building')),
      ),
    ],
  );
}

/// Adds a room to one of [buildings], or edits [room].
Future<void> showFacilityFormDialog(
  BuildContext context, {
  required List<Building> buildings,
  Facility? room,
}) => showDialog<void>(
  context: context,
  builder: (_) => _FacilityFormDialog(room: room, buildings: buildings),
);

class _FacilityFormDialog extends ConsumerStatefulWidget {
  const _FacilityFormDialog({required this.buildings, this.room});

  final Facility? room;
  final List<Building> buildings;

  @override
  ConsumerState<_FacilityFormDialog> createState() =>
      _FacilityFormDialogState();
}

class _FacilityFormDialogState extends ConsumerState<_FacilityFormDialog> {
  /// The building chosen, by id. A room from before buildings were kept
  /// finds its building by name.
  late String? _buildingId =
      widget.room?.buildingId ??
      widget.buildings
          .where(
            (b) =>
                b.name.toLowerCase() == widget.room?.buildingName.toLowerCase(),
          )
          .firstOrNull
          ?.id;
  late final _floor = TextEditingController(text: widget.room?.floor);
  late final _room = TextEditingController(text: widget.room?.roomIdentifier);
  late final _description = TextEditingController(
    text: widget.room?.locationDescription,
  );
  late final _latitude = TextEditingController(
    text: widget.room?.coordinates?.latitude.toString(),
  );
  late final _longitude = TextEditingController(
    text: widget.room?.coordinates?.longitude.toString(),
  );
  late final _code = TextEditingController(text: widget.room?.qrCode);
  String? _error;
  bool _busy = false;

  bool get _editing => widget.room != null;

  @override
  void dispose() {
    for (final controller in [
      _floor,
      _room,
      _description,
      _latitude,
      _longitude,
      _code,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Building? get _building =>
      widget.buildings.where((b) => b.id == _buildingId).firstOrNull;

  Future<void> _save() async {
    final pin = _readPin(_latitude, _longitude);
    if (pin.problem case final problem?) {
      setState(() => _error = problem);
      return;
    }
    final building = _building;
    if (building == null) {
      setState(() => _error = 'Choose the building.');
      return;
    }
    final draft = FacilityDraft(
      buildingName: building.name,
      buildingId: building.id,
      floor: _floor.text,
      roomIdentifier: _room.text,
      locationDescription: _description.text,
      latitude: pin.latitude,
      longitude: pin.longitude,
      qrCode: _code.text,
    );
    if (draft.problem case final problem?) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final controller = ref.read(inventoryControllerProvider);
    final result = _editing
        ? await controller.updateFacility(widget.room!.id, draft)
        : await controller.createFacility(draft);
    if (!mounted) return;
    switch (result) {
      case Success():
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        final clean = draft.normalized();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${_editing ? 'Saved' : 'Added'} '
              '${[clean.buildingName, ?clean.roomIdentifier].join(', ')}.',
            ),
          ),
        );
      case Error(:final failure):
        setState(() {
          _busy = false;
          _error = failure.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget field(
      TextEditingController controller,
      String label, {
      String? hint,
      bool numeric = false,
      int? maxLength,
    }) => TextField(
      controller: controller,
      enabled: !_busy,
      maxLength: maxLength,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : null,
      inputFormatters: numeric
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))]
          : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
        border: const OutlineInputBorder(),
      ),
    );

    return AlertDialog(
      title: Text(_editing ? 'Edit room' : 'Add room'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                key: const ValueKey('room-building'),
                initialValue: _buildingId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Building',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final building in widget.buildings)
                    DropdownMenuItem(
                      value: building.id,
                      child: Text(
                        building.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (id) => setState(() {
                        _buildingId = id;
                        _error = null;
                      }),
              ),
              const SizedBox(height: 12),
              field(
                _room,
                'Room (optional)',
                hint: 'e.g. Room 203, Computer Laboratory 2',
                maxLength: FacilityDraft.nameLimit,
              ),
              const SizedBox(height: 12),
              field(
                _floor,
                'Floor (optional)',
                hint: 'e.g. 2nd floor',
                maxLength: FacilityDraft.floorLimit,
              ),
              const SizedBox(height: 12),
              field(
                _description,
                'Where it is (optional)',
                hint: 'Building and room if empty',
                maxLength: FacilityDraft.descriptionLimit,
              ),
              const SizedBox(height: 12),
              _PinFields(
                latitude: _latitude,
                longitude: _longitude,
                enabled: !_busy,
                onPicked: () => setState(() => _error = null),
                start: () {
                  final pin = _readPin(_latitude, _longitude);
                  return pinPickerStart(
                    current: pin.latitude == null || pin.longitude == null
                        ? null
                        : GeoCoordinates(
                            latitude: pin.latitude!,
                            longitude: pin.longitude!,
                          ),
                    near: [_building?.coordinates],
                    buildings: widget.buildings,
                  );
                },
              ),
              const SizedBox(height: 12),
              field(
                _code,
                _editing
                    ? 'Code on its sticker'
                    : 'Code on its sticker (optional)',
                hint: _editing ? null : 'Made from its record if empty',
                maxLength: FacilityDraft.qrCodeLimit,
              ),
              if (_error case final message?) ...[
                const SizedBox(height: 12),
                Text(
                  message,
                  style: AppTextStyles.inventoryStatNote.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Saving…' : (_editing ? 'Save' : 'Add room')),
        ),
      ],
    );
  }
}

/// Adds equipment to one of [rooms], or edits [asset].
Future<void> showAssetFormDialog(
  BuildContext context, {
  required List<Facility> rooms,
  Asset? asset,
}) => showDialog<void>(
  context: context,
  builder: (_) => _AssetFormDialog(rooms: rooms, asset: asset),
);

class _AssetFormDialog extends ConsumerStatefulWidget {
  const _AssetFormDialog({required this.rooms, this.asset});

  final List<Facility> rooms;
  final Asset? asset;

  @override
  ConsumerState<_AssetFormDialog> createState() => _AssetFormDialogState();
}

class _AssetFormDialogState extends ConsumerState<_AssetFormDialog> {
  late final _name = TextEditingController(text: widget.asset?.name);
  late final _category = TextEditingController(text: widget.asset?.category);
  late final _serial = TextEditingController(text: widget.asset?.serialNumber);
  late final _code = TextEditingController(text: widget.asset?.qrCode);
  late String? _roomId = widget.asset?.facilityId;
  late ItemCondition _condition = widget.asset?.condition ?? ItemCondition.good;
  String? _error;
  bool _busy = false;

  bool get _editing => widget.asset != null;

  @override
  void dispose() {
    for (final controller in [_name, _category, _serial, _code]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final draft = AssetDraft(
      name: _name.text,
      facilityId: _roomId ?? '',
      condition: _condition,
      category: _category.text,
      serialNumber: _serial.text,
      qrCode: _code.text,
    );
    if (draft.problem case final problem?) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final controller = ref.read(inventoryControllerProvider);
    final result = _editing
        ? await controller.updateAsset(widget.asset!.id, draft)
        : await controller.createAsset(draft);
    if (!mounted) return;
    switch (result) {
      case Success():
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${_editing ? 'Saved' : 'Added'} ${draft.normalized().name}.',
            ),
          ),
        );
      case Error(:final failure):
        setState(() {
          _busy = false;
          _error = failure.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final rooms = [
      for (final room in widget.rooms)
        if (room.isActive || room.id == _roomId) room,
    ];
    return AlertDialog(
      title: Text(_editing ? 'Edit equipment' : 'Add equipment'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                enabled: !_busy,
                maxLength: AssetDraft.nameLimit,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Split-Type Aircon Unit',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _roomId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Room',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final room in rooms)
                    DropdownMenuItem(
                      value: room.id,
                      child: Text(
                        [room.buildingName, ?room.roomIdentifier].join(', '),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _busy ? null : (id) => setState(() => _roomId = id),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _category,
                      enabled: !_busy,
                      maxLength: AssetDraft.shortLimit,
                      decoration: const InputDecoration(
                        labelText: 'Type (optional)',
                        counterText: '',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _serial,
                      enabled: !_busy,
                      maxLength: AssetDraft.shortLimit,
                      decoration: const InputDecoration(
                        labelText: 'Serial number (optional)',
                        counterText: '',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ItemCondition>(
                isExpanded: true,
                initialValue: _condition,
                decoration: const InputDecoration(
                  labelText: 'Condition',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final condition in ItemCondition.values)
                    DropdownMenuItem(
                      value: condition,
                      child: Text(condition.label),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _condition = value!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _code,
                enabled: !_busy,
                maxLength: FacilityDraft.qrCodeLimit,
                decoration: InputDecoration(
                  labelText: _editing
                      ? 'Code on its sticker'
                      : 'Code on its sticker (optional)',
                  hintText: _editing ? null : 'Made from its record if empty',
                  counterText: '',
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_error case final message?) ...[
                const SizedBox(height: 12),
                Text(
                  message,
                  style: AppTextStyles.inventoryStatNote.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(
            _busy ? 'Saving…' : (_editing ? 'Save' : 'Add equipment'),
          ),
        ),
      ],
    );
  }
}
