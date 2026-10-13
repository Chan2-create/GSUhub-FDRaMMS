import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/storage_paths.dart';
import '../../../core/di/repository_providers.dart';
import '../../../core/di/service_providers.dart';
import '../../../core/enums/item_condition.dart';
import '../../../core/enums/tool_status.dart';
import '../../../core/errors/failures.dart';
import '../../../core/services/photo_picker_service.dart';
import '../../../core/utils/result.dart';
import '../../audit/data/models/audit_actor.dart';
import '../../audit/presentation/current_actor_provider.dart';
import '../../facilities/data/models/facility_draft.dart';
import '../../tools/data/models/tool_draft.dart';
import '../data/models/inventory_item_draft.dart';

/// What an administrator does on the Inventory Management and Facilities
/// pages (Objective 6).
///
/// Thin on purpose, like the console's other controllers: who may act and
/// on what is the repositories' and the security rules' business. This
/// resolves who is acting, and uploads a material's photo before saving
/// its address.
class InventoryController {
  const InventoryController(this._ref);

  final Ref _ref;

  /// Adds a material with its [openingStock], then its [photo] if one was
  /// picked. A photo that fails to upload leaves the material saved
  /// without one, and says so.
  Future<Result<String>> createMaterial({
    required InventoryItemDraft draft,
    required double openingStock,
    PickedPhoto? photo,
  }) => _actFor((actor) async {
    final repository = _ref.read(inventoryRepositoryProvider);
    final created = await repository.createItem(
      draft: draft,
      openingStock: openingStock,
      actor: actor,
    );
    if (photo == null) return created;
    final id = switch (created) {
      Success(:final value) => value,
      Error() => null,
    };
    if (id == null) return created;

    final withPhoto = await _savePhoto(id, draft, photo, actor);
    return switch (withPhoto) {
      Success() => Result.success(id),
      Error(:final failure) => Result.failure(
        UnknownFailure(
          'The material was added, but its photo was not: '
          '${failure.message}',
        ),
      ),
    };
  });

  /// Saves a material's details, with a new [photo] if one was picked.
  Future<Result<void>> updateMaterial({
    required String itemId,
    required InventoryItemDraft draft,
    PickedPhoto? photo,
  }) => _act((actor) async {
    if (photo != null) return _savePhoto(itemId, draft, photo, actor);
    return _ref
        .read(inventoryRepositoryProvider)
        .updateItemDetails(itemId: itemId, draft: draft, actor: actor);
  });

