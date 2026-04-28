import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/services/push_notification_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/webview_overlay_provider.dart';
import '../../../shared/utils/order_actions.dart';
import '../../printer/providers/printer_settings_provider.dart';

// ── Models ────────────────────────────────────────────────────────────────────

class _StaffInfo {
  final String staffName;
  final String restaurantName;
  final String restaurantSlug;
  final bool featureOnlineOrdering;

  const _StaffInfo({
    required this.staffName,
    required this.restaurantName,
    required this.restaurantSlug,
    this.featureOnlineOrdering = false,
  });

  factory _StaffInfo.fromJson(Map<String, dynamic> json) => _StaffInfo(
        staffName: json['staff_name'] as String? ?? '',
        restaurantName: json['restaurant_name'] as String? ?? '',
        restaurantSlug: json['restaurant_slug'] as String? ?? '',
        featureOnlineOrdering: json['feature_online_ordering'] as bool? ?? false,
      );
}

// ── Screen ────────────────────────────────────────────────────────────────────

class StaffViewScreen extends ConsumerStatefulWidget {
  final String token;

  const StaffViewScreen({super.key, required this.token});

  @override
  ConsumerState<StaffViewScreen> createState() => _StaffViewScreenState();
}

class _StaffViewScreenState extends ConsumerState<StaffViewScreen> {
  Timer? _pollTimer;

  _StaffInfo? _info;
  bool _loadingInfo = true;
  String? _error;

