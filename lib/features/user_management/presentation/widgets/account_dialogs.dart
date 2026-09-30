import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/constants/damage_categories.dart';
import '../../../../core/enums/account_status.dart';
import '../../../../core/enums/personnel_availability.dart';
import '../../../../core/enums/user_role.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/utils/result.dart';
import '../../data/models/app_user.dart';
import '../account_controller.dart';

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

/// Asks before activating or deactivating [person], then does it.
Future<void> confirmStatusChange(
  BuildContext context,
  WidgetRef ref, {
  required AppUser person,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final deactivating = person.accountStatus == AccountStatus.active;
  final work = person.activeTaskCount;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        deactivating
            ? 'Deactivate ${person.fullName}?'
            : 'Reactivate ${person.fullName}?',
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              deactivating
                  ? 'They will no longer be able to use GSUhub. Their '
                        'reports and work history stay on record, and the '
                        'account can be reactivated at any time.'
                  : 'They will be able to sign in and use GSUhub again.',
              style: AppTextStyles.bodyText,
            ),
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
          child: Text(deactivating ? 'Deactivate' : 'Reactivate'),
        ),
      ],
    ),
  );
  if (!(confirmed ?? false)) return;

  final result = await ref
      .read(accountControllerProvider)
      .setStatus(
        person,
        deactivating ? AccountStatus.inactive : AccountStatus.active,
      );
  result.fold(
    (_) => messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${deactivating ? 'Deactivated' : 'Reactivated'} '
          '${person.fullName}.',
        ),
      ),
    ),
    (failure) => messenger.showSnackBar(
      SnackBar(
        content: Text(failure.message),
        backgroundColor: AppColors.error,
      ),
    ),
  );
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
  late final TextEditingController _department;
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
    _department = TextEditingController(text: person?.department);
    _contact = TextEditingController(text: person?.contactNumber);
    _role = person?.role ?? UserRole.maintenancePersonnel;
    _specialization = person?.specialization;
    _onLeave = person?.availability == PersonnelAvailability.onLeave;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _department.dispose();
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

  @override
  Widget build(BuildContext context) {
    final isPersonnel = _role == UserRole.maintenancePersonnel;
    final lock = _roleLock;

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
                    initialValue: _role,
                    decoration: InputDecoration(
                      labelText: 'Role',
                      helperText: lock,
                      helperMaxLines: 2,
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
                TextFormField(
                  controller: _department,
                  decoration: const InputDecoration(
                    labelText: 'Department (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _contact,
                  decoration: const InputDecoration(
                    labelText: 'Contact number (optional)',
                  ),
                  keyboardType: TextInputType.phone,
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

  static String? _validateEmail(String? value) {
    final email = (value ?? '').trim();
    if (email.isEmpty) return 'Enter their email address.';
    // A shape check only; the sign-in service is the real judge.
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'That does not look like an email address.';
    }
    return null;
  }

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
        department: _department.text,
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
        department: _department.text,
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
