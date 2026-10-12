import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/features/classification/data/models/classification_rules_config.dart';
import 'package:gsuhub/features/classification/presentation/keyword_draft.dart';

/// The Settings page's keyword editing rules (Objective 4.A).
void main() {
  final savedAt = DateTime.utc(2026, 10, 12);
  final saved = ClassificationRulesConfig.seededFromManuscript(
    updatedAt: savedAt,
    updatedBy: 'admin-1',
  );
  final draft = KeywordDraft.of(saved);

  test('stores a keyword trimmed, single-spaced and in lower case', () {
    expect(draft.clean('  Burst   PIPE '), 'burst pipe');

    final added = draft.adding(DamageCategory.plumbing, '  Burst   PIPE ');
    expect(added.keywordsOf(DamageCategory.plumbing).last, 'burst pipe');
    // The draft it came from is untouched.
    expect(
      draft.keywordsOf(DamageCategory.plumbing),
      isNot(contains('burst pipe')),
    );
  });

  test('removes a keyword from its damage type only', () {
    final removed = draft.removing(DamageCategory.electrical, 'power outage');

    expect(
      removed.keywordsOf(DamageCategory.electrical),
      isNot(contains('power outage')),
    );
    expect(
      removed.keywordsOf(DamageCategory.plumbing),
      draft.keywordsOf(DamageCategory.plumbing),
    );
  });

  group('refuses', () {
    String? problem(DamageCategory category, String input) =>
        draft.problemWith(category, input);

    test('nothing typed', () {
      expect(problem(DamageCategory.plumbing, '   '), 'Type a keyword first.');
    });

    test('punctuation alone', () {
      expect(
        problem(DamageCategory.plumbing, '!!!'),
        'A keyword needs letters or numbers.',
      );
    });

    test('a keyword shorter than three characters', () {
      expect(problem(DamageCategory.plumbing, 'cr'), contains('at least 3'));
      expect(problem(DamageCategory.plumbing, 'tap'), isNull);
    });

    test('a keyword longer than 60 characters', () {
      expect(
        problem(DamageCategory.plumbing, 'a' * 61),
        contains('60 characters'),
      );
      expect(problem(DamageCategory.plumbing, 'a' * 60), isNull);
    });

    test('a keyword already on the list', () {
      expect(
        problem(DamageCategory.plumbing, 'Flooding'),
        '"flooding" is already on this list.',
      );
    });

    test("another damage type's keyword, compared as the classifier "
        'compares', () {
      // "Exposed-Wire" reads as "exposed wire".
      expect(
        problem(DamageCategory.plumbing, 'Exposed-Wire'),
        '"exposed wire" is already a keyword for Electrical. A keyword can '
        'point to one damage type only.',
      );
    });

    test('and does not add what it refuses', () {
      expect(draft.adding(DamageCategory.plumbing, 'cr'), draft);
    });
  });

  test('knows whether it differs from the saved list', () {
    expect(draft.sameKeywordsAs(saved), isTrue);
    expect(
      draft.adding(DamageCategory.plumbing, 'burst pipe').sameKeywordsAs(saved),
      isFalse,
    );
    // Adding and removing the same keyword is no change.
    expect(
      draft
          .adding(DamageCategory.plumbing, 'burst pipe')
          .removing(DamageCategory.plumbing, 'burst pipe')
          .sameKeywordsAs(saved),
      isTrue,
    );
  });

  test('saves every damage type, even one with no keywords', () {
    final config = draft
        .removing(DamageCategory.carpentry, 'broken door')
        .toConfig(updatedAt: savedAt, updatedBy: 'admin-2');

    expect(config.keywordsByCategory.keys, DamageCategory.values);
    expect(
      config.keywordsByCategory[DamageCategory.generalMaintenance],
      isEmpty,
    );
    expect(
      config.keywordsByCategory[DamageCategory.carpentry],
      isNot(contains('broken door')),
    );
    expect(config.updatedBy, 'admin-2');
  });

  test('classifies with the keywords being edited', () {
    final edited = draft.adding(DamageCategory.plumbing, 'burst pipe');

    expect(
      edited.classifier.classify('A burst pipe in the lab').category,
      DamageCategory.plumbing,
    );
    expect(
      draft.classifier.classify('A burst pipe in the lab').category,
      isNull,
    );
  });

  test('keeps letter case when the dictionary is case-sensitive', () {
    final cased = KeywordDraft.of(saved.copyWith(caseSensitive: true));

    expect(cased.clean('  CR  Odor '), 'CR Odor');
  });
}
