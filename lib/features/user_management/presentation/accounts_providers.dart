import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/repository_providers.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/utils/result.dart';
import '../data/models/app_user.dart';

/// Every account, live, sorted by name — the User Accounts table
/// (Objective 2.C).
final allAccountsProvider = StreamProvider<Result<List<AppUser>>>(
  (ref) => ref
      .watch(userRepositoryProvider)
      .watchAll()
      .map(
        (result) => result.map(
          (people) =>
              people.toList(growable: false)
                ..sort((a, b) => a.fullName.compareTo(b.fullName)),
        ),
      ),
);

/// The role tab, search and page on User Accounts (Figma `89:4626`).
///
/// The design has both tabs and an "All Roles" select. They are one
/// filter drawn twice, so they share this state: choosing a role in either
/// moves the other, and the two can never contradict each other into an
/// empty table.
class AccountsView {
  const AccountsView({
    this.role,
    this.search = '',
    this.page = 0,
    this.pageSize = 10,
  });

  /// Null is "All Users".
  final UserRole? role;
  final String search;

  /// Zero-based page index.
  final int page;
  final int pageSize;

  bool matches(AppUser person) {
    if (role != null && person.role != role) return false;
    final term = search.trim().toLowerCase();
    if (term.isEmpty) return true;
    return '${person.fullName} ${person.email}'.toLowerCase().contains(term);
  }
}

class AccountsViewController extends Notifier<AccountsView> {
  @override
  AccountsView build() => const AccountsView();

  void setRole(UserRole? role) => state = AccountsView(
    role: role,
    search: state.search,
    pageSize: state.pageSize,
  );

  void setSearch(String search) => state = AccountsView(
    role: state.role,
    search: search,
    pageSize: state.pageSize,
  );

  void setPage(int page) => state = AccountsView(
    role: state.role,
    search: state.search,
    page: page,
    pageSize: state.pageSize,
  );

  void setPageSize(int pageSize) => state = AccountsView(
    role: state.role,
    search: state.search,
    pageSize: pageSize,
  );
}

final accountsViewProvider =
    NotifierProvider<AccountsViewController, AccountsView>(
      AccountsViewController.new,
    );

final filteredAccountsProvider = Provider<AsyncValue<Result<List<AppUser>>>>((
  ref,
) {
  final view = ref.watch(accountsViewProvider);
  return ref
      .watch(allAccountsProvider)
      .whenData(
        (result) => result.map(
          (people) => people.where(view.matches).toList(growable: false),
        ),
      );
});

final accountsPageProvider = Provider<AsyncValue<Result<List<AppUser>>>>((ref) {
  final view = ref.watch(accountsViewProvider);
  return ref
      .watch(filteredAccountsProvider)
      .whenData(
        (result) => result.map((people) {
          final start = view.page * view.pageSize;
          if (start >= people.length) return const <AppUser>[];
          final end = (start + view.pageSize).clamp(0, people.length);
          return people.sublist(start, end);
        }),
      );
});
