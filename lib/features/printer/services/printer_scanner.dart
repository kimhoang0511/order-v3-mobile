import 'dart:async';
import 'dart:io';

class ScanResult {
  final String ip;
  final int port;

  const ScanResult({required this.ip, required this.port});

  @override
  String toString() => '$ip:$port';
}

class PrinterScanner {
  static Future<List<ScanResult>> scan({
    int port = 9100,
    Duration timeout = const Duration(milliseconds: 400),
    void Function(int scanned, int total)? onProgress,
  }) async {
    final localIp = await _getLocalIp();
    if (localIp == null) {
      throw Exception('Không lấy được địa chỉ IP. Kiểm tra kết nối Wi-Fi/LAN.');
    }

    final parts = localIp.split('.');
    if (parts.length != 4) {
      throw Exception('Địa chỉ IP không hợp lệ: $localIp');
    }

    final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
    const total = 254;
    final found = <ScanResult>[];
    int scanned = 0;

    const batchSize = 30;
    for (int batch = 0; batch < total; batch += batchSize) {
      final futures = <Future<void>>[];
      final end = (batch + batchSize).clamp(0, total);
      for (int i = batch + 1; i <= end; i++) {
        final ip = '$subnet.$i';
        futures.add(_probe(ip, port, timeout).then((open) {
          if (open) found.add(ScanResult(ip: ip, port: port));
        }).whenComplete(() {
          scanned++;
          onProgress?.call(scanned, total);
        }));
      }
      await Future.wait(futures);
    }

    found.sort((a, b) {
      final aLast = int.tryParse(a.ip.split('.').last) ?? 0;
      final bLast = int.tryParse(b.ip.split('.').last) ?? 0;
      return aLast.compareTo(bLast);
    });

    return found;
  }

  static Future<bool> _probe(String ip, int port, Duration timeout) async {
    try {
      final socket = await Socket.connect(ip, port, timeout: timeout);
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        if (name.contains('wlan') || name.contains('wifi') || name.startsWith('en')) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback) return addr.address;
          }
        }
      }
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return null;
  }
}
