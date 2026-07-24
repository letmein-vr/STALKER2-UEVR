-- Inspired by letmein's work with Stalker-2
local uevrUtils = require("libs/uevr_utils")
local controllers = require("libs/controllers")
local configui = require("libs/configui")
local paramModule = require("libs/core/params")
--local hands = require("libs/hands")

local M = {}

local callerModule = nil
-- Scope class definition
local Accessories = {}
Accessories.__index = Accessories

local parameterDefaults = {
	socket_name = "",
    attach_type = 0,
    location = {0, 0, 0},
    rotation = {0, 0, 0},
    activation_hand = 1,
    activation_distance = 0.0,
    start_time = 0.0,
    end_time = 0.0,
    grip_animation = "",
	grip_priority = 1,
}

local currentLogLevel = LogLevel.Error
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
	if logLevel == nil then logLevel = LogLevel.Debug end
	if logLevel <= currentLogLevel then
		uevrUtils.print("[accessories] " .. text, logLevel)
	end
end

local parametersFileName = "accessories_parameters"
local parameters = {}
local paramManager = paramModule.new(parametersFileName, parameters, true)

-- Shared clipboard for Copy/Paste UI actions.
-- Add new clipboard features by storing additional keys in this table.
local clipboard = {}

local function buildDefaultMarker()
    return uevrUtils.deepCopyTable(parameterDefaults)
end

local function saveAccessoryField(attachmentID, accessoryID, key, value, persist)
    paramManager:set({"accessories", attachmentID, accessoryID, key}, value, persist)
end

local function getAccessoryField(attachmentID, accessoryID, key)
    return paramManager:get({"accessories", attachmentID, accessoryID, key})
end

local function saveMarkerField(attachmentID, accessoryID, markerIndex, key, value, persist)
    markerIndex = markerIndex or 1
    paramManager:set({"accessories", attachmentID, accessoryID, "markers", markerIndex, key}, value, persist)
end

local function getMarkerField(attachmentID, accessoryID, markerIndex, key)
    markerIndex = markerIndex or 1
    local value = paramManager:get({"accessories", attachmentID, accessoryID, "markers", markerIndex, key})
    return value ~= nil and value or parameterDefaults[key]
end

local function ensureAccessoryHasMarkers(attachmentID, accessoryID, persist)
    local acc = paramManager:get({"accessories", attachmentID, accessoryID})
    if acc == nil then return nil end

    if type(acc.markers) ~= "table" then
        -- migrate from old flat fields into a single marker
        local marker = buildDefaultMarker()
        for key, defaultValue in pairs(parameterDefaults) do
            local v = acc[key]
            if v ~= nil then
                marker[key] = v
            else
                marker[key] = defaultValue
            end
        end
        acc = {
            label = acc.label or accessoryID,
            markers = { marker }
        }
        paramManager:set({"accessories", attachmentID, accessoryID}, acc, persist)
    elseif #acc.markers == 0 then
        acc.markers = { buildDefaultMarker() }
        paramManager:set({"accessories", attachmentID, accessoryID, "markers"}, acc.markers, persist)
    end

    return acc
end

-- Constructor for new scope instance
function M.new(attachmentID, options)
	local instance = setmetatable({}, Accessories)

	instance.attachmentID = attachmentID or ""
	-- Auto-create the scope components
	instance:create(options)

	return instance
end

function Accessories:create(options)

end

--[[
accessories = {
    Inventory_W_J_PlasmaRifle_01_FP = {
        3f051aa9-1a9f-457c-8b6e-5662c49bb81e = {
            label = "Trigger Grip",
            activation_hand = 1,
            attach_type = 0,
            end_time = 0.0,
            grip_animation = "rifle",
            location = {
                0.0,
                0.0,
                0.6000000238418579
            },
            rotation = {
                0.0,
                -11.399999618530273,
                0.0
            },
            socket_name = "Grip_Socket"
        },
        806e7314-9496-42c5-83b0-c87a8b6f8d45 = {
            label = "Offhand Grip",
            activation_distance = 8.5,
            activation_hand = 2,
            attach_type = 0,
            grip_animation = "rifle_offhand",
            location = {
                -7.0,
                1.7000000476837158,
                -5.199999809265137
            },
            rotation = {
                14.399999618530273,
                39.099998474121094,
                -75.0
            },
            socket_name = "Barrel_Socket"
        },
        db74521a-d4ec-4d6d-80d4-28f1a35fa346 = {
            label = "Reload",
            attach_type = 0,
            end_time = 1.2999999523162842,
            label = "Reload",
            location = {
                -4.099999904632568,
                0.800000011920929,
                -7.300000190734863
            },
            rotation = {
                43.5,
                24.399999618530273,
                29.399999618530273
            },
            socket_name = "Magazine_Socket"
        }
    }
}

accessories = {
    Inventory_W_J_PlasmaRifle_01_FP = {
        3f051aa9-1a9f-457c-8b6e-5662c49bb81e = {
            label = "Trigger Grip",
            markers = {
                {
                    activation_hand = 1,
                    attach_type = 0,
                    end_time = 0.0,
                    grip_animation = "rifle",
                    location = {
                        0.0,
                        0.0,
                        0.6000000238418579
                    },
                    rotation = {
                        0.0,
                        -11.399999618530273,
                        0.0
                    },
                    socket_name = "Grip_Socket"
                }
            }
        },
        806e7314-9496-42c5-83b0-c87a8b6f8d45 = {
            label = "Offhand Grip",
            markers = {
                {
                    activation_distance = 8.5,
                    activation_hand = 2,
                    attach_type = 0,
                    grip_animation = "rifle_offhand",
                    location = {
                        -7.0,
                        1.7000000476837158,
                        -5.199999809265137
                    },
                    rotation = {
                        14.399999618530273,
                        39.099998474121094,
                        -75.0
                    },
                    socket_name = "Barrel_Socket"
                }
            }
        }
        db74521a-d4ec-4d6d-80d4-28f1a35fa346 = {
            label = "Reload",
            markers = {
                {
                    attach_type = 0,
                    end_time = 1.3,
                    location = {
                        -4.099999904632568,
                        0.800000011920929,
                        -7.300000190734863
                    },
                    rotation = {
                        43.5,
                        24.399999618530273,
                        29.399999618530273
                    },
                    socket_name = "Magazine_Socket"
                },
                {
                    attach_type = 0,
                    start_time = 1.3,
                    end_time = 2.0,
                    location = {
                        -1.099999904632568,
                        0.800000011920929,
                        -8.300000190734863
                    },
                    rotation = {
                        22,
                        27.399999618530273,
                        21.399999618530273
                    },
                    socket_name = "Pullback_Socket"
                },
            }
        }
    }
}

]]--

local animationLabels = {"None"}
local animationIDs = {""}

