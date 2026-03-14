local uevrUtils = require("libs/uevr_utils")
local configui = require("libs/configui")

local M = {}

local configFileName = "dev/pawn_config_dev"
local configTabLabel = "Pawn Dev Config"
local widgetPrefix = "uevr_pawn_"

local configDefaults = {}
local paramManager = nil

local pawnMeshList = {}
local boneList = {}
local includeChildrenInMeshList = false

local currentLogLevel = LogLevel.Error
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
	if logLevel == nil then logLevel = LogLevel.Debug end
	if logLevel <= currentLogLevel then
		uevrUtils.print("[pawn config dev] " .. text, logLevel)
	end
end

local helpText = "This module allows you to configure the pawn body and arms meshes. You can hide/show the meshes in order to help locate them, select different meshes if your game has multiple meshes, and hide the arm bones if they are visible using the arms mesh. If your game has a separate mesh for first person arms animation (e.g. when using weapons), you can also configure that mesh separately. If your game uses the same mesh for everything, then just select that mesh in each dropdown box"

local function getConfigWidgets(m_paramManager)
    return spliceableInlineArray{
		expandArray(m_paramManager.getProfilePreConfigurationWidgets, widgetPrefix),
		{
			widgetType = "tree_node",
			id = widgetPrefix .. "body",
			initialOpen = true,
			label = "Pawn Body"
		},
			{
				widgetType = "combo",
				id = widgetPrefix .. "pawnBodyMeshList",
				label = "Mesh",
				selections = {"None"},
				initialValue = 1,
	--			width = 400
			},
			{ widgetType = "same_line" },
			{
				widgetType = "checkbox",
				id = widgetPrefix .. "hidePawnBodyMesh",
				label = "Hide",
				initialValue = configDefaults["hidePawnBodyMesh"] or false
			},
			{
				widgetType = "input_text",
				id = widgetPrefix .. "selectedPawnBodyMesh",
				label = "Name",
				initialValue = "",
				isHidden = true
			},
			{
				widgetType = "input_text",
				id = widgetPrefix .. "pawnBodyFOVFix",
				label = "FOV Fix ID",
				initialValue = configDefaults["bodyMeshFOVFixID"] or "",
				isHidden = false
			},

		{
			widgetType = "tree_pop"
		},
		{
			widgetType = "tree_node",
			id = widgetPrefix .. "arms",
			initialOpen = true,
			label = "Pawn Arms"
		},
			{
				widgetType = "combo",
				id = widgetPrefix .. "pawnArmsMeshList",
				label = "Mesh",
				selections = {"None"},
				initialValue = 1,
	--			width = 400
			},
			{ widgetType = "same_line" },
			{
				widgetType = "checkbox",
				id = widgetPrefix .. "hidePawnArmsMesh",
				label = "Hide",
				initialValue = configDefaults["hidePawnArmsMesh"] or false
			},
			{
				widgetType = "input_text",
				id = widgetPrefix .. "selectedPawnArmsMesh",
				label = "Name",
				initialValue = "",
				isHidden = true
			},
			{
				widgetType = "combo",
				id = widgetPrefix .. "pawnUpperArmLeft",
				label = "Left Upper Arm Bone",
				selections = {"None"},
				initialValue = 1
			},
			{
				widgetType = "combo",
				id = widgetPrefix .. "pawnUpperArmRight",
				label = "Right Upper Arm Bone",
				selections = {"None"},
				initialValue = 1
			},
			{
				widgetType = "checkbox",
				id = widgetPrefix .. "hidePawnArmsBones",
				label = "Hide Arm Bones",
				initialValue = configDefaults["hidePawnArmsBones"] or false
			},
			{
				widgetType = "input_text",
				id = widgetPrefix .. "pawnArmsFOVFix",
				label = "FOV Fix ID",
				initialValue = configDefaults["armsMeshFOVFixID"] or "",
				isHidden = false
			},
		{
			widgetType = "tree_pop"
		},
		{
			widgetType = "tree_node",
			id = widgetPrefix .. "arms_animation",
			initialOpen = true,
			label = "Pawn Arms Animation"
		},
			{
				widgetType = "combo",
				id = widgetPrefix .. "pawnArmsAnimationMeshList",
				label = "Mesh",
				selections = {"None"},
				initialValue = 1,
	--			width = 400
			},
			{ widgetType = "same_line" },
			{
				widgetType = "checkbox",
				id = widgetPrefix .. "hidePawnArmsAnimationMesh",
				label = "Hide",
				initialValue = configDefaults["hideAnimationArms"] or false
			},
			{
				widgetType = "input_text",
				id = widgetPrefix .. "selectedPawnArmsAnimationMesh",
				label = "Name",
				initialValue = "",
				isHidden = true
			},
		{
			widgetType = "tree_pop"
		},
		{ widgetType = "new_line" },
		expandArray(m_paramManager.getProfilePostConfigurationWidgets, widgetPrefix),
		{ widgetType = "new_line" },
		{
			widgetType = "tree_node",
			id = widgetPrefix .. "help_tree",
			initialOpen = true,
			label = "Help"
		},
			{
				widgetType = "text",
				id = widgetPrefix .. "help",
				label = helpText,
				wrapped = true
			},
		{
			widgetType = "tree_pop"
		},
	}
