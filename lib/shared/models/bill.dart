class BillItem {
  final String name;
  final String? sizeName;
  final int quantity;
  final double unitPrice;
  final bool isTakeaway;

  const BillItem({
    required this.name,
    this.sizeName,
    required this.quantity,
    required this.unitPrice,
    this.isTakeaway = false,
  });

  double get subtotal => unitPrice * quantity;

  factory BillItem.fromJson(Map<String, dynamic> json) => BillItem(
        name: json['name'] as String,
        sizeName: json['size_name'] as String?,
        quantity: json['quantity'] as int,
        unitPrice: (json['unit_price'] as num).toDouble(),
        isTakeaway: json['is_takeaway'] as bool? ?? false,
      );
}

class TableBill {
  final int id;
  final String tableNumber;
  final double subtotal;
  final double? discount;
  final double? surcharge;
  final double total;
  final List<BillItem> items;
  final bool isPaid;
  final DateTime createdAt;

  const TableBill({
    required this.id,
    required this.tableNumber,
    required this.subtotal,
    this.discount,
    this.surcharge,
    required this.total,
    this.items = const [],
    required this.isPaid,
    required this.createdAt,
  });

  factory TableBill.fromJson(Map<String, dynamic> json) => TableBill(
        id: json['id'] as int,
        tableNumber: json['table_number'].toString(),
        subtotal: (json['subtotal'] as num? ?? json['total_amount'] as num? ?? 0).toDouble(),
        discount: json['discount'] != null ? (json['discount'] as num).toDouble() : null,
        surcharge: json['surcharge'] != null ? (json['surcharge'] as num).toDouble() : null,
        total: (json['total'] as num? ?? json['total_amount'] as num? ?? 0).toDouble(),
        items: (json['items'] as List<dynamic>? ?? [])
            .map((i) => BillItem.fromJson(i as Map<String, dynamic>))
            .toList(),
        isPaid: json['is_paid'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
