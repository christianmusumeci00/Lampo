# Decisions

Choices made where the spec was ambiguous, and deviations forced by the real SDK.
Newest at the bottom of each section.

## FoundationModels API (verified on macOS 27.0 SDK, Xcode 27.1)

Checked against `FoundationModels.swiftmodule/arm64e-apple-macos.swiftinterface` and small probes.

| Spec name | Real API | Notes |
|---|---|---|
| `SystemLanguageModel` | `SystemLanguageModel.default`, `.availability`, `.contextSize`, `.variant` | Unavailable reasons: `deviceNotEligible`, `appleIntelligenceNotEnabled`, `modelNotReady`. Context on the test Mac: 8192 tokens, variant "AFM 3 Core Advanced". |
| `LanguageModelSession` | `init(model:instructions:)`, `init(model:transcript:)` (generic over `some LanguageModel`) | `@unchecked Sendable`. |
| `streamResponse` | `streamResponse(to:options:contextOptions:metadata:)` | Snapshots are **cumulative**; `snapshot.content` is the full text so far. |
| Image attachments | `Attachment(cgImage)` inside the `@PromptBuilder` closure (`Attachment<ImageAttachmentContent>`), sent with `streamResponse(contextOptions:) { … }` | The on-device model has the `.vision` capability (probe: read a rendered compiler error correctly). `tokenCount(for:)` **throws** on a prompt with an image (ModelManagerError 1001). |
| `PrivateCloudComputeLanguageModel` | exists, `init()`, `.availability`, `.contextSize` (async), `.quotaUsage` | Requires managed entitlement, see below. |
| `ContextOptions(reasoningLevel:)` | `ContextOptions(includeSchemaInPrompt:reasoningLevel:)`, levels `.light .moderate .deep .custom` | Passed per request, not per session. |
| `tokenCount(for:)` | `SystemLanguageModel.tokenCount(for:)` async throws | Also overloads for instructions, tools, schema. |
| Errors | `LanguageModelError` (new in 27), `SystemLanguageModel.Error.assetsUnavailable`, `LanguageModelSession.Error.concurrentRequests`, `PrivateCloudComputeLanguageModel.Error` | `LanguageModelSession.GenerationError` is deprecated in 27; not referenced (no warnings). |
| `@Generable`, `@Guide`, `Tool` | `@Generable(description:)`, `@Guide(description:)`, `session.respond(to:generating:)` | `Date` is not Generable, so dates are generated as words and parsed (M4). Regex guides need Swift 6 bare-slash regex literals; not used. |
| EventKit (macOS 14+) | `requestWriteOnlyAccessToEvents()`, `requestFullAccessToReminders()`, `authorizationStatus(for:)` → `.fullAccess/.writeOnly/.notDetermined/.denied/.restricted` | Reminders have no write-only level. Hardened Runtime needs `com.apple.security.personal-information.calendars` (covers reminders too). |

## M1

- **PCC behind a compile-time flag.** A probe without the entitlement crashed with
  `Fatal error: Missing entitlement: com.apple.developer.private-cloud-compute`. A runtime
  check can't catch a trap, so PCC code is compiled only with the `LAMPO_PCC` Swift condition,
  to be set in a build signed with the managed entitlement. Without it, "Think harder" is
  disabled with the tooltip "Not available in this build" and routing never selects the cloud.
- **Cancel leaves the session broken.** Cancelling a stream ends it *without* throwing, and the
  next request on the same session fails ("Session ended without producing a response").
  `FoundationModelConversation` keeps the transcript of the last completed turn and rebuilds the
  session from it after a cancel or error, so follow-ups after Esc keep the context.
- **Routing.** "Only on this Mac" makes explicit cloud requests fail with a clear message;
  actions merely *configured* for the cloud fall back to on-device (badge says "On Mac").
  Default for "Only on this Mac": off (the cloud is still only used on explicit request).
- **Session lifetime.** The conversation survives closing the panel and is forgotten after
  5 minutes without activity (checked when the panel opens and on submit). ⌘N starts over.
  Reason: closing by accident (click outside) shouldn't lose an answer; the spec's
  "while open or up to 5 minutes of inactivity" is read as "5 minutes of inactivity".
