import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/di/service_providers.dart';
import '../../../../core/routing/route_paths.dart';
import '../../../../core/services/photo_picker_service.dart';
import '../../../../core/utils/display_id.dart';
import '../../../../core/utils/quantity_format.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../qr_labels/qr_label.dart';
import '../../../qr_labels/qr_label_actions.dart';
import '../../../user_management/presentation/personnel_providers.dart';
import '../../data/models/inventory_item.dart';
import '../../data/models/inventory_item_draft.dart';
import '../../data/models/inventory_transaction.dart';
import '../../data/repositories/inventory_repository_impl.dart';
import '../inventory_controller.dart';
import '../inventory_providers.dart';
import 'inventory_widgets.dart';

/// The material dialogs of the Inventory page (Objective 6.A). None is in
/// the design, which shows the buttons that open them; they use the
/// console's dialog and field styles.

final _numbers = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];

/// Adds a material, or edits [item].
Future<void> showMaterialFormDialog(
  BuildContext context, {
  InventoryItem? item,
}) => showDialog<void>(
  context: context,
  builder: (_) => _MaterialFormDialog(item: item),
);

class _MaterialFormDialog extends ConsumerStatefulWidget {
  const _MaterialFormDialog({this.item});

  final InventoryItem? item;

  @override
  ConsumerState<_MaterialFormDialog> createState() =>
      _MaterialFormDialogState();
}

class _MaterialFormDialogState extends ConsumerState<_MaterialFormDialog> {
  late final _name = TextEditingController(text: widget.item?.name);
  late final _category = TextEditingController(text: widget.item?.category);
  late final _specification = TextEditingController(
    text: widget.item?.specification,
  );
  late final _unit = TextEditingController(
    text: widget.item?.unitOfMeasurement ?? 'units',
  );
  late final _location = TextEditingController(
    text: widget.item?.storageLocation ?? 'GSU Store',
  );
  late final _code = TextEditingController(text: widget.item?.qrCode);
  late final _minimum = TextEditingController(
    text: widget.item == null
        ? ''
        : QuantityFormat.amount(widget.item!.minimumThreshold),
  );
  late final _cost = TextEditingController(
    text: widget.item?.unitCost == null
        ? ''
        : QuantityFormat.amount(widget.item!.unitCost!),
  );
  final _opening = TextEditingController();
  PickedPhoto? _photo;
  String? _error;
  bool _busy = false;

  bool get _editing => widget.item != null;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _category,
      _specification,
      _unit,
      _location,
      _code,
      _minimum,
      _cost,
      _opening,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// `INV-` and the name in capitals: the code a new material's label
  /// carries unless another is typed.
  static String _defaultCode(String name) {
    final slug = name
        .trim()
        .toUpperCase()
        .replaceAll(RegExp('[^A-Z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return 'INV-${slug.length > 40 ? slug.substring(0, 40) : slug}';
  }

  Future<void> _pickPhoto() async {
    final picked = await ref
        .read(photoPickerServiceProvider)
        .pick(PhotoSource.gallery, limit: 1);
    if (!mounted) return;
    switch (picked) {
      case Success(:final value) when value.isNotEmpty:
        setState(() => _photo = value.first);
      case Success():
        break;
      case Error(:final failure):
        setState(() => _error = failure.message);
    }
  }

  Future<void> _save() async {
    final minimum = parseQuantity(_minimum.text);
    final cost = _cost.text.trim().isEmpty ? null : parseQuantity(_cost.text);
    final opening = _opening.text.trim().isEmpty
        ? 0.0
        : parseQuantity(_opening.text);
    if (minimum == null) {
      setState(
        () => _error = 'Enter the stock level that should raise an alert.',
      );
      return;
    }
    if (_cost.text.trim().isNotEmpty && cost == null) {
      setState(
        () => _error = 'Enter the unit cost as a number, or leave it empty.',
      );
      return;
    }
    if (opening == null) {
      setState(() => _error = 'Enter the opening stock as a number.');
      return;
    }
    final draft = InventoryItemDraft(
      name: _name.text,
      category: _category.text,
      specification: _specification.text,
      unitOfMeasurement: _unit.text,
      storageLocation: _location.text,
      qrCode: _code.text.trim().isEmpty ? _defaultCode(_name.text) : _code.text,
      minimumThreshold: minimum,
      unitCost: cost,
      photoUrl: widget.item?.photoUrl,
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
    final Result<Object?> result = _editing
        ? await controller.updateMaterial(
            itemId: widget.item!.id,
            draft: draft,
            photo: _photo,
          )
        : await controller.createMaterial(
            draft: draft,
            openingStock: opening,
            photo: _photo,
          );
    if (!mounted) return;
    switch (result) {
      case Success():
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              _editing
                  ? 'Saved ${draft.normalized().name}.'
                  : 'Added ${draft.normalized().name} to the inventory.',
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
      int? maxLength,
      bool numeric = false,
      String? prefix,
    }) => TextField(
      controller: controller,
      enabled: !_busy,
      maxLength: maxLength,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : null,
      inputFormatters: numeric ? _numbers : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: prefix,
        counterText: '',
        border: const OutlineInputBorder(),
      ),
    );

    Widget pair(Widget left, Widget right) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ],
    );

