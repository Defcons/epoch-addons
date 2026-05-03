-- Core/Session.lua
-- Session state machine. A single session runs from Start() until End() (or
-- until the player logs out — sessions don't persist across game sessions
-- by design; the gold-per-hour stat would otherwise be meaningless after
-- coming back from work). Pause()/Resume() suspends the timer without
-- losing accumulated loot.

LA = LA or {}
LA.Session = {}
local Session = LA.Session

-- ----- internal state ----------------------------------------------------
local state = {
    isRunning  = false,
    isPaused   = false,
    startTime  = 0,        -- GetTime() at Start()
    pauseStart = 0,        -- GetTime() at Pause()
    pausedTotal = 0,       -- accumulated paused seconds
    startGold  = 0,        -- GetMoney() at Start()
    lootTotal  = 0,        -- copper value of all looted rows in this session
    itemCount  = 0,        -- total stack count
    lootRows   = {},       -- chronological list, newest at index 1
    zone       = "",       -- zone name at session start (informational)
    -- ----- bag-loss reconciliation ----------------------------------------
    -- Snapshot of bag contents at session start. Items already in bags
    -- before we started farming aren't ours; if their count drops we
    -- debit the baseline first, then session-tracked items, so destroying
    -- a pre-session stack of [Linen Cloth] doesn't wrongly nuke the
    -- looted-this-session counter.
    bagBaseline = {},      -- [itemID] = count present at Start()
    bagOwn      = {},      -- [itemID] = total count looted into bags this session
}

-- ----- bag scanning ------------------------------------------------------
-- Sums every item we currently carry across the regular bags (backpack +
-- 4 bag slots). Specialty bags like the keyring (-2) and ammo bag (-1)
-- are excluded — they shouldn't carry tracked loot, and including them
-- mostly causes false positives when the user equips/swaps a quiver.
local function ScanBagsToCounts()
    local counts = {}
    for bag = 0, NUM_BAG_SLOTS do
        local n = GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local _, count = GetContainerItemInfo(bag, slot)
                local id = tonumber(link:match("item:(%d+)"))
                if id then
                    counts[id] = (counts[id] or 0) + (count or 1)
                end
            end
        end
    end
    return counts
end

-- Reduce session totals by the value/count of `lostCount` of itemID,
-- iterating lootRows newest-first (LIFO) and applying per-row pricing
-- proportionally for partial losses.
local function ApplyLossToLootRows(id, lostCount)
    local i = 1
    while i <= #state.lootRows and lostCount > 0 do
        local row = state.lootRows[i]
        local rowID = tonumber((row.link or ""):match("item:(%d+)"))
        if rowID == id and (row.count or 0) > 0 then
            local take = math.min(row.count, lostCount)
            local perItem = (row.value or 0) / row.count
            row.count = row.count - take
            row.value = row.value - perItem * take
            state.lootTotal = state.lootTotal - perItem * take
            state.itemCount = state.itemCount - take
            lostCount = lostCount - take
            if row.count <= 0 then
                table.remove(state.lootRows, i)
                -- intentionally don't increment i: the next row took this slot
            else
                i = i + 1
            end
        else
            i = i + 1
        end
    end
    -- Floors against floating-point accumulation (per-item division) and
    -- any tracking drift if the player started with items in bags that
    -- somehow ended up double-debited.
    if state.lootTotal < 0 then state.lootTotal = 0 end
    if state.itemCount < 0 then state.itemCount = 0 end
end

function Session.IsRunning() return state.isRunning end
function Session.IsPaused()  return state.isPaused  end

function Session.Start()
    state.isRunning   = true
    state.isPaused    = false
    state.startTime   = GetTime()
    state.pauseStart  = 0
    state.pausedTotal = 0
    state.startGold   = GetMoney() or 0
    state.lootTotal   = 0
    state.itemCount   = 0
    state.lootRows    = {}
    state.zone        = GetRealZoneText() or GetZoneText() or ""
    state.bagBaseline = ScanBagsToCounts()
    state.bagOwn      = {}
end

function Session.End()
    if state.isPaused then
        -- collapse the pending pause into total before stopping
        state.pausedTotal = state.pausedTotal + (GetTime() - state.pauseStart)
        state.isPaused    = false
    end
    state.isRunning = false
end

function Session.Pause()
    if not state.isRunning or state.isPaused then return end
    state.isPaused   = true
    state.pauseStart = GetTime()
end

function Session.Resume()
    if not state.isRunning or not state.isPaused then return end
    state.pausedTotal = state.pausedTotal + (GetTime() - state.pauseStart)
    state.isPaused    = false
    state.pauseStart  = 0
end

-- Effective elapsed time, excluding any paused interval. Always >= 1s to
-- avoid divide-by-zero when computing GPH on the first tick.
function Session.Elapsed()
    if not state.isRunning then return 0 end
    local now = GetTime()
    local raw = now - state.startTime - state.pausedTotal
    if state.isPaused then raw = raw - (now - state.pauseStart) end
    return math.max(raw, 1)
end

function Session.LootTotal() return state.lootTotal end
function Session.ItemCount() return state.itemCount end
function Session.GoldDelta() return (GetMoney() or 0) - state.startGold end
function Session.Zone()      return state.zone end

-- (lootValue + goldDelta) projected per hour. Honours pauses.
function Session.GoldPerHour()
    local elapsed = Session.Elapsed()
    if elapsed <= 0 then return 0 end
    local total = state.lootTotal + Session.GoldDelta()
    return math.floor(total / elapsed * 3600)
end

