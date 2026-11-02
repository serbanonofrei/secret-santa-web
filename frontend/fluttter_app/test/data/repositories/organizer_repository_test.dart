import 'package:flutter_test/flutter_test.dart';
import 'package:secret_santa/core/network/api_failure.dart';
import 'package:secret_santa/core/storage/identity_store.dart';
import 'package:secret_santa/core/storage/secure_storage.dart';
import 'package:secret_santa/data/models/organizer_session.dart';
import 'package:secret_santa/data/models/session_status.dart';
import 'package:secret_santa/data/repositories/organizer_repository.dart';
import 'package:secret_santa/data/repositories/repository_exceptions.dart';
import 'package:secret_santa/data/services/edge_functions.dart';
import 'package:secret_santa/data/services/session_service.dart';

import '../../helpers/fakes.dart';
import '../../helpers/fixtures.dart';

void main() {
  final now = DateTime.utc(2026, 11, 2, 9);

  late FakeApiClient client;
  late InMemorySecureStorage storage;
  late CredentialStore store;
  late OrganizerRepository repository;

  OrganizerRepository buildRepository(SecureStorage storage) => OrganizerRepository(
        service: SessionService(client),
        store: CredentialStore(storage),
        clock: () => now,
      );

  OrganizerSession storedSession({String id = Fixtures.sessionId, DateTime? createdAt}) => OrganizerSession(
        sessionId: id,
        organizerToken: id == Fixtures.sessionId ? Fixtures.organizerToken : 'ORG_other',
        inviteCode: Fixtures.inviteCode,
        sessionName: 'Office Xmas',
        createdAt: createdAt ?? now,
      );

  setUp(() {
    client = FakeApiClient();
    storage = InMemorySecureStorage();
    store = CredentialStore(storage);
    repository = buildRepository(storage);
  });

  group('createSession', () {
    test('stores the organizer session and returns a token-free result', () async {
      client.respond(EdgeFunctions.createSession, Fixtures.createSession);

      final created = await repository.createSession(
        sessionName: '  Office Xmas  ',
        maxParticipants: 2,
        allowedColors: [1, 2, 3],
      );

      expect(await store.findOrganizerSession(Fixtures.sessionId), storedSession());
      expect(created.sessionId, Fixtures.sessionId);
      expect(created.sessionName, 'Office Xmas');
      expect(created.inviteCode, Fixtures.inviteCode);
      expect(created.toString(), isNot(contains(Fixtures.organizerToken)));
    });

    test('server rejection stores nothing', () async {
      const failure = UnknownColorsFailure(message: 'unknown', statusCode: 422, unknownColorIds: [3]);
      client.fail(EdgeFunctions.createSession, failure);

      await expectLater(
        repository.createSession(sessionName: 'x', maxParticipants: 2, allowedColors: [1, 2, 3]),
        throwsA(same(failure)),
      );
      expect(storage.values, isEmpty);
    });

    test('failed save keeps the session pending in memory and retry persists it', () async {
      client.respond(EdgeFunctions.createSession, Fixtures.createSession);
      client.respond(EdgeFunctions.closeSession, Fixtures.closeSession);
      final flaky = FlakyWriteStorage();
      final repo = buildRepository(flaky);

      await expectLater(
        repo.createSession(sessionName: 'Office Xmas', maxParticipants: 2, allowedColors: [1, 2]),
        throwsA(isA<OrganizerSessionNotSavedException>()),
      );
      expect(repo.hasPendingSession, isTrue);

      // Still usable while pending: the token is held in memory.
      await repo.closeSession(Fixtures.sessionId);
      expect(client.callsTo(EdgeFunctions.closeSession).single.body['organizerToken'], Fixtures.organizerToken);
      expect((await repo.listOrganizerSessions()).single.sessionId, Fixtures.sessionId);

      // Storage recovers: retry persists it.
      flaky.failWrites = false;
      expect(await repo.retrySavePendingSession(), isTrue);
      expect(repo.hasPendingSession, isFalse);
      expect(await CredentialStore(flaky).findOrganizerSession(Fixtures.sessionId), isNotNull);
    });
  });

  group('session lookup', () {
    test('findOrganizerSession returns a token-free summary or null', () async {
      await store.upsertOrganizerSession(storedSession());

      final summary = await repository.findOrganizerSession(Fixtures.sessionId);
      expect(summary?.sessionName, 'Office Xmas');
      expect(summary.toString(), isNot(contains(Fixtures.organizerToken)));

      expect(await repository.findOrganizerSession('missing'), isNull);
    });

    test('listOrganizerSessions is newest first', () async {
      await store.upsertOrganizerSession(storedSession(id: 'old', createdAt: DateTime.utc(2026, 1, 1)));
      await store.upsertOrganizerSession(storedSession(id: 'new', createdAt: DateTime.utc(2026, 6, 1)));

      final sessions = await repository.listOrganizerSessions();

      expect(sessions.map((s) => s.sessionId), ['new', 'old']);
    });

    test('removeOrganizerSession forgets the session', () async {
      await store.upsertOrganizerSession(storedSession());

      await repository.removeOrganizerSession(Fixtures.sessionId);

      expect(await repository.findOrganizerSession(Fixtures.sessionId), isNull);
    });
  });

  group('token-based calls', () {
    setUp(() async => store.upsertOrganizerSession(storedSession()));

    test('closeSession uses the stored organizer token', () async {
      client.respond(EdgeFunctions.closeSession, Fixtures.closeSession);

      final closed = await repository.closeSession(Fixtures.sessionId);

      expect(client.calls.single.body, {
        'sessionId': Fixtures.sessionId,
        'organizerToken': Fixtures.organizerToken,
      });
      expect(closed.status, SessionStatus.closed);
    });

    test('publishSession and getParticipants use the stored organizer token', () async {
      client.respond(EdgeFunctions.publishSession, Fixtures.publishSession);
      client.respond(EdgeFunctions.getParticipants, Fixtures.getParticipants);

      await repository.publishSession(Fixtures.sessionId);
      await repository.getParticipants(Fixtures.sessionId);

      for (final call in client.calls) {
        expect(call.body['organizerToken'], Fixtures.organizerToken);
      }
    });

    test('unknown session throws without calling the API', () async {
      await expectLater(
        repository.closeSession('not-on-this-device'),
        throwsA(isA<UnknownOrganizerSessionException>()),
      );
      expect(client.calls, isEmpty);
    });

    test('server failure propagates unchanged and the session stays stored', () async {
      const failure = ConflictFailure(
        code: ApiErrorCodes.sessionAlreadyClosed,
        message: 'closed',
        statusCode: 409,
      );
      client.fail(EdgeFunctions.closeSession, failure);

      await expectLater(repository.closeSession(Fixtures.sessionId), throwsA(same(failure)));
      expect(await store.findOrganizerSession(Fixtures.sessionId), isNotNull);
    });
  });

  test('listColors passes through', () async {
    client.respond(EdgeFunctions.listColors, Fixtures.listColors);

    final result = await repository.listColors();

    expect(result.colors, hasLength(2));
  });
}