- **Esc** stops generation if streaming, otherwise closes the panel. Closing also stops generation.
- **⌘C** copies the answer only when the input field has no selected text, so normal text copy works.
- **"Insert ⌘↩"** is deferred to M2 with `OutputService` (needs Accessibility and clipboard restore).
- **"Go deeper"** sends a fixed follow-up prompt in the same session.
- **Panel window.** Borderless `NSPanel` (`.nonactivatingPanel`, `.fullSizeContentView`), clear
  background, SwiftUI draws the rounded glass and shadow inside a transparent margin. Height
  follows the content (measured with `onGeometryChange`), anchored at the top edge.
- **Glass.** SwiftUI `glassEffect(.regular, in:)` (available since macOS 26, so the
  `.ultraThinMaterial` fallback isn't needed on a macOS 27 target). "Reduce transparency" switches
  to an opaque `windowBackgroundColor` surface.
- **Calculator.** Local recursive-descent evaluator. Accepts `.`/`,` decimals, `×÷−`, `%` as
  /100, `^`, a few functions. Needs at least one operator or function (a bare number goes to the
  model). `:` is not division, so times like `14:30` are left to the model. Results formatted with
  the user's locale (Italian doesn't group 4-digit numbers: `1234`, `12.345`).
- **Markdown.** Own block parser (headings, lists incl. nested, quotes, fences) + SwiftUI inline
  Markdown. Unclosed fences render as code while streaming.
- **Hotkeys** fire on key-down (snappier than key-up). Disabling Lampo calls
  `KeyboardShortcuts.disable` on every registered name, which unregisters the Carbon hotkeys.
- **Localization.** Source language English (code language); Italian via `Localizable.xcstrings`.
  `scripts/check-strings.sh` syncs from build output and fails on missing Italian.
- **Signing.** Ad-hoc (`-`) for local builds; Developer ID + notarization in M5.
- **Swift isolation.** Kept the default nonisolated isolation with explicit `@MainActor`, as the
  spec asks, rather than the module-wide MainActor default.

## M2

- **Signing.** Debug builds are signed "Apple Development", Release "Developer ID Application",
  team 9K3LNS3KHP (manual style, no provisioning profile needed). A stable signature keeps the
  Accessibility permission across rebuilds; ad-hoc signing would lose it every build.
- **Reading the selection.** Accessibility first (`kAXFocusedUIElementAttribute` of the frontmost
  app → `kAXSelectedTextAttribute`). Password fields are never read. For Electron apps Lampo sets
  `AXManualAccessibility` once per process so later reads can work through AX.
