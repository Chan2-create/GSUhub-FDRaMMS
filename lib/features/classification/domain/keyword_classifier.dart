import 'package:flutter/foundation.dart';

import '../../../core/constants/damage_categories.dart';
import '../data/models/classification_rules_config.dart';

/// One keyword found in a report's text.
@immutable
class KeywordMatch {
  const KeywordMatch(this.category, this.keyword);

  final DamageCategory category;
  final String keyword;

  @override
  bool operator ==(Object other) =>
      other is KeywordMatch &&
      other.category == category &&
      other.keyword == keyword;

  @override
  int get hashCode => Object.hash(category, keyword);

  @override
  String toString() => 'KeywordMatch(${category.id}: "$keyword")';
}

/// What the keyword classifier made of one report (Objective 4.A).
@immutable
class ClassificationResult {
  const ClassificationResult({required this.category, required this.matches});

  /// Nothing matched.
  static const ClassificationResult none = ClassificationResult(
    category: null,
    matches: [],
  );

  /// The damage type the report is classified into, or null when no
  /// keyword matched — or when two types matched equally often, which no
  /// rule can settle. Either way an administrator classifies it by hand
  /// (§3.4: reports that match no keyword "are forwarded to the authorized
  /// GSU Administrator for manual review and classification").
  final DamageCategory? category;

  /// Every keyword found, in dictionary order.
  final List<KeywordMatch> matches;

  bool get matchedAny => matches.isNotEmpty;

  /// Keywords were found, but for two or more types equally.
  bool get isTie => category == null && matches.isNotEmpty;

  /// The keywords found for [category].
  List<String> keywordsFor(DamageCategory category) => [
    for (final match in matches)
      if (match.category == category) match.keyword,
  ];
}

/// The rule-based damage classifier (manuscript §3.4, Table 3.3;
/// Objective 4.A).
///
/// Looks for each keyword of the `config/classification_rules` dictionary
/// in a report's title and description. A keyword matches as a phrase:
/// its words in the same order, each allowed a longer ending — "exposed
/// wire" matches "the exposed wires", and "leaking pipe" matches "a
/// leaking pipes joint", but not "the pipe is leaking". Case is ignored
/// unless the dictionary says otherwise; punctuation and line breaks
/// count as spaces.
///
/// The report goes to the damage type with the most keywords found. A tie
/// between types decides nothing, and the report is left for an
/// administrator. DERIVED: the manuscript says only that the description
/// is compared with the keywords.
///
/// Pure Dart, no Firebase: the faculty and staff app runs it when a report
/// is filed (there is no server on the Spark plan), and the console runs
/// it to show an administrator why a report was classified as it was.
class KeywordClassifier {
  KeywordClassifier(this.rules)
    : _patterns = {
        for (final entry in rules.keywordsByCategory.entries)
          for (final keyword in entry.value)
            (entry.key, keyword): ?_patternFor(keyword, rules.caseSensitive),
      };

  final ClassificationRulesConfig rules;
  final Map<(DamageCategory, String), RegExp> _patterns;

  /// The text classified for a report: its title, then its description.
  /// The title is included because requestors often name the problem there
  /// ("Leaking pipe in the CR") and describe the circumstances below.
  static String textOf({required String title, required String description}) =>
      '$title\n$description';

  ClassificationResult classify(String text) {
    final haystack = normalize(text, caseSensitive: rules.caseSensitive);
    if (haystack.isEmpty) return ClassificationResult.none;

    final matches = <KeywordMatch>[];
    final counts = <DamageCategory, int>{};
    for (final category in DamageCategory.values) {
      for (final keyword
          in rules.keywordsByCategory[category] ?? const <String>[]) {
        final pattern = _patterns[(category, keyword)];
        if (pattern == null || !pattern.hasMatch(haystack)) continue;
        matches.add(KeywordMatch(category, keyword));
        counts[category] = (counts[category] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return ClassificationResult.none;

    final most = counts.values.reduce((a, b) => a > b ? a : b);
    final leaders = [
      for (final entry in counts.entries)
        if (entry.value == most) entry.key,
    ];
    return ClassificationResult(
      category: leaders.length == 1 ? leaders.single : null,
      matches: List.unmodifiable(matches),
    );
  }

  /// [text] as the classifier compares it: letters and digits only,
  /// single-spaced, lower case unless [caseSensitive].
  static String normalize(String text, {bool caseSensitive = false}) {
    final cased = caseSensitive ? text : text.toLowerCase();
    return cased.replaceAll(_separators, ' ').trim();
  }

  static final RegExp _separators = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

  /// A keyword's words in order, each followed by any further letters, and
  /// starting at a word boundary. Null for a keyword with no letters or
  /// digits, which can match nothing.
  static RegExp? _patternFor(String keyword, bool caseSensitive) {
    final words = normalize(keyword, caseSensitive: caseSensitive).split(' ');
    if (words.length == 1 && words.single.isEmpty) return null;
    final phrase = words.map(RegExp.escape).join(r'[\p{L}\p{N}]* ');
    return RegExp('(?:^| )$phrase[\\p{L}\\p{N}]*(?= |\$)', unicode: true);
  }
}
