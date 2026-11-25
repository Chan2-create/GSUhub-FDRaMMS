import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/constants/damage_categories.dart';
import '../../../../core/enums/account_status.dart';
import '../../../../core/enums/personnel_availability.dart';
import '../../../../core/enums/user_role.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/utils/account_validation.dart';
import '../../../../core/utils/result.dart';
import '../../data/models/app_user.dart';
import '../../data/models/department.dart';
import '../account_controller.dart';
import '../department_providers.dart';

// The designs draw the buttons that open these — "Add Personnel", "Create
// Maintenance Account", the row menu and pencil — but not the dialogs
// themselves. They follow the app's existing dialogs (2.B's Assign and
// Reject): the theme's AlertDialog, the app's field styles, and the
// model's own fields, nothing the data cannot hold (decided for 2.C).

/// Opens the new-account dialog. Only maintenance accounts are made here:
/// the design's button says so, faculty and staff register from the mobile
/// app, and a second administrator is made by promoting an account.
Future<void> showCreateAccountDialog(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final created = await showDialog<_Created>(
    context: context,
    builder: (_) => const _AccountFormDialog(),
  );
  if (created == null) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        created.setupEmailSent
            ? 'Created an account for ${created.name}. A link to set their '
                  'password has been sent to ${created.email}.'
            : 'Created an account for ${created.name}, but the password '
                  'email could not be sent. Use "Send password reset" from '
                  'their row.',
      ),
    ),
  );
}

/// Opens the edit dialog for [person].
Future<void> showEditAccountDialog(
  BuildContext context, {
  required AppUser person,
  required bool isSelf,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _AccountFormDialog(existing: person, isSelf: isSelf),
  );
  if (saved ?? false) {
    messenger.showSnackBar(
      SnackBar(content: Text('Saved changes to ${person.fullName}.')),
    );
  }
}

/// Asks before moving [person]'s account to [to], then does it: activating
/// or deactivating it, or — for someone who signed themselves up (3.A) —
/// approving or declining the request.
Future<void> confirmStatusChange(
  BuildContext context,
  WidgetRef ref, {
  required AppUser person,
  required AccountStatus to,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final deactivating = to == AccountStatus.inactive;
  final request = person.accountStatus == AccountStatus.pending;
  final work = person.activeTaskCount;
  final (title, body, action, done) = switch ((request, deactivating)) {
    (true, false) => (
      'Approve ${person.fullName}?',
      'They will be able to sign in to the faculty and staff app and file '
          'damage reports as ${person.email}.',
      'Approve',
      'Approved',
    ),
    (true, true) => (
      'Decline ${person.fullName}?',
      'They will not be able to sign in. The request stays on record as an '
          'inactive account, and can be reactivated later.',
      'Decline',
      'Declined',
    ),
    (false, true) => (
      'Deactivate ${person.fullName}?',
      'They will no longer be able to use GSUhub, and are signed out at '
          'once on every device they are using, with a notice saying why. '
          'Their reports and work history stay on record, and the account '
          'can be reactivated at any time.',
      'Deactivate',
      'Deactivated',
    ),
    (false, false) => (
      'Reactivate ${person.fullName}?',
      'They will be able to sign in and use GSUhub again.',
      'Reactivate',
      'Reactivated',
    ),
  };

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(body, style: AppTextStyles.bodyText),
            if (deactivating && work > 0) ...[
              const SizedBox(height: 12),
              // A warning rather than a refusal: someone who has left must
              // be deactivated even if their work is unfinished, and there
              // is no reassignment screen yet to clear it first.
              Text(
                'They still hold $work active work order'
                '${work == 1 ? '' : 's'}, which will stay assigned to them.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.priorityHighForeground,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: deactivating
              ? FilledButton.styleFrom(backgroundColor: AppColors.error)
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(action),
        ),
      ],
    ),
  );
  if (!(confirmed ?? false)) return;

  final result = await ref
      .read(accountControllerProvider)
      .setStatus(person, to);
  result.fold(
    (_) => messenger.showSnackBar(
      SnackBar(content: Text('$done ${person.fullName}.')),
    ),
    (failure) => messenger.showSnackBar(
      SnackBar(
        content: Text(failure.message),
        backgroundColor: AppColors.error,
      ),
    ),
  );
}

