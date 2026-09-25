import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../config/app_config.dart';
import '../../errors/firebase_error_mapper.dart';
import '../../utils/result.dart';
import '../account_provisioning_service.dart';
import 'firebase_call_guard.dart';

/// [AccountProvisioningService] over a second Firebase app instance.
///
/// Creating a user with the client SDK signs that user in, which on the
/// default app would sign the administrator out mid-task. A separately
/// named app has its own auth state, so the new account signs in there
/// and is signed straight back out, leaving the administrator's session
/// untouched. This is the standard approach where there is no server to
/// call the Admin SDK from.
class FirebaseAccountProvisioningService implements AccountProvisioningService {
  FirebaseAccountProvisioningService({
    required this._config,
    required this._guard,
  });

  final AppConfig _config;
  final FirebaseCallGuard _guard;

  static const String _appName = 'account-provisioning';

  @override
  Future<Result<ProvisionedAccount>> provision({
    required String email,
    required Future<Result<void>> Function(String uid) writeProfile,
  }) async {
    final FirebaseAuth auth;
    try {
      auth = await _secondaryAuth();
    } on Object catch (error) {
      return Result.failure(FirebaseErrorMapper.map(error));
    }

    final address = email.trim();
    final UserCredential credential;
    try {
      // Not retried: if a first attempt timed out after the account was
      // actually made, a retry would fail as "email already in use" and
      // hide the real outcome.
      credential = await auth
          .createUserWithEmailAndPassword(
            email: address,
            password: _randomPassword(),
          )
          .timeout(_config.requestTimeout);
    } on Object catch (error) {
      return Result.failure(FirebaseErrorMapper.map(error));
    }

    final user = credential.user!;
    try {
      final profile = await writeProfile(user.uid);
      if (profile case Error(:final failure)) {
        // Roll back the login so no account exists without a profile.
        await _guard.call(user.delete);
        return Result.failure(failure);
      }

      final setupEmail = await _guard.call(
        () => auth.sendPasswordResetEmail(email: address),
      );
      return Result.success(
        ProvisionedAccount(uid: user.uid, setupEmailSent: setupEmail.isSuccess),
      );
    } finally {
      await _guard.call(auth.signOut);
    }
  }

  /// The secondary app, created on first use and reused afterwards.
  Future<FirebaseAuth> _secondaryAuth() async {
    final existing = Firebase.apps.where((app) => app.name == _appName);
    if (existing.isNotEmpty) {
      return FirebaseAuth.instanceFor(app: existing.first);
    }

    final app = await Firebase.initializeApp(
      name: _appName,
      options: Firebase.app().options,
    );
    final auth = FirebaseAuth.instanceFor(app: app);
    // Nothing about the new account should outlive this call — least of
    // all a session persisted in the administrator's browser storage.
    if (kIsWeb) await auth.setPersistence(Persistence.NONE);
    if (_config.useEmulator) {
      await auth.useAuthEmulator(
        _config.emulatorHost,
        _config.authEmulatorPort,
      );
    }
    return auth;
  }

  /// 32 characters from a cryptographic source. Never shown or stored: the
  /// person sets their own through the emailed link.
  static String _randomPassword() {
    const alphabet =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#%^*-_';
    final random = Random.secure();
    return String.fromCharCodes(
      Iterable.generate(
        32,
        (_) => alphabet.codeUnitAt(random.nextInt(alphabet.length)),
      ),
    );
  }
}
