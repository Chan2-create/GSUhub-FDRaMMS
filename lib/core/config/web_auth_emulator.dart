import 'web_auth_emulator_stub.dart'
    if (dart.library.js_interop) 'web_auth_emulator_web.dart'
    as platform;

/// Keeps a web page reload on the Auth emulator (Objective 1, item 3).
///
/// The bug: on the web, Firebase restores a saved session while it starts,
/// before `useAuthEmulator` can run, and restoring checks the account with
/// the live project. Once that request has gone out the emulator can no
/// longer be attached; FlutterFire swallows the error, and the tab signs in
/// against live Firebase while the log claims emulators.
///
/// FlutterFire re-attaches the emulator early by itself, from a note in
/// session storage, but only on a debug build served from `localhost`. So
/// before Firebase starts: on such a build, the note is written (a fresh
/// tab has none); anywhere else, the saved session is forgotten instead,
/// so that starting sends nothing anywhere and the emulator attaches as
/// usual. The cost there is signing in again after a reload.
///
/// Startup then checks [authEmulatorAttached] and refuses to run rather
/// than run against live Auth.
///
/// [origin] is the emulator's, e.g. `http://localhost:9099`. Does nothing
/// outside the browser, where startup order has no such gap.
Future<void> prepareAuthEmulatorBeforeStart(String origin) =>
    platform.prepareAuthEmulatorBeforeStart(origin);

/// Whether the Auth instance of the Firebase app [appName] is attached to
/// the emulator, or `null` where that cannot be told (outside the browser).
bool? authEmulatorAttached({String appName = '[DEFAULT]'}) =>
    platform.authEmulatorAttached(appName);
