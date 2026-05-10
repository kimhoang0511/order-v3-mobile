import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/storage/secure_storage.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/deep_link_service.dart';
import '../../../core/services/push_notification_service.dart';
import '../../../shared/providers/auth_provider.dart';

class WebLoginScreen extends ConsumerStatefulWidget {
  const WebLoginScreen({super.key});

  @override
  ConsumerState<WebLoginScreen> createState() => _WebLoginScreenState();
}

class _WebLoginScreenState extends ConsumerState<WebLoginScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _tokenCaptured = false;
  bool _localStorageCleared = false;
  Timer? _pollTimer;
  StreamSubscription<Uri>? _deepLinkSub;

  @override
  void initState() {
    super.initState();
    _initWebView();
    // On iOS, Google OAuth completes in Safari and returns via kinzoapp:// deep link.
    if (Platform.isIOS) {
      _deepLinkSub = DeepLinkService.stream.listen((uri) {
        if (uri.scheme == 'kinzoapp' && uri.host == 'auth') {
          final token = uri.queryParameters['token'] ?? '';
          final params = uri.queryParameters;
          if (token.isNotEmpty) _handleDeepLinkAuth(params);
        }
      });
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _deepLinkSub?.cancel();
    super.dispose();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        Platform.isIOS
            ? 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1'
            : 'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
      )
      ..addJavaScriptChannel(
        'FlutterAuth',
        onMessageReceived: (msg) => _handleAuthMessage(msg.message),
      )
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          // On iOS, intercept Google OAuth URL and open in external browser.
          // Adds webview=true so backend redirects back via kinzoapp:// deep link.
          if (Platform.isIOS && request.url.contains('/api/auth/google/login')) {
            final uri = Uri.parse(request.url);
            final newUri = uri.replace(
              queryParameters: {...uri.queryParameters, 'webview': 'true'},
            );
            launchUrl(newUri, mode: LaunchMode.externalApplication);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        onPageStarted: (_) {
          setState(() => _isLoading = true);
          _pollTimer?.cancel();
        },
        onPageFinished: (url) async {
          setState(() => _isLoading = false);
          // Chỉ xóa localStorage 1 lần duy nhất khi mới vào màn hình login
          if (!_localStorageCleared) {
            _localStorageCleared = true;
            await _controller.runJavaScript(
              "localStorage.clear(); sessionStorage.clear();",
            );
          }

          // JS channel: intercept localStorage.setItem
          await _controller.runJavaScript('''
            (function() {
              if (window.__flutterAuthInjected) return;
              window.__flutterAuthInjected = true;
              var _setItem = localStorage.setItem.bind(localStorage);
              localStorage.setItem = function(key, value) {
                _setItem(key, value);
                if (key === 'owner_token') {
                  var owner = localStorage.getItem('owner_info') || '';
                  FlutterAuth.postMessage(value + '|||' + owner);
                }
              };
            })();
          ''');

          // Dart-side polling: chủ động đọc localStorage mỗi 1 giây
          _startPolling();
        },
      ));

    _loadLoginUrl();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_tokenCaptured) {
        _pollTimer?.cancel();
        return;
      }
      try {
        final result = await _controller.runJavaScriptReturningResult(
          "localStorage.getItem('owner_token') || ''",
        );
        final token = result.toString().replaceAll('"', '').trim();
        if (token.isNotEmpty && token != 'null') {
          _pollTimer?.cancel();
          final ownerResult = await _controller.runJavaScriptReturningResult(
            "localStorage.getItem('owner_info') || ''",
          );
          final ownerRaw = ownerResult.toString().replaceAll(r'\"', '"');
          await _handleAuthMessage('$token|||$ownerRaw');
        }
      } catch (_) {}
    });
  }

  Future<void> _loadLoginUrl() async {
    // Clear WebView cookies so the previous Google OAuth session is invalidated,
    // forcing the user to choose an account instead of silently reusing account A.
    await WebViewCookieManager().clearCookies();

    final uri = Uri.parse(AppConstants.loginUrl);
    await _controller.loadRequest(
      uri.replace(queryParameters: {...uri.queryParameters, 'webview': 'true'}),
    );
  }

  Future<void> _handleDeepLinkAuth(Map<String, String> params) async {
    final token = params['token'] ?? '';
    if (token.isEmpty || _tokenCaptured) return;
    _tokenCaptured = true;
    _pollTimer?.cancel();

    await AppSecureStorage.write(AppConstants.authTokenKey, token);

    final slug = params['restaurant_slug'] ?? '';
    final name = params['restaurant_name'] ?? '';
    final username = params['username'] ?? '';
    final ownerId = int.tryParse(params['owner_id'] ?? '') ?? 0;
    if (slug.isNotEmpty) {
      await AppSecureStorage.write(AppConstants.ownerInfoKey,
          '{"id":$ownerId,"username":"$username","restaurant_slug":"$slug","restaurant_name":"$name"}');
    }

    await ref.read(authProvider.notifier).checkAuth();
    PushNotificationService.registerForOwner(token).ignore();
    if (mounted) context.go('/home');
  }

  Future<void> _handleAuthMessage(String message) async {
    if (_tokenCaptured) return;

    try {
      final parts = message.split('|||');
      final token = parts[0].replaceAll('"', '').trim();
      if (token.isEmpty || token == 'null') return;

      _tokenCaptured = true;
      _pollTimer?.cancel();

      final ownerRaw = parts.length > 1 ? parts[1].trim() : null;

      await AppSecureStorage.write(AppConstants.authTokenKey, token);
      if (ownerRaw != null && ownerRaw.isNotEmpty && ownerRaw != 'null' && ownerRaw != '""') {
        final cleaned = ownerRaw.startsWith('"') && ownerRaw.endsWith('"')
            ? ownerRaw.substring(1, ownerRaw.length - 1)
            : ownerRaw;
        await AppSecureStorage.write(AppConstants.ownerInfoKey, cleaned);
      }

      await ref.read(authProvider.notifier).checkAuth();

      PushNotificationService.registerForOwner(token).ignore();

      if (mounted) context.go('/home');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Đăng nhập'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _tokenCaptured = false;
              _localStorageCleared = false;
              _pollTimer?.cancel();
              _loadLoginUrl();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
