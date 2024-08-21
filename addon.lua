local core = LibStub("AceAddon-3.0"):NewAddon("DropTheCheapestThing", "AceEvent-3.0", "AceBucket-3.0")
local AceTimer = LibStub("AceTimer-3.0")

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
    }, DEFAULT)
    self.db = db
    self:RegisterBucketEvent("BAG_UPDATE", 2)
    self:RegisterEvent("MERCHANT_SHOW")
    self:RegisterEvent("MERCHANT_CLOSED")

    if MerchantFrame:IsVisible() then
        self:MERCHANT_SHOW()
    end
end

function core:Print(...)
    ChatFrame1:AddMessage(string.join(" ", "|cFF33FF99DropTCT|r:", ...))
end

function core:MERCHANT_SHOW()
    Debug("MERCHANT_SHOW")
    self.at_merchant = true
    self.events:Fire("Merchant_Open")
end

function core:MERCHANT_CLOSED()
    Debug("MERCHANT_CLOSED")
    self.at_merchant = nil
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

function core:BAG_UPDATE()
    table.wipe(drop_slots)
    table.wipe(sell_slots)
    table.wipe(slot_contents)
    table.wipe(slot_counts)
    table.wipe(slot_stacksizes)
    table.wipe(slot_values)
    table.wipe(slot_weightedvalues)
    table.wipe(slot_valuesources)

    local total, total_sell, total_drop = 0, 0, 0

    clearSellIcons()

    for bag = 0, NUM_BAG_SLOTS do
        local bagsSlotCount = GetContainerNumSlots(bag)
        for slot = 1, bagsSlotCount do
            local itemid, link, count, stacksize, quality, value, source = GetConsideredItemInfo(bag, slot)

            -- First Remove all the coin textures.
            local itemButton = _G["ContainerFrame" .. bag + 1 .. "Item" .. bagsSlotCount - slot + 1]
            if itemButton and itemButton.textureFrame then
                itemButton.textureFrame:Hide()
            end

            if itemid then
                local bagslot = encode_bagslot(bag, slot)
                slot_contents[bagslot] = link
                slot_counts[bagslot] = count
                slot_stacksizes[bagslot] = stacksize
                slot_values[bagslot] = value * count
                slot_weightedvalues[bagslot] = db.profile.full_stacks and (value * stacksize) or (value * count)
                slot_valuesources[bagslot] = source
                if db.profile.always_consider[itemid] or quality <= db.profile.threshold then
                    total_drop = total_drop + slot_values[bagslot]
                    table.insert(drop_slots, bagslot)
                end
                if db.profile.always_consider[itemid] or quality <= db.profile.sell_threshold then
                    total_sell = total_sell + slot_values[bagslot]
                    table.insert(sell_slots, bagslot)
                end
                local characterName = UnitName("player")
                if core.db.profile.sell_next_vendor[itemid] then
                    for _, uniqueIdentifier in ipairs(core.db.profile.sell_next_vendor[itemid]) do
                        local storedCharacterName, storedItemName = string.match(uniqueIdentifier, "(.-):(.*)")
                        local name = GetItemInfo(link)
                        if storedCharacterName == characterName and storedItemName == name then
                            -- This item matches both the character and the specific item name
                            slot_contents[bagslot] = link
                            table.insert(sell_slots, bagslot)
                            total_sell = total_sell + slot_values[bagslot]
                            break -- Found a match, no need to check further
                        end
                    end
                end
                total = total + slot_values[bagslot]

                -- Introduce a delay before calling markItemForSale
                AceTimer:ScheduleTimer(function()
                    -- Pass the itemButton directly for standard bags
                    if itemButton then
                        markItemForSale(itemButton, itemid, link, characterName)
                    end

                    -- Handle AdiBags separately
                    if AdiBagsItemButton1 then
                        -- Assuming AdiBagsItemButton1 exists if AdiBags is loaded
                        for i = 1, 360 do
                            local frameName = "AdiBagsItemButton" .. i
                            local adiBagsButton = _G[frameName]
                            if adiBagsButton and adiBagsButton:IsShown() and adiBagsButton.bag == bag and adiBagsButton.slot == slot then
                                markItemForSale(adiBagsButton, itemid, link, characterName)
                                break
                            end
                        end
                    end
                end, 0.2) -- Delay of 0.1 seconds
            end
        end
    end

    table.sort(drop_slots, slot_sorter)
    table.sort(sell_slots, slot_sorter)
    self.events:Fire("Junk_Update", #drop_slots, #sell_slots, total_drop, total_sell, total)
end

-- The rest is utility functions used above:

function GetConsideredItemInfo(bag, slot)
    -- this tells us whether or not the item in this slot could possibly be a candidate for dropping/selling
    local link = GetContainerItemLink(bag, slot)
    if not link then
        return
    end -- empty slot!

    local _, count, _, quality = GetContainerItemInfo(bag, slot)
    local stacksize = select(8, GetItemInfo(link))
    -- quality_ is -1 if the item requires "special handling"; stackable, quest, whatever.
    -- I'm not actually sure how best to handle this; it's not really a problem with greys, but
    -- whites and above could have quest-item issues. Though I suppose quest items don't have
    -- vendor values, so...
    if quality == -1 then
        quality = select(3, GetItemInfo(link))
    end
    if not quality then
        return
    end -- if we don't know the quality now, something weird is going on

    local itemid = link_to_id(link)
    if db.profile.never_consider[itemid] then
        return
    end
    if not db.profile.always_consider[itemid] and quality > db.profile.threshold and quality > db.profile.sell_threshold and not core.db.profile.sell_next_vendor[itemid] then
        return
    end
    local value, source = item_value(itemid, quality < db.profile.auction_threshold)
    if (not value) or value == 0 then
        return
    end
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
end -- "item" because we only care about items, duh
core.link_to_id = link_to_id

function pretty_bagslot_name(bagslot, show_name, show_count, force_count)
    if not bagslot or not slot_contents[bagslot] then
        return "???"
    end
    if show_name == nil then
        show_name = true
    end
    if show_count == nil then
        show_count = true
    end
    local link = slot_contents[bagslot]
    local name = link:gsub("[%[%]]", "")
    local max = select(8, GetItemInfo(link))
    return (show_name and link:gsub("[%[%]]", "") or '') ..
            ((show_name and show_count) and ' ' or '') ..
            ((show_count and (force_count or max > 1)) and (slot_counts[bagslot] .. '/' .. max) or '')
end
core.pretty_bagslot_name = pretty_bagslot_name

function copper_to_pretty_money(c)
    if c >= 10000 then
        return ("|cffffffff%d|r|cffffd700g|r|cffffffff%d|r|cffc7c7cfs|r|cffffffff%d|r|cffeda55fc|r"):format(c / 10000, (c / 100) % 100, c % 100)
    elseif c >= 100 then
        return ("|cffffffff%d|r|cffc7c7cfs|r|cffffffff%d|r|cffeda55fc|r"):format((c / 100) % 100, c % 100)
    else
        return ("|cffffffff%d|r|cffeda55fc|r"):format(c % 100)
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

function encode_bagslot(bag, slot)
    return (bag * 100) + slot
end
function decode_bagslot(int)
    return math.floor(int / 100), int % 100
end
core.encode_bagslot = encode_bagslot
core.decode_bagslot = decode_bagslot

function drop_bagslot(bagslot, sell_only)
    Debug("drop_bagslot", bagslot, sell_only and 'sell_only' or '')
    Debug("At merchant?", core.at_merchant and 'yes' or 'no')
    local bag, slot = decode_bagslot(bagslot)
    if CursorHasItem() then
        return DEFAULT_CHAT_FRAME:AddMessage(("DropTheCheapestThing Error: Can't delete/sell items while an item is on the cursor. Aborting."):format(slot_contents[bagslot], GetContainerItemLink(bag, slot)), 1, 0, 0)
    end
    if sell_only and not core.at_merchant then
        return DEFAULT_CHAT_FRAME:AddMessage(("DropTheCheapestThing Error: Can't sell items while not at a merchant. Aborting."):format(slot_contents[bagslot], GetContainerItemLink(bag, slot)), 1, 0, 0)
    end
    if not (bagslot and slot_contents[bagslot]) then
        return DEFAULT_CHAT_FRAME:AddMessage("DropTheCheapestThing Error: Nothing found in requested slot. Aborting.", 1, 0, 0)
    end
    if slot_contents[bagslot] ~= GetContainerItemLink(bag, slot) then
        return DEFAULT_CHAT_FRAME:AddMessage(("DropTheCheapestThing Error: Expected %s in bag slot, found %s instead. Aborting."):format(slot_contents[bagslot], GetContainerItemLink(bag, slot) or "nothing"), 1, 0, 0)
    end

    if core.at_merchant then
        DEFAULT_CHAT_FRAME:AddMessage("Selling " .. pretty_bagslot_name(bagslot) .. " for " .. copper_to_pretty_money(slot_values[bagslot]))
        UseContainerItem(bag, slot)
        local charName = UnitName("player") -- Get the name of the current character
        for id, entries in pairs(core.db.profile.sell_next_vendor) do
            for i = #entries, 1, -1 do
                if entries[i]:match("^(.-):") == charName then
                    table.remove(entries, i)
                end
            end
            if #entries == 0 then
                core.db.profile.sell_next_vendor[id] = nil
            end
        end
        --clearSellIcons()
        --core:BAG_UPDATE()

    else
        DEFAULT_CHAT_FRAME:AddMessage("Dropping " .. pretty_bagslot_name(bagslot) .. " worth " .. copper_to_pretty_money(slot_values[bagslot]))
        PickupContainerItem(bag, slot)
        DeleteCursorItem()
--        clearSellIcons()
--        core:BAG_UPDATE()

    end
end
core.drop_bagslot = drop_bagslot

-- Automatically delete unwanted items, or open items (like clams).
-- To add/remove items, edit one of the following lists and (re)run the page.
-- Initial Code from addon named Hack.

-- Function to delete items from the auto_delete list
function core:deleteAutoDeleteItems()
    local autoDeleteList = core.db.profile.auto_delete or {} -- Retrieve the auto_delete list from your addon's configuration
    if not core.db.profile.auto_delete_toggle or (not core.db.profile.combat_delete_toggle and UnitAffectingCombat('Player')) then
        return
    end

    -- Table to store deleted items
    if not core.deletedItems then
        core.deletedItems = {}
    end

    -- Iterate through the bags and slots
    for bag = 0, 16 do
        for slot = 1, GetContainerNumSlots(bag) do
            local item = GetContainerItemLink(bag, slot)
            if item then
                local itemId = tonumber(item:match("item:(%d+)")) -- Extract item ID from the item link
                if autoDeleteList[itemId] then
                    -- Check if the item ID is in the auto_delete list
                    local itemKey = bag .. "-" .. slot

                    if not core.deletedItems[itemKey] and core.db.profile.print_delete_toggle then
                        print('Deleting ' .. item .. ' (' .. bag + 1 .. ',' .. slot .. ')')
                        core.deletedItems[itemKey] = true

                        AceTimer:ScheduleTimer(function()
                            core.deletedItems = {}
                        end, 1)
                    end

                    PickupContainerItem(bag, slot)
                    if CursorHasItem() then
                        DeleteCursorItem()
                    end
                end
            end
        end
    end
end


-- Schedule the function to run 1 second after an item is picked up
local function onItemPush()
    AceTimer:ScheduleTimer(function()
        core:deleteAutoDeleteItems()
    end, 1)
end

-- Register event to trigger when an item is pushed to the bag
local customFrame = CreateFrame("Frame")
customFrame:RegisterEvent("ITEM_PUSH")
customFrame:SetScript("OnEvent", onItemPush)

-- run delete items function initially with delay for DB to have time to init.
AceTimer:ScheduleTimer(function()
    core:deleteAutoDeleteItems()
end, 1)

--------------------------------------------------------------------------------
---- XD
--------------------------------------------------------------------------------


-- Handle Alt + click event
function core:ALT_CLICK_ITEM(bag, slot)
    local link = GetContainerItemLink(bag, slot)
    local id = link:match("item:(%d+)")
    id = tonumber(id)
    local name = GetItemInfo(link) -- Get the full name of the item, including random enchantments
    if id and IsAltKeyDown() then
        local characterName = UnitName("player")
        if not core.db.profile.sell_next_vendor[id] then
            core.db.profile.sell_next_vendor[id] = {}
        end
        local uniqueIdentifier = characterName .. ":" .. name
        -- Check if this unique identifier is already in the list
        if not tContains(core.db.profile.sell_next_vendor[id], uniqueIdentifier) then
            table.insert(core.db.profile.sell_next_vendor[id], uniqueIdentifier)
            core:Print(link .. " |cFFFFFF00added to sell list.|r")
        else
            -- If it's already in the list, remove it
            for i, v in ipairs(core.db.profile.sell_next_vendor[id]) do
                if v == uniqueIdentifier then
                    table.remove(core.db.profile.sell_next_vendor[id], i)
                    break
                end
            end
            core:Print(link .. " |cFFFF0000removed from sell list.|r")
        end
    end
end

hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", function(self, button)
    if button == "RightButton" then
        local bag, slot = self:GetParent():GetID(), self:GetID();
        core:ALT_CLICK_ITEM(bag, slot)
        core:BAG_UPDATE()
    end
end);

