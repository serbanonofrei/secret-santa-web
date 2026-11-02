import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/participant_api_models.dart';
import '../../../shared/errors/failure_messages.dart';
import '../../../shared/widgets/color_swatch_card.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/recovery_code_display.dart';
import 'assignment_controller.dart';

/// `/assignment`. Navigation after "Leave this device" is done by the router
/// guard (startup state becomes anonymous).
class AssignmentScreen extends ConsumerWidget {
  const AssignmentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(assignmentControllerProvider);
    final controller = ref.read(assignmentControllerProvider.notifier);

    // A failed REFRESH keeps the assignment on screen; report the error as a
    // temporary message instead of replacing the content.
    ref.listen<AsyncValue<Assignment>>(assignmentControllerProvider, (previous, next) {
      final failedRefresh = next.hasError && !next.isLoading && next.hasValue;
      final isNewError = previous == null || !previous.hasError || previous.isLoading;
      if (failedRefresh && isNewError) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              key: const Key('refreshErrorSnackBar'),
              content: Text("Couldn't refresh. ${assignmentFailureMessage(next.error!)}"),
            ),
          );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Secret Santa'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: state.isLoading ? null : controller.refresh,
          ),
          PopupMenuButton<_MenuAction>(
            key: const Key('assignmentMenu'),
            tooltip: 'More',
            onSelected: (action) => switch (action) {
              _MenuAction.showRecoveryCode => _showRecoveryCode(context, controller),
              _MenuAction.leaveDevice => _confirmLeave(context, controller),
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: _MenuAction.showRecoveryCode, child: Text('Show Recovery Code')),
              PopupMenuItem(value: _MenuAction.leaveDevice, child: Text('Leave This Device')),
            ],
          ),
        ],
      ),
      body: switch (state) {
        AsyncValue(:final value?) => RefreshIndicator(
            onRefresh: controller.refresh,
            child: _AssignmentView(assignment: value, refreshing: state.isLoading),
          ),
        AsyncValue(:final error?) => _ErrorView(
            error: error,
            onRetry: controller.refresh,
            onLeave: () => _confirmLeave(context, controller),
          ),
        _ => const Center(child: CircularProgressIndicator(semanticsLabel: 'Loading your assignment')),
      },
    );
  }

  static Future<void> _showRecoveryCode(BuildContext context, AssignmentController controller) async {
    final code = await controller.storedRecoveryCode();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your recovery code'),
        content: code == null
            ? const Text('No recovery code is saved on this device.')
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RecoveryCodeDisplay(code: code),
                  const SizedBox(height: 12),
                  const Text('Use it to see your assignment on another device. Keep it private.'),
                ],
              ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
      ),
    );
  }

  static Future<void> _confirmLeave(BuildContext context, AssignmentController controller) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave this device?'),
        content: const Text(
          'This removes your local identity from this device. '
          'It does not remove you from the session. '
          'You can come back later with your recovery code.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('confirmLeaveButton'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await controller.leaveDevice();
    } on Exception catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(commonFailureMessage(e))));
    }
  }
}

enum _MenuAction { showRecoveryCode, leaveDevice }

class _AssignmentView extends StatelessWidget {
  const _AssignmentView({required this.assignment, required this.refreshing});

  final Assignment assignment;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      // Always scrollable so pull-to-refresh works on short content.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (refreshing) const LinearProgressIndicator(),
                Text('Hi ${assignment.participantName}!', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 24),
                ColorSwatchCard(label: 'Your color', color: assignment.myColor),
                const SizedBox(height: 16),
                ColorSwatchCard(label: 'Buy a gift for', color: assignment.giftColor),
                const SizedBox(height: 16),
                Text(
                  'Keep your gift color a secret!',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry, required this.onLeave});

  final Object error;
  final VoidCallback onRetry;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final rejected = isIdentityRejected(error);
    return FormColumn(
      children: [
        FormErrorBanner(message: assignmentFailureMessage(error)),
        const SizedBox(height: 24),
        if (rejected)
          FilledButton(onPressed: onLeave, child: const Text('Leave This Device'))
        else ...[
          FilledButton(onPressed: onRetry, child: const Text('Try again')),
          const SizedBox(height: 12),
          TextButton(onPressed: onLeave, child: const Text('Leave This Device')),
        ],
      ],
    );
  }
}
