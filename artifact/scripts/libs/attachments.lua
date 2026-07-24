--[[ 
Usage
    Drop the lib folder containing this file into your project folder
    Add code like this in your script:
        local attachments = require("libs/attachments")
        local isDeveloperMode = true  
        attachments.init(isDeveloperMode)

    Available functions:

    attachments.init(isDeveloperMode, logLevel, defaultLocation, defaultRotation, defaultScale) - initializes the attachments system
        example:
            attachments.init(true, LogLevel.Debug, {0,0,0}, {0,0,0}, {1,1,1})

    attachments.attachToMesh(attachment, mesh, socketName, gripHand, detachFromParent) - attaches an object to a mesh at a specified socket
		The parameter gripHand is used to determine which hand's grip animation to use for the attachment. Set to nil if there is no animation 
		needed or if this is not a grip attachment.
        example:
            attachments.attachToMesh(myAttachment, targetMesh, "hand_socket", Handed.Right, true)

    attachments.attachToController(attachment, controllerID, detachFromParent) - attaches an object to a VR controller
        example:
            attachments.attachToController(myAttachment, Handed.Right, true)

    attachments.detach(attachment, parent) - detaches an object from its parent
        example:
            attachments.detach(myAttachment)

    attachments.registerOnGripUpdateCallback(callback) - registers a callback function that handles automatic grip updates.
		Your callback will be called periodically to request the item that is being gripped in the right or left hand as
		well as the mesh or component being used for the right and left hands. If no item is currently being gripped then return nil.
        If rightMesh or leftMesh are nil then the attachments will be directly attached to the raw controller instead of a component.
		Return parameters are rightAttachment, rightMesh, rightSocketName, leftAttachment, leftMesh, leftSocketName, detachFromParent, allowReattach
		rightAttachment - the object being held in the right hand (or nil if nothing is held)
		rightMesh (optional) - the mesh or component to attach the right attachment to (or nil to attach to raw controller)
		rightSocketName (optional) - the socket name on the right mesh to attach to (or nil for no socket)
		leftAttachment (optional) - the object being held in the left hand (or nil if nothing is held)
		leftMesh (optional) - the mesh or component to attach the left attachment to (or nil to attach to raw controller)
		leftSocketName (optional) - the socket name on the left mesh to attach to (or nil for no socket)
		detachFromParent (optional) - boolean value indicating whether to detach the attachment from its current parent before attaching. Defaults to true
		allowReattach (optional) - boolean value indicating whether to allow reattaching the attachment to its previous parent when detaching from the current mesh/controller. Defaults to false
			Note that when attaching to raw controller, allowReattach is passed to set_permanent() function of UEVR_UObjectHook so
			if you dont want permananent attachment to controller (eg the object will be thrown), allowReattach should be false.
		example:
			attachments.registerOnGripUpdateCallback(function()
				if uevrUtils.getValid(pawn) ~= nil and pawn.GetCurrentWeapon ~= nil then
					local currentWeapon = pawn:GetCurrentWeapon()
					if currentWeapon ~= nil and currentWeapon.RootComponent ~= nil then
						return currentWeapon.RootComponent, hands.getHandComponent(Handed.Right), nil, nil, nil, nil, true
					end
				end
			end)

    attachments.registerOnGripAnimationCallback(callbackFunc) - registers a callback function that will be called when grip animation changes, 
		for example when a new weapon is equipped.
        example:
            attachments.registerOnGripAnimationCallback(function(animationID, gripHand)
                -- Handle grip animation change
                print("Grip animation " .. animationID .. " activated for hand " .. gripHand)
            end)

    attachments.registerAttachmentChangeCallback(callbackFunc) - registers a callback function that will be called when an attachment changes, 
		for example when a new weapon is equipped.
        example:
            attachments.registerAttachmentChangeCallback(function(id, gripHand, attachment)
                -- Handle attachmentchange
                print("Attachment " .. id .. " activated for hand " .. gripHand)
            end)

			
    attachments.detachAttachmentFromMeshes(attachment, reattachToParent) - detaches an object from all meshes
        example:
            attachments.detachAttachmentFromMeshes(myAttachment, true)

    attachments.detachAttachmentsFromMesh(mesh, reattachToParent) - detaches all objects from a specific mesh
        example:
            attachments.detachAttachmentsFromMesh(targetMesh, true)

    attachments.setAttachmentOffset(id, location, rotation) - sets the offset for an attachment relative to its parent
        example:
            attachments.setAttachmentOffset("WP_BerettaAuto9_C_Beretta_Mesh", {0,0,10}, {0,90,0})

    attachments.getAttachmentOffset(attachment) - gets the current position, rotation and scale for an attachment
        example:
            local pos, rot, scale = attachments.getAttachmentOffset(myAttachment)

    attachments.updateAttachmentTransform(pos, rot, scale, id) - updates an attachment's transform
        example:
            attachments.updateAttachmentTransform({0,0,0}, {0,0,0}, {1,1,1}, "WP_BerettaAuto9_C_Beretta_Mesh")

    attachments.setActiveAnimation(attachment, gripHand) - sets the active grip animation for an attachment
        example:
            attachments.setActiveAnimation(myAttachment, Handed.Right)

    attachments.getCurrentGripAnimation(handed) - gets the current grip animation for a controller
        example:
            local anim = attachments.getCurrentGripAnimation(Handed.Right)

    attachments.updateAttachmentAnimation(id, animationIndex) - updates the animation for an attachment
        example:
            attachments.updateAttachmentAnimation("WP_BerettaAuto9_C_Beretta_Mesh", 1)

    attachments.setLogLevel(val) - sets the logging level for attachment messages
        example:
            attachments.setLogLevel(LogLevel.Debug)

    attachments.setAttachmentNames(attachmentNamesList) - sets the list of available attachment names
        example:
            attachments.setAttachmentNames({"weapon", "tool", "item"})

    attachments.setAnimationIDs(animationIDList) - sets the available animation IDs and their display labels
        example:
            attachments.setAnimationIDs({
                grip_pistol = {label = "Pistol Grip"},
                grip_rifle = {label = "Rifle Grip"}
            })
	attachments.getCurrentGrippedAttachment(gripHand) - gets the attachment currently gripped by the specified hand
		example:
			local currentAttachment = attachments.getCurrentGrippedAttachment(Handed.Right)
			
    attachments.isActiveAttachmentMelee(hand) - checks if the attachment gripped by the specified hand is marked as melee
        example:
            local isMelee = attachments.isActiveAttachmentMelee(Handed.Right)

    attachments.isActiveAttachmentScoped(hand) - checks if the attachment gripped by the specified hand is marked as scoped
        example:
            local isScoped = attachments.isActiveAttachmentScoped(Handed.Right)

    attachments.isActiveAttachmentTwoHanded(hand) - checks if the attachment gripped by the specified hand is marked as two-handed
        example:
            local isTwoHanded = attachments.isActiveAttachmentTwoHanded(Handed.Right)

    attachments.allowChildVisibilityHandling(value) - sets whether attachments will control the visibility of their child components
        value - boolean, true to allow child visibility handling, false to disable
        example:
            attachments.allowChildVisibilityHandling(true)

    attachments.setGripUpdateTimeout(timeout) - determines how often to check for grip attachment changes
		setting higher values can make weapon switch animations look better but can add input lag to attachment changes
        timeout - the timeout value in milliseconds
        example:
            attachments.setGripUpdateTimeout(200)

]]--

local uevrUtils = require("libs/uevr_utils")
local configui = require("libs/configui")
local controllers = require("libs/controllers")
local scope = require('libs/scope')
local laser = require('libs/laser')
local accessoriesConfig = require('libs/config/accessories_config_dev')

--local debugger = require("libs/uevr_debug")

local M = {}

M.AttachType =
{
    MESH = 0,
    CONTROLLER = 1,
    RAW_CONTROLLER = 2,
    VIRTUAL = 3,  -- Tracked for UI/animation only; no physical K2_AttachTo/DetachFromParent calls
}

--how often to check for grip updates
local gripUpdateTimeout = 200 --milliseconds

local parametersFileName = "attachments_parameters"
local parameters = {}
local isParametersDirty = false

local configFileName = "dev/attachments_config_dev"
local widgetPrefix = "uevr_attachments_"

local attachmentNames = {}
local attachmentOffsets = {}
local attachmentOffsetsLookup = {}

local attachmentLasers = {}
local attachmentScopes = {}
local laserColor = "#FF0000FF" --red by default

--use supplied function that can give additional insight into whether or not a scope should be displayed
local scopeActiveCallback = nil

--local activeAttachment = nil
local defaultLocation = nil
local defaultRotation = nil
local defaultScale = nil
local animationLabels = {"Default", "None"}
local animationIDs = {"", "attachment_none"}
--local activeAnimationID = false

local gunstockOffsetsEnabled = true
local gunstockRotationOffset = uevrUtils.rotator(0,0,0)
local gunstockOffhandLocationOffset = uevrUtils.vector(0,0,0)

local meshAttachmentList = {}
local activeGripAnimations = {}
--local attachmentCallbacks = {}

local stripParentNameNumericSuffix = false
local allowChildVisibilityHandling = true --attachments will set the visibility of child components based on this flag
local useZeroTransformOnReattach = true --when reattaching an attachment, use zero transform instead of original transform

local baseSettings = {
	rotation = {0,0,0},
}
local currentLogLevel = LogLevel.Error
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
	if logLevel == nil then logLevel = LogLevel.Debug end
	if logLevel <= currentLogLevel then
		uevrUtils.print("[attachments] " .. text, logLevel)
	end
end

--called when an attachment that is a grip attachment has changed
local function executeGripAttachmentChanged(...)
	uevrUtils.executeUEVRCallbacks("attachment_grip_changed", table.unpack({...}))
end

local function executeGripAttachmentRotationChange(...)
	uevrUtils.executeUEVRCallbacks("attachment_grip_rotation_change", table.unpack({...}))
end

local function executeGripAnimationChange(...)
	uevrUtils.executeUEVRCallbacks("attachment_grip_animation_changed", table.unpack({...}))
end


local helpText = "This module allows you to configure attachment offsets for objects attached to meshes or controllers. You can specify position, rotation, scale, and grip animation for each attachment. New entries are added each time a new mesh is attached. Items colored blue indicate the currently selected right hand attachment. Items colored green indicate the currently selected left hand attachment. Items colored purple indicate the attachment is currently attached to both hands."

