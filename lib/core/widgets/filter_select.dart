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

/// Which frame's select to draw.
enum FilterSelectStyle {
  /// Damage Reports (Figma `198:2794`): tinted, compact.
  tinted,

  /// Work orders (Figma `234:650`): white, 8px corners.
  dense,

  /// Maintenance Personnel (Figma `201:4726`): white, tall, a 24px
  /// chevron.
  large,

  /// User Accounts (Figma `89:4726`): white, with the filter glyph where
  /// the others have a chevron.
  outlined,

  /// The mobile report form (Figma `165:137`, Objective 3.C): white, 56
  /// tall, 12px corners, filling its column. Here the select picks a value
  /// rather than filtering, so a chosen value is drawn like the placeholder
  /// rather than highlighted.
  form,
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
    this.style = FilterSelectStyle.tinted,
    this.width,
    this.leading,
    this.enabled = true,
  });

  /// Shown when nothing is selected — the design labels these by what
  /// they filter ("Damage Type"), not by the current value.
  final String placeholder;

  final List<FilterOption<T>> options;
  final T? value;
  final ValueChanged<T?> onChanged;

  final FilterSelectStyle style;

  final double? width;

  /// Drawn before the value — the urgency dot on the report form.
  final Widget? leading;

  /// False while the options are loading or the form is sending.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;

    // At rest the control is labelled by what it filters ("Damage Type"),
    // as the design draws it — not by its "all" option, which would read
    // as a selection nobody made.
    final selected = hasValue
        ? options.where((option) => option.value == value).firstOrNull
        : null;

    final isForm = style == FilterSelectStyle.form;
    final leadingWidget = leading;

    final content = Row(
      mainAxisSize: isForm ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (leadingWidget != null) ...[leadingWidget, const SizedBox(width: 8)],
        Flexible(
          fit: isForm ? FlexFit.tight : FlexFit.loose,
          child: Text(
            selected?.label ?? placeholder,
            style: isForm
                ? _textStyle
                : _textStyle.copyWith(
                    color: hasValue ? AppColors.primary : null,
                    fontWeight: hasValue ? FontWeight.w600 : null,
                  ),
            overflow: TextOverflow.ellipsis,
            maxLines: isForm ? 1 : null,
          ),
        ),
        const SizedBox(width: 8),
        _trailing(),
      ],
    );

    return PopupMenuButton<_Pick<T>>(
      tooltip: placeholder,
      enabled: enabled,
      position: PopupMenuPosition.under,
      initialValue: _Pick(value),
      onSelected: (pick) => onChanged(pick.value),
      itemBuilder: (context) => [
        for (final option in options)
          PopupMenuItem(value: _Pick(option.value), child: Text(option.label)),
      ],
      child: isForm ? _formBox(content) : _filterBox(content),
    );
  }

  /// The report form's box (Figma `169:682`).
  Widget _formBox(Widget content) => Opacity(
    opacity: enabled ? 1 : 0.6,
    child: Container(
      width: width ?? double.infinity,
      height: 56,
      padding: const EdgeInsets.fromLTRB(16, 0, 23, 0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.borderStrong),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            offset: Offset(0, 1),
            blurRadius: 1,
          ),
        ],
      ),
      child: content,
    ),
  );

  Widget _filterBox(Widget content) => Container(
    width: width,
    constraints: style == FilterSelectStyle.large
        ? const BoxConstraints(minWidth: 180)
        : null,
    padding: switch (style) {
      FilterSelectStyle.tinted => const EdgeInsets.symmetric(
        horizontal: 13,
        vertical: 5,
      ),
      FilterSelectStyle.dense ||
      FilterSelectStyle.outlined ||
      FilterSelectStyle.form => const EdgeInsets.symmetric(
        horizontal: 17,
        vertical: 9,
      ),
      FilterSelectStyle.large => const EdgeInsets.fromLTRB(17, 13, 9, 13),
    },
    decoration: BoxDecoration(
      color: style == FilterSelectStyle.tinted
          ? AppColors.surfaceTint
          : AppColors.surface,
      border: Border.all(color: AppColors.borderStrong),
      borderRadius: BorderRadius.circular(
        style == FilterSelectStyle.dense ? 8 : 4,
      ),
    ),
    child: content,
  );

  TextStyle get _textStyle => switch (style) {
    FilterSelectStyle.tinted => AppTextStyles.controlText,
    FilterSelectStyle.dense => AppTextStyles.inputText,
    FilterSelectStyle.large => AppTextStyles.filterStripText,
    FilterSelectStyle.outlined => AppTextStyles.accountsControlText,
    FilterSelectStyle.form => AppTextStyles.formSelectText,
  };

  Widget _trailing() {
    const tint = ColorFilter.mode(AppColors.textSecondary, BlendMode.srcIn);
    return switch (style) {
      FilterSelectStyle.tinted => SvgPicture.asset(
        'assets/icons/select_chevron.svg',
        width: 16,
        height: 16,
        colorFilter: tint,
      ),
      FilterSelectStyle.dense => SvgPicture.asset(
        'assets/icons/select_chevron_small.svg',
        width: 12,
        height: 7.4,
        colorFilter: tint,
      ),
      // The same 12 x 7.4 chevron, in the report form's grey (`169:690`).
      FilterSelectStyle.form => SvgPicture.asset(
        'assets/icons/select_chevron_small.svg',
        width: 12,
        height: 7.4,
        colorFilter: const ColorFilter.mode(
          AppColors.iconMuted,
          BlendMode.srcIn,
        ),
      ),
      FilterSelectStyle.large => SvgPicture.asset(
        'assets/icons/select_chevron_large.svg',
        width: 24,
        height: 24,
        colorFilter: tint,
      ),
      FilterSelectStyle.outlined => SvgPicture.asset(
        'assets/icons/filter_list.svg',
        width: 18,
        height: 12,
        colorFilter: const ColorFilter.mode(
          AppColors.textMuted,
          BlendMode.srcIn,
        ),
      ),
    };
  }
}

/// A menu entry's value, wrapped.
///
/// The "all" option's value is null, and a popup menu treats a null
/// selection as a cancel — it never calls `onSelected`. Unwrapped, choosing
/// "All damage types" after a type did nothing and the filter stuck.
final class _Pick<T> {
  const _Pick(this.value);

  final T? value;

  @override
  bool operator ==(Object other) => other is _Pick<T> && other.value == value;

  @override
  int get hashCode => value.hashCode;
}
