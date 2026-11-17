import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/data/row_record.dart';
import 'package:gsuhub/features/tools/data/models/tool_request.dart';

/// A tool request as the database sends it, and the status people read
/// (2026-11-16): the brief's table, with Overdue and lapsed read from the
/// clock so they show before the database's sweep marks them.
void main() {
  final asked = DateTime.utc(2026, 11, 16, 1);
  final due = DateTime.utc(2026, 11, 16, 9);

  Map<String, dynamic> row({
    String kind = 'checkOut',
    String status = 'pending',
    String? confirmedAt,
  }) => {
    'id': 'tr-1',
    'kind': kind,
    'tool_id': 'tl-1',
    'tool_name': 'Fluke Multimeter',
    'tool_code': 'TL-0001',
    'qr_code': 'TOOL-TL-0001',
    'personnel_id': 'u-tech',
    'requested_by': 'u-admin',
    'requested_at': '2026-11-16T01:00:00+00:00',
    'checkout_at': kind == 'checkOut' ? '2026-11-16T02:00:00+00:00' : null,
    'due_at': '2026-11-16T09:00:00+00:00',
    'expires_at': kind == 'checkOut' ? '2026-11-17T02:00:00+00:00' : null,
    'purpose': kind == 'checkOut' ? 'Ceiling fan repair' : null,
    'message': 'Bring the charger back too.',
    'work_order_id': 'w-1',
    'loan_id': kind == 'checkIn' ? 'lo-1' : null,
    'status': status,
    'confirmed_at': confirmedAt,
    'closed_at': status == 'cancelled' || status == 'expired'
        ? '2026-11-16T03:00:00+00:00'
        : null,
    'closed_by': status == 'cancelled' ? 'u-admin' : null,
    'reminded_at': null,
    'overdue_notified_at': null,
  };

  ToolRequest read(Map<String, dynamic> row) =>
      ToolRequest.fromRecord(RowRecord.fromRow(row));

  test('reads a row as the database sends it', () {
    final request = read(row());
    expect(request.kind, ToolRequestKind.checkOut);
    expect(request.toolCode, 'TL-0001');
    expect(request.qrCode, 'TOOL-TL-0001');
    expect(request.requestedAt, asked);
    expect(request.dueAt, due);
    expect(request.purpose, 'Ceiling fan repair');
    expect(request.workOrderId, 'w-1');
    expect(request.isPending, isTrue);
  });

  group('the status people read', () {
    final before = DateTime.utc(2026, 11, 16, 3);
    final afterDue = DateTime.utc(2026, 11, 16, 10);
    final afterLapse = DateTime.utc(2026, 11, 17, 3);

    test('a checkout: pending, borrowed, cancelled, lapsed', () {
      expect(
        read(row()).statusAt(before),
        ToolTransactionStatus.pendingConfirmation,
      );
      expect(
        read(row(status: 'confirmed', confirmedAt: '2026-11-16T02:05:00+00:00'))
            .statusAt(before),
        ToolTransactionStatus.borrowed,
      );
      expect(
        read(row(status: 'cancelled')).statusAt(before),
        ToolTransactionStatus.cancelled,
      );
      expect(
        read(row(status: 'expired')).statusAt(before),
        ToolTransactionStatus.expired,
      );
      expect(
        read(row()).statusAt(afterLapse),
        ToolTransactionStatus.expired,
        reason: 'lapsed before the sweep has marked it',
      );
    });

    test('a return: awaiting, overdue once due, returned', () {
      expect(
        read(row(kind: 'checkIn')).statusAt(before),
        ToolTransactionStatus.awaitingReturn,
      );
      expect(
        read(row(kind: 'checkIn')).statusAt(afterDue),
        ToolTransactionStatus.overdue,
      );
      expect(
        read(
          row(
            kind: 'checkIn',
            status: 'confirmed',
            confirmedAt: '2026-11-16T10:30:00+00:00',
          ),
        ).statusAt(afterDue),
        ToolTransactionStatus.returned,
        reason: 'returned late is still returned',
      );
    });

    test('the labels are the brief\'s, and only the waiting ones are open', () {
      expect(ToolTransactionStatus.values.map((status) => status.label), [
        'Pending Confirmation',
        'Borrowed',
        'Awaiting Return',
        'Overdue',
        'Returned',
        'Cancelled',
        'Expired',
      ]);
      expect(ToolTransactionStatus.values.where((status) => status.isOpen), [
        ToolTransactionStatus.pendingConfirmation,
        ToolTransactionStatus.awaitingReturn,
        ToolTransactionStatus.overdue,
      ]);
      expect(ToolRequestKind.checkOut.label, 'Check-Out');
      expect(ToolRequestKind.checkIn.label, 'Check-In');
    });
  });

  test('a return request names the loan it closes', () {
    final missing = row(kind: 'checkIn')..['loan_id'] = null;
    expect(() => read(missing), throwsArgumentError);
  });
}
