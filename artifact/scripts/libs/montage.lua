--[[ 
Usage
    Drop the lib folder containing this file into your project folder
    Add code like this in your script:
        local montage = require("libs/montage")
        local isDeveloperMode = true  
        montage.init(isDeveloperMode)

    This module allows you to configure how animations (montages) are handled in VR. You can track recently
    played montages and configure various settings for montage playback. In developer mode, you can use the 
    configuration panel to adjust settings for specific montages.

    Available functions:

    montage.init(isDeveloperMode, logLevel) - initializes the montage system
        example:
            montage.init(true, LogLevel.Debug)

    montage.setLogLevel(val) - sets the logging level for montage messages
        example:
            montage.setLogLevel(LogLevel.Debug)

    montage.loadParameters(fileName) - loads montage parameters from a file
        example:
            montage.loadParameters("montage_config")

    montage.showConfiguration(saveFileName, options) - shows basic configuration UI
        example:
            montage.showConfiguration("montage_config")

    montage.showDeveloperConfiguration(saveFileName, options) - shows developer configuration UI
        example:
            montage.showDeveloperConfiguration("montage_config_dev")

    montage.addRecentMontage(montageName) - manually adds a montage to the recent history
        example:
            montage.addRecentMontage("AM_PlayerCharacterHands_Telekinesis")

    montage.getRecentMontages() - returns array of recent montages, newest first
        example:
            local montages = montage.getRecentMontages()
            for _, name in ipairs(montages) do
                print(name)
            end

    montage.getMostRecentMontage() - returns the name of the most recently played montage
        example:
            local lastMontage = montage.getMostRecentMontage()

    montage.getRecentMontagesAsString() - returns recent montages as a newline-delimited string
        example:
            local montagesString = montage.getRecentMontagesAsString()

    montage.clearRecentMontages() - clears the montage history
        example:
            montage.clearRecentMontages()

    montage.getConfigurationWidgets(options) - gets configuration UI widgets
        example:
            local widgets = montage.getConfigurationWidgets()

    montage.getDeveloperConfigurationWidgets(options) - gets developer configuration UI widgets
        example:
            local widgets = montage.getDeveloperConfigurationWidgets()
]]--

local uevrUtils = require("libs/uevr_utils")
local configui = require("libs/configui")
local hands = require("libs/hands")
local ui = require("libs/ui")
local pawnModule = require("libs/pawn")
local accessoriesConfig = require("libs/config/accessories_config_dev")

local M = {}

-- Configuration for recent montages tracking
local MAX_RECENT_MONTAGES = 10
local recentMontages = {}  -- Queue of recent montages, newest first

local configFileName = "dev/montage_config_dev"

local parametersFileName = "montage_parameters"
local parameters = {}
local isParametersDirty = false

local montageList = {}
local montageIDList = {}

local meshMonitors = {}
local disableMeshMonitoring = false

local montageState = {
	hands = nil,
	leftArm = nil,
	rightArm = nil,
	pawnBody = nil,
	pawnArms = nil,
	pawnArmBones = nil,
	motionSicknessCompensation = nil,
	inputEnabled = nil,
	leftAccessory = nil,
	rightAccessory = nil,
}

-- Accessory selections for montage accessory override combos.
-- Index 1 is always "No effect"; indexes > 1 correspond to GUIDs in the parallel array.
local accessorySelectionLabels = {"No effect"}
local accessorySelectionGuids = {}

