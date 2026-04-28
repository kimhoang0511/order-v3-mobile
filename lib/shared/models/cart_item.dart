import 'menu_item.dart';

class CartItem {
  final String cartId;
  final MenuItem menuItem;
  final MenuItemSize? size;
  int quantity;
  final bool isTakeaway;

  CartItem({
    required this.cartId,
    required this.menuItem,
    this.size,
    required this.quantity,
    this.isTakeaway = false,
  });

  double get unitPrice => size?.price ?? menuItem.effectivePrice;
  double get subtotal => unitPrice * quantity;

  CartItem copyWith({int? quantity, bool? isTakeaway}) => CartItem(
        cartId: cartId,
        menuItem: menuItem,
        size: size,
        quantity: quantity ?? this.quantity,
        isTakeaway: isTakeaway ?? this.isTakeaway,
      );

  Map<String, dynamic> toOrderItemJson() => {
        'menu_item_id': menuItem.id,
        'size_id': size?.id,
        'quantity': quantity,
        'unit_price': unitPrice,
        'is_takeaway': isTakeaway,
      };
}
