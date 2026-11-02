import 'package:freezed_annotation/freezed_annotation.dart';

import '../../core/logging/redaction.dart';
import 'color_info.dart';

part 'view_models.freezed.dart';

/// UI-facing result of a successful join. Never contains the browser token.
///
/// [recoveryCode] is included on purpose: the participant must see it once to
/// write it down. It is still redacted from [toString].
@freezed
class JoinOutcome with _$JoinOutcome {
  const JoinOutcome._();

  const factory JoinOutcome({
    required String participantId,
    required String recoveryCode,
    required ColorInfo myColor,
    required ColorInfo giftColor,
  }) = _JoinOutcome;

  @override
  String toString() => 'JoinOutcome(participantId: $participantId, recoveryCode: $redactedPlaceholder, '
      'myColor: $myColor, giftColor: $giftColor)';
}

/// UI-facing result of create-session. Never contains the organizer token.
@freezed
class CreatedSession with _$CreatedSession {
  const factory CreatedSession({
    required String sessionId,
    required String inviteCode,
    required String sessionName,
    required bool published,
    required List<SelectedColor> selectedColors,
  }) = _CreatedSession;
}

/// UI-facing view of a session this device organizes. Never contains the
/// organizer token.
@freezed
class OrganizerSessionSummary with _$OrganizerSessionSummary {
  const factory OrganizerSessionSummary({
    required String sessionId,
    required String inviteCode,
    required String sessionName,
    required DateTime createdAt,
  }) = _OrganizerSessionSummary;
}
