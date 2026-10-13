import '../../../../core/enums/item_condition.dart';

/// What the console's tool form holds (Objective 6.B): a tool's details,
/// and nothing about who has it. Loans change that.
class ToolDraft {
  const ToolDraft({
    required this.toolCode,
    required this.name,
    required this.condition,
    required this.qrCode,
    this.category,
    this.storageLocation,
  });

  static const int codeLimit = 20;
  static const int nameLimit = 80;
  static const int shortLimit = 40;
  static const int qrCodeLimit = 80;

  /// The asset tag in Figure 15's Tool ID column, e.g. "TL-0824".
  final String toolCode;
  final String name;
  final ItemCondition condition;
  final String qrCode;
  final String? category;
  final String? storageLocation;

  /// The code a new tool's label carries unless another is typed:
  /// `TOOL-<tool ID>`, the form the seed and the scanner already use.
  static String defaultQrCode(String toolCode) =>
      'TOOL-${toolCode.trim().toUpperCase()}';

  ToolDraft normalized() => ToolDraft(
    toolCode: toolCode.trim().toUpperCase(),
    name: name.trim(),
    condition: condition,
    qrCode: qrCode.trim(),
    category: _orNull(category),
    storageLocation: _orNull(storageLocation),
  );

  /// Why the draft cannot be saved, or null when it can.
  String? get problem {
    final draft = normalized();
    if (draft.toolCode.isEmpty) return 'Enter the tool ID on its tag.';
    if (draft.toolCode.length > codeLimit) {
      return 'Keep the tool ID to $codeLimit characters.';
    }
    if (draft.name.isEmpty) return 'Enter the tool’s name.';
    if (draft.name.length > nameLimit) {
      return 'Keep the name to $nameLimit characters.';
    }
    if ((draft.category?.length ?? 0) > shortLimit) {
      return 'Keep the category to $shortLimit characters.';
    }
    if ((draft.storageLocation?.length ?? 0) > nameLimit) {
      return 'Keep the storage location to $nameLimit characters.';
    }
    if (draft.qrCode.isEmpty) return 'Enter the code on its label.';
    if (draft.qrCode.length > qrCodeLimit) {
      return 'Keep the code to $qrCodeLimit characters.';
    }
    return null;
  }

  /// The fields as stored.
  Map<String, dynamic> toFields() {
    final draft = normalized();
    return {
      'toolCode': draft.toolCode,
      'name': draft.name,
      'condition': draft.condition.id,
      'qrCode': draft.qrCode,
      'category': draft.category,
      'storageLocation': draft.storageLocation,
    };
  }

  static String? _orNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
