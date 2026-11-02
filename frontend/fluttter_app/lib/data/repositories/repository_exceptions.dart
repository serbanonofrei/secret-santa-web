import '../../core/logging/redaction.dart';
import '../models/view_models.dart';

/// No participant identity is stored on this device.
class NoParticipantIdentityException implements Exception {
  const NoParticipantIdentityException();

  @override
  String toString() => 'NoParticipantIdentityException: no participant identity stored on this device';
}

/// This device holds no organizer token for [sessionId].
class UnknownOrganizerSessionException implements Exception {
  const UnknownOrganizerSessionException(this.sessionId);

  final String sessionId;

  @override
  String toString() => 'UnknownOrganizerSessionException: no organizer token stored for session $sessionId';
}

/// The server call succeeded but saving the identity to secure storage failed.
///
/// The server-side state already exists (participant joined / session created),
/// so the caller must NOT treat this as a plain failure and retry the API call
/// (that would create a duplicate participant or session).
sealed class IdentityPersistenceException implements Exception {
  const IdentityPersistenceException(this.cause);

  /// The underlying storage error (e.g. SecureStorageException).
  final Object cause;
}

/// join-session succeeded, saving the participant identity failed.
///
/// [outcome] carries the recovery code so the UI can show it: the participant
/// can still get back in with recover-assignment once storage works again.
final class ParticipantNotSavedException extends IdentityPersistenceException {
  const ParticipantNotSavedException(this.outcome, super.cause);

  final JoinOutcome outcome;

  @override
  String toString() => 'ParticipantNotSavedException(participantId: ${outcome.participantId}, '
      'recoveryCode: $redactedPlaceholder): $cause';
}

/// recover-assignment succeeded, saving the participant identity failed.
/// Safe to simply retry recovery: it is read-only on the server.
final class RecoveryNotSavedException extends IdentityPersistenceException {
  const RecoveryNotSavedException(super.cause);

  @override
  String toString() => 'RecoveryNotSavedException: $cause';
}

/// create-session succeeded, saving the organizer session failed.
///
/// The repository keeps the session (with its token) in memory; call
/// `OrganizerRepository.retrySavePendingSession()` to try again. If the app is
/// closed first, the organizer token is lost.
final class OrganizerSessionNotSavedException extends IdentityPersistenceException {
  const OrganizerSessionNotSavedException(this.session, super.cause);

  /// UI-safe view (no organizer token).
  final CreatedSession session;

  @override
  String toString() => 'OrganizerSessionNotSavedException(sessionId: ${session.sessionId}): $cause';
}
