import 'package:freezed_annotation/freezed_annotation.dart';

part 'organizer_session.freezed.dart';
part 'organizer_session.g.dart';

/// A session this device organizes (secure storage key
/// `ssw.v1.organizer_sessions`, stored as a list). Written right after
/// create-session succeeds. Losing [organizerToken] means the session can no
/// longer be published or closed.
@freezed
class OrganizerSession with _$OrganizerSession {
  const OrganizerSession._();

  const factory OrganizerSession({
    required String sessionId,
    required String organizerToken,
    required String inviteCode,
    required String sessionName,
    required DateTime createdAt,
  }) = _OrganizerSession;

  factory OrganizerSession.fromJson(Map<String, dynamic> json) => _$OrganizerSessionFromJson(json);

  /// Never includes the organizer token.
  @override
  String toString() => 'OrganizerSession(sessionId: $sessionId, sessionName: $sessionName)';
}
