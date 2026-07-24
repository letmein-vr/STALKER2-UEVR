--[[ 
Usage
    Drop the lib folder containing this file into your project folder
    Add code like this in your script:
        local pawnModule = require("libs/pawn")
        local isDeveloperMode = true
        pawnModule.init(isDeveloperMode)

    Typical usage would be to run this code with developerMode set to true, then use the configuration tab
    to set parameters the way you want them, then set developerMode to false for production use. Be sure
    to ship your code with the data folder as well as the script folder because the data folder will contain
    your parameter settings.
        
    Available functions:

    pawnModule.init(isDeveloperMode, logLevel) - initializes the pawn management system with specified mode and log level
        example:
            pawnModule.init(true, LogLevel.Debug)

    pawnModule.registerIsArmBonesHiddenCallback(func) - registers a callback for when arm bones visibility changes
        example:
			pawnModule.registerIsArmBonesHiddenCallback(function()
				return isPlayerPlaying(), 0
			end)

    pawnModule.setBodyMeshName(val) - sets the name of the body mesh
        example:
            pawnModule.setBodyMeshName("Character.Body")

    pawnModule.getBodyMesh() - gets the body mesh object
        example:
            local mesh = pawnModule.getBodyMesh()

    pawnModule.getArmsMesh() - gets the arms mesh object
        example:
            local mesh = pawnModule.getArmsMesh()

    pawnModule.getArmsAnimationMesh() - gets the arms animation mesh object (used for weapon animations)
        example:
            local mesh = pawnModule.getArmsAnimationMesh()

    pawnModule.hideBodyMesh(val) - shows/hides the body mesh
        example:
            pawnModule.hideBodyMesh(true)  -- hides the body mesh
            pawnModule.hideBodyMesh(false) -- shows the body mesh

    pawnModule.hideAnimationArms(val) - shows/hides the animation arms
        example:
            pawnModule.hideAnimationArms(true)  -- hides animation arms
            pawnModule.hideAnimationArms(false) -- shows animation arms

    pawnModule.hideArms(val) - shows/hides the arms
        example:
            pawnModule.hideArms(true)  -- hides the arms
            pawnModule.hideArms(false) -- shows the arms

    pawnModule.hideArmsBones(val) - shows/hides the arm bones
        example:
            pawnModule.hideArmsBones(true)  -- hides arm bones
            pawnModule.hideArmsBones(false) -- shows arm bones

	pawnModule.setLogLevel(val) - sets the logging level for the pawn module
        example:
            pawnModule.setLogLevel(LogLevel.Debug)

    pawnModule.showConfiguration(saveFileName, options) - shows user configuration UI
        example:
            pawnModule.showConfiguration("pawn_config.json", {})


]]

local uevrUtils = require("libs/uevr_utils")
local configui = require("libs/configui")
--local hands = require("libs/hands")
local paramModule = require("libs/core/params")

local M = {}

local parametersFileName = "pawn_parameters"
local parameters = {
    bodyMeshName = "Pawn.Mesh",
    armsMeshName = "Pawn.Mesh",
    armsAnimationMeshName = "Pawn.Mesh",
    pawnUpperArmRight = "",
    pawnUpperArmLeft = "",
    hidePawnArmsBones = false,
    hidePawnBodyMesh = false,
    hidePawnArmsMesh = false,
    hideAnimationArms = false,
	bodyMeshFOVFixID = "",
	armsMeshFOVFixID = "",
}
-- local parameters = {
--     _profileLabels = {
--         default = "Default"
--     },
--     _profileState = {
--         currentEditingProfile = "default"
--     },
-- 	default = {
-- 		bodyMeshName = "Pawn.Mesh",
-- 		armsMeshName = "Pawn.Mesh",
-- 		armsAnimationMeshName = "Pawn.Mesh",
-- 		pawnUpperArmRight = "",
-- 		pawnUpperArmLeft = "",
-- 		hidePawnArmsBones = false,
-- 		hidePawnBodyMesh = false,
-- 		hidePawnArmsMesh = false,
-- 		hideAnimationArms = false,
-- 		bodyMeshFOVFixID = "",
-- 		armsMeshFOVFixID = "",
-- 	}
-- }
local pawnConfigDev = nil

