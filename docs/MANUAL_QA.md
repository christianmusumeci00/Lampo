# Manual QA

Run before each milestone commit that touches UI. Test on the oldest supported macOS (27.0),
light and dark, with at least two displays when possible.

Launch a Debug build from `/` (not from inside ~/Documents, which triggers a Documents-access prompt):
`cd / && ~/Documents/Lampo/build/DerivedData/Build/Products/Debug/Lampo.app/Contents/MacOS/Lampo`

## M1 — Skeleton

Menu bar
- [ ] Icon is `bolt.fill`; toggling "Enabled" off switches it to `bolt.slash`, and back.
- [ ] Header shows "Lampo" with status ("Attivo · modello sul Mac" / "Modello non disponibile" / "Disabilitato").
- [ ] "Apri Lampo" shows the current shortcut (⌥⇧Space by default) and opens the panel.
- [ ] "Impostazioni…" (⌘,) opens Settings in front; "Esci da Lampo" (⌘Q) quits.
- [ ] "Enabled" state survives relaunch.

Hotkey and panel
- [ ] ⌥⇧Space opens the panel on the screen under the pointer, centred, ~20% from the top; again closes it.
- [ ] With Lampo disabled, ⌥⇧Space does nothing (the shortcut reaches the frontmost app instead).
- [ ] Opening the panel does not activate Lampo: the app underneath keeps its menu bar and title highlight.
- [ ] Works on every Space and over a full-screen app (Safari full screen, Keynote).
- [ ] Multi-monitor: opens on the display with the pointer; moves when the pointer moves to the other display.
- [ ] Esc closes when idle; click outside closes; ⌘W closes.
- [ ] Changing the shortcut in Settings › Scorciatoie takes effect immediately; "Ripristina predefinite" restores ⌥⇧Space.
- [ ] Panel position "Vicino al puntatore" opens it under the pointer.

Answers
- [ ] A question starts streaming within ~1 s; text appears progressively; badge "Sul Mac" with lock.
- [ ] Markdown: bold, italic, inline code, bullet/numbered/nested lists, code blocks render.
- [ ] Esc during streaming stops it ("Interrotto"), keeps partial text; a follow-up then still knows the context.
- [ ] Follow-up question uses previous context; previous questions appear compact above, click to expand.
- [ ] "Approfondisci" expands the last answer in the same session.
- [ ] "Pensa di più" is disabled with tooltip "Non disponibile in questa build".
- [ ] ⌘C copies the answer (pasteboard check); with text selected in the field, ⌘C copies that selection instead.
- [ ] "Chiudi il pannello dopo la copia" closes the panel after Copy.
- [ ] `12*(3+4)`, `200 * 15%`, `3,5 x 2`, `√81` answer instantly with "Calcolato sul Mac"; `1/0` → "Non definito".
- [ ] ⌘N clears the conversation. Reopening within 5 min keeps it; after 5 min of inactivity it's gone.

Model availability
- [ ] With Apple Intelligence off (System Settings), the panel shows the explanation and
      "Apri Impostazioni di Sistema" opens the right pane; "Controlla di nuovo" refreshes after turning it on.
- [ ] Menu status reflects availability when the menu is opened.

Appearance and accessibility
- [ ] Light and dark: glass legible, contrast OK, no clipped shadow.
- [ ] Reduce transparency: panel becomes opaque. Reduce motion: no scale animation.
- [ ] VoiceOver: input labelled "Chiedi a Lampo"; icon buttons labelled; the answer is announced when complete.
- [ ] Keyboard only: type, ↩, Esc, ⌘C, ⌘N, Tab through buttons.
- [ ] Italian and English system language both show translated UI.

Resources
- [ ] Idle in background: ~0% CPU in Activity Monitor; memory stays small with the panel closed.

## M2 — Lens and selection actions

Apps: TextEdit, Mail (compose), Notes, Safari (a `<textarea>`, e.g. a feedback form), VS Code (Electron).

- [ ] First launch without Accessibility: the permissions window opens; "Consenti…" shows the system
      prompt and System Settings; the row turns green within a second of enabling Lampo.
