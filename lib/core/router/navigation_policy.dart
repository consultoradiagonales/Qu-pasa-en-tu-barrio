/// La app ciudadana abre un inicio simple: cámara rápida arriba y cuenta abajo.
/// Operations requiere una URL web explícita o un build separado.
const citizenStartLocation = '/home';
const operationsBuild = bool.fromEnvironment('CONDI_OPERATIONS');

bool isOperationsPath(String path) =>
    path.startsWith('/admin') ||
    path.startsWith('/coordinator') ||
    path.startsWith('/field');

String signedInDestination(String? next) {
  if (next != null &&
      RegExp(r'^(/field)?/notifications\?open=[A-Za-z0-9_-]{1,240}$')
          .hasMatch(next)) {
    return next;
  }
  if (next != null &&
      RegExp(r'^/field/task/[A-Za-z0-9_-]{1,180}(/work)?$').hasMatch(next)) {
    return next;
  }
  if (next == '/admin' ||
      next == '/coordinator' ||
      next == '/field' ||
      next == '/home' ||
      next == '/map' ||
      next == '/my-reports' ||
      next == '/profile' ||
      next == '/notifications' ||
      next == '/field/notifications' ||
      next == '/clima' ||
      next == '/clima?view=map') {
    return next!;
  }
  if (next == 'report') return '/report/new?resume=1';
  return citizenStartLocation;
}

bool canOpenOperations(String path, String? role, {required bool enabled}) {
  if (!isOperationsPath(path)) return true;
  if (!enabled) return false;
  if (path.startsWith('/field')) {
    return role == 'field_worker' || role == 'field_manager';
  }
  return role == 'admin' ||
      role == 'coordinator' ||
      role == 'moderator' ||
      role == 'field_manager';
}
