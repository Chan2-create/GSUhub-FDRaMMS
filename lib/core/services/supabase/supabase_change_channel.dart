import 'dart:async';

import 'package:supabase/supabase.dart';

import '../../data/live_sync.dart';
import '../../errors/supabase_error_mapper.dart';

/// The app's one Realtime channel (2026-11-16): every row change in the
/// `public` schema that the signed-in person may see, as the table it
/// happened in. Row level security decides what reaches whom, as it does
/// for reads; the tables are those in the `supabase_realtime` publication
/// (supabase/migrations/*_realtime.sql).
///
/// What a change carries is not used. [LiveSync] reads the rows again
/// through the API, so the screen never depends on what an event did or
/// did not include.
class SupabaseChangeChannel implements ChangeChannel {
  SupabaseChangeChannel._(this._client, this._channel);

  /// Opens the channel on [client].
  factory SupabaseChangeChannel.open(
    SupabaseClient client, {
    required void Function(String table) onChange,
    required void Function(ChangeChannelStatus status) onStatus,
  }) {
    // A name of its own each time: a channel that is being replaced may
    // still be leaving, and two on one topic would close each other.
    final channel = client.channel('db-changes-${_opened++}');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          callback: (payload) => onChange(payload.table),
        )
        // The join is answered before the server's change stream for it
        // is running. This is the server saying that it now is: everything
        // is read again, for what changed in between. (Its saying that it
        // failed arrives through subscribe's own callback, below.)
        .onSystemEvents((payload) {
          if (payload is Map && payload['status'] == 'ok') {
            onStatus(ChangeChannelStatus.subscribed);
          }
        })
        .subscribe(
          (status, [error]) => onStatus(switch (status) {
            RealtimeSubscribeStatus.subscribed =>
              ChangeChannelStatus.subscribed,
            RealtimeSubscribeStatus.channelError ||
            RealtimeSubscribeStatus.timedOut => ChangeChannelStatus.interrupted,
            RealtimeSubscribeStatus.closed => ChangeChannelStatus.closed,
          }),
        );
    return SupabaseChangeChannel._(client, channel);
  }

  static int _opened = 0;

  final SupabaseClient _client;
  final RealtimeChannel _channel;
  bool _closed = false;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _client.removeChannel(_channel);
  }
}

/// [LiveSync] over [client]'s Realtime connection.
///
/// [isSignedIn] says whether there is anyone to read for: signed out,
/// nothing is read and no channel is kept.
LiveSync supabaseLiveSync(
  SupabaseClient client, {
  bool Function()? isSignedIn,
}) => LiveSync(
  openChannel: ({required onChange, required onStatus}) =>
      SupabaseChangeChannel.open(
        client,
        onChange: onChange,
        onStatus: onStatus,
      ),
  isSignedIn: isSignedIn,
  isTransient: SupabaseErrorMapper.isRetryable,
);
