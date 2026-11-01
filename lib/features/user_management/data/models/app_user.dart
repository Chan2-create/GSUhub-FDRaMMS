import '../../../../core/constants/damage_categories.dart';
import '../../../../core/data/data_record.dart';
import '../../../../core/enums/account_status.dart';
import '../../../../core/enums/personnel_availability.dart';
import '../../../../core/enums/user_role.dart';
import '../../../../core/utils/record_converters.dart';

/// A `users` document — an authorized account in one of the three roles
/// (manuscript §1.5 Scope: faculty/staff, GSU maintenance personnel, GSU
/// Administrators; students are never authorized).
///
/// Named `AppUser` rather than `User` to avoid colliding with
/// `firebase_auth`'s `User` once 1.C wires authentication up. This is the
/// full profile document; `AuthService`'s `AuthUser` (from 1.A) is the
/// thin identity subset used for routing.
///
/// Personnel-only fields ([specialization], [availability],
/// [activeTaskCount]) come from the Admin "Maintenance Personnel" screen
/// (manuscript Figure 17) and are null/zero for other roles.
class AppUser {
  AppUser({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.accountStatus,
    required this.createdAt,
    required this.updatedAt,
    this.department,
    this.contactNumber,
    this.specialization,
    this.availability,
    this.activeTaskCount = 0,
    this.fcmToken,
  }) {
    RecordConverters.validateNotBlank(fullName, 'fullName');
    RecordConverters.validateNotBlank(email, 'email');
    RecordConverters.validateNonNegative(activeTaskCount, 'activeTaskCount');
  }

  factory AppUser.fromRecord(DataRecord record) {
    final data = record.fields;
    return AppUser(
      id: record.id,
      fullName: RecordConverters.require<String>(data, 'fullName'),
      email: RecordConverters.require<String>(data, 'email'),
      role: RecordConverters.requireEnum(data, 'role', UserRole.fromId),
      accountStatus: RecordConverters.requireEnum(
        data,
        'accountStatus',
        AccountStatus.fromId,
      ),
      department: RecordConverters.optional<String>(data, 'department'),
      contactNumber: RecordConverters.optional<String>(data, 'contactNumber'),
      specialization: RecordConverters.optionalEnum(
        data,
        'specialization',
        DamageCategory.fromId,
      ),
      availability: RecordConverters.optionalEnum(
        data,
        'availability',
        PersonnelAvailability.fromId,
      ),
      activeTaskCount:
          RecordConverters.optional<int>(data, 'activeTaskCount') ?? 0,
      fcmToken: RecordConverters.optional<String>(data, 'fcmToken'),
      createdAt: RecordConverters.requireDate(data, 'createdAt'),
      updatedAt: RecordConverters.requireDate(data, 'updatedAt'),
    );
  }

  /// Firestore document id, equal to the Firebase Auth uid.
  final String id;

  final String fullName;
  final String email;
  final UserRole role;
  final AccountStatus accountStatus;

  /// DERIVED — not named in the manuscript; useful for routing reports to
  /// the right office and for reporting. See docs/data_dictionary.md.
  final String? department;

  /// DERIVED — the manuscript shows a "CONTACT INFO" column (Figure 17)
  /// but only ever populates it with an email address.
  final String? contactNumber;

  /// Maintenance personnel only — the damage category this technician
  /// handles (Figure 17 "SPECIALIZATION"). Drives assignment suggestions.
  final DamageCategory? specialization;

  /// Maintenance personnel only (Figure 17 "STATUS").
  final PersonnelAvailability? availability;

  /// DENORMALIZED from `tasks` — count of this person's non-completed
  /// tasks, shown in the Admin personnel list (Figure 17 "ACTIVE TASKS")
  /// so that screen doesn't need a per-row subquery. Written by whatever
  /// assigns or completes a task; see docs/data_dictionary.md.
  final int activeTaskCount;

  /// Firebase Cloud Messaging device token for push delivery. DERIVED —
  /// implied by the push-notification requirement (§1.5) rather than
  /// stated as a field.
  final String? fcmToken;

  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toFields() => {
    'fullName': fullName,
    'email': email,
    'role': role.id,
    'accountStatus': accountStatus.id,
    'department': department,
    'contactNumber': contactNumber,
    'specialization': specialization?.id,
    'availability': availability?.id,
    'activeTaskCount': activeTaskCount,
    'fcmToken': fcmToken,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };

  AppUser copyWith({
    String? id,
    String? fullName,
    String? email,
    UserRole? role,
    AccountStatus? accountStatus,
    String? department,
    String? contactNumber,
    DamageCategory? specialization,
    PersonnelAvailability? availability,
    int? activeTaskCount,
    String? fcmToken,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => AppUser(
    id: id ?? this.id,
    fullName: fullName ?? this.fullName,
    email: email ?? this.email,
    role: role ?? this.role,
    accountStatus: accountStatus ?? this.accountStatus,
    department: department ?? this.department,
    contactNumber: contactNumber ?? this.contactNumber,
    specialization: specialization ?? this.specialization,
    availability: availability ?? this.availability,
    activeTaskCount: activeTaskCount ?? this.activeTaskCount,
    fcmToken: fcmToken ?? this.fcmToken,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppUser &&
          other.id == id &&
          other.fullName == fullName &&
          other.email == email &&
          other.role == role &&
          other.accountStatus == accountStatus &&
          other.department == department &&
          other.contactNumber == contactNumber &&
          other.specialization == specialization &&
          other.availability == availability &&
          other.activeTaskCount == activeTaskCount &&
          other.fcmToken == fcmToken &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    fullName,
    email,
    role,
    accountStatus,
    department,
    contactNumber,
    specialization,
    availability,
    activeTaskCount,
    fcmToken,
    createdAt,
    updatedAt,
  );

  @override
  String toString() =>
      'AppUser(id: $id, fullName: $fullName, email: $email, role: $role, '
      'accountStatus: $accountStatus)';
}
