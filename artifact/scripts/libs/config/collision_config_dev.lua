local uevrUtils = require("libs/uevr_utils")
local configui = require("libs/configui")
local paramModule = require("libs/core/params")

local M = {}

local configFileName = "dev/collision_config_dev"
local configTabLabel = "Collision Dev Config"
local widgetPrefix = "uevr_collision_"
local objectFinderPrefix = "object_finder_"

local configDefaults = {}
local paramManager = nil
local status = {}

local parameterDefaults = {
    active = false,
    channels = {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1},
    shape = 1,
    radius = 5.0,
    half_height = 20.0,
    extents = {10.0, 10.0, 10.0},
    position = {0.0, 0.0, 0.0},
    rotation = {0.0, 0.0, 0.0},
    scale = {1.0, 1.0, 1.0},
    collision_enabled = 1,
    collision_object_type = 1,
    visible = false,
    generate_overlap_events = true,
    attachTo = 2, -- 1 = left hand, 2 = right hand, 3 = head
    collision_detection_type = 1,
}

local currentLogLevel = LogLevel.Error
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
	if logLevel == nil then logLevel = LogLevel.Debug end
	if logLevel <= currentLogLevel then
		uevrUtils.print("[collision config] " .. text, logLevel)
	end
end

local helpText = "This module allows you to configure collisions"

local function getChannels(prefix, useBool)
    local widgets = {}
    for i = 1, #parameterDefaults.channels do
        local labelIndex = i - 1
        -- table.insert(widgets,
        --     {
        --         widgetType = "text",
        --         id = prefix .. "label_channel" .. i,
        --         label = "Channel " .. labelIndex .. (labelIndex < 10 and "  " or ""),
        --         wrapped = true
        --     }
        -- )
        -- table.insert(widgets,
        --     {
        --         widgetType = "same_line",
        --     }
        -- )
        if useBool then
            table.insert(widgets,
                {
                    widgetType = "combo",
                    id = prefix .. "bool_channel" .. i,
                    label = "  " ..COLLISION_OBJECT_TYPE_STRINGS[i],
                    selections = {"Off", "On"},
                    initialValue = 1,
                    width = 100
                }
            )
        else
            table.insert(widgets,
                {
                    widgetType = "combo",
                    id = prefix .. "channel" .. i,
                    label = "  " ..COLLISION_OBJECT_TYPE_STRINGS[i],
                    selections = COLLISION_RESPONSE_STRINGS,
                    initialValue = 1,
                    width = 100
                }
            )
        end
    end
    return widgets
end

