import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/enums/tool_status.dart';
import '../../../core/utils/quantity_format.dart';
import '../../../core/utils/result.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../qr_labels/qr_label.dart';
import '../../qr_labels/qr_label_actions.dart';
import '../../reporting/presentation/submission/qr_scanner_screen.dart';
import '../../scanning/domain/personnel_scan_resolver.dart';
import '../../scanning/presentation/scan_result_screen.dart';
import '../../tools/data/models/tool.dart';
import '../../tools/data/models/tool_loan.dart';
import '../../user_management/presentation/personnel_providers.dart';
import '../../work_orders/presentation/work_order_providers.dart';
import '../data/models/inventory_item.dart';
import '../data/models/material_request.dart';
import 'inventory_providers.dart';
import 'widgets/inventory_widgets.dart';
import 'widgets/material_dialogs.dart';
import 'widgets/request_review.dart';
import 'widgets/tool_dialogs.dart';

/// The console's camera scanner for Figure 15's Scan QR: any code GSUhub
/// prints. A provider so tests can answer without a camera.
final consoleScanLauncherProvider = Provider<QrScanLauncher>(
  (ref) =>
      (context) => Navigator.of(context).push<String>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const QrScannerScreen(
            title: 'Scan a label',
            guidance: 'Hold the label of a material or tool up to the camera.',
            fallback: 'find it in the lists on this page instead',
            formats: [BarcodeFormat.all],
          ),
        ),
      ),
);

/// Inventory Management (Figma `200:4032`, manuscript Figure 15;
/// Objectives 6.A–6.B).
///
/// Every number and row is read live from `inventory_items`, `tools`,
/// `tool_loans` and `material_requests`. The mockup's $142,500 / 84 / 09
/// / 15 and its sample rows appear nowhere here.
class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      const SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatRow(),
            _RequestsSection(),
            SizedBox(height: 64),
            _MaterialsSection(),
            SizedBox(height: 64),
            _ToolsSection(),
          ],
        ),
      );
}

// --- stat cards ---------------------------------------------------------

class _StatRow extends ConsumerWidget {
  const _StatRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref
        .watch(inventoryItemsProvider)
        .value
        ?.fold((items) => items, (_) => null);
    final tools = ref
        .watch(allToolsProvider)
        .value
        ?.fold((tools) => tools, (_) => null);
    final loans = ref
        .watch(openLoansProvider)
        .value
        ?.fold((loans) => loans, (_) => null);

    final priced = items?.where((item) => item.unitCost != null).toList();
    final unpriced = items == null ? 0 : items.length - priced!.length;
    final value = priced?.fold<double>(
      0,
      (sum, item) => sum + item.stockValue!,
    );
    final low = items?.where((item) => item.isLowStock).length;

    final now = DateTime.now();
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final startOfToday = DateTime(now.year, now.month, now.day);
    final due = loans
        ?.where(
          (loan) => switch (loan.expectedReturnAt?.toLocal()) {
            final at? => !at.isBefore(startOfToday) && !at.isAfter(endOfToday),
            null => false,
          },
        )
        .length;
    final overdue = loans
        ?.where(
          (loan) =>
              loan.expectedReturnAt?.toLocal().isBefore(startOfToday) ?? false,
        )
        .length;
    final inRepair = tools
        ?.where((tool) => tool.status == ToolStatus.inRepair)
        .length;

