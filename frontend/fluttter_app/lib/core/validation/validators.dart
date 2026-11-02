/// Client-side input rules. They mirror the Edge Function validation so most
/// mistakes are caught before a request is sent; the server stays the
/// authority and its field errors are still shown.
library;

/// Alphabet used by invite codes and recovery codes (no 0, 1, I, O).
const String codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

const int inviteCodeLength = 6;
const int participantNameMaxLength = 100;
const int recoveryCodeRawLength = 12;

final RegExp _nonAlphanumeric = RegExp('[^A-Z0-9]');
final RegExp _whitespaceRun = RegExp(r'\s+');
final RegExp _inviteCodePattern = RegExp('^[$codeAlphabet]{$inviteCodeLength}\$');
final RegExp _recoveryCodePattern = RegExp('^[$codeAlphabet]{4}(-[$codeAlphabet]{4}){2}\$');

// ---------------------------------------------------------------------------
// Invite code
// ---------------------------------------------------------------------------

/// Upper-cases and removes everything that is not A-Z / 0-9 (spaces, dashes).
String normalizeInviteCode(String raw) => raw.toUpperCase().replaceAll(_nonAlphanumeric, '');

/// Returns a user-facing error, or null if [code] (already normalized) is valid.
String? validateInviteCode(String code) {
  if (code.isEmpty) return 'Enter the invite code from your organizer.';
  if (code.length != inviteCodeLength) return 'The invite code has $inviteCodeLength characters.';
  if (!_inviteCodePattern.hasMatch(code)) {
    return 'Invite codes use letters A–Z (no I or O) and digits 2–9.';
  }
  return null;
}

// ---------------------------------------------------------------------------
// Participant name
// ---------------------------------------------------------------------------

/// Collapses whitespace runs and trims, like the server's display form.
String normalizeParticipantName(String raw) => raw.replaceAll(_whitespaceRun, ' ').trim();

/// Returns a user-facing error, or null if [name] (already normalized) is valid.
/// Length counts Unicode code points, like the server.
String? validateParticipantName(String name) {
  if (name.isEmpty) return 'Enter your name.';
  if (name.runes.length > participantNameMaxLength) {
    return 'Your name can have at most $participantNameMaxLength characters.';
  }
  return null;
}

// ---------------------------------------------------------------------------
// Recovery code
// ---------------------------------------------------------------------------

/// Formats any input as `XXXX-XXXX-XXXX` (partial while typing): upper-cases,
/// strips non-alphanumerics, clips to 12 characters, inserts dashes.
String formatRecoveryCode(String raw) {
  final cleaned = raw.toUpperCase().replaceAll(_nonAlphanumeric, '');
  final clipped = cleaned.length > recoveryCodeRawLength ? cleaned.substring(0, recoveryCodeRawLength) : cleaned;
  final buffer = StringBuffer();
  for (var i = 0; i < clipped.length; i++) {
    if (i > 0 && i % 4 == 0) buffer.write('-');
    buffer.write(clipped[i]);
  }
  return buffer.toString();
}

/// Returns a user-facing error, or null if [code] (already formatted) is valid.
String? validateRecoveryCode(String code) {
  if (code.isEmpty) return 'Enter your recovery code.';
  if (!_recoveryCodePattern.hasMatch(code)) {
    return 'Recovery codes look like XXXX-XXXX-XXXX (letters A–Z without I or O, digits 2–9).';
  }
  return null;
}
