import 'package:dio/dio.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  factory ApiException.fromDioError(DioException error) {
    final statusCode = error.response?.statusCode;
    final data = error.response?.data;
    String message = 'Đã xảy ra lỗi. Vui lòng thử lại.';

    if (data is Map && data.containsKey('detail')) {
      message = data['detail'].toString();
    } else if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      message = 'Kết nối timed out. Kiểm tra mạng và thử lại.';
    } else if (error.type == DioExceptionType.connectionError) {
      message = 'Không thể kết nối đến server.';
    }

    return ApiException(message, statusCode: statusCode);
  }

  @override
  String toString() => message;
}
