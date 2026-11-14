import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/breakpoints.dart';
import '../../classification/presentation/keyword_settings_section.dart';
import '../../classification/presentation/scoring_settings_section.dart';

/// The three things Settings holds, one tab each.
enum SettingsTab {
  keywords('Keywords', 1180),
  priority('Priority scoring', 900),
  duplicates('Duplicate detection', 760);

  const SettingsTab(this.label, this.maxWidth);

  final String label;

  /// How wide the tab's content may grow: no wider than reads well, so a
  /// switch is never a screen's width from its label.
  final double maxWidth;
}

/// Settings: the rules the console applies to incoming reports.
///
/// The classification keywords (Objective 4.A), the priority scoring and
/// the duplicate detection (Objective 7.A; configurable because the
/// manuscript's weights disagree, see each section).
///
/// **Arranged in tabs (2026-11-14).** The three used to be stacked on one
/// page, about five screens long, each card a different width with its
/// own save button. Now there is one topic on screen at a time, in a
/// column no wider than reads well, each ending in the same save bar. A
/// tab with edits that are not saved carries a dot, and stays as it was
/// left while another is open: nothing typed is lost by looking at
/// another tab.
///
/// The Figma file's Settings frame (`61:5550`) is a system-information
/// card (name, institution, version, environment, default urgency,
/// auto-archive), none of it a manuscript feature, so this page keeps the
/// console's existing style; listed for the GUI pass.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SettingsTab _open = SettingsTab.keywords;
  final Set<SettingsTab> _unsaved = {};

  void _report(SettingsTab tab, {required bool unsaved}) {
    if (_unsaved.contains(tab) == unsaved) return;
    setState(() => unsaved ? _unsaved.add(tab) : _unsaved.remove(tab));
  }

  Widget _content(SettingsTab tab) => switch (tab) {
    SettingsTab.keywords => KeywordSettingsSection(
      onUnsavedChanged: (unsaved) => _report(tab, unsaved: unsaved),
    ),
    SettingsTab.priority => PrioritySettingsSection(
      onUnsavedChanged: (unsaved) => _report(tab, unsaved: unsaved),
    ),
    SettingsTab.duplicates => DuplicateSettingsSection(
      onUnsavedChanged: (unsaved) => _report(tab, unsaved: unsaved),
    ),
  };

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.all(Breakpoints.gutter(context)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Settings', style: AppTextStyles.pageTitle),
        const SizedBox(height: 4),
        const Text(
          'The rules GSUhub applies to incoming damage reports.',
          style: AppTextStyles.pageSubtitle,
        ),
        const SizedBox(height: 20),
        _TabRow(
          open: _open,
          unsaved: _unsaved,
          onOpen: (tab) => setState(() => _open = tab),
        ),
        const SizedBox(height: 24),
        // Every tab stays built, so its edits survive a look at another;
        // only the open one is laid out on the page.
        for (final tab in SettingsTab.values)
          Offstage(
            offstage: tab != _open,
            child: TickerMode(
              enabled: tab == _open,
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: tab.maxWidth),
                  child: _content(tab),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// The tabs: the open one in the brand's navy over a gold rule, as the
/// sidebar marks where you are.
class _TabRow extends StatelessWidget {
  const _TabRow({
    required this.open,
    required this.unsaved,
    required this.onOpen,
  });

  final SettingsTab open;
  final Set<SettingsTab> unsaved;
  final ValueChanged<SettingsTab> onOpen;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.border)),
    ),
    // Scrolls sideways on a phone rather than squeezing three names.
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final tab in SettingsTab.values)
            _Tab(
              tab: tab,
              selected: tab == open,
              unsaved: unsaved.contains(tab),
              onTap: () => onOpen(tab),
            ),
        ],
      ),
    ),
  );
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.tab,
    required this.selected,
    required this.unsaved,
    required this.onTap,
  });

  final SettingsTab tab;
  final bool selected;
  final bool unsaved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: unsaved ? '${tab.label}, unsaved changes' : tab.label,
    excludeSemantics: true,
    child: InkWell(
      onTap: selected ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 11),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? AppColors.accentGold : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tab.label,
              style: AppTextStyles.sectionTitle.copyWith(
                color: selected ? AppColors.primary : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            if (unsaved) ...[
              const SizedBox(width: 8),
              const Tooltip(
                message: 'Unsaved changes',
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.accentGold,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox.square(dimension: 8),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
