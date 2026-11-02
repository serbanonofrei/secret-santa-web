import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../models/participant_api_models.dart';
import 'edge_functions.dart';
import 'response_parser.dart';

/// Thin typed wrapper over the participant Edge Functions.
///
/// No storage, no navigation, no business logic. [ApiFailure]s from
/// [ApiClient] propagate unchanged; malformed 2xx bodies become a
/// `ServerFailure(INVALID_RESPONSE)`.
class ParticipantService {
  ParticipantService(this._client);

  final ApiClient _client;

  Future<JoinResult> joinSession({
    required String inviteCode,
    required String participantName,
    CancelToken? cancelToken,
  }) async {
    final json = await _client.post(
      EdgeFunctions.joinSession,
      body: {'inviteCode': inviteCode, 'participantName': participantName},
      cancelToken: cancelToken,
    );
    return parseResponse(EdgeFunctions.joinSession, json, JoinResult.fromJson);
  }

  Future<Assignment> getMyAssignment({
    required String browserToken,
    CancelToken? cancelToken,
  }) async {
    final json = await _client.post(
      EdgeFunctions.getMyAssignment,
      body: {'browserToken': browserToken},
      cancelToken: cancelToken,
    );
    return parseResponse(EdgeFunctions.getMyAssignment, json, Assignment.fromJson);
  }

  Future<RecoveredAssignment> recoverAssignment({
    required String recoveryCode,
    CancelToken? cancelToken,
  }) async {
    final json = await _client.post(
      EdgeFunctions.recoverAssignment,
      body: {'recoveryCode': recoveryCode},
      cancelToken: cancelToken,
    );
    return parseResponse(EdgeFunctions.recoverAssignment, json, RecoveredAssignment.fromJson);
  }
}
