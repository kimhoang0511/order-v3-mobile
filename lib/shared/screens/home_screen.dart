import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../utils/order_actions.dart';
import '../../core/constants/app_constants.dart';
import '../../features/printer/models/printer_settings.dart';
import '../../features/printer/providers/printer_app_state_provider.dart';
import '../../features/printer/providers/printer_settings_provider.dart';
import '../../features/printer/screens/printer_settings_screen.dart';
import '../../features/printer/services/printer_scanner.dart';
import '../../features/printer/services/websocket_service.dart';
import '../providers/webview_overlay_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _autoScanTriggered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoScan());
  }

  Future<void> _maybeAutoScan() async {
    if (_autoScanTriggered) return;
    _autoScanTriggered = true;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(AppConstants.printerScanSkippedKey) == true) return;

    final settings = ref.read(printerSettingsProvider);
    if (settings.connectionType != PrinterConnectionType.network) return;

    // Probe cả 2 máy in song song — nếu bất kỳ máy nào kết nối được thì không cần scan
    final probes = await Future.wait([
      if (settings.kitchenEnabled) _probe(settings.ipAddress, settings.port),
      if (settings.billEnabled) _probe(settings.billIpAddress, settings.billPort),
    ]);
    if (!mounted) return;
    if (probes.isEmpty || probes.any((ok) => ok)) return;

    // Hiện thông báo đang scan
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
          SizedBox(width: 12),
          Text('Đang tìm kiếm máy in trong mạng...'),
        ]),
        duration: Duration(seconds: 30),
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      final results = await PrinterScanner.scan(port: settings.port);
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (results.isEmpty) return;

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _PrinterFoundSheet(results: results),
      );
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }
  }

  Future<bool> _probe(String ip, int port) async {
    try {
      final socket = await Socket.connect(ip, port, timeout: const Duration(milliseconds: 600));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final restaurantName = auth.user?.restaurantName ?? '';
    final logoUrl = auth.user?.logoUrl;

    // Khởi động printer state: load settings từ SharedPrefs → configure WS
    ref.watch(printerAppStateProvider);

    void doLogout() {
      ref.read(authProvider.notifier).logout();
      context.go('/login-choice');
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFFBEB), Color(0xFFFFF7ED)],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final isLandscapeTablet = constraints.maxWidth >= 700;
                  return isLandscapeTablet
                      ? _TabletLayout(restaurantName: restaurantName, logoUrl: logoUrl, onLogout: doLogout, ref: ref)
                      : _PhoneLayout(restaurantName: restaurantName, logoUrl: logoUrl, onLogout: doLogout, ref: ref);
                },
              ),
              Positioned(
                top: 12,
                right: 16,
                child: _PrinterButton(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Phone layout: single column scroll ────────────────────────────────────

class _PhoneLayout extends StatelessWidget {
  final String restaurantName;
  final String? logoUrl;
  final VoidCallback onLogout;
  final WidgetRef ref;

  const _PhoneLayout({required this.restaurantName, required this.logoUrl, required this.onLogout, required this.ref});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        children: [
          const SizedBox(height: 8),
          _Logo(logoUrl: logoUrl, size: 80),
          const SizedBox(height: 16),
          _WelcomeText(restaurantName: restaurantName),
          const SizedBox(height: 32),
          ..._buildCards(context, ref, spacing: 16),
          const SizedBox(height: 24),
          _LogoutButton(onLogout: onLogout),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ─── Tablet landscape layout: sidebar left + 2-col grid right ──────────────

class _TabletLayout extends StatelessWidget {
  final String restaurantName;
  final String? logoUrl;
  final VoidCallback onLogout;
  final WidgetRef ref;

  const _TabletLayout({required this.restaurantName, required this.logoUrl, required this.onLogout, required this.ref});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left sidebar
        Container(
          width: 260,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.6),
            border: Border(right: BorderSide(color: Colors.amber.shade100, width: 1.5)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Logo(logoUrl: logoUrl, size: 96),
              const SizedBox(height: 20),
              _WelcomeText(restaurantName: restaurantName, centerAlign: true),
              const Spacer(),
              _LogoutButton(onLogout: onLogout),
              const SizedBox(height: 8),
            ],
          ),
        ),

        // Right content: 2-column card grid
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 2.4,
                  children: _buildCards(context, ref, spacing: 0),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Shared card definitions ───────────────────────────────────────────────

List<Widget> _buildCards(BuildContext context, WidgetRef ref, {required double spacing}) {
  final cards = [
    _ActionCard(
      gradient: const LinearGradient(colors: [Color(0xFF818CF8), Color(0xFFA855F7)]),
      icon: '📋',
      title: 'Quản lý menu',
      subtitle: 'Thêm, sửa, xóa món ăn',
      onTap: () => context.push('/menu-manage'),
    ),
    _ActionCard(
      gradient: const LinearGradient(colors: [Color(0xFFFB923C), Color(0xFFF59E0B)]),
      icon: '🍜',
      title: 'Đặt món',
      subtitle: 'Xem menu, đặt món cho khách',
      onTap: () {
        final user = ref.read(authProvider).user;
        showOrderTablePicker(
          context,
          user?.restaurantSlug ?? '',
          showOnlineOrder: user?.featureOnlineOrdering ?? false,
        );
      },
    ),
    _ActionCard(
      gradient: const LinearGradient(colors: [Color(0xFF2DD4BF), Color(0xFF10B981)]),
      iconWidget: _TableGridIcon(),
      title: 'Quản lý đơn đặt',
      subtitle: 'Xem bàn, xử lý đơn hàng, thanh toán',
      onTap: () async {
        final prefs = await SharedPreferences.getInstance();
        final last = prefs.getString(AppConstants.lastOrderViewKey);
        final url = last == 'online-orders' ? AppConstants.onlineOrdersUrl : AppConstants.staffUrl;
        ref.read(webViewOverlayProvider.notifier).show(
          url: url,
          title: 'Quản lý đơn đặt',
          ignoreWebViewHistory: true,
        );
      },
    ),
    _ActionCard(
      gradient: const LinearGradient(colors: [Color(0xFF4ADE80), Color(0xFF059669)]),
      iconWidget: const Icon(Icons.bar_chart_rounded, color: Colors.white, size: 32),
      title: 'Báo cáo doanh thu',
      subtitle: 'Theo dõi số lượng và doanh thu bán hàng',
      onTap: () => ref.read(webViewOverlayProvider.notifier).show(
        url: AppConstants.reportUrl,
        title: 'Báo cáo doanh thu',
      ),
    ),
    _ActionCard(
      gradient: const LinearGradient(colors: [Color(0xFF64748B), Color(0xFF374151)]),
      iconWidget: const Icon(Icons.settings_rounded, color: Colors.white, size: 32),
      title: 'Cài đặt',
      subtitle: 'Thông tin cửa hàng, bàn, nhân viên',
      onTap: () => context.push('/settings'),
    ),
  ];

  if (spacing == 0) return cards;

  final result = <Widget>[];
  for (int i = 0; i < cards.length; i++) {
    result.add(cards[i]);
    if (i < cards.length - 1) result.add(SizedBox(height: spacing));
  }
  return result;
}

// ─── Shared sub-widgets ────────────────────────────────────────────────────

class _WelcomeText extends StatelessWidget {
  final String restaurantName;
  final bool centerAlign;

  const _WelcomeText({required this.restaurantName, this.centerAlign = false});

  @override
  Widget build(BuildContext context) {
    final align = centerAlign ? TextAlign.center : TextAlign.center;
    return Column(
      children: [
        Text('Chào mừng!',
            textAlign: align,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF1F2937))),
        const SizedBox(height: 4),
        Text(
          restaurantName.isNotEmpty ? restaurantName : 'Chưa khai báo tên nhà hàng',
          textAlign: align,
          style: TextStyle(
            fontSize: 14,
            color: restaurantName.isNotEmpty ? const Color(0xFF374151) : const Color(0xFF9CA3AF),
            fontStyle: restaurantName.isNotEmpty ? FontStyle.normal : FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

class _LogoutButton extends StatelessWidget {
  final VoidCallback onLogout;
  const _LogoutButton({required this.onLogout});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onLogout,
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFEF4444),
            side: const BorderSide(color: Color(0xFFFECACA)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: const Text('Đăng xuất', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      );
}

class _Logo extends StatelessWidget {
  final String? logoUrl;
  final double size;
  const _Logo({this.logoUrl, this.size = 80});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.28),
        child: logoUrl != null
            ? Image.network(logoUrl!, width: size, height: size, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _DefaultLogo(size: size))
            : _DefaultLogo(size: size),
      );
}

class _DefaultLogo extends StatelessWidget {
  final double size;
  const _DefaultLogo({this.size = 80});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFBBF24), Color(0xFFF97316)],
          ),
        ),
        child: Icon(Icons.bookmark_rounded, color: Colors.white, size: size * 0.5),
      );
}

