import '../../core/network/api_failure.dart';
import '../../core/storage/secure_storage.dart';
import '../../data/repositories/repository_exceptions.dart';

/// User-facing error text.
///
/// Decisions are made ONLY on the failure type and `error.code`. Server
/// message text (English, for logs) is never inspected or shown, including
/// field-level `details[].message`: each field gets an app-side message.

/// A general message plus per-field messages for a form.
class FailureFeedback {
  const FailureFeedback({this.message, this.fieldErrors = const {}});

  final String? message;

  /// Keyed by request field name (`inviteCode`, `participantName`, `recoveryCode`).
  final Map<String, String> fieldErrors;
}

// ---------------------------------------------------------------------------
// Shared
// ---------------------------------------------------------------------------

/// Friendly text for every known backend `error.code`, independent of the
/// screen. Screens may override a code with more specific wording (e.g. show
/// it under a field), but no known code ever falls through to a generic text.
///
/// Returns null for unknown codes. Never returns server text.
String? backendCodeMessage(String code) => switch (code) {
      // --- Participant ---
      ApiErrorCodes.sessionNotFound => 'No session uses this invite code. Check it with your organizer.',
      ApiErrorCodes.sessionNotActive =>
        'This session is not open for joining. It may not be published yet, or it is already closed.',
      ApiErrorCodes.sessionFull => 'This session is full. Ask your organizer for help.',
      ApiErrorCodes.duplicateParticipantName =>
        'Someone in this session already uses this name. Add an initial or a nickname.',
      ApiErrorCodes.participantNotFound => 'No participant was found. Check your code and try again.',
      ApiErrorCodes.participantInactive => 'This participant was removed from the session. Ask your organizer for help.',
      ApiErrorCodes.assignmentUnavailable => "The assignment isn't available right now. Please try again later.",
      ApiErrorCodes.credentialsExhausted => 'We could not complete your sign-up. Please try again.',
      // --- Organizer ---
      ApiErrorCodes.sessionNotDraft => 'This session has already been published.',
      ApiErrorCodes.sessionAlreadyClosed => 'This session is already closed.',
      ApiErrorCodes.unknownColors => 'Some of the selected colors are no longer available. Please choose again.',
      ApiErrorCodes.notEnoughColors => 'This session needs at least 2 colors before it can be published.',
      ApiErrorCodes.forbidden => "This device isn't allowed to manage this session.",
      ApiErrorCodes.inviteCodeExhausted => 'We could not create the session right now. Please try again.',
      ApiErrorCodes.invalidReference => 'Some of the details refer to something that no longer exists.',
      // --- Generic ---
      ApiErrorCodes.validationError => 'Some of the details are not valid. Please check and try again.',
      ApiErrorCodes.notFound => 'The service could not be found. Please update the app or try again later.',
      ApiErrorCodes.serverMisconfigured ||
      ApiErrorCodes.databaseError ||
      ApiErrorCodes.invalidDbResponse ||
      ApiErrorCodes.internalError ||
      ApiErrorCodes.invalidResponse =>
        'Something went wrong on our side. Please try again later.',
      _ => null,
    };

/// Message for failures that mean the same thing on every screen.
String commonFailureMessage(Object error) {
  if (error is ApiFailure && error is! NetworkFailure && error is! CancelledFailure) {
    final known = backendCodeMessage(error.code);
    if (known != null) return known;
  }
  return switch (error) {
    NetworkFailure(code: ApiErrorCodes.timeout) =>
      'The server took too long to respond. Check your connection and try again.',
    NetworkFailure() => "Can't reach the server. Check your internet connection and try again.",
    ServiceUnavailableFailure() => 'The service is busy right now. Please try again in a moment.',
    CancelledFailure() => 'The request was cancelled.',
    BadRequestFailure() => 'The app sent a request the server did not understand. Please update the app.',
    ServerFailure() => 'Something went wrong on our side. Please try again later.',
    SecureStorageException() => "This device's secure storage is not available right now.",
    _ => 'Something went wrong. Please try again.',
  };
}

/// App-side message for a server field error, by field name only.
String? _fieldMessage(String field) => switch (field) {
      'inviteCode' => 'Check the invite code: 6 characters from your organizer.',
      'participantName' => 'Check your name: 1 to 100 characters.',
      'recoveryCode' => 'Check your recovery code: it looks like XXXX-XXXX-XXXX.',
      _ => null,
    };

