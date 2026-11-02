import 'package:flutter_test/flutter_test.dart';
import 'package:secret_santa/core/network/api_failure.dart';
import 'package:secret_santa/core/storage/identity_store.dart';
import 'package:secret_santa/core/storage/secure_storage.dart';
import 'package:secret_santa/data/models/participant_identity.dart';
import 'package:secret_santa/data/repositories/participant_repository.dart';
import 'package:secret_santa/data/repositories/repository_exceptions.dart';
import 'package:secret_santa/data/services/edge_functions.dart';
import 'package:secret_santa/data/services/participant_service.dart';

import '../../helpers/fakes.dart';
import '../../helpers/fixtures.dart';

void main() {
  final now = DateTime.utc(2026, 12, 1, 12);

  late FakeApiClient client;
  late InMemorySecureStorage storage;
  late CredentialStore store;
  late ParticipantRepository repository;

  ParticipantRepository buildRepository(SecureStorage storage) => ParticipantRepository(
        service: ParticipantService(client),
        store: CredentialStore(storage),
        clock: () => now,
      );

  setUp(() {
    client = FakeApiClient();
    storage = InMemorySecureStorage();
    store = CredentialStore(storage);
    repository = buildRepository(storage);
  });

  group('joinSession', () {
    test('success stores the identity and returns a token-free outcome', () async {
      client.respond(EdgeFunctions.joinSession, Fixtures.joinSession());

      final outcome = await repository.joinSession(inviteCode: Fixtures.inviteCode, participantName: 'Maria');

      expect(
        await store.readParticipant(),
        ParticipantCredentials(
          participantId: Fixtures.participantId,
          browserToken: Fixtures.browserToken,
          recoveryCode: Fixtures.recoveryCode,
          participantName: 'Maria',
          savedAt: now,
        ),
      );
      expect(outcome.participantId, Fixtures.participantId);
      expect(outcome.recoveryCode, Fixtures.recoveryCode);
      expect(outcome.toString(), isNot(contains(Fixtures.recoveryCode)));
    });

    test('server rejection stores nothing and rethrows the failure', () async {
      const failure = ConflictFailure(code: ApiErrorCodes.sessionFull, message: 'full', statusCode: 409);
      client.fail(EdgeFunctions.joinSession, failure);

      await expectLater(
        repository.joinSession(inviteCode: Fixtures.inviteCode, participantName: 'Maria'),
        throwsA(same(failure)),
      );
      expect(storage.values, isEmpty);
    });

    test('failed save throws ParticipantNotSavedException carrying the recovery code', () async {
      client.respond(EdgeFunctions.joinSession, Fixtures.joinSession());
      final flaky = FlakyWriteStorage();
      final repo = buildRepository(flaky);

      try {
        await repo.joinSession(inviteCode: Fixtures.inviteCode, participantName: 'Maria');
        fail('expected ParticipantNotSavedException');
      } on ParticipantNotSavedException catch (e) {
        expect(e.outcome.recoveryCode, Fixtures.recoveryCode);
        expect(e.cause, isA<SecureStorageException>());
        expect(e.toString(), isNot(contains(Fixtures.recoveryCode)));
      }
      expect(flaky.values, isEmpty);
    });
  });

  group('recoverAssignment', () {
    test('success stores the identity with the recovery code used', () async {
      client.respond(EdgeFunctions.recoverAssignment, Fixtures.recoverAssignment());

      final assignment = await repository.recoverAssignment(recoveryCode: Fixtures.recoveryCode);

      final stored = await store.readParticipant();
      expect(stored?.browserToken, Fixtures.browserToken);
      expect(stored?.recoveryCode, Fixtures.recoveryCode);
      expect(stored?.participantName, 'Maria');
      expect(stored?.savedAt, now);
      expect(assignment.participantName, 'Maria');
      expect(assignment.giftColor.name, 'GREEN');
    });

    test('recovery replaces an existing identity', () async {
      await store.saveParticipant(
        ParticipantCredentials(participantId: 'old', browserToken: 'BT_old', savedAt: now),
      );
      client.respond(EdgeFunctions.recoverAssignment, Fixtures.recoverAssignment());

      await repository.recoverAssignment(recoveryCode: Fixtures.recoveryCode);

      expect((await store.readParticipant())?.participantId, Fixtures.participantId);
    });

    test('failed save throws RecoveryNotSavedException', () async {
      client.respond(EdgeFunctions.recoverAssignment, Fixtures.recoverAssignment());

      await expectLater(
        buildRepository(FlakyWriteStorage()).recoverAssignment(recoveryCode: Fixtures.recoveryCode),
        throwsA(isA<RecoveryNotSavedException>()),
      );
    });
  });

  group('getMyAssignment', () {
    test('reads the stored token and sends it', () async {
      await store.saveParticipant(
        ParticipantCredentials(
          participantId: Fixtures.participantId,
          browserToken: Fixtures.browserToken,
          savedAt: now,
        ),
      );
      client.respond(EdgeFunctions.getMyAssignment, Fixtures.getMyAssignment);

      final assignment = await repository.getMyAssignment();

      expect(client.calls.single.body, {'browserToken': Fixtures.browserToken});
      expect(assignment.participantName, 'Maria');
    });

    test('no stored identity throws without calling the API', () async {
      await expectLater(repository.getMyAssignment(), throwsA(isA<NoParticipantIdentityException>()));
      expect(client.calls, isEmpty);
    });

    test('server failure is rethrown and stored identity is left untouched', () async {
      final credentials = ParticipantCredentials(
        participantId: Fixtures.participantId,
        browserToken: Fixtures.browserToken,
        savedAt: now,
      );
      await store.saveParticipant(credentials);
      const failure = NotFoundFailure(
        code: ApiErrorCodes.participantNotFound,
        message: 'not found',
        statusCode: 404,
      );
      client.fail(EdgeFunctions.getMyAssignment, failure);

      await expectLater(repository.getMyAssignment(), throwsA(same(failure)));
      expect(await store.readParticipant(), credentials);
    });
  });
}
