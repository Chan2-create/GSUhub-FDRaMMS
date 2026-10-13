import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/enums/tool_status.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/initials.dart';
import '../../../../core/utils/result.dart';
import '../../data/models/inventory_item.dart';

/// Pieces Figure 15 (Figma `200:4032`) draws more than once.

/// A section's heading over a rule, with its controls on the right:
/// "Consumable Materials", "Tool Assets & Tracking".
class InventorySectionHeader extends StatelessWidget {
  const InventorySectionHeader({
    required this.title,
    this.actions = const [],
    super.key,
  });

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.borderStrong)),
    ),
    child: Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 12,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: AppTextStyles.inventorySection),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: actions,
          ),
        ],
      ),
    ),
  );
}

/// The rounded pill on a card's photo or in the Status column.
class InventoryBadge extends StatelessWidget {
  const InventoryBadge({
    required this.label,
    required this.background,
    required this.foreground,
    this.horizontalPadding = 8,
    super.key,
  });

  /// IN STOCK, LOW STOCK or OUT OF STOCK, for a material.
  factory InventoryBadge.stock(InventoryItem item) => switch (item) {
    _ when item.isOutOfStock => const InventoryBadge(
      label: 'OUT OF STOCK',
      background: AppColors.inventoryRepairFill,
      foreground: AppColors.inventoryRepairText,
    ),
    _ when item.isLowStock => const InventoryBadge(
      label: 'LOW STOCK',
      background: AppColors.inventoryLowStockFill,
      foreground: AppColors.inventoryLowStockText,
    ),
    _ => const InventoryBadge(
      label: 'IN STOCK',
      background: AppColors.inventoryInStockFill,
      foreground: AppColors.inventoryInStockText,
    ),
  };

  /// A tool's status, as the table's Status column draws it.
  factory InventoryBadge.tool(ToolStatus status) => switch (status) {
    ToolStatus.available => const InventoryBadge(
      label: 'AVAILABLE',
      background: AppColors.inventoryInStockFill,
      foreground: AppColors.inventoryInStockText,
      horizontalPadding: 12,
    ),
    ToolStatus.borrowed => const InventoryBadge(
      label: 'BORROWED',
      background: AppColors.inventoryBorrowedFill,
      foreground: AppColors.inventoryBorrowedText,
      horizontalPadding: 12,
    ),
    ToolStatus.inRepair => const InventoryBadge(
      label: 'IN REPAIR',
      background: AppColors.inventoryRepairFill,
      foreground: AppColors.inventoryRepairText,
      horizontalPadding: 12,
    ),
    ToolStatus.retired => const InventoryBadge(
      label: 'RETIRED',
      background: AppColors.surfaceSunken,
      foreground: AppColors.inventoryLabel,
      horizontalPadding: 12,
    ),
  };

  final String label;
  final Color background;
  final Color foreground;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Padding(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 2.5,
      ),
      child: Text(
        label,
        style: AppTextStyles.inventoryBadge.copyWith(color: foreground),
      ),
    ),
  );
}

/// "Scan QR": navy outline, icon and label.
class InventoryOutlineButton extends StatelessWidget {
  const InventoryOutlineButton({
    required this.label,
    required this.iconAsset,
    required this.onPressed,
    super.key,
  });

  final String label;
  final String iconAsset;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: SvgPicture.asset(iconAsset),
    label: Text(label, style: AppTextStyles.inventoryButton),
    style: OutlinedButton.styleFrom(
      // Figure 15's sizes, on every platform: desktop's compact density
      // would take 8px off the padding.
      visualDensity: VisualDensity.standard,
      foregroundColor: AppColors.inventoryHeading,
      side: const BorderSide(color: AppColors.inventoryHeading),
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
  );
}

/// "Add New Tool": pale blue fill, navy label.
class InventoryTonalButton extends StatelessWidget {
  const InventoryTonalButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: onPressed,
    icon: SvgPicture.asset('assets/icons/inventory_add.svg'),
    label: Text(label, style: AppTextStyles.inventoryButton),
    style: FilledButton.styleFrom(
      visualDensity: VisualDensity.standard,
      backgroundColor: AppColors.inventoryAddFill,
      foregroundColor: AppColors.inventoryHeading,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
  );
}

/// "Check Out", "ORDER": a small navy button with square corners.
class InventoryNavyButton extends StatelessWidget {
  const InventoryNavyButton({
    required this.label,
    required this.onPressed,
    this.compact = false,
    this.semanticLabel,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;

  /// What a screen reader says in place of [label], when the label alone
  /// does not say which item it acts on: "Order more PVC Pipe".
  final String? semanticLabel;

  /// ORDER's 10px capitals, rather than Check Out's 14px.
  final bool compact;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      // Desktop's compact density would take all 8px of vertical padding,
      // squashing the button to its text.
      visualDensity: VisualDensity.standard,
      backgroundColor: AppColors.inventoryHeading,
      foregroundColor: Colors.white,
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.padded,
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 8)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
    ),
    child: Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: Text(
        label,
        style: compact
            ? AppTextStyles.inventoryBadge
            : AppTextStyles.inventoryButton,
      ),
    ),
  );
}

/// The 24px initials circle in Current User. Navy or gold by the name, so
/// two technicians side by side are told apart (the design alternates).
class InventoryAvatar extends StatelessWidget {
  const InventoryAvatar({required this.name, super.key});

  final String name;

  @override
  Widget build(BuildContext context) {
    final gold = name.codeUnits.fold(0, (sum, unit) => sum + unit).isOdd;
    return ExcludeSemantics(
      child: Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: gold
              ? AppColors.inventoryLowStockFill
              : AppColors.inventoryAvatarFill,
          shape: BoxShape.circle,
        ),
        child: Text(
          initialsOf(name),
          style: AppTextStyles.inventoryBadge.copyWith(
            letterSpacing: 0,
            color: gold
                ? AppColors.inventoryLowStockText
                : AppColors.inventoryAvatarText,
          ),
        ),
      ),
    );
  }
}

/// A snackbar for an action's outcome: [success] when it worked, the
/// failure's own words when not.
void showInventoryOutcome(
  BuildContext context,
  Result<Object?> result,
  String success,
) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(switch (result) {
      Success() => SnackBar(content: Text(success)),
      Error(:final failure) => SnackBar(
        content: Text(_messageOf(failure)),
        backgroundColor: AppColors.error,
      ),
    });
}

String _messageOf(Failure failure) => failure.message;

/// A positive number typed into a field, or null. Commas are allowed.
double? parseQuantity(String text) =>
    double.tryParse(text.trim().replaceAll(',', ''));
