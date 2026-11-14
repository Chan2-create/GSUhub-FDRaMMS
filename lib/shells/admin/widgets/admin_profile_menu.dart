import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/utils/result.dart';
import '../../../core/widgets/sign_out_dialog.dart';
import '../../../features/user_management/presentation/profile_providers.dart';

/// The header's gold circle (Figma `196:743`), as the account menu
/// (2026-11-13): who is signed in, My Profile, and Logout, which asks
/// first. Logout used to be an icon in the sidebar's footer.
///
/// No Account Settings entry: the system has no account settings to open.
/// An account's name, department and contact number are kept by an
/// administrator in User Accounts, and a password is changed from
/// "Forget password?" on the sign-in page.
class AdminProfileMenu extends ConsumerWidget {
  const AdminProfileMenu({
    required this.user,
    required this.onSignOut,
    super.key,
    this.size = 36,
  });

  final AuthUser? user;

  /// Ends the session. Called once the person has confirmed.
  final Future<void> Function() onSignOut;

  /// The circle's diameter: 36 in the header, smaller in the phone's bar.
  final double size;

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

    return PopupMenuButton<_Action>(
      tooltip: 'Account',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      elevation: 6,
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 300),
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
          case _Action.signOut:
            if (await confirmSignOut(context)) await onSignOut();
        }
      },
      itemBuilder: (context) => [
        // Who this is. Not a choice, so it does not answer a press.
        PopupMenuItem(
          enabled: false,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
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
              const SizedBox(height: 2),
              Text(
                (profile?.role ?? user?.role)?.profileLabel ?? '',
                style: AppTextStyles.bodySmall,
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
          value: _Action.signOut,
          child: _Entry(
            icon: Icons.logout,
            label: 'Logout',
            color: AppColors.error,
          ),
        ),
      ],
      child: _Circle(size: size),
    );
  }
}

enum _Action { profile, signOut }

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

/// The gold circle, with a soft ring while the pointer is over it, so it
/// reads as something to press.
class _Circle extends StatefulWidget {
  const _Circle({required this.size});

  final double size;

  @override
  State<_Circle> createState() => _CircleState();
}

class _CircleState extends State<_Circle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: Padding(
      // Room for the ring, and a touch target wider than the circle.
      padding: const EdgeInsets.all(4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: AppColors.accentGold,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.accentGold.withValues(
                alpha: _hovered ? 0.35 : 0,
              ),
              spreadRadius: 4,
            ),
          ],
        ),
      ),
    ),
  );
}
