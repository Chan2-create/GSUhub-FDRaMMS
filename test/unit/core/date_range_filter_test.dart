import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/enums/date_range_filter.dart';

/// The shared period choices (work-order board and Analytics).
void main() {
  final now = DateTime(2026, 9, 25, 12);

  test('a period includes its span and nothing older', () {
    const range = DateRangeFilter.last7;
    expect(range.includes(now.subtract(const Duration(days: 6)), now), isTrue);
    expect(range.includes(now.subtract(const Duration(days: 8)), now), isFalse);
  });

  test('the previous period is the equal span just before', () {
    const range = DateRangeFilter.last30;
    expect(
      range.includesPrevious(now.subtract(const Duration(days: 45)), now),
      isTrue,
    );
    expect(
      range.includesPrevious(now.subtract(const Duration(days: 10)), now),
      isFalse,
    );
    expect(
      range.includesPrevious(now.subtract(const Duration(days: 61)), now),
      isFalse,
    );
  });

  test('All Time has no bound and nothing before it', () {
    const range = DateRangeFilter.all;
    expect(range.includes(DateTime(2000), now), isTrue);
    expect(range.hasPreviousPeriod, isFalse);
    expect(range.includesPrevious(DateTime(2000), now), isFalse);
    expect(range.previousLabel, isNull);
  });

  test('comparisons read naturally for the design\'s default', () {
    // "vs last month" — the Analytics frame's own wording.
    expect(DateRangeFilter.last30.previousLabel, 'last month');
    expect(DateRangeFilter.last30.label, 'Last 30 Days');
  });
}
