import 'package:flutter/material.dart';

import '../../../core/constants/app_text_styles.dart';
import '../../classification/presentation/keyword_settings_section.dart';

/// Settings: the rules the console applies to incoming reports.
///
/// Holds the classification keywords (Objective 4.A), the one setting an
/// administrator edits so far. The Figma file draws no Settings screen;
/// this follows the console's other pages (Chris, 2026-10-12).
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
      ],
    ),
  );
}
