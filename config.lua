local core = LibStub("AceAddon-3.0"):GetAddon("DropTheCheapestThing")
local module = core:NewModule("Config")
-- Import AceTimer
local AceTimer = LibStub("AceTimer-3.0")
local AceGUI = LibStub("AceGUI-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local db

local isCachePerformed = false
-- Add this near the top of the file with other module variables
module.searchTerm = nil
module.lastSearchTerm = nil

-- stash the last‐removed for Undo
module._lastRemoved = nil
-- keep track of the pending “clear status” timer
module._clearStatusTimer = nil


-- lazily create & parent the Undo button to your config frame
local function EnsureUndoButton()
	local ACD = LibStub("AceConfigDialog-3.0")
	local guiFrame = ACD.OpenFrames["DropTheCheapestThing"]
	if not (guiFrame and guiFrame.frame) then return end

	-- only build it once
	if not module.undoBtn then
		local parent = guiFrame.frame
		local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
		btn:SetSize(60,20)
		btn:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 20, -40)
		btn:SetText("Undo")
		btn:Hide()
		-- make sure it's on top of the other children
		btn:SetFrameLevel(parent:GetFrameLevel()+20)

		btn:SetScript("OnClick", function()
			local info = module._lastRemoved
			if not info then return end

			-- re-add
			core.db.profile[info.list] = core.db.profile[info.list] or {}
			core.db.profile[info.list][info.itemID] = true
			module:Refresh()
			LibStub("AceConfigRegistry-3.0"):NotifyChange("DropTheCheapestThing")

			local frame = LibStub("AceConfigDialog-3.0").OpenFrames["DropTheCheapestThing"]
			if frame then
				frame:SetStatusText(("Re-added %s"):format(info.display))

				-- cancel the old clear‐timer silently
				if module._clearStatusTimer then
					AceTimer:CancelTimer(module._clearStatusTimer, true)
				end

				-- schedule a fresh clear 5 seconds after the undo
				module._clearStatusTimer = AceTimer:ScheduleTimer(function()
					if frame then frame:SetStatusText("") end
				end, 5)
			end

			module._lastRemoved = nil
			module.undoBtn:Hide()
		end)



		module.undoBtn = btn
	else
		-- if the frame was re-created, re-parent & re-anchor
		module.undoBtn:SetParent(guiFrame.frame)
		module.undoBtn:ClearAllPoints()
		module.undoBtn:SetPoint("BOTTOMLEFT", guiFrame.frame, "BOTTOMLEFT", 24, 47)
	end
end


function module:removable_item(itemID, list_name)
	local list_setting
	if list_name == "Never Consider" then
		list_setting = "never_consider"
	elseif list_name == "Always Consider" then
		list_setting = "always_consider"
	else
		-- For "Auto Delete Items" list
		list_setting = "auto_delete"
	end

	local item_name, _, item_rarity, _, _, _, _, _, _, item_icon = GetItemInfo(itemID)

	-- Handle case where item info isn't available yet
	if not item_name then
		return {
			type = "execute",
			name = "item:"..tostring(itemID),
			desc = "Item info not available - click to remove from "..list_name,
			width = "30%",
			arg = itemID,
			func = function()
				core.db.profile[list_setting][itemID] = nil
				core:BAG_UPDATE()

				-- Update the GUI
				local args = module.options.args[list_setting] and module.options.args[list_setting].args.remove.args
				if args then
					args[tostring(itemID)] = nil
				end

				LibStub("AceConfigRegistry-3.0"):NotifyChange("DropTheCheapestThing")
				module:Refresh()
			end,
		}
	end

	-- Get the color for the item's rarity
	local rarityColor = select(4, GetItemQualityColor(item_rarity))

	-- If item_name exists, wrap it in the color code. Otherwise, use a default representation.
	local coloredItemName = item_name and rarityColor..item_name.."|r" or 'itemid:'..tostring(itemID)

	--print("Function called with list_name: " .. list_name)  -- New debug statement
	--print("List setting: " .. list_setting)
	--print("ItemID: " .. itemID)


	return {
	type = "execute",
	name = coloredItemName,
	desc = "Click to remove from the "..list_name.." list",
	image = item_icon,
	width = "30%",
	arg = itemID,
	func = function()
		-- 1) remove from the saved list
		core.db.profile[list_setting] = core.db.profile[list_setting] or {}
		core.db.profile[list_setting][itemID] = nil

		-- 2) update bags/UI
		core:BAG_UPDATE()

		-- 3) strip it out of the options args table so it disappears immediately
		local args = module.options.args[list_setting]
				and module.options.args[list_setting].args.remove.args
		if args then
			args[tostring(itemID)] = nil
		end

		-- 4) rebuild and notify AceConfig
		LibStub("AceConfigRegistry-3.0"):NotifyChange("DropTheCheapestThing")
		module:Refresh()

		-- 5) show a “Removed X” status message in the config frame
		local _, itemLink = GetItemInfo(itemID)
		-- fall back to your coloured name if the link isn’t cached yet:
		local display = itemLink or coloredItemName

		-- 5) **store** for undo
		module._lastRemoved = {
			itemID  = itemID,
			list    = list_setting,
			display = display,
		}

		-- 6) ensure our Undo button exists & show it
		EnsureUndoButton()
		if module.undoBtn then
			module.undoBtn:Show()
			module.undoBtn:Raise()
		end

		local frame = AceConfigDialog.OpenFrames["DropTheCheapestThing"]
		if frame then
			frame:SetStatusText(("Removed %s"):format(display))

			if module._clearStatusTimer then
				AceTimer:CancelTimer(module._clearStatusTimer, true)
			end
			module._clearStatusTimer = AceTimer:ScheduleTimer(function()
				if frame then frame:SetStatusText("") end
				if module.undoBtn then module.undoBtn:Hide() end
			end, 5)
		end



	end,
	}
