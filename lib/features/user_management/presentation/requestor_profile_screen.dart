import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/utils/result.dart';
import '../../../core/widgets/person_avatar.dart';
import '../../../shells/requestor/requestor_placeholder_page.dart';
import '../../auth/presentation/auth_controller.dart';
import 'profile_providers.dart';

/// The Profile tab — a marked placeholder in Objective 3.A that holds only
/// who is signed in and Sign out. Editing a profile belongs to a later
/// objective; the design draws no Profile page.
class RequestorProfileScreen extends ConsumerWidget {
  const RequestorProfileScreen({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    // Taken before the await: signing out moves the guard, which may
    // replace this page underneath us.
    final router = GoRouter.of(context);
    await ref.read(authControllerProvider.notifier).signOut();
    router.go(RoutePaths.staffLogin);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = switch (ref.watch(signedInProfileProvider).value) {
      Success(:final value) => value,
      _ => null,
    };

    return RequestorPlaceholderPage(
      title: 'Profile',
      icon: Icons.person_outline_rounded,
      message: 'Editing your profile arrives in a later objective.',
      children: [
        if (person != null) ...[
          const SizedBox(height: 32),
          Center(child: PersonAvatar(fullName: person.fullName)),
          const SizedBox(height: 12),
          Text(
            person.fullName,
            textAlign: TextAlign.center,
            style: AppTextStyles.placeholderTitle,
          ),
          Text(
            person.email,
            textAlign: TextAlign.center,
            style: AppTextStyles.placeholderBody,
          ),
          if (person.department case final department?)
            Text(
              department,
              textAlign: TextAlign.center,
              style: AppTextStyles.placeholderBody,
            ),
        ],
        const SizedBox(height: 32),
        Center(
          child: OutlinedButton.icon(
            onPressed: () => _signOut(context, ref),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              minimumSize: const Size(160, 48),
            ),
          ),
        ),
      ],
    );
  }
}
