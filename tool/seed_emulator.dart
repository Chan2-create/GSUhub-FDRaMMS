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

import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/features/notifications/data/models/personnel_notice.dart';
import 'package:gsuhub/features/notifications/data/models/report_notice.dart';

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
  await _seedPersonnelWork();
  await _seedHistory();
  await _seedAuditLogs();
  stdout.writeln(
    '  notifications: $_notices (one per move a reporter is told of; '
    'older than two days already read)',
  );

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
    ..writeln('  liza.tan@dorsu.edu.ph   / password123  is a faculty sign-up')
    ..writeln('  still awaiting approval: approve it from User Accounts.')
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

// Objective 3.A: a faculty member who signed themselves up and is waiting
// for an administrator, so User Accounts has a request to approve and the
// faculty sign-in has an account to refuse with "awaiting approval".
const String facultyPendingUid = 'seed-faculty-0005';

/// Names and trades of the personnel the seeded work orders go to, as an
/// `assigned` timeline entry records them (Objective 3.B).
const Map<String, (String, String)> _personnel = {
  personnelUid: ('Marcus Wright', 'electrical'),
  personnelPlumberUid: ('Juan Luna', 'plumbing'),
  personnelStructuralUid: ('Rosa Villanueva', 'structural'),
  personnelCarpenterUid: ('Pedro Reyes', 'carpentry'),
  personnelGeneralUid: ('Liza Mendoza', 'generalMaintenance'),
  personnelAirconUid: ('Carlo Bato', 'airConditioning'),
};
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
    // Matches the two open work orders seeded against this account (wo-0003
    // and wo-0013); a count that disagrees with the board is the first
    // thing an assigner distrusts.
    'activeTaskCount': _int(2),
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
    // Signed up from the app: no department, as sign-up does not ask.
    (
      facultyPendingUid,
      'Liza Mae Tan',
      'liza.tan@dorsu.edu.ph',
      'requestor',
      'pending',
      null,
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
      'department': department == null ? _null() : _str(department),
      'contactNumber': _null(),
      'specialization': trade == null ? _null() : _str(trade),
      'availability': availability == null ? _null() : _str(availability),
      // Rosa Villanueva has the one job waiting for sign-off (wo-0009).
      'activeTaskCount': _int(uid == personnelStructuralUid ? 1 : 0),
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
  //
  // Several rooms per building, so the report form's Room select (3.C)
  // has a real choice to make. The first id in each building is the one
  // the seeded reports point at.
  final facilities = [
    ('fac-engineering', 'Engineering Building', 'Room 101', 7.2048, 126.5354),
    (
      'fac-engineering-203',
      'Engineering Building',
      'Room 203',
      7.2048,
      126.5354,
    ),
    (
      'fac-engineering-cl2',
      'Engineering Building',
      'Computer Laboratory 2',
      7.2048,
      126.5354,
    ),
    ('fac-library', 'Main Library', 'Level 2', 7.2051, 126.5359),
    ('fac-library-reading', 'Main Library', 'Reading Area', 7.2051, 126.5359),
    ('fac-admin', 'Administration Building', 'Office 12', 7.2044, 126.5348),
    (
      'fac-admin-records',
      'Administration Building',
      'Records Room',
      7.2044,
      126.5348,
    ),
    ('fac-science', 'Science Building', 'Laboratory 3', 7.2056, 126.5362),
    ('fac-science-lab1', 'Science Building', 'Laboratory 1', 7.2056, 126.5362),
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
  // activeScheme selecting one: the §3.4 formula's decimal weights, Chris's
  // choice (Objective 4.B, 2026-10-12). Table 3.2's integers are kept so
  // the conflict stays visible (docs/data_dictionary.md).
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
    // The Frequency hint (4.B): reports of the same damage at the same
    // facility in the last 30 days; 2, 3 and 5 of them suggest Moderate,
    // High and Very High.
    'frequencyWindowDays': _int(30),
    'frequencyBands': _intArray([2, 3, 5]),
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
    'descriptionSimilarityThreshold': _double(0.5),
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
    this.classifiedAutomatically = false,
    this.ratings,
    this.officialPriority,
    this.workOrderId,
    this.rejectionReason,
    this.duplicateOf,
    this.keptSeparateFrom = const [],
  });

  final String id;
  final String title;
  final String description;

  /// Null for the one report left unclassified, so the screens have a case
  /// where category is genuinely absent — assignment refuses it, and the
  /// table shows "Unclassified" rather than a blank.
  final String? category;

  /// Whether the keyword classifier found [category] in the title and
  /// description as the report was filed (Objective 4.A): true only where
  /// a Table 3.3 keyword is in the text. Elsewhere an administrator set it.
  final bool classifiedAutomatically;

  /// The administrator's Severity, Safety risk, Frequency and Location
  /// importance ratings (4.B), on each report whose official priority is
  /// set: the score they give recommends that priority, as a review would
  /// have left it.
  final (int, int, int, int)? ratings;

  final String facilityId;
  final String facilityName;
  final String requestorPriority;

  /// Set only where an administrator would have confirmed it, so both the
  /// filled and the outlined priority chip appear on screen.
  final String? officialPriority;

  final String status;
  final int submittedHoursAgo;
  final String? workOrderId;

  /// Why an administrator turned the report down, for `rejected`.
  final String? rejectionReason;

  /// The report a `merged` one was folded into.
  final String? duplicateOf;

  /// Reports an administrator ruled are not duplicates of this one (4.C).
  final List<String> keptSeparateFrom;

  bool get isReviewed => status != 'submitted' && status != 'underReview';
}

