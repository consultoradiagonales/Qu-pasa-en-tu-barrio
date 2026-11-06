import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

/// Destino de una comunicación enviada desde el centro de gestión.
enum MessageAudience { municipality, everyone }

class MessageDispatchResult {
  const MessageDispatchResult({
    required this.total,
    this.pushed = 0,
    this.inApp = 0,
  });

  /// Personas que ya tienen el mensaje en su bandeja de la app.
  final int total;

  /// Entregas aceptadas por Firebase Cloud Messaging para mostrar fuera de la
  /// app. El servidor nunca cuenta un token ausente como una entrega push.
  final int pushed;

  /// Personas que verán el aviso únicamente al abrir ConDi.
  final int inApp;
}

abstract class AdminMessagesRepository {
  /// Deja un aviso en la bandeja de cada destinatario activo y, cuando hay un
  /// token válido, solicita el push al servidor.
  Future<MessageDispatchResult> send({
    required String title,
    required String body,
    required String senderMunicipalityId,
    required MessageAudience audience,
  });
}

class FunctionsAdminMessagesRepository implements AdminMessagesRepository {
  FunctionsAdminMessagesRepository([FirebaseFunctions? functions])
      : _functions = functions ?? FirebaseFunctions.instanceFor(
          region: 'southamerica-east1',
        );

  final FirebaseFunctions _functions;

  static const _uuid = Uuid();

  int _count(Object? value) => value is num && value >= 0 ? value.toInt() : 0;

  @override
  Future<MessageDispatchResult> send({
    required String title,
    required String body,
    required String senderMunicipalityId,
    required MessageAudience audience,
  }) async {
    if (senderMunicipalityId.isEmpty && audience == MessageAudience.municipality) {
      throw StateError('No se pudo identificar el municipio del administrador.');
    }

    final result = await _functions.httpsCallable('sendCustomMessage').call({
      'title': title,
      'body': body,
      // El identificador hace idempotente el envío si se corta la red después
      // de que el servidor haya empezado a crear avisos.
      'requestId': _uuid.v4(),
      'audience': {
        'type': audience == MessageAudience.everyone ? 'all' : 'municipality',
        if (audience == MessageAudience.municipality)
          'municipalityId': senderMunicipalityId,
      },
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return MessageDispatchResult(
      total: _count(data['total']),
      pushed: _count(data['pushed']),
      inApp: _count(data['inApp']),
    );
  }
}

final adminMessagesRepositoryProvider = Provider<AdminMessagesRepository>(
  (_) => FunctionsAdminMessagesRepository(),
);
