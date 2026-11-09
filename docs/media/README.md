# Media for the README

| File | What | How it was made |
|---|---|---|
| `panel.gif` | Panel: question, streamed answer, "On Mac" badge (English UI) | Lampo's window only, with its shadow (`screencapture -l <window>` in a loop, about 7 frames a second), launched with `LAMPO_OPEN_PANEL=1 LAMPO_QA_QUERY="Explain compound interest in three points"`; frames until the answer ends, 900 px wide on white, the last one held 2.5 s (assembled with ImageIO: no gifski or ffmpeg needed) |
| `create-event.png` | "Create event" confirmation card (English UI) | `LAMPO_QA_DRAFT=event LAMPO_QA_QUERY="Dinner with Marco Thursday at 8pm"`, `screencapture -l <window>` |
| `lens.gif` | **To record.** Lens on a TextEdit selection: "More formal", preview, ↩ replaces, ⌘Z | Needs a real app on screen, so record it by hand |
| `screen.gif` | **To record.** "Ask the screen" on a Terminal compile error + "what does this mean?" | Same |

To record by hand: macOS Screenshot (⇧⌘5) › Record Selected Portion, then convert the `.mov` to a GIF
(for example with `gifski`, ≤ 900 px wide, ~10 fps). Use a clean desktop with no personal content, then
uncomment the matching lines in the main README.