  int _pendingCount = 0;
  int _tableCount = 0;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<String> _getBase() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.apiBasePathKey) ?? AppConstants.defaultApiUrl;
  }

  Future<void> _loadInfo() async {
    try {
      final base = await _getBase();
      final res = await http
          .get(Uri.parse('$base/api/staff-view/info?t=${Uri.encodeComponent(widget.token)}'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 401 || res.statusCode == 403 || res.statusCode == 404) {
        if (mounted) setState(() { _error = 'unauthorized'; _loadingInfo = false; });
        return;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['detail'] != null) {
        if (mounted) setState(() { _error = 'Không tìm thấy nhân viên'; _loadingInfo = false; });
        return;
      }
      if (mounted) setState(() { _info = _StaffInfo.fromJson(data); _loadingInfo = false; });
      ref.read(printerSettingsProvider.notifier).syncFromServer();
      PushNotificationService.registerForStaff(widget.token).ignore();
      await _fetchStats();
      _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => _fetchStats());
    } catch (_) {
      if (mounted) setState(() { _error = 'Không thể tải thông tin'; _loadingInfo = false; });
    }
  }

  Future<void> _fetchStats() async {
    final base = await _getBase();
    final t = Uri.encodeComponent(widget.token);
    try {
      final results = await Future.wait([
        http.get(Uri.parse('$base/api/staff-view/pending-sessions?t=$t')).timeout(const Duration(seconds: 8)),
        http.get(Uri.parse('$base/api/staff-view/orders?t=$t')).timeout(const Duration(seconds: 8)),
        http.get(Uri.parse('$base/api/staff-view/active-tables?t=$t')).timeout(const Duration(seconds: 8)),
      ]);
      if (!mounted) return;

      int pending = 0;
      if (results[0].statusCode == 200) {
        final sessions = jsonDecode(results[0].body) as List<dynamic>;
        pending += sessions.length;
      }
      if (results[1].statusCode == 200) {
        final orders = (jsonDecode(results[1].body) as List<dynamic>)
            .where((o) => ((o as Map)['items'] as List?)?.isNotEmpty == true && (o)['table_number'] != 'online')
            .length;
        pending += orders;
      }
      int tables = 0;
      if (results[2].statusCode == 200) {
        final all = (jsonDecode(results[2].body) as List<dynamic>)
            .where((t) => (t as Map)['table_number'] != 'online');
        tables = all.length;
      }
      setState(() { _pendingCount = pending; _tableCount = tables; });
    } catch (_) {}
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loadingInfo) {
      return const Scaffold(
        backgroundColor: Color(0xFFFBBF24),
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFFEF3C7),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error == 'unauthorized' ? '🔒' : '😕',
                      style: const TextStyle(fontSize: 56)),
                  const SizedBox(height: 16),
                  Text(
                    _error == 'unauthorized'
                        ? 'Token nhân viên không hợp lệ hoặc đã hết hạn'
                        : _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => context.go('/login-choice'),
                    child: const Text('Quét lại QR'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return _buildHome();
  }

  Widget _buildHome() {
    final totalBadge = _pendingCount > 0 ? _pendingCount : null;
    final staffUrl =
        '${AppConstants.webBaseUrl}/staff-view?t=${Uri.encodeComponent(widget.token)}&mode=manage&tab=orders';

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // ── Amber header ──────────────────────────────────────────────────
          Container(
            color: const Color(0xFFFBBF24),
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
                    child: Row(
                      children: [
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.logout, color: Colors.white70, size: 20),
                          onPressed: () async {
                            final staffToken = await AppSecureStorage.read(AppConstants.staffTokenKey);
                            if (staffToken != null) {
                              PushNotificationService.clearTokenForStaff(staffToken).ignore();
                            }
                            await AppSecureStorage.delete(AppConstants.staffTokenKey);
                            if (mounted) context.go('/login-choice');
                          },
                        ),
                      ],
                    ),
                  ),
                  const Text('👋', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 8),
                  Text(
                    'Xin chào, ${_info!.staffName}!',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _info!.restaurantName,
                    style: const TextStyle(color: Color(0xFF78350F), fontSize: 14),
                  ),
                  const SizedBox(height: 36),
                ],
              ),
            ),
          ),

          // ── Stats card (floating over amber via negative translate) ────────
          Transform.translate(
            offset: const Offset(0, -20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                child: Column(
                  children: [
                    _StatRow(
                      icon: Icons.assignment_outlined,
                      iconBg: const Color(0xFFFEF3C7),
                      iconColor: const Color(0xFFD97706),
                      label: 'Đơn chờ xử lý',
                      value: _pendingCount > 0
                          ? '$_pendingCount đơn đang chờ'
                          : 'Không có đơn mới',
                      hasAlert: _pendingCount > 0,
                    ),
                    const SizedBox(height: 16),
                    _StatRow(
                      icon: Icons.table_restaurant,
                      iconBg: const Color(0xFFCCFBF1),
                      iconColor: const Color(0xFF0D9488),
                      label: 'Bàn đang phục vụ',
                      value: _tableCount > 0
                          ? '$_tableCount bàn đang hoạt động'
                          : 'Chưa có bàn nào',
                      hasAlert: false,
                    ),
                  ],
                ),
              ),
            ),
          ),

          const Spacer(),

          // ── 4 action buttons: left=amber, right=outlined ───────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Left column — amber
                Expanded(
                  child: Column(
                    children: [
                      _HomeButton(
                        icon: Icons.restaurant_menu,
                        label: 'Đặt món',
                        amber: true,
                        onTap: () => showOrderTablePicker(context, _info!.restaurantSlug, staffToken: widget.token, showOnlineOrder: _info!.featureOnlineOrdering),
                      ),
                      const SizedBox(height: 12),
                      _HomeButton(
                        icon: Icons.qr_code_scanner,
                        label: 'Quét đặt nhanh',
                        amber: true,
                        onTap: () => context.push('/qr-scanner?mode=quick-order'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Right column — outlined
                Expanded(
                  child: Column(
                    children: [
                      _HomeButton(
                        icon: Icons.receipt_long,
                        label: 'Quản lý đơn đặt',
                        amber: false,
                        badge: totalBadge,
                        onTap: () => ref.read(webViewOverlayProvider.notifier).show(
                          url: staffUrl,
                          title: 'Quản lý đơn đặt',
                          ignoreWebViewHistory: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _HomeButton(
                        icon: Icons.camera_alt_outlined,
                        label: 'Quét tìm bàn nhanh',
                        amber: false,
                        onTap: () => context.push(
                          '/qr-scanner?mode=find-table&t=${Uri.encodeComponent(widget.token)}',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

// ── Stat row ──────────────────────────────────────────────────────────────────

class _StatRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final String value;
  final bool hasAlert;

  const _StatRow({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.hasAlert,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: hasAlert ? const Color(0xFFD97706) : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      );
}

// ── Home button ───────────────────────────────────────────────────────────────

class _HomeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool amber;
  final int? badge;
  final VoidCallback onTap;

  const _HomeButton({
    required this.icon,
    required this.label,
    required this.amber,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = amber ? const Color(0xFFFBBF24) : Colors.white;
    final fg = amber ? Colors.white : AppColors.textPrimary;
    final borderColor = amber ? Colors.transparent : AppColors.border;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, color: fg, size: 26),
                  if (badge != null)
                    Positioned(
                      top: -6,
                      right: -10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$badge',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: fg,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
