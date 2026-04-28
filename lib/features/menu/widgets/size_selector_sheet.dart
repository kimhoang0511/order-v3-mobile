import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format_utils.dart';
import '../../../shared/models/menu_item.dart';
import '../../../shared/widgets/app_button.dart';

class SizeSelectorSheet extends StatefulWidget {
  final MenuItem menuItem;
  final List<MenuItemSize> sizes;
  final void Function(MenuItemSize? size, int qty, bool isTakeaway) onConfirm;

  const SizeSelectorSheet({
    super.key,
    required this.menuItem,
    required this.sizes,
    required this.onConfirm,
  });

  @override
  State<SizeSelectorSheet> createState() => _SizeSelectorSheetState();
}

class _SizeSelectorSheetState extends State<SizeSelectorSheet> {
  MenuItemSize? _selectedSize;
  int _quantity = 1;
  bool _isTakeaway = false;

  @override
  void initState() {
    super.initState();
    if (widget.sizes.isNotEmpty) _selectedSize = widget.sizes.first;
  }

  double get _price => _selectedSize?.price ?? widget.menuItem.effectivePrice;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(
                color: AppColors.border, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            Text(widget.menuItem.name, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            if (widget.sizes.length > 1) ...[
              Text('Chọn size', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: widget.sizes.map((size) => ChoiceChip(
                  label: Text('${size.sizeName} - ${FormatUtils.formatCurrency(size.price)}'),
                  selected: _selectedSize?.id == size.id,
                  onSelected: (_) => setState(() => _selectedSize = size),
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(
                    color: _selectedSize?.id == size.id ? Colors.white : AppColors.textPrimary,
                  ),
                )).toList(),
              ),
              const SizedBox(height: 16),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Mang về'),
                Switch(
                  value: _isTakeaway,
                  onChanged: (v) => setState(() => _isTakeaway = v),
                  activeColor: AppColors.primary,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Số lượng', style: TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('$_quantity', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                IconButton(
                  onPressed: () => setState(() => _quantity++),
                  icon: const Icon(Icons.add_circle_outline, color: AppColors.primary),
                ),
              ],
            ),
            const SizedBox(height: 16),
            AppButton(
              label: 'Thêm vào giỏ - ${FormatUtils.formatCurrency(_price * _quantity)}',
              onPressed: () {
                Navigator.pop(context);
                widget.onConfirm(_selectedSize, _quantity, _isTakeaway);
              },
            ),
          ],
        ),
      );
}
