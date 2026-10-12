import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/display_id.dart';
import '../../../core/utils/result.dart';
import '../../inventory/data/models/inventory_item.dart';
import '../../work_orders/data/models/work_order.dart';
import '../../work_orders/presentation/personnel/personnel_providers.dart';
import '../../work_orders/presentation/personnel/personnel_work_controller.dart';
import '../../work_orders/presentation/personnel/widgets/personnel_widgets.dart';

/// Recording a material as used on a work order (Objective 5.C), from a
/// scan or a work order's page. Not in the design: a plain sheet in the
/// app's style, flagged.
///
/// With no [item], the technician picks one from the inventory; with no
/// [workOrderId], one of their open work orders. [current] is a quantity
/// already recorded, to start from.
Future<void> showRecordMaterialSheet(
  BuildContext context, {
  String? workOrderId,
  InventoryItem? item,
  double? current,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: _RecordMaterialSheet(
      workOrderId: workOrderId,
      item: item,
      current: current,
    ),
  ),
);

class _RecordMaterialSheet extends ConsumerStatefulWidget {
  const _RecordMaterialSheet({
    required this.workOrderId,
    required this.item,
    required this.current,
  });

  final String? workOrderId;
  final InventoryItem? item;
  final double? current;

  @override
  ConsumerState<_RecordMaterialSheet> createState() =>
      _RecordMaterialSheetState();
}

class _RecordMaterialSheetState extends ConsumerState<_RecordMaterialSheet> {
  late InventoryItem? _item = widget.item;
  late String? _workOrderId = widget.workOrderId;
  late final _quantity = TextEditingController(
    text: widget.current == null ? '' : _amount(widget.current!),
  );
  final _search = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _quantity.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final item = _item;
    final workOrderId = _workOrderId;
    final quantity = double.tryParse(_quantity.text.trim());
    if (item == null || workOrderId == null) return;
    if (quantity == null || quantity <= 0) {
      setState(() => _error = 'Enter how much was used.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(personnelWorkControllerProvider)
        .recordMaterial(
          workOrderId: workOrderId,
          inventoryItemId: item.id,
          quantity: quantity,
        );
    if (!mounted) return;
    switch (result) {
      case Success():
        Navigator.of(context).pop();
        showPersonnelMessage(
          context,
          'Recorded ${_amount(quantity)} ${item.unitOfMeasurement} of '
          '${item.name}.',
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
    final item = _item;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Record material used',
                style: AppTextStyles.personnelSection,
              ),
              const SizedBox(height: 4),
              const Text(
                'Taken off stock when you submit the accomplishment report.',
                style: AppTextStyles.personnelCardBody,
              ),
              const SizedBox(height: 16),
              if (item == null)
                _ItemPicker(
                  search: _search,
                  onPicked: (picked) => setState(() => _item = picked),
                )
              else ...[
                _ItemSummary(
                  item: item,
                  onChange: widget.item == null
                      ? () => setState(() => _item = null)
                      : null,
                ),
                const SizedBox(height: 16),
                if (widget.workOrderId == null) ...[
                  _WorkOrderPicker(
                    value: _workOrderId,
                    onChanged: (id) => setState(() => _workOrderId = id),
                  ),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: _quantity,
                  autofocus: widget.item != null,
                  enabled: !_busy,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Quantity used',
                    suffixText: item.unitOfMeasurement,
                    errorText: _error,
                    errorMaxLines: 3,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy || _workOrderId == null ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.textPrimary,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text(_busy ? 'Saving…' : 'Record'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The item chosen, with its stock.
class _ItemSummary extends StatelessWidget {
  const _ItemSummary({required this.item, this.onChange});

  final InventoryItem item;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) => PersonnelCard(
    color: AppColors.personnelTile,
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.name, style: AppTextStyles.personnelCardTitle),
              const SizedBox(height: 2),
              Text(
                '${_amount(item.quantityAvailable)} ${item.unitOfMeasurement} '
                'in stock · ${item.storageLocation}',
                style: AppTextStyles.personnelCardBody,
              ),
            ],
          ),
        ),
        StockChip(item: item),
        if (onChange != null)
          TextButton(onPressed: onChange, child: const Text('Change')),
      ],
    ),
  );
}

/// "AVAILABLE" or "LOW STOCK" (Group 43).
class StockChip extends StatelessWidget {
  const StockChip({required this.item, super.key});

  final InventoryItem item;

  @override
  Widget build(BuildContext context) => item.isLowStock
      ? const PersonnelChip(
          'Low stock',
          background: AppColors.personnelUrgentFill,
          foreground: AppColors.personnelUrgentText,
        )
      : const PersonnelChip(
          'Available',
          background: AppColors.personnelStockFill,
          foreground: AppColors.personnelStockText,
        );
}

/// The inventory, searchable by name or category.
class _ItemPicker extends ConsumerStatefulWidget {
  const _ItemPicker({required this.search, required this.onPicked});

  final TextEditingController search;
  final ValueChanged<InventoryItem> onPicked;

  @override
  ConsumerState<_ItemPicker> createState() => _ItemPickerState();
}

class _ItemPickerState extends ConsumerState<_ItemPicker> {
  @override
  Widget build(BuildContext context) {
    final (items, problem) = switch (ref.watch(inventoryItemsProvider)) {
      AsyncData(value: Success(:final value)) => (value, null),
      AsyncData(value: Error(:final failure)) => (null, failure.message),
      AsyncError(:final error) => (null, '$error'),
      _ => (null, null),
    };
    final query = widget.search.text.trim().toLowerCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: widget.search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search materials',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        if (problem != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'The inventory could not be read. $problem',
              style: AppTextStyles.personnelCardBody,
            ),
          )
        else if (items == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final item in items)
                if (query.isEmpty ||
                    item.name.toLowerCase().contains(query) ||
                    item.category.toLowerCase().contains(query))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(item.name),
                    subtitle: Text(
                      '${item.category} · ${_amount(item.quantityAvailable)} '
                      '${item.unitOfMeasurement} in stock',
                    ),
                    trailing: StockChip(item: item),
                    onTap: () => widget.onPicked(item),
                  ),
            ],
          ),
      ],
    );
  }
}

/// One of the technician's open work orders.
class _WorkOrderPicker extends ConsumerWidget {
  const _WorkOrderPicker({required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = switch (ref.watch(myWorkOrdersProvider)) {
      AsyncData(value: Success(:final value)) => [
        for (final order in value)
          if (MyWork.isOpen(order.status)) order,
      ],
      _ => const <WorkOrder>[],
    };
    if (open.isEmpty) {
      return const Text(
        'You have no open work order to record it on.',
        style: AppTextStyles.personnelCardBody,
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Work order',
        border: OutlineInputBorder(),
      ),
      items: [
        for (final order in open)
          DropdownMenuItem(
            value: order.id,
            child: Text(
              '${DisplayId.workOrder(order.id)} · ${order.title}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

/// 2, not 2.0; 1.5 as it is.
String _amount(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toString();

/// [_amount], for other screens.
String formatQuantity(double value) => _amount(value);
