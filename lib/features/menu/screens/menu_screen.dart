import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:badges/badges.dart' as badges;
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format_utils.dart';
import '../../../shared/models/cart_item.dart';
import '../../../shared/models/menu_item.dart';
import '../../../shared/providers/cart_provider.dart';
import '../../../shared/widgets/loading_widget.dart';
import '../providers/menu_provider.dart';
import '../widgets/size_selector_sheet.dart';

class MenuScreen extends ConsumerStatefulWidget {
  final String restaurantSlug;
  final String tableNumber;

  const MenuScreen({super.key, required this.restaurantSlug, required this.tableNumber});

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedCategoryIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(menuProvider((widget.restaurantSlug, widget.tableNumber)).notifier)
          .loadMenu(widget.restaurantSlug, widget.tableNumber);
    });
  }

  void _onAddItem(MenuItem item, List<MenuItemSize> sizes) {
    if (sizes.length > 1) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => SizeSelectorSheet(
          menuItem: item,
          sizes: sizes,
          onConfirm: (size, qty, isTakeaway) {
            ref.read(cartProvider.notifier).addItem(item, size: size, quantity: qty, isTakeaway: isTakeaway);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Đã thêm ${item.name}'), duration: const Duration(seconds: 1)),
            );
          },
        ),
      );
    } else {
      final size = sizes.isNotEmpty ? sizes.first : null;
      ref.read(cartProvider.notifier).addItem(item, size: size);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã thêm ${item.name}'), duration: const Duration(seconds: 1)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final menuState = ref.watch(menuProvider((widget.restaurantSlug, widget.tableNumber)));
    final cartItems = ref.watch(cartProvider);
    final totalItems = cartItems.fold<int>(0, (sum, i) => sum + i.quantity);

    return Scaffold(
      appBar: AppBar(
        title: Text(menuState.restaurant?.name ?? 'Thực đơn'),
        actions: [
          badges.Badge(
            badgeContent: Text('$totalItems', style: const TextStyle(color: Colors.white, fontSize: 10)),
            showBadge: totalItems > 0,
            child: IconButton(
              icon: const Icon(Icons.shopping_cart_outlined),
              onPressed: () => context.push('/cart'),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: menuState.isLoading
          ? const LoadingWidget()
          : menuState.error != null
              ? ErrorWidget2(
                  message: menuState.error!,
                  onRetry: () => ref
                      .read(menuProvider((widget.restaurantSlug, widget.tableNumber)).notifier)
                      .loadMenu(widget.restaurantSlug, widget.tableNumber),
                )
              : Column(
                  children: [
                    _CategoryTabs(
                      categories: menuState.categories,
                      selectedIndex: _selectedCategoryIndex,
                      onSelected: (i) => setState(() => _selectedCategoryIndex = i),
                    ),
                    Expanded(
                      child: menuState.categories.isEmpty
                          ? const Center(child: Text('Chưa có thực đơn'))
                          : _MenuItemList(
                              category: menuState.categories[_selectedCategoryIndex],
                              onAddItem: _onAddItem,
                            ),
                    ),
                  ],
                ),
      bottomNavigationBar: totalItems > 0
          ? _CartBar(
              totalItems: totalItems,
              totalAmount: cartItems.fold(0, (sum, i) => sum + i.subtotal),
              onTap: () => context.push('/cart'),
            )
          : null,
    );
  }
}

class _CategoryTabs extends StatelessWidget {
  final List categories;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _CategoryTabs({required this.categories, required this.selectedIndex, required this.onSelected});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 44,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: categories.length,
          itemBuilder: (_, i) {
            final selected = i == selectedIndex;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(categories[i].name as String),
                selected: selected,
                onSelected: (_) => onSelected(i),
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : AppColors.textPrimary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            );
          },
        ),
      );
}

class _MenuItemList extends StatelessWidget {
  final MenuCategory category;
  final void Function(MenuItem, List<MenuItemSize>) onAddItem;

  const _MenuItemList({required this.category, required this.onAddItem});

  @override
  Widget build(BuildContext context) => ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: category.items.length,
        itemBuilder: (_, i) => _MenuItemCard(
          item: category.items[i],
          onAdd: () => onAddItem(category.items[i], category.items[i].sizes),
        ),
      );
}

class _MenuItemCard extends StatelessWidget {
  final MenuItem item;
  final VoidCallback onAdd;

  const _MenuItemCard({required this.item, required this.onAdd});

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: item.image != null
                    ? CachedNetworkImage(
                        imageUrl: item.image!,
                        width: 88,
                        height: 88,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const ShimmerBox(width: 88, height: 88),
                        errorWidget: (_, __, ___) => Container(
                          width: 88,
                          height: 88,
                          color: AppColors.shimmerBase,
                          child: const Icon(Icons.fastfood, color: AppColors.textHint),
                        ),
                      )
                    : Container(
                        width: 88,
                        height: 88,
                        color: AppColors.shimmerBase,
                        child: const Icon(Icons.fastfood, color: AppColors.textHint),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name,
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    if (item.description != null) ...[
                      const SizedBox(height: 4),
                      Text(item.description!,
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              FormatUtils.formatCurrency(item.effectivePrice),
                              style: const TextStyle(
                                  color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                            if (item.discount != null && item.discount! > 0)
                              Text(
                                FormatUtils.formatCurrency(item.basePrice),
                                style: const TextStyle(
                                    color: AppColors.textHint,
                                    decoration: TextDecoration.lineThrough,
                                    fontSize: 12),
                              ),
                          ],
                        ),
                        if (item.isAvailable)
                          InkWell(
                            onTap: onAdd,
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Icon(Icons.add, color: Colors.white, size: 20),
                            ),
                          )
                        else
                          const Text('Hết món',
                              style: TextStyle(color: AppColors.textHint, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _CartBar extends StatelessWidget {
  final int totalItems;
  final double totalAmount;
  final VoidCallback onTap;

  const _CartBar({required this.totalItems, required this.totalAmount, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('$totalItems', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
              const Text('Xem giỏ hàng', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
              Text(FormatUtils.formatCurrency(totalAmount),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );
}
