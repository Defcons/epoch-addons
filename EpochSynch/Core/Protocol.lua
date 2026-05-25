-- Core/Protocol.lua
-- Wire format encode/decode + send/receive for ES.
--
-- A single packet carries one OR MORE observation records, batched to
-- amortise per-message overhead and stay under 3.3.5's ~10 msg/sec
-- outbound throttle. Records are semicolon-delimited; fields within a
-- record are comma-delimited.
--
-- Fast packet (prefix EpochSynch_F): name,hp,x,y,flags
-- Slow packet (prefix EpochSynch_S): name,mp,classToken
-- Enemy packet (prefix EpochSynch_E): name,x,y[,class] — see Core/Enemy.lua
--
-- HP/MP/x/y are sent as integer 0..100 (percent) for HP/MP and 0..1000
-- (per-mille) for x/y. Per-mille gives ~3.7-yard precision on a 1000-
-- yard BG which is more than enough for "where is my flag carrier".
-- Both are bandwidth-friendly: each field is 1-4 ASCII chars.

local ES = EpochSynch
ES.Protocol = {}
local P = ES.Protocol

-- ----- encoders ---------------------------------------------------------

-- Pack a single fast-tier record: name,hp_pct,x_permille,y_permille,flags
function P.encodeFastRecord(r)
    return string.format("%s,%d,%d,%d,%d",
        r.name or "?",
        math.floor((r.hp or 0)  + 0.5),
        math.floor((r.x  or 0) * 1000 + 0.5),
        math.floor((r.y  or 0) * 1000 + 0.5),
        r.flags or 0)
end

function P.encodeSlowRecord(r)
    return string.format("%s,%d,%s",
        r.name or "?",
        math.floor((r.mp or 0) + 0.5),
        r.classToken or "?")
end

function P.encodeEnemyRecord(r)
    return string.format("%s,%d,%d,%s",
        r.name or "?",
        math.floor((r.x or 0) * 1000 + 0.5),
        math.floor((r.y or 0) * 1000 + 0.5),
        r.classToken or "?")
end

-- Batch records into a single message string. Caller responsible for
-- keeping the resulting string under WoW's ~255-byte per-message limit
-- — at ~30 bytes/record, 5-6 records is the comfortable ceiling.
local function batch(records, encoder)
    if not records or #records == 0 then return nil end
    local parts = {}
    for i = 1, #records do
        parts[i] = encoder(records[i])
    end
    return table.concat(parts, ";")
end
function P.encodeFastBatch(records)  return batch(records, P.encodeFastRecord)  end
function P.encodeSlowBatch(records)  return batch(records, P.encodeSlowRecord)  end
function P.encodeEnemyBatch(records) return batch(records, P.encodeEnemyRecord) end

-- ----- decoders ---------------------------------------------------------

-- Split helper. 3.3.5 has neither string.split nor strsplit on a
-- usable API surface for limit=N, so we roll our own. Pre-allocated
-- result avoids garbage on the hot CHAT_MSG_ADDON path.
local function splitInto(out, str, sep)
    local n, i = 0, 1
    for chunk in string.gmatch(str, "[^" .. sep .. "]+") do
        n = n + 1
        out[n] = chunk
    end
    return n
end

local _recordBuf = {}
local _fieldsBuf = {}

function P.decodeFastBatch(msg, into)
    into = into or {}
    local nrec = splitInto(_recordBuf, msg, ";")
    for r = 1, nrec do
        local nf = splitInto(_fieldsBuf, _recordBuf[r], ",")
        if nf >= 5 then
            into[#into + 1] = {
                name  = _fieldsBuf[1],
                hp    = tonumber(_fieldsBuf[2]) or 0,
                x     = (tonumber(_fieldsBuf[3]) or 0) / 1000,
                y     = (tonumber(_fieldsBuf[4]) or 0) / 1000,
                flags = tonumber(_fieldsBuf[5]) or 0,
            }
        end
    end
    return into
end

function P.decodeSlowBatch(msg, into)
    into = into or {}
    local nrec = splitInto(_recordBuf, msg, ";")
    for r = 1, nrec do
        local nf = splitInto(_fieldsBuf, _recordBuf[r], ",")
        if nf >= 2 then
            into[#into + 1] = {
                name       = _fieldsBuf[1],
                mp         = tonumber(_fieldsBuf[2]) or 0,
                classToken = _fieldsBuf[3] or "?",
            }
        end
    end
    return into
end

function P.decodeEnemyBatch(msg, into)
    into = into or {}
    local nrec = splitInto(_recordBuf, msg, ";")
    for r = 1, nrec do
        local nf = splitInto(_fieldsBuf, _recordBuf[r], ",")
        if nf >= 3 then
            into[#into + 1] = {
                name       = _fieldsBuf[1],
                x          = (tonumber(_fieldsBuf[2]) or 0) / 1000,
                y          = (tonumber(_fieldsBuf[3]) or 0) / 1000,
                classToken = _fieldsBuf[4] or "?",
            }
        end
    end
    return into
end

-- ----- send -------------------------------------------------------------

-- The chat type for in-BG broadcasts. RAID works when grouped into a
-- raid (which all BGs are); PARTY for sub-5-player BGs (rare). We try
-- RAID first and fall back to PARTY so the same call site works
-- regardless of group type.
local function chatType()
    if (GetNumRaidMembers and GetNumRaidMembers() or 0) > 0 then return "RAID" end
    if (GetNumPartyMembers and GetNumPartyMembers() or 0) > 0 then return "PARTY" end
    return nil
end

function P.send(prefix, msg)
    if not msg or msg == "" then return end
    local t = chatType()
    if not t then return end
    -- SendAddonMessage is unsecured on 3.3.5 — safe to call from any
    -- script context including OnUpdate handlers.
    SendAddonMessage(prefix, msg, t)
end
