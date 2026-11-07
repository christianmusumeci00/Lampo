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
