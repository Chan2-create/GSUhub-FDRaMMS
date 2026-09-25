// Seeds the Firebase Emulator Suite with realistic GSUhub test data.
//
// Run with the emulators already started:
//
//     firebase emulators:start
//     dart run tool/seed_emulator.dart
//
// REFUSES TO RUN AGAINST A LIVE PROJECT. It talks to the emulator REST
// endpoints on localhost only — there is no code path here that can reach
// production, which is the point: a seed script that could be pointed at
// the real database by a stray environment variable is an accident
// waiting to happen.
//
// Safe to re-run: every document uses a fixed id, so a second run
// overwrites rather than duplicating.

import 'dart:convert';
import 'dart:io';

const String projectId = 'gsuhub-dorsu';

/// Emulator endpoints, overridable through the standard Firebase emulator
/// environment variables.
///
/// Hardcoding them means the script cannot follow the suite onto a
/// different port — and Windows reserves shifting TCP ranges at boot
/// (`netsh interface ipv4 show excludedportrange protocol=tcp`), which
/// periodically makes 9099 unbindable on a developer machine.
final String firestoreHost =
    Platform.environment['FIRESTORE_EMULATOR_HOST'] ?? 'localhost:8080';
final String authHost =
    Platform.environment['FIREBASE_AUTH_EMULATOR_HOST'] ?? 'localhost:9099';

const String _documentsRoot =
    '/v1/projects/$projectId/databases/(default)/documents';

Future<void> main() async {
  stdout.writeln('Seeding GSUhub emulator data...');

  if (!await _emulatorReachable()) {
    stderr
      ..writeln('Could not reach the Firestore emulator at $firestoreHost.')
      ..writeln('Start it first:  firebase emulators:start');
    exitCode = 1;
    return;
  }

  await _seedUsers();
  await _seedFacilities();
  await _seedAssets();
  await _seedInventory();
  await _seedTools();
  await _seedConfig();
  await _seedDamageReports();
  await _seedWorkOrders();
  await _seedHistory();
  await _seedAuditLogs();

  if (_failures > 0) {
    stderr
      ..writeln()
      ..writeln(
        '$_failures write(s) FAILED — the emulator is not fully '
        'seeded. See the errors above.',
      );
    exitCode = 1;
    return;
  }

  stdout
    ..writeln()
    ..writeln('Done. Sign in at the app with any of:')
    ..writeln('  admin@dorsu.edu.ph      / password123  (GSU Administrator)')
    ..writeln('  faculty@dorsu.edu.ph    / password123  (Faculty/Staff)')
    ..writeln('  personnel@dorsu.edu.ph  / password123  (Maintenance)')
    ..writeln()
    ..writeln('Emulator UI: http://localhost:4000');
}

// --- users -------------------------------------------------------------

/// Fixed uids so seeded Firestore documents and Auth accounts line up, and
/// so damage reports can reference their reporter without a lookup.
const String adminUid = 'seed-admin-0001';
const String facultyUid = 'seed-faculty-0001';
const String personnelUid = 'seed-personnel-0001';
const String personnelPlumberUid = 'seed-personnel-0002';

// Objective 2.C: enough accounts that Personnel and User Accounts show
// every state they can draw — on leave, deactivated, each role.
const String personnelStructuralUid = 'seed-personnel-0003';
const String personnelCarpenterUid = 'seed-personnel-0004';
const String personnelGeneralUid = 'seed-personnel-0005';
const String personnelAirconUid = 'seed-personnel-0006';
const String facultyCasUid = 'seed-faculty-0002';
const String facultyRegistrarUid = 'seed-faculty-0003';
const String facultyFormerUid = 'seed-faculty-0004';
const String secondAdminUid = 'seed-admin-0002';