function M.addAttachmentOffsetsToConfigUI(configDefinition, m_attachmentOffsets)
	if m_attachmentOffsets == nil then m_attachmentOffsets = attachmentOffsets end
	table.insert(configDefinition[1]["layout"],
		{
			widgetType = "tree_node",
			id = widgetPrefix .. "offsets",
			initialOpen = true,
			label = "Attachment Configuration"
		}
	)

	if #m_attachmentOffsets == 0 then
		table.insert(configDefinition[1]["layout"],
			{
				widgetType = "text",
				id = widgetPrefix .. "no_attachments_configured",
				label = "No attachments configured yet. Either implement the attachments.registerOnGripUpdateCallback(callback) function or manually call the attachments.attachToMesh() function as described in attachments.lua.",
				wrapped = true
			}
		)
	end

	for i = 1, #m_attachmentOffsets do
		local parent = m_attachmentOffsets[i]["parent"]
		local child = m_attachmentOffsets[i]["child"]
		local id = m_attachmentOffsets[i]["id"]
		if id == nil then id = parent .. "_" .. child end
		m_attachmentOffsets[i]["id"] = id
		local name = id
		local pos = m_attachmentOffsets[i]["location"]
		local rot = m_attachmentOffsets[i]["rotation"]
		local scale = m_attachmentOffsets[i]["scale"]
		local isMelee = m_attachmentOffsets[i]["melee"] or false
		local isTwoHanded = m_attachmentOffsets[i]["two_handed"] or false
		local isScoped = m_attachmentOffsets[i]["scoped"] or false
		local animation = m_attachmentOffsets[i]["animation"]
		local anyChild = m_attachmentOffsets[i]["any_child"] and true or false
		local anyParent = m_attachmentOffsets[i]["any_parent"] and true or false
		local meleeRotationOffset = m_attachmentOffsets[i]["melee_rotation_offset"] or {0,0,0}
		--local useSightsPositionOffset = m_attachmentOffsets[i]["use_sights_position_offset"] or false
		local sightsPositionOffset = m_attachmentOffsets[i]["sights_position_offset"] or {0,0,0}
		local useLaser = m_attachmentOffsets[i]["use_laser"] or false

		local selectedIndex = 1
		for j = 1, #animationIDs do
			if animation == animationIDs[j] then
				selectedIndex = j
			end
		end

		table.insert(configDefinition[1]["layout"],
				{
					id = widgetPrefix .. name, label = name, widgetType = "tree_node",
				}
		)
		table.insert(configDefinition[1]["layout"],
					{
						id = widgetPrefix .. name .. "_position", label = "Position",
						widgetType = "drag_float3", speed = .1, range = {-500, 500}, initialValue = pos
					}
		)
		table.insert(configDefinition[1]["layout"],
					{
						id = widgetPrefix .. name .. "_rotation", label = "Rotation",
						widgetType = "drag_float3", speed = .1, range = {-360, 360}, initialValue = rot
					}
		)
		table.insert(configDefinition[1]["layout"],
					{
						id = widgetPrefix .. name .. "_scale", label = "Scale",
						widgetType = "drag_float3", speed = .1, range = {0.01, 10}, initialValue = scale
					}
		)
		table.insert(configDefinition[1]["layout"],
			{
				id = widgetPrefix .. name .. "_sights_position_offset", label = "Sights Position Offset",
				widgetType = "drag_float3", speed = .1, range = {-500, 500}, initialValue = sightsPositionOffset,  width = 250
			}
		)
		table.insert(configDefinition[1]["layout"],
            {
                widgetType = "checkbox",
                id =  widgetPrefix .. name .. "_is_melee",
                label = "Melee",
                initialValue = isMelee
            }
		)
		table.insert(configDefinition[1]["layout"],{ widgetType = "indent", width = 20 })
		table.insert(configDefinition[1]["layout"],
			{
				id = widgetPrefix .. name .. "_melee_rotation_offset", label = "Melee Rotation Offset",
				widgetType = "drag_float3", speed = .1, range = {-360, 360}, initialValue = meleeRotationOffset, isHidden = isMelee ~= true, width = 250
			}
		)
		table.insert(configDefinition[1]["layout"],{ widgetType = "unindent", width = 20 })
		table.insert(configDefinition[1]["layout"],
            {
                widgetType = "checkbox",
                id =  widgetPrefix .. name .. "_is_two_handed",
                label = "Two Handed",
                initialValue = isTwoHanded
            }
		)
		table.insert(configDefinition[1]["layout"],
            {
                widgetType = "checkbox",
                id =  widgetPrefix .. name .. "_use_laser",
                label = "Use Laser",
                initialValue = useLaser
            }
		)
		table.insert(configDefinition[1]["layout"],
            {
                widgetType = "checkbox",
                id =  widgetPrefix .. name .. "_is_scoped",
                label = "Scoped",
                initialValue = isScoped
            }
		)


		table.insert(configDefinition[1]["layout"], { widgetType = "begin_group", id = widgetPrefix .. "scope_group_" .. name, isHidden = false })
		table.insert(configDefinition[1]["layout"],
			{
				id = widgetPrefix .. "scope_settings_" .. name, label = "Scope Settings", widgetType = "tree_node",
			}
		)
		local scopeWidgets = scope.getConfigWidgets(widgetPrefix .. name .. "_")
		for j = 1, #scopeWidgets do
			table.insert(configDefinition[1]["layout"], scopeWidgets[j])
		end
		table.insert(configDefinition[1]["layout"],
			{
				widgetType = "tree_pop"
			}
		)
		table.insert(configDefinition[1]["layout"], { widgetType = "end_group" })


		-- table.insert(configDefinition[1]["layout"],
        --     {
        --         widgetType = "checkbox",
        --         id =  "attachment_" .. name .. "_use_sights_position_offset",
        --         label = "Sights",
        --         initialValue = useSightsPositionOffset
        --     }
		-- )
		-- table.insert(configDefinition[1]["layout"],{ widgetType = "indent", width = 20 })
		-- table.insert(configDefinition[1]["layout"],
		-- 	{
		-- 		id = "attachment_" .. name .. "_sights_position_offset", label = "Sights Position Offset",
		-- 		widgetType = "drag_float3", speed = .1, range = {-500, 500}, initialValue = sightsPositionOffset, isHidden = useSightsPositionOffset ~= true, width = 250
		-- 	}
		-- )
		-- table.insert(configDefinition[1]["layout"],{ widgetType = "unindent", width = 20 })
		table.insert(configDefinition[1]["layout"],
			{
				id = widgetPrefix .. name .. "_grip_animation", label = "Grip Animation",
				widgetType = "combo", selections = animationLabels, initialValue = selectedIndex
			}
		)

		local accessoriesWidgets = accessoriesConfig.getConfigWidgets(name, widgetPrefix .. name .. "_", 300)
		for j = 1, #accessoriesWidgets do
			table.insert(configDefinition[1]["layout"], accessoriesWidgets[j])
		end

		table.insert(configDefinition[1]["layout"],
            {
                widgetType = "checkbox",
                id =  widgetPrefix .. name .. "_any_child",
                label = "Use for all children",
                initialValue = anyChild
            }
		)
		table.insert(configDefinition[1]["layout"],
            { widgetType = "same_line" }
		)
		table.insert(configDefinition[1]["layout"],
            {
                widgetType = "checkbox",
                id =  widgetPrefix .. name .. "_any_parent",
                label = "Use for all parents",
                initialValue = anyParent
            }
		)
		table.insert(configDefinition[1]["layout"],
				{
					widgetType = "tree_pop"
				}
		)

		scope.createConfigCallbacks(name, widgetPrefix .. name .. "_")

		accessoriesConfig.createConfigCallbacks(name, widgetPrefix .. name .. "_")

		configui.onUpdate(widgetPrefix .. name .. "_position", function(value)
			M.updateAttachmentTransform(value, nil, nil, id)
		end)
		configui.onUpdate(widgetPrefix .. name .. "_rotation", function(value)
			M.updateAttachmentTransform(nil, value, nil, id)
		end)
		configui.onUpdate(widgetPrefix .. name .. "_scale", function(value)
			M.updateAttachmentTransform(nil, nil, value, id)
		end)
		configui.onCreateOrUpdate(widgetPrefix .. name .. "_is_melee", function(value)
			M.updateAttachmentIsMelee(id, value)
			configui.setHidden(widgetPrefix .. name .. "_melee_rotation_offset", not value)
		end)
		configui.onCreateOrUpdate(widgetPrefix .. name .. "_is_two_handed", function(value)
			M.updateAttachmentIsTwoHanded(id, value)
		end)
		configui.onCreateOrUpdate(widgetPrefix .. name .. "_is_scoped", function(value)
			M.updateAttachmentIsScoped(id, value)
			configui.setHidden(widgetPrefix .. "scope_group_" .. name, not value)
		end)
		configui.onCreateOrUpdate(widgetPrefix .. name .. "_any_child", function(value)
			M.updateAttachmentUseAnyChild(id, value)
		end)
		configui.onCreateOrUpdate(widgetPrefix .. name .. "_any_parent", function(value)
			M.updateAttachmentUseAnyParent(id, value)
		end)
		configui.onUpdate(widgetPrefix .. name .. "_grip_animation", function(value)
			M.updateAttachmentAnimation(id, value)
		end)
		configui.onUpdate(widgetPrefix .. name .. "_melee_rotation_offset", function(value)
			M.updateMeleeRotationOffset(value, id)
		end)
		-- configui.onCreateOrUpdate(widgetPrefix .. name .. "_use_sights_position_offset", function(value)
		-- 	M.updateAttachmentUseSightsPositionOffset(id, value)
		-- 	configui.setHidden(widgetPrefix .. name .. "_sights_position_offset", not value)
		-- end)
		configui.onUpdate(widgetPrefix .. name .. "_sights_position_offset", function(value)
			M.updateSightsPositionOffset(value, id)
		end)
		configui.onCreateOrUpdate(widgetPrefix .. name .. "_use_laser", function(value)
			M.updateAttachmentHasLaser(id, value)
		end)

	end

	table.insert(configDefinition[1]["layout"],
		{
			widgetType = "tree_pop"
		}
	)
	table.insert(configDefinition[1]["layout"],
		{ widgetType = "new_line" }
	)
	table.insert(configDefinition[1]["layout"],
		{
			widgetType = "tree_node",
			id = "uevr_attachments_advanced_tree",
			initialOpen = false,
			label = "Advanced"
		}
	)
	table.insert(configDefinition[1]["layout"],
		{
			id = "uevr_attachment_base_rotation", label = "Base Rotation",
			widgetType = "drag_float3", speed = .1, range = {-360, 360}, initialValue = baseSettings.rotation
		}
	)
	table.insert(configDefinition[1]["layout"],
		{
			widgetType = "checkbox",
			id = "use_uevr_attachments_strip_parent_name_numeric_suffix",
			label = "Strip numeric suffix from parent attachment names",
			initialValue = stripParentNameNumericSuffix
		}
	)
	table.insert(configDefinition[1]["layout"],
		{
			widgetType = "tree_pop"
		}
	)
	table.insert(configDefinition[1]["layout"],
		{ widgetType = "new_line" }
	)
	table.insert(configDefinition[1]["layout"],
		{
			widgetType = "tree_node",
			id = "uevr_attachments_help_tree",
			initialOpen = true,
			label = "Help"
		}
	)
	table.insert(configDefinition[1]["layout"],
		{
			widgetType = "text",
			id = "uevr_attachments_help",
			label = helpText,
			wrapped = true
		}
	)
	table.insert(configDefinition[1]["layout"],
		{
			widgetType = "tree_pop"
		}
	)
	return configDefinition
end

function M.loadParameters(fileName)
	if fileName ~= nil then parametersFileName = fileName end
	M.print("Loading attachments parameters " .. parametersFileName)
	parameters = json.load_file(parametersFileName .. ".json")

	if parameters == nil then
		parameters = {}
		M.print("Creating attachments parameters")
	end
	if parameters["attachmentOffsets"] == nil then
		parameters["attachmentOffsets"] = {}
		isParametersDirty = true
	end
	if parameters["baseOffsets"] == nil then
		parameters["baseOffsets"] = {location = {0,0,0}, rotation = {0,0,0}, scale = {1,1,1}}
		isParametersDirty = true
	end
	if parameters["baseOffsets"]["rotation"] == nil then
		parameters["baseOffsets"]["rotation"] = {0,0,0}
		isParametersDirty = true
	end
	for i = 1, #parameters["attachmentOffsets"] do
		local parent = parameters["attachmentOffsets"][i]["parent"]
		local child = parameters["attachmentOffsets"][i]["child"]
		local id = parameters["attachmentOffsets"][i]["id"]
		if id == nil then id = parent .. "_" .. child end
		parameters["attachmentOffsets"][i]["id"] = id
		isParametersDirty = true
	end
	attachmentOffsets = parameters["attachmentOffsets"]
	if parameters["stripParentNameNumericSuffix"] ~= nil then
		stripParentNameNumericSuffix = parameters["stripParentNameNumericSuffix"]
	end
end

local function saveParameters()
	M.print("Saving attachments parameters " .. parametersFileName)
	json.dump_file(parametersFileName .. ".json", parameters, 4)
end

local createDevMonitor = doOnce(function()
    uevrUtils.setInterval(1000, function()
        if isParametersDirty == true then
            saveParameters()
            isParametersDirty = false
        end
    end)
end, Once.EVER)

local function getDefaultConfig()
	return  {
		{
			panelLabel = "Attachments Config Dev",
			saveFile = configFileName,
			layout =
			{
			}
		}
	}
end

function M.showDeveloperConfiguration(m_defaultLocation, m_defaultRotation, m_defaultScale)
	defaultLocation = m_defaultLocation
	defaultRotation = m_defaultRotation
	defaultScale = m_defaultScale

	local configDefinition = M.addAttachmentOffsetsToConfigUI(getDefaultConfig())
	configui.create(configDefinition)
end

local function registerAttachmentCallback(callbackName, callbackFunc)
	uevrUtils.registerUEVRCallback(callbackName, callbackFunc)
	-- if attachmentCallbacks[callbackName] == nil then attachmentCallbacks[callbackName] = {} end
	-- for i, existingFunc in ipairs(attachmentCallbacks[callbackName]) do
	-- 	if existingFunc == callbackFunc then
	-- 		--print("Function already exists")
	-- 		return
	-- 	end
	-- end
	-- table.insert(attachmentCallbacks[callbackName], callbackFunc)
