import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/utils/display_id.dart';
import '../../../core/utils/result.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../shells/personnel/personnel_shell.dart';
import '../../inventory/data/models/inventory_item.dart';
import '../../tools/data/models/tool_loan.dart';
import '../../tools/presentation/tool_sheets.dart';
import '../../work_orders/data/models/work_order.dart';
import '../../work_orders/presentation/personnel/personnel_providers.dart';
import '../../work_orders/presentation/personnel/widgets/personnel_widgets.dart';
import '../data/models/recorded_material.dart';
import 'material_sheets.dart';

/// The Materials tab (Objective 5.C; Chris's export Group 43): the tools
/// the technician has out, and the materials recorded on each open work
/// order, with the scanner one tap away.
///
/// Group 43 also draws pre-assigned materials and material requests; both
/// belong to Objective 6 (Chris, 2026-10-12), so this is the usage side.
class PersonnelMaterialsScreen extends ConsumerWidget {
  const PersonnelMaterialsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(myWorkOrdersProvider);

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 20, 16, personnelBottomInset(context)),
      children: [
        Semantics(
          header: true,
          child: const Text(
            'Materials & Tools',
            style: AppTextStyles.personnelGreeting,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Record what you use on each job, and the tools you borrow.',
          style: AppTextStyles.personnelSubtitle,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => PersonnelShell.scan(context, ref),
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: const Text('Scan a material or tool'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accentGold,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const PersonnelSectionTitle('Tools with you'),
        const SizedBox(height: 12),
        const _ToolLoans(),
        const SizedBox(height: 24),
        const PersonnelSectionTitle('Materials used'),
        const SizedBox(height: 12),
        AsyncValueView<List<WorkOrder>>(
          value: orders,
          loadingHeight: 120,
          onRetry: () => ref.invalidate(myWorkOrdersProvider),
          isEmpty: (list) => !list.any((order) => MyWork.isOpen(order.status)),
          emptyIcon: Icons.inventory_2_outlined,
          emptyMessage: 'No open work orders to record materials on.',
          data: (list) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final order in list)
                if (MyWork.isOpen(order.status)) ...[
                  _WorkOrderMaterials(workOrder: order),
                  const SizedBox(height: 16),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ToolLoans extends ConsumerWidget {
  const _ToolLoans();

  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) => AsyncValueView<List<ToolLoan>>(
    value: ref.watch(myToolLoansProvider),
    loadingHeight: 80,
    onRetry: () => ref.invalidate(myToolLoansProvider),
    isEmpty: (loans) => loans.isEmpty,
    emptyIcon: Icons.handyman_outlined,
    emptyMessage:
        'You have no tools out. Scan a tool, or borrow one from a work '
        'order.',
    data: (loans) => PersonnelCard(
      edge: AppColors.accentGold,
      child: Column(
        children: [
          for (final loan in loans) ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loan.toolName,
                        style: AppTextStyles.personnelCardTitle,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          'Since ${DateFormat('MMM d, h:mm a').format(loan.borrowedAt.toLocal())}',
                          if (loan.workOrderId case final id?)
                            'for ${DisplayId.workOrder(id)}',
                        ].join(' · '),
                        style: AppTextStyles.personnelCardBody,
                      ),
                    ],
                  ),
                ),
                OutlinedButton(
                  onPressed: () => showReturnToolSheet(context, loan),
                  child: const Text('Return'),
                ),
              ],
            ),
            if (loan != loans.last) const Divider(height: 24),
          ],
        ],
      ),
    ),
  );
}

/// One open work order's recorded materials (Group 43): its number and
/// place in gold, then each item with its unit, amount and stock.
class _WorkOrderMaterials extends ConsumerWidget {
  const _WorkOrderMaterials({required this.workOrder});

  final WorkOrder workOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stock = switch (ref.watch(inventoryItemsProvider)) {
      AsyncData(value: Success(:final value)) => {
        for (final item in value) item.id: item,
      },
      _ => const <String, InventoryItem>{},
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () =>
              context.push(RoutePaths.personnelWorkOrderFor(workOrder.id)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DisplayId.workOrder(workOrder.id),
                style: AppTextStyles.personnelWorkOrderId.copyWith(
                  color: AppColors.accentGold,
                ),
              ),
              Text(
                [?workOrder.facilityName, workOrder.title].join(' - '),
                style: AppTextStyles.personnelSubtitle.copyWith(
                  color: AppColors.personnelTitle,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        PersonnelCard(
          edge: AppColors.accentGold,
          child: AsyncValueView<List<RecordedMaterial>>(
            value: ref.watch(recordedMaterialsProvider(workOrder.id)),
            loadingHeight: 40,
            onRetry: () =>
                ref.invalidate(recordedMaterialsProvider(workOrder.id)),
            isEmpty: (list) => list.isEmpty,
            emptyIcon: Icons.inventory_2_outlined,
            emptyMessage: 'Nothing recorded yet.',
            data: (list) => Column(
              children: [
                for (final material in list) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              material.usage.itemName,
                              style: AppTextStyles.personnelCardTitle.copyWith(
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              'Unit: ${material.usage.unitOfMeasurement}',
                              style: AppTextStyles.personnelCardBody,
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            formatQuantity(material.usage.quantityUsed),
                            style: AppTextStyles.personnelCardTitle.copyWith(
                              color: AppColors.accentGold,
                            ),
                          ),
                          if (stock[material.inventoryItemId] case final item?)
                            StockChip(item: item),
                        ],
                      ),
                    ],
                  ),
                  if (material != list.last) const Divider(height: 20),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: () =>
                showRecordMaterialSheet(context, workOrderId: workOrder.id),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add Material'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accentGold,
              side: const BorderSide(color: AppColors.accentGold, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
