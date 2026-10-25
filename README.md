# Deutschap

German for Turkish speakers. **Discover** it in connected stories, **keep** every word with the sentence you met it in, **remember** it with honest spaced repetition, and **use** it in realistic conversations.

v0.2 is a local-first A1–A2 foundation (with the first B1 units): no account, no network, all learner data on the device.

## Run
```bash
flutter pub get          # on Windows without Developer Mode this prints a symlink warning; packages still resolve
flutter run -d chrome    # web (SQLite via wasm + IndexedDB)
flutter run              # Android/iOS device or emulator
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
               reading, discover, vocabulary, review, progress, profile, settings
  ui/          shared widgets, tappable German text
assets/content/  lexicon, grammar, A1 and A2 paths, stories, scenarios, reading, listening, discover (JSON)
docs/          plan, ADRs, data model, review engine, AI design, content schema,
               design system, testing, limitations, release checklist
test/          content, domain, data, widget/journey tests
```

## Documentation
Start with [docs/PLAN.md](docs/PLAN.md) (product and architecture answers A–L), then [docs/KNOWN_LIMITATIONS.md](docs/KNOWN_LIMITATIONS.md).
