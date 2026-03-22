# EpochFixes

A lightweight patch addon for **WoW 3.3.5a (Ascension/Epoch)** that silently fixes four persistent client bugs without requiring any user interaction.

## Fixes

### Fix 1 — SpellBook tab error
Wraps the `OnEnter` handler in `pcall()` to suppress a nil concatenation error that occurs when the `TOGGLEPETBOOK` keybind is unassigned.

### Fix 2 — Quest abandon selecting wrong quest
Hooks `QuestLogAbandonButton:OnClick` to snapshot the quest log selection index at click time. Wraps `StaticPopupDialogs["ABANDON_QUEST"].OnAccept` to restore that index immediately before `AbandonQuest()` runs — guaranteeing the correct quest is abandoned regardless of what other addons (e.g. Leatrix auto-quest scanning) did to the selection while the popup was open.

### Fix 3 — Quest reward tooltip corruption
Hooks quest item `OnEnter` events to reclaim `GameTooltip` ownership when pfQuest or Leatrix have corrupted the tooltip anchor state.

### Fix 4 — Inspect tooltip returning nil item links
Caches all 19 equipped item links on `INSPECT_READY`. Falls back to the cached links after the API starts returning nil (~10–15 seconds after the cache window expires).

## Compatibility

- **Server:** Ascension / Epoch private server
- **Interface:** 30300 (WoW 3.3.5a)
- **Lua:** 5.1
- Works alongside: pfQuest-wotlk, Leatrix, and other quest/tooltip addons
