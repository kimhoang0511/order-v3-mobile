class MenuItemSize {
  final int id;
  final String sizeName;
  final double price;

  const MenuItemSize({required this.id, required this.sizeName, required this.price});

  factory MenuItemSize.fromJson(Map<String, dynamic> json) => MenuItemSize(
        id: json['id'] as int,
        sizeName: json['size_name'] as String,
        price: (json['price'] as num).toDouble(),
      );
}

class MenuItem {
  final int id;
  final String name;
  final String? description;
  final String? image;
  final double basePrice;
  final double? discount;
  final bool isAvailable;
  final bool isFeatured;
  final int categoryId;
  final List<MenuItemSize> sizes;

  const MenuItem({
    required this.id,
    required this.name,
    this.description,
    this.image,
    required this.basePrice,
    this.discount,
    required this.isAvailable,
    required this.isFeatured,
    required this.categoryId,
    this.sizes = const [],
  });

  double get effectivePrice {
    if (discount != null && discount! > 0) {
      return basePrice * (1 - discount! / 100);
    }
    return basePrice;
  }

  factory MenuItem.fromJson(Map<String, dynamic> json) => MenuItem(
        id: json['id'] as int,
        name: json['name'] as String,
        description: json['description'] as String?,
        image: json['image'] as String?,
        basePrice: (json['base_price'] as num).toDouble(),
        discount: json['discount'] != null ? (json['discount'] as num).toDouble() : null,
        isAvailable: json['is_available'] as bool? ?? true,
        isFeatured: json['is_featured'] as bool? ?? false,
        categoryId: json['category_id'] as int,
        sizes: (json['sizes'] as List<dynamic>? ?? [])
            .map((s) => MenuItemSize.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}

class MenuCategory {
  final int id;
  final String name;
  final String? icon;
  final int sortOrder;
  final List<MenuItem> items;

  const MenuCategory({
    required this.id,
    required this.name,
    this.icon,
    required this.sortOrder,
    this.items = const [],
  });

  factory MenuCategory.fromJson(Map<String, dynamic> json) => MenuCategory(
        id: json['id'] as int,
        name: json['name'] as String,
        icon: json['icon'] as String?,
        sortOrder: json['sort_order'] as int? ?? 0,
        items: (json['items'] as List<dynamic>? ?? [])
            .map((i) => MenuItem.fromJson(i as Map<String, dynamic>))
            .toList(),
      );
}
