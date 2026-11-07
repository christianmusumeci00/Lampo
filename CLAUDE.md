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
```

Run for manual QA (start from `/`, otherwise macOS asks for Documents access because
the process cwd is inside ~/Documents):

```bash
cd / && LAMPO_OPEN_PANEL=1 LAMPO_QA_QUERY="..." ~/Documents/Lampo/build/DerivedData/Build/Products/Debug/Lampo.app/Contents/MacOS/Lampo
```
`LAMPO_OPEN_PANEL` / `LAMPO_QA_QUERY` are DEBUG-only helpers in `AppDelegate`.

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

## Milestones

M1 skeleton ✅ · M2 lens & selection actions · M3 screen context & full settings ·
M4 structured output & cloud · M5 polish & launch. One commit per milestone, green build and tests.
