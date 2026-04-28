import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/remote_settings.dart';

enum WsStatus { disconnected, connecting, connected, reconnecting }

class WebSocketService extends ChangeNotifier {
  WsStatus _status = WsStatus.disconnected;
  RemoteSettings _settings = const RemoteSettings();

  WebSocket? _socket;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  int _reconnectAttempt = 0;

  // Callbacks được gán bởi PrinterAppStateNotifier
  Future<void> Function(Map<String, dynamic> data, String? requestId)? onPrintBill;
  Future<void> Function(Map<String, dynamic> data, String? requestId)? onPrintKitchen;

  WsStatus get status => _status;

  void configure(RemoteSettings settings) {
    _settings = settings;
    if (settings.wsEnabled && settings.isConfigured) {
      _disconnect();
      _connect();
    } else {
      _disconnect();
    }
  }

  void reconnect() => configure(_settings);

  void sendAck(String requestId, String status) {
    _send({'event': 'ack', 'requestId': requestId, 'status': status});
  }

  void _connect() {
    _setStatus(WsStatus.connecting);
    WebSocket.connect(_settings.wsUrl).then((socket) {
      _socket = socket;
      _sub = socket.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );
      _setStatus(WsStatus.connected);
      _reconnectAttempt = 0;
      _startPingTimer();
    }).catchError((Object e) { _onError(e); });
  }

  void _disconnect() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _sub?.cancel();
    _sub = null;
    _socket?.close();
    _socket = null;
    _setStatus(WsStatus.disconnected);
  }

  void _onMessage(dynamic raw) {
    try {
      final map = jsonDecode(raw as String) as Map<String, dynamic>;
      final event = map['event'] as String?;
      final requestId = map['requestId'] as String?;
      final data = map['data'] as Map<String, dynamic>? ?? map;
      switch (event) {
        case 'print_bill':
          onPrintBill?.call(data, requestId);
        case 'print_kitchen':
          onPrintKitchen?.call(data, requestId);
        case 'pong':
          break;
        default:
          debugPrint('[WS] Unknown event: $event');
      }
    } catch (e) {
      debugPrint('[WS] Failed to parse message: $e');
    }
  }

  void _onError(Object error) {
    debugPrint('[WS] Error: $error');
    _pingTimer?.cancel();
    _pingTimer = null;
    _sub?.cancel();
    _sub = null;
    _socket = null;
    if (_settings.wsEnabled && _settings.isConfigured) {
      _scheduleReconnect();
    } else {
      _setStatus(WsStatus.disconnected);
    }
  }

  void _onDone() {
    debugPrint('[WS] Connection closed');
    _pingTimer?.cancel();
    _pingTimer = null;
    _sub?.cancel();
    _sub = null;
    _socket = null;
    if (_settings.wsEnabled && _settings.isConfigured) {
      _scheduleReconnect();
    } else {
      _setStatus(WsStatus.disconnected);
    }
  }

  void _scheduleReconnect() {
    _setStatus(WsStatus.reconnecting);
    _reconnectAttempt++;
    _reconnectTimer = Timer(_backoffDuration(), _connect);
  }

  Duration _backoffDuration() {
    final seconds = [1, 2, 4, 8, 30];
    final idx = (_reconnectAttempt - 1).clamp(0, seconds.length - 1);
    return Duration(seconds: seconds[idx]);
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _send({'event': 'ping'});
    });
  }

  void _send(Map<String, dynamic> payload) {
    try {
      _socket?.add(jsonEncode(payload));
    } catch (e) {
      debugPrint('[WS] Failed to send: $e');
    }
  }

  void _setStatus(WsStatus status) {
    if (_status != status) {
      _status = status;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disconnect();
    super.dispose();
  }
}
