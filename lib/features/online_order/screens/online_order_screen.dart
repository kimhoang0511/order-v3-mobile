import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/cart_provider.dart';
import '../../../shared/widgets/app_button.dart';

class OnlineOrderScreen extends ConsumerStatefulWidget {
  const OnlineOrderScreen({super.key});

  @override
  ConsumerState<OnlineOrderScreen> createState() => _OnlineOrderScreenState();
}

class _OnlineOrderScreenState extends ConsumerState<OnlineOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _noteController = TextEditingController();
  bool _isOrdering = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _placeOnlineOrder() async {
    if (!_formKey.currentState!.validate()) return;
    final cartItems = ref.read(cartProvider);
    if (cartItems.isEmpty) {
      setState(() => _error = 'Giỏ hàng trống');
      return;
    }
    setState(() { _isOrdering = true; _error = null; });
    try {
      final prefs = await SharedPreferences.getInstance();
      final restaurantSlug = prefs.getString(AppConstants.restaurantSlugKey) ?? '';
      await ref.read(apiClientProvider).post('/api/online-orders', data: {
        'restaurant_slug': restaurantSlug,
        'customer_name': _nameController.text.trim(),
        'customer_phone': _phoneController.text.trim(),
        'customer_address': _addressController.text.trim(),
        'note': _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
        'items': cartItems.map((i) => i.toOrderItemJson()).toList(),
      });
      ref.read(cartProvider.notifier).clearCart();
      if (mounted) {
        context.go('/my-orders');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đặt hàng online thành công!'),
            backgroundColor: AppColors.success,
          ),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Đặt hàng online')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Thông tin giao hàng', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Họ tên',
                  prefixIcon: Icon(Icons.person_outlined),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Vui lòng nhập họ tên' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Số điện thoại',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                validator: (v) => v == null || v.length < 10 ? 'Số điện thoại không hợp lệ' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Địa chỉ giao hàng',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
                maxLines: 2,
                validator: (v) => v == null || v.isEmpty ? 'Vui lòng nhập địa chỉ' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: 'Ghi chú (tuỳ chọn)',
                  prefixIcon: Icon(Icons.note_outlined),
                ),
              ),
              const SizedBox(height: 24),
              Text('Giỏ hàng (${cartItems.length} món)', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...cartItems.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${item.quantity}x ${item.menuItem.name}'),
                        Text('${item.subtotal.toStringAsFixed(0)}đ',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  )),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.error)),
              ],
              const SizedBox(height: 24),
              AppButton(
                label: 'Xác nhận đặt hàng',
                onPressed: _placeOnlineOrder,
                isLoading: _isOrdering,
                icon: Icons.delivery_dining,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
