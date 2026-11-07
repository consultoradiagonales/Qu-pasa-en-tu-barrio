# ConDi - iOS

- Bundle ID: `ar.com.consultoradiagonales.condi`
- Deployment target: iOS 15.0
- Firebase: `ios/Runner/GoogleService-Info.plist`
- Google Sign-In: cliente iOS y cliente servidor web configurados en `ios/Runner/Info.plist`
- Google Maps: inicializado en `ios/Runner/AppDelegate.swift`

La fuente nativa esta en `../../ios/`. Para compilar y firmar hace falta macOS con Xcode y una cuenta Apple Developer.

## Compilacion en Mac

```bash
flutter pub get
cd ios
pod install
cd ..
flutter build ipa --release
```

## Flujos a validar en iPhone

- inicio de sesion con Google y correo
- camara y selector de imagen
- ubicacion y seleccion manual en el mapa
- carga del reporte en Firestore
- lectura del estado del reporte
- notificaciones y cierre de sesion
