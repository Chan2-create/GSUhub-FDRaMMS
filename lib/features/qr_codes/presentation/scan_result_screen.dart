import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/di/repository_providers.dart';
import '../../../core/enums/tool_status.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/utils/result.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../shells/personnel/personnel_shell.dart';
import '../../accomplishment/presentation/material_sheets.dart';
import '../../tools/data/models/tool.dart';
import '../../tools/data/models/tool_request.dart';
import '../../tools/presentation/tool_sheets.dart';
import '../../work_orders/presentation/personnel/my_work_orders_screen.dart';
import '../../work_orders/presentation/personnel/personnel_providers.dart';
import '../../work_orders/presentation/personnel/widgets/personnel_widgets.dart';
import '../domain/personnel_scan_resolver.dart';
import '../domain/qr_lookup.dart';

final personnelScanResolverProvider = Provider<PersonnelScanResolver>(
  (ref) => PersonnelScanResolver(
    ref.watch(inventoryRepositoryProvider),
    ref.watch(toolRepositoryProvider),
    ref.watch(qrLookupProvider),
  ),
);

/// What [code] identified, resolved once per code.
final scanMatchProvider = FutureProvider.autoDispose
    .family<Result<ScanMatch>, String>(
      (ref, code) => ref.watch(personnelScanResolverProvider).resolve(code),
    );

/// What a scanned code identified, and what can be done with it
/// (Objective 5.C; the gold "+" scans, then opens this). Not in the
/// design: built from the personnel pages' own cards, flagged.
class ScanResultScreen extends ConsumerWidget {
  const ScanResultScreen({required this.code, super.key});

  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    padding: EdgeInsets.fromLTRB(16, 8, 16, personnelBottomInset(context)),
    children: [
      Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: () => context.canPop()
                ? context.pop()
                : context.go(RoutePaths.personnelDashboard),
            icon: const Icon(Icons.arrow_back, color: AppColors.myReportsTitle),
          ),
          Expanded(
            child: Semantics(
              header: true,
              child: const Text(
                'Scanned code',
                style: AppTextStyles.personnelGreeting,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () => PersonnelShell.scan(context, ref),
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text('Scan again'),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.only(left: 12, bottom: 16),
        child: Text(code, style: AppTextStyles.personnelWorkOrderId),
      ),
      AsyncValueView<ScanMatch>(
        value: ref.watch(scanMatchProvider(code)),
        onRetry: () => ref.invalidate(scanMatchProvider(code)),
        loading: Skeleton.cards(count: 1, height: 120, radius: 16),
        data: (match) => switch (match) {
          MaterialMatch(:final item) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PersonnelCard(
                edge: AppColors.accentGold,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            style: AppTextStyles.personnelSection,
                          ),
                        ),
                        StockChip(item: item),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${item.category} · ${formatQuantity(item.quantityAvailable)} '
                      '${item.unitOfMeasurement} in stock · ${item.storageLocation}',
                      style: AppTextStyles.personnelCardBody,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => showRecordMaterialSheet(context, item: item),
                icon: const Icon(Icons.add_shopping_cart_rounded),
                label: const Text('Record use on a work order'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.textPrimary,
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            ],
          ),
          ToolMatch(:final tool) => _ToolActions(tool: tool, code: code),
          PlaceMatch(:final place) => _PlaceWork(place: place),
        },
      ),
    ],
  );
}

/// What the technician can do with a scanned tool. Since 2026-11-16 the
/// scan itself is the confirmation: a checkout GSU sent them is confirmed
/// here, a return GSU asked for is confirmed here, and a tool on the shelf
/// is borrowed here, each with the code just scanned.
class _ToolActions extends ConsumerWidget {
  const _ToolActions({required this.tool, required this.code});

  final Tool tool;

