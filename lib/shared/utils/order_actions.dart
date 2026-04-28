import 'package:flutter/material.dart';
import '../../features/tables/widgets/table_picker_sheet.dart';

/// Hiện bottom sheet chọn bàn để đặt món.
/// Dùng chung cho HomeScreen và StaffViewScreen.
void showOrderTablePicker(
  BuildContext context,
  String restaurantSlug, {
  String? staffToken,
  bool showOnlineOrder = true,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => TablePickerSheet(
      restaurantSlug: restaurantSlug,
      staffToken: staffToken,
      showOnlineOrder: showOnlineOrder,
    ),
  );
}
