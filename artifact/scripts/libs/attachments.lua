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

    attachments.forceGripUpdate() - immediately runs one grip-update pass (same work as the periodic timer).
		Use after temporarily suppressing mesh reattach so the weapon snaps back without waiting for setGripUpdateTimeout.
		example:
			attachments.forceGripUpdate()

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
local mathLib = require("libs/core/math_lib")
local physics = require("libs/physics")

--local debugger = require("libs/uevr_debug")

local M = {}

M.AttachType =
{
    MESH = 0,
    CONTROLLER = 1,
    RAW_CONTROLLER = 2,
    -- VIRTUAL: attachment is registered for UI / animation purposes only, never
    -- physically re-parented. Stalker 2 specific — see registerGrippedAttachment below.
    VIRTUAL = 3,
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
local attachmentIDCache = {}
local attachmentNameCache = {}
local attachmentOverrideChildLookup = {}
local attachmentOverrideParentLookup = {}
local attachmentStrippedChildLookup = {}
local attachmentStrippedKeyCanonicalChildLookup = {}
local attachmentStripLengths = {}
local attachmentNameLookupDirty = true
local invalidateAttachmentNameLookups
-- Forward declaration: defined next to setAnimationIDs (which owns animationIDs/animationLabels)
-- but must be callable from showDeveloperConfiguration, which appears earlier in this file.
local syncGripAnimationSelections

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
				id = widgetPrefix .. name .. "_sights_rotation_offset", label = "Sights Rotation Offset",
				widgetType = "drag_float3", speed = .1, range = {-360, 360}, initialValue = sightsPositionOffset,  width = 250
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
            { widgetType = "same_line" }
		)
		table.insert(configDefinition[1]["layout"],
			{
				widgetType = "input_text",
				id = widgetPrefix .. name .. "_strip_child_suffix_length",
				label = "Strip child suffix length",
				initialValue = false,
				wrapped = true,
				width = 50
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
		configui.onCreateOrUpdate(widgetPrefix .. name .. "_strip_child_suffix_length", function(value)
			M.updateAttachmentStripChildSuffixLength(id, value)
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
		configui.onUpdate(widgetPrefix .. name .. "_sights_rotation_offset", function(value)
			M.updateSightsRotationOffset(value, id)
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
			widgetType = "checkbox",
			id = "uevr_attachments_use_left_hand_offsets",
			label = "Use Offsets For Left Hand",
			initialValue = false
		}
	)
	table.insert(configDefinition[1]["layout"],{ widgetType = "indent", width = 20 })
	table.insert(configDefinition[1]["layout"],
		{
			widgetType = "begin_group", id = "uevr_attachments_use_left_hand_offsets_group", isHidden = true
		}
	)
		table.insert(configDefinition[1]["layout"],
			{
				widgetType = "checkbox",
				id = "uevr_attachments_left_hand_flip_x",
				label = "Flip X",
				initialValue = false
			}
		)
		table.insert(configDefinition[1]["layout"],
			{ widgetType = "same_line" }
		)
		table.insert(configDefinition[1]["layout"],
			{
				widgetType = "checkbox",
				id = "uevr_attachments_left_hand_flip_y",
				label = "Flip Y",
				initialValue = false
			}
		)
		table.insert(configDefinition[1]["layout"],
			{ widgetType = "same_line" }
		)
		table.insert(configDefinition[1]["layout"],
			{
				widgetType = "checkbox",
				id = "uevr_attachments_left_hand_flip_z",
				label = "Flip Z",
				initialValue = false
			}
		)
		table.insert(configDefinition[1]["layout"],
			{
				id = "uevr_attachments_left_hand_position", label = "Position",
				widgetType = "drag_float3", speed = .1, range = {-500, 500}, initialValue = {0,0,0}
			}
		)
		table.insert(configDefinition[1]["layout"],
			{
				id = "uevr_attachments_left_hand_rotation", label = "Rotation",
				widgetType = "drag_float3", speed = .1, range = {-360, 360}, initialValue = {0,0,0}
			}
		)
		table.insert(configDefinition[1]["layout"],
			{
				id = "uevr_attachments_left_hand_scale", label = "Scale",
				widgetType = "drag_float3", speed = .1, range = {-10, 10}, initialValue = {1,1,1}
			}
		)
	table.insert(configDefinition[1]["layout"],
		{
			widgetType = "end_group"
		}
	)
	table.insert(configDefinition[1]["layout"],{ widgetType = "unindent", width = 20 })
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
	if parameters["leftHandOffsets"] == nil then
		parameters["leftHandOffsets"] = {location = {0,0,0}, rotation = {0,0,0}, scale = {1,1,1}, flip_x = false, flip_y = false, flip_z = false}
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
	invalidateAttachmentNameLookups()
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

	configui.setValue("use_uevr_attachments_strip_parent_name_numeric_suffix", parameters["stripParentNameNumericSuffix"] or false, true)
	configui.setValue("uevr_attachment_base_rotation", parameters["baseOffsets"].rotation or {0,0,0}, true)

	--Other modules may update this later but let's set it here using the default hands params file so we have defaults
	local handConfigurationFileName = "hands_parameters"
	local handsConfiguration = json.load_file(handConfigurationFileName .. ".json")
	if handsConfiguration ~= nil then
		M.setAnimationIDs(handsConfiguration["attachments"])
	end

	-- The call above usually early-returns: Entry.lua deliberately calls setAnimationIDs BEFORE
	-- init() (to stop configui baking in the stale {"Default","None"} list), which means
	-- currentAnimationIDList already matches and deepEqual() short-circuits the rebuild. At that
	-- earlier point the widgets did not exist yet, so nothing was synced — and configui.create()
	-- above has just applied the persisted (stale) combo indices. Sync unconditionally here, now
	-- that the widgets exist, so each dropdown shows the animation its ID actually names.
	syncGripAnimationSelections()
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

invalidateAttachmentNameLookups = function()
	attachmentIDCache = {}
	attachmentNameCache = {}
	attachmentOverrideChildLookup = {}
	attachmentOverrideParentLookup = {}
	attachmentStrippedChildLookup = {}
	attachmentStrippedKeyCanonicalChildLookup = {}
	attachmentStripLengths = {}
	attachmentNameLookupDirty = true
end

local function rebuildAttachmentNameLookups()
	attachmentOverrideChildLookup = {}
	attachmentOverrideParentLookup = {}
	attachmentStrippedChildLookup = {}
	attachmentStrippedKeyCanonicalChildLookup = {}
	attachmentStripLengths = {}

	-- "any_child" means: for this parent, ignore the real child mesh and always resolve to this
	-- entry's child. That is only meaningful when the parent hosts exactly ONE attachment.
	-- In Stalker 2 EVERY weapon is a child of the same parent ("CharacterMesh"), so if more than
	-- one entry sets any_child the map below collapses all of them onto whichever entry is written
	-- last, and getAttachmentNames() then reports that one weapon for every weapon you hold
	-- (never even reading the real SkeletalMesh). Track conflicts and drop those overrides so a
	-- stray "Use for all children" checkbox cannot silently break per-weapon resolution.
	local anyChildConflict = {}

	for i = 1, #attachmentOffsets do
		local offset = attachmentOffsets[i]
		local parentName = offset["parent"]
		local childName = offset["child"]

		if offset["any_child"] == true and parentName ~= nil then
			if attachmentOverrideChildLookup[parentName] ~= nil then
				anyChildConflict[parentName] = true
			end
			attachmentOverrideChildLookup[parentName] = childName or ""
		end

		if offset["any_parent"] == true and childName ~= nil then
			attachmentOverrideParentLookup[childName] = parentName or ""
		end

		local stripChildSuffixLength = offset["strip_child_suffix_length"] or 0
		if type(stripChildSuffixLength) == "string" then
			stripChildSuffixLength = tonumber(stripChildSuffixLength) or 0
		end
		if stripChildSuffixLength > 0 and childName ~= nil then
			if attachmentStrippedChildLookup[stripChildSuffixLength] == nil then
				attachmentStrippedChildLookup[stripChildSuffixLength] = {}
				table.insert(attachmentStripLengths, stripChildSuffixLength)
			end
			local strippedChildName = string.sub(childName, 1, -stripChildSuffixLength - 1)
			attachmentStrippedChildLookup[stripChildSuffixLength][strippedChildName] = childName
			if offset["any_parent"] == true then
				attachmentStrippedKeyCanonicalChildLookup[strippedChildName] = childName
			end
		end
	end

	-- Ambiguous any_child overrides are worse than none: fall back to reading the real mesh.
	for parentName, _ in pairs(anyChildConflict) do
		M.print("Ignoring ambiguous 'any_child' override for parent '" .. tostring(parentName)
			.. "' (multiple attachments claim it) - resolving from the real mesh instead", LogLevel.Warning)
		attachmentOverrideChildLookup[parentName] = nil
	end

	attachmentNameLookupDirty = false
end

local function getOverrideChildname(parentName)
	if attachmentNameLookupDirty then
		rebuildAttachmentNameLookups()
	end
	return attachmentOverrideChildLookup[parentName] or ""
end

local function getOverrideParentname(childName)
	if attachmentNameLookupDirty then
		rebuildAttachmentNameLookups()
	end
	return attachmentOverrideParentLookup[childName] or ""
end

local function getStrippedChildname(childName)
	if attachmentNameLookupDirty then
		rebuildAttachmentNameLookups()
	end
	for i = 1, #attachmentStripLengths do
		local stripChildSuffixLength = attachmentStripLengths[i]
		local strippedChildName = string.sub(childName, 1, -stripChildSuffixLength - 1)
		local existingChildName = attachmentStrippedChildLookup[stripChildSuffixLength][strippedChildName]
		if existingChildName ~= nil then
			local canonicalChildName = attachmentStrippedKeyCanonicalChildLookup[strippedChildName]
			if canonicalChildName ~= nil and canonicalChildName ~= existingChildName then
				return canonicalChildName
			end
			return existingChildName
		end
	end
	return childName
end

local function getAttachmentNames(attachment)
	local attachmentFullName = attachment:get_full_name()
	local cachedNames = attachmentNameCache[attachmentFullName]
	if cachedNames ~= nil then
		return cachedNames.parentName, cachedNames.childName, cachedNames.attachmentID
	end

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

	attachmentChildName = getStrippedChildname(attachmentChildName)

	local attachmentParentName_Alt = getOverrideParentname(attachmentChildName)
	if attachmentParentName_Alt ~= "" then
		attachmentParentName = attachmentParentName_Alt
	end

	local attachmentID = attachmentParentName .. "_" .. attachmentChildName
	attachmentNameCache[attachmentFullName] = {
		parentName = attachmentParentName,
		childName = attachmentChildName,
		attachmentID = attachmentID,
	}

	return attachmentParentName, attachmentChildName, attachmentID
end
getAttachmentNames = uevrUtils.profiler:wrap("Attachments: getAttachmentNames", getAttachmentNames)

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

-- weaponChildNameHint: optional short mesh name overriding the derived child name when
-- the attachment's SkeletalMesh property is stale during weapon-swap transitions.
function M.addAttachmentToConfig(attachment, weaponChildNameHint)
	if parameters ~= nil then
		local attachmentParentName, attachmentChildName, id = getAttachmentNames(attachment)
		if weaponChildNameHint then
			attachmentChildName = weaponChildNameHint
			id = attachmentParentName .. "_" .. attachmentChildName
		end

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
				invalidateAttachmentNameLookups()
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
	invalidateAttachmentNameLookups()
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
getAttachmentOffsetByID = uevrUtils.profiler:wrap("Attachments: getAttachmentOffsetByID", getAttachmentOffsetByID)

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
		if attachment.RelativeLocation.X > 10000 or attachment.RelativeLocation.Y > 10000 or attachment.RelativeLocation.Z > 10000 then
			M.print("Attachment location is too large. Resetting to 0,0,0: " .. attachment.RelativeLocation.X .. ", " .. attachment.RelativeLocation.Y .. ", " .. attachment.RelativeLocation.Z)
			attachmentLocation = {0,0,0}
			attachment.RelativeLocation.X = 0
			attachment.RelativeLocation.Y = 0
			attachment.RelativeLocation.Z = 0
		else
			attachmentLocation = {attachment.RelativeLocation.X, attachment.RelativeLocation.Y, attachment.RelativeLocation.Z}
		end
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
updateScopeForAttachmentID = uevrUtils.profiler:wrap("Attachments: updateScopeForAttachmentID", updateScopeForAttachmentID)

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
	local sightsLocationOffset, sightsRotationOffset = M.getActiveAttachmentSightsOffsets(gripHand)
	attachmentLasers[gripHand]:setRelativePosition(sightsLocationOffset)
	local finalRotation = sightsRotationOffset
	local rot = parameters["baseOffsets"]["rotation"]
	if rot ~= nil then
		finalRotation = kismet_math_library:ComposeRotators(uevrUtils.rotator(rot), sightsRotationOffset)
	end
	attachmentLasers[gripHand]:setRelativeRotation(finalRotation)
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
			local sightsLocationOffset, sightsRotationOffset = M.getActiveAttachmentSightsOffsets(gripHand)
			attachmentLasers[gripHand]:setRelativePosition(sightsLocationOffset)

			local finalRotation = sightsRotationOffset
			local rot = parameters["baseOffsets"]["rotation"]
			if rot ~= nil then
				finalRotation = kismet_math_library:ComposeRotators(uevrUtils.rotator(rot), sightsRotationOffset)
			end
			attachmentLasers[gripHand]:setRelativeRotation(finalRotation)
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
updateLaserForAttachmentID = uevrUtils.profiler:wrap("Attachments: updateLaserForAttachmentID", updateLaserForAttachmentID)

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
local zeroVector = uevrUtils.vector(0,0,0)
local zeroRotation = uevrUtils.rotator(0,0,0)
local sightsCache = {}
function M.updateSightsPositionOffset(positionOffset, id)
	local offset = getAttachmentOffsetByID(id)
	if offset ~= nil then
		offset["sights_position_offset"] = {positionOffset.X, positionOffset.Y, positionOffset.Z}
		sightsCache[id] = nil --the cache will update itself next time it's requested
		updateLaserForAttachmentID(id)
	end
	parameters["attachmentOffsets"] = attachmentOffsets --TODO doesnt seem like the whole document needs to be re-written
	isParametersDirty = true
end

function M.updateSightsRotationOffset(rotationOffset, id)
	local offset = getAttachmentOffsetByID(id)
	if offset ~= nil then
		offset["sights_rotation_offset"] = {rotationOffset.Roll, rotationOffset.Pitch, rotationOffset.Yaw}
		sightsCache[id] = nil --the cache will update itself next time it's requested
		updateLaserForAttachmentID(id)
	end
	parameters["attachmentOffsets"] = attachmentOffsets --TODO doesnt seem like the whole document needs to be re-written
	isParametersDirty = true
end

function M.getSightsOffsets(id)
	if sightsCache[id] ~= nil then
		return sightsCache[id][1], sightsCache[id][2]
	end
	local vector = nil
	local rotation = nil
	local offset = getAttachmentOffsetByID(id)
	if offset ~= nil then
		local pos = offset["sights_position_offset"]
		if pos ~= nil then
			vector = uevrUtils.vector(pos)
		end
		local rot = offset["sights_rotation_offset"]
		if rot ~= nil then
			rotation = uevrUtils.rotator(rot)
		end
	end
	if vector == nil then
		vector = zeroVector
	end
	if rotation == nil then
		rotation = zeroRotation
	end
	sightsCache[id] = {vector, rotation}
	return vector, rotation
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
			if uevrUtils.getValid(attachmentData.attachment) ~= nil and attachmentData.attachment.K2_GetComponentLocation ~= nil then
				local location = attachmentData.attachment:K2_GetComponentLocation()
				local rotation = attachmentData.attachment:K2_GetComponentRotation()
				local sightsLocationOffset, sightsRotationOffset = M.getActiveAttachmentSightsOffsets(hand)

				rotation = mathLib.composeRotators(uevrUtils.rotator(parameters["baseOffsets"]["rotation"]), rotation)

				-- This is almost definitely right but SH2 rifle and shotgun fire dont match laset aim when using this
				--rotation = kismet_math_library:ComposeRotators(kismet_math_library:ComposeRotators(uevrUtils.rotator(parameters["baseOffsets"]["rotation"]), sightsRotationOffset), rotation)
				--rotation = kismet_math_library:ComposeRotators(uevrUtils.rotator(parameters["baseOffsets"]["rotation"]), rotation)
				local vector = uevrUtils.rotateVector(sightsLocationOffset, rotation)
				location = location + vector

				return location, rotation
			end
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

			local sightsLocationOffset, sightsRotationOffset = M.getActiveAttachmentSightsOffsets(hand)
			local vector = uevrUtils.rotateVector(sightsLocationOffset, rotation)
			location = location + vector
			return location, rotation
		end
	end
	return uevrUtils.vector(0,0,0), uevrUtils.rotator(0,0,0)
end
M.getActiveAttachmentTransforms = uevrUtils.profiler:wrap("Attachments: getActiveAttachmentTransforms", M.getActiveAttachmentTransforms)

function M.getActiveAttachmentMeleeRotationOffset(hand)
	local attachmentID = M.getActiveAttachmentID(hand)
	if attachmentID ~= nil then
		return M.getMeleeRotationOffset(attachmentID)
	end
	return uevrUtils.rotator(0,0,0)
end

function M.getActiveAttachmentSightsOffsets(hand)
	local attachmentID = M.getActiveAttachmentID(hand)
	if attachmentID ~= nil then
		return M.getSightsOffsets(attachmentID)
	end
	return zeroVector, zeroRotation
end

function M.setAttachmentOffset(id, location, rotation, scale)
	for i = 1, #attachmentOffsets do
		local attachmentID = attachmentOffsets[i]["id"]
		if id == attachmentID then
			if location ~= nil then attachmentOffsets[i]["location"] = {location.X, location.Y, location.Z} end
			if rotation ~= nil then attachmentOffsets[i]["rotation"] = {rotation.X, rotation.Y, rotation.Z} end
			if scale ~= nil then attachmentOffsets[i]["scale"] = {scale.X, scale.Y, scale.Z} end
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
	if propertyName == "any_child" or propertyName == "any_parent" or propertyName == "strip_child_suffix_length" then
		invalidateAttachmentNameLookups()
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

function M.updateAttachmentStripChildSuffixLength(id, length)
	updateAttachmentProperty(id, "strip_child_suffix_length", length)
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

function M.getAttachmentIDFromAttachment(attachment)
	if attachment ~= nil then
		-- A freed attachment (weapon swap / level transition / recycled WeaponInHandsMesh) can
		-- still pass getValid/exists() on this backend; get_full_name then throws
		-- "caught (...) exception" out of the per-tick callers (accessories proximity check,
		-- grip broadcasts). Treat an inaccessible attachment as having no ID - every caller
		-- already handles nil.
		local ok, name = pcall(function() return attachment:get_full_name() end)
		if not ok or name == nil then return nil end
		if attachmentIDCache[name] ~= nil then
			return attachmentIDCache[name]
		end
		local okNames, _, _, attachmentID = pcall(getAttachmentNames, attachment)
		if not okNames then return nil end
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
function M.updateAttachmentTransform(pos, rot, scale, id, gripHand)
	if gripHand == nil then gripHand = Handed.Right end
	if id ~= nil then
		M.setAttachmentOffset(id, pos, rot, scale)
	end

	--only using rotationOffset on the Raw Controller currently assuming if the attachment is connected to a mesh then the mesh will be rotated
	--local rotationOffset = gunstock.setActive(id)
	M.print("Updating attachment transform for id " .. tostring(id))
	local attachmentDataArray = getAttachmentDataFromMeshAttachmentList(id)
	--local attachment, attachType, attachState = getAttachmentDataFromMeshAttachmentList(id)
	for j = 1, #attachmentDataArray do
		local attachmentData = attachmentDataArray[j]
		--without the check for attachmentData.gripHand == gripHand, if both hands hold the same kind of attachment, one will overwrite the other
		--Very important where left hand offsets are used
		if attachmentData ~= nil and attachmentData.gripHand == gripHand then
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
				if pos ~= nil then
					local finalPos = pos
					if parameters["use_left_hand_offsets"] == true and gripHand == Handed.Left then
						finalPos = {pos.X * (parameters["leftHandOffsets"]["flip_x"] and -1 or 1) + parameters["leftHandOffsets"]["location"][1], pos.Y * (parameters["leftHandOffsets"]["flip_y"] and -1 or 1) + parameters["leftHandOffsets"]["location"][2], pos.Z * (parameters["leftHandOffsets"]["flip_z"] and -1 or 1) + parameters["leftHandOffsets"]["location"][3]}
					end
					--print("Setting attachment location", finalPos.X, finalPos.Y, finalPos.Z)
					uevrUtils.set_component_relative_location(attachment, finalPos)
				end
				if rot ~= nil then
			--This all seems wrong
					local offsetRot = uevrUtils.rotator(rot)
					local gunstockRot = uevrUtils.rotator(gunstockRotationOffset)
					local baseRot = uevrUtils.rotator(parameters["baseOffsets"]["rotation"])
					--local old = offsetRot + gunstockRot - baseRot
					baseRot.Pitch = -baseRot.Pitch
					baseRot.Yaw = -baseRot.Yaw
					baseRot.Roll = -baseRot.Roll
					local finalRot = uevrUtils.sumRotators(offsetRot, gunstockRot, baseRot)
					--local finalRot2 = kismet_math_library:ComposeRotators(kismet_math_library:ComposeRotators(gunstockRot,offsetRot), baseRot ) --uevrUtils.rotator(rot)
					--local finalRot3 = kismet_math_library:ComposeRotators(kismet_math_library:ComposeRotators(offsetRot, gunstockRot), baseRot ) --uevrUtils.rotator(rot)

					if parameters["use_left_hand_offsets"] == true and gripHand == Handed.Left then
						finalRot = kismet_math_library:ComposeRotators(uevrUtils.rotator(parameters["leftHandOffsets"]["rotation"][1],parameters["leftHandOffsets"]["rotation"][2],parameters["leftHandOffsets"]["rotation"][3]), finalRot)
					end

					if offsetRot ~= nil then uevrUtils.set_component_relative_rotation(attachment, finalRot) end
					--local combined = finalRot --offsetRot + gunstockRot - baseRot
					--print("Set rotation", offsetRot.Pitch, offsetRot.Yaw, offsetRot.Roll, "/", gunstockRot.Pitch, gunstockRot.Yaw, gunstockRot.Roll, "/", baseRot.Pitch, baseRot.Yaw, baseRot.Roll, "/", combined.Pitch, combined.Yaw, combined.Roll, "/", finalRot2.Pitch, finalRot2.Yaw, finalRot2.Roll, "/",  old.Pitch, old.Yaw, old.Roll)
				end
				if scale ~= nil then
					if parameters["use_left_hand_offsets"] == true and gripHand == Handed.Left then
						--uevrUtils.set_component_relative_scale(attachment, {-scale.X, -scale.Y, -scale.Z})
						uevrUtils.set_component_relative_scale(attachment, {scale.X * parameters["leftHandOffsets"]["scale"][1], scale.Y * parameters["leftHandOffsets"]["scale"][2], scale.Z * parameters["leftHandOffsets"]["scale"][3]})
					else
						uevrUtils.set_component_relative_scale(attachment, scale)
					end
				end
				--print(attachment.RelativeScale3D.X, attachment.RelativeScale3D.Y, attachment.RelativeScale3D.Z)
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
M.updateAttachmentTransform = uevrUtils.profiler:wrap("Attachments: updateAttachmentTransform", M.updateAttachmentTransform)

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
updateSelectedColor = uevrUtils.profiler:wrap("Attachments: updateSelectedColor", updateSelectedColor)

local function updateSelectedColors()
	for i = 1, #attachmentOffsets do
		local parent = attachmentOffsets[i]["parent"]
		local child = attachmentOffsets[i]["child"]
		local m_id = attachmentOffsets[i]["id"]
		if m_id == nil then m_id = parent .. "_" .. child end
		configui.setColor(widgetPrefix .. m_id, "#FFFFFFFF")
	end

	-- Find the stored overrideID for each grip hand (set when registerGrippedAttachment was called
	-- with a weaponChildNameHint, which bypasses the stale SkeletalMesh read during transitions)
	local leftID, rightID = nil, nil
	for meshName, meshData in pairs(meshAttachmentList) do
		for attachmentName, attachmentData in pairs(meshData.attachments or {}) do
			if attachmentData ~= nil then
				if attachmentData.gripHand == Handed.Right and attachmentData.overrideID then
					rightID = attachmentData.overrideID
				elseif attachmentData.gripHand == Handed.Left and attachmentData.overrideID then
					leftID = attachmentData.overrideID
				end
			end
		end
	end

	--print("Updating selected colors for left and right attachments", leftAttachment, rightAttachment)
	if rightID == nil then
		local rightAttachment = uevrUtils.getValid(M.getCurrentGrippedAttachment(Handed.Right))
		if rightAttachment ~= nil then
			rightID = M.getAttachmentIDFromAttachment(rightAttachment)
		end
	end
	if leftID == nil then
		local leftAttachment = uevrUtils.getValid(M.getCurrentGrippedAttachment(Handed.Left))
		if leftAttachment ~= nil then
			leftID = M.getAttachmentIDFromAttachment(leftAttachment)
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
updateSelectedColors = uevrUtils.profiler:wrap("Attachments: updateSelectedColors", updateSelectedColors)


function M.initAttachment(attachment, gripHand, options)
	if attachment ~= nil then
		invalidateAttachmentNameLookups()
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
		M.updateAttachmentTransform(location, rotation, scale, id, gripHand)
		M.setActiveAnimation(attachment, gripHand)

		updateScopeForAttachmentID(id)
		updateLaserForAttachmentID(id)
		updateSelectedColors()
		uevrUtils.executeUEVRCallbacks("attachment_initialized", attachment)
	end
end
M.initAttachment = uevrUtils.profiler:wrap("Attachments: initAttachment", M.initAttachment)

function M.registerAttachmentInitializedCallback(callback)
	uevrUtils.registerUEVRCallback("attachment_initialized", callback)
end


-- weaponChildNameHint: optional short mesh name (e.g. "SK_rhino00000") used to match
-- the animation entry when attachment.SkeletalMesh returns a stale value during
-- weapon-swap transitions (equip/unequip montages temporarily revert the mesh).
-- Bypasses getAttachmentIDFromAttachment() and matches attachmentOffsets[i].child directly.
function M.setActiveAnimation(attachment, gripHand, weaponChildNameHint)
	if gripHand ~= nil then
		local previousAnimation = activeGripAnimations[gripHand]
		local nextAnimation = false
		if uevrUtils.getValid(attachment) ~= nil then
			nextAnimation = true
			local attachmentOffset = nil
			if weaponChildNameHint then
				for i = 1, #attachmentOffsets do
					if attachmentOffsets[i]["child"] == weaponChildNameHint then
						attachmentOffset = attachmentOffsets[i]
						break
					end
				end
			else
				local attachmentID = M.getAttachmentIDFromAttachment(attachment)
				--print("Attachment ID", attachmentID)
				attachmentOffset = attachmentID ~= nil and getAttachmentOffsetByID(attachmentID) or nil
			end
			--print("Attachment Offset", attachmentOffset)
			-- for k, v in pairs(attachmentOffset) do
			-- 	print("Attachment Offset Key", k, "Value", v)
			-- end
			if attachmentOffset ~= nil and attachmentOffset["animation"] ~= nil then
				--print("Attachment Offset Animation", attachmentOffset["animation"])
				nextAnimation = attachmentOffset["animation"] == "animation_none" and false or attachmentOffset["animation"]
			end
		end
		activeGripAnimations[gripHand] = nextAnimation
		if previousAnimation == nextAnimation then
			return
		end
		M.print("Calling callback for grip animation " .. tostring(nextAnimation) .. " " .. tostring(gripHand))
		executeGripAnimationChange(nextAnimation, gripHand)
		--executeAttachmentCallbacks("grip_animation", activeGripAnimations[gripHand], gripHand)
	end
end
M.setActiveAnimation = uevrUtils.profiler:wrap("Attachments: setActiveAnimation", M.setActiveAnimation)

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
M.getCurrentGrippedAttachment = uevrUtils.profiler:wrap("Attachments: getCurrentGrippedAttachment", M.getCurrentGrippedAttachment)

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
M.getCurrentGrippedAttachmentData = uevrUtils.profiler:wrap("Attachments: getCurrentGrippedAttachmentData", M.getCurrentGrippedAttachmentData)

-- PERF (2026-09-08): runs every pre-engine tick. The MuzzleSocket FName is now resolved once
-- (was a Conv_StringToName UFunction call per gripped hand per frame), and the dispatch is skipped
-- when nothing is gripped AND the previous broadcast was also empty. Grip/ungrip transitions still
-- broadcast (including the nil,nil one) so input.lua can clear its cached weapon rotation.
local muzzleSocketFName = nil
local lastBroadcastHadAttachment = true -- force the first broadcast through
local staleAttachmentWarned = false

-- A gripped attachment can be freed (weapon swap, level transition) while its cached
-- handle still passes getValid/exists(); touching it then throws "caught (...) exception"
-- from the index metamethod out of on_pre_engine_tick. Treat it as no rotation instead.
local function getMuzzleRotation(attachment)
	if attachment == nil then return nil end
	local ok, rot = pcall(function()
		if attachment.GetSocketRotation ~= nil then
			return attachment:GetSocketRotation(muzzleSocketFName)
		end
	end)
	if ok then return rot end
	if not staleAttachmentWarned then
		staleAttachmentWarned = true
		M.print("broadcastGrippedAttachmentRotation: gripped attachment is no longer accessible (freed?), skipping", LogLevel.Warning)
	end
	return nil
end

function M.broadcastGrippedAttachmentRotation()
	local leftAttachment = M.getCurrentGrippedAttachment(Handed.Left)
	local rightAttachment = M.getCurrentGrippedAttachment(Handed.Right)
	local hasAttachment = (leftAttachment ~= nil) or (rightAttachment ~= nil)
	if not hasAttachment and not lastBroadcastHadAttachment then
		return
	end
	lastBroadcastHadAttachment = hasAttachment
	if hasAttachment and muzzleSocketFName == nil then
		muzzleSocketFName = uevrUtils.fname_from_string("MuzzleSocket")
	end
	executeGripAttachmentRotationChange(getMuzzleRotation(leftAttachment), getMuzzleRotation(rightAttachment))
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

local physicsStatus = {}
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

		-- print("Inside mesh attachment",  tostring(options.usePhysicsHandle))
		-- if options.usePhysicsHandle == true then
		-- 	if physicsStatus[gripHand] == nil then
		-- 		physicsStatus[gripHand] = {}
		-- 		--need to detach any normal gripped meshes but should only do it once
		-- 		if gripHand ~= nil then
		-- 			M.detachGripAttachments(gripHand)
		-- 		end
		-- 	end

		-- 	if physicsStatus[gripHand] ~= attachment:get_full_name() then
		-- 		physics.releaseComponentWithPhysicsHandle(physicsStatus[gripHand])

		-- 		physicsStatus[gripHand] = attachment:get_full_name()
		-- 		M.initAttachment(attachment, gripHand, options)
		-- 		--M.createPhysicsHandle(attachment:get_full_name())
		-- 		physics.createPhysicsHandle(attachment:get_full_name(), nil, nil, nil)
		-- 		physics.grabComponentWithPhysicsHandle(attachment:get_full_name(), attachment)
		-- 	end

		-- 	return true
		-- end

		-- if physicsStatus[gripHand] ~= nil then
		-- 	physics.releaseComponentWithPhysicsHandle(physicsStatus[gripHand])
		-- end
		-- physicsStatus[gripHand] = nil

		--see if the attachment is already a child of the mesh
		--In atomic heart, the entire attachment can run apparently successfully and still not be attached to the mesh
		--Something in the engine must disconnect it (probably the animation) after the attach call. So this check can not be removed.
		local meshName = mesh:get_full_name()
		local attachmentName = attachment:get_full_name()
		local childMesh = attachment.StaticMesh or attachment.SkeletalMesh
		local childMeshName = childMesh and childMesh:get_full_name() or ""
		--print("Checking if attachment is already a child of the mesh", meshName, attachmentName, childMeshName)
		if meshAttachmentList[meshName] ~= nil and meshAttachmentList[meshName].attachments ~= nil and meshAttachmentList[meshName].attachments[attachmentName] ~= nil then
			if meshAttachmentList[meshName].attachments[attachmentName].childMeshName == childMeshName then
				-- AttachParent is the source of truth. AttachChildren can lag after the game
				-- reparents the weapon (e.g. anim notify), which made forceGripUpdate no-op.
				if attachment.AttachParent == mesh then
					return true
				end
				-- Tracked as gripped to this mesh but currently parented elsewhere (e.g. accessories
				-- temporarily promoted it to a motion controller to break an IK hierarchy cycle,
				-- or a game anim notify owns parenting for a reload window).
				-- Do not steal it back while that override is active.
				if uevrUtils.executeUEVRCallbacksWithBooleanResult("attachment_suppress_mesh_reattach", attachment, mesh) == true then
					return true
				end
			end
		end

		-- Also honor suppress when the tracked-entry checks above don't match (name/mesh churn).
		if uevrUtils.executeUEVRCallbacksWithBooleanResult("attachment_suppress_mesh_reattach", attachment, mesh) == true then
			return true
		end


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

		-- We have to check for existence because with IK arms there is one mesh for left and right and we dont want to overwrite each time
		if meshAttachmentList[meshName] ==  nil then
			meshAttachmentList[meshName] = {mesh = mesh, attachments = {}}
		end
		--local attachmentName = attachment:get_full_name()
		--if meshAttachmentList[meshName][attachmentName] == nil then
			meshAttachmentList[meshName].attachments[attachmentName] = {childMeshName = childMeshName, attachment=attachment, socket=socketName, detachFromParentOnRelease = options.detachFromParentOnRelease, maintainWorldPositionOnDetachFromParent = options.maintainWorldPositionOnDetachFromParent, attachType = M.AttachType.MESH, gripHand = gripHand}
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
		pcall(function()
			if options.detachFromOriginOnGrip == true and attachment.DetachFromParent ~= nil then
				attachment:DetachFromParent(options.maintainWorldPositionOnDetachFromOrigin or false, false)
			end
		end)

		M.print("Attaching attachment to mesh: " .. attachment:get_full_name() .. " to " .. mesh:get_full_name())
		if type(socketName) == "string" then
			socketName = uevrUtils.fname_from_string(socketName)
		end
		if options.useCurrentAttachedSocketName ~= false then
			if socketName == nil then socketName = attachment.AttachSocketName end
		end
		if socketName == nil then
			socketName = uevrUtils.fname_from_string("")
		end
	    local ok, result = pcall(function()
			--print("Attempting to attach attachment to mesh with socket", socketName)
			local result = attachment:K2_AttachTo(mesh, socketName, 0, false)
			if result == false and options.allowMobiltyChange == true then
				attachment.Mobility = 2
				result = attachment:K2_AttachTo(mesh, socketName, 0, false)
			end
			return result -- attachment:K2_AttachTo(mesh, socketName, 0, false)
		end)
		if not ok then
			M.print("Failed to attach attachment to mesh in pcall")
			M.print(result)
			return false
		end
		success = result

		if success then M.initAttachment(attachment, gripHand, options) end
		M.print("" .. (success and " Attached attachment to mesh successfully" or " Failed to attach attachment to mesh because attach result was false"))

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

--set grip hand to nil and use the hand param instead if you just want a non-managed attachment
function M.attachToRawController(attachment, gripHand, options, hand)
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
		pcall(function()
			if options.detachFromOriginOnGrip == true then
				attachment:DetachFromParent(options.maintainWorldPositionOnDetachFromOrigin or false, false)
			end
		end)

		M.print("Attaching " .. attachment:get_full_name() .. " to raw controller with ID " .. (gripHand and tostring(gripHand) or "nil"))
		local state = UEVR_UObjectHook.get_or_add_motion_controller_state(attachment)
		state:set_hand(hand or gripHand)
		state:set_permanent(options.restoreTransformToOriginOnReattach == true)
		meshAttachmentList[meshName].attachments[attachmentName].state = state

		M.initAttachment(attachment, gripHand, options)
		M.print("Attached attachment to raw controller")
	else
		M.print("Failed to attach attachment to raw controller")
	end
end

function M.detach(attachment, parent, attachType, originalTransform, detachFromParentOnRelease, maintainWorldPositionOnDetachFromParent)
	--print("Detaching attachment", attachment, parent or nil, attachType)
	if uevrUtils.getValid(attachment) ~= nil then
		--grab the name early before its detached or else it will be lost at reattach time
		local attachSocketName = attachment.AttachSocketName

		if attachType == M.AttachType.RAW_CONTROLLER then
			M.print("Detaching attachment from raw controller: " .. attachment:get_full_name())
			UEVR_UObjectHook.remove_motion_controller_state(attachment)
		end
		-- VIRTUAL entries are registered for UI/animation tracking only — never
		-- physically re-parented, so skip DetachFromParent / K2_AttachTo.
		if attachType == M.AttachType.VIRTUAL then
			M.print("Skipping physical detach for VIRTUAL attachment: " .. attachment:get_full_name())
			return
		end
		M.print("Detaching attachment " .. attachment:get_full_name() .. (parent and (" and reattaching to parent: " .. parent:get_full_name()) or " did not reattach to parent because no parent existed"))
		pcall(function()
			if detachFromParentOnRelease == true then
				attachment:DetachFromParent(maintainWorldPositionOnDetachFromParent, false)
			end
		end)
		if parent ~= nil then
			if originalTransform ~= nil then
				-- print("Restoring original transform on reattach", originalTransform.location.X, originalTransform.location.Y, originalTransform.location.Z,
				-- 	originalTransform.rotation.Pitch, originalTransform.rotation.Yaw, originalTransform.rotation.Roll,
				-- 	originalTransform.scale.X, originalTransform.scale.Y, originalTransform.scale.Z)
				uevrUtils.set_component_relative_location(attachment, originalTransform.location)
				uevrUtils.set_component_relative_rotation(attachment, originalTransform.rotation)
				uevrUtils.set_component_relative_scale(attachment, originalTransform.scale)
			end
			M.print("Reattaching to parent socket: " .. attachSocketName:to_string())
			attachment:K2_AttachTo(parent, attachSocketName, 0, false)
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
		executeGripAttachmentChanged("", attachmentData.gripHand, nil)
    end

    local parent = reattachToParent and attachmentData.parent or nil
    M.detach(attachmentData.attachment, parent, attachmentData.attachType, attachmentData.originalTransform, attachmentData.detachFromParentOnRelease, attachmentData.maintainWorldPositionOnDetachFromParent)
end

function M.detachAllAttachments()
    M.print("Detaching all attachments from all meshes")
    for meshName, meshData in pairs(meshAttachmentList) do
		M.print("  Detaching attachments from mesh: " .. meshName)
        if meshData.attachments ~= nil then
			M.print("   Found attachments, detaching...")
            for attachmentName, attachmentData in pairs(meshData.attachments) do
				M.print("    Detaching attachment: " .. attachmentName)
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
	invalidateAttachmentNameLookups()
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
-- Re-derive every attachment's grip-animation combo INDEX from the authoritative animation ID
-- in attachments_parameters.json.
--
-- WHY THIS MUST RUN AFTER THE PANEL IS CREATED: configui persists the combo's numeric index
-- (attachments_config_dev.json: "..._grip_animation": 28), but that index points into an array
-- built by pairs() over a hash table, whose iteration order is not stable across runs. A saved
-- index therefore decays into a different weapon's label next session (e.g. showing "Gvintar"
-- for a UDP whose stored animation is correctly "udp"). configui.create() -> configui.load()
-- applies that stale index, so the index must be recomputed from the ID afterwards.
syncGripAnimationSelections = function()
	if animationIDs == nil or animationLabels == nil then return end
	for i = 1, #attachmentOffsets do
		local parent = attachmentOffsets[i]["parent"]
		local child = attachmentOffsets[i]["child"]
		local name = parent .. "_" .. child
		configui.setSelections(widgetPrefix .. name .. "_grip_animation", animationLabels)
		local selectedID = attachmentOffsets[i]["animation"]
		for j = 1, #animationIDs do
			if selectedID == animationIDs[j] then
				--noCallbacks: we're only syncing the UI to existing settings, not changing them
				configui.setValue(widgetPrefix .. name .. "_grip_animation", j, true)
			end
		end
	end
end

function M.setAnimationIDs(animationIDList)
	--dont rewrite if nothing has changed
	if not deepEqual(animationIDList, currentAnimationIDList) then
		currentAnimationIDList = animationIDList
		if animationIDList ~= nil then
			animationLabels = getAnimationLabelsArray(animationIDList)
			animationIDs = getAnimationIDsArray(animationIDList)
			syncGripAnimationSelections()
		end
	end
	-- Always forward so accessory combos refresh even when attachment IDs are unchanged
	-- (e.g. widgets created after the first call, or early-return path).
	accessoriesConfig.setAnimationIDs(animationIDList)
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

local function updateLeftHandOffsets()
	local attachmentData = M.getCurrentGrippedAttachmentData(Handed.Left)
	if attachmentData ~= nil and uevrUtils.getValid(attachmentData.attachment) ~= nil then
		local loc, rot, scale = M.getAttachmentOffset(attachmentData.attachment)
		local id = M.getAttachmentIDFromAttachment(attachmentData.attachment)
		M.updateAttachmentTransform(loc, rot, scale, id, Handed.Left)
	end
end

configui.onUpdate("uevr_attachments_use_left_hand_offsets", function(value)
	configui.hideWidget("uevr_attachments_use_left_hand_offsets_group", not value)
	parameters["use_left_hand_offsets"] = true
	isParametersDirty = true
	updateLeftHandOffsets()
end)
configui.onCreate("uevr_attachments_use_left_hand_offsets", function(value)
	configui.hideWidget("uevr_attachments_use_left_hand_offsets_group", not value)
end)

configui.onUpdate("uevr_attachments_left_hand_location", function(value)
	parameters["leftHandOffsets"]["location"] = {value.X, value.Y, value.Z}
	isParametersDirty = true
	updateLeftHandOffsets()
end)

configui.onUpdate("uevr_attachments_left_hand_rotation", function(value)
	parameters["leftHandOffsets"]["rotation"] = {value.X, value.Y, value.Z}
	isParametersDirty = true
	updateLeftHandOffsets()
end)

configui.onUpdate("uevr_attachments_left_hand_scale", function(value)
	parameters["leftHandOffsets"]["scale"] = {value.X, value.Y, value.Z}
	isParametersDirty = true
	updateLeftHandOffsets()
end)

configui.onUpdate("uevr_attachments_left_hand_flip_x", function(value)
	parameters["leftHandOffsets"]["flip_x"] = value
	isParametersDirty = true
	updateLeftHandOffsets()
end)

configui.onUpdate("uevr_attachments_left_hand_flip_y", function(value)
	parameters["leftHandOffsets"]["flip_y"] = value
	isParametersDirty = true
	updateLeftHandOffsets()
end)

configui.onUpdate("uevr_attachments_left_hand_flip_z", function(value)
	parameters["leftHandOffsets"]["flip_z"] = value
	isParametersDirty = true
	updateLeftHandOffsets()
end)

local autoUpdateCallbackCreated = false
local gripUpdateCallback = nil
local failedAttachments = {}

local function runGripUpdate()
	if gripUpdateCallback == nil then return false end
	local rightAttachment, rightMesh, rightSocketName, leftAttachment, leftMesh, leftSocketName, attachOptionsRight, attachOptionsLeft = gripUpdateCallback()
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

	-- detach them first so switching left to right isnt affected
	if rightAttachment == nil then
		M.detachGripAttachments(Handed.Right)
	end
	if leftAttachment == nil then
		M.detachGripAttachments(Handed.Left)
	end

	--failedAttachments keeps a mesh that cant be attached from endlessly being retried
	if rightAttachment ~= nil and uevrUtils.getValid(rightAttachment) ~= nil and failedAttachments[rightAttachment:get_full_name()] ~= true then
		if failedAttachments[rightAttachment:get_full_name()] == nil then failedAttachments[rightAttachment:get_full_name()] = 0 end
		local rightSuccess = false
		if rightMesh == nil then
			rightSuccess = M.attachToRawController(rightAttachment, Handed.Right, attachOptionsRight)
		else
			rightSuccess = M.attachToMesh(rightAttachment, rightMesh, rightSocketName, Handed.Right, attachOptionsRight)
		end
		if not rightSuccess then
			print("########### Failed to attach right attachment")
			failedAttachments[rightAttachment:get_full_name()] = failedAttachments[rightAttachment:get_full_name()] + 1
		else
			failedAttachments[rightAttachment:get_full_name()] = 0
		end
	end

	if leftAttachment ~= nil and uevrUtils.getValid(leftAttachment) ~= nil and failedAttachments[leftAttachment:get_full_name()] ~= true then
		if failedAttachments[leftAttachment:get_full_name()] == nil then failedAttachments[leftAttachment:get_full_name()] = 0 end
		local leftSuccess = false
		if leftMesh == nil then
			leftSuccess = M.attachToRawController(leftAttachment, Handed.Left, attachOptionsLeft)
		else
			leftSuccess = M.attachToMesh(leftAttachment, leftMesh, leftSocketName, Handed.Left, attachOptionsLeft)
		end
		if not leftSuccess then
			failedAttachments[leftAttachment:get_full_name()] = failedAttachments[leftAttachment:get_full_name()] + 1
		else
			failedAttachments[leftAttachment:get_full_name()] = 0
		end
	end
	return true
end

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
function M.registerOnGripUpdateCallback(callback)
	gripUpdateCallback = callback
	if not autoUpdateCallbackCreated then
		autoUpdateCallbackCreated = true
		uevrUtils.setInterval(gripUpdateTimeout, function()
			runGripUpdate()
		end)
	end
end

function M.forceGripUpdate()
	return runGripUpdate()
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

-- ---------------------------------------------------------------------------
-- Virtual grip registration — for use when the hand is NOT physically
-- re-parented to the weapon (e.g. Stalker 2 where the hand attaches TO
-- the weapon socket, not the other way around).
--
-- Registers a weapon component as the current grip for `gripHand` WITHOUT
-- calling K2_AttachTo / DetachFromParent. This:
--   1. Adds the weapon to meshAttachmentList so updateSelectedColors() works
--   2. Calls addAttachmentToConfig() so an entry appears in the dev UI
--   3. Calls setActiveAnimation() to fire attachment_grip_animation_changed
--      → updateAnimationState() → animation.pose("grip_right_weapon_<id>")
--   4. Calls updateSelectedColors() to highlight the entry in the UI
-- ---------------------------------------------------------------------------
-- weaponChildNameHint: optional short mesh name (e.g. "SK_rhino00000") that overrides
-- getAttachmentNames() when the component's SkeletalMesh property is stale during
-- weapon-swap equip/unequip animations. Propagated to setActiveAnimation.
function M.registerGrippedAttachment(gripHand, attachment, weaponChildNameHint)
	if uevrUtils.getValid(attachment) == nil then
		M.print("registerGrippedAttachment: invalid attachment, skipping")
		return
	end

	-- CRITICAL: Stalker 2 REUSES a single WeaponInHandsMesh component across weapon
	-- switches, swapping only its SkeletalMesh property — the component's full name never
	-- changes. getAttachmentNames()/getAttachmentIDFromAttachment() cache by that full name,
	-- so without invalidating here they keep returning the FIRST weapon ever gripped (e.g.
	-- "CharacterMesh_SK_gauss" while actually holding the UDP), which silently breaks every
	-- per-weapon lookup downstream (grip animation, accessories, offsets).
	-- This is the one moment we know the SkeletalMesh may have changed, so clear the caches
	-- BEFORE addAttachmentToConfig/setActiveAnimation read them below.
	invalidateAttachmentNameLookups()

	local meshName = "VirtualGrip_" .. tostring(gripHand)
	local attachmentName = attachment:get_full_name()

	-- Clear previous virtual entry for this hand without calling DetachFromParent
	if meshAttachmentList[meshName] ~= nil and meshAttachmentList[meshName].attachments ~= nil then
		for aName, _ in pairs(meshAttachmentList[meshName].attachments) do
			meshAttachmentList[meshName].attachments[aName] = nil
		end
	end
	activeGripAnimations[gripHand] = false

	-- Build overrideID from the hint (bypasses stale SkeletalMesh read during transitions)
	local overrideID = nil
	if weaponChildNameHint then
		local attachmentParentName = uevrUtils.getShortName(attachment:get_outer())
		local attachmentNameNoNumberSuffix = string.gsub(attachmentParentName, "%d+$", "")
		if string.sub(attachmentNameNoNumberSuffix, -1, -1) ~= "_" then
			attachmentParentName = attachmentNameNoNumberSuffix
		else
			attachmentParentName = string.match(attachmentParentName, "^(.-)_[^_]*$") or attachmentParentName
		end
		overrideID = attachmentParentName .. "_" .. weaponChildNameHint
	end

	-- Write the new entry as VIRTUAL (M.detach will skip physical ops for this type)
	meshAttachmentList[meshName] = meshAttachmentList[meshName] or {mesh = nil, attachments = {}}
	meshAttachmentList[meshName].attachments[attachmentName] = {
		attachment   = attachment,
		socket       = nil,
		detachFromParentOnRelease = false,
		attachType   = M.AttachType.VIRTUAL,
		gripHand     = gripHand,
		overrideID   = overrideID,  -- stored for updateSelectedColors
	}

	-- Ensure this weapon has a config entry (adds to UI if not seen before).
	-- Pass the hint so addAttachmentToConfig uses the correct child name, not the stale SkeletalMesh.
	M.addAttachmentToConfig(attachment, weaponChildNameHint)

	-- Read the saved animation ID for this weapon and fire the pose callback.
	-- Pass the hint so setActiveAnimation matches by child name, not stale SkeletalMesh.
	M.setActiveAnimation(attachment, gripHand, weaponChildNameHint)

	-- Refresh colour highlights in the dev UI (blue = right, green = left)
	updateSelectedColors()
end

-- Unregisters the virtual grip for `gripHand` and resets the animation state.
function M.unregisterGrippedAttachment(gripHand)
	local meshName = "VirtualGrip_" .. tostring(gripHand)
	if meshAttachmentList[meshName] ~= nil and meshAttachmentList[meshName].attachments ~= nil then
		for aName, _ in pairs(meshAttachmentList[meshName].attachments) do
			meshAttachmentList[meshName].attachments[aName] = nil
		end
	end
	activeGripAnimations[gripHand] = false
	executeGripAnimationChange(false, gripHand)
	updateSelectedColors()
end

-- Thin public wrapper so external callers can force a colour-highlight refresh.
function M.refreshSelectedColors()
	updateSelectedColors()
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