Future<void> _seedUsers() async {
  final accounts = [
    (adminUid, 'admin@dorsu.edu.ph'),
    (facultyUid, 'faculty@dorsu.edu.ph'),
    (personnelUid, 'personnel@dorsu.edu.ph'),
    (personnelPlumberUid, 'plumber@dorsu.edu.ph'),
  ];

  for (final (uid, email) in accounts) {
    await _createAuthUser(uid: uid, email: email, password: 'password123');
  }

  await _writeDoc('users', adminUid, {
    'fullName': _str('Ramon Dela Cruz'),
    'email': _str('admin@dorsu.edu.ph'),
    'role': _str('admin'),
    'accountStatus': _str('active'),
    'department': _str('General Services Unit'),
    'contactNumber': _str('09171234567'),
    'activeTaskCount': _int(0),
    'createdAt': _now(),
    'updatedAt': _now(),
  });

  await _writeDoc('users', facultyUid, {
    'fullName': _str('Maria Santos'),
    'email': _str('faculty@dorsu.edu.ph'),
    'role': _str('requestor'),
    'accountStatus': _str('active'),
    'department': _str('College of Engineering'),
    'contactNumber': _str('09171234568'),
    'activeTaskCount': _int(0),
    'createdAt': _now(),
    'updatedAt': _now(),
  });

  await _writeDoc('users', personnelUid, {
    'fullName': _str('Marcus Wright'),
    'email': _str('personnel@dorsu.edu.ph'),
    'role': _str('maintenancePersonnel'),
    'accountStatus': _str('active'),
    'department': _str('General Services Unit'),
    'specialization': _str('electrical'),
    'availability': _str('available'),
    // Matches the one open work order seeded against this account; a count
    // that disagrees with the board is the first thing an assigner distrusts.
    'activeTaskCount': _int(1),
    'createdAt': _now(),
    'updatedAt': _now(),
  });

  await _writeDoc('users', personnelPlumberUid, {
    'fullName': _str('Juan Luna'),
    'email': _str('plumber@dorsu.edu.ph'),
    'role': _str('maintenancePersonnel'),
    'accountStatus': _str('active'),
    'department': _str('General Services Unit'),
    'specialization': _str('plumbing'),
    'availability': _str('busy'),
    'activeTaskCount': _int(1),
    'createdAt': _now(),
    'updatedAt': _now(),
  });

  // uid, name, email, role, status, department, trade, availability
  final more = [
    (
      personnelStructuralUid,
      'Rosa Villanueva',
      'structural@dorsu.edu.ph',
      'maintenancePersonnel',
      'active',
      'General Services Unit',
      'structural',
      'available',
    ),
    // On leave: the one status an administrator sets by hand.
    (
      personnelCarpenterUid,
      'Pedro Reyes',
      'carpenter@dorsu.edu.ph',
      'maintenancePersonnel',
      'active',
      'General Services Unit',
      'carpentry',
      'onLeave',
    ),
    (
      personnelGeneralUid,
      'Liza Mendoza',
      'general@dorsu.edu.ph',
      'maintenancePersonnel',
      'active',
      'General Services Unit',
      'generalMaintenance',
      'available',
    ),
    // Deactivated, so User Accounts has an inactive row to grey out and
    // Personnel has an account it must leave out.
    (
      personnelAirconUid,
      'Carlo Bato',
      'aircon@dorsu.edu.ph',
      'maintenancePersonnel',
      'inactive',
      'General Services Unit',
      'airConditioning',
      'available',
    ),
    (
      facultyCasUid,
      'Ana Gomez',
      'ana.gomez@dorsu.edu.ph',
      'requestor',
      'active',
      'College of Arts and Sciences',
      null,
      null,
    ),
    (
      facultyRegistrarUid,
      'Paolo Garcia',
      'paolo.garcia@dorsu.edu.ph',
      'requestor',
      'active',
      "Registrar's Office",
      null,
      null,
    ),
    (
      facultyFormerUid,
      'Grace Lim',
      'grace.lim@dorsu.edu.ph',
      'requestor',
      'inactive',
      'Office of Student Affairs',
      null,
      null,
    ),
    (
      secondAdminUid,
      'Elena Cruz',
      'elena.cruz@dorsu.edu.ph',
      'admin',
      'active',
      'IT Services',
      null,
      null,
    ),
  ];

  for (final (uid, name, email, role, status, department, trade, availability)
      in more) {
    // A real sign-in for every account, so a password reset sent from
    // User Accounts reaches the emulator's inbox rather than failing.
    await _createAuthUser(uid: uid, email: email, password: 'password123');
    await _writeDoc('users', uid, {
      'fullName': _str(name),
      'email': _str(email),
      'role': _str(role),
      'accountStatus': _str(status),
      'department': _str(department),
      'contactNumber': _null(),
      'specialization': trade == null ? _null() : _str(trade),
      'availability': availability == null ? _null() : _str(availability),
      'activeTaskCount': _int(0),
      'createdAt': _ago(const Duration(days: 150)),
      'updatedAt': _now(),
    });
  }

  stdout.writeln('  users: ${4 + more.length}');
}

// --- facilities & assets ----------------------------------------------

