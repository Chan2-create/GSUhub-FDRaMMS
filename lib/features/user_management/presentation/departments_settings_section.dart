import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/di/repository_providers.dart';
import '../../../core/utils/result.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/section_card.dart';
import '../../settings/presentation/widgets/settings_parts.dart';
import '../data/models/department.dart';
import 'department_providers.dart';

/// Settings → Departments (2026-11-17): the departments and faculties
/// faculty and staff choose from when they create an account, and the
/// console's account dialog offers.
///
/// Each change is saved as it is made, unlike the other tabs, which save
/// a whole form at once: a list is changed one entry at a time, and the
/// database refuses a duplicate there and then.
class DepartmentsSettingsSection extends ConsumerStatefulWidget {
  const DepartmentsSettingsSection({super.key});

  @override
  ConsumerState<DepartmentsSettingsSection> createState() =>
      _DepartmentsSettingsSectionState();
}

class _DepartmentsSettingsSectionState
    extends ConsumerState<DepartmentsSettingsSection> {
  final _name = TextEditingController();
  bool _adding = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = _name.text.trim();
    if (name.isEmpty || _adding) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _adding = true);
    final result = await ref.read(departmentRepositoryProvider).create(name);
    if (!mounted) return;
    setState(() => _adding = false);
    result.fold((_) {
      _name.clear();
      messenger.showSnackBar(SnackBar(content: Text('Added $name.')));
    }, (failure) => _showFailure(messenger, failure.message));
  }

  @override
  Widget build(BuildContext context) => SectionCard(
    title: 'Departments and faculties',
    subtitle:
        'What faculty and staff choose from when they create an account. '
        'Required on that form while the list has any.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroup(
          title: 'Add one',
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('new-department'),
                  controller: _name,
                  enabled: !_adding,
                  maxLength: 120,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText:
                        'e.g. Faculty of Computing, Engineering and '
                        'Technology',
                    counterText: '',
                  ),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton(
                  onPressed: _adding ? null : _add,
                  child: Text(_adding ? 'Adding…' : 'Add'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SettingsGroup(
          title: 'On the list',
          description:
              'Renaming one renames it on the accounts that name it. A '
              'retired one is no longer offered; the accounts that name it '
              'keep it.',
          child: AsyncValueView<List<Department>>(
            value: ref.watch(allDepartmentsProvider),
            onRetry: () => ref.invalidate(allDepartmentsProvider),
            isEmpty: (list) => list.isEmpty,
            emptyMessage:
                'No departments yet. Until there are, faculty and staff '
                'create accounts without one.',
            data: (list) => Column(
              children: [
                for (final department in list)
                  _DepartmentRow(department: department),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

void _showFailure(ScaffoldMessengerState messenger, String message) =>
    messenger.showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );

class _DepartmentRow extends ConsumerStatefulWidget {
  const _DepartmentRow({required this.department});

  final Department department;

  @override
  ConsumerState<_DepartmentRow> createState() => _DepartmentRowState();
}

class _DepartmentRowState extends ConsumerState<_DepartmentRow> {
  bool _busy = false;

  Future<void> _run(
    Future<Result<void>> Function() action, {
    required String done,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final result = await action();
    if (mounted) setState(() => _busy = false);
    result.fold(
      (_) => messenger.showSnackBar(SnackBar(content: Text(done))),
      (failure) => _showFailure(messenger, failure.message),
    );
  }

  Future<void> _rename() async {
    final department = widget.department;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(current: department.name),
    );
    if (name == null || name == department.name || !mounted) return;
    await _run(
      () => ref.read(departmentRepositoryProvider).rename(department.id, name),
      done: 'Renamed to $name.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final department = widget.department;
    final repository = ref.read(departmentRepositoryProvider);
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: department.name,
                    style: AppTextStyles.fieldValue.copyWith(
                      color: department.isActive
                          ? null
                          : AppColors.textSecondary,
                    ),
                  ),
                  if (!department.isActive)
                    const TextSpan(
                      text: '  · retired',
                      style: AppTextStyles.bodySmall,
                    ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: _busy ? null : _rename,
                  child: const Text('Rename'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => repository.setActive(
                            department.id,
                            active: !department.isActive,
                          ),
                          done: department.isActive
                              ? 'Retired ${department.name}.'
                              : 'Restored ${department.name}.',
                        ),
                  child: Text(department.isActive ? 'Retire' : 'Restore'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.current});

  final String current;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _name = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.length < 2) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename department'),
    content: SizedBox(
      width: 420,
      child: TextField(
        controller: _name,
        autofocus: true,
        maxLength: 120,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (_) => _submit(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Rename')),
    ],
  );
}
