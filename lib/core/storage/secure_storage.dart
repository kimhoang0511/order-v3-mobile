import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';

/// Wraps FlutterSecureStorage for auth-sensitive keys.
/// Non-sensitive prefs (API URL, printer config, etc.) remain in SharedPreferences.
class AppSecureStorage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static Future<String?> read(String key) => _storage.read(key: key);

  static Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  static Future<void> delete(String key) => _storage.delete(key: key);

  /// Runs once after app update: moves sensitive tokens from SharedPreferences
  /// into Keychain/EncryptedSharedPreferences.
  static Future<void> migrateFromSharedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    const migratedKey = 'secure_storage_migrated_v1';
    if (prefs.getBool(migratedKey) == true) return;

    const sensitiveKeys = [
      AppConstants.authTokenKey,
      AppConstants.staffTokenKey,
      AppConstants.ownerInfoKey,
      AppConstants.managerLinkKey,
    ];

    for (final key in sensitiveKeys) {
      final value = prefs.getString(key);
      if (value != null && value.isNotEmpty) {
        await _storage.write(key: key, value: value);
        await prefs.remove(key);
      }
    }

    await prefs.setBool(migratedKey, true);
  }
}
