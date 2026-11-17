import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase/supabase.dart' show SupabaseClient;

import '../config/app_config.dart';
import '../data/live_sync.dart';
import '../errors/failures.dart';
import '../errors/supabase_error_mapper.dart';
import '../services/account_provisioning_service.dart';
import '../services/auth_service.dart';
import '../services/connectivity_service.dart';
import '../services/device/geolocator_location_service.dart';
import '../services/device/image_picker_photo_service.dart';
import '../services/file_download_service.dart';
import '../services/firebase/fcm_notification_service.dart';
import '../services/firebase/firebase_account_provisioning_service.dart';
import '../services/firebase/firebase_auth_service.dart';
import '../services/firebase/firebase_call_guard.dart';
import '../services/firebase/firebase_initializer.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/photo_picker_service.dart';
import '../services/storage_service.dart';
import '../services/supabase/supabase_call_guard.dart';
import '../services/supabase/supabase_change_channel.dart';
import '../services/supabase/supabase_connectivity_service.dart';
import '../services/supabase/supabase_session.dart';
import '../services/supabase/supabase_storage_service.dart';
import '../session/inactivity_monitor.dart';

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

/// Supabase access tokens for the signed-in Firebase user, traded at the
/// `firebase-token-exchange` function (Objective 1).
final supabaseSessionProvider = Provider<SupabaseSession>((ref) {
  final config = ref.watch(appConfigProvider);
  final session = SupabaseSession.forFirebase(
    auth: ref.watch(firebaseStartupProvider).auth,
    supabaseUrl: config.supabaseUrl,
    apiKey: config.supabaseAnonKey,
  );
  ref.onDispose(session.dispose);
  return session;
});

/// The Supabase client: data, photos and live updates. Who is calling
/// comes from [supabaseSessionProvider]; Supabase's own sign-in is unused.
///
/// Repositories take this through their providers, never directly from a
/// screen — Shared Backend Contract, rule 1.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  final config = ref.watch(appConfigProvider);
  final session = ref.watch(supabaseSessionProvider);
  final client = SupabaseClient(
    config.supabaseUrl,
    config.supabaseAnonKey,
    accessToken: session.accessToken,
  );
  // Realtime keeps the token it joined with until handed a new one, and
  // the server closes a channel whose token has expired. Signed out, the
  // channel goes; `liveSyncProvider` opens it again at the next sign-in.
  session.onTokenChanged = (token) => unawaited(
    token == null ? client.removeAllChannels() : client.realtime.setAuth(token),
  );
  ref.onDispose(() {
    session.onTokenChanged = null;
    unawaited(client.dispose());
  });
  return client;
});

final supabaseCallGuardProvider = Provider<SupabaseCallGuard>(
  (ref) => SupabaseCallGuard(
    ref.watch(appConfigProvider),
    // The database ended the session as idle (PT401): the app signs out,
    // whichever call the refusal came back on.
    onFailure: (failure) {
      if (failure is SessionExpiredFailure) {
        ref.read(inactivityMonitorProvider).expire();
      }
    },
  ),
);

/// Authentication. Features depend on the [AuthService] abstraction, never
/// on this concrete type — Shared Backend Contract, rule 1.
///
/// Sign-in is Firebase's; who the person is in GSUhub — role and account
/// status — is their `users` row (Objective 1).
final authServiceProvider = Provider<AuthService>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final guard = ref.watch(supabaseCallGuardProvider);
  return FirebaseAuthService(
    auth: ref.watch(firebaseStartupProvider).auth,
    lookupProfile: (uid) => guard.call(() async {
      final row = await client
          .from('users')
          .select('email, role, account_status')
          .eq('id', uid)
          .maybeSingle();
      return row == null
          ? null
          : {
              'email': row['email'],
              'role': row['role'],
              'accountStatus': row['account_status'],
            };
    }),
    guard: ref.watch(firebaseCallGuardProvider),
  );
});

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

/// Who the data on screen was read for: the signed-in account's id, or
/// null. The repositories watch it, so everything read for one sign-in is
/// dropped at the next (2026-11-16).
final sessionScopeProvider = Provider<String?>(
  (ref) => ref.watch(authStateProvider.select((state) => state.value?.uid)),
);

