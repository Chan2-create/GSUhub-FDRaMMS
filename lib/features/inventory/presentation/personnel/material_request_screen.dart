import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/di/repository_providers.dart';
import '../../../../core/enums/material_request_status.dart';
import '../../../../core/routing/route_paths.dart';
import '../../../../core/utils/display_id.dart';
import '../../../../core/utils/quantity_format.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../shells/personnel/personnel_shell.dart';
import '../../../work_orders/data/models/work_order.dart';
import '../../../work_orders/presentation/personnel/personnel_providers.dart';
import '../../../work_orders/presentation/personnel/personnel_work_controller.dart';
import '../../../work_orders/presentation/personnel/widgets/personnel_widgets.dart';
import '../../data/models/allocated_material.dart';
import '../../data/models/inventory_item.dart';
import '../../data/models/material_line.dart';
import '../../data/models/material_request.dart';
import '../../data/repositories/material_request_repository_impl.dart';

/// A work order's materials, as the technician sees them (Objective 6.B,
/// Figure Group 43): what GSU pre-assigned, the additional materials to
/// ask for, and the requests made and their answers.
///
/// Departures from the frame, flagged: a back button, as every personnel
/// page has; a note box, because the design's request history shows the
/// technician's own words but the form has nowhere to type them; and each
/// request lists what it asked for.
class MaterialRequestScreen extends ConsumerStatefulWidget {
  const MaterialRequestScreen({required this.workOrderId, super.key});

  final String workOrderId;

  @override
  ConsumerState<MaterialRequestScreen> createState() =>
      _MaterialRequestScreenState();
}

