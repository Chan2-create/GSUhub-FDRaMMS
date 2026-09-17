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
const String firestoreHost = 'localhost:8080';
const String authHost = 'localhost:9099';

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
    'activeTaskCount': _int(0),
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

  stdout.writeln('  users: 4');
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

// --- damage reports ----------------------------------------------------

Future<void> _seedDamageReports() async {
  // Spread across categories, statuses and priorities so every filter in
  // the Admin dashboard has something to show.
  final reports = [
    (
      'rep-0001',
      'Broken Ceiling Fan',
      'Ceiling fan in Room 101 wobbles badly and makes a loud grinding '
          'noise. It looks like it could come loose.',
      'electrical',
      'fac-engineering',
      'Engineering Building',
      'high',
      'underReview',
    ),
    (
      'rep-0002',
      'Leaking Pipe Under Sink',
      'Water is pooling under the sink in Science Laboratory 3. The floor '
          'is slippery and it has been getting worse since yesterday.',
      'plumbing',
      'fac-science',
      'Science Building',
      'critical',
      'assigned',
    ),
    (
      'rep-0003',
      'Flickering Lights',
      'Lights in the library study area flicker constantly. Possibly a '
          'ballast issue.',
      'electrical',
      'fac-library',
      'Main Library',
      'medium',
      'inProgress',
    ),
    (
      'rep-0004',
      'Aircon Not Cooling',
      'The split-type aircon in the admin office runs but does not cool '
          'the room at all.',
      'airConditioning',
      'fac-admin',
      'Administration Building',
      'medium',
      'submitted',
    ),
    (
      'rep-0005',
      'Cracked Wall Near Stairwell',
      'A crack has appeared along the wall beside the west stairwell. It '
          'runs about a metre.',
      'structural',
      'fac-engineering',
      'Engineering Building',
      'high',
      'completed',
    ),
  ];

  for (final (
        id,
        title,
        description,
        category,
        facilityId,
        facilityName,
        priority,
        status,
      )
      in reports) {
    await _writeDoc('damage_reports', id, {
      'reporterId': _str(facultyUid),
      'reporterName': _str('Maria Santos'),
      'title': _str(title),
      'description': _str(description),
      'category': _str(category),
      'classifiedAutomatically': _bool(true),
      'facilityId': _str(facilityId),
      'facilityName': _str(facilityName),
      'locationDescription': _str(facilityName),
      'photoUrls': _strArray([]),
      'requestorPriority': _str(priority),
      'status': _str(status),
      // The four criterion ratings are deliberately absent: who populates
      // them is still an open question (docs/data_dictionary.md §2.2).
      'submittedAt': _now(),
      'updatedAt': _now(),
    });
  }

  stdout.writeln('  damage_reports: ${reports.length}');
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
Map<String, Object?> _now() => {
  'timestampValue': DateTime.now().toUtc().toIso8601String(),
};
Map<String, Object?> _map(Map<String, Object?> fields) => {
  'mapValue': {'fields': fields},
};
Map<String, Object?> _strArray(List<String> values) => {
  'arrayValue': {'values': values.map(_str).toList(growable: false)},
};
