/// Kind of movement recorded in the append-only `inventory_transactions`
/// ledger. Derived from manuscript §3.4, which describes the inventory
/// mechanism as monitoring "the issuance, usage, deduction, and
/// replenishment of maintenance materials".
enum InventoryTransactionType {
  /// Stock handed out to personnel for a work order, before it is known
  /// how much will actually be used.
  issuance,

  /// Stock consumed during maintenance — the automatic deduction the
  /// system performs once an accomplishment report is submitted
  /// (manuscript §3.4).
  consumption,

  /// Unused issued stock handed back.
  returned,

  /// New stock received into the GSU store.
  replenishment,

  /// Manual correction (stock count, spoilage, loss). DERIVED — not named
  /// in the manuscript, but without it any discrepancy found during a
  /// physical count has no lawful way to be recorded in an append-only
  /// ledger. Flagged in docs/data_dictionary.md.
  adjustment;

  /// Whether this transaction type decreases `quantityAvailable`.
  bool get isDeduction =>
      this == InventoryTransactionType.issuance ||
      this == InventoryTransactionType.consumption;

  /// The value persisted on `inventory_transactions/{id}.type`.
  String get id => name;

  static InventoryTransactionType fromId(String id) =>
      InventoryTransactionType.values.firstWhere(
        (type) => type.id == id,
        orElse: () => throw ArgumentError.value(
          id,
          'id',
          'Unknown InventoryTransactionType',
        ),
      );
}
