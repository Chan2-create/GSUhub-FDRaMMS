import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/features/classification/data/models/classification_rules_config.dart';
import 'package:gsuhub/features/classification/domain/keyword_classifier.dart';

/// The rule-based classifier (manuscript §3.4, Table 3.3; Objective 4.A).
void main() {
  final savedAt = DateTime.utc(2026, 10, 12);
  final tableThreeThree = KeywordClassifier(
    ClassificationRulesConfig.seededFromManuscript(
      updatedAt: savedAt,
      updatedBy: 'admin-1',
    ),
  );

  KeywordClassifier classifierFor(
    Map<DamageCategory, List<String>> keywords, {
    bool caseSensitive = false,
  }) => KeywordClassifier(
    ClassificationRulesConfig(
      keywordsByCategory: keywords,
      caseSensitive: caseSensitive,
      updatedAt: savedAt,
      updatedBy: 'admin-1',
    ),
  );

  ClassificationResult classify(String text) => tableThreeThree.classify(text);

  test('classifies a report by a Table 3.3 keyword', () {
    final result = classify('There is an exposed wire beside the switch.');

    expect(result.category, DamageCategory.electrical);
    expect(result.keywordsFor(DamageCategory.electrical), ['exposed wire']);
  });

  test('ignores letter case, punctuation and line breaks', () {
    expect(
      classify('SHORT-CIRCUIT in the lab!').category,
      DamageCategory.electrical,
    );
    expect(
      classify('The drain is\nclogged... clogged drain').category,
      DamageCategory.plumbing,
    );
  });

  test('lets each word of a keyword take a longer ending', () {
    // "exposed wire" in "exposed wires"; "leaking aircon" in "leaking
    // aircons".
    expect(
      classify('Two exposed wires by the door').category,
      DamageCategory.electrical,
    );
    expect(
      classify('Both leaking aircons in the faculty room').category,
      DamageCategory.airConditioning,
    );
  });

  test('matches a phrase only with its words in order', () {
    // "leaking pipe" is not "the pipe is leaking".
    expect(classify('The pipe is leaking').matchedAny, isFalse);
  });

  test('matches only at the start of a word', () {
    // "flooding" is not found inside "reflooding".
    expect(classify('A reflooding test of the tank').matchedAny, isFalse);
  });

  test('reads the title as well as the description', () {
    final text = KeywordClassifier.textOf(
      title: 'Clogged drain',
      description: 'Water everywhere in the comfort room.',
    );

    expect(classify(text).category, DamageCategory.plumbing);
  });

  test('gives the damage type with the most keywords found', () {
    final result = classify(
      'Flooding from a leaking pipe caused a short circuit.',
    );

    expect(result.category, DamageCategory.plumbing);
    expect(result.keywordsFor(DamageCategory.plumbing), [
      'leaking pipe',
      'flooding',
    ]);
    expect(result.keywordsFor(DamageCategory.electrical), ['short circuit']);
    expect(result.isTie, isFalse);
  });

  test('a tie between two damage types decides nothing', () {
    // §3.4 leaves an unmatched report to the administrator; a tie is no
    // better a match.
    final result = classify('A short circuit, and now flooding.');

    expect(result.category, isNull);
    expect(result.isTie, isTrue);
    expect(result.matchedAny, isTrue);
  });

  test('a report that matches no keyword is left unclassified', () {
    final result = classify('The projector remote is missing.');

    expect(result.category, isNull);
    expect(result.matchedAny, isFalse);
    expect(result.isTie, isFalse);
  });

  test('blank text matches nothing', () {
    expect(classify('').matchedAny, isFalse);
    expect(classify('  \n ').matchedAny, isFalse);
  });

  test('uses the dictionary it is given, not Table 3.3', () {
    final classifier = classifierFor({
      DamageCategory.plumbing: ['tap'],
    });

    expect(
      classifier.classify('The tap drips all night').category,
      DamageCategory.plumbing,
    );
    expect(classifier.classify('An exposed wire').matchedAny, isFalse);
  });

  test('respects letter case when the dictionary says to', () {
    final classifier = classifierFor({
      DamageCategory.cleaningAndSanitation: ['CR'],
    }, caseSensitive: true);

    expect(
      classifier.classify('The CR smells').category,
      DamageCategory.cleaningAndSanitation,
    );
    expect(classifier.classify('the cr smells').matchedAny, isFalse);
  });

  test('a keyword with no letters or digits never matches', () {
    final classifier = classifierFor({
      DamageCategory.electrical: ['--'],
    });

    expect(classifier.classify('-- --').matchedAny, isFalse);
  });

  test('normalize keeps letters and digits, single-spaced', () {
    expect(
      KeywordClassifier.normalize('  Room 101:\tAIRCON  not-cooling '),
      'room 101 aircon not cooling',
    );
    expect(
      KeywordClassifier.normalize('Room 101', caseSensitive: true),
      'Room 101',
    );
  });
}
