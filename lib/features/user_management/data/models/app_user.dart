import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/damage_categories.dart';
import '../../../../core/enums/account_status.dart';
import '../../../../core/enums/personnel_availability.dart';
import '../../../../core/enums/user_role.dart';
import '../../../../core/utils/firestore_converters.dart';

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
    FirestoreConverters.validateNotBlank(fullName, 'fullName');
    FirestoreConverters.validateNotBlank(email, 'email');
    FirestoreConverters.validateNonNegative(activeTaskCount, 'activeTaskCount');
  }

  factory AppUser.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return AppUser(
      id: doc.id,
      fullName: FirestoreConverters.require<String>(data, 'fullName'),
      email: FirestoreConverters.require<String>(data, 'email'),
      role: FirestoreConverters.requireEnum(data, 'role', UserRole.fromId),
      accountStatus: FirestoreConverters.requireEnum(
        data,
        'accountStatus',
        AccountStatus.fromId,
      ),
      department: FirestoreConverters.optional<String>(data, 'department'),
      contactNumber: FirestoreConverters.optional<String>(
        data,
        'contactNumber',
      ),
      specialization: FirestoreConverters.optionalEnum(
        data,
        'specialization',
        DamageCategory.fromId,
      ),
      availability: FirestoreConverters.optionalEnum(
        data,
        'availability',
        PersonnelAvailability.fromId,
      ),
      activeTaskCount:
          FirestoreConverters.optional<int>(data, 'activeTaskCount') ?? 0,
      fcmToken: FirestoreConverters.optional<String>(data, 'fcmToken'),
      createdAt: FirestoreConverters.requireDate(data, 'createdAt'),
      updatedAt: FirestoreConverters.requireDate(data, 'updatedAt'),
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

  Map<String, dynamic> toFirestore() => {
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
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
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
