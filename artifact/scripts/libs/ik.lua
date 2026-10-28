--IK arm system for VR two-bone solvers and poseable mesh arms in Unreal Engine VR mods

--[[ 
Usage
    Drop the lib folder containing this file into your project folder
    To create IK arms for a game, add code like this in your script:
		local uevrUtils = require('libs/uevr_utils')
		local ik = require('libs/ik')
		ik.init()
	In developer mode, ik.init(true) also loads the in-game IK configuration tool.
	With auto-create enabled (default), the module will create arms from ik_parameters.json /
	hands_parameters when a mesh is configured on the active profile.

    This module provides two-bone IK arm solving against VR motion controllers, poseable mesh
    management, accessory socket targeting, profile-based configuration, and optional copy-pose
    animation from a source skeletal mesh.
        
    Profile settings: 
		IK Pose Authoritative (animation_ik_pose_authoritative) (IK Dev Config → Animation → "IK Pose Authoritative")
			Controls whether two-bone solvers keep running during CopyPose animation frames.
			CopyPoseFromSkeletalComponent always writes the full shared arms skeleton, so games need
			different ownership of the pose afterward:
				true  - solvers always run (including after CopyPose). Use when a one-arm montage would
					otherwise leave the other arm stuck in the game's animated pose and you need IK to
					reclaim controller tracking on that arm. (see Atomic Heart for an example)
				false - solvers run only when not animating. Use when montages (e.g. weapon reloads)
					must keep their authored arm/weapon rotations and post-CopyPose IK would twist them
					toward the controllers. (see The Outer Worlds for an example)
			Configure per profile in ik_parameters / the IK Dev Config UI.
	
	Available functions:
    
    ik.init((optional)isDeveloperMode, (optional)logLevel) - initializes the IK module.
		If isDeveloperMode is omitted, uses uevrUtils.getDeveloperMode(). In developer mode the
		ik_config_dev UI is loaded for live parameter editing.
        example:
            ik.init()
            ik.init(true, LogLevel.Debug)

    ik.setAutoCreateArms(val) - enables/disables automatic creation of IK arms from configuration.
		Automatic creation is enabled by default. If disabled, arms will not be automatically created
		and you will need to call ik.new() manually (or re-enable auto-create).
        example:
            ik.setAutoCreateArms(false)

	Enhanced Stabilization (enhanced_stabilization) is a per-rig IK Dev Config checkbox.
		When enabled, IK runs after the engine tick. The mesh stays attached to its
		selected parent for position, while its world rotation is set before the solve.
		Disabled by default for existing game profiles.

    ik.new((optional)options) - creates a new IK rig instance from the active (or specified) profile.
		Returns the rig instance, or nil if creation failed.
		options:
			rigId - profile/rig id to use (defaults to active profile)
			animationsFile - hands_parameters file name for grip animations (e.g. "hands_parameters")
			tickPhase - "pre" (default) or "post" engine tick
			tickPriority - optional tick callback priority
			Enhanced Stabilization is read from the rig profile, not from ik.new options.
        example:
            local rig = ik.new({ animationsFile = "hands_parameters" })
            local rig = ik.new({ rigId = "my_profile", tickPhase = "post" })

    ik.exists() - returns true if at least one IK rig instance exists
        example:
            if ik.exists() then
                -- Do something with IK arms
            end

    ik.getCurrentMesh((optional)index) - gets a poseable mesh from the most recently created rig.
		index defaults to 1.
        example:
            local armsMesh = ik.getCurrentMesh()
            local secondMesh = ik.getCurrentMesh(2)

    ik.hide(isHidden) - shows/hides all IK rig meshes
        example:
            ik.hide(true)  -- Hide IK arms

    ik.destroyAll() - destroys all IK rig instances and cleans up created components
        example:
            ik.destroyAll()

    ik.destroy(instance, (optional)skipUnregister) - destroys a specific IK rig instance.
		Pass skipUnregister=true when the instance is already being removed from the registry
		(used internally by destroyAll).
        example:
            local rig = ik.new()
            ik.destroy(rig)

    ik.setPawn(pawnObject) - sets the pawn used for root/capsule coupling instead of the global pawn
        example:
            ik.setPawn(myPawn)

    ik.setRootBoneRotation(rotator) - sets the root bone rotation on the most recently created rig
        example:
            ik.setRootBoneRotation(uevrUtils.rotator(0, 90, 0))

    ik.lockWristAxis(solverId, pitch, yaw, roll) - locks end-bone pitch/yaw/roll for a solver on the
		most recently created rig (true/false per axis). For a real example see Subnautica
        example:
            ik.lockWristAxis("left_arm", true, false, true)

    ik.setGunstockOffsetsEnabled(val) - enables/disables applying gunstock rotation offsets to the
		right-hand IK controller target
        example:
            ik.setGunstockOffsetsEnabled(true)

    ik.setCurrentProfile(profileID) - sets the active IK parameter profile by id
        example:
            ik.setCurrentProfile("055655c3-5c27-40fb-afa2-af6169aa5397")

    ik.setCurrentProfileByLabel(profileLabel) - sets the active IK parameter profile by display label
        example:
            ik.setCurrentProfileByLabel("Default")

    ik.registerOnMeshCreatedCallback(callback) - registers a callback invoked after a rig's meshes
		are created. Callback receives (meshList, ikInstance).
        example:
            ik.registerOnMeshCreatedCallback(function(meshList, ikInstance)
                local mesh = meshList and meshList[1]
                if mesh ~= nil then
                    print("IK mesh ready:", mesh:get_full_name())
                end
            end)

    ik.registerOnDestroyCallback(callback) - registers a callback invoked before an IK instance is destroyed.
		Callback receives (ikInstance).
        example:
            ik.registerOnDestroyCallback(function(ikInstance)
                print("IK destroyed:", ikInstance.rigId)
            end)

    ik.registerGetCustomAnimationInitialTransformCallback(func) - registers a callback used after
		CopyPoseFromSkeletalComponent animation. Return a list of initialTransforms bone indexes that
		should be reset to their captured initial transforms (to undo bad animated values on bones
		IK should own). Set ik.enableAnimationBoneListPrintout = true to print index/name pairs when
		a solver becomes active.
        example:
            ik.enableAnimationBoneListPrintout = true  -- once, to discover indexes
            ik.registerGetCustomAnimationInitialTransformCallback(function()
                return { 1, 2, 3, 4, 5, 6, 7, 8 }  -- bone indexes into initialTransforms
            end)

    ik.setInitialTransformOnAnimationCompleteEnabled(val) - when true (default), after CopyPose
		animation stops the rig resets all bones to the transforms captured at solver activation.
		Disable if that full reset snaps or destroys the mesh for your game.
        example:
            ik.setInitialTransformOnAnimationCompleteEnabled(false)

    ik.registerIsSetInitialTransformOnAnimationCompleteEnabledCallback(func) - optional priority
		boolean override for the setting above. Return true/false[, priority], or nil for no opinion.
        example:
            ik.registerIsSetInitialTransformOnAnimationCompleteEnabledCallback(function()
                return false, 10
            end)

    ik.enableAnimationBoneListPrintout - debug flag (default false). When true, prints bone index and
		name while capturing initialTransforms for an active solver.
        example:
            ik.enableAnimationBoneListPrintout = true

    ik.printMeshBoneTransforms(mesh, (optional)boneSpace) - prints local bone transforms for a mesh
		(debug). boneSpace defaults to 0 / component space.
        example:
            ik.printMeshBoneTransforms(ik.getCurrentMesh())

    ik.setLogLevel(val) - sets the logging level for IK system messages
        example:
            ik.setLogLevel(LogLevel.Debug)

	Optional global hooks (define in your game script; not module functions):
		getCustomIKComponent(rigId) - called when the active profile mesh is "Custom". Used when a
			game has multiple meshes for one pawn, or different pawn layouts (e.g. on foot vs vehicle).
			Return either:
				- a single string descriptor, which is wrapped as {{descriptor = "<string>"}}
				- or a table of mesh template entries (preferred)
			Each template entry may contain:
				descriptor (string) - hierarchy path resolved with uevrUtils.getObjectFromDescriptor.
					Paths usually start with "Pawn" (capital P). The rest follows the game's component
					names, e.g. "Pawn.Mesh", "Pawn.Mesh(Arms)", "Pawn.Body". Parentheses select among
					child siblings of the base name.
				instance (UObject, optional) - already-resolved skeletal mesh component. If set, the
					descriptor lookup is skipped.
				animation (string, optional) - hands animation profile key to bind grip animations to
					this mesh copy, e.g. "Arms" or "Gloves". If omitted, the first unused mesh may be
					used as a fallback animation target.
				optional (boolean, optional) - if true, failing to create this poseable mesh does not
					fail the whole IK rig. Required meshes (optional ~= true) must succeed.
			example:
				function getCustomIKComponent(rigID)
					local path = "Pawn"
					if status.currentVehicle == "TadPole" then
						path = "Pawn.Pilot"
					end
					return {
						{descriptor = path .. ".Body"},
						{descriptor = path .. ".Hands", animation = "Arms", optional = true},
					}
				end
			example (multiple clothing layers):
				function getCustomIKComponent(rigID)
					return {
						{descriptor = "Pawn.Mesh(Robe)"},
						{descriptor = "Pawn.Mesh(Gloves)", animation = "Gloves", optional = true},
						{descriptor = "Pawn.Mesh(Arms)", animation = "Arms", optional = true},
					}
				end

		getCustomAnimationIKComponent(rigId) - return the skeletal mesh component used as the
			CopyPoseFromSkeletalComponent animation source when profile animation_mesh is "Custom".
			example:
				function getCustomAnimationIKComponent(rigID)
					return uevrUtils.getObjectFromDescriptor("Pawn.Mesh", false)
				end

--]]

local uevrUtils = require("libs/uevr_utils")
local mathLib = require("libs/core/math_lib")
local paramModule = require("libs/core/params")
local controllers = require("libs/controllers")
local handsAnimation = require("libs/hands_animation")
local input = require("libs/input")
--local collision = require("libs/collision")
--local animation = require("libs/animation") --used for debugging only
require("libs/accessories")
require("libs/enums/unreal")

local M = {}

M.SolverType = {
    TWO_BONE = 1,
    ROTATION_ONLY = 2,
}

M.ControllerType = {
    LEFT_CONTROLLER = 0,
    RIGHT_CONTROLLER = 1,
}

-- Keep a module owned registry of rig instances for global cleanup
local _rigInstances = {}
local function registerInstance(inst)
    table.insert(_rigInstances, inst)
end
local function unregisterInstance(inst)
    for i = #_rigInstances, 1, -1 do
        if _rigInstances[i] == inst then
            table.remove(_rigInstances, i)
            return
        end
    end
end
local function isRegisteredInstance(inst)
    for i = 1, #_rigInstances do
        if _rigInstances[i] == inst then return true end
    end
    return false
end
function M.destroyAll()
    for i = #_rigInstances, 1, -1 do
		local inst = table.remove(_rigInstances, i)
		if inst then M.destroy(inst, true) end
    end
end

function M.hide(isHidden)
    for i = #_rigInstances, 1, -1 do
		_rigInstances[i]:hide(isHidden)
    end
end

function M.exists()
	return #_rigInstances > 0
end

