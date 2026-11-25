import 'package:gsuhub/core/data/live_sync.dart';

/// A change channel that needs no server (2026-11-25): what the fake app
/// scopes give the real [LiveSync], so a navigation button's refresh runs
/// as it does in the app. The fake repositories do not read through
/// [LiveSync], so a refresh there has nothing to read and succeeds.
class FakeChangeChannel implements ChangeChannel {
  bool closed = false;

  @override
  Future<void> close() async => closed = true;
}

/// For `changeChannelOpenerProvider`.
ChangeChannel openFakeChangeChannel({
  required void Function(String table) onChange,
  required void Function(ChangeChannelStatus status) onStatus,
}) => FakeChangeChannel();
