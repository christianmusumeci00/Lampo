# Lampo — notes for Claude

macOS 27 menu-bar agent (`LSUIElement`) that brings Apple's on-device model
(FoundationModels) to the user's context. Product spec: the implementation prompt
in the first session; decisions and API deviations live in `docs/DECISIONS.md`.

## Commands

```bash
xcodegen generate                       # after adding/removing files or editing project.yml
xcodebuild -project Lampo.xcodeproj -scheme Lampo -derivedDataPath build/DerivedData \
  -clonedSourcePackagesDirPath build/SourcePackages build
xcodebuild -project Lampo.xcodeproj -scheme Lampo -derivedDataPath build/DerivedData \
  -clonedSourcePackagesDirPath build/SourcePackages test
scripts/check-strings.sh                # after a build: sync String Catalog, list missing Italian
scripts/release.sh --skip-notarize --skip-appcast   # local signed build; full release needs Packaging/release.env
swift scripts/make-icon.swift           # re-render the app icon
```

Run for manual QA (start from `/`, otherwise macOS asks for Documents access because
the process cwd is inside ~/Documents):

```bash
cd / && LAMPO_OPEN_PANEL=1 LAMPO_QA_QUERY="..." ~/Documents/Lampo/build/DerivedData/Build/Products/Debug/Lampo.app/Contents/MacOS/Lampo
```
`LAMPO_OPEN_PANEL` / `LAMPO_QA_QUERY` / `LAMPO_QA_ACTION=<uuid>` / `LAMPO_QA_AUTOREPLACE=1` /
`LAMPO_QA_DRAFT=event|reminder` (opens the confirmation card for `LAMPO_QA_QUERY`) / `LAMPO_QA_DICTATION_FILE=<audio>` are
DEBUG-only helpers (`AppDelegate`, `LensViewModel`); `LAMPO_QA_ACTION` + `LAMPO_QA_QUERY` asks a question
after a panel action ("Ask the screen" is `6C0A0008-0000-4000-8000-00000000C0DE`). Launched from a shell that has Accessibility,
Lampo inherits it, so selection read/replace can be checked end to end (e.g. on a scratch TextEdit doc).
Signing: team 9K3LNS3KHP, "Apple Development" (Debug) / "Developer ID Application" (Release).

## Conventions

- Swift 6 language mode, strict concurrency complete, **zero warnings**. Default isolation is
  nonisolated: UI types and view models are explicitly `@MainActor`; view models are `@Observable`.
- Every system-touching service sits behind a protocol with a mock in `LampoTests/Mocks.swift`
  (`ModelService`, `PasteboardClient`, `HotkeyBackend`, …). Tests never need permissions or the model.
- Tests use Swift Testing (`@Test`, `#expect`). The test bundle is hosted by the app;
  `RuntimeEnvironment.isRunningTests` keeps the app from starting hotkeys/panels.
- Code and comments in English. UI strings are English keys in `Localizable.xcstrings`
  with Italian translations; every new string needs an `it` entry (`scripts/check-strings.sh`).
- Logging: `Log.<category>` (`os.Logger`). Never log user content.
- Design constants only in `Support/DesignTokens.swift`. SF Symbols only.
- `.xcodeproj` is generated: edit `project.yml`, never the project.

## Key decisions (details in docs/DECISIONS.md)

- Model streaming is exposed as `AsyncThrowingStream<String, Error>` of **cumulative** text.
- After a cancelled/failed stream, `FoundationModelConversation` rebuilds the
  `LanguageModelSession` from the last good transcript (the framework leaves it unusable).
- Private Cloud Compute code compiles only with `LAMPO_PCC`: without the managed entitlement
  `com.apple.developer.private-cloud-compute` FoundationModels **traps** on any PCC call.
- No App Sandbox (Accessibility); Hardened Runtime on; distribution outside the Mac App Store.
- Panel hotkey ⌥⇧Space (⌥Space clashes with Codex); `PanelShortcutMigration` moves old installs once.
- Translate uses Apple's Translation framework, not the model (`translationTarget`, `TranslationPlanner`); Rewrite
  uses `{{tone}}`. Actions can be turned off (`isEnabled`); `actions.json` v2 turns off the Writing Tools duplicates once.
- Dictate (⌥⇧D): `SpeechAnalyzer` + `DictationTranscriber` on device (`DictationEngine`), cleaned by the model, pasted at
  the cursor (`DictationController`). Tap = toggle, hold = push-to-talk, Esc cancels. DEBUG `LAMPO_QA_DICTATION_FILE=<audio>`.
- Selection: AX first, ⌘C clipboard fallback (Lens/silent only) with full clipboard snapshot/restore.
  Replace: AX write for native text (verified), one ⌘V elsewhere (web content) so ⌘Z always works.
- Built-in action prompts use `{{text_language}}` (NLLanguageRecognizer): the small model otherwise
  drifts to English. Panel questions with context end the context block with "Answer in <language>."
- Screen: `SCContentFilter(desktopIndependentWindow:)` (Lampo never in the shot), ≤ 1600 px, attached with
  `Attachment(cgImage)`. `tokenCount` can't count images: `ContextBudget` reserves 1000 tokens each.
- `ContextBudget` cuts long selection/clipboard to head ⅔ + tail ⅓; truncated input is never written back
  (Lens Replace off, silent mode refuses).
- Create event/reminder: `@Generable` extracts only words (title, day words, HH:mm, place); `WhenParser`
  resolves dates in the user's calendar. Nothing reaches EventKit without the confirmation card.
  Events use write-only access. Extraction is on device only.
- History is off by default (`HistoryStore`, Application Support/Lampo/history.json, 200 entries);
  turning it off deletes the file. `Preferences.privateCloudInBuild` is the test seam for "Only on Mac".
- `lampo://ask?q=` asks with no context attached; App Intents are thin wrappers over `ShortcutsService`
  (registered with `AppDependencyManager`). Shortcut phrases are in `AppShortcuts.xcstrings`.
- Sparkle settings (`LAMPO_FEED_URL`, `LAMPO_SPARKLE_PUBLIC_KEY`, …) are empty build settings in dev builds,
  so the updater doesn't start; release.sh passes them. Never notarize or upload without the user's OK.

## Milestones

M1 skeleton ✅ · M2 lens & selection actions ✅ · M3 screen context & full settings ✅ ·
M4 structured output & cloud ✅ · M5 polish & launch ✅. One commit per milestone, green build and tests.
