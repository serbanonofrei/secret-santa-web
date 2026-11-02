import 'package:dio/dio.dart';

import '../../core/storage/identity_store.dart';
import '../models/participant_api_models.dart';
import '../models/participant_identity.dart';
import '../models/view_models.dart';
import '../services/participant_service.dart';
import 'repository_exceptions.dart';

/// Participant use cases: API call + identity persistence.
///
/// * The ONLY place that writes the participant identity (via
///   [CredentialStore], never SecureStorage directly).
/// * Never returns the browser token to callers.
/// * [ApiFailure]s propagate unchanged. Deciding whether to clear stored
///   credentials after a 404/403 is the caller's policy (startup controller).
class ParticipantRepository {
  ParticipantRepository({
    required ParticipantService service,
    required CredentialStore store,
    DateTime Function()? clock,
  })  : _service = service,
        _store = store,
        _clock = clock ?? DateTime.now;

  final ParticipantService _service;
  final CredentialStore _store;
  final DateTime Function() _clock;

  /// Joins a session and stores the new identity.
  ///
  /// Throws:
  /// * [ApiFailure] if the server rejects the join (nothing stored).
  /// * [ParticipantNotSavedException] if the join succeeded but storing failed.
  Future<JoinOutcome> joinSession({
    required String inviteCode,
    required String participantName,
    CancelToken? cancelToken,
  }) async {
    final JoinResult result = await _service.joinSession(
      inviteCode: inviteCode,
      participantName: participantName,
      cancelToken: cancelToken,
    );

    final outcome = JoinOutcome(
      participantId: result.participantId,
      recoveryCode: result.recoveryCode,
      myColor: result.myColor,
      giftColor: result.giftColor,
    );

    try {
      await _store.saveParticipant(
        ParticipantCredentials(
          participantId: result.participantId,
          browserToken: result.browserToken,
          recoveryCode: result.recoveryCode,
          participantName: participantName,
          savedAt: _clock().toUtc(),
        ),
      );
    } on Object catch (e) {
      throw ParticipantNotSavedException(outcome, e);
    }

    return outcome;
  }

  /// Recovers an identity with a recovery code and stores it.
  ///
  /// Throws:
  /// * [ApiFailure] if the code is rejected (nothing stored).
  /// * [RecoveryNotSavedException] if recovery succeeded but storing failed.
  Future<Assignment> recoverAssignment({
    required String recoveryCode,
    CancelToken? cancelToken,
  }) async {
    final RecoveredAssignment result = await _service.recoverAssignment(
      recoveryCode: recoveryCode,
      cancelToken: cancelToken,
    );

    try {
      await _store.saveParticipant(
        ParticipantCredentials(
          participantId: result.participantId,
          browserToken: result.browserToken,
          recoveryCode: recoveryCode,
          participantName: result.participantName,
          savedAt: _clock().toUtc(),
        ),
      );
    } on Object catch (e) {
      throw RecoveryNotSavedException(e);
    }

    return Assignment(
      participantId: result.participantId,
      participantName: result.participantName,
      myColor: result.myColor,
      giftColor: result.giftColor,
    );
  }

  /// Loads the assignment for the identity stored on this device.
  ///
  /// Throws:
  /// * [NoParticipantIdentityException] if nothing is stored (no API call).
  /// * [ApiFailure] from the server, unchanged. Stored data is NOT modified.
  Future<Assignment> getMyAssignment({CancelToken? cancelToken}) async {
    final credentials = await _store.readParticipant();
    if (credentials == null) throw const NoParticipantIdentityException();

    return _service.getMyAssignment(
      browserToken: credentials.browserToken,
      cancelToken: cancelToken,
    );
  }

  /// Recovery code stored on this device, for "show my recovery code".
  Future<String?> storedRecoveryCode() async => (await _store.readParticipant())?.recoveryCode;

  /// Removes the identity from this device ("leave this device", or after the
  /// server reported it invalid). Does not contact the server.
  Future<void> clearIdentity() => _store.clearParticipant();
}
