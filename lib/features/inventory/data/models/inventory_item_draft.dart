/// What the console's material form holds (Objective 6.A): every field an
/// administrator sets on an `inventory_items` document, and nothing that
/// moves stock. Stock moves only through the ledger.
class InventoryItemDraft {
  const InventoryItemDraft({
    required this.name,
    required this.category,
    required this.unitOfMeasurement,
    required this.storageLocation,
    required this.qrCode,
    required this.minimumThreshold,
    this.specification,
    this.unitCost,
    this.photoUrl,
  });

  static const int nameLimit = 80;
  static const int shortLimit = 40;
  static const int locationLimit = 80;
  static const int qrCodeLimit = 80;

  final String name;
  final String category;
  final String unitOfMeasurement;
  final String storageLocation;
  final String qrCode;
  final double minimumThreshold;
  final String? specification;
  final double? unitCost;
  final String? photoUrl;

  /// The same draft with its text trimmed and empty optionals cleared.
  InventoryItemDraft normalized() => InventoryItemDraft(
    name: name.trim(),
    category: category.trim(),
    unitOfMeasurement: unitOfMeasurement.trim(),
    storageLocation: storageLocation.trim(),
    qrCode: qrCode.trim(),
    minimumThreshold: minimumThreshold,
    specification: _orNull(specification),
    unitCost: unitCost,
    photoUrl: _orNull(photoUrl),
  );

  /// Why the draft cannot be saved, or null when it can. Checks the
  /// normalized draft.
  String? get problem {
    final draft = normalized();
    if (draft.name.isEmpty) return 'Enter the material’s name.';
    if (draft.name.length > nameLimit) {
      return 'Keep the name to $nameLimit characters.';
    }
    if (draft.category.isEmpty) return 'Enter a category.';
    if (draft.category.length > shortLimit) {
      return 'Keep the category to $shortLimit characters.';
    }
    if ((draft.specification?.length ?? 0) > shortLimit) {
      return 'Keep the size or pack to $shortLimit characters.';
    }
    if (draft.unitOfMeasurement.isEmpty) {
      return 'Enter the unit it is counted in.';
    }
    if (draft.unitOfMeasurement.length > shortLimit) {
      return 'Keep the unit to $shortLimit characters.';
    }
    if (draft.storageLocation.isEmpty) return 'Enter where it is stored.';
    if (draft.storageLocation.length > locationLimit) {
      return 'Keep the storage location to $locationLimit characters.';
    }
    if (draft.qrCode.isEmpty) return 'Enter the code on its label.';
    if (draft.qrCode.length > qrCodeLimit) {
      return 'Keep the code to $qrCodeLimit characters.';
    }
    if (draft.minimumThreshold < 0) {
      return 'The minimum cannot be below zero.';
    }
    if ((draft.unitCost ?? 0) < 0) return 'The unit cost cannot be below zero.';
    return null;
  }

  /// The fields as stored, for creating or updating the document.
  Map<String, dynamic> toFields() {
    final draft = normalized();
    return {
      'name': draft.name,
      'category': draft.category,
      'specification': draft.specification,
      'unitOfMeasurement': draft.unitOfMeasurement,
      'storageLocation': draft.storageLocation,
      'qrCode': draft.qrCode,
      'minimumThreshold': draft.minimumThreshold,
      'unitCost': draft.unitCost,
      'photoUrl': draft.photoUrl,
    };
  }

  static String? _orNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
