import 'package:flutter/material.dart';

import '../../../core/constants/breakpoints.dart';
import '../../../core/navigation/unsaved_work.dart';
import '../../../core/widgets/console_tabs.dart';
import '../../../core/widgets/page_header.dart';
import '../../classification/presentation/keyword_settings_section.dart';
import '../../classification/presentation/scoring_settings_section.dart';
import '../../user_management/presentation/departments_settings_section.dart';

/// The things Settings holds, one tab each.
enum SettingsTab {
  keywords('Keywords', 1180),
  priority('Priority scoring', 900),
  duplicates('Duplicate detection', 760),

  /// The departments and faculties accounts choose from (2026-11-17).
  departments('Departments', 760);

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

class _SettingsScreenState extends State<SettingsScreen>
    with GuardsUnsavedWork {
  SettingsTab _open = SettingsTab.keywords;
  final Set<SettingsTab> _unsaved = {};

  /// Any tab with edits not saved: asked about before the sidebar leaves
  /// the page (2026-11-25).
  @override
  bool get hasUnsavedWork => _unsaved.isNotEmpty;

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
    // Saved entry by entry: never anything unsaved to mark.
    SettingsTab.departments => const DepartmentsSettingsSection(),
  };

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.all(Breakpoints.gutter(context)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(
          title: 'Settings',
          subtitle:
              'The rules GSUhub applies to incoming damage reports, and the '
              'departments accounts belong to.',
        ),
        const SizedBox(height: PageHeader.gapBelow),
        ConsoleTabBar<SettingsTab>(
          tabs: SettingsTab.values,
          selected: _open,
          onSelected: (tab) => setState(() => _open = tab),
          labelOf: (tab) => tab.label,
          markedOf: _unsaved.contains,
        ),
        const SizedBox(height: 24),
        // Every tab stays built, so its edits survive a look at another;
        // only the open one is laid out on the page.
        ConsoleTabPages<SettingsTab>(
          tabs: SettingsTab.values,
          open: _open,
          pageOf: (tab) => Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: tab.maxWidth),
              child: _content(tab),
            ),
          ),
        ),
      ],
    ),
  );
}
