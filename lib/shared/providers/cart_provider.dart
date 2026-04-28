import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/cart_item.dart';
import '../models/menu_item.dart';
import '../../core/constants/app_constants.dart';

class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super([]) {
    _loadCart();
  }

  final _uuid = const Uuid();

  void addItem(MenuItem menuItem, {MenuItemSize? size, int quantity = 1, bool isTakeaway = false}) {
    final existing = state.where((i) =>
        i.menuItem.id == menuItem.id &&
        i.size?.id == size?.id &&
        i.isTakeaway == isTakeaway).firstOrNull;

    if (existing != null) {
      state = [
        for (final item in state)
          if (item.cartId == existing.cartId)
            item.copyWith(quantity: item.quantity + quantity)
          else
            item
      ];
    } else {
      state = [
        ...state,
        CartItem(
          cartId: _uuid.v4(),
          menuItem: menuItem,
          size: size,
          quantity: quantity,
          isTakeaway: isTakeaway,
        )
      ];
    }
    _saveCart();
  }

  void removeItem(String cartId) {
    state = state.where((i) => i.cartId != cartId).toList();
    _saveCart();
  }

  void updateQuantity(String cartId, int quantity) {
    if (quantity <= 0) {
      removeItem(cartId);
      return;
    }
    state = [
      for (final item in state)
        if (item.cartId == cartId) item.copyWith(quantity: quantity) else item
    ];
    _saveCart();
  }

  void clearCart() {
    state = [];
    _saveCart();
  }

  double get totalAmount => state.fold(0, (sum, item) => sum + item.subtotal);
  int get totalItems => state.fold(0, (sum, item) => sum + item.quantity);

  Future<void> _saveCart() async {
    final prefs = await SharedPreferences.getInstance();
    final data = state.map((item) => {
      'cartId': item.cartId,
      'menuItemId': item.menuItem.id,
      'menuItemName': item.menuItem.name,
      'menuItemImage': item.menuItem.image,
      'menuItemBasePrice': item.menuItem.basePrice,
      'menuItemDiscount': item.menuItem.discount,
      'sizeId': item.size?.id,
      'sizeName': item.size?.sizeName,
      'sizePrice': item.size?.price,
      'quantity': item.quantity,
      'isTakeaway': item.isTakeaway,
      'categoryId': item.menuItem.categoryId,
    }).toList();
    await prefs.setString(AppConstants.cartKey, jsonEncode(data));
  }

  Future<void> _loadCart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(AppConstants.cartKey);
      if (raw == null) return;
      final data = jsonDecode(raw) as List<dynamic>;
      state = data.map((d) {
        final map = d as Map<String, dynamic>;
        final menuItem = MenuItem(
          id: map['menuItemId'] as int,
          name: map['menuItemName'] as String,
          image: map['menuItemImage'] as String?,
          basePrice: (map['menuItemBasePrice'] as num).toDouble(),
          discount: map['menuItemDiscount'] != null ? (map['menuItemDiscount'] as num).toDouble() : null,
          isAvailable: true,
          isFeatured: false,
          categoryId: map['categoryId'] as int? ?? 0,
        );
        MenuItemSize? size;
        if (map['sizeId'] != null) {
          size = MenuItemSize(
            id: map['sizeId'] as int,
            sizeName: map['sizeName'] as String,
            price: (map['sizePrice'] as num).toDouble(),
          );
        }
        return CartItem(
          cartId: map['cartId'] as String,
          menuItem: menuItem,
          size: size,
          quantity: map['quantity'] as int,
          isTakeaway: map['isTakeaway'] as bool? ?? false,
        );
      }).toList();
    } catch (_) {
      state = [];
    }
  }
}

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>((ref) => CartNotifier());
