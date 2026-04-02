# pfQuest-epoch (v1.0)

Originally by Bennylavaa & Cuddlehorn. Modified for **WoW 3.3.5a (Ascension/Epoch)** by Defcon — uses independent version history.

## Features

- Layers Epoch-specific NPC and quest data over pfQuest-wotlk via a `patchtable()` merge system
- `overwrites.lua` removes content not present on Epoch (Silithus NPCs, TBC quest givers, Zul'Aman island, etc.)
- Version checking with optional update notifications (off by default — enable via pfQuest config)

### Rares/Chests toggle buttons on the WorldMap
- Two small toggle buttons anchored inside the WorldMap (top-right area)
- **Rares** and **Chests** buttons toggle their respective `pfDatabase:TrackMeta()` tracking on/off with a single click
- Label and colour update to reflect current state (green = ON, dark = OFF)
- Tooltip shows current state and equivalent slash command
- Syncs with slash-command state changes via `WORLD_MAP_UPDATE` event
- Buttons use `SetFrameStrata("DIALOG")` + `SetFrameLevel(100)` so they remain clickable in windowed map mode

## Requirements

- **pfQuest-wotlk** must be installed

## Compatibility

- **Server:** Ascension / Epoch private server
- **Interface:** 30300 (WoW 3.3.5a)
- **Lua:** 5.1
