import 'package:flutter/foundation.dart';

import '../../../core/constants/damage_categories.dart';
import '../data/models/classification_rules_config.dart';
import '../domain/keyword_classifier.dart';

/// The keyword dictionary as the Settings page is editing it (Objective
/// 4.A): what is saved, plus the administrator's unsaved additions and
/// removals.
@immutable
class KeywordDraft {
  KeywordDraft(
    Map<DamageCategory, List<String>> keywordsByCategory, {
    this.caseSensitive = false,
  }) : keywordsByCategory = Map.unmodifiable({
         for (final category in DamageCategory.values)
           category: List<String>.unmodifiable(
             keywordsByCategory[category] ?? const <String>[],
           ),
       });

  factory KeywordDraft.of(ClassificationRulesConfig config) => KeywordDraft(
    config.keywordsByCategory,
    caseSensitive: config.caseSensitive,
  );

  /// Shortest keyword accepted. Each word of a keyword also matches longer
  /// words that start with it ("leak" matches "leaking"), so a two-letter
  /// keyword would match the start of far too many words.
  static const int minLength = 3;

  /// Longest keyword accepted. A keyword matches as a phrase, word for
  /// word, so a long one would hardly ever match.
  static const int maxLength = 60;

  /// Every damage type, in order, each with its keywords (possibly none).
  final Map<DamageCategory, List<String>> keywordsByCategory;

  final bool caseSensitive;

  List<String> keywordsOf(DamageCategory category) =>
      keywordsByCategory[category]!;

  /// [input] as it would be stored: trimmed, single-spaced, and in lower
  /// case unless the dictionary is case-sensitive.
  String clean(String input) {
    final spaced = input.trim().replaceAll(RegExp(r'\s+'), ' ');
    return caseSensitive ? spaced : spaced.toLowerCase();
  }

  /// Why [input] cannot be added to [category], or null when it can.
  String? problemWith(DamageCategory category, String input) {
    final keyword = clean(input);
    if (keyword.isEmpty) return 'Type a keyword first.';
    final compared = _compared(keyword);
    if (compared.isEmpty) return 'A keyword needs letters or numbers.';
    if (keyword.length < minLength) {
      return 'Use at least $minLength characters: a shorter keyword would '
          'match the start of too many words.';
    }
    if (keyword.length > maxLength) {
      return 'Keep it to $maxLength characters: a keyword matches only '
          'when its words appear in order.';
    }
    for (final entry in keywordsByCategory.entries) {
      for (final existing in entry.value) {
        if (_compared(existing) != compared) continue;
        return entry.key == category
            ? '"$existing" is already on this list.'
            : '"$existing" is already a keyword for ${entry.key.label}. '
                  'A keyword can point to one damage type only.';
      }
    }
    return null;
  }

  /// This draft with [input] added to [category]. Unchanged when
  /// [problemWith] has an objection.
  KeywordDraft adding(DamageCategory category, String input) {
    if (problemWith(category, input) != null) return this;
    return _with(category, [...keywordsOf(category), clean(input)]);
  }

  KeywordDraft removing(DamageCategory category, String keyword) =>
      _with(category, [
        for (final existing in keywordsOf(category))
          if (existing != keyword) existing,
      ]);

  /// Whether this draft lists the same keywords as [config], in the same
  /// order.
  bool sameKeywordsAs(ClassificationRulesConfig config) =>
      this == KeywordDraft.of(config);

  /// The dictionary to save. Damage types without keywords are kept, as
  /// empty lists, so the saved document names all of them.
  ClassificationRulesConfig toConfig({
    required DateTime updatedAt,
    required String updatedBy,
  }) => ClassificationRulesConfig(
    keywordsByCategory: keywordsByCategory,
    caseSensitive: caseSensitive,
    updatedAt: updatedAt,
    updatedBy: updatedBy,
  );

  /// The classifier as this draft would run it, for the page's "Try a
  /// description" box.
  KeywordClassifier get classifier => KeywordClassifier(
    toConfig(updatedAt: DateTime.utc(2026), updatedBy: 'draft'),
  );

  KeywordDraft _with(DamageCategory category, List<String> keywords) =>
      KeywordDraft({
        ...keywordsByCategory,
        category: keywords,
      }, caseSensitive: caseSensitive);

  /// The form the classifier compares, so "Exposed wire" and "exposed
  /// wire," count as the same keyword.
  String _compared(String keyword) =>
      KeywordClassifier.normalize(keyword, caseSensitive: caseSensitive);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! KeywordDraft || other.caseSensitive != caseSensitive) {
      return false;
    }
    for (final category in DamageCategory.values) {
      if (!listEquals(other.keywordsOf(category), keywordsOf(category))) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    caseSensitive,
    Object.hashAll([
      for (final category in DamageCategory.values)
        Object.hashAll(keywordsOf(category)),
    ]),
  );
}