end

local function updateSetting(key, value)
    uevrUtils.executeUEVRCallbacks("on_pawn_config_param_change", key, value)
end

local function setPawnUpperArmLeft(value)
	--pawnUpperArmLeft = boneList[value]
    updateSetting("pawnUpperArmLeft", boneList[value])
end

local function setPawnUpperArmRight(value)
	--pawnUpperArmRight = boneList[value]
    updateSetting("pawnUpperArmRight", boneList[value])
end

local function getArmsMesh()
	return uevrUtils.getObjectFromDescriptor(configui.getValue(widgetPrefix .. "selectedPawnArmsMesh"))
end

local function setBoneNames()
	local mesh = getArmsMesh()
	if mesh ~= nil then
		boneList = uevrUtils.getBoneNames(mesh)
		if #boneList == 0 then return end
		configui.setSelections(widgetPrefix .. "pawnUpperArmLeft", boneList)
		configui.setSelections(widgetPrefix .. "pawnUpperArmRight", boneList)
	end
	local currentBoneIndex = configui.getValue(widgetPrefix .. "pawnUpperArmLeft")
	if currentBoneIndex ~= nil and currentBoneIndex > 1 then
		setPawnUpperArmLeft(currentBoneIndex)
	end
	currentBoneIndex = configui.getValue(widgetPrefix .. "pawnUpperArmRight")
	if currentBoneIndex ~= nil and  currentBoneIndex > 1 then
		setPawnUpperArmRight(currentBoneIndex)
	end
end

local function updateMeshUI(pawnMeshList, listName, selectedName, defaultValue)
	configui.setSelections(widgetPrefix .. listName, pawnMeshList)

	local selectedPawnBodyMesh = configui.getValue(widgetPrefix .. selectedName)
	if selectedPawnBodyMesh == nil or selectedPawnBodyMesh == "" then
		selectedPawnBodyMesh = defaultValue
	end

	for i = 1, #pawnMeshList do
		if pawnMeshList[i] == selectedPawnBodyMesh then
			configui.setValue(widgetPrefix .. listName, i)
			break
		end
	end

end

