import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../config/firebase_initializer.dart';
import '../services/auth_service.dart';
import '../services/connectivity_service.dart';
import '../services/firebase/fcm_notification_service.dart';
import '../services/firebase/firebase_auth_service.dart';
import '../services/firebase/firebase_call_guard.dart';
import '../services/firebase/firebase_connectivity_service.dart';
import '../services/firebase/firebase_storage_service.dart';
import '../services/firebase/firestore_service_impl.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';

/// The app-wide [AppConfig]. Overridden in `main.dart`.
final appConfigProvider = Provider<AppConfig>(
  (ref) => throw UnimplementedError('appConfigProvider must be overridden'),
);

/// The Firebase handles produced by a successful startup. Overridden in
/// `main.dart` once [FirebaseInitializer] has run.
///
/// Throwing by default is deliberate: a provider that silently returned a
/// stub would let a misconfigured build reach production looking healthy.
final firebaseStartupProvider = Provider<FirebaseStartupSuccess>(
  (ref) =>
      throw UnimplementedError('firebaseStartupProvider must be overridden'),
);

final firebaseCallGuardProvider = Provider<FirebaseCallGuard>(
  (ref) => FirebaseCallGuard(ref.watch(appConfigProvider)),
);

/// Authentication. Features depend on the [AuthService] abstraction, never
/// on this concrete type — Shared Backend Contract, rule 1.
final authServiceProvider = Provider<AuthService>(
  (ref) => FirebaseAuthService(
    auth: ref.watch(firebaseStartupProvider).auth,
    firestore: ref.watch(firebaseStartupProvider).firestore,
    guard: ref.watch(firebaseCallGuardProvider),
  ),
);

/// Concrete auth service, for the few callers that need the extras beyond
/// the interface (token refresh).
final firebaseAuthServiceProvider = Provider<FirebaseAuthService>(
  (ref) => ref.watch(authServiceProvider) as FirebaseAuthService,
);

/// The signed-in user, or `null`. This is what 2.A's route guard will
/// watch to enforce role-based access.
final authStateProvider = StreamProvider<AuthUser?>(
  (ref) => ref.watch(authServiceProvider).authStateChanges(),
);

final firestoreServiceProvider = Provider<FirestoreService>(
  (ref) => FirestoreServiceImpl(
    firestore: ref.watch(firebaseStartupProvider).firestore,
    guard: ref.watch(firebaseCallGuardProvider),
  ),
);

/// Concrete Firestore service. Repositories take this rather than the
/// interface because they need the query, transaction and batch
/// primitives the generic interface does not expose.
final firestoreServiceImplProvider = Provider<FirestoreServiceImpl>(
  (ref) => ref.watch(firestoreServiceProvider) as FirestoreServiceImpl,
);

final storageServiceProvider = Provider<StorageService>(
  (ref) => FirebaseStorageService(
    storage: ref.watch(firebaseStartupProvider).storage,
    guard: ref.watch(firebaseCallGuardProvider),
  ),
);

final firebaseStorageServiceProvider = Provider<FirebaseStorageService>(
  (ref) => ref.watch(storageServiceProvider) as FirebaseStorageService,
);

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => FcmNotificationService(
    messaging: ref.watch(firebaseStartupProvider).messaging,
    guard: ref.watch(firebaseCallGuardProvider),
    config: ref.watch(appConfigProvider),
  ),
);

final fcmNotificationServiceProvider = Provider<FcmNotificationService>(
  (ref) => ref.watch(notificationServiceProvider) as FcmNotificationService,
);

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  final service = FirebaseConnectivityService(
    firestore: ref.watch(firebaseStartupProvider).firestore,
    guard: ref.watch(firebaseCallGuardProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Live backend reachability, for showing an offline state (§1.5 requires
/// connectivity, so the UI must be able to say when it is absent).
final reachabilityProvider = StreamProvider<BackendReachability>(
  (ref) => ref.watch(connectivityServiceProvider).reachability,
);
