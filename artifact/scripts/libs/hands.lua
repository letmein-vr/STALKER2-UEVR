local uevrUtils = require("libs/uevr_utils")
local controllers = require("libs/controllers")
local animation = require("libs/animation")
local attachments = require("libs/attachments")
local pawnModule = require("libs/pawn")

local M = {}

local autoHandleInput = true
local autoCreateHands = true
local autoCreateConfigName = nil
local autoCreateAnimationName = nil

local handComponents = {}
local handBaseTransforms = {}
local handDefinitions = {}
local handBoneList = {} --used for debugging
local offset={X=0, Y=0, Z=0, Pitch=0, Yaw=0, Roll=0}
local inputHandlerAnimID = {} --list of animID only used for the default input handler
local handsConfig = nil -- the configuration tool for creating hands in game
local holdingAttachment = {}
local fingerBlends = {} -- [hand] = running finger-curl blend (see M.blendFingerPose)

--externally controlled animations
local armsAnimationMeshes = {}
armsAnimationMeshes[Handed.Left] = {animating=false, mesh=nil, componentName=nil}
armsAnimationMeshes[Handed.Right] = {animating=false, mesh=nil, componentName=nil}
local defaultAnimationMesh = nil
-- Set to true to only update bones from wrist to root when copying pose from mesh. 
-- This is faster (less CPU intensive) but may not work for all skeletons. 
-- If the hand disappears when set to true then set it to false.
-- For example, Atomic Heart can be set to true but Robocop cannot.
--local optimizeAnimationFromMesh = false

local currentLogLevel = LogLevel.Error
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
	if logLevel == nil then logLevel = LogLevel.Debug end
	if logLevel <= currentLogLevel then
		uevrUtils.print("[hands] " .. text, logLevel)
	end
end

-- IK Arms mode (Stalker 2, 2026-10-04): scripts/hands.lua installs stalker2/ik_arms.lua here while the
-- IK rig is the active arms. The glove entry points below (attach / pose / animation state / hand
-- component) then hand off to it, so Entry.lua, physical_pickup and the reload modules drive the rig
-- without knowing which arms are active. nil = gloves, everything below runs unchanged.
local ikDelegate = nil
function M.setIKDelegate(delegate)
	ikDelegate = delegate
end
function M.isIKMode()
	return ikDelegate ~= nil
end

-- True when this hand's components are currently parented to `mesh` (compared by address,
-- since two Lua wrappers of the same UObject need not be equal).
local function isHandAttachedTo(hand, mesh)
	if uevrUtils.getValid(mesh) == nil then return false end
	local meshAddress = mesh:get_address()
	for _, components in pairs(handComponents) do
		local component = components[hand]
		if uevrUtils.getValid(component) ~= nil then
			local ok, parent = pcall(function() return component:GetAttachParent() end)
			return ok and parent ~= nil and parent:get_address() == meshAddress
		end
	end
	return false
end

local createInputHandler = doOnce(function()
	attachments.registerOnGripAnimationCallback(function(gripAnimation, gripHand)
		--M.print("Grip animation changed to " .. (gripAnimation and gripAnimation or "None") .. " for " .. (gripHand == Handed.Left and "Left" or "Right") .. " hand", LogLevel.Debug)
		-- print("Grip animation changed to ", gripAnimation, gripHand)
		M.updateAnimationState(gripHand)
	end)

	-- libs/accessories.lua (Stalker 2 accessories system) resolves proximity/montage-driven
	-- accessory activation and fires these events, but never physically moves anything itself
	-- for the common "off-hand grabs a socket on the weapon the other hand is holding" case
	-- (its own cacheAndReparentAttachmentToMotionController only reparents the WEAPON onto the
	-- hand when that hand is the weapon's own grip hand — it explicitly no-ops otherwise to
	-- avoid an IK hierarchy feedback loop). So without a listener here, an accessory can be
	-- fully configured and "active" and the hand still never snaps to its socket.
	uevrUtils.registerUEVRCallback("on_accessory_attach", function(handed, attachment, socketName, attachType, location, rotation)
		-- Glide onto the gun (e.g. two-handing a pistol) like the two-handed system does, but
		-- only when the hand is arriving from elsewhere. Re-attaches while the hand is already
		-- on this mesh (dev-panel preview tweaks fire every update, montage markers switch
		-- sockets) stay instant so they track exactly.
		if not isHandAttachedTo(handed, attachment) then
			M.attachHandToMeshBlended(handed, attachment, socketName, rotation, location, Config.supportHandBlendTime)
		else
			M.attachHandToMesh(handed, attachment, socketName, rotation, location)
		end
	end)

	-- accessories.lua fires this with the marker's "Grip Animation" value (e.g. "udp") on attach,
	-- and nil on release. Nothing else in the project consumed it, so the hand would snap to the
	-- socket but keep whatever finger pose it already had. updateAnimationState() derives the pose
	-- name as "grip_<hand>_weapon_<id>" (here: grip_left_weapon_udp) from holdingAttachment[hand],
	-- falling back to attachments.getCurrentGripAnimation(hand) when that slot is nil — so clearing
	-- it on release restores the hand's normal (free/weapon) pose.
	uevrUtils.registerUEVRCallback("on_accessory_animation", function(handed, gripAnimation)
		local animID = (type(gripAnimation) == "string" and gripAnimation ~= "") and gripAnimation or nil
		M.setHoldingAttachment(handed, animID)
		if animID ~= nil then
			-- Grabbing (e.g. two-handing a pistol): fingers curl into the grip over fingerCurlTime
			M.blendFingerPose(handed, Config.fingerCurlTime, function() M.updateAnimationState(handed) end)
		else
			M.updateAnimationState(handed)
		end
	end)

	uevrUtils.registerUEVRCallback("on_accessory_detach", function(handed)
		-- Must re-parent, not just reset the pose: attachHandToMesh() above K2_AttachTo'd this
		-- hand to the weapon mesh, and setInitialTransform() only rewrites bone data
		-- (animation.initializeBones) — it leaves the component parented to the weapon, so the
		-- hand stays visually stuck to the gun after leaving the activation radius.
		-- attachHandToController() is the real inverse: it re-attaches to the motion controller
		-- and internally restores the initial transform, base offsets and animation state.
		-- The blended version glides back to the controller (0 = instant snap).
		M.attachHandToControllerBlended(handed, Config.supportHandBlendTime)
	end)

	uevrUtils.registerOnInputGetStateCallback(function(retval, user_index, state)
		if autoHandleInput and M.exists() then
			local rightAttachment = holdingAttachment[Handed.Right]
			local leftAttachment = holdingAttachment[Handed.Left]

			-- Original crossover: physical attachments on the left-hand mesh register under
			-- Handed.Left, so rightAttachment reads from that slot.
			-- Extended fallback: virtual grips (Stalker 2 registerGrippedAttachment) store the
			-- animation ID under Handed.Right.  If holdingAttachment or the crossed slot is
			-- nil/false we read Handed.Right directly so the correct per-weapon extension
			-- (e.g. "rhino" -> right_grip_weapon_rhino) reaches handleInputTwoHanded.
			if rightAttachment == nil or rightAttachment == false then
				local crossFallback  = attachments.getCurrentGripAnimation(Handed.Left)
				local directFallback = attachments.getCurrentGripAnimation(Handed.Right)
				rightAttachment = crossFallback or directFallback or false
			end
			if leftAttachment == nil then
				leftAttachment = attachments.getCurrentGripAnimation(Handed.Right)
			end

			--M.handleInput(state, attachment, Handed.Right, nil, true)
			M.handleInputTwoHanded(state, rightAttachment, leftAttachment, nil, true)
		end
	end)
end, Once.EVER)

-- Registers the listeners above without creating glove components. They are normally registered when the
-- gloves are created; a session that starts in IK Arms mode never creates gloves, so the accessories.lua
-- events (pistol two-handing) had no listener until a switch to Hands and back. (Stalker 2, 2026-10-05.)
function M.ensureInputHandler()
	createInputHandler()
end


local function getValidVector(definition, id, default)
	if definition == nil or id == nil or definition[id] == nil then
		return uevrUtils.vector(default[1], default[2], default[3])
	end
	return uevrUtils.vector(definition[id][1], definition[id][2], definition[id][3])
end

local function getValidRotator(definition, id, default)
	if definition == nil or id == nil or definition[id] == nil then
		return uevrUtils.rotator(default[1], default[2], default[3])
	end
	return uevrUtils.rotator(definition[id][1], definition[id][2], definition[id][3])
end

local function getComponentName(componentName)
	local foundName = componentName
	if componentName == nil then --just get the first one
		for name, component in pairs(handComponents) do
			foundName = name
			break
		end
	end
	return foundName == nil and "" or foundName
end

local function getAnimIDSuffix(animID)
	local arr = uevrUtils.splitStr(animID, "_")
	return #arr > 0 and arr[#arr] or nil
end

function M.enableConfigurationTool()
	handsConfig = require('libs/config/hands_config')
end

function M.setAutoHandleInput(val)
	autoHandleInput = val
end

function M.setHoldingAttachment(hand, val)
	holdingAttachment[hand] = val
	if ikDelegate then ikDelegate.setHoldingAttachment(hand, val) end
end

function M.reset()
	if M.invalidatePoseCache then M.invalidatePoseCache() end
	handComponents = {}
	handBaseTransforms = {}
	handDefinitions = {}
	handBoneList = {}
	offset={X=0, Y=0, Z=0, Pitch=0, Yaw=0, Roll=0}
	inputHandlerAnimID = {}
	armsAnimationMeshes[Handed.Left] = {animating=false, mesh=nil, componentName=nil}
	armsAnimationMeshes[Handed.Right] = {animating=false, mesh=nil, componentName=nil}
	defaultAnimationMesh = nil
end

function M.exists()
	return M.getHandComponent(Handed.Left) ~= nil or M.getHandComponent(Handed.Right) ~= nil
end

-- Master switch for the glove auto-create (IK Arms mode turns it off). Sticky: while disabled,
-- resetAutoCreate / rebuildHands / the level-change re-arm leave it off, so the 1 s auto-create
-- timer can't respawn gloves behind the IK rig. (Stalker 2 IK port, 2026-10-04.)
local autoCreateSuppressed = false
function M.setAutoCreateHands(val)
	autoCreateSuppressed = (val == false)
	autoCreateHands = (val ~= false)
end
function M.isAutoCreateHandsEnabled()
	return not autoCreateSuppressed
end

function M.resetAutoCreate()
	autoCreateHands = not autoCreateSuppressed
	autoCreateConfigName = nil
	autoCreateAnimationName = nil
end

-- if using multiple components like hands and gloves then include componentName or which one is picked will be random
function M.getHandComponent(hand, componentName)
	if ikDelegate then return ikDelegate.getHandComponent(hand) end -- the rig mesh (one mesh, both hands)
	componentName = getComponentName(componentName)
	if handComponents[componentName] ~= nil then
		return handComponents[componentName][hand]
	end
end

function M.getHandComponents()
	return handComponents
end

-- The frame a glove hand component's origin sits in, for things attached to the hand at socket "None"
-- with offsets tuned against the glove (the weapon-mod mesh, the attachment simulator). Gloves: the hand
-- component itself. IK: a scene component on the rig's hand bone placed where the glove origin would be.
function M.getHandAttachParent(hand)
	if ikDelegate then return ikDelegate.getHandAttachParent(hand) end
	return M.getHandComponent(hand)
end

