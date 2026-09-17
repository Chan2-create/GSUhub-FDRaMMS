import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Typography tokens from the Figma design.
///
/// Two families, used for distinct purposes rather than interchangeably:
/// **Poppins** carries the university-facing surfaces (login screen, admin
/// sidebar), **Public Sans** carries the dense data UI (cards, tables,
/// charts). Both are bundled — see `pubspec.yaml` for why.
abstract final class AppTextStyles {
  static const String _display = 'Poppins';
  static const String _ui = 'Public Sans';
  static const String _mono = 'Roboto Mono';

  // --- login screen (Poppins) ---

  /// "DAVAO ORIENTAL STATE UNIVERSITY"
  static const TextStyle loginHeadline = TextStyle(
    fontFamily: _display,
    fontSize: 50,
    fontWeight: FontWeight.w700,
    color: AppColors.textOnDark,
    height: 1.2,
    shadows: [
      Shadow(offset: Offset(0, 4), blurRadius: 4, color: Color(0x40000000)),
    ],
  );

  /// "GSUhub Facility Damage Reporting and Maintenance Management System"
  static const TextStyle loginSubtitle = TextStyle(
    fontFamily: _display,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textOnDark,
    height: 1.4,
    shadows: [
      Shadow(offset: Offset(0, 4), blurRadius: 4, color: Color(0x40000000)),
    ],
  );

  /// "Excellence, Innovation, and Inclusion in Higher Education."
  static const TextStyle loginTagline = TextStyle(
    fontFamily: _display,
    fontSize: 20,
    fontWeight: FontWeight.w400,
    color: AppColors.textOnDark,
    shadows: [
      Shadow(offset: Offset(0, 4), blurRadius: 4, color: Color(0x40000000)),
    ],
  );

  /// "Welcome back!"
  static const TextStyle loginCardTitle = TextStyle(
    fontFamily: _display,
    fontSize: 22,
    fontWeight: FontWeight.w400,
    color: Colors.black,
  );

  static const TextStyle loginFieldPlaceholder = TextStyle(
    fontFamily: _display,
    fontSize: 15,
    fontWeight: FontWeight.w300,
    color: AppColors.textPlaceholder,
  );

  static const TextStyle loginFieldValue = TextStyle(
    fontFamily: _display,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: Colors.black,
  );

  static const TextStyle loginButton = TextStyle(
    fontFamily: _display,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.textOnDark,
  );

  static const TextStyle loginLink = TextStyle(
    fontFamily: _display,
    fontSize: 18,
    fontWeight: FontWeight.w300,
    color: Colors.black,
  );

  // --- sidebar (Poppins) ---

  /// "GSU Administration"
  static const TextStyle sidebarTitle = TextStyle(
    fontFamily: _display,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: AppColors.textOnDark,
    shadows: [
      Shadow(offset: Offset(0, 4), blurRadius: 4, color: Color(0x40000000)),
    ],
  );

  /// "Overview", "Management", "System" group headers.
  static const TextStyle sidebarGroupLabel = TextStyle(
    fontFamily: _display,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textOnDark,
  );

  static const TextStyle sidebarItem = TextStyle(
    fontFamily: _display,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textOnDark,
  );

  /// Active item — dark text on the gold pill.
  static const TextStyle sidebarItemActive = TextStyle(
    fontFamily: _display,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.onAccentGold,
  );

  static const TextStyle sidebarFooterName = TextStyle(
    fontFamily: _display,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: Colors.black,
  );

  static const TextStyle sidebarFooterRole = TextStyle(
    fontFamily: _display,
    fontSize: 10,
    fontWeight: FontWeight.w300,
    color: Colors.black,
  );

  // --- dashboard (Public Sans) ---

  /// Card and panel headings: "Recent Reports", "Reports by Category".
  static const TextStyle sectionTitle = TextStyle(
    fontFamily: _ui,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 20 / 14,
  );

  /// The large number on a stat card.
  static const TextStyle statValue = TextStyle(
    fontFamily: _display,
    fontSize: 30,
    fontWeight: FontWeight.w600,
    color: Colors.black,
  );

  /// The caption under a stat card's number.
  static const TextStyle statLabel = TextStyle(
    fontFamily: _display,
    fontSize: 10,
    fontWeight: FontWeight.w600,
    color: Color(0xD9000000),
  );

  /// Donut centre total.
  static const TextStyle chartCenterValue = TextStyle(
    fontFamily: _ui,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 32 / 24,
  );

  /// "TOTAL" under the donut centre, and other small uppercase captions.
  static const TextStyle captionUpper = TextStyle(
    fontFamily: _ui,
    fontSize: 10,
    fontWeight: FontWeight.w400,
    color: AppColors.textFaint,
    height: 1.5,
  );

  static const TextStyle legendLabel = TextStyle(
    fontFamily: _ui,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 16 / 12,
  );

  /// Table column headers — uppercase with wide tracking.
  static const TextStyle tableHeader = TextStyle(
    fontFamily: _ui,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: AppColors.textMuted,
    letterSpacing: 0.6,
  );

  static const TextStyle tableCell = TextStyle(
    fontFamily: _ui,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 20 / 14,
  );

  /// Primary cell text, e.g. the facility/issue title.
  static const TextStyle tableCellStrong = TextStyle(
    fontFamily: _ui,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 20 / 14,
  );

  /// Secondary line under a cell's primary text, e.g. the category.
  static const TextStyle tableCellCaption = TextStyle(
    fontFamily: _ui,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
    height: 16 / 12,
  );

  /// Report identifiers.
  static const TextStyle monoIdentifier = TextStyle(
    fontFamily: _mono,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 20 / 14,
  );

  /// Status chip text.
  static const TextStyle statusChip = TextStyle(
    fontFamily: _ui,
    fontSize: 10,
    fontWeight: FontWeight.w700,
  );

  // --- top bar (Public Sans) ---

  static const TextStyle topBarTitle = TextStyle(
    fontFamily: _ui,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 20 / 14,
  );

  static const TextStyle topBarMeta = TextStyle(
    fontFamily: _ui,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textMuted,
    height: 20 / 14,
  );

  static const TextStyle buttonLabel = TextStyle(
    fontFamily: _ui,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 20 / 14,
  );

  // --- activity feed (Public Sans) ---

  static const TextStyle activityTitle = TextStyle(
    fontFamily: _ui,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
    height: 20 / 14,
  );

  static const TextStyle activityBody = TextStyle(
    fontFamily: _ui,
    fontSize: 10,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
    height: 1.6,
  );

  // --- bar chart (Public Sans) ---

  static const TextStyle barLabel = TextStyle(
    fontFamily: _ui,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 16 / 12,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: _ui,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
    height: 16 / 12,
  );

  /// Chart legend keys: "CURRENT MONTH" / "PREVIOUS MONTH".
  static const TextStyle legendKeyUpper = TextStyle(
    fontFamily: _ui,
    fontSize: 10,
    fontWeight: FontWeight.w700,
    color: AppColors.textFaint,
    height: 1.5,
  );
}
