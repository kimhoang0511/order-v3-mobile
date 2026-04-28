import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/webview_overlay_provider.dart';
import '../../printer/providers/printer_settings_provider.dart';

class QrScannerScreen extends ConsumerStatefulWidget {
  final String? mode;
  final String? staffToken;

  const QrScannerScreen({super.key, this.mode, this.staffToken});

  @override
  ConsumerState<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends ConsumerState<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;

    setState(() => _isProcessing = true);
    await _controller.stop();

    final url = barcode!.rawValue!;
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _showError('QR code không hợp lệ');
      return;
    }

    // Detect staff-view URL: /staff-view?t=xxx
    if (uri.path.contains('staff-view')) {
      final token = uri.queryParameters['t'];
      if (token == null || token.isEmpty) {
        _showError('QR code nhân viên không hợp lệ');
        return;
      }
      await _handleStaffToken(token);
      return;
    }

    // Regular table QR
    final restaurant = uri.queryParameters['restaurant'];
    final table = uri.queryParameters['table'];

    if (restaurant == null || table == null) {
      _showError('QR code không chứa thông tin bàn hợp lệ');
      return;
    }

    if (widget.mode == 'quick-order') {
      if (mounted) {
        ref.read(webViewOverlayProvider.notifier).show(
          url: url,
          title: 'Đặt nhanh - Bàn $table',
        );
        Navigator.pop(context);
      }
      return;
    }

    if (widget.mode == 'find-table' && widget.staffToken != null) {
      final staffUrl =
          '${AppConstants.webBaseUrl}/staff-view?t=${Uri.encodeComponent(widget.staffToken!)}'
          '&mode=manage&tab=tables&tableFilter=${Uri.encodeComponent(table)}';
      if (mounted) {
        ref.read(webViewOverlayProvider.notifier).show(
          url: staffUrl,
          title: 'Bàn $table',
          ignoreWebViewHistory: true,
        );
        Navigator.pop(context);
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.restaurantSlugKey, restaurant);
    await prefs.setString(AppConstants.tableNumberKey, table);

    if (mounted) {
      context.go('/menu?restaurant=$restaurant&table=$table');
    }
  }

  Future<void> _handleStaffToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final apiBase = prefs.getString(AppConstants.apiBasePathKey) ?? AppConstants.defaultApiUrl;
      final response = await http.get(
        Uri.parse('$apiBase/api/staff-view/info?t=${Uri.encodeComponent(token)}'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['detail'] != null) {
          _showError('Token nhân viên không hợp lệ');
          return;
        }
        await AppSecureStorage.write(AppConstants.staffTokenKey, token);
        ref.read(printerSettingsProvider.notifier).syncFromServer();
        if (mounted) {
          context.go('/staff-view?t=${Uri.encodeComponent(token)}');
        }
      } else if (response.statusCode == 401 || response.statusCode == 403 || response.statusCode == 404) {
        _showError('Token nhân viên không hợp lệ hoặc đã hết hạn');
      } else {
        _showError('Không thể xác thực token nhân viên');
      }
    } catch (e) {
      _showError('Lỗi kết nối, vui lòng thử lại');
    }
  }

  void _showError(String message) {
    setState(() => _isProcessing = false);
    _controller.start();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Quét QR'),
          actions: [
            IconButton(
              icon: ValueListenableBuilder(
                valueListenable: _controller,
                builder: (_, state, __) => Icon(
                  state.torchState == TorchState.on ? Icons.flash_on : Icons.flash_off,
                ),
              ),
              onPressed: _controller.toggleTorch,
            ),
          ],
        ),
        body: Stack(
          children: [
            MobileScanner(controller: _controller, onDetect: _onDetect),
            Center(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.primary, width: 3),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            Positioned(
              bottom: 48,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  if (_isProcessing)
                    const CircularProgressIndicator(color: AppColors.primary)
                  else
                    const Text(
                      'Đặt QR code vào khung để quét',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
}