end
-- local function executeAttachmentCallbacks(callbackName, ...)
-- 	uevrUtils.executeUEVRCallbacks(callbackName, reusable_hit_result)
-- 	-- if attachmentCallbacks[callbackName] ~= nil then
-- 	-- 	for i, func in ipairs(attachmentCallbacks[callbackName]) do
-- 	-- 		func(table.unpack({...}))
-- 	-- 	end
-- 	-- end
-- end

function M.init(isDeveloperMode, logLevel, m_defaultLocation, m_defaultRotation, m_defaultScale)
    if logLevel ~= nil then
        M.setLogLevel(logLevel)
    end
    if isDeveloperMode == nil and uevrUtils.getDeveloperMode() ~= nil then
        isDeveloperMode = uevrUtils.getDeveloperMode()
    end

	scope.init()
	accessoriesConfig.init(isDeveloperMode, logLevel, M)

    if isDeveloperMode then
		--backward compatibility
		if json.load_file("attachments_config_dev.json") ~= nil then
			configFileName = "attachments_config_dev"
			widgetPrefix = "attachment_"
		end

	    M.showDeveloperConfiguration(m_defaultLocation, m_defaultRotation, m_defaultScale)
        createDevMonitor()
    end

end

local function strip_after_last_underscore(str)
    local last = str:match("^(.*)_.*$")
    return last or str
end
local function stripTrailingNumbers(str)
    return str:match("^(.-)%d*$")
end

local function getOverrideChildname(parentName)
	--print("getOverrideChildname for parentName " .. parentName)
	for i = 1, #attachmentOffsets do
		if attachmentOffsets[i]["parent"] == parentName and attachmentOffsets[i]["any_child"] == true then
			--print("Found any_child override for parent name " .. parentName)
			return attachmentOffsets[i]["child"]
		end
	end
	--print("No override child name found")
	return ""
end

local function getOverrideParentname(childName)
	--print("getOverrideParentname for childName " .. childName)
	for i = 1, #attachmentOffsets do
		if attachmentOffsets[i]["child"] == childName and attachmentOffsets[i]["any_parent"] == true then
			--print("Found any_parent override for child name " .. childName)
			return attachmentOffsets[i]["parent"]
		end
	end
	--print("No override parent name found")
	return ""
end

local function getAttachmentNames(attachment)
	local attachmentParentName = uevrUtils.getShortName(attachment:get_outer())
	local attachmentNameNoNumberSuffix = stripTrailingNumbers(attachmentParentName)
	if string.sub(attachmentNameNoNumberSuffix, -1, -1) ~= "_" then
		attachmentParentName = attachmentNameNoNumberSuffix
	else
		attachmentParentName = strip_after_last_underscore(attachmentParentName) -- strip off anything after the last underscore
	end
	if stripParentNameNumericSuffix then
		attachmentParentName = stripTrailingNumbers(attachmentParentName)
	end

	local attachmentChildName = getOverrideChildname(attachmentParentName)
	if attachmentChildName == "" then
		if attachment.StaticMesh ~= nil then
			attachmentChildName = uevrUtils.getShortName(attachment.StaticMesh)
		elseif attachment.SkeletalMesh ~= nil then
			attachmentChildName = uevrUtils.getShortName(attachment.SkeletalMesh)
		else
			attachmentChildName = uevrUtils.getShortName(attachment)
		end
	end


	local attachmentParentName_Alt = getOverrideParentname(attachmentChildName)
	if attachmentParentName_Alt ~= "" then
		attachmentParentName = attachmentParentName_Alt
	end

	--print("getAttachmentNames",attachmentParentName, attachmentChildName)
	return attachmentParentName, attachmentChildName, attachmentParentName .. "_" .. attachmentChildName
end

local function hasNamedObject(attachment, parentName, childName)
	--M.print("Called hasNamedObject with parent: " .. parentName .. " child: " .. childName)
	local result = false
	if parentName == nil or parentName == "" then
		result = true
	else
		result = not not string.find(attachment:get_full_name(), parentName)
	end

	if result then
		if not(childName == nil or childName == "") then
			if attachment.StaticMesh ~= nil then
				--print("Static Mesh",attachment.StaticMesh:get_full_name())
				result = not not string.find(attachment.StaticMesh:get_full_name(), childName)
			elseif attachment.SkeletalMesh ~= nil then
				--print("Skeletal Mesh",attachment.SkeletalMesh:get_full_name())
				result = not not string.find(attachment.SkeletalMesh:get_full_name(), childName)
			else
				result = not not string.find(attachment:get_full_name(), childName)
			end
		else
			result = false
		end
	end
	--M.print("hasNamedObject result is " .. (result and "true" or "false"))
	return result
end

-- function M.getActiveAttachment()
-- 	return activeAttachment
-- end

function M.addAttachmentToConfig(attachment)
	if parameters ~= nil then
		local attachmentParentName, attachmentChildName, id = getAttachmentNames(attachment)

		local exists = false
		--if configuration["attachmentOffsets"] == nil then configuration["attachmentOffsets"] = {} end
		if parameters["attachmentOffsets"] ~= nil then
			for i = 1, #parameters["attachmentOffsets"] do
				if attachmentParentName == attachmentOffsets[i]["parent"] and attachmentChildName == attachmentOffsets[i]["child"] then
					exists = true
				end
			end
			if not exists then
				M.print("Adding attachment to config " .. attachmentParentName .. " - " .. attachmentChildName)
				local attachmentLocation =  defaultLocation or {attachment.RelativeLocation.X, attachment.RelativeLocation.Y, attachment.RelativeLocation.Z}
				local attachmentRotation = defaultRotation or {attachment.RelativeRotation.Pitch, attachment.RelativeRotation.Yaw, attachment.RelativeRotation.Roll}
				local attachmentScale = defaultScale or {attachment.RelativeScale3D.X, attachment.RelativeScale3D.Y, attachment.RelativeScale3D.Z}

				table.insert(parameters["attachmentOffsets"], {id = id, parent=attachmentParentName, child=attachmentChildName, location=attachmentLocation, rotation=attachmentRotation, scale=attachmentScale})
				isParametersDirty = true

				attachmentOffsets = parameters["attachmentOffsets"]
				local configDefinition = M.addAttachmentOffsetsToConfigUI(getDefaultConfig())
				configui.update(configDefinition)
			end
		end
	end
end

function M.setAttachmentNames(attachmentNamesList)
	attachmentNames = attachmentNamesList
	attachmentOffsets = {}
	for i, attachmentName in ipairs(attachmentNames) do
		table.insert(attachmentOffsets, {parent=attachmentName, child="", location=defaultLocation or {0,0,0}, rotation=defaultRotation or {0,0,0}, scale=defaultScale or {1,1,1}})
	end
end

local function getAttachmentOffsetByID(id)
	if attachmentOffsetsLookup[id] ~= nil then
		return attachmentOffsetsLookup[id]
	end
	for i = 1, #attachmentOffsets do
		local attachmentID = attachmentOffsets[i]["id"]
		if id == attachmentID then
			attachmentOffsetsLookup[id] = attachmentOffsets[i]
			return attachmentOffsets[i]
		end
	end
	return nil
end

function M.getAttachmentOffset(attachment)
	local attachmentLocation = {0,0,0}
	local attachmentRotation = {0,0,0}
	local attachmentScale = {1,1,1}

	if uevrUtils.getValid(attachment) ~= nil then
		for i = 1, #attachmentOffsets do
			local parent = attachmentOffsets[i]["parent"]
			local child = attachmentOffsets[i]["child"]
			local id = attachmentOffsets[i]["id"]
			--local name = parent .. "_" .. child
			--if hasNamedObject(attachment, parent, child) then
			local _, _, attachmentID = getAttachmentNames(attachment)
			if id == attachmentID then
				local position = attachmentOffsets[i]["location"]
				if position == nil then
					position = configui.getValue(widgetPrefix .. id .. "_position")
				-- else
				-- 	configui.setValue(widgetPrefix .. id .. "_position", position)
				end
				-- local position = configui.getValue(widgetPrefix .. id .. "_position")
				-- if position == nil then position = attachmentOffsets[i]["location"] end

				local rotation = attachmentOffsets[i]["rotation"]
				if rotation == nil then rotation = configui.getValue(widgetPrefix .. id .. "_rotation") end
				--local rotation = configui.getValue(widgetPrefix .. id .. "_rotation")
				--if rotation == nil then rotation = attachmentOffsets[i]["rotation"] end

				local scale = attachmentOffsets[i]["scale"]
				if scale == nil then scale = configui.getValue(widgetPrefix .. id .. "_scale") end
				-- local scale = configui.getValue(widgetPrefix .. id .. "_scale")
				-- if scale == nil then scale = attachmentOffsets[i]["scale"] end
				if scale == nil then --set a fixed scale in case something else tries to change it
					attachmentOffsets[i]["scale"] = {attachment.RelativeScale3D.X, attachment.RelativeScale3D.Y, attachment.RelativeScale3D.Z}
					scale = attachmentOffsets[i]["scale"]
				end

				return uevrUtils.vector(position), uevrUtils.rotator(rotation), uevrUtils.vector(scale)
			end
		end
		attachmentLocation = {attachment.RelativeLocation.X, attachment.RelativeLocation.Y, attachment.RelativeLocation.Z}
		attachmentRotation = {attachment.RelativeRotation.Pitch, attachment.RelativeRotation.Yaw, attachment.RelativeRotation.Roll}
		attachmentScale = {attachment.RelativeScale3D.X, attachment.RelativeScale3D.Y, attachment.RelativeScale3D.Z}
	end

	if defaultLocation ~= nil then attachmentLocation = defaultLocation end
	if defaultRotation ~= nil then attachmentRotation = defaultRotation end
	if defaultScale ~= nil then attachmentScale = defaultScale end

	--we didnt find an existing attachment. Add it to config if config is enabled
	M.addAttachmentToConfig(attachment)

	return uevrUtils.vector(attachmentLocation), uevrUtils.rotator(attachmentRotation), uevrUtils.rotator(attachmentScale)
end


-- function M.setAttachmentOffset(parentName, childName, location, rotation)
-- 	for i = 1, #attachmentOffsets do
-- 		local parent = attachmentOffsets[i]["parent"]
-- 		local child = attachmentOffsets[i]["child"]
-- 		if parentName == parent and childName == child then
-- 			if location ~= nil then attachmentOffsets[i]["location"] = {location.X, location.Y, location.Z} end
-- 			if rotation ~= nil then attachmentOffsets[i]["rotation"] = {rotation.X, rotation.Y, rotation.Z} end
-- 		end
-- 	end
-- 	parameters["attachmentOffsets"] = attachmentOffsets
-- 	isParametersDirty = true
-- end

--there can be the same attachment class in both hands so we need to return all of them
local function getAttachmentDataFromMeshAttachmentList(id)
	local resultArray = {}
	for meshName, meshData in pairs(meshAttachmentList) do
		for attachmentName, attachmentData in pairs(meshData.attachments or {}) do
			local ok, result = pcall(function()
				if attachmentData == nil then
					M.print("getAttachmentDataFromMeshAttachmentList had nil attachmentData " .. id)
				elseif uevrUtils.getValid(attachmentData.attachment) ~= nil then
					local _, _, attachmentID = getAttachmentNames(attachmentData.attachment)
					M.print("Checking attachment " .. attachmentID .. " against " .. id)
					if id == attachmentID then
						M.print("Found matching attachment " .. attachmentID)
						return attachmentData --.attachment, attachmentData.attachType, attachmentData.state
					end
				end
			end)
			if not ok then
				M.print("Error in getAttachmentDataFromMeshAttachmentList: ")
				meshData.attachments[attachmentName] = nil
			end
			if ok and result ~= nil then
				table.insert(resultArray, result)
			end
		end
	end
	return resultArray
end

function M.updateMeleeRotationOffset(rotationOffset, id)
	for i = 1, #attachmentOffsets do
		local attachmentID = attachmentOffsets[i]["id"]
		if id == attachmentID then
			attachmentOffsets[i]["melee_rotation_offset"] = {rotationOffset.X, rotationOffset.Y, rotationOffset.Z}
		end
	end
	parameters["attachmentOffsets"] = attachmentOffsets
	isParametersDirty = true
