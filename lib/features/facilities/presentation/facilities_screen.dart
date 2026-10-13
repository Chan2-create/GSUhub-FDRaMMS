import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/di/repository_providers.dart';
import '../../../core/enums/item_condition.dart';
import '../../../core/utils/result.dart';
import '../../../core/widgets/app_data_table.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/section_card.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../../inventory/presentation/widgets/inventory_widgets.dart';
import '../../qr_labels/qr_label.dart';
import '../../qr_labels/qr_label_actions.dart';
import '../data/models/asset.dart';
import '../data/models/facility.dart';
import '../data/models/facility_draft.dart';

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
class FacilitiesScreen extends ConsumerWidget {
  const FacilitiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facilities = ref.watch(facilitiesProvider);
    final assets = ref.watch(assetsProvider);
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
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 16,
            runSpacing: 16,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Facilities & Equipment',
                    style: AppTextStyles.pageTitle,
                  ),
                  SizedBox(height: 4),
                  Text(
                    'The rooms reports are filed against, the equipment in '
                    'them, and the codes on their stickers.',
                    style: AppTextStyles.pageSubtitle,
                  ),
                ],
              ),
              OutlinedButton.icon(
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
                icon: const Icon(Icons.print_outlined, size: 18),
                label: const Text('Print all labels'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          SectionCard(
            title: 'Rooms',
            subtitle:
                'Faculty and staff pick these on the report form, or scan '
                'their stickers. An inactive room is left off the form.',
            trailing: FilledButton.icon(
              onPressed: () => showFacilityFormDialog(context),
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
  const _RoomsTable({required this.rooms, required this.equipmentCount});

  final List<Facility> rooms;
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
          onEdit: () => showFacilityFormDialog(context, room: room),
          onLabel: () => showQrLabelDialog(context, QrLabel.facility(room)),
          onActive: (active) => ref
              .read(inventoryControllerProvider)
              .setFacilityActive(room.id, active: active),
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
          ),
        ),
      ],
    );
  }
}

/// Edit, the sticker, and deactivate or reactivate.
class _RowActions extends StatelessWidget {
  const _RowActions({
    required this.name,
    required this.active,
    required this.onEdit,
    required this.onLabel,
    required this.onActive,
  });

  final String name;
  final bool active;
  final VoidCallback onEdit;
  final VoidCallback onLabel;
  final Future<Result<void>> Function(bool active) onActive;

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
    ],
  );
}

/// Adds a room, or edits [room].
Future<void> showFacilityFormDialog(BuildContext context, {Facility? room}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _FacilityFormDialog(room: room),
    );

class _FacilityFormDialog extends ConsumerStatefulWidget {
  const _FacilityFormDialog({this.room});

  final Facility? room;

  @override
  ConsumerState<_FacilityFormDialog> createState() =>
      _FacilityFormDialogState();
}

class _FacilityFormDialogState extends ConsumerState<_FacilityFormDialog> {
  late final _building = TextEditingController(text: widget.room?.buildingName);
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
      _building,
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

  Future<void> _save() async {
    double? number(TextEditingController controller) =>
        double.tryParse(controller.text.trim());
    if ((_latitude.text.trim().isNotEmpty && number(_latitude) == null) ||
        (_longitude.text.trim().isNotEmpty && number(_longitude) == null)) {
      setState(() => _error = 'Enter the coordinates as numbers.');
      return;
    }
    final draft = FacilityDraft(
      buildingName: _building.text,
      roomIdentifier: _room.text,
      locationDescription: _description.text,
      latitude: number(_latitude),
      longitude: number(_longitude),
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
              field(
                _building,
                'Building',
                hint: 'e.g. Engineering Building',
                maxLength: FacilityDraft.nameLimit,
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
                _description,
                'Where it is (optional)',
                hint: 'Building and room if empty',
                maxLength: FacilityDraft.descriptionLimit,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: field(
                      _latitude,
                      'Latitude (optional)',
                      numeric: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: field(
                      _longitude,
                      'Longitude (optional)',
                      numeric: true,
                    ),
                  ),
                ],
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
