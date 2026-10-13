import '../../../../core/enums/item_condition.dart';

/// What the console's room form holds (Objective 6.C): a place reports
/// are filed against, and the code on its sticker.
class FacilityDraft {
  const FacilityDraft({
    required this.buildingName,
    this.roomIdentifier,
    this.locationDescription,
    this.latitude,
    this.longitude,
    this.qrCode,
  });

  static const int nameLimit = 80;
  static const int descriptionLimit = 160;
  static const int qrCodeLimit = 80;

  final String buildingName;
  final String? roomIdentifier;
  final String? locationDescription;
  final double? latitude;
  final double? longitude;

  /// Left empty, a new room's code is made from its id: `FAC-<ID>`.
  final String? qrCode;

  /// The code a new room's sticker carries unless another is typed.
  static String defaultQrCode(String id) => 'FAC-${id.toUpperCase()}';

  FacilityDraft normalized() => FacilityDraft(
    buildingName: buildingName.trim(),
    roomIdentifier: _orNull(roomIdentifier),
    locationDescription: _orNull(locationDescription),
    latitude: latitude,
    longitude: longitude,
    qrCode: _orNull(qrCode),
  );

  /// Why the draft cannot be saved, or null when it can.
  String? get problem {
    final draft = normalized();
    if (draft.buildingName.isEmpty) return 'Enter the building.';
    if (draft.buildingName.length > nameLimit) {
      return 'Keep the building to $nameLimit characters.';
    }
    if ((draft.roomIdentifier?.length ?? 0) > nameLimit) {
      return 'Keep the room to $nameLimit characters.';
    }
    if ((draft.locationDescription?.length ?? 0) > descriptionLimit) {
      return 'Keep the description to $descriptionLimit characters.';
    }
    if ((draft.latitude == null) != (draft.longitude == null)) {
      return 'Enter both the latitude and the longitude, or neither.';
    }
    if (draft.latitude case final latitude? when latitude.abs() > 90) {
      return 'The latitude must be between -90 and 90.';
    }
    if (draft.longitude case final longitude? when longitude.abs() > 180) {
      return 'The longitude must be between -180 and 180.';
    }
    if ((draft.qrCode?.length ?? 0) > qrCodeLimit) {
      return 'Keep the code to $qrCodeLimit characters.';
    }
    return null;
  }

  static String? _orNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

/// What the console's equipment form holds (Objective 6.C): a piece of
/// equipment installed in a room, which reports can name by its sticker.
class AssetDraft {
  const AssetDraft({
    required this.name,
    required this.facilityId,
    required this.condition,
    this.category,
    this.serialNumber,
    this.qrCode,
  });

  static const int nameLimit = 80;
  static const int shortLimit = 40;

  final String name;
  final String facilityId;
  final ItemCondition condition;
  final String? category;
  final String? serialNumber;

  /// Left empty, new equipment's code is made from its id: `AST-<ID>`.
  final String? qrCode;

  static String defaultQrCode(String id) => 'AST-${id.toUpperCase()}';

  AssetDraft normalized() => AssetDraft(
    name: name.trim(),
    facilityId: facilityId.trim(),
    condition: condition,
    category: FacilityDraft._orNull(category),
    serialNumber: FacilityDraft._orNull(serialNumber),
    qrCode: FacilityDraft._orNull(qrCode),
  );

  String? get problem {
    final draft = normalized();
    if (draft.name.isEmpty) return 'Enter the equipment’s name.';
    if (draft.name.length > nameLimit) {
      return 'Keep the name to $nameLimit characters.';
    }
    if (draft.facilityId.isEmpty) return 'Pick the room it is in.';
    if ((draft.category?.length ?? 0) > shortLimit) {
      return 'Keep the type to $shortLimit characters.';
    }
    if ((draft.serialNumber?.length ?? 0) > shortLimit) {
      return 'Keep the serial number to $shortLimit characters.';
    }
    if ((draft.qrCode?.length ?? 0) > FacilityDraft.qrCodeLimit) {
      return 'Keep the code to ${FacilityDraft.qrCodeLimit} characters.';
    }
    return null;
  }
}