local currentLogLevel = LogLevel.Error
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
	if logLevel == nil then logLevel = LogLevel.Debug end
	if logLevel <= currentLogLevel then
		uevrUtils.print("[pawn] " .. text, logLevel)
	end
end

local paramManager = paramModule.new(parametersFileName, parameters, true)
paramManager:load(true)

local function getParameter(key)
    return paramManager:getFromActiveProfile(key)
end

local function setParameter(key, value, persist)
    return paramManager:setInActiveProfile(key, value, persist)
end

local function doHideArmsBones(val)
	local armsMesh = M.getArmsMesh()
	if armsMesh ~= nil then
		M.print("Hiding arms bones: " .. tostring(val))
		if val then
			if getParameter("pawnUpperArmRight") ~= nil and getParameter("pawnUpperArmRight") ~= "" then
				armsMesh:HideBoneByName(uevrUtils.fname_from_string(getParameter("pawnUpperArmRight")), 0)
			end
			if getParameter("pawnUpperArmLeft") ~= nil and getParameter("pawnUpperArmLeft") ~= "" then
				armsMesh:HideBoneByName(uevrUtils.fname_from_string(getParameter("pawnUpperArmLeft")), 0)
			end
		else
			if getParameter("pawnUpperArmRight") ~= nil and getParameter("pawnUpperArmRight") ~= "" then
				armsMesh:UnHideBoneByName(uevrUtils.fname_from_string(getParameter("pawnUpperArmRight")))
			end
			if getParameter("pawnUpperArmLeft") ~= nil and getParameter("pawnUpperArmLeft") ~= "" then
				armsMesh:UnHideBoneByName(uevrUtils.fname_from_string(getParameter("pawnUpperArmLeft")))
			end
		end
	end
end

local function fixFOV()
	local bodyMesh = nil
	if getParameter("hidePawnBodyMesh") == false and getParameter("bodyMeshFOVFixID") ~= nil and getParameter("bodyMeshFOVFixID") ~= "" then
		bodyMesh = M.getBodyMesh()
		if bodyMesh ~= nil then
			uevrUtils.fixMeshFOV(bodyMesh, getParameter("bodyMeshFOVFixID"), 0.0, true, true, false)
		end
	end
	if getParameter("hidePawnArmsMesh") == false and getParameter("armsMeshFOVFixID") ~= nil and getParameter("armsMeshFOVFixID") ~= "" then
		local armsMesh = M.getArmsMesh()
		--dont do it again if it was already done on the body and body and arms are the same
		if (bodyMesh == nil or bodyMesh ~= armsMesh) and armsMesh ~= nil then
			uevrUtils.fixMeshFOV(armsMesh, getParameter("armsMeshFOVFixID"), 0.0, true, true, false)
		end
	end
end

local function doHideBodyMesh(val)
	local mesh = M.getBodyMesh()
	if mesh ~= nil then
		M.print("Hiding body mesh: " .. tostring(val))
		if getParameter("hideSettingsVisibility") == true then
			mesh:SetVisibility(not val, getParameter("hideSettingsVisibilityPropagate") == true)
		end
		if getParameter("hideSettingsHiddenInGame") == true then
			mesh:SetHiddenInGame(val, getParameter("hideSettingsHiddenInGamePropagate") == true)
		end
		if getParameter("hideSettingsRenderInMainPass") ~= false then
			mesh:call("SetRenderInMainPass", not val)
		end
		if getParameter("hideSettingsRenderInDepthPass") == true then
			mesh:call("SetRenderInDepthPass", not val)
		end
		fixFOV()
	end
end

local function doHideArms(val)
	local mesh = M.getArmsMesh()
	if mesh ~= nil then
		M.print("Hiding arms mesh: " .. tostring(val))
		if getParameter("hideSettingsVisibility") == true then
			mesh:SetVisibility(not val, getParameter("hideSettingsVisibilityPropagate") == true)
		end
		if getParameter("hideSettingsHiddenInGame") == true then
			mesh:SetHiddenInGame(val, getParameter("hideSettingsHiddenInGamePropagate") == true)
		end
		if getParameter("hideSettingsRenderInMainPass") ~= false then
			mesh:call("SetRenderInMainPass", not val)
		end
		if getParameter("hideSettingsRenderInDepthPass") == true then
			mesh:call("SetRenderInDepthPass", not val)
		end
		fixFOV()
	end