Future<void> _seedFacilities() async {
  // Real DOrSU buildings, so the seeded data reads plausibly during a
  // demo rather than looking like lorem ipsum.
  final facilities = [
    ('fac-engineering', 'Engineering Building', 'Room 101', 7.2048, 126.5354),
    ('fac-library', 'Main Library', 'Level 2', 7.2051, 126.5359),
    ('fac-admin', 'Administration Building', 'Office 12', 7.2044, 126.5348),
    ('fac-science', 'Science Building', 'Laboratory 3', 7.2056, 126.5362),
    ('fac-gym', 'Gymnasium', 'Main Court', 7.2041, 126.5365),
  ];

  for (final (id, building, room, lat, lng) in facilities) {
    await _writeDoc('facilities', id, {
      'name': _str(building),
      'buildingName': _str(building),
      'roomIdentifier': _str(room),
      'locationDescription': _str('$building, $room'),
      'coordinates': {
        'geoPointValue': {'latitude': lat, 'longitude': lng},
      },
      'qrCode': _str('FAC-${id.toUpperCase()}'),
      'isActive': _bool(true),
      'createdAt': _now(),
      'updatedAt': _now(),
    });
  }

  stdout.writeln('  facilities: ${facilities.length}');
}

Future<void> _seedAssets() async {
  final assets = [
    ('asset-aircon-01', 'Split-Type Aircon Unit', 'fac-engineering', 'good'),
    ('asset-projector-01', 'Ceiling Projector', 'fac-engineering', 'fair'),
    ('asset-fan-01', 'Ceiling Fan', 'fac-science', 'poor'),
  ];

  for (final (id, name, facilityId, condition) in assets) {
    await _writeDoc('assets', id, {
      'name': _str(name),
      'qrCode': _str('AST-${id.toUpperCase()}'),
      'facilityId': _str(facilityId),
      'condition': _str(condition),
      'category': _str(name),
      'isActive': _bool(true),
      'createdAt': _now(),
      'updatedAt': _now(),
    });
  }

  stdout.writeln('  assets: ${assets.length}');
}

// --- inventory & tools -------------------------------------------------

Future<void> _seedInventory() async {
  final items = [
    ('inv-led-bulb', 'LED Bulbs (60W Eq)', 'Electrical', 452.0, 'units', 50.0),
    ('inv-pvc-pipe', 'PVC Pipe (2-inch)', 'Plumbing', 12.0, 'units', 20.0),
    ('inv-hvac-filter', 'HVAC MERV-13 Filter', 'HVAC', 128.0, 'units', 25.0),
    ('inv-romex-wire', '12/2 ROMEX Wire', 'Electrical', 34.0, 'rolls', 10.0),
    ('inv-white-paint', 'Campus White (Flat)', 'Paint', 5.0, 'gallons', 8.0),
  ];

  for (final (id, name, category, quantity, unit, threshold) in items) {
    await _writeDoc('inventory_items', id, {
      'name': _str(name),
      'category': _str(category),
      'quantityAvailable': _double(quantity),
      'unitOfMeasurement': _str(unit),
      'storageLocation': _str('GSU Store Room A'),
      'qrCode': _str('INV-${id.toUpperCase()}'),
      'minimumThreshold': _double(threshold),
      'createdAt': _now(),
      'updatedAt': _now(),
    });
  }

  // Two items are deliberately below threshold (PVC pipe, white paint) so
  // the low-stock alert path has something to show without editing data.
  stdout.writeln('  inventory_items: ${items.length} (2 below threshold)');
}

Future<void> _seedTools() async {
  final tools = [
    (
      'tool-impact-driver',
      'TL-0824',
      'DeWalt Impact Driver 20V',
      'available',
      'excellent',
    ),
    ('tool-multimeter', 'TL-0912', 'Fluke Multimeter 179', 'available', 'good'),
    (
      'tool-hammer-drill',
      'TL-0755',
      'Hilti Rotary Hammer Drill',
      'inRepair',
      'fair',
    ),
    (
      'tool-pipe-threader',
      'TL-1102',
      'Pipe Threading Kit (Rigid)',
      'available',
      'poor',
    ),
  ];

  for (final (id, code, name, status, condition) in tools) {
    await _writeDoc('tools', id, {
      'toolCode': _str(code),
      'name': _str(name),
      'status': _str(status),
      'condition': _str(condition),
      'category': _str('Power Tools'),
      'storageLocation': _str('GSU Tool Crib'),
      'qrCode': _str('TOOL-$code'),
      'createdAt': _now(),
      'updatedAt': _now(),
    });
  }

  stdout.writeln('  tools: ${tools.length}');
}

// --- config ------------------------------------------------------------

