import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/services/push_notification_service.dart';
import 'core/services/deep_link_service.dart';
import 'firebase_options.dart';
import 'shared/widgets/webview_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  DeepLinkService.initialize();

  if (DefaultFirebaseOptions.isSupported) {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    } catch (_) {
      // Firebase unavailable — app still runs.
    }
  }

  // Render the app immediately so user never sees a black/white screen.
  // Push notification setup (including permission dialog) runs after first frame.
  runApp(const ProviderScope(child: KinzoApp()));

  if (DefaultFirebaseOptions.isSupported) {
    try {
      await PushNotificationService.initialize();
    } catch (_) {}
  }
}

class KinzoApp extends ConsumerWidget {
  const KinzoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Kinzo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
      builder: (context, child) => Stack(
        children: [
          child ?? const SizedBox.shrink(),
          const WebViewOverlay(),
        ],
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('vi', 'VN'),
        Locale('en', 'US'),
      ],
      locale: const Locale('vi', 'VN'),
    );
  }
}
