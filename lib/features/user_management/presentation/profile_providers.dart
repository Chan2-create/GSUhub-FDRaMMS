import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/repository_providers.dart';
import '../../../core/di/service_providers.dart';
import '../../../core/errors/failures.dart';
import '../../../core/utils/result.dart';
import '../data/models/app_user.dart';

/// The signed-in person's own `users` profile, read once — the faculty and
/// staff home screen's greeting and the Profile tab (Objective 3.A).
/// `AuthUser` carries only uid, email and role; the name and department
/// live here.
final signedInProfileProvider = FutureProvider<Result<AppUser>>((ref) async {
  final user =
      ref.watch(authStateProvider).value ??
      ref.read(authServiceProvider).currentUser;
  if (user == null) {
    return const Result.failure(
      PermissionFailure('Your session has expired. Please sign in again.'),
    );
  }
  return ref.watch(userRepositoryProvider).getById(user.uid);
});