- [ ] Each built-in hotkey (⌥⇧C Correggi, ⌥⇧F Più formale, ⌥⇧B Più breve, ⌥⇧T Traduci in inglese,
      ⌥⇧R Riassumi) opens the Lens under the selection (above it near the bottom of the screen),
      with the arrow pointing at the selection and the triggered action highlighted.
- [ ] Header shows "Testo selezionato · N parole · <App>" and the "Sul Mac" badge.
- [ ] Tab / ⇧Tab / ← → switch action and regenerate; clicking a chip does too.
- [ ] For every app above: "Più formale" + ↩ replaces the selection in place; ⌘Z in that app restores
      the original in one step; the clipboard (text *and* an image copied beforehand) is unchanged.
- [ ] Italian text stays Italian for Correggi / Più formale / Più breve.
- [ ] Esc closes the Lens without touching the text; clicking elsewhere closes it too.
- [ ] Riprova regenerates; Copia puts the result on the clipboard ("Copiato" flash).
- [ ] No selection: HUD "Seleziona prima del testo, poi riprova."
- [ ] Silent mode (Impostazioni › Azioni › Risultato: "Sostituisci senza anteprima"):
      HUD "Correggi…" then "Fatto · ⌘Z per annullare"; ⌘Z restores.
- [ ] Menu › Azioni rapide lists every action with its shortcut and runs it on the current selection.
- [ ] "Spiega" opens the Glass panel with the selection as context and streams the explanation.
- [ ] Glass panel over a selection shows the "Selezione · N parole" chip; ✕ or Backspace (empty field)
      removes it; the question uses it; ⌘⇧V adds an "Appunti" chip.
- [ ] Panel "Inserisci ⌘↩" replaces the selection the answer is about, or pastes at the cursor; ⌘Z undoes.
- [ ] Lampo disabled: no action hotkey responds and Azioni rapide is disabled.
- [ ] Password field selected: nothing is read.
- [ ] VoiceOver: Lens chips announce selection state; HUD messages are announced.

## M3 — Screen context and full Settings

Apps: Terminal (a compiler error), Safari (a web page), Xcode (an issue in the editor), Preview (a PDF).

- [ ] **Acceptance:** with a compiler error visible in Terminal, ⌥⇧S ("Chiedi allo schermo") opens the
      panel with the "Finestra: Terminale" chip (thumbnail); "cosa significa?" gives a relevant
      explanation, in Italian. *(Checked: explains the Int/Double mismatch in Italian.)*
- [ ] ⌘⇧S inside the panel attaches the window that was frontmost when the panel opened; ⌘⇧S again
      removes it; ✕ removes it; Backspace in the empty field removes it.
- [ ] Lampo's own panel and Lens never appear in the screenshot, even when they overlap the window.
- [ ] Follow-up questions don't resend the image; ⌘N starts over.
- [ ] Without Screen Recording: ⌘⇧S / ⌥⇧S show "Consenti la Registrazione schermo…" with "Consenti…",
      which shows the system prompt and opens System Settings › Privacy › Registrazione schermo.
      After allowing, macOS may ask to quit and reopen Lampo.
- [ ] Desktop focused (no window): "Non c'è una finestra da guardare…".
- [ ] Multiple monitors / full-screen app: the frontmost window of the app is captured.
- [ ] Long text (select a long article, e.g. 15 000 words) + Riassumi: the Lens shows
      "Testo lungo: usato un estratto." and Sostituisci is disabled; Copia works. Silent mode on the
      same text refuses with "Il testo è troppo lungo per riscriverlo al suo posto…".
- [ ] Same long text in the panel ("riassumi"): the answer shows the "Testo lungo" notice.

Settings
- [ ] Scorciatoie lists Apri Lampo and every action with its own recorder.
- [ ] Recording a combination already used by another command is refused with
      "Questa scorciatoia è già usata da “…”." A duplicate already present (e.g. from an import)
      shows an orange "… è assegnata a … Ne funzionerà solo una." row.
