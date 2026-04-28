class BillItem {
  final String name;
  final String? sizeName;
  final int quantity;
  final double unitPrice;

  BillItem({
    required this.name,
    this.sizeName,
    required this.quantity,
    required this.unitPrice,
  });

  String get displayName => sizeName != null ? '$name ($sizeName)' : name;
  double get total => quantity * unitPrice;

  factory BillItem.fromJson(Map<String, dynamic> json) {
    return BillItem(
      name: json['name'] as String,
      sizeName: json['size_name'] as String?,
      quantity: (json['quantity'] as num).toInt(),
      unitPrice: (json['unit_price'] as num).toDouble(),
    );
  }
}

class Bill {
  final String shopName;
  final String? shopAddress;
  final String? shopPhone;
  final String staffName;
  final String customerName;
  final String tableNumber;
  final DateTime printTime;
  final List<BillItem> items;
  final double baseTotal;
  final double adjustment;
  final String adjustNote;
  final String note;
  final double finalTotal;
  final String footer;
  final int? paperWidth;
  final String? bankName;
  final String? bankAccountName;
  final String? bankAccountNumber;
  final String? bankQrUrl;

  Bill({
    required this.shopName,
    this.shopAddress,
    this.shopPhone,
    required this.staffName,
    required this.customerName,
    required this.tableNumber,
    required this.printTime,
    required this.items,
    required this.baseTotal,
    this.adjustment = 0,
    this.adjustNote = '',
    this.note = '',
    required this.finalTotal,
    this.footer = 'Xin cảm ơn Quý khách',
    this.paperWidth,
    this.bankName,
    this.bankAccountName,
    this.bankAccountNumber,
    this.bankQrUrl,
  });

  factory Bill.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List)
        .map((i) => BillItem.fromJson(i as Map<String, dynamic>))
        .toList();
    final baseTotal = (json['baseTotal'] as num).toDouble();
    return Bill(
      shopName: json['restaurantName'] as String,
      shopAddress: json['restaurantAddress'] as String?,
      shopPhone: json['restaurantPhone'] as String?,
      staffName: json['staffName'] as String? ?? '',
      customerName: json['customerName'] as String? ?? 'Khách lẻ',
      tableNumber: json['tableNumber'] as String,
      printTime: DateTime.now(),
      items: items,
      baseTotal: baseTotal,
      adjustment: (json['adjustment'] as num?)?.toDouble() ?? 0,
      adjustNote: json['adjustNote'] as String? ?? '',
      note: json['note'] as String? ?? '',
      finalTotal: (json['finalTotal'] as num?)?.toDouble() ?? baseTotal,
      footer: json['footer'] as String? ?? 'Xin cảm ơn Quý khách',
      paperWidth: json['paperWidth'] as int?,
      bankName: json['bankName'] as String?,
      bankAccountName: json['bankAccountName'] as String?,
      bankAccountNumber: json['bankAccountNumber'] as String?,
      bankQrUrl: json['bankQrUrl'] as String?,
    );
  }
}