/// Asks before approving [person]'s sign-up, and approves it (2026-11-26).
/// The dialog says what they signed up as, Faculty or Utility, and so
/// which app they will open; a Utility account is approved with the trade
/// work is routed to it by, chosen here.
Future<void> confirmApproval(
  BuildContext context,
  WidgetRef ref, {
  required AppUser person,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final approved = await showDialog<bool>(
    context: context,
    builder: (_) => _ApproveDialog(person: person),
  );
  if (approved ?? false) {
    messenger.showSnackBar(
      SnackBar(content: Text('Approved ${person.fullName}.')),
    );
  }
}

/// Approve, with what the person signed up as, and for a Utility account
/// their trade. Runs the approval itself, so a refusal shows here.
class _ApproveDialog extends ConsumerStatefulWidget {
  const _ApproveDialog({required this.person});

  final AppUser person;

  @override
  ConsumerState<_ApproveDialog> createState() => _ApproveDialogState();
}

class _ApproveDialogState extends ConsumerState<_ApproveDialog> {
  late DamageCategory? _trade = widget.person.specialization;
  bool _busy = false;
  String? _error;

  bool get _utility => widget.person.role == UserRole.maintenancePersonnel;

  Future<void> _approve() async {
    if (_utility && _trade == null) {
      setState(() => _error = 'Choose the trade they work in.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(accountControllerProvider)
        .approve(widget.person, specialization: _trade);
    if (!mounted) return;
    switch (result) {
      case Success():
        Navigator.of(context).pop(true);
      case Error(:final failure):
        setState(() {
          _busy = false;
          _error = failure.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final person = widget.person;
    final app = _utility
        ? 'the maintenance app, and take the work assigned to them'
        : 'the faculty and staff app, and file damage reports';
    return AlertDialog(
      title: Text('Approve ${person.fullName}?'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Signed up as ${person.role.signUpLabel}',
              style: AppTextStyles.fieldValue.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'They will be able to sign in to $app, as ${person.email}.',
              style: AppTextStyles.bodyText,
            ),
            if (_utility) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<DamageCategory>(
                key: const ValueKey('approve-trade'),
                isExpanded: true,
                initialValue: _trade,
                decoration: const InputDecoration(
                  labelText: 'Trade',
                  helperText:
                      'Reports are matched to personnel by trade (Table 3.3).',
                  helperMaxLines: 2,
                ),
                items: [
                  for (final category in DamageCategory.values)
                    DropdownMenuItem(
                      value: category,
                      child: Text(category.assignedPersonnelLabel),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                        _trade = value;
                        _error = null;
                      }),
              ),
            ],
            if (_error case final message?) ...[
              const SizedBox(height: 12),
              Text(
                message,
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _approve,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Approve'),
        ),
      ],
    );
  }
}

/// Emails [person] a link to set a new password.
Future<void> sendPasswordReset(
  BuildContext context,
  WidgetRef ref, {
  required AppUser person,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final result = await ref
      .read(accountControllerProvider)
      .sendPasswordReset(person);
  result.fold(
    (_) => messenger.showSnackBar(
      SnackBar(content: Text('Sent a password reset link to ${person.email}.')),
    ),
    (failure) => messenger.showSnackBar(
      SnackBar(
        content: Text(failure.message),
        backgroundColor: AppColors.error,
      ),
    ),
  );
}

class _Created {
  const _Created({
    required this.name,
    required this.email,
    required this.setupEmailSent,
  });

  final String name;
  final String email;
  final bool setupEmailSent;
}

/// Create (no [existing]) or edit. Runs the save itself, so a refusal —
/// "an account with this email already exists" — is shown here, with the
/// administrator's input still in place, rather than after the dialog has
/// closed.
class _AccountFormDialog extends ConsumerStatefulWidget {
  const _AccountFormDialog({this.existing, this.isSelf = false});

  final AppUser? existing;
  final bool isSelf;

  @override
  ConsumerState<_AccountFormDialog> createState() => _AccountFormDialogState();
}

class _AccountFormDialogState extends ConsumerState<_AccountFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;

  /// The department chosen from the list, or null for none.
  String? _department;
  late final TextEditingController _contact;
  late UserRole _role;
  DamageCategory? _specialization;
  late bool _onLeave;

  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final person = widget.existing;
    _name = TextEditingController(text: person?.fullName);
    _email = TextEditingController(text: person?.email);
    _department = person?.department;
    _contact = TextEditingController(text: person?.contactNumber);
    _role = person?.role ?? UserRole.maintenancePersonnel;
    _specialization = person?.specialization;
    _onLeave = person?.availability == PersonnelAvailability.onLeave;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _contact.dispose();
    super.dispose();
  }

  /// Why the role cannot change here, or null when it can. The repository
  /// refuses the same cases; saying so up front saves a round trip.
  String? get _roleLock {
    final person = widget.existing;
    if (person == null) return null;
    if (widget.isSelf) {
      return 'You cannot change your own role. Ask another administrator.';
    }
    final work = person.activeTaskCount;
    if (work > 0) {
      return 'Finish or reassign their $work active work order'
          '${work == 1 ? '' : 's'} before changing their role.';
    }
    return null;
  }

  /// Said under the role while it is being changed: what saving does.
  String? get _roleNotice {
    final person = widget.existing;
    if (person == null || _role == person.role) return null;
    return 'Saving signs ${person.fullName} out on every device. They sign in '
        'again to use GSUhub as ${_role.label}.';
  }

  @override
  Widget build(BuildContext context) {
    final isPersonnel = _role == UserRole.maintenancePersonnel;
    final lock = _roleLock;
    final roleNotice = _roleNotice;

    return AlertDialog(
      title: Text(_isEdit ? 'Edit account' : 'Create maintenance account'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!_isEdit) ...[
                  const Text(
                    'They will be emailed a link to set their own password.',
                    style: AppTextStyles.bodySmall,
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _name,
                  autofocus: !_isEdit,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  textCapitalization: TextCapitalization.words,
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Enter their full name.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  readOnly: _isEdit,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    helperText: _isEdit
                        ? 'The email is their sign-in and cannot be changed '
                              'here.'
                        : null,
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: _isEdit ? null : _validateEmail,
                ),
                if (_isEdit) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<UserRole>(
                    isExpanded: true,
                    initialValue: _role,
                    decoration: InputDecoration(
                      labelText: 'Role',
                      helperText: lock ?? roleNotice,
                      helperMaxLines: 3,
                      helperStyle: roleNotice != null && lock == null
                          ? AppTextStyles.bodySmall.copyWith(
                              color: AppColors.accountPending,
                            )
                          : null,
                    ),
                    items: [
                      for (final role in UserRole.values)
                        DropdownMenuItem(value: role, child: Text(role.label)),
                    ],
                    onChanged: lock != null || _busy
                        ? null
                        : (role) => setState(() => _role = role ?? _role),
                  ),
                ],
                if (isPersonnel) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<DamageCategory>(
                    isExpanded: true,
                    initialValue: _specialization,
                    decoration: const InputDecoration(
                      labelText: 'Specialization',
                    ),
                    items: [
                      for (final category in DamageCategory.values)
                        DropdownMenuItem(
                          value: category,
                          child: Text(category.label),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _specialization = value),
                    validator: (value) =>
                        value == null ? 'Choose the trade they work in.' : null,
                  ),
                ],
                const SizedBox(height: 12),
                _DepartmentSelect(
                  value: _department,
                  // An account from before the list keeps its department
                  // until it is changed.
                  current: widget.existing?.department,
                  enabled: !_busy,
                  onChanged: (value) => setState(() => _department = value),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _contact,
                  decoration: const InputDecoration(
                    labelText: 'Mobile number (optional)',
                    hintText: '09XX XXX XXXX',
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    // An account's number from before the check stays
                    // until it is changed, as the database allows.
                    final stored = widget.existing?.contactNumber;
                    if (stored != null && (value ?? '').trim() == stored) {
                      return null;
                    }
                    return AccountValidation.contactNumber(value);
                  },
                ),
                if (_isEdit && isPersonnel) ...[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _onLeave,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _onLeave = value),
                    title: const Text(
                      'On leave',
                      style: AppTextStyles.fieldValue,
                    ),
                    subtitle: const Text(
                      'Shown as on leave in the personnel directory.',
                      style: AppTextStyles.bodySmall,
                    ),
                  ),
                ],
                if (_error case final message?) ...[
                  const SizedBox(height: 12),
                  Text(
                    message,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isEdit ? 'Save changes' : 'Create account'),
        ),
      ],
    );
  }

  /// Leave is the only availability an administrator sets. Anything else
  /// stored is left as it was, so saving an unrelated edit does not log an
  /// availability change nobody made.
  PersonnelAvailability _availabilityFor(AppUser existing) {
    if (_onLeave) return PersonnelAvailability.onLeave;
    final stored = existing.availability;
    return stored == null || stored == PersonnelAvailability.onLeave
        ? PersonnelAvailability.available
        : stored;
  }

  static String? _validateEmail(String? value) =>
      AccountValidation.email(value, missing: 'Enter their email address.');

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final controller = ref.read(accountControllerProvider);
    final existing = widget.existing;

    if (existing == null) {
      final result = await controller.createMaintenanceAccount(
        fullName: _name.text,
        email: _email.text,
        specialization: _specialization!,
        department: _department,
        contactNumber: _contact.text,
      );
      if (!mounted) return;
      switch (result) {
        case Success(:final value):
          Navigator.of(context).pop(
            _Created(
              name: _name.text.trim(),
              email: _email.text.trim(),
              setupEmailSent: value.setupEmailSent,
            ),
          );
        case Error(:final failure):
          setState(() {
            _busy = false;
            _error = failure.message;
          });
      }
      return;
    }

    final isPersonnel = _role == UserRole.maintenancePersonnel;
    final AppUser updated;
    try {
      // Built through the constructor, not copyWith, so a trade or leave
      // status can be cleared when the role no longer carries one.
      updated = AppUser(
        id: existing.id,
        fullName: _name.text.trim(),
        email: existing.email,
        role: _role,
        accountStatus: existing.accountStatus,
        department: _department,
        contactNumber: _contact.text,
        specialization: isPersonnel ? _specialization : null,
        availability: isPersonnel ? _availabilityFor(existing) : null,
        activeTaskCount: existing.activeTaskCount,
        fcmToken: existing.fcmToken,
        createdAt: existing.createdAt,
        updatedAt: existing.updatedAt,
      );
    } on ValidationException catch (error) {
      setState(() {
        _busy = false;
        _error = error.message;
      });
      return;
    }

    final result = await controller.update(updated);
    if (!mounted) return;
    switch (result) {
      case Success():
        Navigator.of(context).pop(true);
      case Error(:final failure):
        setState(() {
          _busy = false;
          _error = failure.message;
        });
    }
  }
}