local fixEnabled = false
local currentProfile = nil
local function registerFOVFix(profile)
	currentProfile = profile

	if currentProfile ~= nil and fixEnabled == false then
		setInterval(1000, function()
			if currentProfile ~= nil then
				for name, components in pairs(handComponents) do
					local fovFixParam = currentProfile[name]["FOV"]
					--print(name, profileName, fovFixParam, components[0], components[1])
					if fovFixParam ~= nil and fovFixParam ~= "" then
						uevrUtils.fixMeshFOV(components[Handed.Left], fovFixParam, 0.0, true, true, false)
						uevrUtils.fixMeshFOV(components[Handed.Right], fovFixParam, 0.0, true, true, false)
					end
				end
			end
		end)
		fixEnabled = true
	end
end

function M.updateAnimationState(hand)
	if ikDelegate then return ikDelegate.updateAnimationState(hand) end
	if M.exists() then
		local attachment = holdingAttachment[hand]
		if attachment == nil then
			attachment = attachments.getCurrentGripAnimation(hand)
		end
		local isHoldingAttachment = false
		local attachmentExtension = ""
		-- print("In updateAnimationState", hand, attachment, type(attachment))
		if type(attachment) == "boolean" then
			isHoldingAttachment = attachment
		elseif type(attachment) == "string" and attachment ~= "attachment_none" then
			isHoldingAttachment = true
			if attachment ~= "" then
				attachmentExtension = "_" .. attachment
			end
		end
		-- print("isHoldingAttachment", isHoldingAttachment)
		if isHoldingAttachment then
			for id, target in pairs(inputHandlerAnimID) do
				local handStr = hand == Handed.Left and "left" or "right"
				-- Reset any running bare-hand lerps so they don't override the weapon pose.
				-- If right_grip was in "on" state (user squeezed before equipping), its lerp
				-- would continue to run and override the weapon grip bones for up to 100ms.
				animation.updateAnimation(id, handStr.."_grip", false, {duration=0.1})
				animation.updateAnimation(id, handStr.."_trigger", false, {duration=0.1})
				-- Apply the weapon-specific static pose as the baseline
				animation.pose(handStr .. "_" .. target, "grip_" .. handStr .. "_weapon" .. attachmentExtension)
			end
		else
			for id, target in pairs(inputHandlerAnimID) do
				local handStr = hand == Handed.Left and "left" or "right"
				animation.pose(handStr .. "_" .. target, "open_" .. handStr)
			end
		end
	end
end

function M.createFromConfig(configuration, profileName, animationName)
	if type(configuration) == "string" then
		configuration = json.load_file(configuration .. ".json")
	end
	if configuration ~= nil and configuration["profiles"] ~= nil then
		local profile = configuration["profiles"][profileName]
		if profile ~= nil then
			local components = {}
			for key, mesh in pairs(profile) do
				--key = "Arms"
				local meshPropertyName = mesh["Mesh"]
				if meshPropertyName ~= "" then
					local component = uevrUtils.getObjectFromDescriptor(meshPropertyName) -- "Pawn.Mesh(Arm).Glove")
					if component ~= nil then
						components[key] = component
					end
				end
			end

			local animations = nil
			if configuration["animations"] ~= nil and animationName ~= nil and animationName ~= "" then
				animations = configuration["animations"][animationName]
				-- animDef = {}
				-- local poses = {}
				-- poses["open_left"] = { {"left_grip","off"}, {"left_trigger","off"}, {"left_thumb","off"} }
				-- poses["open_right"] = { {"right_grip","off"}, {"right_trigger","off"}, {"right_thumb","off"} }
				-- poses["grip_right_weapon"] = { {"right_grip_weapon","on"}, {"right_trigger_weapon","off"} }
				-- poses["grip_left_weapon"] = { {"left_grip_weapon","on"}, {"left_trigger_weapon","off"} }

				-- animDef.positions = animations
				-- animDef.poses = poses
			end

			attachments.setAnimationIDs(configuration["attachments"])

			M.create(components, profile, animations)

			--going to need to call fixMeshFOV on lazy poll
			for name, components in pairs(handComponents) do
				--print(name, profileName, components[0], components[1])
				local fovFixParam = configuration["profiles"][profileName][name]["FOV"]
				if fovFixParam ~= nil and fovFixParam ~= "" then
					uevrUtils.fixMeshFOV(components[Handed.Left], fovFixParam, 0.0, true, true, false)
					uevrUtils.fixMeshFOV(components[Handed.Right], fovFixParam, 0.0, true, true, false)
					registerFOVFix(profile)
				end
			end

		end
	else
		M.print("Could not create from config because configuration is invalid")
		--json.dump_file("debug.json", configuration, 4)
	end
end

--skeletalMeshComponent can either be a single component or a table of components
function M.create(skeletalMeshComponent, definition, handAnimations)
	if M.invalidatePoseCache then M.invalidatePoseCache() end
	if definition ~= nil then
		for name, skeletalMeshDefinition in pairs(definition) do
			if skeletalMeshDefinition["Offset"] ~= nil then
				offset = skeletalMeshDefinition["Offset"]
			end
			M.print("Creating hand component: " .. name )
			local component = nil
			if type(skeletalMeshComponent) == "table" then
				component = skeletalMeshComponent[name]
			else
				component = skeletalMeshComponent
			end
			if uevrUtils.validate_object(component) ~= nil then
				-- FIX (2026-09-07): used to unconditionally wipe to {} here, discarding any
				-- already-valid component reference without destroying it (a leak) every time
				-- this ran. That mattered once createComponent() could return nil for a hand
				-- whose controller isn't ready yet (see its own comment) - tryAutoCreateHands()'s
				-- 1s retry would otherwise call back in here every second, leaking the OTHER
				-- hand's already-successfully-created PMC on every single retry tick while
				-- waiting for the slow one. Now: keep whichever hand already has a valid
				-- component, only (re)create the one that's actually missing. Safe for this
				-- project specifically because the hands-wizard config tool (which intentionally
				-- wants a full destroy+recreate on every UI edit) is never enabled here - see
				-- Entry.lua, no call to hands.enableConfigurationTool(). If that ever changes,
				-- this needs an explicit M.destroyHands() before re-createFromConfig instead.
				if handComponents[name] == nil then handComponents[name] = {} end
				for index = Handed.Left , Handed.Right do
					if handComponents[name][index] == nil or uevrUtils.validate_object(handComponents[name][index]) == nil then
						handComponents[name][index] = M.createComponent(component, name, index, skeletalMeshDefinition[index==Handed.Left and "Left" or "Right"])
					end
					if handComponents[name][index] ~= nil then
						M.print("Created " .. name .. " component: " .. (index==Handed.Left and "Left" or "Right"), LogLevel.Info )
						if skeletalMeshDefinition["FOV"] ~= nil and skeletalMeshDefinition["FOV"] ~= "" then
							uevrUtils.fixMeshFOV(handComponents[name][index], skeletalMeshDefinition["FOV"], 0.0, true, true, false)
						end

						local initialTransform = skeletalMeshDefinition["InitialTransform"]
						if initialTransform ~= nil then
							animation.initializeBones(handComponents[name][index], initialTransform[index==Handed.Left and "left_hand" or "right_hand"])
						end

						local animID = skeletalMeshDefinition[index==Handed.Left and "Left" or "Right"]["AnimationID"]
						if animID ~= nil then
							local suffix = getAnimIDSuffix(animID)
							if suffix ~= nil then inputHandlerAnimID[animID] = suffix end
							animation.add(animID, handComponents[name][index], handAnimations)
							animation.initialize(animID, handComponents[name][index])
						end
					end
				end
				if autoHandleInput == true then
					createInputHandler()
					M.updateAnimationState(Handed.Left)
					M.updateAnimationState(Handed.Right)
				end
			else
				M.print("Call to create " .. name .. " failed, invalid skeletalMeshComponent", LogLevel.Info )
			end
		end

		handDefinitions = definition
	else
		M.print("Call to create failed, invalid definiton", LogLevel.Warning )
	end
end

function M.createComponent(skeletalMeshComponent, name, hand, definition)
	local component = nil
	if uevrUtils.validate_object(skeletalMeshComponent) ~= nil then
		--not using an existing actor as owner. Mesh affects the hands opacity so its not appropriate
		component = animation.createPoseableComponent(skeletalMeshComponent, nil, definition ~= nil and definition["UseDefaultPose"] == true)
		if component ~= nil then
			--fixes flickering but > 1 causes a perfomance hit with dynamic shadows according to unreal doc
			--a better way to do this should be found
			component.BoundsScale = 16.0
			component.bCastDynamicShadow = Config.vrShadowsEnabled
			component:SetCastShadow(Config.vrShadowsEnabled)

			-- FIX (2026-09-07): attachComponentToController() silently returns false (just a
			-- print) if the target MotionControllerComponent doesn't exist yet - a real race
			-- right after a script reset/reload, since controllers.lua's own auto-creation
			-- monitor and this module's tryAutoCreateHands() run on independent, uncoordinated
			-- 1s intervals. Previously the freshly-created PMC was kept and stored into
			-- handComponents[name][hand] regardless, so it sat orphaned and unattached, frozen
			-- at its spawn transform ("stuck hand"). Worse, M.exists() is an OR across both
			-- hands, so once the OTHER hand's creation succeeded, M.exists() reported true and
			-- tryAutoCreateHands()'s `not M.exists()` guard never retried this hand again -
			-- permanently stuck until a manual M.rebuildHands() or full game restart. Discard
			-- and return nil instead, so handComponents[name][hand] stays nil and the existing
			-- 1s retry keeps trying until the controller genuinely exists.
			if not controllers.attachComponentToController(hand, component) then
				M.print("Controller " .. hand .. " not ready yet - discarding unattached hand component, will retry.", LogLevel.Warning)
				uevrUtils.detachAndDestroyComponent(component, true)
				return nil
			end
			local baseRotation = skeletalMeshComponent.RelativeRotation
			local finalRot = {Pitch=baseRotation.Pitch+offset.Pitch, Yaw=baseRotation.Yaw+offset.Yaw,Roll=baseRotation.Roll+offset.Roll}
			uevrUtils.set_component_relative_transform(component, offset, finalRot)

			if handBaseTransforms[name] == nil then handBaseTransforms[name] = {} end
			handBaseTransforms[name][hand] = { loc={X=offset.X, Y=offset.Y, Z=offset.Z}, rot=finalRot }

			if definition ~= nil then
				local jointName = definition["Name"]
				if jointName ~= nil and jointName ~= "" then
					local location = getValidVector(definition, "Location", {0,0,0})
					local rotation = getValidRotator(definition, "Rotation", {0,0,0})
					local scale = getValidVector(definition, "Scale", {1,1,1})
					local taperVector = getValidVector(definition, "TaperOffset", {0,0,0})
                    local taperOffset = uevrUtils.vector(taperVector.X + Config.handTaperValue, taperVector.Y, taperVector.Z)
					animation.transformBoneToRoot(component, jointName, location, rotation, scale, taperOffset)
				else
					M.print("Could not initialize bone in createComponent() because joint name is invalid" )
				end
			end
		end
	else
		M.print("SkeletalMesh component is nil in createComponent()" )
	end
	return component
end

function M.setInitialTransform(hand, componentName)
	if ikDelegate then
		fingerBlends[hand] = nil
		M.invalidatePoseCache(hand)
		return ikDelegate.setInitialTransform(hand)
	end
	componentName = getComponentName(componentName)
	if componentName == nil or componentName == "" or handDefinitions[componentName] == nil then
		M.print("Could not update set initial transform because component is undefined")
	else
		local initialTransform = handDefinitions[componentName]["InitialTransform"]
		if initialTransform ~= nil then
			local component = M.getHandComponent(hand, componentName)
			local handStr = hand == Handed.Left and "left_hand" or "right_hand"
			fingerBlends[hand] = nil -- a reset wins over a running finger curl
			M.invalidatePoseCache(hand, componentName)
			animation.initializeBones(component, initialTransform[handStr])
		end
	end
