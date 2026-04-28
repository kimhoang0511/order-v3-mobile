import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format_utils.dart';
import '../../../shared/models/bill.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/loading_widget.dart';

final billProvider = FutureProvider.autoDispose.family<TableBill, (String, String)>((ref, params) async {
  final api = ref.read(apiClientProvider);
  final response = await api.get('/api/customer-bill', queryParameters: {
    'restaurant': params.$1,
    'table': params.$2,
  });
  return TableBill.fromJson(response.data as Map<String, dynamic>);
});

class BillScreen extends ConsumerStatefulWidget {
  final String restaurantSlug;
  final String tableNumber;

  const BillScreen({super.key, required this.restaurantSlug, required this.tableNumber});

  @override
  ConsumerState<BillScreen> createState() => _BillScreenState();
}

class _BillScreenState extends ConsumerState<BillScreen> {
  bool _isRequesting = false;

  Future<void> _requestBill() async {
    setState(() => _isRequesting = true);
    try {
      await ref.read(apiClientProvider).post('/api/request-bill', queryParameters: {
        'restaurant': widget.restaurantSlug,
        'table': widget.tableNumber,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã yêu cầu thanh toán. Nhân viên sẽ đến ngay!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiException.fromDioError(e).message), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isRequesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final billAsync = ref.watch(billProvider((widget.restaurantSlug, widget.tableNumber)));
    return Scaffold(
      appBar: AppBar(title: Text('Hoá đơn bàn ${widget.tableNumber}')),
      body: billAsync.when(
        loading: () => const LoadingWidget(),
        error: (e, _) => ErrorWidget2(
          message: e is DioException ? ApiException.fromDioError(e).message : e.toString(),
          onRetry: () => ref.invalidate(billProvider((widget.restaurantSlug, widget.tableNumber))),
        ),
        data: (bill) => Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Chi tiết hoá đơn', style: Theme.of(context).textTheme.titleLarge),
                          const Divider(height: 20),
                          ...bill.items.map((item) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(item.name),
                                          if (item.sizeName != null)
                                            Text(item.sizeName!,
                                                style: const TextStyle(
                                                    color: AppColors.textSecondary, fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                    Text('x${item.quantity}',
                                        style: const TextStyle(color: AppColors.textSecondary)),
                                    const SizedBox(width: 16),
                                    Text(FormatUtils.formatCurrency(item.subtotal),
                                        style: const TextStyle(fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              )),
                          const Divider(height: 24),
                          _SummaryRow(label: 'Tạm tính', value: FormatUtils.formatCurrency(bill.subtotal)),
                          if (bill.discount != null && bill.discount! > 0)
                            _SummaryRow(
                                label: 'Giảm giá',
                                value: '- ${FormatUtils.formatCurrency(bill.discount!)}',
                                color: AppColors.success),
                          if (bill.surcharge != null && bill.surcharge! > 0)
                            _SummaryRow(
                                label: 'Phụ phí',
                                value: FormatUtils.formatCurrency(bill.surcharge!)),
                          const Divider(height: 16),
                          _SummaryRow(
                            label: 'Tổng cộng',
                            value: FormatUtils.formatCurrency(bill.total),
                            isBold: true,
                            color: AppColors.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!bill.isPaid)
              Padding(
                padding: const EdgeInsets.all(16),
                child: AppButton(
                  label: 'Gọi thanh toán',
                  onPressed: _requestBill,
                  isLoading: _isRequesting,
                  icon: Icons.payment,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final Color? color;

  const _SummaryRow({required this.label, required this.value, this.isBold = false, this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
                    fontSize: isBold ? 16 : 14)),
            Text(value,
                style: TextStyle(
                    fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
                    color: color,
                    fontSize: isBold ? 18 : 14)),
          ],
        ),
      );
}