const List<_SeededReport> _seededReports = [
  _SeededReport(
    id: 'rep-0001',
    title: 'Broken Ceiling Fan',
    description:
        'Ceiling fan in Room 101 wobbles badly and makes a loud grinding '
        'noise. The wall switch sparks like a short circuit.',
    category: 'electrical',
    classifiedAutomatically: true,
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
    classifiedAutomatically: true,
    // 0.40×4 + 0.30×4 + 0.20×2 + 0.10×3 = 3.50: Critical. Frequency 2:
    // rep-0007 is plumbing at the same building.
    ratings: (4, 4, 2, 3),
    // Plumbing at the same building within 72 hours, so the two were
    // flagged as possible duplicates; a leaking pipe and a clogged drain
    // are two jobs, and the administrator kept them separate.
    keptSeparateFrom: ['rep-0007'],
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
    // 1.90: Medium. No keyword in the text: the administrator chose it.
    ratings: (2, 2, 1, 3),
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
    classifiedAutomatically: true,
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
    classifiedAutomatically: true,
    // 2.50: High, on the band's edge.
    ratings: (3, 3, 1, 2),
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
    classifiedAutomatically: true,
    // 1.10: Low.
    ratings: (1, 1, 1, 2),
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
    classifiedAutomatically: true,
    // Approved before 4.C, with no official priority: Task Assignment sends
    // it to its page to be reviewed first.
    keptSeparateFrom: ['rep-0002'],
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
  // Objective 3.B: the stages the reports above never reach, so the
  // faculty timeline can be seen in every one of them.
  _SeededReport(
    id: 'rep-0009',
    title: 'Loose Ceiling Panel',
    description:
        'A ceiling panel above the Science Building lobby sags at one '
        'corner and moves when the door slams.',
    category: 'structural',
    // 2.10: Medium, below the requestor's High.
    ratings: (2, 3, 1, 2),
    facilityId: 'fac-science',
    facilityName: 'Science Building',
    requestorPriority: 'high',
    officialPriority: 'medium',
    status: 'forReview',
    submittedHoursAgo: 120,
    workOrderId: 'wo-0009',
  ),
  _SeededReport(
    id: 'rep-0010',
    title: 'Projector Mount Rattling',
    description:
        'The projector in Engineering Room 204 rattles on its ceiling mount '
        'whenever it is switched on.',
    category: 'electrical',
    facilityId: 'fac-engineering',
    facilityName: 'Engineering Building',
    requestorPriority: 'low',
    status: 'rejected',
    submittedHoursAgo: 50,
    rejectionReason:
        'Projectors are serviced by the ICT Office, not the General '
        'Services Unit. Please raise this with ICT.',
  ),
  _SeededReport(
    id: 'rep-0011',
    title: 'Noisy Fan in Room 101',
    description:
        'The ceiling fan in Engineering Room 101 grinds loudly when it '
        'runs at full speed.',
    category: 'electrical',
    facilityId: 'fac-engineering',
    facilityName: 'Engineering Building',
    requestorPriority: 'medium',
    status: 'merged',
    submittedHoursAgo: 4,
    duplicateOf: 'rep-0001',
  ),
  // Objective 5: assigned to personnel@ this morning and not yet started,
  // so "Start work" can be tried. At the Administration Building, where no
  // other electrical report is open, so it is flagged as nobody's
  // duplicate.
  _SeededReport(
    id: 'rep-0013',
    title: 'Sparking Wall Outlet',
    description:
        'The wall outlet beside the registrar counter sparks whenever '
        'anything is plugged in. Possibly a faulty outlet.',
    category: 'electrical',
    classifiedAutomatically: true,
    // 0.40×3 + 0.30×4 + 0.20×1 + 0.10×2 = 2.80: High.
    ratings: (3, 4, 1, 2),
    facilityId: 'fac-admin',
    facilityName: 'Administration Building',
    requestorPriority: 'high',
    officialPriority: 'high',
    status: 'assigned',
    submittedHoursAgo: 10,
    workOrderId: 'wo-0013',
  ),
  _SeededReport(
    id: 'rep-0012',
    title: 'Faded Room Signage',
    description:
        'The room number signs along the Administration Building corridor '
        'have faded and are hard to read.',
    category: 'generalMaintenance',
    facilityId: 'fac-admin',
    facilityName: 'Administration Building',
    requestorPriority: 'low',
    status: 'archived',
    submittedHoursAgo: 400,
  ),
];

Future<void> _seedDamageReports() async {
  for (final report in _seededReports) {
    final ratings = report.ratings;
    final score = ratings == null ? null : _scoreOf(ratings);
    await _writeDoc('damage_reports', report.id, {
      'reporterId': _str(facultyUid),
      'reporterName': _str('Maria Santos'),
      'title': _str(report.title),
      'description': _str(report.description),
      'category': report.category == null ? _null() : _str(report.category!),
      'classifiedAutomatically': _bool(report.classifiedAutomatically),
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
      // Rated by an administrator in review (Objective 4.B), on the
      // reports whose official priority is set; null on the rest.
      'severityRating': ratings == null ? _null() : _int(ratings.$1),
      'safetyRiskRating': ratings == null ? _null() : _int(ratings.$2),
      'frequencyRating': ratings == null ? _null() : _int(ratings.$3),
      'locationImportanceRating': ratings == null ? _null() : _int(ratings.$4),
      'priorityScore': score == null ? _null() : _double(score),
      'recommendedPriority': score == null ? _null() : _str(_levelFor(score)),
      'officialPriority': report.officialPriority == null
          ? _null()
          : _str(report.officialPriority!),
      'duplicateOf': report.duplicateOf == null
          ? _null()
          : _str(report.duplicateOf!),
      'dismissedDuplicateIds': _strArray(report.keptSeparateFrom),
      'workOrderId': report.workOrderId == null
          ? _null()
          : _str(report.workOrderId!),
      'reviewedBy': report.isReviewed ? _str(adminUid) : _null(),
      'reviewedAt': report.isReviewed
          ? _ago(Duration(hours: report.submittedHoursAgo - 1))
          : _null(),
      'rejectionReason': report.rejectionReason == null
          ? _null()
          : _str(report.rejectionReason!),
      'submittedAt': _ago(Duration(hours: report.submittedHoursAgo)),
      'updatedAt': _now(),
    });
    await _seedReviewTimeline(report);
  }

  // Objective 3.A: one report filed by somebody else, so signing in as
  // faculty@ shows My Reports leaving it out.
  await _writeDoc('damage_reports', 'rep-ana-0001', {
    'reporterId': _str(facultyCasUid),
    'reporterName': _str('Ana Gomez'),
    'title': _str('Projector will not turn on'),
    'description': _str(
      'The ceiling projector in the reading area shows no power light.',
    ),
    'category': _null(),
    'classifiedAutomatically': _bool(false),
    'requestorCategory': _str('electrical'),
    'facilityId': _str('fac-library-reading'),
    'facilityName': _str('Main Library'),
    'locationDescription': _str('Main Library, Reading Area'),
    'photoUrls': _strArray([]),
    'requestorPriority': _str('medium'),
    'status': _str('submitted'),
    'assetId': _null(),
    'coordinates': _null(),
    'severityRating': _null(),
    'safetyRiskRating': _null(),
    'frequencyRating': _null(),
    'locationImportanceRating': _null(),
    'priorityScore': _null(),
    'recommendedPriority': _null(),
    'officialPriority': _null(),
    'duplicateOf': _null(),
    'dismissedDuplicateIds': _strArray([]),
    'workOrderId': _null(),
    'reviewedBy': _null(),
    'reviewedAt': _null(),
    'rejectionReason': _null(),
    'submittedAt': _ago(const Duration(hours: 5)),
    'updatedAt': _now(),
  });
  await _writeStep(
    'rep-ana-0001',
    1,
    'submitted',
    _ago(const Duration(hours: 5)),
    changedBy: facultyCasUid,
    notify: (
      recipientId: facultyCasUid,
      reportTitle: 'Projector will not turn on',
      mergedInto: null,
    ),
  );

  // Objective 4.C: the same fan in Room 101, filed by somebody else three
  // hours ago. "short circuit" classifies it Electrical on the phone, and
  // it is flagged as a possible duplicate of rep-0001: the same facility
  // and damage type, filed within 72 hours.
  await _writeDoc('damage_reports', 'rep-ana-0002', {
    'reporterId': _str(facultyCasUid),
    'reporterName': _str('Ana Gomez'),
    'title': _str('Ceiling fan sparking in Room 101'),
    'description': _str(
      'The fan in Room 101 grinds and its switch gives off sparks. Could be '
      'a short circuit.',
    ),
    'category': _str('electrical'),
    'classifiedAutomatically': _bool(true),
    'requestorCategory': _str('electrical'),
    'facilityId': _str('fac-engineering'),
    'facilityName': _str('Engineering Building'),
    'locationDescription': _str('Engineering Building, Room 101'),
    'photoUrls': _strArray([]),
    'requestorPriority': _str('high'),
    'status': _str('submitted'),
    'assetId': _null(),
    'coordinates': _null(),
    'severityRating': _null(),
    'safetyRiskRating': _null(),
    'frequencyRating': _null(),
    'locationImportanceRating': _null(),
    'priorityScore': _null(),
    'recommendedPriority': _null(),
    'officialPriority': _null(),
    'duplicateOf': _null(),
    'dismissedDuplicateIds': _strArray([]),
    'workOrderId': _null(),
    'reviewedBy': _null(),
    'reviewedAt': _null(),
    'rejectionReason': _null(),
    'submittedAt': _ago(const Duration(hours: 3)),
    'updatedAt': _now(),
  });
  await _writeStep(
    'rep-ana-0002',
    1,
    'submitted',
    _ago(const Duration(hours: 3)),
    changedBy: facultyCasUid,
    notify: (
      recipientId: facultyCasUid,
      reportTitle: 'Ceiling fan sparking in Room 101',
      mergedInto: null,
    ),
  );

  stdout.writeln(
    '  damage_reports: ${_seededReports.length + 2} '
    '(3 approved and awaiting assignment, of which rep-0007 and the '
    'unclassified rep-0008 still need their type and priority reviewed; '
    '1 each rejected, merged and archived; 2 filed by another faculty '
    'member; 1 possible duplicate, rep-ana-0002 of rep-0001), each with '
    'its status history',
  );
}

/// The §3.4 formula with the weights Chris chose (Objective 4.B), rounded
/// to two decimals as the app's PriorityScorer rounds it.
double _scoreOf((int, int, int, int) ratings) {
  final (severity, safetyRisk, frequency, locationImportance) = ratings;
  final score =
      0.40 * severity +
      0.30 * safetyRisk +
      0.20 * frequency +
      0.10 * locationImportance;
  return (score * 100).roundToDouble() / 100;
}

/// Table 3.5's band for [score].
String _levelFor(double score) => switch (score) {
  >= 3.50 => 'critical',
  >= 2.50 => 'high',
  >= 1.50 => 'medium',
  _ => 'low',
};

/// The first part of a seeded report's timeline (Objective 3.B): filed,
/// reviewed, and the administrator's decision. Work-order stages are
/// appended by [_seedWorkOrders], numbered on from 4.
Future<void> _seedReviewTimeline(_SeededReport report) async {
  final filed = report.submittedHoursAgo;
  Map<String, Object?> at(double hoursAgo) =>
      _ago(Duration(minutes: (hoursAgo * 60).round()));
  final notify = _notifyOf(report);

  await _writeStep(
    report.id,
    1,
    'submitted',
    at(filed.toDouble()),
    changedBy: facultyUid,
    notify: notify,
  );
  if (report.status == 'submitted') return;

  await _writeStep(
    report.id,
    2,
    'underReview',
    at(filed - 0.5),
    notify: notify,
  );
  if (report.status == 'underReview') return;

  // The decision, at the report's reviewedAt.
  final decision = switch (report.status) {
    'rejected' || 'merged' || 'archived' => report.status,
    _ => 'approved',
  };
  await _writeStep(
    report.id,
    3,
    decision,
    at(filed - 1.0),
    note: report.rejectionReason,
    notify: notify,
  );
}

/// Who a seeded report's notifications go to, and what they name.
typedef _Notify = ({
  String recipientId,
  String reportTitle,
  String? mergedInto,
});

_Notify _notifyOf(_SeededReport report) => (
  recipientId: facultyUid,
  reportTitle: report.title,
  mergedInto: report.duplicateOf,
);

/// Notices older than this are seeded already read, so Alerts shows both
/// states, with unread ones in Today and Earlier alike.
const Duration _seededReadAfter = Duration(hours: 48);

/// Writes one status history entry the way the app's repositories do
/// (Objective 3.B) and, given [notify], the reporter's notification for it
/// when the move is one they are told of — in the app's own wording
/// (`ReportNotice`). Fixed ids, so a re-run overwrites rather than
/// doubling the timeline or the Alerts list.
Future<void> _writeStep(
  String reportId,
  int step,
  String status,
  Map<String, Object?> at, {
  String changedBy = adminUid,
  String? note,
  String? personnelUid,
  _Notify? notify,
}) async {
  final person = personnelUid == null ? null : _personnel[personnelUid];
  await _writeDoc('damage_reports/$reportId/status_history', 'h$step', {
    'status': _str(status),
    'changedAt': at,
    'changedBy': _str(changedBy),
    'note': note == null ? _null() : _str(note),
    'personnelName': person == null ? _null() : _str(person.$1),
    'personnelSpecialization': person == null ? _null() : _str(person.$2),
  });

  if (notify == null) return;
  final notice = ReportNotice.forMove(
    to: ReportStatus.fromId(status),
    reportTitle: notify.reportTitle,
    personnelName: person?.$1,
    reason: note,
    mergedInto: notify.mergedInto,
  );
  if (notice == null) return;

  final created = DateTime.parse(at['timestampValue']! as String);
  final isRead = DateTime.now().toUtc().difference(created) > _seededReadAfter;
  _notices++;
  await _writeDoc('notifications', 'nt-$reportId-h$step', {
    'recipientId': _str(notify.recipientId),
    'type': _str(notice.type.id),
    'title': _str(notice.title),
    'body': _str(notice.body),
    'relatedEntityType': _str('damage_reports'),
    'relatedEntityId': _str(reportId),
    'isRead': _bool(isRead),
    'readAt': isRead ? _at(created.add(const Duration(hours: 1))) : _null(),
    'createdAt': at,
  });
}

/// How many notifications [_writeStep] seeded, for the summary line.
var _notices = 0;

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
    // Done and waiting for the administrator's sign-off (3.B).
    (
      'wo-0009',
      'rep-0009',
      'structural',
      'medium',
      'forReview',
      personnelStructuralUid,
      96,
      24,
      false,
    ),
    // Objective 5: personnel@'s work not yet started.
    (
      'wo-0013',
      'rep-0013',
      'electrical',
      'high',
      'pending',
      personnelUid,
      6,
      24,
      false,
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

    // The rest of the report's timeline, after _seedReviewTimeline's three.
    final notify = _notifyOf(report);
    await _writeStep(
      reportId,
      4,
      'assigned',
      _ago(Duration(hours: createdHoursAgo)),
      personnelUid: assignee,
      notify: notify,
    );
    if (status == 'pending') continue;
    await _writeStep(
      reportId,
      5,
      'inProgress',
      _ago(Duration(hours: createdHoursAgo - 4)),
      notify: notify,
    );
    if (status == 'inProgress') continue;
    await _writeStep(
      reportId,
      6,
      'forReview',
      _ago(Duration(hours: isCompleted ? 5 : 6)),
      notify: notify,
    );
    if (status == 'forReview') continue;
    await _writeStep(
      reportId,
      7,
      'completed',
      _ago(const Duration(hours: 3)),
      notify: notify,
    );
  }

  stdout.writeln(
    '  work_orders: ${workOrders.length} (1 overdue, 1 awaiting sign-off, '
    '1 not yet started)',
  );
}

