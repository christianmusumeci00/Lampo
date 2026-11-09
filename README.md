# Lampo

**Your Mac's intelligence, one shortcut away. On your text, your screen, your apps.**

Lampo is a menu bar app for macOS 27 that brings Apple's on-device language model to wherever you are
working: the text you select in any app, the window in front of you, what you just copied, what you say.
Select, press a key, and the text changes in place. No chat window to copy into, no account, no API key,
no subscription.

![The Lampo panel: a question, the answer streaming in, and the "On Mac" badge (Italian UI)](docs/media/vetro.gif)

The app is available in **English** (default) and **Italian**.

## Why Lampo

1. **Instant.** The panel opens in a blink and answers right away: no network round trip, no loading.
2. **Works offline.** On a train, on a plane, without Wi-Fi: the model is already on your Mac.
3. **Free, forever.** No subscription, no request limits, no API keys, no sign-up.
4. **Private for real.** What you write and select never leaves your Mac. Apple's Private Cloud Compute
   is used only when you ask for it, and a badge always tells you where every answer was computed.
5. **Works where you are.** Select, press a shortcut, and the result replaces the text in place, in any
   app: Mail, Notes, Pages, Safari, and also Chrome, Slack, VS Code and other Electron apps.
6. **Sees what you see.** Ask about any window: an error message, a chart, a form, a web page.
7. **Hears you.** Hold a key, talk, release: clean, punctuated text appears at the cursor.
8. **Turns text into things.** A sentence becomes a calendar event, a list becomes reminders, an email
   signature becomes a contact, rows of text become a table, always behind a confirmation card.
9. **Yours to shape.** Create your own actions, each with its own prompt and shortcut.
10. **Native and light.** Built in Swift for macOS, discreet in the menu bar, minimal resource usage.

## What Lampo brings to Italy (and the rest of the EU)

