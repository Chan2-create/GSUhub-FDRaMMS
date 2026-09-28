/// Canonical Cloud Storage paths.
///
/// Centralized for the same reason collection names are: a path typed by
/// hand in two places eventually diverges, and here a divergence means
/// uploads land somewhere the security rules do not cover. These mirror
/// the `match` blocks in `firebase/storage.rules` exactly — change one and
/// you must change the other.
///
/// Lives beside `FirestorePaths` rather than inside the Firebase storage
/// service so a screen can name where its upload goes without importing a
/// file that imports Firebase.
abstract final class StoragePaths {
  /// Photo evidence attached to a damage report (manuscript §1.5).
  static String damageReportPhoto(String reportId, String fileName) =>
      'damage_reports/$reportId/$fileName';

  /// Photo documentation of completed maintenance.
  static String accomplishmentPhoto(String reportId, String fileName) =>
      'accomplishment_reports/$reportId/$fileName';

  /// Per-task proof of work (Figure 24, "Upload Proof").
  static String taskProofPhoto(String taskId, String fileName) =>
      'tasks/$taskId/$fileName';

  /// Generated QR code image for a facility or asset.
  static String qrCode(String entityType, String entityId) =>
      'qr_codes/$entityType/$entityId.png';

  static String userProfileImage(String uid, String fileName) =>
      'users/$uid/$fileName';
}
