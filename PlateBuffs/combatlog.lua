--[[
	Here I do the combatlog stuff. 
	
	Todo: 
		SPELL_AURA_REMOVED_DOSE
		SPELL_DISPEL
		SPELL_STOLEN
]]
local folder, core = ...

local GetTime = GetTime
local _G = _G
local UnitGUID = UnitGUID
local table_getn = table.getn
local table_remove = table.remove
local table_insert = table.insert
local bit_band = bit.band
local COMBATLOG_OBJECT_TYPE_PLAYER = COMBATLOG_OBJECT_TYPE_PLAYER
local nametoGUIDs = core.nametoGUIDs
local type = type
local GetSpellInfo = GetSpellInfo
local CombatLogClearEntries = CombatLogClearEntries

local P
local playerGUID
local Debug = core.Debug
local guidBuffs = core.guidBuffs
local _ --underscore so GetGlobals doesn't nag me.

local LibAI = LibStub("LibAuraInfo-1.0", true)
if not LibAI then	error(folder .. " requires LibAuraInfo-1.0.") return end

local prev_OnEnable = core.OnEnable
function core:OnEnable()
	prev_OnEnable(self)
	P = self.db.profile
	
	playerGUID = UnitGUID("player")

	core:RegisterLibAuraInfo()
	
end

function core:RegisterLibAuraInfo()
	LibAI.UnregisterAllCallbacks(self) 
	if P.watchCombatlog == true then
--~ 		self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
		LibAI.RegisterCallback(self, "LibAuraInfo_AURA_APPLIED")
		LibAI.RegisterCallback(self, "LibAuraInfo_AURA_REMOVED")
		LibAI.RegisterCallback(self, "LibAuraInfo_AURA_REFRESH")
		LibAI.RegisterCallback(self, "LibAuraInfo_AURA_APPLIED_DOSE")
		LibAI.RegisterCallback(self, "LibAuraInfo_AURA_CLEAR")
		
		CombatLogClearEntries()
	end
end

local prev_OnDisable = core.OnDisable
function core:OnDisable(...)
	if prev_OnDisable then prev_OnDisable(self, ...) end
	
	LibAI.UnregisterAllCallbacks(self) 
end

