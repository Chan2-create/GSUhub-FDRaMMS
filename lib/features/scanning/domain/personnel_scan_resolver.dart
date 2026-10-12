import '../../../core/errors/failures.dart';
import '../../../core/utils/result.dart';
import '../../facilities/presentation/qr_lookup.dart';
import '../../inventory/data/models/inventory_item.dart';
import '../../inventory/data/repositories/inventory_repository.dart';
import '../../tools/data/models/tool.dart';
import '../../tools/data/repositories/tool_repository.dart';

/// What a code scanned in the personnel app identified (Objective 5.C).
sealed class ScanMatch {
  const ScanMatch();
}

/// An inventory material: record it as used.
class MaterialMatch extends ScanMatch {
  const MaterialMatch(this.item);

  final InventoryItem item;
}

/// A tool: borrow it or return it.
class ToolMatch extends ScanMatch {
  const ToolMatch(this.tool);

  final Tool tool;
}

/// A room, or an asset in one: its details and the work linked to it
/// (§3.4 personnel: "scan QR codes to access facility or asset
/// information and linked work orders").
class PlaceMatch extends ScanMatch {
  const PlaceMatch(this.place);

  final QrMatch place;
}

/// Resolves a scanned code to a material, a tool, or a place — tried in
/// that order (§1.5: QR identification covers "facilities, assets,
/// materials, tools, and equipment" registered in the system).
///
/// The seed and the console print each with its own prefix (`INV-`,
/// `TOOL-`, `FAC-`, `AST-`), but a printed label need not follow it, so
/// every kind is tried rather than guessed from the prefix.
class PersonnelScanResolver {
  const PersonnelScanResolver(this._inventory, this._tools, this._places);

  final InventoryRepository _inventory;
  final ToolRepository _tools;
  final QrLookup _places;

  static const String unregistered =
      "This code isn't registered in GSUhub — it is not a material, a "
      'tool, a room or a piece of equipment on record.';

  Future<Result<ScanMatch>> resolve(String scanned) async {
    final code = scanned.trim();
    if (code.isEmpty) {
      return const Result.failure(NotFoundFailure(unregistered));
    }

    switch (await _inventory.getItemByQrCode(code)) {
      case Success(:final value):
        return Result.success(MaterialMatch(value));
      case Error(:final failure) when failure is! NotFoundFailure:
        return Result.failure(failure);
      case Error():
        break;
    }

    switch (await _tools.getToolByQrCode(code)) {
      case Success(:final value):
        return Result.success(ToolMatch(value));
      case Error(:final failure) when failure is! NotFoundFailure:
        return Result.failure(failure);
      case Error():
        break;
    }

    return switch (await _places.resolve(code)) {
      Success(:final value) => Result.success(PlaceMatch(value)),
      // QrLookup's own wording speaks to the report form; a retired place
      // keeps its message, an unknown code gets this one.
      Error(:final failure)
          when failure is NotFoundFailure &&
              !failure.message.contains('no longer in service') =>
        const Result.failure(NotFoundFailure(unregistered)),
      Error(:final failure) => Result.failure(failure),
    };
  }
}
