/// How far back a screen looks: the work-order board's date filter and the
/// Analytics range selector offer the same choices, so they share one
/// definition rather than two lists that could drift apart.
enum DateRangeFilter {
  last7(Duration(days: 7), 'Last 7 Days', 'last week'),
  last30(Duration(days: 30), 'Last 30 Days', 'last month'),
  last90(Duration(days: 90), 'Last 90 Days', 'last quarter'),
  all(null, 'All Time', null);

  const DateRangeFilter(this.window, this.label, this.previousLabel);

  /// Null for [all], which has no lower bound.
  final Duration? window;

  /// The option as the controls write it ("Last 30 Days").
  final String label;

  /// How the equal-length period before this one reads in a comparison —
  /// "vs last month" for [last30]. Null for [all], which has nothing
  /// before it to compare against.
  final String? previousLabel;

  /// Whether a trend against the preceding period can be computed.
  bool get hasPreviousPeriod => window != null;

  /// Start of the current period, or null for [all].
  DateTime? startOf(DateTime now) =>
      window == null ? null : now.subtract(window!);

  /// Start of the equal-length period immediately before the current one.
  DateTime? previousStartOf(DateTime now) =>
      window == null ? null : now.subtract(window! * 2);

  /// Whether [moment] falls within the current period ending at [now].
  bool includes(DateTime moment, DateTime now) =>
      window == null || moment.isAfter(now.subtract(window!));

  /// Whether [moment] falls within the period immediately before the
  /// current one. Always false for [all].
  bool includesPrevious(DateTime moment, DateTime now) {
    final start = startOf(now);
    final previousStart = previousStartOf(now);
    if (start == null || previousStart == null) return false;
    return moment.isAfter(previousStart) && !moment.isAfter(start);
  }
}
