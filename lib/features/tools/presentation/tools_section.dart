import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/enums/tool_status.dart';
import '../../../core/utils/result.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../inventory/presentation/widgets/inventory_widgets.dart';
import '../../inventory/presentation/widgets/material_dialogs.dart';
import '../../qr_codes/domain/personnel_scan_resolver.dart';
import '../../qr_codes/presentation/qr_label.dart';
import '../../qr_codes/presentation/qr_label_actions.dart';
import '../../qr_codes/presentation/qr_scanner_screen.dart';
import '../../qr_codes/presentation/scan_result_screen.dart';
import '../../user_management/presentation/personnel_providers.dart';
import '../data/models/tool.dart';
import '../data/models/tool_loan.dart';
import 'tool_providers.dart';
import 'widgets/tool_dialogs.dart';

/// "Tool Assets & Tracking", the tools half of the console's Inventory
/// page (Figure 15; Objective 6.B): every tool, its status and condition,
/// who has it, its QR label, and Check Out, Check In and Delete. Scan QR
/// opens a material's or tool's record from its label.
///
/// Moved out of the inventory screen on 2026-11-14 so that the tools
/// feature holds all of its own screens; nothing in it changed.
class ToolsSection extends ConsumerStatefulWidget {
  const ToolsSection({super.key});

  @override
  ConsumerState<ToolsSection> createState() => _ToolsSectionState();
}

class _ToolsSectionState extends ConsumerState<ToolsSection> {
  static const int _pageSize = 5;
  int _page = 0;

