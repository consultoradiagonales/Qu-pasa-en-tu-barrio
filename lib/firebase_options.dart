// ESTE ARCHIVO SE GENERA AUTOMÁTICAMENTE CON:
//   flutterfire configure
//
// Pasos para generarlo:
//   1. Instalar FlutterFire CLI: dart pub global activate flutterfire_cli
//   2. Estar logueado en Firebase: firebase login
//   3. En la raíz del proyecto: flutterfire configure
//   4. Seleccionar el proyecto Firebase correspondiente
//   5. El archivo firebase_options.dart se genera automáticamente
//
// NO commitear este archivo con credenciales reales a un repositorio público.
// Agregar a .gitignore si el proyecto es open source.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web. '
        'Reconfigure with `flutterfire configure`.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // TODO: Reemplazar estos valores ejecutando `flutterfire configure`
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'TU_API_KEY_ANDROID',
    appId: 'TU_APP_ID_ANDROID',
    messagingSenderId: 'TU_SENDER_ID',
    projectId: 'TU_PROJECT_ID',
    storageBucket: 'TU_PROJECT_ID.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'TU_API_KEY_IOS',
    appId: 'TU_APP_ID_IOS',
    messagingSenderId: 'TU_SENDER_ID',
    projectId: 'TU_PROJECT_ID',
    storageBucket: 'TU_PROJECT_ID.appspot.com',
    iosBundleId: 'com.tuorganizacion.quepasaentubarrio',
  );
}
