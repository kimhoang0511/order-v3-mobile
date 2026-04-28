import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

class DefaultFirebaseOptions {
  static bool get isSupported =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('Firebase is only supported on Android and iOS');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBwHn1t0ZoVSSlWbZzA17jX7EbTcfnLwhM',
    appId: '1:285960105739:android:75cb6a34a84d3247e4bc0e',
    messagingSenderId: '285960105739',
    projectId: 'kinzo-order-e7264',
    storageBucket: 'kinzo-order-e7264.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDSlKq8KGFKl84gLjHFvtsWUZr2RAtBKcs',
    appId: '1:285960105739:ios:0f5f9b1a27b6cdc7e4bc0e',
    messagingSenderId: '285960105739',
    projectId: 'kinzo-order-e7264',
    storageBucket: 'kinzo-order-e7264.firebasestorage.app',
    iosBundleId: 'com.kinzo.orderV3Mobile',
  );

  // iOS: run `flutterfire configure --platforms=ios` to fill in real values.
}