import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../content/content_bundle.dart';
import '../content/content_updates.dart';
import '../content/json_utils.dart';
import '../core/audio/speech_service.dart';
import '../core/clock.dart';
import '../core/db/app_database.dart';
import '../core/db/kv_store.dart';
import '../features/conversation/domain/conversation_engine.dart';
import '../features/conversation/domain/error_detectors.dart';
import '../features/profile/data/profile_repository.dart';
import '../features/profile/domain/learner_profile.dart';
import '../features/progress/data/progress_repository.dart';
import '../features/progress/data/stats_repository.dart';
import '../features/reading/data/reading_repository.dart';
import '../features/settings/data/data_repository.dart';
import '../features/vocabulary/data/vocab_repository.dart';

class AppServices {
  const AppServices({required this.database, required this.content, this.bundledSources = const {}, this.overrides});
  final AppDatabase database;
  final ContentBundle content;

  /// Content files shipped with the app (the base for updates).
  final Map<String, String> bundledSources;

  /// Downloaded content in use, if any.
  final ContentOverrides? overrides;
}

/// Opens the database and parses content. Shown as the splash state;
/// failures are shown with a retry button instead of crashing.
final bootstrapProvider = FutureProvider<AppServices>((ref) async {
  final results = await Future.wait<Object>([
    AppDatabase.open(),
    ContentBundle.loadSources(rootBundle),
  ]);
  final database = results[0] as AppDatabase;
  final bundled = results[1] as Map<String, String>;
  ref.onDispose(database.close);
  // Downloaded content replaces bundled files of the same name. If it no
  // longer parses (e.g. after an app update changed the schema), it is
  // dropped and the bundled content is used.
  final kv = KvStore(database.db);
  var overrides = await ContentOverrides.load(kv);
  ContentBundle content;
  try {
    content = ContentBundle.fromSources({...bundled, ...?overrides?.files});
  } on ContentFormatException {
    await ContentOverrides.clear(kv);
    overrides = null;
    content = ContentBundle.fromSources(bundled);
  }
  return AppServices(database: database, content: content, bundledSources: bundled, overrides: overrides);
});

final databaseProvider = Provider<Database>((ref) => ref.watch(bootstrapProvider).requireValue.database.db);
final contentProvider = Provider<ContentBundle>((ref) => ref.watch(bootstrapProvider).requireValue.content);

final vocabRepositoryProvider = Provider<VocabRepository>(
  (ref) => VocabRepository(ref.watch(databaseProvider), clock: ref.watch(clockProvider), ids: ref.watch(idGeneratorProvider)),
);
final progressRepositoryProvider = Provider<ProgressRepository>(
  (ref) => ProgressRepository(ref.watch(databaseProvider), clock: ref.watch(clockProvider), ids: ref.watch(idGeneratorProvider)),
);
final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(databaseProvider), clock: ref.watch(clockProvider)),
);
final readingRepositoryProvider = Provider<ReadingRepository>(
  (ref) => ReadingRepository(ref.watch(databaseProvider), clock: ref.watch(clockProvider), ids: ref.watch(idGeneratorProvider)),
);
final statsRepositoryProvider = Provider<StatsRepository>(
  (ref) => StatsRepository(ref.watch(databaseProvider), clock: ref.watch(clockProvider)),
);
final dataRepositoryProvider = Provider<DataRepository>(
  (ref) => DataRepository(ref.watch(databaseProvider), clock: ref.watch(clockProvider)),
);

final kvStoreProvider = Provider<KvStore>((ref) => KvStore(ref.watch(databaseProvider)));

final speechServiceProvider = Provider<SpeechService>((ref) {
  final rate = ref.watch(profileProvider.select((p) => p.valueOrNull?.speechRate ?? 0.45));
  final voice = ref.watch(profileProvider.select((p) => p.valueOrNull?.voiceName));
  return PlatformSpeechService(normalRate: rate, preferredVoice: voice);
});

final conversationEngineProvider = Provider<ConversationEngine>(
  (ref) => OfflineScenarioEngine(ErrorDetectors(ref.watch(contentProvider).lexicon)),
);

/// Bumped after every learner-data write; read-side providers watch it so
/// screens refresh without each feature wiring its own notifications.
final dataRevisionProvider = StateProvider<int>((ref) => 0);

extension DataRevision on Ref {
  void bumpData() => read(dataRevisionProvider.notifier).state++;
}

extension WidgetDataRevision on WidgetRef {
  void bumpData() => read(dataRevisionProvider.notifier).state++;
}

class ProfileNotifier extends AsyncNotifier<LearnerProfile> {
  @override
  Future<LearnerProfile> build() => ref.watch(profileRepositoryProvider).load();

  Future<void> edit(LearnerProfile Function(LearnerProfile p) change) async {
    final current = state.valueOrNull ?? await future;
    final next = change(current);
    state = AsyncData(next);
    await ref.read(profileRepositoryProvider).save(next);
  }

  Future<void> reload() async {
    state = AsyncData(await ref.read(profileRepositoryProvider).load());
  }
}

final profileProvider = AsyncNotifierProvider<ProfileNotifier, LearnerProfile>(ProfileNotifier.new);

final savedLexemeIdsProvider = FutureProvider<Set<String>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(vocabRepositoryProvider).savedLexemeIds();
});

final dueCountProvider = FutureProvider<int>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(vocabRepositoryProvider).dueCount();
});