end

function M.getMeleeRotationOffset(id)
	for i = 1, #attachmentOffsets do
		local attachmentID = attachmentOffsets[i]["id"]
		if id == attachmentID then
			local rot = attachmentOffsets[i]["melee_rotation_offset"]
			if rot ~= nil then
				return uevrUtils.rotator(rot)
				--return kismet_math_library:ComposeRotators(uevrUtils.rotator(rot),uevrUtils.rotator(parameters["baseOffsets"]["rotation"])) --uevrUtils.rotator(rot)
			end
		end
	end
	return uevrUtils.rotator(0,0,0)
end

-- local function handleScope(id, attachment, gripHand)
-- 	if M.isActiveAttachmentScoped(gripHand) and (scopeActiveCallback == nil or scopeActiveCallback(attachment)) then
-- 		scope.createAndAttach(id, attachment)
-- 	else
-- 		M.print("No weapon scope settings found. Destroying scope")
-- 		scope.destroy()
-- 	end
-- end

-- Scopes ------------------------------------------------
local function createScopeForAttachment(id,attachment, gripHand)
	attachmentScopes[gripHand] = scope.new(id)
	attachmentScopes[gripHand]:attachTo(attachment)
	return attachmentScopes[gripHand]
end

local function destroyScopeForGripHand(gripHand)
	if attachmentScopes[gripHand] ~= nil then
		attachmentScopes[gripHand]:destroy()
		attachmentScopes[gripHand] = nil
	end
end

local function updateScopeForAttachment(id, attachment, gripHand)
	if M.isActiveAttachmentScoped(gripHand) and (scopeActiveCallback == nil or scopeActiveCallback(attachment)) then
		if attachmentScopes[gripHand] == nil then
			createScopeForAttachment(id, attachment, gripHand)
		end
	else
		destroyScopeForGripHand(gripHand)
	end
end

local function updateScopeForAttachmentID(id)
	local attachmentDataArray = getAttachmentDataFromMeshAttachmentList(id)
	--local attachment, _, _ = getAttachmentDataFromMeshAttachmentList(id)
	if attachmentDataArray ~= nil and #attachmentDataArray > 0 then
		for j = 1, #attachmentDataArray do
			local attachmentData = attachmentDataArray[j]
			if attachmentData ~= nil and uevrUtils.getValid(attachmentData.attachment) ~= nil and attachmentData.gripHand ~= nil then
				updateScopeForAttachment(id, attachmentData.attachment, attachmentData.gripHand)
			end
		end
	end
end

function M.getSocketsForAttachmentID(id, callback)
	local attachmentDataArray = getAttachmentDataFromMeshAttachmentList(id)
	if attachmentDataArray ~= nil and #attachmentDataArray > 0 then
		for j = 1, #attachmentDataArray do
			local attachmentData = attachmentDataArray[j]
			if attachmentData ~= nil and uevrUtils.getValid(attachmentData.attachment) ~= nil and attachmentData.gripHand ~= nil then
				uevrUtils.getSocketNames(attachmentData.attachment, callback)
			end
		end
	end
end
--------------------------------------------------------


--- Lasers ---------------------------------------------
local function createLaserForAttachment(attachment, gripHand)
	--subscribeToLineTracer(gripHand)
	local lengthSettings = {
        type = laser.LengthType.CAMERA,
        lengthPercentage = 1.0
    }
	--attachmentLasers[gripHand] = laser.new({laserColor = laserColor, lengthSettings = lengthSettings, target = {type = "particle", options = {particleSystemAsset = "ParticleSystem /Game/Art/VFX/ParticleSystems/Weapons/Projectiles/Plasma/PS_Plasma_Ball.PS_Plasma_Ball", scale = {0.04, 0.04, 0.04}, autoActivate = true}}})
	attachmentLasers[gripHand] = laser.new({laserColor = laserColor, lengthSettings = lengthSettings})
	attachmentLasers[gripHand]:attachTo(attachment)--, "Sight_Socket")
	attachmentLasers[gripHand]:setRelativePosition(M.getActiveAttachmentSightsPositionOffset(gripHand))
	local rot = parameters["baseOffsets"]["rotation"]
	if rot ~= nil then
		attachmentLasers[gripHand]:setRelativeRotation(uevrUtils.rotator(rot))
	end
	--attachmentLasers[gripHand]:setLength(50)
	return attachmentLasers[gripHand]
end

local function destroyLaserForGripHand(gripHand)
	--unsubscribeFromLineTracer(gripHand)
	if attachmentLasers[gripHand] ~= nil then
		attachmentLasers[gripHand]:destroy()
		attachmentLasers[gripHand] = nil
	end
end

local function updateLaserForAttachment(attachment, gripHand)
	if M.isActiveAttachmentLasered(gripHand) then
		if attachmentLasers[gripHand] == nil then
			createLaserForAttachment(attachment, gripHand)
		else
			attachmentLasers[gripHand]:setRelativePosition(M.getActiveAttachmentSightsPositionOffset(gripHand))
		end
	else
		destroyLaserForGripHand(gripHand)
	end
end

local function updateLaserForAttachmentID(id)
	local attachmentDataArray = getAttachmentDataFromMeshAttachmentList(id)
	--local attachment, _, _ = getAttachmentDataFromMeshAttachmentList(id)
	if attachmentDataArray ~= nil and #attachmentDataArray > 0 then
		for j = 1, #attachmentDataArray do
			local attachmentData = attachmentDataArray[j]
			if attachmentData ~= nil and uevrUtils.getValid(attachmentData.attachment) ~= nil and attachmentData.gripHand ~= nil then
				updateLaserForAttachment(attachmentData.attachment, attachmentData.gripHand)
			end
		end
	end
end

function M.setLaserColor(colorHex)
	laserColor = colorHex
	for gripHand, laserInstance in pairs(attachmentLasers) do
		if laserInstance ~= nil then
			laserInstance:setColor(laserColor)
		end
	end
end
---------------------------------------------------------

-- Sights ----------------------------------------------
local sightsCache = {}
function M.updateSightsPositionOffset(positionOffset, id)
	local offset = getAttachmentOffsetByID(id)
	if offset ~= nil then
		offset["sights_position_offset"] = {positionOffset.X, positionOffset.Y, positionOffset.Z}
		sightsCache[id] = nil --the cache will update itself next time it's requested
		updateLaserForAttachmentID(id)
	end
	parameters["attachmentOffsets"] = attachmentOffsets
	isParametersDirty = true
end

function M.getSightsPositionOffset(id)
	if sightsCache[id] ~= nil then
		return sightsCache[id]
	end
	local vector = nil
	local offset = getAttachmentOffsetByID(id)
	if offset ~= nil then
		local pos = offset["sights_position_offset"]
		if pos ~= nil then
			vector = uevrUtils.vector(pos)
		end
	end
	if vector == nil then
		vector = uevrUtils.vector(0,0,0)
	end
	sightsCache[id] = vector
	return vector
end
------------------------------------------------


--My homespun version of kismet_math_library:ComposeRotators
-- local function compose(rotation1, rotation2)
-- 	--Quat_MakeFromEuler expects Roll Pitch Yaw
-- 	local quat1 = kismet_math_library:Quat_MakeFromEuler(uevrUtils.vector(rotation1.Roll, rotation1.Pitch, rotation1.Yaw))
-- 	local quat2 = kismet_math_library:Quat_MakeFromEuler(uevrUtils.vector(rotation2.Roll, rotation2.Pitch, rotation2.Yaw))
-- 	local quat3 = kismet_math_library:Multiply_QuatQuat(quat2, quat1)
-- 	local final = kismet_math_library:Quat_Rotator(quat3)
-- 	return final
-- end

function M.getActiveAttachmentTransforms(hand)
	local attachmentData = M.getCurrentGrippedAttachmentData(hand)
	if attachmentData ~= nil then
		if attachmentData.attachType ~= M.AttachType.RAW_CONTROLLER then
			local location = attachmentData.attachment:K2_GetComponentLocation()
			local rotation = attachmentData.attachment:K2_GetComponentRotation()
			rotation = kismet_math_library:ComposeRotators(uevrUtils.rotator(parameters["baseOffsets"]["rotation"]), rotation)
			local vector = uevrUtils.rotateVector(M.getActiveAttachmentSightsPositionOffset(hand), rotation)
			location = location + vector

			return location, rotation
		else
			--I cant find a way to get the world transforms of raw controller attachments so
			--doing this instead. Get world transform of motion controllers and add local tranform of weapons
			--Since this runs on the tick it's an argument against attaching to raw controllers since
			--it uses a lot more computation than the other attachment methods
			local location = controllers.getControllerLocation(hand)
			local rotation = controllers.getControllerRotation(hand)

			local offsetLocation = nil
			local attachmentID = M.getAttachmentIDFromAttachment(attachmentData.attachment)
			local offset = getAttachmentOffsetByID(attachmentID)
			if offset ~= nil then
				offsetLocation = uevrUtils.vector(offset["location"])
				local attachmentLocalRotation = uevrUtils.rotator(offset["rotation"])

				attachmentLocalRotation.Yaw = -attachmentLocalRotation.Yaw
				attachmentLocalRotation.Pitch = -attachmentLocalRotation.Pitch
				attachmentLocalRotation.Roll = -attachmentLocalRotation.Roll
				attachmentLocalRotation = kismet_math_library:ComposeRotators(attachmentLocalRotation, uevrUtils.rotator(0,-90,0))
				rotation = kismet_math_library:ComposeRotators(attachmentLocalRotation, rotation)
				--TODO probably need this
				--rotation = kismet_math_library:ComposeRotators(uevrUtils.rotator(parameters["baseOffsets"]["rotation"]), rotation)

				if (gunstockRotationOffset.Pitch == nil or gunstockRotationOffset.Pitch == 0) and (gunstockRotationOffset.Yaw == nil or gunstockRotationOffset.Yaw == 0) and (gunstockRotationOffset.Roll == nil or gunstockRotationOffset.Roll == 0) then
					--do nothing
				else
					rotation = kismet_math_library:ComposeRotators(gunstockRotationOffset, rotation)
				end
				--rotation = compose(gunstockRotationOffset, rotation)
			else
				offsetLocation = uevrUtils.vector(0,0,0)
			end

			--notice I am not doing anything with the offsetLocation here. Something is severely broken
			--with attaching things. As the local position changes the attachments rotates itself to always
			--point at a distant point along the controllers forward vector. I have no explanation for this behavior.
			--But it means that adding the offsetLocation here just makes things worse.

			local sightsOffset = M.getActiveAttachmentSightsPositionOffset(hand)
			local vector = uevrUtils.rotateVector(sightsOffset, rotation)
			location = location + vector
			return location, rotation
		end
	end
	return uevrUtils.vector(0,0,0), uevrUtils.rotator(0,0,0)
end

function M.getActiveAttachmentMeleeRotationOffset(hand)
	local attachmentID = M.getActiveAttachmentID(hand)
	if attachmentID ~= nil then
		return M.getMeleeRotationOffset(attachmentID)
	end
	return uevrUtils.rotator(0,0,0)
end

function M.getActiveAttachmentSightsPositionOffset(hand)
	local attachmentID = M.getActiveAttachmentID(hand)
	if attachmentID ~= nil then
		return M.getSightsPositionOffset(attachmentID)
	end
	return uevrUtils.vector(0,0,0)
end

function M.setAttachmentOffset(id, location, rotation)
	for i = 1, #attachmentOffsets do
		local attachmentID = attachmentOffsets[i]["id"]
		if id == attachmentID then
			if location ~= nil then attachmentOffsets[i]["location"] = {location.X, location.Y, location.Z} end
			if rotation ~= nil then attachmentOffsets[i]["rotation"] = {rotation.X, rotation.Y, rotation.Z} end
		end
	end
	parameters["attachmentOffsets"] = attachmentOffsets
	isParametersDirty = true
end

