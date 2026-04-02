# ItemRackOptions (v1.0)

Originally by Gello. Modified for **WoW 3.3.5a (Ascension/Epoch)** by Defcon — uses independent version history.

## Changes

### New feature — "Disable in BG/Arena" checkbox in Sets panel
- New checkbox in the Sets panel to flag a set as PvP-safe (will not auto-equip in BG/Arena)
- Disabled when no set is selected; syncs to saved value when a set is loaded

### Bug fix — "stop queue here" always available for all slots
- The `-- stop queue here --` sentinel is now unconditionally added to all slot sort lists
- Previously was only added when `AllowEmpty=="ON"` AND a slot had an item equipped AND the bank was closed — meaning slot 14 (bottom trinket) would often be missing the stop marker

## Requirements

- Install alongside **ItemRack**

## Compatibility

- **Server:** Ascension / Epoch private server
- **Interface:** 30300 (WoW 3.3.5a)
- **Lua:** 5.1
