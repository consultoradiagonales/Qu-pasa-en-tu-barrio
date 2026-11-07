import 'package:flutter_test/flutter_test.dart';
import 'package:que_pasa_en_tu_barrio/features/advertising/local_ad.dart';

void main() {
  final start = DateTime.utc(2026, 10, 11), end = DateTime.utc(2026, 11, 11);
  LocalAd ad(bool active) => LocalAd(
      id: 'a',
      municipalityId: '060707',
      business: 'Comercio',
      message: 'Oferta',
      imageUrl: '',
      link: 'https://example.com',
      startsAt: start,
      endsAt: end,
      active: active,
      dismissMode: LocalAdDismissMode.closeNow);
  test('vigencia incluye inicio y excluye fin', () {
    expect(
        ad(true).visibleAt(start.subtract(const Duration(seconds: 1))), false);
    expect(ad(true).visibleAt(start), true);
    expect(ad(true).visibleAt(end), false);
    expect(ad(false).visibleAt(start), false);
  });
  test('anuncios solo abren enlaces HTTPS sin credenciales', () {
    expect(LocalAd.validLink('https://wa.me/549123456789'), true);
    for (final value in [
      'javascript:alert(1)',
      'file:///tmp/a',
      'http://example.com',
      'https://',
      'https://user:password@example.com'
    ]) {
      expect(LocalAd.validLink(value), false);
    }
  });
}
