import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';

/// One choice in a [FilterSelect].
class FilterOption<T> {
  const FilterOption({required this.value, required this.label});

  /// Null is the "no filter" choice — "All Statuses", "Damage Type".
  final T? value;
  final String label;
}

/// Dropdown used by every filter bar in the admin console.
///
/// Two looks, because the designs draw two: the Damage Reports pills
/// (`198:2800`, tinted, 4px radius) and the work-order selects
/// (`234:660`, white, 8px radius, smaller type).
class FilterSelect<T> extends StatelessWidget {
  const FilterSelect({
    required this.placeholder,
    required this.options,
    required this.value,
    required this.onChanged,
    super.key,
    this.dense = false,
    this.width,
  });

  /// Shown when nothing is selected — the design labels these by what
  /// they filter ("Damage Type"), not by the current value.
  final String placeholder;

  final List<FilterOption<T>> options;
  final T? value;
  final ValueChanged<T?> onChanged;

  /// The work-order bar's white, 8px variant.
  final bool dense;

  final double? width;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;

    // At rest the control is labelled by what it filters ("Damage Type"),
    // as the design draws it — not by its "all" option, which would read
    // as a selection nobody made.
    final selected = hasValue
        ? options.where((option) => option.value == value).firstOrNull
        : null;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            selected?.label ?? placeholder,
            style: (dense ? AppTextStyles.inputText : AppTextStyles.controlText)
                .copyWith(
                  color: hasValue ? AppColors.primary : null,
                  fontWeight: hasValue ? FontWeight.w600 : null,
                ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        SvgPicture.asset(
          dense
              ? 'assets/icons/select_chevron_small.svg'
              : 'assets/icons/select_chevron.svg',
          width: dense ? 12 : 16,
          height: dense ? 7.4 : 16,
          colorFilter: const ColorFilter.mode(
            AppColors.textSecondary,
            BlendMode.srcIn,
          ),
        ),
      ],
    );

    return PopupMenuButton<T?>(
      tooltip: placeholder,
      position: PopupMenuPosition.under,
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final option in options)
          PopupMenuItem<T?>(value: option.value, child: Text(option.label)),
      ],
      child: Container(
        width: width,
        padding: dense
            ? const EdgeInsets.symmetric(horizontal: 17, vertical: 9)
            : const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
        decoration: BoxDecoration(
          color: dense ? AppColors.surface : AppColors.surfaceTint,
          border: Border.all(color: AppColors.borderStrong),
          borderRadius: BorderRadius.circular(dense ? 8 : 4),
        ),
        child: content,
      ),
    );
  }
}