local function setPawnMeshList()
	M.print("Setting pawn mesh list", LogLevel.Debug)
	pawnMeshList = uevrUtils.getObjectPropertyDescriptors(pawn, "Pawn", "Class /Script/Engine.SkeletalMeshComponent", includeChildrenInMeshList)
	M.print("Found " .. #pawnMeshList .. " meshes", LogLevel.Debug)
	updateMeshUI(pawnMeshList, "pawnBodyMeshList", "selectedPawnBodyMesh", configDefaults["bodyMeshName"])
	updateMeshUI(pawnMeshList, "pawnArmsMeshList", "selectedPawnArmsMesh", configDefaults["armsMeshName"])
	updateMeshUI(pawnMeshList, "pawnArmsAnimationMeshList", "selectedPawnArmsAnimationMesh", configDefaults["armsAnimationMeshName"])
end

--if the pawn isnt ready then keep checking until it is
local function loadPawnProperties()
	if uevrUtils.getValid(pawn) == nil then
		delay(1000, loadPawnProperties)
		return
	end
	setPawnMeshList()
	setBoneNames()
end


configui.onUpdate(widgetPrefix .. "pawnBodyMeshList", function(value)
	configui.setValue(widgetPrefix .. "selectedPawnBodyMesh", pawnMeshList[value])
end)

configui.onCreateOrUpdate(widgetPrefix .. "selectedPawnBodyMesh", function(value)
	if value ~= "" then
		--bodyMeshName = value
        updateSetting("bodyMeshName", value)
	end
end)

configui.onUpdate(widgetPrefix .. "pawnArmsMeshList", function(value)
	configui.setValue(widgetPrefix .. "selectedPawnArmsMesh", pawnMeshList[value])
end)

configui.onCreateOrUpdate(widgetPrefix .. "selectedPawnArmsMesh", function(value)
	if value ~= "" then
		--armsMeshName = value
        updateSetting("armsMeshName", value)
		setBoneNames()
	end
end)

configui.onUpdate(widgetPrefix .. "pawnArmsAnimationMeshList", function(value)
	configui.setValue(widgetPrefix .. "selectedPawnArmsAnimationMesh", pawnMeshList[value])
end)

configui.onCreateOrUpdate(widgetPrefix .. "selectedPawnArmsAnimationMesh", function(value)
	if value ~= "" then
		--armsAnimationMeshName = value
        updateSetting("armsAnimationMeshName", value)
	end
end)

configui.onCreateOrUpdate(widgetPrefix .. "hidePawnBodyMesh", function(value)
	--M.hideBodyMesh(value)
    updateSetting("hidePawnBodyMesh", value)
end)

configui.onCreateOrUpdate(widgetPrefix .. "hidePawnArmsMesh", function(value)
	--M.hideArms(value)
    updateSetting("hidePawnArmsMesh", value)
end)

configui.onCreateOrUpdate(widgetPrefix .. "hidePawnArmsBones", function(value)
    updateSetting("hidePawnArmsBones", value)
	--M.hideArmsBones(value)
end)

configui.onCreateOrUpdate(widgetPrefix .. "hidePawnArmsAnimationMesh", function(value)
	--M.hideAnimationArms(value)
    updateSetting("hideAnimationArms", value)
end)

configui.onCreateOrUpdate(widgetPrefix .. "pawnUpperArmRight", function(value)
	setPawnUpperArmRight(value)
end)

configui.onCreateOrUpdate(widgetPrefix .. "pawnUpperArmLeft", function(value)
	setPawnUpperArmLeft(value)
end)

configui.onCreateOrUpdate(widgetPrefix .. "pawnBodyFOVFix", function(value)
    updateSetting("bodyMeshFOVFixID", value)
	--M.setBodyMeshFOVFixID(value)
end)

configui.onCreateOrUpdate(widgetPrefix .. "pawnArmsFOVFix", function(value)
	--M.setArmsMeshFOVFixID(value)
    updateSetting("armsMeshFOVFixID", value)
end)

local createDevMonitor = doOnce(function()
	uevrUtils.registerLevelChangeCallback(function(level)
		loadPawnProperties()
	end)
end, Once.EVER)

function M.getConfigurationWidgets(options)
	return configui.applyOptionsToConfigWidgets(getConfigWidgets(paramManager), options)
end

function M.showConfiguration(saveFileName, options)
	configui.createConfigPanel(configTabLabel, saveFileName, spliceableInlineArray{expandArray(M.getConfigurationWidgets, options)})
end

local function setUIValue(key, value)
	local bonesChangd = false
	if key == "pawnUpperArmLeft" then
		configui.setValue(widgetPrefix .. "pawnUpperArmLeft", uevrUtils.indexOf(boneList, value) or 1, true)
	elseif key == "pawnUpperArmRight" then
		configui.setValue(widgetPrefix .. "pawnUpperArmRight", uevrUtils.indexOf(boneList, value) or 1, true)
	elseif key == "bodyMeshName" then
		configui.setValue(widgetPrefix .. "selectedPawnBodyMesh", value, true)
		configui.setValue(widgetPrefix .. "pawnBodyMeshList", uevrUtils.indexOf(pawnMeshList, value) or 1, true)
	elseif key == "armsMeshName" then
		configui.setValue(widgetPrefix .. "selectedPawnArmsMesh", value, true)
		configui.setValue(widgetPrefix .. "pawnArmsMeshList", uevrUtils.indexOf(pawnMeshList, value) or 1, true)
		bonesChangd = true
		--setBoneNames()
	elseif key == "armsAnimationMeshName" then
		configui.setValue(widgetPrefix .. "selectedPawnArmsAnimationMesh", value, true)
		configui.setValue(widgetPrefix .. "pawnArmsAnimationMeshList", uevrUtils.indexOf(pawnMeshList, value) or 1, true)
	elseif key == "hideAnimationArms" then
		configui.setValue(widgetPrefix .. "hidePawnArmsAnimationMesh", value, true)
	elseif key == "bodyMeshFOVFixID" then
		configui.setValue(widgetPrefix .. "pawnBodyFOVFix", value, true)
	elseif key == "armsMeshFOVFixID" then
		configui.setValue(widgetPrefix .. "pawnArmsFOVFix", value, true)
	else
		configui.setValue(widgetPrefix .. key, value, true)
	end
	return bonesChangd
end

local function updateUI(params)
	local bonesChanged = false
	for key, value in pairs(params) do
		if setUIValue(key, value) then bonesChanged = true end
	end
	if bonesChanged then
		setBoneNames()
	end
end

function M.init(m_paramManager)
    configDefaults = m_paramManager and m_paramManager:getAll() or {}
	paramManager = m_paramManager
    createDevMonitor()
    M.showConfiguration(configFileName)
	loadPawnProperties()

	paramManager:initProfileHandler(widgetPrefix, function(profileParams)
		if updateUI(profileParams) then
			setBoneNames()
		end
	end)
end

uevrUtils.registerUEVRCallback("on_pawn_config_param_change", function(key, value)
	setUIValue(key, value)
end)


return M