-- AH-style only: just the loot value GPH (no gold delta). Useful for
-- "what would I make if I sold everything I farmed".
function Session.LootPerHour()
    local elapsed = Session.Elapsed()
    if elapsed <= 0 then return 0 end
    return math.floor(state.lootTotal / elapsed * 3600)
end

-- ----- loot intake -------------------------------------------------------
-- Called by LootManager when a tracked item drops. Stores the row, updates
-- totals. The UI re-reads via Session.GetRows() / Session.LootTotal().
function Session.AddLoot(entry)
    if not state.isRunning then return end

    state.lootTotal = state.lootTotal + (entry.value or 0)
    state.itemCount = state.itemCount + (entry.count or 1)

    -- newest row at the front (cheap when capped to MAX_LOOT_ROWS)
    table.insert(state.lootRows, 1, entry)
    while #state.lootRows > LA_CONST.MAX_LOOT_ROWS do
        table.remove(state.lootRows)
    end

    -- Track the intake against the bag-reconciliation ledger so
    -- ReconcileBags() can later debit the right amount when the item
    -- leaves bags (destroy/vendor/mail/trade).
    local id = tonumber((entry.link or ""):match("item:(%d+)"))
    if id then
        state.bagOwn[id] = (state.bagOwn[id] or 0) + (entry.count or 1)
    end
end

-- ----- bag-loss reconciliation -------------------------------------------
-- Compare current bag contents against what we expect (baseline + bagOwn).
-- For any item where the current count is below expected, debit the loss:
-- prefer reducing bagOwn (and lootRows) first; only fall back to baseline
-- if the entire session-looted amount of that item is already gone. This
-- is the right ordering because session items are "newer" — a player
-- generally vendors/destroys what they just looted before pre-existing
-- stacks.
--
-- Returns true iff lootTotal/itemCount actually changed (UI refresh needed).
-- ----- repricing pass ----------------------------------------------------
-- Re-evaluate recently-ingested rows that landed at the vendor floor.
-- The fresh-loot timing race is real: CHAT_MSG_LOOT fires before
-- ArkInventory has scanned the bag for the new item, so a rule-classified
-- item (e.g. "DE rule" assigned via an ArkInventory rule rather than a
-- manual Custom-category drop) tends to resolve as "default" on the
-- first lookup and gets priced as vendor.
--
-- A few hundred ms later, ArkInventory finishes its scan and slot.cat is
-- populated. By that point our BAG_UPDATE → reconcile tick fires; this
-- function piggybacks on that tick and re-prices any recent vendor row.
-- Once a row's source flips off vendor it won't be re-priced again on
-- subsequent ticks (the `if row.src == VENDOR` guard self-stabilises).
--
-- Returns true iff lootTotal changed (UI refresh hint).
function Session.RepriceRecentVendor()
    if not state.isRunning then return false end
    local now = GetTime()
    local db  = LA.db and LA.db.profile or LA_DEFAULTS
    local opts = {
        useDisenchant   = db.useDisenchant,
        valueCategory   = db.arkInvValueCategory,
        deCategory      = db.arkInvDECategory,
        vendorCategory  = db.arkInvVendorCategory,
    }
    local changed = false
    for _, row in ipairs(state.lootRows) do
        local age = now - (row.time or 0)
        if age > 5 then break end -- rows are stored newest-first, so older = stop
        if row.src == LA_CONST.PRICE_VENDOR and row.link then
            local newCopper, newSrc = LA.Pricing.GetItemValue(row.link, opts)
            if newSrc and newSrc ~= LA_CONST.PRICE_VENDOR
                and newCopper and newCopper > 0 then
                local oldValue = row.value or 0
                local newValue = newCopper * (row.count or 1)
                row.unit  = newCopper
                row.src   = newSrc
                row.value = newValue
                state.lootTotal = state.lootTotal - oldValue + newValue
                if state.lootTotal < 0 then state.lootTotal = 0 end
                changed = true
            end
        end
    end
    return changed
end

function Session.ReconcileBags()
    if not state.isRunning then return false end

    local current = ScanBagsToCounts()
    local changed = false

    -- Collect IDs first, then mutate. Modifying state.bagOwn while iterating
    -- it via pairs() is undefined in Lua 5.1 — depending on hash bucket
    -- layout some entries can be skipped, which presents to the user as
    -- "loot rows aren't going away" (most visible when disenchanting: the
    -- source item should be debited at the same time the mats arrive).
    local ids = {}
    for id in pairs(state.bagOwn) do ids[#ids + 1] = id end

    for _, id in ipairs(ids) do
        local own = state.bagOwn[id]
        if own and own > 0 then
            local base = state.bagBaseline[id] or 0
            local cur  = current[id] or 0
            local expected = base + own
            if cur < expected then
                local loss     = expected - cur
                local fromOwn  = math.min(own, loss)
                local fromBase = loss - fromOwn

                state.bagOwn[id] = own - fromOwn
                if state.bagOwn[id] == 0 then state.bagOwn[id] = nil end
                if fromBase > 0 then
                    state.bagBaseline[id] = math.max(0, base - fromBase)
                end

                if fromOwn > 0 then
                    ApplyLossToLootRows(id, fromOwn)
                    changed = true
                end
            end
        end
    end

    return changed
end

function Session.GetRows() return state.lootRows end

-- For UI debug / external integrations
function Session.Snapshot()
    return {
        isRunning   = state.isRunning,
        isPaused    = state.isPaused,
        elapsed     = Session.Elapsed(),
        startGold   = state.startGold,
        goldDelta   = Session.GoldDelta(),
        lootTotal   = state.lootTotal,
        itemCount   = state.itemCount,
        gph         = Session.GoldPerHour(),
        lootPerHour = Session.LootPerHour(),
        zone        = state.zone,
    }
end
