class AppConstants {
  static const String webBaseUrl = 'https://www.kinzo.vn';
  static const String defaultApiUrl = 'https://api.kinzo.vn';
  static const String webviewRedirectUrl = '$defaultApiUrl/api/auth/webview';
  static const String loginUrl = '$webBaseUrl/login';
  static const String settingsUrl = '$webBaseUrl/settings';
  static const String menuManageUrl = '$webBaseUrl/menu-manage';
  static const String staffUrl = '$webBaseUrl/staff';
  static const String onlineOrdersUrl = '$webBaseUrl/online-orders';
  static const String reportUrl = '$webBaseUrl/report';
  static const String lastOrderViewKey = 'last_order_view';
  static const String printerScanSkippedKey = 'printer_scan_skipped';
  static String menuUrl(String restaurant, String table, {String? staffToken}) {
    final base = '$webBaseUrl/menu?restaurant=${Uri.encodeComponent(restaurant)}&table=${Uri.encodeComponent(table)}';
    return staffToken != null ? '$base&st=${Uri.encodeComponent(staffToken)}' : base;
  }
  static const String apiBasePathKey = 'api_base_url';
  static const String authTokenKey = 'owner_token';
  static const String ownerInfoKey = 'owner_info';
  static const String cachedRestaurantNameKey = 'cached_restaurant_name';
  static const String restaurantSlugKey = 'restaurant_slug';
  static const String tableNumberKey = 'table_number';
  static const String sessionTokenKey = 'session_token';
  static const String staffTokenKey = 'staff_token';
  static const String managerLinkKey = 'manager_link_token';
  static const String cartKey = 'cart_data';
  static const String privacyPolicyUrl = '$webBaseUrl/privacy-policy';
  static const String termsUrl = '$webBaseUrl/terms';
  static const String languageKey = 'app_language';

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);
}