end

local categoryOrder = {
	["Trade Goods"] = 100,
	["Consumable"] = 200,
	["Miscellaneous"] = 300,
	["Armor"] = 400,
	["Weapon"] = 500,
	["Container"] = 600,
	["Gem"] = 700,
	["Key"] = 800,
	["Money"] = 900,
	["Reagent"] = 1000,
	["Recipe"] = 1100,
	["Projectile"] = 1200,
	["Quest"] = 1300,
	["Quiver"] = 1400,
	["Junk"] = 1400,
}

function module:CreateCategory(name, group)
	if not group.args[name] then
		local order = categoryOrder[name] or 50  -- Fallback to higher order if unknown category
		group.args[name] = {
			type = "group",
			name = name,
			inline = true,
			order = order,
			args = {}
		}
	end
	return group.args[name]
end

local function cacheItemInfo(itemID)
	isCachePerformed = false
	-- Return if the item is already cached
	if GetItemInfo(itemID) ~= nil then
		return
	end

	-- Query for the missing item info
	GameTooltip:SetHyperlink("item:"..itemID)
	--print("Query Item:" .. itemID)
	isCachePerformed = true
end


local function item_list_group(name, order, description, db_table)
	local group = {
		type = "group",
		name = name,
		order = order,
		args = {},
	}

	group.args.about = {
		type = "description",
		name = description,
		order = 0,
	}

	group.args.add = {
		type = "input",
		name = "Add",
		desc = "Add an item, either by pasting the item link, dragging the item into the field, or entering the itemid.",
		get = function(info) return '' end,
		set = function(info, v)
			local itemid = core.link_to_id(v) or tonumber(v)
			db_table[itemid] = true

			local itemName, itemLink, itemRarity, _, _, itemType = GetItemInfo(itemid)
			if itemName and itemType then
				local category = module:CreateCategory(itemType, group.args.remove)
				category.args[tostring(itemid)] = module:removable_item(itemid, name)
			end
			-- itemLink will be something like "|cff9d9d9d[Worn Shortsword]|r"
			local display = itemLink or ( select(4,GetItemQualityColor(itemRarity)) .. (itemName or "") .. "|r" )

			local frame = AceConfigDialog.OpenFrames["DropTheCheapestThing"]
			if frame then
				frame:SetStatusText(("Added %s"):format(display))
				-- clear it after 5s
				AceTimer:ScheduleTimer(function()
					if frame then frame:SetStatusText("") end
				end, 5)
			end

			core:BAG_UPDATE()
			AceTimer:ScheduleTimer(function() _G["AceGUI-3.0EditBox2"]:ClearFocus() end, 0.01)
		end,
		validate = function(info, v)
			if v:match("^%d+$") or v:match("item:%d+") then return true end
		end,
		dialogControl = "DropCheapAddBox",
		order = 5,
		width = "quarter",
	}

	group.args.spacer_after_add = {
		type = "description",
		name = "",
		order = 5.5,
		width = "full",
	}


	if name == "Always Consider" then
		group.args.search = {
			type = "input",
			name = "Search",
			desc = "Filter items shown below.",
			get = function(info) return module.searchTerm or "" end,
			set = function(info, v)
				module.searchTerm = v ~= "" and v:lower() or nil
				module.lastSearchTerm = module.searchTerm
				AceTimer:ScheduleTimer(function()
					module:RebuildFilteredRemoveGroup()
				end, 0.01)
			end,
			dialogControl = "DropCheapSearchBox",
			order = 6,
			width = "quarter",
		}

		group.args.clear_search = {
			type = "execute",
			name = "Clear",
			desc = "Reset the search filter.",
			func = function()
				module.searchTerm = nil
				module.lastSearchTerm = nil
				module.activeTab = "always"
				module:Refresh()
				local ACD = LibStub("AceConfigDialog-3.0")
				ACD:SelectGroup("DropTheCheapestThing", "always")
				ACD:Open("DropTheCheapestThing")
			end,
			order = 7,
			width = "half",
		}
	end

	group.args.remove = {
		type = "group",
		inline = true,
		name = "Remove",
		order = 10,
		args = {
			about = {
				type = "description",
				name = "Remove an item.",
				order = 0,
			},
		},
	}
	-- FIXME: is it needed?
	--db.profile.auto_delete = db.profile.auto_delete or {}

	-- Add checkbox toggles for "Auto Delete Items" page
	if name == "Auto Delete Items" then
		group.args.auto_delete_toggle = {
			type = "toggle",
			name = "Enable Auto Delete",
			desc = "Toggle to enable auto deletion for items on this list.",
			get = function(info) return db.profile.auto_delete_toggle end,
			set = function(info, v) db.profile.auto_delete_toggle = v end,
			order = 10,
			width = "full",
		}

		group.args.combat_delete_toggle = {
			type = "toggle",
			name = "Delete in Combat",
			desc = "Toggle to enable auto deletion of items during combat.",
			get = function(info) return db.profile.combat_delete_toggle end,
			set = function(info, v) db.profile.combat_delete_toggle = v end,
			order = 15,
			width = "full",
		}

		group.args.print_delete_toggle = {
			type = "toggle",
			name = "Print Deleted Items",
			desc = "Toggle to print deleted items to chat.",
			get = function(info) return db.profile.print_delete_toggle end,
			set = function(info, v) db.profile.print_delete_toggle = v end,
			order = 16,
			width = "full",
		}
	end

	for itemID in pairs(db_table) do
		cacheItemInfo(itemID)
		local itemName, _, _, _, _, itemType = GetItemInfo(itemID)

		if itemName and itemType then
			local showItem = true

			if showItem then
				local category = module:CreateCategory(itemType, group.args.remove)
				category.args[tostring(itemID)] = module:removable_item(itemID, name)
			end
		else
			-- Uncached items
			local category = module:CreateCategory("Uncached Items", group.args.remove)
			category.args[tostring(itemID)] = {
				type = "execute",
				name = "item:"..tostring(itemID),
				desc = "Item info not available - click to remove",
				width = "30%",
				arg = itemID,
				func = function()
					core.db.profile[list_setting][itemID] = nil
					core:BAG_UPDATE()
					LibStub("AceConfigRegistry-3.0"):NotifyChange("DropTheCheapestThing")
					module:Refresh()
				end,
			}
		end
	end

	return group