    final cards = [
      _StatCard(
        label: 'Total Stock Value',
        iconAsset: 'assets/icons/inventory_stock_value.svg',
        value: value == null ? null : QuantityFormat.wholePesos(value),
        note: items == null
            ? null
            : unpriced == 0
            ? 'Across ${items.length} material${items.length == 1 ? '' : 's'}'
            : '$unpriced material${unpriced == 1 ? ' has' : 's have'} no unit '
                  'cost yet',
        definition:
            'Quantity in stock × unit cost, for every material with a unit '
            'cost.',
      ),
      _StatCard(
        label: 'Active Tool Loans',
        iconAsset: 'assets/icons/inventory_loans.svg',
        value: loans?.length.toString(),
        note: loans == null
            ? null
            : [
                '${due ?? 0} due today',
                if ((overdue ?? 0) > 0) '$overdue overdue',
              ].join(' · '),
        noteColor: (overdue ?? 0) > 0 ? AppColors.error : null,
        definition:
            'Tools out with a technician. Due today counts loans whose '
            'return date is today.',
      ),
      _StatCard(
        label: 'Low Stock Alerts',
        iconAsset: 'assets/icons/inventory_low_stock.svg',
        // The design writes the count with two digits: "09".
        value: low?.toString().padLeft(2, '0'),
        valueColor: (low ?? 0) > 0 ? AppColors.error : null,
        note: low == null
            ? null
            : low > 0
            ? 'Action required soon'
            : 'Every material is above its minimum',
        noteColor: (low ?? 0) > 0 ? AppColors.error : null,
        definition:
            'Materials at or below the minimum set for them (§1.5). Each '
            'shows LOW STOCK and an ORDER button.',
      ),
      _StatCard(
        label: 'Tools in Repair',
        iconAsset: 'assets/icons/inventory_repair.svg',
        value: inRepair?.toString(),
        note: tools == null ? null : 'Of ${tools.length} tools in total',
        definition:
            'Tools sent to repair, including any checked in in poor '
            'condition.',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 500
            ? 2
            : 1;
        final width = (constraints.maxWidth - 24 * (columns - 1)) / columns;
        return Wrap(
          spacing: 24,
          runSpacing: 24,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }
}

/// Figure 15's summary tile: caption and icon, the number, a line under it.
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.iconAsset,
    required this.value,
    required this.note,
    required this.definition,
    this.valueColor,
    this.noteColor,
  });

  final String label;
  final String iconAsset;

  /// Null while loading or unreadable: drawn as a dash.
  final String? value;
  final String? note;
  final String definition;
  final Color? valueColor;
  final Color? noteColor;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: definition,
    child: Semantics(
      container: true,
      label: '$label: ${value ?? 'not available'}. ${note ?? ''}',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.borderStrong),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D000000),
              offset: Offset(0, 1),
              blurRadius: 1,
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(25, 25, 25, 29),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: AppTextStyles.inventoryCaption,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SvgPicture.asset(iconAsset),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value ?? '—',
              style: AppTextStyles.inventoryStatValue.copyWith(
                color: valueColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              note ?? '',
              style: AppTextStyles.inventoryStatNote.copyWith(color: noteColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    ),
  );
}

// --- material requests --------------------------------------------------

class _RequestsSection extends ConsumerStatefulWidget {
  const _RequestsSection();

  @override
  ConsumerState<_RequestsSection> createState() => _RequestsSectionState();
}

class _RequestsSectionState extends ConsumerState<_RequestsSection> {
  bool _showDecided = false;

  @override
  Widget build(BuildContext context) {
    final requests = ref.watch(recentMaterialRequestsProvider);
    final titles = switch (ref.watch(workOrdersStreamProvider)) {
      AsyncData(value: Success(:final value)) => {
        for (final order in value) order.id: order.title,
      },
      _ => const <String, String>{},
    };

    return switch (requests) {
      AsyncData(value: Success(:final value)) when value.isNotEmpty => () {
        final pending = [
          for (final request in value)
            if (request.isPending) request,
        ];
        final decided = [
          for (final request in value)
            if (!request.isPending) request,
        ].take(5).toList();
        Widget card(MaterialRequest request) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: MaterialRequestCard(
            request: request,
            workOrderTitle: titles[request.workOrderId],
          ),
        );
        return Padding(
          padding: const EdgeInsets.only(top: 64),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InventorySectionHeader(
                title: 'Material Requests',
                actions: [
                  if (decided.isNotEmpty)
                    TextButton(
                      onPressed: () =>
                          setState(() => _showDecided = !_showDecided),
                      child: Text(
                        _showDecided ? 'Hide decided' : 'Show recently decided',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              if (pending.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'No request is waiting for review.',
                    style: AppTextStyles.inventoryStatNote,
                  ),
                ),
              for (final request in pending) card(request),
              if (_showDecided)
                for (final request in decided) card(request),
            ],
          ),
        );
      }(),
      // Quiet until there is something to review: the page is Figure 15's.
      _ => const SizedBox.shrink(),
    };
  }
}

