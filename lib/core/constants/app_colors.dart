import 'package:flutter/material.dart';

/// GSUhub colour tokens, lifted from the Figma design
/// (`sKEnh4SncUyOQFT9JJgy3W`, nodes `194:504` login and `196:534` admin
/// dashboard).
///
/// The Figma file defines only one published variable (`icon-color`), so
/// every other value below was read from raw hex in the design. Names are
/// **semantic** — what the colour is for, not what it looks like or where
/// it happened to appear first — so that a future palette change is a
/// one-file edit rather than a hunt for `#241597` across the codebase.
abstract final class AppColors {
  // --- brand ---

  /// Sidebar and login background. Deep indigo.
  static const Color sidebarBackground = Color(0xFF241597);

  /// Gold used for the sidebar's active item and the accent bar beneath
  /// the top app bar.
  static const Color accentGold = Color(0xFFC8960C);

  /// Primary action colour — outlined buttons, links, chart series.
  static const Color primary = Color(0xFF00236F);

  /// Call-to-action fill (the "Report New Damage" button).
  static const Color ctaAmber = Color(0xFFFDCC14);

  /// Foreground for text sitting on [ctaAmber].
  static const Color ctaAmberForeground = Color(0xFF6E5700);

  /// Foreground for text sitting on [accentGold] (the active nav item).
  static const Color onAccentGold = Color(0xB8000000);

  // --- surfaces ---

  static const Color surface = Color(0xFFFFFFFF);
  static const Color pageBackground = Color(0xFFFFFFFF);

  /// Table header fill.
  static const Color surfaceMuted = Color(0xFFF8FAFC);

  /// Card and panel borders.
  static const Color border = Color(0xFFE2E8F0);

  /// Hairline rules inside tables.
  static const Color borderSubtle = Color(0xFFF1F5F9);

  /// Track behind a progress bar.
  static const Color trackBackground = Color(0xFFF1F5F9);

  /// Filled portion of a "previous period" bar.
  static const Color trackComparison = Color(0xFFE2E8F0);

  // --- text ---

  /// Headings and primary values.
  static const Color textPrimary = Color(0xFF0B1C30);

  /// Body copy and table cells.
  static const Color textSecondary = Color(0xFF475569);

  /// Supporting copy, column headers.
  static const Color textMuted = Color(0xFF64748B);

  /// Timestamps, unit labels, de-emphasised captions.
  static const Color textFaint = Color(0xFF94A3B8);

  static const Color textOnDark = Color(0xFFFFFFFF);

  /// Placeholder text in login form fields.
  static const Color textPlaceholder = Color(0x61000000);

  // --- report status ---
  // Chip fills and foregrounds for the Recent Reports table. Mapped from
  // ReportStatus in core/enums/report_status.dart by
  // core/widgets/status_chip.dart.

  static const Color statusPendingBackground = Color(0xFFFEE2E2);
  static const Color statusPendingForeground = Color(0xFFB91C1C);

  static const Color statusInProgressBackground = Color(0xFFDBEAFE);
  static const Color statusInProgressForeground = Color(0xFF1D4ED8);

  static const Color statusResolvedBackground = Color(0xFFDCFCE7);
  static const Color statusResolvedForeground = Color(0xFF15803D);

  static const Color statusNeutralBackground = Color(0xFFF1F5F9);
  static const Color statusNeutralForeground = Color(0xFF475569);

  // --- stat card accents ---
  // The four coloured left-edge rules on the dashboard stat cards, in the
  // order the design places them.

  static const Color statAccentTotal = Color(0xFF00236F);
  static const Color statAccentNeedsReview = Color(0xFFDC2626);
  static const Color statAccentInProgress = Color(0xFFC8960C);
  static const Color statAccentCompleted = Color(0xFF16A34A);

  // --- charts ---

  /// Category donut series, in legend order.
  static const List<Color> categorySeries = [
    Color(0xFF00236F),
    Color(0xFFFDCC14),
    Color(0xFF722A00),
    Color(0xFF15803D),
    Color(0xFF1D4ED8),
    Color(0xFFB91C1C),
    Color(0xFF64748B),
  ];

  /// Fill for the "Others" slice and any category beyond
  /// [categorySeries].
  static const Color categoryOther = Color(0xFFCBD5E1);

  // --- activity feed dots ---

  static const Color activityPositive = Color(0xFF22C55E);
  static const Color activityInfo = Color(0xFF00236F);
  static const Color activityNeutral = Color(0xFF94A3B8);

  // --- Objective 2.B: management screens ---
  // Read from nodes 196:1371 (Damage Reports), 61:4970 (Task Assignment)
  // and 202:5355 (Work Order Management). The three frames spell the same
  // greys and navies with slightly different hex values; where two were
  // visually the same role they map onto the existing token above rather
  // than minting a near-duplicate here.

  /// Stronger control borders: filter pills, inputs, pagination buttons.
  static const Color borderStrong = Color(0xFFC4C5D3);

