import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

/// Writes [data] into an in-memory Firestore and reads it back as a real
/// [DocumentSnapshot], so model `fromFirestore` converters can be
/// round-trip tested without touching a live project — which this
/// objective (1.B) deliberately does not have.
///
/// `DocumentSnapshot` is a sealed class and cannot be hand-faked, and
/// going through a real (if in-memory) Firestore is the better test
/// anyway: it exercises the actual `Timestamp` and `GeoPoint` marshalling
/// a deployed app would hit, rather than a hand-written approximation of
/// it.
Future<DocumentSnapshot<Map<String, dynamic>>> roundTrip(
  String collection,
  String id,
  Map<String, dynamic> data,
) async {
  final firestore = FakeFirebaseFirestore();
  final reference = firestore.collection(collection).doc(id);
  await reference.set(data);
  return reference.get();
}