local activePrefixes = {}
local accessoriesMap = {}
function M.getConfigWidgets(id, prefix, width)
    prefix = prefix or ""
    table.insert(activePrefixes, {prefix = prefix, id = id})

    local accessoryIDs = {}
    local accessoryLabels = {}
    local accessories = paramManager:get({"accessories", id})
    if accessories ~= nil then
        for accessoryID, accessoryParams in pairs(accessories) do
            table.insert(accessoryIDs, accessoryID)
            table.insert(accessoryLabels, accessoryParams["label"] or accessoryID)
        end
    end
    --add a "none" option
    if #accessoryIDs == 0 then
        table.insert(accessoryIDs, 1, "none")
        table.insert(accessoryLabels, 1, "None")
    end

    accessoriesMap[id] = {}
    accessoriesMap[id]["ids"] = accessoryIDs
    accessoriesMap[id]["labels"] = accessoryLabels

    if width == nil then width = 350 end
    
    return {
        {
            widgetType = "tree_node",
            id = prefix .. "accessory_tree",
            initialOpen = false,
            label = "Accessories"
        },
            {
                widgetType = "combo",
                id = prefix .. "accessory_picker",
                label = "Accessory",
                selections = accessoryLabels,
                initialValue = 1,
                width = width - 100
            },
            { widgetType = "same_line" },
            {
                widgetType = "button",
                id = prefix .. "accessory_new_button",
                label = "Add",
                size = {40,24},
            },
            { widgetType = "begin_group", id = prefix .. "accessory_group", isHidden = true }, { widgetType = "indent", width = 15 }, { widgetType = "text", label = "Settings" }, { widgetType = "begin_rect", },
            -- {
            --     widgetType = "begin_group",
            --     id = prefix .. "accessory_group",
            --     isHidden = true
            -- },
                {
                    widgetType = "tree_node",
                    id = prefix .. "accessory_replication_tree",
                    initialOpen = false,
                    label = "Replication"
                },
					{
						widgetType = "text",
						id = prefix .. "accessory_replication_instructions",
						label = "A single montage can sometimes affect multiple attachments. If you have already created another accessory for a specific montage, either select it from the list below and press Replicate or go to the other accessory's replication section and press Copy then come back here and press Paste. The montage will then affect this accessory as well.",
						wrapped = true,
                        width = width
					},
					{
						widgetType = "text",
						id = prefix .. "accessory_replication_automatic_label",
						label = "Automatic",
					},
                    {
                        widgetType = "combo",
                        id = prefix .. "accessory_existing_guid",
                        label = "Existing",
                        selections = {"(none)"},
                        initialValue = 1,
                        width = width - 100
                    },
                    { widgetType = "same_line", },
                    {
                        widgetType = "button",
                        id = prefix .. "accessory_replicate_button",
                        label = "Replicate",
                        size = {100,24},
                    },
					{
						widgetType = "text",
						id = prefix .. "accessory_replication_manual_label",
						label = "Manual",
					},
                    {
                        widgetType = "input_text",
                        id = prefix .. "accessory_item_id",
                        label = "Current ID",
                        initialValue = "",
                        isHidden = false,
                        width = width - 100
                    },
                    {widgetType = "same_line"},
                    {
                        widgetType = "button",
                        id = prefix .. "accessory_item_id_copy_button",
                        label = "Copy",
                        size = {60,22}
                    },
                    {widgetType = "same_line"},
                    {
                        widgetType = "button",
                        id = prefix .. "accessory_item_id_paste_button",
                        label = "Paste",
                        size = {60,22}
                    },
                    { widgetType = "new_line" },
                { widgetType = "tree_pop" },
                {
                    widgetType = "input_text",
                    id = prefix .. "accessory_item_label",
                    label = "Label",
                    initialValue = "",
                    isHidden = false,
                    width = width - 100
                },
                { widgetType = "same_line" },
                { widgetType = "space_horizontal", space = 10 },
                {
                    widgetType = "checkbox",
                    id = prefix .. "accessory_item_test_left_hand",
                    label = "Test Left",
                    initialValue = false
                },
                { widgetType = "same_line" },
                { widgetType = "space_horizontal", space = 10 },
                {
                    widgetType = "checkbox",
                    id = prefix .. "accessory_item_test_right_hand",
                    label = "Test Right",
                    initialValue = false
                },
                {
                    widgetType = "combo",
                    id = prefix .. "accessory_marker_picker",
                    label = " ",
                    selections = {"Marker 1"},
                    initialValue = 1,
                    width = width - 150
                },
                { widgetType = "same_line" },
                {
                    widgetType = "button",
                    id = prefix .. "accessory_marker_add_button",
                    label = "Add Marker",
                    size = {100,24},
                },
                { widgetType = "same_line" },
                {
                    widgetType = "button",
                    id = prefix .. "accessory_marker_copy_button",
                    label = "Copy",
                    size = {60,24},
                },
                { widgetType = "same_line" },
                {
                    widgetType = "button",
                    id = prefix .. "accessory_marker_paste_button",
                    label = "Paste",
                    size = {60,24},
                },
                { widgetType = "same_line" },
                {
                    widgetType = "button",
                    id = prefix .. "accessory_marker_delete_button",
                    label = "Delete Marker",
                    size = {110,24},
                    isHidden = true
                },
                { widgetType = "same_line" },{ widgetType = "text" , label = "" }, --dont sameline the start timeif delete button is hidden
                { widgetType = "indent", width = 10 },
                {
                    widgetType = "drag_float",
                    id = prefix .. "accessory_start_time",
                    label = "",
                    speed = 0.1,
                    range = {0, 1000},
                    initialValue = parameterDefaults["start_time"],
                    isHidden = false,
                    width = 80
                },
                { widgetType = "same_line", },
                { widgetType = "text", label = "to " },
                { widgetType = "same_line", },
                {
                    widgetType = "drag_float",
                    id = prefix .. "accessory_end_time",
                    label = "Montage Time Range (secs)",
                    speed = 0.1,
                    range = {0, 1000},
                    initialValue = parameterDefaults["end_time"],
                    isHidden = false,
                    width = 80
                },
                {
                    widgetType = "tree_node",
                    id = prefix .. "accessory_item_socket_finder_tool",
                    initialOpen = false,
                    label = "Socket Finder"
                },
                { widgetType = "begin_group", id = prefix .. "accessory_item_socket_finder_group", isHidden = false }, { widgetType = "indent", width = 10 }, { widgetType = "text", label = "" }, { widgetType = "begin_rect", },
					{
						widgetType = "text",
						id = prefix .. "accessory_item_socket_finder_instructions",
						label = "If no sockets are listed, equip the attachment and press refresh",
						wrapped = true,
                        width = width
					},
                    {
                        widgetType = "combo",
                        id = prefix .. "accessory_item_socket_list",
                        label = "Sockets",
                        selections = {"None"},
                        initialValue = 1,
                        width = width - 100
                    },
                    { widgetType = "same_line", },
                    {
                        widgetType = "button",
                        id = prefix .. "accessory_item_socket_finder_search_button",
                        label = "Refresh",
                        size = {80,22}
                    },
        			{ widgetType = "indent", width = 100 },
                    {
                        widgetType = "button",
                        id = prefix .. "accessory_item_socket_finder_use_button",
                        label = "Use Selected",
                        size = {150,22}
                    },
				    { widgetType = "unindent", width = 100 },
                { widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 10 }, { widgetType = "new_line" }, { widgetType = "end_group", },
                {
                    widgetType = "tree_pop"
                },
                {
                    widgetType = "input_text",
                    id = prefix .. "accessory_item_socket_name",
                    label = "Socket Name",
                    initialValue = "",
                    width = width
                },
                {
                    widgetType = "combo",
                    id = prefix .. "accessory_item_attach_type",
                    label = "Attach Type",
                    selections = {"Keep Relative", "Keep World", "Snap To Target"},
                    initialValue = parameterDefaults["attach_type"] + 1,
                    width = width
                },
                {
                    widgetType = "drag_float3",
                    id = prefix .. "accessory_item_location",
                    label = "Position",
                    speed = 0.1,
                    range = {-100, 100},
                    initialValue = parameterDefaults["location"],
                    isHidden = false,
                    width = width - 80
                },
                { widgetType = "same_line" },
                {
                    widgetType = "button",
                    id = prefix .. "accessory_item_location_copy_button",
                    label = "Copy",
                    size = {60,22}
                },
                { widgetType = "same_line" },
                {
                    widgetType = "button",
                    id = prefix .. "accessory_item_location_paste_button",
                    label = "Paste",
                    size = {60,22}
                },
                {
                    widgetType = "drag_float3",
                    id = prefix .. "accessory_item_rotation",
                    label = "Rotation",
                    speed = 0.1,
                    range = {-180, 180},
                    initialValue = parameterDefaults["rotation"],
                    isHidden = false,
                    width = width - 80
                },
                { widgetType = "same_line" },
                {
                    widgetType = "button",
                    id = prefix .. "accessory_item_rotation_copy_button",
                    label = "Copy",
                    size = {60,22}
                },
                { widgetType = "same_line" },
                {
                    widgetType = "button",
                    id = prefix .. "accessory_item_rotation_paste_button",
                    label = "Paste",
                    size = {60,22}
                },
                {
                    widgetType = "combo",
                    id = prefix .. "accessory_item_grip_animation",
                    label = "Grip Animation",
                    selections = animationLabels,
                    initialValue = 1,
					width = width - 60
                },
				{ widgetType = "same_line" },
				{
					widgetType = "input_text",
					id = prefix .. "accessory_item_grip_priority",
					label = "Priority",
					initialValue = "1",
					width = 50,
				},
                {
                    widgetType = "combo",
                    id = prefix .. "accessory_item_activation_hand",
                        label = "Activation Requirement",
                        selections = {"None", "Left Hand Proximity", "Right Hand Proximity", "Either Hand Proximity", "Left Hand Proximity During Montage Only", "Right Hand Proximity During Montage Only", "Either Hand Proximity During Montage Only", "Left Hand Always", "Right Hand Always", "Either Hand Always"},
                    initialValue = 1,
                    width = width
                },
				{
					widgetType = "drag_float",
					id = prefix .. "accessory_item_activation_distance",
					label = "Activation Distance",
					speed = 0.1,
					range = {0, 100},
					initialValue = 0.0,
                    isHidden = true,
                    width = width
				},
                { widgetType = "unindent", width = 10 },
                { widgetType = "indent", width = 140 },
                {
                    widgetType = "button",
                    id = prefix .. "delete_accessory_button",
                    label = "Delete",
                    size = {100,22}
                },
                { widgetType = "same_line", },
                {
                    widgetType = "checkbox",
                    id = prefix .. "delete_accessory_override",
                    label = "Allow Delete",
                    initialValue = false,
                    isHidden = true
                },
            { widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 15 }, { widgetType = "new_line" }, { widgetType = "end_group", },
            -- {
            --     widgetType = "end_group",
            -- },
            -- {
            --     widgetType = "tree_pop"
            -- },
        {
            widgetType = "tree_pop"
        },
    }
