import 'package:freezed_annotation/freezed_annotation.dart';

import '../../core/logging/redaction.dart';
import 'color_info.dart';
import 'session_status.dart';

part 'organizer_api_models.freezed.dart';
part 'organizer_api_models.g.dart';

/// list-colors response: `{ colors: [...] }`.
@freezed
class ListColorsResult with _$ListColorsResult {
  const factory ListColorsResult({
    required List<CatalogColor> colors,
  }) = _ListColorsResult;

  factory ListColorsResult.fromJson(Map<String, dynamic> json) => _$ListColorsResultFromJson(json);
}

/// create-session response.
///
/// Contains the organizer token: only services and [OrganizerRepository] may
/// hold this type. UI code receives `CreatedSession` instead.
@freezed
class CreateSessionResult with _$CreateSessionResult {
  const CreateSessionResult._();

  const factory CreateSessionResult({
    required String sessionId,
    required String inviteCode,
    required String organizerToken,
    required bool published,
    required List<SelectedColor> selectedColors,
  }) = _CreateSessionResult;

  factory CreateSessionResult.fromJson(Map<String, dynamic> json) => _$CreateSessionResultFromJson(json);

  @override
  String toString() => 'CreateSessionResult(sessionId: $sessionId, inviteCode: $inviteCode, '
      'organizerToken: $redactedPlaceholder, published: $published, selectedColors: $selectedColors)';
}

/// publish-session response.
@freezed
class SessionInfo with _$SessionInfo {
  const factory SessionInfo({
    required String sessionId,
    required String sessionName,
    required String inviteCode,
    required int maxParticipants,
    @JsonKey(unknownEnumValue: SessionStatus.unknown) required SessionStatus status,
    required bool published,
    required bool draft,
    required int colorCount,
  }) = _SessionInfo;

  factory SessionInfo.fromJson(Map<String, dynamic> json) => _$SessionInfoFromJson(json);
}

/// get-participants `participants` entry.
@freezed
class ParticipantSummary with _$ParticipantSummary {
  const factory ParticipantSummary({
    required String participantId,
    required String participantName,
  }) = _ParticipantSummary;

  factory ParticipantSummary.fromJson(Map<String, dynamic> json) => _$ParticipantSummaryFromJson(json);
}

/// get-participants response. Participants are already sorted by the server.
@freezed
class ParticipantList with _$ParticipantList {
  const factory ParticipantList({
    required String sessionId,
    required String sessionName,
    @JsonKey(unknownEnumValue: SessionStatus.unknown) required SessionStatus status,
    required bool published,
    required int joinedCount,
    required int maxParticipants,
    required List<ParticipantSummary> participants,
  }) = _ParticipantList;

  factory ParticipantList.fromJson(Map<String, dynamic> json) => _$ParticipantListFromJson(json);
}

/// close-session response.
@freezed
class ClosedSession with _$ClosedSession {
  const factory ClosedSession({
    required String sessionId,
    @JsonKey(unknownEnumValue: SessionStatus.unknown) required SessionStatus status,
    required bool published,
    required String sessionName,
  }) = _ClosedSession;

  factory ClosedSession.fromJson(Map<String, dynamic> json) => _$ClosedSessionFromJson(json);
}
