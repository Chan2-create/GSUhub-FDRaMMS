import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';

/// A KPI's change against the previous period, as the chip in the corner
/// of an Analytics tile shows it (Figma `85:3654`).
class StatTrend {
  const StatTrend({
    required this.text,
    required this.isIncrease,
    required this.isFavourable,
  });

  /// "+12%", "-0.8 days", "-2".
  final String text;

  /// Which way the arrow points.
  final bool isIncrease;

  /// Whether the change is good news. Fewer overdue jobs is a decrease that
  /// is favourable; more reports is an increase that is not, necessarily —
  /// the caller decides, since only it knows what the number measures.
  final bool isFavourable;
}

enum _StatCardStyle { dashboard, metric, kpi }

/// Summary tile — a large number with a caption.
///
/// Three layouts from three frames, sharing one set of behaviour: a
/// spinner while loading, a dash (never a zero) when the number cannot be
/// read, and an optional tooltip explaining how the number is computed.
///
/// - [StatCard.new] — the dashboard's tile, a coloured rule down its left
///   edge (Figma `196:571`).
/// - [StatCard.metric] — the Personnel tile: caption over value, icon in
///   the corner (Figma `201:4684`).
/// - [StatCard.kpi] — the Analytics tile: icon and trend chip, caption,
///   value, then a footnote or progress bar (Figma `85:3650`).
class StatCard extends StatelessWidget {
  const StatCard({
    required this.label,
    required Color this.accent,
    super.key,
    this.value,
    this.valueText,
    this.definition,
    this.isLoading = false,
    this.hasError = false,
  }) : _style = _StatCardStyle.dashboard,
       iconAsset = null,
       unit = null,
       trend = null,
       footnote = null,
       progress = null,
       valueColor = null;

  /// Personnel metric tile. With an [accent], the border takes that colour
  /// and thickens on the left, as AVAILABLE NOW and ON TASK do.
  const StatCard.metric({
    required this.label,
    required String this.iconAsset,
    super.key,
    this.accent,
    this.value,
    this.definition,
    this.isLoading = false,
    this.hasError = false,
  }) : _style = _StatCardStyle.metric,
       valueText = null,
       unit = null,
       trend = null,
       footnote = null,
       progress = null,
       valueColor = null;

  /// Analytics KPI tile.
  const StatCard.kpi({
    required this.label,
    required String this.iconAsset,
    super.key,
    this.value,
    this.valueText,
    this.unit,
    this.trend,
    this.footnote,
    this.progress,
    this.valueColor,
    this.definition,
    this.isLoading = false,
    this.hasError = false,
  }) : _style = _StatCardStyle.kpi,
       accent = null;

  final _StatCardStyle _style;

  final String label;

  /// The count. Null renders a placeholder dash — used for the error state
  /// and while unset.
  final int? value;

  /// A pre-formatted value, for metrics that are not counts ("4.2h").
  /// Takes precedence over [value]; null falls back to it.
  final String? valueText;

  /// How the number is computed, shown as a tooltip on the card. Metrics
  /// whose definition is a judgement call — what "response time" measures
  /// from and to — should carry one, so the figure can be defended.
  final String? definition;

  /// The dashboard tile's left rule, or a metric tile's border.
  final Color? accent;

  /// The metric tile's corner icon, or the KPI tile's icon tile. Drawn at
  /// the SVG's own size.
  final String? iconAsset;

  /// Text after a KPI value, smaller — "days".
  final String? unit;

  final StatTrend? trend;

  /// The KPI tile's last line — "vs last month".
  final String? footnote;

  /// 0.0–1.0 fills a progress bar in place of the footnote.
  final double? progress;

  /// Overrides the KPI value colour, for a number that is a warning in
  /// itself (PENDING / OVERDUE draws it red).
  final Color? valueColor;

