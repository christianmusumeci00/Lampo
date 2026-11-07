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
| Image attachments | `Attachment(cgImage)` inside the `@PromptBuilder` closure (`Attachment<ImageAttachmentContent>`) | Use in M3. |
| `PrivateCloudComputeLanguageModel` | exists, `init()`, `.availability`, `.contextSize` (async), `.quotaUsage` | Requires managed entitlement, see below. |
| `ContextOptions(reasoningLevel:)` | `ContextOptions(includeSchemaInPrompt:reasoningLevel:)`, levels `.light .moderate .deep .custom` | Passed per request, not per session. |
| `tokenCount(for:)` | `SystemLanguageModel.tokenCount(for:)` async throws | Also overloads for instructions, tools, schema. |
| Errors | `LanguageModelError` (new in 27), `SystemLanguageModel.Error.assetsUnavailable`, `LanguageModelSession.Error.concurrentRequests`, `PrivateCloudComputeLanguageModel.Error` | `LanguageModelSession.GenerationError` is deprecated in 27; not referenced (no warnings). |
| `@Generable`, `@Guide`, `Tool` | present | Used in M4. |

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
