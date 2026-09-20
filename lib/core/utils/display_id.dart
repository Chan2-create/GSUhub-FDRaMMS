/// Human-readable record numbers for the admin tables and cards.
///
/// Firestore document ids are either the seed script's readable ones
/// (`rep-0001`) or 20-character auto ids (`K3mPq9...`). The designs show a
/// short prefixed number like `#DR-5021`, and a sequential counter would
/// need a transaction on a shared document for every submission — a
/// requestor-side concern for Objective 3, not this one. Until then the id
/// itself is shown, shortened when it is an auto id.
abstract final class DisplayId {
  /// `rep-0001` → `#REP-0001`; an auto id → `#DR-K3MPQ9`.
  static String report(String id) => _format(id, prefix: 'DR');

  /// `wo-0001` → `#WO-0001`; an auto id → `#WO-K3MPQ9`.
  static String workOrder(String id) => _format(id, prefix: 'WO');

  static const int _autoIdLength = 6;

  static String _format(String id, {required String prefix}) {
    // Seeded ids already carry a readable prefix and number.
    if (id.contains('-')) return '#${id.toUpperCase()}';

    final short = id.length <= _autoIdLength
        ? id
        : id.substring(0, _autoIdLength);
    return '#$prefix-${short.toUpperCase()}';
  }
}