end

local function getProfileList()
	local profiles = db:GetProfiles()
	local profileList = {}
	for _, key in ipairs(profiles) do
		profileList[key] = key
	end
	return profileList
end

local function createProfile(newProfileName)
	if newProfileName and newProfileName ~= "" then
		db:SetProfile(newProfileName)
		module:Refresh()
	end
end

local function tryDeleteProfile(profileKey)
	-- Check if the profile to be deleted is the active profile
	if db:GetCurrentProfile() == profileKey then
		local profiles = db:GetProfiles()
		local foundAlternativeProfile = false

		-- Try to switch to the "Default" profile if it exists and is not the active profile
		for _, p in ipairs(profiles) do
			if p == "Default" and p ~= profileKey then
				db:SetProfile(p)
				print("Switched to profile:", p)
				foundAlternativeProfile = true
				break
			end
		end

		-- If the "Default" profile was not found, switch to another profile
		if not foundAlternativeProfile then
			for _, p in ipairs(profiles) do
				if p ~= profileKey then
					db:SetProfile(p)
					print("Switched to profile:", p)
					foundAlternativeProfile = true
					break
				end
			end
		end

		-- If no alternative profile was found, print an error message and return
		if not foundAlternativeProfile then
			print("Error: Cannot delete the active profile when there are no other profiles available.")
			return
		end
	end

	-- Delete the profile after switching (if needed)
	db:DeleteProfile(profileKey, true) -- The second argument "true" enables the built-in confirmation dialog
	module:Refresh()
