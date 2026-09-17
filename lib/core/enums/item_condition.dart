/// Physical condition of a durable item — a tool (`tools`) or a registered
/// asset (`assets`). Values mirror the condition column in the Admin
/// Inventory Management screen (manuscript Figure 15: Excellent, Good,
/// Fair, Poor).
///
/// Consumable `inventory_items` do not use this — they are tracked by
/// quantity, not condition.
enum ItemCondition {
  excellent,
  good,
  fair,
  poor;

  /// The value persisted on the owning document's `condition` field.
  String get id => name;

  static ItemCondition fromId(String id) => ItemCondition.values.firstWhere(
    (condition) => condition.id == id,
    orElse: () => throw ArgumentError.value(id, 'id', 'Unknown ItemCondition'),
  );
}
