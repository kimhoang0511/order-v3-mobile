import 'package:flutter_riverpod/flutter_riverpod.dart';

class WebViewRequest {
  final String url;
  final String title;
  final bool ignoreWebViewHistory;
  final String? restaurantSlug;

  const WebViewRequest({
    required this.url,
    required this.title,
    this.ignoreWebViewHistory = false,
    this.restaurantSlug,
  });
}

class WebViewOverlayNotifier extends StateNotifier<WebViewRequest?> {
  WebViewOverlayNotifier() : super(null);

  void show({
    required String url,
    required String title,
    bool ignoreWebViewHistory = false,
    String? restaurantSlug,
  }) {
    state = WebViewRequest(
      url: url,
      title: title,
      ignoreWebViewHistory: ignoreWebViewHistory,
      restaurantSlug: restaurantSlug,
    );
  }

  void hide() => state = null;
}

final webViewOverlayProvider =
    StateNotifierProvider<WebViewOverlayNotifier, WebViewRequest?>(
  (ref) => WebViewOverlayNotifier(),
);