end

-- Per hand+component: the pose table last applied and when. Several Entry.lua
-- paths call setHandPose with the SAME pose table every frame "to ensure
-- persistence"; each call is a full per-bone C++ walk (initializeBones), which
-- under the current UEVR build costs ~60ms per hand and was halving the frame
-- rate during reloads. Identical-pose re-applies are throttled instead.
local lastAppliedPose = {}
local lastAppliedPoseTime = {}
local SAME_POSE_REAPPLY_INTERVAL = 0.25 -- seconds

local function poseKey(hand, componentName)
	return tostring(hand) .. ":" .. tostring(componentName)
end

function M.invalidatePoseCache(hand, componentName)
	if hand == nil then
		lastAppliedPose = {}
		lastAppliedPoseTime = {}
	else
		local key = poseKey(hand, getComponentName(componentName))
		lastAppliedPose[key] = nil
		lastAppliedPoseTime[key] = nil
	end
end

function M.setHandPose(hand, pose, componentName)
    componentName = getComponentName(componentName)
    local component = M.getHandComponent(hand, componentName)
    if component == nil then return end

    -- A finger curl towards this same pose owns the bones until it lands; the per-frame
    -- "persistence" re-applies would otherwise snap it to the end. A different pose wins.
    local fingerBlend = fingerBlends[hand]
    if fingerBlend ~= nil then
        if fingerBlend.pose ~= nil and fingerBlend.pose == pose then return end
        fingerBlends[hand] = nil
    end

    local key = poseKey(hand, componentName)
    local now = os.clock()
    if lastAppliedPose[key] == pose and (now - (lastAppliedPoseTime[key] or 0)) < SAME_POSE_REAPPLY_INTERVAL then
        return
    end
    lastAppliedPose[key] = pose
    lastAppliedPoseTime[key] = now

    local initialTransform = {}
    for boneName, rotation in pairs(pose) do
        initialTransform[boneName] = { ["rotation"] = rotation }
    end

    animation.initializeBones(component, initialTransform)
end

-- function M.enableOptimizedAnimations(val)
-- 	optimizeAnimationFromMesh = val
-- end

--if, in debug mode, the skeleton is not pointed forward when the wrist is pointed forward then make adjustments with this function
function  M.setOffset(newOffset)
	offset = newOffset
end

--only for debugging
function M.updateOffset(skeletalMeshComponent, newOffset)
	if skeletalMeshComponent ~= nil then
		local baseRotation = skeletalMeshComponent.RelativeRotation
		local component = handComponents["Arms"][Handed.Right]
		uevrUtils.set_component_relative_transform(component, newOffset, {Pitch=baseRotation.Pitch+newOffset.Pitch, Yaw=baseRotation.Yaw+newOffset.Yaw,Roll=baseRotation.Roll+newOffset.Roll})
	end
end

function M.addRealism()

end

function M.setAnimationMesh(mesh)
	defaultAnimationMesh = mesh
end

function M.updateAnimationFromMesh(hand, mesh, componentName)
	--print("Updating animation from mesh", hand, mesh:get_full_name(), componentName)
	if mesh ~= nil then
		componentName = getComponentName(componentName)
		if componentName == nil or componentName == "" or handDefinitions[componentName] == nil then
			M.print("Could not update Animation From Mesh because component is undefined")
		else
			local component = M.getHandComponent(hand, componentName)
			local handStr = hand == Handed.Left and "Left" or "Right"
			local definition = handDefinitions[componentName][handStr]
			if definition ~= nil then
				local jointName = definition["Name"]
				if jointName ~= nil and jointName ~= "" then
					local success, response = pcall(function()		
						component:CopyPoseFromSkeletalComponent(mesh)
						--component:SetLeaderPoseComponent(mesh, true)
						local location = getValidVector(definition, "Location", {0,0,0})
						local rotation = getValidRotator(definition, "Rotation", {0,0,0})
						local scale = getValidVector(definition, "Scale", {1,1,1})
						--When an animation is applied, every bone in the entire skeleton is moved, so we need to reapply the transform from wrist to root
						local taperVector = getValidVector(definition, "TaperOffset", {0,0,0})
                        local taperOffset = uevrUtils.vector(taperVector.X + Config.handTaperValue, taperVector.Y, taperVector.Z)
						local optimizeAnimationFromMesh = handDefinitions[componentName]["OptimizeAnimations"] ~= false
						local optimizationRootBone = definition["OptimizeAnimationsRootBone"]
						animation.transformBoneToRoot(component, jointName, location, rotation, scale, taperOffset, optimizeAnimationFromMesh, optimizationRootBone)
						--component:SetLeaderPoseComponent(nil, false)
					end)
					if success == false then
						M.print("[hands] " .. response, LogLevel.Error)
					end
				end
			end
		end
	end
end

function M.setHandsAreAnimatingFromMesh(isLeftAnimating, isRightAnimating, leftMesh, rightMesh, componentName)
	if isLeftAnimating ~= nil then
		if isLeftAnimating == true and armsAnimationMeshes[Handed.Left].animating ~= true then
			armsAnimationMeshes[Handed.Left].mesh = leftMesh and leftMesh or (uevrUtils.getValid(defaultAnimationMesh) ~= nil and defaultAnimationMesh or pawnModule.getArmsAnimationMesh())
			armsAnimationMeshes[Handed.Left].componentName = componentName
		elseif isLeftAnimating == false and armsAnimationMeshes[Handed.Left].animating == true then
			-- Don't call setInitialTransform here - let Entry.lua's pose logic handle restoration
			armsAnimationMeshes[Handed.Left].mesh = nil
			armsAnimationMeshes[Handed.Left].componentName = nil
		end
		armsAnimationMeshes[Handed.Left].animating = isLeftAnimating
	end
	
	if isRightAnimating ~= nil then
		if isRightAnimating == true and armsAnimationMeshes[Handed.Right].animating ~= true then
			armsAnimationMeshes[Handed.Right].mesh = rightMesh and rightMesh or (uevrUtils.getValid(defaultAnimationMesh) ~= nil and defaultAnimationMesh or pawnModule.getArmsAnimationMesh())
			armsAnimationMeshes[Handed.Right].componentName = componentName
		elseif isRightAnimating == false and armsAnimationMeshes[Handed.Right].animating == true then
			-- Don't call setInitialTransform here - let Entry.lua's pose logic handle restoration
			armsAnimationMeshes[Handed.Right].mesh = nil
			armsAnimationMeshes[Handed.Right].componentName = nil
		end
		armsAnimationMeshes[Handed.Right].animating = isRightAnimating
	end
end


--set overrideTrigger to true if the default triggers have already been swapped (ie a plugin or code aleady makes the game do right trigger actions when the left trigger is pulled)
function M.handleInput(state, attachment, hand, overrideTrigger, allowAutoHandle)
	if allowAutoHandle ~= true then
		autoHandleInput = false --if something else is calling this then dont auto handle input
	end

	local isHoldingAttachment = false
	local attachmentExtension = ""
	if type(attachment) == "boolean" then
		isHoldingAttachment = attachment
	elseif type(attachment) == "string" and attachment ~= "" then
		isHoldingAttachment = true
		attachmentExtension = "_" .. attachment
	end

	if hand == nil then hand = Handed.Right end
	if overrideTrigger == nil then overrideTrigger = false end
	local isRightHanded = hand == Handed.Right
	local weaponHandStr = isRightHanded and "right" or "left"
	local offHandStr = isRightHanded and "left" or "right"
	local animDuration = 0.1
	for id, target in pairs(inputHandlerAnimID) do
		local offhandTriggerValue = (isRightHanded or overrideTrigger) and state.Gamepad.bLeftTrigger or state.Gamepad.bRightTrigger
		animation.updateAnimation(offHandStr.."_"..target, offHandStr.."_trigger", offhandTriggerValue > 100, {duration=animDuration})

		animation.updateAnimation(offHandStr.."_"..target, offHandStr.."_grip", uevrUtils.isButtonPressed(state, isRightHanded and XINPUT_GAMEPAD_LEFT_SHOULDER or XINPUT_GAMEPAD_RIGHT_SHOULDER), {duration=animDuration})

		local offhandController = uevr.params.vr.get_left_joystick_source()
		if not isRightHanded then offhandController = uevr.params.vr.get_right_joystick_source() end
		local offhandRest = uevr.params.vr.get_action_handle(isRightHanded and "/actions/default/in/ThumbrestTouchLeft" or "/actions/default/in/ThumbrestTouchRight")
		if not M.isThumbLerpSuppressed(isRightHanded and Handed.Left or Handed.Right) then
			animation.updateAnimation(offHandStr.."_"..target, offHandStr.."_thumb", uevr.params.vr.is_action_active(offhandRest, offhandController), {duration=animDuration})
		end

		if not isHoldingAttachment then
			local weaponHandTriggerValue = (isRightHanded or overrideTrigger) and state.Gamepad.bRightTrigger or state.Gamepad.bLeftTrigger
			animation.updateAnimation(weaponHandStr.."_"..target, weaponHandStr.."_trigger", weaponHandTriggerValue > 100, {duration=animDuration})

			animation.updateAnimation(weaponHandStr.."_"..target, weaponHandStr.."_grip", uevrUtils.isButtonPressed(state, isRightHanded and XINPUT_GAMEPAD_RIGHT_SHOULDER or XINPUT_GAMEPAD_LEFT_SHOULDER), {duration=animDuration})

			local weaponhandController = uevr.params.vr.get_right_joystick_source()
			if not isRightHanded then weaponhandController = uevr.params.vr.get_left_joystick_source() end
			local weaponhandRest = uevr.params.vr.get_action_handle(isRightHanded and "/actions/default/in/ThumbrestTouchRight" or "/actions/default/in/ThumbrestTouchLeft")
			if not M.isThumbLerpSuppressed(hand) then
				animation.updateAnimation(weaponHandStr.."_"..target, weaponHandStr.."_thumb", uevr.params.vr.is_action_active(weaponhandRest, weaponhandController), {duration=animDuration})
			end
		else
			local weaponHandTriggerValue = (isRightHanded or overrideTrigger) and state.Gamepad.bRightTrigger or state.Gamepad.bLeftTrigger
			animation.updateAnimation(weaponHandStr.."_"..target, weaponHandStr.."_trigger_weapon" .. attachmentExtension, weaponHandTriggerValue > 100, {duration=animDuration})
			-- Same fix as handleInputTwoHanded: unconditional updateAnimation so the lerp fires
			-- once on press and runs to completion, rather than restarting every ~11ms poll.
			animation.updateAnimation(weaponHandStr.."_"..target, weaponHandStr.."_grip_weapon" .. attachmentExtension, uevrUtils.isButtonPressed(state, isRightHanded and XINPUT_GAMEPAD_RIGHT_SHOULDER or XINPUT_GAMEPAD_LEFT_SHOULDER), {duration=animDuration})
		end
	end
end

-- Thumb-lerp suppression (2026-09-11). Entry.lua owns the support hand with its own raw
-- bone tables (two-handing capture, reloadHandPose, ptmMagGripPose, detector pose) applied
-- via setHandPose at most every 250ms. The edge-triggered grip/trigger/thumb lerps below keep
-- running meanwhile; grip is held and trigger untouched during those actions so they never
-- fire, but the thumbrest touch flips constantly and every flip snapped thumb_01..03 to the
-- JSON left_thumb rest values - the "thumb looks wrong while two-handing / grabbing a mag"
-- bug. While a hand is flagged here its _thumb updateAnimation is skipped; on release the
-- next updateAnimation resyncs against the real touch state.
local thumbLerpSuppressed = {}