Future<void> _seedConfig() async {
  // Both weight schemes, exactly as the manuscript states them, with
  // activeScheme selecting one. See docs/data_dictionary.md — the conflict
  // is unresolved and this document is where the decision will land.
  await _writeDoc('config', 'prioritization', {
    'activeScheme': _str('decimalWeights'),
    'integerWeights': _map({
      'severity': _double(3),
      'safetyRisk': _double(4),
      'frequency': _double(2),
      'locationImportance': _double(3),
    }),
    'decimalWeights': _map({
      'severity': _double(0.40),
      'safetyRisk': _double(0.30),
      'frequency': _double(0.20),
      'locationImportance': _double(0.10),
    }),
    'thresholds': _map({
      'critical': _double(3.50),
      'high': _double(2.50),
      'medium': _double(1.50),
      'low': _double(1.00),
    }),
    'minRating': _int(1),
    'maxRating': _int(4),
    'updatedAt': _now(),
    'updatedBy': _str(adminUid),
  });

  await _writeDoc('config', 'classification_rules', {
    'keywordsByCategory': _map({
      'electrical': _strArray([
        'power outage',
        'exposed wire',
        'short circuit',
        'faulty outlet',
      ]),
      'plumbing': _strArray([
        'leaking pipe',
        'clogged drain',
        'broken faucet',
        'flooding',
      ]),
      'structural': _strArray([
        'cracked wall',
        'damaged ceiling',
        'broken floor',
        'structural damage',
      ]),
      'carpentry': _strArray([
        'broken door',
        'damaged window',
        'broken chair',
        'broken cabinet',
      ]),
      'airConditioning': _strArray([
        'aircon not cooling',
        'leaking aircon',
        'ventilation issue',
      ]),
      'cleaningAndSanitation': _strArray([
        'waste buildup',
        'dirty area',
        'foul odor',
        'sanitation concern',
      ]),
      'generalMaintenance': _strArray([]),
    }),
    'caseSensitive': _bool(false),
    'updatedAt': _now(),
    'updatedBy': _str(adminUid),
  });

  await _writeDoc('config', 'duplicate_detection', {
    'enabled': _bool(true),
    'matchOnFacilityIdentifier': _bool(true),
    'matchOnLocation': _bool(true),
    'matchOnCategory': _bool(true),
    'descriptionSimilarityThreshold': _double(0.75),
    'timeWindowHours': _int(72),
    'updatedAt': _now(),
    'updatedBy': _str(adminUid),
  });

  stdout.writeln('  config: 3 documents');
}

// --- damage reports, work orders and the audit trail -------------------

/// One seeded report. Written as a class rather than a long positional
/// record because 2.B added review, assignment and scheduling fields, and
/// a nine-slot tuple stopped being readable.
class _SeededReport {
  const _SeededReport({
    required this.id,
    required this.title,
    required this.description,
    required this.facilityId,
    required this.facilityName,
    required this.requestorPriority,
    required this.status,
    required this.submittedHoursAgo,
    this.category,
    this.officialPriority,
    this.workOrderId,
  });

  final String id;
  final String title;
  final String description;

  /// Null for the one report left unclassified, so the screens have a case
  /// where category is genuinely absent — assignment refuses it, and the
  /// table shows "Unclassified" rather than a blank.
  final String? category;

  final String facilityId;
  final String facilityName;
  final String requestorPriority;

  /// Set only where an administrator would have confirmed it, so both the
  /// filled and the outlined priority chip appear on screen.
  final String? officialPriority;

  final String status;
  final int submittedHoursAgo;
  final String? workOrderId;

  bool get isReviewed => status != 'submitted' && status != 'underReview';
}

