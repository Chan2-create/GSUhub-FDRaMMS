import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/sign_out_dialog.dart';
import '../../../shells/mobile/mobile_title_row.dart';
import '../../../shells/requestor/requestor_shell.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../notifications/presentation/push_coordinator.dart';
import '../data/models/app_user.dart';
import 'profile_providers.dart';
import 'widgets/profile_cards.dart';

/// The Profile tab of both phone apps, faculty and staff and maintenance
/// personnel alike: who is signed in, what their account holds, and
/// Logout (Objective 3.A; drawn as a profile on 2026-11-13, where it had
/// been a name on a blank page).
///
/// The manuscript gives nobody profile editing and the design draws no
/// Profile page: accounts are changed by an administrator, in User
/// Accounts (2.C), and the page says who to ask.
class MobileProfileScreen extends ConsumerWidget {
  const MobileProfileScreen({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    // Taken before the await: signing out moves the guard, which may
    // replace this page underneath us.
    final router = GoRouter.of(context);
    if (!await confirmSignOut(context)) return;
    // The phone's push token goes first, while the account can still clear
    // it: the next person to sign in here must not get this one's notices.
    await ref.read(pushCoordinatorProvider).signOutDevice();
    await ref.read(authControllerProvider.notifier).signOut();
    router.go(RoutePaths.staffLogin);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The one page serves both apps; Back goes to whichever it is in.
    final inPersonnelApp = GoRouterState.of(context).matchedLocation
        .startsWith(RoutePaths.personnelProfile);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MobileTitleRow(
          title: 'Profile',
          onBack: () => context.go(
            inPersonnelApp
                ? RoutePaths.personnelDashboard
                : RoutePaths.staffHome,
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              requestorBottomInset(context),
            ),
            children: [
              AsyncValueView<AppUser>(
                value: ref.watch(signedInProfileProvider),
                loadingHeight: 260,
                onRetry: () => ref.invalidate(signedInProfileProvider),
                data: (person) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ProfileHeaderCard(person: person),
                    const SizedBox(height: 12),
                    ProfileSections(person: person),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => _signOut(context, ref),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Logout'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
