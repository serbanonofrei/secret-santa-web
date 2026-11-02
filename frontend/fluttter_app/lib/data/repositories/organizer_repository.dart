import 'package:dio/dio.dart';

import '../../core/storage/identity_store.dart';
import '../models/organizer_api_models.dart';
import '../models/organizer_session.dart';
import '../models/view_models.dart';
import '../services/session_service.dart';
import 'repository_exceptions.dart';

/// Organizer use cases: API call + organizer session persistence.
///
/// * The ONLY place that writes organizer sessions (via [CredentialStore]).
/// * The organizer token never leaves this class: callers pass a `sessionId`,
///   the token is looked up here, and results returned to callers never
///   contain it.
class OrganizerRepository {
  OrganizerRepository({
    required SessionService service,
    required CredentialStore store,
    DateTime Function()? clock,
  })  : _service = service,
        _store = store,
        _clock = clock ?? DateTime.now;

  final SessionService _service;
  final CredentialStore _store;
  final DateTime Function() _clock;

  /// Session created on the server whose save to secure storage failed.
  /// Kept in memory so the token is not lost while the app is running.
  OrganizerSession? _pendingSession;

  /// Whether a created session still has to be saved (see
  /// [retrySavePendingSession]).
  bool get hasPendingSession => _pendingSession != null;

  Future<ListColorsResult> listColors({CancelToken? cancelToken}) =>
      _service.listColors(cancelToken: cancelToken);

  /// Creates a session and stores its organizer token on this device.
  ///
  /// Throws:
  /// * [ApiFailure] if the server rejects it (nothing stored).
  /// * [OrganizerSessionNotSavedException] if the session was created but
  ///   storing failed. The session is kept in memory; call
  ///   [retrySavePendingSession].
  Future<CreatedSession> createSession({
    required String sessionName,
    required int maxParticipants,
    required List<int> allowedColors,
    CancelToken? cancelToken,
  }) async {
    final CreateSessionResult result = await _service.createSession(
      sessionName: sessionName,
      maxParticipants: maxParticipants,
      allowedColors: allowedColors,
      cancelToken: cancelToken,
    );

    // The server trims the name; store the same form.
    final storedName = sessionName.trim();

    final session = OrganizerSession(
      sessionId: result.sessionId,
      organizerToken: result.organizerToken,
      inviteCode: result.inviteCode,
      sessionName: storedName,
      createdAt: _clock().toUtc(),
    );

    final created = CreatedSession(
      sessionId: result.sessionId,
      inviteCode: result.inviteCode,
      sessionName: storedName,
      published: result.published,
      selectedColors: result.selectedColors,
    );

    try {
      await _store.upsertOrganizerSession(session);
    } on Object catch (e) {
      _pendingSession = session;
      throw OrganizerSessionNotSavedException(created, e);
    }

    return created;
  }

  /// Retries saving a session whose save failed in [createSession].
  /// Returns false if nothing was pending. Throws the storage error if the
  /// retry fails again (the session stays pending).
  Future<bool> retrySavePendingSession() async {
    final pending = _pendingSession;
    if (pending == null) return false;
    await _store.upsertOrganizerSession(pending);
    _pendingSession = null;
    return true;
  }

  Future<SessionInfo> publishSession(String sessionId, {CancelToken? cancelToken}) async {
    final session = await _requireSession(sessionId);
    return _service.publishSession(
      sessionId: session.sessionId,
      organizerToken: session.organizerToken,
      cancelToken: cancelToken,
    );
  }

  Future<ParticipantList> getParticipants(String sessionId, {CancelToken? cancelToken}) async {
    final session = await _requireSession(sessionId);
    return _service.getParticipants(
      sessionId: session.sessionId,
      organizerToken: session.organizerToken,
      cancelToken: cancelToken,
    );
  }

  Future<ClosedSession> closeSession(String sessionId, {CancelToken? cancelToken}) async {
    final session = await _requireSession(sessionId);
    return _service.closeSession(
      sessionId: session.sessionId,
      organizerToken: session.organizerToken,
      cancelToken: cancelToken,
    );
  }

  /// Sessions organized on this device, without tokens. Newest first.
  Future<List<OrganizerSessionSummary>> listOrganizerSessions() async {
    final sessions = [...await _store.readOrganizerSessions()];
    final pending = _pendingSession;
    if (pending != null && sessions.every((s) => s.sessionId != pending.sessionId)) {
      sessions.add(pending);
    }
    sessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(sessions.map(_toSummary));
  }

  /// Token-free view of one stored session, or null if this device does not
  /// organize it.
  Future<OrganizerSessionSummary?> findOrganizerSession(String sessionId) async {
    final session = await _findSession(sessionId);
    return session == null ? null : _toSummary(session);
  }

  /// Forgets a session on this device. Its organizer token is gone afterwards.
  Future<void> removeOrganizerSession(String sessionId) async {
    if (_pendingSession?.sessionId == sessionId) _pendingSession = null;
    await _store.removeOrganizerSession(sessionId);
  }

  Future<OrganizerSession?> _findSession(String sessionId) async {
    final pending = _pendingSession;
    if (pending != null && pending.sessionId == sessionId) return pending;
    return _store.findOrganizerSession(sessionId);
  }

  /// Throws [UnknownOrganizerSessionException] (no API call) if not found.
  Future<OrganizerSession> _requireSession(String sessionId) async {
    final session = await _findSession(sessionId);
    if (session == null) throw UnknownOrganizerSessionException(sessionId);
    return session;
  }

  static OrganizerSessionSummary _toSummary(OrganizerSession s) => OrganizerSessionSummary(
        sessionId: s.sessionId,
        inviteCode: s.inviteCode,
        sessionName: s.sessionName,
        createdAt: s.createdAt,
      );
}
