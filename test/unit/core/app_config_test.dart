import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/config/app_config.dart';

void main() {
  group('PrioritizationWeights', () {
    test('manuscript Table 3.2 defaults sum to 1.0', () {
      const weights = PrioritizationWeights();
      expect(weights.isValid, isTrue);
      expect(weights.severity, 0.40);
      expect(weights.safetyRisk, 0.30);
      expect(weights.frequency, 0.20);
      expect(weights.locationImportance, 0.10);
    });

    test('isValid is false when weights do not sum to 1.0', () {
      const weights = PrioritizationWeights(severity: 0.9);
      expect(weights.isValid, isFalse);
    });
  });
}
