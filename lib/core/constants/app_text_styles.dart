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

  // --- Objective 2.B: management screens (Public Sans) ---
  // The Work Order frame (202:5355) is set in Hanken Grotesk, Inter and
  // JetBrains Mono — an older design generation. Its text is mapped onto
  // the families already bundled (Public Sans, Roboto Mono), as 2.A did
  // with Liberation Mono, rather than shipping three more typefaces for one
  // screen.

  /// Page heading: "Damage Reports", "Task Assignment",
  /// "Work Order Management".
  static const TextStyle pageTitle = TextStyle(
    fontFamily: _ui,
    fontSize: 32,
    fontWeight: FontWeight.w700,
    color: AppColors.primary,
    letterSpacing: -0.32,
    height: 40 / 32,
  );

  static const TextStyle pageSubtitle = TextStyle(
    fontFamily: _ui,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 24 / 16,
  );

  /// Body copy inside the Damage Reports panels.
  static const TextStyle bodyText = pageSubtitle;

  /// "Filters:" and similar small bold labels.
  static const TextStyle filterLabel = TextStyle(
    fontFamily: _ui,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: AppColors.textSecondary,
    letterSpacing: 0.6,
  );

  /// Text inside filter pills and dropdown triggers.
  static const TextStyle controlText = TextStyle(
    fontFamily: _ui,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 20 / 14,
  );

  /// Compact input text on the work-order filter bar.
  static const TextStyle inputText = TextStyle(
    fontFamily: _ui,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 18 / 12,
  );

  /// "Clear all filters", "View All Personnel".
  static const TextStyle linkText = TextStyle(
    fontFamily: _ui,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.primary,
    height: 20 / 14,
  );

  /// The outlined "View" row action.
  static const TextStyle rowActionText = TextStyle(
    fontFamily: _ui,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.accentOlive,
    height: 16 / 12,
  );

  /// "Showing 1 to 10 of 42 results".
  static const TextStyle paginationSummary = pageSubtitle;

  static const TextStyle paginationPage = TextStyle(
    fontFamily: _ui,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 20 / 14,
  );

  /// Panel heading in the design's blue: "Campus View".
  static const TextStyle panelHeading = TextStyle(
    fontFamily: _ui,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.primary,
    height: 24 / 16,
  );

  /// Panel heading in the design's near-black: "Personnel Availability".
  static const TextStyle panelTitle = TextStyle(
    fontFamily: _ui,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 24 / 16,
  );

  static const TextStyle emergencyTitle = TextStyle(
    fontFamily: _ui,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    color: AppColors.textOnDark,
    height: 31.2 / 24,
  );

  static const TextStyle emergencyBody = TextStyle(
    fontFamily: _ui,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: Color(0xCCFFFFFF),
    height: 24 / 16,
  );

  /// Large primary button labels: "Create Report", "Dispatch Emergency
  /// Team".
  static const TextStyle ctaLabel = TextStyle(
    fontFamily: _ui,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 24 / 16,
  );

  /// "UNASSIGNED REPORTS".
  static const TextStyle sectionOverline = TextStyle(
    fontFamily: _ui,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
    height: 24 / 16,
  );

  /// Small bold pill text: "4 PENDING", category chips.
  static const TextStyle badgeText = TextStyle(
    fontFamily: _ui,
    fontSize: 10,
    fontWeight: FontWeight.w700,
    height: 15 / 10,
  );

  /// Priority chip text.
  static const TextStyle priorityChip = TextStyle(
    fontFamily: _ui,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    height: 16 / 12,
  );

  /// Report number on an assignment queue card.
  static const TextStyle queueCardId = TextStyle(
    fontFamily: _ui,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: AppColors.textFaint,
    height: 16 / 12,
  );

  static const TextStyle queueCardTitle = TextStyle(
    fontFamily: _ui,
    fontSize: 18,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 28 / 18,
  );

  /// Location lines and other secondary metadata.
  static const TextStyle metaText = TextStyle(
    fontFamily: _ui,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
    height: 20 / 14,
  );

  /// Personnel table column headers.
  static const TextStyle panelHeaderCell = TextStyle(
    fontFamily: _ui,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.textFaint,
  );

  static const TextStyle personName = TextStyle(
    fontFamily: _ui,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle personRole = TextStyle(
    fontFamily: _ui,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
    height: 16 / 12,
  );

  /// Initials inside an avatar tile.
  static const TextStyle avatarInitials = TextStyle(
    fontFamily: _ui,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.primary,
  );

  static const TextStyle taskCount = TextStyle(
    fontFamily: _ui,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    height: 20 / 14,
  );

  /// ACTIVE / INACTIVE beside the presence dot.
  static const TextStyle presenceLabel = TextStyle(
    fontFamily: _ui,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    height: 16 / 12,
  );

  static const TextStyle outlineButtonSmall = TextStyle(
    fontFamily: _ui,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 16 / 12,
  );

  static const TextStyle kanbanColumnTitle = TextStyle(
    fontFamily: _ui,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 24 / 16,
  );

  static const TextStyle kanbanCount = TextStyle(
    fontFamily: _mono,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 18 / 12,
  );

  /// Work-order number on a Kanban card.
  static const TextStyle workOrderId = TextStyle(
    fontFamily: _mono,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: AppColors.primary,
    height: 16.5 / 11,
  );

  static const TextStyle workOrderTitle = TextStyle(
    fontFamily: _ui,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 19.25 / 14,
  );

  static const TextStyle workOrderMeta = TextStyle(
    fontFamily: _ui,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 18 / 12,
  );

  /// Labels in the report detail view's field grid.
  static const TextStyle fieldLabel = TextStyle(
    fontFamily: _ui,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: AppColors.textMuted,
    letterSpacing: 0.6,
    height: 16 / 12,
  );

  static const TextStyle fieldValue = TextStyle(
    fontFamily: _ui,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 20 / 14,
  );

  // --- Objective 2.C: personnel (200:4316) ---

  /// "TOTAL STAFF" and siblings — sentence-size, not the dashboard caps.
  static const TextStyle metricLabel = TextStyle(
    fontFamily: _ui,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 24 / 16,
  );

  static const TextStyle metricValue = TextStyle(
    fontFamily: _ui,
    fontSize: 40,
    fontWeight: FontWeight.w700,
    color: AppColors.primary,
    letterSpacing: -0.8,
    height: 48 / 40,
  );

  /// Personnel table headers — the design sets them at body size.
  static const TextStyle staffTableHeader = TextStyle(
    fontFamily: _ui,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.textSecondary,
  );

  static const TextStyle staffName = TextStyle(
    fontFamily: _ui,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle staffId = TextStyle(
    fontFamily: _ui,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  /// Category pill text; colour comes from the category palette.
  static const TextStyle categoryChip = TextStyle(
    fontFamily: _ui,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
    height: 12 / 12,
  );

  static const TextStyle staffStatus = TextStyle(
    fontFamily: _ui,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 21 / 14,
  );

  static const TextStyle staffTaskCount = TextStyle(
    fontFamily: _ui,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.primary,
  );

  static const TextStyle staffContact = TextStyle(
    fontFamily: _ui,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 21 / 14,
  );

  static const TextStyle assignTaskLabel = TextStyle(
    fontFamily: _ui,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.ctaAmberForeground,
  );

  /// Search, select and label text in the personnel filter strip.
  static const TextStyle filterStripText = TextStyle(
    fontFamily: _ui,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 24 / 16,
  );

  static const TextStyle tableFooterText = TextStyle(
    fontFamily: _ui,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 21 / 14,
  );

  /// "Add Personnel" — the design sets this primary button at 16px.
  static const TextStyle primaryButtonLarge = TextStyle(
    fontFamily: _ui,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textOnDark,
    height: 24 / 16,
  );

  // --- Objective 2.C: analytics (61:5086) ---

  static const TextStyle kpiLabel = TextStyle(
    fontFamily: _ui,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: AppColors.iconMuted,
    letterSpacing: 0.6,
    height: 12 / 12,
  );

  static const TextStyle kpiValue = TextStyle(
    fontFamily: _ui,
    fontSize: 40,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.8,
    height: 48 / 40,
  );

  /// The unit after a KPI value — "days".
  static const TextStyle kpiUnit = TextStyle(
    fontFamily: _ui,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.iconMuted,
    height: 24 / 16,
  );

  static const TextStyle kpiFootnote = TextStyle(
    fontFamily: _ui,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: AppColors.iconMuted,
    height: 16.5 / 11,
  );

  /// Trend chip text; colour comes from the chip.
  static const TextStyle trendChip = TextStyle(
    fontFamily: _ui,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    height: 16 / 12,
  );

  static const TextStyle chartTitle = TextStyle(
    fontFamily: _ui,
    fontSize: 18,
    fontWeight: FontWeight.w400,
    color: AppColors.primary,
    height: 28.8 / 18,
  );

  /// Month labels under the charts; the current month is darkened.
  static const TextStyle chartAxisLabel = TextStyle(
    fontFamily: _ui,
    fontSize: 10,
    fontWeight: FontWeight.w700,
    color: AppColors.iconMuted,
    height: 15 / 10,
  );

  static const TextStyle donutCenterValue = TextStyle(
    fontFamily: _ui,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 31.2 / 24,
  );

  static const TextStyle legendName = TextStyle(
    fontFamily: _ui,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    height: 20 / 14,
  );

  static const TextStyle legendShare = TextStyle(
    fontFamily: _ui,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 20 / 14,
  );

  /// "MAIN BUILDING" and its count in Reports by Building.
  static const TextStyle barRowLabel = TextStyle(
    fontFamily: _ui,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: AppColors.textSecondary,
    height: 16 / 12,
  );

  static const TextStyle barRowValue = TextStyle(
    fontFamily: _ui,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 16 / 12,
  );

  /// "-72% Improvement" badge on the resolution-time chart.
  static const TextStyle chartBadge = TextStyle(
    fontFamily: _ui,
    fontSize: 10,
    fontWeight: FontWeight.w700,
    height: 15 / 10,
  );

  static const TextStyle issueRank = TextStyle(
    fontFamily: _ui,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static const TextStyle issueName = TextStyle(
    fontFamily: _ui,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle issueCell = TextStyle(
    fontFamily: _ui,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  static const TextStyle issueCount = TextStyle(
    fontFamily: _ui,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static const TextStyle viewReportLink = TextStyle(
    fontFamily: _ui,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: AppColors.primary,
    letterSpacing: 1.4,
    height: 20 / 14,
  );

  /// The top bar range selector on the Analytics page.
  static const TextStyle rangeSelect = TextStyle(
    fontFamily: _ui,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
    height: 20 / 14,
  );

  // --- Objective 2.C: user accounts (89:4626) ---

  static const TextStyle tabActive = TextStyle(
    fontFamily: _ui,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: AppColors.primary,
    height: 1,
  );

  static const TextStyle tabInactive = TextStyle(
    fontFamily: _ui,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    height: 1,
  );

  static const TextStyle accountsControlText = TextStyle(
    fontFamily: _ui,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 21 / 14,
  );

  static const TextStyle accountsButton = TextStyle(
    fontFamily: _ui,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textOnDark,
    height: 1,
  );

  static const TextStyle accountsHeader = TextStyle(
    fontFamily: _ui,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: AppColors.textSecondary,
    letterSpacing: 0.6,
    height: 12 / 12,
  );

  static const TextStyle accountName = TextStyle(
    fontFamily: _ui,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 21 / 14,
  );

  static const TextStyle accountCell = TextStyle(
    fontFamily: _ui,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 21 / 14,
  );

  /// Role pill and ACTIVE/INACTIVE text; colour comes from the role.
  static const TextStyle roleChip = TextStyle(
    fontFamily: _ui,
    fontSize: 10,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
    height: 12 / 10,
  );

  static const TextStyle legendTitle = TextStyle(
    fontFamily: _ui,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: AppColors.textSecondary,
    letterSpacing: 0.6,
    height: 12 / 12,
  );

  static const TextStyle legendItem = TextStyle(
    fontFamily: _ui,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 21 / 14,
  );
}
