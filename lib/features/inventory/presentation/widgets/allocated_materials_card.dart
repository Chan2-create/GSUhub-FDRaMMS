import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/quantity_format.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/widgets/section_card.dart';
import '../../../work_orders/data/models/work_order.dart';
import '../../data/models/allocated_material.dart';
import '../../data/models/inventory_item.dart';
import '../../data/models/material_request.dart';
import '../inventory_controller.dart';
import '../inventory_providers.dart';
import 'inventory_widgets.dart';
import 'request_review.dart';

/// The console work-order page's "Pre-assigned materials" (Objective 6.B):
/// what GSU has set aside for the job, set here or by approving the
/// technician's requests, which are listed under it. Group 43 shows the
/// technician's side; this side has no design and uses the page's cards.
class AllocatedMaterialsCard extends ConsumerWidget {
  const AllocatedMaterialsCard({
    required this.workOrder,
    required this.open,
    super.key,
  });

  final WorkOrder workOrder;

  /// Pending or in progress: materials can still be assigned.
  final bool open;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allocated = switch (ref.watch(
      allocatedMaterialsProvider(workOrder.id),
    )) {
      AsyncData(value: Success(:final value)) => value,
      _ => const <AllocatedMaterial>[],
    };
    final requests = switch (ref.watch(
      workOrderMaterialRequestsProvider(workOrder.id),
    )) {
      AsyncData(value: Success(:final value)) => value,
      _ => const <MaterialRequest>[],
    };

    return SectionCard(
      title: 'Pre-assigned materials',
      subtitle:
          'Set aside for this job. Stock comes off only by what the '
          'technician reports as used.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (allocated.isEmpty)
            const Text(
              'None pre-assigned.',
              style: AppTextStyles.inventoryStatNote,
            ),
          for (final material in allocated)
            Row(
              children: [
                Expanded(
                  child: Text(
                    material.line.itemName,
                    style: AppTextStyles.inventoryCell,
                  ),
                ),
                Text(
                  QuantityFormat.withUnit(
                    material.line.quantity,
                    material.line.unitOfMeasurement,
                  ),
                  style: AppTextStyles.inventoryCellStrong,
                ),
                if (open)
                  IconButton(
                    tooltip: 'Remove ${material.line.itemName}',
                    onPressed: () async {
                      final result = await ref
                          .read(inventoryControllerProvider)
                          .removeAllocation(
                            workOrderId: workOrder.id,
                            inventoryItemId: material.inventoryItemId,
                          );
                      if (context.mounted) {
                        showInventoryOutcome(
                          context,
                          result,
                          'Took ${material.line.itemName} off the job.',
                        );
                      }
                    },
                    icon: const Icon(Icons.close, size: 18),
                  ),
              ],
            ),
          if (open) ...[
            const SizedBox(height: 12),
            _AllocateForm(workOrderId: workOrder.id),
          ],
          if (requests.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('REQUESTS', style: AppTextStyles.inventoryCaption),
            const SizedBox(height: 8),
            for (final request in requests)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: MaterialRequestCard(
                  request: request,
                  showWorkOrder: false,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _AllocateForm extends ConsumerStatefulWidget {
  const _AllocateForm({required this.workOrderId});

  final String workOrderId;

  @override
  ConsumerState<_AllocateForm> createState() => _AllocateFormState();
}

class _AllocateFormState extends ConsumerState<_AllocateForm> {
  final _quantity = TextEditingController();
  String? _itemId;
  bool _busy = false;

  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  Future<void> _save(InventoryItem item) async {
    final quantity = parseQuantity(_quantity.text);
    if (quantity == null || quantity <= 0) {
      showInventoryOutcome(
        context,
        const Result.failure(ValidationFailure('Enter how much to set aside.')),
        '',
      );
      return;
    }
    setState(() => _busy = true);
    final result = await ref
        .read(inventoryControllerProvider)
        .allocate(
          workOrderId: widget.workOrderId,
          inventoryItemId: item.id,
          quantity: quantity,
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.isSuccess) {
        _itemId = null;
        _quantity.clear();
      }
    });
    showInventoryOutcome(
      context,
      result,
      'Pre-assigned ${QuantityFormat.withUnit(quantity, item.unitOfMeasurement)} '
      'of ${item.name}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = switch (ref.watch(inventoryItemsProvider)) {
      AsyncData(value: Success(:final value)) => value,
      _ => const <InventoryItem>[],
    };
    final chosen = items.where((item) => item.id == _itemId).firstOrNull;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: DropdownButtonFormField<String>(
            initialValue: _itemId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Material',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: [
              for (final item in items)
                DropdownMenuItem(
                  value: item.id,
                  child: Text(
                    '${item.name} · '
                    '${QuantityFormat.withUnit(item.quantityAvailable, item.unitOfMeasurement)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _busy ? null : (id) => setState(() => _itemId = id),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextField(
            controller: _quantity,
            enabled: !_busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: InputDecoration(
              labelText: 'Quantity',
              suffixText: chosen?.unitOfMeasurement,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _busy || chosen == null ? null : () => _save(chosen),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.inventoryHeading,
          ),
          child: Text(_busy ? 'Saving…' : 'Pre-assign'),
        ),
      ],
    );
  }
}
