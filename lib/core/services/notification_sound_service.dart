import 'dart:io';
import 'package:flutter_tts/flutter_tts.dart';

/// Speaks Vietnamese notification text using the device's on-board TTS engine.
class NotificationSoundService {
  static final _tts = FlutterTts();
  static bool _ready = false;
  // null = not checked yet, true = vi-VN OK, false = unavailable
  static bool? _viAvailable;

  static Future<void> _init() async {
    if (_ready) return;

    await _tts.setSpeechRate(0.85);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    if (Platform.isAndroid) {
      // Android TTS isLanguageAvailable constants:
      //   >= 0 : available (0=LANG_AVAILABLE, 1=LANG_COUNTRY_AVAILABLE, 2=LANG_COUNTRY_VAR_AVAILABLE)
      //   -2   : LANG_MISSING_DATA (engine present, voice pack not installed)
      //   -1   : LANG_NOT_SUPPORTED
      final result = await _tts.isLanguageAvailable('vi-VN');
      final code = result is int ? result : int.tryParse(result.toString()) ?? -1;

      if (code >= 0) {
        await _tts.setLanguage('vi-VN');
        _viAvailable = true;
      } else if (code == -2) {
        // Voice data missing — Android 10+ auto-downloads in background.
        await _tts.setLanguage('vi-VN');
        _viAvailable = false;
        _ready = false; // re-check on next warmUp after auto-download completes
      } else {
        _viAvailable = false;
      }
    } else {
      // iOS: AVSpeechSynthesizer supports Vietnamese natively.
      await _tts.setLanguage('vi-VN');
      _viAvailable = true;
    }

    _ready = true;
  }

  /// Build the spoken phrase from FCM data payload.
  static String _buildPhrase(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    final tableFilter = data['tableFilter'] as String?;

    final hasTable = tableFilter != null && tableFilter.isNotEmpty;
    final ban = hasTable ? 'Bàn $tableFilter' : '';

    switch (type) {
      case 'new_order':
        return hasTable ? '$ban vừa đặt món' : 'Có đơn hàng mới';
      case 'bill_request':
        return hasTable ? '$ban yêu cầu tính tiền' : 'Yêu cầu tính tiền';
      case 'support_request':
        return hasTable ? '$ban gọi nhân viên' : 'Có bàn gọi nhân viên';
      case 'support_accepted':
        return hasTable ? 'Đã tiếp nhận yêu cầu $ban' : 'Đã tiếp nhận yêu cầu';
      case 'order_accepted':
        return hasTable ? 'Đã tiếp nhận đơn $ban' : 'Đã tiếp nhận đơn';
      case 'order_ready':
        return hasTable ? '$ban đã xong món' : 'Có món đã xong';
      case 'online_order_new':
        return 'Có đơn hàng online mới';
      case 'online_order_cancelled':
        return 'Đơn hàng online bị hủy';
      case 'session_request':
        return hasTable ? '$ban cần cấp quyền đặt món' : 'Có khách cần cấp quyền đặt món';
    }

    // Fallback for older backend versions without type field.
    final tab = data['tab'] as String?;
    final route = data['route'] as String?;
    if (tab == 'tables') return hasTable ? '$ban yêu cầu tính tiền' : 'Yêu cầu tính tiền';
    if (tab == 'orders') return hasTable ? '$ban vừa đặt món' : 'Có đơn hàng mới';
    if (tab == 'sessions') return hasTable ? '$ban cần cấp quyền đặt món' : 'Có thông báo mới';
    if (route == 'online-orders') return 'Có đơn hàng online mới';
    return 'Có thông báo mới';
  }

  /// Speak the notification aloud. Interrupts any in-progress speech.
  static Future<void> playFromData(Map<String, dynamic> data) async {
    try {
      await _init();
      if (_viAvailable == false) return; // language not ready yet
      final phrase = _buildPhrase(data);
      await _tts.stop();
      await _tts.speak(phrase);
    } catch (_) {}
  }

  /// Call once at app startup so the first notification has no init delay.
  static Future<void> warmUp() async => _init();
}
