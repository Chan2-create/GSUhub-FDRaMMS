import '../enums/user_role.dart';
import '../utils/result.dart';

/// The identity subset every shell needs for routing and access control —
/// not the full `users/{uid}` profile document (fields, contact info, etc.
/// belong to the data model built in Objective 1.B). Kept intentionally
/// minimal so this service contract doesn't depend on a schema that
/// doesn't exist yet.
class AuthUser {
  const AuthUser({required this.uid, required this.email, required this.role});

  final String uid;
  final String email;
  final UserRole role;
}

/// Abstract authentication contract. Every shell depends on this
/// interface, never on `firebase_auth` directly — see the "Shared Backend
/// Contract" in docs/architecture_decisions.md, rule 1.
///
/// No implementation exists yet. A concrete `FirebaseAuthService` is built
/// in Objective 1.C once Firebase Authentication is actually configured;
/// `route_guards.dart` and the shells only ever see this interface.
abstract interface class AuthService {
  /// Emits the signed-in [AuthUser], or `null` when signed out, on every
  /// auth-state change (including app startup).
  Stream<AuthUser?> authStateChanges();

  /// The currently signed-in user, if any, without waiting for a stream
  /// event. Useful for synchronous route-guard checks.
  AuthUser? get currentUser;

  Future<Result<AuthUser>> signInWithEmailAndPassword({
    required String email,
    required String password,
  });

  Future<Result<void>> signOut();

  Future<Result<void>> sendPasswordResetEmail({required String email});
}
