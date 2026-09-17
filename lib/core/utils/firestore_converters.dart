import 'package:cloud_firestore/cloud_firestore.dart';

import '../errors/exceptions.dart';

/// Shared read/validate helpers for model `fromFirestore` converters.
///
/// Firestore hands back `Map<String, dynamic>`, so every field read is an
/// unchecked cast waiting to happen. These helpers centralize that risk:
/// a malformed or missing field throws a [ValidationException] naming the
/// field, instead of a bare `TypeError` somewhere up the stack with no
/// indication of which document is bad.
abstract final class FirestoreConverters {
  /// Reads a required field of type [T], throwing if absent or wrongly
  /// typed.
  static T require<T>(Map<String, dynamic> data, String field) {
    final value = data[field];
    if (value == null) {
      throw ValidationException('Missing required field "$field"');
    }
    if (value is! T) {
      throw ValidationException(
        'Field "$field" expected $T but was ${value.runtimeType}',
      );
    }
    return value;
  }

  /// Reads an optional field of type [T], returning `null` when absent.
  /// Still throws if present but wrongly typed — a wrong type is a data
  /// defect, not an absent value.
  static T? optional<T>(Map<String, dynamic> data, String field) {
    final value = data[field];
    if (value == null) return null;
    if (value is! T) {
      throw ValidationException(
        'Field "$field" expected $T? but was ${value.runtimeType}',
      );
    }
    return value;
  }

  /// Reads a required `Timestamp` field as a **UTC** [DateTime].
  ///
  /// `Timestamp.toDate()` returns a local-zone `DateTime`. Every model
  /// normalizes to UTC on the way in, for two reasons: Dart's `DateTime`
  /// equality compares the UTC flag as well as the instant, so a
  /// local/UTC mismatch makes two identical moments compare unequal; and
  /// maintenance timestamps that silently shift meaning with the device's
  /// timezone are a bug waiting to happen in a system that reports on
  /// response times.
  static DateTime requireDate(Map<String, dynamic> data, String field) =>
      require<Timestamp>(data, field).toDate().toUtc();

  /// Reads an optional `Timestamp` field as a **UTC** [DateTime]. See
  /// [requireDate] for why UTC.
  static DateTime? optionalDate(Map<String, dynamic> data, String field) =>
      optional<Timestamp>(data, field)?.toDate().toUtc();

  /// Reads a list-of-strings field, treating absence as an empty list —
  /// an empty photo list and a missing photo list mean the same thing.
  static List<String> stringList(Map<String, dynamic> data, String field) {
    final value = data[field];
    if (value == null) return const [];
    if (value is! List) {
      throw ValidationException(
        'Field "$field" expected List but was ${value.runtimeType}',
      );
    }
    return value.map((element) => element.toString()).toList(growable: false);
  }

  /// Reads a required enum field via its `fromId` resolver, rethrowing an
  /// unknown value as a [ValidationException] naming the field.
  static T requireEnum<T>(
    Map<String, dynamic> data,
    String field,
    T Function(String id) fromId,
  ) {
    final raw = require<String>(data, field);
    try {
      return fromId(raw);
    } on ArgumentError {
      throw ValidationException('Field "$field" has unknown value "$raw"');
    }
  }

  /// Reads an optional enum field via its `fromId` resolver.
  static T? optionalEnum<T>(
    Map<String, dynamic> data,
    String field,
    T Function(String id) fromId,
  ) {
    final raw = optional<String>(data, field);
    if (raw == null) return null;
    try {
      return fromId(raw);
    } on ValidationException {
      rethrow;
    } on ArgumentError {
      throw ValidationException('Field "$field" has unknown value "$raw"');
    }
  }

  /// Throws unless [value] falls within [min]..[max] inclusive.
  static void validateRange(num value, num min, num max, String field) {
    if (value < min || value > max) {
      throw ValidationException(
        'Field "$field" must be between $min and $max (was $value)',
      );
    }
  }

  /// Throws unless [value] is zero or greater.
  static void validateNonNegative(num value, String field) {
    if (value < 0) {
      throw ValidationException(
        'Field "$field" must not be negative (was $value)',
      );
    }
  }

  /// Throws unless [value] contains a non-whitespace character.
  static void validateNotBlank(String value, String field) {
    if (value.trim().isEmpty) {
      throw ValidationException('Field "$field" must not be blank');
    }
  }
}
