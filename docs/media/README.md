# Media for the README

| File | What | How it was made |
|---|---|---|
| `vetro.gif` | Panel: question, streamed answer, "Sul Mac" badge | Lampo's window only (`screencapture -l`), launched with `LAMPO_OPEN_PANEL=1 LAMPO_QA_QUERY="Spiegami in tre punti cos'è l'interesse composto"` |
| `crea-evento.png` | "Crea evento" confirmation card | `LAMPO_QA_DRAFT=event LAMPO_QA_QUERY="cena con Marco giovedì alle 20"` |
| `lente.gif` | **To record.** Lens on a TextEdit selection: "Più formale", preview, ↩ replaces, ⌘Z | Needs a real app on screen, so record it by hand |
| `schermo.gif` | **To record.** "Chiedi allo schermo" on a Terminal compile error + "cosa significa?" | Same |

To record by hand: macOS Screenshot (⇧⌘5) › Record Selected Portion, then convert the `.mov` to a GIF
(for example with `gifski`, ≤ 900 px wide, ~10 fps). Use a clean desktop with no personal content, then
uncomment the matching lines in the main README.