class _ActionCard extends StatelessWidget {
  final LinearGradient gradient;
  final String? icon;
  final Widget? iconWidget;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionCard({
    required this.gradient,
    this.icon,
    this.iconWidget,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4)),
            ],
          ),
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(16)),
                child: Center(
                  child: iconWidget ?? Text(icon ?? '', style: const TextStyle(fontSize: 26)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1F2937))),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFFD1D5DB), size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _TableGridIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(10),
        child: GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 5,
          crossAxisSpacing: 5,
          children: [
            _dot(const Color(0xFFFDBA74)),
            _dot(Colors.white38),
            _dot(Colors.white38),
            _dot(const Color(0xFFFDBA74)),
          ],
        ),
      );

  Widget _dot(Color color) =>
      Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)));
}

class _PrinterButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wsService = ref.read(printerAppStateProvider.notifier).wsService;
    final remoteSettings = ref.watch(remoteSettingsProvider);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PrinterSettingsScreen()),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(Icons.print_rounded, size: 20, color: Color(0xFF6B7280)),
              ),
              if (remoteSettings.wsEnabled)
                Positioned(
                  top: 0,
                  right: 0,
                  child: ListenableBuilder(
                    listenable: wsService,
                    builder: (_, __) => _WsDot(status: wsService.status),
                  ),
                ),
            ],
          ),
          if (remoteSettings.wsEnabled) ...[
            const SizedBox(height: 4),
            ListenableBuilder(
              listenable: wsService,
              builder: (_, __) => _WsLabel(status: wsService.status),
            ),
          ],
        ],
      ),
    );
  }
}