  Future<Result<void>> _savePhoto(
    String itemId,
    InventoryItemDraft draft,
    PickedPhoto photo,
    AuditActor actor,
  ) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final extension = switch (photo.mimeType) {
      'image/png' => '.png',
      'image/webp' => '.webp',
      _ => '.jpg',
    };
    final uploaded = await _ref
        .read(storageServiceProvider)
        .uploadFile(
          path: StoragePaths.inventoryPhoto(itemId, 'photo-$stamp$extension'),
          bytes: photo.bytes,
          contentType: photo.mimeType,
        );
    return switch (uploaded) {
      Success(:final value) =>
        _ref
            .read(inventoryRepositoryProvider)
            .updateItemDetails(
              itemId: itemId,
              draft: InventoryItemDraft(
                name: draft.name,
                category: draft.category,
                unitOfMeasurement: draft.unitOfMeasurement,
                storageLocation: draft.storageLocation,
                qrCode: draft.qrCode,
                minimumThreshold: draft.minimumThreshold,
                specification: draft.specification,
                unitCost: draft.unitCost,
                photoUrl: value,
              ),
              actor: actor,
            ),
      Error(:final failure) => Result.failure(failure),
    };
  }

  Future<Result<void>> recordDelivery({
    required String itemId,
    required double quantity,
    String? notes,
  }) => _act(
    (actor) async => _done(
      await _ref
          .read(inventoryRepositoryProvider)
          .recordDelivery(
            itemId: itemId,
            quantity: quantity,
            actor: actor,
            notes: notes,
          ),
    ),
  );

  Future<Result<void>> recordStockCount({
    required String itemId,
    required double countedQuantity,
    required String reason,
  }) => _act(
    (actor) async => _done(
      await _ref
          .read(inventoryRepositoryProvider)
          .recordStockCount(
            itemId: itemId,
            countedQuantity: countedQuantity,
            actor: actor,
            reason: reason,
          ),
    ),
  );

  Future<Result<void>> createTool(ToolDraft draft) => _act(
    (actor) async => _done(
      await _ref
          .read(toolRepositoryProvider)
          .createTool(draft: draft, actor: actor),
    ),
  );

  Future<Result<void>> updateTool(String toolId, ToolDraft draft) => _act(
    (actor) => _ref
        .read(toolRepositoryProvider)
        .updateToolDetails(toolId: toolId, draft: draft, actor: actor),
  );

  Future<Result<void>> setToolStatus(String toolId, ToolStatus status) => _act(
    (actor) => _ref
        .read(toolRepositoryProvider)
        .setToolStatus(toolId: toolId, status: status, actor: actor),
  );

  /// Figure 15's Check Out: lends [toolId] to a technician.
  Future<Result<void>> checkOut({
    required String toolId,
    required AuditActor technician,
    String? workOrderId,
    DateTime? expectedReturnAt,
  }) => _act(
    (actor) async => _done(
      await _ref
          .read(toolRepositoryProvider)
          .borrowTool(
            toolId: toolId,
            borrower: technician,
            issuedBy: actor,
            workOrderId: workOrderId,
            expectedReturnAt: expectedReturnAt,
          ),
    ),
  );

  /// Figure 15's Check In: closes the loan with the condition it came
  /// back in.
  Future<Result<void>> checkIn({
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

  Future<Result<void>> approveRequest(String requestId, {String? note}) => _act(
    (actor) => _ref
        .read(materialRequestRepositoryProvider)
        .approve(requestId: requestId, actor: actor, note: note),
  );

  Future<Result<void>> declineRequest(String requestId, String note) => _act(
    (actor) => _ref
        .read(materialRequestRepositoryProvider)
        .decline(requestId: requestId, actor: actor, note: note),
  );

  /// Sets how much of a material is pre-assigned to a work order.
  Future<Result<void>> allocate({
    required String workOrderId,
    required String inventoryItemId,
    required double quantity,
  }) => _act(
    (actor) => _ref
        .read(materialAllocationRepositoryProvider)
        .allocate(
          workOrderId: workOrderId,
          inventoryItemId: inventoryItemId,
          quantity: quantity,
          actor: actor,
        ),
  );

  Future<Result<void>> removeAllocation({
    required String workOrderId,
    required String inventoryItemId,
  }) => _act(
    (actor) => _ref
        .read(materialAllocationRepositoryProvider)
        .remove(
          workOrderId: workOrderId,
          inventoryItemId: inventoryItemId,
          actor: actor,
        ),
  );

  Future<Result<void>> createFacility(FacilityDraft draft) => _act(
    (actor) async => _done(
      await _ref
          .read(facilityRepositoryProvider)
          .createFacility(draft: draft, actor: actor),
    ),
  );

  Future<Result<void>> updateFacility(String id, FacilityDraft draft) => _act(
    (actor) => _ref
        .read(facilityRepositoryProvider)
        .updateFacility(facilityId: id, draft: draft, actor: actor),
  );

  Future<Result<void>> setFacilityActive(String id, {required bool active}) =>
      _act(
        (actor) => _ref
            .read(facilityRepositoryProvider)
            .setFacilityActive(facilityId: id, active: active, actor: actor),
      );

  Future<Result<void>> createAsset(AssetDraft draft) => _act(
    (actor) async => _done(
      await _ref
          .read(facilityRepositoryProvider)
          .createAsset(draft: draft, actor: actor),
    ),
  );

  Future<Result<void>> updateAsset(String id, AssetDraft draft) => _act(
    (actor) => _ref
        .read(facilityRepositoryProvider)
        .updateAsset(assetId: id, draft: draft, actor: actor),
  );

  Future<Result<void>> setAssetActive(String id, {required bool active}) =>
      _act(
        (actor) => _ref
            .read(facilityRepositoryProvider)
            .setAssetActive(assetId: id, active: active, actor: actor),
      );

  static Result<void> _done(Result<Object?> result) => switch (result) {
    Success() => const Result.success(null),
    Error(:final failure) => Result.failure(failure),
  };

  Future<Result<void>> _act(
    Future<Result<void>> Function(AuditActor actor) action,
  ) => _actFor(action);

  Future<Result<T>> _actFor<T>(
    Future<Result<T>> Function(AuditActor actor) action,
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

final inventoryControllerProvider = Provider(InventoryController.new);
