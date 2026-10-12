import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show listEquals;

import '../../../../core/enums/priority_level.dart';
import '../../../../core/utils/firestore_converters.dart';

/// Which of the two weight schemes the manuscript provides is currently
/// authoritative.
///
/// **This exists because the manuscript contradicts itself.** See
/// [PrioritizationConfig] for the details. Until the conflict is
/// resolved with the GSU, the system must be able to hold both and be told
/// which to use.
enum PrioritizationScheme {
  /// Table 3.2's integer weights: Severity 3, Safety Risk 4, Frequency 2,
  /// Location Importance 3.
  integerWeights,

  /// The §3.4 formula's decimal weights: Severity 0.40, Safety Risk 0.30,
  /// Frequency 0.20, Location Importance 0.10.
  decimalWeights;

  String get id => name;

  static PrioritizationScheme fromId(String id) =>
      PrioritizationScheme.values.firstWhere(
        (scheme) => scheme.id == id,
        orElse: () =>
            throw ArgumentError.value(id, 'id', 'Unknown PrioritizationScheme'),
      );
}

/// The `config/prioritization` document — the weighted-scoring parameters
/// used to compute a report's recommended priority.
///
/// ## Conflict in the source material
///
/// The manuscript specifies the prioritization weights **twice, and the
/// two do not agree**:
///
/// | Criterion | Table 3.2 | §3.4 formula |
/// |---|---|---|
/// | Severity | 3 | 0.40 |
/// | Safety Risk | **4** | 0.30 |
/// | Frequency | 2 | 0.20 |
/// | Location Importance | 3 | 0.10 |
///
/// They disagree on more than notation: Table 3.2 ranks **Safety Risk**
/// highest, the formula ranks **Severity** highest. Normalizing Table 3.2
/// (3/12, 4/12, 2/12, 3/12 = 0.25, 0.33, 0.17, 0.25) does not reconcile
/// them. Whether a live electrical hazard outranks a large but harmless
/// defect is a policy question for the GSU, not a rounding difference.
///
/// This model therefore stores **both schemes side by side** and defers to
/// [activeScheme]. Nothing is hardcoded, nothing is silently reconciled,
/// and switching the decision later is a single field edit rather than a
/// data migration. Chris chose the formula's weights on 2026-10-12
/// (Objective 4.B); the manuscript's Table 3.2 needs correcting to match.
class PrioritizationConfig {
  PrioritizationConfig({
    required this.activeScheme,
    required this.integerWeights,
    required this.decimalWeights,
    required this.thresholds,
    required this.updatedAt,
    required this.updatedBy,
    this.minRating = 1,
    this.maxRating = 4,
    this.frequencyWindowDays = defaultFrequencyWindowDays,
    this.frequencyBands = defaultFrequencyBands,
  }) {
    for (final criterion in PrioritizationCriterion.values) {
      if (!integerWeights.containsKey(criterion)) {
        throw ArgumentError.value(
          integerWeights,
          'integerWeights',
          'Missing weight for $criterion',
        );
      }
      if (!decimalWeights.containsKey(criterion)) {
        throw ArgumentError.value(
          decimalWeights,
          'decimalWeights',
          'Missing weight for $criterion',
        );
      }
    }
    if (minRating >= maxRating) {
      throw ArgumentError.value(
        maxRating,
        'maxRating',
        'maxRating must exceed minRating',
      );
    }
    if (frequencyWindowDays <= 0) {
      throw ArgumentError.value(
        frequencyWindowDays,
        'frequencyWindowDays',
        'The frequency window must be a positive number of days',
      );
    }
    if (frequencyBands.length != maxRating - minRating) {
      throw ArgumentError.value(
        frequencyBands,
        'frequencyBands',
        'One report count is needed for each rating above the lowest',
      );
    }
    for (var i = 0; i < frequencyBands.length; i++) {
      final previous = i == 0 ? 1 : frequencyBands[i - 1];
      if (frequencyBands[i] <= previous) {
        throw ArgumentError.value(
          frequencyBands,
          'frequencyBands',
          'Report counts must rise with the rating, starting above 1',
        );
      }
    }
  }