--[[
----------------------------------------------------------------------
function core:COMBAT_LOG_EVENT_UNFILTERED(event, ...)				--
-- Combatlog event handler. 										--
-- Check if we have eventType function then pass the event to it.	--
----------------------------------------------------------------------
	--timestamp, eventType, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags
	local _, eventType  = ...-- ***
--~ 	Debug(event, eventType, self[eventType])

--~ 	Debug(event, "eventType: "..tostring(eventType))
	if core[eventType] then
		core[eventType](self, eventType, ...)
	end
end

function core:GetSpellInfo(spellID)
	if spellInfo[spellID] then
--~ 		if type(spellInfo[spellID]) == "table" then
--~ 			return spellInfo[spellID].icon, spellInfo[spellID].duration, spellInfo[spellID].debuffType
--~ 		elseif type(spellInfo[spellID]) == "string" then
			local success, icon, duration, debuffType = core:Deserialize(spellInfo[spellID])
			if success then
--~ 				Debug("GetSpellInfo", spellID, icon, duration, debuffType, spellInfo[spellID])
				return icon, duration or 0, debuffType
			end
--~ 		end
	end
	return nil
end

--------------------------------------------------------------------------------------------------
function core:SPELL_AURA_APPLIED(event, _, _, srcGUID, srcName, _, dstGUID, dstName, dstFlags, ...)	--
-- Aura applied, if we know the spell's texture and duration then add it to our buffs list. 	--
--	If not add a question mark the the mob's nameplate.											--
--------------------------------------------------------------------------------------------------
	local spellID, spellName, spellSchool, auraType, amount  = ...
--~ 	Debug(event, spellID, spellName, spellSchool, auraType, amount)
	if spellInfo[spellID] then
		local icon, duration, debuffType = self:GetSpellInfo(spellID)
		if not icon then
			return false
		end
		
		
		local getTime = GetTime()

		guidBuffs[dstGUID] = guidBuffs[dstGUID] or {}
		local count = table_getn(guidBuffs[dstGUID])
		if P.spellOpts[spellName] and P.spellOpts[spellName].show then
			if P.spellOpts[spellName].show == 1 or (P.spellOpts[spellName].show == 2 and srcGUID == playerGUID) then --fix this
				if count == 0 then
					local i = count + 1
					table_insert(guidBuffs[dstGUID], i, {
						name		= spellName,
						icon		= icon,
						duration	= duration or 0,
						playerCast	= srcGUID == playerGUID and 1,
						stackCount	= 1,
						startTime	= getTime,
						expirationTime = getTime + (duration or 0),
						sID = spellID,
						caster = srcName,
					})
					
					if auraType == "DEBUFF" then
						guidBuffs[dstGUID][i].isDebuff = true
						guidBuffs[dstGUID][i].debuffType = debuffType or "none"
					end
				else
					self:RemoveOldSpells(dstGUID)
					count = table_getn(guidBuffs[dstGUID])
					for i=1, count do 
						if guidBuffs[dstGUID][i].sID == spellID and (not guidBuffs[dstGUID][i].caster or guidBuffs[dstGUID][i].caster == srcName) then
							--I know 2 of the same buff can be on someone, but how do I confirm that?
							-- unitCaster returns a unitID and combatlog has names. =/
							break
						elseif i == count then
							table_insert(guidBuffs[dstGUID], i+1, {
								name		= spellName,
								icon		= icon,
								duration	= (duration or 0),
								playerCast	= srcGUID == playerGUID and 1,
								stackCount	= 1,
								startTime	= getTime,
								expirationTime = getTime + (duration or 0),
								sID = spellID,
								caster = srcName,
							})
							
							if auraType == "DEBUFF" then
								guidBuffs[dstGUID][i+1].isDebuff = true
								guidBuffs[dstGUID][i+1].debuffType = debuffType or "none"
							end
						end
					end
				end
			end
		else
			if auraType == "BUFF" and P.defaultBuffShow == 1 or (P.defaultBuffShow == 2 and srcGUID == playerGUID) 
			or auraType == "DEBUFF" and P.defaultDebuffShow == 1 or (P.defaultDebuffShow == 2 and srcGUID == playerGUID) then

				if count == 0 then
					local i = count + 1
					table_insert(guidBuffs[dstGUID], i, {
						name		= spellName,
						icon		= icon,
						duration	= (duration or 0),
						playerCast	= srcGUID == playerGUID and 1,
						stackCount	= 1,
						startTime	= getTime,
						expirationTime = getTime + (duration or 0),
						sID = spellID,
						caster = srcName,
					})
					
					if auraType == "DEBUFF" then
						guidBuffs[dstGUID][i].isDebuff = true
						guidBuffs[dstGUID][i].debuffType = debuffType or "none"
					end
				else
					for i=1, count do 
						if guidBuffs[dstGUID][i].sID == spellID and (not guidBuffs[dstGUID][i].caster or guidBuffs[dstGUID][i].caster == srcName) then
							--I know 2 of the same buff can be on someone, but how do I confirm that?
							-- unitCaster returns a unitID and combatlog has names. =/
							break
						elseif i == count then
							table_insert(guidBuffs[dstGUID], i+1, {
								name		= spellName,
								icon		= icon,
								duration	= (duration or 0),
								playerCast	= srcGUID == playerGUID and 1,
								stackCount	= 1,
								startTime	= getTime,
								expirationTime = getTime + (duration or 0),
								sID = spellID,
								caster = srcName,
							})
							
							if auraType == "DEBUFF" then
								guidBuffs[dstGUID][i+1].isDebuff = true
								guidBuffs[dstGUID][i+1].debuffType = debuffType or "none"
							end
						end
					end
				end
			end
		end

--~ 		Debug("Combatlog", dstName, spellName, self:UpdatePlateByGUID(dstGUID), self:FlagIsPlayer(dstFlags))
		if not self:UpdatePlateByGUID(dstGUID) and self:FlagIsPlayer(dstFlags) then
			local shortName = core:RemoveServerName(dstName)
			nametoGUIDs[shortName] = dstGUID
			self:UpdatePlateByName(shortName)
		end
	end
	
end

------------------------------------------------------------------------------------------
function core:SPELL_AURA_REMOVED(event, _, _, srcGUID, srcName, _, dstGUID, dstName, dstFlags, ...)	--
-- Spell's been removed, remove it from our table.										--
------------------------------------------------------------------------------------------
	local spellID, spellName, spellSchool, auraType  = ...
	
	if guidBuffs[dstGUID] then
		for i=table_getn(guidBuffs[dstGUID]), 1, -1 do 
			if guidBuffs[dstGUID][i].sID == spellID and (not guidBuffs[dstGUID][i].caster or guidBuffs[dstGUID][i].caster == srcName) then
--~ 					Debug("REMOVED 3", spellName, srcName, dstName)
				table_remove(guidBuffs[dstGUID], i)
				if not self:UpdatePlateByGUID(dstGUID) and self:FlagIsPlayer(dstFlags) then
					self:UpdatePlateByName(dstName)
				end
				return
			end
		end
	end
end


function core:SPELL_AURA_REFRESH(event, _, _, srcGUID, srcName, _, dstGUID, dstName, dstFlags, ...)
	local spellID, spellName, spellSchool, auraType  = ...
	if guidBuffs[dstGUID] then
		for i=table_getn(guidBuffs[dstGUID]), 1, -1 do 
			if guidBuffs[dstGUID][i].sID == spellID and (not guidBuffs[dstGUID][i].caster or guidBuffs[dstGUID][i].caster == srcName) then
				local getTime = GetTime()
				guidBuffs[dstGUID][i].startTime	= getTime
				guidBuffs[dstGUID][i].expirationTime = getTime + guidBuffs[dstGUID][i].duration
--~ 				Debug("AURA_REFRESH", srcName, spellName, dstName)
				
				if not self:UpdatePlateByGUID(dstGUID) and self:FlagIsPlayer(dstFlags) then
					self:UpdatePlateByName(dstName)
				end
				return
			end
		end
	end
	--Spell isn't in our list, let's add it.
	self:SPELL_AURA_APPLIED(event, _, _, srcGUID, srcName, _, dstGUID, dstName, dstFlags, ...)
end

--DOSE = spell stacking
function core:SPELL_AURA_APPLIED_DOSE(event, _, _, srcGUID, srcName, _, dstGUID, dstName, dstFlags, ...)
	local spellID, spellName, spellSchool, auraType  = ...

--~ 	Debug("DOSE", srcName, spellName, dstName)
	if spellInfo[spellID] and guidBuffs[dstGUID] then
		for i=table_getn(guidBuffs[dstGUID]), 1, -1 do 
			if guidBuffs[dstGUID][i].sID == spellID and (not guidBuffs[dstGUID][i].caster or guidBuffs[dstGUID][i].caster == srcName) then
--~ 				Debug("SPELL_AURA_APPLIED_DOSE", srcName, spellName, dstName)
				guidBuffs[dstGUID][i].stackCount = guidBuffs[dstGUID][i].stackCount + 1
				
				if not self:UpdatePlateByGUID(dstGUID) and self:FlagIsPlayer(dstFlags) then
					self:UpdatePlateByName(dstName)
				end
				return
			end
		end
	end
	--Spell isn't in our list, let's add it.
	--Note this event could have fired on the 5th stack but our spell frame will only show it applied once. 
	self:SPELL_AURA_APPLIED(event, _, _, srcGUID, srcName, _, dstGUID, dstName, dstFlags, ...)
end

--sheep break
-- Gouge break
function core:SPELL_AURA_BROKEN_SPELL(event, _, _, srcGUID, srcName, _, dstGUID, dstName, dstFlags, ...)
--~ 	local spellID, spellName, spellSchool, auraType  = ...
	self:SPELL_AURA_REMOVED(event, _, _, srcGUID, srcName, _, dstGUID, dstName, dstFlags, ...)
end

--Not sure when this fires.
-- fires on sap break
function core:SPELL_AURA_BROKEN(event, _, _, srcGUID, srcName, _, dstGUID, dstName, dstFlags, ...)
--~ 	local spellID, spellName, spellSchool, auraType  = ...
	self:SPELL_AURA_REMOVED(event, _, _, srcGUID, srcName, _, dstGUID, dstName, dstFlags, ...)
end


function core:UNIT_DIED(event, _, _, srcGUID, srcName, _, dstGUID, dstName, dstFlags, ...)
	if guidBuffs[dstGUID] then
		--Remove all known buffs for that person. Maybe we're in a BG and don't need their old buffs on our plates.
		for i=table_getn(guidBuffs[dstGUID]), 1, -1 do 
			table_remove(guidBuffs[dstGUID], i)
		end
		if not self:UpdatePlateByGUID(dstGUID) and self:FlagIsPlayer(dstFlags) then
			self:UpdatePlateByName(dstName)
		end
	end
end

function core:UNIT_DESTROYED(event, _, _, srcGUID, srcName, _, dstGUID, dstName, dstFlags, ...)
	self:UNIT_DIED(event, _, _, srcGUID, srcName, _, dstGUID, dstName, dstFlags, ...)
end

function core:UNIT_DISSIPATES(event, _, _, srcGUID, srcName, _, dstGUID, dstName, dstFlags, ...)
	self:UNIT_DIED(event, _, _, srcGUID, srcName, _, dstGUID, dstName, dstFlags, ...)
end

function core:PARTY_KILL(event, _, _, srcGUID, srcName, _, dstGUID, dstName, dstFlags, ...)
	self:UNIT_DIED(event, _, _, srcGUID, srcName, _, dstGUID, dstName, dstFlags, ...)
end]]


