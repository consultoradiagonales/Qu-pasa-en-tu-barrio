import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'features/demo/investor_demo_app.dart';
import 'core/services/app_update_service.dart';
import 'core/services/device_profile_service.dart';
import 'core/services/local_notification_service.dart';
import 'core/services/push_token_registrar.dart';

/// Manejador de mensajes FCM en segundo plano (debe ser función de nivel superior)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('Mensaje FCM en background: ${message.messageId}');
}

/// Apunta la app al emulador local en vez de a Firebase real.
/// Se activa con: flutter run --dart-define=USE_EMULATOR=true
const _useEmulator = bool.fromEnvironment('USE_EMULATOR');

Future<void> _connectToEmulators() async {
  const host = 'localhost';
  await FirebaseAuth.instance.useAuthEmulator(host, 9099);
  FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
  await FirebaseStorage.instance.useStorageEmulator(host, 9199);
  debugPrint('Conectado al emulador de Firebase en $host');
}

/// Firebase App Check: demuestra ante Firebase que las peticiones vienen de la
/// app original instalada desde Google Play y no de un script que reutiliza la
/// API key (que viaja dentro del APK y no es secreta).
///
/// Por sí solo no bloquea a nadie: Firebase solo rechaza peticiones sin token
/// cuando se activa "Enforce" en la consola. Eso se hace recién después de
/// comprobar que los usuarios reales llegan con token válido.
///
/// En debug usa el proveedor de depuración, que imprime en el log un token
/// para registrar en la consola. La web queda afuera a propósito: necesitaría
/// una clave reCAPTCHA y activarlo sin ella rompería el panel web.
Future<void> _activateAppCheck() async {
  if (kIsWeb) return;
  try {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kReleaseMode
          ? const AndroidPlayIntegrityProvider()
          : const AndroidDebugProvider(),
      providerApple: kReleaseMode
          ? const AppleDeviceCheckProvider()
          : const AppleDebugProvider(),
    );
  } catch (error) {
    // Nunca debe impedir que la app abra.
    debugPrint('App Check no se pudo activar: $error');
  }
}

final _pushRegistrar = PushTokenRegistrar(
  getToken: () => FirebaseMessaging.instance.getToken(),
  saveToken: (uid, token) => FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .update({'fcmToken': token}),
  ensurePermission: () async {
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.getNotificationSettings();
    debugPrint('Push: permiso de notificaciones = '
        '${settings.authorizationStatus}');
    if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
      await messaging.requestPermission(alert: true, badge: true, sound: true);
    }
  },
);

/// Guarda el token FCM de la persona con sesión iniciada. Se llama al abrir
/// la app con sesión ya iniciada y en cada cambio de sesión; los errores se
/// loguean y se reintentan (ver PushTokenRegistrar).
Future<void> _registerPushForUser(User user) async {
  if (kIsWeb) return;
  await _pushRegistrar.register(user.uid);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  var firebaseReady = false;
  RequiredAppUpdate? requiredUpdate;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    if (_useEmulator) {
      await _connectToEmulators();
      runApp(const ProviderScope(child: QuePasaApp()));
      return;
    }

    await _activateAppCheck();
    try {
      requiredUpdate = await AppUpdateService.requiredUpdate();
    } catch (error) {
      debugPrint('No se pudo consultar la versión mínima: $error');
    }
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    try {
      await LocalNotificationService.initialize();
    } catch (error) {
      debugPrint('Notificaciones locales no disponibles: $error');
    }
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        unawaited(_registerPushForUser(user));
        unawaited(DeviceProfileService.recordUsageIfAllowed());
      }
    });
    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification == null) return;
      unawaited(LocalNotificationService.showRemote(
        title: notification.title ?? 'ConDi',
        body: notification.body ?? 'Tenés una actualización en tu reporte.',
      ));
    });
    FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'fcmToken': token,
        });
      } catch (error) {
        debugPrint('Push: no se pudo guardar el token renovado: $error');
      }
    });
    firebaseReady = true;
  } catch (error, stack) {
    debugPrint('Firebase no se pudo inicializar: $error $stack');
  }

  runApp(
    // ProviderScope envuelve toda la app para Riverpod
    ProviderScope(
      child: firebaseReady
          ? QuePasaApp(requiredUpdate: requiredUpdate)
          : const InvestorDemoApp(),
    ),
  );
}

class QuePasaApp extends ConsumerWidget {
  const QuePasaApp({super.key, this.requiredUpdate});

  final RequiredAppUpdate? requiredUpdate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (requiredUpdate != null) {
      return MaterialApp(
        title: 'ConDi',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        home: MandatoryUpdateScreen(update: requiredUpdate!),
      );
    }
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'ConDi',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
