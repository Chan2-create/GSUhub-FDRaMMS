import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';

/// The Terms of Use and Privacy Notice a person accepts to create an
/// account (2026-11-25).
///
/// **DRAFT, for Chris and the adviser to review.** GSUhub had no terms or
/// privacy notice before; this one was written from what the system
/// actually collects and who can see it, with the Data Privacy Act of 2012
/// (Republic Act No. 10173) as its frame. Edit the wording here: it is
/// shown only from Create Account, by [showTermsNotice].
abstract final class TermsNotice {
  static const String title = 'Terms of Use and Privacy Notice';
  static const String updated = 'Last updated 25 November 2026';

  static const List<(String, String)> sections = [
    (
      'What GSUhub is for',
      'GSUhub is the General Services Unit (GSU) facility management system '
          'of Davao Oriental State University. Faculty and staff use it to '
          'report damaged facilities and follow those reports until the '
          'repair is done.',
    ),
    (
      'Your account',
      'Accounts are for DOrSU faculty and staff. A new account can be used '
          'only after a GSU administrator approves it, and an administrator '
          'may deactivate an account that is no longer needed or is misused. '
          'Keep your password to yourself; you are responsible for what is '
          'done with your account. You are signed out after a period of '
          'inactivity.',
    ),
    (
      'Using GSUhub properly',
      'Report only genuine facility damage, and describe it truthfully. Do '
          'not upload photos of people or anything unrelated to the damage, '
          'and do not use GSUhub to harass anyone or to get around university '
          'rules.',
    ),
    (
      'What we collect',
      'Your name, email address, department or faculty, and any contact '
          'number an administrator adds. For each report: its description, '
          'photos, building and room, and the GPS location of the phone when '
          'the report is made. We also keep the dates and times of what '
          'happens to a report, your ratings and comments on completed work, '
          'the time of your last activity (for the automatic sign-out), and '
          'a notification token for your phone.',
    ),
    (
      'Why we collect it',
      'Only to receive, assess, assign, and complete repair work, to tell '
          'you how your reports are progressing, and to keep the records GSU '
          'needs to manage the university\'s facilities.',
    ),
    (
      'Who can see it',
      'GSU administrators, and the utility personnel assigned to your '
          'report. Your information is not sold or shared with anyone outside '
          'the university, except the cloud services that host GSUhub on the '
          "university's behalf, or where the law requires it.",
    ),
    (
      'How it is protected',
      'Your password is held by the sign-in service only as a secure hash; '
          'nobody at GSU can see it. Records are reached over encrypted '
          'connections, and each person sees only what their role allows.',
    ),
    (
      'How long it is kept',
      'For as long as your account is active, and afterwards for as long as '
          "the university's records rules require. A deactivated account's "
          'reports stay in the record of the work that was done.',
    ),
    (
      'Your rights',
      'Under the Data Privacy Act of 2012 (Republic Act No. 10173), you may '
          'ask to see the personal information GSUhub holds about you, have '
          'it corrected, or object to its use. Ask the GSU Administrator\'s '
          'Office, or the university\'s Data Protection Officer.',
    ),
  ];
}

/// Shows [TermsNotice] over the page. Completes with true when the person
/// taps I Agree, false or null otherwise.
Future<bool?> showTermsNotice(BuildContext context) => showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    backgroundColor: Colors.white,
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    title: Text(
      TermsNotice.title,
      style: AppTextStyles.signUpTitle.copyWith(fontSize: 20),
    ),
    content: SizedBox(
      width: double.maxFinite,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              TermsNotice.updated,
              style: AppTextStyles.formError.copyWith(
                color: AppColors.warmText,
              ),
            ),
            for (final (heading, body) in TermsNotice.sections) ...[
              const SizedBox(height: 14),
              Text(heading, style: AppTextStyles.signUpLabel),
              const SizedBox(height: 4),
              Text(body, style: AppTextStyles.signUpText),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('Close'),
      ),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
        onPressed: () => Navigator.of(context).pop(true),
        child: const Text('I Agree'),
      ),
    ],
  ),
);