function core:FlagIsPlayer(flags)
	if bit_band(flags, COMBATLOG_OBJECT_TYPE_PLAYER) == COMBATLOG_OBJECT_TYPE_PLAYER then
		return true
	end
	return nil
end



--[[]]
function core:ForceNameplateUpdate(dstGUID)
	if not self:UpdatePlateByGUID(dstGUID) then
		--We can't find a nameplate that matches that GUID.
		--Lets check if the GUID is a player, if so find a nameplate that matches the player's name.

		local dstName, dstFlags = LibAI:GetGUIDInfo(dstGUID)
		if dstFlags and self:FlagIsPlayer(dstFlags) then
			local shortName = self:RemoveServerName(dstName) --Nameplates don't have server names.
			nametoGUIDs[shortName] = dstGUID
			self:UpdatePlateByName(shortName)
		end
	end
end

-- Claude: rewritten to match by srcGUID, guard nil duration/expires, support no-timer entries
function core:AddSpellToGUID(dstGUID, spellID, srcName, spellName, spellTexture, duration, srcGUID, isDebuff, debuffType, expires, stackCount)
	guidBuffs[dstGUID] = guidBuffs[dstGUID] or {}
	if #guidBuffs[dstGUID] > 0 then
		self:RemoveOldSpells(dstGUID)
	end

	local getTime = GetTime()
	-- Claude: normalize duration/expires. If duration is unknown (0/nil), store
	-- expirationTime=0 so iconOnUpdate's "> 0" guard treats it as no-timer and
	-- never auto-removes (only SPELL_AURA_REMOVED clears it).
	local normDuration = (duration and duration > 0) and duration or 0
	local normExpires
	if expires and expires > 0 then
		normExpires = expires
	elseif normDuration > 0 then
		normExpires = getTime + normDuration
	else
		normExpires = 0
	end

	local count = #guidBuffs[dstGUID]
	if count == 0 then
		local i = 0
		table_insert(guidBuffs[dstGUID], i+1, {
			name		= spellName,
			icon		= spellTexture,
			duration	= normDuration,
			playerCast	= srcGUID == playerGUID and 1,
			stackCount	= stackCount or 1,
			startTime	= getTime,
			expirationTime = normExpires,
			sID = spellID,
			caster = srcName,
			casterGUID = srcGUID, -- Claude: GUID-based match (CLEU always provides this)
		})

		if isDebuff then
			guidBuffs[dstGUID][i+1].isDebuff = true
			guidBuffs[dstGUID][i+1].debuffType = debuffType or "none"
		end
		return true

	else
		for i=1, count do
			-- Claude: prefer casterGUID match; fall back to legacy name match for old entries
			local entry = guidBuffs[dstGUID][i]
			local sameCaster = (entry.casterGUID and entry.casterGUID == srcGUID)
				or (not entry.casterGUID and (not entry.caster or entry.caster == srcName))
			if entry.sID == spellID and sameCaster then
				entry.expirationTime = normExpires
				entry.startTime = getTime
				entry.duration = normDuration
				entry.casterGUID = srcGUID -- backfill for legacy entries
				return true
			elseif i == count then
				table_insert(guidBuffs[dstGUID], i+1, {
					name		= spellName,
					icon		= spellTexture,
					duration	= normDuration,
					playerCast	= srcGUID == playerGUID and 1,
					stackCount	= stackCount or 1,
					startTime	= getTime,
					expirationTime = normExpires,
					sID = spellID,
					caster = srcName,
					casterGUID = srcGUID, -- Claude
				})

				if isDebuff then
					guidBuffs[dstGUID][i+1].isDebuff = true
					guidBuffs[dstGUID][i+1].debuffType = debuffType or "none"
				end
				return true
			end
		end
	end
	return false
