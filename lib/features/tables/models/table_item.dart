class TableItem {
  final int id;
  final String tableNumber;
  final bool isLocked;
  final String? redirectTo;

  const TableItem({
    required this.id,
    required this.tableNumber,
    this.isLocked = false,
    this.redirectTo,
  });

  factory TableItem.fromJson(Map<String, dynamic> json) => TableItem(
        id: json['id'] as int,
        tableNumber: json['table_number'] as String,
        isLocked: json['is_locked'] as bool? ?? false,
        redirectTo: json['redirect_to'] as String?,
      );

  TableItem copyWith({bool? isLocked, String? redirectTo, bool clearRedirect = false}) => TableItem(
        id: id,
        tableNumber: tableNumber,
        isLocked: isLocked ?? this.isLocked,
        redirectTo: clearRedirect ? null : (redirectTo ?? this.redirectTo),
      );
}

List<TableItem> sortTables(List<TableItem> tables) {
  final list = [...tables];
  list.sort((a, b) {
    final na = int.tryParse(a.tableNumber);
    final nb = int.tryParse(b.tableNumber);
    if (na != null && nb != null) return na.compareTo(nb);
    return a.tableNumber.compareTo(b.tableNumber);
  });
  return list;
}
