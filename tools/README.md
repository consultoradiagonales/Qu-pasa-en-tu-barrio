# Herramientas del proyecto

Todos los scripts, configuraciones y credenciales específicas de este proyecto.

## Estructura

```
tools/
├── setup.ps1              ← Instala todo desde cero en un PC nuevo
├── build-android.ps1      ← Genera APK de release
├── build-web.ps1          ← Compila Flutter Web y sube a gh-pages
├── deploy-firebase.ps1    ← Despliega Cloud Functions + Firestore rules
├── env.example            ← Variables de entorno requeridas (sin valores reales)
├── firebase/              ← Archivos de configuración Firebase (sin google-services.json)
└── signing/               ← Instrucciones para firmar el APK (sin el keystore real)
```

## Herramientas del sistema (fuera del proyecto, compartidas)

| Herramienta | Ubicación | Instalar con |
|---|---|---|
| Flutter SDK | `C:\flutter` | `tools\setup.ps1` |
| Android SDK | `C:\Android` | Android Studio o `setup.ps1` |
| Java JDK 17 | `C:\jdk17` | `tools\setup.ps1` |
| Firebase CLI | global npm | `npm install -g firebase-tools` |
| FlutterFire CLI | global pub | `dart pub global activate flutterfire_cli` |

## Primer uso en un PC nuevo

```powershell
cd "E:\CODEX ChatGPT\04 - APP municipal → Qué pasa en tu barrio"
.\tools\setup.ps1
```