end

-- Claude: bypass LibAI gating. If LibAI hasn't tracked the aura yet (cold cache,
-- spell not in its filter), still add it using GetSpellInfo + auraType from CLEU.
function core:LibAuraInfo_AURA_APPLIED(event, dstGUID, spellID, srcGUID, spellSchool, auraType)
	local found, stackCount, debuffType, duration, expires, isDebuff, casterGUID = LibAI:GUIDAuraID(dstGUID, spellID)

	local spellName, _, spellTexture = GetSpellInfo(spellID)
	if not spellName or not spellTexture then return end -- Claude: nothing we can show

	-- Claude: fall back to CLEU-derived data when LibAI is silent
	if not found then
		stackCount = 1
		isDebuff = (auraType == "DEBUFF")
		debuffType = nil
		duration = 0   -- AddSpellToGUID will treat as no-timer
		expires = 0
	end

	if core.PB_DEBUG then
		local dn = LibAI:GetGUIDInfo(dstGUID) or "?"
		Debug("AURA_APPLIED", found and "lib" or "cleu", dn, spellName, spellID, "dur="..tostring(duration))
	end

	for _, _, shortIcon in spellTexture:gmatch("(.+)\\(.+)\\(.+)") do
		spellTexture = shortIcon
		break
	end

	local updateBars = false
	if P.spellOpts[spellName] and P.spellOpts[spellName].show then
		if P.spellOpts[spellName].show == 1 or (P.spellOpts[spellName].show == 2 and srcGUID == playerGUID) then
			local srcName = LibAI:GetGUIDInfo(srcGUID)
			updateBars = self:AddSpellToGUID(dstGUID, spellID, srcName, spellName, spellTexture, duration, srcGUID, isDebuff, debuffType, expires, stackCount)
		end
	else
		if auraType == "BUFF" and P.defaultBuffShow == 1 or (P.defaultBuffShow == 2 and srcGUID == playerGUID)
		or auraType == "DEBUFF" and P.defaultDebuffShow == 1 or (P.defaultDebuffShow == 2 and srcGUID == playerGUID) then
			local srcName = LibAI:GetGUIDInfo(srcGUID)
			updateBars = self:AddSpellToGUID(dstGUID, spellID, srcName, spellName, spellTexture, duration, srcGUID, isDebuff, debuffType, expires, stackCount)
		end
	end

	if updateBars then
		-- Claude: opportunistically learn dstName -> dstGUID for plate fallback resolution.
		-- Mark colliding names as `false` so we never bind to the wrong nameplate.
		local dstName = LibAI:GetGUIDInfo(dstGUID)
		if dstName then
			local existing = nametoGUIDs[dstName]
			if existing == nil then
				nametoGUIDs[dstName] = dstGUID
			elseif existing ~= dstGUID and existing ~= false then
				nametoGUIDs[dstName] = false -- collision; disable name fallback for this name
			end
		end
		core:ForceNameplateUpdate(dstGUID)
	end
