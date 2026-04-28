import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/constants/app_constants.dart';
import '../../core/storage/secure_storage.dart';
import '../../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await ref.read(apiClientProvider).loadBaseUrl();
    await AppSecureStorage.migrateFromSharedPreferences();

    final ownerToken = await AppSecureStorage.read(AppConstants.authTokenKey);
    final staffToken = await AppSecureStorage.read(AppConstants.staffTokenKey);

    if (!mounted) return;

    if (ownerToken != null) {
      await ref.read(authProvider.notifier).checkAuth();
      if (!mounted) return;
      context.go('/home');
    } else if (staffToken != null && staffToken.isNotEmpty) {
      context.go('/staff-view?t=${Uri.encodeComponent(staffToken)}');
    } else {
      context.go('/login-choice');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.primary,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(Icons.restaurant, color: AppColors.primary, size: 52),
              ),
              const SizedBox(height: 24),
              const Text(
                'Kinzo',
                style: TextStyle(
                    color: Colors.white, fontSize: 36, fontWeight: FontWeight.w700, letterSpacing: 1.5),
              ),
              const SizedBox(height: 8),
              Text(
                'Ứng dụng đặt món thông minh',
                style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 16),
              ),
              const SizedBox(height: 48),
              const CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            ],
          ),
        ),
      );
}