    final currentPhoto = widget.item?.photoUrl;
    return AlertDialog(
      title: Text(_editing ? 'Edit material' : 'Add material'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              field(
                _name,
                'Name',
                hint: 'e.g. LED Bulbs (60W Eq)',
                maxLength: InventoryItemDraft.nameLimit,
              ),
              const SizedBox(height: 12),
              pair(
                field(
                  _category,
                  'Category',
                  hint: 'e.g. Electrical',
                  maxLength: InventoryItemDraft.shortLimit,
                ),
                field(
                  _specification,
                  'Size or pack (optional)',
                  hint: 'e.g. 10ft, 5 Gal',
                  maxLength: InventoryItemDraft.shortLimit,
                ),
              ),
              const SizedBox(height: 12),
              pair(
                field(
                  _unit,
                  'Counted in',
                  hint: 'units, rolls, cans',
                  maxLength: InventoryItemDraft.shortLimit,
                ),
                field(
                  _location,
                  'Stored at',
                  maxLength: InventoryItemDraft.locationLimit,
                ),
              ),
              const SizedBox(height: 12),
              pair(
                field(_minimum, 'Alert when at or below', numeric: true),
                field(
                  _cost,
                  'Unit cost (optional)',
                  numeric: true,
                  prefix: '₱ ',
                ),
              ),
              const SizedBox(height: 12),
              if (_editing)
                field(
                  _code,
                  'Code on its label',
                  maxLength: InventoryItemDraft.qrCodeLimit,
                )
              else
                pair(
                  field(
                    _code,
                    'Code on its label (optional)',
                    hint: 'Made from the name if empty',
                    maxLength: InventoryItemDraft.qrCodeLimit,
                  ),
                  field(_opening, 'Opening stock', numeric: true),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pickPhoto,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(
                      _photo != null || currentPhoto != null
                          ? 'Change photo'
                          : 'Add a photo (optional)',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _photo?.fileName ??
                          (currentPhoto == null ? '' : 'Photo on file'),
                      style: AppTextStyles.inventoryStatNote,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
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
          child: Text(_busy ? 'Saving…' : (_editing ? 'Save' : 'Add material')),
        ),
      ],
    );
  }
}

/// Records stock received for [item]: Figure 15's cart, and ORDER.
Future<void> showDeliveryDialog(BuildContext context, InventoryItem item) =>
    showDialog<void>(
      context: context,
      builder: (_) => _DeliveryDialog(item: item),
    );

class _DeliveryDialog extends ConsumerStatefulWidget {
  const _DeliveryDialog({required this.item});

  final InventoryItem item;

  @override
  ConsumerState<_DeliveryDialog> createState() => _DeliveryDialogState();
}

