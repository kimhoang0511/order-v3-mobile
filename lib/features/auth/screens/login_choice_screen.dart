import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../printer/providers/printer_settings_provider.dart';

class LoginChoiceScreen extends ConsumerStatefulWidget {
  const LoginChoiceScreen({super.key});

  @override
  ConsumerState<LoginChoiceScreen> createState() => _LoginChoiceScreenState();
}

class _LoginChoiceScreenState extends ConsumerState<LoginChoiceScreen> {
  void _showStaffLoginOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: AppColors.surface,
      builder: (ctx) => _StaffLoginSheet(
        onScanQr: () {
          Navigator.of(ctx).pop();
          _handleQrScan(context);
        },
        onEnterUrl: () {
          Navigator.of(ctx).pop();
          _handleEnterUrl(context);
        },
      ),
    );
  }

  Future<void> _handleQrScan(BuildContext context) async {
    final status = await Permission.camera.request();
    if (!context.mounted) return;

    if (status.isGranted) {
      context.push('/qr-scanner');
    } else if (status.isPermanentlyDenied) {
      _showCameraPermissionDeniedDialog(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cần cấp quyền camera để quét mã QR'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _handleEnterUrl(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _StaffUrlDialog(
        onSubmit: (url) async {
          Navigator.of(ctx).pop();
          await _validateAndNavigate(context, url);
        },
      ),
    );
  }

  Future<void> _validateAndNavigate(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      if (context.mounted) _showError(context, 'URL không hợp lệ');
      return;
    }

    final token = uri.queryParameters['t'];
    if (token == null || token.isEmpty) {
      if (context.mounted) _showError(context, 'URL không chứa token nhân viên');
      return;
    }

    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final base = prefs.getString(AppConstants.apiBasePathKey) ?? AppConstants.defaultApiUrl;
      final res = await http
          .get(Uri.parse('$base/api/staff-view/info?t=${Uri.encodeComponent(token)}'))
          .timeout(const Duration(seconds: 10));

      if (!context.mounted) return;
      Navigator.of(context).pop(); // close loading

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['detail'] != null) {
          _showError(context, 'Token nhân viên không hợp lệ');
          return;
        }
        await AppSecureStorage.write(AppConstants.staffTokenKey, token);
        ref.read(printerSettingsProvider.notifier).syncFromServer();
        if (context.mounted) {
          context.go('/staff-view?t=${Uri.encodeComponent(token)}');
        }
      } else if (res.statusCode == 401 || res.statusCode == 403 || res.statusCode == 404) {
        _showError(context, 'Token nhân viên không hợp lệ hoặc đã hết hạn');
      } else {
        _showError(context, 'Không thể xác thực token nhân viên');
      }
    } catch (_) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst || r.settings.name != null);
        _showError(context, 'Lỗi kết nối, vui lòng thử lại');
      }
    }
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  void _showCameraPermissionDeniedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quyền camera bị từ chối'),
        content: const Text(
          'Ứng dụng cần quyền camera để quét mã QR. Vui lòng vào Cài đặt để cấp quyền.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Huỷ'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              openAppSettings();
            },
            child: const Text('Mở Cài đặt'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 2),
              _buildHeader(),
              const Spacer(flex: 3),
              _buildLoginOptions(context),
              const Spacer(flex: 2),
              _buildPrivacyFooter(),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.restaurant, color: Colors.white, size: 48),
        ),
        const SizedBox(height: 20),
        const Text(
          'Kinzo',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Chọn loại đăng nhập',
          style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildPrivacyFooter() {
    return Text.rich(
      TextSpan(
        text: 'Bằng cách đăng nhập, bạn đồng ý với ',
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        children: [
          TextSpan(
            text: 'Chính sách bảo mật',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.primary,
              decoration: TextDecoration.underline,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () => launchUrl(
                    Uri.parse(AppConstants.privacyPolicyUrl),
                    mode: LaunchMode.externalApplication,
                  ),
          ),
          const TextSpan(text: ' của chúng tôi.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildLoginOptions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LoginOptionCard(
          icon: Icons.admin_panel_settings_outlined,
          title: 'Người quản lý đăng nhập',
          subtitle: 'Đăng nhập bằng tài khoản quản lý',
          iconColor: AppColors.primary,
          iconBgColor: AppColors.primary.withOpacity(0.1),
          onTap: () => context.push('/web-login'),
        ),
        const SizedBox(height: 16),
        _LoginOptionCard(
          icon: Icons.badge_outlined,
          title: 'Nhân viên đăng nhập',
          subtitle: 'Quét QR hoặc nhập link đăng nhập',
          iconColor: AppColors.secondary,
          iconBgColor: AppColors.secondary.withOpacity(0.08),
          onTap: () => _showStaffLoginOptions(context),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => launchUrl(
            Uri.parse('https://www.kinzo.vn/register'),
            mode: LaunchMode.externalApplication,
          ),
          icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
          label: const Text('Đăng ký', style: TextStyle(fontWeight: FontWeight.w600)),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: BorderSide(color: AppColors.primary.withOpacity(0.4)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            minimumSize: const Size(double.infinity, 0),
          ),
        ),
      ],
    );
  }
}

// ── Staff login bottom sheet ───────────────────────────────────────────────────

class _StaffLoginSheet extends StatelessWidget {
  final VoidCallback onScanQr;
  final VoidCallback onEnterUrl;

  const _StaffLoginSheet({required this.onScanQr, required this.onEnterUrl});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Nhân viên đăng nhập',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              'Chọn cách đăng nhập vào tài khoản nhân viên',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            _SheetOption(
              icon: Icons.qr_code_scanner,
              color: AppColors.secondary,
              title: 'Quét mã QR',
              subtitle: 'Dùng camera quét mã QR từ quản lý',
              onTap: onScanQr,
            ),
            const SizedBox(height: 12),
            _SheetOption(
              icon: Icons.link,
              color: AppColors.primary,
              title: 'Nhập link trực tiếp',
              subtitle: 'Dán link /staff-view?t=... vào ô nhập',
              onTap: onEnterUrl,
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SheetOption({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }
}

// ── URL input dialog ──────────────────────────────────────────────────────────

class _StaffUrlDialog extends StatefulWidget {
  final void Function(String url) onSubmit;

  const _StaffUrlDialog({required this.onSubmit});

  @override
  State<_StaffUrlDialog> createState() => _StaffUrlDialogState();
}

class _StaffUrlDialogState extends State<_StaffUrlDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Nhập link đăng nhập', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            hintText: 'https://kinzo.vn/staff-view?t=...',
            hintStyle: const TextStyle(fontSize: 13, color: AppColors.textHint),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            prefixIcon: const Icon(Icons.link, size: 20),
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Vui lòng nhập link';
            final uri = Uri.tryParse(v.trim());
            if (uri == null) return 'Link không hợp lệ';
            if (uri.queryParameters['t'] == null) return 'Link không chứa token nhân viên';
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Huỷ'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              widget.onSubmit(_controller.text.trim());
            }
          },
          child: const Text('Đăng nhập'),
        ),
      ],
    );
  }
}

// ── Shared card widget ────────────────────────────────────────────────────────

class _LoginOptionCard extends StatelessWidget {
  const _LoginOptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.iconColor,
    required this.iconBgColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconColor;
  final Color iconBgColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }
}
