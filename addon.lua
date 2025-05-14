local core = LibStub("AceAddon-3.0"):NewAddon("DropTheCheapestThing", "AceEvent-3.0", "AceBucket-3.0")
local AceTimer = LibStub("AceTimer-3.0")
local AdiBags
if IsAddOnLoaded("AdiBags") then
    AdiBags = LibStub('AceAddon-3.0'):GetAddon('AdiBags')
end

local debugf = tekDebug and tekDebug:GetFrame("DropTheCheapestThing")
local function Debug(...)
    if debugf then
        debugf:AddMessage(string.join(", ", ...))
    end
end

local db, iterate_bags, slot_sorter, copper_to_pretty_money, encode_bagslot,
decode_bagslot, pretty_bagslot_name, drop_bagslot, add_junk_to_tooltip,
link_to_id, item_value, GetConsideredItemInfo, markItemForSale, clearSellIcons

local drop_slots = {}
local sell_slots = {}
local slot_contents = {}
local slot_counts = {}
local slot_stacksizes = {}
local slot_values = {}
local slot_weightedvalues = {}
local slot_valuesources = {}

core.drop_slots = drop_slots
core.sell_slots = sell_slots
core.slot_contents = slot_contents
core.slot_counts = slot_counts
core.slot_stacksizes = slot_stacksizes
core.slot_values = slot_values
core.slot_weightedvalues = slot_weightedvalues
core.slot_valuesources = slot_valuesources
core.events = LibStub("CallbackHandler-1.0"):New(core)
core.has_loaded = false

function core:OnInitialize()
    db = LibStub("AceDB-3.0"):New("DropTheCheapestThingDB", {
        profile = {
            threshold = 0, -- items above this quality won't even be considered
            sell_threshold = 0,
            always_consider = {},
            never_consider = {},
            auto_delete = {},
            auction = false,
            auction_threshold = 1,
            full_stacks = false,
            auto_delete_toggle = true,
            combat_delete_toggle = true,
            print_delete_toggle = false,
            sell_next_vendor = {}
        },
    }, "Default") -- Added "Default" profile name, AceDB-3.0 needs it
    self.db = db
    self:RegisterBucketEvent("BAG_UPDATE", 2, "ThrottledBagUpdate") -- Use a different method name for bucketed event
    self:RegisterEvent("MERCHANT_SHOW")
    self:RegisterEvent("MERCHANT_CLOSED")
    self:RegisterEvent("PLAYER_LOGIN", "OnPlayerLogin") -- For initial setup

    -- No need to check MerchantFrame:IsVisible() here, MERCHANT_SHOW will handle it if already open.
end

function core:OnPlayerLogin()
    -- Initial bag update after a delay to ensure everything is loaded
    AceTimer:ScheduleTimer(function()
        if IsAddOnLoaded("AdiBags") and AdiBagsContainer1 then
            -- Hook AdiBags if it's present
            if not AdiBagsContainer1.dtctHooked then -- Prevent multiple hooks
                AdiBagsContainer1:HookScript("OnHide", function()
                    -- self:_BAG_UPDATE_INTERNAL() -- Consider if this is needed or too much
                end)
                AdiBagsContainer1:HookScript("OnShow", function()
                    self:ScheduleBagUpdate() -- Use scheduled update
                end)
                AdiBagsContainer1.dtctHooked = true
            end
        end
        self:ScheduleBagUpdate() -- Initial scan
    end, 5) -- 5 second delay after login
    self.has_loaded = true
end


function core:Print(...)
    ChatFrame1:AddMessage(string.join(" ", "|cFF33FF99DropTCT|r:", ...))
end

function core:MERCHANT_SHOW()
    Debug("MERCHANT_SHOW")
    self.at_merchant = true
    self:ScheduleBagUpdate() -- Update when merchant opens, as sellability might change
    self.events:Fire("Merchant_Open")
end

function core:MERCHANT_CLOSED()
    Debug("MERCHANT_CLOSED")
    self.at_merchant = nil
    self:ScheduleBagUpdate() -- Update when merchant closes
    self.events:Fire("Merchant_Close")
