import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show listEquals;

import '../../../../core/constants/damage_categories.dart';
import '../../../../core/utils/firestore_converters.dart';

/// The `config/classification_rules` document — the admin-editable keyword
/// dictionary the rule-based classifier matches report descriptions
/// against (manuscript §3.4, Table 3.3 "Rule-Based Classification and
/// Maintenance Personnel Assignment Rules").
///
/// Stored as data rather than compiled in, because §1.5 constrains the
/// mechanism to "predefined keywords, categories, criteria, ratings, and
/// assigned weights" with no AI or machine learning — which only stays
/// maintainable if GSU staff can edit the keyword list without a rebuild.
///
/// `DamageCategory.sampleKeywords` (from 1.A) holds Table 3.3's keywords
/// as a compile-time reference for traceability; **this document is the
/// live, authoritative list.** [seededFromManuscript] produces one
/// pre-populated with Table 3.3 as a starting point.
class ClassificationRulesConfig {
  ClassificationRulesConfig({
    required this.keywordsByCategory,
    required this.updatedAt,
    required this.updatedBy,
    this.caseSensitive = false,
  }) {
    for (final entry in keywordsByCategory.entries) {
      for (final keyword in entry.value) {
        if (keyword.trim().isEmpty) {
          throw ArgumentError.value(
            entry.value,
            'keywordsByCategory',
            'Blank keyword for category ${entry.key.id}',
          );
        }
      }
    }
  }

  factory ClassificationRulesConfig.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    final raw = FirestoreConverters.require<Map<String, dynamic>>(
      data,
      'keywordsByCategory',
    );
    return ClassificationRulesConfig(
      keywordsByCategory: {
        for (final category in DamageCategory.values)
          if (raw.containsKey(category.id))
            category: (raw[category.id] as List<dynamic>)
                .map((keyword) => keyword.toString())
                .toList(growable: false),
      },
      caseSensitive:
          FirestoreConverters.optional<bool>(data, 'caseSensitive') ?? false,
      updatedAt: FirestoreConverters.requireDate(data, 'updatedAt'),
      updatedBy: FirestoreConverters.require<String>(data, 'updatedBy'),
    );
  }

  /// A starting dictionary populated from Table 3.3, for first-run
  /// seeding. `generalMaintenance` gets no keywords — the manuscript lists
  /// none, and it functions as the catch-all.
  factory ClassificationRulesConfig.seededFromManuscript({
    required DateTime updatedAt,
    required String updatedBy,
  }) => ClassificationRulesConfig(
    keywordsByCategory: {
      for (final category in DamageCategory.values)
        category: List<String>.unmodifiable(category.sampleKeywords),
    },
    updatedAt: updatedAt,
    updatedBy: updatedBy,
  );

  /// Keywords to match per category. A report matching none of these is
  /// routed to the Administrator for manual classification (§3.4).
  final Map<DamageCategory, List<String>> keywordsByCategory;

  /// Whether matching respects letter case. Defaults to `false`: a
  /// requestor typing "Exposed Wire" should match "exposed wire".
  /// DERIVED — the manuscript does not specify matching semantics.
  final bool caseSensitive;

  final DateTime updatedAt;
  final String updatedBy;

  /// Every keyword across all categories, for duplicate-keyword checks in
  /// the admin editor (4.A).
  Iterable<String> get allKeywords =>
      keywordsByCategory.values.expand((keywords) => keywords);

  Map<String, dynamic> toFirestore() => {
    'keywordsByCategory': {
      for (final entry in keywordsByCategory.entries) entry.key.id: entry.value,
    },
    'caseSensitive': caseSensitive,
    'updatedAt': Timestamp.fromDate(updatedAt),
    'updatedBy': updatedBy,
  };

  ClassificationRulesConfig copyWith({
    Map<DamageCategory, List<String>>? keywordsByCategory,
    bool? caseSensitive,
    DateTime? updatedAt,
    String? updatedBy,
  }) => ClassificationRulesConfig(
    keywordsByCategory: keywordsByCategory ?? this.keywordsByCategory,
    caseSensitive: caseSensitive ?? this.caseSensitive,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedBy: updatedBy ?? this.updatedBy,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ClassificationRulesConfig) return false;
    if (other.keywordsByCategory.length != keywordsByCategory.length) {
      return false;
    }
    for (final entry in keywordsByCategory.entries) {
      if (!listEquals(other.keywordsByCategory[entry.key], entry.value)) {
        return false;
      }
    }
    return other.caseSensitive == caseSensitive &&
        other.updatedAt == updatedAt &&
        other.updatedBy == updatedBy;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(
      keywordsByCategory.entries.map(
        (entry) => '${entry.key.id}:${entry.value.join(",")}',
      ),
    ),
    caseSensitive,
    updatedAt,
    updatedBy,
  );

  @override
  String toString() =>
      'ClassificationRulesConfig(categories: ${keywordsByCategory.length}, '
      'keywords: ${allKeywords.length}, updatedAt: $updatedAt)';
}