local function refreshAccessorySelections()
	accessorySelectionLabels = {"No effect"}
	accessorySelectionGuids = {}

	local map = nil
	if accessoriesConfig ~= nil and type(accessoriesConfig.getAccessories) == "function" then
		map = accessoriesConfig.getAccessories()
	end

	--print("Map", map)
	if map ~= nil then
		local guids = {}
		for guid, _ in pairs(map) do
			guids[#guids + 1] = guid
		end
		-- Stable ordering: sort by label then GUID.
		table.sort(guids, function(a, b)
			local la = tostring(map[a])
			local lb = tostring(map[b])
			if la == lb then
				return tostring(a) < tostring(b)
			end
			return la < lb
		end)

		for _, guid in ipairs(guids) do
			accessorySelectionGuids[#accessorySelectionGuids + 1] = guid
			accessorySelectionLabels[#accessorySelectionLabels + 1] = tostring(map[guid])
		end
	end

	-- Update selections if the UI is already created.
	pcall(function()
		configui.setSelections("leftAccessoryWhenActive", accessorySelectionLabels)
		configui.setSelections("rightAccessoryWhenActive", accessorySelectionLabels)
	end)
end

local function guidToAccessoryIndex(guid)
	if guid == nil or guid == "" then return 1 end
	for i = 1, #accessorySelectionGuids do
		if accessorySelectionGuids[i] == guid then
			return i + 1
		end
	end
	return 1
end

local function accessoryIndexToGuid(index)
	if index == nil or index <= 1 then return "" end
	return accessorySelectionGuids[index - 1] or ""
end

local stateConfig = {
	{stateKey = "hands", valueKey = "handsWhenActive", kind = "tri"},
	{stateKey = "leftArm", valueKey = "leftArmWhenActive", kind = "tri"},
	{stateKey = "rightArm", valueKey = "rightArmWhenActive", kind = "tri"},
	{stateKey = "pawnBody", valueKey = "pawnBodyWhenActive", kind = "tri"},
	{stateKey = "pawnArms", valueKey = "pawnArmsWhenActive", kind = "tri"},
	{stateKey = "pawnArmBones", valueKey = "pawnArmBonesWhenActive", kind = "tri"},
	{stateKey = "motionSicknessCompensation", valueKey = "motionSicknessCompensationWhenActive", kind = "tri"},
	{stateKey = "inputEnabled", valueKey = "inputWhenActive", kind = "tri"},
	{stateKey = "leftAccessory", valueKey = "leftAccessoryWhenActive", kind = "accessory"},
	{stateKey = "rightAccessory", valueKey = "rightAccessoryWhenActive", kind = "accessory"},
}

local currentLogLevel = LogLevel.Error
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
    if logLevel == nil then logLevel = LogLevel.Debug end
    if logLevel <= currentLogLevel then
        uevrUtils.print("[montage] " .. text, logLevel)
    end
end

local helpText = "This module allows you to configure how montages (animations) are handled. You can view a list of recently played montages to see what montage is triggered for actions you perform in the game. You can use the configuration panel of a selected montage to adjust settings such as whether the montage will trigger hand animations or cause motion sickness compensation to kick in. Priority settings can be useful if you have written a general purpose montage handler in code but want to override certain montages manually"
local configWidgets = spliceableInlineArray{
}

local developerWidgets = spliceableInlineArray{
	{
		widgetType = "tree_node",
		id = "uevr_montage",
		initialOpen = true,
		label = "Montage Configuration"
	},
		{
			widgetType = "combo",
			id = "knownMontageList",
			label = "Montages",
			selections = {"Any"},
			initialValue = 1,
--			width = 400
		},
        {
            widgetType = "begin_group",
            id = "knowMontageSettings",
            isHidden = false
        },
            { widgetType = "indent", width = 20 },
	        { widgetType = "begin_group", id = "montage_behavior_config", isHidden = false }, { widgetType = "indent", width = 5 }, { widgetType = "text", label = "When Active" }, { widgetType = "begin_rect", },
				{ widgetType = "text", label = "State                                       Priority"},
				{
					widgetType = "combo",
					id = "handsWhenActive",
					label = "",
					selections = {"No effect", "Hidden", "Visibile"},
					initialValue = 1,
					width = 150,
				},
				{ widgetType = "same_line" },
				{
					widgetType = "input_text",
					id = "handsWhenActivePriority",
					label = " Hands Visibility",
					initialValue = "0",
					width = 35,
				},
				{
					widgetType = "combo",
					id = "inputWhenActive",
					label = "",
					selections = {"No effect", "Enable", "Disable"},
					initialValue = 1,
					width = 150,
				},
				{ widgetType = "same_line" },
				{
					widgetType = "input_text",
					id = "inputWhenActivePriority",
					label = " Input",
					initialValue = "0",
					width = 35,
				},
				{
					widgetType = "combo",
					id = "leftArmWhenActive",
					label = "",
					selections = {"No effect", "Enable Animation", "Disable Animation"},
					initialValue = 1,
					width = 150,
				},
				{ widgetType = "same_line" },
				{
					widgetType = "input_text",
					id = "leftArmWhenActivePriority",
					label = " Left Arm Animation",
					initialValue = "0",
					width = 35,
				},
				{
					widgetType = "combo",
					id = "rightArmWhenActive",
					label = "",
					selections = {"No effect", "Enable Animation", "Disable Animation"},
					initialValue = 1,
					width = 150,
				},
				{ widgetType = "same_line" },
				{
					widgetType = "input_text",
					id = "rightArmWhenActivePriority",
					label = " Right Arm Animation",
					initialValue = "0",
					width = 35,
				},
				{
					widgetType = "combo",
					id = "pawnBodyWhenActive",
					label = "",
					selections = {"No effect", "Hidden", "Visible"},
					initialValue = 1,
					width = 150,
				},
				{ widgetType = "same_line" },
				{
					widgetType = "input_text",
					id = "pawnBodyWhenActivePriority",
					label = " Pawn Body Visibility",
					initialValue = "0",
					width = 35,
				},
				{
					widgetType = "combo",
					id = "pawnArmsWhenActive",
					label = "",
					selections = {"No effect", "Hidden", "Visible"},
					initialValue = 1,
					width = 150,
				},
				{ widgetType = "same_line" },
				{
					widgetType = "input_text",
					id = "pawnArmsWhenActivePriority",
					label = " Pawn Arms Visibility",
					initialValue = "0",
					width = 35,
				},
				{
					widgetType = "combo",
					id = "pawnArmBonesWhenActive",
					label = "",
					selections = {"No effect", "Hidden", "Visible"},
					initialValue = 1,
					width = 150,
				},
				{ widgetType = "same_line" },
				{
					widgetType = "input_text",
					id = "pawnArmBonesWhenActivePriority",
					label = " Pawn Arm Bones Visibility",
					initialValue = "0",
					width = 35,
				},
				{
					widgetType = "combo",
					id = "motionSicknessCompensationWhenActive",
					label = "",
					selections = {"No effect", "Enable", "Disable"},
					initialValue = 1,
					width = 150,
				},
				{ widgetType = "same_line" },
				{
					widgetType = "input_text",
					id = "motionSicknessCompensationWhenActivePriority",
					label = " Motion Sickness Compensation",
					initialValue = "0",
					width = 35,
				},
				{
					widgetType = "combo",
					id = "leftAccessoryWhenActive",
					label = "",
					selections = {"No effect"},
					initialValue = 1,
					width = 150,
				},
				{ widgetType = "same_line" },
				{
					widgetType = "input_text",
					id = "leftAccessoryWhenActivePriority",
					label = " Left Accessory",
					initialValue = "0",
					width = 35,
				},
				{
					widgetType = "combo",
					id = "rightAccessoryWhenActive",
					label = "",
					selections = {"No effect"},
					initialValue = 1,
					width = 150,
				},
				{ widgetType = "same_line" },
				{
					widgetType = "input_text",
					id = "rightAccessoryWhenActivePriority",
					label = " Right Accessory",
					initialValue = "0",
					width = 35,
				},
            { widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 5 }, { widgetType = "end_group", },
            { widgetType = "unindent", width = 20 },
        {
            widgetType = "end_group",
        },
		{ widgetType = "new_line" },
       	{
            widgetType = "input_text_multiline",
            id = "recentMontagesPlayed",
            label = " ",
            initialValue = "",
            size = {440, 230} -- optional, will default to full size without it
        },
		-- {
		-- 	widgetType = "input_text",
		-- 	id = "lastMontagePlayed",
		-- 	label = "Last Montage Played",
		-- 	initialValue = "",
		-- },
	{
		widgetType = "tree_pop"
	},
	{ widgetType = "new_line" },
	{
		widgetType = "tree_node",
		id = "uevr_pawn_help_tree",
		initialOpen = true,
		label = "Help"
	},
		{
			widgetType = "text",
			id = "uevr_pawn_help",
			label = helpText,
			wrapped = true
		},
	{
		widgetType = "tree_pop"
	},
}

local function showMontageEditFields()
	refreshAccessorySelections()
    local index = configui.getValue("knownMontageList")
    if index == nil then --or index == 1 then
        configui.setHidden("knowMontageSettings", true)
        return
    end
    configui.setHidden("knowMontageSettings", false)

    local id = montageIDList[index]
    if id ~= "" and parameters ~= nil and parameters["montagelist"] ~= nil and parameters["montagelist"][id] ~= nil then
        local data = parameters["montagelist"][id]
        if data ~= nil then
			-- Initialize and set values for all state configs
			for _, config in ipairs(stateConfig) do
				local valueKey = config.valueKey
				if config.kind == "tri" then
					if data[valueKey] == nil then data[valueKey] = 1 end
					configui.setValue(valueKey, data[valueKey], true)
				elseif config.kind == "accessory" then
					local guid = data[valueKey] or ""
					configui.setValue(valueKey, guidToAccessoryIndex(guid), true)
				end

				local priorityKey = valueKey .. "Priority"
				if data[priorityKey] == nil or data[priorityKey] == "" then data[priorityKey] = "0" end
				configui.setValue(priorityKey, data[priorityKey], true)
			end
        end
    end
end

-- local function updateMontageList()
--     montageList = {}
-- 	montageIDList = {}
--     if parameters ~= nil and parameters["montagelist"] ~= nil then
--         for id, data in pairs(parameters["montagelist"]) do
--             if data ~= nil and data["label"] ~= nil then
--                 table.insert(montageList, data["label"])
--                 table.insert(montageIDList, id)
--             end
--         end
-- 		--can only do this because key and label are the same
--         table.sort(montageList)
--         table.sort(montageIDList)

--         --table.insert(montageList, 1, "Any")
--         --table.insert(montageIDList, 1, "Any")
--         configui.setSelections("knownMontageList", montageList)
-- 		configui.setValue("knownMontageList", 1)

-- 		showMontageEditFields()
--     end
-- end

local function updateMontageList()
    montageList = {}
    montageIDList = {}

    if parameters ~= nil and parameters["montagelist"] ~= nil then
        local entries = {}
        for id, data in pairs(parameters["montagelist"]) do
            if data ~= nil and data["label"] ~= nil then
                entries[#entries + 1] = { id = id, label = data["label"] }
            end
        end

        table.sort(entries, function(a, b)
            local la = tostring(a.label)
            local lb = tostring(b.label)
            if la == lb then
                return tostring(a.id) < tostring(b.id)
            end
            return la < lb
        end)

        for _, e in ipairs(entries) do
            montageList[#montageList + 1] = e.label
            montageIDList[#montageIDList + 1] = e.id
        end

        configui.setSelections("knownMontageList", montageList)
        configui.setValue("knownMontageList", 1)
        showMontageEditFields()
    end
end

local function saveParameters()
	M.print("Saving montage parameters " .. parametersFileName)
	json.dump_file(parametersFileName .. ".json", parameters, 4)
end

local createDevMonitor = doOnce(function()
    uevrUtils.setInterval(1000, function()
        if isParametersDirty == true then
            saveParameters()
            isParametersDirty = false
        end
    end)

	M.registerMontageChangeCallback(function(montageObject, montageName, label)
		if parameters ~= nil and montageName ~= nil and montageName ~= "" then
			if parameters["montagelist"] == nil then
				parameters["montagelist"] = {}
				isParametersDirty = true
			end
			if parameters["montagelist"][montageName] == nil then
				parameters["montagelist"][montageName] = {}
				parameters["montagelist"][montageName]["label"] = label .. " " .. montageName
				parameters["montagelist"][montageName]["class_name"] = montageObject:get_full_name()
				isParametersDirty = true
				updateMontageList()
			elseif parameters["montagelist"][montageName]["class_name"] == nil then
				parameters["montagelist"][montageName]["class_name"] = montageObject:get_full_name()
				isParametersDirty = true
			end
			--configui.setValue("lastMontagePlayed", montageName)
            M.addRecentMontage(montageName)  -- Track in recent history
			configui.setValue("recentMontagesPlayed", M.getRecentMontagesAsString())
		end
	end)

	-- uevrUtils.registerMontageChangeCallback(function(montage, montageName)
	-- 	if parameters ~= nil and montageName ~= nil and montageName ~= "" then
	-- 		if parameters["montagelist"] == nil then
	-- 			parameters["montagelist"] = {}
	-- 			isParametersDirty = true
	-- 		end
	-- 		if parameters["montagelist"][montageName] == nil then
	-- 			parameters["montagelist"][montageName] = {}
	-- 			parameters["montagelist"][montageName]["label"] = montageName
	-- 			parameters["montagelist"][montageName]["class_name"] = montage:get_full_name()
	-- 			isParametersDirty = true
	-- 			updateMontageList()
	-- 		elseif parameters["montagelist"][montageName]["class_name"] == nil then
	-- 			parameters["montagelist"][montageName]["class_name"] = montage:get_full_name()
	-- 			isParametersDirty = true
	-- 		end
	-- 		--configui.setValue("lastMontagePlayed", montageName)
    --         M.addRecentMontage(montageName)  -- Track in recent history
	-- 		configui.setValue("recentMontagesPlayed", M.getRecentMontagesAsString())
	-- 	end
	-- end)
end, Once.EVER)

local function updateCurrentMontageFields()
    local index = configui.getValue("knownMontageList")
    if index ~= nil then --and index ~= 1 then
        local id = montageIDList[index]
        if id ~= "" and  parameters ~= nil and parameters["montagelist"] ~= nil and parameters["montagelist"][id] ~= nil then
			for _, config in ipairs(stateConfig) do
				local valueKey = config.valueKey
				if config.kind == "tri" then
					parameters["montagelist"][id][valueKey] = configui.getValue(valueKey)
				elseif config.kind == "accessory" then
					local idxVal = configui.getValue(valueKey)
					parameters["montagelist"][id][valueKey] = accessoryIndexToGuid(idxVal)
				end
				parameters["montagelist"][id][valueKey .. "Priority"] = configui.getValue(valueKey .. "Priority")
			end
            isParametersDirty = true
        end
    end
end

local function updateStateIfHigherPriority(data, stateKey, valueKey)
	local priority = tonumber(data[valueKey .. "Priority"]) or 0
	if priority >= montageState[stateKey .. "Priority"] then
		if data[valueKey] == 2 then
			montageState[stateKey] = true
			montageState[stateKey .. "Priority"] = priority
		elseif data[valueKey] == 3 then
			montageState[stateKey] = false
			montageState[stateKey .. "Priority"] = priority
		end
	end
end

local function updateAccessoryStateIfHigherPriority(data, stateKey, valueKey)
	local priority = tonumber(data[valueKey .. "Priority"]) or 0
	local currentPriority = montageState[stateKey .. "Priority"] or 0
	if priority >= currentPriority then
		local guid = data[valueKey]
		if guid == nil or guid == "" then
			montageState[stateKey] = nil
		else
			montageState[stateKey] = guid
		end
		montageState[stateKey .. "Priority"] = priority
	end
end

local function executeMontageChange(...)
	uevrUtils.executeUEVRCallbacks("on_module_montage_change", table.unpack({...}))
end

local function handleMontageChanged(montage, montageName, label, animInstance)
	print("Montage changed: " .. tostring(montageName))
	for _, config in ipairs(stateConfig) do
		montageState[config.stateKey] = nil
		montageState[config.stateKey .. "Priority"] = 0
	end

	if parameters ~= nil and montageName ~= nil and montageName ~= "" and parameters["montagelist"] ~= nil and parameters["montagelist"][montageName] ~= nil  then
		local data = parameters["montagelist"][montageName]
		for _, config in ipairs(stateConfig) do
			if config.kind == "tri" then
				updateStateIfHigherPriority(data, config.stateKey, config.valueKey)
			elseif config.kind == "accessory" then
				updateAccessoryStateIfHigherPriority(data, config.stateKey, config.valueKey)
			end
		end
	end

	executeMontageChange(montage, montageName, label, animInstance)
end

uevrUtils.registerMontageChangeCallback(function(montage, montageName, animInstance)
	handleMontageChanged(montage, montageName, "Pawn", animInstance)
	-- if montageState["inputEnabled"] == 3 and montageName == nil then
	-- 	delay(3000, function()
	-- 		montageState["inputEnabled"] = nil
	-- 		montageState["inputEnabledPriority"] = 0
	-- 	end)
	-- 	return
	-- end

	-- for _, config in ipairs(stateConfig) do
	-- 	montageState[config.stateKey] = nil
	-- 	montageState[config.stateKey .. "Priority"] = 0
	-- end

	-- if parameters ~= nil and montageName ~= nil and montageName ~= "" and parameters["montagelist"] ~= nil and parameters["montagelist"][montageName] ~= nil  then
	-- 	local data = parameters["montagelist"][montageName]
	-- 	for _, config in ipairs(stateConfig) do
	-- 		updateStateIfHigherPriority(data, config.stateKey, config.valueKey)
	-- 	end
	-- end
end)

--TODO implement monitoring of montage states on meshes as well as pawn
--AnimMontage /Game/Art/ANIM/Character/FirstPerson/MeleeHvy/AS_MeleeHvy_FP_BasicAttack_R2L_Start_001_Montage.AS_MeleeHvy_FP_BasicAttack_R2L_Start_001_Montage
--AnimMontage /Game/Art/ANIM/Character/FirstPerson/MeleeHvy/AS_MeleeHvy_FP_BasicAttack_R2L_Hit_001_Montage.AS_MeleeHvy_FP_BasicAttack_R2L_Hit_001_Montage
-- local currentMontage = nil
-- function checkMontage()
-- 	local animInstance = uevrUtils.getValid(pawn,{"FPVMesh","AnimScriptInstance"})
-- 	if animInstance ~= nil then
-- 		local montage = animInstance:GetCurrentActiveMontage()
-- 		print(montage and montage:get_full_name() or "nil")
-- 		if currentMontage ~= montage then
-- 			currentMontage = montage
-- 			local montageName = currentMontage and M.getShortName(currentMontage) or ""
-- 			if on_montage_change ~= nil then
-- 				on_montage_change(currentMontage, montageName)
-- 			end
-- 		end
-- 	end
-- end

-- function M.playAnimScriptInstanceMontage(montageName, speed, startTime, stopAllAnimations)
-- 	local animInstance = uevrUtils.getValid(pawn,{"FPVMesh","AnimScriptInstance"})
-- 	if animInstance ~= nil then
-- 		--local className = parameters["montagelist"][montageName]["class_name"]
-- 		local className = "AnimMontage /Game/Art/ANIM/Character/FirstPerson/MeleeHvy/AS_MeleeHvy_FP_BasicAttack_R2L_Hit_001_Montage.AS_MeleeHvy_FP_BasicAttack_R2L_Hit_001_Montage"
-- 		if className ~= nil then
-- 			--this should be get_class so it caches
-- 			local montage = uevrUtils.find_required_object(className)
-- 			if montage ~= nil then
-- 				local result = animInstance:Montage_Play(montage, speed or 1.0, 0, startTime or 0.0, stopAllAnimations or false)
-- 			end
-- 		end
-- 	end
-- end

-- function M.stopAnimScriptInstanceMontage(montageName, blendTime)
-- 	local animInstance = uevrUtils.getValid(pawn,{"FPVMesh","AnimScriptInstance"})
-- 	if animInstance ~= nil then
-- 		--local className = parameters["montagelist"][montageName]["class_name"]
-- 		local className = "AnimMontage /Game/Art/ANIM/Character/FirstPerson/MeleeHvy/AS_MeleeHvy_FP_BasicAttack_R2L_Hit_001_Montage.AS_MeleeHvy_FP_BasicAttack_R2L_Hit_001_Montage"
-- 		if className ~= nil then
-- 			--this should be get_class so it caches
-- 			local montage = uevrUtils.find_required_object(className)
-- 			if montage ~= nil then
-- 				local result = animInstance:Montage_Stop(blendTime or 0.0, montage )
-- 			end
-- 		end
-- 	end
-- end

-- function M.setPlayRateAnimScriptInstanceMontage(montageName, newPlayRate)
-- 	local animInstance = uevrUtils.getValid(pawn,{"FPVMesh","AnimScriptInstance"})
-- 	if animInstance ~= nil then
-- 		--local className = parameters["montagelist"][montageName]["class_name"]
-- 		local className = "AnimMontage /Game/Art/ANIM/Character/FirstPerson/MeleeHvy/AS_MeleeHvy_FP_BasicAttack_R2L_Hit_001_Montage.AS_MeleeHvy_FP_BasicAttack_R2L_Hit_001_Montage"
-- 		if className ~= nil then
-- 			--this should be get_class so it caches
-- 			local montage = uevrUtils.find_required_object(className)
-- 			if montage ~= nil then
-- 				local result = animInstance:Montage_SetPlayRate(montage, newPlayRate or 1.0)
-- 			end
-- 		end
-- 	end
-- end

local function getAnimInstanceForMontage(montageObject, label)
	if label == nil or label == "" then
		--try to find the montage object in the meshMonitors current montages
		for descriptor, monitor in pairs(meshMonitors) do
			if monitor["currentMontage"] == montageObject then
				label = monitor.label
				break
			end
		end
	end
	if label == nil or label == "" or label == "Pawn" then
		--there's a possibility Mesh doesnt exist. In that case we need to scan for all mesh children and I guess pick the first one
		--same goes for the check in uevrUtils
		return uevrUtils.getValid(pawn, {"Mesh","AnimScriptInstance"}), montageObject
	else
		for descriptor, monitor in pairs(meshMonitors) do
			if monitor.label == label then
				if monitor.meshObject ~= nil then
					if montageObject == nil then
						montageObject = monitor["currentMontage"]
					end
					return monitor.meshObject.AnimScriptInstance, montageObject
				end
			end
		end
	end
end

function M.setPlaybackRate(montage, label, rate)
	local animInstance, montageObject = getAnimInstanceForMontage(montage, label)
	if animInstance ~= nil then
		animInstance:Montage_SetPlayRate(montageObject, rate or 1.0)
		print("Set playback rate to " .. tostring(rate) .. " for montage " .. montageObject:get_full_name() .. " on " .. tostring(label))
	end
end

function M.getPosition(montage, label)
	local animInstance, montageObject = getAnimInstanceForMontage(montage, label)
	if animInstance ~= nil then
		local position = animInstance:Montage_GetPosition(montageObject)
		--print("Current position for montage " .. montageObject:get_full_name() .. " on " .. tostring(label) .. " is " .. tostring(position))
		return position
	end
end

function M.play(montage, label, rate, startTime, stopAllAnimations)
	local animInstance, montageObject = getAnimInstanceForMontage(montage, label)
	if animInstance ~= nil then
		animInstance:Montage_Play(montageObject, rate or 1.0, 0, startTime or 0.0, stopAllAnimations or false)
	end
end

function M.pause(montage, label)
	local animInstance, montageObject = getAnimInstanceForMontage(montage, label)
	if animInstance ~= nil then
		animInstance:Montage_Pause(montageObject)
	end
end

function M.stop(montage, label, rate)
	local animInstance, montageObject = getAnimInstanceForMontage(montage, label)
	if animInstance ~= nil then
		animInstance:Montage_Stop(rate or 0.0, montageObject)
	end
end

function M.init(isDeveloperMode, logLevel)
    if logLevel ~= nil then
        M.setLogLevel(logLevel)
    end
    if isDeveloperMode == nil and uevrUtils.getDeveloperMode() ~= nil then
        isDeveloperMode = uevrUtils.getDeveloperMode()
    end

    if isDeveloperMode then
		--maintain backward compatability
		if json.load_file("montage_config_dev.json") ~= nil then
			configFileName = "montage_config_dev"
		end
		M.showDeveloperConfiguration(configFileName)
        createDevMonitor()
        updateMontageList()
    end
end

local function checkMonitoredMeshes()
	for descriptor, monitor in pairs(meshMonitors) do
		if monitor.meshObject ~= nil then
			local animInstance = monitor.meshObject.AnimScriptInstance
			if animInstance ~= nil then
				local playingMontage = animInstance:GetCurrentActiveMontage()
				--print("Checking monitored mesh " .. monitor.label .. " for montage changes. Current: " .. tostring(monitor["currentMontage"] and monitor["currentMontage"]:get_full_name() or "nil") .. " New: " .. tostring(playingMontage and playingMontage:get_full_name() or "nil"))
				if monitor["currentMontage"] ~= playingMontage then
					monitor["currentMontage"] = playingMontage
					local montageName = playingMontage and uevrUtils.getShortName(playingMontage) or ""
					handleMontageChanged(playingMontage, montageName, monitor.label, animInstance)
				end
			end
		end
	end
end

function M.addMeshMonitor(label, meshDescriptor)
	meshMonitors[meshDescriptor] = {label = label, descriptor = meshDescriptor, meshObject = uevrUtils.getObjectFromDescriptor(meshDescriptor, false)}
end

setInterval(2000, function()
	if not disableMeshMonitoring then
		for descriptor, monitor in pairs(meshMonitors) do
			if monitor.meshObject == nil then
				monitor.meshObject = uevrUtils.getObjectFromDescriptor(descriptor, false)
			end
		end
	end
end)

function M.reset()
	for descriptor, monitor in pairs(meshMonitors) do
		monitor.meshObject = nil
		monitor["currentMontage"] = nil
	end
end

function M.loadParameters(fileName)
	if fileName ~= nil then parametersFileName = fileName end
	M.print("Loading montage parameters " .. parametersFileName)
	parameters = json.load_file(parametersFileName .. ".json")

	if parameters == nil then
		parameters = {}
		M.print("Creating montage parameters")
	end

	if parameters["montagelist"] == nil then
		parameters["montagelist"] = {}
		isParametersDirty = true
	end
	if parameters["montagelist"]["Any"] == nil then
		parameters["montagelist"]["Any"] = {}
		parameters["montagelist"]["Any"]["label"] = "Any"
		isParametersDirty = true
	end

    updateMontageList()
end

function M.getConfigurationWidgets(options)
	return configui.applyOptionsToConfigWidgets(configWidgets, options)
end

function M.getDeveloperConfigurationWidgets(options)
	return configui.applyOptionsToConfigWidgets(developerWidgets, options)
end

function M.showConfiguration(saveFileName, options)
	configui.createConfigPanel("Montage Config", saveFileName, spliceableInlineArray{expandArray(M.getConfigurationWidgets, options)})
end

function M.showDeveloperConfiguration(saveFileName, options)
	configui.createConfigPanel("Montage Config Dev", saveFileName, spliceableInlineArray{expandArray(M.getDeveloperConfigurationWidgets, options)})
end

-- Functions for managing recent montages
function M.addRecentMontage(montageName)
    -- Remove if already in list (to move it to front)
    -- for i = #recentMontages, 1, -1 do
    --     if recentMontages[i] == montageName then
    --         table.remove(recentMontages, i)
    --         break
    --     end
    -- end

    -- Add to front
    table.insert(recentMontages, 1, montageName)

    -- Trim if exceeds max size
    while #recentMontages > MAX_RECENT_MONTAGES do
        table.remove(recentMontages)
    end

    M.print("Recent montage added: " .. montageName, LogLevel.Debug)
end

function M.getRecentMontages()
    return recentMontages
end

function M.getMostRecentMontage()
    return recentMontages[1]
end

function M.clearRecentMontages()
    recentMontages = {}
end

--deprecated, use M.play instead
function M.playMontage(montageName, speed)
	if uevrUtils.getValid(pawn) ~= nil and parameters ~= nil and montageName ~= nil and montageName ~= "" and parameters["montagelist"][montageName] ~= nil then
		local className = parameters["montagelist"][montageName]["class_name"]
		if className ~= nil then
			--this should be get_class so it caches
			local montage = uevrUtils.find_required_object(className)
			if montage ~= nil then
				local result = pawn:PlayAnimMontage(montage, speed or 1.0, uevrUtils.fname_from_string(""))
			end
		end
	end
end
-- Returns recent montages as a newline-delimited string
function M.getRecentMontagesAsString()
    return table.concat(recentMontages, "\n")
end

hands.registerIsAnimatingFromMeshCallback(function(hand)
	--print("IsAnimatingFromMesh", hand, montageState["leftArm"], montageState["leftArmPriority"], montageState["rightArm"], montageState["rightArmPriority"])
	if hand == Handed.Right then
		return montageState["rightArm"], montageState["rightArmPriority"]
	end
	return montageState["leftArm"], montageState["leftArmPriority"]
end)

ui.registerIsInMotionSicknessCausingSceneCallback(function()
	return montageState["motionSicknessCompensation"], montageState["motionSicknessCompensationPriority"]
end)

pawnModule.registerIsArmBonesHiddenCallback(function()
	return montageState["pawnArmBones"], montageState["pawnArmBonesPriority"]
end)

pawnModule.registerIsPawnBodyHiddenCallback(function()
	return montageState["pawnBody"], montageState["pawnBodyPriority"]
end)

pawnModule.registerIsPawnArmsHiddenCallback(function()
	return montageState["pawnArms"], montageState["pawnArmsPriority"]
end)

hands.registerIsHiddenCallback(function()
	return montageState["hands"], montageState["handsPriority"]
end)

uevrUtils.registerUEVRCallback("is_input_disabled", function()
	return montageState["inputEnabled"] ~= nil and (not montageState["inputEnabled"]) or nil, montageState["inputEnabledPriority"]
end)

uevrUtils.registerUEVRCallback("active_left_accessory", function()
	return montageState["leftAccessory"], montageState["leftAccessoryPriority"]
end)

uevrUtils.registerUEVRCallback("active_right_accessory", function()
	return montageState["rightAccessory"], montageState["rightAccessoryPriority"]
end)

function M.registerMontageChangeCallback(func)
    if func ~= nil and type(func) == "function" then
	    uevrUtils.registerUEVRCallback("on_module_montage_change", func)
    end
end

-- Register update handlers for all state configs and their priorities
for _, config in ipairs(stateConfig) do
    local valueKey = config.valueKey
    configui.onUpdate(valueKey, function(value)
        updateCurrentMontageFields()
    end)
    configui.onUpdate(valueKey .. "Priority", function(value)
        updateCurrentMontageFields()
    end)
end

configui.onUpdate("knownMontageList", function(value)
	showMontageEditFields()
end)

uevrUtils.registerPreLevelChangeCallback(function(level)
	M.reset()
end)

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
	--check the monitored meshes for montages
	checkMonitoredMeshes()
end)

M.loadParameters()

return M