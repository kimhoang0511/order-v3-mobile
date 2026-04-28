import 'dart:async';
import 'package:flutter/services.dart';

class DeepLinkService {
  static const _channel = MethodChannel('com.kinzo/deep_link');
  static final _controller = StreamController<Uri>.broadcast();

  static Stream<Uri> get stream => _controller.stream;

  static void initialize() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onDeepLink') {
        final url = call.arguments as String?;
        if (url != null) {
          final uri = Uri.tryParse(url);
          if (uri != null) _controller.add(uri);
        }
      }
    });
  }
}
