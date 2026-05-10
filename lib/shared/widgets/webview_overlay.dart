import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../../core/storage/secure_storage.dart';
import '../../core/router/app_router.dart';
import '../../core/services/push_notification_service.dart';
import '../../features/printer/models/bill_model.dart';
import '../../features/printer/providers/printer_settings_provider.dart';
import '../../features/printer/services/printer_service.dart';
import '../providers/auth_provider.dart';
import '../providers/webview_overlay_provider.dart';

class WebViewOverlay extends ConsumerStatefulWidget {
  const WebViewOverlay({super.key});

  @override
  ConsumerState<WebViewOverlay> createState() => _WebViewOverlayState();
}

class _WebViewOverlayState extends ConsumerState<WebViewOverlay>
    with WidgetsBindingObserver {
  late final WebViewController _controller;
  bool _isLoading = false;
  bool _showControls = false;
  Timer? _hideTimer;
  String _cachedToken = '';
  String _cachedSlug = '';
  String _cachedStaffToken = '';
  WebViewRequest? _lastRequest;
  int _downloadCount = 0;
  Timer? _downloadSummaryTimer;
  StreamSubscription<String>? _notifSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initController();
    _loadCachedAuth();
    _notifSub = PushNotificationService.urlStream.listen(_navigateTo);
    // Consume any URL saved before this widget was mounted (killed-state tap).
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumePending());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _downloadSummaryTimer?.cancel();
    _notifSub?.cancel();
    super.dispose();
  }

  // Called when app comes back to foreground — picks up any pending nav URL
  // from a background notification tap.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _consumePending();
  }

  void _navigateTo(String url) {
    ref.read(webViewOverlayProvider.notifier).show(
      url: url,
      title: 'Thông báo',
      ignoreWebViewHistory: true,
    );
  }

  Future<void> _consumePending() async {
    var url = await PushNotificationService.consumePendingNavUrl();
    url ??= await PushNotificationService.consumeNativeTapUrl();
    if (url != null && mounted) _navigateTo(url);
  }

  Future<void> _loadCachedAuth() async {
    _cachedToken = await AppSecureStorage.read(AppConstants.authTokenKey) ?? '';
    _cachedStaffToken = await AppSecureStorage.read(AppConstants.staffTokenKey) ?? '';
    final ownerRaw = await AppSecureStorage.read(AppConstants.ownerInfoKey);
    if (ownerRaw != null) {
      try {
        final map = jsonDecode(ownerRaw) as Map<String, dynamic>;
        _cachedSlug = map['restaurant_slug'] as String? ?? '';
      } catch (_) {}
    }
  }

  void _showControlsTemporarily() {
    if (!mounted) return;
    setState(() => _showControls = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  bool _isLandingPageUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final host = uri.host;
    if (!host.contains('kinzo.vn')) return false;
    final path = uri.path;
    return path == '' || path == '/';
  }

  bool _isRestaurantHomeUrl(String url) {
    final slug = _lastRequest?.restaurantSlug?.isNotEmpty == true
        ? _lastRequest!.restaurantSlug!
        : _cachedSlug.isNotEmpty
            ? _cachedSlug
            : ref.read(authProvider).user?.restaurantSlug ?? '';
    if (slug.isEmpty) return false;
    final home = '${AppConstants.webBaseUrl}/$slug';
    return url == home || url == '$home/' || url.startsWith('$home?');
  }

  Uri _withWebviewParam(String url, {String? token}) {
    final uri = Uri.parse(url);
    final params = {...uri.queryParameters, 'webview': 'true'};
    if (token != null && token.isNotEmpty) params['owner_token'] = token;
    return uri.replace(queryParameters: params);
  }

  Future<void> _loadWithToken(String url) async {
    final token = await AppSecureStorage.read(AppConstants.authTokenKey) ?? '';
    if (token.isNotEmpty) _cachedToken = token;

    if (token.isEmpty) {
      await _controller.loadRequest(_withWebviewParam(url));
      return;
    }

    final uri = Uri.parse(url);
    final path = uri.path + (uri.hasQuery ? '?${uri.query}' : '');
    final redirectUri = Uri.parse(AppConstants.webviewRedirectUrl).replace(
      queryParameters: {'token': token, 'path': path},
    );
    await _controller.loadRequest(redirectUri);
  }

  void _hide() => ref.read(webViewOverlayProvider.notifier).hide();

  Future<void> _goHome() async {
    final ownerToken = await AppSecureStorage.read(AppConstants.authTokenKey) ?? '';
    final staffToken = await AppSecureStorage.read(AppConstants.staffTokenKey) ?? '';
    _hide();
    if (!mounted) return;
    if (ownerToken.isNotEmpty) {
      // Kiểm tra lại trạng thái tài khoản — nếu đã xóa (is_active=false) backend trả 401
      await ref.read(authProvider.notifier).refresh();
      if (!mounted) return;
      if (!ref.read(authProvider).isAuthenticated) {
        ref.read(routerProvider).go('/login-choice');
        return;
      }
      ref.read(routerProvider).go('/home');
    } else if (staffToken.isNotEmpty) {
      ref.read(routerProvider).go('/staff-view?t=${Uri.encodeComponent(staffToken)}');
    } else {
      ref.read(routerProvider).go('/login-choice');
    }
  }

  Future<void> _clearWebViewAuth() async {
    _cachedToken = '';
    _cachedSlug = '';
    try {
      await WebViewCookieManager().clearCookies();
    } catch (_) {}
    try {
      await _controller.runJavaScript(
        "localStorage.removeItem('owner_token'); localStorage.removeItem('owner_info');",
      );
    } catch (_) {}
  }

  Future<void> _handleBack() async {
    final ignoreHistory = _lastRequest?.ignoreWebViewHistory ?? false;
    if (!ignoreHistory && await _controller.canGoBack()) {
      await _controller.goBack();
    } else {
      await _goHome();
    }
  }

  void _initController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        Platform.isIOS
            ? 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1'
            : 'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _isLoading = true);
        },
        onPageFinished: (url) async {
          if (mounted) setState(() => _isLoading = false);
          if (!Platform.isIOS) {
            final token = await AppSecureStorage.read(AppConstants.authTokenKey) ?? '';
            if (token.isNotEmpty) {
              _cachedToken = token;
              try {
                await _controller.runJavaScript(
                  "localStorage.setItem('owner_token', '${token}');",
                );
              } catch (_) {}
            }
          }
          try {
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
          } catch (_) {}
          try {
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
          } catch (_) {}
        },
        onUrlChange: (change) async {
          final url = change.url ?? '';
          final uri = Uri.tryParse(url);
          if (uri == null) return;

          // Detect account deletion — web page gọi history.replaceState với ?status=deleted
          if (uri.path == '/account/delete' && uri.queryParameters['status'] == 'deleted') {
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (!mounted) return;
              await ref.read(authProvider.notifier).logout();
              await _clearWebViewAuth();
              if (mounted) {
                _hide();
                ref.read(routerProvider).go('/login-choice');
              }
            });
            return;
          }

          if (_isRestaurantHomeUrl(url)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _hide();
                ref.read(routerProvider).go('/home');
              }
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
          // Block landing page — redirect đến login với webview=true
          if (_isLandingPageUrl(request.url)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _loadWithToken('${AppConstants.webBaseUrl}/login?webview=true');
              }
            });
            return NavigationDecision.prevent;
          }
          if (_isRestaurantHomeUrl(request.url)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _hide();
                ref.read(routerProvider).go('/home');
              }
            });
            return NavigationDecision.prevent;
          }
          final uri = Uri.tryParse(request.url);
          if (uri != null && uri.path == '/register') {
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
      ..addJavaScriptChannel(
        'FlutterAuth',
        onMessageReceived: (msg) async {
          if (msg.message == 'account_deleted') {
            await ref.read(authProvider.notifier).logout();
            await _clearWebViewAuth();
            if (mounted) {
              _hide();
              ref.read(routerProvider).go('/login-choice');
            }
          }
        },
      )
      ..loadRequest(Uri.parse('about:blank'));

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

  Future<List<String>> _handleAndroidFileSelector(FileSelectorParams params) async {
    final picker = ImagePicker();
    XFile? file;
    if (params.isCaptureEnabled) {
      file = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    } else {
      if (!mounted) return [];
      final source = await _showImageSourceDialog();
      if (source == null) return [];
      file = await picker.pickImage(source: source, imageQuality: 85);
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
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: const Color(0xFFFBBF24), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.camera_alt_rounded, color: Colors.white),
              ),
              title: const Text('Chụp ảnh trực tiếp',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Mở camera và chụp ngay bây giờ'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: Colors.grey.shade200, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.photo_library_rounded, color: Colors.grey),
              ),
              title: const Text('Chọn từ thư viện',
                  style: TextStyle(fontWeight: FontWeight.w600)),
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
    ref.listen<WebViewRequest?>(webViewOverlayProvider, (prev, next) {
      if (next != null) {
        _lastRequest = next;
        _loadWithToken(next.url);
      }
    });

    // Xóa WebView auth khi user đăng xuất
    ref.listen<AuthState>(authProvider, (prev, next) {
      if (prev?.isAuthenticated == true && !next.isAuthenticated) {
        _clearWebViewAuth();
      }
    });

    final request = ref.watch(webViewOverlayProvider);

    return Offstage(
      offstage: request == null,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          await _handleBack();
        },
        child: Material(
          color: Colors.white,
          child: SafeArea(
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_isLoading)
                  const Center(child: CircularProgressIndicator()),
                Positioned(
                  bottom: 20,
                  left: 16,
                  child: AnimatedOpacity(
                    opacity: _showControls ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    child: IgnorePointer(
                      ignoring: !_showControls,
                      child: _OverlayButton(
                        icon: Icons.home_rounded,
                        onTap: _goHome,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 20,
                  right: 16,
                  child: AnimatedOpacity(
                    opacity: _showControls ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    child: IgnorePointer(
                      ignoring: !_showControls,
                      child: _OverlayButton(
                        icon: Icons.refresh_rounded,
                        onTap: () => _controller.reload(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OverlayButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _OverlayButton({required this.icon, required this.onTap});

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
