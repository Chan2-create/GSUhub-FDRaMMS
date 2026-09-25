import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/di/service_providers.dart';
import '../../../core/enums/account_status.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/filter_select.dart';
import '../../../core/widgets/table_pagination.dart';
import '../data/models/app_user.dart';
import 'accounts_providers.dart';
import 'widgets/account_dialogs.dart';

/// User Accounts (Figma node `89:4626`, content area only).
///
/// The one User Accounts frame that is not an obsolete "DOrSUMaintain"
/// design comes from an earlier HTML-import pass with its own sidebar and
/// top bar. Its content is built here inside the admin shell, set in the
/// app's type and colours (decided for 2.C). Two things are left out
/// deliberately:
///
/// - the row checkboxes — the frame draws no bulk action for a selection
///   to feed, and a checkbox that does nothing is decoration;
/// - the narrow NAME column that wraps every name onto two lines, an
///   artifact of the import's table layout rather than a choice.
class UserAccountsScreen extends ConsumerWidget {
  const UserAccountsScreen({super.key});

  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) => const SingleChildScrollView(
    padding: EdgeInsets.all(32),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('User Accounts', style: AppTextStyles.pageTitle),
        SizedBox(height: 12),
        Text(
          'Manage university personnel access levels and system permissions.',
          style: AppTextStyles.pageSubtitle,
        ),
        SizedBox(height: 24),
        _RoleTabs(),
        SizedBox(height: 24),
        _ActionBar(),
        SizedBox(height: 24),
        _AccountsTable(),
        SizedBox(height: 48),
        _RoleLegend(),
      ],
    ),
  );
}

/// All Users / End Users / Maintenance Personnel / Administrators.
class _RoleTabs extends ConsumerWidget {
  const _RoleTabs();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(accountsViewProvider).role;
    final controller = ref.read(accountsViewProvider.notifier);

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderStrong)),
      ),
      child: Row(
        children: [
          _Tab(
            label: 'All Users',
            selected: role == null,
            onTap: () => controller.setRole(null),
          ),
          for (final option in UserRole.values) ...[
            const SizedBox(width: 64),
            _Tab(
              label: option.tabLabel,
              selected: role == option,
              onTap: () => controller.setRole(option),
            ),
          ],
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: InkWell(
      onTap: selected ? null : onTap,
      child: Container(
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? AppColors.primary : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Text(
          label,
          style: selected ? AppTextStyles.tabActive : AppTextStyles.tabInactive,
        ),
      ),
    ),
  );
}

/// Search, the role select, and Create Maintenance Account.
class _ActionBar extends ConsumerStatefulWidget {
  const _ActionBar();

  @override
  ConsumerState<_ActionBar> createState() => _ActionBarState();
}

class _ActionBarState extends ConsumerState<_ActionBar> {
  late final TextEditingController _search = TextEditingController(
    text: ref.read(accountsViewProvider).search,
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(accountsViewProvider).role;
    final controller = ref.read(accountsViewProvider.notifier);

    return Wrap(
      spacing: 24,
      runSpacing: 16,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 448,
              child: TextField(
                controller: _search,
                onChanged: controller.setSearch,
                style: AppTextStyles.accountsControlText,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search by name or email...',
                  hintStyle: AppTextStyles.accountsControlText.copyWith(
                    color: AppColors.textMuted,
                  ),
                  filled: true,
                  fillColor: AppColors.surface,
                  prefixIcon: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 11, 0),
                    child: SvgPicture.asset(
                      'assets/icons/search.svg',
                      width: 18,
                      height: 18,
                      colorFilter: const ColorFilter.mode(
                        AppColors.iconMuted,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 41),
                  contentPadding: const EdgeInsets.symmetric(vertical: 11),
                  border: _border,
                  enabledBorder: _border,
                ),
              ),
            ),
            const SizedBox(width: 24),
            FilterSelect<UserRole>(
              placeholder: 'All Roles',
              style: FilterSelectStyle.outlined,
              width: 148,
              value: role,
              onChanged: controller.setRole,
              options: [
                const FilterOption(value: null, label: 'All Roles'),
                for (final option in UserRole.values)
                  FilterOption(value: option, label: option.label),
              ],
            ),
          ],
        ),
        FilledButton.icon(
          onPressed: () => showCreateAccountDialog(context),
          icon: const Icon(Icons.add, size: 14),
          label: const Text(
            'Create Maintenance Account',
            style: AppTextStyles.accountsButton,
          ),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.textOnDark,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ],
    );
  }

  static final OutlineInputBorder _border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(4),
    borderSide: const BorderSide(color: AppColors.borderStrong),
  );
}

