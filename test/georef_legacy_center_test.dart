import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:que_pasa_en_tu_barrio/data/services/georef_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('legacy La Plata resolves without GPS or network and keeps real center',
      () async {
    var requests = 0;
    final service = GeoRefService(client: MockClient((request) async {
      requests++;
      throw StateError('offline');
    }));
    for (final id in ['la-plata', 'la_plata', '06441', 'georef_06441']) {
      final point = await service.municipalityCenter(id);
      expect(point, isNotNull, reason: id);
      expect(point!.lat, closeTo(-35.0038470156373, .000001));
      expect(point.lng, closeTo(-58.0177777886065, .000001));
    }
    expect(requests, 0);
  });

  test('known official municipality has catalog reference when GeoRef fails',
      () async {
    final service =
        GeoRefService(client: MockClient((_) async => http.Response('', 503)));
    final point = await service.municipalityCenter('georef_060441');
    expect(point, isNotNull);
    expect(point!.lat, closeTo(-35.0038470156373, .000001));
    expect(await service.municipalityCenter('unknown-municipality'), isNull);
    expect(await service.municipalityCenter('999999'), isNull);
  });
}