  /// The code that found [tool]: what each hand-over is confirmed with,
  /// and read again once one is done, so the page shows where the tool is.
  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(signedInUidProvider);
    final mine = tool.currentHolderId != null && tool.currentHolderId == uid;
    final loan = switch (ref.watch(myToolLoansProvider)) {
      AsyncData(value: Success(:final value)) =>
        value.where((loan) => loan.toolId == tool.id).firstOrNull,
      _ => null,
    };
    // GSU's request about this tool, if it was made of this technician.
    final request = switch (ref.watch(myToolRequestsProvider)) {
      AsyncData(value: Success(:final value)) =>
        value
            .where((request) => request.toolId == tool.id && request.isPending)
            .firstOrNull,
      _ => null,
    };

    Future<void> then(Future<void> step) async {
      await step;
      if (context.mounted) ref.invalidate(scanMatchProvider(code));
    }

    Widget button(String label, IconData icon, VoidCallback onPressed) =>
        FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.textPrimary,
            minimumSize: const Size.fromHeight(52),
          ),
        );

    final checkOut = request?.kind == ToolRequestKind.checkOut ? request : null;
    final checkIn = request?.kind == ToolRequestKind.checkIn ? request : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PersonnelCard(
          edge: AppColors.accentGold,
          child: ToolSummary(tool: tool),
        ),
        const SizedBox(height: 16),
        if (checkOut != null && tool.status == ToolStatus.reserved) ...[
          ToolRequestCard(request: checkOut),
          const SizedBox(height: 16),
          button(
            'Confirm receipt',
            Icons.verified_outlined,
            () => then(
              showConfirmCheckOutSheet(context, checkOut, scannedCode: code),
            ),
          ),
        ] else if (mine && loan != null) ...[
          if (checkIn != null) ...[
            ToolRequestCard(request: checkIn),
            const SizedBox(height: 16),
          ],
          button(
            checkIn == null ? 'Return' : 'Confirm return',
            Icons.assignment_return_outlined,
            () => then(
              showReturnToolSheet(
                context,
                loan,
                scannedCode: code,
                request: checkIn,
              ),
            ),
          ),
        ] else if (tool.status.isIssuable)
          button(
            'Borrow',
            Icons.handyman_outlined,
            () => then(
              showBorrowToolSheet(context, tool: tool, scannedCode: code),
            ),
          )
        else
          Text(switch (tool.status) {
            ToolStatus.reserved =>
              'This tool is reserved for another technician to collect.',
            ToolStatus.borrowed when mine => 'You have this tool.',
            ToolStatus.borrowed =>
              'Another technician has this tool. It can be borrowed once '
                  'it is returned.',
            ToolStatus.inRepair => 'This tool is in repair.',
            ToolStatus.retired => 'This tool is retired.',
            ToolStatus.available => '',
          }, style: AppTextStyles.personnelSubtitle),
      ],
    );
  }
}

/// A room or asset, and the technician's work there.
class _PlaceWork extends ConsumerWidget {
  const _PlaceWork({required this.place});

  final QrMatch place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facility = place.facility;
    final asset = place.asset;
    final orders = switch (ref.watch(myWorkOrdersProvider)) {
      AsyncData(value: Success(:final value)) => [
        for (final order in value)
          if (order.facilityId == facility.id) order,
      ],
      _ => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PersonnelCard(
          edge: AppColors.accentGold,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(facility.name, style: AppTextStyles.personnelSection),
              if (facility.locationDescription case final where?)
                Text(where, style: AppTextStyles.personnelSubtitle),
              if (asset != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Equipment: ${asset.name}'
                  '${asset.serialNumber == null ? '' : ' · ${asset.serialNumber}'}',
                  style: AppTextStyles.personnelCardBody,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        const PersonnelSectionTitle('Your work here'),
        const SizedBox(height: 12),
        switch (orders) {
          null => const LinearProgressIndicator(minHeight: 2),
          [] => const PersonnelCard(
            child: Text(
              'None of your work orders is at this place.',
              style: AppTextStyles.personnelCardBody,
            ),
          ),
          final list => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final order in list) ...[
                WorkOrderCard(workOrder: order, showStatus: true),
                const SizedBox(height: 12),
              ],
            ],
          ),
        },
      ],
    );
  }
}
