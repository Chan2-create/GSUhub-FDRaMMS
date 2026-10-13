import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/di/service_providers.dart';
import '../../../../core/utils/quantity_format.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/section_card.dart';
import '../../../inventory/presentation/inventory_providers.dart';
import '../analytics_providers.dart';
import '../inventory_usage.dart';

/// Analytics' Inventory section (Objective 6.C, Chris's decision
/// 2026-10-13): the materials used most in the period, and the inventory
/// report as a CSV. No Figma frame: built from the page's chart cards and
/// bars.
class InventoryAnalyticsSection extends ConsumerWidget {
  const InventoryAnalyticsSection({super.key});

  static const int _shown = 8;

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final (items, movements) = switch ((
      ref.read(inventoryItemsProvider).value,
      ref.read(inventoryMovementsProvider).value,
    )) {
      (Success(value: final items), Success(value: final movements)) => (
        items,
        movements,
      ),
      _ => (null, null),
    };
    if (items == null || movements == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('The inventory is still loading. Try again.'),
        ),
      );
      return;
    }
    final range = ref.read(analyticsRangeProvider);
    final now = DateTime.now();
    final name = InventoryUsage.fileName(range, now);
    final saved = await ref
        .read(fileDownloadServiceProvider)
        .saveText(
          fileName: name,
          contents: InventoryUsage.buildCsv(
            items: items,
            movements: movements,
            range: range,
            now: now,
          ),
        );
    messenger.showSnackBar(switch (saved) {
      Success() => SnackBar(content: Text('Inventory report saved to $name.')),
      Error(:final failure) => SnackBar(
        content: Text(failure.message),
        backgroundColor: AppColors.error,
      ),
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(analyticsRangeProvider).label.toLowerCase();
    return SectionCard(
      title: 'Most Used Materials',
      subtitle:
          'Materials deducted on accomplishment reports in the $period, '
          'by how many jobs used them.',
      titleStyle: AppTextStyles.chartTitle,
      headerPadding: const EdgeInsets.fromLTRB(25, 25, 25, 0),
      contentPadding: const EdgeInsets.fromLTRB(25, 24, 25, 25),
      trailing: OutlinedButton.icon(
        onPressed: () => _export(context, ref),
        icon: const Icon(Icons.download_outlined, size: 18),
        label: const Text('Export inventory report'),
      ),
      child: AsyncValueView<List<MaterialUse>>(
        value: ref.watch(mostUsedMaterialsProvider),
        onRetry: () => ref
          ..invalidate(inventoryMovementsProvider)
          ..invalidate(inventoryItemsProvider),
        data: (uses) {
          if (uses.isEmpty) {
            return SizedBox(
              height: 120,
              child: Center(
                child: Text(
                  'No materials were used in the $period.',
                  style: AppTextStyles.bodySmall,
                ),
              ),
            );
          }
          final shown = uses.take(_shown).toList();
          final peak = shown.first.jobs;
          return Column(
            children: [
              for (var i = 0; i < shown.length; i++) ...[
                if (i > 0) const SizedBox(height: 16),
                _UseBar(
                  use: shown[i],
                  fraction: peak == 0 ? 0 : shown[i].jobs / peak,
                  color: Color.alphaBlend(
                    AppColors.primary.withValues(alpha: (_shown - i) / _shown),
                    AppColors.surface,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _UseBar extends StatelessWidget {
  const _UseBar({
    required this.use,
    required this.fraction,
    required this.color,
  });

  final MaterialUse use;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final value = use.value;
    return Semantics(
      container: true,
      label:
          '${use.name}: ${QuantityFormat.withUnit(use.quantity, use.unit)} on '
          '${use.jobs} job${use.jobs == 1 ? '' : 's'}',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  use.name.toUpperCase(),
                  style: AppTextStyles.barRowLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${QuantityFormat.withUnit(use.quantity, use.unit)} · '
                '${use.jobs} job${use.jobs == 1 ? '' : 's'}'
                '${value == null ? '' : ' · ${QuantityFormat.pesos(value)}'}',
                style: AppTextStyles.barRowValue,
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: double.infinity,
              height: 8,
              child: ColoredBox(
                color: AppColors.trackBackground,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: fraction.clamp(0.0, 1.0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