const List<_SeededReport> _seededReports = [
  _SeededReport(
    id: 'rep-0001',
    title: 'Broken Ceiling Fan',
    description:
        'Ceiling fan in Room 101 wobbles badly and makes a loud grinding '
        'noise. It looks like it could come loose.',
    category: 'electrical',
    facilityId: 'fac-engineering',
    facilityName: 'Engineering Building',
    requestorPriority: 'high',
    status: 'underReview',
    submittedHoursAgo: 5,
  ),
  _SeededReport(
    id: 'rep-0002',
    title: 'Leaking Pipe Under Sink',
    description:
        'Water is pooling under the sink in Science Laboratory 3. The floor '
        'is slippery and it has been getting worse since yesterday.',
    category: 'plumbing',
    facilityId: 'fac-science',
    facilityName: 'Science Building',
    requestorPriority: 'critical',
    officialPriority: 'critical',
    status: 'assigned',
    submittedHoursAgo: 26,
    workOrderId: 'wo-0002',
  ),
  _SeededReport(
    id: 'rep-0003',
    title: 'Flickering Lights',
    description:
        'Lights in the library study area flicker constantly. Possibly a '
        'ballast issue.',
    category: 'electrical',
    facilityId: 'fac-library',
    facilityName: 'Main Library',
    requestorPriority: 'medium',
    officialPriority: 'medium',
    status: 'inProgress',
    submittedHoursAgo: 72,
    workOrderId: 'wo-0003',
  ),
  _SeededReport(
    id: 'rep-0004',
    title: 'Aircon Not Cooling',
    description:
        'The split-type aircon in the admin office runs but does not cool '
        'the room at all.',
    category: 'airConditioning',
    facilityId: 'fac-admin',
    facilityName: 'Administration Building',
    requestorPriority: 'medium',
    status: 'submitted',
    submittedHoursAgo: 2,
  ),
  _SeededReport(
    id: 'rep-0005',
    title: 'Cracked Wall Near Stairwell',
    description:
        'A crack has appeared along the wall beside the west stairwell. It '
        'runs about a metre.',
    category: 'structural',
    facilityId: 'fac-engineering',
    facilityName: 'Engineering Building',
    requestorPriority: 'high',
    officialPriority: 'high',
    status: 'completed',
    submittedHoursAgo: 288,
    workOrderId: 'wo-0005',
  ),
  // The three below are approved and unassigned: without them the Task
  // Assignment queue is empty and the screen cannot be demonstrated.
  _SeededReport(
    id: 'rep-0006',
    title: 'Broken Door Handle',
    description:
        'The handle on the admin office door has come away from the frame '
        'and no longer latches.',
    category: 'carpentry',
    facilityId: 'fac-admin',
    facilityName: 'Administration Building',
    requestorPriority: 'low',
    officialPriority: 'low',
    status: 'approved',
    submittedHoursAgo: 8,
  ),
  _SeededReport(
    id: 'rep-0007',
    title: 'Clogged Drain in Laboratory 2',
    description:
        'The floor drain backs up whenever the sink is used. Standing water '
        'by the end of the afternoon.',
    category: 'plumbing',
    facilityId: 'fac-science',
    facilityName: 'Science Building',
    requestorPriority: 'high',
    status: 'approved',
    submittedHoursAgo: 30,
  ),
  _SeededReport(
    id: 'rep-0008',
    title: 'Ceiling Stain Spreading',
    description:
        'A brown stain on the library ceiling has grown since last week. '
        'Unclear whether it is a roof leak or a pipe.',
    facilityId: 'fac-library',
    facilityName: 'Main Library',
    requestorPriority: 'medium',
    status: 'approved',
    submittedHoursAgo: 20,
  ),
];

Future<void> _seedDamageReports() async {
  for (final report in _seededReports) {
    await _writeDoc('damage_reports', report.id, {
      'reporterId': _str(facultyUid),
      'reporterName': _str('Maria Santos'),
      'title': _str(report.title),
      'description': _str(report.description),
      'category': report.category == null ? _null() : _str(report.category!),
      'classifiedAutomatically': _bool(report.category != null),
      'facilityId': _str(report.facilityId),
      'facilityName': _str(report.facilityName),
      'locationDescription': _str(report.facilityName),
      'photoUrls': _strArray([]),
      'requestorPriority': _str(report.requestorPriority),
      'status': _str(report.status),
      // Every remaining nullable key DamageReport.toFirestore() writes,
      // written here as an explicit null so a seeded document has the same
      // shape as one the app creates. Omitting `duplicateOf` made all five
      // seeded reports invisible to the dashboard, whose queue filters on
      // `duplicateOf == null` — a document missing the field does not match.
      'assetId': _null(),
      'coordinates': _null(),
      // The four criterion ratings stay unset: who populates them is still
      // an open question (docs/data_dictionary.md §2.2). Null is what an
      // unrated report carries, so this is the shape either way.
      'severityRating': _null(),
      'safetyRiskRating': _null(),
      'frequencyRating': _null(),
      'locationImportanceRating': _null(),
      'priorityScore': _null(),
      'recommendedPriority': _null(),
      'officialPriority': report.officialPriority == null
          ? _null()
          : _str(report.officialPriority!),
      'duplicateOf': _null(),
      'workOrderId': report.workOrderId == null
          ? _null()
          : _str(report.workOrderId!),
      'reviewedBy': report.isReviewed ? _str(adminUid) : _null(),
      'reviewedAt': report.isReviewed
          ? _ago(Duration(hours: report.submittedHoursAgo - 1))
          : _null(),
      'rejectionReason': _null(),
      'submittedAt': _ago(Duration(hours: report.submittedHoursAgo)),
      'updatedAt': _now(),
    });
  }

  stdout.writeln(
    '  damage_reports: ${_seededReports.length} '
    '(3 approved and awaiting assignment, 1 unclassified)',
  );
}

