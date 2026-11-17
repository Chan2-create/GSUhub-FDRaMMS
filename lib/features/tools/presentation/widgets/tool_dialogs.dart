import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/enums/account_status.dart';
import '../../../../core/enums/item_condition.dart';
import '../../../../core/enums/tool_status.dart';
import '../../../../core/utils/display_id.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/confirm_delete_dialog.dart';
import '../../../audit/data/models/audit_actor.dart';
import '../../../inventory/presentation/inventory_controller.dart';
import '../../../inventory/presentation/widgets/inventory_widgets.dart';
import '../../../qr_codes/presentation/qr_label.dart';
import '../../../qr_codes/presentation/qr_label_actions.dart';
import '../../../user_management/data/models/app_user.dart';
import '../../../user_management/presentation/accounts_providers.dart';
import '../../../user_management/presentation/personnel_providers.dart';
import '../../../work_orders/data/models/work_order.dart';
import '../../../work_orders/presentation/personnel/personnel_providers.dart'
    show MyWork;
import '../../../work_orders/presentation/work_order_providers.dart';
import '../../data/models/tool.dart';
import '../../data/models/tool_draft.dart';
import '../../data/models/tool_loan.dart';
import '../../data/models/tool_request.dart';
import '../tool_providers.dart';
import 'tool_request_widgets.dart';

/// The tool dialogs of the Inventory page (Objective 6.B): adding and
/// editing a tool, Figure 15's Check Out and Check In, and a tool's
/// details. The design shows the buttons; the dialogs use the console's
/// dialog and field styles.

/// Adds a tool, or edits [tool].
Future<void> showToolFormDialog(BuildContext context, {Tool? tool}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _ToolFormDialog(tool: tool),
    );

class _ToolFormDialog extends ConsumerStatefulWidget {
  const _ToolFormDialog({this.tool});

  final Tool? tool;

  @override
  ConsumerState<_ToolFormDialog> createState() => _ToolFormDialogState();
}

class _ToolFormDialogState extends ConsumerState<_ToolFormDialog> {
  late final _code = TextEditingController(text: widget.tool?.toolCode);
  late final _name = TextEditingController(text: widget.tool?.name);
  late final _category = TextEditingController(text: widget.tool?.category);
  late final _location = TextEditingController(
    text: widget.tool?.storageLocation,
  );
  late final _qr = TextEditingController(text: widget.tool?.qrCode);
  late ItemCondition _condition = widget.tool?.condition ?? ItemCondition.good;
  String? _error;
  bool _busy = false;

  bool get _editing => widget.tool != null;