local function getConfigWidgets(m_paramManager)
    return spliceableInlineArray{
		expandArray(m_paramManager.getProfilePreConfigurationWidgets, widgetPrefix, "Collider"),
		-- {
		-- 	widgetType = "tree_node",
		-- 	id = widgetPrefix .. "body",
		-- 	initialOpen = true,
		-- 	label = "Pawn Body"
		-- },
        { widgetType = "begin_group", id = widgetPrefix .. "collision_config_group", isHidden = false }, { widgetType = "indent", width = 10 }, { widgetType = "text", label = "Collider Configuration" }, { widgetType = "begin_rect", },
            {
                widgetType = "checkbox",
                id = widgetPrefix .. "active",
                label = "Active",
                initialValue = parameterDefaults["active"] or false
            },
            {
				widgetType = "combo",
				id = widgetPrefix .. "shape",
				label = "Collider Shape",
				selections = COLLISION_SHAPE_STRINGS,
				initialValue = parameterDefaults["shape"] or 1,
			},
            {
                widgetType = "drag_float",
                id = widgetPrefix .. "radius",
                label = "Radius",
                speed = 0.1,
                range = {0.1, 500},
                initialValue = parameterDefaults.radius
            },
            {
                widgetType = "drag_float",
                id = widgetPrefix .. "half_height",
                label = "Half Height",
                speed = 0.1,
                range = {0.1, 500},
                initialValue = parameterDefaults.half_height
            },
            {
                widgetType = "drag_float3",
                id = widgetPrefix .. "extents",
                label = "Extents",
                speed = 0.1,
                range = {-100, 100},
                initialValue = parameterDefaults.extents,
            },
			{
				widgetType = "combo",
				id = widgetPrefix .. "attachTo",
				label = "Attach To",
				selections = COLLISION_ATTACHMENT_STRINGS,
				initialValue = parameterDefaults["attachTo"] or 2,
			},
            {
                widgetType = "drag_float3",
                id = widgetPrefix .. "position",
                label = "Position",
                speed = 0.1,
                range = {-100, 100},
                initialValue = parameterDefaults.position,
            },
            {
                widgetType = "drag_float3",
                id = widgetPrefix .. "rotation",
                label = "Rotation",
                speed = 0.1,
                range = {-100, 100},
                initialValue = parameterDefaults.rotation,
            },
            -- {
            --     widgetType = "drag_float3",
            --     id = widgetPrefix .. "scale",
            --     label = "Scale",
            --     speed = 0.1,
            --     range = {-100, 100},
            --     initialValue = parameterDefaults.scale,
            -- },
            { widgetType = "begin_group", id = widgetPrefix .. "overlap_settings_group", isHidden = false },
                {
                    widgetType = "tree_node",
                    id = widgetPrefix .. "collision_response",
                    initialOpen = false,
                    label = "Overlap Detection Channels"
                },
                    { widgetType = "indent", width="10"},
                        {
                            widgetType = "button",
                            id = widgetPrefix .. "off_all_button",
                            label = "All Off",
                            size = {80,22}
                        },
                        {widgetType = "same_line"},
                        {
                            widgetType = "button",
                            id = widgetPrefix .. "on_all_button",
                            label = "All On",
                            size = {80,22}
                        },
                        expandArray(getChannels, widgetPrefix, true),
                    { widgetType = "unindent", width="10"},
                {
                    widgetType = "tree_pop"
                },
            { widgetType = "end_group", },
            { widgetType = "begin_group", id = widgetPrefix .. "collision_settings_group", isHidden = false },
                {
                    widgetType = "combo",
                    id = widgetPrefix .. "collision_enabled",
                    label = "Collision Enabled Type",
                    selections = COLLISION_ENABLED_STRINGS,
                    initialValue = parameterDefaults["collision_enabled"] or 2,
                },
                {
                    widgetType = "combo",
                    id = widgetPrefix .. "collision_object_type",
                    label = "Collision Object Type",
                    selections = COLLISION_OBJECT_TYPE_STRINGS,
                    initialValue = parameterDefaults["collision_object_type"] or 3,
                },
                {
                    widgetType = "tree_node",
                    id = widgetPrefix .. "collision_response",
                    initialOpen = false,
                    label = "Collision Response To Channels"
                },
                { widgetType = "indent", width="10"},
                    {
                        widgetType = "button",
                        id = widgetPrefix .. "ignore_all_button",
                        label = "Ignore All",
                        size = {80,22}
                    },
                    {widgetType = "same_line"},
                    {
                        widgetType = "button",
                        id = widgetPrefix .. "overlap_all_button",
                        label = "Overlap All",
                        size = {80,22}
                    },
                    {widgetType = "same_line"},
                    {
                        widgetType = "button",
                        id = widgetPrefix .. "block_all_button",
                        label = "Block All",
                        size = {80,22}
                    },
                    expandArray(getChannels, widgetPrefix),
                { widgetType = "unindent", width="10"},
                {
                    widgetType = "tree_pop"
                },
                {
                    widgetType = "combo",
                    id = widgetPrefix .. "collision_detection_type",
                    label = "Overlap Detection Type",
                    selections = COLLISION_DETECTION_TYPE_STRINGS,
                    initialValue = parameterDefaults["collision_detection_type"] or 1,
                },
                {
                    widgetType = "checkbox",
                    id = widgetPrefix .. "generate_overlap_events",
                    label = "Generate Overlap Events",
                    initialValue = parameterDefaults["generate_overlap_events"] or true
                },
            { widgetType = "end_group", },
            {
                widgetType = "tree_node",
                id = widgetPrefix .. "debug_options",
                initialOpen = true,
                label = "Debug Options"
            },
                {
                    widgetType = "checkbox",
                    id = widgetPrefix .. "visible",
                    label = "Show Debug Mesh",
                    initialValue = parameterDefaults["visible"] or true
                },
                {
                    widgetType = "checkbox",
                    id = widgetPrefix .. "show_overlapped_components",
                    label = "Show Overlapped Components",
                    initialValue = parameterDefaults["show_overlapped_components"] or true
                },
                {
                    widgetType = "input_text_multiline",
                    id = widgetPrefix .. "detected_components",
                    label = " ",
                    initialValue = "",
                    --size = {440, 180} -- optional, will default to full size without it
                },
            {
                widgetType = "tree_pop"
            },
        { widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 10 }, { widgetType = "end_group", },

		-- {
		-- 	widgetType = "tree_pop"
		-- },
		{ widgetType = "new_line" },
		expandArray(m_paramManager.getProfilePostConfigurationWidgets, widgetPrefix, "Collider"),
		{ widgetType = "new_line" },

		{
			widgetType = "tree_node",
			id = widgetPrefix .. objectFinderPrefix .. "tree",
			initialOpen = false,
			label = "Component Finder"
		},
            {
                widgetType = "tree_node",
                id = widgetPrefix .. objectFinderPrefix .. "description_tree",
                initialOpen = true,
                label = "How to use the Component Finder"
            },
                {
                    widgetType = "text",
                    id = widgetPrefix .. objectFinderPrefix .. "description",
                    label = "To use the Finder, enable a laser in 'Interaction Config Dev' and then check the 'Enable Object Finder' checkbox below. You can then point the laser at any component in the game and see and change the component's current collision settings. (Tip: attach the laser pointer to your left hand). Changes made to components are for testing only and do not persist between game sessions.",
                    wrapped = true
                },
            {
                widgetType = "tree_pop"
            },
            {
				widgetType = "checkbox",
				id = widgetPrefix .. objectFinderPrefix .. "enable",
				label = "Enable Object Finder",
				initialValue = false
			},
			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "Collision Info" }, { widgetType = "begin_rect", },
                {
                    widgetType = "text",
                    id = widgetPrefix .. objectFinderPrefix .. "name_label",
                    label = "Component Name",
                    wrapped = true
                },
                {widgetType = "same_line"},
                {
                    widgetType = "text",
                    id = widgetPrefix .. objectFinderPrefix .. "name",
                    label = "",
                    wrapped = true
                },
                {
                    widgetType = "text",
                    id = widgetPrefix .. objectFinderPrefix .. "class_label",
                    label = "Component Class",
                    wrapped = true
                },
                {widgetType = "same_line"},
                {
                    widgetType = "text",
                    id = widgetPrefix .. objectFinderPrefix .. "class",
                    label = "",
                    wrapped = true
                },
                {
                    widgetType = "text",
                    id = widgetPrefix .. objectFinderPrefix .. "details_label",
                    label = "Component Details",
                    wrapped = true
                },
                {widgetType = "same_line"},
                {
                    widgetType = "text",
                    id = widgetPrefix .. objectFinderPrefix .. "details",
                    label = "",
                    wrapped = false
                },
                {
                    widgetType = "combo",
                    id = widgetPrefix .. objectFinderPrefix .. "collision_enabled",
                    label = "Collision Enabled Type",
                    selections = COLLISION_ENABLED_STRINGS,
                    initialValue = 1,
                },
                {
                    widgetType = "combo",
                    id = widgetPrefix .. objectFinderPrefix .. "collision_object_type",
                    label = "Collision Object Type",
                    selections = COLLISION_OBJECT_TYPE_STRINGS,
                    initialValue = 1,
                },
                {
                    widgetType = "combo",
                    id = widgetPrefix .. objectFinderPrefix .. "mobility",
                    label = "Mobility",
                    selections = COLLISION_MOBILITY_STRINGS,
                    initialValue = 1,
                },
                {
                    widgetType = "checkbox",
                    id = widgetPrefix .. objectFinderPrefix .. "generate_overlap_events",
                    label = "Generate Overlap Events",
                    initialValue = false
                },
                {
                    widgetType = "checkbox",
                    id = widgetPrefix .. objectFinderPrefix .. "simulate_physics",
                    label = "Simulate Physics",
                    initialValue = false
                },
                {
                    widgetType = "checkbox",
                    id = widgetPrefix .. objectFinderPrefix .. "enable_gravity",
                    label = "Enable Gravity",
                    initialValue = false
                },
                {
                    widgetType = "tree_node",
                    id = widgetPrefix .. "collision_response",
                    initialOpen = true,
                    label = "Collision Response To Channels"
                },
                    { widgetType = "indent", width="10"},
                        expandArray(getChannels, widgetPrefix .. objectFinderPrefix),
                    { widgetType = "unindent", width="10"},
                {
                    widgetType = "tree_pop"
                },
            { widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
		{
			widgetType = "tree_pop"
		},
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
    uevrUtils.executeUEVRCallbacks("on_collision_config_param_change", key, value)
end

local function updateUIState(key)
    --print("updateUIState", key)
    -- local exKey = widgetPrefix .. key
    if key == "shape" then
        local value = configui.getValue(widgetPrefix .. key)
        local isOverlapOnly = value == COLLISION_SHAPES.Sphere_Overlap_Only or value == COLLISION_SHAPES.Box_Overlap_Only or value == COLLISION_SHAPES.Capsule_Overlap_Only
        configui.hideWidget(widgetPrefix .. "collision_settings_group", isOverlapOnly)
        configui.hideWidget(widgetPrefix .. "overlap_settings_group", not isOverlapOnly)
    
        local isBox = value == COLLISION_SHAPES.Box or value == COLLISION_SHAPES.Box_Overlap_Only
        local isCapsule = value == COLLISION_SHAPES.Capsule or value == COLLISION_SHAPES.Capsule_Overlap_Only
        configui.hideWidget(widgetPrefix .. "half_height", not isCapsule)
        configui.hideWidget(widgetPrefix .. "extents", not isBox)
    end
end

local function updateUIValue(key, value)
    if key == "channels" then
        for i = 1, #value do
            configui.setValue(widgetPrefix .. "channel" .. i, value[i], true)
        end
        for i = 1, #value do
            configui.setValue(widgetPrefix .. "bool_channel" .. i, value[i] > 1 and 2 or 1, true)
        end
    else
        configui.setValue(widgetPrefix .. key, value, true)
    end
    updateUIState(key)
end


function M.getConfigurationWidgets(options)
	return configui.applyOptionsToConfigWidgets(getConfigWidgets(paramManager), options)
end

function M.showConfiguration(saveFileName, options)
	configui.createConfigPanel(configTabLabel, saveFileName, spliceableInlineArray{expandArray(M.getConfigurationWidgets, options)})
end

function M.init(m_paramManager)
    configDefaults = m_paramManager and m_paramManager:getAll() or {}
	paramManager = m_paramManager
    --createDevMonitor()
    M.showConfiguration(configFileName)

	paramManager:initProfileHandler(widgetPrefix, function(profileParams)
        for key, value in pairs(profileParams) do
            updateUIValue(key, value)
        end
	end)

    m_paramManager:registerProfileChangeCallback(function(profileParams)
        for key, value in pairs(profileParams) do
            updateUIValue(key, value)
        end
	end)

    for key, value in pairs(parameterDefaults) do
        if key == "channels" then
            for i = 1, #value do
                configui.onUpdate(widgetPrefix .. "channel" .. i, function(val)
                    updateSetting({"channels", i}, val)
                end)
            end
            for i = 1, #value do
                configui.onUpdate(widgetPrefix .. "bool_channel" .. i, function(val)
                    updateSetting({"channels", i}, val)
                end)
            end
        else
            configui.onUpdate(widgetPrefix .. key, function(val)
                updateSetting(key, val)
                updateUIState(key)
            end)
        end
    end

    --set up handlers for the object finder channel widgets
    for i = 1, 32 do
        configui.onUpdate(widgetPrefix.. objectFinderPrefix .. "channel" .. i, function(val)
            if status.objectFinderComponent ~= nil then
                status.objectFinderComponent:SetCollisionResponseToChannel(i - 1, val - 1)
            end
        end)
    end

end

function M.setObjectFinderInfo(info)
    configui.setLabel(widgetPrefix .. objectFinderPrefix .. "name", info.componentName or "N/A")
    configui.setLabel(widgetPrefix .. objectFinderPrefix .. "class", info.componentClass or "N/A")
    configui.setLabel(widgetPrefix .. objectFinderPrefix .. "details", info.componentDetails or "N/A")
    configui.setValue(widgetPrefix .. objectFinderPrefix .. "collision_enabled", info.collisionEnabled and (info.collisionEnabled + 1) or 1)
    configui.setValue(widgetPrefix .. objectFinderPrefix .. "collision_object_type", info.collisionObjectType and (info.collisionObjectType + 1) or 1)
    configui.setValue(widgetPrefix .. objectFinderPrefix .. "generate_overlap_events", info.generateOverlapEvents or false)
    configui.setValue(widgetPrefix .. objectFinderPrefix .. "mobility", info.mobility and (info.mobility + 1) or 1)
    configui.setValue(widgetPrefix .. objectFinderPrefix .. "simulate_physics", info.simulatePhysics or false)
    configui.setValue(widgetPrefix .. objectFinderPrefix .. "enable_gravity", info.enableGravity or false)
    for i = 1, #info.channels do
        local response = info.channels[i] or 1
        configui.setValue(widgetPrefix .. objectFinderPrefix .. "channel" .. i, response + 1)
    end
end

function M.setObjectFinderComponent(component)
    if component == nil then return end
    status.objectFinderComponent = component
    local name = component:get_full_name():match(".*/([^/]+)$") or component:get_full_name()
    local details = ""
    if component.GetOwner ~= nil then
        local owner = component:GetOwner()
        if owner ~= nil then
            details = details .. "Owner: " .. owner:get_full_name() .. "\n"
            details = details .. "Owner Class: " .. owner:get_class():get_full_name() .. "\n"
        end
    end
    if component.StaticMesh ~= nil then
        details = details .. "Static Mesh: " .. component.StaticMesh:get_full_name()
    elseif component.SkeletalMesh ~= nil then
        details = details .. "Skeletal Mesh: " .. component.SkeletalMesh:get_full_name()
    end
    local info = {
        componentName = name, --uevrUtils.getShortName(component), -- component:get_full_name(),
        componentClass = component:get_class():get_full_name(),
        componentDetails = details,
        collisionEnabled = component.GetCollisionEnabled and component:GetCollisionEnabled() or 1,
        collisionObjectType = component:GetCollisionObjectType(),
        generateOverlapEvents = component.bGenerateOverlapEvents,
        mobility = component.Mobility,
        simulatePhysics = component.BodyInstance.bSimulatePhysics,
        enableGravity = component.BodyInstance.bEnableGravity,
        channels = {}
    }
    for i = 0, 31, 1 do
        info.channels[i + 1] = component:GetCollisionResponseToChannel(i)
    end
    M.setObjectFinderInfo(info)
end

function M.setCollisionComponentNames(componentNames)
    configui.setValue(widgetPrefix .. "detected_components", table.concat(componentNames, "\n"), true)
end

local function checkInteraction()
    -- local hitResult = linetracer.getLastResult("interaction")
    -- if hitResult ~= nil then
    --     print("HITRESULT", hitResult.Distance, hitResult.Component)
    -- end

    if status.lastHitResult ~= nil then
        local component = uevrUtils.getValid(status.lastHitResult.Component)
        if component ~= nil then
            --print("Last hit result component: ", component:get_full_name())
            -- local collisionEnabled =  component:GetCollisionEnabled()
            -- local collisionObjectType = component:GetCollisionObjectType()
            --print("Collision enabled: ", collisionEnabled, "Collision object type: ", collisionObjectType, "Overlap events enabled:", component.bGenerateOverlapEvents)
            -- component.bGenerateOverlapEvents = false
            -- for i = 0, 31, 1 do
            --     local response = component:GetCollisionResponseToChannel(i)
            --     if response ~= 0 then
            --         --print("Collision response to channel ", i, ": ", response)
            --     end
            -- end

            M.setObjectFinderComponent(component)
        end
    end
end

configui.onUpdate(widgetPrefix .. objectFinderPrefix .. "collision_enabled", function(val)
    if status.objectFinderComponent ~= nil then
        status.objectFinderComponent:SetCollisionEnabled(val - 1)
    end
end)

configui.onUpdate(widgetPrefix .. objectFinderPrefix .. "collision_object_type", function(val)
    if status.objectFinderComponent ~= nil then
        status.objectFinderComponent:SetCollisionObjectType(val - 1)
    end
end)

configui.onUpdate(widgetPrefix .. objectFinderPrefix .. "generate_overlap_events", function(val)
    if status.objectFinderComponent ~= nil then
        status.objectFinderComponent.bGenerateOverlapEvents = val
    end
end)

configui.onUpdate(widgetPrefix .. objectFinderPrefix .. "mobility", function(val)
    if status.objectFinderComponent ~= nil then
        status.objectFinderComponent.Mobility = val - 1
    end
end)

configui.onUpdate(widgetPrefix .. objectFinderPrefix .. "simulate_physics", function(val)
    if status.objectFinderComponent ~= nil then
        status.objectFinderComponent.BodyInstance.bSimulatePhysics = val
    end
end)

configui.onUpdate(widgetPrefix .. objectFinderPrefix .. "enable_gravity", function(val)
    if status.objectFinderComponent ~= nil then
        status.objectFinderComponent.BodyInstance.bEnableGravity = val
    end
end)

configui.onUpdate(widgetPrefix .. "ignore_all_button", function(val)
    for i = 1, 32, 1 do
        configui.setValue(widgetPrefix .. "channel" .. i, 1)
    end
end)
configui.onUpdate(widgetPrefix .. "overlap_all_button", function(val)
    for i = 1, 32, 1 do
        configui.setValue(widgetPrefix .. "channel" .. i, 2)
    end
end)
configui.onUpdate(widgetPrefix .. "block_all_button", function(val)
    for i = 1, 32, 1 do
        configui.setValue(widgetPrefix .. "channel" .. i, 3)
    end
end)

configui.onUpdate(widgetPrefix .. "off_all_button", function(val)
    for i = 1, 32, 1 do
        configui.setValue(widgetPrefix .. "bool_channel" .. i, 1)
    end
end)
configui.onUpdate(widgetPrefix .. "on_all_button", function(val)
    for i = 1, 32, 1 do
        configui.setValue(widgetPrefix .. "bool_channel" .. i, 2)
    end
end)

uevrUtils.registerUEVRCallback("on_interaction_hit", function(hitResult)
    status.lastHitResult = hitResult
    --print("HITRESULT", hitResult.Distance, hitResult.Component and hitResult.Component:get_full_name() or "nil")
end)

setInterval(1000,function()
    if configui.getValue(widgetPrefix .. objectFinderPrefix .. "enable") then
        checkInteraction()
    end
end)

return M