function M.updateAttachmentAnimation(id, animationIndex)
	for i = 1, #attachmentOffsets do
		local attachmentID = attachmentOffsets[i]["id"]
		if id == attachmentID then
			attachmentOffsets[i]["animation"] = animationIDs[animationIndex]
			--when we change the setting in configui, we also need to update the active animation(s)
			local attachmentDataArray = getAttachmentDataFromMeshAttachmentList(id)
			for j = 1, #attachmentDataArray do
				local attachmentData = attachmentDataArray[j]
				if attachmentData ~= nil and attachmentData.gripHand ~= nil then
					M.setActiveAnimation(attachmentData.attachment, attachmentData.gripHand)
				end
			end
		end
	end
	parameters["attachmentOffsets"] = attachmentOffsets
	isParametersDirty = true
end

local function updateAttachmentProperty(id, propertyName, value)
	for i = 1, #attachmentOffsets do
		local attachmentID = attachmentOffsets[i]["id"]
		if id == attachmentID then
			attachmentOffsets[i][propertyName] = value
		end
	end
	parameters["attachmentOffsets"] = attachmentOffsets
	isParametersDirty = true
end

function M.updateAttachmentUseAnyChild(id, anyChild)
	updateAttachmentProperty(id, "any_child", anyChild)
end

function M.updateAttachmentUseAnyParent(id, anyParent)
	updateAttachmentProperty(id, "any_parent", anyParent)
end

function M.updateAttachmentIsScoped(id, isScoped)
	updateAttachmentProperty(id, "scoped", isScoped)
	updateScopeForAttachmentID(id)
end

function M.updateAttachmentIsTwoHanded(id, isTwoHanded)
	updateAttachmentProperty(id, "two_handed", isTwoHanded)
end

function M.updateAttachmentIsMelee(id, isMelee)
	updateAttachmentProperty(id, "melee", isMelee)
end

function M.updateAttachmentHasLaser(id, hasLaser)
	updateAttachmentProperty(id, "use_laser", hasLaser)
	updateLaserForAttachmentID(id)
end

-- function M.updateAttachmentUseSightsPositionOffset(id, useSightsPositionOffset)
-- 	updateAttachmentProperty(id, "use_sights_position_offset", useSightsPositionOffset)
-- end

local function checkAttachmentProperty(attachment, property)
	--print("checkAttachmentProperty called for property " .. property, attachment)
	if uevrUtils.getValid(attachment) ~= nil then
		local _, _, attachmentID = getAttachmentNames(attachment)
		--print("Checking attachment property " .. property .. " for attachment ID " .. attachmentID)
		for i = 1, #attachmentOffsets do
			if attachmentOffsets[i]["id"] == attachmentID then
				return attachmentOffsets[i][property] == true
			end
		end
	end
	return false
end

local attachmentIDCache = {}
function M.getAttachmentIDFromAttachment(attachment)
	if attachment ~= nil then
		local name = attachment:get_full_name()
		if attachmentIDCache[name] ~= nil then
			return attachmentIDCache[name]
		end
		local _, _, attachmentID = getAttachmentNames(attachment)
		attachmentIDCache[name] = attachmentID
		return attachmentID
	end
	return nil
end

function M.getActiveAttachmentID(hand)
	local attachment = M.getCurrentGrippedAttachment(hand)
	return M.getAttachmentIDFromAttachment(attachment)
	-- if attachment ~= nil then
	-- 	local name = attachment:get_full_name()
	-- 	if attachmentIDCache[name] ~= nil then
	-- 		return attachmentIDCache[name]
	-- 	end
	-- 	local _, _, attachmentID = getAttachmentNames(attachment)
	-- 	attachmentIDCache[name] = attachmentID
	-- 	return attachmentID
	-- end
	-- return nil
end

function M.isActiveAttachmentMelee(hand)
	return checkAttachmentProperty(M.getCurrentGrippedAttachment(hand), "melee")
end

function M.isActiveAttachmentScoped(hand)
	return checkAttachmentProperty( M.getCurrentGrippedAttachment(hand), "scoped")
end

function M.isActiveAttachmentLasered(hand)
	return checkAttachmentProperty( M.getCurrentGrippedAttachment(hand), "use_laser")
end

function M.isActiveAttachmentTwoHanded(hand)
	return checkAttachmentProperty(M.getCurrentGrippedAttachment(hand), "two_handed")
end

-- local function getNamedAttachmentFromMeshAttachmentList(parentName, childName)
-- 	for meshName, meshData in pairs(meshAttachmentList) do
-- 		for attachmentName, attachmentData in pairs(meshData) do
-- 			if attachmentData == nil then
-- 				print("getNamedAttachmentFromMeshAttachmentList had nil attachmentData", parentName, childName)
-- 			elseif uevrUtils.getValid(attachmentData.attachment) ~= nil then
-- 				if hasNamedObject(attachmentData.attachment, parentName, childName) then
-- 					return attachmentData.attachment, attachmentData.attachType, attachmentData.state
-- 				end
-- 			end
-- 		end
-- 	end
-- 	return nil, nil
-- end

--function M.updateAttachmentTransform(pos, rot, scale, parentName, childName)

function M.updateAttachmentTransform(pos, rot, scale, id)
	if id ~= nil then
		M.setAttachmentOffset(id, pos, rot)
	end

	--only using rotationOffset on the Raw Controller currently assuming if the attachment is connected to a mesh then the mesh will be rotated
	--local rotationOffset = gunstock.setActive(id)
	M.print("Updating attachment transform for id " .. tostring(id))
	local attachmentDataArray = getAttachmentDataFromMeshAttachmentList(id)
	--local attachment, attachType, attachState = getAttachmentDataFromMeshAttachmentList(id)
	for j = 1, #attachmentDataArray do
		local attachmentData = attachmentDataArray[j]
		if attachmentData ~= nil then
			local attachment = attachmentData.attachment
			local attachType = attachmentData.attachType
			local attachState = attachmentData.state
			if attachType == M.AttachType.RAW_CONTROLLER then
				if attachState ~= nil then
					if pos ~= nil then attachState:set_location_offset(Vector3f.new( pos.X, pos.Y, pos.Z)) end
					-- if rot ~= nil then
					-- 	local final = kismet_math_library:ComposeRotators( uevrUtils.rotator(rot.X, rot.Y + 90, rot.Z), rotationOffset * 1)
					-- 	attachState:set_rotation_offset(Vector3f.new( math.rad(final.Pitch), math.rad(final.Yaw),  math.rad(final.Roll)))
					-- end
					local baseRotation = parameters["baseOffsets"]["rotation"]
					if rot ~= nil then attachState:set_rotation_offset(Vector3f.new( math.rad(rot.X - gunstockRotationOffset.Pitch - baseRotation[1]), math.rad(rot.Y + 90 - gunstockRotationOffset.Yaw - baseRotation[2]),  math.rad(rot.Z - gunstockRotationOffset.Roll - baseRotation[3]))) end
				end
			end
			if attachment ~= nil and (attachType == M.AttachType.MESH or attachType == M.AttachType.CONTROLLER) then
				M.print("Setting attachment transform for attachment " .. tostring(attachment:get_full_name()))
				if pos ~= nil then uevrUtils.set_component_relative_location(attachment, pos) end
				if rot ~= nil then uevrUtils.set_component_relative_rotation(attachment, rot + gunstockRotationOffset - uevrUtils.rotator(parameters["baseOffsets"]["rotation"])) end
				if scale ~= nil then uevrUtils.set_component_relative_scale(attachment, scale) end
			end
		end
	end
	-- for id, mesh in pairs(meshAttachmentList) do
	-- 	for attachmentName, attachmentData in pairs(mesh) do
	-- 		if uevrUtils.getValid(attachmentData.attachment) ~= nil then
	-- 			if hasNamedObject(attachmentData.attachment, parentName, childName) then
	-- 				local attachType = attachmentData.attachType
	-- 				if attachType == M.AttachType.RAW_CONTROLLER then
	-- 					-- if attachmentState ~= nil then
	-- 					-- 	if pos ~= nil then attachmentState:set_location_offset(Vector3f.new( pos.X, pos.Y, pos.Z)) end
	-- 					-- 	if rot ~= nil then attachmentState:set_rotation_offset(Vector3f.new( math.rad(rot.X), math.rad(rot.Y+90),  math.rad(rot.Z))) end
	-- 					-- end
	-- 				end
	-- 				if attachType == M.AttachType.MESH or attachType == M.AttachType.CONTROLLER then
	-- 					if pos ~= nil then uevrUtils.set_component_relative_location(activeAttachment, pos) end
	-- 					if rot ~= nil then uevrUtils.set_component_relative_rotation(activeAttachment, rot) end
	-- 					if scale ~= nil then uevrUtils.set_component_relative_scale(activeAttachment, scale) end
	-- 				end
	-- 			end
	-- 		end
	-- 	end
	-- end
	-- if uevrUtils.validate_object(activeAttachment) ~= nil then
	-- 	if parentName == nil or hasNamedObject(activeAttachment, parentName, childName) then
	-- 		if attachType == M.AttachType.RAW_CONTROLLER then
	-- 			-- if attachmentState ~= nil then
	-- 			-- 	if pos ~= nil then attachmentState:set_location_offset(Vector3f.new( pos.X, pos.Y, pos.Z)) end
	-- 			-- 	if rot ~= nil then attachmentState:set_rotation_offset(Vector3f.new( math.rad(rot.X), math.rad(rot.Y+90),  math.rad(rot.Z))) end
	-- 			-- end
	-- 		end
	-- 		if attachType == M.AttachType.MESH or attachType == M.AttachType.CONTROLLER then
	-- 			if pos ~= nil then uevrUtils.set_component_relative_location(activeAttachment, pos) end
	-- 			if rot ~= nil then uevrUtils.set_component_relative_rotation(activeAttachment, rot) end
	-- 			if scale ~= nil then uevrUtils.set_component_relative_scale(activeAttachment, scale) end
	-- 		end
	-- 	end
	-- end
end

-- uevrUtils.registerUEVRCallback("aim_rotation_offset_change", function(newRotation)
-- 	gunstockRotationOffset = newRotation
-- end)

uevrUtils.registerUEVRCallback("gunstock_transform_change", function(id, location, rotation, offhandLocationOffset)
	if gunstockOffsetsEnabled then
		gunstockRotationOffset = rotation
		gunstockOffhandLocationOffset = offhandLocationOffset
		local attachmentDataArray = getAttachmentDataFromMeshAttachmentList(id)
		--local attachment, _, _ = getAttachmentDataFromMeshAttachmentList(id)
		if attachmentDataArray ~= nil and #attachmentDataArray > 0 then
			for j = 1, #attachmentDataArray do
				local attachmentData = attachmentDataArray[j]
				if attachmentData ~= nil and uevrUtils.getValid(attachmentData.attachment) ~= nil then
					local loc, rot, scale = M.getAttachmentOffset(attachmentData.attachment)
					M.updateAttachmentTransform(loc, rot, scale, id)
				end
			end
		end
	end
end)

function M.allowChildVisibilityHandling(value)
	allowChildVisibilityHandling = value
end

local function updateSelectedColor(id, color)
	--print("changing color", "attachment_" .. id)
	configui.setColor(widgetPrefix .. id, color)
end

local function updateSelectedColors()
	for i = 1, #attachmentOffsets do
		local parent = attachmentOffsets[i]["parent"]
		local child = attachmentOffsets[i]["child"]
		local m_id = attachmentOffsets[i]["id"]
		if m_id == nil then m_id = parent .. "_" .. child end
		configui.setColor(widgetPrefix .. m_id, "#FFFFFFFF")
	end

	-- First try the standard path (live attachment objects)
	local leftAttachment = uevrUtils.getValid(M.getCurrentGrippedAttachment(Handed.Left))
	local rightAttachment = uevrUtils.getValid(M.getCurrentGrippedAttachment(Handed.Right))

	local leftID, rightID = nil, nil
	if leftAttachment ~= nil then
		local _, _, m_leftID = getAttachmentNames(leftAttachment)
		leftID = m_leftID
	end
	if rightAttachment ~= nil then
		local _, _, m_rightID = getAttachmentNames(rightAttachment)
		rightID = m_rightID
	end

	-- Fallback: read cachedID from VIRTUAL grip entries (survives stale mesh pointers)
	for meshName, meshData in pairs(meshAttachmentList) do
		if string.sub(meshName, 1, 12) == "VirtualGrip_" then
			for _, attachmentData in pairs(meshData.attachments or {}) do
				if attachmentData.cachedID ~= nil then
					if attachmentData.gripHand == Handed.Left and leftID == nil then
						leftID = attachmentData.cachedID
					elseif attachmentData.gripHand == Handed.Right and rightID == nil then
						rightID = attachmentData.cachedID
					end
				end
			end
		end
	end

	if leftID ~= nil and rightID ~= nil and leftID == rightID then
		--set color to purple if both hands are holding the same attachment
		updateSelectedColor(leftID, "#FF00FFFF")
	else
		if leftID ~= nil then
			updateSelectedColor(leftID, "#00FF88FF")
		end
		if rightID ~= nil then
			updateSelectedColor(rightID, "#0088FFFF")
		end
	end

