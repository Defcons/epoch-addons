# ItemRack (v2.243)

An equipment set manager for **WoW 3.3.5a (Ascension/Epoch)**, modified with new features and bug fixes.

## Changes from v2.243

### New feature — "Disable in BG/Arena" per-set option
- Each equipment set can be flagged to never auto-equip while inside a battleground or arena
- Prevents unwanted set swaps during PvP regardless of what event triggered them (stance, zone, or buff)
- Configure per-set from the ItemRackOptions Sets panel

### Bug fix — trinket autoqueue cross-slot stop
- When either trinket fires and its buff becomes active, the *other* trinket's queue now also pauses
- Prevents unnecessary swaps during the 20-second shared trinket cooldown
- Symmetric: works regardless of which trinket (slot 13 or 14) was used first

## Compatibility

- **Server:** Ascension / Epoch private server
- **Interface:** 30300 (WoW 3.3.5a)
- **Lua:** 5.1
- Install alongside **ItemRackOptions** for the full UI