-- Function for marking directly in the loop
function markItemForSale(itemButton, itemid, link, characterName)
    -- If an item button is found, proceed with creating/showing the texture frame
    if itemButton then
        local frame = itemButton.textureFrame
        if not frame then
            frame = CreateFrame("Frame", nil, itemButton)
            frame:SetAllPoints(itemButton)
            itemButton.textureFrame = frame

            local texture = frame:CreateTexture(nil, "OVERLAY")
            texture:SetPoint("TOPRIGHT", frame, "TOPRIGHT") -- Adjust anchoring as needed
            texture:SetSize(24, 24) -- Adjust size as needed
            frame.texture = texture
            frame:Hide()
        end

        local name = GetItemInfo(link)
        if link then
            local uniqueIdentifier = characterName .. ":" .. (name or "")
            -- Check if the item is on the sell list OR in the always_consider list
            if core.db.profile.sell_next_vendor[itemid] and tContains(core.db.profile.sell_next_vendor[itemid], uniqueIdentifier) then
                frame:Show()
                frame.texture:SetTexture("interface\\buttons\\ui-grouploot-coin-up.blp")
            elseif core.db.profile.always_consider[itemid] and not core.db.profile.never_consider[itemid] then
                frame:Show()
                frame.texture:SetTexture("interface\\buttons\\ui-grouploot-coin-up.blp") -- You can use a different texture here
            else
                frame:Hide()
            end
        end
    end
