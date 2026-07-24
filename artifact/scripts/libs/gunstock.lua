local uevrUtils = require("libs/uevr_utils")
local configui = require("libs/configui")
--local input = require("libs/input")

local M = {}

--[[
gunstock.addAdjustment({
        id = "beretta",
        label = "Beretta M9",
        rotation_offset = {0,0,0}
})
gunstock.addAdjustment({
        id = "mossberg",
        label = "Mossberg",
        rotation_offset = {0,0,0}
})
gunstock.setActive("mossberg")
]]--
local parametersFileName = "gunstock_parameters"
local parameters = {}
local isParametersDirty = false

local configFileName = "gunstock_config"
local configTabLabel = "Gunstock Config"
local widgetPrefix = "uevr_gunstock_"


local disableGunstockConfiguration = false
local activeAttachmentID = nil
-- parameters["attachments"] = {
--     {
--         id = "WP_BerettaAuto9_C_Beretta_Mesh",
--         label = "Beretta M9",
--         rotation = {0,0,0}
--     }
-- }

local currentLogLevel = LogLevel.Error
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
	if logLevel == nil then logLevel = LogLevel.Debug end
	if logLevel <= currentLogLevel then
		uevrUtils.print("[gunstock] " .. text, logLevel)
	end
end

-- local function executeAimRotationOffsetChangeCallback(...)
-- 	uevrUtils.executeUEVRCallbacks("aim_rotation_offset_change", table.unpack({...}))
-- end

local function executeTransformChange(...)
	uevrUtils.executeUEVRCallbacks("gunstock_transform_change", table.unpack({...}))
end


local function getDefaultConfig(saveFileName)
    if saveFileName == nil then saveFileName = configFileName end
	return  {
		{
			panelLabel = configTabLabel,
			saveFile = saveFileName,
			layout =
			{
			}
		}
	}
end

local function updateConfigUI(configDefinition)
    local attachmentList = parameters["attachments"]
	table.insert(configDefinition[1]["layout"],
        {
            widgetType = "checkbox",
            id = widgetPrefix .. "disable_configuration",
            label = "Disable",
            initialValue = disableGunstockConfiguration
        }
	)

	table.insert(configDefinition[1]["layout"],
		{
			widgetType = "tree_node",
			id = widgetPrefix .. "configuration",
			initialOpen = true,
			label = "Gunstock Configuration"
		}
	)

    table.insert(configDefinition[1]["layout"],
        {
            widgetType = "tree_node",
            id = widgetPrefix .. "default",
            initialOpen = true,
            label = "Default"
        }
    )
    table.insert(configDefinition[1]["layout"],
        {
            id = widgetPrefix .. "default_rotation", label = "Rotation",
            widgetType = "drag_float3", speed = .1, range = {-360, 360}, initialValue = {0,0,0}
        }
    )
    table.insert(configDefinition[1]["layout"],
        {
            id = widgetPrefix .. "default_offhand_location_offset", label = "Offhand Location Offset",
            widgetType = "drag_float3", speed = .1, range = {-100, 100}, initialValue = {0,0,0}
        }
    )
    table.insert(configDefinition[1]["layout"],
        {
            widgetType = "tree_pop"
        }
    )

    for i = 1, #attachmentList do
		local id = attachmentList[i]["id"]
		local label = attachmentList[i]["label"]
		local rot = attachmentList[i]["rotation"]
		local offhand_location_offset = attachmentList[i]["offhand_location_offset"]

        table.insert(configDefinition[1]["layout"],
            {
                widgetType = "tree_node",
                id = widgetPrefix .. id,
                initialOpen = false,
                label = label
            }
        )
		table.insert(configDefinition[1]["layout"],
            {
                id = widgetPrefix .. id .. "_use_default", label = "Use Default Rotation",
                widgetType = "checkbox", initialValue = true
            }
		)
		table.insert(configDefinition[1]["layout"],
            {
                id = widgetPrefix .. id .. "_rotation", label = "Rotation",
                widgetType = "drag_float3", speed = .1, range = {-360, 360}, initialValue = rot
            }
		)
		table.insert(configDefinition[1]["layout"],
            {
                id = widgetPrefix .. id .. "_use_default_offhand_location_offset", label = "Use Default Offhand Location Offset",
                widgetType = "checkbox", initialValue = true
            }
		)
		table.insert(configDefinition[1]["layout"],
            {
                id = widgetPrefix .. id .. "_offhand_location_offset", label = "Offhand Location Offset",
                widgetType = "drag_float3", speed = .1, range = {-100, 100}, initialValue = offhand_location_offset
            }
		)
		table.insert(configDefinition[1]["layout"],
            {
                widgetType = "tree_pop"
            }
		)

        configui.onUpdate(widgetPrefix .. id .. "_rotation", function(value)
			M.updateTransforms(id, nil, value, nil)
		end)
        configui.onUpdate(widgetPrefix .. id .. "_offhand_location_offset", function(value)
			M.updateTransforms(id, nil, nil, nil, value)
		end)
        configui.onCreateOrUpdate(widgetPrefix .. id .. "_use_default", function(value)
			configui.setHidden(widgetPrefix .. id .. "_rotation", value)
		end)
        configui.onCreateOrUpdate(widgetPrefix .. id .. "_use_default_offhand_location_offset", function(value)
			configui.setHidden(widgetPrefix .. id .. "_offhand_location_offset", value)
		end)

    end

    table.insert(configDefinition[1]["layout"],
		{
			widgetType = "tree_pop"
		}
	)
	return configDefinition
