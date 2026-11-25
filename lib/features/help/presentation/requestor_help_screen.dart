import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/routing/route_paths.dart';
import '../../../shells/mobile/mobile_title_row.dart';
import '../../../shells/requestor/requestor_shell.dart';

/// Help for faculty and staff (2026-11-26), opened from the question mark
/// in the header: how to send a report, what each status means, how to
/// scan a facility's QR code, and who to ask at GSU.
///
/// Plain text, kept here rather than in the database: it changes with the
/// app, not with the day's data. The wording follows what the app shows
/// (the form's fields, the chips, the timeline), so check it when those
/// change.
class RequestorHelpScreen extends StatelessWidget {
  const RequestorHelpScreen({super.key});

  void _leave(BuildContext context) =>
      context.canPop() ? context.pop() : context.go(RoutePaths.staffHome);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      MobileTitleRow(title: 'Help', onBack: () => _leave(context)),
      Expanded(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            14,
            16,
            14,
            requestorBottomInset(context),
          ),
          children: const [
            _Section(
              icon: Icons.add_circle_outline_rounded,
              title: 'Sending a damage report',
              children: [
                _Step(
                  number: 1,
                  text:
                      'Tap the gold + in the middle of the bar at the bottom.',
                ),
                _Step(
                  number: 2,
                  text:
                      'Choose the building and the room, or scan the QR code '
                      'on the room or the equipment (see below) to fill them '
                      'in.',
                ),
                _Step(
                  number: 3,
                  text:
                      'Give the damage a short title, such as "Broken ceiling '
                      'fan", and pick the damage type. Not sure of the type? '
                      'Choose "Not sure" and GSU will decide.',
                ),
                _Step(
                  number: 4,
                  text:
                      'Choose how urgent it is, then describe the damage: '
                      'what is broken, where exactly, and since when.',
                ),
                _Step(
                  number: 5,
                  text:
                      'Add at least one photo (up to 5), from the camera or '
                      'the gallery. The GPS location is captured for you '
                      'when it is on.',
                ),
                _Step(
                  number: 6,
                  text:
                      'Tap Submit Report. You can follow it under Reports, '
                      'and you will get a notification at every step.',
                ),
              ],
            ),
            SizedBox(height: 16),
            _Section(
              icon: Icons.flag_outlined,
              title: 'What each status means',
              children: [
                _Status(
                  name: 'Pending',
                  color: AppColors.progressPending,
                  meaning:
                      'GSU has received your report and has not opened it '
                      'yet.',
                ),
                _Status(
                  name: 'Under Review',
                  color: AppColors.statusReviewForeground,
                  meaning:
                      'GSU is checking it: confirming the damage type and '
                      'how urgent it is.',
                ),
                _Status(
                  name: 'Approved',
                  color: AppColors.progressInProgress,
                  meaning:
                      'GSU has accepted it, and the repair is being '
                      'planned.',
                ),
                _Status(
                  name: 'Scheduled',
                  color: AppColors.progressInProgress,
                  meaning:
                      'GSU has set a date for the work. The report shows the '
                      'date and why.',
                ),
                _Status(
                  name: 'Assigned',
                  color: AppColors.progressInProgress,
                  meaning: 'Maintenance staff have been given the job.',
                ),
                _Status(
                  name: 'In Progress',
                  color: AppColors.progressInProgress,
                  meaning:
                      'The staff are working on it. When they finish, GSU '
                      'checks the work.',
                ),
                _Status(
                  name: 'Completed',
                  color: AppColors.progressCompleted,
                  meaning:
                      'The repair is done and checked. You can rate the '
                      'service on the report.',
                ),
                _Status(
                  name: 'Rejected',
                  color: AppColors.statusNeutralForeground,
                  meaning:
                      'GSU did not accept the report, for example because '
                      'it was already reported. The report shows the '
                      'reason.',
                ),
                SizedBox(height: 4),
                Text(
                  'On the Reports list, Approved and Assigned reports show '
                  'as In Progress. Open a report to see each step on its '
                  'timeline.',
                  style: AppTextStyles.signUpLabel,
                ),
              ],
            ),
            SizedBox(height: 16),
            _Section(
              icon: Icons.qr_code_scanner,
              title: 'Scanning a QR code',
              children: [
                _Step(
                  number: 1,
                  text:
                      'Rooms and equipment carry a GSUhub QR sticker. Open the '
                      'report form with the gold +.',
                ),
                _Step(
                  number: 2,
                  text:
                      'Tap the QR button at the top right of the form, and '
                      'allow the camera if asked.',
                ),
                _Step(
                  number: 3,
                  text:
                      'Point the camera at the sticker. Use the torch button '
                      'if it is dark.',
                ),
                _Step(
                  number: 4,
                  text:
                      'The building and the room (and the equipment, if the '
                      'sticker is on it) are filled in for you. Check them, '
                      'then finish the report.',
                ),
              ],
            ),
            SizedBox(height: 16),
            _Section(
              icon: Icons.support_agent_rounded,
              title: 'Contacting GSU',
              children: [
                // The office's phone number and email belong here once GSU
                // gives them: not invented.
                _Paragraph(
                  'Reports are handled by the General Services Unit (GSU). '
                  'For a question about a report, about your account, or '
                  'about the app, go to the GSU Administrator\'s Office.',
                ),
                _Paragraph(
                  'If the damage is dangerous right now, such as exposed '
                  'wires, a gas smell or flooding, keep people away and tell '
                  'the GSU office in person as well as sending a report.',
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );
}

/// A white card with a gold left edge, as on the report page.
class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  // Clipped rather than given a border radius: Flutter draws a one-sided
  // border only on a square box.
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      boxShadow: const [
        BoxShadow(
          color: Color(0x14000000),
          blurRadius: 6,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            left: BorderSide(color: AppColors.accentGold, width: 4),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 22, color: AppColors.accentGold),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: AppTextStyles.trackingSectionTitle,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      ),
    ),
  );
}

/// A numbered step.
class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: AppTextStyles.trackingBody)),
      ],
    ),
  );
}

/// A status, its colour as on the chips, and what it means.
class _Status extends StatelessWidget {
  const _Status({
    required this.name,
    required this.color,
    required this.meaning,
  });

  final String name;
  final Color color;
  final String meaning;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$name. ',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: meaning),
              ],
            ),
            style: AppTextStyles.trackingBody,
          ),
        ),
      ],
    ),
  );
}

class _Paragraph extends StatelessWidget {
  const _Paragraph(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(text, style: AppTextStyles.trackingBody),
  );
}
