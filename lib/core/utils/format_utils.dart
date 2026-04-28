import 'package:intl/intl.dart';

class FormatUtils {
  static final _currencyFormatter = NumberFormat.currency(
    locale: 'vi_VN',
    symbol: '₫',
    decimalDigits: 0,
  );

  static String formatCurrency(num amount) => _currencyFormatter.format(amount);

  static String formatDate(DateTime date) => DateFormat('dd/MM/yyyy HH:mm').format(date);

  static String formatShortDate(DateTime date) => DateFormat('dd/MM/yyyy').format(date);

  static String timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    return formatDate(date);
  }
}