end

local function saveParameters()
	M.print("Saving gunstock parameters " .. parametersFileName)
	json.dump_file(parametersFileName .. ".json", parameters, 4)
end

local createMonitor = doOnce(function()
    uevrUtils.setInterval(1000, function()
        if isParametersDirty == true then
            saveParameters()
            isParametersDirty = false
        end
    end)
end, Once.EVER)

local function getAttachment(id)
    if id == nil then return nil end
    if parameters ~= nil and parameters["attachments"] ~= nil then
        for i = 1, #parameters["attachments"] do
            if id == parameters["attachments"][i].id then
                return parameters["attachments"][i]
            end
        end
    end
    return nil
end

function M.loadParameters(fileName)
	if fileName ~= nil then parametersFileName = fileName end
	M.print("Loading attachments parameters " .. parametersFileName)
	parameters = json.load_file(parametersFileName .. ".json")

	if parameters == nil then
		parameters = {}
		M.print("Creating attachments parameters")
	end
	if parameters["attachments"] == nil then
		parameters["attachments"] = {}
		isParametersDirty = true
	end

    createMonitor()
end

function M.showConfiguration(saveFileName, options)
	configui.create(updateConfigUI(getDefaultConfig(saveFileName)))
end

function M.addAdjustment(attachment)
	if attachment ~= nil and attachment.id ~= nil and attachment.id ~= "" and parameters ~= nil then
		local exists = false
		if parameters["attachments"] == nil then parameters["attachments"] = {} end
        for i = 1, #parameters["attachments"] do
            if attachment.id == parameters["attachments"][i].id then
                exists = true
            end
        end
        if not exists then
            if attachment.label == nil then
                attachment.label = attachment.id
            end
            if attachment.rotation == nil then
                local rot = configui.getValue(widgetPrefix .. "default_rotation")
                if rot ~= nil then attachment.rotation =  {rot.x, rot.y, rot.z} end
            end
            if attachment.offhand_location_offset == nil then
                local loc = configui.getValue(widgetPrefix .. "default_offhand_location_offset")
                if loc ~= nil then attachment.offhand_location_offset =  {loc.x, loc.y, loc.z} end
            end
            table.insert(parameters["attachments"], attachment)
            isParametersDirty = true

            configui.update(updateConfigUI(getDefaultConfig()))
        end
    else
        M.print("Invalid attachment parameters", LogLevel.Warning)
	end
end

-- function M.registerUpdateCallback(func)
-- 	uevrUtils.registerUEVRCallback("gunstock_update", func)
-- end
local function broadcastUpdate(id, attachmentParams)
    local rot = attachmentParams["rotation"] or {x=0, y=0, z=0}
    local offhandLocationOffset = attachmentParams["offhand_location_offset"] or {x=0, y=0, z=0}
    if disableGunstockConfiguration == false and id == activeAttachmentID then
        executeTransformChange(id, nil, uevrUtils.rotator(rot), uevrUtils.vector(offhandLocationOffset))
    end
end

