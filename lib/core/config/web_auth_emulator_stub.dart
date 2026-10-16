/// Outside the browser: Firebase's native SDKs attach the emulator before
/// any request, so there is nothing to prepare or to check.
Future<void> prepareAuthEmulatorBeforeStart(String origin) async {}

bool? authEmulatorAttached(String appName) => null;