- [ ] Ripristina predefinite restores ⌥⇧Space and ⌥⇧C/R/T/S/E/P on the turned-on actions.
- [ ] Azioni: +, −, duplicate, drag to reorder; edits are saved immediately and survive a relaunch.
- [ ] Editor: name, symbol, prompt, "Inserisci variabile", live preview with the sample text,
      unknown-variable warning, Input / Risultato / Modello, own shortcut recorder.
- [ ] "Prova" on the sample text streams the result with the "Sul Mac" badge; "Ferma" stops it.
      *(Checked: Correggi fixes the accents of the Italian sample.)*
- [ ] A new action gets a hotkey that works right away (no relaunch); deleting it frees the shortcut.
- [ ] Esporta azioni… / Importa azioni… round-trip (imported actions are added as new ones).
- [ ] Ripristina azioni predefinite… asks for confirmation and keeps custom actions.
- [ ] Privacy shows Accessibilità and Registrazione schermo with live status.
- [ ] Privacy also shows Calendari and Promemoria; "Consenti…" asks the first time, then opens System Settings.

## M4 — Create event / reminder, history

Create event / reminder
- [x] "cena con Marco giovedì alle 20" (on Sunday 8 Nov 2026): card with "Cena con Marco",
      12/11/2026 20:00–21:00, badge Sul Mac. *(Checked live with `LAMPO_QA_DRAFT=event`.)*
- [x] An email ("venerdì 20 novembre dalle 15:00 alle 16:30 in sala Volta per la revisione…"): title,
      range and place filled. *(Checked live.)*
- [x] "ricordami di chiamare Anna domani alle 10 per il preventivo" → reminder "Chiamare Anna per il
      preventivo", 09/11 10:00 with Data and Ora on. *(Checked live.)*
- [x] Annulla closes the card and writes nothing. *(Checked live.)*
- [ ] Select a sentence in TextEdit, press ⌥⇧E: the card opens from the selection.
- [ ] With nothing selected, ⌥⇧E shows the "Crea evento" chip; typing a description and ↩ opens the card.
- [ ] First Aggiungi asks for Calendar access (write-only wording); after allowing, the event is in the
      default calendar at the right time; "Apri Calendario" jumps to its day.
- [ ] Refusing access shows the message and "Apri Impostazioni di Sistema".
- [ ] ⌥⇧P + Aggiungi ai promemoria: first time asks for Reminders access; the reminder has the due time
      and an alert.
- [ ] Editing the start keeps the duration; "Tutto il giorno" hides Fine.
- [ ] VoiceOver announces "Aggiunto al calendario".

History
- [ ] Off by default; with it off nothing is written to ~/Library/Application Support/Lampo/history.json.
- [ ] On: panel answers, Lens previews and copy/replace results appear in "Mostra cronologia…", newest
      first; search filters; right-click copies or deletes.
- [ ] "Cancella cronologia…" asks for confirmation and empties the list; turning history off deletes the file.

Solo sul Mac
- [x] Covered by `OnlyOnMacTests` with PCC compiled in (no cloud conversation in any flow).

## M5 — Polish and launch

Links and Shortcuts
- [x] `open "lampo://ask?q=…"` with Lampo running opens the panel and answers. *(Checked live.)*
- [x] The same link when Lampo isn't running launches it and answers. *(Checked live.)*
- [ ] `lampo://ask` without `q` just opens the panel; a link with a selection in the front app doesn't attach it.
- [ ] Shortcuts app: "Chiedi a Lampo" returns the answer; "Esegui azione Lampo" with Correggi on a text
      returns the corrected text; with Crea evento it opens the card in Lampo.
- [ ] With Lampo disabled both intents fail with "Lampo è disattivato…".

Updates and release
- [x] `scripts/release.sh --skip-notarize --skip-appcast`: tests, Release archive, Developer ID export,
      signature checks, zip, cask. *(Checked.)*
- [ ] Full release with `Packaging/release.env`: notarization succeeds, `spctl` says "Notarized Developer ID",
      appcast is signed (`sparkle:edSignature`).
- [ ] A release build shows "Controlla aggiornamenti…" in the menu and in Info; on the second launch Sparkle
      asks about automatic checks; an older build finds the newer one and installs it.
