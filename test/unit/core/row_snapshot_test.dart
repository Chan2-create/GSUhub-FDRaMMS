import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/data/row_snapshot.dart';
import 'package:gsuhub/core/enums/account_status.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/enums/work_order_status.dart';
import 'package:gsuhub/features/audit/data/models/audit_log_entry.dart';
import 'package:gsuhub/features/classification/data/models/classification_rules_config.dart';
import 'package:gsuhub/features/facilities/data/models/facility.dart';
import 'package:gsuhub/features/feedback/data/models/service_feedback.dart';
import 'package:gsuhub/features/notifications/data/models/app_notification.dart';
import 'package:gsuhub/features/reporting/data/models/damage_report.dart';
import 'package:gsuhub/features/reporting/data/models/status_change.dart';
import 'package:gsuhub/features/user_management/data/models/app_user.dart';
import 'package:gsuhub/features/work_orders/data/models/work_order.dart';

/// Rows as the Supabase API returns them: snake_case columns, timestamps
/// as ISO strings with an offset, coordinates as two numbers.
void main() {
  const stamp = '2026-10-16T08:30:00.123456+00:00';
  final when = DateTime.utc(2026, 10, 16, 8, 30, 0, 123, 456);

  test('columns become fields, and timestamps Timestamps', () {
    final fields = RowSnapshot.documentFields({
      'id': 'x',
      'full_name': 'Ana',
      'active_task_count': 2,
      'created_at': stamp,
      'timestamp': stamp,
      'due_date': null,
    });
    expect(fields['fullName'], 'Ana');
    expect(fields['activeTaskCount'], 2);
    expect(fields['createdAt'], isA<Timestamp>());
    expect((fields['createdAt'] as Timestamp).toDate().toUtc(), when);
    expect(fields['timestamp'], isA<Timestamp>());
    expect(fields['dueDate'], isNull);
  });

  test('a time Realtime sends without a zone is read as UTC', () {
    final fields = RowSnapshot.documentFields({
      'id': 'x',
      'updated_at': '2026-10-16T08:30:00.123456',
    });
    expect(
      (fields['updatedAt'] as Timestamp).toDate().toUtc(),
      DateTime.utc(2026, 10, 16, 8, 30, 0, 123, 456),
    );
  });

  test('a damage report row, coordinates and all, reads as the report', () {
    final report = DamageReport.fromFirestore(
      RowSnapshot.fromRow({
        'id': 'r-1',
        'reporter_id': 'u-1',
        'reporter_name': 'Maria Santos',
        'title': 'Flickering lights',
        'description': 'Room 101.',
        'category': 'electrical',
        'classified_automatically': true,
        'requestor_category': null,
        'facility_id': 'f-1',
        'facility_name': 'Engineering Building',
        'location_description': null,
        'asset_id': null,
        'latitude': 7.1,
        'longitude': 126,
        'photo_urls': ['https://photos.test/1.jpg'],
        'requestor_priority': 'high',
        'severity_rating': 3,
        'safety_risk_rating': null,
        'frequency_rating': null,
        'location_importance_rating': null,
        'priority_score': 3,
        'recommended_priority': null,
        'official_priority': null,
        'status': 'submitted',
        'duplicate_of': null,
        'dismissed_duplicate_ids': <String>[],
        'work_order_id': null,
        'reviewed_by': null,
        'reviewed_at': null,
        'rejection_reason': null,
        'submitted_at': stamp,
        'updated_at': stamp,
      }),
    );
    expect(report.id, 'r-1');
    expect(report.status, ReportStatus.submitted);
    expect(report.category, DamageCategory.electrical);
    expect(report.coordinates, const GeoPoint(7.1, 126));
    expect(report.photoUrls, ['https://photos.test/1.jpg']);
    expect(report.priorityScore, 3);
    expect(report.submittedAt, when);
  });

  test('a report with no geo-tag has no coordinates', () {
    final fields = RowSnapshot.documentFields({
      'id': 'r',
      'latitude': null,
      'longitude': null,
    });
    expect(fields.containsKey('coordinates'), isTrue);
    expect(fields['coordinates'], isNull);
    expect(fields.containsKey('latitude'), isFalse);
  });

  test('a users row reads as the account', () {
    final user = AppUser.fromFirestore(
      RowSnapshot.fromRow({
        'id': 'u-1',
        'full_name': 'Marcus Wright',
        'email': 'tech@test.ph',
        'role': 'maintenancePersonnel',
        'account_status': 'active',
        'department': null,
        'contact_number': null,
        'specialization': 'electrical',
        'availability': 'available',
        'active_task_count': 1,
        'fcm_token': null,
        'created_at': stamp,
        'updated_at': stamp,
      }),
    );
    expect(user.role, UserRole.maintenancePersonnel);
    expect(user.accountStatus, AccountStatus.active);
    expect(user.specialization, DamageCategory.electrical);
    expect(user.activeTaskCount, 1);
  });

  test('work orders, rooms, timelines, ratings, notices and audit entries read too', () {
    final workOrder = WorkOrder.fromFirestore(
      RowSnapshot.fromRow({
        'id': 'w-1',
        'report_ids': ['r-1'],
        'title': 'Flickering lights',
        'description': 'Room 101.',
        'category': 'electrical',
        'priority': 'high',
        'status': 'inProgress',
        'assigned_personnel_ids': ['u-1'],
        'facility_id': 'f-1',
        'facility_name': 'Engineering Building',
        'admin_notes': null,
        'scheduled_for': stamp,
        'started_at': stamp,
        'completed_at': null,
        'created_by': 'u-admin',
        'created_at': stamp,
        'updated_at': stamp,
      }),
    );
    expect(workOrder.status, WorkOrderStatus.inProgress);
    expect(workOrder.scheduledFor, when);

    final facility = Facility.fromFirestore(
      RowSnapshot.fromRow({
        'id': 'f-1',
        'name': 'Engineering Building',
        'building_name': 'Engineering Building',
        'room_identifier': 'Room 101',
        'location_description': null,
        'latitude': 7.1,
        'longitude': 126.5,
        'qr_code': 'FAC-F-1',
        'is_active': true,
        'created_at': stamp,
        'updated_at': stamp,
      }),
    );
    expect(facility.roomIdentifier, 'Room 101');
    expect(facility.qrCode, 'FAC-F-1');

    final change = StatusChange.fromFirestore(
      RowSnapshot.fromRow({
        'id': 'h-1',
        'report_id': 'r-1',
        'status': 'assigned',
        'changed_at': stamp,
        'changed_by': 'u-admin',
        'note': null,
        'personnel_name': 'Marcus Wright',
        'personnel_specialization': 'electrical',
      }),
    );
    expect(change.status, ReportStatus.assigned);
    expect(change.personnelName, 'Marcus Wright');

    final feedback = ServiceFeedback.fromFirestore(
      RowSnapshot.fromRow({
        'id': 'r-1',
        'work_order_id': 'w-1',
        'report_id': 'r-1',
        'submitted_by': 'u-1',
        'response_time_rating': 4,
        'service_quality_rating': 5,
        'overall_satisfaction_rating': 3,
        'comments': null,
        'submitted_at': stamp,
      }),
    );
    expect(feedback.serviceQualityRating, 5);

    final notification = AppNotification.fromFirestore(
      RowSnapshot.fromRow({
        'id': 'n-1',
        'recipient_id': 'u-1',
        'type': 'statusUpdate',
        'title': 'Report approved',
        'body': 'Approved.',
        'related_entity_type': 'damage_reports',
        'related_entity_id': 'r-1',
        'is_read': true,
        'read_at': stamp,
        'created_at': stamp,
      }),
    );
    expect(notification.isRead, isTrue);
    expect(notification.readAt, when);

    final entry = AuditLogEntry.fromFirestore(
      RowSnapshot.fromRow({
        'id': 'au-1',
        'actor_id': 'u-admin',
        'actor_name': 'Ramon Dela Cruz',
        'action': 'assigned',
        'entity_type': 'damage_reports',
        'entity_id': 'r-1',
        'description': 'Assigned to Marcus Wright',
        'changes': {'from': 'approved', 'to': 'assigned'},
        'timestamp': stamp,
      }),
    );
    expect(entry.timestamp, when);
    expect(entry.changes, {'from': 'approved', 'to': 'assigned'});
  });

  test('a settings row reads as its document, stamped with who saved it', () {
    final config = ClassificationRulesConfig.fromFirestore(
      RowSnapshot.fromConfigRow({
        'id': 'classification_rules',
        'data': {
          'keywordsByCategory': {
            'plumbing': ['leak', 'pipe'],
          },
          'caseSensitive': false,
        },
        'updated_by': 'u-admin',
        'updated_at': stamp,
      }),
    );
    expect(config.keywordsByCategory[DamageCategory.plumbing], [
      'leak',
      'pipe',
    ]);
    expect(config.updatedBy, 'u-admin');
    expect(config.updatedAt, when);
  });
}
