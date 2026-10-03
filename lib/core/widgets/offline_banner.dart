import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../di/service_providers.dart';
import '../services/connectivity_service.dart';

/// A strip that says the backend cannot be reached, shown only while it
/// cannot (§1.5 makes connectivity a requirement).
///
/// Screens that update live (Objective 3.B) keep showing what Firestore
/// last cached when the connection drops, and nothing on them changes to
/// say so. Without this, a report that has moved on would sit on screen
/// looking current.
///
/// Neither the design nor the manuscript draws an offline state, so this
/// is plain — flagged in the 3.B report.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline =
        ref.watch(reachabilityProvider).value == BackendReachability.offline;
    if (!offline) return const SizedBox.shrink();

    return Semantics(
      liveRegion: true,
      child: ColoredBox(
        color: AppColors.ctaAmber,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(
                Icons.cloud_off_outlined,
                size: 18,
                color: AppColors.ctaAmberForeground,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "You're offline. Showing your last saved updates until the "
                  'connection is back.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.ctaAmberForeground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