Apple's new **Siri AI**, the version that understands what is on your screen and works with your
personal context, launched in September 2026 **in beta and in English only**. French, Japanese, Korean,
Portuguese and Spanish were announced next; **Italian is not on the list**. On iPhone, iPad and Apple
Watch, Siri AI is not available in the EU at all for now
([Apple Newsroom](https://www.apple.com/newsroom/2026/09/siri-ai-a-profoundly-more-capable-and-personal-assistant-is-here/)).

Apple Intelligence itself, including the on-device model that apps can use, does support Italian. Lampo
builds on that model, so on a Mac set to Italian you can already:

- **ask about what's on your screen, in Italian** ("cosa significa questo errore?", "riassumi questa
  pagina"), with the window's text read on the Mac so codes and figures come through exactly;
- **correct, rewrite and translate the text you select in any app, with one keystroke**, including the
  apps where Apple's Writing Tools don't appear (Chrome, Slack, VS Code, Electron apps);
- **draft replies in the language of the message** while you give instructions in Italian;
- **dictate in Italian** and get clean text, without hesitations, typed at the cursor;
- **turn Italian sentences into events and reminders**: "cena con Marco giovedì alle 20" → the right day
  and time in your calendar, after you confirm.

Everything runs on the Mac, under European privacy expectations: no data leaves your computer unless you
explicitly ask for Private Cloud Compute.

## Lampo vs. what macOS already has

| | Apple Writing Tools | Siri AI (Sept 2026) | **Lampo** |
|---|---|---|---|
| Correct and rewrite selected text | ✓ from the context menu, in supported apps | | ✓ one shortcut, in any app, ⌘Z to undo |
| Ask about the current window | | ✓ English only (beta) | ✓ in any language Apple Intelligence supports, Italian included |
| Translate with a shortcut | | | ✓ Apple Translation, on device |
| Dictate and clean up | macOS Dictation types what you say | | ✓ on device, hesitations removed, typed at the cursor |
| Event / reminder / contact / table from text | | | ✓ with a confirmation card |
| Custom actions with your own prompts | | | ✓ |
| Shows where each answer ran | | | ✓ "On Mac" / "Private Cloud" badge |

## Features

| Action | Shortcut |
|---|---|
| Open Lampo (the panel) | ⌥⇧Space |
| Correct | ⌥⇧C |
| Rewrite | ⌥⇧R |
| Translate | ⌥⇧T |
| Reply | ⌥⇧M |
| Dictate | ⌥⇧D (hold to talk, or press once to start and again to stop) |
| Ask the screen | ⌥⇧S |
| Create event | ⌥⇧E |
| Create reminder | ⌥⇧P |
| Extract | ⌥⇧X |

Every shortcut can be changed in Settings › Shortcuts; Lampo warns you when a shortcut is already taken.

### The panel: ask from any app

Press **⌥⇧Space** and the panel opens above the app you are using, without taking it over. Type a
question and the answer streams in. Text you have selected, your clipboard or the front window can be
attached as context (they show as chips you can remove). Then copy the answer (⌘C), insert it into the
app below as plain text (⌘↩), ask a follow-up, "Go deeper", or "Think harder" with Private Cloud Compute
when it is available. Calculations ("12 * 3.5") are computed by Lampo itself, without the model.

### The Lens: rewrite in place

Select text in any app and press an action's shortcut. The Lens shows a preview next to the selection;
↩ replaces the text in place and ⌘Z brings it back. Tab or → moves to the next action. Your clipboard is
left as it was.

- **Correct** (⌥⇧C) fixes spelling, grammar and punctuation, keeping the text's language.
- **Rewrite** (⌥⇧R) has four tones: clearer, formal, friendly, shorter. Lampo remembers the last one.
- **Translate** (⌥⇧T) uses Apple's Translation framework, not the language model: it is more accurate,
  runs on the Mac and works even without Apple Intelligence. It translates into your language, or, when
  the text is already in your language, into the language you picked last. Languages are downloaded in
  System Settings › General › Language & Region › Translation Languages.

Long selections are summarized from an excerpt; Lampo tells you and never writes a truncated text back.

### Reply

Select an email or a message and press **⌥⇧M**: Lampo drafts a reply in the message's language, with no
signature and no invented dates or promises. Refine it in the panel in your own language ("shorter",
"say Thursday at 3 works"): the reply stays in the message's language. ⌘↩ types it at the cursor, never
over the selected message.

### Dictate

Hold **⌥⇧D**, talk, and release: Lampo transcribes on the Mac with Apple's speech model, removes
hesitations ("uhm", "ehm"), adds punctuation and types the text at the cursor in any app (⌘Z removes it).
For long dictation press ⌥⇧D once, talk, and press it again. Esc cancels. The speech model is downloaded
once from Apple, only after you confirm.

### Ask the screen

**⌥⇧S** captures only the window you are using (never Lampo, never the rest of the screen) and opens the
panel ready for your question. The window's text is also read on the Mac (Apple's Vision text
recognition) and sent along with the image, so codes, totals and small print arrive exactly.

### Create event and Create reminder

Select "dinner with Marco Thursday at 8pm" (or an email with a date) and press **⌥⇧E**: Lampo prepares
the event with day, time, place and title. **Nothing is added until you confirm**, and everything is
editable on the card. For events Lampo asks for write-only access, so it can't read your calendars.
**⌥⇧P** does the same for Reminders. A list ("milk, call Luca tomorrow, pay the bill Friday") becomes one
card with several items, each with its own date; untick the ones you don't want and confirm once.

![The confirmation card of "Create event" (Italian UI)](docs/media/crea-evento.png)

### Extract

Select some text and press **⌥⇧X**: Lampo works out what it contains and puts it on a card.

- **Contact** (an email signature): name, company, phones, emails, address. "Add to Contacts" opens it in
  Contacts, which asks you to confirm: Lampo never reads or changes your address book.
- **Table** (rows of data): "Copy" pastes as cells in Numbers or Excel; "Copy as Markdown" too.
- **To-dos** (an email full of requests): they become reminders to confirm, with their due dates.

Wrong type? Switch it at the top of the card. Without Apple Intelligence, simple rules (phone numbers,
emails, separated columns) still work, and Lampo tells you.

### Your own actions

In Settings › Actions you can turn actions on and off, edit their prompts, and create new ones: with your
own prompt (variables such as `{{selection}}`, `{{text_language}}`, `{{language}}`, `{{tone}}`), with
Apple Translation into a fixed language ("Translate to German"), or with dictation as input. Each action
can show a preview, replace the text right away, copy the result, or open the answer in the panel. "Try"
runs it on a sample text before you use it.

"More formal", "Shorter" and "Summarize" are off by default, because Rewrite and Apple's Writing Tools
already cover them; you can turn them back on.

### Shortcuts app and links

- The **Shortcuts** app gets "Ask Lampo" (returns the answer) and "Run Lampo Action" (runs an action on a
  text and returns the result).
- The **`lampo://ask?q=…`** link opens the panel and asks the question, for example from Raycast, Alfred
  or a bookmark: `lampo://ask?q=What%20time%20is%20it%20in%20Tokyo%20at%203pm%20here`. A link can't run
  actions or change text.

## Privacy

- Requests run on Apple's model **on your Mac**. A badge always shows where each answer was computed.
- **Private Cloud Compute** (Apple's private cloud) is used only when you press "Think harder", in builds
  that include it (it needs an entitlement from Apple). With **Only on this Mac** turned on, it is never used.
- Lampo goes online only to **check for updates** (Sparkle), and only if you allow it. The only other
  downloads are Apple's own speech and translation models, after you confirm. No telemetry, no account,
  no analytics.
- **History** is off by default. When on, it stays on the Mac
  (`~/Library/Application Support/Lampo/history.json`, up to 200 requests); turning it off deletes it.
- Permissions, each asked one at a time by the welcome guide:
  - **Accessibility**: read the selected text and replace it in place (the one Lampo really needs);
  - **Screen Recording**: only for "Ask the screen";
  - **Microphone**: only while you dictate;
  - **Calendars** (write-only) and **Reminders**: only when you confirm an event or a reminder.
  No access to Contacts: an extracted contact is handed to the Contacts app, which asks you.

## What Lampo is not

- **Not a search engine or an encyclopedia.** The on-device model is small: it is great at rewriting,
  summarizing, translating, extracting and explaining what is in front of it, not at remembering facts.
  Always check dates, names and numbers against the source.
- It doesn't browse the web and doesn't read your files, emails or calendars.
- It never writes back a text it could only read in part.

## Requirements

- **macOS 27** on a Mac with **Apple silicon**.
- **Apple Intelligence** turned on (System Settings › Apple Intelligence & Siri) for the model-based
  actions. Translate, the calculator and the rule-based Extract work without it.

## Installation

Lampo is distributed outside the Mac App Store (it needs Accessibility, which sandboxed apps can't
use), as a signed and notarized app with automatic updates through Sparkle.

- **Download:** the notarized builds are published on the
  [Releases](https://github.com/christianmusumeci00/Lampo/releases) page. Unzip and move `Lampo.app` to
  `/Applications`.
- **Homebrew:** each release also produces a cask (`Packaging/Homebrew`), to be published in a tap with
  the first public release.

No public release has been published yet: until then, [build it from source](#build-from-source).

### First launch

A step-by-step guide opens in the middle of the screen. It explains what Lampo does and its shortcuts,
asks for the permissions one at a time (Accessibility, Screen Recording, Microphone, Calendars and
Reminders) and sets a few preferences. While the guide is open Lampo has a Dock icon: if the window ends
up behind System Settings, click the icon to bring it back (it also comes back by itself when you grant a
permission). If Lampo restarts, the guide resumes where you left off; you can reopen it from the menu bar
› Welcome Guide.

Lampo starts in English. Switch to Italian in the first step of the guide or in Settings › General ›
Language (Lampo restarts). Answers, Translate and Dictate keep following your Mac's language.

## Build from source

You need **Xcode 27** (macOS 27 SDK) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
```

```bash
git clone https://github.com/christianmusumeci00/Lampo.git
```

```bash
cd Lampo && xcodegen generate
```

The `.xcodeproj` is generated from `project.yml` and isn't committed. Open `Lampo.xcodeproj` in Xcode and
run the **Lampo** scheme, or build from the command line:

```bash
xcodebuild -project Lampo.xcodeproj -scheme Lampo -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages build
```

**Signing.** `project.yml` signs with the maintainer's team (`9K3LNS3KHP`). To build without that team,
sign ad hoc:

```bash
xcodebuild -project Lampo.xcodeproj -scheme Lampo -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build
```

or set your own `DEVELOPMENT_TEAM` in `project.yml` and run `xcodegen generate` again. With an ad hoc
signature macOS treats every rebuild as a new app, so you may have to grant Accessibility again.

**Tests** (Swift Testing; they need no permissions and no model, every system service has a mock):

```bash
xcodebuild -project Lampo.xcodeproj -scheme Lampo -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages test
```

**Strings.** UI strings are English keys in `Lampo/Resources/Localizable.xcstrings` with Italian
translations. After a build, `scripts/check-strings.sh` syncs the catalog and lists missing translations.

**Manual testing.** Debug builds read a few environment variables to open the panel, ask a question or
run an action at launch (`LAMPO_OPEN_PANEL`, `LAMPO_QA_QUERY`, `LAMPO_QA_ACTION`, …); see
[CLAUDE.md](CLAUDE.md). Start Lampo from `/` so macOS doesn't ask for access to the folder the shell is in.

### Project layout

| Folder | What's inside |
|---|---|
| `Lampo/App` | App entry point, menu bar, app state |
| `Lampo/Output`, `Lampo/Support` | Replace/paste/insert, clipboard, calculator, logging, design tokens |
| `Lampo/Panel`, `Lampo/Lens` | The panel and the Lens (SwiftUI + AppKit windows) |
| `Lampo/Model` | FoundationModels sessions, streaming, system instructions |
| `Lampo/Actions` | Built-in and custom actions, prompt templates |
| `Lampo/Context` | Selection (Accessibility, clipboard fallback), screen capture, text recognition |
| `Lampo/Dictation` | SpeechAnalyzer-based dictation |
| `Lampo/Structured` | Events, reminders, contacts, tables, to-dos (`@Generable` + date parsing) |
| `Lampo/Translation` | Apple Translation |
| `Lampo/Onboarding` | Welcome guide and permissions |
| `Lampo/Settings`, `Lampo/History`, `Lampo/Hotkeys`, `Lampo/Integration`, `Lampo/Updates` | Settings, history, shortcuts, App Intents and links, Sparkle |
| `LampoTests` | Unit tests and mocks |
| `docs` | [Design decisions](docs/DECISIONS.md), [manual QA checklist](docs/MANUAL_QA.md), media |
| `scripts`, `Packaging` | Release script, string check, icon, export options, Homebrew cask template |

Conventions: Swift 6 language mode with complete strict concurrency and zero warnings; every
system-touching service behind a protocol; design constants only in `Support/DesignTokens.swift`; SF
Symbols only; user content is never logged. Details in [CLAUDE.md](CLAUDE.md) and
[docs/DECISIONS.md](docs/DECISIONS.md).

### Releasing

`scripts/release.sh` runs the tests, archives with the Developer ID signature, notarizes, and produces
the zip, the Sparkle appcast and the Homebrew cask. One-time setup:

1. A "Developer ID Application" certificate in your keychain.
2. Notarization credentials:
   `xcrun notarytool store-credentials lampo-notary --apple-id <id> --team-id <team>`
3. The Sparkle EdDSA key (it stays in the keychain; the command prints the public key):
   `build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys`
4. `cp Packaging/release.env.example Packaging/release.env` and fill in the feed URL, the download prefix
   and the public key. `release.env` is git-ignored.

Then:

```bash
scripts/release.sh
```

For a local check without notarization or appcast:

```bash
scripts/release.sh --skip-notarize --skip-appcast
```

The version is `MARKETING_VERSION` in `project.yml`; the build number is the commit count.

## Built with

- [FoundationModels](https://developer.apple.com/documentation/foundationmodels), Translation,
  Speech (SpeechAnalyzer), Vision, ScreenCaptureKit, EventKit, App Intents
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) by Sindre Sorhus
- [Sparkle](https://sparkle-project.org) for updates

## License

Lampo is released under the [MIT License](LICENSE). Apple, Apple Intelligence, Siri and macOS are
trademarks of Apple Inc.; Lampo is an independent project, not affiliated with Apple.