/// Work orders for the three reports that have been assigned.
///
/// `wo-0002` is deliberately past its target date so the OVERDUE card has
/// something to count, and `wo-0005` completed this morning so COMPLETED
/// TODAY is not zero.
Future<void> _seedWorkOrders() async {
  final workOrders = [
    (
      'wo-0002',
      'rep-0002',
      'plumbing',
      'critical',
      'pending',
      personnelPlumberUid,
      24,
      -48,
      false,
    ),
    (
      'wo-0003',
      'rep-0003',
      'electrical',
      'medium',
      'inProgress',
      personnelUid,
      48,
      48,
      false,
    ),
    (
      'wo-0005',
      'rep-0005',
      'structural',
      'high',
      'completed',
      personnelUid,
      240,
      24,
      true,
    ),
  ];

  for (final (
        id,
        reportId,
        category,
        priority,
        status,
        assignee,
        createdHoursAgo,
        scheduledInHours,
        isCompleted,
      )
      in workOrders) {
    final report = _seededReports.firstWhere(
      (candidate) => candidate.id == reportId,
    );

    await _writeDoc('work_orders', id, {
      'reportIds': _strArray([reportId]),
      'title': _str(report.title),
      'description': _str(report.description),
      'category': _str(category),
      'priority': _str(priority),
      'status': _str(status),
      'assignedPersonnelIds': _strArray([assignee]),
      'facilityId': _str(report.facilityId),
      'facilityName': _str(report.facilityName),
      'adminNotes': _null(),
      'scheduledFor': _ago(Duration(hours: -scheduledInHours)),
      'startedAt': status == 'pending'
          ? _null()
          : _ago(Duration(hours: createdHoursAgo - 4)),
      'completedAt': isCompleted ? _ago(const Duration(hours: 3)) : _null(),
      'createdBy': _str(adminUid),
      'createdAt': _ago(Duration(hours: createdHoursAgo)),
      'updatedAt': _now(),
    });
  }

  stdout.writeln('  work_orders: ${workOrders.length} (1 overdue)');
}

