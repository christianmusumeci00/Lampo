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
