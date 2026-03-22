# TitanGoldTracker

A **Titan Panel** plugin for **WoW 3.3.5a (Ascension/Epoch)** that tracks gold across all your characters on the same realm, including both factions.

## Features

- Displays total gold across all characters in the Titan Panel bar
- Tracks gold per-character, persisted across sessions via SavedVariables
- **Cross-faction:** matches all characters on the same realm regardless of Alliance/Horde faction
- Tooltip breaks down gold per character
- Uses `UIDropDownMenu` for context menus (no modern MenuUtil dependency)
- Uses Ace3 timer wrappers — no `C_Timer` dependency

## Requirements

- **Titan Panel** must be installed

## Compatibility

- **Server:** Ascension / Epoch private server
- **Interface:** 30300 (WoW 3.3.5a)
- **Lua:** 5.1
