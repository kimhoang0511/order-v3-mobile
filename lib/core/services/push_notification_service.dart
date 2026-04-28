import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../constants/app_constants.dart';
import '../storage/secure_storage.dart';
import 'notification_sound_service.dart';

// Background message handler — must be top-level function.
@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  // OS displays the notification automatically — no work needed here.
}

class PushNotificationService {
  static final _localNotifications = FlutterLocalNotificationsPlugin();

  // Bump suffix (v3, v4...) whenever sound files change — old channels cannot be updated.
  // IMPORTANT: never put current channels in _legacyChannelIds; Android does not reliably
  // reset sound when a channel is deleted and recreated with the same ID.
  static const _channels = [
    AndroidNotificationChannel('kinzo_new_order_v3',        'Đặt món mới',        description: 'Thông báo bàn đặt món',                  importance: Importance.high, playSound: true, sound: RawResourceAndroidNotificationSound('kinzo_new_order')),
    AndroidNotificationChannel('kinzo_bill_request_v3',     'Yêu cầu tính tiền',  description: 'Thông báo yêu cầu tính tiền',            importance: Importance.high, playSound: true, sound: RawResourceAndroidNotificationSound('kinzo_bill_request')),
    AndroidNotificationChannel('kinzo_support_request_v3',  'Gọi nhân viên',      description: 'Thông báo bàn gọi nhân viên',            importance: Importance.high, playSound: true, sound: RawResourceAndroidNotificationSound('kinzo_support_request')),
    AndroidNotificationChannel('kinzo_support_accepted_v3', 'Tiếp nhận yêu cầu', description: 'Thông báo đã tiếp nhận yêu cầu hỗ trợ', importance: Importance.high, playSound: true, sound: RawResourceAndroidNotificationSound('kinzo_support_accepted')),
    AndroidNotificationChannel('kinzo_order_accepted_v3',   'Tiếp nhận đơn',      description: 'Thông báo đã tiếp nhận đơn hàng',        importance: Importance.high, playSound: true, sound: RawResourceAndroidNotificationSound('kinzo_order_accepted')),
    AndroidNotificationChannel('kinzo_order_ready_v3',      'Món đã xong',        description: 'Thông báo món ăn đã sẵn sàng',           importance: Importance.high, playSound: true, sound: RawResourceAndroidNotificationSound('kinzo_order_ready')),
    AndroidNotificationChannel('kinzo_online_new_v3',       'Đơn online mới',     description: 'Thông báo đơn hàng online mới',          importance: Importance.high, playSound: true, sound: RawResourceAndroidNotificationSound('kinzo_online_new')),
    AndroidNotificationChannel('kinzo_online_cancelled_v3', 'Đơn online bị hủy', description: 'Thông báo đơn hàng online bị hủy',       importance: Importance.high, playSound: true, sound: RawResourceAndroidNotificationSound('kinzo_online_cancelled')),
    AndroidNotificationChannel('kinzo_session_request_v3',  'Cấp quyền đặt món', description: 'Thông báo khách cần cấp quyền đặt món',  importance: Importance.high, playSound: true, sound: RawResourceAndroidNotificationSound('kinzo_session_request')),
  ];

  // Only OLD (retired) channel IDs go here — deleted so they don't appear in system Settings.
  // Never add the current channels to this list.
  static const _legacyChannelIds = [
    'kinzo_notifications',
    'kinzo_new_order',        'kinzo_new_order_v2',
    'kinzo_bill_request',     'kinzo_bill_request_v2',
    'kinzo_support_request',  'kinzo_support_request_v2',
    'kinzo_support_accepted', 'kinzo_support_accepted_v2',
    'kinzo_order_accepted',   'kinzo_order_accepted_v2',
    'kinzo_order_ready',      'kinzo_order_ready_v2',
    'kinzo_online_new',       'kinzo_online_new_v2',
    'kinzo_online_cancelled', 'kinzo_online_cancelled_v2',
    'kinzo_session_request',  'kinzo_session_request_v2',
  ];