/// Opens the app's one Realtime channel, for [liveSyncProvider]. Its own
/// provider so a test can stand in a channel that needs no server.
final changeChannelOpenerProvider = Provider<ChangeChannelOpener>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return ({required onChange, required onStatus}) => SupabaseChangeChannel.open(
    client,
    onChange: onChange,
    onStatus: onStatus,
  );
});

/// Whether anyone is signed in, asked at the moment it matters: Firebase's
/// own answer, which changes the instant a sign-out begins, ahead of
/// [sessionScopeProvider]. Signed out, nothing is read and no channel is
/// kept.
final signedInCheckProvider = Provider<bool Function()>((ref) {
  final auth = ref.watch(firebaseStartupProvider).auth;
  return () => auth.currentUser != null;
});

/// Keeps what the screens show in step with the database: one Realtime
/// channel, and every live view read again when it may have changed
/// (2026-11-16, `LiveSync`). Also read again when someone signs in, when
/// the connection returns, and when the app or its browser tab comes back
/// to the front.
final liveSyncProvider = Provider<LiveSync>((ref) {
  final sync = LiveSync(
    openChannel: ref.watch(changeChannelOpenerProvider),
    isSignedIn: ref.watch(signedInCheckProvider),
    isTransient: SupabaseErrorMapper.isRetryable,
  );

  // Coming back to a window is frequent; reading everything again on each
  // return within a few seconds is not worth its cost.
  DateTime? lastResume;
  final lifecycle = AppLifecycleListener(
    onResume: () {
      final now = DateTime.now();
      final last = lastResume;
      if (last != null && now.difference(last) < _resumeResyncGap) return;
      lastResume = now;
      unawaited(sync.resync());
    },
  );

  ref
    ..listen(sessionScopeProvider, (_, _) => sync.sessionChanged())
    ..listen(reachabilityProvider, (previous, next) {
      if (previous?.value == BackendReachability.offline &&
          next.value == BackendReachability.online) {
        unawaited(sync.resync());
      }
    })
    ..onDispose(() {
      lifecycle.dispose();
      sync.dispose();
    });
  return sync;
});

const Duration _resumeResyncGap = Duration(seconds: 15);

/// Creates sign-in accounts on an administrator's behalf (Objective 2.C).
/// Kept apart from [authServiceProvider]: that service is about the
/// signed-in user, this one about everyone else.
final accountProvisioningServiceProvider = Provider<AccountProvisioningService>(
  (ref) => FirebaseAccountProvisioningService(
    config: ref.watch(appConfigProvider),
    guard: ref.watch(firebaseCallGuardProvider),
  ),
);

/// Browser file downloads — the Analytics CSV export.
final fileDownloadServiceProvider = Provider<FileDownloadService>(
  (ref) => FileDownloadService(),
);

/// Photos, in the private `photos` bucket on Supabase Storage (Objective
/// 1), filed under the signed-in user's uid where the bucket's policies
/// want it.
final storageServiceProvider = Provider<StorageService>((ref) {
  final auth = ref.watch(firebaseStartupProvider).auth;
  return SupabaseStorageService(
    client: ref.watch(supabaseClientProvider),
    currentUid: () => auth.currentUser?.uid,
    guard: ref.watch(supabaseCallGuardProvider),
  );
});

/// Device GPS, for the geo-tag on a damage report (Objective 3.C).
final locationServiceProvider = Provider<LocationService>(
  (ref) => const GeolocatorLocationService(),
);

/// Camera and photo library, for photo evidence (Objective 3.C).
final photoPickerServiceProvider = Provider<PhotoPickerService>(
  (ref) => ImagePickerPhotoService(),
);

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => FcmNotificationService(
    messaging: ref.watch(firebaseStartupProvider).messaging,
    guard: ref.watch(firebaseCallGuardProvider),
    config: ref.watch(appConfigProvider),
  ),
);

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  final service = SupabaseConnectivityService(
    client: ref.watch(supabaseClientProvider),
    guard: ref.watch(supabaseCallGuardProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Live backend reachability, for showing an offline state (§1.5 requires
/// connectivity, so the UI must be able to say when it is absent).
final reachabilityProvider = StreamProvider<BackendReachability>(
  (ref) => ref.watch(connectivityServiceProvider).reachability,
);