/// Six months of resolved work, so Analytics has a history to chart
/// (Objective 2.C).
///
/// Every report here is completed or closed, so none of it reaches the
/// review queue, the assignment queue or anyone's workload — the live
/// demo scenario above is untouched. Generated rather than listed: the
/// spread (which trade, which building, how long each took) is
/// deterministic, so every seeded emulator draws the same charts.
/// Resolution time falls month on month, so the trend has a direction.
Future<void> _seedHistory() async {
  const trades = [
    ('electrical', personnelUid, 'Faulty wall outlet'),
    ('plumbing', personnelPlumberUid, 'Leaking faucet'),
    ('structural', personnelStructuralUid, 'Cracked floor tile'),
    ('airConditioning', personnelAirconUid, 'Aircon not cooling'),
    ('carpentry', personnelCarpenterUid, 'Broken cabinet door'),
    ('cleaningAndSanitation', personnelGeneralUid, 'Clogged restroom drain'),
    ('generalMaintenance', personnelGeneralUid, 'Loose stair handrail'),
  ];
  const buildings = [
    ('fac-engineering', 'Engineering Building'),
    ('fac-library', 'Main Library'),
    ('fac-science', 'Science Building'),
    ('fac-admin', 'Administration Building'),
    ('fac-gym', 'Gymnasium'),
  ];
  const priorities = ['low', 'medium', 'high', 'medium'];

  // Oldest month first: how many reports, and roughly how many days each
  // took from report to finished work.
  const months = [(4, 6.5), (5, 5.6), (6, 4.9), (5, 4.1), (7, 3.4), (3, 2.9)];

  final now = DateTime.now();
  var seeded = 0;
  for (var m = 0; m < months.length; m++) {
    final (count, days) = months[m];
    final monthsAgo = months.length - 1 - m;
    final monthStart = DateTime(now.year, now.month - monthsAgo);

    for (var i = 0; i < count; i++) {
      // Spread across the month; in the current one, only days already
      // past, finished before today.
      final day = monthsAgo == 0 ? 1 + i : 2 + (i * 5) % 25;
      final submitted = monthStart.add(
        Duration(days: day - 1, hours: 8 + (i * 3) % 8),
      );
      final took = Duration(
        minutes: ((days + (i % 3 - 1) * 0.4) * Duration.minutesPerDay).round(),
      );
      final completed = submitted.add(took);
      if (!completed.isBefore(now)) continue;

      final (category, assignee, title) =
          trades[(seeded * 3 + m) % trades.length];
      final (facilityId, facilityName) =
          buildings[(seeded + m) % buildings.length];
      final priority = priorities[seeded % priorities.length];
      final suffix = '$m${i.toString().padLeft(2, '0')}';
      final reportId = 'rep-h$suffix';
      final workOrderId = 'wo-h$suffix';
      final created = submitted.add(const Duration(hours: 6));

      await _writeDoc('damage_reports', reportId, {
        'reporterId': _str(facultyUid),
        'reporterName': _str('Maria Santos'),
        'title': _str(title),
        'description': _str('$title — $facilityName.'),
        'category': _str(category),
        'classifiedAutomatically': _bool(true),
        'facilityId': _str(facilityId),
        'facilityName': _str(facilityName),
        'locationDescription': _str(facilityName),
        'photoUrls': _strArray([]),
        'requestorPriority': _str(priority),
        // Older than a month: signed off. This month: finished, not yet
        // closed.
        'status': _str(monthsAgo > 0 ? 'closed' : 'completed'),
        'assetId': _null(),
        'coordinates': _null(),
        'severityRating': _null(),
        'safetyRiskRating': _null(),
        'frequencyRating': _null(),
        'locationImportanceRating': _null(),
        'priorityScore': _null(),
        'recommendedPriority': _null(),
        'officialPriority': _str(priority),
        'duplicateOf': _null(),
        'workOrderId': _str(workOrderId),
        'reviewedBy': _str(adminUid),
        'reviewedAt': _at(submitted.add(const Duration(hours: 2))),
        'rejectionReason': _null(),
        'submittedAt': _at(submitted),
        'updatedAt': _at(completed),
      });

      await _writeDoc('work_orders', workOrderId, {
        'reportIds': _strArray([reportId]),
        'title': _str(title),
        'description': _str('$title — $facilityName.'),
        'category': _str(category),
        'priority': _str(priority),
        'status': _str('completed'),
        'assignedPersonnelIds': _strArray([assignee]),
        'facilityId': _str(facilityId),
        'facilityName': _str(facilityName),
        'adminNotes': _null(),
        'scheduledFor': _at(created.add(const Duration(days: 7))),
        'startedAt': _at(created.add(const Duration(hours: 2))),
        'completedAt': _at(completed),
        'createdBy': _str(adminUid),
        'createdAt': _at(created),
        'updatedAt': _at(completed),
      });
      seeded++;
    }
  }

  stdout.writeln('  history: $seeded resolved reports over six months');
}

/// A short audit trail, so the dashboard's Recent Activity panel and the
/// report detail view's history have something to show on a fresh
/// emulator. Entries the app writes itself look exactly like these.
Future<void> _seedAuditLogs() async {
  final entries = [
    (
      'aud-0001',
      'rep-0002',
      'damage_reports',
      'statusChanged',
      'Status changed from UNDER REVIEW to APPROVED',
      27,
    ),
    (
      'aud-0002',
      'rep-0002',
      'damage_reports',
      'assigned',
      'Assigned to Juan Luna',
      24,
    ),
    (
      'aud-0003',
      'wo-0002',
      'work_orders',
      'created',
      'Work order created from report rep-0002',
      24,
    ),
    (
      'aud-0004',
      'rep-0003',
      'damage_reports',
      'assigned',
      'Assigned to Marcus Wright',
      48,
    ),
    (
      'aud-0005',
      'wo-0003',
      'work_orders',
      'statusChanged',
      'Status changed from Pending to In Progress',
      44,
    ),
    (
      'aud-0006',
      'rep-0005',
      'damage_reports',
      'statusChanged',
      'Status changed from FOR REVIEW to COMPLETED',
      3,
    ),
  ];

  for (final (id, entityId, entityType, action, description, hoursAgo)
      in entries) {
    await _writeDoc('audit_logs', id, {
      'actorId': _str(adminUid),
      'actorName': _str('Ramon Dela Cruz'),
      'action': _str(action),
      'entityType': _str(entityType),
      'entityId': _str(entityId),
      'description': _str(description),
      'changes': _null(),
      'timestamp': _ago(Duration(hours: hoursAgo)),
    });
  }

  stdout.writeln('  audit_logs: ${entries.length}');
}