- [ ] `brew install --cask` from the tap installs and launches; `brew uninstall --zap` removes the data.

First launch
- [x] Welcome screen with the icon, tagline and ⌥⇧Spazio / ⌥⇧R / ⌥⇧S; Continua shows the permissions. *(Checked live.)*
- [ ] Shown only once; the Dock/Finder/Get Info icon is the blue bolt.
- [ ] Italian and English everywhere (System Settings › Language per app), including Shortcuts phrases
      and the calendar/reminders permission prompts.

## After M5 — Screen Recording permission
- [x] Settings › Privacy › Registrazione schermo › Consenti… (Lampo opened from the Finder): the macOS
      alert appears and stays in front; Lampo shows the instructions with the two buttons. *(Checked live.)*
- [x] In the alert, "Apri Impostazioni di Sistema" opens the pane with Lampo in the list. *(Confirmed by the user.)*
- [ ] Turning it on and reopening Lampo makes "Chiedi allo schermo" work.
- [ ] If Lampo isn't listed: "Mostra Lampo nel Finder", then + (or drag) adds it.


## After M5 — panel shortcut ⌥⇧Space
- [ ] Fresh install: Settings › Scorciatoie shows ⌥⇧Space for "Apri Lampo"; ⌥Space reaches Codex.
- [ ] An install that had ⌥Space moves to ⌥⇧Space on the next launch, once; setting ⌥Space again by hand sticks.

## 1.1 — Rewrite, Apple Translation, actions on/off
- [ ] Fresh install: Settings › Azioni shows Correggi, Riscrivi, Traduci, Chiedi allo schermo, Crea evento,
      Crea promemoria, Spiega turned on; Più formale, Più breve, Riassumi "Spenta" and not in the Lens or menu.
