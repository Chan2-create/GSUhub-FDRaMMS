import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/routing/route_paths.dart';
import 'requestor_shell.dart';
import 'requestor_title_row.dart';

/// A tab the faculty and staff app has but does not build yet, marked as
/// such (Objective 3.A builds the bar; Alerts arrives with 3.B). Plain:
/// the design draws no empty state.
class RequestorPlaceholderPage extends StatelessWidget {
  const RequestorPlaceholderPage({
    required this.title,
    required this.icon,
    required this.message,
    super.key,
    this.children = const [],
  });

  final String title;
  final IconData icon;
  final String message;

  /// Anything the page offers in the meantime, under the message.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      RequestorTitleRow(
        title: title,
        onBack: () => context.go(RoutePaths.staffHome),
      ),
      Expanded(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            32,
            48,
            32,
            requestorBottomInset(context),
          ),
          children: [
            Icon(icon, size: 48, color: AppColors.reportThumbPlaceholder),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.placeholderTitle,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.placeholderBody,
            ),
            ...children,
          ],
        ),
      ),
    ],
  );
}

/// Alerts — notifications about the requestor's reports, Objective 3.B.
class RequestorAlertsPage extends StatelessWidget {
  const RequestorAlertsPage({super.key});

  @override
  Widget build(BuildContext context) => const RequestorPlaceholderPage(
    title: 'Alerts',
    icon: Icons.notifications_none_rounded,
    message:
        'Updates on your reports will appear here. Notifications arrive '
        'in Objective 3.B.',
  );
}
