local core = LibStub("AceAddon-3.0"):GetAddon("DropTheCheapestThing")
local module = core:NewModule("LDB")
local icon = LibStub("LibDBIcon-1.0", true)

local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Bag_22.blp"

local dataobject = LibStub("LibDataBroker-1.1"):NewDataObject("DropTheCheapestThing", {
	type = "data source",
	icon = DEFAULT_ICON,
	label = "Drop",
	text = "",
})

function dataobject:OnTooltipShow()
	GameTooltip:AddLine("Junk To "..(MerchantFrame:IsVisible() and "Sell" or "Drop"))
	core.add_junk_to_tooltip(GameTooltip, MerchantFrame:IsVisible() and core.sell_slots or core.drop_slots)
	GameTooltip:AddLine("|cffeda55fShift-Click|r to ".. (MerchantFrame:IsVisible() and "sell" or "delete") .." the cheapest item.", 0.2, 1, 0.2, 1)
	GameTooltip:AddLine("|cffeda55fControl-Right-Click|r to add the current cheapest item to the ignore list.", 0.2, 1, 0.2, 1)
end

function dataobject:OnClick(button)
	if CursorHasItem() and button == "LeftButton" then
		local _, itemID = GetCursorInfo()
		ClearCursor()

		if itemID then
			core.db.profile.always_consider[itemID] = true
			core:_BAG_UPDATE_INTERNAL()

			-- Update the 'always consider' list in the GUI
			local config = core:GetModule("Config", true)
			if config then
				config:AddItemToAlwaysConsider(itemID)
			end
		end
		-- Refresh the tooltip if it's showing
		if GameTooltip:GetOwner() == icon.objects["DropTheCheapestThing"] then
			GameTooltip:ClearLines()
			dataobject:OnTooltipShow()
			GameTooltip:Show()
		end
		return
	end
	if button == "RightButton" then
		if IsControlKeyDown() then
			-- add topmost item to the ignore list
			local slots = MerchantFrame:IsVisible() and core.sell_slots or core.drop_slots
			if #slots == 0 then return end
			local id = core.link_to_id(core.slot_contents[table.remove(slots, 1)])
			if not id then return end -- this really shouldn't happen... but just in case
			core.db.profile.never_consider[id] = true
			core:_BAG_UPDATE_INTERNAL()

			-- Update the 'never consider' list in the GUI
			local config = core:GetModule("Config", true)
			if config then
				config:AddItemToNeverConsider(id)
			end
		else

			-- toggle the config
			local config = core:GetModule("Config", true)
			if config then
				config:ToggleConfig()
			end
		end
	else
		local slots = MerchantFrame:IsVisible() and core.sell_slots or core.drop_slots
		if #slots == 0 then return end
		if not IsShiftKeyDown() then return end
		core.drop_bagslot(table.remove(slots, 1))
	end
	-- Refresh the tooltip if it's showing
	if GameTooltip:GetOwner() == icon.objects["DropTheCheapestThing"] then
		GameTooltip:ClearLines()
		dataobject:OnTooltipShow()
		GameTooltip:Show()
	end
end

local WHITE = "|cffffffff"
local END = "|r"

core.RegisterCallback("LDB", "Junk_Update", function(callback, drop_count, sell_count, drop_total, sell_total, total)
	if drop_count == 0 then
		dataobject.text = ''
		-- dataobject.icon = DEFAULT_ICON
		return
	end
	local db = module.db.profile.text
	dataobject.text = 
		((db.item or db.itemcount) and core.pretty_bagslot_name(core.drop_slots[1], db.item, db.itemcount, db.itemcount) or '') ..
		WHITE .. ((db.item and db.itemprice) and ' @ ' or '') .. END ..
		WHITE .. (db.itemprice and core.copper_to_pretty_money(core.slot_values[core.drop_slots[1]]) or '') .. END ..
		WHITE .. (((db.item or db.itemprice) and (db.junkcount or db.totalprice)) and ' : ' or '') .. END ..
		WHITE .. (db.junkcount and drop_count or '') .. END ..
		WHITE .. ((db.junkcount and db.totalprice) and ' @ ' or '') .. END ..
		WHITE .. (db.totalprice and core.copper_to_pretty_money(drop_total) or '') .. END
	-- dataobject.icon = select(10, GetItemInfo(core.slot_contents[core.drop_slots[1]]))
end)

function module:OnInitialize()
	self.db = core.db:RegisterNamespace("LDB", {
		profile = {
			minimap = {},
			text = {
				item = false,
				itemcount = false,
				junkcount = true,
				itemprice = false,
				totalprice = true,
			},
		},
	})
	if core.db.profile.ldbtext then
		self.db.profile.text = core.db.profile.ldbtext
		core.db.profile.ldbtext = nil
	end
	if icon then
		icon:Register("DropTheCheapestThing", dataobject, self.db.profile.minimap)
	end

	local config = core:GetModule("Config", true)
	if config then
		config.options.args.general.plugins.broker = {
			minimap = {
				type = "toggle",
				name = "Show minimap icon",
				desc = "Toggle showing or hiding the minimap icon.",
				get = function() return not self.db.profile.minimap.hide end,
				set = function(info, v)
					local hide = not v
					self.db.profile.minimap.hide = hide
					if hide then
						icon:Hide("DropTheCheapestThing")
					else
						icon:Show("DropTheCheapestThing")
					end
				end,
				width = "full",
				hidden = function() return not icon or not dataobject or not icon:IsRegistered("DropTheCheapestThing") end,
			},
			text = {
				type = "multiselect",
				name = "Broker Text",
				desc = "What to display as text for the broker icon.",
				get = function(info, key)
					return self.db.profile.text[key]
				end,
				set = function(info, key, v)
					self.db.profile.text[key] = v
					core:_BAG_UPDATE_INTERNAL()
				end,
				values = {
					item = "Cheapest item",
					itemcount = "Stack size of cheapest item",
					itemprice = "Value of cheapest item",
					junkcount = "Number of junk items",
					totalprice = "Total value of junk",
				},
			},
		}
	end
end

