import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_ad.dart';

class LocalAdsRepository {
  LocalAdsRepository(this._functions);

  final FirebaseFunctions _functions;

  Future<void> save({
    String? adId,
    required String municipalityId,
    required String business,
    required String message,
    required String imageUrl,
    required String link,
    required DateTime startsAt,
    required DateTime endsAt,
    required bool active,
    required LocalAdDismissMode dismissMode,
  }) async {
    await _functions.httpsCallable('saveLocalAd').call({
      if (adId != null) 'adId': adId,
      'municipalityId': municipalityId,
      'business': business,
      'message': message,
      'imageUrl': imageUrl,
      'link': link,
      'startsAt': startsAt.millisecondsSinceEpoch,
      'endsAt': endsAt.millisecondsSinceEpoch,
      'active': active,
      'dismissMode': dismissMode.value,
    });
  }
}

final localAdsRepositoryProvider = Provider<LocalAdsRepository>((_) {
  return LocalAdsRepository(FirebaseFunctions.instanceFor(
    region: 'southamerica-east1',
  ));
});