// --- consumable materials ----------------------------------------------

class _MaterialsSection extends ConsumerStatefulWidget {
  const _MaterialsSection();

  @override
  ConsumerState<_MaterialsSection> createState() => _MaterialsSectionState();
}

class _MaterialsSectionState extends ConsumerState<_MaterialsSection> {
  final _search = TextEditingController();
  String? _category;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(inventoryItemsProvider);
    final categories = switch (items) {
      AsyncData(value: Success(:final value)) => {
        for (final item in value) item.category,
      }.toList()..sort(),
      _ => const <String>[],
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InventorySectionHeader(
          title: 'Consumable Materials',
          actions: [
            SizedBox(
              width: 256,
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                style: AppTextStyles.inventoryControl,
                decoration: InputDecoration(
                  hintText: 'Search materials...',
                  hintStyle: AppTextStyles.inventoryControl.copyWith(
                    color: AppColors.inventoryPlaceholder,
                  ),
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.fromLTRB(17, 11, 8, 12),
                  suffixIcon: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SvgPicture.asset(
                      'assets/icons/inventory_search_filter.svg',
                    ),
                  ),
                  suffixIconConstraints: const BoxConstraints(),
                  border: _outline,
                  enabledBorder: _outline,
                ),
              ),
            ),
            _CategorySelect(
              categories: categories,
              value: _category,
              onChanged: (category) => setState(() => _category = category),
            ),
            InventoryTonalButton(
              label: 'Add Material',
              onPressed: () => showMaterialFormDialog(context),
            ),
          ],
        ),
        const SizedBox(height: 24),
        AsyncValueView<List<InventoryItem>>(
          value: items,
          loadingHeight: 312,
          onRetry: () => ref.invalidate(inventoryItemsProvider),
          data: (items) {
            final query = _search.text.trim().toLowerCase();
            final shown = [
              for (final item in items)
                if ((_category == null || item.category == _category) &&
                    (query.isEmpty ||
                        item.name.toLowerCase().contains(query) ||
                        item.category.toLowerCase().contains(query) ||
                        item.qrCode.toLowerCase().contains(query)))
                  item,
            ];
            if (shown.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  items.isEmpty
                      ? 'No materials yet. Add the store’s materials with Add '
                            'Material.'
                      : 'No material matches.',
                  style: AppTextStyles.inventoryStatNote,
                  textAlign: TextAlign.center,
                ),
              );
            }
            return LayoutBuilder(
              builder: (context, constraints) {
                const gap = 24.0;
                final columns = ((constraints.maxWidth + gap) / (180 + gap))
                    .floor()
                    .clamp(1, 5);
                final width =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final item in shown)
                      SizedBox(
                        width: width,
                        child: _MaterialCard(item: item),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }

  static const _outline = OutlineInputBorder(
    borderSide: BorderSide(color: AppColors.borderStrong),
  );
}

/// "Category: All", as Figure 15 draws it.
class _CategorySelect extends StatelessWidget {
  const _CategorySelect({
    required this.categories,
    required this.value,
    required this.onChanged,
  });

  final List<String> categories;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String?>(
    tooltip: 'Filter by category',
    initialValue: value,
    onSelected: onChanged,
    itemBuilder: (context) => [
      const PopupMenuItem<String?>(child: Text('All')),
      for (final category in categories)
        PopupMenuItem<String?>(value: category, child: Text(category)),
    ],
    child: Container(
      padding: const EdgeInsets.fromLTRB(17, 9, 9, 9),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.borderStrong),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Category: ${value ?? 'All'}',
            style: AppTextStyles.inventoryControl,
          ),
          const SizedBox(width: 12),
          SvgPicture.asset('assets/icons/inventory_select_chevron.svg'),
        ],
      ),
    ),
  );
}

