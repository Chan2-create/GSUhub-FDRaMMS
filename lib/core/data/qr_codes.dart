import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/firestore_paths.dart';

/// The collections whose documents carry a printed code (§3.4): one
/// scanner reads them all, so a code may belong to one thing only.
const List<String> _labelled = [
  FirestorePaths.inventoryItems,
  FirestorePaths.tools,
  FirestorePaths.facilities,
  FirestorePaths.assets,
];

/// What already carries [code], as "a material", "a tool", "a room" or
/// "equipment", or null when nothing does. [exceptId] is the document
/// being edited, which may keep its own code.
///
/// Read outside the write that saves the code: Firestore transactions
/// cannot run queries. Two administrators saving the same new code in the
/// same second could both pass; acceptable at GSU's scale.
Future<String?> qrCodeOwner(
  FirebaseFirestore firestore,
  String code, {
  String? exceptId,
}) async {
  for (final path in _labelled) {
    final matches = await firestore
        .collection(path)
        .where('qrCode', isEqualTo: code)
        .limit(2)
        .get();
    if (matches.docs.any((doc) => doc.id != exceptId)) {
      return switch (path) {
        FirestorePaths.inventoryItems => 'a material',
        FirestorePaths.tools => 'a tool',
        FirestorePaths.facilities => 'a room',
        _ => 'equipment',
      };
    }
  }
  return null;
}
