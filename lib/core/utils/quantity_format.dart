import 'package:intl/intl.dart';

/// How stock quantities and prices are written (Objective 6).
abstract final class QuantityFormat {
  /// 2, not 2.0; 1.5 as it is.
  static String amount(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();

  /// "4 units", "1.5 rolls", and "1 roll": units are stored as typed, in
  /// the plural, so one of them drops its final "s".
  static String withUnit(double value, String unit) {
    final one =
        value == 1 &&
        unit.length > 2 &&
        unit.endsWith('s') &&
        !unit.endsWith('ss');
    return '${amount(value)} ${one ? unit.substring(0, unit.length - 1) : unit}';
  }

  static final NumberFormat _pesos = NumberFormat.currency(
    locale: 'en_US',
    symbol: '₱',
    decimalDigits: 2,
  );

  static final NumberFormat _wholePesos = NumberFormat.currency(
    locale: 'en_US',
    symbol: '₱',
    decimalDigits: 0,
  );

  /// "₱1,250.00".
  static String pesos(double value) => _pesos.format(value);

  /// "₱142,500": the stat card's total, without centavos.
  static String wholePesos(double value) => _wholePesos.format(value);
}