function M.setThumbLerpSuppressed(hand, suppressed)
	thumbLerpSuppressed[hand] = suppressed == true
	if ikDelegate then ikDelegate.setThumbLerpSuppressed(hand, suppressed == true) end
end

function M.isThumbLerpSuppressed(hand)
	return thumbLerpSuppressed[hand] == true
end

-- Per-hand lock for ALL the input-driven grip/trigger/thumb lerps (the glove twin of
-- hands_animation.setInputLocked, which the IK delegate forwards to). The input handler reads the raw
-- pad BEFORE game-side suppression, so a script that owns a hand's pose every frame (Stalker 2 rack:
-- left grip on the slide -> mag-grip pose) would otherwise fight the 0.1 s grip curl the press starts.
-- The hand keeps whatever pose is applied; updateAnimationState / attachHandToController resync it.
local inputLocked = {}

function M.setInputLocked(hand, locked)
	inputLocked[hand] = locked == true or nil
	if ikDelegate then ikDelegate.setInputLocked(hand, locked == true) end
end

function M.isInputLocked(hand)
	return inputLocked[hand] == true
end

-- PERF helpers for handleInputTwoHanded (see comments inside). Action handles are cached only once
-- they resolve to something non-nil/non-zero, so an early call before the VR runtime is ready
-- cannot pin an invalid handle.
local twoHandedTargetsSeen = {}
local thumbrestHandleRight = nil
local thumbrestHandleLeft = nil
local function getThumbrestHandle(isRight)
	if isRight then
		if thumbrestHandleRight == nil then
			local h = uevr.params.vr.get_action_handle("/actions/default/in/ThumbrestTouchRight")
			if h ~= nil and h ~= 0 then thumbrestHandleRight = h end
			return h
		end
		return thumbrestHandleRight
	else
		if thumbrestHandleLeft == nil then
			local h = uevr.params.vr.get_action_handle("/actions/default/in/ThumbrestTouchLeft")
			if h ~= nil and h ~= 0 then thumbrestHandleLeft = h end
			return h
		end
		return thumbrestHandleLeft
	end
end

function M.handleInputTwoHanded(state, rightAttachment, leftAttachment, overrideTrigger, allowAutoHandle)
	if allowAutoHandle ~= true then
		autoHandleInput = false --if something else is calling this then dont auto handle input
	end

	if overrideTrigger == nil then overrideTrigger = false end
	local animDuration = 0.1
	-- PERF (2026-09-08): inputHandlerAnimID maps every hand's animID (e.g. left_arms, right_arms)
	-- to the same suffix ("arms"), and the inner loop below already covers BOTH hands for a given
	-- suffix. Iterating the outer map unfiltered therefore ran each hand's work once per entry
	-- (2x per xinput poll). Dedupe by distinct suffix; the body is idempotent so the result is
	-- identical. The two thumbrest action handles are also resolved once instead of per poll.
	for k in pairs(twoHandedTargetsSeen) do twoHandedTargetsSeen[k] = nil end
	for id, target in pairs(inputHandlerAnimID) do
	  if not twoHandedTargetsSeen[target] then
		twoHandedTargetsSeen[target] = true
		for hand = Handed.Left, Handed.Right do
		  if not inputLocked[hand] then
			local handStr = hand == Handed.Right and "right" or "left"
			local isHoldingAttachment = false
			local attachmentExtension = ""
			local attachment = hand == Handed.Right and rightAttachment or leftAttachment
			if type(attachment) == "boolean" then
				isHoldingAttachment = attachment
			elseif type(attachment) == "string" and attachment ~= "" then
				isHoldingAttachment = true
				attachmentExtension = "_" .. attachment
			end
			if not isHoldingAttachment then
				local weaponHandTriggerValue = (hand == Handed.Right or overrideTrigger) and state.Gamepad.bRightTrigger or state.Gamepad.bLeftTrigger
				animation.updateAnimation(handStr.."_"..target, handStr.."_trigger", weaponHandTriggerValue > 100, {duration=animDuration})

				animation.updateAnimation(handStr.."_"..target, handStr.."_grip", uevrUtils.isButtonPressed(state, hand == Handed.Right and XINPUT_GAMEPAD_RIGHT_SHOULDER or XINPUT_GAMEPAD_LEFT_SHOULDER), {duration=animDuration})

				local weaponhandController = uevr.params.vr.get_right_joystick_source()
				if not (hand == Handed.Right) then weaponhandController = uevr.params.vr.get_left_joystick_source() end
				local weaponhandRest = getThumbrestHandle(hand == Handed.Right)
				if not M.isThumbLerpSuppressed(hand) then
					animation.updateAnimation(handStr.."_"..target, handStr.."_thumb", uevr.params.vr.is_action_active(weaponhandRest, weaponhandController), {duration=animDuration})
				end
			else
				local weaponHandTriggerValue = (hand == Handed.Right or overrideTrigger) and state.Gamepad.bRightTrigger or state.Gamepad.bLeftTrigger
				animation.updateAnimation(handStr.."_"..target, handStr.."_trigger_weapon" .. attachmentExtension, weaponHandTriggerValue > 100, {duration=animDuration})
				-- Apply grip_weapon animation unconditionally (same pattern as bare-hand grip).
				-- Previously used resetAnimation+conditional which restarted the lerp every xinput
				-- poll (~11ms), keeping it permanently at alpha=0 (the "off" position) while the
				-- button was held.  Now the lerp fires once on press, runs to completion, and
				-- reverses cleanly on release.
				animation.updateAnimation(handStr.."_"..target, handStr.."_grip_weapon" .. attachmentExtension, uevrUtils.isButtonPressed(state, hand == Handed.Right and XINPUT_GAMEPAD_RIGHT_SHOULDER or XINPUT_GAMEPAD_LEFT_SHOULDER), {duration=animDuration})
			end
		  end
		end
	  end
	end
end

function M.hideHands(val)
	if val == nil then return end
	for name, components in pairs(handComponents) do
		if uevrUtils.getValid(components[0]) ~= nil and components[0].SetVisibility ~= nil then
			M.print((val and "Hiding " or "Showing ") .. components[0]:get_full_name() .. " hand components", LogLevel.Debug)
			components[0]:SetVisibility(not val, true)
		end
		if uevrUtils.getValid(components[1]) ~= nil and components[1].SetVisibility ~= nil then
			components[1]:SetVisibility(not val, true)
		end
	end
end

local function executeIsHiddenCallback(...)
	return uevrUtils.executeUEVRCallbacksWithPriorityBooleanResult("is_hands_hidden", table.unpack({...}))
end
function M.registerIsHiddenCallback(func)
	uevrUtils.registerUEVRCallback("is_hands_hidden", func)
end

local function executeIsAnimatingFromMeshCallback(...)
	return uevrUtils.executeUEVRCallbacksWithPriorityBooleanResult("is_hands_animating_from_mesh", table.unpack({...}))
end
function M.registerIsAnimatingFromMeshCallback(func)
	uevrUtils.registerUEVRCallback("is_hands_animating_from_mesh", func)
end

function M.destroyHands()
	--since we didnt use an existing actor as parent in createComponent(), destroy the owner actor too
	for name, components in pairs(handComponents) do
		M.print("Destroying " .. name .. " hand components", LogLevel.Debug)
		uevrUtils.detachAndDestroyComponent(components[0], true)
		uevrUtils.detachAndDestroyComponent(components[1], true)
	end
	M.reset()
end

-- Destroys current poseable hand components and re-arms the auto-create system so
-- they are rebuilt from the current pawn.Mesh on the next tryAutoCreateHands() tick.
-- Call this whenever the pawn SkeletalMesh changes (e.g. suit swap).
function M.rebuildHands()
	M.print("rebuildHands() called — destroying existing hands and re-arming auto-create", LogLevel.Info)
	M.destroyHands()
	-- Reset autoCreate state so tryAutoCreateHands() reads fresh from hands_parameters.json
	-- (stays off while IK Arms mode has suppressed glove auto-create)
	autoCreateHands = not autoCreateSuppressed
	autoCreateConfigName = nil
	autoCreateAnimationName = nil
	-- tryAutoCreateHands() runs on a 1s interval and will recreate on the next tick
end

local visualCallbackExists = false
function M.createSkeletalVisualization(hand, scale, componentName)
	animation.destroySkeletalVisualization()
	if M.exists() then
		if hand == nil then hand = Handed.Right end
		if scale == nil then scale = 0.003 end
		animation.createSkeletalVisualization(M.getHandComponent(hand, componentName), scale)
		if not visualCallbackExists then
			uevrUtils.registerPostEngineTickCallback(function()
				if M.exists() then
					animation.updateSkeletalVisualization(M.getHandComponent(hand, componentName))
				end
			end)
		end
		visualCallbackExists = true
	end
end

local adjustMode = 1  -- 1-hand rotation  2-hand location  3-finger angles
local adjustModeLabels = {"Hand Rotation", "Hand Location", "Finger Angles"}
local currentHand = 1 -- 0-left  1-right
local currentHandLabels = {"Left", "Right"}
local currentIndex = 1	--1-knuckle 
local currentFinger = 1 -- 1-10
local currentFingerLabels = {"Left Thumb", "Left Index", "Left Middle", "Left Ring", "Left Pinky", "Right Thumb", "Right Index", "Right Middle", "Right Ring", "Right Pinky"}
local positionDelta = 0.2
local rotationDelta = 45
local jointAngleDelta = 5

