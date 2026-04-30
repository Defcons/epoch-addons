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
}

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
