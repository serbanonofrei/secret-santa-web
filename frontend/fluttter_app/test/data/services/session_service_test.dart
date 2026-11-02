import 'package:flutter_test/flutter_test.dart';
import 'package:secret_santa/core/network/api_failure.dart';
import 'package:secret_santa/data/models/session_status.dart';
import 'package:secret_santa/data/services/edge_functions.dart';
import 'package:secret_santa/data/services/session_service.dart';

import '../../helpers/fakes.dart';
import '../../helpers/fixtures.dart';

void main() {
  late FakeApiClient client;
  late SessionService service;

  setUp(() {
    client = FakeApiClient();
    service = SessionService(client);
  });

  group('success parsing', () {
    test('listColors keeps server order and maps fields', () async {
      client.respond(EdgeFunctions.listColors, Fixtures.listColors);

      final result = await service.listColors();

      expect(result.colors.map((c) => c.id), [2, 1]);
      expect(result.colors.first.name, 'GREEN');
      expect(result.colors.first.hexColor, '#00FF00');
      expect(client.calls.single.body, isEmpty);
    });

    test('createSession sends the contract body and parses the result', () async {
      client.respond(EdgeFunctions.createSession, Fixtures.createSession);

      final result = await service.createSession(
        sessionName: 'Office Xmas',
        maxParticipants: 2,
        allowedColors: [1, 2, 3],
      );

      expect(client.calls.single.body, {
        'sessionName': 'Office Xmas',
        'maxParticipants': 2,
        'allowedColors': [1, 2, 3],
      });
      expect(result.sessionId, Fixtures.sessionId);
      expect(result.organizerToken, Fixtures.organizerToken);
      expect(result.published, isFalse);
      expect(result.selectedColors.map((c) => c.catalogId), [1, 2]);
    });

    test('publishSession parses status and flags', () async {
      client.respond(EdgeFunctions.publishSession, Fixtures.publishSession);

      final info = await service.publishSession(
        sessionId: Fixtures.sessionId,
        organizerToken: Fixtures.organizerToken,
      );

      expect(client.calls.single.body, {
        'sessionId': Fixtures.sessionId,
        'organizerToken': Fixtures.organizerToken,
      });
      expect(info.status, SessionStatus.active);
      expect(info.published, isTrue);
      expect(info.draft, isFalse);
      expect(info.colorCount, 2);
    });

    test('getParticipants parses the list', () async {
      client.respond(EdgeFunctions.getParticipants, Fixtures.getParticipants);

      final list = await service.getParticipants(
        sessionId: Fixtures.sessionId,
        organizerToken: Fixtures.organizerToken,
      );

      expect(list.joinedCount, 1);
      expect(list.participants.single.participantName, 'Maria');
    });

    test('closeSession parses CLOSED', () async {
      client.respond(EdgeFunctions.closeSession, Fixtures.closeSession);

      final closed = await service.closeSession(
        sessionId: Fixtures.sessionId,
        organizerToken: Fixtures.organizerToken,
      );

      expect(closed.status, SessionStatus.closed);
    });

    test('unknown status value parses as SessionStatus.unknown', () async {
      client.respond(EdgeFunctions.closeSession, {...Fixtures.closeSession, 'status': 'ARCHIVED'});

      final closed = await service.closeSession(
        sessionId: Fixtures.sessionId,
        organizerToken: Fixtures.organizerToken,
      );

      expect(closed.status, SessionStatus.unknown);
    });
  });

  group('ApiFailure propagation', () {
    test('failure from ApiClient is rethrown as the same instance', () async {
      const failure = ConflictFailure(
        code: ApiErrorCodes.sessionNotDraft,
        message: 'already published',
        statusCode: 409,
      );
      client.fail(EdgeFunctions.publishSession, failure);

      await expectLater(
        service.publishSession(sessionId: Fixtures.sessionId, organizerToken: Fixtures.organizerToken),
        throwsA(same(failure)),
      );
    });

    test('NetworkFailure propagates unchanged', () async {
      const failure = NetworkFailure(code: ApiErrorCodes.timeout, message: 'timeout');
      client.fail(EdgeFunctions.listColors, failure);

      await expectLater(service.listColors(), throwsA(same(failure)));
    });
  });

  group('malformed responses', () {
    void expectInvalidResponse(Future<Object?> future) => expectLater(
          future,
          throwsA(
            isA<ServerFailure>().having((f) => f.code, 'code', ApiErrorCodes.invalidResponse),
          ),
        );

    test('missing field', () async {
      client.respond(EdgeFunctions.createSession, Map.of(Fixtures.createSession)..remove('organizerToken'));
      await expectInvalidResponse(
        service.createSession(sessionName: 'x', maxParticipants: 2, allowedColors: [1, 2]),
      );
    });

    test('wrong field type', () async {
      client.respond(EdgeFunctions.getParticipants, {...Fixtures.getParticipants, 'joinedCount': '1'});
      await expectInvalidResponse(
        service.getParticipants(sessionId: Fixtures.sessionId, organizerToken: Fixtures.organizerToken),
      );
    });

    test('null status', () async {
      client.respond(EdgeFunctions.closeSession, {...Fixtures.closeSession, 'status': null});
      await expectInvalidResponse(
        service.closeSession(sessionId: Fixtures.sessionId, organizerToken: Fixtures.organizerToken),
      );
    });

    test('malformed nested list item', () async {
      client.respond(EdgeFunctions.listColors, {
        'colors': [
          {'id': 'one', 'name': 'RED', 'hexColor': '#FF0000'},
        ],
      });
      await expectInvalidResponse(service.listColors());
    });

    test('failure message does not echo the token', () async {
      client.respond(
        EdgeFunctions.createSession,
        {...Fixtures.createSession, 'published': Fixtures.organizerToken},
      );

      try {
        await service.createSession(sessionName: 'x', maxParticipants: 2, allowedColors: [1, 2]);
        fail('expected ServerFailure');
      } on ServerFailure catch (e) {
        expect(e.message, isNot(contains(Fixtures.organizerToken)));
      }
    });
  });

  test('CreateSessionResult.toString redacts the organizer token', () async {
    client.respond(EdgeFunctions.createSession, Fixtures.createSession);
    final result = await service.createSession(sessionName: 'x', maxParticipants: 2, allowedColors: [1, 2]);

    expect(result.toString(), isNot(contains(Fixtures.organizerToken)));
  });
}