function M.enableHandAdjustments(boneList, componentName)
	handBoneList = boneList
	local logLevel = LogLevel.Critical
	M.print("Adjust Mode " .. adjustModeLabels[adjustMode], logLevel)
	if adjustMode == 3 then
		M.print("Current finger:" .. currentFingerLabels[currentFinger] .. " finger joint:" .. currentIndex, logLevel)
	else
		M.print("Current hand: " .. currentHandLabels[currentHand+1], logLevel)
	end

	register_key_bind("NumPadFive", function()
		M.print("Num5 pressed")
		adjustMode = (adjustMode % 3) + 1
		M.print("Adjust Mode " .. adjustModeLabels[adjustMode], logLevel)
		if adjustMode == 3 then
			M.print("Current finger:" .. currentFingerLabels[currentFinger] .. " finger joint:" .. currentIndex, logLevel)
		else
			M.print("Current hand: " .. currentHandLabels[currentHand+1], logLevel)
		end
	end)

	register_key_bind("NumPadNine", function()
		M.print("Num9 pressed")
		currentIndex = (currentIndex % 3) + 1
		M.print("Current finger:" .. currentFingerLabels[currentFinger] .. " finger joint:" .. currentIndex, logLevel)
	end)

	register_key_bind("NumPadSeven", function()
		M.print("Num7 pressed")
		if adjustMode == 3 then
			currentFinger = (currentFinger % 10) + 1
			M.print("Current finger:" .. currentFingerLabels[currentFinger] .. " finger joint:" .. currentIndex, logLevel)
		else
			currentHand = (currentHand + 1) % 2
			M.print("Current hand: " .. currentHandLabels[currentHand+1], logLevel)
		end
	end)

	register_key_bind("NumPadEight", function()
		M.print("Num8 pressed")
		if adjustMode == 1 then
			M.adjustRotation(currentHand, 1, rotationDelta, componentName)
		elseif adjustMode == 2 then
			M.adjustLocation(currentHand, 1, positionDelta, componentName)
		elseif adjustMode == 3 then
			M.setFingerAngles(currentFinger, currentIndex, 0, jointAngleDelta, componentName)
		end
	end)
	register_key_bind("NumPadTwo", function()
		M.print("Num2 pressed")
		if adjustMode == 1 then
			M.adjustRotation(currentHand, 1, -rotationDelta, componentName)
		elseif adjustMode == 2 then
			M.adjustLocation(currentHand, 1, -positionDelta, componentName)
		elseif adjustMode == 3 then
			M.setFingerAngles(currentFinger, currentIndex, 0, -jointAngleDelta, componentName)
		end
	end)

	register_key_bind("NumPadFour", function()
		M.print("Num4 pressed")
		if adjustMode == 1 then
			M.adjustRotation(currentHand, 2, rotationDelta, componentName)
		elseif adjustMode == 2 then
			M.adjustLocation(currentHand, 2, positionDelta, componentName)
		elseif adjustMode == 3 then
			M.setFingerAngles(currentFinger, currentIndex, 1, jointAngleDelta, componentName)
		end
	end)
	register_key_bind("NumPadSix", function()
		M.print("Num6 pressed")
		if adjustMode == 1 then
			M.adjustRotation(currentHand, 2, -rotationDelta, componentName)
		elseif adjustMode == 2 then
			M.adjustLocation(currentHand, 2, -positionDelta, componentName)
		elseif adjustMode == 3 then
			M.setFingerAngles(currentFinger, currentIndex, 1, -jointAngleDelta, componentName)
		end
	end)

	register_key_bind("NumPadThree", function()
		M.print("Num3 pressed")
		if adjustMode == 1 then
			M.adjustRotation(currentHand, 3, rotationDelta, componentName)
		elseif adjustMode == 2 then
			M.adjustLocation(currentHand, 3, positionDelta, componentName)
		elseif adjustMode == 3 then
			M.setFingerAngles(currentFinger, currentIndex, 2, jointAngleDelta, componentName)
		end
	end)
	register_key_bind("NumPadOne", function()
		M.print("Num1 pressed")
		if adjustMode == 1 then
			M.adjustRotation(currentHand, 3, -rotationDelta, componentName)
		elseif adjustMode == 2 then
			M.adjustLocation(currentHand, 3, -positionDelta, componentName)
		elseif adjustMode == 3 then
			M.setFingerAngles(currentFinger, currentIndex, 2, -jointAngleDelta, componentName)
		end
	end)
end

function M.setFingerAngles(fingerIndex, jointIndex, angleID, angle, componentName)
	if handBoneList == nil or #handBoneList ==0 then
		M.print("Could not adjust fingers because hand bonelist in invalid")
	else
		componentName = getComponentName(componentName)
		if componentName == "" then
			M.print("Could not adjust rotation because component is undefined")
		else
			local component = M.getHandComponent(fingerIndex < 6 and 0 or 1, componentName)
			animation.setFingerAngles(component, handBoneList, fingerIndex, jointIndex, angleID, angle)
		end
	end
end

function M.printHandTranforms(transforms)
	local logLevel = LogLevel.Critical
	if transforms["Rotation"] ~= nil then
		M.print("Rotation = {" .. transforms["Rotation"][1] .. ", " .. transforms["Rotation"][2] .. ", "  .. transforms["Rotation"][3] ..  "}", logLevel)
	end
	if transforms["Location"] ~= nil then
		M.print("Location = {" .. transforms["Location"][1] .. ", " .. transforms["Location"][2] .. ", "  .. transforms["Location"][3] ..  "}", logLevel)
	end
end

-- local function getValidRotator(definition, id, default)
	-- if definition == nil or id == nil or definition[id] == nil then
		-- return uevrUtils.rotator(default[1], default[2], default[3])
	-- end
	-- return uevrUtils.rotator(definition[id][1], definition[id][2], definition[id][3])
-- end

local function getValidArray(definition, id, default)
	if definition == nil or id == nil or definition[id] == nil then
		return default
	end
	return definition[id]
end

--transformType "Rotation", "Location", "Scale"
function M.setTransform(hand, axis, val, transformType, isDelta, componentName)
--print(hand, axis, val, transformType, isDelta, componentName)
	componentName = getComponentName(componentName)
	--print(componentName)
	if componentName == nil or componentName == "" or handDefinitions[componentName] == nil then
		M.print("Could not adjust transform because component is undefined")
	else
		local handStr = hand == Handed.Left and "Left" or "Right"
		local definition = handDefinitions[componentName][handStr]
		if definition ~= nil then
			local jointName = definition["Name"]
			if jointName ~= nil and jointName ~= "" then
				local currentTransforms = {}
				currentTransforms["Location"] = getValidArray(definition, "Location", {0,0,0})
				currentTransforms["Rotation"] = getValidArray(definition, "Rotation", {0,0,0})
				currentTransforms["Scale"] = getValidArray(definition, "Scale", {1,1,1})
				handDefinitions[componentName][handStr][transformType] = currentTransforms[transformType]
				if isDelta then
					handDefinitions[componentName][handStr][transformType][axis] = handDefinitions[componentName][handStr][transformType][axis] + val
				else
					handDefinitions[componentName][handStr][transformType][axis] = val
				end

				local taperVector = getValidVector(definition, "TaperOffset", {0,0,0})
                local taperOffset = uevrUtils.vector(taperVector.X + Config.handTaperValue, taperVector.Y, taperVector.Z)
				animation.transformBoneToRoot(component, jointName, uevrUtils.vector(currentTransforms["Location"]), uevrUtils.rotator(currentTransforms["Rotation"]), uevrUtils.vector(currentTransforms["Scale"]), taperOffset)
				-- print(handDefinitions[componentName][handStr]["Rotation"][1], handDefinitions[componentName][handStr]["Rotation"][2], handDefinitions[componentName][handStr]["Rotation"][3])
				-- print(handDefinitions[componentName][handStr]["Location"][1], handDefinitions[componentName][handStr]["Location"][2], handDefinitions[componentName][handStr]["Location"][3])
				-- print(handDefinitions[componentName][handStr]["Scale"][1], handDefinitions[componentName][handStr]["Scale"][2], handDefinitions[componentName][handStr]["Scale"][3])
				M.printHandTranforms(handDefinitions[componentName][handStr])
			else
				M.print("Could not adjust bone in adjustRotation() because joint name is invalid" )
			end
		end
	end

end


function M.setRotation(hand, axis, rot, componentName)
	M.setTransform(hand, axis, rot, "Rotation", false, componentName)

	-- componentName = getComponentName(componentName)
	-- print(componentName)
	-- if componentName == nil or componentName == "" or handDefinitions[componentName] == nil then
		-- M.print("Could not adjust rotation because component is undefined")
	-- else	
		-- local handStr = hand == Handed.Left and "Left" or "Right"
		-- local definition = handDefinitions[componentName][handStr]
		-- if definition ~= nil then
			-- local jointName = definition["Name"]
			-- if jointName ~= nil and jointName ~= "" then
				-- local location = getValidVector(definition, "Location", {0,0,0})
				-- --local rotation = getValidRotator(definition, "Rotation", {0,0,0})
				-- if handDefinitions[componentName][handStr]["Rotation"] == nil then
					-- handDefinitions[componentName][handStr]["Rotation"] = {0,0,0}
				-- end
				-- handDefinitions[componentName][handStr]["Rotation"][axis] = rot
				-- local rotation = uevrUtils.rotator(handDefinitions[componentName][handStr]["Rotation"][1], handDefinitions[componentName][handStr]["Rotation"][2], handDefinitions[componentName][handStr]["Rotation"][3])
				-- local scale = getValidVector(definition, "Scale", {1,1,1})
				-- local taperOffset = getValidVector(definition, "TaperOffset", {0,0,0})
				-- local component = M.getHandComponent(hand, componentName)
				-- animation.transformBoneToRoot(component, jointName, location, rotation, scale, taperOffset)		
				-- M.printHandTranforms(handDefinitions[componentName][handStr])
			-- else
				-- M.print("Could not adjust bone in adjustRotation() because joint name is invalid" )
			-- end
		-- end
	-- end
end

function M.adjustRotation(hand, axis, delta, componentName)
	M.setTransform(hand, axis, delta, "Rotation", true, componentName)

	-- componentName = getComponentName(componentName)
	-- if componentName == "" then
		-- M.print("Could not adjust rotation because component is undefined")
	-- else	
		-- local handStr = hand == Handed.Left and "Left" or "Right"
		-- local definition = handDefinitions[componentName][handStr]
		-- if definition ~= nil then
			-- local jointName = definition["Name"]
			-- if jointName ~= nil and jointName ~= "" then
				-- local location = getValidVector(definition, "Location", {0,0,0})
				-- --local rotation = getValidRotator(definition, "Rotation", {0,0,0})
				-- if handDefinitions[componentName][handStr]["Rotation"] == nil then
					-- handDefinitions[componentName][handStr]["Rotation"] = {0,0,0}
				-- end
				-- handDefinitions[componentName][handStr]["Rotation"][axis] = handDefinitions[componentName][handStr]["Rotation"][axis] + delta
				-- local rotation = uevrUtils.rotator(handDefinitions[componentName][handStr]["Rotation"][1], handDefinitions[componentName][handStr]["Rotation"][2], handDefinitions[componentName][handStr]["Rotation"][3])
				-- local scale = getValidVector(definition, "Scale", {1,1,1})
				-- local taperOffset = getValidVector(definition, "TaperOffset", {0,0,0})
				-- local component = M.getHandComponent(hand, componentName)
				-- animation.transformBoneToRoot(component, jointName, location, rotation, scale, taperOffset)		
				-- M.printHandTranforms(handDefinitions[componentName][handStr])
			-- else
				-- M.print("Could not adjust bone in adjustRotation() because joint name is invalid" )
			-- end
		-- end
	-- end
end

function M.setLocation(hand, axis, loc, componentName)
	M.setTransform(hand, axis, loc, "Location", false, componentName)

	-- componentName = getComponentName(componentName)
	-- if componentName == nil or componentName == "" or handDefinitions[componentName] == nil then
		-- M.print("Could not adjust rotation because component is undefined")
	-- else	
		-- local handStr = hand == Handed.Left and "Left" or "Right"
		-- local definition = handDefinitions[componentName][handStr]
		-- if definition ~= nil then
			-- local jointName = definition["Name"]
			-- if jointName ~= nil and jointName ~= "" then
				-- --local location = getValidVector(definition, "Location", {0,0,0})
				-- if handDefinitions[componentName][handStr]["Location"] == nil then
					-- handDefinitions[componentName][handStr]["Location"] = {0,0,0}
				-- end
				-- handDefinitions[componentName][handStr]["Location"][axis] = loc
				-- local location = uevrUtils.vector(handDefinitions[componentName][handStr]["Location"][1], handDefinitions[componentName][handStr]["Location"][2], handDefinitions[componentName][handStr]["Location"][3])
				-- local rotation = getValidRotator(definition, "Rotation", {0,0,0})
				-- local scale = getValidVector(definition, "Scale", {1,1,1})
				-- local taperOffset = getValidVector(definition, "TaperOffset", {0,0,0})
				-- local component = M.getHandComponent(hand, componentName)
				-- animation.transformBoneToRoot(component, jointName, location, rotation, scale, taperOffset)		
				-- M.printHandTranforms(handDefinitions[componentName][handStr])
			-- else
				-- M.print("Could not adjust bone in adjustRotation() because joint name is invalid" )
			-- end
		-- end
	-- end
end


