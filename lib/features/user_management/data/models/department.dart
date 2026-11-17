import 'package:flutter/foundation.dart';

import '../../../../core/data/data_record.dart';
import '../../../../core/utils/record_converters.dart';

/// A department or faculty people belong to (2026-11-17): what faculty
/// and staff choose when they create an account, and what an account's
/// `department` names. Kept by the administrator in Settings.
@immutable
class Department {
  const Department({
    required this.id,
    required this.name,
    this.isActive = true,
  });

  factory Department.fromRecord(DataRecord record) => Department(
    id: record.id,
    name: RecordConverters.require<String>(record.fields, 'name'),
    isActive:
        RecordConverters.optional<bool>(record.fields, 'isActive') ?? true,
  );

  final String id;
  final String name;

  /// On the list for new choices. A retired one stays on the accounts
  /// that name it.
  final bool isActive;

  @override
  bool operator ==(Object other) =>
      other is Department &&
      other.id == id &&
      other.name == name &&
      other.isActive == isActive;

  @override
  int get hashCode => Object.hash(id, name, isActive);

  @override
  String toString() => 'Department($name${isActive ? '' : ', retired'})';
}