  factory PrioritizationConfig.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return PrioritizationConfig(
      activeScheme: FirestoreConverters.requireEnum(
        data,
        'activeScheme',
        PrioritizationScheme.fromId,
      ),
      integerWeights: _readWeights(data, 'integerWeights'),
      decimalWeights: _readWeights(data, 'decimalWeights'),
      thresholds: _readThresholds(data),
      minRating: FirestoreConverters.optional<int>(data, 'minRating') ?? 1,
      maxRating: FirestoreConverters.optional<int>(data, 'maxRating') ?? 4,
      // Added in 4.B; a document saved before then has neither.
      frequencyWindowDays:
          FirestoreConverters.optional<int>(data, 'frequencyWindowDays') ??
          defaultFrequencyWindowDays,
      frequencyBands: data['frequencyBands'] == null
          ? defaultFrequencyBands
          : List<int>.unmodifiable(
              (data['frequencyBands'] as List<dynamic>).map(
                (value) => (value as num).toInt(),
              ),
            ),
      updatedAt: FirestoreConverters.requireDate(data, 'updatedAt'),
      updatedBy: FirestoreConverters.require<String>(data, 'updatedBy'),
    );
  }

  /// The manuscript's Table 3.2 weights, as written.
  factory PrioritizationConfig.manuscriptDefaults({
    required DateTime updatedAt,
    required String updatedBy,
    PrioritizationScheme activeScheme = PrioritizationScheme.decimalWeights,
  }) => PrioritizationConfig(
    activeScheme: activeScheme,
    integerWeights: const {
      PrioritizationCriterion.severity: 3,
      PrioritizationCriterion.safetyRisk: 4,
      PrioritizationCriterion.frequency: 2,
      PrioritizationCriterion.locationImportance: 3,
    },
    decimalWeights: const {
      PrioritizationCriterion.severity: 0.40,
      PrioritizationCriterion.safetyRisk: 0.30,
      PrioritizationCriterion.frequency: 0.20,
      PrioritizationCriterion.locationImportance: 0.10,
    },
    thresholds: const {
      PriorityLevel.critical: 3.50,
      PriorityLevel.high: 2.50,
      PriorityLevel.medium: 1.50,
      PriorityLevel.low: 1.00,
    },
    updatedAt: updatedAt,
    updatedBy: updatedBy,
  );

  static Map<PrioritizationCriterion, double> _readWeights(
    Map<String, dynamic> data,
    String field,
  ) {
    final raw = FirestoreConverters.require<Map<String, dynamic>>(data, field);
    return {
      for (final criterion in PrioritizationCriterion.values)
        criterion:
            (raw[criterion.id] as num?)?.toDouble() ??
            (throw ArgumentError.value(
              raw,
              field,
              'Missing weight for ${criterion.id}',
            )),
    };
  }

  static Map<PriorityLevel, double> _readThresholds(Map<String, dynamic> data) {
    final raw = FirestoreConverters.require<Map<String, dynamic>>(
      data,
      'thresholds',
    );
    return {
      for (final level in PriorityLevel.values)
        level:
            (raw[level.id] as num?)?.toDouble() ??
            (throw ArgumentError.value(
              raw,
              'thresholds',
              'Missing threshold for ${level.id}',
            )),
    };
  }

  /// Which weight scheme the scoring engine reads. Chris chose the §3.4
  /// formula's decimal weights on 2026-10-12 (Objective 4.B); the integer
  /// scheme stays stored so the choice can be revisited with the GSU.
  final PrioritizationScheme activeScheme;

  /// Table 3.2's weights, stored verbatim.
  final Map<PrioritizationCriterion, double> integerWeights;

  /// The §3.4 formula's weights, stored verbatim.
  final Map<PrioritizationCriterion, double> decimalWeights;

  /// Inclusive lower bound of each priority band (manuscript Table 3.5).
  final Map<PriorityLevel, double> thresholds;

  /// Bounds of the criterion rating scale (Table 3.4: 1 = Low through
  /// 4 = Very High).
  final int minRating;
  final int maxRating;

  /// How far back the Frequency hint counts similar reports, in days
  /// (Objective 4.B). DERIVED, Chris's decision of 2026-10-12: the
  /// manuscript defines Frequency as "the recurrence or number of reports
  /// involving the same issue" but gives no period.
  final int frequencyWindowDays;

  /// The report counts at which the Frequency hint rises a rating: with
  /// the default `[2, 3, 5]`, one report suggests 1 (Low), two suggest 2
  /// (Moderate), three or four suggest 3 (High), and five or more suggest 4
  /// (Very High). One count per rating above [minRating]. DERIVED, like
  /// [frequencyWindowDays]; the administrator can always change the rating.
  final List<int> frequencyBands;

  static const int defaultFrequencyWindowDays = 30;
  static const List<int> defaultFrequencyBands = [2, 3, 5];

  final DateTime updatedAt;
  final String updatedBy;

  /// The weights the scoring engine should actually apply, resolved
  /// through [activeScheme].
  Map<PrioritizationCriterion, double> get activeWeights =>
      switch (activeScheme) {
        PrioritizationScheme.integerWeights => integerWeights,
        PrioritizationScheme.decimalWeights => decimalWeights,
      };

  /// Whether [activeWeights] sum to 1.0, meaning a weighted score lands in
  /// the same 1.00–4.00 range the Table 3.5 thresholds assume.
  ///
  /// This is `false` for [PrioritizationScheme.integerWeights] as written
  /// (3 + 4 + 2 + 3 = 12), which is exactly why the conflict matters: the
  /// integer scheme needs normalizing before its scores can be compared
  /// against Table 3.5's bands at all. 4.B must handle that, and cannot
  /// until the scheme question is answered.
  bool get activeWeightsAreNormalized {
    final sum = activeWeights.values.fold<double>(
      0,
      (total, weight) => total + weight,
    );
    return (sum - 1.0).abs() < 0.0001;
  }

  Map<String, dynamic> toFirestore() => {
    'activeScheme': activeScheme.id,
    'integerWeights': {
      for (final entry in integerWeights.entries) entry.key.id: entry.value,
    },
    'decimalWeights': {
      for (final entry in decimalWeights.entries) entry.key.id: entry.value,
    },
    'thresholds': {
      for (final entry in thresholds.entries) entry.key.id: entry.value,
    },
    'minRating': minRating,
    'maxRating': maxRating,
    'frequencyWindowDays': frequencyWindowDays,
    'frequencyBands': frequencyBands,
    'updatedAt': Timestamp.fromDate(updatedAt),
    'updatedBy': updatedBy,
  };

  PrioritizationConfig copyWith({
    PrioritizationScheme? activeScheme,
    Map<PrioritizationCriterion, double>? integerWeights,
    Map<PrioritizationCriterion, double>? decimalWeights,
    Map<PriorityLevel, double>? thresholds,
    int? minRating,
    int? maxRating,
    int? frequencyWindowDays,
    List<int>? frequencyBands,
    DateTime? updatedAt,
    String? updatedBy,
  }) => PrioritizationConfig(
    activeScheme: activeScheme ?? this.activeScheme,
    integerWeights: integerWeights ?? this.integerWeights,
    decimalWeights: decimalWeights ?? this.decimalWeights,
    thresholds: thresholds ?? this.thresholds,
    minRating: minRating ?? this.minRating,
    maxRating: maxRating ?? this.maxRating,
    frequencyWindowDays: frequencyWindowDays ?? this.frequencyWindowDays,
    frequencyBands: frequencyBands ?? this.frequencyBands,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedBy: updatedBy ?? this.updatedBy,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrioritizationConfig &&
          other.activeScheme == activeScheme &&
          _mapEquals(other.integerWeights, integerWeights) &&
          _mapEquals(other.decimalWeights, decimalWeights) &&
          _mapEquals(other.thresholds, thresholds) &&
          other.minRating == minRating &&
          other.maxRating == maxRating &&
          other.frequencyWindowDays == frequencyWindowDays &&
          listEquals(other.frequencyBands, frequencyBands) &&
          other.updatedAt == updatedAt &&
          other.updatedBy == updatedBy;

  static bool _mapEquals<K>(Map<K, double> a, Map<K, double> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    activeScheme,
    Object.hashAll(integerWeights.entries.map((e) => '${e.key}:${e.value}')),
    Object.hashAll(decimalWeights.entries.map((e) => '${e.key}:${e.value}')),
    Object.hashAll(thresholds.entries.map((e) => '${e.key}:${e.value}')),
    minRating,
    maxRating,
    frequencyWindowDays,
    Object.hashAll(frequencyBands),
    updatedAt,
    updatedBy,
  );

  @override
  String toString() =>
      'PrioritizationConfig(activeScheme: $activeScheme, '
      'normalized: $activeWeightsAreNormalized, updatedAt: $updatedAt)';
}

/// The four weighted criteria (manuscript Table 3.2 / §3.4 formula).
enum PrioritizationCriterion {
  severity,
  safetyRisk,
  frequency,
  locationImportance;

  String get id => name;

  static PrioritizationCriterion fromId(String id) =>
      PrioritizationCriterion.values.firstWhere(
        (criterion) => criterion.id == id,
        orElse: () => throw ArgumentError.value(
          id,
          'id',
          'Unknown PrioritizationCriterion',
        ),
      );
}
