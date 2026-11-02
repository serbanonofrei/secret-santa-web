import 'package:freezed_annotation/freezed_annotation.dart';

import '../../core/logging/redaction.dart';
import 'color_info.dart';

part 'participant_api_models.freezed.dart';
part 'participant_api_models.g.dart';

/// join-session response.
///
/// Contains the browser token: only services and [ParticipantRepository] may
/// hold this type. UI code receives `JoinOutcome` instead.
@freezed
class JoinResult with _$JoinResult {
  const JoinResult._();

  const factory JoinResult({
    required String participantId,
    required String browserToken,
    required String recoveryCode,
    required ColorInfo myColor,
    required ColorInfo giftColor,
  }) = _JoinResult;

  factory JoinResult.fromJson(Map<String, dynamic> json) => _$JoinResultFromJson(json);

  @override
  String toString() => 'JoinResult(participantId: $participantId, browserToken: $redactedPlaceholder, '
      'recoveryCode: $redactedPlaceholder, myColor: $myColor, giftColor: $giftColor)';
}

/// get-my-assignment response. Also the UI-facing result of a recovery.
@freezed
class Assignment with _$Assignment {
  const factory Assignment({
    required String participantId,
    required String participantName,
    required ColorInfo myColor,
    required ColorInfo giftColor,
  }) = _Assignment;

  factory Assignment.fromJson(Map<String, dynamic> json) => _$AssignmentFromJson(json);
}

/// recover-assignment response.
///
/// Contains the browser token: only services and [ParticipantRepository] may
/// hold this type. UI code receives an [Assignment] instead.
@freezed
class RecoveredAssignment with _$RecoveredAssignment {
  const RecoveredAssignment._();

  const factory RecoveredAssignment({
    required String participantId,
    required String participantName,
    required String browserToken,
    required ColorInfo myColor,
    required ColorInfo giftColor,
  }) = _RecoveredAssignment;

  factory RecoveredAssignment.fromJson(Map<String, dynamic> json) => _$RecoveredAssignmentFromJson(json);

  @override
  String toString() => 'RecoveredAssignment(participantId: $participantId, participantName: $participantName, '
      'browserToken: $redactedPlaceholder, myColor: $myColor, giftColor: $giftColor)';
}
