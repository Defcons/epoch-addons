# FeralAPFix

A minimal compatibility fix for **WoW 3.3.5a (Ascension/Epoch)** that prevents a crash caused by the interaction between Ascension's built-in `feral-attack.lua` and TradeSkillMaster's LibExtraTip.

## The Problem

Ascension's `feral-attack.lua` calls `GetItemInfo(link)` with a nil link when TSM's LibExtraTip fires tooltip callbacks. This causes `GameTooltip:SetHyperlink(nil)` to throw a hard Lua error.

## The Fix

Wraps `GameTooltip:SetHyperlink()` with a nil guard at file load time (before TSM or any other addon can fire `SetHyperlink(nil)` during the login sequence).

## Compatibility

- **Server:** Ascension / Epoch private server
- **Interface:** 30300 (WoW 3.3.5a)
- **Lua:** 5.1
- Requires: TradeSkillMaster (any v2.x build)
