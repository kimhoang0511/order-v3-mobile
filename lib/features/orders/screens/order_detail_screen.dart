import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format_utils.dart';
import '../../../shared/models/order.dart';
import '../../../shared/widgets/loading_widget.dart';

final orderDetailProvider = FutureProvider.autoDispose.family<Order, int>((ref, id) async {
  final api = ref.read(apiClientProvider);
  final response = await api.get('/api/orders/$id');
  return Order.fromJson(response.data as Map<String, dynamic>);
});

class OrderDetailScreen extends ConsumerWidget {
  final int orderId;
  const OrderDetailScreen({super.key, required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderAsync = ref.watch(orderDetailProvider(orderId));
    return Scaffold(
      appBar: AppBar(title: Text('Đơn #$orderId')),
      body: orderAsync.when(
        loading: () => const LoadingWidget(),
        error: (e, _) => ErrorWidget2(
          message: e is DioException ? ApiException.fromDioError(e).message : e.toString(),
          onRetry: () => ref.invalidate(orderDetailProvider(orderId)),
        ),
        data: (order) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StatusCard(order: order),
            const SizedBox(height: 16),
            _ItemsCard(order: order),
            if (order.note != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Ghi chú', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text(order.note!),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final Order order;
  const _StatusCard({required this.order});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Đơn #${order.id}', style: Theme.of(context).textTheme.titleLarge),
                  Text(order.status.displayName,
                      style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                ],
              ),
              const Divider(height: 24),
              if (order.tableNumber != null)
                _InfoRow(label: 'Bàn', value: order.tableNumber!),
              _InfoRow(label: 'Thời gian', value: FormatUtils.formatDate(order.createdAt)),
              _InfoRow(
                  label: 'Tổng cộng',
                  value: FormatUtils.formatCurrency(order.totalAmount),
                  valueStyle: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 16)),
            ],
          ),
        ),
      );
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final TextStyle? valueStyle;

  const _InfoRow({required this.label, required this.value, this.valueStyle});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: AppColors.textSecondary)),
            Text(value, style: valueStyle),
          ],
        ),
      );
}

class _ItemsCard extends StatelessWidget {
  final Order order;
  const _ItemsCard({required this.order});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Món đã đặt (${order.items.length})',
                  style: Theme.of(context).textTheme.titleMedium),
              const Divider(height: 20),
              ...order.items.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.menuItemName, style: const TextStyle(fontWeight: FontWeight.w500)),
                              if (item.sizeName != null)
                                Text(item.sizeName!,
                                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                              if (item.isTakeaway)
                                const Text('Mang về',
                                    style: TextStyle(color: AppColors.primary, fontSize: 12)),
                            ],
                          ),
                        ),
                        Text('x${item.quantity}', style: const TextStyle(color: AppColors.textSecondary)),
                        const SizedBox(width: 16),
                        Text(FormatUtils.formatCurrency(item.subtotal),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  )),
            ],
          ),
        ),
      );
}
