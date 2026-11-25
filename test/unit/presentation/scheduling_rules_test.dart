import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/enums/audit_action.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/enums/work_order_status.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/errors/supabase_error_mapper.dart';
import 'package:gsuhub/core/widgets/status_chip.dart';
import 'package:gsuhub/core/widgets/working_day_picker.dart';
import 'package:gsuhub/features/audit/data/models/audit_log_entry.dart';
import 'package:gsuhub/features/classification/presentation/assessment_draft.dart';
import 'package:gsuhub/features/damage_reports/data/models/damage_report.dart';
import 'package:gsuhub/features/damage_reports/presentation/report_detail_screen.dart';
import 'package:gsuhub/features/work_orders/data/models/work_order.dart';
import 'package:gsuhub/features/work_orders/presentation/work_order_providers.dart';
import 'package:supabase/supabase.dart';

/// The rules behind the second brief of 2026-11-26: working days for
/// scheduling, the work orders' order, a database behind the app said
/// plainly, the reporter's damage type first, and the roles' new names.
void main() {
  final now = DateTime.utc(2026, 11, 26, 8);

  group('working days', () {
    // Monday 30 Nov 2026 is made a holiday below; 28 and 29 are a
    // Saturday and a Sunday.
    final holidays = {DateTime(2026, 11, 30)};

    test('no Saturday, Sunday or holiday', () {
      expect(
        WorkingDays.isWorkingDay(DateTime(2026, 11, 27), holidays),
        isTrue,
      );
      expect(
        WorkingDays.isWorkingDay(DateTime(2026, 11, 28), holidays),
        isFalse,
        reason: 'Saturday',
      );
      expect(
        WorkingDays.isWorkingDay(DateTime(2026, 11, 29), holidays),
        isFalse,
        reason: 'Sunday',
      );
      expect(
        WorkingDays.isWorkingDay(DateTime(2026, 11, 30, 15), holidays),
        isFalse,
        reason: 'a holiday, whatever the time',
      );
    });

    test('the first working day from a weekend skips it and the holiday', () {
      expect(
        WorkingDays.firstFrom(
          DateTime(2026, 11, 28),
          holidays,
          last: DateTime(2026, 12, 31),
        ),
        DateTime(2026, 12),
      );
      expect(
        WorkingDays.firstFrom(
          DateTime(2026, 11, 28),
          holidays,
          last: DateTime(2026, 11, 30),
        ),
        isNull,
        reason: 'none before the last day offered',
      );
    });
  });

  group('the Work Order Management order', () {
    WorkOrder workOrder(String id, PriorityLevel priority, int hoursOld) =>
        WorkOrder(
          id: id,
          reportIds: const ['r'],
          title: id,
          description: '',
          category: DamageCategory.electrical,
          priority: priority,
          status: WorkOrderStatus.pending,
          createdBy: 'admin',
          createdAt: now.subtract(Duration(hours: hoursOld)),
          updatedAt: now,
        );

    test('Critical, High, Medium, Low; the oldest first within each, as '
        'the Damage Reports list', () {
      final sorted = [
        workOrder('low', PriorityLevel.low, 50),
        workOrder('high-new', PriorityLevel.high, 1),
        workOrder('critical', PriorityLevel.critical, 0),
        workOrder('high-old', PriorityLevel.high, 9),
        workOrder('medium', PriorityLevel.medium, 3),
      ]..sort(workOrdersByPriorityThenOldest);
      expect(
        [for (final w in sorted) w.id],
        ['critical', 'high-old', 'high-new', 'medium', 'low'],
      );
    });
  });

  group('a database behind the app', () {
    test('a missing table or function is a database update, not a "schema '
        'cache" error', () {
      for (final code in ['PGRST205', 'PGRST202', 'PGRST204', '42883']) {
        final failure = SupabaseErrorMapper.map(
          PostgrestException(
            message:
                "Could not find the table 'public.buildings' in the schema "
                'cache',
            code: code,
          ),
        );
        expect(failure, isA<DatabaseUpdateFailure>(), reason: code);
        expect(failure.message, isNot(contains('schema cache')));
        expect(failure.message, contains('database update'));
      }
    });
  });

  group("the reporter's damage type", () {
    DamageReport report({
      DamageCategory? requestorCategory,
      DamageCategory? keyword,
      PriorityLevel? official,
    }) => DamageReport(
      id: 'r-1',
      reporterId: 'faculty-1',
      reporterName: 'Maria Santos',
      title: 'Sparks',
      description: 'Sparks from the outlet.',
      requestorPriority: PriorityLevel.high,
      requestorCategory: requestorCategory,
      category: keyword,
      classifiedAutomatically: keyword != null,
      officialPriority: official,
      reviewedBy: official == null ? null : 'admin-1',
      status: ReportStatus.underReview,
      submittedAt: now,
      updatedAt: now,
    );

    test("the review starts with the reporter's choice, over the keywords", () {
      expect(
        AssessmentDraft.of(
          report(
            requestorCategory: DamageCategory.plumbing,
            keyword: DamageCategory.electrical,
          ),
        ).category,
        DamageCategory.plumbing,
      );
    });

    test('with none chosen, the rule-based classification', () {
      expect(
        AssessmentDraft.of(report(keyword: DamageCategory.electrical)).category,
        DamageCategory.electrical,
      );
      expect(
        AssessmentDraft.of(
          report(),
          suggestion: DamageCategory.carpentry,
        ).category,
        DamageCategory.carpentry,
      );
    });

    test('once confirmed, the confirmed type', () {
      expect(
        AssessmentDraft.of(
          report(
            requestorCategory: DamageCategory.plumbing,
            keyword: DamageCategory.electrical,
            official: PriorityLevel.high,
          ),
        ).category,
        DamageCategory.electrical,
      );
    });

    AuditLogEntry review(String? reporter, String to) => AuditLogEntry(
      id: 'a',
      actorId: 'admin-1',
      actorName: 'Ramon Dela Cruz',
      action: AuditAction.updated,
      entityType: 'damage_reports',
      entityId: 'r-1',
      description: 'Classified',
      timestamp: now,
      changes: {
        'requestor': {'category': reporter, 'priority': 'high'},
        'category': {'from': 'electrical', 'to': to},
        'officialPriority': {'from': null, 'to': 'high'},
      },
    );

    test("the history says whether the reporter's type was kept or "
        'changed', () {
      expect(
        reviewDetailsOf(review('electrical', 'electrical')).first,
        "Damage type: the reporter's Electrical, kept",
      );
      expect(
        reviewDetailsOf(review('electrical', 'plumbing')).first,
        "Damage type: changed from the reporter's Electrical to Plumbing",
      );
      expect(
        reviewDetailsOf(review(null, 'plumbing')).first,
        'Damage type: Plumbing (the reporter chose none)',
      );
    });
  });

  group('words', () {
    test('a report given a date on its page reads Scheduled', () {
      expect(
        StatusChip.requestorLabelOf(ReportStatus.approved, rescheduled: true),
        'Scheduled',
      );
    });

    test('the roles are Faculty and Utility', () {
      expect(UserRole.requestor.label, 'Faculty');
      expect(UserRole.maintenancePersonnel.label, 'Utility');
      expect(UserRole.requestor.tabLabel, 'Faculty');
      expect(UserRole.maintenancePersonnel.tabLabel, 'Utility Personnel');
      expect(UserRole.maintenancePersonnel.profileLabel, 'Utility Personnel');
      // The trades of Table 3.3 keep their names.
      expect(
        DamageCategory.structural.assignedPersonnelLabel,
        'Structural Maintenance Personnel',
      );
    });
  });
}
