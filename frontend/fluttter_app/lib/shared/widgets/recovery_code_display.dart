import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Large, selectable recovery code with a copy button.
class RecoveryCodeDisplay extends StatelessWidget {
  const RecoveryCodeDisplay({super.key, required this.code});

  final String code;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Recovery code copied')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          // Read character by character, with "dash" spoken, so a screen reader
          // user can write the code down correctly.
          label: 'Recovery code: ${code.split('').map((c) => c == '-' ? 'dash' : c).join(' ')}',
          child: ExcludeSemantics(
            child: SelectableText(
              code,
              key: const Key('recoveryCodeText'),
              textAlign: TextAlign.center,
              style: theme.textTheme.displaySmall?.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Semantics(
          button: true,
          label: 'Copy recovery code',
          excludeSemantics: true,
          child: OutlinedButton.icon(
            onPressed: () => _copy(context),
            icon: const Icon(Icons.copy),
            label: const Text('Copy'),
          ),
        ),
      ],
    );
  }
}
