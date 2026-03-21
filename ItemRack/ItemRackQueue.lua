-- ItemRackQueue.lua

function ItemRack.PeriodicQueueCheck()
	if SpellIsTargeting() then
		return
	end
	if ItemRackUser.EnableQueues=="ON" then
		for i in pairs(ItemRackUser.QueuesEnabled) do
			ItemRack.ProcessAutoQueue(i)
		end
	end
end

function ItemRack.ProcessAutoQueue(slot)
	if not slot or IsInventoryItemLocked(slot) then
		return
	end

	local start,duration,enable = GetInventoryItemCooldown("player",slot)
	local timeLeft = GetTime()-start
	local id = string.match(GetInventoryItemLink("player",slot) or "","item:(%d+)")
	local icon = getglobal("ItemRackButton"..slot.."Queue")

	if not id then return end

	local buff = GetItemSpell(id)
	if buff then
		if UnitAura("player",buff) or (start>0 and (duration-timeLeft)>30 and timeLeft<1) then
			icon:SetDesaturated(1)
			return
		end
	end

	local otherSlot = ItemRack.SlotInfo[slot] and ItemRack.SlotInfo[slot].other
	if otherSlot then
		local otherId = string.match(GetInventoryItemLink("player",otherSlot) or "","item:(%d+)")
		if otherId then
			local otherBuff = GetItemSpell(otherId)
			if otherBuff then
				local oStart,oDuration = GetInventoryItemCooldown("player",otherSlot)
				local oTimeLeft = GetTime()-oStart
				if UnitAura("player",otherBuff) or (oStart>0 and (oDuration-oTimeLeft)>30 and oTimeLeft<1) then
					icon:SetDesaturated(1)
					return
				end
			end
		end
	end

	if ItemRackItems[id] then
		if ItemRackItems[id].keep then
			icon:SetVertexColor(1,.5,.5)
			return -- leave if .keep flag set on this item
		end
		if ItemRackItems[id].delay then
			-- leave if currently equipped trinket is on cooldown for less than its delay
			if start>0 and (duration-timeLeft)>30 and timeLeft<ItemRackItems[id].delay then
				icon:SetDesaturated(1)
				return
			end
		end
	end
	icon:SetDesaturated(0)
	icon:SetVertexColor(1,1,1)

	local ready = ItemRack.ItemNearReady(id)
	if ready and ItemRack.CombatQueue[slot] then
		ItemRack.CombatQueue[slot] = nil
		ItemRack.UpdateCombatQueue()
	end

	local list,rank = ItemRackUser.Queues[slot]

	local candidate,bag,s
	for i=1,#(list) do
		candidate = string.match(list[i],"(%d+)")
		if list[i]==0 then
			break
		elseif ready and candidate==id then
			break
		else
			if not ready or enable==0 or (ItemRackItems[candidate] and ItemRackItems[candidate].priority) then
				if ItemRack.ItemNearReady(candidate) then
					if GetItemCount(candidate)>0 and not IsEquippedItem(candidate) then
						_,bag,s = ItemRack.FindItem(list[i])
						if bag then
							if ItemRack.CombatQueue[slot]~=list[i] then
								ItemRack.EquipItemByID(list[i],slot)
							end
							break
						end
					end
				end
			end
		end
	end
end

function ItemRack.ItemNearReady(id)
	local start,duration = GetItemCooldown(id)
	if start==0 or duration-(GetTime()-start)<30 then
		return 1
	end
end

function ItemRack.SetQueue(slot,newQueue)
	if not newQueue then
		ItemRackUser.QueuesEnabled[slot] = nil
	elseif type(newQueue)=="table" then
		ItemRackUser.Queues[slot] = ItemRackUser.Queues[slot] or {}
		for i in pairs(ItemRackUser.Queues[slot]) do
			ItemRackUser.Queues[slot][i] = nil
		end
		for i=1,#(newQueue) do
			table.insert(ItemRackUser.Queues[slot],newQueue[i])
		end
		if ItemRackOptFrame:IsVisible() then
			if ItemRackOptSubFrame7:IsVisible() and ItemRackOpt.SelectedSlot==slot then
				ItemRackOpt.SetupQueue(slot)
			else
				ItemRackOpt.UpdateInv()
			end
		end
		ItemRackUser.QueuesEnabled[slot] = 1
	end
	ItemRack.UpdateCombatQueue()
end
