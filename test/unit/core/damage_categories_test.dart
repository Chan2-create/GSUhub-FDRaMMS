import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';

void main() {
  group('DamageCategory', () {
    test('has exactly the seven categories from manuscript §1.5', () {
      expect(DamageCategory.values.length, 7);
    });

    test('id round-trips through fromId', () {
      for (final category in DamageCategory.values) {
        expect(DamageCategory.fromId(category.id), category);
      }
    });

    test('every category except generalMaintenance has sample keywords', () {
      for (final category in DamageCategory.values) {
        if (category == DamageCategory.generalMaintenance) {
          expect(category.sampleKeywords, isEmpty);
        } else {
          expect(category.sampleKeywords, isNotEmpty);
        }
      }
    });
  });
}