end

function item_value(item, force_vendor)
    local vendor = select(11, GetItemInfo(item)) or 0
    if db.profile.auction and GetAuctionBuyout and not force_vendor then
        local auction = GetAuctionBuyout(item) or 0
        if auction > vendor then
            return auction, 'auction'
        end
    end
    return vendor, 'vendor'
end
core.item_value = item_value

local bagUpdateScheduled = nil
function core:ScheduleBagUpdate()
    if bagUpdateScheduled then
        AceTimer:CancelTimer(bagUpdateScheduled)
    end
    -- print("DTCT: Scheduling _BAG_UPDATE_INTERNAL")
    bagUpdateScheduled = AceTimer:ScheduleTimer(function()
        -- print("DTCT: Executing scheduled _BAG_UPDATE_INTERNAL")
        self:_BAG_UPDATE_INTERNAL()
        bagUpdateScheduled = nil
    end, 0.1) -- Consolidate updates within a 0.5 sec window
end

function core:ThrottledBagUpdate() -- Renamed to avoid conflict with direct calls
    -- print("DTCT: ThrottledBagUpdate (from bucket)")
    self:ScheduleBagUpdate()
end


-- Replace the existing _BAG_UPDATE_INTERNAL function with this one.

function core:_BAG_UPDATE_INTERNAL()
    -- print("DTCT: _BAG_UPDATE_INTERNAL running")
    table.wipe(drop_slots)
    table.wipe(sell_slots)
    table.wipe(slot_contents)
    table.wipe(slot_counts)
    table.wipe(slot_stacksizes)
    table.wipe(slot_values)
    table.wipe(slot_weightedvalues)
    table.wipe(slot_valuesources)

    local total, total_sell, total_drop = 0, 0, 0
    local characterName = UnitName("player")

    -- 1. Process all items to populate drop_slots, sell_slots, and other data
    -- This part remains largely the same, but we won't try to update icons here yet.
    for bag = 0, NUM_BAG_SLOTS do
        local bagsSlotCount = GetContainerNumSlots(bag)
        for slot = 1, bagsSlotCount do
            local itemid, link, count, stacksize, quality, value, source = GetConsideredItemInfo(bag, slot)

            if itemid then
                local bagslot = encode_bagslot(bag, slot)
                slot_contents[bagslot] = link
                slot_counts[bagslot] = count
                slot_stacksizes[bagslot] = stacksize
                slot_values[bagslot] = value * count
                slot_weightedvalues[bagslot] = db.profile.full_stacks and (value * stacksize) or (value * count)
                slot_valuesources[bagslot] = source

                local isDropCandidate = false
                if db.profile.always_consider[itemid] or quality <= db.profile.threshold then
                    isDropCandidate = true
                    table.insert(drop_slots, bagslot)
                    total_drop = total_drop + slot_values[bagslot]
                end

                local isSellCandidate = false
                if db.profile.always_consider[itemid] then -- always_consider items are sell candidates
                    isSellCandidate = true
                elseif quality <= db.profile.sell_threshold then
                    isSellCandidate = true
                end

                local itemNameFromLink = GetItemInfo(link)
                if core.db.profile.sell_next_vendor[itemid] then
                    for _, uniqueIdentifier in ipairs(core.db.profile.sell_next_vendor[itemid]) do
                        local storedCharacterName, storedItemName = string.match(uniqueIdentifier, "(.-):(.*)")
                        if storedCharacterName == characterName and storedItemName == itemNameFromLink then
                            isSellCandidate = true
                            break
                        end
                    end
                end

                if isSellCandidate then
                    if not tContains(sell_slots, bagslot) then
                        table.insert(sell_slots, bagslot)
                    end
                    total_sell = total_sell + slot_values[bagslot]
                end
                total = total + slot_values[bagslot]
            end
        end
    end



    -- 2. Update Icons for Standard Bags
    clearSellIcons() -- Clears old standard bag icons (ensure this function itself is correct for standard bags)

    -- Re-iterate to apply icons to standard bags, using THE CORRECT OLD INDEXING
    for bag = 0, NUM_BAG_SLOTS do
        local containerFrame = _G["ContainerFrame" .. (bag + 1)]
        if containerFrame and containerFrame:IsShown() then
            local bagsSlotCount = GetContainerNumSlots(bag) -- Get bagsSlotCount here
            for slot = 1, bagsSlotCount do
                -- ***** THIS IS THE CRUCIAL FIX FOR STANDARD BAGS *****
                local itemButtonStd = _G["ContainerFrame" .. (bag + 1) .. "Item" .. (bagsSlotCount - slot + 1)]
                -- ******************************************************

                if itemButtonStd then -- Check if the button itself exists
                    local itemLink = GetContainerItemLink(bag, slot) -- Get link based on logical bag/slot
                    if itemLink then
                        local itemid = link_to_id(itemLink)
                        if itemid then
                            local shouldBeMarked = false
                            if (db.profile.always_consider[itemid] and not db.profile.never_consider[itemid]) then
                                shouldBeMarked = true
                            end
                            if core.db.profile.sell_next_vendor[itemid] then
                                local itemName = GetItemInfo(itemLink)
                                local uniqueIdentifier = characterName .. ":" .. (itemName or "")
                                if tContains(core.db.profile.sell_next_vendor[itemid], uniqueIdentifier) then
                                    shouldBeMarked = true
                                end
                            end
                            -- Call markItemForSale with the correctly identified button and its logical bag/slot
                            markItemForSale(itemButtonStd, itemid, itemLink, characterName, bag, slot, false)
                        else
                            -- No valid itemid from link, ensure icon on this specific button is hidden
                            if itemButtonStd.textureFrame then itemButtonStd.textureFrame:Hide() end
                        end
                    else
                        -- No itemLink in this logical bag/slot, ensure icon on this specific button is hidden
                        if itemButtonStd.textureFrame then itemButtonStd.textureFrame:Hide() end
                    end
                end
            end
        end
    end


    -- 3. Update Icons for AdiBags
    if AdiBags then
        -- Iterate ALL potentially visible AdiBags buttons and update their icon state.
        -- This is still the "iterate 1 to 360" approach, which isn't ideal for performance
        -- but is necessary for this direct manipulation method if we don't have a better way
        -- to get only currently rendered AdiBags buttons.
        for i = 1, 360 do -- Max possible AdiBags buttons
            local frameName = "AdiBagsItemButton" .. i
            local adiButton = _G[frameName]

            if adiButton and adiButton:IsShown() and adiButton.bag and adiButton.slot then
                local itemLink = GetContainerItemLink(adiButton.bag, adiButton.slot)
                if itemLink then
                    local itemid = link_to_id(itemLink)
                    if itemid then
                        -- Determine if this AdiBags item should be marked
                        local shouldBeMarked = false
                        if (db.profile.always_consider[itemid] and not db.profile.never_consider[itemid]) then
                            shouldBeMarked = true
                        end
                        if core.db.profile.sell_next_vendor[itemid] then
                            local itemName = GetItemInfo(itemLink)
                            local uniqueIdentifier = characterName .. ":" .. (itemName or "")
                            if tContains(core.db.profile.sell_next_vendor[itemid], uniqueIdentifier) then
                                shouldBeMarked = true
                            end
                        end
                        markItemForSale(adiButton, itemid, itemLink, characterName, adiButton.bag, adiButton.slot, true)
                    else
                        -- No valid itemid from link, ensure icon is hidden
                        if adiButton.dtctSellIcon then adiButton.dtctSellIcon:Hide() end
                    end
                else
                    -- No itemLink in this AdiBags button slot, ensure icon is hidden
                    if adiButton.dtctSellIcon then adiButton.dtctSellIcon:Hide() end
                end
            end
        end
        -- AdiBags:SendMessage("AdiBags_UpdateAllButtons") -- This might be redundant if we are manually updating icons,
        -- but could be needed if AdiBags does other things.
        -- If performance is good, leave it. If not, try removing.
        -- Given we directly manipulate, it might be safe to remove or make conditional.
        -- For now, let's keep it to be safe, as AdiBags might do other layout updates.
    end
    if AdiBags then AdiBags:SendMessage("AdiBags_UpdateAllButtons") end -- Keep this for now
    table.sort(drop_slots, slot_sorter)
    table.sort(sell_slots, slot_sorter)
    self.events:Fire("Junk_Update", #drop_slots, #sell_slots, total_drop, total_sell, total)
end


function GetConsideredItemInfo(bag, slot)
    local link = GetContainerItemLink(bag, slot)
    if not link then return end

    local _, count, _, quality = GetContainerItemInfo(bag, slot)
    local stacksize = select(8, GetItemInfo(link))
    if quality == -1 then quality = select(3, GetItemInfo(link)) end
    if not quality then return end

    local itemid = link_to_id(link)
    if db.profile.never_consider[itemid] then return end

    -- Simplified condition: if it's not always_consider and above both thresholds, and not in sell_next_vendor, ignore.
    local itemNameFromLink = GetItemInfo(link) -- Get name for sell_next_vendor check
    local characterName = UnitName("player")
    local inSellNextVendorList = false
    if core.db.profile.sell_next_vendor[itemid] then
        for _, uniqueIdentifier in ipairs(core.db.profile.sell_next_vendor[itemid]) do
            local storedCharacterName, storedItemName = string.match(uniqueIdentifier, "(.-):(.*)")
            if storedCharacterName == characterName and storedItemName == itemNameFromLink then
                inSellNextVendorList = true
                break
            end
        end
    end

    if not db.profile.always_consider[itemid] and
            quality > db.profile.threshold and
            quality > db.profile.sell_threshold and
            not inSellNextVendorList then
        return
    end

    local value, source = item_value(itemid, quality < db.profile.auction_threshold)
    if (not value) or value == 0 then return end
    return itemid, link, count, stacksize, quality, value, source
end

function slot_sorter(a, b)
    if slot_weightedvalues[a] == slot_weightedvalues[b] then
        if slot_values[a] == slot_values[b] then
            return slot_counts[a] < slot_counts[b]
        end
        return slot_values[a] < slot_values[b]
    end
    return slot_weightedvalues[a] < slot_weightedvalues[b]
end

function link_to_id(link)
    return link and tonumber(string.match(link, "item:(%d+)"))
end
core.link_to_id = link_to_id

function pretty_bagslot_name(bagslot, show_name, show_count, force_count)
    if not bagslot or not slot_contents[bagslot] then return "???" end
    if show_name == nil then show_name = true end
    if show_count == nil then show_count = true end
    local link = slot_contents[bagslot]
    local name = GetItemInfo(link) -- Use GetItemInfo for name to be consistent
    local max = select(8, GetItemInfo(link))
    return (show_name and name or '') .. -- Changed to use name from GetItemInfo
            ((show_name and show_count) and ' ' or '') ..
            ((show_count and (force_count or max > 1)) and (slot_counts[bagslot] .. '/' .. max) or '')
end
core.pretty_bagslot_name = pretty_bagslot_name

function copper_to_pretty_money(c)
    if c == nil then c = 0 end -- Safety for nil values
    if c >= 10000 then
        return ("|cffffffff%d|r|cffffd700g|r|cffffffff%d|r|cffc7c7cfs|r|cffffffff%d|r|cffeda55fc|r"):format(floor(c / 10000), floor((c / 100) % 100), floor(c % 100))
    elseif c >= 100 then
        return ("|cffffffff%d|r|cffc7c7cfs|r|cffffffff%d|r|cffeda55fc|r"):format(floor((c / 100) % 100), floor(c % 100))
    else
        return ("|cffffffff%d|r|cffeda55fc|r"):format(floor(c % 100))
    end
end
core.copper_to_pretty_money = copper_to_pretty_money

function add_junk_to_tooltip(tooltip, slots)
    slots = slots or drop_slots
    if #slots == 0 then
        tooltip:AddLine("Nothing")
        return
    else
        local total = 0
        for _, bagslot in ipairs(slots) do
            tooltip:AddDoubleLine(pretty_bagslot_name(bagslot), copper_to_pretty_money(slot_values[bagslot]) ..
                    (slot_values[bagslot] ~= slot_weightedvalues[bagslot] and (' (' .. copper_to_pretty_money(slot_weightedvalues[bagslot]) .. ')') or '') ..
                    (db.profile.auction and
                            (' ' .. (slot_valuesources[bagslot] == 'vendor' and '|cff9d9d9d' or '|cff1eff00') ..
                                    slot_valuesources[bagslot]:sub(1, 1)) ..
                                    (slot_valuesources[bagslot] == 'vendor' and '|r' or '') or ''
                    ),
                    nil, nil, nil, 1, 1, 1)
            total = total + slot_values[bagslot]
        end
        tooltip:AddDoubleLine(" ", "Total: " .. copper_to_pretty_money(total), nil, nil, nil, 1, 1, 1)
    end
end
core.add_junk_to_tooltip = add_junk_to_tooltip

function encode_bagslot(bag, slot) return (bag * 100) + slot end
function decode_bagslot(int) return math.floor(int / 100), int % 100 end
core.encode_bagslot = encode_bagslot
core.decode_bagslot = decode_bagslot

function drop_bagslot(bagslot, sell_only)
    Debug("drop_bagslot", bagslot, sell_only and 'sell_only' or '')
    Debug("At merchant?", core.at_merchant and 'yes' or 'no')
    local bag, slot = decode_bagslot(bagslot)
    if CursorHasItem() then
        return DEFAULT_CHAT_FRAME:AddMessage(("DropTheCheapestThing Error: Can't delete/sell items while an item is on the cursor. Aborting."), 1, 0, 0)
    end
    if sell_only and not core.at_merchant then
        return DEFAULT_CHAT_FRAME:AddMessage(("DropTheCheapestThing Error: Can't sell items while not at a merchant. Aborting."), 1, 0, 0)
    end
    if not (bagslot and slot_contents[bagslot]) then
        return DEFAULT_CHAT_FRAME:AddMessage("DropTheCheapestThing Error: Nothing found in requested slot. Aborting.", 1, 0, 0)
    end
    -- Re-fetch current link to compare, as slot_contents might be stale if BAG_UPDATE hasn't run recently
    local currentLinkInSlot = GetContainerItemLink(bag, slot)
    if slot_contents[bagslot] ~= currentLinkInSlot then
        -- Don't abort here, just log it maybe. The action should still proceed based on the intended item.
        -- Or, if it's critical, then re-evaluate. For now, proceed with caution.
        -- print(("DropTheCheapestThing Warning: Expected %s in bag slot, found %s instead. Proceeding cautiously."):format(slot_contents[bagslot], currentLinkInSlot or "nothing"))
    end
    if not currentLinkInSlot then -- If the slot is now empty
        return DEFAULT_CHAT_FRAME:AddMessage("DropTheCheapestThing Error: Slot is now empty. Aborting.", 1, 0, 0)
    end


    local itemToProcessName = pretty_bagslot_name(bagslot) -- Use cached name for message
    local valueToProcess = slot_values[bagslot] or 0 -- Use cached value

    if core.at_merchant then
        DEFAULT_CHAT_FRAME:AddMessage("Selling " .. itemToProcessName .. " for " .. copper_to_pretty_money(valueToProcess))
        UseContainerItem(bag, slot)
        local charName = UnitName("player")
        local itemid = link_to_id(slot_contents[bagslot]) -- Get itemid from cached link
        if itemid and core.db.profile.sell_next_vendor[itemid] then
            local itemNameFromLink = GetItemInfo(slot_contents[bagslot]) -- Get name from cached link
            local entries = core.db.profile.sell_next_vendor[itemid]
            for i = #entries, 1, -1 do
                local storedCharacterName, storedItemName = string.match(entries[i], "(.-):(.*)")
                if storedCharacterName == charName and storedItemName == itemNameFromLink then
                    table.remove(entries, i)
                end
            end
            if #entries == 0 then
                core.db.profile.sell_next_vendor[itemid] = nil
            end
        end
    else
        DEFAULT_CHAT_FRAME:AddMessage("Dropping " .. itemToProcessName .. " worth " .. copper_to_pretty_money(valueToProcess))
        PickupContainerItem(bag, slot)
        DeleteCursorItem()
    end
    core:ScheduleBagUpdate() -- Rescan bags after action
end
core.drop_bagslot = drop_bagslot

local autoDeleteScheduled = nil
function core:ProcessAutoDelete()
    autoDeleteScheduled = nil -- Clear schedule flag
    local autoDeleteList = core.db.profile.auto_delete or {}
    if not core.db.profile.auto_delete_toggle or (#autoDeleteList == 0) or (not core.db.profile.combat_delete_toggle and UnitAffectingCombat('Player')) then
        return
    end

    if not core.deletedItems then core.deletedItems = {} end

    for bag = 0, NUM_BAG_SLOTS do -- Iterate all bags, including bank if open
        for slot = 1, GetContainerNumSlots(bag) do
            local itemLink = GetContainerItemLink(bag, slot)
            if itemLink then
                local itemId = tonumber(itemLink:match("item:(%d+)"))
                if itemId and autoDeleteList[itemId] then
                    local itemKey = bag .. "-" .. slot
                    if not core.deletedItems[itemKey] and core.db.profile.print_delete_toggle then
                        core:Print('Deleting ' .. itemLink .. ' (' .. bag + 1 .. ',' .. slot .. ')')
                        core.deletedItems[itemKey] = true
                        AceTimer:ScheduleTimer(function() core.deletedItems[itemKey] = nil end, 2) -- Clear after 2s
                    end
                    PickupContainerItem(bag, slot)
                    if CursorHasItem() then DeleteCursorItem() end
                    -- No need to schedule another ProcessAutoDelete from here, ITEM_PUSH will handle it
                    return -- Exit after one deletion to avoid issues, ITEM_PUSH will re-trigger for next
                end
            end
        end
    end
end

local function onItemPushOrUpdate()
    if autoDeleteScheduled then AceTimer:CancelTimer(autoDeleteScheduled) end
    autoDeleteScheduled = AceTimer:ScheduleTimer(function() core:ProcessAutoDelete() end, 1.5)
end

local customFrame = CreateFrame("Frame")
customFrame:RegisterEvent("ITEM_PUSH", onItemPushOrUpdate)
customFrame:RegisterEvent("BAG_UPDATE_COOLDOWN", onItemPushOrUpdate) -- Might help catch other changes

AceTimer:ScheduleTimer(function() core:ProcessAutoDelete() end, 2.5) -- Initial run after login/load

function core:ALT_CLICK_ITEM(bag, slot)
    local link = GetContainerItemLink(bag, slot)
    if not link then return end
    local id = link:match("item:(%d+)")
    id = tonumber(id)
    local name = GetItemInfo(link)
    if id and IsAltKeyDown() then
        local characterName = UnitName("player")
        if not core.db.profile.sell_next_vendor[id] then
            core.db.profile.sell_next_vendor[id] = {}
        end
        local uniqueIdentifier = characterName .. ":" .. name
        local found = false
        for i, v in ipairs(core.db.profile.sell_next_vendor[id]) do
            if v == uniqueIdentifier then
                table.remove(core.db.profile.sell_next_vendor[id], i)
                found = true
                break
            end
        end

        if not found then
            table.insert(core.db.profile.sell_next_vendor[id], uniqueIdentifier)
            core:Print(link .. " |cFFFFFF00added to sell list.|r")
        else
            core:Print(link .. " |cFFFF0000removed from sell list.|r")
        end
        if #core.db.profile.sell_next_vendor[id] == 0 then
            core.db.profile.sell_next_vendor[id] = nil -- Clean up empty tables
        end
        self:ScheduleBagUpdate() -- Update icons after changing list
    end
end

hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", function(self, button)
    if button == "RightButton" and self:GetParent() and self:GetParent():GetID() and self:GetID() then -- Add safety checks
        local bag, slot = self:GetParent():GetID(), self:GetID()
        core:ALT_CLICK_ITEM(bag, slot)
        -- BAG_UPDATE is now scheduled by ALT_CLICK_ITEM
    end
end)

function markItemForSale(itemButton, itemid, link, characterName, currentBag, currentSlot, isAdiBagsButton)
    if not itemButton or not link then return end

    local itemNameFromLink = GetItemInfo(link)
    local markForSale = false

    if core.db.profile.always_consider[itemid] and not core.db.profile.never_consider[itemid] then
        markForSale = true
    end

    if core.db.profile.sell_next_vendor[itemid] then
        local uniqueIdentifier = characterName .. ":" .. (itemNameFromLink or "")
        if tContains(core.db.profile.sell_next_vendor[itemid], uniqueIdentifier) then
            markForSale = true
        end
    end

    if isAdiBagsButton then
        -- START: Direct texture manipulation for AdiBags (less ideal, but for visuals)
        if not itemButton.dtctSellIcon then
            -- Create the texture ONCE per button
            itemButton.dtctSellIcon = itemButton:CreateTexture(nil, "OVERLAY") -- Or "ARTWORK" if overlay doesn't work
            itemButton.dtctSellIcon:SetSize(16, 16) -- Adjust size as needed
            itemButton.dtctSellIcon:SetPoint("TOPRIGHT", itemButton, "TOPRIGHT", -2, -2) -- Adjust position
            -- print("DTCT: Created dtctSellIcon for AdiBags button", itemButton:GetName())
        end

        if markForSale then
            itemButton.dtctSellIcon:SetTexture("interface\\buttons\\ui-grouploot-coin-up.blp")
            itemButton.dtctSellIcon:Show()
        else
            if itemButton.dtctSellIcon then -- Check if it exists before trying to hide
                itemButton.dtctSellIcon:Hide()
            end
        end
        -- itemButton.dtct_beingSold = markForSale -- You can still set this flag if you want
        -- END: Direct texture manipulation for AdiBags
    else -- Standard WoW UI Button
        if not itemButton.textureFrame then
            local frame = CreateFrame("Frame", nil, itemButton)
            frame:SetAllPoints(itemButton)
            itemButton.textureFrame = frame
            local texture = frame:CreateTexture(nil, "OVERLAY")
            texture:SetPoint("TOPRIGHT", frame, "TOPRIGHT") -- Default UI might need different anchor/offset
            texture:SetSize(16, 16)
            frame.texture = texture
            -- frame:Hide() -- Texture frame itself doesn't need to be hidden, just its texture content
        end

        if markForSale then
            itemButton.textureFrame.texture:SetTexture("interface\\buttons\\ui-grouploot-coin-up.blp")
            itemButton.textureFrame:Show()
        else
            if itemButton.textureFrame then
                itemButton.textureFrame:Hide()
            end
        end
    end
end
core.markItemForSale = markItemForSale

function clearSellIcons() -- Only for standard bags now
    for bag = 0, NUM_BAG_SLOTS do -- Only backpack + normal bags
        local containerFrame = _G["ContainerFrame" .. (bag + 1)]
        if containerFrame then
            for slot = 1, GetContainerNumSlots(bag) do
                local itemButton = _G["ContainerFrame" .. (bag + 1) .. "Item" .. slot]
                if itemButton and itemButton.textureFrame then
                    itemButton.textureFrame:Hide()
                end
            end
        end
    end
    -- AdiBags icons should be cleared by its own update logic when dtct_beingSold is false
end
core.clearSellIcons = clearSellIcons

-- Utility tContains if not already available globally
if not tContains then
    function tContains(table, val)
        for _, value in ipairs(table) do
            if value == val then
                return true
            end
        end
        return false
    end
end