end

local socketCache = {}
local function refreshSocketList(id, prefix)
    if socketCache[id] ~= nil then
        configui.setSelections(prefix .. "accessory_item_socket_list", socketCache[id])
    else
       --need to get all the sockets for the mesh represented by id
        if callerModule ~= nil then
            print("Requesting sockets for attachment ID: " .. tostring(id))
            callerModule.getSocketsForAttachmentID(id, function(names)
                print(names)
                local socketList = {}
                if names == nil or #names == 0 then
                    M.print("No socket names received", LogLevel.Warning)
                    socketList = {"None"}
                else
                    socketList = names
                    socketCache[id] = socketList
                end
                configui.setSelections(prefix .. "accessory_item_socket_list", socketList)
            end)
        end
    end
end

local function refreshMarkerList(attachmentID, prefix, accessoryID)
    if accessoryID == nil or accessoryID == "none" then
        configui.setSelections(prefix .. "accessory_marker_picker", {"Marker 1"})
        configui.setValue(prefix .. "accessory_marker_picker", 1, true)
        configui.setHidden(prefix .. "accessory_marker_delete_button", true)
        return
    end

    local acc = ensureAccessoryHasMarkers(attachmentID, accessoryID, true)
    local markerCount = 1
    if acc ~= nil and type(acc.markers) == "table" and #acc.markers > 0 then
        markerCount = #acc.markers
    end

    local labels = {}
    for i = 1, markerCount do
        labels[i] = "Marker " .. tostring(i)
    end

    configui.setSelections(prefix .. "accessory_marker_picker", labels)
    local currentIndex = configui.getValue(prefix .. "accessory_marker_picker") or 1
    if currentIndex > markerCount then currentIndex = markerCount end
    if currentIndex < 1 then currentIndex = 1 end
    configui.setValue(prefix .. "accessory_marker_picker", currentIndex, true)
    configui.setHidden(prefix .. "accessory_marker_delete_button", markerCount <= 1)
end

local function getSelectedMarkerIndex(prefix)
    local idx = configui.getValue(prefix .. "accessory_marker_picker")
    if idx == nil or idx < 1 then return 1 end
    return idx
end

local function setUIForMarker(attachmentID, prefix, accessoryID, markerIndex)
    if accessoryID == nil or accessoryID == "none" then return end
    markerIndex = markerIndex or 1
    ensureAccessoryHasMarkers(attachmentID, accessoryID, false)

    configui.setValue(prefix .. "accessory_item_label", getAccessoryField(attachmentID, accessoryID, "label") or "", true)
    configui.setValue(prefix .. "accessory_item_socket_name", getMarkerField(attachmentID, accessoryID, markerIndex, "socket_name") or "", true)
    configui.setValue(prefix .. "accessory_item_attach_type", (getMarkerField(attachmentID, accessoryID, markerIndex, "attach_type") or 0) + 1, true)
    configui.setValue(prefix .. "accessory_item_location", getMarkerField(attachmentID, accessoryID, markerIndex, "location") or {0.0, 0.0, 0.0}, true)
    configui.setValue(prefix .. "accessory_item_rotation", getMarkerField(attachmentID, accessoryID, markerIndex, "rotation") or {0.0, 0.0, 0.0}, true)
    configui.setValue(prefix .. "accessory_item_activation_hand", getMarkerField(attachmentID, accessoryID, markerIndex, "activation_hand") or 1, true)
    configui.setValue(prefix .. "accessory_item_activation_distance", getMarkerField(attachmentID, accessoryID, markerIndex, "activation_distance") or 0.0, true)
    configui.setHidden(prefix .. "accessory_item_activation_distance", (getMarkerField(attachmentID, accessoryID, markerIndex, "activation_hand") or 1) == 1)
    configui.setValue(prefix .. "accessory_start_time", getMarkerField(attachmentID, accessoryID, markerIndex, "start_time") or 0.0, true)
    configui.setValue(prefix .. "accessory_end_time", getMarkerField(attachmentID, accessoryID, markerIndex, "end_time") or 0.0, true)

    local gripAnimationID = getMarkerField(attachmentID, accessoryID, markerIndex, "grip_animation") or ""
    local index = 1
    for i, idx in ipairs(animationIDs) do
        if idx == gripAnimationID then
            index = i
            break
        end
    end
    configui.setValue(prefix .. "accessory_item_grip_animation", index, true)

	local gripPriority = getMarkerField(attachmentID, accessoryID, markerIndex, "grip_priority")
	if gripPriority == nil then gripPriority = 1 end
	configui.setValue(prefix .. "accessory_item_grip_priority", tostring(gripPriority), true)
