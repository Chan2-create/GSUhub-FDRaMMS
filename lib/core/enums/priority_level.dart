/// Official maintenance priority level assigned to a facility damage report
/// (manuscript §3.4, Table 3.5 "Priority Score Ranges and Priority Levels").
///
/// A [PriorityLevel] may originate from two places: the requestor's initial,
/// perceived-urgency selection at submission time, or the system's computed
/// weighted Priority Score (Severity x0.40 + Safety Risk x0.30 +
/// Frequency x0.20 + Location Importance x0.10, each criterion rated 1-4).
/// Either way, the *official* priority level is always subject to
/// confirmation or modification by an authorized GSU Administrator before
/// work-order assignment — this enum only models the value itself, not who
/// set it.
///
/// The weights and rating scale are configuration, not hardcoded here: see
/// `lib/core/config/app_config.dart`. Only the score-to-level thresholds
/// below are fixed by the manuscript.
enum PriorityLevel {
  low,
  medium,
  high,
  critical;

  /// Maps a computed Priority Score to its [PriorityLevel] per Table 3.5:
  ///
  /// | Score range   | Level    |
  /// |---------------|----------|
  /// | 3.50 - 4.00   | critical |
  /// | 2.50 - 3.49   | high     |
  /// | 1.50 - 2.49   | medium   |
  /// | 1.00 - 1.49   | low      |
  ///
  /// [score] must fall within `1.00` to `4.00` inclusive — the theoretical
  /// min/max of the weighted formula when every criterion is rated on its
  /// 1-4 scale (Table 3.4). Throws [ArgumentError] otherwise, since a score
  /// outside that range indicates a defect in the scoring computation
  /// itself, not a valid edge case to silently clamp.
  factory PriorityLevel.fromScore(double score) {
    if (score < 1.0 || score > 4.0) {
      throw ArgumentError.value(
        score,
        'score',
        'Priority Score must be between 1.00 and 4.00 inclusive',
      );
    }
    if (score >= 3.50) return PriorityLevel.critical;
    if (score >= 2.50) return PriorityLevel.high;
    if (score >= 1.50) return PriorityLevel.medium;
    return PriorityLevel.low;
  }

  /// The value persisted on the `damage_reports/{id}.priorityLevel` and
  /// `work_orders/{id}.priorityLevel` fields.
  String get id => name;

  /// Chip label. `critical` stays CRITICAL even though the mockups say
  /// "URGENT" and "EMERGENCY" in different frames: the enum is the source
  /// of truth, and three words for one level would be three chances for an
  /// administrator to wonder whether they differ.
  String get label => name.toUpperCase();

  /// High enough to count toward the Damage Reports "HIGH PRIORITY" card.
  bool get isHighOrAbove =>
      this == PriorityLevel.high || this == PriorityLevel.critical;

  static PriorityLevel fromId(String id) => PriorityLevel.values.firstWhere(
    (level) => level.id == id,
    orElse: () => throw ArgumentError.value(id, 'id', 'Unknown PriorityLevel'),
  );
}
