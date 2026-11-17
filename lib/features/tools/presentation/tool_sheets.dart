import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/di/repository_providers.dart';
import '../../../core/enums/item_condition.dart';
import '../../../core/utils/display_id.dart';
import '../../../core/utils/result.dart';
import '../../qr_codes/presentation/qr_scanner_screen.dart';
import '../../work_orders/data/models/work_order.dart';
import '../../work_orders/presentation/personnel/personnel_providers.dart';
import '../../work_orders/presentation/personnel/personnel_work_controller.dart';
import '../../work_orders/presentation/personnel/widgets/personnel_widgets.dart';
import '../data/models/tool.dart';
import '../data/models/tool_loan.dart';
import '../data/models/tool_request.dart';

/// The technician's side of a tool changing hands (Objective 5.C; since
/// 2026-11-16 every hand-over is confirmed with the code scanned from the
/// tool itself). Not in the design: plain sheets in the app's style,
/// flagged.

final DateFormat _when = DateFormat('MMM d, h:mm a');

/// Scans a code and finds the tool it is on: the code as read, and the
/// tool, or null when the code is on no tool. Null altogether when the
/// technician backs out of the scanner.
Future<(String, Tool?)?> _scanTool(BuildContext context, WidgetRef ref) async {
  final raw = await ref.read(personnelScanLauncherProvider)(context);
  final code = raw?.trim() ?? '';
  if (code.isEmpty) return null;
  final found = await ref.read(toolRepositoryProvider).getToolByQrCode(code);
  return (code, found.fold<Tool?>((tool) => tool, (_) => null));
}

/// What the database says when the wrong code is scanned, said before
/// asking it: "That is Hammer Drill (TL-0006), not Multimeter (TL-0001)."
String _wrongTool(Tool? scanned, String name, String toolCode) =>
    scanned == null
    ? 'That code is not on $name ($toolCode). Scan the QR code on $name.'
    : 'That is ${scanned.name} (${scanned.toolCode}), not $name ($toolCode). '
          'Scan the QR code on $name.';

/// Opens the scanner, then the borrow sheet for the tool scanned:
/// [workOrderId] preselects the work it is for. The technician's own way
/// to take a tool off the shelf (5.C).
Future<void> scanToBorrow(
  BuildContext context,
  WidgetRef ref, {
  String? workOrderId,
}) async {
  final scan = await _scanTool(context, ref);
  if (scan == null || !context.mounted) return;
  final (code, tool) = scan;
  if (tool == null) {
    showPersonnelMessage(context, 'That code is not on any tool.');
    return;
  }
  await showBorrowToolSheet(
    context,
    tool: tool,
    scannedCode: code,
    workOrderId: workOrderId,
  );
}

/// Opens the scanner, then — when the scanned tool is the one on [loan] —
/// the return sheet. [request] is GSU's request for it back, if any.
Future<void> scanToReturn(
  BuildContext context,
  WidgetRef ref,
  ToolLoan loan, {
  ToolRequest? request,
}) async {
  final scan = await _scanTool(context, ref);
  if (scan == null || !context.mounted) return;
  final (code, tool) = scan;
  if (tool?.id != loan.toolId) {
    final own = await ref.read(toolRepositoryProvider).getToolById(loan.toolId);
    if (!context.mounted) return;
    showPersonnelMessage(
      context,
      _wrongTool(
        tool,
        loan.toolName,
        own.fold((own) => own.toolCode, (_) => request?.toolCode ?? '—'),
      ),
    );
    return;
  }
  await showReturnToolSheet(context, loan, scannedCode: code, request: request);
}

/// Opens the scanner, then — when the scanned tool is the one GSU checked
/// out to the technician — the sheet to confirm receiving it.
Future<void> scanToConfirmCheckOut(
  BuildContext context,
  WidgetRef ref,
  ToolRequest request,
) async {
  final scan = await _scanTool(context, ref);
  if (scan == null || !context.mounted) return;
  final (code, tool) = scan;
  if (tool?.id != request.toolId) {
    showPersonnelMessage(
      context,
      _wrongTool(tool, request.toolName, request.toolCode),
    );
    return;
  }
  await showConfirmCheckOutSheet(context, request, scannedCode: code);
}

