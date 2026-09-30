import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/repository_providers.dart';
import '../../../core/utils/result.dart';
import '../data/models/facility.dart';

/// Every active facility, grouped the way the report form asks for one:
/// a building, then a room in it (Objective 3.C).
///
/// Facilities are building-and-room pairs (`Facility.buildingName` plus
/// `roomIdentifier`), so the buildings are derived from them rather than
/// stored separately.
class FacilityDirectory {
  FacilityDirectory(Iterable<Facility> facilities)
    : _byBuilding = _group(facilities);

  final Map<String, List<Facility>> _byBuilding;

  /// Building names, alphabetical.
  List<String> get buildings => _byBuilding.keys.toList(growable: false);

  /// The facilities in [building], in room order. Empty for a building the
  /// directory does not know.
  List<Facility> roomsIn(String building) =>
      _byBuilding[building] ?? const <Facility>[];

  bool get isEmpty => _byBuilding.isEmpty;

  /// How a facility reads in the Room select: its room, or — for a
  /// facility that is a whole building or an outdoor area, with no room —
  /// its own name.
  static String roomLabelOf(Facility facility) =>
      facility.roomIdentifier ?? facility.name;

  static Map<String, List<Facility>> _group(Iterable<Facility> facilities) {
    final grouped = <String, List<Facility>>{};
    for (final facility in facilities) {
      if (!facility.isActive) continue;
      (grouped[facility.buildingName] ??= []).add(facility);
    }
    final buildings = grouped.keys.toList()..sort(_byName);
    return {
      for (final building in buildings)
        building: grouped[building]!
          ..sort((a, b) => _byName(roomLabelOf(a), roomLabelOf(b))),
    };
  }

  /// Case-insensitive, with runs of digits compared as numbers, so
  /// "Room 9" sorts before "Room 10".
  static int _byName(String a, String b) {
    final pattern = RegExp(r'(\d+)|(\D+)');
    final left = pattern.allMatches(a.toLowerCase()).toList();
    final right = pattern.allMatches(b.toLowerCase()).toList();
    for (var i = 0; i < left.length && i < right.length; i++) {
      final x = left[i].group(0)!;
      final y = right[i].group(0)!;
      final xNumber = int.tryParse(x);
      final yNumber = int.tryParse(y);
      final order = xNumber != null && yNumber != null
          ? xNumber.compareTo(yNumber)
          : x.compareTo(y);
      if (order != 0) return order;
    }
    return left.length.compareTo(right.length);
  }
}

/// The active facilities, read once per visit to the report form.
///
/// A one-off read rather than a live stream: the facility registry
/// changes when GSU adds a building, not while someone is filling in a
/// form, and a listener per open form would be paid for in reads.
final facilityDirectoryProvider =
    FutureProvider.autoDispose<Result<FacilityDirectory>>(
      (ref) async =>
          (await ref.watch(facilityRepositoryProvider).getFacilities()).map(
            FacilityDirectory.new,
          ),
    );
