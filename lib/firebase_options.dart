// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCB_rLKGb0O_6Ha7jb6uidb1Bq9jdq75rk',
    appId: '1:440927216737:web:23f01132e168d8f55a3620',
    messagingSenderId: '440927216737',
    projectId: 'heatwatch-nv',
    authDomain: 'heatwatch-nv.firebaseapp.com',
    storageBucket: 'heatwatch-nv.firebasestorage.app',
    measurementId: 'G-P5GEL38LJH',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCM5NyPUxn_cd6_JJCaJ8NBeYGUYDo2rvw',
    appId: '1:440927216737:android:90556ced9bd27f7f5a3620',
    messagingSenderId: '440927216737',
    projectId: 'heatwatch-nv',
    storageBucket: 'heatwatch-nv.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCZNacQxGWQXNFinA18zbgxtcgvCUgVgLs',
    appId: '1:440927216737:ios:8aa5d032d778b9de5a3620',
    messagingSenderId: '440927216737',
    projectId: 'heatwatch-nv',
    storageBucket: 'heatwatch-nv.firebasestorage.app',
    iosBundleId: 'com.ivantrac.heatwatch',
  );
  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyCZNacQxGWQXNFinA18zbgxtcgvCUgVgLs',
    appId: '1:440927216737:ios:8aa5d032d778b9de5a3620',
    messagingSenderId: '440927216737',
    projectId: 'heatwatch-nv',
    storageBucket: 'heatwatch-nv.firebasestorage.app',
    iosBundleId: 'com.ivantrac.heatwatch',
  );
  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyCB_rLKGb0O_6Ha7jb6uidb1Bq9jdq75rk',
    appId: '1:440927216737:web:11841407d8f4b36a5a3620',
    messagingSenderId: '440927216737',
    projectId: 'heatwatch-nv',
    authDomain: 'heatwatch-nv.firebaseapp.com',
    storageBucket: 'heatwatch-nv.firebasestorage.app',
    measurementId: 'G-E9XDTEPEQF',
  );
}