  @override
  void dispose() {
    for (final controller in [_code, _name, _category, _location, _qr]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final draft = ToolDraft(
      toolCode: _code.text,
      name: _name.text,
      condition: _condition,
      qrCode: _qr.text.trim().isEmpty
          ? ToolDraft.defaultQrCode(_code.text)
          : _qr.text,
      category: _category.text,
      storageLocation: _location.text,
    );
    if (draft.problem case final problem?) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final controller = ref.read(inventoryControllerProvider);
    final result = _editing
        ? await controller.updateTool(widget.tool!.id, draft)
        : await controller.createTool(draft);
    if (!mounted) return;
    switch (result) {
      case Success():
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              _editing
                  ? 'Saved ${draft.normalized().name}.'
                  : 'Added ${draft.normalized().name} to the tools.',
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
    final out = widget.tool?.status == ToolStatus.borrowed;
    Widget field(
      TextEditingController controller,
      String label, {
      String? hint,
      int? maxLength,
    }) => TextField(
      controller: controller,
      enabled: !_busy,
      maxLength: maxLength,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
        border: const OutlineInputBorder(),
      ),
    );

    return AlertDialog(
      title: Text(_editing ? 'Edit tool' : 'Add new tool'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 150,
                    child: field(
                      _code,
                      'Tool ID',
                      hint: 'TL-0824',
                      maxLength: ToolDraft.codeLimit,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: field(
                      _name,
                      'Tool name',
                      hint: 'e.g. DeWalt Impact Driver 20V',
                      maxLength: ToolDraft.nameLimit,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: field(
                      _category,
                      'Type (optional)',
                      hint: 'e.g. Power Tools',
                      maxLength: ToolDraft.shortLimit,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: field(
                      _location,
                      'Kept at (optional)',
                      maxLength: ToolDraft.nameLimit,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ItemCondition>(
                isExpanded: true,
                initialValue: _condition,
                decoration: InputDecoration(
                  labelText: 'Condition',
                  helperText: out
                      ? 'Out with a technician: Check In records the '
                            'condition it comes back in.'
                      : null,
                  helperMaxLines: 2,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final condition in ItemCondition.values)
                    DropdownMenuItem(
                      value: condition,
                      child: Text(condition.label),
                    ),
                ],
                onChanged: _busy || out
                    ? null
                    : (value) => setState(() => _condition = value!),
              ),
              const SizedBox(height: 12),
              field(
                _qr,
                _editing ? 'Code on its label' : 'Code on its label (optional)',
                hint: _editing ? null : 'TOOL- and the tool ID if empty',
                maxLength: ToolDraft.qrCodeLimit,
              ),
              if (_error case final message?) ...[
                const SizedBox(height: 12),
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
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Saving…' : (_editing ? 'Save' : 'Add tool')),
        ),
      ],
    );
  }
}

/// Figure 15's Check Out (2026-11-16): asks a technician to collect a
/// tool. Nothing is lent here: the tool is reserved for them, and becomes
/// theirs only when they scan its QR code in the app and confirm.
Future<void> showCheckOutDialog(BuildContext context, Tool tool) =>
    showDialog<void>(
      context: context,
      builder: (_) => _CheckOutDialog(tool: tool),
    );

class _CheckOutDialog extends ConsumerStatefulWidget {
  const _CheckOutDialog({required this.tool});

  final Tool tool;

  @override
  ConsumerState<_CheckOutDialog> createState() => _CheckOutDialogState();
}

class _CheckOutDialogState extends ConsumerState<_CheckOutDialog> {
  late Tool _tool = widget.tool;
  AppUser? _technician;
  String? _workOrderId;
  DateTime _checkoutAt = DateTime.now();
  DateTime? _dueAt;
  final _purpose = TextEditingController();
  final _message = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _purpose.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final technician = _technician;
    final purpose = _purpose.text.trim();
    final problem = technician == null
        ? 'Pick the technician to collect it.'
        : purpose.isEmpty
        ? 'Say what the tool is for.'
        : _dueAt != null && !_dueAt!.isAfter(_checkoutAt)
        ? 'The expected return must be after the checkout.'
        : null;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final message = _message.text.trim();
    final result = await ref
        .read(inventoryControllerProvider)
        .checkOut(
          toolId: _tool.id,
          technician: AuditActor(id: technician!.id, name: technician.fullName),
          checkoutAt: _checkoutAt,
          purpose: purpose,
          dueAt: _dueAt,
          message: message.isEmpty ? null : message,
          workOrderId: _workOrderId,
        );
    if (!mounted) return;
    switch (result) {
      case Success():
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Asked ${technician.fullName} to collect ${_tool.name}. It is '
              'theirs once they scan it.',
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
    final tools = switch (ref.watch(allToolsProvider)) {
      AsyncData(value: Success(:final value)) => [
        for (final tool in value)
          if (tool.status == ToolStatus.available || tool.id == _tool.id) tool,
      ],
      _ => [_tool],
    };
    final people = switch (ref.watch(personnelStreamProvider)) {
      AsyncData(value: Success(:final value)) => [
        for (final person in value)
          if (person.accountStatus == AccountStatus.active) person,
      ],
      _ => const <AppUser>[],
    };
    final technician = _technician;
    final orders = switch (ref.watch(workOrdersStreamProvider)) {
      AsyncData(value: Success(:final value)) when technician != null => [
        for (final order in value)
          if (MyWork.isOpen(order.status) &&
              order.assignedPersonnelIds.contains(technician.id))
            order,
      ],
      _ => const <WorkOrder>[],
    };

    return AlertDialog(
      title: const Text('Check out a tool'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'The technician is told, and the tool is reserved for them. '
                'It becomes theirs when they scan its QR code in GSUhub and '
                'confirm they have it.',
                style: AppTextStyles.inventoryStatNote,
              ),
              const SizedBox(height: 16),
              // By id: the live list hands over new records as tools
              // change, and a picker matches its value by equality.
              DropdownButtonFormField<String>(
                initialValue: _tool.id,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Tool',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final tool in tools)
                    DropdownMenuItem(
                      value: tool.id,
                      child: Text(
                        '${tool.name} · ${tool.toolCode} · '
                        '${tool.condition.label.toLowerCase()} condition',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (id) => setState(
                        () => _tool = tools.firstWhere(
                          (tool) => tool.id == id,
                          orElse: () => _tool,
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<AppUser>(
                initialValue: technician,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Technician',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final person in people)
                    DropdownMenuItem(
                      value: person,
                      child: Text(person.fullName),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (person) => setState(() {
                        _technician = person;
                        _workOrderId = null;
                      }),
              ),
              const SizedBox(height: 12),
              DateTimeField(
                label: 'Collect on',
                value: _checkoutAt,
                enabled: !_busy,
                onChanged: (value) =>
                    setState(() => _checkoutAt = value ?? DateTime.now()),
              ),
              const SizedBox(height: 12),
              DateTimeField(
                label: 'Expected back by',
                value: _dueAt,
                enabled: !_busy,
                optional: true,
                onChanged: (value) => setState(() => _dueAt = value),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _purpose,
                enabled: !_busy,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'Purpose',
                  hintText: 'What the tool is for',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _message,
                enabled: !_busy,
                maxLength: 500,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Instructions (optional)',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: ValueKey(technician?.id),
                initialValue: _workOrderId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'For work order (optional)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(child: Text('None')),
                  for (final order in orders)
                    DropdownMenuItem<String?>(
                      value: order.id,
                      child: Text(
                        '${DisplayId.workOrder(order.id)} · ${order.title}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _busy || technician == null
                    ? null
                    : (id) => setState(() => _workOrderId = id),
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
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Sending…' : 'Send checkout request'),
        ),
      ],
    );
  }
}

/// Figure 15's Check In (2026-11-16): asks the technician holding [tool]
/// to return it by a date and time. Nothing moves here: the loan closes
/// when they scan the tool in the app and confirm the return, saying what
/// condition it is in.
Future<void> showCheckInDialog(
  BuildContext context, {
  required Tool tool,
  required String loanId,
  ToolLoan? loan,
  String? holderName,
}) => showDialog<void>(
  context: context,
  builder: (_) => _CheckInDialog(
    tool: tool,
    loanId: loanId,
    loan: loan,
    holderName: holderName,
  ),
);

class _CheckInDialog extends ConsumerStatefulWidget {
  const _CheckInDialog({
    required this.tool,
    required this.loanId,
    this.loan,
    this.holderName,
  });

  final Tool tool;
  final String loanId;
  final ToolLoan? loan;
  final String? holderName;

  @override
  ConsumerState<_CheckInDialog> createState() => _CheckInDialogState();
}

class _CheckInDialogState extends ConsumerState<_CheckInDialog> {
  late DateTime _dueAt = defaultReturnTime(DateTime.now());
  final _message = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_dueAt.isAfter(DateTime.now())) {
      setState(
        () => _error = 'Pick a return date and time that has not passed.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final message = _message.text.trim();
    final result = await ref
        .read(inventoryControllerProvider)
        .checkIn(
          loanId: widget.loanId,
          dueAt: _dueAt,
          message: message.isEmpty ? null : message,
        );
    if (!mounted) return;
    switch (result) {
      case Success():
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Asked ${widget.holderName ?? 'the technician'} to return '
              '${widget.tool.name}. It is back once they scan it.',
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
    final tool = widget.tool;
    final loan = widget.loan;
    final when = DateFormat('MMM d, y h:mm a');

    Widget fact(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: AppTextStyles.inventoryCaption),
          ),
          Expanded(child: Text(value, style: AppTextStyles.inventoryCell)),
        ],
      ),
    );

    return AlertDialog(
      title: Text('Check in ${tool.name}'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              fact('TOOL', '${tool.name} · ${tool.toolCode}'),
              fact(
                'ASSET',
                [
                  ?tool.category,
                  'went out in ${(loan?.conditionOnBorrow ?? tool.condition).label.toLowerCase()} condition',
                  ?tool.storageLocation,
                ].join(' · '),
              ),
              fact('WITH', widget.holderName ?? 'A technician'),
              if (loan != null)
                fact(
                  'SINCE',
                  [
                    when.format(loan.borrowedAt.toLocal()),
                    if (loan.workOrderId case final id?)
                      'for ${DisplayId.workOrder(id)}',
                  ].join(' · '),
                ),
              const SizedBox(height: 12),
              const Text(
                'They are told, and the tool stays theirs until they scan '
                'its QR code in GSUhub and confirm the return, saying what '
                'condition it is in.',
                style: AppTextStyles.inventoryStatNote,
              ),
              const SizedBox(height: 16),
              DateTimeField(
                label: 'Return by',
                value: _dueAt,
                enabled: !_busy,
                onChanged: (value) => setState(() => _dueAt = value ?? _dueAt),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _message,
                enabled: !_busy,
                maxLength: 500,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Message or instructions (optional)',
                  hintText: 'Where to bring it, what to check',
                  counterText: '',
                  border: OutlineInputBorder(),
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
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Sending…' : 'Send return request'),
        ),
      ],
    );
  }
}

/// When a return is asked for by default: the end of the working day,
/// 5:00 PM, today when there is still an hour before it, else tomorrow.
@visibleForTesting
DateTime defaultReturnTime(DateTime now) {
  final today = DateTime(now.year, now.month, now.day, 17);
  return now.isBefore(today.subtract(const Duration(hours: 1)))
      ? today
      : today.add(const Duration(days: 1));
}

/// A date and a time, picked with the platform's pickers: "Nov 18, 2026"
/// and "5:00 PM" side by side. [optional] adds a way to clear it.
class DateTimeField extends StatelessWidget {
  const DateTimeField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.optional = false,
    super.key,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool enabled;
  final bool optional;

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final current = value ?? defaultReturnTime(now);
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isBefore(now) ? now : current,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    onChanged(
      DateTime(
        picked.year,
        picked.month,
        picked.day,
        current.hour,
        current.minute,
      ),
    );
  }

  Future<void> _pickTime(BuildContext context) async {
    final current = value ?? defaultReturnTime(DateTime.now());
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (picked == null) return;
    onChanged(
      DateTime(
        current.year,
        current.month,
        current.day,
        picked.hour,
        picked.minute,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: enabled ? () => _pickDate(context) : null,
            icon: const Icon(Icons.event_outlined, size: 18),
            label: Text(
              value == null
                  ? 'Pick a date'
                  : DateFormat('MMM d, y').format(value),
            ),
          ),
          TextButton.icon(
            onPressed: enabled ? () => _pickTime(context) : null,
            icon: const Icon(Icons.schedule_outlined, size: 18),
            label: Text(
              value == null ? 'Time' : DateFormat('h:mm a').format(value),
            ),
          ),
          const Spacer(),
          if (optional && value != null)
            IconButton(
              tooltip: 'Clear',
              onPressed: enabled ? () => onChanged(null) : null,
              icon: const Icon(Icons.close, size: 18),
            ),
        ],
      ),
    );
  }
}

/// Asks before withdrawing [request], and withdraws it. A reserved tool
/// goes back on the shelf; the technician is told.
Future<void> showCancelToolRequestDialog(
  BuildContext context,
  WidgetRef ref,
  ToolRequest request, {
  String? technicianName,
}) async {
  final checkOut = request.kind == ToolRequestKind.checkOut;
  final what = checkOut ? 'checkout' : 'return';
  final sure = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Cancel the $what of ${request.toolName}?'),
      content: Text(
        checkOut
            ? '${technicianName ?? 'The technician'} will not need to collect '
                  'it, and ${request.toolName} goes back on the shelf.'
            : '${technicianName ?? 'The technician'} keeps '
                  '${request.toolName} until GSU asks again.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep it'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          child: Text('Cancel $what'),
        ),
      ],
    ),
  );
  if (sure != true || !context.mounted) return;
  final result = await ref
      .read(inventoryControllerProvider)
      .cancelToolRequest(request.id);
  if (context.mounted) {
    showInventoryOutcome(
      context,
      result,
      'Cancelled the $what of ${request.toolName}.',
    );
  }
}

/// Asks before deleting [tool], and deletes it. True once it is deleted;
/// a tool out on loan is refused, and the dialog says so.
Future<bool> showDeleteToolDialog(BuildContext context, Tool tool) {
  final controller = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(inventoryControllerProvider);
  return showConfirmDeleteDialog(
    context: context,
    title: 'Delete ${tool.name} (${tool.toolCode})?',
    message:
        'It leaves the tools list and its label no longer scans. Its loan '
        'history stays in the records, and its tool ID and code can go on '
        'another tool.',
    doneMessage: 'Deleted ${tool.name}.',
    onConfirm: () => controller.deleteTool(tool.id),
  );
}

/// A tool's details, its loans, and what can be done with it: edit, send
/// to repair or bring back, retire, print its label, delete.
Future<void> showToolDetailsDialog(BuildContext context, String toolId) =>
    showDialog<void>(
      context: context,
      builder: (_) => _ToolDetailsDialog(toolId: toolId),
    );

class _ToolDetailsDialog extends ConsumerWidget {
  const _ToolDetailsDialog({required this.toolId});

  final String toolId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tool = ref.watch(toolProvider(toolId));
    return AlertDialog(
      title: switch (tool) {
        AsyncData(value: Success(:final value)) => Text(value.name),
        _ => const Text('Tool'),
      },
      content: SizedBox(
        width: 600,
        child: AsyncValueView<Tool>(
          value: tool,
          loadingHeight: 200,
          onRetry: () => ref.invalidate(toolProvider(toolId)),
          data: (tool) => _ToolDetails(tool: tool),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _ToolDetails extends ConsumerWidget {
  const _ToolDetails({required this.tool});

  final Tool tool;

  Future<void> _move(
    BuildContext context,
    WidgetRef ref,
    ToolStatus status,
    String done,
  ) async {
    final result = await ref
        .read(inventoryControllerProvider)
        .setToolStatus(tool.id, status);
    if (context.mounted) showInventoryOutcome(context, result, done);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names = ref.watch(personnelNamesProvider);
    // Everyone's names, administrators' too: who asked, who cancelled.
    final accounts = switch (ref.watch(allAccountsProvider)) {
      AsyncData(value: Success(:final value)) => {
        for (final account in value) account.id: account.fullName,
      },
      _ => names,
    };
    final loans = ref.watch(toolLoanHistoryProvider(tool.id));
    final when = DateFormat('MMM d, y h:mm a');

    Widget fact(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: AppTextStyles.inventoryCaption),
          ),
          Expanded(child: Text(value, style: AppTextStyles.inventoryCell)),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            InventoryBadge.tool(tool.status),
            const SizedBox(width: 12),
            Text(tool.toolCode, style: AppTextStyles.inventoryCellStrong),
          ],
        ),
        const SizedBox(height: 16),
        fact('CONDITION', tool.condition.label),
        if (tool.category case final category?) fact('TYPE', category),
        if (tool.storageLocation case final location?)
          fact('KEPT AT', location),
        if (tool.currentHolderId case final holder?)
          fact('WITH', names[holder] ?? 'A technician'),
        fact('CODE ON LABEL', tool.qrCode),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => showToolFormDialog(context, tool: tool),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit'),
            ),
            if (tool.status == ToolStatus.available)
              OutlinedButton.icon(
                onPressed: () => _move(
                  context,
                  ref,
                  ToolStatus.inRepair,
                  'Sent ${tool.name} to repair.',
                ),
                icon: const Icon(Icons.build_outlined, size: 18),
                label: const Text('Send to repair'),
              ),
            if (tool.status == ToolStatus.inRepair)
              OutlinedButton.icon(
                onPressed: () => _move(
                  context,
                  ref,
                  ToolStatus.available,
                  '${tool.name} is back on the shelf.',
                ),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('Back from repair'),
              ),
            if (tool.status == ToolStatus.available ||
                tool.status == ToolStatus.inRepair)
              OutlinedButton.icon(
                onPressed: () async {
                  final sure = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text('Retire ${tool.name}?'),
                      content: const Text(
                        'A retired tool cannot be checked out again. Its '
                        'loans stay in its history.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.error,
                          ),
                          child: const Text('Retire'),
                        ),
                      ],
                    ),
                  );
                  if (sure == true && context.mounted) {
                    await _move(
                      context,
                      ref,
                      ToolStatus.retired,
                      'Retired ${tool.name}.',
                    );
                  }
                },
                icon: const Icon(Icons.block, size: 18),
                label: const Text('Retire'),
              ),
            OutlinedButton.icon(
              onPressed: () => showQrLabelDialog(context, QrLabel.tool(tool)),
              icon: const Icon(Icons.qr_code_2_outlined, size: 18),
              label: const Text('QR label'),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
              onPressed: () async {
                final navigator = Navigator.of(context);
                if (await showDeleteToolDialog(context, tool)) {
                  navigator.pop();
                }
              },
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Delete'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text('REQUESTS', style: AppTextStyles.inventoryCaption),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: AsyncValueView<List<ToolRequest>>(
            value: ref.watch(toolRequestHistoryProvider(tool.id)),
            loadingHeight: 100,
            onRetry: () => ref.invalidate(toolRequestHistoryProvider(tool.id)),
            data: (requests) => requests.isEmpty
                ? const Text(
                    'No checkout or return has been requested.',
                    style: AppTextStyles.inventoryStatNote,
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: requests.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) => ToolRequestHistoryRow(
                      request: requests[index],
                      names: accounts,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 20),
        const Text('LOANS', style: AppTextStyles.inventoryCaption),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: AsyncValueView<List<ToolLoan>>(
            value: loans,
            loadingHeight: 100,
            onRetry: () => ref.invalidate(toolLoanHistoryProvider(tool.id)),
            data: (loans) => loans.isEmpty
                ? const Text(
                    'Never checked out.',
                    style: AppTextStyles.inventoryStatNote,
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: loans.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final loan = loans[index];
                      final returned = loan.returnedAt;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          names[loan.borrowedBy] ?? 'A technician',
                          style: AppTextStyles.inventoryCellStrong,
                        ),
                        subtitle: Text(
                          'Out ${when.format(loan.borrowedAt.toLocal())}'
                          '${loan.workOrderId == null ? '' : ' for ${DisplayId.workOrder(loan.workOrderId!)}'}'
                          '${returned == null ? ' · not back yet' : ' · back ${when.format(returned.toLocal())}, ${loan.conditionOnReturn?.label.toLowerCase() ?? ''}'}'
                          '${loan.notes == null ? '' : ' · ${loan.notes}'}',
                          style: AppTextStyles.inventoryStatNote,
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
