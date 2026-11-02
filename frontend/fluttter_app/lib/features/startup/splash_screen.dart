import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'startup_controller.dart';

/// Shown on `/` while the startup controller reads secure storage. The router
/// redirect moves on once the state is data. On a storage error it offers a
/// retry; credentials are never deleted here.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startup = ref.watch(startupControllerProvider);

    return Scaffold(
      body: Center(
        child: startup.hasError
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 48),
                  const SizedBox(height: 16),
                  const Text('Could not read secure storage on this device.'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => ref.read(startupControllerProvider.notifier).retry(),
                    child: const Text('Try again'),
                  ),
                ],
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}
