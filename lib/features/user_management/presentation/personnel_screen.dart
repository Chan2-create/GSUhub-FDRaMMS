import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/damage_categories.dart';
import '../../../core/di/service_providers.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/utils/display_id.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/category_chip.dart';
import '../../../core/widgets/filter_select.dart';
import '../../../core/widgets/person_avatar.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../core/widgets/table_pagination.dart';
import '../data/models/app_user.dart';
import 'personnel_directory_providers.dart';
import 'personnel_providers.dart';
import 'widgets/account_dialogs.dart';

/// Maintenance Personnel (Figma node `200:4316`, content area only;
/// manuscript Figure 17).
///
/// Every row and number is read from the `users` collection. The mockup's
/// 24 / 18 / 6 / 0 and its four sample staff appear nowhere here.
class PersonnelScreen extends ConsumerWidget {
  const PersonnelScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => SingleChildScrollView(
    padding: const EdgeInsets.all(32),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Maintenance Personnel', style: AppTextStyles.pageTitle),
                  SizedBox(height: 4),
                  Text(
                    'Manage and monitor GSU maintenance staff availability '
                    'and workloads.',
                    style: AppTextStyles.pageSubtitle,
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: () => showCreateAccountDialog(context),
              icon: SvgPicture.asset('assets/icons/personnel_add.svg'),
              label: const Text(
                'Add Personnel',
                style: AppTextStyles.primaryButtonLarge,
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 48),
        const _MetricRow(),
        const SizedBox(height: 48),
        const _FilterStrip(),
        const SizedBox(height: 24),
        const _StaffTable(),
      ],
    ),
  );
}

class _MetricRow extends ConsumerWidget {
  const _MetricRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(staffStatsProvider);
    final data = stats.value?.fold((s) => s, (_) => null);
    final isLoading = stats.isLoading;
    final hasError = stats.hasError || (stats.value?.isFailure ?? false);

    final cards = [
      StatCard.metric(
        label: 'TOTAL STAFF',
        iconAsset: 'assets/icons/stat_staff_total.svg',
        value: data?.total,
        definition: 'Maintenance personnel with active accounts.',
        isLoading: isLoading,
        hasError: hasError,
      ),
      StatCard.metric(
        label: 'AVAILABLE NOW',
        iconAsset: 'assets/icons/stat_staff_available.svg',
        accent: AppColors.presenceAvailable,
        value: data?.available,
        definition: 'Not on leave and holding no active work orders.',
        isLoading: isLoading,
        hasError: hasError,
      ),
      StatCard.metric(
        label: 'ON TASK',
        iconAsset: 'assets/icons/stat_staff_on_task.svg',
        accent: AppColors.presenceBusy,
        value: data?.onTask,
        definition: 'Holding at least one active work order.',
        isLoading: isLoading,
        hasError: hasError,
      ),
      StatCard.metric(
        label: 'ON LEAVE',
        iconAsset: 'assets/icons/stat_staff_on_leave.svg',
        value: data?.onLeave,
        definition: 'Marked on leave by an administrator.',
        isLoading: isLoading,
        hasError: hasError,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000 ? 4 : 2;
        const gap = 24.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }
}

/// Search, availability and trade (Figma `201:4716`).
class _FilterStrip extends ConsumerStatefulWidget {
  const _FilterStrip();

  @override
  ConsumerState<_FilterStrip> createState() => _FilterStripState();
}

class _FilterStripState extends ConsumerState<_FilterStrip> {
  late final TextEditingController _search = TextEditingController(
    text: ref.read(personnelDirectoryViewProvider).search,
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(personnelDirectoryViewProvider);
    final controller = ref.read(personnelDirectoryViewProvider.notifier);
    final trade = view.trade;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.filterBarBackground,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _search,
              onChanged: controller.setSearch,
              style: AppTextStyles.filterStripText,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search by name or specialization...',
                hintStyle: AppTextStyles.filterStripText.copyWith(
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
                  ),
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 41),
                contentPadding: const EdgeInsets.symmetric(vertical: 15),
                border: _border,
                enabledBorder: _border,
              ),
            ),
          ),
          const SizedBox(width: 24),
          const Text('AVAILABILITY:', style: AppTextStyles.metricLabel),
          const SizedBox(width: 12),
          FilterSelect<StaffStatus>(
            placeholder: 'All Statuses',
            style: FilterSelectStyle.large,
            value: view.status,
            onChanged: controller.setStatus,
            options: [
              const FilterOption(value: null, label: 'All Statuses'),
              for (final status in StaffStatus.values)
                FilterOption(value: status, label: status.label),
            ],
          ),
          const SizedBox(width: 24),
          // Indexed rather than keyed by category: "All trades" has no
          // category, and a popup menu treats a null choice as a cancel.
          PopupMenuButton<int>(
            tooltip: trade == null
                ? 'Filter by trade'
                : 'Trade: ${trade.label}',
            position: PopupMenuPosition.under,
            initialValue: trade?.index ?? -1,
            onSelected: (index) => controller.setTrade(
              index < 0 ? null : DamageCategory.values[index],
            ),
            itemBuilder: (context) => [
              const PopupMenuItem(value: -1, child: Text('All trades')),
              for (final category in DamageCategory.values)
                PopupMenuItem(
                  value: category.index,
                  child: Text(category.label),
                ),
            ],
            child: Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: trade == null
                    ? AppColors.filterButtonBackground
                    : AppColors.primary,
                border: Border.all(color: AppColors.borderStrong),
                borderRadius: BorderRadius.circular(4),
              ),
              child: SvgPicture.asset(
                'assets/icons/filter_list.svg',
                width: 18,
                height: 12,
                colorFilter: ColorFilter.mode(
                  trade == null
                      ? AppColors.textSecondary
                      : AppColors.textOnDark,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static final OutlineInputBorder _border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(4),
    borderSide: const BorderSide(color: AppColors.borderStrong),
  );
}