  /// Filter pills and the pagination strip — a barely-blue white.
  static const Color surfaceTint = Color(0xFFF8F9FF);

  /// Recessed panels: the work-order filter bar and Kanban columns.
  static const Color surfaceSunken = Color(0xFFF1F4FB);

  /// Segmented-toggle track and the work-order assignee avatar.
  static const Color surfaceControl = Color(0xFFEBEEF5);

  /// Neutral count badge on the Pending and For Review columns.
  static const Color badgeNeutral = Color(0xFFDFE2E9);

  /// Soft amber: the active view toggle and the In Progress count badge.
  static const Color highlightAmber = Color(0xFFFED65B);

  /// Olive text and borders paired with [highlightAmber], and the outlined
  /// "View" row action.
  static const Color accentOlive = Color(0xFF745B00);

  /// Row-action icons in the reports table.
  static const Color iconMuted = Color(0xFF757683);

  /// The left edge on the report card currently selected for assignment.
  static const Color cardSelectedAccent = Color(0xFFEF4444);

  /// Initials tile behind an active person's avatar.
  static const Color avatarBackground = Color(0xFFEFF6FF);

  /// Personnel status: dot and label for an active account…
  static const Color presenceActive = Color(0xFF10B981);
  static const Color presenceActiveText = Color(0xFF047857);

  /// …and for an inactive one.
  static const Color presenceInactive = Color(0xFFCBD5E1);

  // Priority chips (node 196:1371). The design shows three levels; CRITICAL
  // reuses HIGH's red as a solid fill, the one treatment not drawn in any
  // frame, so the most severe level reads as the most severe.
  static const Color priorityLowBackground = Color(0xFFD3E4FE);
  static const Color priorityLowForeground = Color(0xFF444652);
  static const Color priorityMediumBackground = Color(0xFFFFE08B);
  static const Color priorityMediumForeground = Color(0xFF241A00);
  static const Color priorityHighBackground = Color(0xFFFFDAD6);
  static const Color priorityHighForeground = Color(0xFF93000A);
  static const Color priorityCriticalBackground = Color(0xFF93000A);
  static const Color priorityCriticalForeground = Color(0xFFFFFFFF);

  // --- Objective 2.C: personnel, analytics, user accounts ---

  /// Personnel availability (node 200:4316): the metric card accents and
  /// the dot beside each row's status.
  static const Color presenceAvailable = activityPositive;
  static const Color presenceBusy = ctaAmber;

  /// The personnel search-and-filter strip, and its square filter button.
  static const Color filterBarBackground = Color(0xFFE5EEFF);
  static const Color filterButtonBackground = Color(0xFFD3E4FE);

  /// Table header rows and the alternate-row stripe (nodes 200:4316 and
  /// 89:4626 share the value).
  static const Color tableStripe = Color(0xFFEFF4FF);

  /// Analytics KPI trend chips (node 85:3649). The design draws only the
  /// favourable case; the unfavourable one mirrors it in red.
  static const Color trendGoodBackground = Color(0xFFF0FDF4);
  static const Color trendGoodForeground = statAccentCompleted;
  static const Color trendBadBackground = Color(0xFFFEF2F2);
  static const Color trendBadForeground = statAccentNeedsReview;

  /// Completion-rate progress fill.
  static const Color progressFill = activityPositive;

  /// Resolution-time line and its points (node 85:4146).
  static const Color chartLine = Color(0xFF1A3A8F);

  /// The "Top Reported Issues" card's title strip.
  static const Color tableTitleBar = Color(0xFFFBFCFD);

  /// Arrow colours in the issues table's TREND column.
  static const Color trendUp = error;
  static const Color trendDown = activityPositive;
  static const Color trendFlat = textFaint;

  /// User account role chips and legend dots (node 89:4626).
  static const Color roleRequestorBackground = Color(0xFFDBEAFE);
  static const Color roleRequestorForeground = Color(0xFF1D4ED8);
  static const Color roleRequestorDot = Color(0xFF3B82F6);
  static const Color roleMaintenanceBackground = Color(0xFFFFEDD5);
  static const Color roleMaintenanceForeground = Color(0xFFC2410C);
  static const Color roleMaintenanceDot = Color(0xFFF97316);
  static const Color roleAdminBackground = Color(0xFFF3E8FF);
  static const Color roleAdminForeground = Color(0xFF7E22CE);
  static const Color roleAdminDot = Color(0xFFA855F7);

  /// An inactive account's row, chip and status (node 89:4843).
  static const Color inactiveRowBackground = Color(0xFFF7F9FB);
  static const Color inactiveChipBackground = Color(0xFFEEF1F6);
  static const Color inactiveForeground = Color(0xFFA2ACB9);

  /// Account status: ACTIVE in green, the legend's inactive dot in slate.
  static const Color accountActive = statAccentCompleted;
  static const Color accountInactiveDot = presenceInactive;

  // --- feedback ---

  static const Color error = Color(0xFFBA1A1A);

  /// Notification badge on the top bar bell.
  static const Color notificationBadge = Color(0xFFBA1A1A);
}
