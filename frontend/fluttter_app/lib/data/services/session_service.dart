import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../models/organizer_api_models.dart';
import 'edge_functions.dart';
import 'response_parser.dart';

/// Thin typed wrapper over the organizer Edge Functions.
///
/// No storage, no navigation, no business logic. [ApiFailure]s from
/// [ApiClient] propagate unchanged; malformed 2xx bodies become a
/// `ServerFailure(INVALID_RESPONSE)`.
class SessionService {
  SessionService(this._client);

  final ApiClient _client;

  Future<ListColorsResult> listColors({CancelToken? cancelToken}) async {
    final json = await _client.post(EdgeFunctions.listColors, cancelToken: cancelToken);
    return parseResponse(EdgeFunctions.listColors, json, ListColorsResult.fromJson);
  }

  Future<CreateSessionResult> createSession({
    required String sessionName,
    required int maxParticipants,
    required List<int> allowedColors,
    CancelToken? cancelToken,
  }) async {
    final json = await _client.post(
      EdgeFunctions.createSession,
      body: {
        'sessionName': sessionName,
        'maxParticipants': maxParticipants,
        'allowedColors': allowedColors,
      },
      cancelToken: cancelToken,
    );
    return parseResponse(EdgeFunctions.createSession, json, CreateSessionResult.fromJson);
  }

  Future<SessionInfo> publishSession({
    required String sessionId,
    required String organizerToken,
    CancelToken? cancelToken,
  }) async {
    final json = await _client.post(
      EdgeFunctions.publishSession,
      body: _organizerBody(sessionId, organizerToken),
      cancelToken: cancelToken,
    );
    return parseResponse(EdgeFunctions.publishSession, json, SessionInfo.fromJson);
  }

  Future<ParticipantList> getParticipants({
    required String sessionId,
    required String organizerToken,
    CancelToken? cancelToken,
  }) async {
    final json = await _client.post(
      EdgeFunctions.getParticipants,
      body: _organizerBody(sessionId, organizerToken),
      cancelToken: cancelToken,
    );
    return parseResponse(EdgeFunctions.getParticipants, json, ParticipantList.fromJson);
  }

  Future<ClosedSession> closeSession({
    required String sessionId,
    required String organizerToken,
    CancelToken? cancelToken,
  }) async {
    final json = await _client.post(
      EdgeFunctions.closeSession,
      body: _organizerBody(sessionId, organizerToken),
      cancelToken: cancelToken,
    );
    return parseResponse(EdgeFunctions.closeSession, json, ClosedSession.fromJson);
  }

  static Map<String, Object?> _organizerBody(String sessionId, String organizerToken) => {
        'sessionId': sessionId,
        'organizerToken': organizerToken,
      };
}