- **Clipboard fallback** (Lens and silent actions only): snapshot *every* pasteboard item and type,
  wait until the hotkey modifiers are released (so ⌥⇧ don't merge into the synthetic ⌘C), post ⌘C,
  poll `changeCount` up to 150 ms, read, restore the snapshot. ⌘C/⌘V use ANSI key codes, which is
  right for QWERTY-family layouts (Italian included); other layouts are a known limitation.
- **The Glass panel never uses the clipboard fallback**: it must open instantly and, once open, it
  holds keyboard focus so a synthetic ⌘C would reach Lampo. The panel's "Selection" chip is AX-only.
- **Replacing.** AX `kAXSelectedTextAttribute` write only for native text elements, then verified by
  reading the value back. Inside web content (`AXWebArea` ancestor: Safari, Mail compose, Electron)
  Lampo pastes instead, because web views can accept the AX write without registering it for undo.
  The paste is one ⌘V of a transient pasteboard item (`org.nspasteboard.TransientType`, ignored by
  clipboard managers); the user's clipboard is restored 300 ms later unless something else wrote to it.
- **Lens focus.** The Lens is a non-activating key panel; before writing back it is ordered out and
  Lampo waits 60 ms so keystrokes reach the source app. If the source app is no longer frontmost,
  Lampo re-activates it first.
- **Text language.** The small model translated Italian text into English on "More formal" despite
  "keep its language". Built-in prompts now use a new `{{text_language}}` variable, detected on
  device with `NLLanguageRecognizer` (≥ 12 characters, confidence ≥ 0.6), and the action
  instructions repeat "same language as the text unless translating". Verified in TextEdit.
- **Prompts** fence user text in `<text>…</text>` and the action instructions say to treat it as
  content, not as instructions. `RewriteCleaner` strips preambles ("Ecco il testo corretto:"),
  wrapping quotes and leftover tags, and keeps the original's trailing newline.
- **Action names** of built-ins are seeded in the user's language on first launch and stored in
  `actions.json` like any other action (renaming works; changing system language doesn't rename them).
  Built-ins have fixed UUIDs; new built-ins in later versions are merged; deleted ones stay deleted.
- **Default shortcuts** ⌥⇧C/F/B/T/R are set as KeyboardShortcuts initial values for the built-ins
  only. Note they shadow the characters ⌥⇧ types (e.g. Ç) while Lampo is enabled.
- **Output modes.** `preview` → Lens; `replaceSilently` → HUD "Correct…" then "Done · ⌘Z to undo";
  `copy` → HUD "Copied"; `openPanel` → Glass panel with the selection as context ("Explain").
  The Lens lists selection actions except `openPanel` ones. Screen actions arrive in M3.
- **Panel extras.** "Insert ⌘↩" replaces the selection the conversation is about, or pastes at the
  cursor. ⌘⇧V attaches the clipboard as a chip. Context chips are sent once with the next question
  (the session keeps them), then cleared; the turn shows a "Selection · N words" tag.
- **Onboarding.** A permissions window opens on first launch when Accessibility is missing, and
  whenever a selection action is blocked by it. Status refreshes every second while visible.
- **QA helpers (DEBUG only).** `LAMPO_QA_ACTION=<action UUID>` runs an action 1 s after launch;
  `LAMPO_QA_AUTOREPLACE=1` confirms the Lens when the preview is ready. A Lampo started from a shell
  that has Accessibility inherits it (TCC responsibility), which makes end-to-end checks possible.

## M3

- **Window capture.** ScreenCaptureKit `SCScreenshotManager.captureImage(contentFilter:configuration:)`
  with `SCContentFilter(desktopIndependentWindow:)`: only that window is captured, so Lampo's panel and
  Lens can't appear in it even when they overlap. The window is the frontmost layer-0 window of the
  app that was frontmost when the panel opened (front-to-back order from `CGWindowListCopyWindowInfo`,
  matched by window ID). Native resolution, scaled so the longest side is ≤ 1600 px; no cursor, no shadow.
- **"Ask the screen"** is a built-in action (input `.screen`, output `.openPanel`, ⌥⇧S) with an **empty
  template**: an empty template means "open the panel with the window chip and wait for the question".
  A custom screen action with a template runs it on the screenshot right away. ⌘⇧S in the panel
  toggles the window chip. The image is sent once, with the next question; follow-ups reuse the session.
- **Screen Recording permission** is checked with `CGPreflightScreenCaptureAccess` and requested with
  `CGRequestScreenCaptureAccess` + the Privacy_ScreenCapture pane. Missing permission shows an
  actionable notice in the panel (not a silent failure). macOS may only report a new grant after
  Lampo relaunches; the permissions view says so.
- **Token budget.** Before sending, selection and clipboard are measured with `tokenCount(for:)` against
  `contextSize` minus instructions, the template/question scaffold, the session history (panel), 1000
  tokens for the answer and **1000 tokens per screenshot** (images can't be counted, see the table; a
  rough probe suggested far fewer, so this is conservative). A text that doesn't fit keeps its first ⅔
  and last ⅓, cut at word boundaries and joined by "[…]"; two texts share the room by size. If the model
  can't count, ~3 UTF-8 bytes per token is assumed. The UI says "Testo lungo: usato un estratto."
- **Truncated text is never written back.** The Lens disables Sostituisci (Copia still works) and silent
  mode refuses with a clear message, because a rewrite of an excerpt would delete the middle of the
  selection. "Pensa di più" is offered next to the notice when Private Cloud Compute is allowed; it
  resends the *untruncated* prompt (the cloud window is larger).
- **Answer language with context.** With a screenshot (or long English-looking context) the small model
  answered an Italian question in English. When a question carries context, the prompt now ends the
  context block with "Answer in <language>.": the forced language from Settings, else the question's
  own language (`NLLanguageRecognizer`), else the system language. Verified with the acceptance test.
- **Shortcut conflicts.** Recorders refuse a combination already used by another Lampo command
  (KeyboardShortcuts `shortcutValidation`); duplicates that slip in anyway (imports, defaults) are listed
  as warnings. "Ripristina predefinite" resets the panel and all action shortcuts. Deleting an action
  frees its shortcut; hotkeys are re-registered whenever actions are added or removed.
- **Action editor.** Edits are saved on every change (the JSON file is small). Built-ins are editable;
  "Ripristina azioni predefinite" brings back their original definitions and default shortcuts (only
  where the user hasn't set another). Actions without selection input (clipboard, screen, none) always
  show their result in the panel, whatever the output mode, since there's nothing to replace.
  "Prova" runs the action on an editable sample text with a fresh session; screen actions can't be
  tried there.
- **QA helper (DEBUG).** `LAMPO_QA_ACTION=<uuid>` + `LAMPO_QA_QUERY="…"` also submits the question to the
  panel 2 s after the action (used for the acceptance test with "Ask the screen").

## M4

- **The model reads words; code does the calendar maths.** A probe showed the small model copies the
  day and time words well but resolves "giovedì" to wrong dates and invents end times. So
  `@Generable` asks only for title, the day words, the start time (HH:mm) and the place, and
  `WhenParser` resolves everything deterministically in the user's calendar and time zone: ISO and
  day-first numeric dates (month-first in the US), Italian/English month names, oggi/domani/dopodomani/
  stasera, "tra N giorni", weekdays (the same weekday as today means today only if the time is still
  ahead), ranges ("dalle 14 alle 16", "from 9:30 to 11"), durations (only with "per"/"for", so
  "tra un'ora" isn't one), "e mezza"/"e un quarto", noon/midnight. Hours 1–7 without am/pm or a part
  of the day mean the afternoon. A past date without a year is next year.
- **Priority.** Start time: explicit time in the text → the model's time, only if the text hints at a
  time of day → the usual time of a meal (colazione 8:30, pranzo 13, aperitivo 19, cena 20) → the part
  of the day (mattina 9, pomeriggio 15, sera 19) → all day. Day: parsed → the model's day words parsed →
  `NSDataDetector` → today if the time is still ahead, else tomorrow. End: explicit → duration → +1 h.
  The place is kept only if it appears in the text. Texts over 25 words go in the notes.
- **Titles.** "Ricordami di …" is stripped. If the model returns a lone verb ("Chiamare"), the title is
  taken from the text with the day and time words removed ("Chiamare Anna per il preventivo").
- **Always confirmed.** Every draft opens as an editable card in the panel ("Non viene aggiunto nulla
  finché non confermi"); EventKit is called only from Aggiungi (⌘↩). Permission is requested on the
  first confirm, not at launch; a refusal shows the reason and "Apri Impostazioni di Sistema".
  Events use **write-only** access (Lampo can't read calendars); reminders need full access. Items go
  to the default calendar / list; a reminder with a time gets an alarm at that time.
- **If the model can't help** (unavailable, refusal), the card is built from the parser alone and is
  still editable. Extraction is always on device, with a fresh session, and never uses PCC.
- **Input.** With selected text (AX, or the ⌘C fallback) the card opens directly; otherwise the panel
  shows a "Crea evento" chip and asks for a description. Structured actions don't use the prompt
  template; the action editor hides it and explains this.
- **History (off by default).** `HistoryStore` keeps up to 200 finished requests (panel turns, Lens and
  silent/copy results; source, input, output, route) in `Application Support/Lampo/history.json`,
  mode 0600, inputs and outputs clipped at 4000 characters. Turning it off, or "Cancella cronologia",
  deletes the file. Settings › Privacy has the switch, a searchable viewer with copy/delete, and the
  Calendars/Reminders status rows.
- **"Solo sul Mac" is tested with PCC compiled in.** `Preferences.privateCloudInBuild` is a test seam;
  `OnlyOnMacTests` checks that panel questions, "Pensa di più", "Approfondisci", PCC-configured actions,
  the Lens and drafts create no `.privateCloud` conversation, and that switching it off does.
  The `LAMPO_PCC` build compiles cleanly (not run: it needs the managed entitlement).
- **QA helper (DEBUG).** `LAMPO_QA_DRAFT=event|reminder` + `LAMPO_QA_QUERY="…"` opens the card for that
  text with the real extraction, without reading the selection.

## M5

- **`lampo://ask?q=…`** opens the panel and asks the question with **no context attached** (no selection,
  no screen), so a link from a web page can't make Lampo read anything. Other commands are ignored; a link
  can't run an action or replace text. Questions are cut at 2000 characters. The handler is installed with
  `NSAppleEventManager` in `applicationWillFinishLaunching` (a link that launches Lampo arrives before
  didFinishLaunching) and again after start; early links are queued until the app has started.
- **App Intents.** "Chiedi a Lampo" (`AskLampoIntent`) and "Esegui azione Lampo" (`RunLampoActionIntent`,
  with a `LampoActionEntity` per action) run in the background (`supportedModes = .background`) and
  return the text. The logic is in `ShortcutsService` (tested with mocks); the intents get it through
  `AppDependencyManager` / `@Dependency`. Asks run on device in a fresh session (calculator first).
  Screen actions aren't offered (they need the window you're in). "Crea evento/promemoria" open the
  confirmation card: Shortcuts never writes to the calendar. Phrases are localized in
  `AppShortcuts.xcstrings`.
- **Sparkle 2.10** with the standard user driver and gentle reminders (Lampo has no Dock icon: a scheduled
  update shows as "Aggiornamento disponibile…" in the menu). `SUFeedURL`, `SUPublicEDKey`, website and
  repository URLs come from build settings that are **empty in development builds**, so the updater
  doesn't start there; `scripts/release.sh` fills them from `Packaging/release.env` (git-ignored, not
  secret). Automatic checks stay off until the user agrees (Sparkle asks on the second launch);
  `SUEnableSystemProfiling` is false. This is the only network use besides PCC.
- **Release.** `scripts/release.sh`: tests → Release archive (Developer ID, Hardened Runtime, timestamp)
  → export (`Packaging/ExportOptions.plist`) → signature checks (Developer ID, runtime flag, no
  `get-task-allow`, calendars entitlement) → zip (`ditto`) → `notarytool --wait` + staple → re-zip →
  `generate_appcast` (starting from the published feed so history is kept; EdDSA key from the keychain)
  → cask from `Packaging/Homebrew/lampo.rb.template`. Build number = commit count. A real release
  refuses a dirty tree. Uploads are left to the user. Verified locally with `--skip-notarize --skip-appcast`.
- **Homebrew cask** uses the zip, `depends_on macos: ">= :golden_gate"` (macOS 27), `arch: :arm64`,
  `auto_updates true` (Sparkle) and a Sparkle livecheck.
- **App icon** is drawn in code (`scripts/make-icon.swift`): blue squircle on the macOS grid with a
  hand-drawn bolt. SF Symbols may not be used in app icons (license).
- **Welcome screen** on first launch (`didShowWelcome`): tagline, the three shortcuts with the user's
  current keys, the privacy promise, a warning if the model is unavailable, then the permissions page.
  It replaces the old first-launch permissions window; that window is still used when an action needs a
  permission.
- **README** is in Italian with a short English summary. The panel GIF and the event card are captured
  from Lampo's own window only. The Lens and screen GIFs need other apps on screen and are left to record
  by hand (`docs/media/README.md`).
- **Fix found while recording:** Italian button labels ("Approfondisci") wrapped inside 34 pt buttons;
  `LampoButtonStyle` now keeps labels on one line.