end

local function doHideAnimationArms(val)
	local mesh = M.getArmsAnimationMesh()
	if mesh ~= nil then
		M.print("Hiding animation arms mesh: " .. tostring(val))
		if getParameter("hideSettingsVisibility") == true then
			mesh:SetVisibility(not val, getParameter("hideSettingsVisibilityPropagate") == true)
		end
		if getParameter("hideSettingsHiddenInGame") == true then
			mesh:SetHiddenInGame(val, getParameter("hideSettingsHiddenInGamePropagate") == true)
		end
		if getParameter("hideSettingsRenderInMainPass") ~= false then
			mesh:call("SetRenderInMainPass", not val)
		end
		if getParameter("hideSettingsRenderInDepthPass") == true then
			mesh:call("SetRenderInDepthPass", not val)
		end
		fixFOV()
	end
end

-- Since multiple settings can affect the same mesh, this function keeps the visibility states synchronized
local isSyncingMeshVisibility = false 
local function syncMeshVisibilityStates(isHidden, mesh, key, value, persist, noCallbacks)
    if isSyncingMeshVisibility then
        return  -- Prevent re-entry and endless loops
    end
    isSyncingMeshVisibility = true
	local bodyMesh = M.getBodyMesh()
	local armsMesh = M.getArmsMesh()
	local armsAnimationMesh = M.getArmsAnimationMesh()
	if mesh == bodyMesh then
		setParameter("hidePawnBodyMesh", isHidden, persist)
		uevrUtils.executeUEVRCallbacks("on_pawn_config_param_change", "hidePawnBodyMesh", isHidden)
		uevrUtils.executeUEVRCallbacks("on_pawn_param_change", "hidePawnBodyMesh", isHidden)
	end
	if mesh == armsMesh then
		setParameter("hidePawnArmsMesh", isHidden, persist)
		uevrUtils.executeUEVRCallbacks("on_pawn_config_param_change", "hidePawnArmsMesh", isHidden)
		uevrUtils.executeUEVRCallbacks("on_pawn_param_change", "hidePawnArmsMesh", isHidden)
	end
	if mesh == armsAnimationMesh then
		setParameter("hideAnimationArms", isHidden, persist)
		uevrUtils.executeUEVRCallbacks("on_pawn_config_param_change", "hidePawnArmsAnimationMesh", isHidden)
		uevrUtils.executeUEVRCallbacks("on_pawn_param_change", "hidePawnArmsAnimationMesh", isHidden)
	end
	isSyncingMeshVisibility = false  -- Reset flag
end

local function saveParameter(key, value, persist, noCallbacks)
	if key == "hidePawnArmsMesh" then
		syncMeshVisibilityStates(value, M.getArmsMesh(), key, value, persist, noCallbacks)
		doHideArms(value)
	elseif key == "hidePawnArmsAnimationMesh" then
		syncMeshVisibilityStates(value, M.getArmsAnimationMesh(), key, value, persist, noCallbacks)
		doHideAnimationArms(value)
	elseif key == "hidePawnBodyMesh" then
		syncMeshVisibilityStates(value, M.getBodyMesh(), key, value, persist, noCallbacks)
		doHideBodyMesh(value)
	else
		setParameter(key, value, persist)
		if key == "hidePawnArmsBones" then
			doHideArmsBones(value)
		end
		if not (noCallbacks == true) then
			uevrUtils.executeUEVRCallbacks("on_pawn_config_param_change", key, value)
		end
		uevrUtils.executeUEVRCallbacks("on_pawn_param_change", key, value)
	end
end

local createConfigMonitor = doOnce(function()
	uevrUtils.registerUEVRCallback("on_pawn_config_param_change", function(key, value)
		saveParameter(key, value, true, true)
	end)
end, Once.EVER)