// --- emulator REST helpers --------------------------------------------

final HttpClient _client = HttpClient();

/// Number of writes that failed, so the script can exit non-zero instead
/// of printing reassuring counts for data it never wrote.
int _failures = 0;

/// The Firebase emulators accept this bearer token as full administrative
/// access, bypassing security rules. That is exactly what seeding needs:
/// the rules correctly deny unauthenticated writes, and seeding is not a
/// client operation. No real credential is involved, and this only works
/// against an emulator — a live project rejects it outright.
const Map<String, String> _adminHeaders = {'Authorization': 'Bearer owner'};

Future<bool> _emulatorReachable() async {
  try {
    final request = await _client
        .getUrl(Uri.parse('http://$firestoreHost/'))
        .timeout(const Duration(seconds: 3));
    final response = await request.close().timeout(const Duration(seconds: 3));
    await response.drain<void>();
    return true;
  } on Object {
    return false;
  }
}

/// Writes a document with a fixed id, replacing any existing one.
Future<void> _writeDoc(
  String collection,
  String id,
  Map<String, Object?> fields,
) async {
  final uri = Uri.parse('http://$firestoreHost$_documentsRoot/$collection/$id');

  final request = await _client.patchUrl(uri);
  request.headers.contentType = ContentType.json;
  _adminHeaders.forEach(request.headers.set);
  request.write(jsonEncode({'fields': fields}));

  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();

  if (response.statusCode >= 300) {
    _failures++;
    stderr.writeln('  ! $collection/$id -> ${response.statusCode} $body');
  }
}

/// Creates an Auth emulator account with a fixed uid.
///
/// Uses the Admin-SDK-shaped endpoint rather than `accounts:signUp`: the
/// public sign-up endpoint assigns its own uid and rejects `localId`,
/// but the seeded Firestore `users/{uid}` documents have to line up with
/// real Auth uids or every sign-in resolves to a missing profile.
///
/// Ignores "already exists" so the script stays re-runnable.
Future<void> _createAuthUser({
  required String uid,
  required String email,
  required String password,
}) async {
  final uri = Uri.parse(
    'http://$authHost/identitytoolkit.googleapis.com/v1/'
    'projects/$projectId/accounts',
  );

  final request = await _client.postUrl(uri);
  request.headers.contentType = ContentType.json;
  _adminHeaders.forEach(request.headers.set);
  request.write(
    jsonEncode({
      'localId': uid,
      'email': email,
      'password': password,
      'emailVerified': true,
    }),
  );

  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();

  final alreadyExists =
      body.contains('EMAIL_EXISTS') || body.contains('DUPLICATE_LOCAL_ID');

  if (response.statusCode >= 300 && !alreadyExists) {
    _failures++;
    stderr.writeln('  ! auth $email -> ${response.statusCode} $body');
  }
}

// Firestore REST value wrappers.
Map<String, Object?> _str(String value) => {'stringValue': value};
Map<String, Object?> _int(int value) => {'integerValue': '$value'};
Map<String, Object?> _double(double value) => {'doubleValue': value};
Map<String, Object?> _bool(bool value) => {'booleanValue': value};

/// An explicit null, which is not the same as omitting the field.
///
/// `where('x', isNull: true)` matches only documents that *have* the field
/// set to null; a document missing it entirely does not match. Seeded data
/// therefore has to write the same nulls `toFirestore()` writes, or queries
/// that filter on them silently return nothing.
Map<String, Object?> _null() => {'nullValue': null};

/// A timestamp [ago] before now, so seeded data has a believable spread
/// of ages — response time and the volume chart both measure elapsed time.
Map<String, Object?> _ago(Duration ago) => {
  'timestampValue': DateTime.now().toUtc().subtract(ago).toIso8601String(),
};

/// A timestamp at [moment] — for the history, whose dates are calendar
/// positions rather than distances from now.
Map<String, Object?> _at(DateTime moment) => {
  'timestampValue': moment.toUtc().toIso8601String(),
};

Map<String, Object?> _now() => {
  'timestampValue': DateTime.now().toUtc().toIso8601String(),
};
Map<String, Object?> _map(Map<String, Object?> fields) => {
  'mapValue': {'fields': fields},
};
Map<String, Object?> _strArray(List<String> values) => {
  'arrayValue': {'values': values.map(_str).toList(growable: false)},
};