  /// Figure 15's Scan QR: finds a material or tool by its label.
  Future<void> _scan() async {
    final code = await ref.read(consoleScanLauncherProvider)(context);
    if (code == null || !mounted) return;
    final match = await ref.read(personnelScanResolverProvider).resolve(code);
    if (!mounted) return;
    switch (match) {
      case Success(value: MaterialMatch(:final item)):
        await showMaterialDetailsDialog(context, item.id);
      case Success(value: ToolMatch(:final tool)):
        await showToolDetailsDialog(context, tool.id);
      case Success(value: PlaceMatch(:final place)):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'That is the label of ${place.facility.buildingName}'
              '${place.facility.roomIdentifier == null ? '' : ', ${place.facility.roomIdentifier}'}'
              '. Rooms are on the Facilities & Equipment page.',
            ),
          ),
        );
      case Error(:final failure):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(failure.message),
            backgroundColor: AppColors.error,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tools = ref.watch(allToolsProvider);
    final loans = switch (ref.watch(openLoansProvider)) {
      AsyncData(value: Success(:final value)) => {
        for (final loan in value) loan.id: loan,
      },
      _ => const <String, ToolLoan>{},
    };
    final names = ref.watch(personnelNamesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InventorySectionHeader(
          title: 'Tool Assets & Tracking',
          actions: [
            InventoryOutlineButton(
              label: 'Scan QR',
              iconAsset: 'assets/icons/inventory_scan.svg',
              onPressed: _scan,
            ),
            InventoryTonalButton(
              label: 'Add New Tool',
              onPressed: () => showToolFormDialog(context),
            ),
          ],
        ),
        const SizedBox(height: 24),
        AsyncValueView<List<Tool>>(
          value: tools,
          loadingHeight: 300,
          onRetry: () => ref.invalidate(allToolsProvider),
          data: (tools) {
            final pages = (tools.length / _pageSize).ceil().clamp(1, 1 << 20);
            final page = _page.clamp(0, pages - 1);
            final rows = tools.skip(page * _pageSize).take(_pageSize).toList();
            return _ToolTable(
              rows: rows,
              loans: loans,
              names: names,
              footer: _TableFooter(
                first: tools.isEmpty ? 0 : page * _pageSize + 1,
                last: page * _pageSize + rows.length,
                total: tools.length,
                page: page,
                pages: pages,
                onPage: (page) => setState(() => _page = page),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ToolTable extends StatelessWidget {
  const _ToolTable({
    required this.rows,
    required this.loans,
    required this.names,
    required this.footer,
  });

  final List<Tool> rows;
  final Map<String, ToolLoan> loans;
  final Map<String, String> names;
  final Widget footer;

  /// Figure 15's column widths, as flex weights; Actions took 40 from Tool
  /// Name for the delete button (2026-11-08), so a row stays one line.
  static const List<(String, int, Alignment)> _columns = [
    ('Tool ID', 106, Alignment.centerLeft),
    ('Tool Name', 176, Alignment.centerLeft),
    ('Status', 135, Alignment.centerLeft),
    ('Condition', 109, Alignment.centerLeft),
    ('Current User', 153, Alignment.centerLeft),
    ('QR', 88, Alignment.center),
    ('Actions', 190, Alignment.centerRight),
  ];

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.surface,
      border: Border.all(color: AppColors.borderStrong),
      borderRadius: BorderRadius.circular(8),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0D000000),
          offset: Offset(0, 1),
          blurRadius: 2,
        ),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final table = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColoredBox(
              color: AppColors.inventoryTableBand,
              child: _row([
                for (final (label, _, _) in _columns)
                  Text(label, style: AppTextStyles.inventoryCaption),
              ]),
            ),
            const Divider(height: 1, color: AppColors.borderStrong),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No tools yet. Register the store’s tools with Add New '
                  'Tool.',
                  style: AppTextStyles.inventoryStatNote,
                  textAlign: TextAlign.center,
                ),
              ),
            for (final tool in rows) ...[
              _toolRow(context, tool),
              const Divider(height: 1, color: AppColors.borderStrong),
            ],
            ColoredBox(color: AppColors.inventoryTableBand, child: footer),
          ],
        );
        // Below the design's width the table scrolls sideways rather
        // than squeezing its columns.
        if (constraints.maxWidth >= 900) return table;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: 960, child: table),
        );
      },
    ),
  );

  Widget _row(List<Widget> cells, {double vertical = 16}) => Row(
    children: [
      for (var i = 0; i < cells.length; i++)
        Expanded(
          flex: _columns[i].$2,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: vertical),
            child: Align(alignment: _columns[i].$3, child: cells[i]),
          ),
        ),
    ],
  );

  Widget _toolRow(BuildContext context, Tool tool) {
    final holder = tool.currentHolderId;
    final holderName = holder == null ? null : names[holder] ?? 'A technician';
    final loan = tool.currentLoanId == null ? null : loans[tool.currentLoanId];
    return _row([
      InkWell(
        onTap: () => showToolDetailsDialog(context, tool.id),
        child: Text(
          tool.toolCode,
          style: AppTextStyles.inventoryCellStrong,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      InkWell(
        onTap: () => showToolDetailsDialog(context, tool.id),
        child: Text(
          tool.name,
          style: AppTextStyles.inventoryCell,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      InventoryBadge.tool(tool.status),
      Text(tool.condition.label, style: AppTextStyles.inventoryCell),
      if (holderName == null)
        Text(
          '—',
          style: AppTextStyles.inventoryCell.copyWith(
            fontStyle: FontStyle.italic,
            color: AppColors.inventoryLabel,
          ),
        )
      else
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InventoryAvatar(name: holderName),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                holderName,
                style: AppTextStyles.inventoryCell,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      IconButton(
        tooltip: 'QR label for ${tool.toolCode}',
        onPressed: () => showQrLabelDialog(context, QrLabel.tool(tool)),
        icon: SvgPicture.asset('assets/icons/inventory_qr.svg'),
      ),
      Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          _toolAction(context, tool, holderName, loan),
          _delete(context, tool),
        ],
      ),
    ], vertical: 20);
  }

  /// Delete, after asking; a tool out on loan is refused, and says so.
  Widget _delete(BuildContext context, Tool tool) => IconButton(
    tooltip: 'Delete ${tool.name}',
    visualDensity: VisualDensity.compact,
    onPressed: () => showDeleteToolDialog(context, tool),
    icon: const Icon(
      Icons.delete_outline,
      size: 20,
      color: AppColors.inventoryLabel,
    ),
  );

  Widget _toolAction(
    BuildContext context,
    Tool tool,
    String? holderName,
    ToolLoan? loan,
  ) => switch (tool.status) {
    ToolStatus.available => InventoryNavyButton(
      label: 'Check Out',
      onPressed: () => showCheckOutDialog(context, tool),
    ),
    ToolStatus.borrowed => TextButton(
      onPressed: tool.currentLoanId == null
          ? null
          : () => showCheckInDialog(
              context,
              toolName: tool.name,
              loanId: tool.currentLoanId!,
              conditionOnBorrow: loan?.conditionOnBorrow ?? tool.condition,
              holderName: holderName,
            ),
      child: Text(
        'Check In',
        style: AppTextStyles.inventoryCellStrong.copyWith(
          color: AppColors.inventoryHeading,
        ),
      ),
    ),
    ToolStatus.inRepair => Tooltip(
      message: 'In repair. Bring it back from its details.',
      child: Text(
        'Locked',
        style: AppTextStyles.inventoryCellStrong.copyWith(
          color: AppColors.inventoryLabel,
        ),
      ),
    ),
    ToolStatus.retired => Text(
      'Retired',
      style: AppTextStyles.inventoryCellStrong.copyWith(
        color: AppColors.inventoryLabel,
      ),
    ),
  };
}

/// "Showing 1-5 of 124 tools", with the page and its arrows.
class _TableFooter extends StatelessWidget {
  const _TableFooter({
    required this.first,
    required this.last,
    required this.total,
    required this.page,
    required this.pages,
    required this.onPage,
  });

  final int first;
  final int last;
  final int total;
  final int page;
  final int pages;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    Widget arrow(String asset, String tooltip, VoidCallback? onPressed) =>
        Tooltip(
          message: tooltip,
          child: InkWell(
            onTap: onPressed,
            child: Opacity(
              opacity: onPressed == null ? 0.4 : 1,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.borderStrong),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: SvgPicture.asset(asset, width: 12, height: 12),
              ),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              total == 0
                  ? 'No tools'
                  : 'Showing $first-$last of $total tool${total == 1 ? '' : 's'}',
              style: AppTextStyles.inventoryCell.copyWith(
                color: AppColors.inventoryLabel,
              ),
            ),
          ),
          arrow(
            'assets/icons/page_prev.svg',
            'Previous page',
            page > 0 ? () => onPage(page - 1) : null,
          ),
          const SizedBox(width: 8),
          Text('${page + 1}', style: AppTextStyles.inventoryCellStrong),
          const SizedBox(width: 8),
          arrow(
            'assets/icons/page_next.svg',
            'Next page',
            page < pages - 1 ? () => onPage(page + 1) : null,
          ),
        ],
      ),
    );
  }
}