  final bool isLoading;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final card = switch (_style) {
      _StatCardStyle.dashboard => _dashboardCard(),
      _StatCardStyle.metric => _metricCard(),
      _StatCardStyle.kpi => _kpiCard(),
    };
    final text = definition;
    return text == null ? card : Tooltip(message: text, child: card);
  }

  // --- dashboard (196:571) ---

  Widget _dashboardCard() => Container(
    height: 113,
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0x66000000)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x40000000),
          offset: Offset(0, 4),
          blurRadius: 4,
        ),
      ],
    ),
    child: Row(
      children: [
        // The coloured left rule, inset so the card's rounded corner is
        // not clipped by a square edge.
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 7),
          child: Container(width: 5, color: accent),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _value(AppTextStyles.statValue, spinnerSize: 30),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: AppTextStyles.statLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  // --- metric (201:4684) ---

  Widget _metricCard() {
    final accentColor = accent;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        // One colour on every side — a borderRadius needs that — with the
        // left side thickened for the accented tiles.
        border: accentColor == null
            ? Border.all(color: AppColors.borderStrong)
            : Border(
                left: BorderSide(color: accentColor, width: 4),
                top: BorderSide(color: accentColor),
                right: BorderSide(color: accentColor),
                bottom: BorderSide(color: accentColor),
              ),
        boxShadow: _subtleShadow,
      ),
      padding: EdgeInsets.fromLTRB(accentColor == null ? 25 : 28, 25, 25, 25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTextStyles.metricLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _value(AppTextStyles.metricValue, spinnerSize: 40),
                ),
              ),
              SvgPicture.asset(iconAsset!),
            ],
          ),
        ],
      ),
    );
  }

  // --- kpi (85:3650) ---

  Widget _kpiCard() {
    final bar = progress;
    final note = footnote;
    final trendChip = trend;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
        boxShadow: _subtleShadow,
      ),
      padding: EdgeInsets.fromLTRB(25, 25, 25, bar == null ? 25 : 31.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SvgPicture.asset(iconAsset!),
              const Spacer(),
              if (trendChip != null && !isLoading && !hasError)
                _TrendChip(trend: trendChip),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            label.toUpperCase(),
            style: AppTextStyles.kpiLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          _kpiValueRow(),
          if (bar != null) ...[
            const SizedBox(height: 12),
            _ProgressBar(fraction: isLoading || hasError ? 0 : bar),
          ] else if (note != null) ...[
            const SizedBox(height: 8),
            Text(note, style: AppTextStyles.kpiFootnote),
          ],
        ],
      ),
    );
  }

  Widget _kpiValueRow() {
    final style = AppTextStyles.kpiValue.copyWith(color: valueColor);
    final unitText = unit;
    if (unitText == null || isLoading || hasError || _text == null) {
      return _value(style, spinnerSize: 40);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        _value(style, spinnerSize: 40),
        const SizedBox(width: 4),
        Text(unitText, style: AppTextStyles.kpiUnit),
      ],
    );
  }

  // --- shared ---

  static const List<BoxShadow> _subtleShadow = [
    BoxShadow(color: Color(0x0D000000), offset: Offset(0, 1), blurRadius: 1),
  ];

  String? get _text => valueText ?? (value == null ? null : '$value');

  Widget _value(TextStyle style, {required double spinnerSize}) {
    if (isLoading) {
      return SizedBox(
        height: spinnerSize,
        width: spinnerSize,
        child: const Padding(
          padding: EdgeInsets.all(4),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final text = _text;
    if (hasError || text == null) {
      // A dash rather than a zero: "we could not read this" and "there are
      // none" are different facts, and showing 0 for the former would be a
      // lie the administrator acts on.
      return Text('—', style: style.copyWith(color: AppColors.textFaint));
    }
    return Text(text, style: style);
  }
}

class _TrendChip extends StatelessWidget {
  const _TrendChip({required this.trend});

  final StatTrend trend;

  @override
  Widget build(BuildContext context) {
    final background = trend.isFavourable
        ? AppColors.trendGoodBackground
        : AppColors.trendBadBackground;
    final foreground = trend.isFavourable
        ? AppColors.trendGoodForeground
        : AppColors.trendBadForeground;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            trend.isIncrease
                ? 'assets/icons/trend_up.svg'
                : 'assets/icons/trend_down.svg',
            colorFilter: ColorFilter.mode(foreground, BlendMode.srcIn),
          ),
          const SizedBox(width: 4),
          Text(
            trend.text,
            style: AppTextStyles.trendChip.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    // Full width, stated, for the same reason as Analytics' building bars:
    // in a loose parent the fill would shrink the track to its own width.
    child: SizedBox(
      width: double.infinity,
      height: 6,
      child: ColoredBox(
        color: AppColors.trackBackground,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: fraction.clamp(0.0, 1.0),
          child: const DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.progressFill,
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
        ),
      ),
    ),
  );
}
