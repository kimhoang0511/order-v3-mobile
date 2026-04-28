import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/bill_model.dart';
import '../models/kitchen_ticket_model.dart';
import '../services/printer_service.dart';
import '../services/websocket_service.dart';
import 'printer_settings_provider.dart';

// ─── State ────────────────────────────────────────────────────────────────────

class PrinterAppState {
  final PrintStatus printStatus;
  final String statusMessage;

  const PrinterAppState({
    this.printStatus = PrintStatus.idle,
    this.statusMessage = '',
  });
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class PrinterAppStateNotifier extends StateNotifier<PrinterAppState> {
  final Ref _ref;
  final WebSocketService _wsService = WebSocketService();
  bool _isPrinting = false;

  PrinterAppStateNotifier(this._ref) : super(const PrinterAppState()) {
    _wsService.onPrintBill = _handlePrintBill;
    _wsService.onPrintKitchen = _handlePrintKitchen;

    // Khi remoteSettings thay đổi → tự động configure WS
    _ref.listen(
      remoteSettingsProvider,
      (_, next) => _wsService.configure(next),
      fireImmediately: true,
    );
  }

  WebSocketService get wsService => _wsService;

  // ── Xử lý lệnh print_bill từ WS ─────────────────────────────────────────

  Future<void> _handlePrintBill(Map<String, dynamic> data, String? requestId) async {
    if (!_ref.read(printerSettingsProvider).billEnabled) {
      if (requestId != null) _wsService.sendAck(requestId, 'disabled');
      return;
    }
    if (_isPrinting) {
      if (requestId != null) _wsService.sendAck(requestId, 'busy');
      return;
    }
    try {
      final bill = Bill.fromJson(data);
      await _executePrintBill(bill);
      if (requestId != null) _wsService.sendAck(requestId, 'printed');
    } catch (e) {
      debugPrint('[Printer] print_bill error: $e');
      if (requestId != null) _wsService.sendAck(requestId, 'error');
    }
  }

  // ── Xử lý lệnh print_kitchen từ WS ──────────────────────────────────────

  Future<void> _handlePrintKitchen(Map<String, dynamic> data, String? requestId) async {
    if (!_ref.read(printerSettingsProvider).kitchenEnabled) {
      if (requestId != null) _wsService.sendAck(requestId, 'disabled');
      return;
    }
    if (_isPrinting) {
      if (requestId != null) _wsService.sendAck(requestId, 'busy');
      return;
    }
    try {
      final ticket = KitchenTicket.fromJson(data);
      if (_isKitchenTicketExpired(ticket)) {
        debugPrint('[Printer] Bỏ qua phiếu chế biến #${ticket.orderId} — quá 60 giây');
        if (requestId != null) _wsService.sendAck(requestId, 'printed');
        return;
      }
      await _executePrintKitchen(ticket);
      if (requestId != null) _wsService.sendAck(requestId, 'printed');
    } catch (e) {
      debugPrint('[Printer] print_kitchen error: $e');
      if (requestId != null) _wsService.sendAck(requestId, 'error');
    }
  }

  // ── Thực thi in bill (máy in lễ tân: billIpAddress:billPort) ────────────

  Future<void> _executePrintBill(Bill bill) async {
    _setStatus(PrintStatus.printing, 'Đang gửi lệnh in...');
    _isPrinting = true;
    final s = _ref.read(printerSettingsProvider);
    final billSettings = s.copyWith(ipAddress: s.billIpAddress, port: s.billPort);
    final result = await PrinterService.printViaNetwork(bill: bill, settings: billSettings);
    _isPrinting = false;
    _setStatus(result.success ? PrintStatus.success : PrintStatus.error, result.message);
    await Future.delayed(const Duration(seconds: 3));
    _setStatus(PrintStatus.idle, '');
  }

  // ── Thực thi in phiếu chế biến (máy in bếp: ipAddress:port) ─────────────

  Future<void> _executePrintKitchen(KitchenTicket ticket) async {
    _setStatus(PrintStatus.printing, 'Đang in phiếu chế biến...');
    _isPrinting = true;
    final s = _ref.read(printerSettingsProvider);
    final result = await PrinterService.printKitchenTicketViaNetwork(ticket: ticket, settings: s);
    _isPrinting = false;
    _setStatus(result.success ? PrintStatus.success : PrintStatus.error, result.message);
    await Future.delayed(const Duration(seconds: 3));
    _setStatus(PrintStatus.idle, '');
  }

  bool _isKitchenTicketExpired(KitchenTicket ticket) {
    final t = ticket.requestedAt;
    if (t == null) return false;
    return DateTime.now().difference(t).abs().inSeconds > 60;
  }

  void _setStatus(PrintStatus status, String message) {
    if (!mounted) return;
    state = PrinterAppState(printStatus: status, statusMessage: message);
  }

  @override
  void dispose() {
    _wsService.dispose();
    super.dispose();
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final printerAppStateProvider =
    StateNotifierProvider<PrinterAppStateNotifier, PrinterAppState>(
  (ref) => PrinterAppStateNotifier(ref),
);