end



function module:OnInitialize()
	db = core.db

	local options = {
		type = "group",
		name = "DropTheCheapestThing",
		get = function(info) return db.profile[info[#info]] end,
		set = function(info, v) db.profile[info[#info]] = v; core:BAG_UPDATE() end,
		args = {
			general = {
				type = "group",
				name = "General",
				order = 10,
				args = {
					threshold = {
						type = "range",
						name = "Quality Threshold (Drop)",
						desc = "Choose the maximum quality of item that will be considered for dropping. 0 is grey, 1 is white, 2 is green, etc.",
						min = 0, max = 7, step = 1,
						order = 10,
					},
					sell_threshold = {
						type = "range",
						name = "Quality Threshold (Sell)",
						desc = "Choose the maximum quality of item that will be considered for selling. 0 is grey, 1 is white, 2 is green, etc.",
						min = 0, max = 7, step = 1,
						order = 15,
					},
					auction = {
						type = "group",
						name = "Auction values",
						inline = true,
						order = 20,
						args = {
							auction = {
								type = "toggle",
								name = "Auction values",
								desc = "If a supported auction addon is installed, use the higher of the vendor and buyout prices as the item's value.",
								order = 10,
							},
							auction_threshold = {
								type = "range",
								name = "Auction threshold",
								desc = "Only consider auction values for items of at least this quality.",
								min = 0, max = 7, step = 1,
								order = 20,
							},
						},
					},
					full_stacks = {
						type = "toggle",
						name = "Use full stack value",
						order = 30,
					},
				},
				plugins = {},
			},
			always = item_list_group("Always Consider", 20, "Items listed here will *always* be considered junk and sold/dropped, regardless of the quality threshold that has been chosen. Be careful with this -- you'll never be prompted about it, and it will have no qualms about dropping things that could be auctioned for 5000g.", db.profile.always_consider),
			never = item_list_group("Never Consider", 30, "Items listed here will *never* be considered junk and sold/dropped, regardless of the quality threshold that has been chosen.", db.profile.never_consider),
			auto_delete = item_list_group("Auto Delete Items", 40, "Items listed here will be automatically deleted without further prompting.", db.profile.auto_delete),
			profiles = {
				type = "group",
				name = "Profiles",
				order = 1000,
				args = {
					select_profile = {
						type = "select",
						name = "Available Profiles",
						desc = "Select one of the available profiles",
						values = getProfileList,
						get = function() return db:GetCurrentProfile() end,
						set = function(_, profileKey) db:SetProfile(profileKey); module:Refresh() core:BAG_UPDATE() print("Switched to profile:", profileKey) end,
						order = 10,
					},
					blank1 = {
						type = "description",
						name = "",
						desc = "",
						width = "full",
						order = 20,
					},
					create_profile = {
						type = "input",
						name = "Create Profile",
						desc = "Enter a name for a new profile",
						set = function(_, newProfileName) createProfile(newProfileName) print("Switched to profile:", newProfileName) end, -- Set function to create a new profile
						order = 30,
					},
					blank2 = {
						type = "description",
						name = "",
						desc = "",
						width = "full",
						order = 40,
					},
					delete_profile = {
						type = "select",
						name = "Delete Profile",
						desc = "Select a profile to delete",
						values = getProfileList,
						set = function(_, profileKey) tryDeleteProfile(profileKey) end,
						confirm = true,
						confirmText = "Are you sure you want to delete this profile?",
						order = 50,
					},
				},
			},
		},
		plugins = {
			--profiles = { profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(db), },
		},
	}
	self.options = options

	AceGUI:RegisterWidgetType("DropCheapSearchBox",
			function()
			-- create a normal EditBox…
				local widget = AceGUI:Create("EditBox")
			widget:SetLabel("Search")

			-- but *immediately* hook its OnTextChanged
				widget.editbox:HookScript("OnTextChanged", function()
					local txt = widget.editbox:GetText():lower()
					module.searchTerm = (txt ~= "") and txt or nil
					module.searchBox  = widget
                	module:RebuildFilteredRemoveGroup("always")
				end)

				return widget
			end,
			1)

	-- a bespoke EditBox just for your "Add" field
	AceGUI:RegisterWidgetType("DropCheapAddBox",
			function()
				local widget = AceGUI:Create("EditBox")
				widget:SetLabel("Add")

				-- preserve the original drag handler...
				local orig = widget.editbox:GetScript("OnReceiveDrag")
				-- then hook *after* it runs, only on *this* widget:
				widget.editbox:HookScript("OnReceiveDrag", function(self, ...)
					-- call the original so item-links still get dropped in correctly
					orig(self, ...)
					-- then clear focus a moment later
					AceTimer:ScheduleTimer(function()
						widget:ClearFocus()
					end, 0.01)
				end)

				return widget
			end,
			1
	)



	LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable("DropTheCheapestThing", options)
	LibStub("AceConfigDialog-3.0"):AddToBlizOptions("DropTheCheapestThing", "DropTheCheapestThing")
end

local function SetDialogPosition(dialog)
	--local frame = dialog.frame
	--frame:ClearAllPoints()
	--
	--local adiBagsContainer = _G["AdiBagsContainer1"]
	--if IsAddOnLoaded("AdiBags") and adiBagsContainer and adiBagsContainer:IsShown() then
	--	frame:SetPoint("TOP", adiBagsContainer, "BOTTOM", 0, -10) -- Attach the top of our frame to the bottom of AdiBagsContainer1
	--else
	--	frame:SetPoint("CENTER", 0, -200) -- Set the position of the frame 200 px below the center
	--end
end

function module:ShowConfig()
	module.activeTab = "always"
	local ACD = LibStub("AceConfigDialog-3.0")
	ACD:SelectGroup("DropTheCheapestThing", "always")
	ACD:Open("DropTheCheapestThing")
	EnsureUndoButton()

	module:Refresh()
end


function module:HideConfig()
	local dialog = AceConfigDialog.OpenFrames["DropTheCheapestThing"]
	if dialog then
		dialog:Hide()
	end
end

function module:IsConfigShown()
	local dialog = AceConfigDialog.OpenFrames["DropTheCheapestThing"]
	if dialog then
		return dialog:IsShown()
	else
		return false
	end
end

function module:ToggleConfig()
	--local adiBagsContainer = _G["AdiBagsContainer1"]

	if self:IsConfigShown() then
		self:HideConfig()

		---- If AdiBags is loaded and the bag is shown, hide it when closing the config
		--if IsAddOnLoaded("AdiBags") and adiBagsContainer and adiBagsContainer:IsShown() then
		--	adiBagsContainer:Hide()
		--end
	else
		self:ShowConfig()

		---- If AdiBags is loaded and the bag is not shown, show it when opening the config
		--if IsAddOnLoaded("AdiBags") and adiBagsContainer and not adiBagsContainer:IsShown() then
		--	adiBagsContainer:Show()
		--end
	end
end

function module:AddItemToAlwaysConsider(itemID)
	if not itemID then
		return
	end

	-- Add the new item to the 'always consider' list in the GUI
	local always_consider = self.options.args.always.args.remove
	local itemName, _, _, _, _, itemType = GetItemInfo(itemID)
	if itemName and itemType then
		local category = module:CreateCategory(itemType, always_consider)
		category.args[tostring(itemID)] = module:removable_item(itemID, "Always Consider")
	end

	core.db.profile.always_consider[itemID] = true
	core:BAG_UPDATE()

	LibStub("AceConfigRegistry-3.0"):NotifyChange("DropTheCheapestThing")
end

function module:AddItemToNeverConsider(itemID)
	if not itemID then
		return
	end

	-- Add the new item to the 'never consider' list in the GUI
	local never_consider = self.options.args.never.args.remove
	local itemName, _, _, _, _, itemType = GetItemInfo(itemID)
	if itemName and itemType then
		local category = module:CreateCategory(itemType, never_consider)
		category.args[tostring(itemID)] = module:removable_item(itemID, "Never Consider")
	end

	core.db.profile.never_consider[itemID] = true
	core:BAG_UPDATE()

	LibStub("AceConfigRegistry-3.0"):NotifyChange("DropTheCheapestThing")
end

function module:AutoDeleteItem(itemID)
	if not itemID then
		return
	end

	-- Add the new item to the 'auto delete' list in the GUI
	local auto_delete = self.options.args.auto_delete.args.remove
	local itemName, _, _, _, _, itemType = GetItemInfo(itemID)
	if itemName and itemType then
		local category = module:CreateCategory(itemType, auto_delete)
		category.args[tostring(itemID)] = module:removable_item(itemID, "Auto Delete Items")
	end

	core.db.profile.auto_delete[itemID] = true
	core:BAG_UPDATE()

	LibStub("AceConfigRegistry-3.0"):NotifyChange("DropTheCheapestThing")
end


function module:Refresh()
	-- Rebuild Always Consider group
	local always_group = item_list_group("Always Consider", 20, "Items listed here will *always* be considered junk and sold/dropped, regardless of the quality threshold that has been chosen. Be careful with this -- you'll never be prompted about it, and it will have no qualms about dropping things that could be auctioned for 5000g.", db.profile.always_consider)
	module.options.args.always = always_group

	-- Rebuild Never Consider group
	local never_group = item_list_group("Never Consider", 30, "Items listed here will *never* be considered junk and sold/dropped, regardless of the quality threshold that has been chosen.", db.profile.never_consider)
	module.options.args.never = never_group

	local auto_delete_group = item_list_group("Auto Delete Items", 40, "Items listed here will be automatically deleted without further prompting.", db.profile.auto_delete)
	module.options.args.auto_delete = auto_delete_group

end



SLASH_DROPTHECHEAPESTTHING1 = "/dropcheap"
SLASH_DROPTHECHEAPESTTHING2 = "/dtct"
function SlashCmdList.DROPTHECHEAPESTTHING()
	module:ShowConfig()
end

function module:RebuildFilteredRemoveGroup()
	-- guard: if there’s no searchTerm *and* the search box isn’t focused, bail
	if (not module.searchTerm or module.searchTerm == "")
			and (not module.searchBox
			or not module.searchBox.editbox:HasFocus())
	then
		return
	end

	local dialog = LibStub("AceConfigDialog-3.0").OpenFrames["DropTheCheapestThing"]
	if not dialog then return end

	-- find the “Remove” InlineGroup under Always Consider
	local removeGroup
	for _, frame in ipairs(dialog.children or {}) do
		if frame.type=="TreeGroup" or frame.type=="TabGroup" then
			for _, sf in ipairs(frame.children or {}) do
				if sf.type=="ScrollFrame" then
					for _, ig in ipairs(sf.children or {}) do
						if ig.type=="InlineGroup"
								and ig.titletext:GetText()=="Remove"
						then
							removeGroup = ig
							break
						end
					end
				end
			end
		end
	end
	if not removeGroup then return end

	-- clear & rebuild, always using the AlwaysConsider table
	removeGroup:ReleaseChildren()
	local term = module.searchTerm
	for itemID in pairs(core.db.profile.always_consider) do
		local name = select(1, GetItemInfo(itemID))
		if name then
			if not term
					or name:lower():find(term)
					or tostring(itemID):find(term)
			then
				local entry  = module:removable_item(itemID, "Always Consider")
				local widget = LibStub("AceGUI-3.0"):Create("Icon")
				widget:SetImage(entry.image or "Interface\\Icons\\INV_Misc_QuestionMark")
				widget:SetLabel(entry.name)
				widget:SetCallback("OnClick", function() entry.func() end)
				removeGroup:AddChild(widget)
			end
		end
	end
	removeGroup:DoLayout()
end

