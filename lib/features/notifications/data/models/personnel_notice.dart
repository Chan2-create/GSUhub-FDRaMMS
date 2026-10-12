import '../../../../core/enums/notification_type.dart';

/// What a maintenance technician is told about their work (Objective
/// 5.A): the notification's type, title and body.
///
/// Manuscript §3.4 has personnel "receive push notifications for assigned
/// work orders and tasks". The wording is DERIVED; the sources give none.
///
/// Free of Flutter imports on purpose, like `ReportNotice`:
/// tool/seed_emulator.dart seeds notifications with this same wording.
class PersonnelNotice {
  const PersonnelNotice({
    required this.type,
    required this.title,
    required this.body,
  });

  /// A work order assigned to the technician.
  factory PersonnelNotice.workOrderAssigned({
    required String workOrderTitle,
    String? facilityName,
  }) => PersonnelNotice(
    type: NotificationType.workOrderAssigned,
    title: 'New work order',
    body:
        'You have been assigned "$workOrderTitle"'
        '${facilityName == null ? '' : ' at $facilityName'}.',
  );

  /// A task an administrator added to one of the technician's work orders.
  factory PersonnelNotice.taskAssigned({
    required String taskTitle,
    required String workOrderTitle,
  }) => PersonnelNotice(
    type: NotificationType.taskAssigned,
    title: 'New task',
    body: '"$taskTitle" was added to "$workOrderTitle".',
  );

  /// Submitted work sent back to be finished.
  factory PersonnelNotice.sentBack({required String workOrderTitle}) =>
      PersonnelNotice(
        type: NotificationType.statusUpdate,
        title: 'Work sent back',
        body:
            'GSU reviewed your accomplishment report for "$workOrderTitle" '
            'and sent the work back to be finished.',
      );

  /// Submitted work signed off.
  factory PersonnelNotice.signedOff({required String workOrderTitle}) =>
      PersonnelNotice(
        type: NotificationType.maintenanceCompleted,
        title: 'Work signed off',
        body: 'GSU signed off "$workOrderTitle" as completed.',
      );

  final NotificationType type;
  final String title;
  final String body;
}
