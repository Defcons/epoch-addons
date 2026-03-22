# Whats-Training-Epoch — Changelog

## Ascension/Epoch Modifications

### Bug fix — "Now available at trainer" messages shown at level 60 (`Announce.lua`)
- Login announcement and level-up announcement both fire at level 60 even though there are no more trainable levels beyond cap
- Added `UnitLevel("player") < 60` guard to the login delayed-announcement scheduler
- Added early `return` in the `PLAYER_LEVEL_UP` handler when new level ≥ 60
- `/wte test` command is unaffected and still works for manual testing
