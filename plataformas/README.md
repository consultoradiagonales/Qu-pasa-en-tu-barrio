# Organizacion de plataformas ConDi

- `lib/`: codigo Flutter compartido para Android, iOS y Web.
- `android/`: proyecto nativo Android canonico requerido por Flutter.
- `ios/`: proyecto nativo iOS canonico requerido por Flutter.
- `plataformas/Android/`: entregables y notas de Android.
- `plataformas/iOS/`: configuracion, checklist y notas de iOS.

Las carpetas nativas `android/` e `ios/` conservan sus nombres porque Flutter las necesita para compilar. Las subcarpetas con mayuscula organizan los entregables por plataforma sin duplicar el codigo fuente.