end



-- Claude: match by casterGUID so other players' removes can't strip ours
function core:LibAuraInfo_AURA_REMOVED(event, dstGUID, spellID, srcGUID, spellSchool, auraType)
	if guidBuffs[dstGUID] then
		for i = #guidBuffs[dstGUID], 1, -1 do
			local entry = guidBuffs[dstGUID][i]
			if entry.sID == spellID and (entry.casterGUID == srcGUID or (not entry.casterGUID and not entry.caster)) then
				if core.PB_DEBUG then Debug("AURA_REMOVED", entry.name, "from", LibAI:GetGUIDInfo(dstGUID) or "?") end
				table_remove(guidBuffs[dstGUID], i)
				self:ForceNameplateUpdate(dstGUID)
				return
			end
		end
	end
end

-- Claude: match by casterGUID; refresh from another caster won't refresh our entry
function core:LibAuraInfo_AURA_REFRESH(event, dstGUID, spellID, srcGUID, spellSchool, auraType, expirationTime)
	local spellName = GetSpellInfo(spellID)

	if guidBuffs[dstGUID] then
		for i = #guidBuffs[dstGUID], 1, -1 do
			local entry = guidBuffs[dstGUID][i]
			if entry.sID == spellID and (entry.casterGUID == srcGUID or (not entry.casterGUID and not entry.caster)) then
				local getTime = GetTime()
				entry.startTime = getTime
				if expirationTime and expirationTime > 0 then
					entry.expirationTime = expirationTime
				elseif entry.duration and entry.duration > 0 then
					entry.expirationTime = getTime + entry.duration
				end
				if core.PB_DEBUG then Debug("AURA_REFRESH", spellName, "on", LibAI:GetGUIDInfo(dstGUID) or "?") end
				self:ForceNameplateUpdate(dstGUID)
				return
			end
		end
	end

	
	local dstName = LibAI:GetGUIDInfo(dstGUID)
	if not LibAI:GUIDAuraID(dstGUID, spellID) then
		Debug("SPELL_AURA_REFRESH",LibAI:GUIDAuraID(dstGUID, spellID), dstName, spellName, "passing to SPELL_AURA_APPLIED")
	end
	self:LibAuraInfo_AURA_APPLIED(event, dstGUID, spellID, srcGUID, spellSchool, auraType)