end

local function setUIForAccessory(id, prefix, accessoryID)
    --print("Setting UI for accessory ID: " .. tostring(accessoryID))
    configui.setHidden(prefix .. "accessory_group", accessoryID == "none")
    if accessoryID ~= "none" then
        refreshSocketList(id, prefix)
        refreshMarkerList(id, prefix, accessoryID)
        local markerIndex = getSelectedMarkerIndex(prefix)
        setUIForMarker(id, prefix, accessoryID, markerIndex)
    end
end

local function getAccessoryID(id, prefix)
    local value = configui.getValue(prefix .. "accessory_picker")
    local accessoryID = accessoriesMap[id]["ids"][value]
    if accessoryID == "none" then
        accessoryID = nil
    end
    return accessoryID
end

local function deleteCurrentAccessory(id, prefix)
    local accessoryID = getAccessoryID(id, prefix)
    if accessoryID == nil then
        M.print("No accessory selected to delete.", LogLevel.Warning)
        return false
    end
    paramManager:set({"accessories", id, accessoryID}, nil, true)

    -- Properly remove from arrays
    local ids = accessoriesMap[id]["ids"]
    local labels = accessoriesMap[id]["labels"]
    for i = #ids, 1, -1 do
        if ids[i] == accessoryID then
            table.remove(ids, i)
            table.remove(labels, i)
            break
        end
    end

    -- If no accessories left, add "none" option
    if #ids == 0 then
        table.insert(ids, 1, "none")
        table.insert(labels, 1, "None")
    end

    configui.setSelections(prefix .. "accessory_picker", labels)
    configui.setValue(prefix .. "accessory_picker", 1)  -- Select "None" or first item

    return true
end

local function updateGripAnimationUI()
    -- Update all existing grip animation combos
    for _, param in ipairs(activePrefixes) do
        configui.setSelections(param.prefix .. "accessory_item_grip_animation", animationLabels)
        --get the current stored value and re-set it to update index
        local accessoryID = getAccessoryID(param.id, param.prefix)
        if accessoryID ~= nil then
			local markerIndex = getSelectedMarkerIndex(param.prefix)
			local gripAnimationID = getMarkerField(param.id, accessoryID, markerIndex, "grip_animation") or ""
            local index = -1
            for i, id in ipairs(animationIDs) do
                if id == gripAnimationID then
                    index = i
                    break
                end
            end
            if index ~= -1 then
                configui.setValue(param.prefix .. "accessory_item_grip_animation", index, true)
            end
        end
    end
end

-- Preview functionality
local PREVIEW_PRIORITY = 1000000
local preview = {
    enabled = false,
    handed = Handed.Right,   -- choose which hand to preview
    accessoryID = nil,       -- GUID string
    markerIndex = 1,
}

-- Register once (module scope). This makes preview “win” by returning a huge priority.
uevrUtils.registerUEVRCallback("active_right_accessory", function()
    if preview.enabled and preview.handed == Handed.Right and preview.accessoryID ~= nil then
        return preview.accessoryID, PREVIEW_PRIORITY
    end
    -- return nil => no opinion
end)

uevrUtils.registerUEVRCallback("active_left_accessory", function()
    if preview.enabled and preview.handed == Handed.Left and preview.accessoryID ~= nil then
        return preview.accessoryID, PREVIEW_PRIORITY
    end
end)

local function pokePreviewChanged()
    -- hands.lua listens for this and re-applies attachments (even if GUID didn’t change)
    uevrUtils.executeUEVRCallbacks("on_accessory_preview_changed", preview.handed, preview.accessoryID, preview.enabled, preview.markerIndex or 1)
end

-- Replication UI helpers ------------------------------------------------------
-- This enables “one montage affects multiple attachments” by re-keying a local
-- accessory to use an existing GUID (ID), while keeping the destination params.

local function normalizeGuidInput(val)
    local s = tostring(val or "")
    s = s:gsub("%s+", "")
    return s
end

-- General-purpose humanizer: does not rely on any game-specific prefixes.
local function humanizeAttachmentID(value, maxLen)
    local s = tostring(value or "")
    -- if s == "" then return "" end

    -- -- If the ID looks like a path/qualified name, keep only the last segment.
    -- s = s:gsub("\\", "/")
    -- s = s:match("([^/]+)$") or s
    -- s = s:match("([^%.:]+)$") or s

    -- -- Generic Unreal-ish cleanup (safe even if not Unreal).
    -- s = s:gsub("^Default__", "")
    -- s = s:gsub("_C$", "")

    -- -- Normalize separators.
    -- s = s:gsub("[_%-%+]+", " ")
    -- s = s:gsub("[%[%]%(%){}]", " ")
    -- s = s:gsub("%s+", " ")

    -- -- Insert spaces for CamelCase and alnum boundaries.
    -- s = s:gsub("(%l)(%u)", "%1 %2")
    -- s = s:gsub("(%a)(%d)", "%1 %2")
    -- s = s:gsub("(%d)(%a)", "%1 %2")

    -- -- Trim.
    -- s = s:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")

    -- if maxLen ~= nil and #s > maxLen then
    --     if maxLen <= 3 then return s:sub(1, maxLen) end
    --     s = s:sub(1, maxLen - 3) .. "..."
    -- end

    return s
end

