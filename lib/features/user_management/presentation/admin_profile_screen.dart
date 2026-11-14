import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/breakpoints.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/page_header.dart';
import '../data/models/app_user.dart';
import 'profile_providers.dart';
import 'widgets/profile_cards.dart';

/// My Profile (2026-11-13): the signed-in administrator's own account,
/// opened from the header's account menu. The same cards as the phone
/// apps' Profile tab, laid out for a wide window: who they are on the
/// left, what the account holds on the right.
///
/// No design draws this page; it is built from the console's shared
/// widgets and listed for the GUI pass.
class AdminProfileScreen extends ConsumerWidget {
  const AdminProfileScreen({super.key});

  /// From this width the header card sits beside the sections.
  static const double _sideBySide = 900;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SingleChildScrollView(
    padding: EdgeInsets.all(Breakpoints.gutter(context)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader(
          heading: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('My Profile', style: AppTextStyles.pageTitle),
              SizedBox(height: 4),
              Text(
                'Your administrator account, as GSUhub keeps it.',
                style: AppTextStyles.pageSubtitle,
              ),
            ],
          ),
          action: SizedBox.shrink(),
        ),
        const SizedBox(height: 24),
        AsyncValueView<AppUser>(
          value: ref.watch(signedInProfileProvider),
          loadingHeight: 320,
          onRetry: () => ref.invalidate(signedInProfileProvider),
          data: (person) => LayoutBuilder(
            builder: (context, constraints) {
              final header = ProfileHeaderCard(person: person);
              final sections = ProfileSections(person: person);
              if (constraints.maxWidth < _sideBySide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [header, const SizedBox(height: 16), sections],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 360, child: header),
                  const SizedBox(width: 24),
                  // No wider than reads well, on a very wide window.
                  Expanded(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: sections,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}
