import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/constants/app_constants.dart';
import '../../core/storage/secure_storage.dart';
import '../../core/services/push_notification_service.dart';
import '../models/user.dart';
import '../../features/printer/providers/printer_settings_provider.dart';

class AuthState {
  final User? user;
  final bool isLoading;
  final String? error;

  const AuthState({this.user, this.isLoading = false, this.error});

  bool get isAuthenticated => user != null;
}

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiClient _api;
  final Ref _ref;

  AuthNotifier(this._api, this._ref) : super(const AuthState());

  Future<void> login(String email, String password) async {
    state = const AuthState(isLoading: true);
    try {
      final response = await _api.post('/api/login', data: {
        'username': email,
        'password': password,
      });
      final token = response.data['access_token'] as String;
      final restaurantName = response.data['restaurant_name'] as String?;
      await AppSecureStorage.write(AppConstants.authTokenKey, token);
      if (restaurantName != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(AppConstants.cachedRestaurantNameKey, restaurantName);
      }
      await _fetchCurrentUser();
      PushNotificationService.registerForOwner(token).ignore();
    } on DioException catch (e) {
      state = AuthState(error: ApiException.fromDioError(e).message);
    } catch (e) {
      state = AuthState(error: e.toString());
    }
  }

  Future<void> _fetchCurrentUser() async {
    try {
      final response = await _api.get('/api/auth/me');
      var user = User.fromJson(response.data as Map<String, dynamic>);
      if (user.restaurantName == null) {
        final prefs = await SharedPreferences.getInstance();
        final cached = prefs.getString(AppConstants.cachedRestaurantNameKey);
        if (cached != null) user = user.copyWith(restaurantName: cached);
      }
      state = AuthState(user: user);
      _ref.read(printerSettingsProvider.notifier).syncFromServer();
    } catch (_) {
      state = const AuthState();
    }
  }

  Future<void> logout() async {
    final token = await AppSecureStorage.read(AppConstants.authTokenKey);
    if (token != null) {
      PushNotificationService.clearTokenForOwner(token).ignore();
    }
    await AppSecureStorage.delete(AppConstants.authTokenKey);
    await AppSecureStorage.delete(AppConstants.ownerInfoKey);
    await AppSecureStorage.delete(AppConstants.managerLinkKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.cachedRestaurantNameKey);
    state = const AuthState();
  }

  Future<void> refresh() => _fetchCurrentUser();

  Future<void> checkAuth() async {
    final token = await AppSecureStorage.read(AppConstants.authTokenKey);
    if (token == null) return;

    // Try local owner_info first (saved by WebView login)
    final ownerRaw = await AppSecureStorage.read(AppConstants.ownerInfoKey);
    if (ownerRaw != null) {
      try {
        final map = jsonDecode(ownerRaw) as Map<String, dynamic>;
        final user = User(
          id: map['id'] as int? ?? 0,
          email: map['username'] as String? ?? '',
          restaurantName: map['restaurant_name'] as String?,
          restaurantSlug: map['restaurant_slug'] as String?,
          isAdmin: true,
        );
        state = AuthState(user: user);
        _ref.read(printerSettingsProvider.notifier).syncFromServer();
        if (await AppSecureStorage.read(AppConstants.managerLinkKey) == null) {
          PushNotificationService.registerForOwner(token).ignore();
        }
        return;
      } catch (_) {}
    }

    await _fetchCurrentUser();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.read(apiClientProvider), ref);
});