/// Department (optional): one from the list in Settings, or none
/// (2026-11-17). [current] is the account's department as stored: one
/// from before the list stays a choice, marked, so editing something else
/// does not take it away.
class _DepartmentSelect extends ConsumerWidget {
  const _DepartmentSelect({
    required this.value,
    required this.onChanged,
    this.current,
    this.enabled = true,
  });

  final String? value;
  final String? current;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final departments = ref.watch(activeDepartmentsProvider);
    final listed = switch (departments) {
      AsyncData(value: Success(:final value)) => value,
      _ => const <Department>[],
    };
    final names = {for (final department in listed) department.name};
    final unlisted = current != null && !names.contains(current)
        ? current
        : null;

    return DropdownButtonFormField<String?>(
      key: const ValueKey('account-department'),
      isExpanded: true,
      initialValue: value,
      decoration: InputDecoration(
        labelText: 'Department (optional)',
        helperText: departments.isLoading
            ? 'Loading the departments…'
            : listed.isEmpty
            ? 'No departments yet: add them in Settings → Departments.'
            : null,
      ),
      items: [
        const DropdownMenuItem<String?>(child: Text('None')),
        for (final department in listed)
          DropdownMenuItem(
            value: department.name,
            child: Text(department.name, overflow: TextOverflow.ellipsis),
          ),
        if (unlisted != null)
          DropdownMenuItem(
            value: unlisted,
            child: Text(
              '$unlisted (not on the list)',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: enabled ? onChanged : null,
    );
  }
}
