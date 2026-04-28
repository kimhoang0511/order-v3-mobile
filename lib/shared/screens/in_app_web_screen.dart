import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../../core/storage/secure_storage.dart';
import '../../features/printer/models/bill_model.dart';
import '../../features/printer/providers/printer_settings_provider.dart';
import '../../features/printer/services/printer_service.dart';
import '../providers/auth_provider.dart';

class InAppWebScreen extends ConsumerStatefulWidget {
  final String title;
  final String url;
  /// Khi webview navigate về /{restaurantSlug} thì tự đóng về home
  final String? restaurantSlug;
  /// Nếu true, nút back luôn pop về màn hình trước (không navigate trong webview history)
  final bool ignoreWebViewHistory;

  const InAppWebScreen({
    super.key,
    required this.title,
    required this.url,
    this.restaurantSlug,
    this.ignoreWebViewHistory = false,
  });

  @override
  ConsumerState<InAppWebScreen> createState() => _InAppWebScreenState();
}

class _InAppWebScreenState extends ConsumerState<InAppWebScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _showControls = false;
  Timer? _hideTimer;
  int _downloadCount = 0;
  Timer? _downloadSummaryTimer;

  @override
  void initState() {
    super.initState();
    _initWebView();
    _loadTokenAndInject();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _downloadSummaryTimer?.cancel();
    super.dispose();
  }

  void _showControlsTemporarily() {
    if (!mounted) return;
    setState(() => _showControls = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  // Trả về true nếu URL là trang home của nhà hàng → cần đóng webview về HomeScreen
  bool _isRestaurantHomeUrl(String url) {
    final slug = widget.restaurantSlug?.isNotEmpty == true
        ? widget.restaurantSlug!
        : _cachedSlug.isNotEmpty
            ? _cachedSlug
            : ref.read(authProvider).user?.restaurantSlug ?? '';
    if (slug.isEmpty) return false;
    final home = '${AppConstants.webBaseUrl}/$slug';
    return url == home || url == '$home/' || url.startsWith('$home?');
  }

  Future<void> _handleBack() async {
    if (!widget.ignoreWebViewHistory && await _controller.canGoBack()) {
      await _controller.goBack();
    } else {
      if (mounted) context.go('/home');
    }
  }

  String _cachedToken = '';
  String _cachedSlug = '';

  Future<void> _loadTokenAndInject() async {
    _cachedToken = await AppSecureStorage.read(AppConstants.authTokenKey) ?? '';
    final ownerRaw = await AppSecureStorage.read(AppConstants.ownerInfoKey);
    if (ownerRaw != null) {
      try {
        final map = jsonDecode(ownerRaw) as Map<String, dynamic>;
        _cachedSlug = map['restaurant_slug'] as String? ?? '';
      } catch (_) {}
    }
  }

  Uri _urlWithWebviewParam(String url) {
    final uri = Uri.parse(url);
    return uri.replace(queryParameters: {...uri.queryParameters, 'webview': 'true'});
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 10; Mobile) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/124.0.0.0 Mobile Safari/537.36',
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _isLoading = true),
        onPageFinished: (_) async {
          setState(() => _isLoading = false);
          if (_cachedToken.isNotEmpty) {
            await _controller.runJavaScript(
              "localStorage.setItem('owner_token', '$_cachedToken');",
            );
          }
          await _controller.runJavaScript('''
            (function(){
              var t;
              function notify(){
                if(t) return;
                FlutterControls.postMessage('s');
                t = setTimeout(function(){ t=null; }, 500);
              }
              window.addEventListener('touchstart', notify, {passive:true});
              window.addEventListener('scroll', notify, {passive:true});
            })();
          ''');
          await _controller.runJavaScript('''
            (function(){
              if(typeof FlutterDownload==='undefined') return;
              var _orig=HTMLAnchorElement.prototype.click;
              HTMLAnchorElement.prototype.click=function(){
                if(this.hasAttribute('download')&&this.href&&this.href.indexOf('data:')===0){
                  FlutterDownload.postMessage(JSON.stringify({filename:this.getAttribute('download')||'download',dataUrl:this.href}));
                  return;
                }
                return _orig.call(this);
              };
              document.addEventListener('click',function(e){
                var a=e.target&&e.target.closest?e.target.closest('a[download]'):null;
                if(!a)return;
                var href=a.href||'';
                if(href.indexOf('data:')===0){
                  e.preventDefault();e.stopPropagation();
                  FlutterDownload.postMessage(JSON.stringify({filename:a.getAttribute('download')||'download',dataUrl:href}));
                }
              },true);
            })();
          ''');
        },
        onUrlChange: (change) async {
          final url = change.url ?? '';
          final uri = Uri.tryParse(url);
          if (uri == null) return;
          if (_isRestaurantHomeUrl(url)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) context.go('/home');
            });
            return;
          }
          final path = uri.path;
          if (path == '/staff') {
            final p = await SharedPreferences.getInstance();
            await p.setString(AppConstants.lastOrderViewKey, 'staff');
          } else if (path == '/online-orders') {
            final p = await SharedPreferences.getInstance();
            await p.setString(AppConstants.lastOrderViewKey, 'online-orders');
          }
        },
        onNavigationRequest: (request) {
          if (_isRestaurantHomeUrl(request.url)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) context.go('/home');
            });
            return NavigationDecision.prevent;
          }
          final uri = Uri.tryParse(request.url);
          if (uri != null && uri.path == '/register') {
            launchUrl(
              Uri.parse('https://www.kinzo.vn/register'),
              mode: LaunchMode.externalApplication,
            );
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..addJavaScriptChannel(
        'FlutterPrinter',
        onMessageReceived: (msg) => _handlePrintBill(msg.message),
      )
      ..addJavaScriptChannel(
        'FlutterControls',
        onMessageReceived: (_) => _showControlsTemporarily(),
      )
      ..addJavaScriptChannel(
        'FlutterDownload',
        onMessageReceived: (msg) => _handleFileDownload(msg.message),
      )
      ..loadRequest(_urlWithWebviewParam(widget.url));

    if (Platform.isAndroid) {
      final androidController = _controller.platform as AndroidWebViewController;
      AndroidWebViewController.enableDebugging(true);
      androidController.setOnShowFileSelector(_handleAndroidFileSelector);
    }
  }

  Future<void> _handlePrintBill(String message) async {
    try {
      final data = jsonDecode(message) as Map<String, dynamic>;
      final bill = Bill.fromJson(data);
      final settings = ref.read(printerSettingsProvider);
      if (!settings.billEnabled) return;
      final billSettings = settings.copyWith(
        ipAddress: settings.billIpAddress,
        port: settings.billPort,
      );
      final result = await PrinterService.printViaNetwork(bill: bill, settings: billSettings);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result.success ? 'Đã in bill thành công' : 'In thất bại: ${result.message}'),
          backgroundColor: result.success ? Colors.green : Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      debugPrint('[FlutterPrinter] Error: $e');
    }
  }

  static const _storageChannel = MethodChannel('com.kinzo/storage');

  Future<void> _handleFileDownload(String message) async {
    try {
      final data = jsonDecode(message) as Map<String, dynamic>;
      final filename = (data['filename'] as String?)
              ?.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_') ??
          'download';
      final dataUrl = data['dataUrl'] as String? ?? '';
      if (dataUrl.isEmpty) return;

      final commaIdx = dataUrl.indexOf(',');
      if (commaIdx < 0) return;
      final bytes = base64Decode(dataUrl.substring(commaIdx + 1));

      if (Platform.isAndroid) {
        final mimeType = dataUrl.startsWith('data:image/png') ? 'image/png' : 'image/jpeg';
        await _storageChannel.invokeMethod('saveToDownloads', {
          'filename': filename,
          'bytes': bytes,
          'subDir': 'KinzoQR',
          'mimeType': mimeType,
        });
      } else {
        // iOS: lưu vào thư viện ảnh (Photos app) qua platform channel
        await _storageChannel.invokeMethod('saveToDownloads', {
          'filename': filename,
          'bytes': bytes,
        });
      }

      _downloadCount++;
      _downloadSummaryTimer?.cancel();
      _downloadSummaryTimer = Timer(const Duration(milliseconds: 1500), () {
        if (!mounted || _downloadCount == 0) return;
        final count = _downloadCount;
        _downloadCount = 0;
        final location = Platform.isAndroid ? 'Downloads/KinzoQR' : 'thư viện ảnh';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Đã lưu $count ảnh QR vào $location'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ));
      });
    } catch (e) {
      debugPrint('[FlutterDownload] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Lưu file thất bại'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  // Android: xử lý <input type="file"> trong WebView
  Future<List<String>> _handleAndroidFileSelector(FileSelectorParams params) async {
    final picker = ImagePicker();
    XFile? file;

    // capture="environment" → mở camera trực tiếp
    if (params.isCaptureEnabled) {
      file = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
    } else {
      // Hỏi user muốn chụp ảnh hay chọn từ thư viện
      if (!mounted) return [];
      final source = await _showImageSourceDialog();
      if (source == null) return [];
      file = await picker.pickImage(
        source: source,
        imageQuality: 85,
      );
    }

    if (file == null) return [];
    return [file.path];
  }

  Future<ImageSource?> _showImageSourceDialog() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: const Color(0xFFFBBF24), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.camera_alt_rounded, color: Colors.white),
              ),
              title: const Text('Chụp ảnh trực tiếp', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Mở camera và chụp ngay bây giờ'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.photo_library_rounded, color: Colors.grey),
              ),
              title: const Text('Chọn từ thư viện', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Tải lên ảnh menu đã có sẵn'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // Webview bên dưới status bar
            WebViewWidget(controller: _controller),

            // Loading indicator
            if (_isLoading)
              const Center(child: CircularProgressIndicator()),

            // Nút home góc dưới trái
            Positioned(
              bottom: 20,
              left: 16,
              child: AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: _BarButton(
                    icon: Icons.home_rounded,
                    onTap: () => context.go('/home'),
                  ),
                ),
              ),
            ),
            // Nút reload góc dưới phải
            Positioned(
              bottom: 20,
              right: 16,
              child: AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: _BarButton(
                    icon: Icons.refresh_rounded,
                    onTap: () => _controller.reload(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    )); // PopScope + Scaffold
  }
}

class _BarButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _BarButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.45),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      );
}
