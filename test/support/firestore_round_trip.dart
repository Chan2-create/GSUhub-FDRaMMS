import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:gsuhub/core/data/data_record.dart';

import 'firestore_backend/core/data/firestore_records.dart';

/// Writes [fields] into an in-memory Firestore and reads them back as the
/// [DataRecord] a model's `fromRecord` takes.
///
/// The models are backend-neutral (Objective 7.A), so the round trip
/// proves two things at once: a model's `toFields` and `fromRecord` agree,
/// and the test harness's Firestore backend stores and returns them
/// faithfully, `Timestamp` and `GeoPoint` included.
Future<DataRecord> roundTrip(
  String collection,
  String id,
  Map<String, dynamic> fields,
) async {
  final firestore = FakeFirebaseFirestore();
  final reference = firestore.collection(collection).doc(id);
  await reference.set(fields.forFirestore);
  return firestoreRecord(await reference.get());
}