function M.adjustLocation(hand, axis, delta, componentName)
	M.setTransform(hand, axis, delta, "Location", true, componentName)

	-- componentName = getComponentName(componentName)
	-- if componentName == "" then
		-- M.print("Could not adjust rotation because component is undefined")
	-- else	
		-- local handStr = hand == Handed.Left and "Left" or "Right"
		-- local definition = handDefinitions[componentName][handStr]
		-- if definition ~= nil then
			-- local jointName = definition["Name"]
			-- if jointName ~= nil and jointName ~= "" then
				-- --local location = getValidVector(definition, "Location", {0,0,0})
				-- if handDefinitions[componentName][handStr]["Location"] == nil then
					-- handDefinitions[componentName][handStr]["Location"] = {0,0,0}
				-- end
				-- handDefinitions[componentName][handStr]["Location"][axis] = handDefinitions[componentName][handStr]["Location"][axis] + delta
				-- local location = uevrUtils.vector(handDefinitions[componentName][handStr]["Location"][1], handDefinitions[componentName][handStr]["Location"][2], handDefinitions[componentName][handStr]["Location"][3])
				-- local rotation = getValidRotator(definition, "Rotation", {0,0,0})
				-- local scale = getValidVector(definition, "Scale", {1,1,1})
				-- local taperOffset = getValidVector(definition, "TaperOffset", {0,0,0})
				-- local component = M.getHandComponent(hand, componentName)
				-- animation.transformBoneToRoot(component, jointName, location, rotation, scale, taperOffset)		
				-- M.printHandTranforms(handDefinitions[componentName][handStr])
			-- else
				-- M.print("Could not adjust bone in adjustRotation() because joint name is invalid" )
			-- end
		-- end
	-- end
end

function M.setScale(hand, axis, scale, componentName)
	M.setTransform(hand, axis, scale, "Scale", false, componentName)
end

function M.adjustScale(hand, axis, delta, componentName)
	M.setTransform(hand, axis, delta, "Scale", true, componentName)
end

function M.debug(skeletalMeshComponent, hand, rightTargetJoint, disableVisualization)
	local definition = nil
	if rightTargetJoint ~= nil then
		definition = { Name = rightTargetJoint }
	end
	if hand == nil then hand = Handed.Right end
	if uevrUtils.validate_object(skeletalMeshComponent) ~= nil then
		M.print("Creating hands from " .. skeletalMeshComponent:get_full_name() )
		handComponents["Arms"] = {}
		handComponents["Arms"][hand] = M.createComponent(skeletalMeshComponent, "Arms", hand, definition)

		animation.logBoneNames(skeletalMeshComponent)
		if disableVisualization ~= true then
			M.createSkeletalVisualization(hand)
		end
	else
		M.print("SkeletalMesh component is nil in create" )
	end
end

local isHiddenLast = nil
uevrUtils.setInterval(100, function()
	if M.exists() then
		local isHidden, priority = executeIsHiddenCallback()
		if isHidden ~= isHiddenLast then
			isHiddenLast = isHidden
			M.hideHands(isHidden or false)
		end
	end
end)

local isLeftAnimatingLast = nil
local isRightAnimatingLast = nil
uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
	if M.exists() then
		local isLeftAnimating,  leftPriority = executeIsAnimatingFromMeshCallback(Handed.Left)
		local isRightAnimating, rightPriority = executeIsAnimatingFromMeshCallback(Handed.Right)
		--print(isLeftAnimating, isRightAnimating)
		local left = isLeftAnimating
		if isLeftAnimatingLast ~= nil and isLeftAnimating == nil then left = false end
		local right = isRightAnimating
		if isRightAnimatingLast ~= nil and isRightAnimating == nil then right = false end
		M.setHandsAreAnimatingFromMesh(left, right)
		isLeftAnimatingLast = isLeftAnimating
		isRightAnimatingLast = isRightAnimating

		if armsAnimationMeshes[Handed.Left] ~= nil and armsAnimationMeshes[Handed.Left].mesh ~= nil then
			M.updateAnimationFromMesh(Handed.Left, armsAnimationMeshes[Handed.Left].mesh,  armsAnimationMeshes[Handed.Left].componentName)
		end
		if armsAnimationMeshes[Handed.Right] ~= nil and armsAnimationMeshes[Handed.Right].mesh ~= nil then
			M.updateAnimationFromMesh(Handed.Right, armsAnimationMeshes[Handed.Right].mesh,  armsAnimationMeshes[Handed.Right].componentName)
		end
	end
end)

uevr.params.sdk.callbacks.on_script_reset(function()
	M.destroyHands()
end)

uevrUtils.registerPreLevelChangeCallback(function(level)
	M.print("Pre-Level changed in hands")
	M.reset()
	isHiddenLast = false
	autoHandleInput = true
	isLeftAnimatingLast = nil
	isRightAnimatingLast = nil
	autoCreateConfigName = nil
	autoCreateAnimationName = nil
end)

