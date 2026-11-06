import 'package:que_pasa_en_tu_barrio/core/services/push_token_registrar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PushTokenRegistrar build({
    required Future<String?> Function() getToken,
    required Future<void> Function(String, String) saveToken,
    Future<void> Function()? ensurePermission,
    List<String>? logs,
  }) =>
      PushTokenRegistrar(
        getToken: getToken,
        saveToken: saveToken,
        ensurePermission: ensurePermission,
        retryDelays: const [Duration.zero, Duration.zero],
        log: (m) => logs?.add(m),
      );

  test('guarda el token aunque el permiso falle', () async {
    String? saved;
    final logs = <String>[];
    final ok = await build(
      getToken: () async => 'tok',
      saveToken: (uid, t) async => saved = '$uid:$t',
      ensurePermission: () async => throw StateError('sin actividad'),
      logs: logs,
    ).register('u1');
    expect(ok, isTrue);
    expect(saved, 'u1:tok');
    expect(logs.any((l) => l.contains('permiso')), isTrue);
  });

  test('solicita el permiso antes de obtener el token', () async {
    final events = <String>[];
    final ok = await build(
      ensurePermission: () async => events.add('permission'),
      getToken: () async {
        events.add('token');
        return 'tok';
      },
      saveToken: (_, __) async => events.add('save'),
    ).register('u1');
    expect(ok, isTrue);
    expect(events, ['permission', 'token', 'save']);
  });

  test('reintenta cuando falla guardar (doc de usuario aun no creado)', () async {
    var calls = 0;
    final logs = <String>[];
    final ok = await build(
      getToken: () async => 'tok',
      saveToken: (_, __) async {
        if (++calls < 3) throw StateError('not-found');
      },
      logs: logs,
    ).register('u1');
    expect(ok, isTrue);
    expect(calls, 3);
    expect(logs.where((l) => l.contains('no se pudo registrar')).length, 2);
  });

  test('token nulo o error de getToken: reintenta, loguea y devuelve false',
      () async {
    var calls = 0;
    final logs = <String>[];
    final ok = await build(
      getToken: () async {
        calls++;
        return calls == 1 ? null : throw StateError('SERVICE_NOT_AVAILABLE');
      },
      saveToken: (_, __) async => fail('no debe guardar'),
      logs: logs,
    ).register('u1');
    expect(ok, isFalse);
    expect(calls, 3);
    expect(logs.any((l) => l.contains('SERVICE_NOT_AVAILABLE')), isTrue);
  });

  test('llamadas simultaneas para el mismo uid comparten ejecucion', () async {
    var calls = 0;
    final r = build(
      getToken: () async {
        calls++;
        return 'tok';
      },
      saveToken: (_, __) async {},
    );
    await Future.wait([r.register('u1'), r.register('u1')]);
    expect(calls, 1);
  });
}
