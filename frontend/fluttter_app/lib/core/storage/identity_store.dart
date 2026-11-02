import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';

import '../../data/models/organizer_session.dart';
import '../../data/models/participant_identity.dart';
import 'secure_storage.dart';

/// Thrown when a stored value exists but cannot be decoded (corrupt or from an
/// incompatible app version).
class CredentialDecodeException implements Exception {
  const CredentialDecodeException(this.key, this.cause);

  final String key;
  final Object cause;

  @override
  String toString() => 'CredentialDecodeException("$key"): $cause';
}

/// Typed access to the credentials kept in [SecureStorage].
///
/// | Key                         | Value                              |
/// |-----------------------------|------------------------------------|
/// | `ssw.v1.participant`        | [ParticipantCredentials] as JSON   |
/// | `ssw.v1.organizer_sessions` | List of [OrganizerSession] as JSON |
///
/// Each value is one JSON document, so a save is all-or-nothing.
///
/// Decoding policy:
/// * Participant: a corrupt value is deleted and treated as absent (the
///   participant can get back in with the recovery code). Only decode errors
///   (see [_isDecodeError]) count as corruption; storage failures and any
///   other exception propagate and nothing is deleted.
/// * Organizer sessions: a corrupt list throws [CredentialDecodeException] and
///   is NOT deleted, so a lost organizer token is never silently discarded.
///
/// Only repositories (and the startup controller) should use this class.
class CredentialStore {
  CredentialStore(this._storage);

  static const participantKey = 'ssw.v1.participant';
  static const organizerSessionsKey = 'ssw.v1.organizer_sessions';

  final SecureStorage _storage;

  // ---------------------------------------------------------------------------
  // Participant
  // ---------------------------------------------------------------------------

  /// Returns the stored participant, or null if none is stored or the stored
  /// value is corrupt (in which case it is deleted).
  ///
  /// Throws [SecureStorageException] (or any non-decode error) unchanged,
  /// without deleting anything.
  Future<ParticipantCredentials?> readParticipant() async {
    // Outside the try: storage failures must never be treated as corruption.
    final raw = await _storage.read(participantKey);
    if (raw == null || raw.isEmpty) return null;

    final ParticipantCredentials credentials;
    try {
      credentials = _decodeParticipant(raw);
    } on Object catch (e) {
      if (!_isDecodeError(e)) rethrow;
      // Corrupt or incompatible: drop it, the participant can recover.
      await _storage.delete(participantKey);
      return null;
    }
    return credentials;
  }

  /// Pure decoding, no storage access. Every failure here is a decode error.
  static ParticipantCredentials _decodeParticipant(String raw) {
    final Object? decoded = jsonDecode(raw); // FormatException on invalid JSON
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Expected a JSON object');
    }
    // Generated fromJson: TypeError on a missing / wrongly typed field,
    // FormatException on an unparsable DateTime.
    return ParticipantCredentials.fromJson(decoded);
  }

  /// Exceptions that mean "the stored bytes are not a valid value":
  /// * [FormatException]: invalid JSON, wrong top-level shape (thrown above),
  ///   unparsable DateTime.
  /// * [TypeError]: generated `fromJson` casts (`json['x'] as String`) on a
  ///   missing or wrongly typed field.
  /// * [CheckedFromJsonException]: only if `checked: true` is ever enabled
  ///   for json_serializable.
  static bool _isDecodeError(Object error) =>
      error is FormatException || error is TypeError || error is CheckedFromJsonException;

  Future<void> saveParticipant(ParticipantCredentials credentials) =>
      _storage.write(participantKey, jsonEncode(credentials.toJson()));

  Future<void> clearParticipant() => _storage.delete(participantKey);

  // ---------------------------------------------------------------------------
  // Organizer sessions
  // ---------------------------------------------------------------------------

  /// Throws [CredentialDecodeException] if the stored list is corrupt.
  Future<List<OrganizerSession>> readOrganizerSessions() async {
    final raw = await _storage.read(organizerSessionsKey);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        throw const FormatException('Expected a JSON array');
      }
      return List.unmodifiable(
        decoded.map((item) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('Expected a JSON object in the array');
          }
          return OrganizerSession.fromJson(item);
        }),
      );
    } on Object catch (e) {
      throw CredentialDecodeException(organizerSessionsKey, e);
    }
  }

  Future<OrganizerSession?> findOrganizerSession(String sessionId) async {
    final sessions = await readOrganizerSessions();
    for (final s in sessions) {
      if (s.sessionId == sessionId) return s;
    }
    return null;
  }

  /// Adds [session], replacing any stored session with the same id.
  Future<void> upsertOrganizerSession(OrganizerSession session) async {
    final sessions = await readOrganizerSessions();
    await _writeOrganizerSessions([
      for (final s in sessions)
        if (s.sessionId != session.sessionId) s,
      session,
    ]);
  }

  Future<void> removeOrganizerSession(String sessionId) async {
    final sessions = await readOrganizerSessions();
    final remaining = [
      for (final s in sessions)
        if (s.sessionId != sessionId) s,
    ];
    if (remaining.isEmpty) {
      await _storage.delete(organizerSessionsKey);
    } else {
      await _writeOrganizerSessions(remaining);
    }
  }

  Future<void> _writeOrganizerSessions(List<OrganizerSession> sessions) => _storage.write(
        organizerSessionsKey,
        jsonEncode([for (final s in sessions) s.toJson()]),
      );
}
