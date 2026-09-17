/// Availability state of a durable tool (manuscript Figure 15, "Tool
/// Assets & Tracking": AVAILABLE / BORROWED / IN REPAIR).
///
/// [retired] is DERIVED — the manuscript never mentions decommissioning a
/// tool, but without it a broken-beyond-repair tool has no terminal state
/// and would sit in [inRepair] forever. Flagged in docs/data_dictionary.md.
enum ToolStatus {
  available,
  borrowed,
  inRepair,
  retired;

  /// Whether this tool can currently be issued to personnel.
  bool get isIssuable => this == ToolStatus.available;

  /// The value persisted on `tools/{id}.status`.
  String get id => name;

  static ToolStatus fromId(String id) => ToolStatus.values.firstWhere(
    (status) => status.id == id,
    orElse: () => throw ArgumentError.value(id, 'id', 'Unknown ToolStatus'),
  );
}
