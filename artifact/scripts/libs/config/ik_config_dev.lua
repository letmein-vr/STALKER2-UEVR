local uevrUtils = require('libs/uevr_utils')
local configui = require('libs/configui')

local json = json

local M = {}

M.SolverType = {
    TWO_BONE = 1,
    ROTATION_ONLY = 2,
}

M.ControllerType = {
    LEFT_CONTROLLER = 0,
    RIGHT_CONTROLLER = 1,
}

local configFileName = "dev/ik_config_dev"
local configTabLabel = "IK Dev Config"
local widgetPrefix = "uevr_ik_"

local paramManager = nil
local rigDefaults = {
    mesh = "",
	mesh_location_offset = uevrUtils.vector(0,0,0),
	mesh_rotation_offset = uevrUtils.rotator(0,0,0),
	animation_mesh = "",
	animation_location_offset = uevrUtils.vector(0,0,0),
	animation_rotation_offset = uevrUtils.rotator(0,0,0),
	show_debug_meshes = false,
}
local solverDefaults = {
	label = "",
	active = false,
	solver_type = M.SolverType.TWO_BONE,
    end_bone = "",
	joint_bone = "",
	start_bone = "",
    end_control_type = M.ControllerType.RIGHT_CONTROLLER,
    end_bone_offset = uevrUtils.vector(0,0,0),
    end_bone_rotation = uevrUtils.rotator(0,0,0),
    allow_wrist_affects_elbow = false,
    allow_stretch = false,
    start_stretch_ratio = 0.0,
    max_stretch_scale = 0.0,
    wrist_bone = "",
    twist_bones = {},
    --invert_forearm_roll = false,
	sort_order = 0,
	smoothing = 0,
    wrist_twist_influence = 0.35,
    wrist_twist_max = 75.0,
}

local meshList = {}
local animationMeshList = {}
local boneNames = {}
local solverIds = {}
local selectedSolverId = nil
local solverNames = {}

local helpText = "Developer IK configuration. Profiles are rigs; each rig has mesh/animation settings plus nested solvers."