function M.init(isDeveloperMode, logLevel)
	if logLevel ~= nil then
        M.setLogLevel(logLevel)
    end
    if isDeveloperMode == nil and uevrUtils.getDeveloperMode() ~= nil then
        isDeveloperMode = uevrUtils.getDeveloperMode()
    end

    if isDeveloperMode then
        pawnConfigDev = require("libs/config/pawn_config_dev")
        pawnConfigDev.init(paramManager)
		createConfigMonitor()
    else
    end
end

function M.setBodyMeshName(val)
	--bodyMeshName = "Pawn." .. val
	saveParameter("bodyMeshName", "Pawn." .. val)
end

function M.getBodyMesh()
	return uevrUtils.getObjectFromDescriptor(getParameter("bodyMeshName"))
end

function M.getArmsMesh()
	return uevrUtils.getObjectFromDescriptor(getParameter("armsMeshName"))
end

function M.getArmsAnimationMesh()
	return uevrUtils.getObjectFromDescriptor(getParameter("armsAnimationMeshName"))
end

function M.setBodyMeshFOVFixID(val)
	--bodyMeshFOVFixID = val
	saveParameter("bodyMeshFOVFixID", val)
end
function M.setArmsMeshFOVFixID(val)
	--armsMeshFOVFixID = val
	saveParameter("armsMeshFOVFixID", val)
end


function M.hideBodyMesh(val)
	-- syncMeshVisibilityStates(val, M.getBodyMesh())
	-- doHideBodyMesh(val)
	saveParameter("hidePawnBodyMesh", val)
end

function M.hideAnimationArms(val)
	-- syncMeshVisibilityStates(val, M.getArmsAnimationMesh())
	-- doHideAnimationArms(val)
	saveParameter("hidePawnArmsAnimationMesh", val)
end

function M.hideArms(val)
	-- syncMeshVisibilityStates(val, M.getArmsMesh())
	-- doHideArms(val)
	saveParameter("hidePawnArmsMesh", val)
end

function M.hideArmsBones(val)
	--hidePawnArmsBones = val
	saveParameter("hidePawnArmsBones", val)
	--doHideArmsBones(val)
end

local function executeIsArmBonesHiddenCallback(...)
	return uevrUtils.executeUEVRCallbacksWithPriorityBooleanResult("is_arms_bones_hidden", table.unpack({...}))
end
function M.registerIsArmBonesHiddenCallback(func)
	uevrUtils.registerUEVRCallback("is_arms_bones_hidden", func)
end

local function executeIsPawnBodyHiddenCallback(...)
	return uevrUtils.executeUEVRCallbacksWithPriorityBooleanResult("is_pawn_body_hidden", table.unpack({...}))
end
function M.registerIsPawnBodyHiddenCallback(func)
	uevrUtils.registerUEVRCallback("is_pawn_body_hidden", func)
end

local function executeIsPawnArmsHiddenCallback(...)
	return uevrUtils.executeUEVRCallbacksWithPriorityBooleanResult("is_pawn_arms_hidden", table.unpack({...}))
end
function M.registerIsPawnArmsHiddenCallback(func)
	uevrUtils.registerUEVRCallback("is_pawn_arms_hidden", func)
end

local function executeIsPawnAnimationArmsHiddenCallback(...)
	return uevrUtils.executeUEVRCallbacksWithPriorityBooleanResult("is_pawn_animation_arms_hidden", table.unpack({...}))
end
function M.registerIsPawnAnimationArmsHiddenCallback(func)
	uevrUtils.registerUEVRCallback("is_pawn_animation_arms_hidden", func)
end

local pawnState = {}
function M.setCurrentProfile(profileID)
	pawnState = {}
	paramManager:setActiveProfile(profileID)
	--saveParameter({"_profileState", "currentEditingProfile"}, profileID)
	--uevrUtils.executeUEVRCallbacks("on_pawn_config_param_change", {"_profileState", "currentEditingProfile"}, profileID, false, true)
end

