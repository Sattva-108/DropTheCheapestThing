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
	-- Ensure that the necessary keys exist in the profile table
	core.db.profile[list_setting] = core.db.profile[list_setting] or {}
	core.db.profile[list_setting][itemID] = nil

	core:BAG_UPDATE()

	-- Check if the args table and the corresponding keys exist
	local args = module.options.args[list_setting] and module.options.args[list_setting].args.remove.args
	if args then
	args[tostring(itemID)] = nil
	end

	LibStub("AceConfigRegistry-3.0"):NotifyChange("DropTheCheapestThing")

	-- Refresh the GUI
	module:Refresh()
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

	-- Add search field only for "Always Consider" tab
	if name == "Always Consider" then
		group.args.search = {
			type = "input",
			name = "Search",
			desc = "Search for items in this list",
			get = function(info) return module.searchTerm or "" end,
			set = function(info, v)
				module.searchTerm = v ~= "" and v:lower() or nil
				module.lastSearchTerm = module.searchTerm

				AceTimer:ScheduleTimer(function()
					module:RebuildFilteredRemoveGroup()
				end, 0.01)
			end,
			dialogControl = "DropCheapSearchBox",
			order = 5,
		}

		group.args.clear_search = {
			type = "execute",
			name = "Clear Search",
			desc = "Clear the current search",
			func = function()
				module.searchTerm = nil
				module.lastSearchTerm = nil
				module.activeTab = "always"

				module:Refresh()
				local ACD = LibStub("AceConfigDialog-3.0")
				ACD:SelectGroup("DropTheCheapestThing", "always")
				ACD:Open("DropTheCheapestThing")

				AceTimer:ScheduleTimer(function()
					module:HookSearchEditBox()
				end, 0.3)
			end,
			order = 6,
		}
	end

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

			-- Get and create a proper category for a new item, then add it
			local itemName, _, _, _, _, itemType = GetItemInfo(itemid)
			if itemName and itemType then
				local category = module:CreateCategory(itemType, group.args.remove)
				category.args[tostring(itemid)] = module:removable_item(itemid, name)
			end

			core:BAG_UPDATE()
			-- Schedule a timer to call ClearFocus() after a delay
			AceTimer:ScheduleTimer(function() _G["AceGUI-3.0EditBox1"]:ClearFocus() end, 0.01)
		end,
		validate = function(info, v)
			if v:match("^%d+$") or v:match("item:%d+") then
				return true
			end
		end,
		order = 10,
	}
	group.args.remove = {
		type = "group",
		inline = true,
		name = "Remove",
		order = 20,
		func = function(info)
			db_table[info.arg] = nil
			group.args.remove.args[info[#info]] = nil
			core:BAG_UPDATE()
		end,
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
				-- believe it or not 0.00 delay does fix the issue with ctrl+backspace and ctrl+a+backspace clearing
				LibStub("AceTimer-3.0"):ScheduleTimer(function()
					module:RebuildFilteredRemoveGroup("always")
				end, 0.00)
			end)
			return widget
		end,
	1)


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
	AceTimer:ScheduleTimer(function()
		module:HookSearchEditBox()
	end, 0.3)

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

function module:RebuildFilteredRemoveGroup(selectedTab)
	print("called")
	if (not module.searchTerm or module.searchTerm == "") and (not module.searchBox or not module.searchBox.editbox:HasFocus()) then
		return
	end

	local dialog = LibStub("AceConfigDialog-3.0").OpenFrames["DropTheCheapestThing"]
	if not dialog then return end

	-- Auto-detect tab
	if not selectedTab then
		for _, child in ipairs(dialog.children or {}) do
			if child.type == "TreeGroup" or child.type == "TabGroup" then
				selectedTab = child.status and child.status.selected
			end
		end
	end

	-- Only allow rebuilding for "always" tab
	if selectedTab ~= "always" then
		return
	end


	module.activeTab = selectedTab or "always"

	local db_table, label
	if selectedTab == "never" then
		db_table = core.db.profile.never_consider
		label = "Never Consider"
	elseif selectedTab == "auto_delete" then
		db_table = core.db.profile.auto_delete
		label = "Auto Delete Items"
	else
		db_table = core.db.profile.always_consider
		label = "Always Consider"
	end

	-- Find the Remove group widget
	local removeGroupWidget
	for _, child in ipairs(dialog.children or {}) do
		if child.type == "TreeGroup" or child.type == "TabGroup" then
			for _, subChild in ipairs(child.children or {}) do
				if subChild.type == "ScrollFrame" then
					for _, grandchild in ipairs(subChild.children or {}) do
						if grandchild.type == "InlineGroup" and grandchild.titletext:GetText() == "Remove" then
							removeGroupWidget = grandchild
							break
						end
					end
				end
			end
		end
	end

	if not removeGroupWidget then
		return
	end

	removeGroupWidget:ReleaseChildren()

	for itemID in pairs(db_table) do
		local itemName, _, _, _, _, itemType = GetItemInfo(itemID)
		if itemName and itemType then
			local showItem = true
			if module.activeTab == "always" and module.searchTerm then
				local itemNameLower = itemName:lower()
				local itemIDStr = tostring(itemID)
				showItem = itemNameLower:find(module.searchTerm) or itemIDStr:find(module.searchTerm)
			end
			if showItem then
				local entry = module:removable_item(itemID, label)
				local widget = LibStub("AceGUI-3.0"):Create("Icon")
				widget:SetImage(entry.image or "Interface\\Icons\\INV_Misc_QuestionMark")
				widget:SetLabel(entry.name)
				widget:SetCallback("OnClick", function() entry.func() end)
				removeGroupWidget:AddChild(widget)
			end
		end
	end
	removeGroupWidget:DoLayout()
end

function module:HookSearchEditBox()
	local dialog = LibStub("AceConfigDialog-3.0").OpenFrames["DropTheCheapestThing"]
	if not dialog then return end

	local function scan(container)
		if not container or not container.children then return false end

		for _, widget in ipairs(container.children) do
			print(widget)
			if widget.type == "EditBox" and widget.label and widget.label:GetText() == "Search" then
				module.searchBox = widget
				if not widget._dropcheapHooked then
					widget._dropcheapHooked = true

					local function onUpdateSearchFilter()
						local newTerm = widget.editbox:GetText()
						newTerm = newTerm ~= "" and newTerm:lower() or nil

						if module.lastSearchTerm == newTerm then return end

						module.searchTerm = newTerm
						module.lastSearchTerm = newTerm

						AceTimer:ScheduleTimer(function()
							module:RebuildFilteredRemoveGroup()
						end, 0.2)
					end

					widget.editbox:HookScript("OnTextChanged", function()
						local text = widget.editbox:GetText()
						print("Search box changed to:", text)

						local newTerm = text ~= "" and text:lower() or nil

						module.searchTerm = newTerm
						module.lastSearchTerm = newTerm

						AceTimer:ScheduleTimer(function()
							module:RebuildFilteredRemoveGroup("always")
						end, 0.2)
					end)

				end

				return true
			end

			if scan(widget) then return true end
		end

		return false
	end

	local found = scan(dialog)
	if not found then	end
end