end
core.markItemForSale = markItemForSale


function clearSellIcons()
    for bag = 0, NUM_BAG_SLOTS do
        local bagsSlotCount = GetContainerNumSlots(bag)
        for slot = 1, bagsSlotCount do
            local bagslot = encode_bagslot(bag, slot)
            local itemButton = _G["ContainerFrame" .. bag + 1 .. "Item" .. bagsSlotCount - slot + 1]
            local isMarkedForSale = tContains(sell_slots, bagslot) or tContains(drop_slots, bagslot)

            -- Only hide the icon if the slot is no longer marked for sale
            if itemButton and itemButton.textureFrame and not isMarkedForSale then
                itemButton.textureFrame:Hide()
            end

            if AdiBagsItemButton1 then
                for i = 1, 360 do
                    local frameName = "AdiBagsItemButton" .. i
                    local adiBagsButton = _G[frameName]
                    if adiBagsButton and adiBagsButton.textureFrame then
                        local adiBagSlot = encode_bagslot(adiBagsButton.bag, adiBagsButton.slot)
                        local isAdiMarkedForSale = tContains(sell_slots, adiBagSlot) or tContains(drop_slots, adiBagSlot)

                        if not isAdiMarkedForSale then
                            adiBagsButton.textureFrame:Hide()
                        end
                    end
                end
            end
        end
    end
end

core.clearSellIcons = clearSellIcons