class _MaterialRequestScreenState extends ConsumerState<MaterialRequestScreen> {
  final _needed = <MaterialLine>[];
  final _note = TextEditingController();
  String? _requestId;
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final line = await showModalBottomSheet<MaterialLine>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: const _AddMaterialSheet(),
      ),
    );
    if (line == null || !mounted) return;
    setState(() {
      final index = _needed.indexWhere(
        (other) => other.inventoryItemId == line.inventoryItemId,
      );
      if (index < 0) {
        _needed.add(line);
      } else {
        _needed[index] = line.withQuantity(
          _needed[index].quantity + line.quantity,
        );
      }
      // A changed list is a new request.
      _requestId = null;
    });
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    // Reserved once per request and reused on retry.
    final requestId = _requestId ??= ref
        .read(materialRequestRepositoryProvider)
        .newRequestId();
    final result = await ref
        .read(personnelWorkControllerProvider)
        .submitMaterialRequest(
          requestId: requestId,
          workOrderId: widget.workOrderId,
          items: List.of(_needed),
          note: _note.text,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case Success():
        setState(() {
          _needed.clear();
          _note.clear();
          _requestId = null;
        });
        showPersonnelMessage(
          context,
          'Request sent. GSU will approve or decline it here.',
        );
      case Error(:final failure):
        showPersonnelMessage(context, failure.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final workOrder = ref.watch(personnelWorkOrderProvider(widget.workOrderId));
    final allocated = ref.watch(allocatedMaterialsProvider(widget.workOrderId));
    final requests = ref.watch(myMaterialRequestsProvider(widget.workOrderId));
    final stock = switch (ref.watch(inventoryItemsProvider)) {
      AsyncData(value: Success(:final value)) => {
        for (final item in value) item.id: item,
      },
      _ => const <String, InventoryItem>{},
    };
    final order = switch (workOrder) {
      AsyncData(value: Success(:final value)) => value,
      _ => null,
    };
    final open = order != null && MyWork.isOpen(order.status);

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, personnelBottomInset(context)),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Back',
              onPressed: () => context.canPop()
                  ? context.pop()
                  : context.go(
                      RoutePaths.personnelWorkOrderFor(widget.workOrderId),
                    ),
              icon: const Icon(
                Icons.arrow_back,
                color: AppColors.myReportsTitle,
              ),
            ),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  // Group 43's "WO #45921": the number already says WO.
                  DisplayId.workOrder(widget.workOrderId),
                  style: AppTextStyles.personnelSection.copyWith(
                    color: AppColors.accentGold,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (order != null)
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 8),
            child: Text(
              _placeOf(order),
              style: AppTextStyles.personnelCardTitle,
            ),
          ),
        const SizedBox(height: 16),
        const _Label('Pre-assigned Materials'),
        AsyncValueView<List<AllocatedMaterial>>(
          value: allocated,
          loadingHeight: 80,
          onRetry: () =>
              ref.invalidate(allocatedMaterialsProvider(widget.workOrderId)),
          data: (materials) => PersonnelCard(
            edge: AppColors.accentGold,
            child: materials.isEmpty
                ? const Text(
                    'Nothing pre-assigned yet. Ask for what you need below.',
                    style: AppTextStyles.personnelCardBody,
                  )
                : Column(
                    children: [
                      for (var i = 0; i < materials.length; i++) ...[
                        if (i > 0) const Divider(height: 20),
                        _AllocatedRow(
                          material: materials[i],
                          item: stock[materials[i].inventoryItemId],
                        ),
                      ],
                    ],
                  ),
          ),
        ),
        if (open) ...[
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(child: _Label('Additional Materials Needed')),
              OutlinedButton.icon(
                onPressed: _busy ? null : _add,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Material'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accentGold,
                  side: const BorderSide(color: AppColors.accentGold, width: 2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_needed.isEmpty)
            const PersonnelCard(
              child: Text(
                'Add the materials this job still needs.',
                style: AppTextStyles.personnelCardBody,
              ),
            ),
          for (final line in _needed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PersonnelCard(
                padding: const EdgeInsets.fromLTRB(8, 12, 16, 12),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Remove ${line.itemName}',
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _needed.remove(line);
                              _requestId = null;
                            }),
                      icon: const Icon(
                        Icons.delete_outline,
                        color: AppColors.personnelUrgentText,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            line.itemName,
                            style: AppTextStyles.personnelCardTitle,
                          ),
                          Text(
                            'Qty: ${QuantityFormat.withUnit(line.quantity, line.unitOfMeasurement)}',
                            style: AppTextStyles.personnelCardBody,
                          ),
                        ],
                      ),
                    ),
                    const Text(
                      'Pending',
                      style: AppTextStyles.personnelCardBody,
                    ),
                  ],
                ),
              ),
            ),
          if (_needed.isNotEmpty) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              enabled: !_busy,
              maxLines: 2,
              maxLength: MaterialRequestRepositoryImpl.noteLimit,
              decoration: InputDecoration(
                labelText: 'Note for GSU (optional)',
                hintText: 'e.g. Floor sealant needed for the lobby area.',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ],
        const SizedBox(height: 24),
        const _Label('Request History'),
        AsyncValueView<List<MaterialRequest>>(
          value: requests,
          loadingHeight: 80,
          onRetry: () =>
              ref.invalidate(myMaterialRequestsProvider(widget.workOrderId)),
          data: (requests) => requests.isEmpty
              ? const PersonnelCard(
                  child: Text(
                    'No requests for this job yet.',
                    style: AppTextStyles.personnelCardBody,
                  ),
                )
              : Column(
                  children: [
                    for (final request in requests)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _RequestCard(request: request),
                      ),
                  ],
                ),
        ),
        if (open) ...[
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy || _needed.isEmpty ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.textPrimary,
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(_busy ? 'Sending…' : 'Submit Request'),
          ),
        ],
      ],
    );
  }

  static String _placeOf(WorkOrder order) => order.facilityName ?? order.title;
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Semantics(
      container: true,
      header: true,
      child: Text(text, style: AppTextStyles.personnelSubtitle),
    ),
  );
}

/// One pre-assigned material: name and unit, quantity in gold, and whether
/// the store has it (Group 43).
class _AllocatedRow extends StatelessWidget {
  const _AllocatedRow({required this.material, this.item});

  final AllocatedMaterial material;
  final InventoryItem? item;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              material.line.itemName,
              style: AppTextStyles.personnelCardTitle.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'Unit: ${material.line.unitOfMeasurement}',
              style: AppTextStyles.personnelCardBody,
            ),
          ],
        ),
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            QuantityFormat.amount(material.line.quantity).padLeft(2, '0'),
            style: AppTextStyles.personnelCardTitle.copyWith(
              color: AppColors.accentGold,
            ),
          ),
          if (item case final item?) ...[
            const SizedBox(height: 4),
            item.isLowStock
                ? const PersonnelChip(
                    'LOW STOCK',
                    background: AppColors.personnelUrgentFill,
                    foreground: AppColors.personnelUrgentText,
                  )
                : const PersonnelChip(
                    'AVAILABLE',
                    background: AppColors.personnelStockFill,
                    foreground: AppColors.personnelStockText,
                  ),
          ],
        ],
      ),
    ],
  );
}