end


--DOSE = spell stacking
function core:LibAuraInfo_AURA_APPLIED_DOSE(event, dstGUID, spellID, srcGUID, spellSchool, auraType, stackCount, expirationTime)
	local spellName = GetSpellInfo(spellID)
--~ 	local _, stackCount1 = LibAI:GUIDAuraID(dstGUID, spellID)
--~ 	if srcGUID == playerGUID then
--~ 		
--~ 		Debug("AURA_APPLIED_DOSE", spellName, count, stackCount)
--~ 	end
	
	if guidBuffs[dstGUID] then
		for i = #guidBuffs[dstGUID], 1, -1 do
			local entry = guidBuffs[dstGUID][i]
			-- Claude: match by casterGUID
			if entry.sID == spellID and (entry.casterGUID == srcGUID or (not entry.casterGUID and not entry.caster)) then
				entry.stackCount = stackCount
				entry.startTime = GetTime()
				if expirationTime and expirationTime > 0 then
					entry.expirationTime = expirationTime
				end
				self:ForceNameplateUpdate(dstGUID)
				return
			end
		end
	end
	
	
	local dstName = LibAI:GetGUIDInfo(dstGUID)
	if not LibAI:GUIDAuraID(dstGUID, spellID) then
		Debug("LAURA_APPLIED_DOSE", dstName, spellName, "passing to SPELL_AURA_APPLIED")
	end
	self:LibAuraInfo_AURA_APPLIED(event, dstGUID, spellID, srcGUID, spellSchool, auraType)
end

function core:LibAuraInfo_AURA_CLEAR(event, dstGUID)
	if guidBuffs[dstGUID] then
		--Remove all known buffs for that person. Maybe we're in a BG and don't need their old buffs on our plates.
		for i=table_getn(guidBuffs[dstGUID]), 1, -1 do
			table_remove(guidBuffs[dstGUID], i)
		end
		self:ForceNameplateUpdate(dstGUID)
	end
end

-- Claude: backup CLEU listener for SPELL_PERIODIC_AURA_* (some Ascension DoTs/HoTs
-- only fire under the periodic prefix and LibAuraInfo doesn't always dispatch them).
local pbCleuFrame = CreateFrame("Frame")
pbCleuFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
pbCleuFrame:SetScript("OnEvent", function(self, event, ...)
	local _, eventType, srcGUID, _, _, dstGUID, _, _, spellID, _, spellSchool, auraType = ...
	if eventType == "SPELL_PERIODIC_AURA_APPLIED" then
		core:LibAuraInfo_AURA_APPLIED("SPELL_PERIODIC_AURA_APPLIED", dstGUID, spellID, srcGUID, spellSchool, auraType)
	elseif eventType == "SPELL_PERIODIC_AURA_REFRESH" then
		core:LibAuraInfo_AURA_REFRESH("SPELL_PERIODIC_AURA_REFRESH", dstGUID, spellID, srcGUID, spellSchool, auraType, nil)
	elseif eventType == "SPELL_PERIODIC_AURA_REMOVED" then
		core:LibAuraInfo_AURA_REMOVED("SPELL_PERIODIC_AURA_REMOVED", dstGUID, spellID, srcGUID, spellSchool, auraType)
	end
end)