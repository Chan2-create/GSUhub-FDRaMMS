/// Canonical photo paths, in the `photos` bucket (Objective 1).
///
/// Centralized for the same reason collection names are: a path typed by
/// hand in two places eventually diverges, and here a divergence means
/// uploads land somewhere the bucket's policies do not cover. These match
/// the folders in supabase/migrations/*_storage_policies.sql — change one
/// and you must change the other. The storage service files damage report,
/// accomplishment and task photos under the uploader's uid, which the
/// policies require, so the paths here do not carry it.
///
/// Lives beside `FirestorePaths` rather than inside the storage service so
/// a screen can name where its upload goes without importing a backend.
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

  /// A material's photo for its card on the Inventory page (Objective 6.A).
  static String inventoryPhoto(String itemId, String fileName) =>
      'inventory_items/$itemId/$fileName';

  /// Generated QR code image for a facility or asset.
  static String qrCode(String entityType, String entityId) =>
      'qr_codes/$entityType/$entityId.png';

  static String userProfileImage(String uid, String fileName) =>
      'users/$uid/$fileName';
}