end


function M.initAttachment(attachment, gripHand, options)
	if attachment ~= nil then
		if options == nil then options = {} end
		if options.allowChildVisibilityHandling == nil or options.allowChildVisibilityHandling == true then
			attachment:SetVisibility(true, allowChildVisibilityHandling)
		end
		if options.allowChildHiddenInGameHandling == nil or options.allowChildHiddenInGameHandling == true then
			attachment:SetHiddenInGame(false, allowChildVisibilityHandling)
		end
		if options.allowRenderInMainPassHandling == nil or options.allowRenderInMainPassHandling == true then
			attachment:call("SetRenderInMainPass", true)
		end
		local location, rotation, scale = M.getAttachmentOffset(attachment)
		local parentName, childName, id = getAttachmentNames(attachment)
		M.print("Initializing attachment " .. id)
		--TODO this is used by scope and gunstock but we need to call it also when detach occurs
		if gripHand ~= nil then
			executeGripAttachmentChanged(id, gripHand, attachment)
		end
		M.updateAttachmentTransform(location, rotation, scale, id)
		M.setActiveAnimation(attachment, gripHand)

		updateScopeForAttachmentID(id)
		updateLaserForAttachmentID(id)

		updateSelectedColors()
	end
end

function M.setActiveAnimation(attachment, gripHand)
	if gripHand ~= nil then
		if uevrUtils.getValid(attachment) ~= nil then
			activeGripAnimations[gripHand] = true
			for i = 1, #attachmentOffsets do
				local id = attachmentOffsets[i]["id"]
				-- local parent = attachmentOffsets[i]["parent"]
				-- local child = attachmentOffsets[i]["child"]
				--local name = parent .. "_" .. child
				--if attachmentOffsets[i]["animation"] is nil then its never been set so just use the default animation by returning true
				--if hasNamedObject(attachment, parent, child) and attachmentOffsets[i]["animation"] ~= nil then
				local _, _, attachmentID = getAttachmentNames(attachment)
				if id == attachmentID and attachmentOffsets[i]["animation"] ~= nil then
					activeGripAnimations[gripHand] = attachmentOffsets[i]["animation"] == "animation_none" and false or attachmentOffsets[i]["animation"]
					break
				end
			end
		else
			activeGripAnimations[gripHand] = false
		end
		M.print("Calling callback for grip animation " .. tostring(activeGripAnimations[gripHand]) .. " " .. tostring(gripHand))
		executeGripAnimationChange(activeGripAnimations[gripHand], gripHand)
		--executeAttachmentCallbacks("grip_animation", activeGripAnimations[gripHand], gripHand)
	end
end

function M.getCurrentGrippedAttachment(gripHand)
	local attachmentData = M.getCurrentGrippedAttachmentData(gripHand)
	if attachmentData ~= nil then
		return uevrUtils.getValid(attachmentData.attachment)
	end
	-- if gripHand == nil then gripHand = Handed.Right end
	-- if gripHand ~= nil then
	-- 	for meshName, meshData in pairs(meshAttachmentList) do
	-- 		for attachmentName, attachmentData in pairs(meshData.attachments or {}) do
	-- 			local ok, result = pcall(function()
	-- 				if attachmentData.gripHand == gripHand and uevrUtils.getValid(attachmentData.attachment) then
	-- 					return attachmentData.attachment
	-- 				end
	-- 			end)
	-- 			if not ok then
	-- 				--this error happens when attachments are connected to hands meshes and the hands meshes get deallocated
	-- 				--I dont know how that corrupts the meshAttachmentList which is just a lua table but cleaning it up fixes
	-- 				--the issue without known negative side effects
	-- 				-- Note: may be fixed after making changes to the detach code
	-- 				M.print("Error in getCurrentGrippedAttachment. Cleaning up meshAttachmentList")
	-- 				meshData.attachments[attachmentName] = nil
	-- 			end
	-- 			if ok and result ~= nil then
	-- 				return result
	-- 			end
	-- 		end
	-- 	end
	-- end
end

function M.getCurrentGrippedAttachmentData(gripHand)
	if gripHand == nil then gripHand = Handed.Right end
	if gripHand ~= nil then
		for meshName, meshData in pairs(meshAttachmentList) do
			for attachmentName, attachmentData in pairs(meshData.attachments or {}) do
				--local ok, result = pcall(function()
					if attachmentData.gripHand == gripHand then
						return attachmentData
					end
				--end)
				-- if not ok then
				-- 	M.print("Error in getCurrentGrippedAttachmentData. Cleaning up meshAttachmentList")
				-- 	meshData.attachments[attachmentName] = nil
				-- end
				-- if ok and result ~= nil then
				-- 	return result
				-- end
			end
		end
	end
end

-- TODO: optimize to only send changes
function M.broadcastGrippedAttachmentRotation()
	local leftAttachment = M.getCurrentGrippedAttachment(Handed.Left)
	local rightAttachment = M.getCurrentGrippedAttachment(Handed.Right)
	executeGripAttachmentRotationChange((leftAttachment and leftAttachment.GetSocketRotation ~= nil) and leftAttachment:GetSocketRotation(uevrUtils.fname_from_string("MuzzleSocket")) or nil, (rightAttachment and rightAttachment.GetSocketRotation ~= nil) and rightAttachment:GetSocketRotation(uevrUtils.fname_from_string("MuzzleSocket")) or nil)
	--print("Broadcasting gripped attachment rotation", leftAttachment, rightAttachment)
end

function M.getCurrentGripAnimation(handed)
	return activeGripAnimations[handed]
end

--for debugging
local function printMeshAttachmentList()
	M.print("Current Mesh Attachment List:")
	for meshName, meshData in pairs(meshAttachmentList) do
		M.print(" Mesh: " .. meshName)
		for attachmentName, attachmentData in pairs(meshData.attachments or {}) do
			if attachmentData.attachment ~= nil then
				M.print("  Attachment: " .. attachmentName .. " (Type: " .. tostring(attachmentData.attachType) .. ", GripHand: " .. tostring(attachmentData.gripHand) .. ")")
			end
		end
	end
end

--options = {detachFromOriginOnGrip = true, maintainWorldPositionOnDetachFromOrigin = true, detachFromParentOnRelease = true, maintainWorldPositionOnDetachFromParent = true, reattachToOriginOnRelease = true, restoreTransformToOriginOnReattach = true, useZeroTransformOnReattach = false}
function M.attachToMesh(attachment, mesh, socketName, gripHand, options)
	--printMeshAttachmentList()
	local success = false
	--print(attachment:get_full_name(), mesh:get_full_name(), socketName, tostring(gripHand), tostring(detachFromParent), tostring(allowReattach))
	if uevrUtils.getValid(attachment) ~= nil and uevrUtils.getValid(mesh) ~= nil  then
		if options == nil then
			options = {
				detachFromOriginOnGrip = true,
				maintainWorldPositionOnDetachFromOrigin = false,
				detachFromParentOnRelease = true,
				maintainWorldPositionOnDetachFromParent = false,
				reattachToOriginOnRelease = false,
				restoreTransformToOriginOnReattach = false,
				useZeroTransformOnReattach = false,
				allowChildVisibilityHandling = true,
				allowChildHiddenInGameHandling = true,
				allowRenderInMainPassHandling = true
			}
		end

		--see if the attachment is already a child of the mesh
		--In atomic heart, the entire attachment can run apparently successfully and still not be attached to the mesh
		--Something in the engine must disconnect it (probably the animation) after the attach call. So this check can not be removed.
		if mesh.AttachChildren ~= nil then
			for i, child in ipairs(mesh.AttachChildren) do
				if child == attachment then
					--M.print("Attachment is already a child of the mesh")
					return true
				end
			end
		end

		local meshName = mesh:get_full_name()
		local attachmentName = attachment:get_full_name()
		--if it's already attached then just return
		-- if meshAttachmentList[meshName] ~= nil and meshAttachmentList[meshName][attachmentName] ~= nil then
		-- 	if meshAttachmentList[meshName][attachmentName]["attachment"] == attachment then
		-- 		M.print("Attachment is already a child of the mesh")
		-- 		return true
		-- 	end
		-- end
		--M.print("Attachment is not a child of the mesh")

		--M.detachAttachmentFromMeshes(attachment, true)
		if gripHand ~= nil then
		 	M.detachGripAttachments(gripHand)
		end

		--if meshAttachmentList[meshName] ==  nil then
			meshAttachmentList[meshName] = {mesh = mesh, attachments = {}}
		--end
		--local attachmentName = attachment:get_full_name()
		--if meshAttachmentList[meshName][attachmentName] == nil then
			meshAttachmentList[meshName].attachments[attachmentName] = {attachment=attachment, socket=socketName, detachFromParentOnRelease = options.detachFromParentOnRelease, maintainWorldPositionOnDetachFromParent = options.maintainWorldPositionOnDetachFromParent, attachType = M.AttachType.MESH, gripHand = gripHand}
		--end

		if options.reattachToOriginOnRelease == true then
			meshAttachmentList[meshName].attachments[attachmentName].parent = attachment.AttachParent
			if options.restoreTransformToOriginOnReattach == true then
				meshAttachmentList[meshName].attachments[attachmentName].originalTransform = {}
				if options.useZeroTransformOnReattach or useZeroTransformOnReattach then
					meshAttachmentList[meshName].attachments[attachmentName].originalTransform.rotation = uevrUtils.rotator(0,0,0)
					meshAttachmentList[meshName].attachments[attachmentName].originalTransform.location = uevrUtils.vector(0,0,0)
					meshAttachmentList[meshName].attachments[attachmentName].originalTransform.scale = uevrUtils.vector(1,1,1)
				else
					meshAttachmentList[meshName].attachments[attachmentName].originalTransform.rotation = attachment.RelativeRotation
					meshAttachmentList[meshName].attachments[attachmentName].originalTransform.location = attachment.RelativeLocation
					meshAttachmentList[meshName].attachments[attachmentName].originalTransform.scale = attachment.RelativeScale3D
				end
			end
		end

		--print(attachment:get_full_name() .. " parent before attach: " .. (attachment.AttachParent and attachment.AttachParent:get_full_name() or "nil"))
		if options.detachFromOriginOnGrip == true and attachment.DetachFromParent ~= nil then
			attachment:DetachFromParent(options.maintainWorldPositionOnDetachFromOrigin or false, false)
		end

		M.print("Attaching attachment to mesh: " .. attachment:get_full_name() .. " to " .. mesh:get_full_name())
		if type(socketName) == "string" then
			socketName = uevrUtils.fname_from_string(socketName)
		end
		if socketName == nil then socketName = attachment.AttachSocketName end
		success = attachment:K2_AttachTo(mesh, socketName, 0, false)

		M.initAttachment(attachment, gripHand, options)
		M.print("Attached attachment to mesh" .. (success and " successfully" or " with errors"))

		-- if mesh.AttachChildren ~= nil then
		-- 	for i, child in ipairs(mesh.AttachChildren) do
		-- 		if child == attachment then
		-- 			M.print("Verified the mesh is actually attached")
		-- 		end
		-- 	end
		-- end

	else
		M.print("Failed to attach attachment to mesh")
	end
	return success
end

function M.attachToController(attachment, controllerID, options)
	M.attachToMesh(attachment, controllers.getController(controllerID), nil, controllerID, options)
end