/// Objective 5: the personnel app's working day. personnel@ (Marcus
/// Wright) has wo-0003 under way, with a task done this morning, one in
/// progress and two more due today, another tomorrow, 4 LED bulbs recorded
/// as used and the multimeter out; wo-0013 waits to be started, with a
/// task due today that starts it when ticked. wo-0009 (Rosa Villanueva)
/// has its accomplishment report waiting for sign-off in the console, and
/// wo-0005 one signed off. Every work order's first task is the job itself,
/// as assignment now creates it.
Future<void> _seedPersonnelWork() async {
  final now = DateTime.now();
  DateTime today(int hour) => DateTime(now.year, now.month, now.day, hour);
  DateTime inDays(int days, int hour) =>
      DateTime(now.year, now.month, now.day + days, hour);

  final tasks = [
    (
      'task-0002-1',
      'wo-0002',
      'Leaking Pipe Under Sink',
      'Science Building',
      personnelPlumberUid,
      'pending',
      inDays(-1, 12),
      null,
      24,
    ),
    (
      'task-0003-1',
      'wo-0003',
      'Flickering Lights',
      'Main Library',
      personnelUid,
      'completed',
      today(9),
      2,
      48,
    ),
    (
      'task-0003-2',
      'wo-0003',
      'Replace the ballast in the study area fixtures',
      'The two fixtures over the study tables.',
      personnelUid,
      'inProgress',
      today(12),
      null,
      30,
    ),
    (
      'task-0003-3',
      'wo-0003',
      'Test every fixture on the circuit',
      null,
      personnelUid,
      'pending',
      today(15),
      null,
      30,
    ),
    (
      'task-0003-4',
      'wo-0003',
      'Label the breaker in the library panel',
      null,
      personnelUid,
      'pending',
      inDays(1, 10),
      null,
      30,
    ),
    (
      'task-0005-1',
      'wo-0005',
      'Cracked Wall Near Stairwell',
      'Engineering Building',
      personnelUid,
      'completed',
      inDays(-10, 12),
      6,
      240,
    ),
    (
      'task-0009-1',
      'wo-0009',
      'Loose Ceiling Panel',
      'Science Building',
      personnelStructuralUid,
      'completed',
      inDays(-3, 12),
      7,
      96,
    ),
    (
      'task-0013-1',
      'wo-0013',
      'Sparking Wall Outlet',
      'Administration Building',
      personnelUid,
      'pending',
      inDays(1, 12),
      null,
      6,
    ),
    (
      'task-0013-2',
      'wo-0013',
      'Switch off the circuit before opening the outlet',
      'The breaker is in the panel by the registrar office door.',
      personnelUid,
      'pending',
      today(17),
      null,
      5,
    ),
  ];

  for (final (
        id,
        workOrderId,
        title,
        description,
        assignee,
        status,
        due,
        completedHoursAgo,
        createdHoursAgo,
      )
      in tasks) {
    await _writeDoc('tasks', id, {
      'workOrderId': _str(workOrderId),
      'title': _str(title),
      'description': description == null ? _null() : _str(description),
      'assignedTo': _str(assignee),
      'status': _str(status),
      'dueDate': _at(due),
      'proofPhotoUrls': _strArray([]),
      'completedAt': completedHoursAgo == null
          ? _null()
          : _ago(Duration(hours: completedHoursAgo)),
      'createdAt': _ago(Duration(hours: createdHoursAgo)),
      'updatedAt': _now(),
    });
  }

  // Recorded on wo-0003 as used, deducted when its report is filed.
  await _writeDoc('work_orders/wo-0003/materials_used', 'inv-led-bulb', {
    'itemName': _str('LED Bulbs (60W Eq)'),
    'quantityUsed': _double(4),
    'unitOfMeasurement': _str('units'),
    'recordedBy': _str(personnelUid),
    'recordedAt': _ago(const Duration(hours: 3)),
  });

  // The multimeter is out with personnel@, for wo-0003.
  await _writeDoc('tool_loans', 'loan-0001', {
    'toolId': _str('tool-multimeter'),
    'toolName': _str('Fluke Multimeter 179'),
    'borrowedBy': _str(personnelUid),
    'workOrderId': _str('wo-0003'),
    'borrowedAt': _ago(const Duration(hours: 5)),
    'expectedReturnAt': _null(),
    'returnedAt': _null(),
    'conditionOnBorrow': _str('good'),
    'conditionOnReturn': _null(),
    'notes': _null(),
  });
  await _writeDoc('tools', 'tool-multimeter', {
    'toolCode': _str('TL-0912'),
    'name': _str('Fluke Multimeter 179'),
    'status': _str('borrowed'),
    'condition': _str('good'),
    'category': _str('Power Tools'),
    'storageLocation': _str('GSU Tool Crib'),
    'qrCode': _str('TOOL-TL-0912'),
    'currentHolderId': _str(personnelUid),
    'currentLoanId': _str('loan-0001'),
    'createdAt': _now(),
    'updatedAt': _now(),
  });

  // Accomplishment reports: wo-0005's signed off, wo-0009's waiting.
  final reports = [
    (
      'acc-0005',
      'wo-0005',
      personnelUid,
      'Patched and sealed the crack beside the west stairwell and repainted '
          'the section. The crack is in the plaster only; the wall behind '
          'it is sound.',
      5,
      true,
    ),
    (
      'acc-0009',
      'wo-0009',
      personnelStructuralUid,
      'Re-fixed the sagging ceiling panel with four new clips and checked '
          'the panels around it. It no longer moves when the lobby door '
          'slams.',
      6,
      false,
    ),
  ];
  for (final (id, workOrderId, by, notes, hoursAgo, reviewed) in reports) {
    await _writeDoc('accomplishment_reports', id, {
      'workOrderId': _str(workOrderId),
      'submittedBy': _str(by),
      'completionNotes': _str(notes),
      'photoUrls': _strArray([]),
      'materialsUsed': {
        'arrayValue': {'values': <Object?>[]},
      },
      'inventoryDeducted': _bool(false),
      'reviewedBy': reviewed ? _str(adminUid) : _null(),
      'reviewedAt': reviewed ? _ago(const Duration(hours: 3)) : _null(),
      'submittedAt': _ago(Duration(hours: hoursAgo)),
    });
  }

  // The technicians' own notices, in the app's wording.
  final notices = [
    (
      'nt-wo-0002',
      personnelPlumberUid,
      'wo-0002',
      PersonnelNotice.workOrderAssigned(
        workOrderTitle: 'Leaking Pipe Under Sink',
        facilityName: 'Science Building',
      ),
      24,
    ),
    (
      'nt-wo-0003',
      personnelUid,
      'wo-0003',
      PersonnelNotice.workOrderAssigned(
        workOrderTitle: 'Flickering Lights',
        facilityName: 'Main Library',
      ),
      48,
    ),
    (
      'nt-task-0003-2',
      personnelUid,
      'wo-0003',
      PersonnelNotice.taskAssigned(
        taskTitle: 'Replace the ballast in the study area fixtures',
        workOrderTitle: 'Flickering Lights',
      ),
      30,
    ),
    (
      'nt-wo-0013',
      personnelUid,
      'wo-0013',
      PersonnelNotice.workOrderAssigned(
        workOrderTitle: 'Sparking Wall Outlet',
        facilityName: 'Administration Building',
      ),
      6,
    ),
    (
      'nt-task-0013-2',
      personnelUid,
      'wo-0013',
      PersonnelNotice.taskAssigned(
        taskTitle: 'Switch off the circuit before opening the outlet',
        workOrderTitle: 'Sparking Wall Outlet',
      ),
      5,
    ),
    (
      'nt-wo-0009',
      personnelStructuralUid,
      'wo-0009',
      PersonnelNotice.workOrderAssigned(
        workOrderTitle: 'Loose Ceiling Panel',
        facilityName: 'Science Building',
      ),
      96,
    ),
  ];
  for (final (id, recipient, workOrderId, notice, hoursAgo) in notices) {
    final isRead = Duration(hours: hoursAgo) > _seededReadAfter;
    final created = DateTime.now().toUtc().subtract(Duration(hours: hoursAgo));
    _notices++;
    await _writeDoc('notifications', id, {
      'recipientId': _str(recipient),
      'type': _str(notice.type.id),
      'title': _str(notice.title),
      'body': _str(notice.body),
      'relatedEntityType': _str('work_orders'),
      'relatedEntityId': _str(workOrderId),
      'isRead': _bool(isRead),
      'readAt': isRead ? _at(created.add(const Duration(hours: 1))) : _null(),
      'createdAt': _at(created),
    });
  }

  stdout.writeln(
    '  personnel work: ${tasks.length} tasks, 1 material recorded, 1 tool '
    'out, 2 accomplishment reports (wo-0009 awaiting sign-off), '
    '${notices.length} technician notices',
  );
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
  var rated = 0;
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

      final steps = [
        ('submitted', submitted, facultyUid),
        ('underReview', submitted.add(const Duration(hours: 1)), adminUid),
        ('approved', submitted.add(const Duration(hours: 2)), adminUid),
        ('assigned', created, adminUid),
        ('inProgress', created.add(const Duration(hours: 2)), adminUid),
        ('forReview', completed.subtract(const Duration(hours: 2)), adminUid),
        ('completed', completed, adminUid),
        // Closed by the requestor's rating (Objective 3.C).
        if (monthsAgo > 0)
          ('closed', completed.add(const Duration(days: 1)), facultyUid),
      ];
      for (final (n, (status, moment, by)) in steps.indexed) {
        await _writeStep(
          reportId,
          n + 1,
          status,
          _at(moment),
          changedBy: by,
          personnelUid: status == 'assigned' ? assignee : null,
        );
      }

      // The rating that closed it, filed under the report's id as the app
      // files it. The three ratings vary independently (§1.5).
      if (monthsAgo > 0) {
        await _writeDoc('feedback', reportId, {
          'workOrderId': _str(workOrderId),
          'reportId': _str(reportId),
          'submittedBy': _str(facultyUid),
          'responseTimeRating': _int(const [4, 5, 3, 4, 2, 5, 4][seeded % 7]),
          'serviceQualityRating': _int(
            const [5, 4, 4, 5, 3, 5, 4][(seeded + 2) % 7],
          ),
          'overallSatisfactionRating': _int(
            const [4, 5, 4, 4, 3, 5, 5][(seeded + 4) % 7],
          ),
          'comments': switch (seeded % 3) {
            0 => _str('Fixed quickly and cleaned up after. Thank you.'),
            1 => _str('Good repair, but it took a while to get started.'),
            _ => _null(),
          },
          'submittedAt': _at(completed.add(const Duration(days: 1))),
        });
        rated++;
      }
      seeded++;
    }
  }

  stdout
    ..writeln('  history: $seeded resolved reports over six months')
    ..writeln(
      '  feedback: $rated ratings, one per closed report; '
      'rep-0005 is completed and still unrated',
    );
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
Map<String, Object?> _intArray(List<int> values) => {
  'arrayValue': {'values': values.map(_int).toList(growable: false)},
};
