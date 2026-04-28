import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_client.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/providers/webview_overlay_provider.dart';
import '../models/table_item.dart';
import '../providers/tables_provider.dart';

class TablePickerSheet extends ConsumerStatefulWidget {
  final String restaurantSlug;
  final String? staffToken;
  final bool showOnlineOrder;

  const TablePickerSheet({
    super.key,
    required this.restaurantSlug,
    this.staffToken,
    this.showOnlineOrder = true,
  });

  @override
  ConsumerState<TablePickerSheet> createState() => _TablePickerSheetState();
}

class _TablePickerSheetState extends ConsumerState<TablePickerSheet> {
  final _searchCtrl = TextEditingController();
  final _mergeSearchCtrl = TextEditingController();
  String _search = '';
  TableItem? _mergeFromTable;
  String _mergeSearch = '';
  bool _mergeLoading = false;

  TablesNotifier get _notifier =>
      ref.read(tablesNotifierProvider(widget.restaurantSlug).notifier);

  @override
  void dispose() {
    _searchCtrl.dispose();
    _mergeSearchCtrl.dispose();
    super.dispose();
  }

  void _onSelectTable(TableItem t) {
    if (t.isLocked) return;
    Navigator.pop(context);
    ref.read(webViewOverlayProvider.notifier).show(
      url: AppConstants.menuUrl(widget.restaurantSlug, t.tableNumber, staffToken: widget.staffToken),
      title: 'Bàn ${t.tableNumber}',
      restaurantSlug: widget.restaurantSlug,
    );
  }

  void _onOnlineOrder() {
    Navigator.pop(context);
    ref.read(webViewOverlayProvider.notifier).show(
      url: AppConstants.menuUrl(widget.restaurantSlug, 'online', staffToken: widget.staffToken),
      title: 'Đặt online',
      restaurantSlug: widget.restaurantSlug,
    );
  }

  void _openMerge(TableItem t) {
    setState(() {
      _mergeFromTable = t;
      _mergeSearch = '';
      _mergeSearchCtrl.clear();
    });
  }

  void _closeMerge() {
    setState(() {
      _mergeFromTable = null;
      _mergeSearch = '';
      _mergeSearchCtrl.clear();
    });
  }