function M.attachToRawController(attachment, gripHand, options)
	if uevrUtils.getValid(attachment) ~= nil then
		if options == nil then
			options = {
				detachFromOriginOnGrip = true,
				maintainWorldPositionOnDetachFromOrigin = false,
				detachFromParentOnRelease = true,
				maintainWorldPositionOnDetachFromParent = false,
				reattachToOriginOnRelease = false,
				restoreTransformToOriginOnReattach = false,
				useZeroTransformOnReattach = false,
				allowChildVisibilityHandling = true,
				allowChildHiddenInGameHandling = true,
				allowRenderInMainPassHandling = true
			}
		end
		local meshName = "Controller_Raw" .. (gripHand and ("_" .. gripHand) or "")
		local attachmentName = attachment:get_full_name()
		--if it's already attached then just return
		if meshAttachmentList[meshName] ~= nil and meshAttachmentList[meshName].attachments[attachmentName] ~= nil then
			if meshAttachmentList[meshName].attachments[attachmentName]["attachment"] == attachment then
				return true
			end
		end

		M.detachAttachmentsFromMesh(meshName)

		--if meshAttachmentList[meshName] ==  nil then
			meshAttachmentList[meshName] = {mesh = nil, attachments={}}
		--end
		meshAttachmentList[meshName].attachments[attachmentName] = {attachment=attachment, detachFromParentOnRelease = options.detachFromParentOnRelease, maintainWorldPositionOnDetachFromParent = options.maintainWorldPositionOnDetachFromParent, attachType = M.AttachType.RAW_CONTROLLER, gripHand = gripHand}

		if options.reattachToOriginOnRelease == true and attachment ~= nil and attachment.AttachParent ~= nil then
			meshAttachmentList[meshName].attachments[attachmentName].parent = attachment.AttachParent
			if options.restoreTransformToOriginOnReattach == true then
				meshAttachmentList[meshName].attachments[attachmentName].originalTransform = {}
				if options.useZeroTransformOnReattach or useZeroTransformOnReattach then
					meshAttachmentList[meshName].attachments[attachmentName].originalTransform.rotation = uevrUtils.rotator(0,0,0)
					meshAttachmentList[meshName].attachments[attachmentName].originalTransform.location = uevrUtils.vector(0,0,0)
					meshAttachmentList[meshName].attachments[attachmentName].originalTransform.scale = uevrUtils.vector(1,1,1)
				else
					meshAttachmentList[meshName].attachments[attachmentName].originalTransform.rotation = attachment.RelativeRotation
					meshAttachmentList[meshName].attachments[attachmentName].originalTransform.location = attachment.RelativeLocation
					meshAttachmentList[meshName].attachments[attachmentName].originalTransform.scale = attachment.RelativeScale3D
				end
			end
		end

		if options.detachFromOriginOnGrip == true then
			attachment:DetachFromParent(options.maintainWorldPositionOnDetachFromOrigin or false, false)
		end

		M.print("Attaching " .. attachment:get_full_name() .. " to controller with ID " .. (gripHand and tostring(gripHand) or "nil"))
		local state = UEVR_UObjectHook.get_or_add_motion_controller_state(attachment)
		state:set_hand(gripHand)
		state:set_permanent(options.restoreTransformToOriginOnReattach == true)
		meshAttachmentList[meshName].attachments[attachmentName].state = state

		M.initAttachment(attachment, gripHand, options)
		M.print("Attached attachment to raw controller")
	else
		M.print("Failed to attach attachment to raw controller")
	end
end

function M.detach(attachment, parent, attachType, originalTransform, detachFromParentOnRelease, maintainWorldPositionOnDetachFromParent)
	print("Detaching attachment", attachment, parent or nil, attachType)
	if uevrUtils.getValid(attachment) ~= nil then
		-- VIRTUAL entries are tracked for UI/animation only — skip all physical ops
		if attachType == M.AttachType.VIRTUAL then
			M.print("Skipping physical detach for VIRTUAL attachment: " .. attachment:get_full_name())
			return
		end
		if attachType == M.AttachType.RAW_CONTROLLER then
			M.print("Detaching attachment from raw controller: " .. attachment:get_full_name())
			UEVR_UObjectHook.remove_motion_controller_state(attachment)
		end
		M.print("Detaching attachment " .. attachment:get_full_name() .. (parent and (" and reattaching to parent: " .. parent:get_full_name()) or " did not reattach to parent because no parent existed"))
		if detachFromParentOnRelease == true then
			attachment:DetachFromParent(maintainWorldPositionOnDetachFromParent, false)
		end
		if parent ~= nil then
			if originalTransform ~= nil then
				print("Restoring original transform on reattach", originalTransform.location.X, originalTransform.location.Y, originalTransform.location.Z,
					originalTransform.rotation.Pitch, originalTransform.rotation.Yaw, originalTransform.rotation.Roll,
					originalTransform.scale.X, originalTransform.scale.Y, originalTransform.scale.Z)
				uevrUtils.set_component_relative_location(attachment, originalTransform.location)
				uevrUtils.set_component_relative_rotation(attachment, originalTransform.rotation)
				uevrUtils.set_component_relative_scale(attachment, originalTransform.scale)
			end
			attachment:K2_AttachTo(parent, attachment.AttachSocketName, 0, false)
		end
	else
		M.print("Failed to detach attachment")
	end
end

-- function M.logMeshAttachmentList()
-- 	debugger.dump(meshAttachmentList)
-- end

-- old
-- meshAttachmentList = {
-- 	MotionControllerComponent /Game/Maps/ADR_07_PRO/ADR_07_PRO.ADR_07_PRO.PersistentLevel.Actor_2147477481.MotionControllerComponent_2147477480 = {
-- 		mesh = theContainer,
-- 		["StaticMeshComponent /Game/Weapons/Meshes/Attachments/Scopes/SM_Scope_01.SM_Scope_01"] = {
-- 			attachment = theAttachment,
-- 			socket = "MuzzleSocket",
-- 			detachFromParent = true,
-- 			attachType = M.AttachType.MESH,
-- 			gripHand = Handed.Right
-- 		}
-- 	}
-- }

-- new
-- meshAttachmentList = {
-- 	 MotionControllerComponent /Game/Maps/ADR_07_PRO/ADR_07_PRO.ADR_07_PRO.PersistentLevel.Actor_2147477481.MotionControllerComponent_2147477480 = {
-- 		mesh = theContainer,
--		attachments = {
-- 			["StaticMeshComponent /Game/Weapons/Meshes/Attachments/Scopes/SM_Scope_01.SM_Scope_01"] = {
-- 				attachment = theAttachment,
-- 				socket = "MuzzleSocket",
-- 				detachFromParent = true,
-- 				attachType = M.AttachType.MESH,
-- 				gripHand = Handed.Right
--				originalTransform = {}
-- 			}
-- 		}	
-- 	 }
-- }

-- Helper to clean up all empty mesh entries
local function cleanupEmptyMeshEntries()
    local meshesToRemove = {}
    for meshName, meshData in pairs(meshAttachmentList) do
        if meshData.attachments ~= nil then
            if next(meshData.attachments) == nil then
                M.print("Removing empty mesh entry: " .. meshName)
                table.insert(meshesToRemove, meshName)
            end
        end
    end

    for _, meshName in ipairs(meshesToRemove) do
        meshAttachmentList[meshName] = nil
    end
end

-- Helper function to handle common detachment logic
local function detachAndCleanup(attachmentData, reattachToParent)
    if attachmentData == nil then return end

    if attachmentData.gripHand ~= nil then
		destroyLaserForGripHand(attachmentData.gripHand)
		destroyScopeForGripHand(attachmentData.gripHand)

        activeGripAnimations[attachmentData.gripHand] = false
        executeGripAnimationChange(false, attachmentData.gripHand)
    end

    local parent = reattachToParent and attachmentData.parent or nil
    M.detach(attachmentData.attachment, parent, attachmentData.attachType, attachmentData.originalTransform, attachmentData.detachFromParentOnRelease, attachmentData.maintainWorldPositionOnDetachFromParent)
end

function M.detachAllAttachments()
    M.print("Detaching all attachments from all meshes")
    for meshName, meshData in pairs(meshAttachmentList) do
        if meshData.attachments ~= nil then
            for attachmentName, attachmentData in pairs(meshData.attachments) do
                detachAndCleanup(attachmentData, true)
            end
        end
    end
    meshAttachmentList = {}
end

function M.detachGripAttachments(gripHand)
	--printMeshAttachmentList()
    if gripHand == nil then
        M.print("Failed to detach grip attachments: gripHand is nil")
        return
    end

    for meshName, meshData in pairs(meshAttachmentList) do
		--print(" Checking mesh in detachGripAttachments: " .. meshName)
        if meshData.attachments ~= nil then
            for attachmentName, attachmentData in pairs(meshData.attachments) do
				--print("  Checking attachment: " .. attachmentName .. " with gripHand: " .. tostring(attachmentData.gripHand))
                local ok = pcall(function()
                    if attachmentData.gripHand == gripHand then
                        M.print("Detaching grip attachment " .. attachmentName)
                        detachAndCleanup(attachmentData, true)
                        meshData.attachments[attachmentName] = nil
                    end
                end)
                if not ok then
                    M.print("Error in detachGripAttachments, cleaning up")
                    meshData.attachments[attachmentName] = nil
                end
            end
        end
    end

    cleanupEmptyMeshEntries()
end

-- this is not used anywhere. Maybe superceded by detachGripAttachments?
-- function M.detachAttachmentFromMeshes(attachment, reattachToParent)
--     if uevrUtils.getValid(attachment) == nil then
--         M.print("Failed to detach attachment: invalid attachment")
--         return
--     end

--     local attachmentName = attachment:get_full_name()
--     M.print("Detaching attachment from all meshes: " .. attachmentName)

--     for meshName, meshData in pairs(meshAttachmentList) do
--         if meshData.attachments ~= nil and meshData.attachments[attachmentName] ~= nil then
--             detachAndCleanup(meshData.attachments[attachmentName], reattachToParent)
--             meshData.attachments[attachmentName] = nil
--         end
--     end

--     cleanupEmptyMeshEntries()
-- end

function M.detachAttachmentsFromMesh(mesh)
    local meshName = type(mesh) == "string" and mesh or
        (uevrUtils.getValid(mesh) ~= nil and mesh:get_full_name() or nil)

    if meshName == nil or meshName == "" then
        M.print("Failed to detach attachments: invalid mesh")
        return
    end

    M.print("Detaching all attachments from mesh: " .. meshName)
    local meshData = meshAttachmentList[meshName]

    if meshData ~= nil and meshData.attachments ~= nil then
        for attachmentName, attachmentData in pairs(meshData.attachments) do
            detachAndCleanup(attachmentData, true)
        end
        meshAttachmentList[meshName] = nil
    end
end

local function getAnimationLabelsArray(animationIDList)
	local labels = {"Default", "None"}
	for id, data in pairs(animationIDList) do
		table.insert(labels, data["label"])
	end
	return labels
end

local function getAnimationIDsArray(animationIDList)
	local ids = {"", "attachment_none"}
	for id, data in pairs(animationIDList) do
		table.insert(ids, id)
	end
	return ids
end
function M.setStripParentNameNumericSuffix(value)
	stripParentNameNumericSuffix = value
	configui.setValue("use_uevr_attachments_strip_parent_name_numeric_suffix", stripParentNameNumericSuffix, true)
	if parameters ~= nil then
		parameters["stripParentNameNumericSuffix"] = stripParentNameNumericSuffix
		isParametersDirty = true
	end
end

local function deepEqual(t1, t2)
    if type(t1) ~= "table" or type(t2) ~= "table" then
        return t1 == t2
    end

    -- check keys in t1
    for k, v in pairs(t1) do
        if not deepEqual(v, t2[k]) then
            return false
        end
    end

    -- check keys in t2 (to catch extras)
    for k, v in pairs(t2) do
        if not deepEqual(v, t1[k]) then
            return false
        end
    end

    return true
end

local currentAnimationIDList = {}
function M.setAnimationIDs(animationIDList)
	--dont rewrite if nothing has changed
	if deepEqual(animationIDList, currentAnimationIDList) then
		return
	end
	currentAnimationIDList = animationIDList
	if animationIDList ~= nil then
		animationLabels = getAnimationLabelsArray(animationIDList)
		animationIDs = getAnimationIDsArray(animationIDList)
		for i = 1, #attachmentOffsets do
			local parent = attachmentOffsets[i]["parent"]
			local child = attachmentOffsets[i]["child"]
			local name = parent .. "_" .. child
			configui.setSelections(widgetPrefix .. name .. "_grip_animation", animationLabels)
			local selectedID = attachmentOffsets[i]["animation"]
			for j = 1, #animationIDs do
				if selectedID == animationIDs[j] then
					--dont think callback is needed here since we're just updating the configui to match existing settings
					configui.setValue(widgetPrefix .. name .. "_grip_animation", j, true)
				end
			end
		end
	end