local function getConfigWidgets(m_paramManager)
    local hideLabels = true
	return spliceableInlineArray{
		expandArray(m_paramManager.getProfilePreConfigurationWidgets, widgetPrefix),
		{
			widgetType = "tree_node",
			id = widgetPrefix .. "ik_tree",
			initialOpen = true,
			label = "Rig Settings"
		},
            {
                widgetType = "input_text",
                id = widgetPrefix .. "rig_label",
                label = "Label",
                initialValue = "",
                width = 300,
                isHidden = true
            },
            {
                widgetType = "combo",
                id = widgetPrefix .. "mesh_combo",
                label = "Mesh",
                selections = {"None"},
                initialValue = 1,
                width = 263
            },
            { widgetType = "same_line" },
            {
                widgetType = "checkbox",
                id = widgetPrefix .. "mesh_combo_show_children",
                label = "Show Children",
                initialValue = false
            },
            {
                widgetType = "input_text",
                id = widgetPrefix .. "mesh",
                label = "Mesh",
                initialValue = "",
                isHidden = hideLabels
            },
            {
                widgetType = "drag_float3",
                id = widgetPrefix .. "mesh_location_offset",
                label = "Location",
                speed = 0.1,
                range = {-500, 500},
                initialValue = {0,0,0}
            },
            {
                widgetType = "drag_float3",
                id = widgetPrefix .. "mesh_rotation_offset",
                label = "Rotation",
                speed = 1,
                range = {-360, 360},
                initialValue = {0,0,0}
            },
            {
                widgetType = "checkbox",
                id = widgetPrefix .. "show_debug_meshes",
                label = "Show Debug Meshes",
                initialValue = false
            },
            {
                widgetType = "tree_node",
                id = widgetPrefix .. "animation_tree",
                initialOpen = false,
                label = "Animation"
            },
                {
                    widgetType = "combo",
                    id = widgetPrefix .. "animation_mesh_combo",
                    label = "Animation Mesh",
                    selections = {"None"},
                    initialValue = 1,
                    width = 263
                },
                { widgetType = "same_line" },
                {
                    widgetType = "checkbox",
                    id = widgetPrefix .. "animation_mesh_combo_show_children",
                    label = "Show Children",
                    initialValue = false
                },
                {
                    widgetType = "drag_float3",
                    id = widgetPrefix .. "animation_location_offset",
                    label = "Animation Location",
                    speed = 0.1,
                    range = {-500, 500},
                    initialValue = {0,0,0}
                },
                {
                    widgetType = "drag_float3",
                    id = widgetPrefix .. "animation_rotation_offset",
                    label = "Animation Rotation",
                    speed = 1,
                    range = {-360, 360},
                    initialValue = {0,0,0}
                },
            { widgetType = "tree_pop" },
        	{ widgetType = "begin_group", id =  widgetPrefix .. "solvers_group", isHidden = false },
				{
					widgetType = "tree_node",
					id = widgetPrefix .. "solvers_tree",
					initialOpen = true,
					label = "Solvers"
				},
					{
						widgetType = "combo",
						id = widgetPrefix .. "solver_select",
						label = "Solver",
						selections = {"None"},
						initialValue = 1,
						width = 150
					},
					{ widgetType = "same_line" },
					{
						widgetType = "button",
						id = widgetPrefix .. "solver_new",
						label = "New"
					},
					{ widgetType = "same_line" },
					{
						widgetType = "button",
						id = widgetPrefix .. "solver_duplicate",
						label = "Duplicate"
					},
					{ widgetType = "same_line" },
					{
						widgetType = "button",
						id = widgetPrefix .. "solver_delete",
						label = "Delete"
					},
					{ widgetType = "same_line" },
					{
						widgetType = "button",
						id = widgetPrefix .. "solver_move_up",
						label = "Move Up"
					},
					{ widgetType = "same_line" },
					{
						widgetType = "button",
						id = widgetPrefix .. "solver_move_down",
						label = "Move Down"
					},
        			{ widgetType = "begin_group", id =  widgetPrefix .. "solver_group", isHidden = false },
						{
							widgetType = "checkbox",
							id = widgetPrefix .. "active",
							label = "Active",
							initialValue = false
						},
						{
							widgetType = "input_text",
							id = widgetPrefix .. "label",
							label = "Solver Name",
							initialValue = "",
							isHidden = false
						},
						{
							widgetType = "combo",
							id = widgetPrefix .. "solver_type",
							label = "Solver Type",
							selections = {"Two Bone", "Rotation Only"},
							initialValue = 1,
						},
						{
							widgetType = "combo",
							id = widgetPrefix .. "end_control_type",
							label = "Hand",
							selections = {"Left", "Right"},
							initialValue = 2,
						},
						{
							widgetType = "combo",
							id = widgetPrefix .. "end_bone_combo",
							label = "Hand Bone",
							selections = {"None"},
							initialValue = 1,
						},
						{
							widgetType = "input_text",
							id = widgetPrefix .. "end_bone",
							label = "Hand Bone",
							initialValue = "",
							isHidden = hideLabels
						},
						{
							widgetType = "drag_float3",
							id = widgetPrefix .. "end_bone_offset",
							label = "Hand Position",
							speed = 0.1,
							range = {-100, 100},
							initialValue = {0,0,0}
						},
						{
							widgetType = "drag_float3",
							id = widgetPrefix .. "end_bone_rotation",
							label = "Hand Rotation",
							speed = 1,
							range = {-360, 360},
							initialValue = {0,0,0}
						},
						{
							widgetType = "combo",
							id = widgetPrefix .. "joint_bone_combo",
							label = "Forearm Bone",
							selections = {"None"},
							initialValue = 1,
						},
						{
							widgetType = "input_text",
							id = widgetPrefix .. "joint_bone",
							label = "Forearm Bone",
							initialValue = "",
							isHidden = hideLabels
						},
						{
							widgetType = "combo",
							id = widgetPrefix .. "start_bone_combo",
							label = "Upper Arm Bone",
							selections = {"None"},
							initialValue = 1,
						},
						{
							widgetType = "input_text",
							id = widgetPrefix .. "start_bone",
							label = "Upper Arm Bone",
							initialValue = "",
							isHidden = hideLabels
						},
						{
							widgetType = "combo",
							id = widgetPrefix .. "wrist_bone_combo",
							label = "Wrist Bone",
							selections = {"None"},
							initialValue = 1,
						},
						{
							widgetType = "input_text",
							id = widgetPrefix .. "wrist_bone",
							label = "Wrist Bone",
							initialValue = "",
							width = 300,
							isHidden = hideLabels
						},
						{
							widgetType = "slider_float",
							id = widgetPrefix .. "smoothing",
							label = "Smoothing",
							speed = 0.01,
							range = {0, 1},
							initialValue = 0.0
						},
						-- {
						-- 	widgetType = "checkbox",
						-- 	id = widgetPrefix .. "invert_forearm_roll",
						-- 	label = "Invert Forearm Roll",
						-- 	initialValue = false
						-- },
						{
							widgetType = "checkbox",
							id = widgetPrefix .. "allow_wrist_affects_elbow",
							label = "Allow Wrist Affects Elbow",
							initialValue = false
						},
						{
							widgetType = "slider_float",
							id = widgetPrefix .. "wrist_twist_influence",
							label = "Wrist Twist Influence",
							speed = 0.01,
							range = {0, 1},
							initialValue = 0.35
						},
						{
							widgetType = "slider_float",
							id = widgetPrefix .. "wrist_twist_max",
							label = "Wrist Twist Max Degrees",
							speed = 1,
							range = {0, 120},
							initialValue = 75.0
						},
						{
							widgetType = "checkbox",
							id = widgetPrefix .. "allow_stretch",
							label = "Allow Stretch",
							initialValue = false
						},
						{
							widgetType = "slider_float",
							id = widgetPrefix .. "start_stretch_ratio",
							label = "Start Stretch Ratio",
							speed = 0.01,
							range = {0, 1},
							initialValue = 0.0
						},
						{
							widgetType = "slider_float",
							id = widgetPrefix .. "max_stretch_scale",
							label = "Max Stretch Scale",
							speed = 0.01,
							range = {0, 5},
							initialValue = 0.0
						},
						{
							widgetType = "slider_int",
							id = widgetPrefix .. "sort_order",
							label = "Sort Order",
							range = {0, 100},
							initialValue = 0,
							isHidden = true
						},
						{ widgetType = "new_line" },
						{
							widgetType = "text",
							id = widgetPrefix .. "twist_header",
							label = "Lower Arm Twist Bones",
							wrapped = false
						},
						{
							widgetType = "combo",
							id = widgetPrefix .. "lower_twist_bone_1_combo",
							label = "Bone 1",
							selections = {"None"},
							initialValue = 1,
							width = 170
						},
						{
							widgetType = "input_text",
							id = widgetPrefix .. "lower_twist_bone_1",
							label = "Bone 1",
							initialValue = "",
							width = 170,
							isHidden = hideLabels
						},
						{ widgetType = "same_line" },
						{
							widgetType = "slider_float",
							id = widgetPrefix .. "lower_twist_bone_roll_1",
							label = "Roll %",
							speed = 0.01,
							range = {0,1},
							initialValue = 0.0,
							width = 80
						},
						{ widgetType = "same_line" },
						{
							widgetType = "slider_float",
							id = widgetPrefix .. "lower_twist_bone_pitch_1",
							label = "Pitch %",
							speed = 0.01,
							range = {0,1},
							initialValue = 0.0,
							width = 80
						},
						{ widgetType = "same_line" },
						{
							widgetType = "slider_float",
							id = widgetPrefix .. "lower_twist_bone_yaw_1",
							label = "Yaw %",
							speed = 0.01,
							range = {0,1},
							initialValue = 0.0,
							width = 80
						},
						{
							widgetType = "combo",
							id = widgetPrefix .. "lower_twist_bone_2_combo",
							label = "Bone 2",
							selections = {"None"},
							initialValue = 1,
							width = 170
						},
						{
							widgetType = "input_text",
							id = widgetPrefix .. "lower_twist_bone_2",
							label = "Bone 2",
							initialValue = "",
							width = 170,
							isHidden = hideLabels
						},
						{ widgetType = "same_line" },
						{
							widgetType = "slider_float",
							id = widgetPrefix .. "lower_twist_bone_roll_2",
							label = "Roll %",
							speed = 0.01,
							range = {0,1},
							initialValue = 0.0,
							width = 80
						},
						{ widgetType = "same_line" },
						{
							widgetType = "slider_float",
							id = widgetPrefix .. "lower_twist_bone_pitch_2",
							label = "Pitch %",
							speed = 0.01,
							range = {0,1},
							initialValue = 0.0,
							width = 80
						},
						{ widgetType = "same_line" },
						{
							widgetType = "slider_float",
							id = widgetPrefix .. "lower_twist_bone_yaw_2",
							label = "Yaw %",
							speed = 0.01,
							range = {0,1},
							initialValue = 0.0,
							width = 80
						},
						{
							widgetType = "combo",
							id = widgetPrefix .. "lower_twist_bone_3_combo",
							label = "Bone 3",
							selections = {"None"},
							initialValue = 1,
							width = 170
						},
						{
							widgetType = "input_text",
							id = widgetPrefix .. "lower_twist_bone_3",
							label = "Bone 3",
							initialValue = "",
							width = 170,
							isHidden = hideLabels
						},
						{ widgetType = "same_line" },
						{
							widgetType = "slider_float",
							id = widgetPrefix .. "lower_twist_bone_roll_3",
							label = "Roll %",
							speed = 0.01,
							range = {0,1},
							initialValue = 0.0,
							width = 80
						},
						{ widgetType = "same_line" },
						{
							widgetType = "slider_float",
							id = widgetPrefix .. "lower_twist_bone_pitch_3",
							label = "Pitch %",
							speed = 0.01,
							range = {0,1},
							initialValue = 0.0,
							width = 80
						},
						{ widgetType = "same_line" },
						{
							widgetType = "slider_float",
							id = widgetPrefix .. "lower_twist_bone_yaw_3",
							label = "Yaw %",
							speed = 0.01,
							range = {0,1},
							initialValue = 0.0,
							width = 80
						},
					{ widgetType = "end_group" },
				{
					widgetType = "tree_pop"
				},
			{ widgetType = "end_group" },
		{
			widgetType = "tree_pop"
		},
		{ widgetType = "new_line" },
		expandArray(m_paramManager.getProfilePostConfigurationWidgets, widgetPrefix),
		{ widgetType = "new_line" },
		{
			widgetType = "tree_node",
			id = widgetPrefix .. "help_tree",
			initialOpen = false,
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

local function getActiveRigParams()
	return paramManager and paramManager:getAllActiveProfileParams() or {}
end

local function getSelectedSolverParams(rigParams)
	rigParams = rigParams or {}
	local solvers = rigParams.solvers or {}
	if selectedSolverId == nil or solvers[selectedSolverId] == nil then
		selectedSolverId = solverIds[1]
	end
	if selectedSolverId == nil then return {} end
	return solvers[selectedSolverId] or {}
end

local function setUIValue(key, value)
	configui.setValue(widgetPrefix .. key, value, true)
end

local function getActiveProfileId()
	return paramManager and paramManager:getActiveProfile() or nil
end

local function pmGet(key)
	if paramManager ~= nil and paramManager.get ~= nil then
		return paramManager:get(key)
	end
	return nil
end

local function pmSet(key, value, persist)
	if paramManager ~= nil and paramManager.set ~= nil then
		paramManager:set(key, value, persist)
	end
end

local function getActiveSolversTable(createIfMissing)
	local profileId = getActiveProfileId()
	if profileId == nil then return nil, nil end
	local solvers = pmGet({profileId, "solvers"})
	if solvers == nil and createIfMissing then
		solvers = {}
		pmSet({profileId, "solvers"}, solvers, true)
	end
	return solvers, profileId
end

local function newSolverId()
	return uevrUtils.guid()
end

local function normalizeSolverSortOrders(solvers, profileId)
	if solvers == nil or profileId == nil then return end
	local ids = {}
	for solverId, _ in pairs(solvers) do
		table.insert(ids, solverId)
	end
	table.sort(ids, function(a, b)
		local sa = solvers[a] or {}
		local sb = solvers[b] or {}
		local oa = sa.sort_order or 0
		local ob = sb.sort_order or 0
		if oa == ob then return tostring(a) < tostring(b) end
		return oa < ob
	end)
	for index, solverId in ipairs(ids) do
		pmSet({profileId, "solvers", solverId, "sort_order"}, index, true)
	end
end

local function resolveSelectedSolverId(selectionValue)
	if #solverIds == 0 then return nil end
	if type(selectionValue) == "number" then
		return solverIds[selectionValue]
	end
	if type(selectionValue) == "string" then
		for i, name in ipairs(solverNames) do
			if name == selectionValue then
				return solverIds[i]
			end
		end
	end
	return nil
end

local function updateSolverSelectionUI(rigParams)
	rigParams = rigParams or {}
	local solvers = rigParams.solvers or {}
	solverIds = {}
	solverNames = {}

	for solverId, solverParams in pairs(solvers) do
		table.insert(solverIds, solverId)
		local label = (solverParams and solverParams.label) or ""
		table.insert(solverNames, (label ~= "" and label or solverId))
	end

	table.sort(solverIds, function(a, b)
		local sa = solvers[a] or {}
		local sb = solvers[b] or {}
		local oa = sa.sort_order or 0
		local ob = sb.sort_order or 0
		if oa == ob then return tostring(a) < tostring(b) end
		return oa < ob
	end)

	solverNames = {}
	for _, solverId in ipairs(solverIds) do
		local solverParams = solvers[solverId] or {}
		local label = solverParams.label or ""
		table.insert(solverNames, (label ~= "" and label or solverId))
	end

	if #solverNames == 0 then
		solverNames = {"None"}
		selectedSolverId = nil
	end

	configui.setHidden(widgetPrefix .. "solver_group", selectedSolverId == nil)


	configui.setSelections(widgetPrefix .. "solver_select", solverNames)

	local selectedIndex = 1
	if selectedSolverId == nil then
		local currentSelection = configui.getValue(widgetPrefix .. "solver_select")
		selectedSolverId = resolveSelectedSolverId(currentSelection)
	end
	if selectedSolverId ~= nil then
		for i, solverId in ipairs(solverIds) do
			if solverId == selectedSolverId then
				selectedIndex = i
				break
			end
		end
	elseif #solverIds > 0 then
		selectedSolverId = solverIds[1]
		selectedIndex = 1
	end
	configui.setValue(widgetPrefix .. "solver_select", selectedIndex, true)
end

local function updateSetting(key, value)
	if key == "end_control_type" then
		value = value == 1 and M.ControllerType.LEFT_CONTROLLER or M.ControllerType.RIGHT_CONTROLLER
	end
	local profileId = getActiveProfileId()
	if profileId == nil then return end

	if key == "mesh" or key == "animation_mesh" or key == "animation_location_offset" or key == "animation_rotation_offset" or key == "mesh_location_offset" or key == "mesh_rotation_offset" or key == "show_debug_meshes" then
		pmSet({profileId, key}, value, true)
		uevrUtils.executeUEVRCallbacks("on_ik_config_param_change", key, value, true)
		return
	end

	if selectedSolverId ~= nil then
		pmSet({profileId, "solvers", selectedSolverId, key}, value, true)
		uevrUtils.executeUEVRCallbacks("on_ik_config_param_change", {"solvers", selectedSolverId, key}, value, true)
	end
end

local function updateUI(rigParams)
	rigParams = rigParams or {}
	updateSolverSelectionUI(rigParams)

	for key, value in pairs(rigDefaults) do
		local v = rigParams[key]
		if v == nil then v = value end
		setUIValue(key, v)
	end

	local solverParams = getSelectedSolverParams(rigParams)
	for key, value in pairs(solverDefaults) do
		if key == "twist_bones" then
			local twistValues = solverParams[key] or value or {}
			for i = 1,3 do
				local twistBone = twistValues[i] or {}
				setUIValue("lower_twist_bone_" .. i, twistBone.bone or "")
				setUIValue("lower_twist_bone_roll_" .. i, twistBone.fraction or twistBone.roll or 0.0)
				setUIValue("lower_twist_bone_pitch_" .. i, twistBone.pitch or 0.0)
				setUIValue("lower_twist_bone_yaw_" .. i, twistBone.yaw or 0.0)
			end
		elseif key == "end_control_type" then
			local current = solverParams[key]
			if current == nil then current = value end
			local selectedIndex = current == M.ControllerType.LEFT_CONTROLLER and 1 or 2
			configui.setValue(widgetPrefix .. key, selectedIndex, true)
		else
			local v = solverParams[key]
			if v == nil then v = value end
			setUIValue(key, v)
		end
	end
end

function M.getConfigurationWidgets(options)
	return configui.applyOptionsToConfigWidgets(getConfigWidgets(paramManager), options)
end

function M.showConfiguration(saveFileName, options)
	local configDefinition = {
		{
			panelLabel = configTabLabel,
			saveFile = saveFileName,
			layout = spliceableInlineArray{
				expandArray(M.getConfigurationWidgets, options)
			}
		}
	}
	for paramName, _ in pairs(rigDefaults) do
		configui.onUpdate(widgetPrefix .. paramName, function(value)
			updateSetting(paramName, value)
		end)
	end
	for paramName, _ in pairs(solverDefaults) do
		if paramName ~= "twist_bones" then
			configui.onUpdate(widgetPrefix .. paramName, function(value)
				updateSetting(paramName, value)
			end)
		end
	end
	configui.create(configDefinition)

end

local function setSelectedMesh(currentMeshName, meshID, noCallbacks)
	local selectedIndex = 1
	for i = 1, #meshList do
		if meshList[i] == currentMeshName then
			selectedIndex = i
			break
		end
	end
	configui.setValue(widgetPrefix .. meshID, selectedIndex, noCallbacks)
end

local function setMeshList(currentMeshName, noCallbacks)
    meshList = uevrUtils.getObjectPropertyDescriptors(pawn, "Pawn", "Class /Script/Engine.SkeletalMeshComponent", configui.getValue(widgetPrefix .. "mesh_combo_show_children"))
	table.insert(meshList, 1, "None")
	table.insert(meshList, "Custom")

	configui.setSelections(widgetPrefix .. "mesh_combo", meshList)
	setSelectedMesh(currentMeshName, "mesh_combo", noCallbacks)

	configui.setHidden(widgetPrefix .. "solvers_group", configui.getValue(widgetPrefix .. "mesh_combo") == 1)
end

local function setAnimationMeshList(currentMeshName, noCallbacks)
    animationMeshList = uevrUtils.getObjectPropertyDescriptors(pawn, "Pawn", "Class /Script/Engine.SkeletalMeshComponent", configui.getValue(widgetPrefix .. "animation_mesh_combo_show_children"))
	table.insert(animationMeshList, 1, "None")
	table.insert(animationMeshList, "Custom")

	configui.setSelections(widgetPrefix .. "animation_mesh_combo", animationMeshList)
	setSelectedMesh(currentMeshName, "animation_mesh_combo", noCallbacks)
end

local function setSelectedBone(comboWidgetID, valueWidgetID)
    configui.setSelections(widgetPrefix .. comboWidgetID, boneNames)

    local currentBoneName = configui.getValue(widgetPrefix .. valueWidgetID)
    local selectedIndex = 1
    for i = 1, #boneNames do
        if boneNames[i] == currentBoneName then
            selectedIndex = i
            break
        end
    end
    configui.setValue(widgetPrefix .. comboWidgetID, selectedIndex, true)
end

local function setBoneList()
    boneNames = {}
    local currentMesh = configui.getValue(widgetPrefix .. "mesh")
    if currentMesh == "None" or currentMesh == "" then
        configui.setSelections(widgetPrefix .. "end_bone_combo", {"None"})
        configui.setValue(widgetPrefix .. "end_bone_combo", 1)
        return
    end
    local customMeshList = nil
    if currentMesh == "Custom" then
        if getCustomIKComponent == nil then
--TODO this function is getting called too early need to investigate how to recover
            print("Error: getCustomIKComponent function not defined for custom IK mesh retrieval")
            return
        end
        local activeProfileID = paramManager and paramManager:getActiveProfile() or ""
        local templates = getCustomIKComponent(activeProfileID)
		if type(templates) ~= "table" then
			templates = {{descriptor = templates}}
		end
		customMeshList = {}
		for i, template in ipairs(templates) do
			if template.instance ~= nil then
				table.insert(customMeshList, template.instance)
			else
				table.insert(customMeshList, uevrUtils.getObjectFromDescriptor(template.descriptor))
			end
		end

    else
        customMeshList = {uevrUtils.getObjectFromDescriptor(configui.getValue(widgetPrefix .. "mesh"))}
    end

	local mesh = nil
	if customMeshList ~= nil and #customMeshList > 0 then
		mesh = customMeshList[1]
	end
    if mesh ~= nil then
		boneNames = uevrUtils.getBoneNames(mesh)
        table.insert(boneNames, 1, "None")

        configui.setSelections(widgetPrefix .. "end_bone_combo", boneNames)
        configui.setSelections(widgetPrefix .. "joint_bone_combo", boneNames)
        configui.setSelections(widgetPrefix .. "start_bone_combo", boneNames)
        configui.setSelections(widgetPrefix .. "wrist_bone_combo", boneNames)
        configui.setSelections(widgetPrefix .. "lower_twist_bone_1_combo", boneNames)
        configui.setSelections(widgetPrefix .. "lower_twist_bone_2_combo", boneNames)
        configui.setSelections(widgetPrefix .. "lower_twist_bone_3_combo", boneNames)

        setSelectedBone("end_bone_combo", "end_bone")
        setSelectedBone("joint_bone_combo", "joint_bone")
        setSelectedBone("start_bone_combo", "start_bone")
        setSelectedBone("wrist_bone_combo", "wrist_bone")
        setSelectedBone("lower_twist_bone_1_combo", "lower_twist_bone_1")
        setSelectedBone("lower_twist_bone_2_combo", "lower_twist_bone_2")
        setSelectedBone("lower_twist_bone_3_combo", "lower_twist_bone_3")
	else
		--print("Error: Could not retrieve mesh for bone list population")
		--something is wrong (maybe it's too early in the load process) so try initializing again
		delay(2000, function()
			setMeshList(configui.getValue(widgetPrefix .. "mesh"), true)
			setAnimationMeshList(configui.getValue(widgetPrefix .. "animation_mesh"), true)
			setBoneList()
		end)

    end
end

configui.onUpdate(widgetPrefix .. "solver_select", function(value)
	selectedSolverId = resolveSelectedSolverId(value)
	updateUI(getActiveRigParams())
	setBoneList()
end)

-- configui.onCreate(widgetPrefix .. "solver_select", function()
-- 	configui.setHidden(widgetPrefix .. "solver_group", configui.getValue(widgetPrefix .. "solver_select") == 1)
-- end)

configui.onUpdate(widgetPrefix .. "solver_new", function()
	local solvers, profileId = getActiveSolversTable(true)
	if solvers == nil or profileId == nil then return end
	local solverId = newSolverId()
	local solver = uevrUtils.deepCopyTable(solverDefaults)
	solver.label = "New Solver"
	solver.sort_order = (#solverIds or 0) + 1
	solver.end_bone_offset =  uevrUtils.getNativeValue(solver.end_bone_offset)
	pmSet({profileId, "solvers", solverId}, solver, true)
	normalizeSolverSortOrders(pmGet({profileId, "solvers"}), profileId)
	selectedSolverId = solverId
	updateUI(getActiveRigParams())
	setBoneList()
end)

configui.onUpdate(widgetPrefix .. "solver_duplicate", function()
	if selectedSolverId == nil then return end
	local solvers, profileId = getActiveSolversTable(false)
	if solvers == nil or profileId == nil then return end
	local current = solvers[selectedSolverId]
	if current == nil then return end
	local solverId = newSolverId()
	local copy = uevrUtils.deepCopyTable(current)
	copy.label = ((copy.label and copy.label ~= "") and copy.label or "Solver") .. " Copy"
	copy.sort_order = (#solverIds or 0) + 1
	copy.end_bone_offset =  uevrUtils.getNativeValue(copy.end_bone_offset)
	pmSet({profileId, "solvers", solverId}, copy, true)
	normalizeSolverSortOrders(pmGet({profileId, "solvers"}), profileId)
	selectedSolverId = solverId
	updateUI(getActiveRigParams())
	setBoneList()
end)

configui.onUpdate(widgetPrefix .. "solver_delete", function()
	if selectedSolverId == nil then return end
	local solvers, profileId = getActiveSolversTable(false)
	if solvers == nil or profileId == nil then return end
	pmSet({profileId, "solvers", selectedSolverId}, nil, true)
	selectedSolverId = nil
	normalizeSolverSortOrders(pmGet({profileId, "solvers"}), profileId)
	updateUI(getActiveRigParams())
	setBoneList()
end)

local function moveSelectedSolver(delta)
	if selectedSolverId == nil then return end
	local solvers, profileId = getActiveSolversTable(false)
	if solvers == nil or profileId == nil then return end
	local idx = nil
	for i, id in ipairs(solverIds) do
		if id == selectedSolverId then
			idx = i
			break
		end
	end
	if idx == nil then return end
	local target = idx + delta
	if target < 1 or target > #solverIds then return end
	local aId = solverIds[idx]
	local bId = solverIds[target]
	local aOrder = (solvers[aId] and solvers[aId].sort_order) or idx
	local bOrder = (solvers[bId] and solvers[bId].sort_order) or target
	pmSet({profileId, "solvers", aId, "sort_order"}, bOrder, true)
	pmSet({profileId, "solvers", bId, "sort_order"}, aOrder, true)
	normalizeSolverSortOrders(pmGet({profileId, "solvers"}), profileId)
	updateUI(getActiveRigParams())
	setBoneList()
end

configui.onUpdate(widgetPrefix .. "solver_move_up", function()
	moveSelectedSolver(-1)
end)

configui.onUpdate(widgetPrefix .. "solver_move_down", function()
	moveSelectedSolver(1)
end)

configui.onCreateOrUpdate(widgetPrefix .. "mesh_combo_show_children", function(value)
    setMeshList(configui.getValue(widgetPrefix .. "mesh"), true)
end)

configui.onUpdate(widgetPrefix .. "mesh_combo", function(value)
    updateSetting("mesh", meshList[value] == "None" and "" or meshList[value])
	configui.setHidden(widgetPrefix .. "solvers_group", configui.getValue(widgetPrefix .. "mesh_combo") == 1)

    setBoneList()
end)

configui.onCreateOrUpdate(widgetPrefix .. "animation_mesh_combo_show_children", function(value)
    setAnimationMeshList(configui.getValue(widgetPrefix .. "animation_mesh"), true)
end)

configui.onUpdate(widgetPrefix .. "animation_mesh_combo", function(value)
    updateSetting("animation_mesh", animationMeshList[value] == "None" and "" or animationMeshList[value])
end)

configui.onUpdate(widgetPrefix .. "end_bone_combo", function(value)
    updateSetting("end_bone", boneNames[value] == "None" and "" or boneNames[value])
end)

configui.onUpdate(widgetPrefix .. "joint_bone_combo", function(value)
    updateSetting("joint_bone", boneNames[value] == "None" and "" or boneNames[value])
end)

configui.onUpdate(widgetPrefix .. "start_bone_combo", function(value)
	updateSetting("start_bone", boneNames[value] == "None" and "" or boneNames[value])
end)

configui.onUpdate(widgetPrefix .. "wrist_bone_combo", function(value)
    updateSetting("wrist_bone", boneNames[value] == "None" and "" or boneNames[value])
end)

configui.onUpdate(widgetPrefix .. "label", function(value)
	--change the label of the currently selected solver
	updateSolverSelectionUI(getActiveRigParams())
end)

configui.onCreateOrUpdate(widgetPrefix .. "allow_wrist_affects_elbow", function(value)
    configui.setHidden(widgetPrefix .. "wrist_twist_influence", not value)
    configui.setHidden(widgetPrefix .. "wrist_twist_max", not value)
end)

configui.onCreateOrUpdate(widgetPrefix .. "allow_stretch", function(value)
    configui.setHidden(widgetPrefix .. "start_stretch_ratio", not value)
    configui.setHidden(widgetPrefix .. "max_stretch_scale", not value)
end)

local function updateTwistBones()
    local twistBones = {}
    for i = 1,3 do
		local comboIndex = configui.getValue(widgetPrefix .. "lower_twist_bone_" .. i .. "_combo") or 1
		local boneName = boneNames[comboIndex]
		if boneName == nil then 
			print("Error: Invalid bone index selected for lower twist bone " .. i)
			return
		end
        local roll = configui.getValue(widgetPrefix .. "lower_twist_bone_roll_" .. i)
        local pitch = configui.getValue(widgetPrefix .. "lower_twist_bone_pitch_" .. i)
        local yaw = configui.getValue(widgetPrefix .. "lower_twist_bone_yaw_" .. i)
        if  boneName ~= "None" then
            table.insert(twistBones, {bone = boneName, roll = roll, pitch = pitch, yaw = yaw})
        end
    end
    updateSetting("twist_bones", twistBones)
end

configui.onUpdate(widgetPrefix .. "lower_twist_bone_1_combo", function(value)
    updateTwistBones()
end)
configui.onUpdate(widgetPrefix .. "lower_twist_bone_2_combo", function(value)
    updateTwistBones()
end)
configui.onUpdate(widgetPrefix .. "lower_twist_bone_3_combo", function(value)
    updateTwistBones()
end)

configui.onUpdate(widgetPrefix .. "lower_twist_bone_roll_1", function(value)
    updateTwistBones()
end)
configui.onUpdate(widgetPrefix .. "lower_twist_bone_roll_2", function(value)
    updateTwistBones()
end)
configui.onUpdate(widgetPrefix .. "lower_twist_bone_roll_3", function(value)
    updateTwistBones()
end)
configui.onUpdate(widgetPrefix .. "lower_twist_bone_pitch_1", function(value)
    updateTwistBones()
end)
configui.onUpdate(widgetPrefix .. "lower_twist_bone_pitch_2", function(value)
    updateTwistBones()
end)
configui.onUpdate(widgetPrefix .. "lower_twist_bone_pitch_3", function(value)
    updateTwistBones()
end)
configui.onUpdate(widgetPrefix .. "lower_twist_bone_yaw_1", function(value)
    updateTwistBones()
end)
configui.onUpdate(widgetPrefix .. "lower_twist_bone_yaw_2", function(value)
    updateTwistBones()
end)
configui.onUpdate(widgetPrefix .. "lower_twist_bone_yaw_3", function(value)
    updateTwistBones()
end)


function M.init(m_paramManager)
	--configDefaults = m_paramManager and m_paramManager:getAllActiveProfileParams() or {}
	paramManager = m_paramManager
    M.showConfiguration(configFileName)

	paramManager:initProfileHandler(widgetPrefix, function(rigParams)
		updateUI(rigParams)
		setMeshList((rigParams and rigParams["mesh"]) or "", true)
		setAnimationMeshList((rigParams and rigParams["animation_mesh"]) or "", true)
        setBoneList()
	end)

end

uevrUtils.registerUEVRCallback("on_ik_config_param_change", function(key, value)
	updateUI(getActiveRigParams())
	setBoneList()
end)

uevrUtils.registerLevelChangeCallback(function(level)
	local rigParams = getActiveRigParams()
	setMeshList((rigParams and rigParams["mesh"]) or "", true)
	setAnimationMeshList((rigParams and rigParams["animation_mesh"]) or "", true)
	setBoneList()
end)

return M