- [ ] An install from 1.0: the same, plus Traduci in inglese / in italiano turned off (not deleted); custom actions untouched.
- [x] ⌥⇧R on a selection: the Lens shows the four tones; switching tone rewrites again; the next ⌥⇧R starts on that tone. *(Checked live; tone stored.)*
- [ ] ⌥⇧T on English text → Italian (*checked live, layout kept*); on Italian text → the language last picked (English at first). "Sul Mac" badge.
- [x] The target menu in the Lens changes language and is remembered. *(Checked live: English → Tedesco.)*
- [ ] A language that isn't downloaded shows where to download it.
- [ ] Translate works with Apple Intelligence turned off.
- [ ] Turning Riassumi back on drops its old ⌥⇧R (now Riscrivi's) instead of creating a conflict.
- [ ] A custom action with "Funziona con: Traduzione di Apple" and a fixed language translates there.
- [x] Switching chips Riscrivi ↔ Traduci ↔ Correggi repeatedly doesn't crash. *(Checked live after the resize fix.)*

## Dictate (⌥⇧D)
- [x] Tap ⌥⇧D in a text field: the capsule shows the live transcript; ⌥⇧D again inserts the cleaned text.
      *(Checked live with `LAMPO_QA_DICTATION_FILE`, TextEdit.)*
- [x] Holding ⌥⇧D while talking and releasing inserts. *(Checked live, file input.)*
- [x] Esc cancels: capsule gone, nothing inserted. *(Checked live.)*
- [x] First use with the real microphone: macOS asks for the Microphone; after "Allow", dictation listens
      until the next press. *(Confirmed by the user.)*
- [ ] Microphone denied: the HUD says so and System Settings › Microphone opens.
- [ ] A language without its model: the alert offers the download; Settings › General › Dictation shows
      the status, the Download button and the language picker.
- [ ] ⌘Z right after an insert removes the whole dictated text.
- [ ] A custom action with Input: Dictation and Result: Create an event opens the card from what you said.
- [ ] Apple Intelligence off: the transcript is inserted as said, with a note.

## 1.1 — Reply, text in screenshots, lists, Extract
- [x] Ask the screen on a TextEdit order confirmation: order code, total and delivery date answered exactly.
      *(Checked live.)*
- [x] Reply on an English email selected in TextEdit: English draft, no signature; the Italian follow-up
      "più breve e dì che giovedì alle 15 va bene" rewrites it in English. *(Checked live.)*
- [ ] Reply › Insert (⌘↩) types at the cursor (e.g. in Mail's reply window), not over the message.
- [x] Create reminder on "latte, chiamare Luca domani alle 10, bolletta venerdì": three rows, Luca
      tomorrow at 10, the bill on Friday. *(Checked live, `LAMPO_QA_DRAFT`.)*
- [x] Create event on "riunione lunedì alle 10, dentista giovedì alle 15 e palestra sabato mattina": three
      events; "cena con Marco, giovedì alle 20 da Gino" stays one event. *(Checked live.)*
- [ ] Unticking a row and confirming adds only the ticked ones to Reminders.
- [x] Extract on an email signature: contact with name, company, role, two phones, email, address, site.
      *(Checked live, `LAMPO_QA_EXTRACT=auto`.)*
- [ ] Extract › Add to Contacts: Contacts opens the card and asks before adding it.
- [x] Extract on four "Name - age - city" lines: a table; on a meeting email: four to-dos with Friday and
      Tuesday deadlines. *(Checked live.)*
- [ ] Copy a table and paste it in Numbers: one cell per value.
- [ ] Switching Contact/Table/To-dos in the card re-reads the text.

## Welcome guide, Dock icon, English by default
- [x] First launch on an Italian Mac: the guide opens in English, exactly centered (x 436 on a 1512-pt
      screen), above the frontmost app, with a Dock icon. *(Checked live.)*
- [x] All eight steps render; shortcuts show the current keys. *(Checked live.)*
- [x] Quit at step 8 and relaunch: the guide reopens at step 8. *(Checked live.)*
- [x] Guide buried behind System Settings: clicking Lampo in the Dock brings it back in front. *(Checked live.)*
- [x] English → Italiano → English → Italiano in the first step: Lampo relaunches each time in that language,
      also when opened from the Finder (`open`). *(Checked live.)*
- [x] An action without Accessibility opens the permissions window, centered, with a Dock icon. *(Checked live.)*
- [ ] Turning on Accessibility in System Settings brings the guide back in front by itself.
      *(Not checked live: Accessibility was already allowed for the Developer ID build, and permissions
      aren't removed during QA. `PermissionMonitor.onGranted` is covered by tests.)*
- [x] Release build (Developer ID, not notarized) installed in /Applications with no saved settings: guide
      centered, English, above the frontmost app, Dock icon; all eight steps. *(Checked live.)*
- [x] Settings › General › Language relaunches Lampo in the chosen language (English → Italiano → English);
      built-in action names follow. *(Checked live.)*

## Full pass on 1.1 + welcome guide (9 Nov 2026, Debug build, Italian Mac)
- [x] Panel, Lens (Correct, Rewrite, Translate, Replace + ⌘Z in TextEdit and Safari), Dictate (audio file),
      Reply, Ask the screen, Create event/reminder lists (card only), Extract (contact, table into Numbers,
      to-dos), Settings (action on/off, custom action + Try, shortcut conflict alert and change, History
      on → `history.json` 0600, off → deleted, Near the pointer, Close after copying), `lampo://ask`.
- Fixed during the pass:
  - Insert typed Markdown markers (`**`, `#`): it now inserts plain text (`MarkdownText.plain`).
  - English with typos was taken for Catalan, so Correct answered in Catalan: `TextLanguage.detect`
    re-runs with the Mac's languages + English as hints when the guess is unsure and unlikely.
  - The to-dos/list card header counted every item, not the ticked ones.
  - Extract › contact: "Marco Marco" when the model repeated the first name as the last name.
  - The dictation language said "Same as Lampo (…)" although Lampo's language is no longer the Mac's: now
    "Automatic (…)".
- Not checked: Confirm on the event/reminder cards and "Add" in Contacts (they would write to the real
  calendar/contacts and ask for Calendars access); Mail itself (Reply checked in TextEdit); the Shortcuts
  app; removing the Microphone permission.
