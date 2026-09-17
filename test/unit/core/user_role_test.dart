import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/enums/user_role.dart';

void main() {
  group('UserRole', () {
    test('id round-trips through fromId', () {
      for (final role in UserRole.values) {
        expect(UserRole.fromId(role.id), role);
      }
    });

    test('fromId throws on unknown value', () {
      expect(() => UserRole.fromId('student'), throwsArgumentError);
    });
  });
}
