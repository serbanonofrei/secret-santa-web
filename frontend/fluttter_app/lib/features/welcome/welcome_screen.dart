import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../shared/widgets/form_widgets.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: FormColumn(
          children: [
            const Icon(Icons.card_giftcard, size: 72),
            const SizedBox(height: 16),
            Text(
              'Secret Santa',
              textAlign: TextAlign.center,
              style: theme.textTheme.displaySmall,
              semanticsLabel: 'Secret Santa',
            ),
            const SizedBox(height: 8),
            Text(
              'Join with the invite code from your organizer, or get back in with your recovery code.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => context.push(Routes.join),
              icon: const Icon(Icons.group_add),
              label: const Text('Join Session'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => context.push(Routes.recover),
              icon: const Icon(Icons.key),
              label: const Text('Recover Assignment'),
            ),
            const SizedBox(height: 32),
            TextButton(
              onPressed: () => context.push(Routes.organizer),
              child: const Text('I am an organizer'),
            ),
          ],
        ),
      ),
    );
  }
}