function M.getCurrentMesh(index)
    if #_rigInstances > 0 then
       local meshes =  _rigInstances[#_rigInstances].meshList
	   if meshes ~= nil and #meshes > 0 then -- nil while a dead rig is being dropped (solveTwoBone)
		   return meshes[index or 1]
	   end
    end
    return nil
end

-- "pre" / "post" engine tick of the most recently created rig ("post" with Enhanced Stabilization), nil without a
-- rig. Stalker 2: Base/basic.lua needs it to render the weapon at the pose the visible arm pose was solved against.
function M.getTickPhase()
	if #_rigInstances > 0 then
		return _rigInstances[#_rigInstances].tickPhase
	end
	return nil
end

function M.lockWristAxis(solverId, pitch, yaw, roll)
	if #_rigInstances > 0 then
		local rig = _rigInstances[#_rigInstances]
		rig:setSolverParameter(solverId, "end_bone_lock_pitch", pitch)
		rig:setSolverParameter(solverId, "end_bone_lock_yaw", yaw)
		rig:setSolverParameter(solverId, "end_bone_lock_roll", roll)
	end
end

function M.setRootBoneRotation(rotator)
	if #_rigInstances > 0 then
		local rig = _rigInstances[#_rigInstances]
		rig:setRootBoneRotation(rotator)
	end
end

local pawnObject = nil
function M.setPawn(newPawnObject)
	pawnObject = newPawnObject
end

local function getPawn()
	return pawnObject or pawn
end

-- The pawn's RootComponent. After a level load UObjectHook.exists() rejects the fresh pawn's root for
-- 0-20+ s (deferred adoption on this backend), which made rig creation fail ("No RootComponent on pawn")
-- and the per-tick placement skip, so the arms appeared long after the level. The pawn itself validates,
-- so read its current root directly when exists() refuses it.
local function getPawnRootComponent()
	local p = getPawn()
	local root = uevrUtils.getValid(p, {"RootComponent"})
	if root == nil and uevrUtils.getValid(p) ~= nil then
		pcall(function() root = p.RootComponent end)
	end
	return root
end

-- handle script resets to cleanup components we created
uevr.params.sdk.callbacks.on_script_reset(function()
	M.destroyAll()
end)

uevrUtils.registerPreLevelChangeCallback(function(level)
	M.print("Pre level change detected, cleaning up IK rigs...")
	M.destroyAll()
end)


local status = {}
local autoCreateArms = true

-- Liveness without UEVR_UObjectHook.exists(): on this backend a freshly created rig mesh is not adopted
-- for seconds, and uevrUtils.getValid() returned nil for it every tick ("SolveVRArmIK: Mesh is not
-- valid" x236) so the solver never ran. Never gate lib-owned, just-created components on exists().
-- Declared up here because Rig:create()/updateBonesVisibility() above the solver code use it.
local function isMeshAlive(mesh)
	if mesh == nil or type(mesh) ~= "userdata" then return false end
	local ok, r = pcall(function() return mesh:get_full_name() ~= nil end)
	return ok and r
end

-- Bone names reach the *ByName UFunctions as Lua strings all over this file. The backend marshals a string
-- to FName through the FName constructor, which is unresolved on The Outer Worlds 2, so every such call
-- silently operated on bone "None" (zero locations, no-op writes). Convert through Conv_StringToName
-- (uevrUtils.fname_from_string) instead, cached per name; FName userdata passes straight through.
local boneFNameCache = {}
local function toBoneFName(name)
	if type(name) ~= "string" then return name end
	local f = boneFNameCache[name]
	if f == nil then
		f = uevrUtils.fname_from_string(name)
		boneFNameCache[name] = f
	end
	return f
end
--local useCustomInstance = false
local meshCreatedCallbackList = {}
local instanceDestroyedCallbackList = {}
-- function M.setUseCustomIKComponentInstance(val)
-- 	useCustomInstance = val
-- end

local isDeveloperMode = false
local gunstockRotation = uevrUtils.rotator(0,0,0)
local gunstockOffsetsEnabled = false
function M.setGunstockOffsetsEnabled(val)
	gunstockOffsetsEnabled = val
end

local currentLogLevel = LogLevel.Error
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
	if logLevel == nil then logLevel = LogLevel.Debug end
	if logLevel <= currentLogLevel then
		uevrUtils.print("[ik] " .. text, logLevel)
	end
end

local function ProjectVectorOnToPlane(vec, planeNormal)
	if kismet_math_library.ProjectVectorOnToPlane ~= nil then
        return kismet_math_library:ProjectVectorOnToPlane(vec, planeNormal)
    else
        if vec == nil then return uevrUtils.vector(0,0,0) end
			if planeNormal == nil then return vec end

			-- Prefer engine helpers if present
			if kismet_math_library.Subtract_VectorVector then
				local dotVN = mathLib.vectorDot(vec, planeNormal) or 0.0
				local denom = mathLib.vectorDot(planeNormal, planeNormal) or 0.0
				if denom <= 1e-8 then return uevrUtils.vector(0,0,0) end
				local scale = dotVN / denom
				local comp = planeNormal * scale
				return kismet_math_library:Subtract_VectorVector(vec, comp)
			end
			-- Fallback: plain numeric vectors (supports {X,Y,Z} or array)
			local vx = vec.X or vec[1] or 0
			local vy = vec.Y or vec[2] or 0
			local vz = vec.Z or vec[3] or 0
			local nx = planeNormal.X or planeNormal[1] or 0
			local ny = planeNormal.Y or planeNormal[2] or 0
			local nz = planeNormal.Z or planeNormal[3] or 0
			local dotVN = vx*nx + vy*ny + vz*nz
			local denom = nx*nx + ny*ny + nz*nz
			if denom <= 1e-8 then return uevrUtils.vector(0,0,0) end
			local s = dotVN / denom
			--if MakeVector doesnt work try FVector Conv_FloatToVector(float InFloat); and then change the individual params
			return kismet_math_library:MakeVector(vx - nx*s, vy - ny*s, vz - nz*s)
	end
end

local ikConfigDev = nil
local parametersFileName = "ik_parameters"
local parameters = {
	mesh = "",
    animation_mesh = "",
	show_debug_meshes = false,
	debug_sphere_jointTarget = true,
	debug_sphere_effector = true,
	debug_sphere_solvedElbow = true,
	debug_sphere_solvedEnd = true,
	debug_sphere_desiredPole = true,
	debug_sphere_boneElbow = true,
	debug_sphere_boneTwist = true,
	debug_sphere_forearmTwist = true,
    mesh_location_offset = uevrUtils.vector(0,0,0),
    mesh_rotation_offset = uevrUtils.rotator(0,0,0),
    mesh_scale_offset = uevrUtils.vector(1,1,1),
    animation_location_offset = uevrUtils.vector(0,0,0),
    animation_rotation_offset = uevrUtils.rotator(0,0,0),
	animation_ik_pose_authoritative = false,
	solvers = {},
}
local paramManager = paramModule.new(parametersFileName, parameters, true)
paramManager:load(true)

--TODO ParamManager now handles nested table keys like {"channels", 5} so we don't need to handle it here
--Should be able to use just the last line of the function and remove the other code
local function setParameter(key, value, persist)
	local activeProfile = paramManager:getActiveProfile()
	if activeProfile == nil then return end
	if type(key) == "table" then
		local fullKey = {activeProfile}
		for _, k in ipairs(key) do
			table.insert(fullKey, k)
		end
		return paramManager:set(fullKey, value, persist)
	end
	return paramManager:set({activeProfile, key}, value, persist)
end

local function saveParameter(key, value, persist)
	--paramManager:set(key, value, persist)
    setParameter(key, value, persist)
end

local function getParameter(key)
    return paramManager:get(key)
end

local Rig = {}
Rig.__index = Rig

local UKismetAnimationLibrary = nil
local accessoryStatus = {}

local safeNormalize

local IK_MIN_SWING_DEG = 0.02
local IK_MIN_TWIST_DEG = 0.02
local ALIGN_SWING_DEADBAND_DEG = 0.0
local enableScopeStability = true

uevrUtils.registerUEVRCallback("scope_active_change", function(isActive)
	if enableScopeStability then
		ALIGN_SWING_DEADBAND_DEG = isActive and 0.6 or 0.0
	end
end)

local FOREARM_TWIST_MAX_DEG_DEFAULT = 100.0
local FIRST_TWIST_BONE_WRIST_SWING_ALPHA = 0.18
local _reuseWristSwingQuat = { X = 0.0, Y = 0.0, Z = 0.0, W = 1.0 }

local function mulVec(v, s)
	return mathLib.vectorMultiply(v, s)
end

local function vsize(v)
	return mathLib.vectorSize(v)
end

local function normalizeDeg180(angleDeg)
	return mathLib.normalizeDeg180(angleDeg)
end

-- Unwrap an angle to be continuous vs a previous sample.
-- Keeps the returned value within +/-180 of prevAngleDeg.
local function unwrapDeg(angleDeg, prevAngleDeg)
	return mathLib.unwrapDeg(angleDeg, prevAngleDeg)
end

-- Module-level constants (allocated once, never mutated).
local VEC_UNIT_Y     = nil  -- uevrUtils.vector(0,1,0) initialised on first use after kismet is live
local VEC_UNIT_Y_FORWARD     = nil  -- uevrUtils.vector(0,1,0) initialised on first use after kismet is live
local VEC_UNIT_Y_INVERSE     = nil  -- uevrUtils.vector(0,-1,0) initialised on first use after kismet is live

-- Minimal IK state: baseline elbow direction for a stable pole.
local function newIKState()
	return {
		baselineElbowDirCS = nil,
		shoulderPoleAxisChoice = nil,
		shoulderPoleAxisForBones = nil,
		jointPoleAxisChoice = nil,
		jointPoleAxisForBones = nil,
		composeOrderSwing = nil,   -- legacy shared cache (kept for compatibility)
		composeOrderTwist = nil,   -- legacy shared cache (kept for compatibility)
		composeOrderSwingShoulder = nil,
		composeOrderTwistShoulder = nil,
		composeOrderSwingElbow = nil,
		composeOrderTwistElbow = nil,
		twistBoneVecs = nil,       -- per-bone: { x, z } axes stored in lower-arm local space at F2 capture time
		lastCtrlPoleCS = nil,      -- for stable pole twist coupling
		-- Cached per-mesh constants.
		-- NOTE: compToWorld and meshRightVec are NOT cached they change every tick as the pawn rotates.
		upperLen = nil,            -- upper arm bone length         skeleton constant
		lowerLen = nil,            -- lower arm bone length         skeleton constant
		bonesKey = nil,            -- JointBone.."->"..EndBone      never changes per call site
		-- Smoothed controller target offset in component space (from shoulder).
		lastEffectorOffsetCS = nil,
		-- Smoothed IK direction vectors and pole suppress per-tick numerical noise that drives
		-- micro-oscillation in the alignment twist correction.
		smUpperDirCS = nil,
		smLowerDirCS = nil,
		smPoleCS = nil,
		lastShoulderCompRot = nil, -- cached per-tick; used to suppress animation override passthrough
		lastControllerRotWS = nil, -- smoothed WS controller rotation; used to compute compToWorld-independent EndBone WS stamp
		-- Last measured forearm tube twist (degrees), unwrapped for continuity.
		--lastForearmTwistDegUnwrapped = nil,
		-- Last applied forearm tube twist (degrees).
		--lastForearmTwistDegApplied = nil,
	}
end

local function executeIsHiddenCallback(...)
	return uevrUtils.executeUEVRCallbacksWithPriorityBooleanResult("is_hands_hidden", table.unpack({...}))
end

function M.new(options)
    options = options or {}
    local rigId = options.rigId or paramManager:getActiveProfile()
    local rigParams = rigId and paramManager:get(rigId) or nil
    local enhancedStabilization = rigParams ~= nil and rigParams.enhanced_stabilization == true
    local self = setmetatable({
		tickPhase = enhancedStabilization and "post" or (options.tickPhase or "pre"),
		tickPriority = options.tickPriority,
		enhancedStabilization = enhancedStabilization,
		rigId = rigId,
		orderedSolvers = nil,
		solverOrderDirty = true,

    }, Rig)

	if options.animationsFile ~= nil then
		self:setAnimationsFromHandsParametersFile(options.animationsFile)
	end

	if not self:create() then -- auto-create component
		return nil
	end

	self.liveUpdateFn = function(key, value, persist)
		local activeRigId = paramManager:getActiveProfile()
		if self.rigId ~= nil and activeRigId ~= nil and self.rigId == activeRigId then
			-- on_ik_config_param_change is raised synchronously from configui widget callbacks, i.e. from
			-- on_draw_ui (UEVR's draw thread). setConfigParameter can destroy/recreate rig components
			-- (parent_type, hide_body, mesh...), and on some games (The Outer Worlds 2) component
			-- destruction requested off the game thread is silently dropped -> leaked live meshes.
			-- Defer to the next engine tick; uevrUtils.setTimeout is serviced from on_pre_engine_tick.
			uevrUtils.setTimeout(1, function()
				if isRegisteredInstance(self) then
					self:setConfigParameter(key, value, persist)
				end
			end)
		end
	end

	--live update of ui config changes from ik_config_dev
	uevrUtils.registerUEVRCallback("on_ik_config_param_change", self.liveUpdateFn)

	--see if montage or other systems have triggered hide hands
	self.hideIntervalTimer = uevrUtils.setInterval(200, function()
		local isHidden, priority = executeIsHiddenCallback()
		if isHidden ~= self.wasHidden then
			self.wasHidden = isHidden
			self:hide(isHidden or false)
		end
	end)

	registerInstance(self)

    return self
end


local function executeIsAnimatingFromMeshCallback(...)
	return uevrUtils.executeUEVRCallbacksWithPriorityBooleanResult("is_hands_animating_from_mesh", table.unpack({...}))
end

local function getRigParams(rigId)
	if rigId == nil then return nil end
	return paramManager:get(rigId)
end

local function getSolverParams(rigId, solverId)
	if rigId == nil or solverId == nil then return nil end
	return paramManager:get({rigId, "solvers", solverId})
end

local function getControllerTarget(hand, controller)
	local loc = nil
	local rot = nil
	if isMeshAlive(controller) and controller.K2_GetComponentLocation ~= nil then -- not getValid(): a fresh lib-created controller fails exists() for seconds after a load
		loc = controller:K2_GetComponentLocation()
		rot = controller:K2_GetComponentRotation()
		--TODO hard coded for right handed weapon holding. Add left support
		if rot ~= nil and hand == Handed.Right and gunstockOffsetsEnabled == true then
			--rotate the worldspace controller rotation but the gunstock local space offset
			rot = kismet_math_library:ComposeRotators(gunstockRotation, rot)
		end

		-- local collisionLoc = collision.getLocation(hand == Handed.Right and "right_hand" or "left_hand")
		-- if collisionLoc ~= nil then
		-- 	loc = collisionLoc
		-- end
	end
	return loc, rot
end

local function getAccessoryTarget(handStatus)
	local loc = nil
	local rot = nil
	if uevrUtils.getValid(handStatus.parentAttachment) ~= nil then
		if handStatus.parentAttachment.GetSocketLocation == nil then
			print("IK accessory parent attachment has no GetSocketLocation:", handStatus.parentAttachment:get_full_name())
		else
			loc = handStatus.parentAttachment:GetSocketLocation(uevrUtils.fname_from_string(handStatus.socketName or ""))
			rot = handStatus.parentAttachment:GetSocketRotation(uevrUtils.fname_from_string(handStatus.socketName or ""))
			if loc ~= nil and rot ~= nil and handStatus.loc ~= nil and handStatus.rot ~= nil then
				local offsetPos = uevrUtils.vector(handStatus.loc) or uevrUtils.vector(0,0,0)
				local offsetRot = uevrUtils.rotator(handStatus.rot) or uevrUtils.rotator(0,0,0)

				loc = loc + mathLib.vectorRotate(offsetPos, rot)
				rot = kismet_math_library:ComposeRotators(offsetRot, rot)
			end
		end
	end
	return loc, rot
end

-- Blended accessory attach/detach (Stalker 2 IK port, 2026-10-04): the target eases between the
-- controller and the accessory socket instead of snapping, the IK equivalent of the glove
-- hands.attachHandToMeshBlended / attachHandToControllerBlended. Both ends are re-read every tick, so
-- a moving weapon or controller never makes the hand chase a stale point.
local function getBlendAlpha(handStatus)
	if handStatus.blendTime == nil or handStatus.blendTime <= 0 then return 1 end
	local alpha = math.min((handStatus.blendElapsed or 0) / handStatus.blendTime, 1)
	return alpha * alpha * (3 - 2 * alpha) -- smoothstep
end

local getAccessoryBlendTarget -- defined below
local function getTargetLocationAndRotation(hand, controller)
	local handStatus = accessoryStatus[hand]
	if handStatus == nil then
		return getControllerTarget(hand, controller)
	end
	return getAccessoryBlendTarget(hand, controller, handStatus)
end

getAccessoryBlendTarget = function(hand, controller, handStatus)
	-- An attach parent that does not validate (freed, or a fresh weapon not adopted yet) falls back to
	-- the controller: returning nil here skips the solve and freezes the arm in place.
	local loc, rot = getAccessoryTarget(handStatus)
	if loc == nil or rot == nil then
		return getControllerTarget(hand, controller)
	end

	local alpha = getBlendAlpha(handStatus)
	if handStatus.releasing then alpha = 1 - alpha end
	if alpha < 1 then
		local cLoc, cRot = getControllerTarget(hand, controller)
		if cLoc ~= nil and cRot ~= nil then
			-- Written into the engine-returned socket vector in place: a fresh uevrUtils.vector() target put
			-- the solved hand ~95 cm off its target on every blend frame (ik_target_trace 2026-10-04), while
			-- the engine's own return values solve correctly.
			loc.X = cLoc.X + (loc.X - cLoc.X) * alpha
			loc.Y = cLoc.Y + (loc.Y - cLoc.Y) * alpha
			loc.Z = cLoc.Z + (loc.Z - cLoc.Z) * alpha
			rot = kismet_math_library:RLerp(cRot, rot, alpha, true)
		end
	end
	return loc, rot
end

local function executeGetCustomAnimationInitialTransformCallback(...)
	return uevrUtils.executeUEVRCallbacks("get_custom_animation_initial_transform", table.unpack({...}))
end
function M.registerGetCustomAnimationInitialTransformCallback(func)
	uevrUtils.registerUEVRCallback("get_custom_animation_initial_transform", func)
end

-- When CopyPose animation ends, optionally snap all bones back to the transforms captured
-- when the solver was activated. Some games need this; others snap/distort if it runs.
local setInitialTransformOnAnimationCompleteEnabled = true
local function executeIsSetInitialTransformOnAnimationCompleteEnabledCallback(...)
	return uevrUtils.executeUEVRCallbacksWithPriorityBooleanResult("is_set_initial_transform_on_animation_complete_enabled", table.unpack({...}))
end
function M.setInitialTransformOnAnimationCompleteEnabled(val)
	setInitialTransformOnAnimationCompleteEnabled = val == true
end
function M.registerIsSetInitialTransformOnAnimationCompleteEnabledCallback(func)
	uevrUtils.registerUEVRCallback("is_set_initial_transform_on_animation_complete_enabled", func)
end
function Rig:isSetInitialTransformOnAnimationCompleteEnabled()
	local result = select(1, executeIsSetInitialTransformOnAnimationCompleteEnabledCallback())
	if result ~= nil then
		return result
	end
	return setInitialTransformOnAnimationCompleteEnabled
end

-- The animating mesh in a CopyPoseFromSkeletalComponent can set bones we dont want moved to bad values.
-- This function asks the callback for a list of all bones that should be reset to their initial transform after
-- an animation frame. Implement the callback in your main code with a list of bone indexes. You can
-- see the list of available bone indexes by setting M.enableAnimationBoneListPrintout to true after requiring it.
function Rig:setCustomAnimationInitialTransform()
	local customBones = executeGetCustomAnimationInitialTransformCallback()
	if customBones ~= nil and type(customBones) == "table" then
		for i, boneIndex in ipairs(customBones) do
			local entry = self.initialTransforms[boneIndex]
			if entry ~= nil and entry.boneName and entry.transform then
				local f = uevrUtils.fname_from_string(entry.boneName)
				for _, mesh in pairs(self.meshList or {}) do
					mesh:SetBoneTransformByName(f, entry.transform, EBoneSpaces.ComponentSpace)
				end
			end
		end
	end
end

function Rig:setInitialTransform()
	for _, mesh in pairs(self.meshList or {}) do
		local transforms = self.initialTransforms
		if mesh ~= nil and transforms and type(transforms) == "table" then
			--keeping the bones in the same numbered order as the original seems to keep the transforms
			--being applied in the correct order but I dont know if that is always the case
			--Applying them out of order results in a destroyed mesh
			for i, entry in ipairs(transforms) do
				if entry.boneName and entry.transform then
					--print("Re-applying initial transform for bone:", entry.boneName)
					local f = uevrUtils.fname_from_string(entry.boneName)
					mesh:SetBoneTransformByName(f, entry.transform, EBoneSpaces.ComponentSpace)
				end
			end
		end
	end
end

function Rig:setInitialCustomTransform(boneList)
	if boneList ~= nil then
		self.initialCustomBoneList = boneList
	end
	boneList = boneList or self.initialCustomBoneList
	if boneList == nil or type(boneList) ~= "table" then
		return
	end
	self:runInitialCustomTransform()
end

function Rig:runInitialCustomTransform()
	local boneList = self.initialCustomBoneList
	if boneList == nil then
		return
	end
	for _, mesh in pairs(self.meshList or {}) do
		if isMeshAlive(mesh) then
			-- Apply in mesh bone order so parents update before children.
			local boneNames = uevrUtils.getBoneNames(mesh)
			for _, boneName in ipairs(boneNames) do
				local data = boneList[boneName]
				if data ~= nil and data.location ~= nil and data.rotation ~= nil then
					local f = uevrUtils.fname_from_string(boneName)
					local localLoc = uevrUtils.vector(data.location)
					local localRot = uevrUtils.rotator(data.rotation)
					local localScale = uevrUtils.vector(1, 1, 1)
					local localTransform = kismet_math_library:MakeTransform(localLoc, localRot, localScale)
					local parentFName = mesh:GetParentBone(f)
					local componentTransform = localTransform
					if parentFName ~= nil and parentFName:to_string() ~= "None" then
						local parentTransform = mesh:GetBoneTransformByName(parentFName, EBoneSpaces.ComponentSpace)
						componentTransform = kismet_math_library:ComposeTransforms(localTransform, parentTransform)
					end
					mesh:SetBoneTransformByName(f, componentTransform, EBoneSpaces.ComponentSpace)
				end
			end
		end
	end
end

function Rig:updateEnhancedMeshRotation(mesh, rootComponent, lockMeshYawToHmd)
	if not self.enhancedStabilization or mesh == nil or mesh.K2_SetWorldRotation == nil then return end
	local rotation = nil
	if self.coupling == 2 then
		local hmdRot = controllers.getControllerRotation(2)
		if hmdRot ~= nil then
			rotation = kismet_math_library:ComposeRotators(self.meshRotationOffset, hmdRot)
		end
	elseif self.coupling == 1 then
		if lockMeshYawToHmd then
			local hmdRot = controllers.getControllerRotation(2)
			if hmdRot ~= nil then
				rotation = uevrUtils.rotator(0, hmdRot.Yaw + (self.meshRotationOffset.Yaw or 0), 0)
			end
		elseif rootComponent ~= nil then
			local rootRot = rootComponent:K2_GetComponentRotation()
			if rootRot ~= nil then
				rotation = kismet_math_library:ComposeRotators(self.meshRotationOffset, rootRot)
			end
		end
	end
	if rotation ~= nil then
		mesh:K2_SetWorldRotation(rotation, false, reusable_hit_result, false)
	end
end

function Rig:create()
    if UKismetAnimationLibrary == nil then
		UKismetAnimationLibrary = uevrUtils.find_default_instance("Class /Script/AnimGraphRuntime.KismetAnimationLibrary")
	end
	if UKismetAnimationLibrary == nil then
		M.print("Unable to find KismetAnimationLibrary. IK disabled")
		return false
	end
	-- Allocate-once constants: kismet_math_library is guaranteed live by this point.
	if VEC_UNIT_Y     == nil then VEC_UNIT_Y     = uevrUtils.vector(0, 1, 0) end
	if VEC_UNIT_Y_FORWARD     == nil then VEC_UNIT_Y_FORWARD     = uevrUtils.vector(0, 1, 0) end
    if VEC_UNIT_Y_INVERSE     == nil then VEC_UNIT_Y_INVERSE     = uevrUtils.vector(0, -1, 0) end

	local rigParams = getRigParams(self.rigId)

    self.activeSolvers = {}
	self.orderedSolvers = {}
	self.solverOrderDirty = true
	self.coupling = rigParams and rigParams["parent_type"] or 1 -- 1=pawn root, 2=HMD

	if not self:initializeRigState() then
		return false
	end

	-- Register tick callback
	self.tickFn = function(engine, delta)
		-- When body yaw follows a motion controller (RIGHT/LEFT_CONTROLLER), root
		-- Euler yaw is gimbal-noisy. IK meshes parented to root inherit that and
		-- spin; lock mesh world yaw to the HMD instead so solvers stay stable.
		local pawnRotMode = input.getEffectivePawnRotationMode and input.getEffectivePawnRotationMode() or nil
		local lockMeshYawToHmd = pawnRotMode == input.PawnRotationMode.RIGHT_CONTROLLER
			or pawnRotMode == input.PawnRotationMode.LEFT_CONTROLLER

		for _, mesh in pairs(self.meshList or {}) do
			if isMeshAlive(mesh) then
				local rootComponent = getPawnRootComponent()
				if rootComponent ~= nil and mesh.RelativeLocation ~= nil then
					local capsuleHeight = rootComponent.CapsuleHalfHeight or 0
					--print("Capsule height:", capsuleHeight)
					--print(self.coupling)
					if self.coupling == 1 then
						mesh.RelativeLocation.Z = self.meshLocationOffset.Z + capsuleHeight -- offset relative to the capsule TOP (same anchor input.lua uses for the VR camera); the old form added the offset twice, so crouching (half height 96 -> 55) dropped the rig 41 cm too far
					elseif self.coupling == 3 then
						mesh.RelativeLocation.Z = self.meshLocationOffset.Z + capsuleHeight -- see coupling 1
						if not lockMeshYawToHmd then
							mesh:K2_SetWorldRotation(rootComponent:K2_GetComponentRotation(), false, reusable_hit_result, nil)
						end
					end
					if self.enhancedStabilization then
						self:updateEnhancedMeshRotation(mesh, rootComponent, lockMeshYawToHmd)
					end

					if ((self.coupling == 1 and not self.enhancedStabilization) or self.coupling == 3) and mesh.K2_SetWorldRotation ~= nil then
						if lockMeshYawToHmd then
							local hmdRot = controllers.getControllerRotation(2)
							if hmdRot ~= nil then
								if not self.meshYawLockedToHmd and mesh.SetAbsolute ~= nil then
									mesh:SetAbsolute(false, true, false)
								end
								local offsetYaw = (self.meshRotationOffset and self.meshRotationOffset.Yaw) or 0
								mesh:K2_SetWorldRotation(
									uevrUtils.rotator(0, hmdRot.Yaw + offsetYaw, 0),
									false, reusable_hit_result, false
								)
								self.meshYawLockedToHmd = true
							end
						elseif self.meshYawLockedToHmd then
							if mesh.SetAbsolute ~= nil then
								mesh:SetAbsolute(false, false, false)
							end
							if self.meshRotationOffset ~= nil and mesh.K2_SetRelativeRotation ~= nil then
								mesh:K2_SetRelativeRotation(self.meshRotationOffset, false, reusable_hit_result, false)
							elseif self.meshRotationOffset ~= nil and mesh.RelativeRotation ~= nil then
								mesh.RelativeRotation = self.meshRotationOffset
							end
							self.meshYawLockedToHmd = false
						end
					end
				end
			end
		end

        if self.activeSolvers ~= nil then
            local isLeftAnimating = select(1, executeIsAnimatingFromMeshCallback(Handed.Left))
		    local isRightAnimating = select(1, executeIsAnimatingFromMeshCallback(Handed.Right))
            local didAnimate = false
            if (isLeftAnimating or isRightAnimating) then
                didAnimate = self:animateFromMesh()--uevrUtils.getValid(pawn, {"FPVMesh"}))
				if didAnimate == true then
					self:setCustomAnimationInitialTransform()
				end
            end
            if didAnimate == false then
                if self.wasAnimating then
					if self:isSetInitialTransformOnAnimationCompleteEnabled() then
                    	self:setInitialTransform()
					end
					self:runInitialCustomTransform()
                    self.wasAnimating = false
                end
            end

			-- Authoritative: always solve (AH). Otherwise: only when not animating (TOW).
			if self.animationIKPoseAuthoritative or didAnimate == false then
				self:syncShouldersToFullBody()
				self:rebuildOrderedSolversIfNeeded()
				for _, solverEntry in ipairs(self.orderedSolvers or {}) do
					local activeParams = solverEntry.params
					if activeParams and activeParams.solverType == M.SolverType.TWO_BONE then
						self:solveTwoBone(activeParams)
					end
				end
			end
        end
	end
	if self.tickPhase == "pre" then
		uevrUtils.registerPreEngineTickCallback(self.tickFn, self.tickPriority)
	elseif self.tickPhase == "post" then
		uevrUtils.registerPostEngineTickCallback(self.tickFn, self.tickPriority)
	else
		setInterval(50, self.tickFn)
	end

	--get solvers from params and find any that have the active param = true
	if rigParams ~= nil then
		local solvers = rigParams.solvers
		if solvers ~= nil then
			for solverId, solverParams in pairs(solvers) do
				self:setActive(solverId, solverParams.active)
			end
		end
	end

	--do this late so solvers have time to be created
	for _, callback in ipairs(meshCreatedCallbackList) do
		callback(self.meshList, self)
	end

	return true
end

-- Full body (Stalker 2, 2026-10-05, stalker2/ik_full_body.lua): while a source mesh is set (the game's own animated
-- body, shown with its arms hidden), the rig's clavicles are put exactly where the source's are, in world space,
-- before the arm solve. The IK arms then start at the visible body's shoulders - no seam - and the rig keeps its own
-- finger poses (copying the whole pose every tick would wipe them).
local fullBodySourceFn = nil
function M.setFullBodySource(fn)
	fullBodySourceFn = fn
end

-- Optional per-tick shoulder offset for full body (Hellraiser 2026-10-08: the game body's shoulders are narrower than
-- the player's real ones). fn() -> width, forward, up in cm: each clavicle is pushed `width` outward along the line
-- between the two source clavicles, `forward` along the source mesh owner's forward vector, `up` along world Z.
local fullBodyShoulderOffsetFn = nil
function M.setFullBodyShoulderOffset(fn)
	fullBodyShoulderOffsetFn = fn
end

-- Optional per-tick filter for the full-body clavicles (Stalker 2 2026-10-12: the unarmed walk / jump animation
-- swings the body's shoulders, and the IK arms bobbed with them). fn(index, worldTransform, source) -> world
-- transform to use instead (nil = unchanged); index 1 = left, 2 = right. Runs before the shoulder offset.
local fullBodyShoulderFilterFn = nil
function M.setFullBodyShoulderFilter(fn)
	fullBodyShoulderFilterFn = fn
end

function Rig:syncShouldersToFullBody()
	if fullBodySourceFn == nil then return end
	local source = fullBodySourceFn()
	if source == nil then return end
	local sides = {}
	for i, key in ipairs({"left_shoulder_bone_name", "right_shoulder_bone_name"}) do
		local boneName = getParameter({self.rigId, key})
		if boneName ~= nil and boneName ~= "" then
			local boneFName = toBoneFName(boneName)
			pcall(function()
				sides[i] = { fname = boneFName, transform = source:GetSocketTransform(boneFName, 0) } -- RTS_World
			end)
		end
	end

	if fullBodyShoulderFilterFn ~= nil then
		for i = 1, 2 do
			if sides[i] ~= nil then
				local ok, filtered = pcall(fullBodyShoulderFilterFn, i, sides[i].transform, source)
				if ok and filtered ~= nil then sides[i].transform = filtered end
			end
		end
	end

	local width, forward, up = 0, 0, 0
	if fullBodyShoulderOffsetFn ~= nil then
		local ok, w, f, u = pcall(fullBodyShoulderOffsetFn)
		if ok then width, forward, up = w or 0, f or 0, u or 0 end
	end
	if (width ~= 0 or forward ~= 0 or up ~= 0) and sides[1] ~= nil and sides[2] ~= nil then
		pcall(function()
			local l, r = sides[1].transform.Translation, sides[2].transform.Translation
			local dx, dy, dz = r.X - l.X, r.Y - l.Y, r.Z - l.Z
			local len = math.sqrt(dx * dx + dy * dy + dz * dz)
			if len < 0.01 then return end
			dx, dy, dz = dx / len, dy / len, dz / len -- left -> right
			local fwd = { X = 0, Y = 0, Z = 0 }
			if forward ~= 0 then
				local owner = source:GetOwner()
				local v = owner and owner:GetActorForwardVector()
				if v ~= nil then fwd = { X = v.X, Y = v.Y, Z = v.Z } end
			end
			for i, s in ipairs({ -1, 1 }) do -- left moves -lateral, right +lateral
				local t = sides[i].transform.Translation
				sides[i].transform.Translation = uevrUtils.vector(
					t.X + dx * width * s + fwd.X * forward,
					t.Y + dy * width * s + fwd.Y * forward,
					t.Z + dz * width * s + fwd.Z * forward + up)
			end
		end)
	end

	for i = 1, 2 do
		local side = sides[i]
		if side ~= nil then
			pcall(function()
				for _, mesh in pairs(self.meshList or {}) do
					if isMeshAlive(mesh) then
						mesh:SetBoneTransformByName(side.fname, side.transform, EBoneSpaces.WorldSpace)
					end
				end
			end)
		end
	end
end

function Rig:initializeRigState()
	if self.meshList ~= nil then
		for _, mesh in pairs(self.meshList) do
			uevrUtils.destroyComponent(mesh, true, false) -- not the children, see M.destroy
		end
		self.meshList = nil
	end
	self.meshList = {}

	local rootComponent = getPawnRootComponent()
	if rootComponent == nil then
		M.print("Rig:initializeRigState: No RootComponent on pawn")
		return false
	end

	local meshName = getParameter({self.rigId, "mesh"})
	self.meshTemplates = {}
	if meshName == "Custom" then
		-- if useCustomInstance == false then
			if getCustomIKComponent ~= nil then
				local templates = getCustomIKComponent(self.rigId)
				if type(templates) ~= "table" then
					templates = {{descriptor = templates}}
				end
				self.meshTemplates = templates
				-- for i, descriptor in ipairs(meshDescriptors) do
				-- 	table.insert(meshTemplates, uevrUtils.getObjectFromDescriptor(descriptor))
				-- end
			end
		-- else
		-- 	if getCustomIKComponentInstance ~= nil then
		-- 		self.meshList = getCustomIKComponentInstance(self.rigId)
		-- 		if self.meshList == nil then self.meshList = {} end
		-- 		if type(self.meshList) ~= "table" then
		-- 			self.meshList = {self.meshList}
		-- 		end
		-- 	end
		-- end
	else
		self.meshTemplates = {{descriptor = meshName}}
	end

	for _, meshTemplate in pairs(self.meshTemplates) do
		if meshTemplate.instance == nil and meshTemplate.descriptor then
			meshTemplate.instance = uevrUtils.getObjectFromDescriptor(meshTemplate.descriptor, false)
		end
	end

--	if meshTemplates ~= nil then
		--local capsuleHeight = rootComponent.CapsuleHalfHeight or 0 --should be used here but the tick handles it so whatever
		self.meshLocationOffset = getParameter({self.rigId, "mesh_location_offset"}) and uevrUtils.vector(getParameter({self.rigId, "mesh_location_offset"})) or uevrUtils.vector(0,0,0)
		self.meshRotationOffset = getParameter({self.rigId, "mesh_rotation_offset"}) and uevrUtils.rotator(getParameter({self.rigId, "mesh_rotation_offset"})) or uevrUtils.rotator(0,0,0)
		self.meshScaleOffset = getParameter({self.rigId, "mesh_scale_offset"}) and uevrUtils.vector(getParameter({self.rigId, "mesh_scale_offset"})) or uevrUtils.vector(1,1,1)
		for _, meshTemplate in pairs(self.meshTemplates) do
			--print("Creating mesh from template:", meshTemplate)
			local mesh = uevrUtils.createPoseableMeshFromSkeletalMesh(meshTemplate.instance, {useDefaultPose = true, showDebug=false})
			if mesh ~= nil then
				table.insert(self.meshList, mesh)
				meshTemplate.mesh = mesh
				if self.coupling == 1 or self.coupling == 3 then
					mesh:K2_AttachTo(rootComponent, uevrUtils.fname_from_string(""), 0, false)
				elseif self.coupling == 2 then
					if self.enhancedStabilization then
						local hmdController = controllers.getController(2, true) or controllers.createController(2)
						if hmdController ~= nil then
							mesh:K2_AttachTo(hmdController, uevrUtils.fname_from_string(""), 0, false)
						end
					else
						local springArm = uevrUtils.create_component_of_class("Class /Script/Engine.SpringArmComponent")
						if springArm ~= nil then
							if self.springArmList == nil then self.springArmList = {} end
							table.insert(self.springArmList, springArm)
							springArm.TargetArmLength = 0
							springArm.bEnableCameraRotationLag = true
							springArm.CameraRotationLagSpeed = 10.0
							springArm.bUsePawnControlRotation = false
							controllers.attachComponentToController(2, springArm, "", 0, false, true)
							mesh:K2_AttachTo(springArm, uevrUtils.fname_from_string(""), 0, false)
						end
					end
				end

				mesh:SetVisibility(true, true)
				mesh:SetHiddenInGame(false, true)
				mesh.BoundsScale = 16.0

				mesh.RelativeLocation = self.meshLocationOffset
				mesh.RelativeRotation = self.meshRotationOffset
				mesh.RelativeScale3D = self.meshScaleOffset
				if (self.coupling == 1 or self.coupling == 2) and self.enhancedStabilization and mesh.SetAbsolute ~= nil then
					-- Preserve the selected parent's translation without inheriting its later rotation.
					mesh:SetAbsolute(false, true, false)
					self:updateEnhancedMeshRotation(mesh, rootComponent, false)
				end
			else
				if meshTemplate.optional ~= true then
					M.print("Failed to initializeRigStat because required mesh is could not be created")
					return false
				end
			end
		end
--	end

	self.showDebugMeshes = getParameter({self.rigId, "show_debug_meshes"})
	if self.showDebugMeshes == true then
		self:createDebugMeshes()
	end

	self:updateBonesVisibility()
	-- A freshly created PoseableMeshComponent re-initialises its bone arrays on its first tick(s), which
	-- wipes bone writes made in the creation frame (seen on The Outer Worlds 2, UE 5.5). Re-apply the
	-- body-hiding scales once the component has settled. Not gated on getValid(): UObjectHook.exists()
	-- is false for just-created objects on that backend.
	for _, delayMs in ipairs({100, 600, 1500, 3000}) do
		uevrUtils.setTimeout(delayMs, function()
			if isRegisteredInstance(self) then
				self:updateBonesVisibility()
			end
		end)
	end

	--This is the hands animation system for weapons grips etc
	self:initHandAnimations(self.meshTemplates)

	--This is the animInstance animation system handling
	local animationMeshName = getParameter({self.rigId, "animation_mesh"})
	local animationMesh = nil
	if animationMeshName == "Custom" then
		if getCustomAnimationIKComponent ~= nil then
			animationMesh = getCustomAnimationIKComponent(self.rigId)
		end
	else
		animationMesh = uevrUtils.getObjectFromDescriptor(animationMeshName, false)
	end
	self.animationMesh = animationMesh
	self.animationIKPoseAuthoritative = getParameter({self.rigId, "animation_ik_pose_authoritative"})
	self.animationLocationOffset = getParameter({self.rigId, "animation_location_offset"}) and uevrUtils.vector(getParameter({self.rigId, "animation_location_offset"})) or uevrUtils.vector(0,0,0)
	self.animationRotationOffset = getParameter({self.rigId, "animation_rotation_offset"}) and uevrUtils.rotator(getParameter({self.rigId, "animation_rotation_offset"})) or uevrUtils.rotator(0,0,0)

	return true
end

function Rig:updateBonesVisibility()
	local hideBody = getParameter({self.rigId, "hide_body"})
	local shoulderWidthScale = getParameter({self.rigId, "shoulder_width_scale"}) or 1.0
	local spineBoneName = getParameter({self.rigId, "spine_bone_name"}) or ""
	local leftShoulderBoneName = getParameter({self.rigId, "left_shoulder_bone_name"}) or ""
	local rightShoulderBoneName = getParameter({self.rigId, "right_shoulder_bone_name"}) or ""
	if hideBody then
		if spineBoneName ~= "" and leftShoulderBoneName ~= "" and rightShoulderBoneName ~= "" then
			for i, meshComponent in ipairs(self.meshList or {}) do
				meshComponent:SetBoneScaleByName(meshComponent:GetBoneName(0), uevrUtils.vector(1,1,1), EBoneSpaces.ComponentSpace)
				--scale the skeleton from the root to 0, then make the spine scale only in the z direction so shoulder width can be 
				--adjusted, then make the shoulders full scale so everything after the shoulders is visible
				meshComponent:SetBoneScaleByName(meshComponent:GetBoneName(0), uevrUtils.vector(0.001,0.001,0.001), EBoneSpaces.ComponentSpace)
				meshComponent:SetBoneScaleByName(uevrUtils.fname_from_string(spineBoneName), uevrUtils.vector(0.001,0.001, shoulderWidthScale), EBoneSpaces.ComponentSpace)
				meshComponent:SetBoneScaleByName(uevrUtils.fname_from_string(leftShoulderBoneName), uevrUtils.vector(1,1,1), EBoneSpaces.ComponentSpace)
				meshComponent:SetBoneScaleByName(uevrUtils.fname_from_string(rightShoulderBoneName), uevrUtils.vector(1,1,1), EBoneSpaces.ComponentSpace)
			end
		end
	else
		for i, meshComponent in ipairs(self.meshList or {}) do
			meshComponent:SetBoneScaleByName(meshComponent:GetBoneName(0), uevrUtils.vector(1,1,1), EBoneSpaces.ComponentSpace)
			-- if spineBoneName ~= "" then
			-- 	meshComponent:SetBoneScaleByName(uevrUtils.fname_from_string(spineBoneName), uevrUtils.vector(1,1,1), EBoneSpaces.ComponentSpace)
			-- end
		end
	end
end


function Rig:setRootBoneRotation(rotator)
	if self.meshList == nil then return end
	for _, mesh in pairs(self.meshList or {}) do
		if isMeshAlive(mesh) and mesh.SetBoneRotationByName ~= nil then
			mesh:SetBoneRotationByName(uevrUtils.fname_from_string("Root"), rotator, 1)
		end
	end
end

function Rig:animateFromMesh()
	if self.animationMesh == nil then
		M.print("Rig:animateFromMesh: No animation mesh found")
		return false
	end
	local didAnimate = false
	for _, mesh in pairs(self.meshList or {}) do
		local success, response = pcall(function()
			mesh:CopyPoseFromSkeletalComponent(self.animationMesh)
			didAnimate = true
			self.wasAnimating = true
		end)
		if success == false then
			M.print("Rig:animateFromMesh:" .. response, LogLevel.Error)
		end

		-- In some games the animation moves the skeleton by an offset (probably so they are more visible in the 2D screen)
		-- but we dont want this offset in VR so we correct it here
		if self.animationRotationOffset ~= nil and  self.animationRotationOffset.Pitch ~= 0 or self.animationRotationOffset.Yaw ~= 0 or self.animationRotationOffset.Roll ~= 0 or self.animationLocationOffset.X ~= 0 or self.animationLocationOffset.Y ~= 0 or self.animationLocationOffset.Z ~= 0 then
			local rootName = uevrUtils.fname_from_string(self.rootBone)
			--adding rotators would normally be bad but since its just an offset determined by UI it works here
			local rot = mesh:GetBoneRotationByName(toBoneFName(rootName), EBoneSpaces.ComponentSpace) + self.animationRotationOffset
			--local loc = activeParams.mesh:GetBoneLocationByName(toBoneFName(rootName), EBoneSpaces.ComponentSpace) + activeParams.animationLocationOffset -- this doesnt work, the get returns world space
			-- base location of root should be 0,0,0 in component space so this should work as an offset
			local loc = self.animationLocationOffset
			mesh:SetBoneRotationByName(toBoneFName(rootName), rot, EBoneSpaces.ComponentSpace)
			mesh:SetBoneLocationByName(toBoneFName(rootName), loc, EBoneSpaces.ComponentSpace)
		end
	end

    return didAnimate
end

-- self.meshTemplates = 
-- {
-- 	descriptor = "Pawn.Mesh(Robe)",
-- 	instance = object, --the instance of the descriptor that the game created (the source object)
-- 	mesh = component, -- the poseable mesh copy of instance that we created (the mesh we apply animations to)
-- 	animation = "Arms"
-- }
function Rig:initHandAnimations(meshTemplates)
	if self.animationDefinition == nil or self.animationProfile == nil then
		return
	end
	for key, profileMesh in pairs(self.animationProfile) do
		--key is "Arms", "Gloves", etc
		--look for the best match in meshTemplates by matching key with the animation parameter in meshTemplates
		local component = nil
		for _, meshTemplate in pairs(meshTemplates or {}) do
			if meshTemplate.animationComponent == nil and meshTemplate.animation == key then
				component = meshTemplate.mesh
				meshTemplate.animationComponent = component
				break
			end
		end
		-- If we couldn't find a match based on the animation parameter, just use the first available mesh that isnt already being used for another animation
		if component == nil then
			for _, meshTemplate in pairs(meshTemplates or {}) do
				if meshTemplate.animationComponent == nil and meshTemplate.animation == nil then
					component = meshTemplate.mesh
					meshTemplate.animationComponent = component
					break
				end
			end
		end

		if component ~= nil then
			for index = Handed.Left , Handed.Right do
				local animID = profileMesh[index==Handed.Left and "Left" or "Right"]["AnimationID"]
				if animID ~= nil then
					handsAnimation.createAnimationHandler(animID, component, self.animationDefinition)
				end
			end
		end
	end
end


function Rig:hide(value)
	--print("Hiding hands in IK:", value)
	for _, mesh in pairs(self.meshList or {}) do
		if isMeshAlive(mesh) then -- not getValid(): meshes added after creation (e.g. prosthetic copies) may not be adopted yet
			mesh:SetVisibility(not value, true)
			--mesh:SetHiddenInGame(value, true)
		end
	end
end

-- allow a full rig table to be defined externally and set all parameters at once
-- TODO vector params are currently not being reflected in the json
function Rig:setParameters(params, persist)
	if type(params) ~= "table" then
		return
	end

	local rigId = self.rigId or paramManager:getActiveProfile() or "default"

	-- New schema: single rig payload passed directly.
    if persist then
        paramManager:createProfile(rigId, params.label or "Rig")
        paramManager:setActiveProfile(rigId)
    end
    for key, value in pairs(params) do
        if key ~= "label" then
            paramManager:set({rigId, key}, value, persist)
        end
    end

end


local function isRigLevelParam(paramName)
	return paramName == "mesh"
		or paramName == "mesh_location_offset"
		or paramName == "mesh_rotation_offset"
		or paramName == "mesh_scale_offset"
		or paramName == "animation_mesh"
		or paramName == "animation_location_offset"
		or paramName == "animation_rotation_offset"
		or paramName == "animation_ik_pose_authoritative"
		or paramName == "show_debug_meshes"
		or paramName == "parent_type"
		or paramName == "enhanced_stabilization"
		or paramName == "spine_bone_name"
		or paramName == "left_shoulder_bone_name"
		or paramName == "right_shoulder_bone_name"
		or paramName == "shoulder_width_scale"
		or paramName == "hide_body"
		or (type(paramName) == "string" and string.sub(paramName, 1, 13) == "debug_sphere_")
end

-- K2_GetComponentToWorld is not exposed on this game's SceneComponent (The Outer Worlds 2, UE 5.5), so the
-- component transform is composed from the location/rotation/scale getters when the K2 call is missing.
local function getComponentToWorld(component)
	if component == nil then return nil end
	if component.K2_GetComponentToWorld ~= nil then
		return component:K2_GetComponentToWorld()
	end
	if component.K2_GetComponentLocation == nil or component.K2_GetComponentRotation == nil then return nil end
	local loc = component:K2_GetComponentLocation()
	local rot = component:K2_GetComponentRotation()
	local scale = component.K2_GetComponentScale ~= nil and component:K2_GetComponentScale() or uevrUtils.vector(1, 1, 1)
	if loc == nil or rot == nil then return nil end
	return kismet_math_library:MakeTransform(loc, rot, scale)
end

local function getAncestorBones(mesh, boneName, generations)
    if mesh == nil or boneName == nil or generations == nil then
        return {}
    end
    local ancestors = {}
    -- GetParentBone takes an FName. Passing the Lua string relied on the backend's FName constructor,
    -- which is unresolved on The Outer Worlds 2 (every string-marshalled FName became "None", so the
    -- solver logged "Using bones r_hand_JNT, None, None" and never solved). Convert explicitly.
    local currentBone = type(boneName) == "string" and uevrUtils.fname_from_string(boneName) or boneName
    for i = 1, generations do
        local parentBone = mesh:GetParentBone(toBoneFName(currentBone))
        if parentBone == nil or parentBone == "" then
            break
        end
        table.insert(ancestors, parentBone:to_string())
        currentBone = parentBone
    end
    return ancestors
end

function Rig:setAnimationsFromHandsParametersFile(animFile)
	if animFile == nil then return end
	if type(animFile) == "string" then
		animFile = json.load_file(animFile .. ".json")
	end
	if animFile == nil then return end

	-- We only use the first animation found here. There is currently no support for multiple animation defintions
	self.animationDefinition = nil
	if animFile["animations"] ~= nil then
		for key, value in pairs(animFile["animations"]) do
			M.print("Found animation: " .. key)
			self.animationDefinition = value
			break
		end
	end

	-- We only use the first profile found here. There is currently no support for multiple profile defintions
	self.animationProfile = nil
	if animFile["profiles"] ~= nil then
		for key, profile in pairs(animFile["profiles"]) do
			M.print("Found profile: " .. key)
			self.animationProfile = profile
			break
		end
	end
end

-- Debug sphere sizes (largest → smallest) so you can tell them apart without colors.
-- Legend is also printed to the log when Show Debug Meshes is enabled.
-- Individual visibility is controlled by debug_sphere_<key> params / IK Dev Config checkboxes.
local IK_DEBUG_SPHERE_DEFS = {
	{ key = "jointTarget",  scale = 0.030 }, -- TwoBoneIK joint/pole target
	{ key = "effector",     scale = 0.040 }, -- hand/controller effector target
	{ key = "solvedElbow",  scale = 0.038 }, -- K2_TwoBoneIK outJoint
	{ key = "solvedEnd",    scale = 0.032 }, -- K2_TwoBoneIK outEnd
	{ key = "desiredPole",  scale = 0.035 }, -- solved elbow + outward tip (pole direction)
	{ key = "boneElbow",    scale = 0.030 }, -- actual joint bone after rotateElbow
	{ key = "boneTwist",    scale = 0.015 }, -- tip along joint bone pole axis (elbow twist)
	{ key = "forearmTwist", scale = 0.011 }, -- tip along first twist-bone axis after twistForearm
}

local IK_DEBUG_POLE_TIP_DIST = 18.0

-- Tip at elbow + outward*dist. Built component-wise so K2_TwoBoneIK out-params
-- and mixed vector types don't break Lua +/* metamethods.
local function makeDebugPoleTipWS(elbowWS, outwardWS)
	if elbowWS == nil or outwardWS == nil then return nil end
	local dir = safeNormalize(outwardWS)
	if dir == nil then return nil end
	local dx = dir.X or dir.x or 0.0
	local dy = dir.Y or dir.y or 0.0
	local dz = dir.Z or dir.z or 0.0
	local ex = elbowWS.X or elbowWS.x or 0.0
	local ey = elbowWS.Y or elbowWS.y or 0.0
	local ez = elbowWS.Z or elbowWS.z or 0.0
	local d = IK_DEBUG_POLE_TIP_DIST
	return uevrUtils.vector(ex + dx * d, ey + dy * d, ez + dz * d)
end

local function createIkDebugSphere(scale)
	local comp = uevrUtils.createStaticMeshComponent("StaticMesh /Engine/EngineMeshes/Sphere.Sphere")
	if comp == nil then return nil end
	comp:SetVisibility(false, true)
	comp:SetVisibility(true, true)
	comp:SetHiddenInGame(true, true)
	comp:SetHiddenInGame(false, true)
	uevrUtils.set_component_relative_transform(comp, nil, nil, {X = scale, Y = scale, Z = scale})
	return comp
end

function Rig:isDebugSphereVisible(key)
	if self.debugSphereVisibility == nil then return true end
	local visible = self.debugSphereVisibility[key]
	if visible == nil then return true end
	return visible == true
end

function Rig:loadDebugSphereVisibility()
	self.debugSphereVisibility = self.debugSphereVisibility or {}
	for _, def in ipairs(IK_DEBUG_SPHERE_DEFS) do
		local value = getParameter({self.rigId, "debug_sphere_" .. def.key})
		self.debugSphereVisibility[def.key] = (value ~= false)
	end
end

function Rig:applyDebugSphereVisibility(key)
	if self.debugVisualizers == nil then return end
	local visible = self:isDebugSphereVisible(key)
	for _, side in pairs(self.debugVisualizers) do
		local comp = side and side[key] or nil
		if comp ~= nil then
			comp:SetVisibility(visible, true)
			comp:SetHiddenInGame(not visible, true)
		end
	end
end

function Rig:applyAllDebugSphereVisibility()
	for _, def in ipairs(IK_DEBUG_SPHERE_DEFS) do
		self:applyDebugSphereVisibility(def.key)
	end
end

function Rig:setDebugSphereVisible(key, visible)
	self.debugSphereVisibility = self.debugSphereVisibility or {}
	self.debugSphereVisibility[key] = (visible == true)
	self:applyDebugSphereVisibility(key)
end

function Rig:destroyDebugMeshes()
	if self.debugVisualizers == nil then
		-- Legacy fields from older builds.
		if self.leftJointTargetVisualizer ~= nil then
			uevrUtils.destroyComponent(self.leftJointTargetVisualizer, true, true)
			self.leftJointTargetVisualizer = nil
		end
		if self.rightJointTargetVisualizer ~= nil then
			uevrUtils.destroyComponent(self.rightJointTargetVisualizer, true, true)
			self.rightJointTargetVisualizer = nil
		end
		return
	end
	for _, side in pairs(self.debugVisualizers) do
		if side ~= nil then
			for _, comp in pairs(side) do
				if comp ~= nil then
					uevrUtils.destroyComponent(comp, true, true)
				end
			end
		end
	end
	self.debugVisualizers = nil
	self.leftJointTargetVisualizer = nil
	self.rightJointTargetVisualizer = nil
end

function Rig:createDebugMeshes()
	self:loadDebugSphereVisibility()
	-- Always rebuild so scale/shape changes apply after reload.
	self:destroyDebugMeshes()
	self.debugVisualizers = { left = {}, right = {} }
	for _, sideName in ipairs({ "left", "right" }) do
		local side = self.debugVisualizers[sideName]
		for _, def in ipairs(IK_DEBUG_SPHERE_DEFS) do
			side[def.key] = createIkDebugSphere(def.scale)
		end
	end
	-- Keep legacy aliases pointing at jointTarget so old code paths still work.
	self.leftJointTargetVisualizer = self.debugVisualizers.left.jointTarget
	self.rightJointTargetVisualizer = self.debugVisualizers.right.jointTarget
	self:applyAllDebugSphereVisibility()

	M.print("IK debug spheres enabled (largest→smallest):")
	M.print("  jointTarget  - TwoBoneIK pole/joint target. Erratic => getMeshOutward / getJointTarget")
	M.print("  effector     - hand target. Erratic => controller / effector path")
	M.print("  solvedElbow  - IK solved elbow pos. Erratic while jointTarget calm => TwoBoneIK singularity")
	M.print("  solvedEnd    - IK solved wrist pos. Erratic => reach/stretch / effector mismatch")
	M.print("  desiredPole  - tip at solved elbow + outward. Erratic => pole/outward direction (twist reference)")
	M.print("  boneElbow    - actual joint bone after rotateElbow. Erratic while solvedElbow calm => rotateShoulder/Elbow write")
	M.print("  boneTwist    - tip on joint bone pole axis. Orbits while boneElbow calm => alignBoneAxisToDirCS elbow twist")
	M.print("  forearmTwist - tip on first twist bone. Orbits while boneTwist calm => twistForearm")
end

function Rig:setDebugVisualizerLocation(hand, key, location)
	if self.debugVisualizers == nil or location == nil then return end
	if not self:isDebugSphereVisible(key) then return end
	local side = (hand == Handed.Left) and self.debugVisualizers.left or self.debugVisualizers.right
	local comp = side and side[key] or nil
	if comp ~= nil then
		comp:K2_SetWorldLocation(location, false, reusable_hit_result, false)
	end
end


function Rig:setRigParameter(paramName, value)
	if self.activeSolvers == nil then return end

	if paramName == "mesh" then
		self:initializeRigState()

		if self.meshList ~= nil then
			for solverId, active in pairs(self.activeSolvers) do
				active.meshList = self.meshList
				if active.endBone ~= nil and active.endBone ~= "" then
					local parentBones = getAncestorBones(self.meshList[1], active.endBone, 3)
					if #parentBones == 3 then
						if active.startBone == nil or active.startBone == "" then
							active.startBone = parentBones[#parentBones]
							active.startBoneFName = uevrUtils.fname_from_string(active.startBone)
						end
						if active.jointBone == nil or active.jointBone == "" then
							active.jointBone = parentBones[#parentBones - 1]
							active.jointBoneFName = uevrUtils.fname_from_string(active.jointBone)
						end
					end
				end
				--self:initializeSolverState(active)
			end
		end
		return
	end

	if paramName == "parent_type" or paramName == "enhanced_stabilization" then
		M.destroyAll()
		return
	end

	if paramName == "hide_body" or paramName == "spine_bone_name" or paramName == "left_shoulder_bone_name" or paramName == "right_shoulder_bone_name" or paramName == "shoulder_width_scale" then
		if paramName == "hide_body" and value == false then
			M.destroyAll()
			return
		end
		self:updateBonesVisibility()
		return
	end

	if paramName == "show_debug_meshes" then
		self.showDebugMeshes = value
		if value == true then
			self:createDebugMeshes()
		else
			self:destroyDebugMeshes()
		end
		return
	end

	if type(paramName) == "string" and string.sub(paramName, 1, 13) == "debug_sphere_" then
		local key = string.sub(paramName, 14)
		self:setDebugSphereVisible(key, value == true)
		return
	end

    if paramName == "mesh_location_offset" then
		local offset = value and uevrUtils.vector(value) or uevrUtils.vector(0,0,0)
		self.meshLocationOffset = offset
        if self.meshList ~= nil then --update live
			for _, mesh in pairs(self.meshList) do
				mesh.RelativeLocation = offset
			end
        end
		return
	end

    if paramName == "mesh_rotation_offset" then
		local offset = value and uevrUtils.rotator(value) or uevrUtils.rotator(0,0,0)
		self.meshRotationOffset = offset
        if self.meshList ~= nil then --update live
			for _, mesh in pairs(self.meshList) do
				if self.enhancedStabilization then
					self:updateEnhancedMeshRotation(mesh, getPawnRootComponent(), false)
				else
					mesh.RelativeRotation = offset
				end
			end
        end
		return
	end

    if paramName == "mesh_scale_offset" then
		self.meshScaleOffset = value and uevrUtils.vector(value) or uevrUtils.vector(1,1,1)
        if self.meshList ~= nil then --update live
			for _, mesh in pairs(self.meshList) do
            	mesh.RelativeScale3D = self.meshScaleOffset
			end
        end
		return
	end

	if paramName == "animation_mesh" then
		local animationMesh = nil
		if value == "Custom" then
			if getCustomAnimationIKComponent ~= nil then
				animationMesh = getCustomAnimationIKComponent(self.rigId)
			end
		else
			animationMesh = uevrUtils.getObjectFromDescriptor(value, false)
		end
		self.animationMesh = animationMesh
		return
	end

	if paramName == "animation_location_offset" then
		local offset = value and uevrUtils.vector(value) or uevrUtils.vector(0,0,0)
		self.animationLocationOffset = offset
		return
	end

	if paramName == "animation_rotation_offset" then
		local offset = value and uevrUtils.rotator(value) or uevrUtils.rotator(0,0,0)
		self.animationRotationOffset = offset
		return
	end

	if paramName == "animation_ik_pose_authoritative" then
		self.animationIKPoseAuthoritative = value
		return
	end
end

local keyMap = {
	solver_type = "solverType",
    end_bone = "endBone",
	start_bone = "startBone",
	joint_bone = "jointBone",
    wrist_bone = "wristBone",
    end_bone_offset = "handOffset",
    end_bone_rotation = "endBoneRotation",
    allow_wrist_affects_elbow = "allowWristAffectsElbow",
    allow_stretch = "allowStretch",
    start_stretch_ratio = "startStretchRatio",
    max_stretch_scale = "maxStretchScale",
    wrist_twist_influence = "wristTwistInfluence",
    wrist_twist_max = "wristTwistMax",
	forearm_twist_max = "forearmTwistMax",
    smoothing = "smoothing",
    rot_smoothing = "rotSmoothing",
	enhanced_stability = "enhancedStability",
	pole_proj_min_len = "poleProjMinLen",
	use_hemisphere_lock = "useHemisphereLock",
	max_twist_delta_deg = "maxTwistDeltaDeg",
	shoulder_swing_only = "shoulderSwingOnly",
    end_control_type = "hand",
    twist_bones = "twistBones",
	incremental_forearm_twist = "incrementalForearmTwist",
	sort_order = "sortOrder",
	end_bone_lock_pitch = "endBoneLockPitch",
	end_bone_lock_yaw = "endBoneLockYaw",
	end_bone_lock_roll = "endBoneLockRoll",
}
function Rig:setSolverParameter(solverId, paramName, value)

	if paramName == "active" then
		self:setActive(solverId, value)
		return
	end

	local active = self.activeSolvers and self.activeSolvers[solverId]
	if active == nil then return end

	if paramName == "end_bone" then
		local mesh = active.mesh
		local jointBone = active.jointBone or ""
		local startBone = active.startBone or ""
		if mesh ~= nil and jointBone == "" and startBone == "" then
			local parentBones = getAncestorBones(mesh, value, 3)
			if #parentBones == 3 then
				active.startBone = parentBones[#parentBones]
				active.jointBone = parentBones[#parentBones - 1]
				active.startBoneFName = uevrUtils.fname_from_string(active.startBone)
				active.jointBoneFName = uevrUtils.fname_from_string(active.jointBone)
			end
		end
	elseif paramName == "end_control_type" then
		local controller = nil
		if value == M.ControllerType.LEFT_CONTROLLER then
			controller = controllers.getController(Handed.Left, true) or controllers.getController(Handed.Left) -- cached first: the class scan cannot see a fresh, not-yet-adopted controller
		else
			controller = controllers.getController(Handed.Right, true) or controllers.getController(Handed.Right)
		end
		active.controller = controller
	end

	local runtimeKey = keyMap[paramName]
	if runtimeKey ~= nil then
		if runtimeKey == "handOffset" then
			active[runtimeKey] = value and uevrUtils.vector(value) or uevrUtils.vector(0,0,0)
		elseif runtimeKey == "endBoneRotation" then
			active[runtimeKey] = value and uevrUtils.rotator(value) or uevrUtils.rotator(0,0,0)
		else
			active[runtimeKey] = value
			if runtimeKey == "startBone" then
				active.startBoneFName = uevrUtils.fname_from_string(value)
			elseif runtimeKey == "jointBone" then
				active.jointBoneFName = uevrUtils.fname_from_string(value)
			elseif runtimeKey == "endBone" then
				active.endBoneFName = uevrUtils.fname_from_string(value)
			elseif runtimeKey == "wristBone" then
				active.wristBoneFName = (value ~= nil and value ~= "") and uevrUtils.fname_from_string(value) or nil
			elseif runtimeKey == "incrementalForearmTwist" and active.state ~= nil then
				active.state.lastForearmTwistDegApplied = nil
				active.state.lastForearmTwistHandRotCS = nil
				active.state.lastForearmTwistArmRotCS = nil
			elseif runtimeKey == "enhancedStability" and active.state ~= nil then
				active.state._enhancedStabilityStubLogged = nil
			end
		end
	end

	if paramName == "sort_order" then
		self.solverOrderDirty = true
	end

	--if paramName == "twist_bones" or paramName == "joint_bone" or paramName == "start_bone" then
	if paramName == "twist_bones" then
		self:initializeSolverState(active)
	end
end

function Rig:setConfigParameter(key, value, persist)
	--print("Config parameter changed:", key, value, persist)
	if type(key) == "table" then
		saveParameter(key, value, persist)
		if key[1] == "solvers" and key[2] ~= nil and key[3] ~= nil then
			self:setSolverParameter(key[2], key[3], value)
			return
		end
		if key[1] ~= nil then
			self:setRigParameter(key[1], value)
		end
		return
	end

    --Changing mesh rotation uses the code below
	if isRigLevelParam(key) then
		saveParameter(key, value, persist)
		self:setRigParameter(key, value)
		return
	end

	local defaultSolverId = self.defaultSolverId
	if defaultSolverId == nil then
		for solverId, _ in pairs(self.activeSolvers or {}) do
			defaultSolverId = solverId
			break
		end
	end
	if defaultSolverId ~= nil then
		saveParameter({"solvers", defaultSolverId, key}, value, persist)
		self:setSolverParameter(defaultSolverId, key, value)
	end
end


function Rig:rebuildOrderedSolversIfNeeded()
	if self.activeSolvers == nil then
		self.orderedSolvers = {}
		self.solverOrderDirty = false
		return
	end
	if self.solverOrderDirty ~= true and self.orderedSolvers ~= nil then
		return
	end

	local ordered = {}
	for solverId, activeParams in pairs(self.activeSolvers) do
		table.insert(ordered, { id = solverId, params = activeParams, order = (activeParams and activeParams.sortOrder) or 0 })
	end
	table.sort(ordered, function(a, b)
		if a.order == b.order then
			return tostring(a.id) < tostring(b.id)
		end
		return a.order < b.order
	end)

	self.orderedSolvers = ordered
	self.solverOrderDirty = false
end

--checkpoint
function M.destroy(instance, skipUnregister)
	if instance ~= nil then
		for _, callback in ipairs(instanceDestroyedCallbackList) do
			callback(instance)
		end

		local rigParams = getRigParams(instance.rigId)
		if rigParams ~= nil then
			local solvers = rigParams.solvers
			if solvers ~= nil then
				for solverId, solverParams in pairs(solvers) do
					instance:setActive(solverId, false)
				end
			end
		end

		-- Release the finger-animation handlers of every rig mesh (initHandAnimations registers them on the
		-- meshes in meshList). instance.mesh is never assigned (see the commented-out self.mesh in
		-- initializeRigState), so the old single call was a no-op and animation.lua kept writing to the
		-- destroyed rig after each rebuild. (Stalker 2 port, 2026-10-04.)
		handsAnimation.destroyAnimationHandler(instance.mesh)
		for _, mesh in pairs(instance.meshList or {}) do
			handsAnimation.destroyAnimationHandler(mesh)
		end

		if instance.meshList ~= nil then
			for _, mesh in pairs(instance.meshList) do
				-- destroyChildren false: other modules attach their own components to the rig's hand bones
				-- (Stalker 2: the PTM mag proxy, owned by the PAWN), and destroyComponent destroys each
				-- child's owner actor too. The engine detaches the children when the rig goes.
				uevrUtils.destroyComponent(mesh, true, false)
			end
			instance.meshList = nil
		end
		instance.meshTemplates = nil

		if instance.springArmList ~= nil then
			for _, springArm in pairs(instance.springArmList) do
				uevrUtils.destroyComponent(springArm, true, true)
			end
			instance.springArmList = nil
		end

		instance:destroyDebugMeshes()

		if uevrUtils.unregisterPreEngineTickCallback then
			uevrUtils.unregisterPreEngineTickCallback(instance.tickFn)
		end
		if uevrUtils.unregisterPostEngineTickCallback then
			uevrUtils.unregisterPostEngineTickCallback(instance.tickFn)
		end

		if uevrUtils.unregisterUEVRCallback then
			local ok, err = pcall(function()
				uevrUtils.unregisterUEVRCallback("preEngineTick", instance.tickFn)
				uevrUtils.unregisterUEVRCallback("postEngineTick", instance.tickFn)
			end)
			if not ok then
				M.print("Error unregistering UEVR callback: " .. err)
			end
		end

		if uevrUtils.unregisterUEVRCallback then
			local ok, err = pcall(function() uevrUtils.unregisterUEVRCallback("on_ik_config_param_change", instance.liveUpdateFn) end)
			if not ok then
				M.print("Error unregistering UEVR callback: " .. err)
			end
		end
		local ok, err = pcall(function() uevrUtils.clearInterval(instance.hideIntervalTimer) end)
		if not ok then
			M.print("Error clearing interval: " .. err)
		end

		instance.tickFn = nil
		instance.hideIntervalTimer = nil
		instance.liveUpdateFn = nil
		instance.activeSolvers = nil
		instance.orderedSolvers = nil
		instance.initialTransforms = nil
		instance.animationMesh = nil
		instance.state = nil
		--instance.meshCreatedCallback = nil
		--instance.instanceDestroyedCallback = nil

		if skipUnregister ~= true then
			unregisterInstance(instance)
		end
	end
end


local function getBoneDirCS(mesh, fromBone, toBone)
	if mesh == nil then return nil end
	local a = mesh:GetBoneLocationByName(toBoneFName(fromBone), EBoneSpaces.ComponentSpace)
	local b = mesh:GetBoneLocationByName(toBoneFName(toBone), EBoneSpaces.ComponentSpace)
	if a == nil or b == nil then return nil end
	return safeNormalize(kismet_math_library:Subtract_VectorVector(b, a))
end

-- Stable, head/target independent pole reference computed from the rest pose in component space.
-- Returns the "elbow outward" direction: joint position projected onto plane orthogonal to reach.
local function getBendPoleRefCS(mesh, rootBone, jointBone, endBone)
	if mesh == nil then return nil end
	local s = mesh:GetBoneLocationByName(toBoneFName(rootBone), EBoneSpaces.ComponentSpace)
	local j = mesh:GetBoneLocationByName(toBoneFName(jointBone), EBoneSpaces.ComponentSpace)
	local e = mesh:GetBoneLocationByName(toBoneFName(endBone), EBoneSpaces.ComponentSpace)
	if s == nil or j == nil or e == nil then return nil end
	local reach = safeNormalize(kismet_math_library:Subtract_VectorVector(e, s))
	if reach == nil or mathLib.vectorLengthLessThan(reach, 0.0001) then return nil end
	local elbowOffset = kismet_math_library:Subtract_VectorVector(j, s)
	local pole = safeNormalize(ProjectVectorOnToPlane(elbowOffset, reach))
	if pole == nil or mathLib.vectorLengthLessThan(pole, 0.0001) then return nil end
	return pole
end

local function axisVectorsFromRot(rot)
	if rot == nil then return nil, nil, nil end
	return safeNormalize(kismet_math_library:GetForwardVector(rot)),
		safeNormalize(kismet_math_library:GetRightVector(rot)),
		safeNormalize(kismet_math_library:GetUpVector(rot))
end

local function chooseBestAxis(axisX, axisY, axisZ, dir)
	if dir == nil then return { axis = "X", sign = 1, score = 0 } end
	local function scoreAxis(a)
		if a == nil then return 0 end
		local d = mathLib.vectorDot(a, dir) or 0
		return d
	end
	local dx = scoreAxis(axisX)
	local dy = scoreAxis(axisY)
	local dz = scoreAxis(axisZ)
	local adx, ady, adz = math.abs(dx), math.abs(dy), math.abs(dz)
	if adx >= ady and adx >= adz then
		return { axis = "X", sign = (dx >= 0) and 1 or -1, score = dx }
	elseif ady >= adx and ady >= adz then
		return { axis = "Y", sign = (dy >= 0) and 1 or -1, score = dy }
	else
		return { axis = "Z", sign = (dz >= 0) and 1 or -1, score = dz }
	end
end

local function chooseBestPoleAxis(axisX, axisY, axisZ, longAxisChar, poleDir)
	local best = { axis = "Y", sign = 1, score = 0 }
	local function tryAxis(char, vec)
		if char == longAxisChar or vec == nil then return end
		local d = mathLib.vectorDot(vec, poleDir) or 0
		local ad = math.abs(d)
		if ad > best.score then
			best = { axis = char, sign = (d >= 0) and 1 or -1, score = ad }
		end
	end
	tryAxis("X", axisX)
	tryAxis("Y", axisY)
	tryAxis("Z", axisZ)
	return best
end

local function axisVectorFromRotator(rot, axisChar)
	if rot == nil then return nil end
	if axisChar == "X" then
		return kismet_math_library:GetForwardVector(rot)
	elseif axisChar == "Y" then
		return kismet_math_library:GetRightVector(rot)
	else
		return kismet_math_library:GetUpVector(rot)
	end
end

local function composeSwingWithCachedOrder(state, currentDir, currentRot, desiredDir, deltaSwing)
	if state ~= nil and state.composeOrderSwing == 1 then
		return kismet_math_library:ComposeRotators(deltaSwing, currentRot)
	end
	if state ~= nil and state.composeOrderSwing == 2 then
		return kismet_math_library:ComposeRotators(currentRot, deltaSwing)
	end
	local cand1 = kismet_math_library:ComposeRotators(deltaSwing, currentRot)
	local cand2 = kismet_math_library:ComposeRotators(currentRot, deltaSwing)
	local localDir = safeNormalize(kismet_math_library:LessLess_VectorRotator(currentDir, currentRot))
	local function score(rot)
		if rot == nil then return -1 end
		local a = safeNormalize(mathLib.vectorRotate(localDir, rot))
		return mathLib.vectorDot(a, desiredDir) or -1
	end
	local useSecond = score(cand2) > score(cand1)
	if state ~= nil then
		state.composeOrderSwing = useSecond and 2 or 1
	end
	return useSecond and cand2 or cand1
end

local function composeTwistWithCachedOrder(state, swingRot, deltaTwist, desiredDir, desiredPole, poleAxisChar, poleAxisSign)
	if state ~= nil and state.composeOrderTwist == 1 then
		return kismet_math_library:ComposeRotators(deltaTwist, swingRot)
	end
	if state ~= nil and state.composeOrderTwist == 2 then
		return kismet_math_library:ComposeRotators(swingRot, deltaTwist)
	end
	local t1 = kismet_math_library:ComposeRotators(deltaTwist, swingRot)
	local t2 = kismet_math_library:ComposeRotators(swingRot, deltaTwist)
	local function scorePole(rot)
		local p = axisVectorFromRotator(rot, poleAxisChar)
		if p == nil then return -1 end
		p = safeNormalize(ProjectVectorOnToPlane(mulVec(p, poleAxisSign), desiredDir))
		return mathLib.vectorDot(p, desiredPole) or -1
	end
	local useSecond = scorePole(t2) > scorePole(t1)
	if state ~= nil then
		state.composeOrderTwist = useSecond and 2 or 1
	end
	return useSecond and t2 or t1
end

--local _dbg_ik_align_label = nil   -- set by solveTwoBone; read by alignBoneAxisToDirCS
local function alignBoneAxisToDirCS(mesh, boneName, childBoneName, desiredDirCS, axisChoice, poleCS, state)
	local vectorLengthLessThan = mathLib.vectorLengthLessThan
	local vectorDot = mathLib.vectorDot
	local vectorCross = mathLib.vectorCross
	local projectVectorOnToPlane = ProjectVectorOnToPlane
	local currentRot = mesh:GetBoneRotationByName(toBoneFName(boneName), EBoneSpaces.ComponentSpace)
	if currentRot == nil then return nil end

	local currentDir = (childBoneName ~= nil) and getBoneDirCS(mesh, boneName, childBoneName) or nil
	if currentDir == nil and axisChoice ~= nil then
		local axisVec = axisVectorFromRotator(currentRot, axisChoice.axis or "X")
		currentDir = axisVec and safeNormalize(mulVec(axisVec, axisChoice.sign or 1)) or nil
	end
	if currentDir == nil or vectorLengthLessThan(currentDir, 0.0001) then return currentRot end
	local desiredDir = safeNormalize(desiredDirCS)
	if desiredDir == nil or vectorLengthLessThan(desiredDir, 0.0001) then return currentRot end

	local dot = vectorDot(currentDir, desiredDir) or 1.0
	dot = kismet_math_library:FClamp(dot, -1.0, 1.0)
	--local swingAngleDeg = kismet_math_library:RadiansToDegrees(kismet_math_library:Acos(dot))
	local swingAngleDeg = math.deg(math.acos(dot))
	if swingAngleDeg == nil then return currentRot end

	local swingAxis = vectorCross(currentDir, desiredDir)
	if vectorLengthLessThan(swingAxis, 0.0001) then
		-- If we simply return currentRot here with a value of 0.01 instead of calculating swing axis then jitter is
		-- eliminated but then movement stutters when the desired direction crosses the current direction.
		local pole = safeNormalize(poleCS)
		if pole == nil or vectorLengthLessThan(pole, 0.0001) then pole = VEC_UNIT_Y end
		swingAxis = vectorCross(currentDir, pole)
	end
	swingAxis = safeNormalize(swingAxis)
	if swingAxis == nil or vectorLengthLessThan(swingAxis, 0.0001) then return currentRot end
	local effectiveSwingAngleDeg = math.max(0.0, swingAngleDeg - ALIGN_SWING_DEADBAND_DEG)
	if effectiveSwingAngleDeg < IK_MIN_SWING_DEG then return currentRot end
	local deltaSwing = mathLib.rotatorFromAxisAndAngle(swingAxis, effectiveSwingAngleDeg)
	local swingRot = composeSwingWithCachedOrder(state, currentDir, currentRot, desiredDir, deltaSwing)

	local poleAxisChoice = axisChoice and axisChoice.pole or nil
	if poleAxisChoice == nil then return swingRot end
	local poleAxisChar = poleAxisChoice.axis
	local poleAxisSign = poleAxisChoice.sign or 1

	local rawDesiredPole = projectVectorOnToPlane(poleCS, desiredDir)
	local rawDesiredPoleLen = (rawDesiredPole ~= nil) and vsize(rawDesiredPole) or 0.0

	local useAggressivePoleAlignment = false
	local POLE_PROJ_MIN_LEN = 0.22

	local desiredPole = nil
	if useAggressivePoleAlignment == true then
		if rawDesiredPoleLen < POLE_PROJ_MIN_LEN then
			if state ~= nil and state.lastDesiredPole ~= nil and mathLib.vectorLengthGreaterThan(state.lastDesiredPole, 0.0001) then
				desiredPole = state.lastDesiredPole
			else
				return swingRot
			end
		else
			desiredPole = rawDesiredPole * (1.0 / rawDesiredPoleLen)
			if state ~= nil and state.lastDesiredPole ~= nil then
				if (vectorDot(desiredPole, state.lastDesiredPole) or 0.0) < 0.0 then
					desiredPole = desiredPole * -1.0
				end
			end
			if state ~= nil then state.lastDesiredPole = desiredPole end
		end
	else
		if rawDesiredPoleLen < 0.15 then return swingRot end
		desiredPole = rawDesiredPole * (1.0 / rawDesiredPoleLen)
		if desiredPole == nil then return swingRot end
	end

	local poleAxisVec = axisVectorFromRotator(swingRot, poleAxisChar)
	if poleAxisVec == nil then return swingRot end
	local rawCurrentPole = projectVectorOnToPlane(mulVec(poleAxisVec, poleAxisSign), desiredDir)
	local rawCurrentPoleLen = (rawCurrentPole ~= nil) and vsize(rawCurrentPole) or 0.0

	local currentPole = nil
	if useAggressivePoleAlignment == true then
		if rawCurrentPoleLen < POLE_PROJ_MIN_LEN then
			if state ~= nil and state.lastCurrentPole ~= nil and mathLib.vectorLengthGreaterThan(state.lastCurrentPole, 0.0001) then
				currentPole = state.lastCurrentPole
			else
				return swingRot
			end
		else
			currentPole = rawCurrentPole * (1.0 / rawCurrentPoleLen)
			if state ~= nil and state.lastCurrentPole ~= nil then
				if (vectorDot(currentPole, state.lastCurrentPole) or 0.0) < 0.0 then
					currentPole = currentPole * -1.0
				end
			end
			if state ~= nil then state.lastCurrentPole = currentPole end
		end
	else
		if rawCurrentPoleLen < 0.15 then return swingRot end
		currentPole = rawCurrentPole * (1.0 / rawCurrentPoleLen)
		if currentPole == nil then return swingRot end
	end

	local twistAngleDeg = mathLib.signedAngleDegAroundAxis(currentPole, desiredPole, desiredDir)
	if twistAngleDeg == nil or math.abs(twistAngleDeg) < IK_MIN_TWIST_DEG then return swingRot end

	local deltaTwist = mathLib.rotatorFromAxisAndAngle(desiredDir, twistAngleDeg)
	return composeTwistWithCachedOrder(state, swingRot, deltaTwist, desiredDir, desiredPole, poleAxisChar, poleAxisSign)
end
alignBoneAxisToDirCS = uevrUtils.profiler:wrap("alignBoneAxisToDirCS", alignBoneAxisToDirCS)

-- Enhanced Stability only. Never called unless solver enhanced_stability is true.
-- Keep completely separate from alignBoneAxisToDirCS so the default path cannot change.
local function alignBoneAxisToDirCSEnhanced(mesh, boneName, childBoneName, desiredDirCS, axisChoice, poleCS, state, es)
	local vectorLengthLessThan = mathLib.vectorLengthLessThan
	local vectorDot = mathLib.vectorDot
	local vectorCross = mathLib.vectorCross
	local projectVectorOnToPlane = ProjectVectorOnToPlane
	local currentRot = mesh:GetBoneRotationByName(toBoneFName(boneName), EBoneSpaces.ComponentSpace)
	if currentRot == nil then return nil end

	local currentDir = (childBoneName ~= nil) and getBoneDirCS(mesh, boneName, childBoneName) or nil
	if currentDir == nil and axisChoice ~= nil then
		local axisVec = axisVectorFromRotator(currentRot, axisChoice.axis or "X")
		currentDir = axisVec and safeNormalize(mulVec(axisVec, axisChoice.sign or 1)) or nil
	end
	if currentDir == nil or vectorLengthLessThan(currentDir, 0.0001) then return currentRot end
	local desiredDir = safeNormalize(desiredDirCS)
	if desiredDir == nil or vectorLengthLessThan(desiredDir, 0.0001) then return currentRot end

	local dot = vectorDot(currentDir, desiredDir) or 1.0
	dot = kismet_math_library:FClamp(dot, -1.0, 1.0)
	local swingAngleDeg = math.deg(math.acos(dot))
	if swingAngleDeg == nil then return currentRot end

	local swingAxis = vectorCross(currentDir, desiredDir)
	if vectorLengthLessThan(swingAxis, 0.0001) then
		local pole = safeNormalize(poleCS)
		if pole == nil or vectorLengthLessThan(pole, 0.0001) then pole = VEC_UNIT_Y end
		swingAxis = vectorCross(currentDir, pole)
	end
	swingAxis = safeNormalize(swingAxis)
	if swingAxis == nil or vectorLengthLessThan(swingAxis, 0.0001) then return currentRot end
	local effectiveSwingAngleDeg = math.max(0.0, swingAngleDeg - ALIGN_SWING_DEADBAND_DEG)
	if effectiveSwingAngleDeg < IK_MIN_SWING_DEG then return currentRot end
	local deltaSwing = mathLib.rotatorFromAxisAndAngle(swingAxis, effectiveSwingAngleDeg)
	local swingRot = composeSwingWithCachedOrder(state, currentDir, currentRot, desiredDir, deltaSwing)

	local poleAxisChoice = axisChoice and axisChoice.pole or nil
	if poleAxisChoice == nil then return swingRot end
	local poleAxisChar = poleAxisChoice.axis
	local poleAxisSign = poleAxisChoice.sign or 1

	local rawDesiredPole = projectVectorOnToPlane(poleCS, desiredDir)
	local rawDesiredPoleLen = (rawDesiredPole ~= nil) and vsize(rawDesiredPole) or 0.0
	local poleMinLen = (es and es.poleProjMinLen) or 0.30
	local useHemisphereLock = es == nil or es.useHemisphereLock ~= false
	local maxTwistDeltaDeg = (es and es.maxTwistDeltaDeg) or 10.0

	-- Strong readings: trust the fresh projection (flipping to lastDesiredPole caused sticky 180° twist).
	-- Weak/collapsed readings: hold last good pole or skip twist.
	local desiredPole = nil
	if rawDesiredPoleLen < poleMinLen then
		if useHemisphereLock and state ~= nil and state.lastDesiredPole ~= nil and mathLib.vectorLengthGreaterThan(state.lastDesiredPole, 0.0001) then
			desiredPole = state.lastDesiredPole
		else
			return swingRot
		end
	else
		desiredPole = rawDesiredPole * (1.0 / rawDesiredPoleLen)
		if state ~= nil then state.lastDesiredPole = desiredPole end
	end

	local poleAxisVec = axisVectorFromRotator(swingRot, poleAxisChar)
	if poleAxisVec == nil then return swingRot end
	local rawCurrentPole = projectVectorOnToPlane(mulVec(poleAxisVec, poleAxisSign), desiredDir)
	local rawCurrentPoleLen = (rawCurrentPole ~= nil) and vsize(rawCurrentPole) or 0.0

	local currentPole = nil
	if rawCurrentPoleLen < poleMinLen then
		if useHemisphereLock and state ~= nil and state.lastCurrentPole ~= nil and mathLib.vectorLengthGreaterThan(state.lastCurrentPole, 0.0001) then
			currentPole = state.lastCurrentPole
		else
			return swingRot
		end
	else
		currentPole = rawCurrentPole * (1.0 / rawCurrentPoleLen)
		if state ~= nil then state.lastCurrentPole = currentPole end
	end

	local twistAngleDeg = mathLib.signedAngleDegAroundAxis(currentPole, desiredPole, desiredDir)
	if twistAngleDeg == nil or math.abs(twistAngleDeg) < IK_MIN_TWIST_DEG then return swingRot end
	if math.abs(twistAngleDeg) > maxTwistDeltaDeg then
		twistAngleDeg = (twistAngleDeg >= 0.0) and maxTwistDeltaDeg or -maxTwistDeltaDeg
	end

	local deltaTwist = mathLib.rotatorFromAxisAndAngle(desiredDir, twistAngleDeg)
	return composeTwistWithCachedOrder(state, swingRot, deltaTwist, desiredDir, desiredPole, poleAxisChar, poleAxisSign)
end

safeNormalize = function(v)
	return mathLib.vectorSafeNormalize(v)
	-- if v == nil then return uevrUtils.vector(0,0,0) end
	-- -- UKismetMathLibrary has VSize/Divide_VectorFloat (see Engine_classes.hpp)
	-- local len = mathLib.vectorSize(v)
	-- if len == nil or len < 0.0001 then
	-- 	return uevrUtils.vector(0,0,0)
	-- end
	-- return v * (1.0 / len)
end
safeNormalize = uevrUtils.profiler:wrap("SafeNormalize", safeNormalize)


--stopDebug = false
local count = 0
function Rig:solveTwoBone(solverParams)
    local meshList = solverParams.meshList				-- UPoseableMeshComponent
    local RootBone = solverParams.startBone		-- e.g. "UpperArm_L" (string; for keys/concat)
    local JointBone = solverParams.jointBone	-- e.g. "LowerArm_L"
    local EndBone = solverParams.endBone		-- e.g. "Hand_L"
    local wristBone = solverParams.wristBone
	-- Cached FNames for ByName APIs (some games fail Lua string FName coercion)
	local RootBoneFName = solverParams.startBoneFName
	local JointBoneFName = solverParams.jointBoneFName
	local EndBoneFName = solverParams.endBoneFName
	local wristBoneFName = solverParams.wristBoneFName
    local controllerPosWS, controllerRotWS = getTargetLocationAndRotation(solverParams.hand, solverParams.controller)
    -- local controllerPosWS = solverParams.controller and solverParams.controller:K2_GetComponentLocation() or nil
    -- local controllerRotWS = solverParams.controller and solverParams.controller:K2_GetComponentRotation() or nil
    local handOffset = solverParams.handOffset
    local allowStretch = solverParams.allowStretch
    local startStretchRatio = solverParams.startStretchRatio
    local maxStretchScale = solverParams.maxStretchScale
    local twistBones = solverParams.twistBones
    local endBoneRotation = solverParams.endBoneRotation
    local allowWristAffectsElbow = solverParams.allowWristAffectsElbow
    local wristTwistInfluence = solverParams.wristTwistInfluence
    local wristTwistMax = solverParams.wristTwistMax
	local forearmTwistMax = solverParams.forearmTwistMax
	local smoothing = solverParams.smoothing or 0.0
	local endBoneLockPitch = solverParams.endBoneLockPitch or false
	local endBoneLockYaw = solverParams.endBoneLockYaw or false
	local endBoneLockRoll = solverParams.endBoneLockRoll or false

	if meshList == nil or meshList[1] == nil then
		M.print("solveTwoBone: No mesh")
		return
	end
	local mesh = meshList[1]

	local state = solverParams.state
	if state == nil then
		state = newIKState()
		solverParams.state = state
	end
    VEC_UNIT_Y = VEC_UNIT_Y_FORWARD

	if controllerPosWS == nil or controllerRotWS == nil then
        M.print("solveTwoBone: Missing controller position/rotation" .. tostring(solverParams.hand)) --, solverParams.controller:get_full_name())
		return
	end

    --------------------------------------------------------------
    -- 1. Component transform + shoulder position (fail-fast)
    --------------------------------------------------------------
	-- compToWorld MUST be fetched every tick: the mesh is parented to pawn.RootComponent,
	-- so any body rotation changes this transform. Caching it causes the hand to drift
	-- away from the controller whenever the pawn rotates.
	if not isMeshAlive(mesh) then
		M.print("SolveVRArmIK: Mesh is not valid")
		return
	end
	-- Hellraiser 2026-10-09: a destroyed rig mesh can still answer get_full_name() (freed memory), so isMeshAlive passes
	-- while its PoseableMesh methods are gone ("attempt to call a nil value (method 'GetBoneLocationByName')" every
	-- tick). Drop this rig once; the auto-create (1 s) builds a fresh one.
	if mesh.GetBoneLocationByName == nil then
		if not self.deadMeshHandled then
			self.deadMeshHandled = true
			M.print("SolveVRArmIK: rig mesh is gone - rebuilding the rig", LogLevel.Warning)
			-- forget the dead meshes first: destroy() would otherwise call into the freed component (game-side AV)
			self.meshList = nil
			for _, entry in ipairs(self.orderedSolvers or {}) do
				if entry.params ~= nil then entry.params.meshList = nil end
			end
			uevrUtils.setTimeout(1, function() if isRegisteredInstance(self) then M.destroy(self) end end)
		end
		return
	end
	local compToWorld = getComponentToWorld(mesh)
	if compToWorld == nil then M.print("SolveVRArmIK: no component transform") return end

	-- Stretch support (Hellraiser 2026-10-08, see step 11): step 11 moves the elbow / hand bones outward, and
	-- K2_TwoBoneIK measures the limb from the CURRENT bone positions - without this reset the stretch compounded
	-- every tick (arms ballooned after a ladder, where the controllers stay out of reach) and never shrank back.
	-- So the joint / end bone offsets from the reference pose are captured on the first solve (before any stretch)
	-- and restored at the start of every solve; the solver then always works from the true arm length.
	if allowStretch == true then
		local startF, jointF, endF = toBoneFName(RootBone), toBoneFName(JointBone), toBoneFName(EndBone)
		pcall(function()
			if state.refJointLocal == nil then
				local sT = mesh:GetBoneTransformByName(startF, EBoneSpaces.ComponentSpace)
				local jT = mesh:GetBoneTransformByName(jointF, EBoneSpaces.ComponentSpace)
				local eT = mesh:GetBoneTransformByName(endF, EBoneSpaces.ComponentSpace)
				local jl = kismet_math_library:InverseTransformLocation(sT, jT.Translation)
				local el = kismet_math_library:InverseTransformLocation(jT, eT.Translation)
				state.refJointLocal = uevrUtils.vector(jl.X, jl.Y, jl.Z)
				state.refEndLocal = uevrUtils.vector(el.X, el.Y, el.Z)
			else
				for _, m in ipairs(meshList) do
					if isMeshAlive(m) then
						local sT = m:GetBoneTransformByName(startF, EBoneSpaces.ComponentSpace)
						m:SetBoneLocationByName(jointF, kismet_math_library:TransformLocation(sT, state.refJointLocal), EBoneSpaces.ComponentSpace)
						local jT = m:GetBoneTransformByName(jointF, EBoneSpaces.ComponentSpace)
						m:SetBoneLocationByName(endF, kismet_math_library:TransformLocation(jT, state.refEndLocal), EBoneSpaces.ComponentSpace)
					end
				end
			end
		end)
	end

	local shoulderWS = mesh:GetBoneLocationByName(RootBoneFName or toBoneFName(RootBone), EBoneSpaces.WorldSpace)
	if shoulderWS == nil then M.print("SolveVRArmIK: no shoulder location for " .. tostring(RootBone)) return end

    --------------------------------------------------------------
    -- 2. Compute Effector (hand target)
    --------------------------------------------------------------
    -- effectorWS = where the HAND BONE should go
    -- controllerPosWS is where the real hand is
    -- handOffset rotates/translates controller hand bone pose
	-- If you want no offsets: pass handOffset=nil and effectorWS will be the controller location.
	-- handOffset is controller-local, so we must rotate it by the controller's world rotation.
    --------------------------------------------------------------
	local effectorWS = controllerPosWS
	if handOffset ~= nil then
		local offsetWS = handOffset
		if controllerRotWS ~= nil then
			offsetWS = mathLib.vectorRotate(handOffset, controllerRotWS)
		end
		effectorWS = controllerPosWS + offsetWS
	end

	local controllerRotCS = kismet_math_library:InverseTransformRotation(compToWorld, controllerRotWS)

	-- Smooth controller target in component-space offset from shoulder.
	-- This damps root-motion/head-turn jitter without smoothing final solved outputs.
	if state ~= nil and smoothing > 0 then
		local effectorOffsetWS = effectorWS - shoulderWS
		local effectorOffsetCS = kismet_math_library:InverseTransformDirection(compToWorld, effectorOffsetWS)
		local smOffsetCS = effectorOffsetCS
		if state.lastEffectorOffsetCS ~= nil then
			smOffsetCS = state.lastEffectorOffsetCS * smoothing + effectorOffsetCS * (1 - smoothing)
		end
		state.lastEffectorOffsetCS = smOffsetCS
		local smOffsetWS = kismet_math_library:TransformDirection(compToWorld, smOffsetCS)
		effectorWS = shoulderWS + smOffsetWS
	end

    --------------------------------------------------------------
    -- 3. Auto-generate JointTarget (elbow direction)
    --------------------------------------------------------------
    -- Forward direction from shoulder hand target
	local shoulderToHandWS = effectorWS - shoulderWS
	local shoulderToHandLen = vsize(shoulderToHandWS) or 0.0
	if shoulderToHandLen < 0.0001 then
		return
	end
	local shoulderToHandVector = shoulderToHandWS * (1.0 / shoulderToHandLen)

	-- if count > 1000 then
	-- 	count = 0
	-- 	state.lastOutwardWS = nil
	-- else
	-- 	count = count + 1
	-- end
	-- -- GetRightVector changes with pawn rotation fetch fresh every tick.
	-- if state.lastOutwardWS == nil then
	-- 	print("Recomputing outwardWS")
	-- 	state.lastOutwardWS = self:getMeshOutward(mesh, RootBone, JointBone, shoulderToHandVector, compToWorld, controllerRotCS, allowWristAffectsElbow, wristTwistInfluence, wristTwistMax, solverParams, state)
	-- end
	-- local outwardWS = state.lastOutwardWS
	local jointWS = mesh:GetBoneLocationByName(JointBoneFName or toBoneFName(JointBone), EBoneSpaces.WorldSpace)
	local endWS   = mesh:GetBoneLocationByName(EndBoneFName or toBoneFName(EndBone),   EBoneSpaces.WorldSpace)
	local outwardWS = self:getMeshOutward(mesh, shoulderWS, jointWS, shoulderToHandVector, compToWorld, controllerRotCS, allowWristAffectsElbow, wristTwistInfluence, wristTwistMax, solverParams, state)
	--local outwardWS = self:getMeshOutwardSimple(mesh, RootBone, JointBone, shoulderToHandVector, compToWorld, controllerRotCS, allowWristAffectsElbow, wristTwistInfluence, wristTwistMax, solverParams, state)

	--------------------------------------------------------------
	-- 4. Fetch bone locations and Joint target
	--------------------------------------------------------------
	local jointTargetWS = self:getJointTarget(shoulderWS, jointWS, endWS, shoulderToHandVector, shoulderToHandLen, outwardWS, state)
	--local jointTargetWS = self:calculateProceduralJointTarget(shoulderWS, jointWS, endWS, 20, outwardWS, state)
	local debugHand = solverParams.hand
	local debugEnabled = self.showDebugMeshes == true and self.debugVisualizers ~= nil
	if debugEnabled then
		self:setDebugVisualizerLocation(debugHand, "effector", effectorWS)
		self:setDebugVisualizerLocation(debugHand, "jointTarget", jointTargetWS)
	end
    --------------------------------------------------------------
    -- 5. Run IK solver
    --------------------------------------------------------------
    local outJointWS = uevrUtils.vector()
    local outEndWS   = uevrUtils.vector()

	---@diagnostic disable-next-line: need-check-nil, undefined-field
    UKismetAnimationLibrary:K2_TwoBoneIK(
        shoulderWS, jointWS, endWS,
        jointTargetWS, effectorWS,
        outJointWS, outEndWS,
        allowStretch, startStretchRatio, maxStretchScale
    )

	if debugEnabled then
		self:setDebugVisualizerLocation(debugHand, "solvedElbow", outJointWS)
		self:setDebugVisualizerLocation(debugHand, "solvedEnd", outEndWS)
		-- Desired Pole: tip along outward from the solved elbow (pole/twist reference direction).
		-- Distinct from Joint Target, which is the TwoBoneIK target point.
		self:setDebugVisualizerLocation(debugHand, "desiredPole", makeDebugPoleTipWS(outJointWS, outwardWS))
	end

    --------------------------------------------------------------
    -- 6. Reconstruct rotations from solved positions
    --------------------------------------------------------------
	local upperDirWS = safeNormalize(kismet_math_library:Subtract_VectorVector(outJointWS, shoulderWS))
	local lowerDirWS = safeNormalize(kismet_math_library:Subtract_VectorVector(outEndWS, outJointWS))

	--------------------------------------------------------------
	-- 7. Build target rotations in ComponentSpace
	--------------------------------------------------------------
	-- Many skeletons do NOT use +X as the "bone points-to-child" axis.
	-- We calibrate which axis (X/Y/Z with sign) to align, then construct a component-space rot.
	local upperDirCS = safeNormalize(kismet_math_library:InverseTransformDirection(compToWorld, upperDirWS))
	local lowerDirCS = safeNormalize(kismet_math_library:InverseTransformDirection(compToWorld, lowerDirWS))
	local poleCS = safeNormalize(kismet_math_library:InverseTransformDirection(compToWorld, outwardWS))

	if smoothing > 0 then
		-- Normalized lerp (NLERP) to suppress per-tick noise in IK directions and pole.
		-- Directions use a light touch (20% old / 80% new) so arm tracking stays responsive.
		-- Pole uses stronger smoothing (40% old / 60% new) it only drives elbow orientation,
		-- not hand position, so a tiny lag is perfectly acceptable there.
		local function nlerpSmoothDir(prev, curr, alpha)
			-- alpha = weight of OLD value.  0 = no smoothing, 1 = frozen.
			if prev == nil then return curr end
			local mixed = (prev * alpha) + (curr * (1.0 - alpha))
			local len = vsize(mixed)
			if len == nil or len < 0.0001 then return curr end
			return mixed * (1.0 / len)
		end

		upperDirCS = nlerpSmoothDir(state.smUpperDirCS, upperDirCS, 0.2)
		state.smUpperDirCS = upperDirCS

		lowerDirCS = nlerpSmoothDir(state.smLowerDirCS, lowerDirCS, 0.2)
		state.smLowerDirCS = lowerDirCS

		poleCS = nlerpSmoothDir(state.smPoleCS, poleCS, 0.4)
		state.smPoleCS = poleCS
	end

	-- Opt-in per-solver mitigations (off by default so other games/arms are unchanged).
	self:applyEnhancedStability(solverParams, state, {
		upperDirCS = upperDirCS,
		lowerDirCS = lowerDirCS,
		poleCS = poleCS,
		outwardWS = outwardWS,
	})

	-- Cache shoulder pole axis selection once.
	local axisShoulder = self:getShoulderPoleAxis(mesh, RootBoneFName, JointBoneFName, EndBoneFName, solverParams, state)

	-- Cache joint pole axis selection.
	local axisJoint = self:getJointPoleAxis(mesh, RootBoneFName, JointBoneFName, EndBoneFName, solverParams, state)


--	for _, mesh in ipairs(meshList) do
--		if mesh ~= nil then
			--------------------------------------------------------------
			-- 8. Apply component-space rotations to shoulder and elbow bones
			--------------------------------------------------------------
			self:rotateShoulder(meshList, RootBoneFName, JointBoneFName, upperDirCS, axisShoulder, poleCS, state, smoothing)
			local elbowRotCS = self:rotateElbow(meshList, JointBoneFName, EndBoneFName, lowerDirCS, axisJoint, poleCS, state, smoothing)

			if debugEnabled then
				local boneElbowWS = mesh:GetBoneLocationByName(JointBoneFName, EBoneSpaces.WorldSpace)
				self:setDebugVisualizerLocation(debugHand, "boneElbow", boneElbowWS)
				local boneElbowRotWS = mesh:GetBoneRotationByName(JointBoneFName, EBoneSpaces.WorldSpace)
				local poleChoice = axisJoint and axisJoint.pole or nil
				if boneElbowWS ~= nil and boneElbowRotWS ~= nil and poleChoice ~= nil and poleChoice.axis ~= nil then
					local poleAxisWS = axisVectorFromRotator(boneElbowRotWS, poleChoice.axis)
					if poleAxisWS ~= nil then
						local sign = poleChoice.sign or 1
						self:setDebugVisualizerLocation(debugHand, "boneTwist", boneElbowWS + (poleAxisWS * (sign * IK_DEBUG_POLE_TIP_DIST)))
					end
				elseif boneElbowWS ~= nil then
					self:setDebugVisualizerLocation(debugHand, "boneTwist", boneElbowWS)
				end
			end

			--------------------------------------------------------------
			-- 9. Apply controller rotation to hand/wrist bone 
			--------------------------------------------------------------
			local finalHandRotCS = self:rotateHandAndWrist(meshList, EndBoneFName, wristBoneFName, endBoneRotation, controllerRotWS, controllerRotCS, compToWorld, state, smoothing, endBoneLockPitch, endBoneLockYaw, endBoneLockRoll)

			--------------------------------------------------------------
			-- 10. Twist the forearm bones based on the hand/wrist rotation
			--------------------------------------------------------------
			self:twistForearm(meshList, lowerDirCS, elbowRotCS, finalHandRotCS, twistBones, forearmTwistMax, wristTwistMax, state, solverParams.incrementalForearmTwist)

			if debugEnabled then
				local placedForearmTwist = false
				if twistBones ~= nil and twistBones[1] ~= nil then
					local entry = twistBones[1]
					local twistBoneFName = entry._fname
					if twistBoneFName == nil and entry.bone ~= nil then
						twistBoneFName = uevrUtils.fname_from_string(entry.bone)
						entry._fname = twistBoneFName
					end
					if twistBoneFName ~= nil then
						local twistBoneWS = mesh:GetBoneLocationByName(twistBoneFName, EBoneSpaces.WorldSpace)
						local twistBoneRotWS = mesh:GetBoneRotationByName(twistBoneFName, EBoneSpaces.WorldSpace)
						if twistBoneWS ~= nil and twistBoneRotWS ~= nil then
							-- Radial tip in the plane perpendicular to the forearm so roll orbits the marker.
							-- Do not use raw bone +X: left/right twist bones are often mirrored, which
							-- previously parked this sphere at the fingertips on one side only.
							local tubeDir = lowerDirWS
							local tipDirWS = nil
							if tubeDir ~= nil and (vsize(tubeDir) or 0.0) > 0.0001 then
								for _, axisChar in ipairs({ "Y", "Z", "X" }) do
									local axisWS = axisVectorFromRotator(twistBoneRotWS, axisChar)
									local radial = (axisWS ~= nil) and ProjectVectorOnToPlane(axisWS, tubeDir) or nil
									local radialLen = (radial ~= nil) and (vsize(radial) or 0.0) or 0.0
									if radialLen >= 0.0001 then
										tipDirWS = radial * (1.0 / radialLen)
										break
									end
								end
							end
							if tipDirWS ~= nil then
								self:setDebugVisualizerLocation(debugHand, "forearmTwist", twistBoneWS + (tipDirWS * IK_DEBUG_POLE_TIP_DIST))
							else
								self:setDebugVisualizerLocation(debugHand, "forearmTwist", twistBoneWS)
							end
							placedForearmTwist = true
						end
					end
				end
				-- No twist bones configured: park on solved elbow so it doesn't sit at world origin.
				if not placedForearmTwist then
					self:setDebugVisualizerLocation(debugHand, "forearmTwist", outJointWS)
				end
			end

			--------------------------------------------------------------
			-- 11. Stretch (Hellraiser 2026-10-08): steps 6-8 only take DIRECTIONS from K2_TwoBoneIK, so its stretched
			-- joint/end POSITIONS were discarded and allow_stretch / max_stretch_scale never lengthened the arm. When
			-- stretching is on and the target is past the unstretched reach, move the elbow and hand bones to the
			-- solved positions (world space; the hand keeps the rotation stamped in step 9, children follow).
			--------------------------------------------------------------
			if allowStretch == true and maxStretchScale ~= nil and maxStretchScale > 1.0 then
				local upperLen, lowerLen = state and state.upperLen, state and state.lowerLen
				if upperLen ~= nil and lowerLen ~= nil and vsize(effectorWS - shoulderWS) > (upperLen + lowerLen) * (startStretchRatio or 1.0) then
					local jointFName, endFName = toBoneFName(JointBone), toBoneFName(EndBone)
					for _, m in ipairs(meshList) do
						if isMeshAlive(m) then
							pcall(function()
								m:SetBoneLocationByName(jointFName, outJointWS, EBoneSpaces.WorldSpace)
								m:SetBoneLocationByName(endFName, outEndWS, EBoneSpaces.WorldSpace)
							end)
						end
					end
				end
			end
--		end
--	end
end
Rig.solveTwoBone = uevrUtils.profiler:wrap("solveTwoBone", Rig.solveTwoBone)

-- Per-solver opt-in hook for twist/singularity mitigations.
-- Default off: existing games and solvers keep current behavior.
function Rig:applyEnhancedStability(solverParams, state, context)
	if state == nil then return end
	if solverParams == nil or solverParams.enhancedStability ~= true then
		state.enhancedStabilityAlign = nil
		return
	end

	-- Best-guess mitigations for post-solve twist spin (targets/pole stable, bone writes wild).
	-- Values come from solver config (Enhanced Stability group); defaults match the original guesses.
	local poleProjMinLen = solverParams.poleProjMinLen
	if poleProjMinLen == nil then poleProjMinLen = 0.30 end
	local useHemisphereLock = solverParams.useHemisphereLock
	if useHemisphereLock == nil then useHemisphereLock = true end
	local maxTwistDeltaDeg = solverParams.maxTwistDeltaDeg
	if maxTwistDeltaDeg == nil then maxTwistDeltaDeg = 12.0 end
	state.enhancedStabilityAlign = {
		poleProjMinLen = poleProjMinLen,
		useHemisphereLock = useHemisphereLock,
		maxTwistDeltaDeg = maxTwistDeltaDeg,
		shoulderSwingOnly = solverParams.shoulderSwingOnly == true,
	}

	if state._enhancedStabilityStubLogged ~= true then
		state._enhancedStabilityStubLogged = true
		-- Drop any sticky pole hemispheres from before enhanced mode.
		state.lastDesiredPoleShoulder = nil
		state.lastCurrentPoleShoulder = nil
		state.lastDesiredPoleElbow = nil
		state.lastCurrentPoleElbow = nil
		local handLabel = (solverParams.hand == Handed.Left and "Left")
			or (solverParams.hand == Handed.Right and "Right")
			or tostring(solverParams.hand)
		M.print("Enhanced Stability active (" .. handLabel .. " solver): singularity freeze, twist clamp", LogLevel.Info)
	end
end
Rig.applyEnhancedStability = uevrUtils.profiler:wrap("applyEnhancedStability", Rig.applyEnhancedStability)

-- Only gets called a few times because result is cached normally
function Rig:calculateJointTargetForwardDistance(shoulderWS, jointWS, endWS, state)
	local forwardDist = 0
	local outwardDist = 0
	local upperLen = 0
	local lowerLen = 0
	if state and state.upperLen == nil and jointWS ~= nil and shoulderWS ~= nil then
		state.upperLen = vsize(jointWS - shoulderWS)
	end
	if state and state.lowerLen == nil and jointWS ~= nil and endWS ~= nil then
		state.lowerLen = vsize(endWS - jointWS)
	end
	upperLen = (state and state.upperLen) or 30.0
	lowerLen = (state and state.lowerLen) or 30.0
	forwardDist = (upperLen + lowerLen) * 0.5
	outwardDist = upperLen * 0.35
	if state and state.upperLen ~= nil and state.lowerLen ~= nil then
		state.forwardDist = forwardDist
		state.outwardDist = outwardDist
		state.upperLenSq = upperLen * upperLen
		state.lowerLenSq = lowerLen * lowerLen
		state.maxReach = math.max((upperLen + lowerLen) - 0.001, 0.001)
	end
	return forwardDist, outwardDist, upperLen, lowerLen
end
Rig.calculateJointTargetForwardDistance = uevrUtils.profiler:wrap("calculateJointTargetForwardDistance", Rig.calculateJointTargetForwardDistance)

function Rig:getJointTarget(shoulderWS, jointWS, endWS, reachDir, reachLen, outwardWS, state)
	--local K = kismet_math_library
	local outwardDist = state.outwardDist
	local upperLen = state.upperLen
	local lowerLen = state.lowerLen
	local upperLenSq = state.upperLenSq
	local lowerLenSq = state.lowerLenSq
	local maxReach = state.maxReach
	if outwardDist == nil or upperLen == nil or lowerLen == nil then
		_, outwardDist, upperLen, lowerLen = self:calculateJointTargetForwardDistance(shoulderWS, jointWS, endWS, state)
		upperLenSq = state.upperLenSq or (upperLen * upperLen)
		lowerLenSq = state.lowerLenSq or (lowerLen * lowerLen)
		maxReach = state.maxReach or math.max((upperLen + lowerLen) - 0.001, 0.001)
	end

	if reachLen < 0.0001 then
		return jointWS
	end

	local clampedReachLen = math.min(reachLen, maxReach)
	local alongReach = (upperLenSq - lowerLenSq + (clampedReachLen * clampedReachLen)) / (2.0 * clampedReachLen)
	if alongReach < 0.0 then
		alongReach = 0.0
	elseif alongReach > upperLen then
		alongReach = upperLen
	end

	return shoulderWS + ( (reachDir * alongReach) + (outwardWS * outwardDist) )
end
Rig.getJointTarget = uevrUtils.profiler:wrap("getJointTarget", Rig.getJointTarget)

-- Simple procedural joint target (direct translation of provided algorithm)
-- Returns a world-space Vector where an IK joint target could be placed. Not as efficient
function Rig:calculateProceduralJointTarget(shoulder_pos, elbow_pos, current_hand_pos, pole_vector_offset, outwardWS, state)
	--local K = kismet_math_library
	if shoulder_pos == nil or elbow_pos == nil then return nil end

	local upperLen = state.upperLen
	local lowerLen = state.lowerLen
	if lowerLen == nil or upperLen == nil then
		_, _, upperLen, lowerLen = self:calculateJointTargetForwardDistance(shoulder_pos, elbow_pos, current_hand_pos, state)
	end

	local reach = kismet_math_library:Subtract_VectorVector(current_hand_pos, shoulder_pos)
	local reachLen = kismet_math_library:VSize(reach) or 0.0
	if reachLen < 0.0001 then return elbow_pos end

	local maxReach = math.max((upperLen + lowerLen) - 0.001, 0.001)
	local clampedReachLen = math.min(reachLen, maxReach)
	local reachDir = kismet_math_library:Divide_VectorFloat(reach, reachLen)
	if reachDir == nil or kismet_math_library:VSize(reachDir) < 0.0001 then return elbow_pos end

	local outwardDir = safeNormalize(ProjectVectorOnToPlane(outwardWS, reachDir))
	if outwardDir == nil or kismet_math_library:VSize(outwardDir) < 0.0001 then return elbow_pos end
	local alongReach = ((upperLen * upperLen) - (lowerLen * lowerLen) + (clampedReachLen * clampedReachLen)) / (2.0 * clampedReachLen)
	alongReach = kismet_math_library:FClamp(alongReach, 0.0, upperLen)

	local perpendicularDist = pole_vector_offset
	local elbowOnPlane = shoulder_pos + (
		kismet_math_library:Multiply_VectorFloat(reachDir, alongReach) +
		kismet_math_library:Multiply_VectorFloat(outwardDir, perpendicularDist)
	)
	local jointTargetOffset = pole_vector_offset or (upperLen * 0.35)

	return elbowOnPlane + kismet_math_library:Multiply_VectorFloat(outwardDir, jointTargetOffset)
end
Rig.calculateProceduralJointTarget = uevrUtils.profiler:wrap("calculateProceduralJointTarget", Rig.calculateProceduralJointTarget)


function Rig:getMeshOutwardSimple(mesh, RootBone, JointBone, shoulderToHandVector, compToWorld, controllerRotCS, allowWristAffectsElbow, wristTwistInfluence, wristTwistMax, solverParams, state)
	if true then return mesh:GetRightVector() * (solverParams.hand == Handed.Left and -1 or 1) end
end

function Rig:getMeshOutward(mesh, shoulderWS, jointWS, shoulderToHandVector, compToWorld, controllerRotCS, allowWristAffectsElbow, wristTwistInfluence, wristTwistMax, solverParams, state)
	if state == nil then return mesh:GetRightVector() end

	local meshRight = mesh:GetRightVector()
	local meshFwd   = mesh:GetForwardVector()
	local meshUp    = mesh:GetUpVector()

	if state.anchorPoleInBodySpace == nil then
		local rawDir = safeNormalize(jointWS - shoulderWS)
		state.anchorPoleInBodySpace = {
			right = mathLib.vectorDot(rawDir, meshRight),
			fwd   = mathLib.vectorDot(rawDir, meshFwd),
			up    = mathLib.vectorDot(rawDir, meshUp),
		}
	end

	local handFallbackPole = (solverParams.hand == Handed.Left)
		and meshRight * -1.0
		or meshRight

	local outwardWS = state.lastValidPoleWS or handFallbackPole
	if state.anchorPoleInBodySpace ~= nil then
		local a = state.anchorPoleInBodySpace
		local anchorPoleWS = (meshRight * a.right) + (meshFwd * a.fwd) + (meshUp * a.up)

		local reachWS = shoulderToHandVector
		local perp = mathLib.vectorCross(reachWS, mathLib.vectorCross(anchorPoleWS, reachWS))
		local perpLen = (perp ~= nil) and (vsize(perp) or 0.0) or 0.0
		if perpLen >= 0.0001 then
			local candidate = perp * (1.0 / perpLen)
			if (mathLib.vectorDot(candidate, anchorPoleWS) or 0.0) < 0.0 then
				candidate = candidate * -1.0
			end
			outwardWS = candidate
			state.lastValidPoleWS = candidate
		end

		if controllerRotCS ~= nil and allowWristAffectsElbow and wristTwistInfluence > 0 then
			local ctrlUpCS = kismet_math_library:GetUpVector(controllerRotCS)
			local ctrlUpWS = safeNormalize(kismet_math_library:TransformDirection(compToWorld, ctrlUpCS))
			local upProjWS = (ctrlUpWS ~= nil) and safeNormalize(ProjectVectorOnToPlane(ctrlUpWS, reachWS)) or nil
			local upProjLen = (upProjWS ~= nil) and (vsize(upProjWS) or 0.0) or 0.0
			if upProjLen > 0.25 then
				state.lastCtrlPoleWS = upProjWS
			end
			local ctrlPoleWS = state.lastCtrlPoleWS
			if ctrlPoleWS ~= nil then
				local rawTwistDeg = mathLib.signedAngleDegAroundAxis(outwardWS, ctrlPoleWS, reachWS)
				if rawTwistDeg ~= nil then
					rawTwistDeg = (((360 + rawTwistDeg) % 360) - 180)
					rawTwistDeg = kismet_math_library:FClamp(rawTwistDeg, -wristTwistMax, wristTwistMax)
					local appliedDeg = rawTwistDeg * wristTwistInfluence
					if math.abs(appliedDeg) > 0.01 then
						local deltaPoleRot = mathLib.rotatorFromAxisAndAngle(reachWS, appliedDeg)
						outwardWS = safeNormalize(mathLib.vectorRotate(outwardWS, deltaPoleRot))
					end
				end
			end
		end

		-- Optional pole smoothing (magic numbers).
		-- Keeps elbow/forearm correctness by re-enforcing hemisphere + reach-perpendicularity after blend.
		-- prevents huge jumps when hand approaches the pole direction.
		local prevOutwardWS = state.smOutwardWS
		if prevOutwardWS ~= nil then
			local POLE_SMOOTH_ALPHA_BASE = 0.72
			local POLE_SMOOTH_ALPHA_NEAR = 0.90
			local POLE_SMOOTH_NEAR_LEN = 0.30
			local alpha = (perpLen < POLE_SMOOTH_NEAR_LEN) and POLE_SMOOTH_ALPHA_NEAR or POLE_SMOOTH_ALPHA_BASE

			local mixed = (prevOutwardWS * alpha) + (outwardWS * (1.0 - alpha))
			local mixedLen = vsize(mixed) or 0.0
			if mixedLen > 0.0001 then
				outwardWS = mixed * (1.0 / mixedLen)
				if (mathLib.vectorDot(outwardWS, anchorPoleWS) or 0.0) < 0.0 then
					outwardWS = outwardWS * -1.0
				end
				local perpSm = mathLib.vectorCross(reachWS, mathLib.vectorCross(outwardWS, reachWS))
				local perpSmLen = (perpSm ~= nil) and (vsize(perpSm) or 0.0) or 0.0
				if perpSmLen > 0.0001 then
					outwardWS = perpSm * (1.0 / perpSmLen)
					if (mathLib.vectorDot(outwardWS, anchorPoleWS) or 0.0) < 0.0 then
						outwardWS = outwardWS * -1.0
					end
				end
			end
		end
		state.smOutwardWS = outwardWS
		state.lastValidPoleWS = outwardWS
	end

	return outwardWS
end
Rig.getMeshOutward = uevrUtils.profiler:wrap("getMeshOutward", Rig.getMeshOutward)

function Rig:getShoulderPoleAxis(mesh, RootBone, JointBone, EndBone, solverParams, state)
	local bonesKey = RootBone:to_string() .. "->" .. JointBone:to_string()
	if state.shoulderPoleAxisForBones ~= bonesKey or state.shoulderPoleAxisChoice == nil then
		local rootDir = getBoneDirCS(mesh, RootBone, JointBone)
		local sx, sy, sz = axisVectorsFromRot(mesh:GetBoneRotationByName(toBoneFName(RootBone), EBoneSpaces.ComponentSpace))
		local shoulderLong = chooseBestAxis(sx, sy, sz, rootDir)
		local handFallbackPoleRef = (solverParams.hand == Handed.Left) and (VEC_UNIT_Y_INVERSE or uevrUtils.vector(0, -1, 0)) or (VEC_UNIT_Y or uevrUtils.vector(0, 1, 0))
	    local poleAxisRefCS = getBendPoleRefCS(mesh, RootBone, JointBone, EndBone) or handFallbackPoleRef
		state.shoulderPoleAxisChoice = chooseBestPoleAxis(sx, sy, sz, shoulderLong.axis, poleAxisRefCS)
		state.shoulderPoleAxisForBones = bonesKey
	end
	return { pole = state.shoulderPoleAxisChoice }
end
Rig.getShoulderPoleAxis = uevrUtils.profiler:wrap("getShoulderPoleAxis", Rig.getShoulderPoleAxis)

function Rig:getJointPoleAxis(mesh, RootBone, JointBone, EndBone, solverParams, state)
	if state.bonesKey == nil then state.bonesKey = JointBone:to_string() .. "->" .. EndBone:to_string() end
	local bonesKey = state.bonesKey
	if state.jointPoleAxisChoice == nil or state.jointPoleAxisForBones ~= bonesKey then
		local jointDir = getBoneDirCS(mesh, JointBone, EndBone)
		local jx, jy, jz = axisVectorsFromRot(mesh:GetBoneRotationByName(toBoneFName(JointBone), EBoneSpaces.ComponentSpace))
		local jointLong = chooseBestAxis(jx, jy, jz, jointDir)
		local handFallbackPoleRef = (solverParams.hand == Handed.Left) and (VEC_UNIT_Y_INVERSE or uevrUtils.vector(0, -1, 0)) or (VEC_UNIT_Y or uevrUtils.vector(0, 1, 0))
		local poleAxisRefCS = getBendPoleRefCS(mesh, RootBone, JointBone, EndBone) or handFallbackPoleRef
		state.jointPoleAxisChoice = chooseBestPoleAxis(jx, jy, jz, jointLong.axis, poleAxisRefCS)
		state.jointPoleAxisForBones = bonesKey
	end
	return { pole = state.jointPoleAxisChoice }
end
Rig.getJointPoleAxis = uevrUtils.profiler:wrap("getJointPoleAxis", Rig.getJointPoleAxis)

function Rig:rotateShoulder(meshList, RootBone, JointBone, upperDirCS, axisShoulder, poleCS, state, smoothing)
	-- Shoulder: constrain swing + pole twist to prevent upper-arm axial roll drift.
	local shoulderAlignState = {
		composeOrderSwing = state.composeOrderSwingShoulder,
		composeOrderTwist = state.composeOrderTwistShoulder,
		lastDesiredPole = state.lastDesiredPoleShoulder,
		lastCurrentPole = state.lastCurrentPoleShoulder,
		lastTwistDeg = state.lastAlignTwistDegShoulder,
	}
	-- _dbg_ik_align_label = (solverParams.hand == Handed.Right and stopDebug == false) and "shoulder" or nil
	-- if solverParams.hand == Handed.Right and stopDebug == false then
	-- 	local preShoulderRot = mesh:GetBoneRotationByName(toBoneFName(RootBone), EBoneSpaces.ComponentSpace)
	-- 	if preShoulderRot ~= nil then
	-- 		print("Shoulder bone CS pre-align:", preShoulderRot.Pitch, preShoulderRot.Yaw, preShoulderRot.Roll)
	-- 	end
	-- end

	if smoothing > 0 then
		-- Pre-set shoulder to last IK value so alignBoneAxisToDirCS reads our output, not the animation override.
		-- Without this: when animation snaps the bone and curDir upperDirCS (swing < IK_MIN_SWING_DEG),
		-- the function returns currentRot unchanged passing animation noise straight through to the output.
		if state.lastShoulderCompRot ~= nil then
			for _, mesh in ipairs(meshList) do
				if mesh ~= nil then
					mesh:SetBoneRotationByName(toBoneFName(RootBone), state.lastShoulderCompRot, EBoneSpaces.ComponentSpace)
				end
			end
		end
	end

	local ShoulderCompRot
	local es = state and state.enhancedStabilityAlign or nil
	if es ~= nil then
		-- Opt-in path only. Default solvers never enter here.
		local axisForAlign = (es.shoulderSwingOnly == true) and {} or axisShoulder
		ShoulderCompRot = alignBoneAxisToDirCSEnhanced(meshList[1], RootBone, JointBone, upperDirCS, axisForAlign, poleCS, shoulderAlignState, es)
	else
		ShoulderCompRot = alignBoneAxisToDirCS(meshList[1], RootBone, JointBone, upperDirCS, axisShoulder, poleCS, shoulderAlignState)
	end
	state.composeOrderSwingShoulder = shoulderAlignState.composeOrderSwing
	state.composeOrderTwistShoulder = shoulderAlignState.composeOrderTwist
	state.lastDesiredPoleShoulder = shoulderAlignState.lastDesiredPole
	state.lastCurrentPoleShoulder = shoulderAlignState.lastCurrentPole
	state.lastAlignTwistDegShoulder = shoulderAlignState.lastTwistDeg
	if ShoulderCompRot ~= nil then
		if smoothing > 0 then
			-- Blend to suppress per-tick variation from animation-driven curDir (prevents chain cascade position jitter).
			if state.lastShoulderCompRot ~= nil then
				local a = 1 * (1 - smoothing)
				ShoulderCompRot = uevrUtils.rotator(
					---@diagnostic disable-next-line: undefined-field
					state.lastShoulderCompRot.Pitch + normalizeDeg180(ShoulderCompRot.Pitch - state.lastShoulderCompRot.Pitch) * a,
					---@diagnostic disable-next-line: undefined-field
					state.lastShoulderCompRot.Yaw   + normalizeDeg180(ShoulderCompRot.Yaw   - state.lastShoulderCompRot.Yaw)   * a,
					---@diagnostic disable-next-line: undefined-field
					state.lastShoulderCompRot.Roll  + normalizeDeg180(ShoulderCompRot.Roll  - state.lastShoulderCompRot.Roll)  * a)
			end
			for _, mesh in ipairs(meshList) do
				if mesh ~= nil then
					mesh:SetBoneRotationByName(toBoneFName(RootBone), ShoulderCompRot, EBoneSpaces.ComponentSpace)
				end
			end
			state.lastShoulderCompRot = ShoulderCompRot
		else
 			for _, mesh in ipairs(meshList) do
				if mesh ~= nil then
					mesh:SetBoneRotationByName(toBoneFName(RootBone), ShoulderCompRot, EBoneSpaces.ComponentSpace)
				end
			end
		end
	end
end
Rig.rotateShoulder = uevrUtils.profiler:wrap("rotateShoulder", Rig.rotateShoulder)

function Rig:rotateElbow(meshList, JointBone, EndBone, lowerDirCS, axisJoint, poleCS, state, smoothing)
	-- if solverParams.hand == Handed.Right and stopDebug == false then
	-- 	local dbgJointCS = mesh:GetBoneLocationByName(toBoneFName(JointBone), EBoneSpaces.ComponentSpace)
	-- 	if dbgJointCS ~= nil then
	-- 		print("IK dbg joint CS post-shoulder:", dbgJointCS.X, dbgJointCS.Y, dbgJointCS.Z)
	-- 	end
	-- end

	-- IMPORTANT: compute elbow AFTER applying shoulder.
	-- The joint's ComponentSpace basis changes when the parent rotates; using the pre-shoulder joint basis
	-- can leave the end bone significantly off even if the solver's OutEndWS hits the effector.
	local elbowAlignState = {
		composeOrderSwing = state.composeOrderSwingElbow,
		composeOrderTwist = state.composeOrderTwistElbow,
		lastDesiredPole = state.lastDesiredPoleElbow,
		lastCurrentPole = state.lastCurrentPoleElbow,
		lastTwistDeg = state.lastAlignTwistDegElbow,
	}
	--_dbg_ik_align_label = (solverParams.hand == Handed.Right and stopDebug == false) and "elbow" or nil
	if smoothing > 0 then
		-- Pre-set elbow to last IK value for the same reason as shoulder above.
		if state.lastElbowCompRot ~= nil then
			for _, mesh in ipairs(meshList) do
				if mesh ~= nil then
					mesh:SetBoneRotationByName(toBoneFName(JointBone), state.lastElbowCompRot, EBoneSpaces.ComponentSpace)
				end
			end
		end
	end

	local elbowRotCS
	local es = state and state.enhancedStabilityAlign or nil
	if es ~= nil then
		-- Opt-in path only. Default solvers never enter here.
		elbowRotCS = alignBoneAxisToDirCSEnhanced(meshList[1], JointBone, EndBone, lowerDirCS, axisJoint, poleCS, elbowAlignState, es)
	else
		elbowRotCS = alignBoneAxisToDirCS(meshList[1], JointBone, EndBone, lowerDirCS, axisJoint, poleCS, elbowAlignState)
	end
	--_dbg_ik_align_label = nil
	state.composeOrderSwingElbow = elbowAlignState.composeOrderSwing
	state.composeOrderTwistElbow = elbowAlignState.composeOrderTwist
	state.lastDesiredPoleElbow = elbowAlignState.lastDesiredPole
	state.lastCurrentPoleElbow = elbowAlignState.lastCurrentPole
	state.lastAlignTwistDegElbow = elbowAlignState.lastTwistDeg
	if elbowRotCS ~= nil then
		if smoothing > 0 then
			-- Same blend as shoulder to stabilise end-bone position.
			if state ~= nil and state.lastElbowCompRot ~= nil then
				local a = 1 * (1 - smoothing)
				elbowRotCS = uevrUtils.rotator(
					state.lastElbowCompRot.Pitch + normalizeDeg180(elbowRotCS.Pitch - state.lastElbowCompRot.Pitch) * a,
					state.lastElbowCompRot.Yaw   + normalizeDeg180(elbowRotCS.Yaw   - state.lastElbowCompRot.Yaw)   * a,
					state.lastElbowCompRot.Roll  + normalizeDeg180(elbowRotCS.Roll  - state.lastElbowCompRot.Roll)  * a)
			end
		end
		for _, mesh in ipairs(meshList) do
			if mesh ~= nil then
				mesh:SetBoneRotationByName(toBoneFName(JointBone), elbowRotCS, EBoneSpaces.ComponentSpace)
			end
		end
		-- Cache last lower-axis for next tick to improve stability if needed.
		if state then state.lastLowerDirCS = lowerDirCS; state.lastElbowCompRot = elbowRotCS end
	end
	return elbowRotCS
end
Rig.rotateElbow = uevrUtils.profiler:wrap("rotateElbow", Rig.rotateElbow)

local function cacheMeshBoneRotationState(mesh, meshID, boneFName, state)
	local parentBoneFName = mesh:GetParentBone(toBoneFName(boneFName))
	local parentTransform = nil
	if parentBoneFName ~= nil and parentBoneFName:to_string() ~= "None" then
		parentTransform = mesh:GetBoneTransformByName(toBoneFName(parentBoneFName), EBoneSpaces.ComponentSpace)
	end
	local rotationWithRespectToParentBone = mesh:GetBoneRotationByName(toBoneFName(boneFName), EBoneSpaces.ComponentSpace)
	if parentTransform ~= nil then
		local endBoneTransform = mesh:GetBoneTransformByName(toBoneFName(boneFName), EBoneSpaces.ComponentSpace)
		local localTransform = kismet_math_library:ComposeTransforms(endBoneTransform, kismet_math_library:InvertTransform(parentTransform))
		rotationWithRespectToParentBone = kismet_math_library:TransformRotation(localTransform, uevrUtils.rotator(0,0,0))
	end
	state.meshDefaultRotation[meshID] = rotationWithRespectToParentBone
end

local function setBoneRotationByName(mesh, meshID, boneFName, finalRot, state, boneLockPitch, boneLockYaw, boneLockRoll)
	if state.meshDefaultRotation[meshID] == nil then
		cacheMeshBoneRotationState(mesh, meshID, boneFName, state)
	end

	if boneLockPitch or boneLockYaw or boneLockRoll then
		local initialRot = state.meshDefaultRotation[meshID]
		local parentTransform = mesh:GetBoneTransformByName(mesh:GetParentBone(toBoneFName(boneFName)), EBoneSpaces.ComponentSpace)
		if parentTransform ~= nil then
			initialRot = kismet_math_library:TransformRotation(parentTransform, initialRot)
		end

		-- Doesnt propagate
		-- if boneLockPitch == false then initialRot.Pitch = finalRot.Pitch end
		-- if boneLockYaw == false then initialRot.Yaw = finalRot.Yaw end
		-- if boneLockRoll == false then initialRot.Roll = finalRot.Roll end
		-- mesh:SetBoneRotationByName(toBoneFName(boneFName), initialRot, EBoneSpaces.ComponentSpace)

		-- This method modifies the original finalHandRotCS which should propagate to wrist bone if used
		if boneLockPitch then finalRot.Pitch = initialRot.Pitch end
		if boneLockYaw   then finalRot.Yaw   = initialRot.Yaw   end
		if boneLockRoll  then finalRot.Roll  = initialRot.Roll  end
		mesh:SetBoneRotationByName(toBoneFName(boneFName), finalRot, EBoneSpaces.ComponentSpace)
	else
		mesh:SetBoneRotationByName(toBoneFName(boneFName), finalRot, EBoneSpaces.ComponentSpace)
	end
end

--This function does the final hand and optional wrist rotation using the controller rotation and a user defined offset, endBoneRotation
function Rig:rotateHandAndWrist(meshList, endBone, wristBone, endBoneRotation, controllerRotWS, controllerRotCS, compToWorld, state, smoothing, endBoneLockPitch, endBoneLockYaw, endBoneLockRoll)
	local finalHandRotCS = nil
	if state.meshDefaultRotation == nil then state.meshDefaultRotation = {} end
	if smoothing > 0 then
		-- When the endbone and wrist bone are not rotated at all (this code commented out), the hand mesh still jitters
		-- so although this helps its is not a complete fix for hand stability.

		-- WHY WS smoothing + WS stamp:
		-- Smoothing controllerRotCS (CS) embeds compToWorld noise because
		--   controllerRotCS = InverseTransformRotation(compToWorld, controllerRotWS)
		-- and compToWorld has ~0.04 deg/tick noise from VR tracking.
		-- Rendered bone WS = compToWorld * CS_value, so noise doubles on screen.
		--
		-- FIX: smooth controllerRotWS (no compToWorld involved), then compute:
		--   finalHandWorldRot = ComposeRotators(endBoneRotation, smoothedControllerRotWS)
		-- This equals TransformRotation(compToWorld, ComposeRotators(endBoneRotation, InverseTransformRotation(compToWorld, smoothedControllerRotWS)))
		-- with compToWorld canceling exactly: R_ctw * R_e * R_ctw^{-1} * R_ctrl_WS = R_ctrl_WS * R_e
		-- Stamping in WorldSpace: rendered WS = finalHandWorldRot directly (no compToWorld on render path).
		local rotSmoothing = smoothing --or 0.85
		local smoothedControllerRotWS = controllerRotWS
		if state ~= nil and state.lastControllerRotWS ~= nil then
			local prev = state.lastControllerRotWS
			if prev ~= nil then
				local pP = prev.Pitch; local pY = prev.Yaw; local pR = prev.Roll
				local cP = controllerRotWS.Pitch; local cY = controllerRotWS.Yaw; local cR = controllerRotWS.Roll
				smoothedControllerRotWS = uevrUtils.rotator(
					pP + normalizeDeg180(cP - pP) * (1.0 - rotSmoothing),
					pY + normalizeDeg180(cY - pY) * (1.0 - rotSmoothing),
					pR + normalizeDeg180(cR - pR) * (1.0 - rotSmoothing))
			end
		end
		if state ~= nil then state.lastControllerRotWS = smoothedControllerRotWS end
		-- WS-stable hand rotation: compToWorld cancels exactly in the derivation.
		local finalHandWorldRot = kismet_math_library:ComposeRotators(endBoneRotation, smoothedControllerRotWS)
		-- CS version still needed for twist bone computation downstream.
		local smoothedControllerRotCS = kismet_math_library:InverseTransformRotation(compToWorld, smoothedControllerRotWS)
		finalHandRotCS = kismet_math_library:ComposeRotators(endBoneRotation, smoothedControllerRotCS)

		for meshID, mesh in ipairs(meshList) do
			if mesh ~= nil then
				--mesh:SetBoneRotationByName(toBoneFName(endBone), finalHandWorldRot, EBoneSpaces.WorldSpace)
				setBoneRotationByName(mesh, meshID, endBone, finalHandRotCS, state, endBoneLockPitch, endBoneLockYaw, endBoneLockRoll)
			end
		end
		if wristBone ~= nil and wristBone ~= "" then
			for _, mesh in ipairs(meshList) do
				if mesh ~= nil then
					mesh:SetBoneRotationByName(toBoneFName(wristBone), finalHandWorldRot, EBoneSpaces.WorldSpace)
				end
			end
		end
	else
		finalHandRotCS = kismet_math_library:ComposeRotators(endBoneRotation, controllerRotCS)
		for meshID, mesh in ipairs(meshList) do
			if mesh ~= nil then
				setBoneRotationByName(mesh, meshID, endBone, finalHandRotCS, state, endBoneLockPitch, endBoneLockYaw, endBoneLockRoll)
			end
		end
		if wristBone ~= nil and wristBone ~= "" then
			for _, mesh in ipairs(meshList) do
				if mesh ~= nil then
					mesh:SetBoneRotationByName(toBoneFName(wristBone), finalHandRotCS, EBoneSpaces.ComponentSpace)
				end
			end
		end
	end

	return finalHandRotCS
end
Rig.rotateHandAndWrist = uevrUtils.profiler:wrap("rotateHandAndWrist", Rig.rotateHandAndWrist)

function Rig:twistForearm(meshList, lowerDirCS, lowerArmRotCS, finalHandCompRot, twistBones, forearmTwistMax, wristTwistMax, state, incrementalForearmTwist)
	if state ~= nil and lowerArmRotCS ~= nil and #twistBones > 0 then
		-- Extract the wrist forearm "tube twist" (pronation/supination) around the forearm axis.
		-- We use a quaternion swing twist decomposition of the relative rotation (lowerArmRotCS -> finalHandCompRot)
		-- so wrist pitch/yaw doesn't leak into the twist value.
--if solverParams.hand == Handed.Left and stopDebug == false then print("Lower arm rot CS:", lowerArmRotCS.Pitch, lowerArmRotCS.Yaw, lowerArmRotCS.Roll) end
--if solverParams.hand == Handed.Left and stopDebug == false then print("Final hand comp rot:", finalHandCompRot.Pitch, finalHandCompRot.Yaw, finalHandCompRot.Roll) end
--if solverParams.hand == Handed.Left and stopDebug == false then print("Lower dir CS:", lowerDirCS.X, lowerDirCS.Y, lowerDirCS.Z) end
		local swingQuatX, swingQuatY, swingQuatZ, swingQuatW = nil, nil, nil, nil
		local twistAngleDeg
		twistAngleDeg, swingQuatX, swingQuatY, swingQuatZ, swingQuatW = mathLib.computeSwingTwistAroundAxis_Rotators(lowerArmRotCS, finalHandCompRot, lowerDirCS)
		_reuseWristSwingQuat.X = swingQuatX
		_reuseWristSwingQuat.Y = swingQuatY
		_reuseWristSwingQuat.Z = swingQuatZ
		_reuseWristSwingQuat.W = swingQuatW

		-- -- Twist direction convention: for this rig/controller mapping, negate to match physical wrist roll.
		-- if twistAngleDeg ~= nil then
		-- 	twistAngleDeg = -twistAngleDeg
		-- end
--if solverParams.hand == Handed.Left and stopDebug == false then print("Forearm twist angle deg:", twistAngleDeg) end
		twistAngleDeg = normalizeDeg180(twistAngleDeg)
		if twistAngleDeg == nil then
			return
		end

		-- Atomic Heart needed this method for the left arm, otherwise pitch affected the twist 
		--and it twisted in the wrong direction. Looked like some kind of gimbal lock
		if incrementalForearmTwist then
			local previousHandRot = state.lastForearmTwistHandRotCS
			local previousArmRot = state.lastForearmTwistArmRotCS
			local accumulatedTwist = state.lastForearmTwistDegApplied or 0.0

			if previousHandRot ~= nil and previousArmRot ~= nil then
				local handDelta = mathLib.computeTwistDegAroundAxis_Rotators(previousHandRot, finalHandCompRot, lowerDirCS)
				local armDelta = mathLib.computeTwistDegAroundAxis_Rotators(previousArmRot, lowerArmRotCS, lowerDirCS)
				handDelta = normalizeDeg180(handDelta) or 0.0
				armDelta = normalizeDeg180(armDelta) or 0.0
				local relativeDelta = normalizeDeg180(handDelta - armDelta) or 0.0

				-- Tracking cannot rotate an anatomical wrist this far in one frame.
				if math.abs(relativeDelta) < 45.0 then
					accumulatedTwist = accumulatedTwist + relativeDelta
				end
			end

			state.lastForearmTwistHandRotCS = uevrUtils.rotator(
				finalHandCompRot.Pitch or 0.0,
				finalHandCompRot.Yaw or 0.0,
				finalHandCompRot.Roll or 0.0)
			state.lastForearmTwistArmRotCS = uevrUtils.rotator(
				lowerArmRotCS.Pitch or 0.0,
				lowerArmRotCS.Yaw or 0.0,
				lowerArmRotCS.Roll or 0.0)
			twistAngleDeg = accumulatedTwist
		end
--if solverParams.hand == Handed.Left and stopDebug == false then print("Forearm twist angle deg 2:", twistAngleDeg) end
		-- Unwrap against the last *applied* twist (clamped), to avoid the cached value drifting by full turns.
		-- local prevTwistDeg = state.lastForearmTwistDegApplied or state.lastForearmTwistDegUnwrapped
		-- if prevTwistDeg ~= nil then
		-- 	twistAngleDeg = unwrapDeg(twistAngleDeg, prevTwistDeg)
		-- end
		-- state.lastForearmTwistDegUnwrapped = twistAngleDeg
--if solverParams.hand == Handed.Left and stopDebug == false then print("Forearm twist angle deg: 3", twistAngleDeg) end

		-- Clamp to physically plausible forearm pronation/supination.
		local twistMax = forearmTwistMax or wristTwistMax or FOREARM_TWIST_MAX_DEG_DEFAULT

		local appliedTwistDeg = twistAngleDeg
		if appliedTwistDeg ~= nil and twistMax ~= nil then
			appliedTwistDeg = kismet_math_library:FClamp(appliedTwistDeg, -twistMax, twistMax)
		end

		-- state.lastForearmTwistDegApplied = appliedTwistDeg
		twistAngleDeg = appliedTwistDeg
		if incrementalForearmTwist then
			state.lastForearmTwistDegApplied = appliedTwistDeg
		end
--if solverParams.hand == Handed.Left and stopDebug == false then print("Forearm twist angle deg: 4", twistAngleDeg) end
--if solverParams.hand == Handed.Left and stopDebug == false then print("Forearm twist angle deg: 5", twistAngleDeg) end

		local hasTwist = twistAngleDeg ~= nil and math.abs(twistAngleDeg) >= IK_MIN_TWIST_DEG
		-- local hasSwingForFirstTwistBone = swingQuatW ~= nil and FIRST_TWIST_BONE_WRIST_SWING_ALPHA > 0.0
		-- if not hasTwist and not hasSwingForFirstTwistBone then
		-- 	return
		-- end

		local tubeAxisX = lowerDirCS.X or lowerDirCS.x or lowerDirCS[1] or 0.0
		local tubeAxisY = lowerDirCS.Y or lowerDirCS.y or lowerDirCS[2] or 0.0
		local tubeAxisZ = lowerDirCS.Z or lowerDirCS.z or lowerDirCS[3] or 0.0
		local tubeQuat = { X = 0.0, Y = 0.0, Z = 0.0, W = 1.0 }
		local halfDegToRad = math.pi / 360.0
		local rotateVector = mathLib.vectorRotate
		local rotateVectorQuat = mathLib.vectorRotate_Quat
		local makeRotFromXZ = mathLib.makeRotFromXZ

        for index, entry in ipairs(twistBones) do
            local boneFName = entry._fname
            if boneFName == nil then
				boneFName = uevrUtils.fname_from_string(entry.bone)
				entry._fname = boneFName
			end
            local vecs = state.twistBoneVecs and state.twistBoneVecs[entry.bone]
            if vecs == nil then break end

            -- Step 1: bring stored bone-local axes into current component space.
            -- GreaterGreater_VectorRotator(v_local, rot) = pure matrix multiply, no Euler decomposition.
            local xCS = rotateVector(vecs.x, lowerArmRotCS)
            local zCS = rotateVector(vecs.z, lowerArmRotCS)
			--local rollCS = nil
			--if hasTwist then
				local roll = entry.fraction or entry.roll or 0.0
				local halfAngle = (twistAngleDeg * roll) * halfDegToRad
				local sinHalf = math.sin(halfAngle)
				tubeQuat.X = tubeAxisX * sinHalf
				tubeQuat.Y = tubeAxisY * sinHalf
				tubeQuat.Z = tubeAxisZ * sinHalf
				tubeQuat.W = math.cos(halfAngle)
				xCS = rotateVectorQuat(xCS, tubeQuat, false)
				zCS = rotateVectorQuat(zCS, tubeQuat, false)
				--rollCS = makeRotFromXZ(xCS, zCS, true)
			--end

			local swingWeightPitch = entry.pitch or 0.0
			local swingWeightYaw = entry.yaw or 0.0
			if swingWeightPitch ~= 0 or swingWeightYaw ~= 0 then
				--local swingWeight = FIRST_TWIST_BONE_WRIST_SWING_ALPHA
				local swungXCS = rotateVectorQuat(xCS, _reuseWristSwingQuat, false)
				local swungZCS = rotateVectorQuat(zCS, _reuseWristSwingQuat, false)
				local blendedX = safeNormalize((xCS * (1.0 - swingWeightPitch)) + (swungXCS * swingWeightPitch))
				local blendedZ = safeNormalize((zCS * (1.0 - swingWeightYaw)) + (swungZCS * swingWeightYaw))
				xCS = blendedX or xCS
				zCS = blendedZ or zCS
			end

            -- Step 3: reconstruct CS rotation from two vectors no Euler composition at all.
            local finalCS = makeRotFromXZ(xCS, zCS, true)
			for _, mesh in ipairs(meshList) do
				if mesh ~= nil then
					mesh:SetBoneRotationByName(toBoneFName(boneFName), finalCS, EBoneSpaces.ComponentSpace)
				end
			end
        end
    end
end
Rig.twistForearm = uevrUtils.profiler:wrap("twistForearm", Rig.twistForearm)

function Rig:setTwistBonePitch(boneName, pitch)
	--print("setTwistBonePitch", boneName, pitch,self.activeSolvers, #self.activeSolvers)
	for solverId, solver in pairs(self.activeSolvers) do
		--print("setTwistBonePitch called for bone " .. tostring(boneName) .. " with pitch " .. tostring(pitch) .. " in solver " .. tostring(solverId))
		if solver.twistBones ~= nil then
			for _, entry in pairs(solver.twistBones) do
				if entry.bone == boneName then
					--print("Setting twist bone " .. boneName .. " pitch to " .. tostring(pitch) .. " in solver " .. tostring(solverId))
					entry.pitch = pitch
				end
			end
		end
	end
end

-- Print all bone transforms in bone-local space for a mesh/component
function M.printMeshBoneTransforms(mesh, boneSpace)
	if mesh == nil or uevrUtils.validate_object(mesh) == nil then
		M.print("printMeshBoneTransforms: mesh is nil or invalid", LogLevel.Warning)
		return
	end
	boneSpace = boneSpace or 0
	local boneNames = uevrUtils.getBoneNames(mesh)
	for i, bname in ipairs(boneNames) do
		local f = uevrUtils.fname_from_string(bname)
		local localRot, localLoc, localScale = nil, nil, nil
		-- animation.getBoneSpaceLocalTransform returns (rot, loc, scale, parentTransform)
		-- if animation and animation.getBoneSpaceLocalTransform then
		-- 	localRot, localLoc, localScale = animation.getBoneSpaceLocalTransform(mesh, f, boneSpace)
		-- end
		if localRot == nil then
			-- fallback: compute via component transforms
			local parentTransform = mesh:GetBoneTransformByName(mesh:GetParentBone(toBoneFName(f)), boneSpace)
			local wTransform = mesh:GetBoneTransformByName(toBoneFName(f), boneSpace)
			local localTransform = kismet_math_library:ComposeTransforms(wTransform, kismet_math_library:InvertTransform(parentTransform))
			localLoc = uevrUtils.vector(0,0,0)
			local localRotTmp = uevrUtils.rotator(0,0,0)
			local localScaleTmp = uevrUtils.vector(0,0,0)
			kismet_math_library:BreakTransform(localTransform, localLoc, localRotTmp, localScaleTmp)
			localRot = kismet_math_library:TransformRotation(localTransform, uevrUtils.rotator(0,0,0))
			localScale = localScaleTmp or wTransform.Scale3D
		end

		if localLoc ~= nil and localRot ~= nil then
			M.print(string.format("%s: Loc=(%.3f,%.3f,%.3f) Rot=(%.3f,%.3f,%.3f) Scale=(%.3f,%.3f,%.3f)",
				bname,
				(localLoc.X or localLoc[1] or 0), (localLoc.Y or localLoc[2] or 0), (localLoc.Z or localLoc[3] or 0),
				(localRot.Pitch or localRot.pitch or 0), (localRot.Yaw or localRot.yaw or 0), (localRot.Roll or localRot.roll or 0),
				(localScale and (localScale.X or localScale[1] or 0) or 0), (localScale and (localScale.Y or localScale[2] or 0) or 0), (localScale and (localScale.Z or localScale[3] or 0) or 0)
			), LogLevel.Info)
		else
			M.print(tostring(bname) .. ": <could not resolve local transform>", LogLevel.Warning)
		end
	end
end

function Rig:printMeshBoneTransforms(solverID)
	local active = self.activeSolvers and self.activeSolvers[solverID]
	if active == nil then
        M.print("printMeshBoneTransforms: no solver params for solverID " .. tostring(solverID), LogLevel.Warning)
        return
    end
	local mesh = active.mesh
    if mesh == nil then
        M.print("printMeshBoneTransforms: could not resolve mesh for solverID " .. tostring(solverID), LogLevel.Warning)
        return
    end
    M.printMeshBoneTransforms(mesh, EBoneSpaces.ComponentSpace)
end

function Rig:initializeSolverState(active)
	local state = active and active.state or nil
	local mesh = active and active.meshList and active.meshList[1] or nil
	if state == nil or mesh == nil then return end

	state.twistBoneVecs = state.twistBoneVecs or {}
	local lowerArmRot = mesh:GetBoneRotationByName(active.jointBoneFName or uevrUtils.fname_from_string(active.jointBone), EBoneSpaces.ComponentSpace)
	local twistBones = active.twistBones
	if lowerArmRot ~= nil and twistBones ~= nil then
		for _, entry in ipairs(twistBones) do
			local boneName = entry and entry.bone
			if boneName ~= nil and state.twistBoneVecs[boneName] == nil then
				local boneCS = mesh:GetBoneRotationByName(toBoneFName(boneName), EBoneSpaces.ComponentSpace)
				if boneCS ~= nil then
					state.twistBoneVecs[boneName] = {
						x = kismet_math_library:LessLess_VectorRotator(kismet_math_library:GetForwardVector(boneCS), lowerArmRot),
						z = kismet_math_library:LessLess_VectorRotator(kismet_math_library:GetUpVector(boneCS),    lowerArmRot),
					}
				end
			end
		end
	end
end

M.enableAnimationBoneListPrintout = false
function Rig:setActive(solverId, value)
    if value == nil then value = true end
	if self.rigId == nil then
		self.rigId = paramManager:getActiveProfile()
	end
    self.activeSolvers = self.activeSolvers or {}
    self.solverOrderDirty = true
    self.activeSolvers[solverId] = nil
	if self.defaultSolverId == solverId then
		self.defaultSolverId = nil
	end
    if value == true then
		local rigParams = getRigParams(self.rigId)
		local solverParams = getSolverParams(self.rigId, solverId)
		if solverParams ~= nil and rigParams ~= nil then
			local mesh = self.meshList[1]
            if mesh == nil or mesh.GetBoneLocationByName == nil then
                M.print("setActive: Missing or invalid mesh " .. tostring(solverId), LogLevel.Warning)
                return
            end

            local parentBones = getAncestorBones(mesh, solverParams["end_bone"], 3) -- ensure bone ancestry cache is built
            if #parentBones ~= 3 then
                M.print("setActive: incorrect bones for solverId " .. tostring(solverId), LogLevel.Warning)
                return
            end

            local controller = nil
            if solverParams["end_control_type"] == M.ControllerType.LEFT_CONTROLLER then
                controller = controllers.getController(Handed.Left, true) or controllers.getController(Handed.Left) -- cached first: the class scan cannot see a fresh, not-yet-adopted controller
            else
                controller = controllers.getController(Handed.Right, true) or controllers.getController(Handed.Right)
            end
            if controller == nil then
                M.print("setActive: missing controller for solverId " .. tostring(solverId), LogLevel.Warning)
                --This can happen if the rig is being activated before the controllers are ready
				--Try again in a second
				delay(1000, function()
					self:setActive(solverId, value)
				end)
				return
            end

			local animationMesh = self.animationMesh
			if animationMesh == nil then
				if rigParams.animation_mesh == "Custom" then
					if getCustomAnimationIKComponent ~= nil then
						animationMesh = getCustomAnimationIKComponent(self.rigId)
					end
				else
					animationMesh = uevrUtils.getObjectFromDescriptor(rigParams.animation_mesh, false)
				end
				self.animationMesh = animationMesh
            end

            --this just completely overrides control
            -- if mesh ~= nil and animationMesh ~= nil then
            --     mesh:SetMasterPoseComponent(animationMesh, true)
            -- end

			M.print("Using bones " .. solverParams["end_bone"] .. ", " ..  parentBones[#parentBones - 1] .. ", " .. parentBones[#parentBones] .. " for solverId " .. tostring(solverId), LogLevel.Info)

			if solverParams["start_bone"] == "" then solverParams["start_bone"] = nil end
			if solverParams["joint_bone"] == "" then solverParams["joint_bone"] = nil end

            self.activeSolvers[solverId] = {
                meshList = self.meshList,
                --animationMesh = animationMesh,
                startBone = solverParams["start_bone"] or parentBones[#parentBones], --upperarm
                jointBone = solverParams["joint_bone"] or parentBones[#parentBones - 1], --lowerarm
                endBone = solverParams["end_bone"], --hand
                wristBone = solverParams["wrist_bone"] or "",
                controller = controller,
                hand = solverParams["end_control_type"],
                solverType = solverParams["solver_type"] or solverParams["solver"] or M.SolverType.TWO_BONE,
                sortOrder = solverParams["sort_order"] or 0,
                handOffset = solverParams["end_bone_offset"] and uevrUtils.vector(solverParams["end_bone_offset"]) or uevrUtils.vector(0,0,0),
                endBoneRotation = solverParams["end_bone_rotation"] and uevrUtils.rotator(solverParams["end_bone_rotation"]) or uevrUtils.rotator(0,0,0),
                allowWristAffectsElbow = solverParams["allow_wrist_affects_elbow"] or false,
                allowStretch = solverParams["allow_stretch"] or false,
                startStretchRatio = solverParams["start_stretch_ratio"] or 0.0,
                maxStretchScale = solverParams["max_stretch_scale"] or 0.0,
                wristTwistInfluence = solverParams["wrist_twist_influence"] or 0.35,
                wristTwistMax = solverParams["wrist_twist_max"] or 75,
				forearmTwistMax = solverParams["forearm_twist_max"] or FOREARM_TWIST_MAX_DEG_DEFAULT,
                twistBones = solverParams["twist_bones"] or {},
				incrementalForearmTwist = solverParams["incremental_forearm_twist"] or false,
				smoothing = solverParams["smoothing"] or 0.0,
				rotSmoothing = solverParams["rot_smoothing"] or 0.85,
				enhancedStability = solverParams["enhanced_stability"] or false,
				poleProjMinLen = solverParams["pole_proj_min_len"],
				useHemisphereLock = solverParams["use_hemisphere_lock"],
				maxTwistDeltaDeg = solverParams["max_twist_delta_deg"],
				shoulderSwingOnly = solverParams["shoulder_swing_only"] or false,
				endBoneLockPitch = solverParams["end_bone_lock_pitch"] or false,
				endBoneLockYaw = solverParams["end_bone_lock_yaw"] or false,
				endBoneLockRoll = solverParams["end_bone_lock_roll"] or false,
                --animationLocationOffset = rigParams["animation_location_offset"] and uevrUtils.vector(rigParams["animation_location_offset"]) or uevrUtils.vector(0,0,0),
				--animationRotationOffset = rigParams["animation_rotation_offset"] and uevrUtils.rotator(rigParams["animation_rotation_offset"]) or uevrUtils.rotator(0,0,0),
				state = newIKState(),
            }

			local active = self.activeSolvers[solverId]
			active.startBoneFName = uevrUtils.fname_from_string(active.startBone)
			active.jointBoneFName = uevrUtils.fname_from_string(active.jointBone)
			active.endBoneFName = uevrUtils.fname_from_string(active.endBone)
			active.wristBoneFName = (active.wristBone ~= nil and active.wristBone ~= "") and uevrUtils.fname_from_string(active.wristBone) or nil

			M.print("Final bones " .. active.endBone .. ", " .. active.jointBone .. ", " .. active.startBone .. " for solverId " .. tostring(solverId), LogLevel.Info)

            mesh.RelativeLocation = rigParams["mesh_location_offset"] and uevrUtils.vector(rigParams["mesh_location_offset"]) or uevrUtils.vector(0,0,0)
            if self.enhancedStabilization then
                self:updateEnhancedMeshRotation(mesh, getPawnRootComponent(), false)
            else
                mesh.RelativeRotation = rigParams["mesh_rotation_offset"] and uevrUtils.rotator(rigParams["mesh_rotation_offset"]) or uevrUtils.rotator(0,0,0)
            end
            mesh.RelativeScale3D = rigParams["mesh_scale_offset"] and uevrUtils.vector(rigParams["mesh_scale_offset"]) or uevrUtils.vector(1,1,1)

			self:initializeSolverState(active)
			if self.defaultSolverId == nil then
				self.defaultSolverId = solverId
			end

            local function captureInitialTransforms()
                local initialTransforms = {}
                local boneNames = uevrUtils.getBoneNames(mesh)
                for i, boneName in ipairs(boneNames) do
                    if M.enableAnimationBoneListPrintout then
                        print(i, "boneName: " , boneName)
                    end
                    local f = uevrUtils.fname_from_string(boneName)
                    table.insert(initialTransforms, {boneName = boneName, transform = mesh:GetBoneTransformByName(toBoneFName(f), EBoneSpaces.ComponentSpace)})
                end
                self.initialTransforms = initialTransforms
            end
            captureInitialTransforms()
            -- Re-snapshot after the component has settled: right after creation the component-space
            -- transforms can still be identity/uninitialised (first-tick re-init, see initializeRigState),
            -- and setInitialTransform() would later restore that garbage pose after animate-from-mesh.
            for _, delayMs in ipairs({600, 1500, 3000}) do
                uevrUtils.setTimeout(delayMs, function()
                    if isRegisteredInstance(self) and self.meshList ~= nil then
                        captureInitialTransforms()
                    end
                end)
            end
            self.rootBone = mesh:GetBoneName(0):to_string()


			-- -- Capture ancestor bones (shoulder->root) local transforms for later use.
			-- -- Get full ancestor chain from end bone and use indices 4..end as requested.
			-- local ancestors = getAncestorBones(mesh, solverParams["end_bone"], 100)
			-- local ancestorLocalTransforms = {}
			-- if ancestors ~= nil and #ancestors >= 4 then
			-- 	for idx = 4, #ancestors do
			-- 		local boneName = ancestors[idx]
            --         if boneName == "None" then break end
			-- 		if boneName ~= nil then
			-- 			local f = uevrUtils.fname_from_string(boneName)
            --             ancestorLocalTransforms[boneName] = mesh:GetBoneTransformByName(toBoneFName(f), EBoneSpaces.ComponentSpace)
			-- 		end
			-- 	end
			-- end
			-- active.ancestorLocalTransforms = ancestorLocalTransforms
        end
	else --deactivate solver
		self.activeSolvers[solverId] = nil
    end
end

function Rig:addSolver(solverId)
	self:setActive(solverId, true)
end

-- function on_pre_engine_tick(engine, delta)
-- 	if meshCopy ~= nil then
-- 		SolveVRArmIK(
-- 			meshCopy,               -- UPoseableMeshComponent
-- 			"r_UpperArm_JNT",           -- e.g. "UpperArm_L"
-- 			"r_LowerArm_JNT",          -- e.g. "LowerArm_L"
-- 			"r_Hand_JNT",            -- e.g. "Hand_L"
-- 			"r_wrist_JNT",
-- 			controllers.getControllerLocation(Handed.Right),       -- VR controller world location (FVector)
-- 			controllers.getControllerRotation(Handed.Right),       -- VR controller world rotation (FRotator)
-- 			uevrUtils.vector(-8,0,0),         -- Offset from controller hand bone (controller-local)
-- 			false,       -- AllowStretch (rotation-only solve cannot magically extend the arm)
-- 			0.0,  -- float
-- 			0.0,     -- float,
-- 			{  -- TwistBones: distribute wrist roll across the three forearm pronation bones
-- 				{ bone = "r_lowerTwistUp_JNT",  fraction = 0.25 }, -- nearest elbow
-- 				{ bone = "r_lowerTwistMid_JNT", fraction = 0.50 },
-- 				{ bone = "r_lowerTwistLow_JNT", fraction = 0.75 }, -- nearest wrist
-- 				--{ bone = "r_wrist_JNT", fraction = 0.90 }, -- nearest wrist
-- 				-- r_wrist_JNT is a flexion bone (rest rotation differs ~90?) not a twist bone
-- 			}

-- 		)
-- 	end
-- end

--if not instances are instantiated this still saves the params to file
local createConfigMonitor = doOnce(function()
    uevrUtils.registerUEVRCallback("on_ik_config_param_change", function(key, value, persist)
		saveParameter(key, value, persist)
    end)
end, Once.EVER)

function M.init(m_isDeveloperMode, logLevel)
    if logLevel ~= nil then
        M.setLogLevel(logLevel)
    end
    if m_isDeveloperMode == nil and uevrUtils.getDeveloperMode() ~= nil then
        m_isDeveloperMode = uevrUtils.getDeveloperMode()
    end

    if m_isDeveloperMode then
        ikConfigDev = require("libs/config/ik_config_dev")
        ikConfigDev.init(paramManager)

        createConfigMonitor()
    end

    isDeveloperMode = m_isDeveloperMode
end

function M.registerOnMeshCreatedCallback(callback)
	table.insert(meshCreatedCallbackList, callback)
end

function M.registerOnDestroyCallback(callback)
	table.insert(instanceDestroyedCallbackList, callback)
end

function M.setAutoCreateArms(val)
	autoCreateArms = val
end

local function tryAutoCreateArms()
	if autoCreateArms and not M.exists()then
		--see if the defaults params file exists
		local paramsFile = "hands_parameters"
		local mesh = paramManager:getFromActiveProfile("mesh")
		if mesh ~= nil and mesh ~= "" then
			if M.new({ animationsFile = paramsFile }) ~= nil then
				M.print("Auto-created IK arms with params from " .. paramsFile)
			end
		end
	end
end
setInterval(1000, tryAutoCreateArms)

-- IK targets follow the accessory attachment socket. If that attachment is parented under
-- the IK poseable mesh, solving creates a feedback loop ? accessories uses this list to
-- detect that cycle and temporarily reparent the attachment to a motion controller.
uevrUtils.registerUEVRCallback("accessory_attach_components", function(handed, outList)
	if type(outList) ~= "table" then return end
	if #_rigInstances == 0 then return end
	local meshes = _rigInstances[#_rigInstances].meshList
	if meshes == nil then return end
	for _, mesh in pairs(meshes) do
		if isMeshAlive(mesh) then
			table.insert(outList, mesh)
		end
	end
end)

-- Targets the hand at parentAttachment's socket (+ loc/rot in socket space) instead of its controller.
-- blendTime (optional, seconds): ease from the controller onto the socket instead of snapping.
function M.setAccessoryTarget(handed, parentAttachment, socketName, attachType, loc, rot, blendTime)
	accessoryStatus = accessoryStatus or {}
    accessoryStatus[handed] = {
        parentAttachment = parentAttachment,
        socketName = socketName,
        attachType = attachType,
        loc = loc,
        rot = rot,
        blendTime = blendTime,
        blendElapsed = 0,
    }
end

-- Back to the controller. blendTime (optional, seconds): ease from the socket instead of snapping.
function M.clearAccessoryTarget(handed, blendTime)
	accessoryStatus = accessoryStatus or {}
	local handStatus = accessoryStatus[handed]
	if handStatus ~= nil and blendTime ~= nil and blendTime > 0 then
		-- a release that starts mid attach-blend continues from where the hand is now
		local alpha = handStatus.releasing and 0 or getBlendAlpha(handStatus)
		handStatus.releasing = true
		handStatus.blendTime = blendTime
		handStatus.blendElapsed = (1 - alpha) * blendTime
	else
		accessoryStatus[handed] = nil
	end
end

-- Stalker 2: off while stalker2/ik_arms.lua is installed as the libs/hands.lua IK delegate. The glove
-- listeners in hands.lua already route these events through it, with the glove-tuned offsets converted
-- for the rig; consuming them raw here as well would race that.
local handleAccessoryEvents = true
function M.setHandleAccessoryEvents(val)
	handleAccessoryEvents = val
end

uevrUtils.registerUEVRCallback("on_accessory_attach", function(handed, parentAttachment, socketName, attachType, loc, rot)
	if handleAccessoryEvents then
		M.setAccessoryTarget(handed, parentAttachment, socketName, attachType, loc, rot)
	end
end)

uevrUtils.registerUEVRCallback("on_accessory_detach", function(handed)
	if handleAccessoryEvents then
		M.clearAccessoryTarget(handed)
	end
end)

uevrUtils.registerPreEngineTickCallback(function(engine, delta)
	for handed, handStatus in pairs(accessoryStatus or {}) do
		if handStatus.blendTime ~= nil and handStatus.blendTime > 0 and handStatus.blendElapsed < handStatus.blendTime then
			handStatus.blendElapsed = handStatus.blendElapsed + (delta or 0)
		elseif handStatus.releasing then
			accessoryStatus[handed] = nil
		end
	end
end)

uevrUtils.registerPreLevelChangeCallback(function(level)
	accessoryStatus = {} -- attach parents (weapon, pawn mesh) die with the level
end)

function M.getAccessoryStatus(handed)
	return accessoryStatus and accessoryStatus[handed]
end

-- end_bone_offset / end_bone_rotation (controller space) of the active solver driven by `handed`'s
-- controller, as plain {X,Y,Z} / {Pitch,Yaw,Roll} tables. nil if no such solver.
function M.getEndBoneOffset(handed)
	local solvers = getParameter({paramManager:getActiveProfile(), "solvers"})
	for _, solverParams in pairs(solvers or {}) do
		if solverParams["end_control_type"] == handed and solverParams["active"] ~= false then
			local loc = solverParams["end_bone_offset"] or {0, 0, 0}
			local rot = solverParams["end_bone_rotation"] or {0, 0, 0}
			return {X = loc[1] or loc.X or 0, Y = loc[2] or loc.Y or 0, Z = loc[3] or loc.Z or 0},
				{Pitch = rot[1] or rot.Pitch or 0, Yaw = rot[2] or rot.Yaw or 0, Roll = rot[3] or rot.Roll or 0}
		end
	end
	return nil, nil
end

uevrUtils.registerUEVRCallback("on_accessory_animation", function(handed, anim)

end)

uevrUtils.registerUEVRCallback("gunstock_transform_change", function(id, newLocation, newRotation, newOffhandLocationOffset)
    if gunstockOffsetsEnabled then
		gunstockRotation = newRotation
	end
end)

function M.setCurrentProfile(profileID)
	paramManager:setActiveProfile(profileID)
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

return M
