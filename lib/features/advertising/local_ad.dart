import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum LocalAdDismissMode {
  closeNow('close_now', 'Cierre inmediato'),
  waitSevenSeconds('wait_7_seconds', 'Cerrar luego de 7 segundos');

  const LocalAdDismissMode(this.value, this.label);
  final String value;
  final String label;

  static LocalAdDismissMode fromValue(Object? value) {
    return value == waitSevenSeconds.value
        ? waitSevenSeconds
        : closeNow;
  }
}

class LocalAd {
  const LocalAd({
    required this.id,
    required this.municipalityId,
    required this.business,
    required this.message,
    required this.imageUrl,
    required this.link,
    required this.startsAt,
    required this.endsAt,
    required this.active,
    required this.dismissMode,
  });

  final String id, municipalityId, business, message, imageUrl, link;
  final DateTime startsAt, endsAt;
  final bool active;
  final LocalAdDismissMode dismissMode;

  int get dismissDelaySeconds =>
      dismissMode == LocalAdDismissMode.waitSevenSeconds ? 7 : 0;

  bool visibleAt(DateTime now) => active && !now.isBefore(startsAt) && now.isBefore(endsAt);

  static bool validLink(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty && uri.userInfo.isEmpty;
  }

  static DateTime _date(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  factory LocalAd.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return LocalAd(
      id: doc.id,
      municipalityId: d['municipalityId'] as String? ?? '',
      business: d['business'] as String? ?? '',
      message: d['message'] as String? ?? '',
      imageUrl: d['imageUrl'] as String? ?? '',
      link: d['link'] as String? ?? '',
      startsAt: _date(d['startsAt']),
      endsAt: _date(d['endsAt']),
      active: d['active'] != false,
      dismissMode: LocalAdDismissMode.fromValue(d['dismissMode']),
    );
  }
}
final localAdsProvider = StreamProvider.family<List<LocalAd>, String>((ref, municipality) => FirebaseFirestore.instance.collection('localAds').where('municipalityId', isEqualTo: municipality).where('active', isEqualTo: true).limit(50).snapshots().map((s) => s.docs.map(LocalAd.fromDoc).toList()));
final managedAdsProvider = StreamProvider.family<List<LocalAd>, String>((ref, municipality) => FirebaseFirestore.instance.collection('localAds').where('municipalityId', isEqualTo: municipality).limit(100).snapshots().map((s) => s.docs.map(LocalAd.fromDoc).toList()));
