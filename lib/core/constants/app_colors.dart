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

  // --- feedback ---

  static const Color error = Color(0xFFBA1A1A);

  /// Notification badge on the top bar bell.
  static const Color notificationBadge = Color(0xFFBA1A1A);
}
