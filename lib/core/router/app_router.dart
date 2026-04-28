import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/screens/login_choice_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/auth/screens/web_login_screen.dart';
import '../../features/auth/screens/auth_callback_screen.dart';
import '../../features/menu/screens/menu_screen.dart';
import '../../features/cart/screens/cart_screen.dart';
import '../../features/orders/screens/my_orders_screen.dart';
import '../../features/orders/screens/order_detail_screen.dart';
import '../../features/bill/screens/bill_screen.dart';
import '../../features/qr_scanner/screens/qr_scanner_screen.dart';
import '../../features/staff/screens/staff_screen.dart' show StaffViewScreen;
import '../../features/online_order/screens/online_order_screen.dart';
import '../../shared/screens/home_screen.dart';
import '../../shared/screens/splash_screen.dart';
import '../../shared/screens/in_app_web_screen.dart';
import '../../core/constants/app_constants.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login-choice', builder: (_, __) => const LoginChoiceScreen()),
      GoRoute(path: '/web-login', builder: (_, __) => const WebLoginScreen()),
      GoRoute(
        path: '/auth',
        builder: (_, state) => AuthCallbackScreen(params: state.uri.queryParameters),
      ),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
      GoRoute(
        path: '/menu',
        builder: (_, state) => MenuScreen(
          restaurantSlug: state.uri.queryParameters['restaurant'] ?? '',
          tableNumber: state.uri.queryParameters['table'] ?? '',
        ),
      ),
      GoRoute(path: '/cart', builder: (_, __) => const CartScreen()),
      GoRoute(path: '/my-orders', builder: (_, __) => const MyOrdersScreen()),
      GoRoute(
        path: '/order/:id',
        builder: (_, state) => OrderDetailScreen(orderId: int.parse(state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/bill',
        builder: (_, state) => BillScreen(
          restaurantSlug: state.uri.queryParameters['restaurant'] ?? '',
          tableNumber: state.uri.queryParameters['table'] ?? '',
        ),
      ),
      GoRoute(
        path: '/qr-scanner',
        builder: (_, state) => QrScannerScreen(
          mode: state.uri.queryParameters['mode'],
          staffToken: state.uri.queryParameters['t'],
        ),
      ),
      GoRoute(
        path: '/staff-view',
        builder: (_, state) => StaffViewScreen(
          token: state.uri.queryParameters['t'] ?? '',
        ),
      ),
      GoRoute(path: '/online-order', builder: (_, __) => const OnlineOrderScreen()),
      GoRoute(path: '/settings', builder: (_, __) => const InAppWebScreen(
        title: 'Cài đặt',
        url: AppConstants.settingsUrl,
      )),
      GoRoute(path: '/menu-manage', builder: (_, __) => const InAppWebScreen(
        title: 'Quản lý menu',
        url: AppConstants.menuManageUrl,
      )),
      GoRoute(
        path: '/report',
        builder: (_, __) => const Scaffold(body: Center(child: Text('Báo cáo - coming soon'))),
      ),
    ],
    errorBuilder: (_, state) {
      // Handle kinzoapp://auth?token=... deep link from Google OAuth on iOS.
      final uri = state.uri;
      if (uri.scheme == 'kinzoapp' && uri.host == 'auth') {
        return AuthCallbackScreen(params: uri.queryParameters);
      }
      return Scaffold(
        body: Center(child: Text('Page not found: ${state.error}')),
      );
    },
  );
});
