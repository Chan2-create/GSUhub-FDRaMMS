import '../../../../core/constants/damage_categories.dart';
import '../../../../core/enums/priority_level.dart';
import '../../../../core/services/location_service.dart';
import '../../../audit/data/models/audit_actor.dart';

/// What a requestor files from the mobile report form (Objective 3.C) —
/// the fields they supply, and nothing an administrator decides.
///
/// Separate from `DamageReport` for two reasons. A report carries a dozen
/// fields that are the administrator's to set (classification, official
/// priority, review), and a type that cannot express them cannot pre-set
/// them. And a report stores its geo-tag as Firestore's `GeoPoint`, which
/// the form must not import; this carries plain [GeoCoordinates], and the
/// repository converts.
class ReportSubmission {
  const ReportSubmission({
    required this.reporter,
    required this.title,
    required this.description,
    required this.requestorPriority,
    required this.facilityId,
    required this.facilityName,
    this.requestorCategory,
    this.locationDescription,
    this.assetId,
    this.coordinates,
    this.photoUrls = const [],
  });

  /// Who is filing, as the report and its audit entry should name them.
  final AuditActor reporter;

  final String title;
  final String description;

  /// The requestor's own sense of urgency (§1.2) — supplementary only.
  final PriorityLevel requestorPriority;

  /// The damage type the requestor suggested, if any — never the report's
  /// category, which the classifier or an Administrator decides.
  final DamageCategory? requestorCategory;

  final String facilityId;

  /// The facility's display name, denormalized onto the report.
  final String facilityName;

  /// Wayfinding detail — the building and room.
  final String? locationDescription;

  /// Set when the requestor scanned an asset's QR code rather than a
  /// facility's.
  final String? assetId;

  /// The device's position at submission. Optional: §2.2 makes the geo-tag
  /// supplementary to the location the requestor names.
  final GeoCoordinates? coordinates;

  /// Download URLs of photos already uploaded under
  /// `damage_reports/{reportId}/`.
  final List<String> photoUrls;
}
