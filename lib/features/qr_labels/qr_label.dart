import '../facilities/data/models/asset.dart';
import '../facilities/data/models/facility.dart';
import '../inventory/data/models/inventory_item.dart';
import '../tools/data/models/tool.dart';

/// One printed sticker (Objective 6.C; §3.4 "QR code generation"): the
/// code the scanners read, and two lines saying what it is stuck on.
class QrLabel {
  const QrLabel({required this.code, required this.title, this.subtitle});

  /// A material's label: its name, and category and size.
  factory QrLabel.material(InventoryItem item) => QrLabel(
    code: item.qrCode,
    title: item.name,
    subtitle: [item.category, ?item.specification].join(' · '),
  );

  factory QrLabel.tool(Tool tool) =>
      QrLabel(code: tool.qrCode, title: tool.name, subtitle: tool.toolCode);

  /// A room's label: the building, and the room.
  factory QrLabel.facility(Facility facility) => QrLabel(
    code: facility.qrCode,
    title: facility.buildingName,
    subtitle: facility.roomIdentifier,
  );

  /// Equipment's label: its name, and the room it is in.
  factory QrLabel.asset(Asset asset, {Facility? room}) => QrLabel(
    code: asset.qrCode,
    title: asset.name,
    subtitle: room == null
        ? asset.serialNumber
        : [room.buildingName, ?room.roomIdentifier].join(', '),
  );

  /// What the QR code encodes, printed under it too.
  final String code;
  final String title;
  final String? subtitle;
}