-- FIX (2026-09-07): M.exists() is `getHandComponent(Left) ~= nil OR getHandComponent(Right) ~= nil`
-- - correct for its other callers (e.g. "is the hand system active at all"), but wrong as this
-- retry loop's stop condition: once ONE hand succeeds, M.exists() reports true and this loop
-- never calls createFromConfig() again, even if the other hand's controller wasn't ready yet at
-- creation time (see createComponent()'s own comment) and it's still missing. Requires BOTH
-- hands present for every currently-defined component before treating auto-create as "done".
local function allHandComponentsReady()
	if handDefinitions == nil or next(handDefinitions) == nil then return false end
	for name in pairs(handDefinitions) do
		local components = handComponents[name]
		if components == nil
		or uevrUtils.validate_object(components[Handed.Left]) == nil
		or uevrUtils.validate_object(components[Handed.Right]) == nil then
			return false
		end
	end
	return true
end

local function tryAutoCreateHands()
	if autoCreateHands and not allHandComponentsReady() then
		--see if the defaults params file exists
		local paramsFile = "hands_parameters"
		--if we already found it once we dont ned to keep reading from json to see if it exists
		if autoCreateConfigName ~= nil then
			M.createFromConfig(paramsFile, autoCreateConfigName, autoCreateAnimationName)
		else
			local configuration = json.load_file(paramsFile .. ".json")
			if configuration ~= nil then
				--get the first profile and animation found
				M.print("Loaded hands parameters from hands_parameters.json")
				if configuration["profiles"] ~= nil then
					for key, _ in pairs(configuration["profiles"]) do
						M.print("Found profile: " .. key)
						autoCreateConfigName = key
						break
					end
				end
				if configuration["animations"] ~= nil then
					for key, _ in pairs(configuration["animations"]) do
						M.print("Found animation: " .. key)
						autoCreateAnimationName = key
						break
					end
				end
				if autoCreateConfigName ~= nil then
					M.createFromConfig(paramsFile, autoCreateConfigName, autoCreateAnimationName)
				else
					M.print("Could not auto create hands because no profiles were found")
					autoCreateHands = false --dont keep trying
				end
			else
				M.print("Could not auto create hands")
				autoCreateHands = false --dont keep trying
			end
		end
	end
end

uevrUtils.setInterval(1000, function()
	tryAutoCreateHands()
end)


-- ---------------------------------------------------------------------------
-- Blended (gliding) hand attachment
--
-- attachHandToMesh / attachHandToController snap the hand in one frame. The
-- *Blended variants re-parent with KeepWorldPosition instead, so the hand stays
-- exactly where it is on screen, then ease its RELATIVE transform to the target
-- offset over `duration` seconds. Because the blend runs in the new parent's
-- space, a moving weapon/controller never makes the hand chase its target.
--
-- The re-parent itself is deferred to the post-stereo callback: the motion
-- controllers and the UObjectHook-driven weapon mesh only hold their real poses
-- there (on the game thread they can read as the pawn root), and KeepWorld
-- computes the new relative transform from the parent's CURRENT world pose.
-- If no stereo callback runs within a few ticks it falls back to the game tick.
--
-- Any instant attach/detach of the same hand cancels a pending or running blend.
-- ---------------------------------------------------------------------------
local handBlends = {} -- [hand] = {pending=fn|nil, pendingTicks, elapsed, duration, items={...}}
local blendAppliedThisFrame = false
local BLEND_PENDING_FALLBACK_TICKS = 3

local function cancelHandBlend(hand)
	handBlends[hand] = nil
end
M.cancelHandBlend = cancelHandBlend

function M.isHandBlending(hand)
	return handBlends[hand] ~= nil
end

-- FRotator::Quaternion / FQuat::Rotator (UE conventions), degrees in and out
local function rotatorToQuat(p, y, r)
	local d = math.pi / 360
	local sp, cp = math.sin(p * d), math.cos(p * d)
	local sy, cy = math.sin(y * d), math.cos(y * d)
	local sr, cr = math.sin(r * d), math.cos(r * d)
	return {
		x =  cr * sp * sy - sr * cp * cy,
		y = -cr * sp * cy - sr * cp * sy,
		z =  cr * cp * sy - sr * sp * cy,
		w =  cr * cp * cy + sr * sp * sy,
	}
end

local function normalizeAxis(a)
	a = a % 360
	if a > 180 then a = a - 360 end
	return a
end

local function quatToRotator(q)
	local rad2deg = 180 / math.pi
	local singularity = q.z * q.x - q.w * q.y
	local yawY = 2 * (q.w * q.z + q.x * q.y)
	local yawX = 1 - 2 * (q.y * q.y + q.z * q.z)
	local THRESH = 0.4999995
	local pitch, yaw, roll
	yaw = math.atan(yawY, yawX) * rad2deg
	if singularity < -THRESH then
		pitch = -90
		roll = normalizeAxis(-yaw - 2 * math.atan(q.x, q.w) * rad2deg)
	elseif singularity > THRESH then
		pitch = 90
		roll = normalizeAxis(yaw - 2 * math.atan(q.x, q.w) * rad2deg)
	else
		pitch = math.asin(2 * singularity) * rad2deg
		roll = math.atan(-2 * (q.w * q.x + q.y * q.z), 1 - 2 * (q.x * q.x + q.y * q.y)) * rad2deg
	end
	return pitch, yaw, roll
end

-- Shortest-path slerp (avoids the long way round / flips that Euler lerp gives
-- for offsets like reloadHandRotation's -180 roll)
local function quatSlerp(a, b, t)
	local bx, by, bz, bw = b.x, b.y, b.z, b.w
	local dot = a.x * bx + a.y * by + a.z * bz + a.w * bw
	if dot < 0 then
		dot = -dot
		bx, by, bz, bw = -bx, -by, -bz, -bw
	end
	local s0, s1
	if dot > 0.9995 then
		s0, s1 = 1 - t, t
	else
		local theta = math.acos(dot)
		local sinTheta = math.sin(theta)
		s0 = math.sin((1 - t) * theta) / sinTheta
		s1 = math.sin(t * theta) / sinTheta
	end
	local x = s0 * a.x + s1 * bx
	local y = s0 * a.y + s1 * by
	local z = s0 * a.z + s1 * bz
	local w = s0 * a.w + s1 * bw
	local len = math.sqrt(x * x + y * y + z * z + w * w)
	if len > 0 then x, y, z, w = x / len, y / len, z / len, w / len end
	return {x = x, y = y, z = z, w = w}
end

-- Captures the component's current relative transform (as plain numbers) and
-- records the blend from there to the target relative transform.
local function addBlendItem(items, component, toLoc, toRot)
	local relLoc = component.RelativeLocation
	local relRot = component.RelativeRotation
	if relLoc == nil or relRot == nil then return false end
	items[#items + 1] = {
		component = component,
		fromLoc = {X = relLoc.X, Y = relLoc.Y, Z = relLoc.Z},
		toLoc = {X = toLoc.X, Y = toLoc.Y, Z = toLoc.Z},
		fromQuat = rotatorToQuat(relRot.Pitch, relRot.Yaw, relRot.Roll),
		toQuat = rotatorToQuat(toRot.Pitch, toRot.Yaw, toRot.Roll),
		toRot = {Pitch = toRot.Pitch, Yaw = toRot.Yaw, Roll = toRot.Roll},
	}
	return true
end

local function applyBlendItem(item, alpha)
	local component = item.component
	local hitResult = uevrUtils.get_struct_object("ScriptStruct /Script/Engine.HitResult")
	local loc, rot
	if alpha >= 1 then
		-- Land exactly on the target, same values the instant attach would set
		loc = uevrUtils.vector(item.toLoc.X, item.toLoc.Y, item.toLoc.Z)
		rot = uevrUtils.rotator(item.toRot.Pitch, item.toRot.Yaw, item.toRot.Roll)
	else
		local f, t = item.fromLoc, item.toLoc
		loc = uevrUtils.vector(f.X + (t.X - f.X) * alpha, f.Y + (t.Y - f.Y) * alpha, f.Z + (t.Z - f.Z) * alpha)
		local p, y, r = quatToRotator(quatSlerp(item.fromQuat, item.toQuat, alpha))
		rot = uevrUtils.rotator(p, y, r)
	end
	component:K2_SetRelativeLocationAndRotation(loc, rot, false, hitResult, false)
end

local function stepHandBlends()
	for hand, blend in pairs(handBlends) do
		if blend.pending ~= nil then
			local start = blend.pending
			blend.pending = nil
			local ok, err = pcall(start)
			if not ok then
				M.print("Hand blend start failed: " .. tostring(err), LogLevel.Warning)
			end
			-- start() may have cancelled the blend or replaced it with an instant attach
			blend = handBlends[hand]
		end
		if blend ~= nil and blend.pending == nil then
			local alpha = blend.duration > 0 and math.min(blend.elapsed / blend.duration, 1) or 1
			local eased = 1 - (1 - alpha) ^ 3 -- ease-out cubic: fast start, settles onto the target
			local live = 0
			for _, item in ipairs(blend.items) do
				if uevrUtils.getValid(item.component) ~= nil then
					local ok = pcall(applyBlendItem, item, eased)
					if ok then live = live + 1 end
				end
			end
			if alpha >= 1 or live == 0 then
				handBlends[hand] = nil
			end
		end
	end
end

local function queueHandBlend(hand, duration, start)
	handBlends[hand] = {pending = start, pendingTicks = 0, elapsed = 0, duration = duration, items = {}}
end

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
	blendAppliedThisFrame = false
	if next(handBlends) == nil then return end
	for _, blend in pairs(handBlends) do
		if blend.pending ~= nil then
			blend.pendingTicks = blend.pendingTicks + 1
		else
			blend.elapsed = blend.elapsed + (delta or 0)
		end
	end
	-- No stereo callback picked a pending start up (no HMD / view callbacks not firing):
	-- start it here rather than leave the hand parked where it was.
	for _, blend in pairs(handBlends) do
		if blend.pending ~= nil and blend.pendingTicks >= BLEND_PENDING_FALLBACK_TICKS then
			stepHandBlends()
			break
		end
	end
end)

uevrUtils.registerPostCalculateStereoViewCallback(function(device, view_index)
	if blendAppliedThisFrame or next(handBlends) == nil then return end
	blendAppliedThisFrame = true
	stepHandBlends()
end)

-- The hand components are torn down/rebuilt on these, so drop any blend state with them
uevrUtils.registerPreLevelChangeCallback(function(level)
	handBlends = {}
end)

uevr.params.sdk.callbacks.on_script_reset(function()
	handBlends = {}
end)

-- ---------------------------------------------------------------------------
-- Finger curl blend: ease the 15 finger joints from wherever they are into a
-- new grip pose (two-handing) instead of snapping.
--
-- The pose is applied exactly as before (applyFn), then its result is read back
-- as the target and the fingers are restored to where they were. Start and target
-- are captured once in component space, so each frame is one SetBoneRotationByName
-- per joint (parents before children) — a full pose apply costs ~60 ms per hand
-- on this UEVR build and must not run per frame.
-- ---------------------------------------------------------------------------
local FINGER_NAMES = {"thumb", "index", "middle", "ring", "pinky"}
local BONE_SPACE_COMPONENT = 1
local fingerBoneCache = {} -- [component address] = {FName, ...} (existing bones only)

local function getFingerBones(component, hand)
	local address = component:get_address()
	local cached = fingerBoneCache[address]
	if cached ~= nil then return cached end
	local side = hand == Handed.Left and "l" or "r"
	local bones = {}
	for _, finger in ipairs(FINGER_NAMES) do
		for joint = 1, 3 do -- 01 before 02 before 03: parents are written first
			local name = "jnt_" .. side .. "_hand_" .. finger .. "_0" .. joint
			if animation.hasBone(component, name) then
				bones[#bones + 1] = uevrUtils.fname_from_string(name)
			end
		end
	end
	fingerBoneCache[address] = bones
	return bones
end

local function readFingerQuats(component, bones)
	local quats = {}
	for i, fname in ipairs(bones) do
		local transform = component:GetBoneTransformByName(fname, BONE_SPACE_COMPONENT)
		local r = transform and transform.Rotation
		if r == nil then return nil end
		quats[i] = {x = r.X, y = r.Y, z = r.Z, w = r.W}
	end
	return quats
end

local function applyFingerBlend(blend, alpha)
	local component = blend.component
	for i, fname in ipairs(blend.bones) do
		local q = alpha >= 1 and blend.to[i] or quatSlerp(blend.from[i], blend.to[i], alpha)
		local p, y, r = quatToRotator(q)
		component:SetBoneRotationByName(fname, uevrUtils.rotator(p, y, r), BONE_SPACE_COMPONENT)
	end
end

-- Running the free-hand grip/trigger finger lerps alongside would fight the curl
local function cancelInputFingerLerps(hand)
	local handStr = hand == Handed.Left and "left" or "right"
	for id, _ in pairs(inputHandlerAnimID) do
		uevrUtils.cancelLerp(id .. "-" .. handStr .. "_grip")
		uevrUtils.cancelLerp(id .. "-" .. handStr .. "_trigger")
	end
end

-- Runs applyFn (which applies a pose to `hand` instantly), then eases the fingers
-- into that result over `duration` seconds. `pose` is the bone table when applyFn
-- is a setHandPose call, so per-frame re-applies of the same table don't cut it short.
function M.blendFingerPose(hand, duration, applyFn, pose)
	local component = M.getHandComponent(hand, getComponentName(nil))
	-- IK: no curl. The blend replays component-space finger rotations captured at its start, and the IK
	-- solver moves the rig's hand bone every tick, so the fingers would trail the hand until it lands.
	if duration == nil or duration <= 0 or ikDelegate ~= nil or uevrUtils.getValid(component) == nil then
		fingerBlends[hand] = nil
		applyFn()
		return
	end

	local ok, err = pcall(function()
		local bones = getFingerBones(component, hand)
		-- Mid-curl this reads the in-between pose, so a re-target continues smoothly
		local from = #bones > 0 and readFingerQuats(component, bones) or nil
		fingerBlends[hand] = nil
		applyFn()
		if from == nil then return end
		local to = readFingerQuats(component, bones)
		if to == nil then return end

		local moved = false
		for i = 1, #bones do
			local a, b = from[i], to[i]
			if math.abs(a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w) < 0.99995 then moved = true break end
		end
		if not moved then return end

		cancelInputFingerLerps(hand)
		local blend = {component = component, bones = bones, from = from, to = to, pose = pose, elapsed = 0, duration = duration}
		fingerBlends[hand] = blend
		applyFingerBlend(blend, 0) -- back to the start pose this frame
	end)
	if not ok then
		M.print("Finger blend failed, pose applied instantly: " .. tostring(err), LogLevel.Warning)
		fingerBlends[hand] = nil
	end
end

function M.setHandPoseBlended(hand, pose, duration, componentName)
	M.blendFingerPose(hand, duration, function() M.setHandPose(hand, pose, componentName) end, pose)
end

function M.isFingerBlending(hand)
	return fingerBlends[hand] ~= nil
end

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
	if next(fingerBlends) == nil then return end
	for hand, blend in pairs(fingerBlends) do
		blend.elapsed = blend.elapsed + (delta or 0)
		local alpha = math.min(blend.elapsed / blend.duration, 1)
		local eased = alpha * alpha * (3 - 2 * alpha) -- smoothstep: gentle start and finish
		if uevrUtils.getValid(blend.component) == nil or not pcall(applyFingerBlend, blend, eased) or alpha >= 1 then
			fingerBlends[hand] = nil
		end
	end
end)

uevrUtils.registerPreLevelChangeCallback(function(level)
	fingerBlends = {}
	fingerBoneCache = {}
end)

uevr.params.sdk.callbacks.on_script_reset(function()
	fingerBlends = {}
	fingerBoneCache = {}
end)

-- Same result as attachHandToMesh, but the hand glides from where it currently is
-- to the socket + offsets over `duration` seconds instead of snapping.
function M.attachHandToMeshBlended(hand, mesh, socketName, rotationOffset, locationOffset, duration)
	if mesh == nil then return end
	if ikDelegate then return ikDelegate.attachHandToMesh(hand, mesh, socketName, rotationOffset, locationOffset, duration) end
	if duration == nil or duration <= 0 then
		M.attachHandToMesh(hand, mesh, socketName, rotationOffset, locationOffset)
		return
	end

	queueHandBlend(hand, duration, function()
		if uevrUtils.getValid(mesh) == nil then
			cancelHandBlend(hand)
			return
		end
		local socketFName = uevrUtils.fname_from_string((socketName ~= nil and socketName ~= "") and socketName or "None")
		local toLoc = {X = locationOffset and locationOffset[1] or 0, Y = locationOffset and locationOffset[2] or 0, Z = locationOffset and locationOffset[3] or 0}
		local toRot = {Pitch = rotationOffset and rotationOffset[1] or 0, Yaw = rotationOffset and rotationOffset[2] or 0, Roll = rotationOffset and rotationOffset[3] or 0}
		local items = {}
		local failed = false
		for name, components in pairs(handComponents) do
			local component = components[hand]
			if uevrUtils.getValid(component) ~= nil then
				-- KeepWorldPosition (1): re-parent without moving; the blend then eases it in
				local success = component:K2_AttachTo(mesh, socketFName, 1, true)
				if success then
					component:SetWorldScale3D(uevrUtils.vector(1, 1, 1))
					if not addBlendItem(items, component, toLoc, toRot) then failed = true end
				else
					failed = true
				end
			end
		end
		if failed then
			-- Never leave a half-attached hand: finish with the plain snap
			M.print("Blended attach failed for hand " .. hand .. ", snapping instead", LogLevel.Warning)
			M.attachHandToMesh(hand, mesh, socketName, rotationOffset, locationOffset)
			return
		end
		handBlends[hand].items = items
	end)
end

-- Same result as attachHandToController, but the hand glides from where it currently
-- is back to its controller base transform over `duration` seconds.
-- The finger pose / animation state reset happens immediately, as in the instant version.
function M.attachHandToControllerBlended(hand, duration)
	if ikDelegate then return ikDelegate.attachHandToController(hand, duration) end
	if duration == nil or duration <= 0 then
		M.attachHandToController(hand)
		return
	end

	for name, components in pairs(handComponents) do
		if uevrUtils.getValid(components[hand]) ~= nil then
			M.setInitialTransform(hand, name)
		end
	end
	M.updateAnimationState(hand)

	queueHandBlend(hand, duration, function()
		local items = {}
		local failed = false
		for name, components in pairs(handComponents) do
			local component = components[hand]
			if uevrUtils.getValid(component) ~= nil then
				if controllers.attachComponentToController(hand, component, nil, 1) then -- KeepWorldPosition
					component:SetWorldScale3D(uevrUtils.vector(1, 1, 1))
					local baseTrans = handBaseTransforms[name] and handBaseTransforms[name][hand]
					local toLoc = baseTrans and baseTrans.loc or {X = 0, Y = 0, Z = 0}
					local toRot = baseTrans and baseTrans.rot or {Pitch = 0, Yaw = 0, Roll = 0}
					if not addBlendItem(items, component, toLoc, toRot) then failed = true end
				else
					failed = true
				end
			end
		end
		if failed then
			M.print("Blended controller attach failed for hand " .. hand .. ", snapping instead", LogLevel.Warning)
			M.attachHandToController(hand)
			return
		end
		handBlends[hand].items = items
	end)
end

function M.attachHandToMesh(hand, mesh, socketName, rotationOffset, locationOffset)
	if mesh == nil then return end
	if ikDelegate then return ikDelegate.attachHandToMesh(hand, mesh, socketName, rotationOffset, locationOffset, 0) end
	cancelHandBlend(hand)

	-- Iterate through all hand components (arms, gloves, etc.)
	for name, components in pairs(handComponents) do
		local component = components[hand]
		if uevrUtils.getValid(component) ~= nil then
			-- Detach from current parent (controller)
			component:DetachFromParent(true, true)
			
			-- Attach to the weapon mesh
			-- Using AttachToComponent or K2_AttachToComponent depending on what's available
			-- Usually K2_AttachTo is safe for UEVR usage
            local socketFName = component.AttachSocketName
            if socketName ~= nil and socketName ~= "" then
                socketFName = uevrUtils.fname_from_string(socketName)
            elseif socketFName == nil then
                 socketFName = uevrUtils.fname_from_string("None") 
            end
			M.print("Attaching hand component " .. name .. " to mesh " .. mesh:get_full_name() .. " at socket " .. tostring(socketName))
			local success = component:K2_AttachTo(mesh, socketFName, 2, true) -- EAttachLocation::SnapToTarget = 2
            
            if success then
                local hitResult = uevrUtils.get_struct_object("ScriptStruct /Script/Engine.HitResult")
                
                if rotationOffset ~= nil then
                    -- Apply manual rotation offset
                    local rot = uevrUtils.rotator(rotationOffset[1] or 0, rotationOffset[2] or 0, rotationOffset[3] or 0)
                    M.print("Applying rotation offset: " .. rotationOffset[1] .. ", " .. rotationOffset[2] .. ", " .. rotationOffset[3])
                    component:K2_SetRelativeRotation(rot, false, hitResult, false)
                end
                
                if locationOffset ~= nil then
                    -- Apply manual location offset
                    local pos = uevrUtils.vector(locationOffset[1] or 0, locationOffset[2] or 0, locationOffset[3] or 0)
                    M.print("Applying location offset: " .. locationOffset[1] .. ", " .. locationOffset[2] .. ", " .. locationOffset[3])
                    component:K2_SetRelativeLocation(pos, false, hitResult, false)
                end
                
                -- Reset scale to prevent inheritance issues from parent mesh
                local scale = uevrUtils.vector(1, 1, 1)
                component:SetWorldScale3D(scale)
                M.print("Reset scale to (1,1,1) for " .. name)
            else
                M.print("Failed to attach " .. name .. " to " .. mesh:get_full_name(), LogLevel.Warning)
            end
                                                                        -- Actually user said "attach to the weapon mesh itself" so it follows it.
                                                                        -- If we use SnapToTarget, it snaps to 0,0,0 of weapon. Ideally we want relative offset?
                                                                        -- User said "PoseableMeshComponent ... attached to the weapon... avoid conflict... uobject position"
                                                                        
            -- Let's try KeepRelativeOffset (rule 1) or KeepWorld (rule 0)?
            -- If we snap, we might lose our carefully tuned offsets.
            -- But "follow the controller directly" implies it was attached to controller. 
            -- If we attach to weapon, we probably want it to stay where it is relative to the weapon?
            -- No, the hands need to be AT the weapon handle.
            
            -- Let's stick to simple attachment first. We might need to adjust rules later.
			M.print("Attaching hand component " .. name .. " to weapon")
		end
	end
end

function M.attachHandToController(hand)
	if ikDelegate then return ikDelegate.attachHandToController(hand, 0) end
	cancelHandBlend(hand)
	for name, components in pairs(handComponents) do
		local component = components[hand]
		if uevrUtils.getValid(component) ~= nil then
			-- Re-attach to controller
			controllers.attachComponentToController(hand, component)
			
			-- Reset pose to default
			M.setInitialTransform(hand, name)
			M.updateAnimationState(hand)
			
			-- Reset relative transform to controller default
			local baseTrans = nil
			if handBaseTransforms[name] and handBaseTransforms[name][hand] then
				baseTrans = handBaseTransforms[name][hand]
			end

			local rot = baseTrans and uevrUtils.rotator(baseTrans.rot.Pitch, baseTrans.rot.Yaw, baseTrans.rot.Roll) or uevrUtils.rotator(0, 0, 0)
			local loc = baseTrans and uevrUtils.vector(baseTrans.loc.X, baseTrans.loc.Y, baseTrans.loc.Z) or uevrUtils.vector(0, 0, 0)
			local scale = uevrUtils.vector(1, 1, 1)
			local hitResult = uevrUtils.get_struct_object("ScriptStruct /Script/Engine.HitResult")
			component:K2_SetRelativeRotation(rot, false, hitResult, false)
			component:K2_SetRelativeLocation(loc, false, hitResult, false)
			component:SetWorldScale3D(scale)
			
			M.print("Reset hand component " .. name .. " to controller")
		end
	end
end

-- Dynamically captures the bone rotations of the specified hand from a skeletal mesh component
-- boneList should be an array of string bone names (e.g., {"jnt_l_hand_thumb_01", ...})
function M.capturePoseFromMesh(meshComponent, boneList)
	if meshComponent == nil or boneList == nil then return nil end
	
	local tempPoseableMesh = uevrUtils.createPoseableMeshFromSkeletalMesh(meshComponent)
	if tempPoseableMesh == nil then return nil end
	
	-- uevrUtils copies the pose, but if it is already a poseable mesh, we need to bind it
	if meshComponent:is_a(uevrUtils.get_class("Class /Script/Engine.PoseableMeshComponent")) then
		tempPoseableMesh:SetLeaderPoseComponent(meshComponent, true)
	end

	local rotators = {}
	
	for _, fNameString in ipairs(boneList) do
		local fName = uevrUtils.fname_from_string(fNameString)
		local rotation, location, scale = animation.getBoneSpaceLocalTransform(tempPoseableMesh, fName, 0)
		if rotation ~= nil then
			rotators[fNameString] = {rotation.Pitch, rotation.Yaw, rotation.Roll}
		end
	end
	
	if meshComponent:is_a(uevrUtils.get_class("Class /Script/Engine.PoseableMeshComponent")) then
		tempPoseableMesh:SetLeaderPoseComponent(nil, false)
	end
	
	uevrUtils.destroyComponent(tempPoseableMesh, true, true)
	
	return rotators
end

return M


--deprecated code
-- local currentRightRotation = {0, 0, 0}
-- local currentRightLocation = {0, 0, 0}
-- local currentLeftRotation = {0, 0, 0}
-- local currentLeftLocation = {0, 0, 0}
-- local currentScale = 1.0
-- 

-- local rightHandComponent = nil
-- local leftHandComponent = nil



-- local leftJointName = ""
-- local rightJointName = ""

-- function M.create(skeletalMeshComponent, leftTargetJoint, rightTargetJoint, rightRotation, rightLocation, leftRotation, leftLocation, pHandBoneList, scale)
	-- if uevrUtils.validate_object(skeletalMeshComponent) ~= nil and leftTargetJoint ~= nil and leftTargetJoint ~= "" and rightTargetJoint ~= nil and rightTargetJoint ~= "" then
		-- leftJointName = leftTargetJoint
		-- rightJointName = rightTargetJoint
		-- if pHandBoneList ~= nil then handBoneList = pHandBoneList end
		-- if rightRotation ~= nil then currentRightRotation = rightRotation end
		-- if rightLocation ~= nil then currentRightLocation = rightLocation end
		-- if leftRotation ~= nil then currentLeftRotation = leftRotation end
		-- if leftLocation ~= nil then currentLeftLocation = leftLocation end
		-- if scale ~= nil then currentScale = scale end
		-- M.print("Creating hands from " .. skeletalMeshComponent:get_full_name() )	
		-- rightHandComponent = M.createComponent(skeletalMeshComponent, "Arms", 1)
		-- if rightHandComponent ~= nil then
			-- leftHandComponent = M.createComponent(skeletalMeshComponent, "Arms", 0)	

			-- animation.add("right_hand", rightHandComponent, handAnimations)
			-- animation.add("left_hand", leftHandComponent, handAnimations)			
		-- end
	-- else
		-- M.print("SkeletalMesh component is nil or target joints are invalid in create" )
	-- end
-- end

-- function M.createComponent(skeletalMeshComponent, name, hand, disableInit)
	-- local component = nil
	-- if uevrUtils.validate_object(skeletalMeshComponent) ~= nil then
		-- --not using an existing actor as owner. Mesh affects the hands opacity so its not appropriate
		-- component = animation.createPoseableComponent(skeletalMeshComponent, nil)
		-- if component ~= nil then
			-- --fixes flickering but > 1 causes a perfomance hit with dynamic shadows according to unreal doc
			-- --a better way to do this should be found
			-- component.BoundsScale = 16.0
			-- component.bCastDynamicShadow = false

			-- controllers.attachComponentToController(hand, component)
			-- local baseRotation = skeletalMeshComponent.RelativeRotation
			-- uevrUtils.set_component_relative_transform(component, offset, {Pitch=baseRotation.Pitch+offset.Pitch, Yaw=baseRotation.Yaw+offset.Yaw,Roll=baseRotation.Roll+offset.Roll})	

			-- if disableInit ~= true then
				-- local location = hand == 1 and uevrUtils.vector(currentRightLocation[1], currentRightLocation[2], currentRightLocation[3]) or uevrUtils.vector(currentLeftLocation[1], currentLeftLocation[2], currentLeftLocation[3])
				-- local rotation = hand == 1 and uevrUtils.rotator(currentRightRotation[1], currentRightRotation[2], currentRightRotation[3]) or uevrUtils.rotator(currentLeftRotation[1], currentLeftRotation[2], currentLeftRotation[3])
				-- --animation.initPoseableComponent(component, (hand == 1) and rightJointName or leftJointName, (hand == 1) and rightShoulderName or leftShoulderName, (hand == 1) and leftShoulderName or rightShoulderName, location, rotation, uevrUtils.vector(currentScale, currentScale, currentScale), rootBoneName)
				-- animation.transformBoneToRoot(component, (hand == 1) and rightJointName or leftJointName, location, rotation, uevrUtils.vector(currentScale, currentScale, currentScale), uevrUtils.vector(20, 0, 0))		
			-- end
		-- end
	-- end
	-- return component
-- end
