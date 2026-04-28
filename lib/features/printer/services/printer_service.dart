import 'dart:io';
import '../models/bill_model.dart';
import '../models/kitchen_ticket_model.dart';
import '../models/printer_settings.dart';
import 'escpos_builder.dart';

enum PrintStatus { idle, printing, success, error }

class PrintResult {
  final bool success;
  final String message;

  const PrintResult({required this.success, required this.message});
}

class PrinterService {
  static Future<PrintResult> printViaNetwork({
    required Bill bill,
    required PrinterSettings settings,
  }) async {
    try {
      final bytes = await EscPosBuilder.buildBill(bill, settings);
      final socket = await Socket.connect(
        settings.ipAddress,
        settings.port,
        timeout: const Duration(seconds: 10),
      );
      socket.add(bytes);
      await socket.flush();
      await socket.close();
      return const PrintResult(success: true, message: 'In thành công!');
    } on SocketException catch (e) {
      return PrintResult(
        success: false,
        message: 'Không kết nối được máy in:\n${e.message}',
      );
    } catch (e) {
      return PrintResult(success: false, message: 'Lỗi khi in: $e');
    }
  }

  static Future<PrintResult> printKitchenTicketViaNetwork({
    required KitchenTicket ticket,
    required PrinterSettings settings,
  }) async {
    try {
      final bytes = await EscPosBuilder.buildKitchenTicket(ticket, settings);
      final socket = await Socket.connect(
        settings.ipAddress,
        settings.port,
        timeout: const Duration(seconds: 10),
      );
      socket.add(bytes);
      await socket.flush();
      await socket.close();
      return const PrintResult(
          success: true, message: 'In phiếu chế biến thành công!');
    } on SocketException catch (e) {
      return PrintResult(
        success: false,
        message: 'Không kết nối được máy in:\n${e.message}',
      );
    } catch (e) {
      return PrintResult(
          success: false, message: 'Lỗi khi in phiếu chế biến: $e');
    }
  }
}
