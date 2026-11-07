# Manual QA

Run before each milestone commit that touches UI. Test on the oldest supported macOS (27.0),
light and dark, with at least two displays when possible.

Launch a Debug build from `/` (not from inside ~/Documents, which triggers a Documents-access prompt):
`cd / && ~/Documents/Lampo/build/DerivedData/Build/Products/Debug/Lampo.app/Contents/MacOS/Lampo`

## M1 — Skeleton

Menu bar
- [ ] Icon is `bolt.fill`; toggling "Enabled" off switches it to `bolt.slash`, and back.
- [ ] Header shows "Lampo" with status ("Attivo · modello sul Mac" / "Modello non disponibile" / "Disabilitato").
- [ ] "Apri Lampo" shows the current shortcut (⌥Space by default) and opens the panel.
- [ ] "Impostazioni…" (⌘,) opens Settings in front; "Esci da Lampo" (⌘Q) quits.
- [ ] "Enabled" state survives relaunch.

Hotkey and panel
- [ ] ⌥Space opens the panel on the screen under the pointer, centred, ~20% from the top; again closes it.
- [ ] With Lampo disabled, ⌥Space does nothing (the shortcut reaches the frontmost app instead).
- [ ] Opening the panel does not activate Lampo: the app underneath keeps its menu bar and title highlight.
- [ ] Works on every Space and over a full-screen app (Safari full screen, Keynote).
- [ ] Multi-monitor: opens on the display with the pointer; moves when the pointer moves to the other display.
- [ ] Esc closes when idle; click outside closes; ⌘W closes.
- [ ] Changing the shortcut in Settings › Scorciatoie takes effect immediately; "Ripristina predefinite" restores ⌥Space.
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
- [ ] Ripristina predefinite restores ⌥Space and ⌥⇧C/F/B/T/R/S.
- [ ] Azioni: +, −, duplicate, drag to reorder; edits are saved immediately and survive a relaunch.
- [ ] Editor: name, symbol, prompt, "Inserisci variabile", live preview with the sample text,
      unknown-variable warning, Input / Risultato / Modello, own shortcut recorder.
- [ ] "Prova" on the sample text streams the result with the "Sul Mac" badge; "Ferma" stops it.
      *(Checked: Correggi fixes the accents of the Italian sample.)*
- [ ] A new action gets a hotkey that works right away (no relaunch); deleting it frees the shortcut.
- [ ] Esporta azioni… / Importa azioni… round-trip (imported actions are added as new ones).
- [ ] Ripristina azioni predefinite… asks for confirmation and keeps custom actions.
- [ ] Privacy shows Accessibilità and Registrazione schermo with live status.
