class KitchenItem {
  final String name;
  final String? sizeName;
  final int quantity;
  final bool isTakeaway;

  KitchenItem({
    required this.name,
    this.sizeName,
    required this.quantity,
    this.isTakeaway = false,
  });

  factory KitchenItem.fromJson(Map<String, dynamic> json) {
    return KitchenItem(
      name: json['name'] as String,
      sizeName: json['sizeName'] as String?,
      quantity: (json['quantity'] as num).toInt(),
      isTakeaway: json['isTakeaway'] as bool? ?? false,
    );
  }
}

class KitchenTicket {
  final String orderId;
  final DateTime orderTime;
  final DateTime? requestedAt;
  final String tableNumber;
  final String staffName;
  final String note;
  final List<KitchenItem> items;
  final int? paperWidth;

  KitchenTicket({
    required this.orderId,
    required this.orderTime,
    this.requestedAt,
    required this.tableNumber,
    this.staffName = '',
    this.note = '',
    required this.items,
    this.paperWidth,
  });

  factory KitchenTicket.fromJson(Map<String, dynamic> json) {
    final rawRequestedAt = json['requestedAt'] as String?;
    return KitchenTicket(
      orderId: json['orderId'] as String,
      orderTime: DateTime.parse(json['orderTime'] as String).toLocal(),
      requestedAt: rawRequestedAt != null
          ? DateTime.parse(rawRequestedAt).toLocal()
          : null,
      tableNumber: json['tableNumber'] as String,
      staffName: json['staffName'] as String? ?? '',
      note: json['note'] as String? ?? '',
      items: (json['items'] as List)
          .map((i) => KitchenItem.fromJson(i as Map<String, dynamic>))
          .toList(),
      paperWidth: json['paperWidth'] as int?,
    );
  }
}
