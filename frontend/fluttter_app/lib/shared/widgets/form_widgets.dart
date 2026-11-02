import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Error box shown above a form's submit button.
class FormErrorBanner extends StatelessWidget {
  const FormErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      // Announced when it appears; the "Error" prefix tells screen reader
      // users what kind of message it is (the icon alone is not read).
      liveRegion: true,
      label: 'Error: $message',
      excludeSemantics: true,
      child: Container(
        key: const Key('formErrorBanner'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: TextStyle(color: scheme.onErrorContainer))),
          ],
        ),
      ),
    );
  }
}

/// Filled button that shows a spinner and is disabled while [busy].
class SubmitButton extends StatelessWidget {
  const SubmitButton({super.key, required this.label, required this.busy, required this.onPressed});

  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: 'Please wait'),
            )
          : Text(label),
    );
  }
}

/// Constrains form content to a readable width on web / tablets.
///
/// Wraps the content in a reading-order focus traversal group, so Tab /
/// Shift+Tab on web move through fields and buttons top to bottom.
class FormColumn extends StatelessWidget {
  const FormColumn({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: FocusTraversalGroup(
            policy: ReadingOrderTraversalPolicy(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

/// Upper-cases input as the user types.
class UpperCaseTextFormatter extends TextInputFormatter {
  const UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}
