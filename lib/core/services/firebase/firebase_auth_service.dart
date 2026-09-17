import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

import '../../constants/firestore_paths.dart';
import '../../enums/account_status.dart';
import '../../enums/user_role.dart';
import '../../errors/failures.dart';
import '../../utils/result.dart';
import '../auth_service.dart';
import 'firebase_call_guard.dart';

/// Firebase Authentication implementation of [AuthService].
///
/// ## Why this reads Firestore as well as Auth
///
/// Firebase Auth knows a user's uid and email but nothing about their
/// role, and GSUhub's entire access model turns on role (manuscript §1.5).
/// The role lives on the `users/{uid}` document, so resolving an
/// [AuthUser] means reading both. That is why [currentUser] is backed by a
/// cache refreshed by [authStateChanges] rather than being a simple
/// property read — a synchronous getter cannot await a Firestore lookup,
/// and route guards need it synchronously.
///
/// ## Deactivated accounts
///
/// §1.5 requires accounts to be deactivatable. Firebase Auth has its own
/// "disabled" flag, but the Administrator manages users through Firestore,
/// so `accountStatus` is authoritative here: a user whose document says
/// `inactive` is treated as signed out even if their Auth session is
/// technically valid, and [signInWithEmailAndPassword] refuses them.
class FirebaseAuthService implements AuthService {
  FirebaseAuthService({
    required this._auth,
    required this._firestore,
    required this._guard,
  });

  final fb.FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseCallGuard _guard;

  AuthUser? _cachedUser;

  @override
  AuthUser? get currentUser => _cachedUser;

  @override
  Stream<AuthUser?> authStateChanges() async* {
    await for (final credential in _auth.authStateChanges()) {
      if (credential == null) {
        _cachedUser = null;
        yield null;
        continue;
      }

      final profile = await _loadProfile(credential.uid);
      // A signed-in credential with no readable profile, or a deactivated
      // one, is treated as signed out. Emitting a half-resolved user here
      // would let the route guard admit someone whose role we could not
      // establish.
      _cachedUser = profile;
      yield profile;
    }
  }

  @override
  Future<Result<AuthUser>> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final signIn = await _guard.call(
      () => _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      ),
    );

    return switch (signIn) {
      Error<fb.UserCredential>(:final failure) => Result.failure(failure),
      Success<fb.UserCredential>(:final value) => await _resolveSignedIn(
        value.user?.uid,
      ),
    };
  }

  @override
  Future<Result<void>> signOut() {
    _cachedUser = null;
    return _guard.call(_auth.signOut);
  }

  @override
  Future<Result<void>> sendPasswordResetEmail({required String email}) =>
      _guard.call(() => _auth.sendPasswordResetEmail(email: email.trim()));

  /// Forces a refresh of the signed-in user's ID token.
  ///
  /// Useful after an Administrator changes someone's role: the client
  /// otherwise keeps using a cached token until it expires, and security
  /// rules would evaluate against the stale claim.
  Future<Result<void>> refreshToken() async {
    final user = _auth.currentUser;
    if (user == null) {
      return const Result.failure(
        PermissionFailure('No signed-in user to refresh.'),
      );
    }

    final refreshed = await _guard.call(() => user.getIdToken(true));
    if (refreshed.isFailure) {
      return refreshed.map((_) {});
    }

    _cachedUser = await _loadProfile(user.uid);
    return const Result.success(null);
  }

  Future<Result<AuthUser>> _resolveSignedIn(String? uid) async {
    if (uid == null) {
      return const Result.failure(
        UnknownFailure('Sign-in succeeded but returned no user.'),
      );
    }

    final profile = await _loadProfile(uid);
    if (profile == null) {
      // Signing them straight back out prevents a half-authenticated
      // state where Auth thinks they are in but the app cannot say who
      // they are.
      await _auth.signOut();
      _cachedUser = null;
      return const Result.failure(
        PermissionFailure(
          'This account is not authorized to use GSUhub, or has been '
          'deactivated. Contact the GSU administrator.',
        ),
      );
    }

    _cachedUser = profile;
    return Result.success(profile);
  }

  /// Reads `users/{uid}` and builds an [AuthUser], or returns `null` when
  /// the document is missing, unreadable, malformed, or deactivated.
  Future<AuthUser?> _loadProfile(String uid) async {
    final snapshot = await _guard.call(
      () => _firestore.collection(FirestorePaths.users).doc(uid).get(),
    );

    return snapshot.fold((doc) {
      final data = doc.data();
      if (!doc.exists || data == null) return null;

      final rawRole = data['role'];
      final rawStatus = data['accountStatus'];
      if (rawRole is! String || rawStatus is! String) return null;

      try {
        if (AccountStatus.fromId(rawStatus) != AccountStatus.active) {
          return null;
        }
        return AuthUser(
          uid: uid,
          email: (data['email'] as String?) ?? '',
          role: UserRole.fromId(rawRole),
        );
      } on ArgumentError {
        // An unrecognized role or status means the document is corrupt
        // or was written by something that does not share our schema.
        // Refusing access is the only safe reading.
        return null;
      }
    }, (_) => null);
  }
}