class _DeliveryDialogState extends ConsumerState<_DeliveryDialog> {
  final _quantity = TextEditingController();
  final _notes = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _quantity.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final quantity = parseQuantity(_quantity.text);
    if (quantity == null || quantity <= 0) {
      setState(() => _error = 'Enter how much arrived.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(inventoryControllerProvider)
        .recordDelivery(
          itemId: widget.item.id,
          quantity: quantity,
          notes: _notes.text,
        );
    if (!mounted) return;
    switch (result) {
      case Success():
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Recorded ${QuantityFormat.withUnit(quantity, widget.item.unitOfMeasurement)} '
              'of ${widget.item.name} received.',
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
    final item = widget.item;
    return AlertDialog(
      title: const Text('Record a delivery'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${item.name} · '
              '${QuantityFormat.withUnit(item.quantityAvailable, item.unitOfMeasurement)} '
              'in stock now. GSUhub does not place orders; record stock as '
              'it arrives at the store.',
              style: AppTextStyles.inventoryStatNote,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _quantity,
              autofocus: true,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: _numbers,
              decoration: InputDecoration(
                labelText: 'Quantity received',
                suffixText: item.unitOfMeasurement,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              enabled: !_busy,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Reference (optional)',
                hintText: 'e.g. delivery receipt or PO number',
                counterText: '',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error case final message?) ...[
              const SizedBox(height: 8),
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
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Saving…' : 'Record delivery'),
        ),
      ],
    );
  }
}

/// Corrects [item]'s balance to a physical count.
Future<void> showStockCountDialog(BuildContext context, InventoryItem item) =>
    showDialog<void>(
      context: context,
      builder: (_) => _StockCountDialog(item: item),
    );

class _StockCountDialog extends ConsumerStatefulWidget {
  const _StockCountDialog({required this.item});

  final InventoryItem item;

  @override
  ConsumerState<_StockCountDialog> createState() => _StockCountDialogState();
}

class _StockCountDialogState extends ConsumerState<_StockCountDialog> {
  final _count = TextEditingController();
  final _reason = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _count.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final counted = parseQuantity(_count.text);
    if (counted == null) {
      setState(() => _error = 'Enter how many were counted.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(inventoryControllerProvider)
        .recordStockCount(
          itemId: widget.item.id,
          countedQuantity: counted,
          reason: _reason.text,
        );
    if (!mounted) return;
    switch (result) {
      case Success():
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${widget.item.name} set to '
              '${QuantityFormat.withUnit(counted, widget.item.unitOfMeasurement)}.',
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
    final item = widget.item;
    return AlertDialog(
      title: const Text('Record a stock count'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'The record says '
              '${QuantityFormat.withUnit(item.quantityAvailable, item.unitOfMeasurement)} '
              'of ${item.name}. Enter what is on the shelf; the difference '
              'is kept in its history with your reason.',
              style: AppTextStyles.inventoryStatNote,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _count,
              autofocus: true,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: _numbers,
              decoration: InputDecoration(
                labelText: 'Counted on the shelf',
                suffixText: item.unitOfMeasurement,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              enabled: !_busy,
              maxLength: InventoryRepositoryImpl.reasonLimit,
              decoration: const InputDecoration(
                labelText: 'Why it differs',
                hintText: 'e.g. three broken in storage',
                counterText: '',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error case final message?) ...[
              const SizedBox(height: 8),
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
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Saving…' : 'Save count'),
        ),
      ],
    );
  }
}

/// A material's details and stock history (§3.4 "review material usage
/// history"), with its actions.
Future<void> showMaterialDetailsDialog(BuildContext context, String itemId) =>
    showDialog<void>(
      context: context,
      builder: (_) => _MaterialDetailsDialog(itemId: itemId),
    );

class _MaterialDetailsDialog extends ConsumerWidget {
  const _MaterialDetailsDialog({required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(inventoryItemProvider(itemId));
    return AlertDialog(
      title: switch (item) {
        AsyncData(value: Success(:final value)) => Text(value.name),
        _ => const Text('Material'),
      },
      content: SizedBox(
        width: 640,
        child: AsyncValueView<InventoryItem>(
          value: item,
          loadingHeight: 240,
          onRetry: () => ref.invalidate(inventoryItemProvider(itemId)),
          data: (item) => _MaterialDetails(item: item),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _MaterialDetails extends ConsumerWidget {
  const _MaterialDetails({required this.item});

  final InventoryItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(itemHistoryProvider(item.id));
    final unit = item.unitOfMeasurement;

    Widget fact(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label, style: AppTextStyles.inventoryCaption),
          ),
          Expanded(child: Text(value, style: AppTextStyles.inventoryCell)),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            InventoryBadge.stock(item),
            const SizedBox(width: 12),
            Text(
              QuantityFormat.withUnit(item.quantityAvailable, unit),
              style: AppTextStyles.inventoryQuantity,
            ),
          ],
        ),
        const SizedBox(height: 16),
        fact('CATEGORY', [item.category, ?item.specification].join(' · ')),
        fact('STORED AT', item.storageLocation),
        fact(
          'ALERT AT OR BELOW',
          QuantityFormat.withUnit(item.minimumThreshold, unit),
        ),
        fact(
          'UNIT COST',
          item.unitCost == null
              ? 'Not set'
              : '${QuantityFormat.pesos(item.unitCost!)} per '
                    '${unit.endsWith('s') ? unit.substring(0, unit.length - 1) : unit}',
        ),
        if (item.stockValue case final value?)
          fact('STOCK VALUE', QuantityFormat.pesos(value)),
        fact('CODE ON LABEL', item.qrCode),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => showMaterialFormDialog(context, item: item),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit'),
            ),
            OutlinedButton.icon(
              onPressed: () => showDeliveryDialog(context, item),
              icon: const Icon(Icons.add_shopping_cart_outlined, size: 18),
              label: const Text('Record delivery'),
            ),
            OutlinedButton.icon(
              onPressed: () => showStockCountDialog(context, item),
              icon: const Icon(Icons.fact_check_outlined, size: 18),
              label: const Text('Record stock count'),
            ),
            OutlinedButton.icon(
              onPressed: () =>
                  showQrLabelDialog(context, QrLabel.material(item)),
              icon: const Icon(Icons.qr_code_2_outlined, size: 18),
              label: const Text('QR label'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text('STOCK HISTORY', style: AppTextStyles.inventoryCaption),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: AsyncValueView<List<InventoryTransaction>>(
            value: history,
            loadingHeight: 120,
            onRetry: () => ref.invalidate(itemHistoryProvider(item.id)),
            data: (entries) => entries.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Nothing has moved yet.',
                      style: AppTextStyles.inventoryStatNote,
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) => _HistoryRow(
                      entry: entries[index],
                      unit: unit,
                      names: ref.watch(personnelNamesProvider),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.entry,
    required this.unit,
    required this.names,
  });

  final InventoryTransaction entry;
  final String unit;

  /// Technicians' names, for entries written before the ledger kept them.
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    final change = entry.change;
    final sign = change > 0 ? '+' : '−';
    final workOrderId = entry.workOrderId;
    final who =
        entry.performedByName ?? names[entry.performedBy] ?? 'Not recorded';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              DateFormat('MMM d, y h:mm a').format(entry.performedAt.toLocal()),
              style: AppTextStyles.inventoryStatNote,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.type.label} · $who',
                  style: AppTextStyles.inventoryCellStrong,
                ),
                if (entry.notes case final notes?)
                  Text(notes, style: AppTextStyles.inventoryStatNote),
                if (workOrderId != null)
                  InkWell(
                    onTap: () {
                      Navigator.of(context).pop();
                      context.go(
                        RoutePaths.adminWorkOrderDetailFor(workOrderId),
                      );
                    },
                    child: Text(
                      DisplayId.workOrder(workOrderId),
                      style: AppTextStyles.linkText,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$sign${QuantityFormat.amount(change.abs())}',
                style: AppTextStyles.inventoryCellStrong.copyWith(
                  color: change > 0
                      ? AppColors.inventoryInStockText
                      : AppColors.inventoryRepairText,
                ),
              ),
              Text(
                '${QuantityFormat.amount(entry.quantityAfter)} $unit left',
                style: AppTextStyles.inventoryStatNote,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
