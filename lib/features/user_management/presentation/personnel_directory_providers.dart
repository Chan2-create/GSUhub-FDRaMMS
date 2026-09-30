import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/damage_categories.dart';
import '../../../core/enums/account_status.dart';
import '../../../core/enums/personnel_availability.dart';
import '../../../core/utils/result.dart';
import '../data/models/app_user.dart';
import 'personnel_providers.dart';

/// A technician's status on the Personnel directory (Figma `200:4316`).
///
/// "Busy" is read from live workload — the active work orders 2.B's
/// assignment transactions count — rather than from the stored
/// `availability` field, which nothing keeps in step with the work and
/// which would otherwise drift. Leave is the one status a person's work
/// cannot reveal, so that alone is stored, and set by an administrator.
enum StaffStatus {
  available('Available'),
  busy('Busy'),
  onLeave('On leave');

  const StaffStatus(this.label);

  final String label;

  static StaffStatus of(AppUser person) {
    if (person.availability == PersonnelAvailability.onLeave) return onLeave;
    return person.activeTaskCount > 0 ? busy : available;
  }
}

/// Search, availability, trade and page on the Personnel directory.
class PersonnelDirectoryView {
  const PersonnelDirectoryView({
    this.search = '',
    this.status,
    this.trade,
    this.page = 0,
  });

  final String search;
  final StaffStatus? status;
  final DamageCategory? trade;

  /// Zero-based page index.
  final int page;

  static const int pageSize = 10;

  /// "Search by name or specialization", as the box says.
  bool matches(AppUser person) {
    if (status != null && StaffStatus.of(person) != status) return false;
    if (trade != null && person.specialization != trade) return false;
    final term = search.trim().toLowerCase();
    if (term.isEmpty) return true;
    final haystack = [
      person.fullName,
      person.specialization?.label ?? '',
      person.email,
    ].join(' ').toLowerCase();
    return haystack.contains(term);
  }
}

/// Every filter change returns to the first page, for the same reason as
/// the reports table: a filtered list of three while sitting on page four
/// would look empty.
class PersonnelDirectoryController extends Notifier<PersonnelDirectoryView> {
  @override
  PersonnelDirectoryView build() => const PersonnelDirectoryView();

  void setSearch(String value) => state = PersonnelDirectoryView(
    search: value,
    status: state.status,
    trade: state.trade,
  );

  void setStatus(StaffStatus? value) => state = PersonnelDirectoryView(
    search: state.search,
    status: value,
    trade: state.trade,
  );

  void setTrade(DamageCategory? value) => state = PersonnelDirectoryView(
    search: state.search,
    status: state.status,
    trade: value,
  );

  void setPage(int page) => state = PersonnelDirectoryView(
    search: state.search,
    status: state.status,
    trade: state.trade,
    page: page,
  );
}

final personnelDirectoryViewProvider =
    NotifierProvider<PersonnelDirectoryController, PersonnelDirectoryView>(
      PersonnelDirectoryController.new,
    );

/// Maintenance personnel whose accounts are active — the working roster.
/// Deactivated accounts are managed on User Accounts, not here: they can
/// take no work, and listing them would inflate TOTAL STAFF.
final activeStaffProvider = Provider<AsyncValue<Result<List<AppUser>>>>(
  (ref) => ref
      .watch(personnelStreamProvider)
      .whenData(
        (result) => result.map(
          (people) => people
              .where((person) => person.accountStatus == AccountStatus.active)
              .toList(growable: false),
        ),
      ),
);

final filteredStaffProvider = Provider<AsyncValue<Result<List<AppUser>>>>((
  ref,
) {
  final view = ref.watch(personnelDirectoryViewProvider);
  return ref
      .watch(activeStaffProvider)
      .whenData(
        (result) => result.map(
          (people) => people.where(view.matches).toList(growable: false),
        ),
      );
});

final staffPageProvider = Provider<AsyncValue<Result<List<AppUser>>>>((ref) {
  final view = ref.watch(personnelDirectoryViewProvider);
  return ref
      .watch(filteredStaffProvider)
      .whenData(
        (result) => result.map((people) {
          final start = view.page * PersonnelDirectoryView.pageSize;
          if (start >= people.length) return const <AppUser>[];
          final end = (start + PersonnelDirectoryView.pageSize).clamp(
            0,
            people.length,
          );
          return people.sublist(start, end);
        }),
      );
});

/// TOTAL STAFF, AVAILABLE NOW, ON TASK, ON LEAVE — over the whole roster,
/// not the filtered page.
class StaffStats {
  const StaffStats({
    required this.total,
    required this.available,
    required this.onTask,
    required this.onLeave,
  });

  factory StaffStats.from(List<AppUser> people) {
    var available = 0;
    var onTask = 0;
    var onLeave = 0;
    for (final person in people) {
      switch (StaffStatus.of(person)) {
        case StaffStatus.available:
          available++;
        case StaffStatus.busy:
          onTask++;
        case StaffStatus.onLeave:
          onLeave++;
      }
    }
    return StaffStats(
      total: people.length,
      available: available,
      onTask: onTask,
      onLeave: onLeave,
    );
  }

  final int total;
  final int available;
  final int onTask;
  final int onLeave;
}

final staffStatsProvider = Provider<AsyncValue<Result<StaffStats>>>(
  (ref) => ref
      .watch(activeStaffProvider)
      .whenData((result) => result.map(StaffStats.from)),
);