/// Column shares from the design's header cells
/// (224/199/134/178/183/216).
const List<int> _columns = [224, 199, 134, 178, 183, 216];

class _StaffTable extends ConsumerWidget {
  const _StaffTable();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(personnelDirectoryViewProvider);
    final page = ref.watch(staffPageProvider);
    final total =
        ref
            .watch(filteredStaffProvider)
            .value
            ?.fold((p) => p.length, (_) => 0) ??
        0;
    final signedIn = ref.watch(authStateProvider).value?.uid;
    final filtering =
        view.search.trim().isNotEmpty ||
        view.status != null ||
        view.trade != null;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.borderStrong),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            offset: Offset(0, 1),
            blurRadius: 2,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: AppColors.tableStripe,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: const Row(
              children: [
                _HeaderCell('PERSONNEL', column: 0),
                _HeaderCell('SPECIALIZATION', column: 1),
                _HeaderCell('STATUS', column: 2),
                _HeaderCell('ACTIVE TASKS', column: 3, align: TextAlign.center),
                _HeaderCell('CONTACT INFO', column: 4),
                _HeaderCell('ACTIONS', column: 5, align: TextAlign.right),
              ],
            ),
          ),
          AsyncValueView<List<AppUser>>(
            value: page,
            isEmpty: (people) => people.isEmpty,
            emptyIcon: Icons.engineering_outlined,
            emptyMessage: filtering
                ? 'No personnel match these filters.'
                : 'No maintenance personnel yet. Use Add Personnel to create '
                      'the first account.',
            onRetry: () => ref.invalidate(personnelStreamProvider),
            data: (people) => Column(
              children: [
                for (var i = 0; i < people.length; i++)
                  _StaffRow(
                    person: people[i],
                    striped: i.isOdd,
                    isSelf: people[i].id == signedIn,
                  ),
              ],
            ),
          ),
          TablePagination(
            style: TablePaginationStyle.arrows,
            itemNoun: 'staff members',
            page: view.page,
            pageSize: PersonnelDirectoryView.pageSize,
            totalItems: total,
            onPageChanged: ref
                .read(personnelDirectoryViewProvider.notifier)
                .setPage,
          ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.text, {required this.column, this.align});

  final String text;
  final int column;
  final TextAlign? align;

  @override
  Widget build(BuildContext context) => Expanded(
    flex: _columns[column],
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Text(
        text,
        textAlign: align,
        style: AppTextStyles.staffTableHeader,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );
}

class _StaffRow extends StatelessWidget {
  const _StaffRow({
    required this.person,
    required this.striped,
    required this.isSelf,
  });

  final AppUser person;
  final bool striped;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final status = StaffStatus.of(person);
    final trade = person.specialization;
    final dot = switch (status) {
      StaffStatus.available => AppColors.presenceAvailable,
      StaffStatus.busy => AppColors.presenceBusy,
      StaffStatus.onLeave => AppColors.textFaint,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: striped ? AppColors.tableStripe : AppColors.surface,
        border: const Border(top: BorderSide(color: AppColors.borderStrong)),
      ),
      child: Row(
        children: [
          _cell(
            0,
            Row(
              children: [
                PersonAvatar(fullName: person.fullName),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person.fullName,
                        style: AppTextStyles.staffName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'ID: ${DisplayId.user(person.id)}',
                        style: AppTextStyles.staffId,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _cell(
            1,
            trade == null
                ? const Text('—', style: AppTextStyles.staffContact)
                : Align(
                    alignment: Alignment.centerLeft,
                    child: CategoryChip(category: trade),
                  ),
          ),
          _cell(
            2,
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: dot,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    status.label,
                    style: AppTextStyles.staffStatus,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          _cell(
            3,
            Text(
              '${person.activeTaskCount}',
              textAlign: TextAlign.center,
              style: AppTextStyles.staffTaskCount,
            ),
          ),
          _cell(
            4,
            Tooltip(
              message: person.contactNumber ?? person.email,
              child: Text(
                person.email,
                style: AppTextStyles.staffContact,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          _cell(5, _Actions(person: person, status: status, isSelf: isSelf)),
        ],
      ),
    );
  }

  static Widget _cell(int column, Widget child) => Expanded(
    flex: _columns[column],
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: child,
    ),
  );
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.person,
    required this.status,
    required this.isSelf,
  });

  final AppUser person;
  final StaffStatus status;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final onLeave = status == StaffStatus.onLeave;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        IconButton(
          tooltip: 'Edit ${person.fullName}',
          onPressed: () =>
              showEditAccountDialog(context, person: person, isSelf: isSelf),
          icon: SvgPicture.asset('assets/icons/action_edit_pencil.svg'),
        ),
        const SizedBox(width: 12),
        Tooltip(
          message: onLeave
              ? '${person.fullName} is on leave.'
              : 'Open Task Assignment',
          child: FilledButton(
            onPressed: onLeave
                ? null
                : () => context.go(RoutePaths.adminTaskAssignment),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.ctaAmber,
              foregroundColor: AppColors.ctaAmberForeground,
              disabledBackgroundColor: AppColors.ctaAmber.withValues(
                alpha: 0.4,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              minimumSize: Size.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            child: const Text(
              'Assign Task',
              style: AppTextStyles.assignTaskLabel,
            ),
          ),
        ),
      ],
    );
  }
}
