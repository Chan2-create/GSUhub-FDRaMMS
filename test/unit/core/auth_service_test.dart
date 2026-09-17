import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/services/auth_service.dart';

void main() {
  group('AuthUser', () {
    test('holds the identity fields it is constructed with', () {
      const user = AuthUser(
        uid: 'abc123',
        email: 'admin@dorsu.edu.ph',
        role: UserRole.admin,
      );

      expect(user.uid, 'abc123');
      expect(user.email, 'admin@dorsu.edu.ph');
      expect(user.role, UserRole.admin);
    });
  });
}