FailureFeedback _validationFeedback(ValidationFailure failure, Set<String> formFields) {
  final fieldErrors = <String, String>{
    for (final error in failure.fieldErrors)
      if (formFields.contains(error.field))
        if (_fieldMessage(error.field) case final message?) error.field: message,
  };
  return FailureFeedback(
    message: fieldErrors.isEmpty ? 'Some of the details are not valid. Please check and try again.' : null,
    fieldErrors: fieldErrors,
  );
}

// ---------------------------------------------------------------------------
// Join
// ---------------------------------------------------------------------------

const _joinFields = {'inviteCode', 'participantName'};

FailureFeedback joinFailureFeedback(Object error) {
  return switch (error) {
    ValidationFailure() => _validationFeedback(error, _joinFields),
    NotFoundFailure(code: ApiErrorCodes.sessionNotFound) => const FailureFeedback(
        fieldErrors: {'inviteCode': 'No session uses this invite code. Check it with your organizer.'},
      ),
    ConflictFailure(code: ApiErrorCodes.duplicateParticipantName) => const FailureFeedback(
        fieldErrors: {
          'participantName': 'Someone in this session already uses this name. Add an initial or a nickname.',
        },
      ),
    ConflictFailure(code: ApiErrorCodes.sessionFull) =>
      const FailureFeedback(message: 'This session is full. Ask your organizer for help.'),
    ConflictFailure(code: ApiErrorCodes.sessionNotActive) => const FailureFeedback(
        message: 'This session is not open for joining. It may not be published yet, or it is already closed.',
      ),
    ServiceUnavailableFailure(code: ApiErrorCodes.credentialsExhausted) =>
      const FailureFeedback(message: 'We could not complete your sign-up. Please try again.'),
    _ => FailureFeedback(message: commonFailureMessage(error)),
  };
}

// ---------------------------------------------------------------------------
// Recover
// ---------------------------------------------------------------------------

const _recoverFields = {'recoveryCode'};

FailureFeedback recoverFailureFeedback(Object error) {
  return switch (error) {
    ValidationFailure() => _validationFeedback(error, _recoverFields),
    NotFoundFailure(code: ApiErrorCodes.participantNotFound) => const FailureFeedback(
        fieldErrors: {'recoveryCode': 'No participant has this recovery code. Check it and try again.'},
      ),
    ForbiddenFailure(code: ApiErrorCodes.participantInactive) => const FailureFeedback(
        message: 'This participant was removed from the session. Ask your organizer for help.',
      ),
    ConflictFailure(code: ApiErrorCodes.assignmentUnavailable) => const FailureFeedback(
        message: "Your assignment isn't available right now. Please try again later.",
      ),
    RecoveryNotSavedException() => const FailureFeedback(
        message: 'Your code is correct, but it could not be saved on this device. Please try again.',
      ),
    _ => FailureFeedback(message: commonFailureMessage(error)),
  };
}

// ---------------------------------------------------------------------------
// Assignment
// ---------------------------------------------------------------------------

String assignmentFailureMessage(Object error) {
  return switch (error) {
    NotFoundFailure(code: ApiErrorCodes.participantNotFound) =>
      'This device is linked to a participation that no longer exists. '
          'Leave this device, then join again or use your recovery code.',
    ForbiddenFailure(code: ApiErrorCodes.participantInactive) =>
      'You were removed from this session. Ask your organizer for help.',
    ConflictFailure(code: ApiErrorCodes.assignmentUnavailable) =>
      "Your assignment isn't available right now. Please try again later.",
    NoParticipantIdentityException() => 'No participation is saved on this device.',
    _ => commonFailureMessage(error),
  };
}

/// True when the server says the stored identity itself is no longer valid,
/// so "Leave this device" is the useful next step (not "Try again").
bool isIdentityRejected(Object error) => switch (error) {
      NotFoundFailure(code: ApiErrorCodes.participantNotFound) => true,
      ForbiddenFailure(code: ApiErrorCodes.participantInactive) => true,
      ValidationFailure() => true,
      NoParticipantIdentityException() => true,
      _ => false,
    };
