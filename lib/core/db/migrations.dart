import 'package:sqflite/sqflite.dart';

/// Ordered schema migrations. Index i upgrades from version i to i+1.
/// Never edit a released migration; append a new one instead.
/// See docs/DATA_MODEL.md.
final List<Future<void> Function(DatabaseExecutor db)> migrations = [
  _v1,
];

int get schemaVersion => migrations.length;

Future<void> _v1(DatabaseExecutor db) async {
  const statements = [
    '''
    CREATE TABLE kv (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )''',
    '''
    CREATE TABLE learner_profile (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      data TEXT NOT NULL,
      updated_at INTEGER NOT NULL
    )''',
    '''
    CREATE TABLE vocab_entries (
      id TEXT PRIMARY KEY,
      lexeme_id TEXT UNIQUE,
      headword TEXT NOT NULL,
      lemma TEXT NOT NULL,
      kind TEXT NOT NULL,
      article TEXT,
      plural TEXT,
      meaning_tr TEXT NOT NULL,
      meaning_en TEXT,
      note TEXT,
      status TEXT NOT NULL,
      paused INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )''',
    'CREATE INDEX idx_vocab_lemma ON vocab_entries(lemma)',
    'CREATE INDEX idx_vocab_status ON vocab_entries(status)',
    '''
    CREATE TABLE vocab_contexts (
      id TEXT PRIMARY KEY,
      entry_id TEXT NOT NULL REFERENCES vocab_entries(id) ON DELETE CASCADE,
      source_type TEXT NOT NULL,
      source_id TEXT NOT NULL DEFAULT '',
      source_title TEXT,
      sentence TEXT NOT NULL DEFAULT '',
      sentence_tr TEXT,
      created_at INTEGER NOT NULL,
      UNIQUE (entry_id, source_type, source_id, sentence)
    )''',
    'CREATE INDEX idx_contexts_entry ON vocab_contexts(entry_id)',
    '''
    CREATE TABLE review_cards (
      entry_id TEXT NOT NULL REFERENCES vocab_entries(id) ON DELETE CASCADE,
      card_type TEXT NOT NULL,
      ease REAL NOT NULL,
      interval_days REAL NOT NULL,
      reps INTEGER NOT NULL,
      lapses INTEGER NOT NULL,
      due_at INTEGER NOT NULL,
      last_reviewed_at INTEGER,
      last_unaided_success_at INTEGER,
      last_grade INTEGER,
      PRIMARY KEY (entry_id, card_type)
    )''',
    'CREATE INDEX idx_cards_due ON review_cards(due_at)',
    '''
    CREATE TABLE review_events (
      id TEXT PRIMARY KEY,
      entry_id TEXT NOT NULL REFERENCES vocab_entries(id) ON DELETE CASCADE,
      card_type TEXT NOT NULL,
      grade INTEGER NOT NULL,
      assisted INTEGER NOT NULL,
      latency_ms INTEGER,
      reviewed_at INTEGER NOT NULL,
      was_due INTEGER NOT NULL,
      prev_interval REAL NOT NULL,
      new_interval REAL NOT NULL
    )''',
    'CREATE INDEX idx_events_time ON review_events(reviewed_at)',
    '''
    CREATE TABLE collections (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      created_at INTEGER NOT NULL
    )''',
    '''
    CREATE TABLE collection_items (
      collection_id TEXT NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
      entry_id TEXT NOT NULL REFERENCES vocab_entries(id) ON DELETE CASCADE,
      added_at INTEGER NOT NULL,
      PRIMARY KEY (collection_id, entry_id)
    )''',
    '''
    CREATE TABLE lesson_progress (
      lesson_id TEXT PRIMARY KEY,
      status TEXT NOT NULL,
      step_index INTEGER NOT NULL DEFAULT 0,
      correct INTEGER NOT NULL DEFAULT 0,
      total INTEGER NOT NULL DEFAULT 0,
      completed_at INTEGER,
      updated_at INTEGER NOT NULL
    )''',
    '''
    CREATE TABLE story_progress (
      episode_id TEXT PRIMARY KEY,
      story_id TEXT NOT NULL,
      node_id TEXT NOT NULL,
      flags TEXT NOT NULL,
      history TEXT NOT NULL,
      status TEXT NOT NULL,
      quiz_correct INTEGER,
      quiz_total INTEGER,
      completed_at INTEGER,
      updated_at INTEGER NOT NULL
    )''',
    '''
    CREATE TABLE reading_docs (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      body TEXT NOT NULL,
      source TEXT NOT NULL,
      builtin_id TEXT UNIQUE,
      position INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )''',
    '''
    CREATE TABLE exercise_attempts (
      id TEXT PRIMARY KEY,
      activity_type TEXT NOT NULL,
      activity_id TEXT NOT NULL,
      item_id TEXT NOT NULL,
      correct INTEGER NOT NULL,
      assisted INTEGER NOT NULL,
      created_at INTEGER NOT NULL
    )''',
    '''
    CREATE TABLE conversation_sessions (
      id TEXT PRIMARY KEY,
      scenario_id TEXT NOT NULL,
      mode TEXT NOT NULL,
      status TEXT NOT NULL,
      transcript TEXT,
      goals_done TEXT NOT NULL,
      corrections TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )''',
    '''
    CREATE TABLE activity_log (
      id TEXT PRIMARY KEY,
      kind TEXT NOT NULL,
      ref_id TEXT,
      summary TEXT,
      created_at INTEGER NOT NULL
    )''',
    'CREATE INDEX idx_activity_time ON activity_log(created_at)',
  ];
  for (final s in statements) {
    await db.execute(s);
  }
}
