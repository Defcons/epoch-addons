# TitanSpeed

A **Titan Panel** plugin for **WoW 3.3.5a (Ascension/Epoch)** that displays your current movement speed as a percentage.

## Features

- Displays movement speed % in the Titan Panel bar
- Polls every 0.2 seconds via `OnUpdate`
- **Tooltip** shows:
  - Current speed in yards/sec
  - Each active speed buff with its bonus %, e.g. `Cat Form (+30%)`, `Sprint (+70%) - 9s`
  - Remaining duration for timed buffs
- Detects: Druid forms, Sprint, Ghost Wolf, mounts, speed potions, and more
- Rank-varying spells (Sprint, Dash) correctly resolve the percentage from the rank string

## Requirements

- **Titan Panel** must be installed

## Compatibility

- **Server:** Ascension / Epoch private server
- **Interface:** 30300 (WoW 3.3.5a)
- **Lua:** 5.1