local function sortedKeys(setTable)
    local arr = {}
    for k, _ in pairs(setTable or {}) do
        arr[#arr + 1] = tostring(k)
    end
    table.sort(arr)
    return arr
end

local function countKeys(setTable)
    local n = 0
    for _, _ in pairs(setTable or {}) do n = n + 1 end
    return n
end

local function buildExistingGuidDropdown()
    local accessoriesList = paramManager:get("accessories") or {}

    -- guid -> { labelsSet = { [label]=true }, attachments = { [attachmentID]=true } }
    local grouped = {}
    for attachmentID, accessories in pairs(accessoriesList) do
        for guid, acc in pairs(accessories or {}) do
            local g = grouped[guid]
            if g == nil then
                g = { labelsSet = {}, attachments = {} }
                grouped[guid] = g
            end
            g.attachments[tostring(attachmentID)] = true
            local label = (acc and acc.label) or tostring(guid)
            g.labelsSet[tostring(label)] = true
        end
    end

    local guids = {}
    for guid, _ in pairs(grouped) do
        guids[#guids + 1] = guid
    end

    -- Stable-ish ordering: by label then GUID.
    table.sort(guids, function(a, b)
        local ga = grouped[a]
        local gb = grouped[b]
        local la = (ga and sortedKeys(ga.labelsSet)[1]) or tostring(a)
        local lb = (gb and sortedKeys(gb.labelsSet)[1]) or tostring(b)
        if la == lb then
            return tostring(a) < tostring(b)
        end
        return la < lb
    end)

    local labels = {"(none)"}
    local values = {""}

    local function buildAttachmentSummary(attachmentSet)
        local ids = sortedKeys(attachmentSet)
        if #ids == 0 then return "" end

        local maxShown = 3
        local shown = {}
        for i = 1, math.min(#ids, maxShown) do
            shown[#shown + 1] = humanizeAttachmentID(ids[i], 28)
        end
        local extra = #ids - #shown
        if extra > 0 then
            shown[#shown + 1] = "+" .. tostring(extra)
        end
        return table.concat(shown, ", ")
    end

    for _, guid in ipairs(guids) do
        local g = grouped[guid]
        local labelArr = sortedKeys(g.labelsSet)
        local baseLabel = labelArr[1] or tostring(guid)
        if #labelArr > 1 then
            baseLabel = baseLabel .. " (varies)"
        end

        local attachmentCount = countKeys(g.attachments)
        local where = buildAttachmentSummary(g.attachments)
        if where ~= "" then
            labels[#labels + 1] = baseLabel .. "  [" .. tostring(attachmentCount) .. "]  " .. where
        else
            labels[#labels + 1] = baseLabel .. "  [" .. tostring(attachmentCount) .. "]"
        end
        values[#values + 1] = guid
    end

    return labels, values
end

local function refreshReplicationDropdownUI(attachmentID, prefix)
    local labels, values = buildExistingGuidDropdown()
    accessoriesMap[attachmentID]["replicationExistingGuidValues"] = values
    pcall(function()
        configui.setSelections(prefix .. "accessory_existing_guid", labels)
    end)
end

local function ensureAccessoryInPickerList(attachmentID, prefix, guid)
    local ids = accessoriesMap[attachmentID]["ids"] or {}
    for i, existing in ipairs(ids) do
        if existing == guid then
            configui.setValue(prefix .. "accessory_picker", i, true)
            return true
        end
    end

    -- Exists in params but not in UI list; add it.
    local params = paramManager:get({"accessories", attachmentID, guid})
    if params == nil then return false end

    local label = (params and params.label) or tostring(guid)
    accessoriesMap[attachmentID]["ids"][#accessoriesMap[attachmentID]["ids"] + 1] = guid
    accessoriesMap[attachmentID]["labels"][#accessoriesMap[attachmentID]["labels"] + 1] = label
    configui.setSelections(prefix .. "accessory_picker", accessoriesMap[attachmentID]["labels"])
    configui.setValue(prefix .. "accessory_picker", #accessoriesMap[attachmentID]["ids"], true)
    return true
end

local function replicateAccessoryGuidForCurrentSelection(attachmentID, prefix, targetGuid)
    targetGuid = normalizeGuidInput(targetGuid)
    if targetGuid == "" then
        M.print("Replicate: no target GUID selected/pasted.", LogLevel.Warning)
        return
    end

    local currentGuid = getAccessoryID(attachmentID, prefix)
    if currentGuid == nil then
        M.print("Replicate: no accessory selected.", LogLevel.Warning)
        return
    end
    currentGuid = tostring(currentGuid)

    if currentGuid == targetGuid then
        M.print("Replicate: current GUID already matches target.", LogLevel.Debug)
        return
    end

    -- If the target GUID already exists on this attachment, do not overwrite it.
    local existingHere = paramManager:get({"accessories", attachmentID, targetGuid})
    if existingHere ~= nil then
        ensureAccessoryInPickerList(attachmentID, prefix, targetGuid)
        setUIForAccessory(attachmentID, prefix, targetGuid)
        configui.setValue(prefix .. "accessory_item_id", tostring(targetGuid), true)
        if preview.enabled and preview.accessoryID == currentGuid then
            preview.accessoryID = targetGuid
            pokePreviewChanged()
        end
        M.print("Replicate: target GUID already exists here; switched selection.", LogLevel.Debug)
        return
    end

    -- Destination params are preserved: copy from the currently-selected accessory.
    local currentParams = ensureAccessoryHasMarkers(attachmentID, currentGuid, true)
    if currentParams == nil then
        M.print("Replicate: could not load current accessory params.", LogLevel.Error)
        return
    end

    local newParams = uevrUtils.deepCopyTable(currentParams)
    paramManager:set({"accessories", attachmentID, targetGuid}, newParams, true)
    paramManager:set({"accessories", attachmentID, currentGuid}, nil, true)

    -- Update picker arrays in-place (preserve row/ordering).
    local ids = accessoriesMap[attachmentID]["ids"] or {}
    local labels = accessoriesMap[attachmentID]["labels"] or {}
    for i, guid in ipairs(ids) do
        if guid == currentGuid then
            ids[i] = targetGuid
            labels[i] = (newParams and newParams.label) or (labels[i] or targetGuid)
            break
        end
    end
    configui.setSelections(prefix .. "accessory_picker", labels)

    -- Keep the current selection index and refresh UI state.
    local sel = configui.getValue(prefix .. "accessory_picker") or 1
    configui.setValue(prefix .. "accessory_picker", sel, true)
    setUIForAccessory(attachmentID, prefix, targetGuid)
    configui.setValue(prefix .. "accessory_item_id", tostring(targetGuid), true)

    if preview.enabled and preview.accessoryID == currentGuid then
        preview.accessoryID = targetGuid
        pokePreviewChanged()
    end

    M.print("Replicate: rekeyed accessory GUID " .. tostring(currentGuid) .. " -> " .. tostring(targetGuid), LogLevel.Debug)
end
-- ---------------------------------------------------------------------------

function M.createConfigCallbacks(id, prefix)
    -- If user tweaks the transform/socket while preview is on, force re-apply:
    local function pokeIfPreviewingThisAccessory()
        if preview.enabled then
            local current = getAccessoryID(id, prefix)
            if current == preview.accessoryID then
                preview.markerIndex = getSelectedMarkerIndex(prefix) or 1
                pokePreviewChanged()
            end
        end
    end

    prefix = prefix or ""

    -- Replication UI wiring
    configui.onCreateOrUpdate(prefix .. "accessory_replication_tree", function(_)
        if accessoriesMap[id] ~= nil then
            refreshReplicationDropdownUI(id, prefix)
        end
    end)

    configui.onUpdate(prefix .. "accessory_replicate_button", function()
        local values = (accessoriesMap[id] and accessoriesMap[id]["replicationExistingGuidValues"]) or {""}
        local idx = configui.getValue(prefix .. "accessory_existing_guid") or 1
        local chosen = values[idx] or ""
        local targetGuid = chosen
        if targetGuid == "" then
            targetGuid = configui.getValue(prefix .. "accessory_item_id") or ""
        end
        replicateAccessoryGuidForCurrentSelection(id, prefix, targetGuid)
    end)

    configui.onUpdate(prefix .. "accessory_item_id_copy_button", function()
        local guid = getAccessoryID(id, prefix)
        if guid == nil then
            M.print("Copy: no accessory selected.", LogLevel.Warning)
            return
        end

        clipboard.accessory_guid = tostring(guid)
        configui.setValue(prefix .. "accessory_item_id", clipboard.accessory_guid, true)
    end)

    configui.onUpdate(prefix .. "accessory_item_id_paste_button", function()
        if clipboard.accessory_guid == nil or clipboard.accessory_guid == "" then
            M.print("Paste: clipboard is empty (use Copy first).", LogLevel.Warning)
            return
        end
        configui.setValue(prefix .. "accessory_item_id", tostring(clipboard.accessory_guid), true)
    end)
    configui.onUpdate(prefix .. "accessory_item_label", function(value)
        local accessoryID = getAccessoryID(id, prefix)
		if accessoryID ~= nil then saveAccessoryField(id, accessoryID, "label", value, true) end

        accessoriesMap[id]["labels"][configui.getValue(prefix .. "accessory_picker")] = value
        configui.setSelections(prefix .. "accessory_picker", accessoriesMap[id]["labels"])
	end)

    configui.onUpdate(prefix .. "accessory_item_socket_name", function(value)
        local accessoryID = getAccessoryID(id, prefix)
        local markerIndex = getSelectedMarkerIndex(prefix)
        if accessoryID ~= nil then saveMarkerField(id, accessoryID, markerIndex, "socket_name", value, true) end
        pokeIfPreviewingThisAccessory()
	end)

    configui.onUpdate(prefix .. "accessory_item_attach_type", function(value)
        local accessoryID = getAccessoryID(id, prefix)
        local markerIndex = getSelectedMarkerIndex(prefix)
        if accessoryID ~= nil then saveMarkerField(id, accessoryID, markerIndex, "attach_type", value - 1, true) end
        pokeIfPreviewingThisAccessory()
	end)

    configui.onUpdate(prefix .. "accessory_item_location", function(value)
        local accessoryID = getAccessoryID(id, prefix)
        local markerIndex = getSelectedMarkerIndex(prefix)
        if accessoryID ~= nil then saveMarkerField(id, accessoryID, markerIndex, "location", {value.X, value.Y, value.Z}, true) end
        pokeIfPreviewingThisAccessory()
    end)

    configui.onUpdate(prefix .. "accessory_item_location_copy_button", function()
        local accessoryID = getAccessoryID(id, prefix)
        if accessoryID == nil then
            M.print("Copy Position: no accessory selected.", LogLevel.Warning)
            return
        end
        local markerIndex = getSelectedMarkerIndex(prefix)
        clipboard.marker_location = uevrUtils.deepCopyTable(getMarkerField(id, accessoryID, markerIndex, "location"))
        M.print("Copied Position from Marker " .. tostring(markerIndex), LogLevel.Debug)
    end)

    configui.onUpdate(prefix .. "accessory_item_location_paste_button", function()
        if clipboard.marker_location == nil then
            M.print("Paste Position: clipboard empty (use Copy).", LogLevel.Warning)
            return
        end
        local accessoryID = getAccessoryID(id, prefix)
        if accessoryID == nil then
            M.print("Paste Position: no accessory selected.", LogLevel.Warning)
            return
        end
        local markerIndex = getSelectedMarkerIndex(prefix)
        local pos = uevrUtils.deepCopyTable(clipboard.marker_location)
        saveMarkerField(id, accessoryID, markerIndex, "location", pos, true)
        configui.setValue(prefix .. "accessory_item_location", pos, true)
        pokeIfPreviewingThisAccessory()
        M.print("Pasted Position into Marker " .. tostring(markerIndex), LogLevel.Debug)
    end)

    configui.onUpdate(prefix .. "accessory_item_rotation", function(value)
        local accessoryID = getAccessoryID(id, prefix)
        local markerIndex = getSelectedMarkerIndex(prefix)
        if accessoryID ~= nil then saveMarkerField(id, accessoryID, markerIndex, "rotation", {value.Pitch, value.Yaw, value.Roll}, true) end
        pokeIfPreviewingThisAccessory()
    end)

    configui.onUpdate(prefix .. "accessory_item_rotation_copy_button", function()
        local accessoryID = getAccessoryID(id, prefix)
        if accessoryID == nil then
            M.print("Copy Rotation: no accessory selected.", LogLevel.Warning)
            return
        end
        local markerIndex = getSelectedMarkerIndex(prefix)
        clipboard.marker_rotation = uevrUtils.deepCopyTable(getMarkerField(id, accessoryID, markerIndex, "rotation"))
        M.print("Copied Rotation from Marker " .. tostring(markerIndex), LogLevel.Debug)
    end)

    configui.onUpdate(prefix .. "accessory_item_rotation_paste_button", function()
        if clipboard.marker_rotation == nil then
            M.print("Paste Rotation: clipboard empty (use Copy).", LogLevel.Warning)
            return
        end
        local accessoryID = getAccessoryID(id, prefix)
        if accessoryID == nil then
            M.print("Paste Rotation: no accessory selected.", LogLevel.Warning)
            return
        end
        local markerIndex = getSelectedMarkerIndex(prefix)
        local rot = uevrUtils.deepCopyTable(clipboard.marker_rotation)
        saveMarkerField(id, accessoryID, markerIndex, "rotation", rot, true)
        configui.setValue(prefix .. "accessory_item_rotation", rot, true)
        pokeIfPreviewingThisAccessory()
        M.print("Pasted Rotation into Marker " .. tostring(markerIndex), LogLevel.Debug)
    end)

    configui.onUpdate(prefix .. "accessory_item_activation_hand", function(value)
        local accessoryID = getAccessoryID(id, prefix)
        local markerIndex = getSelectedMarkerIndex(prefix)
        if accessoryID ~= nil then saveMarkerField(id, accessoryID, markerIndex, "activation_hand", value, true) end
        configui.setHidden(prefix .. "accessory_item_activation_distance", value == 1 or value == 8 or value == 9 or value == 10)
    end)

    configui.onUpdate(prefix .. "accessory_start_time", function(value)
        local accessoryID = getAccessoryID(id, prefix)
        local markerIndex = getSelectedMarkerIndex(prefix)
        if accessoryID ~= nil then saveMarkerField(id, accessoryID, markerIndex, "start_time", value, true) end
    end)

    configui.onUpdate(prefix .. "accessory_end_time", function(value)
        local accessoryID = getAccessoryID(id, prefix)
        local markerIndex = getSelectedMarkerIndex(prefix)
        if accessoryID ~= nil then saveMarkerField(id, accessoryID, markerIndex, "end_time", value, true) end
    end)

    configui.onUpdate(prefix .. "accessory_item_activation_distance", function(value)
        local accessoryID = getAccessoryID(id, prefix)
        local markerIndex = getSelectedMarkerIndex(prefix)
        if accessoryID ~= nil then saveMarkerField(id, accessoryID, markerIndex, "activation_distance", value, true) end
    end)

    configui.onCreateOrUpdate(prefix .. "accessory_picker", function(value)
		local accessoryID = accessoriesMap[id]["ids"][value]
        M.print("Selected accessory ID: " .. tostring(accessoryID), LogLevel.Debug)
        setUIForAccessory(id, prefix, accessoryID)

        -- Keep replication "Current ID" field in sync with selection.
        if accessoryID ~= nil and accessoryID ~= "none" then
            configui.setValue(prefix .. "accessory_item_id", tostring(accessoryID), true)
        else
            configui.setValue(prefix .. "accessory_item_id", "", true)
        end
        refreshReplicationDropdownUI(id, prefix)

        if preview.enabled then
            preview.accessoryID = (accessoryID ~= "none") and accessoryID or nil
            preview.markerIndex = getSelectedMarkerIndex(prefix) or 1
            pokePreviewChanged()
        end

	end)

    configui.onUpdate(prefix .. "accessory_marker_picker", function(value)
        local accessoryID = getAccessoryID(id, prefix)
        if accessoryID ~= nil then
            refreshMarkerList(id, prefix, accessoryID)
            setUIForMarker(id, prefix, accessoryID, value)
            pokeIfPreviewingThisAccessory()
        end
    end)

    configui.onUpdate(prefix .. "accessory_marker_add_button", function()
        local accessoryID = getAccessoryID(id, prefix)
        if accessoryID == nil then return end
        local acc = ensureAccessoryHasMarkers(id, accessoryID, true)
        if acc == nil then return end
        acc.markers = acc.markers or {}
        local newIndex = #acc.markers + 1
        acc.markers[newIndex] = buildDefaultMarker()
        paramManager:set({"accessories", id, accessoryID, "markers"}, acc.markers, true)
        refreshMarkerList(id, prefix, accessoryID)
        configui.setValue(prefix .. "accessory_marker_picker", newIndex, true)
        setUIForMarker(id, prefix, accessoryID, newIndex)
        pokeIfPreviewingThisAccessory()
    end)

    configui.onUpdate(prefix .. "accessory_marker_copy_button", function()
        local accessoryID = getAccessoryID(id, prefix)
        if accessoryID == nil then
            M.print("Copy Marker: no accessory selected.", LogLevel.Warning)
            return
        end

        local acc = ensureAccessoryHasMarkers(id, accessoryID, true)
        if acc == nil or type(acc.markers) ~= "table" or #acc.markers < 1 then
            M.print("Copy Marker: no markers to copy.", LogLevel.Warning)
            return
        end

        local markerIndex = getSelectedMarkerIndex(prefix)
        if markerIndex < 1 or markerIndex > #acc.markers then
            M.print("Copy Marker: invalid marker index.", LogLevel.Warning)
            return
        end

        clipboard.marker = uevrUtils.deepCopyTable(acc.markers[markerIndex])
        M.print("Copied Marker " .. tostring(markerIndex), LogLevel.Debug)
    end)

    configui.onUpdate(prefix .. "accessory_marker_paste_button", function()
        if clipboard.marker == nil then
            M.print("Paste Marker: clipboard empty (use Copy first).", LogLevel.Warning)
            return
        end

        local accessoryID = getAccessoryID(id, prefix)
        if accessoryID == nil then
            M.print("Paste Marker: no accessory selected.", LogLevel.Warning)
            return
        end

        local acc = ensureAccessoryHasMarkers(id, accessoryID, true)
        if acc == nil then return end
        acc.markers = acc.markers or {}
        if type(acc.markers) ~= "table" or #acc.markers < 1 then
            M.print("Paste Marker: no markers exist to paste into.", LogLevel.Warning)
            return
        end

        local markerIndex = getSelectedMarkerIndex(prefix)
        if markerIndex < 1 or markerIndex > #acc.markers then
            M.print("Paste Marker: invalid marker index.", LogLevel.Warning)
            return
        end

        acc.markers[markerIndex] = uevrUtils.deepCopyTable(clipboard.marker)
        paramManager:set({"accessories", id, accessoryID, "markers"}, acc.markers, true)
        refreshMarkerList(id, prefix, accessoryID)
        setUIForMarker(id, prefix, accessoryID, markerIndex)
        pokeIfPreviewingThisAccessory()
        M.print("Pasted into Marker " .. tostring(markerIndex), LogLevel.Debug)
    end)

    configui.onUpdate(prefix .. "accessory_marker_delete_button", function()
        local accessoryID = getAccessoryID(id, prefix)
        if accessoryID == nil then return end
        local acc = ensureAccessoryHasMarkers(id, accessoryID, true)
        if acc == nil or type(acc.markers) ~= "table" or #acc.markers <= 1 then return end

        local markerIndex = getSelectedMarkerIndex(prefix)
        if markerIndex < 1 or markerIndex > #acc.markers then return end
        table.remove(acc.markers, markerIndex)
        paramManager:set({"accessories", id, accessoryID, "markers"}, acc.markers, true)
        refreshMarkerList(id, prefix, accessoryID)
        local newIndex = markerIndex
        if newIndex > #acc.markers then newIndex = #acc.markers end
        configui.setValue(prefix .. "accessory_marker_picker", newIndex, true)
        setUIForMarker(id, prefix, accessoryID, newIndex)
        pokeIfPreviewingThisAccessory()
    end)

    configui.onUpdate(prefix .. "accessory_new_button", function()
        -- Remove "none" if present, since we're adding a real accessory
        local ids = accessoriesMap[id]["ids"]
        local labels = accessoriesMap[id]["labels"]
        if #ids > 0 and ids[1] == "none" then
            table.remove(ids, 1)
            table.remove(labels, 1)
        end

        local newAccessoryID = uevrUtils.guid()

        -- Guarantee a unique label by checking existing labels and appending a number if needed
        local baseLabel = "New Accessory"
        local label = baseLabel
        local counter = 1
        while true do
            local exists = false
            for _, existingLabel in ipairs(accessoriesMap[id]["labels"]) do
                if existingLabel == label then
                    exists = true
                    break
                end
            end
            if not exists then break end
            counter = counter + 1
            label = baseLabel .. " " .. counter
        end

        local params = {
            label = label,
            markers = { buildDefaultMarker() },
        }
        paramManager:set({"accessories", id, newAccessoryID}, params, true)

        accessoriesMap[id]["ids"][#accessoriesMap[id]["ids"] + 1] = newAccessoryID
        accessoriesMap[id]["labels"][#accessoriesMap[id]["labels"] + 1] = label
        configui.setSelections(prefix .. "accessory_picker", accessoriesMap[id]["labels"])

        --change selection to new accessory
        configui.setValue(prefix .. "accessory_picker", #accessoriesMap[id]["ids"])
        setUIForAccessory(id, prefix, newAccessoryID)

        M.print("Created new accessory with ID: " .. newAccessoryID, LogLevel.Debug)
    end)

    configui.onUpdate(prefix .. "delete_accessory_button", function()
        if configui.getValue(prefix .. "delete_accessory_override") == true then
            if deleteCurrentAccessory(id, prefix) then
                configui.setValue(prefix .. "accessory_picker", 1)
            end
            configui.hideWidget(prefix .. "delete_accessory_override", true)
            configui.setValue(prefix .. "delete_accessory_override", false)
        else
            configui.hideWidget(prefix .. "delete_accessory_override", false)
            configui.setValue(prefix .. "delete_accessory_override", false)
        end
    end)

    configui.onUpdate(prefix .. "accessory_item_socket_finder_search_button", function()
        local accessoryID = getAccessoryID(id, prefix)
        if accessoryID ~= nil then
            refreshSocketList(id, prefix)
        end
    end)

    configui.onUpdate(prefix .. "accessory_item_socket_finder_use_button", function()
        local socketValue = configui.getValue(prefix .. "accessory_item_socket_list")
        local socketName = socketCache[id][socketValue]
        configui.setValue(prefix .. "accessory_item_socket_name", socketName)
        --configui.setHidden(prefix .. "accessory_item_socket_finder_tool", true)
    end)

    configui.onUpdate(prefix .. "accessory_item_grip_animation", function(value)
        local gripAnimationID = animationIDs[value] or ""
        local accessoryID = getAccessoryID(id, prefix)
        local markerIndex = getSelectedMarkerIndex(prefix)
        if accessoryID ~= nil then saveMarkerField(id, accessoryID, markerIndex, "grip_animation", gripAnimationID, true) end
    end)

    configui.onUpdate(prefix .. "accessory_item_grip_priority", function(value)
        local accessoryID = getAccessoryID(id, prefix)
        local markerIndex = getSelectedMarkerIndex(prefix)
        local p = tonumber(value)
        if accessoryID ~= nil and p ~= nil then
            saveMarkerField(id, accessoryID, markerIndex, "grip_priority", p, true)
            pokeIfPreviewingThisAccessory()
        end
    end)

    -- Preview handlers
    configui.onUpdate(prefix .. "accessory_item_test_left_hand", function(checked)
        local accessoryID = getAccessoryID(id, prefix) -- your existing helper (returns GUID or nil)
        preview.handed = Handed.Left
        preview.enabled = (checked == true) and (accessoryID ~= nil)
        preview.accessoryID = accessoryID
        preview.markerIndex = getSelectedMarkerIndex(prefix) or 1

        pokePreviewChanged()
    end)

    configui.onUpdate(prefix .. "accessory_item_test_right_hand", function(checked)
        local accessoryID = getAccessoryID(id, prefix) -- your existing helper (returns GUID or nil)
        preview.handed = Handed.Right
        preview.enabled = (checked == true) and (accessoryID ~= nil)
        preview.accessoryID = accessoryID
        preview.markerIndex = getSelectedMarkerIndex(prefix) or 1

        pokePreviewChanged()
    end)

end

--returns {333_da_344: "attachment_shotgun_game_name Scope", 432_dd_123: "some_attachment_long_name Laser Sight"}
function M.getAccessories()
    local result = {}
    local accessoriesList = paramManager:get("accessories") or {}

    -- Group by GUID so duplicates across attachments can be represented in the UI.
    local grouped = {}
    for attachmentID, accessories in pairs(accessoriesList) do
        for accessoryID, accessoryParams in pairs(accessories) do
            M.print("Attachment ID: " .. tostring(attachmentID) .. " Accessory ID: " .. tostring(accessoryID), LogLevel.Debug)

            local g = grouped[accessoryID]
            if g == nil then
                g = { attachments = {}, labels = {} }
                grouped[accessoryID] = g
            end

            g.attachments[#g.attachments + 1] = tostring(attachmentID)
            local label = (accessoryParams and accessoryParams.label) or tostring(accessoryID)
            g.labels[label] = true
        end
    end

    local function sortedKeys(setTable)
        local keys = {}
        for k, _ in pairs(setTable or {}) do
            keys[#keys + 1] = k
        end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        return keys
    end

    local function buildAttachmentSummary(attachments)
        if type(attachments) ~= "table" or #attachments == 0 then
            return ""
        end
        table.sort(attachments)

        local maxShown = 3
        local shown = {}
        for i = 1, math.min(#attachments, maxShown) do
            shown[#shown + 1] = attachments[i]
        end
        local extra = #attachments - #shown
        local suffix = (extra > 0) and (" +" .. tostring(extra)) or ""
        return table.concat(shown, ", ") .. suffix
    end

    for accessoryID, g in pairs(grouped) do
        local labels = sortedKeys(g.labels)
        local baseLabel = labels[1] or tostring(accessoryID)
        if #labels > 1 then
            -- If the same GUID was given different labels under different attachments, hint at that.
            baseLabel = baseLabel .. " (varies)"
        end

        local attachmentSummary = buildAttachmentSummary(g.attachments)
        if #g.attachments <= 1 then
            result[accessoryID] = baseLabel .. " (" .. tostring(g.attachments[1] or "") .. ")"
        else
            result[accessoryID] = baseLabel .. " (" .. tostring(#g.attachments) .. " attachments: " .. attachmentSummary .. ")"
        end
    end

    return result
end


local function getAnimationLabelsArray(animationIDList)
	local labels = {"None"}
	for id, data in pairs(animationIDList) do
		table.insert(labels, data["label"])
	end
	return labels
end

local function getAnimationIDsArray(animationIDList)
	local ids = {""}
	for id, data in pairs(animationIDList) do
		table.insert(ids, id)
	end
	return ids
end

--called from hands to set available grip animations
function M.setAnimationIDs(animationIDList)
	if animationIDList ~= nil then
		animationLabels = getAnimationLabelsArray(animationIDList)
		animationIDs = getAnimationIDsArray(animationIDList)
	end
    updateGripAnimationUI()
end

function M.init(isDeveloperMode, logLevel, caller)
    paramManager:load()
    -- migrate any legacy flat accessories into marker-based format
    local accessoriesList = paramManager:get("accessories") or {}
    for attachmentID, accessories in pairs(accessoriesList) do
        for accessoryID, accessoryParams in pairs(accessories) do
            if accessoryID ~= nil and accessoryParams ~= nil then
                ensureAccessoryHasMarkers(attachmentID, accessoryID, true)
            end
        end
    end
    --need this to get the attachment sockets but is there a better way?
    callerModule = caller
end

function M.getAccessoryParams(accessoryID)
    local accessoriesList = paramManager:get("accessories") or {}
    for attachmentID, accessories in pairs(accessoriesList) do
        for aID, accessoryParams in pairs(accessories) do
            if aID == accessoryID then
                return accessoryParams
            end
        end
    end
    return nil
end

function M.getAccessoriesForAttachment(attachmentID)
    if attachmentID == nil or attachmentID == "" then
        return {}
    end
    return paramManager:get({"accessories", attachmentID}) or {}
end

function M.getAccessoryParamsForAttachment(attachmentID, accessoryID)
    if attachmentID == nil or accessoryID == nil then
        return nil
    end
    local list = paramManager:get({"accessories", attachmentID})
    return list and list[accessoryID] or nil
end




return M