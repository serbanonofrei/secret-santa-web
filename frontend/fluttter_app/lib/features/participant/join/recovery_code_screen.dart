import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/recovery_code_display.dart';
import 'join_controller.dart';

/// `/join/recovery-code`: shown once, right after a successful join.
///
/// Reads the [JoinSucceeded] outcome from [joinControllerProvider]. The
/// recovery code is shown in BOTH cases:
/// * saved on device: "I saved my recovery code" -> `/assignment`.
/// * NOT saved (ParticipantNotSavedException): warning + participant id;
///   "Continue" -> `/welcome`. Never offers to join again: the participant
///   already exists, the recovery code is the way back in.
///
/// The screen never navigates itself: the router guard does, from the join
/// and startup state. Without a pending join (browser refresh, hot restart,
/// deep link) the guard redirects to `/join` before this screen is built; the
/// fallback below only covers the frame in which that redirect runs.
class RecoveryCodeScreen extends ConsumerStatefulWidget {
  const RecoveryCodeScreen({super.key});

  @override
  ConsumerState<RecoveryCodeScreen> createState() => _RecoveryCodeScreenState();
}

class _RecoveryCodeScreenState extends ConsumerState<RecoveryCodeScreen> {
  bool _confirming = false;

  /// The outcome this screen was opened for. Kept so the code stays on screen
  /// while confirming: the controller resets to idle before the router has
  /// finished moving to `/assignment`.
  JoinSucceeded? _shown;

  Future<void> _confirm() async {
    setState(() => _confirming = true);
    await ref.read(joinControllerProvider.notifier).confirmRecoveryCodeSaved();
    // On success the router replaces this screen. If confirming did not
    // complete (storage error), re-enable the button.
    if (mounted) setState(() => _confirming = false);
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(joinControllerProvider);
    if (current is JoinSucceeded) _shown = current;
    final state = _shown;
    final theme = Theme.of(context);

    if (state == null) {
      // No outcome: the router guard is redirecting to /join. Never crash,
      // never show an empty code.
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return PopScope(
      // Leaving without confirming would skip the "write it down" step.
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text(state.savedOnDevice ? "You're in!" : 'Joined, but not saved'),
          automaticallyImplyLeading: false,
        ),
        body: FormColumn(
          children: [
            if (!state.savedOnDevice) ...[
              const _NotSavedWarning(),
              const SizedBox(height: 24),
            ],
            Text('Your recovery code', textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            RecoveryCodeDisplay(code: state.outcome.recoveryCode),
            const SizedBox(height: 16),
            Text(
              'Write this code down or save it somewhere safe. '
              'You need it to see your assignment on another device or if this device loses its data. '
              'Anyone with this code can see your assignment, so keep it private.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            if (!state.savedOnDevice) ...[
              const SizedBox(height: 16),
              Text(
                'Participant ID: ${state.outcome.participantId}',
                key: const Key('participantIdText'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 32),
            SubmitButton(
              label: state.savedOnDevice ? 'I saved my recovery code' : 'Continue',
              busy: _confirming,
              onPressed: _confirm,
            ),
          ],
        ),
      ),
    );
  }
}

class _NotSavedWarning extends StatelessWidget {
  const _NotSavedWarning();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const Key('notSavedWarning'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber, color: scheme.onTertiaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Your participation was created but could not be saved on this device. '
                'Keep your recovery code: use "Recover Assignment" to see your assignment.',
                style: TextStyle(color: scheme.onTertiaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
