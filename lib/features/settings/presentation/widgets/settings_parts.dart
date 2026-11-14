import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';

/// The pieces every Settings tab is built from (2026-11-14), so the three
/// read as one page: the same save bar in the same place, the same
/// groups, the same notes.

/// Where a tab's settings stand against what is saved.
enum SettingsSaveState {
  /// Edits on the page that are not saved.
  unsaved,

  /// The page shows what is saved.
  saved,

  /// Nothing has been saved yet: the built-in defaults are in use.
  defaults,
}

/// The foot of a Settings tab: where the settings stand, then Discard
/// changes and Save changes, the same on every tab. Each tab used to end
/// with its own wording and its own button name.
class SettingsSaveBar extends StatelessWidget {
  const SettingsSaveBar({
    required this.state,
    required this.canDiscard,
    required this.onDiscard,
    required this.canSave,
    required this.onSave,
    required this.saving,
    super.key,
    this.unsavedNote,
  });

  final SettingsSaveState state;

  /// What the unsaved edits do not yet affect, after "Unsaved changes."
  final String? unsavedNote;

  final bool canDiscard;
  final VoidCallback onDiscard;
  final bool canSave;
  final VoidCallback onSave;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final (icon, color, text) = switch (state) {
      SettingsSaveState.unsaved => (
        Icons.edit_outlined,
        AppColors.accentGold,
        ['Unsaved changes.', ?unsavedNote].join(' '),
      ),
      SettingsSaveState.saved => (
        Icons.check_circle_outline,
        AppColors.statusResolvedForeground,
        'All changes saved.',
      ),
      SettingsSaveState.defaults => (
        Icons.info_outline,
        AppColors.textSecondary,
        'The defaults are in use until you save.',
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 12,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Flexible(child: Text(text, style: AppTextStyles.bodySmall)),
              ],
            ),
            // A Wrap, so the two buttons stack in a narrow window.
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: canDiscard ? onDiscard : null,
                  child: const Text('Discard changes'),
                ),
                FilledButton(
                  onPressed: canSave ? onSave : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textOnDark,
                  ),
                  child: Text(saving ? 'Saving…' : 'Save changes'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// A named group of controls inside a tab, with a line saying what they
/// are for.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    required this.title,
    required this.child,
    super.key,
    this.description,
  });

  final String title;
  final String? description;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Semantics(
        header: true,
        child: Text(title, style: AppTextStyles.fieldValue),
      ),
      if (description case final text?) ...[
        const SizedBox(height: 2),
        Text(text, style: AppTextStyles.bodySmall),
      ],
      const SizedBox(height: 12),
      child,
    ],
  );
}

/// A tinted note inside a tab.
class SettingsNotice extends StatelessWidget {
  const SettingsNotice(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.border),
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            size: 18,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: AppTextStyles.bodySmall)),
        ],
      ),
    ),
  );
}

/// Tells a tab's owner, once the frame is done, whether the tab has
/// unsaved edits: the Settings page marks that tab with a dot.
mixin ReportsUnsaved<T extends StatefulWidget> on State<T> {
  bool? _reported;

  /// Called from `build` with whether there are unsaved edits now.
  void reportUnsaved(ValueChanged<bool>? listener, {required bool unsaved}) {
    if (listener == null || _reported == unsaved) return;
    _reported = unsaved;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) listener(unsaved);
    });
  }
}