end

configui.onUpdate("use_uevr_attachments_strip_parent_name_numeric_suffix", function(value)
	M.setStripParentNameNumericSuffix(value)
end)

configui.onUpdate("uevr_attachment_base_rotation", function(value)
	parameters["baseOffsets"]["rotation"] = {value.X, value.Y, value.Z}
	isParametersDirty = true

	if attachmentLasers[Handed.Left] then attachmentLasers[Handed.Left]:setRelativeRotation(uevrUtils.rotator(parameters["baseOffsets"]["rotation"])) end
	if attachmentLasers[Handed.Right] then attachmentLasers[Handed.Right]:setRelativeRotation(uevrUtils.rotator(parameters["baseOffsets"]["rotation"])) end

	-- local attachmentData = M.getCurrentGrippedAttachmentData(Handed.Left)
	-- if attachmentData ~= nil then
	-- 	local loc, rot, scale = M.getAttachmentOffset(attachmentData.attachment)
	-- 	local attachmentID = M.getAttachmentIDFromAttachment(attachmentData.attachment)
	-- 	M.updateAttachmentTransform(loc, rot, scale, attachmentID)
	-- end
	-- local attachmentData = M.getCurrentGrippedAttachmentData(Handed.Right)
	-- if attachmentData ~= nil then
	-- 	local loc, rot, scale = M.getAttachmentOffset(attachmentData.attachment)
	-- 	local attachmentID = M.getAttachmentIDFromAttachment(attachmentData.attachment)
	-- 	M.updateAttachmentTransform(loc, rot, scale, attachmentID)
	-- end
end)

local autoUpdateCallbackCreated = false
--options = {
--	detachFromOriginOnGrip = true, 
--	maintainWorldPositionOnDetachFromOrigin = false, 
--	detachFromParentOnRelease = true, 
--	maintainWorldPositionOnDetachFromParent = false, 
--	reattachToOriginOnRelease = fale, 
--	restoreTransformToOriginOnReattach = false, 
--	useZeroTransformOnReattach = false,
--	allowChildVisibilityHandling = true,
--	allowChildHiddenInGameHandling = true,
--	allowRenderInMainPassHandling = true
--}
-- Virtual grip registration — registers a weapon for UI/animation tracking WITHOUT
-- physically re-parenting it (the IK rig manages weapon attachment independently).
function M.registerGrippedAttachment(gripHand, attachment, weaponChildNameHint)
	if uevrUtils.getValid(attachment) == nil then
		M.print("registerGrippedAttachment: invalid attachment, skipping")
		return
	end
	local meshName = "VirtualGrip_" .. tostring(gripHand)
	local attachmentName = attachment:get_full_name()
	-- Compute the stable ID now while the attachment object is guaranteed valid
	local _, _, cachedID = getAttachmentNames(attachment)
	-- Clear previous virtual entry for this hand
	meshAttachmentList[meshName] = {mesh = nil, attachments = {}}
	activeGripAnimations[gripHand] = false
	-- Write new VIRTUAL entry (detach/attach ops are skipped for VIRTUAL type)
	meshAttachmentList[meshName].attachments[attachmentName] = {
		attachment       = attachment,
		socket           = nil,
		detachFromParentOnRelease = false,
		attachType       = M.AttachType.VIRTUAL,
		gripHand         = gripHand,
		cachedID         = cachedID,  -- stable ID stored so highlight works even if mesh ptr goes stale
	}
	-- Register in the config UI so this weapon appears in the Attachments panel
	M.addAttachmentToConfig(attachment)
	-- Fire grip animation callback so hand pose updates for this weapon
	M.setActiveAnimation(attachment, gripHand)
	updateSelectedColors()
end

-- Unregisters the virtual grip for gripHand and resets animation state.
function M.unregisterGrippedAttachment(gripHand)
	local meshName = "VirtualGrip_" .. tostring(gripHand)
	meshAttachmentList[meshName] = {mesh = nil, attachments = {}}
	activeGripAnimations[gripHand] = false
	executeGripAnimationChange(false, gripHand)
	updateSelectedColors()
end

-- Public wrapper so Entry.lua can call this on a periodic interval.
-- Ensures the highlighted weapon in the Attachments Config UI stays in sync
-- even when configui.update() (triggered by new weapon discovery) resets all colors.
function M.refreshHighlight()
	updateSelectedColors()
end

-- Bypasses the deepEqual guard in setAnimationIDs so dropdown selections are
-- re-populated after a configui.update() UI rebuild wipes all widget state.
function M.forceAnimationIDsRefresh(animationIDList)
	currentAnimationIDList = {}  -- invalidate cache so deepEqual always fails
	M.setAnimationIDs(animationIDList)
end

function M.registerOnGripUpdateCallback(callback)
	if not autoUpdateCallbackCreated then
		uevrUtils.setInterval(gripUpdateTimeout, function()
			local rightAttachment, rightMesh, rightSocketName, leftAttachment, leftMesh, leftSocketName, attachOptionsRight, attachOptionsLeft = callback()
			-- print("Before")
			-- printMeshAttachmentList()
			-- print("Left",activeGripAnimations[Handed.Left])
			-- print("Right",activeGripAnimations[Handed.Right])
			local allowReattach = nil
			if attachOptionsLeft ~= nil and type(attachOptionsLeft) == "boolean" then
				allowReattach = attachOptionsLeft
			end
			if attachOptionsRight == nil then
				attachOptionsRight = {
					detachFromOriginOnGrip = true,
					maintainWorldPositionOnDetachFromOrigin = false,
					detachFromParentOnRelease = true,
					maintainWorldPositionOnDetachFromParent = false,
					reattachToOriginOnRelease = allowReattach or false,
					restoreTransformToOriginOnReattach = allowReattach or false,
					useZeroTransformOnReattach = false,
					allowChildVisibilityHandling = true,
					allowChildHiddenInGameHandling = true,
					allowRenderInMainPassHandling = true
				}
			elseif type(attachOptionsRight) == "boolean" then
				attachOptionsRight = {
					detachFromOriginOnGrip = attachOptionsRight,
					maintainWorldPositionOnDetachFromOrigin = false,
					detachFromParentOnRelease = attachOptionsRight,
					maintainWorldPositionOnDetachFromParent = false,
					reattachToOriginOnRelease = allowReattach or false,
					restoreTransformToOriginOnReattach = allowReattach or false,
					useZeroTransformOnReattach = false,
					allowChildVisibilityHandling = true,
					allowChildHiddenInGameHandling = true,
					allowRenderInMainPassHandling = true
				}
			end
			if attachOptionsLeft == nil then
				attachOptionsLeft = {
					detachFromOriginOnGrip = true,
					maintainWorldPositionOnDetachFromOrigin = false,
					detachFromParentOnRelease = true,
					maintainWorldPositionOnDetachFromParent = false,
					reattachToOriginOnRelease = false,
					restoreTransformToOriginOnReattach = false,
					useZeroTransformOnReattach = false,
					allowChildVisibilityHandling = true,
					allowChildHiddenInGameHandling = true,
					allowRenderInMainPassHandling = true
				}
			elseif type(attachOptionsLeft) == "boolean" then
				attachOptionsLeft = {
					detachFromOriginOnGrip = attachOptionsLeft,
					maintainWorldPositionOnDetachFromOrigin = false,
					detachFromParentOnRelease = attachOptionsLeft,
					maintainWorldPositionOnDetachFromParent = false,
					reattachToOriginOnRelease = allowReattach or false,
					restoreTransformToOriginOnReattach = allowReattach or false,
					useZeroTransformOnReattach = false,
					allowChildVisibilityHandling = true,
					allowChildHiddenInGameHandling = true,
					allowRenderInMainPassHandling = true
				}
			end
			-- --print(attachment, mesh, autoUpdateCurrentAttachment)
			-- if detachFromParent == nil then detachFromParent = true end
			-- if allowReattach == nil then allowReattach = false end

			-- detach them first so switchiing left to right isnt affected
			if rightAttachment == nil then
				M.detachGripAttachments(Handed.Right)
			end
			if leftAttachment == nil then
				M.detachGripAttachments(Handed.Left)
			end

			-- if rightAttachment is nil then remove all right grip attachments
			if rightAttachment == nil then
				--M.detachGripAttachments(Handed.Right)
			elseif rightMesh == nil then
				M.attachToRawController(rightAttachment, Handed.Right, attachOptionsRight)
			else
				M.attachToMesh(rightAttachment, rightMesh, rightSocketName, Handed.Right, attachOptionsRight)
			end

			-- if leftAttachment is nil then remove all left grip attachments
			if leftAttachment == nil then
				--M.detachGripAttachments(Handed.Left)
			elseif leftMesh == nil then
				M.attachToRawController(leftAttachment, Handed.Left, attachOptionsLeft)
			else
				M.attachToMesh(leftAttachment, leftMesh, leftSocketName, Handed.Left, attachOptionsLeft)
			end

			-- print("After")
			-- printMeshAttachmentList()
			-- print("Left",activeGripAnimations[Handed.Left])
			-- print("Right",activeGripAnimations[Handed.Right])

			-- if rightMesh == nil and rightAttachment == nil then
			-- 	--do nothing
			-- elseif rightMesh == nil and rightAttachment ~= nil then
			-- 	--M.detachAttachmentFromMeshes(rightAttachment, handleParentAttachment)
			-- elseif rightMesh ~= nil and rightAttachment == nil then
			-- 	M.detachAttachmentsFromMesh(rightMesh, handleParentAttachment)
			-- elseif rightMesh ~= nil and rightAttachment ~= nil then
			-- 	M.attachToMesh(rightAttachment, rightMesh, rightSocketName, Handed.Right, handleParentAttachment)
			-- end

			-- if leftMesh == nil and leftAttachment == nil then
			-- 	--do nothing
			-- elseif leftMesh == nil and leftAttachment ~= nil then
			-- 	--M.detachAttachmentFromMeshes(leftAttachment, handleParentAttachment)
			-- 	M.attachToRawController(leftAttachment, Handed.Left, handleParentAttachment)
			-- elseif leftMesh ~= nil and leftAttachment == nil then
			-- 	M.detachAttachmentsFromMesh(leftMesh, handleParentAttachment)
			-- elseif leftMesh ~= nil and leftAttachment ~= nil then
			-- 	M.attachToMesh(leftAttachment, leftMesh, leftSocketName, Handed.Left, handleParentAttachment)
			-- end

			-- if mesh ~= nil then
			-- 	print("Children",mesh:get_full_name(),mesh.AttachChildren and #mesh.AttachChildren or 0)
			-- end
			-- if (mesh == nil and autoUpdateCurrentMesh~= nil) or (attachment == nil and autoUpdateCurrentAttachment ~= nil) then
			-- 	M.detach(autoUpdateCurrentAttachment, true)
			-- 	autoUpdateCurrentMesh = mesh
			-- 	autoUpdateCurrentAttachment = attachment
			-- elseif attachment ~= nil and mesh ~= nil and autoUpdateCurrentAttachment ~= attachment then
			-- 	M.attachToMesh(attachment, mesh, socketName, true)
			-- 	autoUpdateCurrentMesh = mesh
			-- 	autoUpdateCurrentAttachment = attachment
			-- end
		end)
	end
end

function M.setGunstockOffsetsEnabled(val)
	gunstockOffsetsEnabled = val
end

function M.registerOnScopeUpdateCallback(callback)
	scopeActiveCallback = callback
end

function M.registerOnGripAnimationCallback(callbackFunc)
	registerAttachmentCallback("attachment_grip_animation_changed", callbackFunc)
end

function M.registerAttachmentChangeCallback(callbackFunc)
	uevrUtils.registerUEVRCallback("attachment_grip_changed", callbackFunc)
end

--determines how often to check for grip attachment changes
function M.setGripUpdateTimeout(timeout)
	gripUpdateTimeout = timeout
end

uevrUtils.registerPreLevelChangeCallback(function(level)
	meshAttachmentList = {}
	activeGripAnimations = {}
	sightsCache = {}
end)

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
	M.broadcastGrippedAttachmentRotation()
end)

uevr.params.sdk.callbacks.on_script_reset(function()
	M.detachAllAttachments()
end)

M.loadParameters()

return M