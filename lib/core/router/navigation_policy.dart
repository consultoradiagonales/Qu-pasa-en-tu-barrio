/// The citizen app always opens reporting. Operations requires an explicit
/// web URL or a separately configured operations build.
const citizenStartLocation = '/report/new?mode=camera';
const operationsBuild = bool.fromEnvironment('CONDI_OPERATIONS');

bool isOperationsPath(String path) =>
    path.startsWith('/admin') ||
    path.startsWith('/coordinator') ||
    path.startsWith('/field');

String signedInDestination(String? next) {
  if (next == '/admin' ||
      next == '/coordinator' ||
      next == '/field' ||
      next == '/map' ||
      next == '/my-reports' ||
      next == '/profile' ||
      next == '/notifications') return next!;
  if (next == 'report') return '/report/new?resume=1';
  return citizenStartLocation;
}

bool canOpenOperations(String path, String? role, {required bool enabled}) {
  if (!isOperationsPath(path)) return true;
  if (!enabled) return false;
  if (path.startsWith('/field')) return role == 'field_worker';
  return role == 'admin' || role == 'coordinator' || role == 'moderator';
}