class _WsDot extends StatelessWidget {
  final WsStatus status;
  const _WsDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      WsStatus.connected    => Colors.green,
      WsStatus.connecting   => Colors.blue,
      WsStatus.reconnecting => Colors.orange,
      WsStatus.disconnected => Colors.red,
    };
    return Container(
      width: 10, height: 10,
      decoration: BoxDecoration(
        color: color, shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
    );
  }
}

class _WsLabel extends StatelessWidget {
  final WsStatus status;
  const _WsLabel({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      WsStatus.connected    => ('Đã kết nối', Colors.green.shade700),
      WsStatus.connecting   => ('Đang kết nối', Colors.blue.shade700),
      WsStatus.reconnecting => ('Đang thử lại', Colors.orange.shade700),
      WsStatus.disconnected => ('Mất kết nối', Colors.red.shade700),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4)],
      ),
      child: Text(label, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

// ─── Auto-scan result bottom sheet ────────────────────────────────────────────

class _PrinterFoundSheet extends ConsumerStatefulWidget {
  final List<ScanResult> results;
  const _PrinterFoundSheet({required this.results});

  @override
  ConsumerState<_PrinterFoundSheet> createState() => _PrinterFoundSheetState();
}

class _PrinterFoundSheetState extends ConsumerState<_PrinterFoundSheet> {
  // null = chưa chọn
  ScanResult? _kitchenSelection;
  ScanResult? _billSelection;

  bool get _hasSelection => _kitchenSelection != null || _billSelection != null;

  void _toggleKitchen(ScanResult r) => setState(() {
        _kitchenSelection = _kitchenSelection?.ip == r.ip ? null : r;
      });

  void _toggleBill(ScanResult r) => setState(() {
        _billSelection = _billSelection?.ip == r.ip ? null : r;
      });

  void _confirm() {
    final current = ref.read(printerSettingsProvider);
    final updated = current.copyWith(
      kitchenEnabled: _kitchenSelection != null,
      ipAddress: _kitchenSelection?.ip ?? current.ipAddress,
      port: _kitchenSelection?.port ?? current.port,
      billEnabled: _billSelection != null,
      billIpAddress: _billSelection?.ip ?? current.billIpAddress,
      billPort: _billSelection?.port ?? current.billPort,
    );
    ref.read(printerSettingsProvider.notifier).save(updated);
    Navigator.pop(context);

    final parts = <String>[
      if (_kitchenSelection != null) 'bếp: ${_kitchenSelection!.ip}',
      if (_billSelection != null) 'lễ tân: ${_billSelection!.ip}',
    ];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã cập nhật máy in ${parts.join(' — ')}'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _skip() {
    final current = ref.read(printerSettingsProvider);
    ref.read(printerSettingsProvider.notifier).save(
          current.copyWith(kitchenEnabled: false, billEnabled: false),
        );
    SharedPreferences.getInstance().then(
      (p) => p.setBool(AppConstants.printerScanSkippedKey, true),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),

          // Header
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.print_rounded, color: Colors.green.shade700, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Tìm thấy máy in', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text(
                      'Phát hiện ${widget.results.length} thiết bị — chọn loại máy in cho từng IP',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Legend
          Row(
            children: [
              _LegendDot(color: Colors.orange.shade700, label: 'Máy in bếp'),
              const SizedBox(width: 16),
              _LegendDot(color: Colors.blue.shade700, label: 'Máy in lễ tân'),
            ],
          ),

          const SizedBox(height: 12),

          // IP rows
          ...widget.results.map((r) => _PrinterResultRow(
                result: r,
                kitchenSelected: _kitchenSelection?.ip == r.ip,
                billSelected: _billSelection?.ip == r.ip,
                onToggleKitchen: () => _toggleKitchen(r),
                onToggleBill: () => _toggleBill(r),
              )),

          const SizedBox(height: 16),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _skip,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey,
                    side: BorderSide(color: Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Bỏ qua'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _hasSelection ? _confirm : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6B3A2A),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade200,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Xác nhận', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PrinterResultRow extends StatelessWidget {
  final ScanResult result;
  final bool kitchenSelected;
  final bool billSelected;
  final VoidCallback onToggleKitchen;
  final VoidCallback onToggleBill;

  const _PrinterResultRow({
    required this.result,
    required this.kitchenSelected,
    required this.billSelected,
    required this.onToggleKitchen,
    required this.onToggleBill,
  });

  @override
  Widget build(BuildContext context) {
    final isAnySelected = kitchenSelected || billSelected;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(
          color: isAnySelected ? const Color(0xFF6B3A2A).withValues(alpha: 0.4) : Colors.grey.shade200,
          width: isAnySelected ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(14),
        color: isAnySelected ? const Color(0xFFFFF7ED) : Colors.grey.shade50,
      ),
      child: Row(
        children: [
          const Icon(Icons.router_rounded, size: 18, color: Color(0xFF6B7280)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${result.ip}:${result.port}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
          const SizedBox(width: 8),
          _ToggleChip(
            label: 'Bếp',
            icon: Icons.restaurant,
            color: Colors.orange.shade700,
            selected: kitchenSelected,
            onTap: onToggleKitchen,
          ),
          const SizedBox(width: 8),
          _ToggleChip(
            label: 'Lễ tân',
            icon: Icons.receipt_long_rounded,
            color: Colors.blue.shade700,
            selected: billSelected,
            onTap: onToggleBill,
          ),
        ],
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? color : color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selected ? color : color.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: selected ? Colors.white : color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: selected ? Colors.white : color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ],
      );
}
