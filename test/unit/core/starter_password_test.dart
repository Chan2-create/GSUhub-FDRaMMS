import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/services/firebase/firebase_account_provisioning_service.dart';
import 'package:gsuhub/core/utils/account_validation.dart';

/// The starter password an account made from the console gets (2026-11-25):
/// Firebase's password policy refuses any that does not meet it, which
/// would stop Create Account on the console.
void main() {
  test('every starter password meets the password policy', () {
    final random = Random(25);
    for (var i = 0; i < 5000; i++) {
      final password = FirebaseAccountProvisioningService.randomPassword(
        random,
      );
      expect(password, hasLength(PasswordPolicy.maxLength));
      expect(PasswordPolicy.isValid(password), isTrue, reason: password);
    }
  });

  test('two are not the same', () {
    expect(
      FirebaseAccountProvisioningService.randomPassword(),
      isNot(FirebaseAccountProvisioningService.randomPassword()),
    );
  });
}
