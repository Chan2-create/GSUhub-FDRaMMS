import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/utils/result.dart';

void main() {
  group('Result', () {
    test('Success folds to onSuccess', () {
      const result = Result<int>.success(42);
      final folded = result.fold((value) => 'ok:$value', (f) => 'err:$f');
      expect(folded, 'ok:42');
      expect(result.isSuccess, isTrue);
      expect(result.isFailure, isFalse);
    });

    test('Error folds to onFailure', () {
      const result = Result<int>.failure(ValidationFailure('bad input'));
      final folded = result.fold(
        (value) => 'ok:$value',
        (f) => 'err:${f.message}',
      );
      expect(folded, 'err:bad input');
      expect(result.isFailure, isTrue);
    });

    test('map transforms a Success value only', () {
      const success = Result<int>.success(2);
      final mapped = success.map((value) => value * 10);
      expect(mapped.fold((v) => v, (_) => -1), 20);

      const failure = Result<int>.failure(ServerFailure('down'));
      final mappedFailure = failure.map((value) => value * 10);
      expect(mappedFailure.isFailure, isTrue);
    });
  });
}
