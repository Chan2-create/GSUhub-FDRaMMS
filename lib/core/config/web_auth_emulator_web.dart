import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// FlutterFire's session-storage note: `<app name>-firebaseEmulatorOrigin`.
const String _originSuffix = '-firebaseEmulatorOrigin';

/// Where the Firebase JS SDK keeps a signed-in user.
const String _savedUserPrefix = 'firebase:authUser:';
const String _authDatabase = 'firebaseLocalStorageDb';
const String _authStore = 'firebaseLocalStorage';

Future<void> prepareAuthEmulatorBeforeStart(String origin) async {
  final session = web.window.sessionStorage;

  // FlutterFire's own early re-attach runs only here.
  if (kDebugMode && web.window.location.hostname == 'localhost') {
    session.setItem('[DEFAULT]$_originSuffix', origin);
    return;
  }

  // Anywhere else nothing re-attaches in time. A stale note would also
  // make FlutterFire's useAuthEmulator skip the attach, believing it done.
  _removeKeys(session, (key) => key.endsWith(_originSuffix));
  _removeKeys(
    web.window.localStorage,
    (key) => key.startsWith(_savedUserPrefix),
  );
  _removeKeys(session, (key) => key.startsWith(_savedUserPrefix));
  await _forgetSavedUsers().timeout(
    const Duration(seconds: 2),
    onTimeout: () {},
  );
}

bool? authEmulatorAttached(String appName) {
  try {
    final core = globalContext.getProperty<JSObject?>('firebase_core'.toJS);
    final auth = globalContext.getProperty<JSObject?>('firebase_auth'.toJS);
    if (core == null || auth == null) return null;
    final app = core.callMethod<JSObject?>('getApp'.toJS, appName.toJS);
    final instance = auth.callMethod<JSObject?>('getAuth'.toJS, app);
    if (instance == null) return null;
    return instance.getProperty<JSAny?>('emulatorConfig'.toJS) != null;
  } on Object {
    // FlutterFire changed how it loads the SDK; say nothing rather than
    // stop a working app.
    return null;
  }
}

void _removeKeys(web.Storage storage, bool Function(String key) matches) {
  for (var i = storage.length - 1; i >= 0; i--) {
    final key = storage.key(i);
    if (key != null && matches(key)) storage.removeItem(key);
  }
}

/// Removes the signed-in users from Firebase's database, and nothing else.
/// Deleting the whole database would wait for every other open tab of the
/// app to let go of it, and Firebase would then wait on the delete.
Future<void> _forgetSavedUsers() async {
  final factory = web.window.indexedDB;
  final opening = factory.open(_authDatabase);
  // Not there yet: nobody has signed in on this site. Abort rather than
  // create an empty database for Firebase to trip over.
  opening.onupgradeneeded = ((
    web.Event _,
  ) => opening.transaction?.abort()).toJS;
  final web.IDBDatabase database;
  try {
    database = (await _settled(opening))! as web.IDBDatabase;
  } on Object {
    return;
  }
  try {
    if (!database.objectStoreNames.contains(_authStore)) return;
    final transaction = database.transaction(_authStore.toJS, 'readwrite');
    transaction
        .objectStore(_authStore)
        .delete(
          web.IDBKeyRange.bound(
            _savedUserPrefix.toJS,
            '$_savedUserPrefix￿'.toJS,
          ),
        );
    await _finished(transaction);
  } finally {
    database.close();
  }
}

/// The result of [request], or an error when it fails.
Future<JSAny?> _settled(web.IDBRequest request) {
  final done = Completer<JSAny?>();
  request
    ..onsuccess = ((web.Event _) => done.complete(request.result)).toJS
    ..onerror = ((web.Event _) => done.completeError(
      StateError('IndexedDB: ${request.error?.message}'),
    )).toJS;
  return done.future;
}

Future<void> _finished(web.IDBTransaction transaction) {
  final done = Completer<void>();
  void finish(web.Event _) {
    if (!done.isCompleted) done.complete();
  }

  transaction
    ..oncomplete = finish.toJS
    ..onerror = finish.toJS
    ..onabort = finish.toJS;
  return done.future;
}
