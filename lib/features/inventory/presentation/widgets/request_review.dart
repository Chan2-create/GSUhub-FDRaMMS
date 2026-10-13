import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/enums/material_request_status.dart';
import '../../../../core/routing/route_paths.dart';
import '../../../../core/utils/display_id.dart';
import '../../../../core/utils/quantity_format.dart';
import '../../../../core/utils/relative_time.dart';
import '../../../../core/utils/result.dart';
import '../../data/models/material_line.dart';
import '../../data/models/material_request.dart';
import '../../data/repositories/material_request_repository_impl.dart';
import '../inventory_controller.dart';
import 'inventory_widgets.dart';

/// Technicians' requests for materials, as the console reviews them
/// (Objective 6.B). Not in Figure 15, which has no place for them: a
/// list above the materials, in the page's own card style.

/// "4 units of LED Bulbs, 1 roll of Tape".
String materialLinesSummary(List<MaterialLine> lines) => lines
    .map(
      (line) =>
          '${QuantityFormat.withUnit(line.quantity, line.unitOfMeasurement)} '
          'of ${line.itemName}',
    )
    .join(', ');

/// One request: who asked, for which job, what, and why, with Approve and
/// Decline while it waits.
class MaterialRequestCard extends ConsumerWidget {
  const MaterialRequestCard({
    required this.request,
    this.workOrderTitle,
    this.showWorkOrder = true,
    super.key,
  });

  final MaterialRequest request;
  final String? workOrderTitle;

  /// Off on the work order's own page, where it would repeat itself.
  final bool showWorkOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = request.status;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.borderStrong),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                DisplayId.materialRequest(request.id),
                style: AppTextStyles.inventoryCellStrong,
              ),
              _StatusBadge(status: status),
              Text(
                '${request.requestedByName} · '
                '${RelativeTime.ago(request.createdAt)}',
                style: AppTextStyles.inventoryStatNote,
              ),
              if (showWorkOrder)
                InkWell(
                  onTap: () => context.go(
                    RoutePaths.adminWorkOrderDetailFor(request.workOrderId),
                  ),
                  child: Text(
                    '${DisplayId.workOrder(request.workOrderId)}'
                    '${workOrderTitle == null ? '' : ' · $workOrderTitle'}',
                    style: AppTextStyles.linkText,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            materialLinesSummary(request.items),
            style: AppTextStyles.inventoryCell,
          ),
          if (request.note case final note?) ...[
            const SizedBox(height: 4),
            Text(
              '"$note"',
              style: AppTextStyles.inventoryStatNote.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          if (request.adminNote case final note?) ...[
            const SizedBox(height: 4),
            Text('GSU: "$note"', style: AppTextStyles.inventoryStatNote),
          ],
          if (request.isPending) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                InventoryNavyButton(
                  label: 'Approve',
                  onPressed: () =>
                      showReviewRequestDialog(context, request, approve: true),
                ),
                OutlinedButton(
                  onPressed: () =>
                      showReviewRequestDialog(context, request, approve: false),
                  child: const Text('Decline'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final MaterialRequestStatus status;

  @override
  Widget build(BuildContext context) => switch (status) {
    MaterialRequestStatus.pending => const InventoryBadge(
      label: 'PENDING',
      background: AppColors.inventoryLowStockFill,
      foreground: AppColors.inventoryLowStockText,
    ),
    MaterialRequestStatus.approved => const InventoryBadge(
      label: 'APPROVED',
      background: AppColors.inventoryInStockFill,
      foreground: AppColors.inventoryInStockText,
    ),
    MaterialRequestStatus.declined => const InventoryBadge(
      label: 'DECLINED',
      background: AppColors.inventoryRepairFill,
      foreground: AppColors.inventoryRepairText,
    ),
  };
}

/// Approves [request] (an optional note) or declines it (a note required).
Future<void> showReviewRequestDialog(
  BuildContext context,
  MaterialRequest request, {
  required bool approve,
}) => showDialog<void>(
  context: context,
  builder: (_) => _ReviewDialog(request: request, approve: approve),
);

class _ReviewDialog extends ConsumerStatefulWidget {
  const _ReviewDialog({required this.request, required this.approve});

  final MaterialRequest request;
  final bool approve;

  @override
  ConsumerState<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends ConsumerState<_ReviewDialog> {
  final _note = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final note = _note.text.trim();
    if (!widget.approve && note.isEmpty) {
      setState(() => _error = 'Say why, so the technician knows what to do.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final controller = ref.read(inventoryControllerProvider);
    final result = widget.approve
        ? await controller.approveRequest(
            widget.request.id,
            note: note.isEmpty ? null : note,
          )
        : await controller.declineRequest(widget.request.id, note);
    if (!mounted) return;
    switch (result) {
      case Success():
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              widget.approve
                  ? 'Approved. The materials are on '
                        '${DisplayId.workOrder(widget.request.workOrderId)}, '
                        'and ${widget.request.requestedByName} has been told.'
                  : 'Declined. ${widget.request.requestedByName} has been '
                        'told why.',
            ),
          ),
        );
      case Error(:final failure):
        setState(() {
          _busy = false;
          _error = failure.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    return AlertDialog(
      title: Text(
        '${widget.approve ? 'Approve' : 'Decline'} '
        '${DisplayId.materialRequest(request.id)}?',
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.approve
                  ? '${materialLinesSummary(request.items)} will be '
                        'pre-assigned to '
                        '${DisplayId.workOrder(request.workOrderId)}. Stock '
                        'comes off when the technician reports what was used.'
                  : '${request.requestedByName} asked for '
                        '${materialLinesSummary(request.items)}.',
              style: AppTextStyles.inventoryStatNote,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _note,
              autofocus: true,
              enabled: !_busy,
              maxLines: 3,
              maxLength: MaterialRequestRepositoryImpl.noteLimit,
              decoration: InputDecoration(
                labelText: widget.approve
                    ? 'Note for the technician (optional)'
                    : 'Why it is declined',
                hintText: widget.approve
                    ? 'e.g. collect them from Shelf B'
                    : 'Shown to the technician',
                border: const OutlineInputBorder(),
              ),
            ),
            if (_error case final message?) ...[
              const SizedBox(height: 8),
              Text(
                message,
                style: AppTextStyles.inventoryStatNote.copyWith(
                  color: AppColors.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          style: widget.approve
              ? null
              : FilledButton.styleFrom(backgroundColor: AppColors.error),
          child: Text(
            _busy ? 'Saving…' : (widget.approve ? 'Approve' : 'Decline'),
          ),
        ),
      ],
    );
  }
}