/// Column shares, widened at NAME from the design's (see the class note).
const List<int> _columns = [190, 220, 150, 160, 140, 110, 80];

class _AccountsTable extends ConsumerWidget {
  const _AccountsTable();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(accountsViewProvider);
    final page = ref.watch(accountsPageProvider);
    final total =
        ref
            .watch(filteredAccountsProvider)
            .value
            ?.fold((p) => p.length, (_) => 0) ??
        0;
    final signedIn = ref.watch(authStateProvider).value?.uid;
    final controller = ref.read(accountsViewProvider.notifier);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.borderStrong),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            height: 72,
            color: AppColors.tableStripe,
            child: const Row(
              children: [
                _HeaderCell('NAME', column: 0),
                _HeaderCell('EMAIL', column: 1),
                _HeaderCell('ROLE', column: 2),
                _HeaderCell('DEPARTMENT', column: 3),
                _HeaderCell('DATE REGISTERED', column: 4),
                _HeaderCell('STATUS', column: 5),
                _HeaderCell('ACTIONS', column: 6),
              ],
            ),
          ),
          AsyncValueView<List<AppUser>>(
            value: page,
            isEmpty: (people) => people.isEmpty,
            emptyIcon: Icons.person_search_outlined,
            emptyMessage: view.search.trim().isNotEmpty || view.role != null
                ? 'No accounts match these filters.'
                : 'No accounts yet.',
            onRetry: () => ref.invalidate(allAccountsProvider),
            data: (people) => Column(
              children: [
                for (final person in people)
                  _AccountRow(person: person, isSelf: person.id == signedIn),
              ],
            ),
          ),
          TablePagination(
            style: TablePaginationStyle.full,
            itemNoun: 'users',
            page: view.page,
            pageSize: view.pageSize,
            totalItems: total,
            onPageChanged: controller.setPage,
            onPageSizeChanged: controller.setPageSize,
          ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.text, {required this.column});

  final String text;
  final int column;

  @override
  Widget build(BuildContext context) => Expanded(
    flex: _columns[column],
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Text(text, style: AppTextStyles.accountsHeader),
    ),
  );
}

class _AccountRow extends ConsumerWidget {
  const _AccountRow({required this.person, required this.isSelf});

  final AppUser person;
  final bool isSelf;

  static final DateFormat _date = DateFormat('MMM d, y');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inactive = person.accountStatus == AccountStatus.inactive;
    final text = AppTextStyles.accountCell.copyWith(
      color: inactive ? AppColors.inactiveForeground : null,
    );

