# HCBreathBar

A custom underwater breath bar with sound alerts for **WoW 3.3.5a (Ascension/Epoch)**. Replaces the default MirrorTimer breath bar with a clean, minimal overlay.

## Features

- Hides the default breath bar and replaces it with a fully-controlled overlay
- Flat `WHITE8X8` texture fill with a dark semi-transparent trough (420×14 px)
- No border, minimalist style
- Sound alerts using `igQuestComplete` — rate doubles when breath drops below half the threshold
- Correctly reads breath in seconds (3.3.5 MirrorTimer values are in seconds, not milliseconds)
- Restores the original frame when you surface

## Compatibility

- **Server:** Ascension / Epoch private server
- **Interface:** 30300 (WoW 3.3.5a)
- **Lua:** 5.1
- Ported from Classic Era (Interface 11403)
