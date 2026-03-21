-- FeralAPFix: guards feral-attack.lua against nil links in tooltip hooks.
-- epoch's built-in feral-attack.lua calls GetItemInfo(link) without a nil
-- check, which errors when TSM's LibExtraTip fires tooltip callbacks with
-- no hyperlink set (nil link from various addons checking equipped items).

local orig = GameTooltip.SetHyperlink
GameTooltip.SetHyperlink = function(tooltip, link, ...)
    if not link then return end
    return orig(tooltip, link, ...)
end