function M.setCurrentProfileByLabel(profileLabel)
	local profileIDs, profileNames = paramManager:getProfiles()
	for i, name in ipairs(profileNames) do
		if name == profileLabel then
			M.setCurrentProfile(profileIDs[i])
			return
		end
	end
end

uevrUtils.setInterval(100, function()
	if uevrUtils.getValid(pawn) == nil then return end
	local isHidden, priority = executeIsArmBonesHiddenCallback()
	if isHidden == nil then isHidden = getParameter("hidePawnArmsBones") end
	if pawnState.hideArmsBones ~= isHidden then
		doHideArmsBones(isHidden)
		pawnState.hideArmsBones = isHidden
	end

	isHidden, priority = executeIsPawnAnimationArmsHiddenCallback()
	if isHidden == nil then isHidden = getParameter("hideAnimationArms") end
	if pawnState.hideAnimationArms ~= isHidden then
		doHideAnimationArms(isHidden)
		pawnState.hideAnimationArms = isHidden
	end

	isHidden, priority = executeIsPawnBodyHiddenCallback()
	if isHidden == nil then isHidden = getParameter("hidePawnBodyMesh") end
	if pawnState.hideBodyMesh ~= isHidden then
		doHideBodyMesh(isHidden)
		pawnState.hideBodyMesh = isHidden
	end

	isHidden, priority = executeIsPawnArmsHiddenCallback()
	if isHidden == nil then isHidden = getParameter("hidePawnArmsMesh") end
	if pawnState.hideArmsMesh ~= isHidden then
		doHideArms(isHidden)
		pawnState.hideArmsMesh = isHidden
	end

end)

uevrUtils.setInterval(2000, function()
	fixFOV()
end)

uevrUtils.registerPreLevelChangeCallback(function(level)
	pawnState = {}
end)

--if using Visibility or HiddenInGame to hide meshes, there's a very good chance the game will override
--our settings at some point, so we have to keep reapplying them to ensure they stay hidden. 
--The "render in pass" are less likely to cause issues so we dont waste time with those for now.
--Could make this an adiitional setting within the visibility settings for whether to use polling or not
uevrUtils.setInterval(300, function()
	if getParameter("hideSettingsVisibility") == true or getParameter("hideSettingsHiddenInGame") == true then
		pawnState.hideArmsMesh = nil
		pawnState.hideAnimationArms = nil
		pawnState.hideBodyMesh = nil
	end
end)


return M



-- local armsMesh = pawnModule.getArmsMesh()
-- if armsMesh ~= nil then
	-- print("IsAnyMontagePlaying",armsMesh.AnimScriptInstance:IsAnyMontagePlaying())
	-- print("AnimToPlay",armsMesh.AnimationData.AnimToPlay)
	-- print("GetAnimationMode",armsMesh:GetAnimationMode())
	-- print("IsPlaying",armsMesh:IsPlaying())
	-- --print("IsAnyMontagePlaying2",armsMesh["As ABP PLayer Character Hands"]:IsAnyMontagePlaying())
	-- local component = uevrUtils.find_first_instance("AnimBlueprintGeneratedClass /Game/Development/Characters/PlayerCharacterHands/ABP_PLayerCharacterHands.ABP_PLayerCharacterHands_C", true)
	-- print(component:IsAnyMontagePlaying())
-- end
-- local armsMesh = pawn.FPHandsMesh
-- if armsMesh ~= nil then
	-- print("IsAnyMontagePlaying",armsMesh.AnimScriptInstance:IsAnyMontagePlaying())
	-- print("AnimToPlay",armsMesh.AnimationData.AnimToPlay)
	-- print("GetAnimationMode",armsMesh:GetAnimationMode())
	-- print("IsPlaying",armsMesh:IsPlaying())
	-- --print("IsAnyMontagePlaying2",armsMesh["As ABP PLayer Character Hands"]:IsAnyMontagePlaying())
	-- local component = uevrUtils.find_first_instance("AnimBlueprintGeneratedClass /Game/Development/Characters/PlayerCharacterHands/ABP_PLayerCharacterHands.ABP_PLayerCharacterHands_C", true)
	-- print(component:IsAnyMontagePlaying())
-- end