  static String _channelIdForType(String? type) {
    switch (type) {
      case 'new_order':              return 'kinzo_new_order_v3';
      case 'bill_request':           return 'kinzo_bill_request_v3';
      case 'support_request':        return 'kinzo_support_request_v3';
      case 'support_accepted':       return 'kinzo_support_accepted_v3';
      case 'order_accepted':         return 'kinzo_order_accepted_v3';
      case 'order_ready':            return 'kinzo_order_ready_v3';
      case 'online_order_new':       return 'kinzo_online_new_v3';
      case 'online_order_cancelled': return 'kinzo_online_cancelled_v3';
      case 'session_request':        return 'kinzo_session_request_v3';
      default:                       return 'kinzo_new_order_v3';
    }
  }

  // iOS sound filename (CAF in ios/Runner/ bundle).
  static String _iosSoundForType(String? type) {
    final base = _channelIdForType(type).replaceAll(RegExp(r'_v\d+$'), '');
    return '$base.caf';
  }

  static AndroidNotificationChannel _channelFor(String channelId) =>
      _channels.firstWhere((c) => c.id == channelId, orElse: () => _channels.first);

  // Stream that emits a URL whenever a notification is tapped.
  static final _urlController = StreamController<String>.broadcast();
  static Stream<String> get urlStream => _urlController.stream;

  // Holds foreground notification payloads until user taps them.
  static final _pendingUrls = <int, String>{};

  /// Call once from main() after Firebase.initializeApp().
  static Future<void> initialize() async {
    FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);