  Future<bool> _hasActiveOrders(String tableNumber) async {
    try {
      final isStaff = widget.staffToken != null;
      final res = await ref.read(apiClientProvider).get(
        isStaff ? '/api/staff-view/active-tables' : '/api/manage/active-tables',
        queryParameters: isStaff ? {'t': widget.staffToken} : null,
      );
      final list = res.data as List<dynamic>;
      return list.any((t) => (t as Map<String, dynamic>)['table_number'] == tableNumber);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _showConfirm({
    required String title,
    required String message,
    required String confirmText,
    required String cancelText,
    Color confirmColor = const Color(0xFF3B82F6),
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancelText, style: const TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _showAlert({required String title, required String message}) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(message),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmMerge(TableItem target) async {
    if (_mergeFromTable == null) return;
    setState(() => _mergeLoading = true);
    try {
      final isStaff = widget.staffToken != null;
      final allTables = ref.read(tablesNotifierProvider(widget.restaurantSlug)).valueOrNull ?? [];
      String effectiveTo = target.tableNumber;
      int effectiveToId = target.id;
      bool needRetryMerge = false;

      // Pre-check: ask about active orders BEFORE creating anything on the server.
      // This ensures "Huỷ gộp bàn" truly cancels the whole operation.
      if (!mounted) return;
      final active = await _hasActiveOrders(_mergeFromTable!.tableNumber);
      if (!mounted) return;
      bool wantsTransfer = false;
      if (active) {
        final ok = await _showConfirm(
          title: 'Chuyển đơn hàng',
          message:
              'Bàn ${_mergeFromTable!.tableNumber} đang có đơn hàng chưa thanh toán.\nBạn có muốn cập nhật các đơn hàng từ Bàn ${_mergeFromTable!.tableNumber} → Bàn $effectiveTo không?',
          confirmText: 'Cập nhật',
          cancelText: 'Huỷ gộp bàn',
          confirmColor: const Color(0xFFF59E0B),
        );
        if (!mounted || !ok) return;
        wantsTransfer = true;
      }

      // Step 1: Attempt merge to detect chain redirects
      try {
        await ref.read(apiClientProvider).post(
          isStaff ? '/api/staff-view/table-redirects' : '/api/manage/table-redirects',
          data: {
            'from_table': _mergeFromTable!.tableNumber,
            'to_table': effectiveTo,
            if (!isStaff) 'restaurant_slug': widget.restaurantSlug,
          },
          queryParameters: isStaff ? {'t': widget.staffToken} : null,
        );
      } on DioException catch (e) {
        if (!mounted) return;
        final errData = (e.response?.data as Map<String, dynamic>?) ?? {};
        if (e.response?.statusCode == 409 && errData['suggest_to'] != null) {
          // Target already redirected → offer chain merge
          final suggestTo = errData['suggest_to'] as String;
          final ok = await _showConfirm(
            title: 'Gộp bàn chuỗi',
            message:
                'Bàn $effectiveTo đang gộp vào bàn $suggestTo rồi, có muốn gộp bàn ${_mergeFromTable!.tableNumber} vào bàn $suggestTo luôn không?',
            confirmText: 'Gộp luôn',
            cancelText: 'Huỷ',
          );
          if (!mounted || !ok) return;
          effectiveTo = suggestTo;
          final found = allTables.where((t) => t.tableNumber == suggestTo).firstOrNull;
          if (found != null) effectiveToId = found.id;
          needRetryMerge = true;
        } else {
          await _showAlert(
            title: 'Gộp bàn thất bại',
            message: errData['detail'] as String? ?? 'Không thể gộp bàn',
          );
          return;
        }
      }

      // Step 2: Transfer active orders if user confirmed before merge
      if (wantsTransfer) {
        if (!mounted) return;
        try {
          await ref.read(apiClientProvider).post(
            isStaff
                ? '/api/staff-view/tables/${_mergeFromTable!.id}/transfer'
                : '/api/manage/tables/${_mergeFromTable!.id}/transfer',
            data: {'target_table_id': effectiveToId},
            queryParameters: isStaff ? {'t': widget.staffToken} : null,
          );
        } on DioException catch (e) {
          if (!mounted) return;
          final errData = (e.response?.data as Map<String, dynamic>?) ?? {};
          await _showAlert(
            title: 'Lỗi chuyển đơn',
            message: errData['detail'] as String? ?? 'Không thể chuyển đơn hàng sang bàn đích',
          );
          return;
        }
      }

      // Step 3: Retry merge with resolved effective target if chain redirect
      if (needRetryMerge) {
        if (!mounted) return;
        try {
          await ref.read(apiClientProvider).post(
            isStaff ? '/api/staff-view/table-redirects' : '/api/manage/table-redirects',
            data: {
              'from_table': _mergeFromTable!.tableNumber,
              'to_table': effectiveTo,
              if (!isStaff) 'restaurant_slug': widget.restaurantSlug,
            },
            queryParameters: isStaff ? {'t': widget.staffToken} : null,
          );
        } on DioException catch (e) {
          if (!mounted) return;
          final errData = (e.response?.data as Map<String, dynamic>?) ?? {};
          await _showAlert(
            title: 'Gộp bàn thất bại',
            message: errData['detail'] as String? ?? 'Không thể gộp bàn',
          );
          return;
        }
      }

      if (!mounted) return;
      _notifier.applyOptimisticChange(_mergeFromTable!.tableNumber, effectiveTo);
      setState(() {
        _mergeFromTable = null;
        _mergeSearch = '';
        _mergeSearchCtrl.clear();
      });
    } catch (_) {
      if (mounted) {
        await _showAlert(title: 'Lỗi', message: 'Lỗi kết nối, vui lòng thử lại');
      }
    } finally {
      if (mounted) setState(() => _mergeLoading = false);
    }
  }

  Future<void> _confirmSplit(TableItem t) async {
    final ok = await _showConfirm(
      title: 'Tách bàn',
      message:
          'Bàn ${t.tableNumber} đang gộp vào bàn ${t.redirectTo}.\nBạn có muốn tách 2 bàn này không?',
      confirmText: 'Tách bàn',
      cancelText: 'Huỷ',
      confirmColor: const Color(0xFFF97316),
    );
    if (!mounted || !ok) return;
    try {
      final isStaff = widget.staffToken != null;
      await ref.read(apiClientProvider).post(
        isStaff
            ? '/api/staff-view/table-redirects/deactivate'
            : '/api/manage/table-redirects/deactivate',
        data: {
          'from_table': t.tableNumber,
          if (!isStaff) 'restaurant_slug': widget.restaurantSlug,
        },
        queryParameters: isStaff ? {'t': widget.staffToken} : null,
      );
      if (!mounted) return;
      _notifier.applyOptimisticChange(t.tableNumber, null);
    } on DioException catch (e) {
      if (!mounted) return;
      final errData = (e.response?.data as Map<String, dynamic>?) ?? {};
      await _showAlert(
        title: 'Tách bàn thất bại',
        message: errData['detail'] as String? ?? 'Không thể tách bàn',
      );
    } catch (_) {
      if (mounted) await _showAlert(title: 'Lỗi', message: 'Lỗi kết nối, vui lòng thử lại');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tablesAsync = ref.watch(tablesNotifierProvider(widget.restaurantSlug));

    final tables = tablesAsync.valueOrNull ?? [];
    final filtered = tables
        .where((t) => t.tableNumber.toLowerCase().contains(_search.toLowerCase()))
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollCtrl) => Stack(
        children: [
          // ── Main table picker sheet ───────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),

                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      const Text(
                        'Chọn bàn để đặt',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
                      ),
                      const SizedBox(width: 8),
                      // QR button
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/qr-scanner');
                        },
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: const BoxDecoration(
                              color: Color(0xFFFFFBEB), shape: BoxShape.circle),
                          child: const Icon(Icons.camera_alt_outlined,
                              size: 16, color: Color(0xFFF59E0B)),
                        ),
                      ),
                      const Spacer(),
                      // Đặt online
                      if (widget.showOnlineOrder) ...[
                        GestureDetector(
                          onTap: _onOnlineOrder,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text('Đặt online',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      // Close
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration:
                              BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
                          child: const Icon(Icons.close, size: 16, color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Search
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _search = v),
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Tìm kiếm...',
                      hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFF59E0B)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Table grid
                Expanded(
                  child: tablesAsync.hasError
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline, color: Colors.grey, size: 40),
                                const SizedBox(height: 12),
                                Text(
                                  tablesAsync.error.toString().replaceAll('Exception: ', ''),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: () => ref.invalidate(
                                      tablesNotifierProvider(widget.restaurantSlug)),
                                  child: const Text('Thử lại'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : tablesAsync.isLoading
                          ? const Center(
                              child: CircularProgressIndicator(color: Color(0xFFF59E0B)))
                          : filtered.isEmpty
                              ? const Center(
                                  child: Text('Không tìm thấy bàn nào',
                                      style: TextStyle(color: Colors.grey)))
                              : GridView.builder(
                                  controller: scrollCtrl,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 4),
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    crossAxisSpacing: 10,
                                    mainAxisSpacing: 10,
                                    childAspectRatio: 1.0,
                                  ),
                                  itemCount: filtered.length,
                                  itemBuilder: (_, i) => _TableCard(
                                    table: filtered[i],
                                    onSelect: () => _onSelectTable(filtered[i]),
                                    onMerge: () => _openMerge(filtered[i]),
                                    onSplit: () => _confirmSplit(filtered[i]),
                                  ),
                                ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),

          // ── Merge sheet overlay ───────────────────────────────────────────
          if (_mergeFromTable != null)
            _MergeSheet(
              fromTable: _mergeFromTable!,
              allTables: tables,
              mergeSearch: _mergeSearch,
              mergeSearchCtrl: _mergeSearchCtrl,
              mergeLoading: _mergeLoading,
              onSearchChange: (v) => setState(() => _mergeSearch = v),
              onClose: _closeMerge,
              onConfirm: _confirmMerge,
            ),
        ],
      ),
    );
  }
}

// ── Merge sheet overlay ─────────────────────────────────────────────────────

class _MergeSheet extends StatelessWidget {
  final TableItem fromTable;
  final List<TableItem> allTables;
  final String mergeSearch;
  final TextEditingController mergeSearchCtrl;
  final bool mergeLoading;
  final ValueChanged<String> onSearchChange;
  final VoidCallback onClose;
  final Future<void> Function(TableItem) onConfirm;

  const _MergeSheet({
    required this.fromTable,
    required this.allTables,
    required this.mergeSearch,
    required this.mergeSearchCtrl,
    required this.mergeLoading,
    required this.onSearchChange,
    required this.onClose,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final targets = allTables
        .where((t) =>
            t.id != fromTable.id &&
            t.tableNumber.toLowerCase().contains(mergeSearch.toLowerCase()))
        .toList();

    return Stack(
      children: [
        // Backdrop
        GestureDetector(
          onTap: onClose,
          child: Container(color: Colors.black.withOpacity(0.5)),
        ),
        // Sheet
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            child: Stack(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Gộp bàn',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1F2937))),
                        GestureDetector(
                          onTap: onClose,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                                color: Colors.grey.shade100, shape: BoxShape.circle),
                            child: const Icon(Icons.close, size: 16, color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                        children: [
                          const TextSpan(text: 'Gộp bàn '),
                          TextSpan(
                            text: 'Bàn ${fromTable.tableNumber}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, color: Color(0xFF2563EB)),
                          ),
                          const TextSpan(text: ' sang bàn:'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: mergeSearchCtrl,
                      onChanged: onSearchChange,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Tìm kiếm bàn đích...',
                        hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF60A5FA)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: targets.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: Text('Không tìm thấy bàn',
                                    style: TextStyle(color: Colors.grey)),
                              ),
                            )
                          : GridView.builder(
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                childAspectRatio: 1.0,
                              ),
                              itemCount: targets.length,
                              itemBuilder: (_, i) => _MergeTargetCard(
                                table: targets[i],
                                loading: mergeLoading,
                                onTap: () => onConfirm(targets[i]),
                              ),
                            ),
                    ),
                  ],
                ),
                // Loading overlay
                if (mergeLoading)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.7),
                        borderRadius:
                            const BorderRadius.vertical(top: Radius.circular(24)),
                      ),
                      child: const Center(
                        child: CircularProgressIndicator(color: Color(0xFF60A5FA)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Table card (main grid) ──────────────────────────────────────────────────

class _TableCard extends StatelessWidget {
  final TableItem table;
  final VoidCallback onSelect;
  final VoidCallback onMerge;
  final VoidCallback onSplit;

  const _TableCard({
    required this.table,
    required this.onSelect,
    required this.onMerge,
    required this.onSplit,
  });

  @override
  Widget build(BuildContext context) {
    final locked = table.isLocked;
    final merged = table.redirectTo != null;

    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onTap: locked ? null : onSelect,
          child: Container(
            decoration: BoxDecoration(
              color: locked ? Colors.grey.shade100 : const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: locked ? Colors.grey.shade200 : const Color(0xFFFDE68A)),
            ),
            child: Opacity(
              opacity: locked ? 0.6 : 1.0,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: locked ? Colors.grey.shade400 : const Color(0xFFFBBF24),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.table_restaurant_rounded,
                          color: Colors.white, size: 20),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Bàn ${table.tableNumber}',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: locked ? Colors.grey.shade400 : const Color(0xFF374151),
                      ),
                    ),
                    if (merged)
                      Text(
                        '→${table.redirectTo}',
                        style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFFF97316),
                            fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Merge / split button (top-left)
        Positioned(
          top: 6,
          left: 6,
          child: merged
              ? GestureDetector(
                  onTap: onSplit,
                  child: Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                        color: const Color(0xFFF97316),
                        borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.table_restaurant_rounded,
                            size: 14, color: Colors.white),
                        const SizedBox(width: 3),
                        Text(table.redirectTo ?? '',
                            style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                )
              : GestureDetector(
                  onTap: onMerge,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 6)
                      ],
                    ),
                    child: const Icon(Icons.link_rounded,
                        size: 18, color: Color(0xFF3B82F6)),
                  ),
                ),
        ),
      ],
    );
  }
}

// ── Merge target card (blue accent) ────────────────────────────────────────

class _MergeTargetCard extends StatelessWidget {
  final TableItem table;
  final bool loading;
  final VoidCallback onTap;

  const _MergeTargetCard(
      {required this.table, required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Opacity(
        opacity: loading ? 0.5 : 1.0,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFDBEAFE)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.link_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(height: 6),
              Text(
                'Bàn ${table.tableNumber}',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF374151)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