/// One material: its photo (or an icon), stock badge, name, category and
/// size, quantity, and its edit and delivery buttons. ORDER replaces the
/// cart when stock is low.
class _MaterialCard extends StatelessWidget {
  const _MaterialCard({required this.item});

  final InventoryItem item;

  @override
  Widget build(BuildContext context) {
    final low = item.isLowStock;
    final photo = item.photoUrl;
    return Semantics(
      container: true,
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.borderStrong),
          borderRadius: BorderRadius.circular(4),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showMaterialDetailsDialog(context, item.id),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 170.8,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: AppColors.inventoryPhotoFill,
                      child: photo == null
                          ? const Icon(
                              Icons.inventory_2_outlined,
                              size: 56,
                              color: AppColors.inventoryHeading,
                            )
                          : Image.network(
                              photo,
                              fit: BoxFit.cover,
                              semanticLabel: 'Photo of ${item.name}',
                              errorBuilder: (_, _, _) => const Icon(
                                Icons.inventory_2_outlined,
                                size: 56,
                                color: AppColors.inventoryHeading,
                              ),
                            ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: InventoryBadge.stock(item),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Two lines kept for every name, so a row of cards
                    // lines up as Figure 15's does.
                    SizedBox(
                      height: 48,
                      child: Text(
                        item.name,
                        style: AppTextStyles.inventoryCardName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [item.category, ?item.specification].join(' • '),
                      style: AppTextStyles.inventoryCaption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: QuantityFormat.amount(
                                    item.quantityAvailable,
                                  ),
                                  style: AppTextStyles.inventoryQuantity
                                      .copyWith(
                                        color: low
                                            ? AppColors.inventoryLowQuantity
                                            : null,
                                      ),
                                ),
                                TextSpan(
                                  text: ' ${item.unitOfMeasurement}',
                                  style: AppTextStyles.inventoryUnit,
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Edit ${item.name}',
                          visualDensity: VisualDensity.compact,
                          onPressed: () =>
                              showMaterialFormDialog(context, item: item),
                          icon: SvgPicture.asset(
                            'assets/icons/inventory_edit.svg',
                          ),
                        ),
                        if (low)
                          Tooltip(
                            message: 'Record stock received for ${item.name}',
                            // The button says it; spoken here, it would
                            // land on the whole card instead.
                            excludeFromSemantics: true,
                            child: InventoryNavyButton(
                              label: 'ORDER',
                              semanticLabel: 'Order more ${item.name}',
                              compact: true,
                              onPressed: () =>
                                  showDeliveryDialog(context, item),
                            ),
                          )
                        else
                          IconButton(
                            tooltip: 'Record a delivery of ${item.name}',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => showDeliveryDialog(context, item),
                            icon: SvgPicture.asset(
                              'assets/icons/inventory_cart.svg',
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- tool assets & tracking ----------------------------------------------

class _ToolsSection extends ConsumerStatefulWidget {
  const _ToolsSection();

  @override
  ConsumerState<_ToolsSection> createState() => _ToolsSectionState();
}

class _ToolsSectionState extends ConsumerState<_ToolsSection> {
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

  /// Figure 15's column widths, as flex weights.
  static const List<(String, int, Alignment)> _columns = [
    ('Tool ID', 106, Alignment.centerLeft),
    ('Tool Name', 216, Alignment.centerLeft),
    ('Status', 135, Alignment.centerLeft),
    ('Condition', 109, Alignment.centerLeft),
    ('Current User', 153, Alignment.centerLeft),
    ('QR', 88, Alignment.center),
    ('Actions', 150, Alignment.centerRight),
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
      switch (tool.status) {
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
      },
    ], vertical: 20);
  }
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
