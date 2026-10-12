import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/repository_providers.dart';
import '../../../core/errors/failures.dart';
import '../../../core/utils/result.dart';
import '../../audit/presentation/current_actor_provider.dart';
import 'keyword_draft.dart';

/// Saves the keyword dictionary edited on the Settings page (Objective
/// 4.A).
///
/// The saved document names who saved it and when (`updatedBy`,
/// `updatedAt`); the rules let only an administrator write it. Reports
/// already filed keep their damage type: the new keywords apply to reports
/// filed from now on.
class KeywordSettingsController {
  const KeywordSettingsController(this._ref);

  final Ref _ref;

  Future<Result<void>> save(KeywordDraft draft) async {
    final actor = await _ref.read(currentActorProvider.future);
    if (actor == null) {
      return const Result.failure(
        PermissionFailure('Your session has expired. Please sign in again.'),
      );
    }
    return _ref
        .read(configRepositoryProvider)
        .updateClassificationRules(
          draft.toConfig(
            updatedAt: DateTime.now().toUtc(),
            updatedBy: actor.id,
          ),
        );
  }
}

final keywordSettingsControllerProvider = Provider(
  KeywordSettingsController.new,
);
