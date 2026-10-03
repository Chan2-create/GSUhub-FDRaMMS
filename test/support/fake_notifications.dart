import 'dart:async';

import 'package:gsuhub/core/enums/notification_type.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/services/notification_service.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/notifications/data/models/app_notification.dart';
import 'package:gsuhub/features/notifications/data/repositories/notification_repository.dart';

/// Notifications for the faculty and staff app's tests (Objective 3.B):
/// a phone-side service whose permission, token and taps a test controls,
/// and a notification store that updates its listeners live.

/// A notice about [reportId] for `faculty-1`.
AppNotification fakeNotice(
  String id, {
  String reportId = 'r-newest',
  String recipientId = 'faculty-1',
  NotificationType type = NotificationType.statusUpdate,
  String title = 'Report approved',
  String body = 'Your report "Broken ceiling fan" was approved.',
  bool isRead = false,
  DateTime? createdAt,
}) => AppNotification(
  id: id,
  recipientId: recipientId,
  type: type,
  title: title,
  body: body,
  isRead: isRead,
  readAt: isRead ? DateTime.now() : null,
  relatedEntityType: 'damage_reports',
  relatedEntityId: reportId,
  createdAt: createdAt ?? DateTime.now().subtract(const Duration(minutes: 2)),
);

/// The phone side: permission, token, taps and what was shown.
class FakeNotificationService implements NotificationService {
  PushPermission permission = PushPermission.granted;

  /// What the system prompt answers when asked.
  PushPermission answerWhenAsked = PushPermission.granted;

  String? token = 'device-token-1';
  Map<String, dynamic>? launch;

  int requests = 0;
  int settingsOpened = 0;
  int tokensDeleted = 0;
  final shown =
      <({int id, String title, String body, Map<String, String> payload})>[];

  final _messages = StreamController<Map<String, dynamic>>.broadcast();
  final _taps = StreamController<Map<String, dynamic>>.broadcast();
  final _tokens = StreamController<String>.broadcast();

  /// A push arriving while the app is open.
  void receive(Map<String, dynamic> payload) => _messages.add(payload);

  /// The person tapping a notification.
  void tap(Map<String, dynamic> payload) => _taps.add(payload);

  /// The push service rotating the token.
  void rotate(String newToken) {
    token = newToken;
    _tokens.add(newToken);
  }

  @override
  Future<Result<void>> initialize() async => const Result.success(null);

  @override
  Future<Result<PushPermission>> permissionStatus() async =>
      Result.success(permission);

  @override
  Future<Result<PushPermission>> requestPermission() async {
    requests++;
    permission = answerWhenAsked;
    return Result.success(permission);
  }

  @override
  Future<Result<void>> openSettings() async {
    settingsOpened++;
    return const Result.success(null);
  }

  @override
  Future<Result<String?>> getDeviceToken() async => Result.success(token);

  @override
  Stream<String> get onTokenRefresh => _tokens.stream;

  @override
  Future<Result<void>> deleteDeviceToken() async {
    tokensDeleted++;
    token = null;
    return const Result.success(null);
  }

  @override
  Stream<Map<String, dynamic>> get onMessage => _messages.stream;

  @override
  Stream<Map<String, dynamic>> get onTapped => _taps.stream;

  @override
  Future<Result<Map<String, dynamic>?>> launchPayload() async {
    final payload = launch;
    launch = null;
    return Result.success(payload);
  }

  @override
  Future<Result<void>> show({
    required int id,
    required String title,
    required String body,
    required Map<String, String> payload,
  }) async {
    shown.add((id: id, title: title, body: body, payload: payload));
    return const Result.success(null);
  }

  @override
  Future<Result<void>> subscribeToTopic(String topic) async =>
      const Result.success(null);

  @override
  Future<Result<void>> unsubscribeFromTopic(String topic) async =>
      const Result.success(null);

  Future<void> dispose() async {
    await _messages.close();
    await _taps.close();
    await _tokens.close();
  }
}

/// The notification store: answers live, as Firestore's listeners would.
class FakeNotificationRepository implements NotificationRepository {
  FakeNotificationRepository([List<AppNotification> notices = const []])
    : _notices = {for (final notice in notices) notice.id: notice};

  final Map<String, AppNotification> _notices;
  final _changes = StreamController<void>.broadcast();

  /// When set, listening fails with this.
  Failure? failure;

  final markedRead = <String>[];
  int markAllCalls = 0;

  /// A notice arriving, as a move written elsewhere would land.
  void deliver(AppNotification notice) {
    _notices[notice.id] = notice;
    _changes.add(null);
  }

  AppNotification? byId(String id) => _notices[id];

  Stream<T> _live<T>(T Function() read) => Stream.multi((listener) {
    listener.add(read());
    final changes = _changes.stream.listen((_) => listener.add(read()));
    listener.onCancel = changes.cancel;
  });

  List<AppNotification> _forUser(String userId) =>
      _notices.values.where((notice) => notice.recipientId == userId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Stream<Result<List<AppNotification>>> watchForUser(
    String userId, {
    bool unreadOnly = false,
  }) {
    if (failure case final failure?) {
      return Stream.value(Result.failure(failure));
    }
    return _live(
      () => Result.success(
        _forUser(userId).where((n) => !unreadOnly || !n.isRead).toList(),
      ),
    );
  }

  @override
  Stream<Result<int>> watchUnreadCount(String userId) => _live(
    () => Result.success(_forUser(userId).where((n) => !n.isRead).length),
  );

  @override
  Future<Result<String>> create(AppNotification notification) async {
    deliver(notification);
    return Result.success(notification.id);
  }

  @override
  Future<Result<void>> markAsRead(String notificationId) async {
    markedRead.add(notificationId);
    final notice = _notices[notificationId];
    if (notice != null && !notice.isRead) {
      deliver(notice.copyWith(isRead: true, readAt: DateTime.now()));
    }
    return const Result.success(null);
  }

  @override
  Future<Result<void>> markAllAsRead(String userId) async {
    markAllCalls++;
    for (final notice in _forUser(userId).where((n) => !n.isRead)) {
      _notices[notice.id] = notice.copyWith(
        isRead: true,
        readAt: DateTime.now(),
      );
    }
    _changes.add(null);
    return const Result.success(null);
  }

  Future<void> dispose() => _changes.close();
}
