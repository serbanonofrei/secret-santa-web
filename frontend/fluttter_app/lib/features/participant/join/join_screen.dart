import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/validation/validators.dart';
import '../../../shared/widgets/form_widgets.dart';
import 'join_controller.dart';

/// `/join` (optionally `/join?code=ABC234` from an invite link).
class JoinScreen extends ConsumerStatefulWidget {
  const JoinScreen({super.key, this.initialInviteCode});

  final String? initialInviteCode;

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  late final TextEditingController _inviteCode;
  final _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    final initial = normalizeInviteCode(widget.initialInviteCode ?? '');
    _inviteCode = TextEditingController(
      text: initial.length > inviteCodeLength ? initial.substring(0, inviteCodeLength) : initial,
    );
    // The controller is kept alive across visits: drop errors / a finished
    // result from a previous visit (reset() never discards a pending join).
    // Deferred because providers must not change during build.
    Future.microtask(() {
      if (mounted) ref.read(joinControllerProvider.notifier).reset();
    });
  }

  @override
  void dispose() {
    _inviteCode.dispose();
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    ref.read(joinControllerProvider.notifier).submit(
          inviteCode: _inviteCode.text,
          participantName: _name.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    // No navigation here: when the join succeeds, the router guard moves this
    // route to /join/recovery-code (single navigation mechanism).
    final state = ref.watch(joinControllerProvider);
    final controller = ref.read(joinControllerProvider.notifier);
    final busy = state is JoinSubmitting;
    final feedback = state is JoinFailed ? state.feedback : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Join Session')),
      body: FormColumn(
        children: [
          TextField(
            key: const Key('inviteCodeField'),
            controller: _inviteCode,
            enabled: !busy,
            autofocus: _inviteCode.text.isEmpty,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: [
              FilteringTextInputFormatter.deny(RegExp(r'\s')),
              const UpperCaseTextFormatter(),
              LengthLimitingTextInputFormatter(inviteCodeLength),
            ],
            onChanged: (_) => controller.clearFieldError('inviteCode'),
            decoration: InputDecoration(
              labelText: 'Invite code',
              hintText: 'ABC234',
              errorText: feedback?.fieldErrors['inviteCode'],
              errorMaxLines: 3,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('participantNameField'),
            controller: _name,
            enabled: !busy,
            autofocus: _inviteCode.text.isNotEmpty,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            inputFormatters: [LengthLimitingTextInputFormatter(participantNameMaxLength)],
            onChanged: (_) => controller.clearFieldError('participantName'),
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Your name',
              helperText: 'Shown to your organizer.',
              errorText: feedback?.fieldErrors['participantName'],
              errorMaxLines: 3,
            ),
          ),
          const SizedBox(height: 24),
          if (feedback?.message case final message?) ...[
            FormErrorBanner(message: message),
            const SizedBox(height: 16),
          ],
          SubmitButton(label: 'Join', busy: busy, onPressed: _submit),
        ],
      ),
    );
  }
}
