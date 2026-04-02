# Whats-Training-Epoch (v1.0)

Originally by ZythDr. Modified for **WoW 3.3.5a (Ascension/Epoch)** by Defcon — uses independent version history.

## Changes

### Bug fix — "Now available at trainer" messages shown at level 60
- Both the login announcement and the level-up announcement were firing at level 60, even though there are no further trainable levels at the cap
- Added `UnitLevel("player") < 60` guard to the login delayed-announcement scheduler
- Added early `return` in the `PLAYER_LEVEL_UP` handler when new level ≥ 60
- `/wte test` command is unaffected and still works for manual testing

## Compatibility

- **Server:** Ascension / Epoch private server
- **Interface:** 30300 (WoW 3.3.5a)
- **Lua:** 5.1
