import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/validation/validators.dart';
import '../../../data/data_providers.dart';
import '../../../shared/errors/failure_messages.dart';
import '../../startup/startup_controller.dart';

// =============================================================================
// State
// =============================================================================

sealed class RecoverState {
  const RecoverState();
}

final class RecoverIdle extends RecoverState {
  const RecoverIdle();
}

final class RecoverSubmitting extends RecoverState {
  const RecoverSubmitting();
}

/// The identity is stored; the router moves on to `/assignment`.
final class RecoverSucceeded extends RecoverState {
  const RecoverSucceeded();
}

final class RecoverFailed extends RecoverState {
  const RecoverFailed(this.feedback);

  final FailureFeedback feedback;
}

// =============================================================================
// Controller
// =============================================================================

/// Recovery flow: validate -> recover-assignment -> identity stored ->
/// startup state becomes participant -> router shows `/assignment`.
///
/// Recovery is read-only on the server, so every failure (including
/// RecoveryNotSavedException) can simply be retried.
class RecoverController extends AutoDisposeNotifier<RecoverState> {
  @override
  RecoverState build() => const RecoverIdle();

  Future<void> submit(String recoveryCode) async {
    if (state is RecoverSubmitting) return;

    final code = formatRecoveryCode(recoveryCode);
    if (validateRecoveryCode(code) case final error?) {
      state = RecoverFailed(FailureFeedback(fieldErrors: {'recoveryCode': error}));
      return;
    }

    state = const RecoverSubmitting();
    try {
      await ref.read(participantRepositoryProvider).recoverAssignment(recoveryCode: code);
    } on Exception catch (e) {
      state = RecoverFailed(recoverFailureFeedback(e));
      return;
    }

    state = const RecoverSucceeded();
    await ref.read(startupControllerProvider.notifier).syncFromStorage();
  }

  void clearError() {
    if (state is RecoverFailed) state = const RecoverIdle();
  }
}

final recoverControllerProvider = NotifierProvider.autoDispose<RecoverController, RecoverState>(
  RecoverController.new,
  name: 'recoverControllerProvider',
);
