import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';

/// The end of a table row in the console (§34): a **View** button, then
/// one ⋮ menu with what else the row can do. The Damage Reports and Work
/// Order tables share these, so a row reads the same on both.

/// "View": the small olive outline the design draws on the reports table.
class RowViewButton extends StatelessWidget {
  const RowViewButton({required this.onPressed, super.key});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.accentOlive,
      side: const BorderSide(color: AppColors.accentOlive),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
    ),
    child: const Text('View', style: AppTextStyles.rowActionText),
  );
}

/// The row's ⋮: [tooltip] names the row ("Actions for #REP-12"), so a
/// screen reader, and a test, can tell one row's menu from another's.
class RowMenuButton<T> extends StatelessWidget {
  const RowMenuButton({
    required this.tooltip,
    required this.items,
    required this.onSelected,
    super.key,
  });

  final String tooltip;
  final List<PopupMenuEntry<T>> items;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<T>(
    tooltip: tooltip,
    icon: const Icon(Icons.more_vert, size: 20, color: AppColors.iconMuted),
    position: PopupMenuPosition.under,
    // Sized to the row, not to a 48 px touch target that would make
    // every row taller than its text.
    style: IconButton.styleFrom(
      padding: EdgeInsets.zero,
      minimumSize: const Size(32, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    onSelected: onSelected,
    itemBuilder: (context) => items,
  );
}

/// One line of a row's menu: what it does and, when the row cannot do it
/// now, why not, in a caption under the name. A disabled entry with no
/// reason would leave the administrator guessing.
class RowMenuEntry extends StatelessWidget {
  const RowMenuEntry(this.label, {this.reason, super.key});

  final String label;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final reason = this.reason;
    if (reason == null) return Text(label);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: 2),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Text(reason, style: AppTextStyles.tableCellCaption),
        ),
      ],
    );
  }
}
