import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/push_notification_service.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../shared/providers/auth_provider.dart';

class AuthCallbackScreen extends ConsumerStatefulWidget {
  final Map<String, String> params;
  const AuthCallbackScreen({super.key, required this.params});

  @override
  ConsumerState<AuthCallbackScreen> createState() => _AuthCallbackScreenState();
}

class _AuthCallbackScreenState extends ConsumerState<AuthCallbackScreen> {
  @override
  void initState() {
    super.initState();
    _process();
  }

  Future<void> _process() async {
    final token = widget.params['token'] ?? '';
    if (token.isEmpty) {
      if (mounted) context.go('/login-choice');
      return;
    }

    await AppSecureStorage.write(AppConstants.authTokenKey, token);

    final slug = widget.params['restaurant_slug'] ?? '';
    final name = widget.params['restaurant_name'] ?? '';
    final username = widget.params['username'] ?? '';
    final ownerId = int.tryParse(widget.params['owner_id'] ?? '') ?? 0;
    if (slug.isNotEmpty) {
      await AppSecureStorage.write(
        AppConstants.ownerInfoKey,
        '{"id":$ownerId,"username":"$username","restaurant_slug":"$slug","restaurant_name":"$name"}',
      );
    }

    await ref.read(authProvider.notifier).checkAuth();
    PushNotificationService.registerForOwner(token).ignore();

    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
