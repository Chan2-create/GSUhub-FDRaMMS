import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/breakpoints.dart';
import '../../../core/enums/tool_status.dart';
import '../../../core/utils/quantity_format.dart';
import '../../../core/utils/result.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../tools/presentation/tool_providers.dart';
import '../../tools/presentation/tools_section.dart';
import '../../work_orders/presentation/work_order_providers.dart';
import '../data/models/inventory_item.dart';
import '../data/models/material_request.dart';
import 'inventory_providers.dart';
import 'widgets/inventory_widgets.dart';
import 'widgets/material_dialogs.dart';
import 'widgets/request_review.dart';

/// Inventory Management (Figma `200:4032`, manuscript Figure 15;
/// Objectives 6.A–6.B).
///
/// Every number and row is read live from `inventory_items`, `tools`,
/// `tool_loans` and `material_requests`. The mockup's $142,500 / 84 / 09
/// / 15 and its sample rows appear nowhere here.
class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => SingleChildScrollView(
    padding: EdgeInsets.symmetric(
      horizontal: Breakpoints.gutter(context),
      vertical: Breakpoints.gutter(context) * 1.5,
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatRow(),
        _RequestsSection(),
        SizedBox(height: 64),
        _MaterialsSection(),
        SizedBox(height: 64),
        ToolsSection(),
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
                    // On the photo, opposite the badge: the row below has
                    // no room for a third button at the usual card width.
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Material(
                        color: AppColors.surface.withValues(alpha: 0.9),
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: 'Delete ${item.name}',
                          visualDensity: VisualDensity.compact,
                          onPressed: () =>
                              showDeleteMaterialDialog(context, item),
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: AppColors.inventoryLabel,
                          ),
                        ),
                      ),
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
