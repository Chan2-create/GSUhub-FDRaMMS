import '../enums/priority_level.dart';

/// The console's working order (2026-11-26): by priority, Critical, High,
/// Medium, then Low; within one priority the oldest first, so it is not
/// left waiting behind newer ones; then by id, so the order never shifts
/// between two reads. The one comparison behind the Damage Reports list
/// and Work Order Management.
int byPriorityThenOldestOf<T>(
  T a,
  T b, {
  required PriorityLevel Function(T) priority,
  required DateTime Function(T) since,
  required String Function(T) id,
}) {
  final byPriority = priority(b).index.compareTo(priority(a).index);
  if (byPriority != 0) return byPriority;
  final byAge = since(a).compareTo(since(b));
  return byAge != 0 ? byAge : id(a).compareTo(id(b));
}