function M.updateTransforms(id, pos, rot, scale, offhandLocationOffset)
	if id ~= nil then
        for i = 1, #parameters["attachments"] do
            if id == parameters["attachments"][i].id then
                if rot ~= nil then parameters["attachments"][i].rotation = {rot.x, rot.y, rot.z} end
                if offhandLocationOffset ~= nil then parameters["attachments"][i].offhand_location_offset = {offhandLocationOffset.x, offhandLocationOffset.y, offhandLocationOffset.z} end
                isParametersDirty = true

                broadcastUpdate(id, parameters["attachments"][i])
                -- if disableGunstockConfiguration == false and id == activeAttachmentID then
                --     executeTransformChange(id, nil, uevrUtils.rotator(rot.x, rot.y, rot.z), uevrUtils.vector(offhandLocationOffset.x, offhandLocationOffset.y, offhandLocationOffset.z))
                -- end
                break
            end
        end
	end
end

local function updateDefaultAttachmentTransforms(pos, rot, scale, offhandLocationOffset)
    for i = 1, #parameters["attachments"] do
        local id = parameters["attachments"][i].id
        local useDefault = configui.getValue(widgetPrefix .. id .. "_use_default")
        local useDefaultOffhandOffset = configui.getValue(widgetPrefix .. id .. "_use_default_offhand_location_offset")
        if useDefault == true and rot ~= nil then
            parameters["attachments"][i].rotation = {rot.x, rot.y, rot.z}
            configui.setValue(widgetPrefix .. id .. "_rotation", parameters["attachments"][i].rotation, true)
            isParametersDirty = true
        end
        if useDefaultOffhandOffset == true and offhandLocationOffset ~= nil then
            parameters["attachments"][i].offhand_location_offset = {offhandLocationOffset.x, offhandLocationOffset.y, offhandLocationOffset.z}
            configui.setValue(widgetPrefix .. id .. "_offhand_location_offset", parameters["attachments"][i].offhand_location_offset, true)
            isParametersDirty = true
        end

        broadcastUpdate(id, parameters["attachments"][i])
            -- if disableGunstockConfiguration == false and id == activeAttachmentID then
            --     executeTransformChange(id, nil, uevrUtils.rotator(rot.x, rot.y, rot.z))
            -- end
    end
end

local function updateSelectedColors(id)
	for i = 1, #parameters["attachments"] do
		local p_id = parameters["attachments"][i].id
		configui.setColor(widgetPrefix .. p_id, "#FFFFFFFF")
	end

    if id ~= nil then
	    configui.setColor(widgetPrefix .. id, "#0088FFFF")
    end
end

function M.setActive(id)
    updateSelectedColors(id)
    if id == nil then return end
    activeAttachmentID = id

    local rot = nil
    local offhandLocationOffset = nil
    if disableGunstockConfiguration == false then
        local attachment = getAttachment(id)
        if attachment ~= nil then
            rot = uevrUtils.rotator(attachment.rotation)
            offhandLocationOffset = uevrUtils.vector(attachment.offhand_location_offset)
            --print("Setting gunstock rotation for " .. id .. " to " .. tostring(rot.Pitch) .. ", " .. tostring(rot.Yaw) .. ", " .. tostring(rot.Roll))
            --input.setAimRotationOffset(rot)
        end
    end
    if rot == nil then rot = uevrUtils.rotator(0,0,0) end
    if offhandLocationOffset == nil then offhandLocationOffset = uevrUtils.vector(0,0,0) end
    --executeAimRotationOffsetChangeCallback(rot)
    executeTransformChange(id, nil, rot, offhandLocationOffset)
    return rot
end

function M.disable(val)
    disableGunstockConfiguration = val
    configui.setValue(widgetPrefix .. "disable_configuration", val, true)
    M.setActive(activeAttachmentID)
end

configui.onCreateOrUpdate(widgetPrefix .. "disable_configuration", function(value)
    M.disable(value)
end)
configui.onUpdate(widgetPrefix .. "default_rotation", function(value)
    updateDefaultAttachmentTransforms(nil, value, nil)
end)
configui.onUpdate(widgetPrefix .. "default_offhand_location_offset", function(value)
    updateDefaultAttachmentTransforms(nil, nil, nil, value)
end)

uevrUtils.registerUEVRCallback("attachment_grip_changed", function(id, gripHand)
    M.addAdjustment({id = id})
	M.setActive(id)
end)

M.loadParameters()

return M