import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/api/api_client.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/auth_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _apiUrlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _apiUrlController.text =
        prefs.getString(AppConstants.apiBasePathKey) ?? AppConstants.defaultApiUrl;
  }

  Future<void> _showDeleteAccountDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Xóa tài khoản'),
        content: const Text(
          'Việc xóa tài khoản là không thể hoàn tác. Tất cả dữ liệu nhà hàng, thực đơn và lịch sử đơn hàng sẽ bị vô hiệu hoá.\n\nBạn có chắc chắn muốn xóa tài khoản không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Huỷ'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Xóa tài khoản', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final api = ref.read(apiClientProvider);
      await api.delete('/api/auth/account');
      await ref.read(authProvider.notifier).logout();
      if (mounted) {
        Navigator.of(context).pop();
        context.go('/login-choice');
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Xóa tài khoản thất bại. Vui lòng thử lại.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _saveApiUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.apiBasePathKey, _apiUrlController.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu cài đặt'), backgroundColor: AppColors.success),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (auth.isAuthenticated) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tài khoản', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(auth.user?.email ?? '', style: const TextStyle(color: AppColors.textSecondary)),
                    if (auth.user?.restaurantSlug != null)
                      Text('Nhà hàng: ${auth.user!.restaurantSlug}',
                          style: const TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Server API', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apiUrlController,
                    decoration: const InputDecoration(
                      labelText: 'API Base URL',
                      hintText: 'http://192.168.x.x:8000',
                      prefixIcon: Icon(Icons.link),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: _saveApiUrl, child: const Text('Lưu')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.qr_code_scanner),
                  title: const Text('Quét QR bàn ăn'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/qr-scanner'),
                ),
                if (auth.isAuthenticated) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.dashboard_outlined),
                    title: const Text('Quản lý đơn hàng'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/staff'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.logout, color: AppColors.error),
                    title: const Text('Đăng xuất', style: TextStyle(color: AppColors.error)),
                    onTap: () async {
                      await ref.read(authProvider.notifier).logout();
                      if (context.mounted) context.go('/login-choice');
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.delete_forever_outlined, color: AppColors.error),
                    title: const Text('Xóa tài khoản', style: TextStyle(color: AppColors.error)),
                    onTap: _showDeleteAccountDialog,
                  ),
                ] else ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.login, color: AppColors.primary),
                    title: const Text('Đăng nhập'),
                    onTap: () => context.push('/login'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
