import 'participant_identity.dart';

/// Who the user is on this device, from the participant point of view.
///
/// "Not loaded yet" is not a state here: it is `AsyncLoading` of the
/// `AsyncValue<AppSession>` exposed by the startup controller.
///
/// Organizer sessions are tracked separately; one person can be both a
/// participant and an organizer.
sealed class AppSession {
  const AppSession();
}

/// No participant credentials on this device: show Join / Recover.
final class AnonymousSession extends AppSession {
  const AnonymousSession();

  @override
  bool operator ==(Object other) => other is AnonymousSession;

  @override
  int get hashCode => (AnonymousSession).hashCode;

  @override
  String toString() => 'AnonymousSession()';
}

/// Participant credentials found on this device.
final class ParticipantSession extends AppSession {
  const ParticipantSession(this.credentials);

  final ParticipantCredentials credentials;

  @override
  bool operator ==(Object other) => other is ParticipantSession && other.credentials == credentials;

  @override
  int get hashCode => credentials.hashCode;

  @override
  String toString() => 'ParticipantSession($credentials)';
}
