import '../../../../core/data/data_record.dart';
import '../../../../core/utils/record_converters.dart';

/// The `config/duplicate_detection` document — tunable parameters for
/// flagging potential duplicate reports.
///
/// The criteria come from manuscript §3.4, "Duplicate Report Detection
/// Rules", which lists exactly five comparison inputs:
///
/// - QR code or facility identifier
/// - facility location
/// - report category
/// - similarity of report descriptions
/// - submission time interval
///
/// Each toggle below maps to one of those. The manuscript gives no
/// numeric values for the similarity threshold or the time window, so
/// [descriptionSimilarityThreshold] and [timeWindowHours] are DERIVED
/// starting points meant to be tuned against real GSU data — see
/// docs/data_dictionary.md. How the criteria combine is the detector's
/// (`DuplicateDetector`, Objective 4.C).
///
/// Detection only ever *flags*: §1.5 is explicit that flagged reports
/// "still require verification by an authorized GSU Administrator before
/// they can be merged, dismissed, or retained as separate requests".
/// Nothing in this config authorizes an automatic merge.
class DuplicateDetectionConfig {
  DuplicateDetectionConfig({
    required this.enabled,
    required this.descriptionSimilarityThreshold,
    required this.timeWindowHours,
    required this.updatedAt,
    required this.updatedBy,
    this.matchOnFacilityIdentifier = true,
    this.matchOnLocation = true,
    this.matchOnCategory = true,
  }) {
    RecordConverters.validateRange(
      descriptionSimilarityThreshold,
      0.0,
      1.0,
      'descriptionSimilarityThreshold',
    );
    if (timeWindowHours <= 0) {
      throw ArgumentError.value(
        timeWindowHours,
        'timeWindowHours',
        'The duplicate detection window must be a positive number of hours',
      );
    }
  }

  factory DuplicateDetectionConfig.fromRecord(DataRecord record) {
    final data = record.fields;
    return DuplicateDetectionConfig(
      enabled: RecordConverters.require<bool>(data, 'enabled'),
      descriptionSimilarityThreshold: RecordConverters.require<num>(
        data,
        'descriptionSimilarityThreshold',
      ).toDouble(),
      timeWindowHours: RecordConverters.require<int>(data, 'timeWindowHours'),
      matchOnFacilityIdentifier:
          RecordConverters.optional<bool>(data, 'matchOnFacilityIdentifier') ??
          true,
      matchOnLocation:
          RecordConverters.optional<bool>(data, 'matchOnLocation') ?? true,
      matchOnCategory:
          RecordConverters.optional<bool>(data, 'matchOnCategory') ?? true,
      updatedAt: RecordConverters.requireDate(data, 'updatedAt'),
      updatedBy: RecordConverters.require<String>(data, 'updatedBy'),
    );
  }

  /// Defaults using the DERIVED starting values described on the class.
  /// The threshold was 0.75 until 4.C defined how similarity is measured
  /// (the share of the shorter report's key words the other also uses):
  /// two people describing one problem rarely share three in four words,
  /// so 0.75 would almost never flag a real duplicate.
  factory DuplicateDetectionConfig.defaults({
    required DateTime updatedAt,
    required String updatedBy,
  }) => DuplicateDetectionConfig(
    enabled: true,
    descriptionSimilarityThreshold: 0.5,
    timeWindowHours: 72,
    updatedAt: updatedAt,
    updatedBy: updatedBy,
  );

  final bool enabled;

  /// Compare the scanned QR code / facility id (§3.4 criterion 1).
  final bool matchOnFacilityIdentifier;

  /// Compare the stated facility location (§3.4 criterion 2).
  final bool matchOnLocation;

  /// Compare the classified damage category (§3.4 criterion 3).
  final bool matchOnCategory;

  /// Minimum description similarity, 0.0–1.0, for two reports of
  /// different (or unknown) damage types to be considered potential
  /// duplicates (§3.4 criterion 4). DERIVED value.
  final double descriptionSimilarityThreshold;

  /// How recent the other report must be, in hours (§3.4 criterion 5:
  /// "Reports submitted for the same facility within a defined time
  /// period are flagged"). DERIVED value.
  final int timeWindowHours;

  final DateTime updatedAt;
  final String updatedBy;

  /// The time window as a [Duration], for query construction.
  Duration get timeWindow => Duration(hours: timeWindowHours);

  Map<String, dynamic> toFields() => {
    'enabled': enabled,
    'matchOnFacilityIdentifier': matchOnFacilityIdentifier,
    'matchOnLocation': matchOnLocation,
    'matchOnCategory': matchOnCategory,
    'descriptionSimilarityThreshold': descriptionSimilarityThreshold,
    'timeWindowHours': timeWindowHours,
    'updatedAt': updatedAt,
    'updatedBy': updatedBy,
  };

  DuplicateDetectionConfig copyWith({
    bool? enabled,
    bool? matchOnFacilityIdentifier,
    bool? matchOnLocation,
    bool? matchOnCategory,
    double? descriptionSimilarityThreshold,
    int? timeWindowHours,
    DateTime? updatedAt,
    String? updatedBy,
  }) => DuplicateDetectionConfig(
    enabled: enabled ?? this.enabled,
    matchOnFacilityIdentifier:
        matchOnFacilityIdentifier ?? this.matchOnFacilityIdentifier,
    matchOnLocation: matchOnLocation ?? this.matchOnLocation,
    matchOnCategory: matchOnCategory ?? this.matchOnCategory,
    descriptionSimilarityThreshold:
        descriptionSimilarityThreshold ?? this.descriptionSimilarityThreshold,
    timeWindowHours: timeWindowHours ?? this.timeWindowHours,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedBy: updatedBy ?? this.updatedBy,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DuplicateDetectionConfig &&
          other.enabled == enabled &&
          other.matchOnFacilityIdentifier == matchOnFacilityIdentifier &&
          other.matchOnLocation == matchOnLocation &&
          other.matchOnCategory == matchOnCategory &&
          other.descriptionSimilarityThreshold ==
              descriptionSimilarityThreshold &&
          other.timeWindowHours == timeWindowHours &&
          other.updatedAt == updatedAt &&
          other.updatedBy == updatedBy;

  @override
  int get hashCode => Object.hash(
    enabled,
    matchOnFacilityIdentifier,
    matchOnLocation,
    matchOnCategory,
    descriptionSimilarityThreshold,
    timeWindowHours,
    updatedAt,
    updatedBy,
  );

  @override
  String toString() =>
      'DuplicateDetectionConfig(enabled: $enabled, '
      'similarity: $descriptionSimilarityThreshold, '
      'window: ${timeWindowHours}h)';
}
