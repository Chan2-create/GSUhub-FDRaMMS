import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/enums/account_status.dart';
import '../../../../core/enums/personnel_availability.dart';
import '../../../../core/enums/user_role.dart';
import '../../../../core/utils/initials.dart';
import '../../data/models/app_user.dart';

/// A person's own profile, drawn the same on the phone and in the console
/// (2026-11-13): a header with their initials, name and role, then what
/// the account holds, in sections.
///
/// Only what `users` keeps is shown. There is no photo, no assigned
/// building or room and no self-editing in the system (the manuscript
/// gives account management to the GSU administrator, §1.5), so the
/// avatar is the person's initials and the page ends with who to ask for
/// a change rather than an Edit button.

/// The top of a profile: a band in the brand's indigo, the person's
/// initials on gold, their name, email, role and whether the account is
/// active.
class ProfileHeaderCard extends StatelessWidget {
  const ProfileHeaderCard({required this.person, super.key});

  final AppUser person;

  static const double _band = 84;
  static const double _avatar = 88;

  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      children: [
        SizedBox(
          height: _band + _avatar / 2,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: _band,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.sidebarBackground, AppColors.primary],
                    ),
                    border: Border(
                      bottom: BorderSide(color: AppColors.accentGold, width: 3),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: _band - _avatar / 2,
                child: Semantics(
                  label: 'Initials of ${person.fullName}',
                  excludeSemantics: true,
                  child: Container(
                    width: _avatar,
                    height: _avatar,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.accentGold,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.surface, width: 4),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1F000000),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      initialsOf(person.fullName),
                      style: AppTextStyles.avatarInitials.copyWith(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: AppColors.sidebarBackground,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
          child: Column(
            children: [
              Semantics(
                header: true,
                child: Text(
                  person.fullName,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.pageTitle.copyWith(fontSize: 22),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                person.email,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall,
              ),
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Pill(
                    icon: Icons.badge_outlined,
                    label: person.role.profileLabel,
                    background: AppColors.surfaceSunken,
                    foreground: AppColors.primary,
                  ),
                  _statusPill(person.accountStatus),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  static Widget _statusPill(AccountStatus status) => switch (status) {
    AccountStatus.active => const _Pill(
      icon: Icons.check_circle_outline,
      label: 'Active account',
      background: AppColors.statusResolvedBackground,
      foreground: AppColors.statusResolvedForeground,
    ),
    AccountStatus.pending => const _Pill(
      icon: Icons.hourglass_empty,
      label: 'Awaiting approval',
      background: AppColors.surfaceSunken,
      foreground: AppColors.textSecondary,
    ),
    AccountStatus.inactive => const _Pill(
      icon: Icons.block,
      label: 'Inactive account',
      background: AppColors.statusPendingBackground,
      foreground: AppColors.statusPendingForeground,
    ),
  };
}

/// What the account holds, in sections: how to reach the person, the
/// account itself, and for maintenance personnel their work.
class ProfileSections extends StatelessWidget {
  const ProfileSections({required this.person, super.key});

  final AppUser person;

  static final _joined = DateFormat('MMMM d, y');

  static const String _none = 'Not on file';

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      _Section(
        title: 'Contact',
        rows: [
          _Row(Icons.mail_outline, 'Email', person.email),
          _Row(
            Icons.phone_outlined,
            'Contact number',
            person.contactNumber ?? _none,
            faint: person.contactNumber == null,
          ),
          _Row(
            Icons.apartment_outlined,
            'Department',
            person.department ?? _none,
            faint: person.department == null,
          ),
        ],
      ),
      if (person.role == UserRole.maintenancePersonnel) ...[
        const SizedBox(height: 12),
        _Section(
          title: 'Work',
          rows: [
            _Row(
              Icons.handyman_outlined,
              'Specialization',
              person.specialization?.label ?? 'Not set',
              faint: person.specialization == null,
            ),
            _Row(
              Icons.event_available_outlined,
              'Availability',
              switch (person.availability) {
                PersonnelAvailability.available => 'Available',
                PersonnelAvailability.busy => 'Busy',
                PersonnelAvailability.onLeave => 'On leave',
                null => 'Not set',
              },
              faint: person.availability == null,
            ),
            // The count is of open work orders, whatever the field is
            // called (docs/data_dictionary.md).
            _Row(
              Icons.assignment_outlined,
              'Open work orders',
              person.activeTaskCount == 1
                  ? '1 work order'
                  : '${person.activeTaskCount} work orders',
            ),
          ],
        ),
      ],
      const SizedBox(height: 12),
      _Section(
        title: 'Account',
        rows: [
          _Row(Icons.badge_outlined, 'Role', person.role.profileLabel),
          _Row(
            Icons.verified_user_outlined,
            'Status',
            switch (person.accountStatus) {
              AccountStatus.active => 'Active',
              AccountStatus.pending => 'Awaiting approval',
              AccountStatus.inactive => 'Inactive',
            },
          ),
          _Row(
            Icons.event_outlined,
            'Member since',
            _joined.format(person.createdAt.toLocal()),
          ),
        ],
      ),
      const SizedBox(height: 12),
      // Nobody edits their own account here. An administrator is the one
      // who can change it, so theirs says where rather than who to ask.
      _Note(
        person.role == UserRole.admin
            ? 'Account details are kept in User Accounts, where an '
                  'administrator changes a name, department or contact '
                  'number.'
            : 'Your account is kept by the General Services Unit. To '
                  'change your name, department or contact number, ask '
                  'the GSU office.',
      ),
    ],
  );
}

/// One line of a section: what it is, and its value.
class _Row {
  const _Row(this.icon, this.label, this.value, {this.faint = false});

  final IconData icon;
  final String label;
  final String value;

  /// Drawn lighter: the account does not hold this.
  final bool faint;
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows});

  final String title;
  final List<_Row> rows;

  @override
  Widget build(BuildContext context) => _Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: AppTextStyles.sectionTitle),
          ),
          const SizedBox(height: 6),
          for (final (index, row) in rows.indexed) ...[
            if (index > 0)
              const Divider(height: 1, color: AppColors.borderSubtle),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSunken,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(row.icon, size: 20, color: AppColors.primary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.label.toUpperCase(),
                          style: AppTextStyles.fieldLabel,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          row.value,
                          style: row.faint
                              ? AppTextStyles.fieldValue.copyWith(
                                  color: AppColors.textMuted,
                                )
                              : AppTextStyles.fieldValue,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
    decoration: BoxDecoration(
      color: AppColors.surfaceSunken,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1, right: 10),
          child: Icon(
            Icons.info_outline,
            size: 18,
            color: AppColors.textSecondary,
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: foreground),
        const SizedBox(width: 6),
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

/// The profile's white card: a hairline border and a soft shadow.
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0F0F172A),
          blurRadius: 10,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: child,
  );
}
