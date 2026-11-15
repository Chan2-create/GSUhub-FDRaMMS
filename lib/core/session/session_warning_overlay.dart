import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/session_policy.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import 'inactivity_monitor.dart';
import 'session_watch.dart';

/// The warning the last two minutes of an idle session show, over
/// whatever page is open, with a countdown (2026-11-14). Doing anything
/// at all clears it: the listener around the app resets the clock on the
/// press itself, so the buttons only say so in words.
///
/// Drawn in the tree rather than as a dialog route: it sits above the
/// router, so it shows over any page and over any dialog a page has open,
/// and it needs no Navigator.
class SessionWarningOverlay extends ConsumerWidget {
  const SessionWarningOverlay({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monitor = ref.watch(inactivityMonitorProvider);
    return ListenableBuilder(
      listenable: monitor,
      child: child,
      builder: (context, child) => Stack(
        fit: StackFit.expand,
        children: [
          child!,
          if (monitor.phase == SessionPhase.warning)
            _SessionWarning(
              remaining: monitor.remaining,
              onStay: ref.read(sessionWatchProvider).activity,
              onSignOut: ref.read(sessionWatchProvider).signOutNow,
            ),
        ],
      ),
    );
  }
}

class _SessionWarning extends StatelessWidget {
  const _SessionWarning({
    required this.remaining,
    required this.onStay,
    required this.onSignOut,
  });

  final Duration remaining;
  final VoidCallback onStay;
  final VoidCallback onSignOut;

  /// `1:59`; never below `0:00`.
  static String format(Duration remaining) {
    final seconds = remaining.inSeconds < 0 ? 0 : remaining.inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final countdown = format(remaining);
    return Semantics(
      container: true,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ModalBarrier(dismissible: false, color: Color(0x73000000)),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Material(
                  color: AppColors.surface,
                  elevation: 12,
                  shadowColor: Colors.black54,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                color: AppColors.surfaceSunken,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.timer_outlined,
                                color: AppColors.primary,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Still there?',
                                style: AppTextStyles.sectionTitle,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          // From the policy, so the warning and the clock
                          // can never name different limits again (it said
                          // 30 here after the limit had become 15).
                          'For your security, GSUhub signs you out after '
                          '${SessionPolicy.inactivityLimit.inMinutes} '
                          'minutes without activity.',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Semantics(
                          liveRegion: true,
                          label: 'Signing out in $countdown',
                          child: ExcludeSemantics(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  countdown,
                                  style: AppTextStyles.statValue.copyWith(
                                    color: AppColors.primary,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'until you are signed out',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: onSignOut,
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.textSecondary,
                              ),
                              child: const Text('Sign out now'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: onStay,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: AppColors.textOnDark,
                              ),
                              child: const Text('Stay signed in'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
