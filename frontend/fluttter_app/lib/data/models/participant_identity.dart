import 'package:freezed_annotation/freezed_annotation.dart';

part 'participant_identity.freezed.dart';
part 'participant_identity.g.dart';

/// The participant identity stored on this device (secure storage key
/// `ssw.v1.participant`). Written after join-session or recover-assignment.
@freezed
class ParticipantCredentials with _$ParticipantCredentials {
  const ParticipantCredentials._();

  const factory ParticipantCredentials({
    required String participantId,
    required String browserToken,
    String? recoveryCode,
    String? participantName,
    required DateTime savedAt,
  }) = _ParticipantCredentials;

  factory ParticipantCredentials.fromJson(Map<String, dynamic> json) =>
      _$ParticipantCredentialsFromJson(json);

  /// Never includes the browser token or recovery code.
  @override
  String toString() => 'ParticipantCredentials(participantId: $participantId, savedAt: $savedAt)';
}
