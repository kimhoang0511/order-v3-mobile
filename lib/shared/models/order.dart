class OrderItem {
  final int id;
  final int menuItemId;
  final String menuItemName;
  final String? menuItemImage;
  final int? sizeId;
  final String? sizeName;
  final int quantity;
  final double unitPrice;
  final bool isTakeaway;

  const OrderItem({
    required this.id,
    required this.menuItemId,
    required this.menuItemName,
    this.menuItemImage,
    this.sizeId,
    this.sizeName,
    required this.quantity,
    required this.unitPrice,
    this.isTakeaway = false,
  });

  double get subtotal => unitPrice * quantity;

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
        id: json['id'] as int,
        menuItemId: json['menu_item_id'] as int,
        menuItemName: json['menu_item_name'] as String? ?? json['menu_item']?['name'] as String? ?? '',
        menuItemImage: json['menu_item_image'] as String? ?? json['menu_item']?['image'] as String?,
        sizeId: json['size_id'] as int?,
        sizeName: json['size_name'] as String?,
        quantity: json['quantity'] as int,
        unitPrice: (json['unit_price'] as num).toDouble(),
        isTakeaway: json['is_takeaway'] as bool? ?? false,
      );
}

enum OrderStatus {
  pending,
  confirmed,
  preparing,
  ready,
  served,
  cancelled;

  static OrderStatus fromString(String s) =>
      OrderStatus.values.firstWhere((e) => e.name == s, orElse: () => OrderStatus.pending);

  String get displayName {
    switch (this) {
      case OrderStatus.pending: return 'Chờ xác nhận';
      case OrderStatus.confirmed: return 'Đã xác nhận';
      case OrderStatus.preparing: return 'Đang chuẩn bị';
      case OrderStatus.ready: return 'Sẵn sàng';
      case OrderStatus.served: return 'Đã phục vụ';
      case OrderStatus.cancelled: return 'Đã hủy';
    }
  }
}

class Order {
  final int id;
  final String restaurantSlug;
  final String? tableNumber;
  final OrderStatus status;
  final double totalAmount;
  final String? note;
  final List<OrderItem> items;
  final DateTime createdAt;
  final String? customerName;
  final String? customerPhone;

  const Order({
    required this.id,
    required this.restaurantSlug,
    this.tableNumber,
    required this.status,
    required this.totalAmount,
    this.note,
    this.items = const [],
    required this.createdAt,
    this.customerName,
    this.customerPhone,
  });

  factory Order.fromJson(Map<String, dynamic> json) => Order(
        id: json['id'] as int,
        restaurantSlug: json['restaurant_slug'] as String? ?? '',
        tableNumber: json['table_number']?.toString(),
        status: OrderStatus.fromString(json['status'] as String? ?? 'pending'),
        totalAmount: (json['total_amount'] as num? ?? 0).toDouble(),
        note: json['note'] as String?,
        items: (json['items'] as List<dynamic>? ?? [])
            .map((i) => OrderItem.fromJson(i as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.parse(json['created_at'] as String),
        customerName: json['customer_name'] as String?,
        customerPhone: json['customer_phone'] as String?,
      );
}
