import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';
import '../storage/secure_storage.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

class ApiClient {
  late Dio _dio;

  ApiClient() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConstants.defaultApiUrl,
      connectTimeout: AppConstants.connectTimeout,
      receiveTimeout: AppConstants.receiveTimeout,
      headers: {'Content-Type': 'application/json'},
    ));
    _dio.interceptors.add(_AuthInterceptor());
    _dio.interceptors.add(_CurlLogInterceptor());
  }

  Future<void> setBaseUrl(String url) async {
    _dio.options.baseUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.apiBasePathKey, url);
  }

  Future<void> loadBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(AppConstants.apiBasePathKey) ?? AppConstants.defaultApiUrl;
    _dio.options.baseUrl = url;
  }

  Future<Response> get(String path, {Map<String, dynamic>? queryParameters}) =>
      _dio.get(path, queryParameters: queryParameters);

  Future<Response> post(String path, {dynamic data, Map<String, dynamic>? queryParameters}) =>
      _dio.post(path, data: data, queryParameters: queryParameters);

  Future<Response> put(String path, {dynamic data}) => _dio.put(path, data: data);

  Future<Response> delete(String path, {Map<String, dynamic>? queryParameters}) =>
      _dio.delete(path, queryParameters: queryParameters);
}

class _CurlLogInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final method = options.method.toUpperCase();
    final url = options.uri.toString();

    final headers = options.headers.entries
        .map((e) => "-H '${e.key}: ${e.value}'")
        .join(' \\\n  ');

    String body = '';
    if (options.data != null) {
      final encoded = options.data is String
          ? options.data
          : jsonEncode(options.data);
      body = "\\\n  -d '${encoded.toString().replaceAll("'", "\\'")}'";
    }

    print('\n[CURL] curl -X $method \\\n  $headers $body\\\n  \'$url\'\n');
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final status = response.statusCode;
    final url = response.requestOptions.uri;
    String body = '';
    try {
      body = const JsonEncoder.withIndent('  ').convert(response.data);
    } catch (_) {
      body = response.data.toString();
    }
    print('[CURL] ← $status $url\n$body\n');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final url = err.requestOptions.uri;
    final status = err.response?.statusCode ?? 'NO_RESPONSE';
    String body = '';
    try {
      body = const JsonEncoder.withIndent('  ').convert(err.response?.data);
    } catch (_) {
      body = err.response?.data?.toString() ?? err.message ?? '';
    }
    print('[CURL] ✗ $status $url\n$body\n');
    handler.next(err);
  }
}

class _AuthInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (!options.headers.containsKey('Authorization')) {
      final token = await AppSecureStorage.read(AppConstants.authTokenKey);
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    handler.next(err);
  }
}
