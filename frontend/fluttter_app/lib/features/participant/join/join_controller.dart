import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/route_guard.dart';
import '../../../core/validation/validators.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/app_session.dart';
import '../../../data/models/view_models.dart';
import '../../../data/repositories/repository_exceptions.dart';
import '../../../shared/errors/failure_messages.dart';
import '../../startup/startup_controller.dart';

// =============================================================================
// State
// =============================================================================

sealed class JoinState {
  const JoinState();
}

final class JoinIdle extends JoinState {
  const JoinIdle();
}

final class JoinSubmitting extends JoinState {
  const JoinSubmitting();
}

/// The participant exists on the server.
///
/// [savedOnDevice] is false when join succeeded but secure storage failed
/// (ParticipantNotSavedException): the recovery code is then the ONLY way back.
final class JoinSucceeded extends JoinState {
  const JoinSucceeded({required this.outcome, required this.savedOnDevice});

  final JoinOutcome outcome;
  final bool savedOnDevice;
}

/// Join was rejected (locally or by the server). Nothing exists on the server
/// that would be duplicated by trying again.
final class JoinFailed extends JoinState {
  const JoinFailed(this.feedback);

  final FailureFeedback feedback;
}

/// The user confirmed the code of a join that could NOT be saved on this
/// device. Routing sends them to `/welcome`; the join form is not reachable
/// with this result until the next visit to `/join` resets it.
final class JoinFinishedUnsaved extends JoinState {
  const JoinFinishedUnsaved();
}

/// Join flow status for the router guard.
JoinFlowStatus joinFlowStatusOf(JoinState state) => switch (state) {
      JoinSucceeded() => JoinFlowStatus.pending,
      JoinFinishedUnsaved() => JoinFlowStatus.finishedUnsaved,
      JoinIdle() || JoinSubmitting() || JoinFailed() => JoinFlowStatus.none,
    };

// =============================================================================
// Controller
// =============================================================================

/// Join flow: validate -> join-session -> show recovery code -> confirm.
///
/// Kept alive (not auto-dispose) so the recovery code screen can read the
/// [JoinSucceeded] outcome after navigation; [reset] clears it.
class JoinController extends Notifier<JoinState> {
  @override
  JoinState build() {
    // A saved join is complete as soon as the identity is visible as a
    // participant, however that happened (confirm button, or a storage retry
    // after a failed confirm). Without this, a pending join would outlive the
    // participant state and resurface after "leave this device".
    ref.listen<AsyncValue<AppSession>>(startupControllerProvider, (_, next) {
      final current = state;
      if (current is JoinSucceeded && current.savedOnDevice && next.valueOrNull is ParticipantSession) {
        state = const JoinIdle();
      }
    });
    return const JoinIdle();
  }

  Future<void> submit({required String inviteCode, required String participantName}) async {
    if (state is JoinSubmitting) return;

    final code = normalizeInviteCode(inviteCode);
    final name = normalizeParticipantName(participantName);

    final fieldErrors = <String, String>{
      if (validateInviteCode(code) case final error?) 'inviteCode': error,
      if (validateParticipantName(name) case final error?) 'participantName': error,
    };
    if (fieldErrors.isNotEmpty) {
      state = JoinFailed(FailureFeedback(fieldErrors: fieldErrors));
      return;
    }

    state = const JoinSubmitting();
    try {
      final outcome = await ref.read(participantRepositoryProvider).joinSession(
            inviteCode: code,
            participantName: name,
          );
      state = JoinSucceeded(outcome: outcome, savedOnDevice: true);
    } on ParticipantNotSavedException catch (e) {
      // The participant EXISTS on the server: never offer a retry of the join.
      state = JoinSucceeded(outcome: e.outcome, savedOnDevice: false);
    } on Exception catch (e) {
      state = JoinFailed(joinFailureFeedback(e));
    }
  }

  /// "I saved my recovery code".
  ///
  /// * Saved on device: re-reads storage. Only when that yields a participant
  ///   is the join flow closed; the router then moves to `/assignment`. If the
  ///   read fails (storage error) or finds nothing, the flow stays pending so
  ///   the recovery code is NOT lost: the router shows the splash screen with
  ///   retry, then returns to the code screen.
  /// * Not saved: closes the flow as [JoinFinishedUnsaved]; the router moves
  ///   to `/welcome`.
  Future<void> confirmRecoveryCodeSaved() async {
    final current = state;
    if (current is! JoinSucceeded) return;

    if (!current.savedOnDevice) {
      state = const JoinFinishedUnsaved();
      return;
    }

    final session = await ref.read(startupControllerProvider.notifier).syncFromStorage();
    // Only close the flow we confirmed (not a newer one) and only once the
    // identity is really visible to the router.
    if (identical(state, current) && session.valueOrNull is ParticipantSession) {
      state = const JoinIdle();
    }
  }

  /// Clears a field error once the user edits that field.
  void clearFieldError(String field) {
    final current = state;
    if (current is! JoinFailed || !current.feedback.fieldErrors.containsKey(field)) return;
    final remaining = {...current.feedback.fieldErrors}..remove(field);
    state = remaining.isEmpty && current.feedback.message == null
        ? const JoinIdle()
        : JoinFailed(FailureFeedback(message: current.feedback.message, fieldErrors: remaining));
  }

  /// Clears errors and a finished-unsaved result. A pending join is never
  /// discarded here: its recovery code must be confirmed first.
  void reset() {
    if (state is JoinFailed || state is JoinFinishedUnsaved) state = const JoinIdle();
  }
}

final joinControllerProvider = NotifierProvider<JoinController, JoinState>(
  JoinController.new,
  name: 'joinControllerProvider',
);
