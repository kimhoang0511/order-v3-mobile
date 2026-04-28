import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format_utils.dart';
import '../../../shared/models/cart_item.dart';
import '../../../shared/providers/cart_provider.dart';
import '../../../shared/widgets/app_button.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  final _noteController = TextEditingController();
  bool _isOrdering = false;
  String? _error;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _placeOrder() async {
    final cartItems = ref.read(cartProvider);
    if (cartItems.isEmpty) return;
    setState(() { _isOrdering = true; _error = null; });
    try {
      final prefs = await SharedPreferences.getInstance();
      final restaurantSlug = prefs.getString(AppConstants.restaurantSlugKey) ?? '';
      final tableNumber = prefs.getString(AppConstants.tableNumberKey) ?? '';
      await ref.read(apiClientProvider).post('/api/orders', data: {
        'restaurant_slug': restaurantSlug,
        'table_number': tableNumber,
        'note': _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
        'items': cartItems.map((i) => i.toOrderItemJson()).toList(),
      });
      ref.read(cartProvider.notifier).clearCart();
      if (mounted) {
        context.go('/my-orders');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đặt món thành công!'), backgroundColor: AppColors.success),
        );
      }
    } on DioException catch (e) {
      setState(() => _error = ApiException.fromDioError(e).message);
    } finally {
      if (mounted) setState(() => _isOrdering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartItems = ref.watch(cartProvider);
    final totalAmount = cartItems.fold<double>(0, (s, i) => s + i.subtotal);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Giỏ hàng'),
        actions: [
          if (cartItems.isNotEmpty)
            TextButton(
              onPressed: () => ref.read(cartProvider.notifier).clearCart(),
              child: const Text('Xóa tất cả', style: TextStyle(color: AppColors.error)),
            ),
        ],
      ),
      body: cartItems.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.shopping_cart_outlined, size: 80, color: AppColors.textHint),
                  const SizedBox(height: 16),
                  const Text('Giỏ hàng trống'),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: () => context.pop(), child: const Text('Tiếp tục đặt món')),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: cartItems.length,
                    itemBuilder: (_, i) => _CartItemCard(item: cartItems[i]),
                  ),
                ),
                _OrderSummary(
                  cartItems: cartItems,
                  totalAmount: totalAmount,
                  noteController: _noteController,
                  error: _error,
                  isOrdering: _isOrdering,
                  onOrder: _placeOrder,
                ),
              ],
            ),
    );
  }
}

class _CartItemCard extends ConsumerWidget {
  final CartItem item;
  const _CartItemCard({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.read(cartProvider.notifier);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.menuItem.name, style: Theme.of(context).textTheme.titleMedium),
                  if (item.size != null)
                    Text(item.size!.sizeName,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  if (item.isTakeaway)
                    const Text('Mang về',
                        style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text(FormatUtils.formatCurrency(item.subtotal),
                      style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, color: AppColors.primary),
                  onPressed: () => cart.updateQuantity(item.cartId, item.quantity - 1),
                ),
                Text('${item.quantity}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, color: AppColors.primary),
                  onPressed: () => cart.updateQuantity(item.cartId, item.quantity + 1),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderSummary extends StatelessWidget {
  final List<CartItem> cartItems;
  final double totalAmount;
  final TextEditingController noteController;
  final String? error;
  final bool isOrdering;
  final VoidCallback onOrder;

  const _OrderSummary({
    required this.cartItems,
    required this.totalAmount,
    required this.noteController,
    this.error,
    required this.isOrdering,
    required this.onOrder,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: noteController,
              decoration: const InputDecoration(
                hintText: 'Ghi chú đơn hàng (tuỳ chọn)',
                prefixIcon: Icon(Icons.note_outlined),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Tổng cộng', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                Text(FormatUtils.formatCurrency(totalAmount),
                    style: const TextStyle(
                        color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 18)),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
            ],
            const SizedBox(height: 12),
            AppButton(
              label: 'Đặt món',
              onPressed: onOrder,
              isLoading: isOrdering,
              icon: Icons.check,
            ),
          ],
        ),
      );
}
