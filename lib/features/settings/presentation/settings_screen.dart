import 'package:flutter/material.dart';

import '../../../core/constants/app_text_styles.dart';
import '../../classification/presentation/keyword_settings_section.dart';
import '../../classification/presentation/scoring_settings_section.dart';

/// Settings: the rules the console applies to incoming reports.
///
/// The classification keywords (Objective 4.A), the priority scoring and
/// the duplicate detection (Objective 7.A; configurable because the
/// manuscript's weights disagree, see each section). The Figma file's
/// Settings frame (`61:5550`) is a system-information card (name,
/// institution, version, environment, default urgency, auto-archive),
/// none of it a manuscript feature, so this page keeps the console's
/// existing style; listed for the GUI pass.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => const SingleChildScrollView(
    padding: EdgeInsets.all(32),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Settings', style: AppTextStyles.pageTitle),
        SizedBox(height: 12),
        Text(
          'The rules GSUhub applies to incoming damage reports.',
          style: AppTextStyles.pageSubtitle,
        ),
        SizedBox(height: 24),
        KeywordSettingsSection(),
        SizedBox(height: 24),
        PrioritySettingsSection(),
        SizedBox(height: 24),
        DuplicateSettingsSection(),
      ],
    ),
  );
}