/// One request in the history: its number and status, what it asked for,
/// the technician's note, and GSU's (Group 43).
class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request});

  final MaterialRequest request;

  @override
  Widget build(BuildContext context) {
    final (fill, text) = switch (request.status) {
      MaterialRequestStatus.pending => (
        AppColors.personnelPendingFill,
        AppColors.personnelTitle,
      ),
      MaterialRequestStatus.approved => (
        AppColors.personnelStockFill,
        AppColors.personnelStockText,
      ),
      MaterialRequestStatus.declined => (
        AppColors.personnelUrgentFill,
        AppColors.personnelUrgentText,
      ),
    };
    return PersonnelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Request ${DisplayId.materialRequest(request.id)}',
                  style: AppTextStyles.personnelCardBody,
                ),
              ),
              // Group 43 writes it "Pending", not in capitals.
              DecoratedBox(
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 5,
                  ),
                  child: Text(
                    request.status.label,
                    style: AppTextStyles.personnelChip.copyWith(color: text),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            request.items
                .map(
                  (line) =>
                      '${line.itemName} × '
                      '${QuantityFormat.withUnit(line.quantity, line.unitOfMeasurement)}',
                )
                .join('\n'),
            style: AppTextStyles.personnelCardTitle,
          ),
          if (request.note case final note?) ...[
            const SizedBox(height: 4),
            Text('"$note"', style: AppTextStyles.personnelCardTitle),
          ],
          if (request.adminNote case final note?) ...[
            const Divider(height: 24),
            Text(
              'Admin Note:',
              style: AppTextStyles.personnelCardTitle.copyWith(
                color: AppColors.personnelStatusPill,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              note,
              style: AppTextStyles.personnelCardBody.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Picks a material and how much of it is needed.
class _AddMaterialSheet extends ConsumerStatefulWidget {
  const _AddMaterialSheet();

  @override
  ConsumerState<_AddMaterialSheet> createState() => _AddMaterialSheetState();
}

class _AddMaterialSheetState extends ConsumerState<_AddMaterialSheet> {
  final _search = TextEditingController();
  final _quantity = TextEditingController();
  InventoryItem? _item;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    _quantity.dispose();
    super.dispose();
  }

  void _done() {
    final item = _item;
    final quantity = double.tryParse(_quantity.text.trim().replaceAll(',', ''));
    if (item == null) return;
    if (quantity == null || quantity <= 0) {
      setState(() => _error = 'Enter how much is needed.');
      return;
    }
    Navigator.of(context).pop(
      MaterialLine(
        inventoryItemId: item.id,
        itemName: item.name,
        quantity: quantity,
        unitOfMeasurement: item.unitOfMeasurement,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final items = switch (ref.watch(inventoryItemsProvider)) {
      AsyncData(value: Success(:final value)) => value,
      _ => const <InventoryItem>[],
    };
    final query = _search.text.trim().toLowerCase();
    final shown = [
      for (final candidate in items)
        if (query.isEmpty ||
            candidate.name.toLowerCase().contains(query) ||
            candidate.category.toLowerCase().contains(query))
          candidate,
    ];

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Add a material',
                style: AppTextStyles.personnelSection,
              ),
              const SizedBox(height: 12),
              if (item == null) ...[
                TextField(
                  controller: _search,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Search materials',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final candidate in shown)
                        ListTile(
                          title: Text(candidate.name),
                          subtitle: Text(
                            '${candidate.category} · '
                            '${QuantityFormat.withUnit(candidate.quantityAvailable, candidate.unitOfMeasurement)} '
                            'in stock',
                          ),
                          onTap: () => setState(() => _item = candidate),
                        ),
                    ],
                  ),
                ),
              ] else ...[
                PersonnelCard(
                  color: AppColors.personnelTile,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          style: AppTextStyles.personnelCardTitle,
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _item = null),
                        child: const Text('Change'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _quantity,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Quantity needed',
                    suffixText: item.unitOfMeasurement,
                    errorText: _error,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _done(),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _done,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.textPrimary,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('Add'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
