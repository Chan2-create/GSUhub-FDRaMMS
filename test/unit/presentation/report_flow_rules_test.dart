import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/data/geo_coordinates.dart';
import 'package:gsuhub/core/enums/account_status.dart';
import 'package:gsuhub/core/enums/notification_type.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/enums/work_order_status.dart';
import 'package:gsuhub/core/routing/route_paths.dart';
import 'package:gsuhub/core/widgets/status_chip.dart';
import 'package:gsuhub/features/damage_reports/data/models/damage_report.dart';
import 'package:gsuhub/features/damage_reports/presentation/report_providers.dart';
import 'package:gsuhub/features/facilities/data/models/building.dart';
import 'package:gsuhub/features/facilities/data/models/facility.dart';
import 'package:gsuhub/features/facilities/data/models/facility_draft.dart';
import 'package:gsuhub/features/facilities/presentation/facility_directory.dart';
import 'package:gsuhub/features/notifications/data/models/app_notification.dart';
import 'package:gsuhub/features/notifications/presentation/nav_badges.dart';
import 'package:gsuhub/features/work_orders/data/models/work_order.dart';
import 'package:gsuhub/features/work_orders/presentation/widgets/personnel_assignment.dart';

import '../../support/fake_admin_backend.dart';

/// The rules behind the adviser's changes of 2026-11-26: the reports'
/// order, who may take a report (Table 3.3), what a person holds now, the
/// navigation's badges, and the words the requestor reads.
void main() {
  final now = DateTime.utc(2026, 11, 26, 8);

  DamageReport report(
    String id, {
    required PriorityLevel priority,
    bool confirmed = true,
    Duration age = Duration.zero,
    ReportStatus status = ReportStatus.underReview,
    DateTime? rescheduledTo,
  }) => DamageReport(
    id: id,
    reporterId: 'faculty-1',
    reporterName: 'Maria Santos',
    title: 'Report $id',
    description: 'Something is broken.',
    requestorPriority: confirmed ? PriorityLevel.low : priority,
    officialPriority: confirmed ? priority : null,
    category: DamageCategory.electrical,
    status: status,
    rescheduledTo: rescheduledTo,
    rescheduleReason: rescheduledTo == null ? null : 'Nobody free.',
    submittedAt: now.subtract(age),
    updatedAt: now,
  );

  group('the Damage Reports order', () {
    test('Critical, High, Medium, Low; the oldest first within each', () {
      final reports = [
        report('low-new', priority: PriorityLevel.low),
        report('high-new', priority: PriorityLevel.high),
        report(
          'medium-old',
          priority: PriorityLevel.medium,
          age: const Duration(days: 4),
        ),
        report(
          'high-old',
          priority: PriorityLevel.high,
          age: const Duration(days: 2),
        ),
        report('critical', priority: PriorityLevel.critical),
        report('medium-new', priority: PriorityLevel.medium),
      ]..sort(byPriorityThenOldest);

      expect(
        [for (final r in reports) r.id],
        [
          'critical',
          'high-old',
          'high-new',
          'medium-old',
          'medium-new',
          'low-new',
        ],
      );
    });

    test('an unconfirmed report is listed under the urgency it was filed '
        'with, and moves once its priority is confirmed', () {
      final unconfirmed = report(
        'u',
        priority: PriorityLevel.critical,
        confirmed: false,
      );
      final low = report('l', priority: PriorityLevel.low);
      expect(([low, unconfirmed]..sort(byPriorityThenOldest)).first.id, 'u');

      final lowered = unconfirmed.copyWith(officialPriority: PriorityLevel.low);
      final older = report(
        'older',
        priority: PriorityLevel.low,
        age: const Duration(days: 1),
      );
      expect(
        [
          for (final r in [lowered, older]..sort(byPriorityThenOldest)) r.id,
        ],
        ['older', 'u'],
      );
    });
  });

  group('who can take a report (Table 3.3)', () {
    final people = [
      fakePersonnel(id: 'elec', fullName: 'Ana Electrician'),
      fakePersonnel(
        id: 'plumb',
        fullName: 'Ben Plumber',
        specialization: DamageCategory.plumbing,
      ),
      fakePersonnel(
        id: 'struct',
        fullName: 'Cara Structural',
        specialization: DamageCategory.structural,
      ),
      fakePersonnel(
        id: 'carp',
        fullName: 'Dan Carpenter',
        specialization: DamageCategory.carpentry,
      ),
      fakePersonnel(
        id: 'air',
        fullName: 'Eva Aircon',
        specialization: DamageCategory.airConditioning,
      ),
      fakePersonnel(
        id: 'jan',
        fullName: 'Fe Janitor',
        specialization: DamageCategory.cleaningAndSanitation,
      ),
      fakePersonnel(id: 'none', fullName: 'Gil Untraded', specialization: null),
    ];
    List<String> ids(DamageCategory? category) => [
      for (final person in personnelOfTrade(people, category)) person.id,
    ];

    test('a lights report lists electricians only', () {
      expect(ids(DamageCategory.electrical), ['elec']);
    });

    test('each damage type goes to its own trade', () {
      expect(ids(DamageCategory.plumbing), ['plumb']);
      expect(ids(DamageCategory.airConditioning), ['air']);
      expect(ids(DamageCategory.cleaningAndSanitation), ['jan']);
      // Structural and Carpentry both go to Structural Maintenance
      // Personnel.
      expect(
        ids(DamageCategory.structural),
        unorderedEquals(['struct', 'carp']),
      );
      expect(
        ids(DamageCategory.carpentry),
        unorderedEquals(['struct', 'carp']),
      );
    });

    test('no damage type, nobody', () {
      expect(ids(null), isEmpty);
    });

    test('active accounts first, then the least busy', () {
      final ranked = personnelOfTrade([
        fakePersonnel(id: 'busy', fullName: 'A', activeTaskCount: 3),
        fakePersonnel(
          id: 'off',
          fullName: 'B',
          accountStatus: AccountStatus.inactive,
        ),
        fakePersonnel(id: 'free', fullName: 'C'),
      ], DamageCategory.electrical);
      expect([for (final p in ranked) p.id], ['free', 'busy', 'off']);
    });
  });

  group('availability and workload', () {
    test('available, busy, on leave, inactive', () {
      final person = fakePersonnel(id: 'p', fullName: 'Ana');
      expect(
        AssignmentAvailability.of(person, held: 0),
        AssignmentAvailability.available,
      );
      expect(
        AssignmentAvailability.of(person, held: 2),
        AssignmentAvailability.busy,
      );
      expect(
        AssignmentAvailability.of(
          fakePersonnel(
            id: 'x',
            fullName: 'X',
            accountStatus: AccountStatus.inactive,
          ),
          held: 0,
        ),
        AssignmentAvailability.inactive,
      );
      expect(AssignmentAvailability.busy.canTakeWork, isTrue);
      expect(AssignmentAvailability.inactive.canTakeWork, isFalse);
      expect(AssignmentAvailability.onLeave.canTakeWork, isFalse);
    });

    WorkOrder workOrder(String title) => WorkOrder(
      id: title,
      reportIds: const ['r'],
      title: title,
      description: '',
      category: DamageCategory.electrical,
      priority: PriorityLevel.medium,
      status: WorkOrderStatus.inProgress,
      createdBy: 'admin',
      createdAt: now,
      updatedAt: now,
    );

    test('the tasks a person holds now, the first by name', () {
      expect(workloadSummary(const []), 'No current tasks');
      expect(
        workloadSummary([workOrder('Flickering lights')]),
        '1 current task: Flickering lights',
      );
      expect(
        workloadSummary([
          workOrder('Flickering lights'),
          workOrder('Dead outlet'),
          workOrder('Broken switch'),
        ]),
        '3 current tasks: Flickering lights; Dead outlet and 1 more',
      );
    });
  });

  group('the navigation badges', () {
    AppNotification notice(
      String id,
      String? entity, {
      NotificationType type = NotificationType.statusUpdate,
      String title = 'Notice',
      bool read = false,
    }) => AppNotification(
      id: id,
      recipientId: 'me',
      type: type,
      title: title,
      body: 'Body',
      isRead: read,
      readAt: read ? now : null,
      createdAt: now,
      relatedEntityType: entity,
      relatedEntityId: entity == null ? null : 'x',
    );

    test('the console counts each item its own notices', () {
      final counts = badgeCountsOf([
        notice('1', 'damage_reports', type: NotificationType.reportSubmitted),
        notice('2', 'damage_reports', type: NotificationType.reportSubmitted),
        notice('3', 'work_orders', type: NotificationType.reviewRequested),
        notice('4', 'inventory_items', type: NotificationType.lowStockAlert),
        notice('5', 'material_requests'),
        notice('6', 'tool_requests', type: NotificationType.toolReturned),
        notice('7', 'users', type: NotificationType.accountRequested),
        notice('8', 'damage_reports', read: true),
        notice('9', null),
      ], adminSectionOf);
      expect(counts, {
        RoutePaths.adminReports: 2,
        RoutePaths.adminWorkOrders: 1,
        RoutePaths.adminInventory: 3,
        RoutePaths.adminUsers: 1,
      });
    });

    test("the faculty app's notices are all about its reports", () {
      expect(
        badgeCountsOf([
          notice('1', 'damage_reports'),
          notice('2', 'damage_reports'),
        ], requestorSectionOf),
        {RoutePaths.staffMyReports: 2},
      );
    });

    test('the maintenance app: tasks, materials and tools, and the work', () {
      expect(
        badgeCountsOf([
          notice('1', 'work_orders', type: NotificationType.taskAssigned),
          notice('2', 'work_orders', title: 'Materials approved'),
          notice(
            '3',
            'tool_requests',
            type: NotificationType.toolCheckoutRequested,
          ),
          notice('4', 'work_orders', type: NotificationType.workOrderAssigned),
          notice('5', 'work_orders', title: 'Work sent back'),
        ], personnelSectionOf),
        {
          RoutePaths.personnelTasks: 1,
          RoutePaths.personnelMaterials: 2,
          RoutePaths.personnelDashboard: 2,
        },
      );
    });
  });

  group("the requestor's words for a report", () {
    test('Under Review says so, not Pending', () {
      expect(StatusChip.requestorLabelOf(ReportStatus.submitted), 'Pending');
      expect(
        StatusChip.requestorLabelOf(ReportStatus.underReview),
        'Under Review',
      );
    });

    test('an approved report given a date reads Scheduled', () {
      expect(
        StatusChip.requestorLabelOf(ReportStatus.approved, rescheduled: true),
        'Scheduled',
      );
      expect(StatusChip.requestorLabelOf(ReportStatus.approved), 'In Progress');
    });

    test('a report is rescheduled only while it waits for assignment', () {
      final waiting = report(
        'w',
        priority: PriorityLevel.medium,
        status: ReportStatus.approved,
        rescheduledTo: now.add(const Duration(days: 2)),
      );
      expect(waiting.isRescheduled, isTrue);
      expect(
        waiting
            .copyWith(status: ReportStatus.assigned, workOrderId: 'wo')
            .isRescheduled,
        isFalse,
      );
    });
  });

  group('buildings and rooms', () {
    test('a building needs a name, and both halves of its pin or neither', () {
      expect(
        const BuildingDraft(name: '  ').problem,
        'Enter the building’s name.',
      );
      expect(
        const BuildingDraft(name: 'Library', latitude: 6.93).problem,
        'Enter both the latitude and the longitude, or neither.',
      );
      expect(
        const BuildingDraft(
          name: '  Main   Library ',
          latitude: 6.93,
          longitude: 126.25,
        ).problem,
        isNull,
      );
      expect(
        const BuildingDraft(name: '  Main   Library ').normalized().name,
        'Main Library',
      );
    });

    test('a room is chosen into a building, on a floor of up to 40', () {
      expect(
        const FacilityDraft(buildingName: '').problem,
        'Choose the building.',
      );
      expect(
        FacilityDraft(buildingName: 'Library', floor: 'x' * 41).problem,
        'Keep the floor to 40 characters.',
      );
      expect(
        const FacilityDraft(
          buildingName: 'Library',
          buildingId: 'b-1',
          floor: '2nd floor',
        ).problem,
        isNull,
      );
    });

    test('the report form lists a room with its floor', () {
      Facility room({String? floor}) => Facility(
        id: 'f',
        name: 'Library',
        buildingName: 'Library',
        roomIdentifier: 'Room 203',
        floor: floor,
        qrCode: 'FAC-F',
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );
      expect(
        FacilityDirectory.roomOptionLabelOf(room(floor: '2nd floor')),
        'Room 203 · 2nd floor',
      );
      expect(FacilityDirectory.roomOptionLabelOf(room()), 'Room 203');
    });

    test('a pin is placed from the room, its building, the campus', () {
      const mine = GeoCoordinates(latitude: 1, longitude: 2);
      const near = GeoCoordinates(latitude: 3, longitude: 4);
      Building building(double lat, double lng) => Building(
        id: '$lat',
        name: 'B$lat',
        coordinates: GeoCoordinates(latitude: lat, longitude: lng),
        createdAt: now,
        updatedAt: now,
      );
      expect(pinPickerStart(current: mine, near: [near]), mine);
      expect(pinPickerStart(near: [null, near]), near);
      final middle = pinPickerStart(
        buildings: [building(6, 126), building(8, 128)],
      );
      expect(middle.latitude, 7);
      expect(middle.longitude, 127);
      expect(pinPickerStart(), campusFallbackCentre);
    });
  });
}
