import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/storage_paths.dart';
import '../../../../core/di/repository_providers.dart';
import '../../../../core/di/service_providers.dart';
import '../../../../core/enums/item_condition.dart';
import '../../../../core/enums/task_status.dart';
import '../../../../core/enums/work_order_status.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/services/photo_picker_service.dart';
import '../../../../core/utils/result.dart';
import '../../../accomplishment/data/models/material_usage.dart';
import '../../../audit/data/models/audit_actor.dart';
import '../../../audit/presentation/current_actor_provider.dart';

/// What a technician does in the personnel app (Objectives 5.A–5.C).
///
/// Thin on purpose, like the console's controllers: the rules — who may
/// act, on which work, in which order — live in the repositories and the
/// security rules. This resolves who is acting, and uploads photos before
/// handing their addresses over.
class PersonnelWorkController {
  const PersonnelWorkController(this._ref);

  final Ref _ref;

  /// Starts a pending work order (5.B).
  Future<Result<void>> startWork(String workOrderId) => _act(
    (actor) => _ref
        .read(workOrderRepositoryProvider)
        .setStatus(workOrderId, WorkOrderStatus.inProgress, actor: actor),
  );

  /// Ticks a task done, or back to do (5.A).
  Future<Result<void>> setTaskStatus(String taskId, TaskStatus status) => _act(
    (actor) => _ref
        .read(taskRepositoryProvider)
        .setStatus(taskId: taskId, status: status, actor: actor),
  );

  /// Uploads [photos] as proof for a task, then attaches them (5.A).
  Future<Result<void>> uploadProof(String taskId, List<PickedPhoto> photos) =>
      _act((actor) async {
        final uploaded = await _upload(
          photos,
          (name) => StoragePaths.taskProofPhoto(taskId, name),
        );
        return switch (uploaded) {
          Success(:final value) =>
            _ref
                .read(taskRepositoryProvider)
                .addProofPhotos(taskId: taskId, photoUrls: value, actor: actor),
          Error(:final failure) => Result.failure(failure),
        };
      });

  /// Records [quantity] of an item as used on a work order (5.C).
  Future<Result<void>> recordMaterial({
    required String workOrderId,
    required String inventoryItemId,
    required double quantity,
  }) => _act(
    (actor) => _ref
        .read(materialUsageRepositoryProvider)
        .record(
          workOrderId: workOrderId,
          inventoryItemId: inventoryItemId,
          quantity: quantity,
          actor: actor,
        ),
  );

  Future<Result<void>> removeMaterial({
    required String workOrderId,
    required String inventoryItemId,
  }) => _ref
      .read(materialUsageRepositoryProvider)
      .remove(workOrderId: workOrderId, inventoryItemId: inventoryItemId);

  /// Borrows a tool, for a work order or none (5.C).
  Future<Result<void>> borrowTool({
    required String toolId,
    String? workOrderId,
  }) => _act(
    (actor) async => switch (await _ref
        .read(toolRepositoryProvider)
        .borrowTool(
          toolId: toolId,
          borrower: actor,
          workOrderId: workOrderId,
        )) {
      Success() => const Result.success(null),
      Error(:final failure) => Result.failure(failure),
    },
  );

  /// Returns a tool, saying what condition it is in (5.C).
  Future<Result<void>> returnTool({
    required String loanId,
    required ItemCondition condition,
    String? notes,
  }) => _act(
    (actor) => _ref
        .read(toolRepositoryProvider)
        .returnTool(
          loanId: loanId,
          conditionOnReturn: condition,
          actor: actor,
          notes: notes,
        ),
  );

  /// Files the finished work (5.B): uploads [photos] under [reportId],
  /// then submits the report with [materialsUsed], which deducts them.
  ///
  /// [reportId] is reserved by the caller once per attempt and reused on
  /// retry, so a submission that reached the server but timed out on the
  /// way back is not filed twice.
  Future<Result<void>> submitAccomplishment({
    required String reportId,
    required String workOrderId,
    required String completionNotes,
    required List<PickedPhoto> photos,
    required List<MaterialUsage> materialsUsed,
  }) => _act((actor) async {
    final uploaded = await _upload(
      photos,
      (name) => StoragePaths.accomplishmentPhoto(reportId, name),
    );
    return switch (uploaded) {
      Success(:final value) =>
        _ref
            .read(accomplishmentReportRepositoryProvider)
            .submit(
              reportId: reportId,
              workOrderId: workOrderId,
              completionNotes: completionNotes,
              photoUrls: value,
              materialsUsed: materialsUsed,
              actor: actor,
            ),
      Error(:final failure) => Result.failure(failure),
    };
  });

  /// Uploads [photos] one by one, naming each uniquely per attempt: the
  /// rules refuse overwriting a file, so a retry under the same name
  /// would fail for good.
  Future<Result<List<String>>> _upload(
    List<PickedPhoto> photos,
    String Function(String fileName) pathFor,
  ) async {
    final storage = _ref.read(storageServiceProvider);
    final urls = <String>[];
    final stamp = DateTime.now().millisecondsSinceEpoch;
    for (var index = 0; index < photos.length; index++) {
      final photo = photos[index];
      final result = await storage.uploadFile(
        path: pathFor('photo-${index + 1}-$stamp${_extensionOf(photo)}'),
        bytes: photo.bytes,
        contentType: photo.mimeType,
      );
      switch (result) {
        case Success(:final value):
          urls.add(value);
        case Error(:final failure):
          return Result.failure(failure);
      }
    }
    return Result.success(urls);
  }

  static String _extensionOf(PickedPhoto photo) => switch (photo.mimeType) {
    'image/png' => '.png',
    'image/webp' => '.webp',
    'image/heic' => '.heic',
    _ => '.jpg',
  };

  Future<Result<void>> _act(
    Future<Result<void>> Function(AuditActor actor) action,
  ) async {
    final actor = await _ref.read(currentActorProvider.future);
    if (actor == null) {
      return const Result.failure(
        PermissionFailure('Your session has expired. Please sign in again.'),
      );
    }
    return action(actor);
  }
}

final personnelWorkControllerProvider = Provider(PersonnelWorkController.new);