Future<void> _sheet(BuildContext context, Widget sheet) {
  // A message still showing would sit over the sheet (Objective 7.B).
  ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: sheet,
    ),
  );
}

// ---------------------------------------------------------------- borrowing

/// Borrowing [tool], whose code [scannedCode] was just scanned (5.C);
/// [workOrderId] preselects the work it is for.
Future<void> showBorrowToolSheet(
  BuildContext context, {
  required Tool tool,
  required String scannedCode,
  String? workOrderId,
}) => _sheet(
  context,
  _BorrowToolSheet(
    tool: tool,
    scannedCode: scannedCode,
    workOrderId: workOrderId,
  ),
);

class _BorrowToolSheet extends ConsumerStatefulWidget {
  const _BorrowToolSheet({
    required this.tool,
    required this.scannedCode,
    required this.workOrderId,
  });

  final Tool tool;
  final String scannedCode;
  final String? workOrderId;

  @override
  ConsumerState<_BorrowToolSheet> createState() => _BorrowToolSheetState();
}

class _BorrowToolSheetState extends ConsumerState<_BorrowToolSheet> {
  late String? _workOrderId = widget.workOrderId;
  bool _busy = false;
  String? _error;

  Future<void> _borrow() async {
    final tool = widget.tool;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(personnelWorkControllerProvider)
        .borrowTool(
          toolId: tool.id,
          scannedCode: widget.scannedCode,
          workOrderId: _workOrderId,
        );
    if (!mounted) return;
    switch (result) {
      case Success():
        Navigator.of(context).pop();
        showPersonnelMessage(
          context,
          'You have ${tool.name}. Scan it again when you return it.',
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
    final tool = widget.tool;
    final open = switch (ref.watch(myWorkOrdersProvider)) {
      AsyncData(value: Success(:final value)) => [
        for (final order in value)
          if (MyWork.isOpen(order.status)) order,
      ],
      _ => const <WorkOrder>[],
    };

    return _SheetBody(
      title: 'Borrow a tool',
      intro:
          'It is recorded against you until you return it, with the '
          'condition it is in now.',
      children: [
        PersonnelCard(
          color: AppColors.personnelTile,
          child: ToolSummary(tool: tool),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String?>(
          initialValue: _workOrderId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'For work order',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem(child: Text('None')),
            for (final order in open)
              DropdownMenuItem(
                value: order.id,
                child: Text(
                  '${DisplayId.workOrder(order.id)} · ${order.title}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _busy ? null : (id) => setState(() => _workOrderId = id),
        ),
        _ErrorLine(_error),
        const SizedBox(height: 16),
        _SheetButton(
          label: _busy ? 'Saving…' : 'Borrow',
          onPressed: _busy || !tool.status.isIssuable ? null : _borrow,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- receiving

/// Confirming GSU's checkout [request]: the tool was just scanned with
/// [scannedCode]. The tool is the technician's once they confirm.
Future<void> showConfirmCheckOutSheet(
  BuildContext context,
  ToolRequest request, {
  required String scannedCode,
}) => _sheet(
  context,
  _ConfirmCheckOutSheet(request: request, scannedCode: scannedCode),
);

class _ConfirmCheckOutSheet extends ConsumerStatefulWidget {
  const _ConfirmCheckOutSheet({
    required this.request,
    required this.scannedCode,
  });

  final ToolRequest request;
  final String scannedCode;

  @override
  ConsumerState<_ConfirmCheckOutSheet> createState() =>
      _ConfirmCheckOutSheetState();
}

class _ConfirmCheckOutSheetState extends ConsumerState<_ConfirmCheckOutSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(personnelWorkControllerProvider)
        .confirmCheckOut(
          requestId: widget.request.id,
          scannedCode: widget.scannedCode,
        );
    if (!mounted) return;
    switch (result) {
      case Success():
        Navigator.of(context).pop();
        showPersonnelMessage(
          context,
          'You have ${widget.request.toolName}. GSU has been told.',
        );
      case Error(:final failure):
        setState(() {
          _busy = false;
          _error = failure.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) => _SheetBody(
    title: 'Confirm you have ${widget.request.toolName}',
    intro:
        'You scanned ${widget.scannedCode}, the code on the tool GSU '
        'checked out to you. Confirm only once it is in your hands.',
    children: [
      ToolRequestCard(request: widget.request),
      _ErrorLine(_error),
      const SizedBox(height: 16),
      _SheetButton(
        label: _busy ? 'Saving…' : 'Confirm receipt',
        onPressed: _busy ? null : _confirm,
      ),
    ],
  );
}

// ---------------------------------------------------------------- returning

/// Returning [loan]'s tool, just scanned with [scannedCode]: what
/// condition it comes back in, and a note (5.C). Poor sends it to repair
/// rather than back on the shelf. [request] is GSU's request for it back,
/// if there is one; the return confirms it.
Future<void> showReturnToolSheet(
  BuildContext context,
  ToolLoan loan, {
  required String scannedCode,
  ToolRequest? request,
}) => _sheet(
  context,
  _ReturnToolSheet(loan: loan, scannedCode: scannedCode, request: request),
);

class _ReturnToolSheet extends ConsumerStatefulWidget {
  const _ReturnToolSheet({
    required this.loan,
    required this.scannedCode,
    required this.request,
  });

  final ToolLoan loan;
  final String scannedCode;
  final ToolRequest? request;

  @override
  ConsumerState<_ReturnToolSheet> createState() => _ReturnToolSheetState();
}

class _ReturnToolSheetState extends ConsumerState<_ReturnToolSheet> {
  late ItemCondition _condition = widget.loan.conditionOnBorrow;
  final _notes = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _return() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final notes = _notes.text.trim();
    final result = await ref
        .read(personnelWorkControllerProvider)
        .returnTool(
          loanId: widget.loan.id,
          scannedCode: widget.scannedCode,
          condition: _condition,
          notes: notes.isEmpty ? null : notes,
        );
    if (!mounted) return;
    switch (result) {
      case Success():
        Navigator.of(context).pop();
        showPersonnelMessage(
          context,
          '${widget.loan.toolName} returned. GSU has been told.',
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
    final loan = widget.loan;
    final request = widget.request;
    return _SheetBody(
      title: 'Return ${loan.toolName}',
      intro:
          'You scanned ${widget.scannedCode}. Borrowed '
          '${_when.format(loan.borrowedAt.toLocal())} in '
          '${loan.conditionOnBorrow.label.toLowerCase()} condition. Confirm '
          'only once you have handed it back to GSU.',
      children: [
        if (request != null) ...[
          ToolRequestCard(request: request),
          const SizedBox(height: 16),
        ],
        const Text('CONDITION NOW', style: AppTextStyles.personnelChip),
        const SizedBox(height: 8),
        SegmentedButton<ItemCondition>(
          segments: [
            for (final condition in ItemCondition.values)
              ButtonSegment(value: condition, label: Text(condition.label)),
          ],
          selected: {_condition},
          showSelectedIcon: false,
          onSelectionChanged: _busy
              ? null
              : (selection) => setState(() => _condition = selection.single),
        ),
        if (_condition == ItemCondition.poor) ...[
          const SizedBox(height: 8),
          const Text(
            'A tool returned in poor condition goes to repair.',
            style: AppTextStyles.personnelCardBody,
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: _notes,
          enabled: !_busy,
          maxLines: 3,
          maxLength: 300,
          decoration: const InputDecoration(
            labelText: 'Notes (optional)',
            hintText: 'Anything GSU should know about it',
            border: OutlineInputBorder(),
          ),
        ),
        _ErrorLine(_error),
        const SizedBox(height: 12),
        _SheetButton(
          label: _busy ? 'Saving…' : 'Confirm return',
          onPressed: _busy ? null : _return,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- pieces

/// What GSU asked, as the technician reads it: collect or return, the
/// tool, when, why, the message, and how it stands now.
class ToolRequestCard extends StatelessWidget {
  const ToolRequestCard({required this.request, this.action, super.key});

  final ToolRequest request;

  /// A button under it: "Scan to confirm", "Scan to return".
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final status = request.statusAt(DateTime.now());
    final late = status == ToolTransactionStatus.overdue;
    final when = switch (request.kind) {
      ToolRequestKind.checkOut => [
        if (request.checkoutAt case final at?)
          'Collect ${_when.format(at.toLocal())}',
        if (request.dueAt case final at?)
          'back by ${_when.format(at.toLocal())}',
      ].join(' · '),
      ToolRequestKind.checkIn =>
        'Return by ${_when.format(request.dueAt!.toLocal())}',
    };
    return PersonnelCard(
      edge: late ? AppColors.error : AppColors.accentGold,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  request.kind == ToolRequestKind.checkOut
                      ? 'GSU checked out to you'
                      : 'GSU asks for it back',
                  style: AppTextStyles.personnelChip,
                ),
              ),
              PersonnelChip(
                status.label,
                background: late
                    ? AppColors.personnelUrgentFill
                    : AppColors.personnelStockFill,
                foreground: late
                    ? AppColors.personnelUrgentText
                    : AppColors.personnelStockText,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${request.toolName} · ${request.toolCode}',
            style: AppTextStyles.personnelCardTitle,
          ),
          const SizedBox(height: 2),
          Text(when, style: AppTextStyles.personnelCardBody),
          if (request.purpose case final purpose?) ...[
            const SizedBox(height: 4),
            Text('For: $purpose', style: AppTextStyles.personnelCardBody),
          ],
          if (request.workOrderId case final id?)
            Text(
              'Work order ${DisplayId.workOrder(id)}',
              style: AppTextStyles.personnelCardBody,
            ),
          if (request.message case final message?) ...[
            const SizedBox(height: 4),
            Text(
              '“$message”',
              style: AppTextStyles.personnelCardBody.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          if (action case final action?) ...[
            const SizedBox(height: 12),
            action,
          ],
        ],
      ),
    );
  }
}

/// A tool's name, code, condition and where it is kept.
class ToolSummary extends StatelessWidget {
  const ToolSummary({required this.tool, super.key});

  final Tool tool;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.handyman_outlined, color: AppColors.personnelTitle),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tool.name, style: AppTextStyles.personnelCardTitle),
            const SizedBox(height: 2),
            Text(
              [
                tool.toolCode,
                '${tool.condition.label} condition',
                ?tool.storageLocation,
              ].join(' · '),
              style: AppTextStyles.personnelCardBody,
            ),
          ],
        ),
      ),
      PersonnelChip(
        tool.status.label,
        background: tool.status.isIssuable
            ? AppColors.personnelStockFill
            : AppColors.personnelUrgentFill,
        foreground: tool.status.isIssuable
            ? AppColors.personnelStockText
            : AppColors.personnelUrgentText,
      ),
    ],
  );
}

class _SheetBody extends StatelessWidget {
  const _SheetBody({
    required this.title,
    required this.intro,
    required this.children,
  });

  final String title;
  final String intro;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: AppTextStyles.personnelSection),
            const SizedBox(height: 4),
            Text(intro, style: AppTextStyles.personnelCardBody),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    ),
  );
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.message);

  final String? message;

  @override
  Widget build(BuildContext context) {
    final message = this.message;
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        message,
        style: AppTextStyles.personnelCardBody.copyWith(color: AppColors.error),
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      backgroundColor: AppColors.textPrimary,
      minimumSize: const Size.fromHeight(48),
    ),
    child: Text(label),
  );
}
