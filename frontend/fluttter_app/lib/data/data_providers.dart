import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import 'repositories/organizer_repository.dart';
import 'repositories/participant_repository.dart';
import 'services/participant_service.dart';
import 'services/session_service.dart';

final sessionServiceProvider = Provider<SessionService>(
  (ref) => SessionService(ref.watch(apiClientProvider)),
  name: 'sessionServiceProvider',
);

final participantServiceProvider = Provider<ParticipantService>(
  (ref) => ParticipantService(ref.watch(apiClientProvider)),
  name: 'participantServiceProvider',
);

final participantRepositoryProvider = Provider<ParticipantRepository>(
  (ref) => ParticipantRepository(
    service: ref.watch(participantServiceProvider),
    store: ref.watch(credentialStoreProvider),
  ),
  name: 'participantRepositoryProvider',
);

/// Kept alive for the whole app: it holds an unsaved created session in memory
/// (see `OrganizerRepository.retrySavePendingSession`), which must not be lost
/// to auto-dispose.
final organizerRepositoryProvider = Provider<OrganizerRepository>(
  (ref) => OrganizerRepository(
    service: ref.watch(sessionServiceProvider),
    store: ref.watch(credentialStoreProvider),
  ),
  name: 'organizerRepositoryProvider',
);
