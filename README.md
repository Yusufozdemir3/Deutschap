# Deutschap

German for Turkish speakers. **Discover** it in connected stories, **keep** every word with the sentence you met it in, **remember** it with honest spaced repetition, and **use** it in realistic conversations.

Current version: **v0.4.0**. Runs on Android, iOS and the web.

## What's inside

| Content | Amount |
| --- | --- |
| Learning path (A1–B2) | 36 units, 72 lessons |
| Grammar concepts | 44 |
| Lexicon | 852 words |
| Story | 14 episodes |
| Conversation scenarios | 24 |
| Reading texts | 33 |
| Listening tracks | 20 |
| "Traps" lessons for Turkish speakers | 20 |

Features: spaced-repetition review, mistake-based practice, level mini exams, personal vocabulary library, study and review reminders, backup file save/restore, text-to-speech.

## Local-first, with optional accounts

All learner data lives on the device (SQLite; on the web via wasm + IndexedDB). The app works fully offline without an account.

An optional account (Supabase) adds sign-in with an e-mailed code or Google, sync between devices with revision checks and conflict resolution, and account deletion. Row-level security in [`supabase/migrations`](supabase/migrations) limits each user to their own data.

## Run
```bash
flutter pub get          # on Windows without Developer Mode this prints a symlink warning; packages still resolve
flutter run -d chrome    # web (SQLite via wasm + IndexedDB)
flutter run              # Android/iOS device or emulator
```

To enable accounts, copy `supabase.example.json` to `supabase.local.json` (git-ignored), fill in your project URL and publishable key, then:
```bash
flutter run --dart-define-from-file=supabase.local.json
```

## Test and analyse
```bash
flutter analyze --no-pub
flutter test --no-pub
```

## Build
```bash
flutter build web --no-pub
flutter build apk --release      # needs Android licences accepted
flutter build ipa                # needs macOS + Xcode
```

## Layout
```
lib/
  app/         app shell, router, providers, theme (design tokens)
  core/        database + migrations, kv store, clock/ids, text-to-speech
  content/     curated content models, loader, validator
  learning/    tokenizer, lexicon lookup, answer checker
  features/    onboarding, home, learn, lesson, grammar, stories, conversation,
               reading, listening, review, practice, exam, vocabulary, account, ...
  ui/          shared widgets, tappable German text
assets/content/  lexicon, grammar, A1–B2 paths, stories, scenarios, reading, listening (JSON)
supabase/      database migrations for optional accounts
test/          content, domain, data, widget/journey tests
```

## How it was built

Deutschap was developed by Yusuf Özdemir with AI-assisted development (Claude). Product scope, content structure and feature decisions are his; the code was written with Claude's help.