    await _localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (details) {
        final id = int.tryParse(details.payload ?? '');
        if (id != null && _pendingUrls.containsKey(id)) {
          _urlController.add(_pendingUrls.remove(id)!);
        }
      },
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      // Delete legacy channels so they don't show "No sound" in Settings.
      for (final id in _legacyChannelIds) {
        await androidPlugin.deleteNotificationChannel(id);
      }
      for (final channel in _channels) {
        await androidPlugin.createNotificationChannel(channel);
      }
    }

    await _requestPermission();

    // Pre-init TTS so the first notification has no cold-start delay.
    NotificationSoundService.warmUp().ignore();

    // Foreground: play audio + show local banner, store URL for tap.
    FirebaseMessaging.onMessage.listen(_showForegroundNotification);

    // Background tap: app comes to foreground.
    FirebaseMessaging.onMessageOpenedApp.listen((message) async {
      final url = await _buildUrl(message.data);
      if (url != null) _urlController.add(url);
    });

    // Killed state tap: app launched from notification.
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      final url = await _buildUrl(initial.data);
      if (url != null) {
        // Delay slightly so the widget tree is ready.
        Future.delayed(const Duration(milliseconds: 800), () {
          _urlController.add(url);
        });
      }
    }

    // Refresh token whenever Firebase rotates it.
    FirebaseMessaging.instance.onTokenRefresh.listen(_saveAndUploadToken);
  }

  /// Builds a webview URL from FCM data payload.
  /// Backend sends: {"tab": "orders"} or {"tab": "tables", "tableFilter": "2"}
  /// or {"route": "online-orders"}.
  static Future<String?> _buildUrl(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();

    // Real staff token takes priority; manager link token is fallback for owner devices.
    final staffToken = await AppSecureStorage.read(AppConstants.staffTokenKey);
    final managerToken = await AppSecureStorage.read(AppConstants.managerLinkKey);
    final linkToken = staffToken ?? managerToken;
    final ownerToken = await AppSecureStorage.read(AppConstants.authTokenKey);

    // No navigation data — open default page based on login type.
    if (data.isEmpty) {
      if (linkToken != null) {
        return '${AppConstants.webBaseUrl}/staff-view?t=${Uri.encodeComponent(linkToken)}&mode=manage&tab=orders';
      }
      if (ownerToken != null) return AppConstants.staffUrl;
      return null;
    }

    final route = data['route'] as String?;
    final tab = data['tab'] as String?;
    final tableFilter = data['tableFilter'] as String?;

    // Personalized staff-view URL when any link token is available.
    if (linkToken != null) {
      final encodedToken = Uri.encodeComponent(linkToken);
      if (route == 'online-orders') {
        return '${AppConstants.webBaseUrl}/staff-online-orders?t=$encodedToken';
      }
      if (tab != null) {
        var url = '${AppConstants.webBaseUrl}/staff-view?t=$encodedToken&mode=manage&tab=$tab';
        if (tableFilter != null && tableFilter.isNotEmpty) {
          url += '&tableFilter=${Uri.encodeComponent(tableFilter)}';
        }
        return url;
      }
    }

    // Owner login fallback: use generic web URLs (owner_token injected by WebViewOverlay).
    if (ownerToken != null) {
      if (route == 'online-orders') return AppConstants.onlineOrdersUrl;
      if (tab != null) return AppConstants.staffUrl;
    }

    return null;
  }

  static Future<void> _requestPermission() async {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _saveAndUploadToken(token);
    }
  }

  static Future<void> _showForegroundNotification(RemoteMessage message) async {
    final n = message.notification;
    if (n == null) return;

    final id = message.hashCode;

    // Pre-build URL so it's ready when user taps.
    final url = await _buildUrl(message.data);
    if (url != null) _pendingUrls[id] = url;

    // Play spoken audio (foreground only — background uses system sound).
    NotificationSoundService.playFromData(message.data).ignore();

    final type = message.data['type'] as String?;
    final chId = _channelIdForType(type);
    final ch = _channelFor(chId);

    await _localNotifications.show(
      id,
      n.title,
      n.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          chId,
          ch.name,
          channelDescription: ch.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          // TTS is already speaking — suppress the banner sound to avoid overlap.
          playSound: false,
        ),
        iOS: DarwinNotificationDetails(
          presentSound: false, // TTS is speaking
          sound: _iosSoundForType(type),
        ),
      ),
      payload: id.toString(),
    );
  }

  static Future<void> _saveAndUploadToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fcm_token', token);

    final baseUrl = prefs.getString(AppConstants.apiBasePathKey) ?? AppConstants.defaultApiUrl;

    final ownerToken = await AppSecureStorage.read(AppConstants.authTokenKey);
    if (ownerToken != null) {
      await _postToken('$baseUrl/api/auth/fcm-token', token, bearerToken: ownerToken);
    }

    final staffToken = await AppSecureStorage.read(AppConstants.staffTokenKey);
    if (staffToken != null) {
      await _postToken(
        '$baseUrl/api/staff-view/fcm-token?t=${Uri.encodeComponent(staffToken)}',
        token,
      );
    }
  }

  static Future<void> _postToken(String url, String fcmToken, {String? bearerToken}) async {
    try {
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (bearerToken != null) headers['Authorization'] = 'Bearer $bearerToken';
      await http
          .post(
            Uri.parse(url),
            headers: headers,
            body: jsonEncode({'fcm_token': fcmToken.isEmpty ? null : fcmToken}),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  /// Call after owner login.
  static Future<void> registerForOwner(String ownerToken) async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString(AppConstants.apiBasePathKey) ?? AppConstants.defaultApiUrl;
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;
    await prefs.setString('fcm_token', token);

    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $ownerToken',
      };
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/auth/fcm-token'),
            headers: headers,
            body: jsonEncode({'fcm_token': token}),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final managerToken = data['manager_token'] as String?;
        if (managerToken != null && managerToken.isNotEmpty) {
          await AppSecureStorage.write(AppConstants.managerLinkKey, managerToken);
        }
      }
    } catch (_) {}
  }

  /// Call after staff QR login.
  static Future<void> registerForStaff(String staffToken) async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString(AppConstants.apiBasePathKey) ?? AppConstants.defaultApiUrl;
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;
    await prefs.setString('fcm_token', token);
    await _postToken(
      '$baseUrl/api/staff-view/fcm-token?t=${Uri.encodeComponent(staffToken)}',
      token,
    );
  }

  /// Call on logout — clears FCM token from backend so notifications stop.
  static Future<void> clearTokenForOwner(String ownerToken) async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString(AppConstants.apiBasePathKey) ?? AppConstants.defaultApiUrl;
    await _postToken('$baseUrl/api/auth/fcm-token', '', bearerToken: ownerToken);
  }

  static Future<void> clearTokenForStaff(String staffToken) async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString(AppConstants.apiBasePathKey) ?? AppConstants.defaultApiUrl;
    await _postToken(
      '$baseUrl/api/staff-view/fcm-token?t=${Uri.encodeComponent(staffToken)}',
      '',
    );
  }
}
