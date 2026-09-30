import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/repository_providers.dart';
import '../../../core/di/service_providers.dart';
import '../data/models/audit_actor.dart';

/// The signed-in administrator, as the audit trail should name them.
///
/// `AuthUser` carries only uid, email and role, so the display name comes
/// from the `users` document. If that read fails the email is used rather
/// than blocking the action: an audit entry identified by email is worth
/// more than a refused status change, and the uid is recorded either way.
///
/// Null only when nobody is signed in, which the route guard already
/// prevents on these screens.
final currentActorProvider = FutureProvider<AuditActor?>((ref) async {
  // The live auth state first, falling back to the service's cached user.
  // The stream has not necessarily emitted the first time an action asks
  // who is acting, and treating "not loaded yet" as "signed out" would
  // refuse a legitimate approval with "your session has expired".
  // `currentUser` is the same resolved AuthUser the stream last yielded.
  final user =
      ref.watch(authStateProvider).value ??
      ref.read(authServiceProvider).currentUser;
  if (user == null) return null;

  final result = await ref.watch(userRepositoryProvider).getById(user.uid);
  return result.fold(
    (appUser) => AuditActor(id: appUser.id, name: appUser.fullName),
    (_) => AuditActor(id: user.uid, name: user.email),
  );
});
