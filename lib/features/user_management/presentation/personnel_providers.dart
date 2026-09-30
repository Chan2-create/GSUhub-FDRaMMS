import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/damage_categories.dart';
import '../../../core/di/repository_providers.dart';
import '../../../core/enums/account_status.dart';
import '../../../core/utils/result.dart';
import '../data/models/app_user.dart';

/// Every maintenance-personnel account, live.
///
/// Sorted here rather than in the query: ordering by name alongside the
/// role filter would need a composite index for a list this small.
final personnelStreamProvider = StreamProvider<Result<List<AppUser>>>(
  (ref) => ref
      .watch(userRepositoryProvider)
      .watchPersonnel()
      .map(
        (result) => result.map(
          (people) =>
              people.toList(growable: false)
                ..sort((a, b) => a.fullName.compareTo(b.fullName)),
        ),
      ),
);

/// Personnel names by id, for showing an assignee on a work-order card
/// without a lookup per card.
final personnelNamesProvider = Provider<Map<String, String>>(
  (ref) =>
      ref
          .watch(personnelStreamProvider)
          .value
          ?.fold(
            (people) => {
              for (final person in people) person.id: person.fullName,
            },
            (_) => const {},
          ) ??
      const {},
);

/// Ranks personnel for assigning [category]: the matching trade first,
/// then by how much work each already carries.
///
/// A sort, not a filter. The manuscript routes a category to a trade, but
/// the administrator keeps the final say — hiding everyone else would take
/// that away on the day the only electrician is on leave.
List<AppUser> rankedForCategory(
  List<AppUser> people,
  DamageCategory? category,
) {
  final ranked = people.toList();
  ranked.sort((a, b) {
    final aMatches = _matches(a, category);
    final bMatches = _matches(b, category);
    if (aMatches != bMatches) return aMatches ? -1 : 1;

    final aActive = a.accountStatus == AccountStatus.active;
    final bActive = b.accountStatus == AccountStatus.active;
    if (aActive != bActive) return aActive ? -1 : 1;

    if (a.activeTaskCount != b.activeTaskCount) {
      return a.activeTaskCount.compareTo(b.activeTaskCount);
    }
    return a.fullName.compareTo(b.fullName);
  });
  return ranked;
}

/// Trades are compared by the personnel label rather than the category, so
/// that carpentry and structural work — which the manuscript routes to the
/// same "Structural Maintenance Personnel" — count as a match.
bool _matches(AppUser person, DamageCategory? category) {
  final specialization = person.specialization;
  if (category == null || specialization == null) return false;
  return specialization.assignedPersonnelLabel ==
      category.assignedPersonnelLabel;
}
