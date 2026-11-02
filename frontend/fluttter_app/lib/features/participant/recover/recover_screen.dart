import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/validation/validators.dart';
import '../../../shared/widgets/form_widgets.dart';
import 'recover_controller.dart';

/// `/recover`. On success the startup state becomes participant and the
/// router guard moves to `/assignment`; this screen does not navigate itself.
class RecoverScreen extends ConsumerStatefulWidget {
  const RecoverScreen({super.key});

  @override
  ConsumerState<RecoverScreen> createState() => _RecoverScreenState();
}

class _RecoverScreenState extends ConsumerState<RecoverScreen> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    ref.read(recoverControllerProvider.notifier).submit(_code.text);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(recoverControllerProvider);
    final busy = state is RecoverSubmitting || state is RecoverSucceeded;
    final feedback = state is RecoverFailed ? state.feedback : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Recover Assignment')),
      body: FormColumn(
        children: [
          Text(
            'Enter the recovery code you got when you joined.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('recoveryCodeField'),
            controller: _code,
            enabled: !busy,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword,
            inputFormatters: const [RecoveryCodeInputFormatter()],
            onChanged: (_) => ref.read(recoverControllerProvider.notifier).clearError(),
            onSubmitted: (_) => _submit(),
            style: const TextStyle(fontFamily: 'monospace', letterSpacing: 1.5),
            decoration: InputDecoration(
              labelText: 'Recovery code',
              hintText: 'XXXX-XXXX-XXXX',
              errorText: feedback?.fieldErrors['recoveryCode'],
              errorMaxLines: 3,
            ),
          ),
          const SizedBox(height: 24),
          if (feedback?.message case final message?) ...[
            FormErrorBanner(message: message),
            const SizedBox(height: 16),
          ],
          SubmitButton(label: 'Recover', busy: busy, onPressed: _submit),
        ],
      ),
    );
  }
}

/// Formats as `XXXX-XXXX-XXXX` while typing; the cursor goes to the end.
class RecoveryCodeInputFormatter extends TextInputFormatter {
  const RecoveryCodeInputFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var formatted = formatRecoveryCode(newValue.text);
    // Deleting the character after a dash should remove the dash too.
    if (newValue.text.length < oldValue.text.length && formatted == oldValue.text && formatted.isNotEmpty) {
      formatted = formatRecoveryCode(formatted.substring(0, formatted.length - 1));
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
