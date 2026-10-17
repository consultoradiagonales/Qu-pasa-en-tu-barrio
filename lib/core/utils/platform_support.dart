import 'package:flutter/foundation.dart';

/// En iPhone no se ofrece "Continuar con Google".
///
/// App Review (guideline 4.8) rechaza una app que combina un login de terceros
/// con su propio registro por correo si no ofrece también "Iniciar sesión con
/// Apple". Mientras esa opción no exista, en iOS se entra solo con correo y
/// contraseña. Android y web no cambian.
bool get googleSignInAvailable => defaultTargetPlatform != TargetPlatform.iOS;