    return Container(
      decoration: BoxDecoration(
        color: inactive ? AppColors.inactiveRowBackground : AppColors.surface,
        border: const Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          _cell(
            0,
            Text(
              isSelf ? '${person.fullName} (you)' : person.fullName,
              style: AppTextStyles.accountName.copyWith(
                color: inactive ? AppColors.inactiveForeground : null,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _cell(
            1,
            Text(
              person.email,
              style: text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _cell(2, _RoleChip(role: person.role, inactive: inactive)),
          _cell(
            3,
            Text(
              person.department ?? '—',
              style: text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _cell(4, Text(_date.format(person.createdAt.toLocal()), style: text)),
          _cell(5, _StatusLabel(inactive: inactive)),
          _cell(6, _RowMenu(person: person, isSelf: isSelf)),
        ],
      ),
    );
  }

  static Widget _cell(int column, Widget child) => Expanded(
    flex: _columns[column],
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Align(alignment: Alignment.centerLeft, child: child),
    ),
  );
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role, required this.inactive});

  final UserRole role;
  final bool inactive;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = inactive
        ? (AppColors.inactiveChipBackground, AppColors.inactiveForeground)
        : switch (role) {
            UserRole.requestor => (
              AppColors.roleRequestorBackground,
              AppColors.roleRequestorForeground,
            ),
            UserRole.maintenancePersonnel => (
              AppColors.roleMaintenanceBackground,
              AppColors.roleMaintenanceForeground,
            ),
            UserRole.admin => (
              AppColors.roleAdminBackground,
              AppColors.roleAdminForeground,
            ),
          };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Text(
        role.label.toUpperCase(),
        style: AppTextStyles.roleChip.copyWith(color: foreground),
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.inactive});

  final bool inactive;

  @override
  Widget build(BuildContext context) {
    final color = inactive
        ? AppColors.inactiveForeground
        : AppColors.accountActive;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          inactive ? 'INACTIVE' : 'ACTIVE',
          style: AppTextStyles.roleChip.copyWith(color: color),
        ),
      ],
    );
  }
}

enum _RowAction { edit, toggleStatus, resetPassword }

/// Edit details, Deactivate/Reactivate, Send password reset (decided for
/// 2.C; the frame draws the ⋮ but not its contents).
class _RowMenu extends ConsumerWidget {
  const _RowMenu({required this.person, required this.isSelf});

  final AppUser person;
  final bool isSelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = person.accountStatus == AccountStatus.active;
    return PopupMenuButton<_RowAction>(
      tooltip: 'Account actions',
      icon: const Icon(Icons.more_vert, size: 20, color: AppColors.iconMuted),
      onSelected: (action) => switch (action) {
        _RowAction.edit => showEditAccountDialog(
          context,
          person: person,
          isSelf: isSelf,
        ),
        _RowAction.toggleStatus => confirmStatusChange(
          context,
          ref,
          person: person,
        ),
        _RowAction.resetPassword => sendPasswordReset(
          context,
          ref,
          person: person,
        ),
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: _RowAction.edit,
          child: Text('Edit details'),
        ),
        PopupMenuItem(
          value: _RowAction.toggleStatus,
          // Your own account cannot be deactivated from here — nor, by the
          // security rules, from anywhere.
          enabled: !(isSelf && active),
          child: Text(active ? 'Deactivate' : 'Reactivate'),
        ),
        const PopupMenuItem(
          value: _RowAction.resetPassword,
          child: Text('Send password reset'),
        ),
      ],
    );
  }
}

/// ROLE LEGEND (Figma `89:4924`).
class _RoleLegend extends StatelessWidget {
  const _RoleLegend();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(25),
    decoration: BoxDecoration(
      color: AppColors.surface,
      border: Border.all(color: AppColors.borderStrong),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ROLE LEGEND', style: AppTextStyles.legendTitle),
        const SizedBox(height: 16),
        Wrap(
          spacing: 64,
          runSpacing: 12,
          children: [
            for (final role in UserRole.values)
              _LegendItem(color: _dotFor(role), label: role.label),
            const _LegendItem(
              color: AppColors.accountInactiveDot,
              label: 'Inactive Account',
              muted: true,
            ),
          ],
        ),
      ],
    ),
  );

  static Color _dotFor(UserRole role) => switch (role) {
    UserRole.requestor => AppColors.roleRequestorDot,
    UserRole.maintenancePersonnel => AppColors.roleMaintenanceDot,
    UserRole.admin => AppColors.roleAdminDot,
  };
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    this.muted = false,
  });

  final Color color;
  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 8),
      Text(
        label,
        style: AppTextStyles.legendItem.copyWith(
          color: muted ? AppColors.iconMuted : null,
        ),
      ),
    ],
  );
}
