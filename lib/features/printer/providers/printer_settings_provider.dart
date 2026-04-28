import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/printer_settings.dart';
import '../../../core/storage/secure_storage.dart';
import '../models/remote_settings.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/api/api_client.dart';

// ─── Remote settings ──────────────────────────────────────────────────────────

class RemoteSettingsNotifier extends StateNotifier<RemoteSettings> {
  RemoteSettingsNotifier() : super(const RemoteSettings()) {
    _load();
  }

  static const _keyUrl = 'printer_serverBaseUrl';
  static const _keySlug = 'printer_restaurantSlug';
  static const _keyWs = 'printer_wsEnabled';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();

    // Ưu tiên slug từ auth cache (owner_info) — luôn đồng bộ với tài khoản đăng nhập
    String slug = prefs.getString(_keySlug) ?? '';
    final ownerRaw = await AppSecureStorage.read(AppConstants.ownerInfoKey);
    if (ownerRaw != null) {
      try {
        final map = jsonDecode(ownerRaw) as Map<String, dynamic>;
        final authSlug = map['restaurant_slug'] as String? ?? '';
        if (authSlug.isNotEmpty) slug = authSlug;
      } catch (_) {}
    }

    state = RemoteSettings(
      serverBaseUrl: prefs.getString(_keyUrl) ?? 'https://api.kinzo.vn',
      restaurantSlug: slug,
      wsEnabled: prefs.getBool(_keyWs) ?? false,
    );
  }

  void save(RemoteSettings settings) {
    state = settings;
    _persist(settings);
  }

  Future<void> _persist(RemoteSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUrl, s.serverBaseUrl);
    await prefs.setString(_keySlug, s.restaurantSlug);
    await prefs.setBool(_keyWs, s.wsEnabled);
  }
}

final remoteSettingsProvider =
    StateNotifierProvider<RemoteSettingsNotifier, RemoteSettings>(
  (_) => RemoteSettingsNotifier(),
);

// ─── Printer settings ─────────────────────────────────────────────────────────

class PrinterSettingsNotifier extends StateNotifier<PrinterSettings> {
  final Ref _ref;

  PrinterSettingsNotifier(this._ref) : super(const PrinterSettings()) {
    _load().then((_) => syncFromServer());
  }

  static const _keyType = 'printer_connectionType';
  static const _keyKitchenEnabled = 'printer_kitchenEnabled';
  static const _keyIp = 'printer_ipAddress';
  static const _keyPort = 'printer_port';
  static const _keyBillEnabled = 'printer_billEnabled';
  static const _keyBillIp = 'printer_billIpAddress';
  static const _keyBillPort = 'printer_billPort';
  static const _keyPaper = 'printer_paperWidth';
  static const _keyUnicode = 'printer_unicodeVietnamese';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    const d = PrinterSettings();
    state = PrinterSettings(
      connectionType:
          PrinterConnectionType.values[prefs.getInt(_keyType) ?? d.connectionType.index],
      kitchenEnabled: prefs.getBool(_keyKitchenEnabled) ?? d.kitchenEnabled,
      ipAddress: prefs.getString(_keyIp) ?? d.ipAddress,
      port: prefs.getInt(_keyPort) ?? d.port,
      billEnabled: prefs.getBool(_keyBillEnabled) ?? d.billEnabled,
      billIpAddress: prefs.getString(_keyBillIp) ?? d.billIpAddress,
      billPort: prefs.getInt(_keyBillPort) ?? d.billPort,
      paperWidth: prefs.getInt(_keyPaper) ?? d.paperWidth,
      unicodeVietnamese: prefs.getBool(_keyUnicode) ?? d.unicodeVietnamese,
    );
  }

  Future<void> syncFromServer() async {
    try {
      final ownerToken = await AppSecureStorage.read(AppConstants.authTokenKey);
      final staffToken = await AppSecureStorage.read(AppConstants.staffTokenKey);

      // Không có token nào — bỏ qua
      if (ownerToken == null && (staffToken == null || staffToken.isEmpty)) return;

      final api = _ref.read(apiClientProvider);
      final response = ownerToken != null
          ? await api.get('/api/manage/printer-settings')
          : await api.get('/api/staff-view/printer-settings', queryParameters: {'t': staffToken});

      final data = response.data as Map<String, dynamic>?;
      if (data == null) return;

      final kitchen = data['kitchen'] as Map<String, dynamic>? ?? {};
      final bill    = data['bill']    as Map<String, dynamic>? ?? {};
      final connectionType = (kitchen['connection_type'] as String?) == 'bluetooth'
          ? PrinterConnectionType.bluetooth
          : PrinterConnectionType.network;

      save(PrinterSettings(
        connectionType:    connectionType,
        kitchenEnabled:    kitchen['enabled']        as bool?   ?? false,
        ipAddress:         kitchen['ip_address']     as String? ?? '',
        port:              kitchen['port']            as int?    ?? 9100,
        billEnabled:       bill['enabled']            as bool?   ?? false,
        billIpAddress:     bill['ip_address']         as String? ?? '',
        billPort:          bill['port']               as int?    ?? 9100,
        paperWidth:        data['paper_width']        as int?    ?? 80,
        unicodeVietnamese: data['unicode_vietnamese'] as bool?   ?? false,
      ));
    } catch (_) {
      // Không có mạng hoặc token hết hạn — giữ nguyên setting local
    }
  }

  void save(PrinterSettings settings) {
    state = settings;
    _persist(settings);
  }

  Future<void> _persist(PrinterSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyType, s.connectionType.index);
    await prefs.setBool(_keyKitchenEnabled, s.kitchenEnabled);
    await prefs.setString(_keyIp, s.ipAddress);
    await prefs.setInt(_keyPort, s.port);
    await prefs.setBool(_keyBillEnabled, s.billEnabled);
    await prefs.setString(_keyBillIp, s.billIpAddress);
    await prefs.setInt(_keyBillPort, s.billPort);
    await prefs.setInt(_keyPaper, s.paperWidth);
    await prefs.setBool(_keyUnicode, s.unicodeVietnamese);
  }
}

final printerSettingsProvider =
    StateNotifierProvider<PrinterSettingsNotifier, PrinterSettings>(
  (ref) => PrinterSettingsNotifier(ref),
);
