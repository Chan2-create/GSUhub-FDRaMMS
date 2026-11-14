import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/utils/initials.dart';
import '../../../core/utils/result.dart';
import '../../../core/widgets/sign_out_dialog.dart';
import '../../../features/user_management/presentation/profile_providers.dart';

/// The header's account button (Figma `196:743`, refined 2026-11-15): the
/// signed-in person's initials on the gold circle, with a chevron that
/// says it opens, and a tinted pill while the pointer is over it. The
/// menu beneath (2026-11-13): who is signed in, My Profile, Settings, and
/// Logout, which asks first.
///
/// No Account Settings entry: the system has no account settings to open.
/// An account's name, department and contact number are kept by an
/// administrator in User Accounts, and a password is changed from
/// "Forget password?" on the sign-in page. Settings here is the system's
/// Settings page, the same one the sidebar opens.
class AdminProfileMenu extends ConsumerWidget {
  const AdminProfileMenu({
    required this.user,
    required this.onSignOut,
    super.key,
    this.size = 36,
    this.compact = false,
  });

  final AuthUser? user;

  /// Ends the session. Called once the person has confirmed.
  final Future<void> Function() onSignOut;

  /// The circle's diameter: 36 in the header, smaller in the phone's bar.
  final double size;

  /// The circle alone, without the chevron: the phone's bar.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = switch (ref.watch(signedInProfileProvider).value) {
      Success(:final value) => value,
      _ => null,
    };
    final email = profile?.email ?? user?.email ?? '';
    final name =
        profile?.fullName ??
        (email.isEmpty ? 'Signed in' : email.split('@').first);
    final role = (profile?.role ?? user?.role)?.profileLabel ?? '';
    // Initials only for a name on file; a sign-in without a profile yet
    // gets the generic figure rather than the initials of an address.
    final initials = profile == null ? null : initialsOf(profile.fullName);

    return PopupMenuButton<_Action>(
      tooltip: 'Account',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      elevation: 8,
      shadowColor: const Color(0x330F172A),
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      constraints: const BoxConstraints(minWidth: 260, maxWidth: 320),
      popUpAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 180),
        reverseDuration: Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
      ),
      borderRadius: BorderRadius.circular(size),
      onSelected: (action) async {
        switch (action) {
          case _Action.profile:
            context.go(RoutePaths.adminProfile);
          case _Action.settings:
            context.go(RoutePaths.adminSettings);
          case _Action.signOut:
            if (await confirmSignOut(context)) await onSignOut();
        }
      },
      itemBuilder: (context) => [
        // Who this is. Not a choice, so it does not answer a press.
        PopupMenuItem(
          enabled: false,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              _GoldCircle(size: 40, initials: initials),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: AppTextStyles.fieldValue,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        style: AppTextStyles.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (role.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _RolePill(label: role),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        const PopupMenuItem(
          value: _Action.profile,
          child: _Entry(icon: Icons.person_outline, label: 'My Profile'),
        ),
        const PopupMenuItem(
          value: _Action.settings,
          child: _Entry(icon: Icons.settings_outlined, label: 'Settings'),
        ),
        const PopupMenuDivider(height: 1),
        const PopupMenuItem(
          value: _Action.signOut,
          child: _Entry(
            icon: Icons.logout,
            label: 'Logout',
            color: AppColors.error,
          ),
        ),
      ],
      child: _AccountButton(size: size, initials: initials, chevron: !compact),
    );
  }
}

enum _Action { profile, settings, signOut }

class _Entry extends StatelessWidget {
  const _Entry({
    required this.icon,
    required this.label,
    this.color = AppColors.textPrimary,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 20, color: color),
      const SizedBox(width: 12),
      Text(label, style: AppTextStyles.fieldValue.copyWith(color: color)),
    ],
  );
}

/// The role, as a small pill in the menu's heading.
class _RolePill extends StatelessWidget {
  const _RolePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: AppColors.surfaceSunken,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: AppTextStyles.bodySmall.copyWith(
        color: AppColors.primary,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// The gold circle: the person's initials, or the generic figure.
class _GoldCircle extends StatelessWidget {
  const _GoldCircle({required this.size, required this.initials});

  final double size;
  final String? initials;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: AppColors.accentGold,
      shape: BoxShape.circle,
    ),
    child: initials == null
        ? Icon(
            Icons.person,
            size: size * 0.58,
            color: AppColors.sidebarBackground,
          )
        : Text(
            initials!,
            style: AppTextStyles.avatarInitials.copyWith(
              fontSize: size * 0.38,
              color: AppColors.sidebarBackground,
            ),
          ),
  );
}

/// The circle and its chevron, in a pill that tints while the pointer is
/// over it, so it reads as something to press.
class _AccountButton extends StatefulWidget {
  const _AccountButton({
    required this.size,
    required this.initials,
    required this.chevron,
  });

  final double size;
  final String? initials;
  final bool chevron;

  @override
  State<_AccountButton> createState() => _AccountButtonState();
}

class _AccountButtonState extends State<_AccountButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      // A touch target wider than the circle, and room for the tint.
      padding: EdgeInsets.fromLTRB(4, 4, widget.chevron ? 6 : 4, 4),
      decoration: BoxDecoration(
        color: _hovered ? AppColors.surfaceSunken : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _GoldCircle(size: widget.size, initials: widget.initials),
          if (widget.chevron) ...[
            const SizedBox(width: 2),
            Icon(
              Icons.expand_more,
              size: 18,
              color: _hovered ? AppColors.textPrimary : AppColors.textMuted,
            ),
          ],
        ],
      ),
    ),
  );
}
