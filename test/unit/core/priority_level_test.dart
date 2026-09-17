import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/enums/priority_level.dart';

void main() {
  group('PriorityLevel.fromScore (manuscript Table 3.5)', () {
    test('critical range: 3.50 - 4.00', () {
      expect(PriorityLevel.fromScore(3.50), PriorityLevel.critical);
      expect(PriorityLevel.fromScore(4.00), PriorityLevel.critical);
    });

    test('high range: 2.50 - 3.49', () {
      expect(PriorityLevel.fromScore(2.50), PriorityLevel.high);
      expect(PriorityLevel.fromScore(3.49), PriorityLevel.high);
    });

    test('medium range: 1.50 - 2.49', () {
      expect(PriorityLevel.fromScore(1.50), PriorityLevel.medium);
      expect(PriorityLevel.fromScore(2.49), PriorityLevel.medium);
    });

    test('low range: 1.00 - 1.49', () {
      expect(PriorityLevel.fromScore(1.00), PriorityLevel.low);
      expect(PriorityLevel.fromScore(1.49), PriorityLevel.low);
    });

    test('throws outside the theoretical 1.00-4.00 formula range', () {
      expect(() => PriorityLevel.fromScore(0.99), throwsArgumentError);
      expect(() => PriorityLevel.fromScore(4.01), throwsArgumentError);
    });

    test('id round-trips through fromId', () {
      for (final level in PriorityLevel.values) {
        expect(PriorityLevel.fromId(level.id), level);
      }
    });
  });
}
