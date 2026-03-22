# pfQuest-wotlk

A quest tracker and database addon with multi-client compatibility, modified for **WoW 3.3.5a (Ascension/Epoch)**.

## Changes from the original

### Multi-client compatibility layer (`compat/client.lua`)
- Detects build version and maps API differences between Vanilla/TBC/WotLK clients
- `string.gmatch or string.gfind` fallback for Lua 5.0 vs 5.1
- `mod or math.mod` fallback for math function rename
- Quest frame name mappings for 3.3.5 renames (`QuestLogQuestTitle` → `QuestInfoTitleHeader`, etc.)
- `QuestWatchFrame` vs `WatchFrame` handled per client version
- Item link suffix format differs per client
- Wowhead database URL selected per client (wotlk/tbc/classic)

### Bug fixes — quest log raw override removal (`quest.lua`)
These raw overrides caused UI taint that prevented `QuestLogAbandonButton` from responding to clicks:
- Replaced raw `AbandonQuest = function()` global override with `QuestLogAbandonButton:HookScript("OnClick")` — captures the quest name at click time before any event can shift the selection
- Replaced raw `QuestLog_Update = function()` override with `hooksecurefunc("QuestLog_Update", ...)`
- Replaced raw `QuestLogTitleButton_OnClick = function()` override with `hooksecurefunc("QuestLogTitleButton_OnClick", ...)`

### Configuration
- Added `"Show Update Notifications"` checkbox (`updatenotify`, default `"0"` / off) — controls whether pfQuest-epoch version messages appear in chat

## Compatibility

- **Server:** Ascension / Epoch private server
- **Interface:** 30300 (WoW 3.3.5a)
- **Lua:** 5.1
- Designed to work alongside **pfQuest-epoch** for Epoch-specific database content
