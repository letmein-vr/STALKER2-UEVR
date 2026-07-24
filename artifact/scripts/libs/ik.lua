local uevrUtils = require("libs/uevr_utils")
local paramModule = require("libs/core/params")
local controllers = require("libs/controllers")
local handsAnimation = require("libs/hands_animation")
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
function M.destroyAll()
    for i = #_rigInstances, 1, -1 do
		local inst = table.remove(_rigInstances, i)
		if inst then M.destroy(inst, true) end
    end
end

-- handle script resets to cleanup components we created
uevr.params.sdk.callbacks.on_script_reset(function()
	M.destroyAll()
end)

uevrUtils.registerPreLevelChangeCallback(function(level)
	M.print("Pre level change detected, cleaning up IK rigs...")
	M.destroyAll()
end)



local useCustomInstance = false
local meshCreatedCallback = nil

function M.setUseCustomIKComponentInstance(val)
	useCustomInstance = val
end

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
			if kismet_math_library.Dot_VectorVector and kismet_math_library.Multiply_VectorFloat and kismet_math_library.Subtract_VectorVector then
				local dotVN = kismet_math_library:Dot_VectorVector(vec, planeNormal) or 0.0
				local denom = kismet_math_library:Dot_VectorVector(planeNormal, planeNormal) or 0.0
				if denom <= 1e-8 then return uevrUtils.vector(0,0,0) end
				local scale = dotVN / denom
				local comp = kismet_math_library:Multiply_VectorFloat(planeNormal, scale)
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
			return uevrUtils.vector(vx - nx*s, vy - ny*s, vz - nz*s)
	end
end

local ikConfigDev = nil
local parametersFileName = "ik_parameters"
local parameters = {
	mesh = "",
    animation_mesh = "",
    mesh_location_offset = uevrUtils.vector(0,0,0),
    mesh_rotation_offset = uevrUtils.rotator(0,0,0),
    animation_location_offset = uevrUtils.vector(0,0,0),
    animation_rotation_offset = uevrUtils.rotator(0,0,0),
	solvers = {},
}
local paramManager = paramModule.new(parametersFileName, parameters, true)
paramManager:load(true)

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

local SafeNormalize

local IK_MIN_SWING_DEG = 0.02
local IK_MIN_TWIST_DEG = 0.02
-- Position smoothing alpha (0..1) applied to solver outputs each tick.
-- Lower values = heavier smoothing (more lag), higher = more responsive.
--local IK_POS_SMOOTH_ALPHA = 0.6

local FOREARM_TWIST_MAX_DEG_DEFAULT = 100.0

local function normalizeDeg180(angleDeg)
	if angleDeg == nil then return nil end
	return (((angleDeg + 180.0) % 360.0) - 180.0)
end

-- Unwrap an angle to be continuous vs a previous sample.
-- Keeps the returned value within +/-180 of prevAngleDeg.
local function unwrapDeg(angleDeg, prevAngleDeg)
	if angleDeg == nil or prevAngleDeg == nil then return angleDeg end
	local delta = angleDeg - prevAngleDeg
	delta = (((delta + 180.0) % 360.0) - 180.0)
	return prevAngleDeg + delta
end

-- Robust twist extraction: swing–twist decomposition of the relative rotation.
-- This avoids the fundamental instability of using raw up/right vectors when wrist pitch/yaw changes.
local RAD2DEG = 180.0 / math.pi
local _reuseEulerA = nil
local _reuseEulerB = nil

local function setVec3(v, x, y, z)
	if v == nil then return end
	if v.X ~= nil then
		v.X = x; v.Y = y; v.Z = z
	else
		v.x = x; v.y = y; v.z = z
	end
end

local function computeTwistDegAroundAxis_Rotators(rotA, rotB, axis)
	if rotA == nil or rotB == nil or axis == nil then return nil end

	-- Axis is expected to already be normalized (call sites pass SafeNormalize(lowerDirCS)).
	-- Keep this hot path sqrt-free: just guard against a degenerate axis.
	local ax = axis.X or axis.x or 0.0
	local ay = axis.Y or axis.y or 0.0
	local az = axis.Z or axis.z or 0.0
	local len2 = (ax * ax) + (ay * ay) + (az * az)
	if len2 < 1e-8 then return nil end

	-- IMPORTANT: use Unreal's own Euler->Quat conversion.
	-- Rotator (Pitch/Yaw/Roll) can represent the same orientation with different Euler triples;
	-- hand-rolling conversion/order can disagree with engine conventions and leak pitch/yaw into "twist".
	if _reuseEulerA == nil then
		_reuseEulerA = uevrUtils.vector(0.0, 0.0, 0.0)
		_reuseEulerB = uevrUtils.vector(0.0, 0.0, 0.0)
	end
	setVec3(_reuseEulerA, rotA.Roll or 0.0, rotA.Pitch or 0.0, rotA.Yaw or 0.0) -- Roll, Pitch, Yaw
	setVec3(_reuseEulerB, rotB.Roll or 0.0, rotB.Pitch or 0.0, rotB.Yaw or 0.0)

	local qa = kismet_math_library:Quat_MakeFromEuler(_reuseEulerA)
	local qb = kismet_math_library:Quat_MakeFromEuler(_reuseEulerB)
	if qa == nil or qb == nil then return nil end

	local aw = qa.W or qa.w or 1.0
	local axq = qa.X or qa.x or 0.0
	local ayq = qa.Y or qa.y or 0.0
	local azq = qa.Z or qa.z or 0.0

	local bw = qb.W or qb.w or 1.0
	local bxq = qb.X or qb.x or 0.0
	local byq = qb.Y or qb.y or 0.0
	local bzq = qb.Z or qb.z or 0.0

	-- Relative rotation qRel = qb * conj(qa) (qa assumed unit).
	local rw = (bw * aw) + (bxq * axq) + (byq * ayq) + (bzq * azq)
	local rx = (-bw * axq) + (bxq * aw) - (byq * azq) + (bzq * ayq)
	local ry = (-bw * ayq) + (bxq * azq) + (byq * aw) - (bzq * axq)
	local rz = (-bw * azq) - (bxq * ayq) + (byq * axq) + (bzq * aw)

	-- No normalization required: atan2(k*dot, k*w) == atan2(dot, w) for k>0.
	-- Still guard against degenerate quats.
	local n2 = (rw * rw) + (rx * rx) + (ry * ry) + (rz * rz)
	if n2 < 1e-12 then return 0.0 end

	-- Twist angle around axis for qRel: theta = 2 * atan2(dot(v, axis), w)
	local dot = (rx * ax) + (ry * ay) + (rz * az)
	return (2.0 * math.atan(dot, rw)) * RAD2DEG
end

-- Optional: couple wrist roll into elbow pole so the elbow raises/lowers slightly as you pronate/supinate.
-- Keep conservative defaults to avoid pole flips.
local ELBOW_POLE_TWIST_INFLUENCE = 0.35 -- 0..1 (try 0.15-0.40)
local ELBOW_POLE_TWIST_MAX_DEG   = 75.0 -- clamp the measured twist before applying

-- Module-level constants (allocated once, never mutated).
local VEC_UNIT_Y     = nil  -- uevrUtils.vector(0,1,0) — initialised on first use after kismet is live
local VEC_UNIT_Y_FORWARD     = nil  -- uevrUtils.vector(0,1,0) — initialised on first use after kismet is live
local VEC_UNIT_Y_INVERSE     = nil  -- uevrUtils.vector(0,-1,0) — initialised on first use after kismet is live

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
		-- NOTE: compToWorld and meshRightVec are NOT cached — they change every tick as the pawn rotates.
		upperLen = nil,            -- upper arm bone length         — skeleton constant
		lowerLen = nil,            -- lower arm bone length         — skeleton constant
		bonesKey = nil,            -- JointBone.."->"..EndBone     — never changes per call site
		-- Smoothed controller target offset in component space (from shoulder).
		lastEffectorOffsetCS = nil,
		-- Smoothed IK direction vectors and pole — suppress per-tick numerical noise that drives
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
    local self = setmetatable({
		tickPhase = options.tickPhase or "post", -- "pre" or "post"
		tickPriority = options.tickPriority,
		rigId = options.rigId or paramManager:getActiveProfile(),
		orderedSolvers = nil,
		solverOrderDirty = true,

    }, Rig)

	self.liveUpdateFn = function(key, value, persist)
		local activeRigId = paramManager:getActiveProfile()
		if self.rigId ~= nil and activeRigId ~= nil and self.rigId == activeRigId then
			self:setConfigParameter(key, value, persist)
		end
	end

	--live update of ui config changes from ik_config_dev
	uevrUtils.registerUEVRCallback("on_ik_config_param_change", self.liveUpdateFn)

	--see if montage or other systems have triggered hide hands
	self.hideIntervalTimer = uevrUtils.setInterval(200, function()
		local isHidden, priority = executeIsHiddenCallback()
		self:hide(isHidden)
	end)

	if options.animationsFile ~= nil then
		self:setAnimationsFromHandsParametersFile(options.animationsFile)
	end

    self:create() -- auto-create component

	registerInstance(self)

    return self
end

function Rig:hide(value)
	if value ~= self.wasHidden then
		self.wasHidden = value
		if uevrUtils.getValid(self.mesh) ~= nil then
			self.mesh:SetVisibility(not value, true)
			--self.mesh:SetHiddenInGame(value, true)
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

local function getRigParams(rigId)
	if rigId == nil then return nil end
	return paramManager:get(rigId)
end

local function getSolverParams(rigId, solverId)
	if rigId == nil or solverId == nil then return nil end
	return paramManager:get({rigId, "solvers", solverId})
end

local function isRigLevelParam(paramName)
	return paramName == "mesh"
		or paramName == "mesh_location_offset"
		or paramName == "mesh_rotation_offset"
		or paramName == "animation_mesh"
		or paramName == "animation_location_offset"
		or paramName == "animation_rotation_offset"
end

local function getAncestorBones(mesh, boneName, generations)
    if mesh == nil or boneName == nil or generations == nil then
        return {}
    end
    local ancestors = {}
    local currentBone = boneName
    for i = 1, generations do
        local parentBone = mesh:GetParentBone(currentBone)
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

function Rig:initHandAnimations(component)
	if self.animationDefinition == nil or self.animationProfile == nil then
		return
	end
	for key, profileMesh in pairs(self.animationProfile) do
		for index = Handed.Left , Handed.Right do
			local animID = profileMesh[index==Handed.Left and "Left" or "Right"]["AnimationID"]
			if animID ~= nil then
				handsAnimation.createAnimationHandler(animID, component, self.animationDefinition)
			end
		end
	end
end

function Rig:initializeRigState()
	if self.mesh ~= nil then
		uevrUtils.destroyComponent(self.mesh, true, true)
		self.mesh = nil
	end

	local rootComponent = uevrUtils.getValid(pawn, {"RootComponent"})
	if rootComponent == nil then
		print("Rig:initializeRigState: No RootComponent on pawn")
		return
	end

	local meshName = getParameter({self.rigId, "mesh"})
	local meshTemplate = nil
	if meshName == "Custom" then
		if useCustomInstance == false then
			if getCustomIKComponent ~= nil then
				meshTemplate = getCustomIKComponent(self.rigId)
			end
		else
			if getCustomIKComponentInstance ~= nil then
				self.mesh = getCustomIKComponentInstance(self.rigId)
			end
		end
	else
		meshTemplate = uevrUtils.getObjectFromDescriptor(meshName, false)
	end
	if meshTemplate ~= nil then
		local mesh = uevrUtils.createPoseableMeshFromSkeletalMesh(meshTemplate, {useDefaultPose = true, showDebug=false})
		if mesh ~= nil then
			self.mesh = mesh
			-- local springArm = uevrUtils.create_component_of_class("Class /Script/Engine.SpringArmComponent")
			-- springArm.TargetArmLength = 0
			-- springArm.bEnableCameraLag = true
			-- springArm.CameraLagSpeed = 20.0
			-- springArm.bEnableCameraRotationLag = true
			-- springArm.CameraRotationLagSpeed = 5.0
			-- springArm.bUsePawnControlRotation = false
			-- --controllers.attachComponentToController(2, self.mesh, "", 0, false, true)
			-- controllers.attachComponentToController(2, springArm, "", 0, false, true)
			-- self.mesh:K2_AttachTo(springArm, uevrUtils.fname_from_string(""), 0, false)
			self.mesh:K2_AttachTo(rootComponent, uevrUtils.fname_from_string(""), 0, false)
			self.mesh:SetVisibility(true, true)
			self.mesh:SetHiddenInGame(false, true)
			self.mesh.BoundsScale = 16.0

			--local capsuleHeight = rootComponent.CapsuleHalfHeight or 0 --should be used here but the tick handles it so whatever
			self.meshLocationOffset = getParameter({self.rigId, "mesh_location_offset"}) and uevrUtils.vector(getParameter({self.rigId, "mesh_location_offset"})) or uevrUtils.vector(0,0,0)
			self.meshRotationOffset = getParameter({self.rigId, "mesh_rotation_offset"}) and uevrUtils.rotator(getParameter({self.rigId, "mesh_rotation_offset"})) or uevrUtils.rotator(0,0,0)
			self.mesh.RelativeLocation = self.meshLocationOffset
			self.mesh.RelativeRotation = self.meshRotationOffset

			if meshCreatedCallback ~= nil then
				meshCreatedCallback(self.mesh, self)
			end
		end
	end

	--This is the hands animation system for weapons grips etc
	self:initHandAnimations(self.mesh)

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
	self.animationLocationOffset = getParameter({self.rigId, "animation_location_offset"}) and uevrUtils.vector(getParameter({self.rigId, "animation_location_offset"})) or uevrUtils.vector(0,0,0)
	self.animationRotationOffset = getParameter({self.rigId, "animation_rotation_offset"}) and uevrUtils.rotator(getParameter({self.rigId, "animation_rotation_offset"})) or uevrUtils.rotator(0,0,0)

end

function Rig:setRigParameter(paramName, value)
	if self.activeSolvers == nil then return end

	if paramName == "mesh" then
		self:initializeRigState()

		if self.mesh ~= nil then
			for solverId, active in pairs(self.activeSolvers) do
				active.mesh = self.mesh
				if active.endBone ~= nil and active.endBone ~= "" then
					local parentBones = getAncestorBones(self.mesh, active.endBone, 3)
					if #parentBones == 3 then
						if active.startBone == nil or active.startBone == "" then
							active.startBone = parentBones[#parentBones]
						end
						if active.jointBone == nil or active.jointBone == "" then
							active.jointBone = parentBones[#parentBones - 1]
						end
					end
				end
				--self:initializeSolverState(active)
			end
		end
		return
	end

    if paramName == "mesh_location_offset" then
		local offset = value and uevrUtils.vector(value) or uevrUtils.vector(0,0,0)
		--get this rigs mesh and set its relative location
		self.meshLocationOffset = offset
        if self.mesh ~= nil then --update live
            self.mesh.RelativeLocation = offset
        end
		return
	end

    if paramName == "mesh_rotation_offset" then
		local offset = value and uevrUtils.rotator(value) or uevrUtils.rotator(0,0,0)
		--get this rigs mesh and set its relative rotation
		self.meshRotationOffset = offset
        if self.mesh ~= nil then --update live
            self.mesh.RelativeRotation = offset
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
    end_control_type = "hand",
    twist_bones = "twistBones",
--    invert_forearm_roll = "invertForearmRoll",
	sort_order = "sortOrder",
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
			end
		end
	elseif paramName == "end_control_type" then
		local controller = nil
		if value == M.ControllerType.LEFT_CONTROLLER then
			controller = controllers.getController(Handed.Left)
		else
			controller = controllers.getController(Handed.Right)
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


local function executeIsAnimatingFromMeshCallback(...)
	return uevrUtils.executeUEVRCallbacksWithPriorityBooleanResult("is_hands_animating_from_mesh", table.unpack({...}))
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

function Rig:setInitialTransform()
    local mesh = self.mesh
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

-- I7 perf: named function avoids allocating a new closure every tick inside pcall
local function _doCopyPose(mesh, animationMesh)
    mesh:CopyPoseFromSkeletalComponent(animationMesh)
    return true
end

function Rig:animateFromMesh()
    local didAnimate = false
    local success, response = pcall(_doCopyPose, self.mesh, self.animationMesh)
    if success then
        didAnimate = true
        self.wasAnimating = true
    else
        M.print(response, LogLevel.Error)
    end

    -- In some games the animation moves the skeleton by an offset (probably so they are more visible in the 2D screen)
    -- but we dont want this offset in VR so we correct it here
    if self.animationRotationOffset.Pitch ~= 0 or self.animationRotationOffset.Yaw ~= 0 or self.animationRotationOffset.Roll ~= 0 or self.animationLocationOffset.X ~= 0 or self.animationLocationOffset.Y ~= 0 or self.animationLocationOffset.Z ~= 0 then
        local rootName = uevrUtils.fname_from_string(self.rootBone)
        --adding rotators would normally be bad but since its just an offset determined by UI it works here
        local rot = self.mesh:GetBoneRotationByName(rootName, EBoneSpaces.ComponentSpace) + self.animationRotationOffset
        --local loc = activeParams.mesh:GetBoneLocationByName(rootName, EBoneSpaces.ComponentSpace) + activeParams.animationLocationOffset -- this doesnt work, the get returns world space
        -- base location of root should be 0,0,0 in component space so this should work as an offset
        local loc = self.animationLocationOffset
        self.mesh:SetBoneRotationByName(rootName, rot, EBoneSpaces.ComponentSpace)
        self.mesh:SetBoneLocationByName(rootName, loc, EBoneSpaces.ComponentSpace)
    end

    return didAnimate
end

function Rig:create()
    if UKismetAnimationLibrary == nil then
		UKismetAnimationLibrary = uevrUtils.find_default_instance("Class /Script/AnimGraphRuntime.KismetAnimationLibrary")
	end
	if UKismetAnimationLibrary == nil then
		print("Unable to find KismetAnimationLibrary. IK disabled")
		return
	end
	-- Allocate-once constants: kismet_math_library is guaranteed live by this point.
	if VEC_UNIT_Y     == nil then VEC_UNIT_Y     = uevrUtils.vector(0, 1, 0) end
	if VEC_UNIT_Y_FORWARD     == nil then VEC_UNIT_Y_FORWARD     = uevrUtils.vector(0, 1, 0) end
    if VEC_UNIT_Y_INVERSE     == nil then VEC_UNIT_Y_INVERSE     = uevrUtils.vector(0, -1, 0) end

	self:initializeRigState()

    self.activeSolvers = {}
	self.orderedSolvers = {}
	self.solverOrderDirty = true
	-- Register tick callback
	self.tickFn = function(engine, delta)
		if uevrUtils.getValid(self.mesh) == nil then
			return
		end
		local rootComponent = uevrUtils.getValid(pawn, {"RootComponent"})
		if rootComponent ~= nil then
			local capsuleHeight = rootComponent.CapsuleHalfHeight or 0
			--print("Capsule height:", capsuleHeight)
			self.mesh.RelativeLocation.Z = self.meshLocationOffset.Z + (self.meshLocationOffset.Z + capsuleHeight)
		end

        if self.activeSolvers ~= nil then
            local isLeftAnimating = select(1, executeIsAnimatingFromMeshCallback(Handed.Left))
		    local isRightAnimating = select(1, executeIsAnimatingFromMeshCallback(Handed.Right))
            local didAnimate = false
            if (isLeftAnimating or isRightAnimating) then
                didAnimate = self:animateFromMesh()--uevrUtils.getValid(pawn, {"FPVMesh"}))
            end
            if didAnimate == false then
                if self.wasAnimating then
                    self:setInitialTransform()
                    self.wasAnimating = false
                end

                self:rebuildOrderedSolversIfNeeded()
				for _, solverEntry in ipairs(self.orderedSolvers or {}) do
					local solverId = solverEntry.id
					local activeParams = solverEntry.params
                    if activeParams then
						if activeParams.solverType == M.SolverType.TWO_BONE then
							self:solveTwoBone(activeParams)
                        end
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
	local rigParams = getRigParams(self.rigId)
	if rigParams ~= nil then
		local solvers = rigParams.solvers
		if solvers ~= nil then
			for solverId, solverParams in pairs(solvers) do
				self:setActive(solverId, solverParams.active)
			end
		end
	end
end

--checkpoint
function M.destroy(instance, skipUnregister)
	if instance ~= nil then
		local rigParams = getRigParams(instance.rigId)
		if rigParams ~= nil then
			local solvers = rigParams.solvers
			if solvers ~= nil then
				for solverId, solverParams in pairs(solvers) do
					instance:setActive(solverId, false)
				end
			end
		end

		handsAnimation.destroyAnimationHandler(instance.mesh)

		if instance.mesh ~= nil then
			uevrUtils.destroyComponent(instance.mesh, true, true)
			instance.mesh = nil
		end

		if uevrUtils.unregisterPreEngineTickCallback then
			uevrUtils.unregisterPreEngineTickCallback(instance.tickFn)
		end
		if uevrUtils.unregisterPostEngineTickCallback then
			uevrUtils.unregisterPostEngineTickCallback(instance.tickFn)
		end

		if uevrUtils.unregisterUEVRCallback then
			pcall(function()
				uevrUtils.unregisterUEVRCallback("preEngineTick", instance.tickFn)
				uevrUtils.unregisterUEVRCallback("postEngineTick", instance.tickFn)
			end)
		end

		if uevrUtils.unregisterUEVRCallback then
			pcall(function() uevrUtils.unregisterUEVRCallback("on_ik_config_param_change", instance.liveUpdateFn) end)
		end
		pcall(function() uevrUtils.clearInterval(instance.hideIntervalTimer) end)

		instance.tickFn = nil
		instance.hideIntervalTimer = nil
		instance.liveUpdateFn = nil
		instance.activeSolvers = nil
		instance.orderedSolvers = nil
		instance.initialTransforms = nil
		instance.animationMesh = nil
		instance.state = nil
		instance.meshCreatedCallback = nil

		if skipUnregister ~= true then
			unregisterInstance(instance)
		end
	end
end


local function mulVec(v, s)
	return kismet_math_library:Multiply_VectorFloat(v, s)
end

local function getBoneDirCS(mesh, fromBone, toBone)
	if mesh == nil then return nil end
	local a = mesh:GetBoneLocationByName(fromBone, EBoneSpaces.ComponentSpace)
	local b = mesh:GetBoneLocationByName(toBone, EBoneSpaces.ComponentSpace)
	if a == nil or b == nil then return nil end
	return SafeNormalize(kismet_math_library:Subtract_VectorVector(b, a))
end

-- Stable, head/target independent pole reference computed from the rest pose in component space.
-- Returns the "elbow outward" direction: joint position projected onto plane orthogonal to reach.
local function getBendPoleRefCS(mesh, rootBone, jointBone, endBone)
	if mesh == nil then return nil end
	local s = mesh:GetBoneLocationByName(rootBone, EBoneSpaces.ComponentSpace)
	local j = mesh:GetBoneLocationByName(jointBone, EBoneSpaces.ComponentSpace)
	local e = mesh:GetBoneLocationByName(endBone, EBoneSpaces.ComponentSpace)
	if s == nil or j == nil or e == nil then return nil end
	local reach = SafeNormalize(kismet_math_library:Subtract_VectorVector(e, s))
	if reach == nil or kismet_math_library:VSize(reach) < 0.0001 then return nil end
	local elbowOffset = kismet_math_library:Subtract_VectorVector(j, s)
	local pole = SafeNormalize(ProjectVectorOnToPlane(elbowOffset, reach))
	if pole == nil or kismet_math_library:VSize(pole) < 0.0001 then return nil end
	return pole
end

local function axisVectorsFromRot(rot)
	if rot == nil then return nil, nil, nil end
	return SafeNormalize(kismet_math_library:GetForwardVector(rot)),
		SafeNormalize(kismet_math_library:GetRightVector(rot)),
		SafeNormalize(kismet_math_library:GetUpVector(rot))
end

local function chooseBestAxis(axisX, axisY, axisZ, dir)
	if dir == nil then return { axis = "X", sign = 1, score = 0 } end
	local function scoreAxis(a)
		if a == nil then return 0 end
		local d = kismet_math_library:Dot_VectorVector(a, dir) or 0
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
		local d = kismet_math_library:Dot_VectorVector(vec, poleDir) or 0
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

local function signedAngleDegAroundAxis(a, b, axis)
	-- Signed angle from a->b around axis.
	local cross = kismet_math_library:Cross_VectorVector(a, b)
	local y = kismet_math_library:Dot_VectorVector(axis, cross) or 0.0
	local x = kismet_math_library:Dot_VectorVector(a, b) or 1.0
	return kismet_math_library:RadiansToDegrees(math.atan(y, x))
end

local function composeSwingWithCachedOrder(state, currentDir, currentRot, desiredDir, deltaSwing)
	local cand1 = kismet_math_library:ComposeRotators(deltaSwing, currentRot)
	local cand2 = kismet_math_library:ComposeRotators(currentRot, deltaSwing)
	local localDir = SafeNormalize(kismet_math_library:LessLess_VectorRotator(currentDir, currentRot))
	local function score(rot)
		if rot == nil then return -1 end
		local a = SafeNormalize(kismet_math_library:GreaterGreater_VectorRotator(localDir, rot))
		return kismet_math_library:Dot_VectorVector(a, desiredDir) or -1
	end
	return (score(cand2) > score(cand1)) and cand2 or cand1
end

local function composeTwistWithCachedOrder(state, swingRot, deltaTwist, desiredDir, desiredPole, poleAxisChar, poleAxisSign)
	local t1 = kismet_math_library:ComposeRotators(deltaTwist, swingRot)
	local t2 = kismet_math_library:ComposeRotators(swingRot, deltaTwist)
	local function scorePole(rot)
		local p = axisVectorFromRotator(rot, poleAxisChar)
		if p == nil then return -1 end
		p = SafeNormalize(ProjectVectorOnToPlane(mulVec(p, poleAxisSign), desiredDir))
		return kismet_math_library:Dot_VectorVector(p, desiredPole) or -1
	end
	return (scorePole(t2) > scorePole(t1)) and t2 or t1
end

--local _dbg_ik_align_label = nil   -- set by solveTwoBone; read by alignBoneAxisToDirCS
local function alignBoneAxisToDirCS(mesh, boneName, childBoneName, desiredDirCS, axisChoice, poleCS, state)
	local currentRot = mesh:GetBoneRotationByName(boneName, EBoneSpaces.ComponentSpace)
    if currentRot == nil then return nil end

	-- 1) Determine current direction to align.
	-- In this project we always call with childBoneName; keep a small fallback for completeness.
	local currentDir = (childBoneName ~= nil) and getBoneDirCS(mesh, boneName, childBoneName) or nil
	if currentDir == nil and axisChoice ~= nil then
		local axisVec = axisVectorFromRotator(currentRot, axisChoice.axis or "X")
		currentDir = axisVec and SafeNormalize(mulVec(axisVec, axisChoice.sign or 1)) or nil
	end
	if currentDir == nil or kismet_math_library:VSize(currentDir) < 0.0001 then
		return currentRot
	end
	local desiredDir = SafeNormalize(desiredDirCS)
	if desiredDir == nil or kismet_math_library:VSize(desiredDir) < 0.0001 then
		return currentRot
	end

	-- if stopDebug == false and _dbg_ik_align_label ~= nil then
	-- 	print("IK align", _dbg_ik_align_label, "curDir:", currentDir.X, currentDir.Y, currentDir.Z)
	-- end

	-- 2) Swing: rotate currentDir -> desiredDir.
	local dot = kismet_math_library:Dot_VectorVector(currentDir, desiredDir) or 1.0
	dot = kismet_math_library:FClamp(dot, -1.0, 1.0)
	local swingAngleDeg = kismet_math_library:RadiansToDegrees(kismet_math_library:Acos(dot))
	if swingAngleDeg ~= nil and swingAngleDeg < IK_MIN_SWING_DEG then return currentRot end

	local swingAxis = kismet_math_library:Cross_VectorVector(currentDir, desiredDir)
	if kismet_math_library:VSize(swingAxis) < 0.0001 then
		-- 180° case: pick a stable fallback axis using the pole.
		local pole = SafeNormalize(poleCS)
		if pole == nil or kismet_math_library:VSize(pole) < 0.0001 then pole = VEC_UNIT_Y end
		swingAxis = kismet_math_library:Cross_VectorVector(currentDir, pole)
	end
	swingAxis = SafeNormalize(swingAxis)
	if swingAxis == nil or kismet_math_library:VSize(swingAxis) < 0.0001 then return currentRot end

	local deltaSwing = kismet_math_library:RotatorFromAxisAndAngle(swingAxis, swingAngleDeg)
	local swingRot = composeSwingWithCachedOrder(state, currentDir, currentRot, desiredDir, deltaSwing)

	-- 3) Optional twist: align a pole axis in the plane orthogonal to desiredDir.
	local poleAxisChoice = axisChoice and axisChoice.pole or nil
	if poleAxisChoice == nil then
		return swingRot
	end
	local poleAxisChar = poleAxisChoice.axis
	local poleAxisSign = poleAxisChoice.sign or 1
    --poleAxisSign = -poleAxisSign

	-- Check raw projection length BEFORE normalizing.
	-- When poleCS is nearly parallel/antiparallel to desiredDir (bone pointing toward face),
	-- the raw projection is near-zero; normalizing it amplifies noise and causes ±180° sign-flip oscillation.
	-- Thresholds tuned for near-head/scope poses where the pole projection gets weak.
	local rawDesiredPole = ProjectVectorOnToPlane(poleCS, desiredDir)
	local rawDesiredPoleLen = (rawDesiredPole ~= nil) and kismet_math_library:VSize(rawDesiredPole) or 0.0

	local useAggressivePoleAlignment = false --setting this true doesnt seem to help anything and causes shoulder and elbow flips in AQP
	local POLE_PROJ_MIN_LEN = 0.22

	local desiredPole = nil
	if useAggressivePoleAlignment == true then
		if rawDesiredPoleLen < POLE_PROJ_MIN_LEN then
			if state ~= nil and state.lastDesiredPole ~= nil and kismet_math_library:VSize(state.lastDesiredPole) > 0.0001 then
				desiredPole = state.lastDesiredPole
			else
				return swingRot
			end
		else
			desiredPole = kismet_math_library:Divide_VectorFloat(rawDesiredPole, rawDesiredPoleLen)
			if state ~= nil and state.lastDesiredPole ~= nil then
				if (kismet_math_library:Dot_VectorVector(desiredPole, state.lastDesiredPole) or 0.0) < 0.0 then
					desiredPole = kismet_math_library:Multiply_VectorFloat(desiredPole, -1.0)
				end
			end
			if state ~= nil then state.lastDesiredPole = desiredPole end
		end
	else
		if rawDesiredPoleLen < 0.15 then return swingRot end
		desiredPole = kismet_math_library:Divide_VectorFloat(rawDesiredPole, rawDesiredPoleLen)
		if desiredPole == nil then return swingRot end
	end

	local poleAxisVec = axisVectorFromRotator(swingRot, poleAxisChar)
	if poleAxisVec == nil then return swingRot end
	local rawCurrentPole = ProjectVectorOnToPlane(mulVec(poleAxisVec, poleAxisSign), desiredDir)
	local rawCurrentPoleLen = (rawCurrentPole ~= nil) and kismet_math_library:VSize(rawCurrentPole) or 0.0

	local currentPole = nil
	if useAggressivePoleAlignment == true then
		if rawCurrentPoleLen < POLE_PROJ_MIN_LEN then
			if state ~= nil and state.lastCurrentPole ~= nil and kismet_math_library:VSize(state.lastCurrentPole) > 0.0001 then
				currentPole = state.lastCurrentPole
			else
				return swingRot
			end
		else
			currentPole = kismet_math_library:Divide_VectorFloat(rawCurrentPole, rawCurrentPoleLen)
			if state ~= nil and state.lastCurrentPole ~= nil then
				if (kismet_math_library:Dot_VectorVector(currentPole, state.lastCurrentPole) or 0.0) < 0.0 then
					currentPole = kismet_math_library:Multiply_VectorFloat(currentPole, -1.0)
				end
			end
			if state ~= nil then state.lastCurrentPole = currentPole end
		end
	else
		if rawCurrentPoleLen < 0.15 then return swingRot end
		currentPole = kismet_math_library:Divide_VectorFloat(rawCurrentPole, rawCurrentPoleLen)
		if currentPole == nil then return swingRot end
	end
	-- local desiredPole = SafeNormalize(ProjectVectorOnToPlane(poleCS, desiredDir))
	-- if desiredPole == nil or kismet_math_library:VSize(desiredPole) < 0.0001 then return swingRot end
	-- local poleAxisVec = axisVectorFromRotator(swingRot, poleAxisChar)
	-- if poleAxisVec == nil then return swingRot end
	-- local currentPole = SafeNormalize(ProjectVectorOnToPlane(mulVec(poleAxisVec, poleAxisSign), desiredDir))
	-- if currentPole == nil or kismet_math_library:VSize(currentPole) < 0.0001 then return swingRot end


	local twistAngleDeg = signedAngleDegAroundAxis(currentPole, desiredPole, desiredDir)
	-- if stopDebug == false and _dbg_ik_align_label ~= nil then
	-- 	print("IK align", _dbg_ik_align_label, "twistDeg:", (twistAngleDeg or "nil"), "poleAxis:", poleAxisChar, poleAxisSign)
	-- 	print("IK align", _dbg_ik_align_label, "curPole:", currentPole.X, currentPole.Y, currentPole.Z, "desPole:", desiredPole.X, desiredPole.Y, desiredPole.Z)
	-- end
	-- if twistAngleDeg ~= nil then
	-- 	-- Fade out twist correction in weak-projection poses (underconstrained, prone to visual pops).
	-- 	local poleStability = math.min(rawDesiredPoleLen or 0.0, rawCurrentPoleLen or 0.0)
	-- 	local twistWeight = kismet_math_library:FClamp((poleStability - 0.22) / (0.45 - 0.22), 0.0, 1.0)
	-- 	twistAngleDeg = twistAngleDeg * twistWeight
	-- end

	-- if twistAngleDeg ~= nil and state ~= nil then
	-- 	-- Keep pole-twist continuity to avoid occasional ±30-180° branch snaps.
	-- 	local prevTwist = state.lastTwistDeg
	-- 	twistAngleDeg = normalizeDeg180(twistAngleDeg)
	-- 	if prevTwist ~= nil then
	-- 		local delta = normalizeDeg180(twistAngleDeg - prevTwist)
	-- 		local MAX_ALIGN_TWIST_STEP_DEG = 8.0
	-- 		delta = kismet_math_library:FClamp(delta, -MAX_ALIGN_TWIST_STEP_DEG, MAX_ALIGN_TWIST_STEP_DEG)
	-- 		twistAngleDeg = prevTwist + delta
	-- 	end
	-- 	state.lastTwistDeg = twistAngleDeg
	-- end
	if twistAngleDeg == nil or math.abs(twistAngleDeg) < IK_MIN_TWIST_DEG then return swingRot end

	local deltaTwist = kismet_math_library:RotatorFromAxisAndAngle(desiredDir, twistAngleDeg)
	return composeTwistWithCachedOrder(state, swingRot, deltaTwist, desiredDir, desiredPole, poleAxisChar, poleAxisSign)
end
alignBoneAxisToDirCS = uevrUtils.profiler:wrap("alignBoneAxisToDirCS", alignBoneAxisToDirCS)

SafeNormalize = function(v)
	if v == nil then return uevrUtils.vector(0,0,0) end
	-- UKismetMathLibrary has VSize/Divide_VectorFloat (see Engine_classes.hpp)
	local len = kismet_math_library:VSize(v)
	if len == nil or len < 0.0001 then
		return uevrUtils.vector(0,0,0)
	end
	return kismet_math_library:Divide_VectorFloat(v, len)
end
SafeNormalize = uevrUtils.profiler:wrap("SafeNormalize", SafeNormalize)

-- Per-hand override: when set to true, always use live VR controller position
-- regardless of accessoryStatus. Used to prevent the bare-hands IK poller from
-- overriding controller tracking with frozen CharacterMesh0 socket positions.
local forceControllerTracking = {}

function M.setForceControllerTracking(hand, value)
    forceControllerTracking[hand] = value
    if value then
        -- Also clear any stale accessory status so we start clean
        accessoryStatus = accessoryStatus or {}
        accessoryStatus[hand] = nil
    end
end

local function getTargetLocationAndRotation(hand, controller)
    local loc = nil
    local rot = nil
    -- If force-controller mode is on, bypass accessoryStatus entirely.
    if forceControllerTracking[hand] then
        if uevrUtils.getValid(controller) ~= nil and controller.K2_GetComponentLocation ~= nil then
            loc = controller:K2_GetComponentLocation()
            rot = controller:K2_GetComponentRotation()
        end
        if loc == nil then
            local fresh = controllers.getController(hand)
            if fresh ~= nil then
                loc = fresh:K2_GetComponentLocation()
                rot = fresh:K2_GetComponentRotation()
            end
        end
        if rot ~= nil and hand == Handed.Right and gunstockOffsetsEnabled == true then
            rot = kismet_math_library:ComposeRotators(gunstockRotation, rot)
        end
        return loc, rot
    end
    if accessoryStatus[hand] == nil then
		if uevrUtils.getValid(controller) ~= nil and controller.K2_GetComponentLocation ~= nil then
			loc = controller:K2_GetComponentLocation()
			rot = controller:K2_GetComponentRotation()
		end
		-- Guard: if loc is nil the stored controller ref may be stale (e.g. after a
		-- weapon equip/unequip cycle). Re-fetch the live MotionControllerComponent so
		-- tracking self-heals without requiring a full rig restart.
		if loc == nil then
			local fresh = controllers.getController(hand)
			if fresh ~= nil then
				loc = fresh:K2_GetComponentLocation()
				rot = fresh:K2_GetComponentRotation()
			end
		end
		--TODO hard coded for right handed weapon holding. Add left support
		if rot ~= nil and hand == Handed.Right and gunstockOffsetsEnabled == true then
			--rotate the worldspace controller rotation but the gunstock local space offset
			rot = kismet_math_library:ComposeRotators(gunstockRotation, rot)
		end
    else
        local status = accessoryStatus[hand]
        if status.parentAttachment ~= nil then
            -- Guard against stale/GC'd references (e.g. weapon switched before detach fires)
            if uevrUtils.getValid(status.parentAttachment) == nil then
                accessoryStatus[hand] = nil
                return loc, rot
            end
            if status.parentAttachment.GetSocketLocation == nil then
                print("IK accessory parent attachment has no GetSocketLocation:", status.parentAttachment:get_full_name())
            else
                loc = status.parentAttachment:GetSocketLocation(uevrUtils.fname_from_string(status.socketName or ""))
                rot = status.parentAttachment:GetSocketRotation(uevrUtils.fname_from_string(status.socketName or ""))
                if status.loc ~= nil and status.rot ~= nil then
                    local offsetPos = uevrUtils.vector(status.loc) or uevrUtils.vector(0,0,0)
                    local offsetRot = uevrUtils.rotator(status.rot) or uevrUtils.rotator(0,0,0)

                    loc = kismet_math_library:Add_VectorVector(loc, kismet_math_library:GreaterGreater_VectorRotator(offsetPos, rot))
                    rot = kismet_math_library:ComposeRotators(offsetRot, rot)
                end
            end
        end
    end
    return loc, rot
end

--stopDebug = false
local count = 0
function Rig:solveTwoBone(solverParams)
    local mesh = solverParams.mesh				-- UPoseableMeshComponent
    local RootBone = solverParams.startBone		-- e.g. "UpperArm_L"
    local JointBone = solverParams.jointBone	-- e.g. "LowerArm_L"
    local EndBone = solverParams.endBone		-- e.g. "Hand_L"
    local wristBone = solverParams.wristBone
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

	local state = solverParams.state
	if state == nil then
		state = newIKState()
		solverParams.state = state
	end
    VEC_UNIT_Y = VEC_UNIT_Y_FORWARD

	if controllerPosWS == nil or controllerRotWS == nil then
        print("solveTwoBone: Missing controller position/rotation")
		return
	end

    --------------------------------------------------------------
    -- 1. Component transform + shoulder position (fail-fast)
    --------------------------------------------------------------
	-- compToWorld MUST be fetched every tick: the mesh is parented to pawn.RootComponent,
	-- so any body rotation changes this transform. Caching it causes the hand to drift
	-- away from the controller whenever the pawn rotates.
	if uevrUtils.getValid(mesh) == nil or mesh.K2_GetComponentToWorld == nil then
		print("SolveVRArmIK: Mesh has no K2_GetComponentToWorld")
		return
	end
	local compToWorld = mesh:K2_GetComponentToWorld()
	if compToWorld == nil then return end

	local shoulderWS = mesh:GetBoneLocationByName(RootBone, EBoneSpaces.WorldSpace)
	if shoulderWS == nil then return end

    --------------------------------------------------------------
    -- 2. Compute Effector (hand target)
    --------------------------------------------------------------
    -- effectorWS = where the HAND BONE should go
    -- controllerPosWS is where the real hand is
    -- handOffset rotates/translates controller → hand bone pose
	-- If you want no offsets: pass handOffset=nil and effectorWS will be the controller location.
	-- handOffset is controller-local, so we must rotate it by the controller's world rotation.
    --------------------------------------------------------------
	local effectorWS = controllerPosWS
	if handOffset ~= nil then
		local offsetWS = handOffset
		if controllerRotWS ~= nil then
			offsetWS = kismet_math_library:GreaterGreater_VectorRotator(handOffset, controllerRotWS)
		end
		effectorWS = kismet_math_library:Add_VectorVector(controllerPosWS, offsetWS)
	end
--[[
	InverseTransformRotation(compToWorld, controllerRotWS) amplifies the 0.036° of real controller movement into 0.220° by inheriting compToWorld's per-tick rotational noise. The noise is entirely in that one conversion. endBoneRotation is static, so ComposeRotators passes it straight through to the stamp.
]]--    
	local controllerRotCS = kismet_math_library:InverseTransformRotation(compToWorld, controllerRotWS)

	-- Smooth controller target in component-space offset from shoulder.
	-- This damps root-motion/head-turn jitter without smoothing final solved outputs.
	if state ~= nil and smoothing > 0 then
		local effectorOffsetWS = kismet_math_library:Subtract_VectorVector(effectorWS, shoulderWS)
		local effectorOffsetCS = kismet_math_library:InverseTransformDirection(compToWorld, effectorOffsetWS)
		local smOffsetCS = effectorOffsetCS
		if state.lastEffectorOffsetCS ~= nil then
			smOffsetCS = kismet_math_library:Add_VectorVector(
				kismet_math_library:Multiply_VectorFloat(state.lastEffectorOffsetCS, smoothing),
				kismet_math_library:Multiply_VectorFloat(effectorOffsetCS, 1 - smoothing)
			)
		end
		state.lastEffectorOffsetCS = smOffsetCS
		local smOffsetWS = kismet_math_library:TransformDirection(compToWorld, smOffsetCS)
		effectorWS = kismet_math_library:Add_VectorVector(shoulderWS, smOffsetWS)
	end

    --------------------------------------------------------------
    -- 3. Auto-generate JointTarget (elbow direction)
    --------------------------------------------------------------
    -- Forward direction from shoulder → hand target
	local shoulderToHandVector = SafeNormalize(kismet_math_library:Subtract_VectorVector(effectorWS, shoulderWS))

	-- if count > 1000 then
	-- 	count = 0
	-- 	state.lastOutwardWS = nil
	-- else
	-- 	count = count + 1
	-- end
	-- -- GetRightVector changes with pawn rotation — fetch fresh every tick.
	-- if state.lastOutwardWS == nil then
	-- 	print("Recomputing outwardWS")
	-- 	state.lastOutwardWS = self:getMeshOutward(mesh, RootBone, JointBone, shoulderToHandVector, compToWorld, controllerRotCS, allowWristAffectsElbow, wristTwistInfluence, wristTwistMax, solverParams, state)
	-- end
	-- local outwardWS = state.lastOutwardWS

	local outwardWS = self:getMeshOutward(mesh, RootBone, JointBone, shoulderToHandVector, compToWorld, controllerRotCS, allowWristAffectsElbow, wristTwistInfluence, wristTwistMax, solverParams, state)

	--------------------------------------------------------------
	-- 4. Fetch bone locations and Joint target
	--------------------------------------------------------------
	-- Bone lengths are skeleton constants — measure once, then reuse.
	local jointWS = mesh:GetBoneLocationByName(JointBone, EBoneSpaces.WorldSpace)
	local endWS   = mesh:GetBoneLocationByName(EndBone,   EBoneSpaces.WorldSpace)
	local jointTargetWS = self:getJointTarget(shoulderWS, jointWS, endWS, shoulderToHandVector, outwardWS, state)

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

    --------------------------------------------------------------
    -- 6. Reconstruct rotations from solved positions
    --------------------------------------------------------------
	local upperDirWS = SafeNormalize(kismet_math_library:Subtract_VectorVector(outJointWS, shoulderWS))
	local lowerDirWS = SafeNormalize(kismet_math_library:Subtract_VectorVector(outEndWS, outJointWS))

	--------------------------------------------------------------
	-- 7. Build target rotations in ComponentSpace
	--------------------------------------------------------------
	-- Many skeletons do NOT use +X as the "bone points-to-child" axis.
	-- We calibrate which axis (X/Y/Z with sign) to align, then construct a component-space rot.
	local upperDirCS = SafeNormalize(kismet_math_library:InverseTransformDirection(compToWorld, upperDirWS))
	local lowerDirCS = SafeNormalize(kismet_math_library:InverseTransformDirection(compToWorld, lowerDirWS))
	local poleCS = SafeNormalize(kismet_math_library:InverseTransformDirection(compToWorld, outwardWS))

	if smoothing > 0 then
		-- Normalized lerp (NLERP) to suppress per-tick noise in IK directions and pole.
		-- Directions use a light touch (20% old / 80% new) so arm tracking stays responsive.
		-- Pole uses stronger smoothing (40% old / 60% new) — it only drives elbow orientation,
		-- not hand position, so a tiny lag is perfectly acceptable there.
		local function nlerpSmoothDir(prev, curr, alpha)
			-- alpha = weight of OLD value.  0 = no smoothing, 1 = frozen.
			if prev == nil then return curr end
			local mixed = kismet_math_library:Add_VectorVector(
				kismet_math_library:Multiply_VectorFloat(prev, alpha),
				kismet_math_library:Multiply_VectorFloat(curr, 1.0 - alpha)
			)
			local len = kismet_math_library:VSize(mixed)
			if len == nil or len < 0.0001 then return curr end
			return kismet_math_library:Divide_VectorFloat(mixed, len)
		end

		upperDirCS = nlerpSmoothDir(state.smUpperDirCS, upperDirCS, 0.2)
		state.smUpperDirCS = upperDirCS

		lowerDirCS = nlerpSmoothDir(state.smLowerDirCS, lowerDirCS, 0.2)
		state.smLowerDirCS = lowerDirCS

		poleCS = nlerpSmoothDir(state.smPoleCS, poleCS, 0.4)
		state.smPoleCS = poleCS
	end

	-- Cache shoulder pole axis selection once.
	local axisShoulder = self:getShoulderPoleAxis(mesh, RootBone, JointBone, EndBone, solverParams, state)

	-- Cache joint pole axis selection.
	local axisJoint = self:getJointPoleAxis(mesh, RootBone, JointBone, EndBone, solverParams, state)

	--------------------------------------------------------------
	-- 8. Apply component-space rotations to shoulder and elbow bones
	--------------------------------------------------------------
	self:rotateShoulder(mesh, RootBone, JointBone, upperDirCS, axisShoulder, poleCS, state, smoothing)
	local elbowRotCS = self:rotateElbow(mesh, JointBone, EndBone, lowerDirCS, axisJoint, poleCS, state, smoothing)

	--------------------------------------------------------------
	-- 9. Apply controller rotation to hand/wrist bone 
	--------------------------------------------------------------
	local finalHandRotCS = self:rotateHandAndWrist(mesh, EndBone, wristBone, endBoneRotation, controllerRotWS, controllerRotCS, compToWorld, state, smoothing)

	--------------------------------------------------------------
	-- 10. Twist the forearm bones based on the hand/wrist rotation
	--------------------------------------------------------------
	self:twistForearm(mesh, lowerDirCS, elbowRotCS, finalHandRotCS, twistBones, forearmTwistMax, wristTwistMax, state)

end
Rig.solveTwoBone = uevrUtils.profiler:wrap("solveTwoBone", Rig.solveTwoBone)

function Rig:getJointTarget(shoulderWS, jointWS, endWS, shoulderToHandVector, outwardWS, state)
	if state and state.upperLen == nil and jointWS ~= nil then
		state.upperLen = kismet_math_library:VSize(kismet_math_library:Subtract_VectorVector(jointWS, shoulderWS))
	end
	if state and state.lowerLen == nil and jointWS ~= nil and endWS ~= nil then
		state.lowerLen = kismet_math_library:VSize(kismet_math_library:Subtract_VectorVector(endWS, jointWS))
	end
	local upperLen = (state and state.upperLen) or 30.0
	local lowerLen = (state and state.lowerLen) or 30.0
	local forwardDist = (upperLen + lowerLen) * 0.5
	local outwardDist = upperLen * 0.35

	-- Final elbow direction point
	return kismet_math_library:Add_VectorVector(
		shoulderWS,
		kismet_math_library:Add_VectorVector(
			kismet_math_library:Multiply_VectorFloat(shoulderToHandVector, forwardDist),
			kismet_math_library:Multiply_VectorFloat(outwardWS, outwardDist)
		)
	)
end
Rig.getJointTarget = uevrUtils.profiler:wrap("getJointTarget", Rig.getJointTarget)

function Rig:getMeshOutward(mesh, RootBone, JointBone, shoulderToHandVector, compToWorld, controllerRotCS, allowWristAffectsElbow, wristTwistInfluence, wristTwistMax, solverParams, state)
	if state == nil then return mesh:GetRightVector() end

	local meshRight = mesh:GetRightVector()
	local meshFwd   = mesh:GetForwardVector()
	local meshUp    = mesh:GetUpVector()

	if state.anchorPoleInBodySpace == nil then
		local sWS0 = mesh:GetBoneLocationByName(RootBone, EBoneSpaces.WorldSpace)
		local jWS0 = mesh:GetBoneLocationByName(JointBone, EBoneSpaces.WorldSpace)
		if sWS0 ~= nil and jWS0 ~= nil then
			local rawDir = SafeNormalize(kismet_math_library:Subtract_VectorVector(jWS0, sWS0))
			state.anchorPoleInBodySpace = {
				right = kismet_math_library:Dot_VectorVector(rawDir, meshRight),
				fwd   = kismet_math_library:Dot_VectorVector(rawDir, meshFwd),
				up    = kismet_math_library:Dot_VectorVector(rawDir, meshUp),
			}
		end
	end

	local handFallbackPole = (solverParams.hand == Handed.Left)
		and kismet_math_library:Multiply_VectorFloat(meshRight, -1.0)
		or meshRight

	local outwardWS = state.lastValidPoleWS or handFallbackPole
	if state.anchorPoleInBodySpace ~= nil then
		local a = state.anchorPoleInBodySpace
		local anchorPoleWS = SafeNormalize(
			kismet_math_library:Add_VectorVector(
				kismet_math_library:Add_VectorVector(
					kismet_math_library:Multiply_VectorFloat(meshRight, a.right),
					kismet_math_library:Multiply_VectorFloat(meshFwd, a.fwd)
				),
				kismet_math_library:Multiply_VectorFloat(meshUp, a.up)
			)
		)

		local reachWS = SafeNormalize(shoulderToHandVector)
		local perp = kismet_math_library:Cross_VectorVector(reachWS, kismet_math_library:Cross_VectorVector(anchorPoleWS, reachWS))
		local perpLen = (perp ~= nil) and (kismet_math_library:VSize(perp) or 0.0) or 0.0
		if perpLen >= 0.0001 then
			local candidate = kismet_math_library:Divide_VectorFloat(perp, perpLen)
			if (kismet_math_library:Dot_VectorVector(candidate, anchorPoleWS) or 0.0) < 0.0 then
				candidate = kismet_math_library:Multiply_VectorFloat(candidate, -1.0)
			end
			outwardWS = candidate
			state.lastValidPoleWS = candidate
		end

		if controllerRotCS ~= nil and allowWristAffectsElbow and wristTwistInfluence > 0 then
			local ctrlUpCS = SafeNormalize(kismet_math_library:GetUpVector(controllerRotCS))
			local ctrlUpWS = SafeNormalize(kismet_math_library:TransformDirection(compToWorld, ctrlUpCS))
			local upProjWS = (ctrlUpWS ~= nil) and SafeNormalize(ProjectVectorOnToPlane(ctrlUpWS, reachWS)) or nil
			local upProjLen = (upProjWS ~= nil) and (kismet_math_library:VSize(upProjWS) or 0.0) or 0.0
			if upProjLen > 0.25 then
				state.lastCtrlPoleWS = upProjWS
			end
			local ctrlPoleWS = state.lastCtrlPoleWS
			if ctrlPoleWS ~= nil and kismet_math_library:VSize(ctrlPoleWS) > 0.0001 then
				local rawTwistDeg = signedAngleDegAroundAxis(outwardWS, ctrlPoleWS, reachWS)
				if rawTwistDeg ~= nil then
					rawTwistDeg = (((360 + rawTwistDeg) % 360) - 180)
					rawTwistDeg = kismet_math_library:FClamp(rawTwistDeg, -wristTwistMax, wristTwistMax)
					local appliedDeg = rawTwistDeg * wristTwistInfluence
					if math.abs(appliedDeg) > 0.01 then
						local deltaPoleRot = kismet_math_library:RotatorFromAxisAndAngle(reachWS, appliedDeg)
						outwardWS = SafeNormalize(kismet_math_library:GreaterGreater_VectorRotator(outwardWS, deltaPoleRot))
					end
				end
			end
		end

		-- Optional pole smoothing (magic numbers).
		-- Keeps elbow/forearm correctness by re-enforcing hemisphere + reach-perpendicularity after blend.
		-- prevents huge jumps when hand approaches
		local prevOutwardWS = state.smOutwardWS
		if prevOutwardWS ~= nil and kismet_math_library:VSize(prevOutwardWS) > 0.0001 then
			local POLE_SMOOTH_ALPHA_BASE = 0.72
			local POLE_SMOOTH_ALPHA_NEAR = 0.90
			local POLE_SMOOTH_NEAR_LEN = 0.30
			local alpha = (perpLen < POLE_SMOOTH_NEAR_LEN) and POLE_SMOOTH_ALPHA_NEAR or POLE_SMOOTH_ALPHA_BASE

			local mixed = kismet_math_library:Add_VectorVector(
				kismet_math_library:Multiply_VectorFloat(prevOutwardWS, alpha),
				kismet_math_library:Multiply_VectorFloat(outwardWS, 1.0 - alpha)
			)
			local mixedLen = kismet_math_library:VSize(mixed) or 0.0
			if mixedLen > 0.0001 then
				outwardWS = kismet_math_library:Divide_VectorFloat(mixed, mixedLen)
				if (kismet_math_library:Dot_VectorVector(outwardWS, anchorPoleWS) or 0.0) < 0.0 then
					outwardWS = kismet_math_library:Multiply_VectorFloat(outwardWS, -1.0)
				end
				local perpSm = kismet_math_library:Cross_VectorVector(reachWS, kismet_math_library:Cross_VectorVector(outwardWS, reachWS))
				local perpSmLen = (perpSm ~= nil) and (kismet_math_library:VSize(perpSm) or 0.0) or 0.0
				if perpSmLen > 0.0001 then
					outwardWS = kismet_math_library:Divide_VectorFloat(perpSm, perpSmLen)
					if (kismet_math_library:Dot_VectorVector(outwardWS, anchorPoleWS) or 0.0) < 0.0 then
						outwardWS = kismet_math_library:Multiply_VectorFloat(outwardWS, -1.0)
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
	if state.shoulderPoleAxisForBones ~= (RootBone .. "->" .. JointBone) or state.shoulderPoleAxisChoice == nil then
		local rootDir = getBoneDirCS(mesh, RootBone, JointBone)
		local sx, sy, sz = axisVectorsFromRot(mesh:GetBoneRotationByName(RootBone, EBoneSpaces.ComponentSpace))
		local shoulderLong = chooseBestAxis(sx, sy, sz, rootDir)
		local handFallbackPoleRef = (solverParams.hand == Handed.Left) and (VEC_UNIT_Y_INVERSE or uevrUtils.vector(0, -1, 0)) or (VEC_UNIT_Y or uevrUtils.vector(0, 1, 0))
	    local poleAxisRefCS = getBendPoleRefCS(mesh, RootBone, JointBone, EndBone) or handFallbackPoleRef
		state.shoulderPoleAxisChoice = chooseBestPoleAxis(sx, sy, sz, shoulderLong.axis, poleAxisRefCS)
		state.shoulderPoleAxisForBones = RootBone .. "->" .. JointBone
	end
	return { pole = state.shoulderPoleAxisChoice }
end
Rig.getShoulderPoleAxis = uevrUtils.profiler:wrap("getShoulderPoleAxis", Rig.getShoulderPoleAxis)

function Rig:getJointPoleAxis(mesh, RootBone, JointBone, EndBone, solverParams, state)
	if state.bonesKey == nil then state.bonesKey = JointBone .. "->" .. EndBone end
	local bonesKey = state.bonesKey
	if state.jointPoleAxisChoice == nil or state.jointPoleAxisForBones ~= bonesKey then
		local jointDir = getBoneDirCS(mesh, JointBone, EndBone)
		local jx, jy, jz = axisVectorsFromRot(mesh:GetBoneRotationByName(JointBone, EBoneSpaces.ComponentSpace))
		local jointLong = chooseBestAxis(jx, jy, jz, jointDir)
		local handFallbackPoleRef = (solverParams.hand == Handed.Left) and (VEC_UNIT_Y_INVERSE or uevrUtils.vector(0, -1, 0)) or (VEC_UNIT_Y or uevrUtils.vector(0, 1, 0))
		local poleAxisRefCS = getBendPoleRefCS(mesh, RootBone, JointBone, EndBone) or handFallbackPoleRef
		state.jointPoleAxisChoice = chooseBestPoleAxis(jx, jy, jz, jointLong.axis, poleAxisRefCS)
		state.jointPoleAxisForBones = bonesKey
	end
	return { pole = state.jointPoleAxisChoice }
end
Rig.getJointPoleAxis = uevrUtils.profiler:wrap("getJointPoleAxis", Rig.getJointPoleAxis)

function Rig:rotateShoulder(mesh, RootBone, JointBone, upperDirCS, axisShoulder, poleCS, state, smoothing)
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
	-- 	local preShoulderRot = mesh:GetBoneRotationByName(RootBone, EBoneSpaces.ComponentSpace)
	-- 	if preShoulderRot ~= nil then
	-- 		print("Shoulder bone CS pre-align:", preShoulderRot.Pitch, preShoulderRot.Yaw, preShoulderRot.Roll)
	-- 	end
	-- end

	if smoothing > 0 then
		-- Pre-set shoulder to last IK value so alignBoneAxisToDirCS reads our output, not the animation override.
		-- Without this: when animation snaps the bone and curDir ≈ upperDirCS (swing < IK_MIN_SWING_DEG),
		-- the function returns currentRot unchanged — passing animation noise straight through to the output.
		if state.lastShoulderCompRot ~= nil then
			mesh:SetBoneRotationByName(RootBone, state.lastShoulderCompRot, EBoneSpaces.ComponentSpace)
		end
	end

	local ShoulderCompRot = alignBoneAxisToDirCS(mesh, RootBone, JointBone, upperDirCS, axisShoulder, poleCS, shoulderAlignState)
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
			mesh:SetBoneRotationByName(RootBone, ShoulderCompRot, EBoneSpaces.ComponentSpace)
			state.lastShoulderCompRot = ShoulderCompRot
		else
 			mesh:SetBoneRotationByName(RootBone, ShoulderCompRot, EBoneSpaces.ComponentSpace)
		end
	end
end
Rig.rotateShoulder = uevrUtils.profiler:wrap("rotateShoulder", Rig.rotateShoulder)

function Rig:rotateElbow(mesh, JointBone, EndBone, lowerDirCS, axisJoint, poleCS, state, smoothing)
	-- if solverParams.hand == Handed.Right and stopDebug == false then
	-- 	local dbgJointCS = mesh:GetBoneLocationByName(JointBone, EBoneSpaces.ComponentSpace)
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
			mesh:SetBoneRotationByName(JointBone, state.lastElbowCompRot, EBoneSpaces.ComponentSpace)
		end
	end

	local elbowRotCS = alignBoneAxisToDirCS(mesh, JointBone, EndBone, lowerDirCS, axisJoint, poleCS, elbowAlignState)
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
		mesh:SetBoneRotationByName(JointBone, elbowRotCS, EBoneSpaces.ComponentSpace)
		-- Cache last lower-axis for next tick to improve stability if needed.
		if state then state.lastLowerDirCS = lowerDirCS; state.lastElbowCompRot = elbowRotCS end
	end
	return elbowRotCS
end
Rig.rotateElbow = uevrUtils.profiler:wrap("rotateElbow", Rig.rotateElbow)

--This function does the final hand and optional wrist rotation using the controller rotation and a user defined offset, endBoneRotation
function Rig:rotateHandAndWrist(mesh, endBone, wristBone, endBoneRotation, controllerRotWS, controllerRotCS, compToWorld, state, smoothing)
	local finalHandRotCS = nil
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
		-- if solverParams.hand == Handed.Right and stopDebug == false then
		-- 	print("smoothedControllerRotWS:", smoothedControllerRotWS.Pitch, smoothedControllerRotWS.Yaw, smoothedControllerRotWS.Roll)
		-- 	print("finalHandWorldRot:", finalHandWorldRot.Pitch, finalHandWorldRot.Yaw, finalHandWorldRot.Roll)
		-- end
		-- Stamp in WorldSpace: rendered WS rotation = finalHandWorldRot (independent of compToWorld noise).
		mesh:SetBoneRotationByName(endBone, finalHandWorldRot, EBoneSpaces.WorldSpace)
		if wristBone ~= "" then
			mesh:SetBoneRotationByName(wristBone, finalHandWorldRot, EBoneSpaces.WorldSpace)
		end
		-- if solverParams.hand == Handed.Right and stopDebug == false then
		-- 	local _ebRotWS = mesh:GetBoneRotationByName(EndBone, EBoneSpaces.WorldSpace)
		-- 	local _ebPosWS = mesh:GetBoneLocationByName(EndBone, EBoneSpaces.WorldSpace)
		-- 	if _ebRotWS ~= nil then print("EndBone rot WS post-set:", _ebRotWS.Pitch, _ebRotWS.Yaw, _ebRotWS.Roll) end
		-- 	if _ebPosWS ~= nil then print("EndBone pos WS post-set:", _ebPosWS.X, _ebPosWS.Y, _ebPosWS.Z) end
		-- end
	else
		finalHandRotCS = kismet_math_library:ComposeRotators(endBoneRotation, controllerRotCS)
		mesh:SetBoneRotationByName(endBone, finalHandRotCS, EBoneSpaces.ComponentSpace)
		if wristBone ~= "" then
			mesh:SetBoneRotationByName(wristBone, finalHandRotCS, EBoneSpaces.ComponentSpace)
		end
	end

	return finalHandRotCS
end
Rig.rotateHandAndWrist = uevrUtils.profiler:wrap("rotateHandAndWrist", Rig.rotateHandAndWrist)


function Rig:twistForearm(mesh, lowerDirCS, lowerArmRotCS, finalHandCompRot, twistBones, forearmTwistMax, wristTwistMax, state)
	if state ~= nil and lowerArmRotCS ~= nil and #twistBones > 0 then
		-- Extract the wrist→forearm "tube twist" (pronation/supination) around the forearm axis.
		-- We use a quaternion swing–twist decomposition of the relative rotation (lowerArmRotCS -> finalHandCompRot)
		-- so wrist pitch/yaw doesn't leak into the twist value.
--if solverParams.hand == Handed.Left and stopDebug == false then print("Lower arm rot CS:", lowerArmRotCS.Pitch, lowerArmRotCS.Yaw, lowerArmRotCS.Roll) end
--if solverParams.hand == Handed.Left and stopDebug == false then print("Final hand comp rot:", finalHandCompRot.Pitch, finalHandCompRot.Yaw, finalHandCompRot.Roll) end
--if solverParams.hand == Handed.Left and stopDebug == false then print("Lower dir CS:", lowerDirCS.X, lowerDirCS.Y, lowerDirCS.Z) end
		local twistAngleDeg = computeTwistDegAroundAxis_Rotators(lowerArmRotCS, finalHandCompRot, lowerDirCS)
		-- -- Twist direction convention: for this rig/controller mapping, negate to match physical wrist roll.
		-- if twistAngleDeg ~= nil then
		-- 	twistAngleDeg = -twistAngleDeg
		-- end
--if solverParams.hand == Handed.Left and stopDebug == false then print("Forearm twist angle deg:", twistAngleDeg) end
		twistAngleDeg = normalizeDeg180(twistAngleDeg)
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
--if solverParams.hand == Handed.Left and stopDebug == false then print("Forearm twist angle deg: 4", twistAngleDeg) end

		if twistAngleDeg == nil or math.abs(twistAngleDeg) < IK_MIN_TWIST_DEG then
			return
		end
--if solverParams.hand == Handed.Left and stopDebug == false then print("Forearm twist angle deg: 5", twistAngleDeg) end

        for _, entry in ipairs(twistBones) do
            --if not entry._fname then entry._fname = uevrUtils.fname_from_string(entry.bone) end
            --print(entry.bone, entry.fraction)
            local boneFName = uevrUtils.fname_from_string(entry.bone)
            local vecs = state.twistBoneVecs and state.twistBoneVecs[entry.bone]
            if vecs == nil then break end

            -- Step 1: bring stored bone-local axes into current component space.
            -- GreaterGreater_VectorRotator(v_local, rot) = pure matrix multiply, no Euler decomposition.
            local xCS = kismet_math_library:GreaterGreater_VectorRotator(vecs.x, lowerArmRotCS)
            local zCS = kismet_math_library:GreaterGreater_VectorRotator(vecs.z, lowerArmRotCS)

            -- Step 2: rotate both axes around the forearm tube axis by the fractional angle.
            local tubeRot = kismet_math_library:RotatorFromAxisAndAngle(lowerDirCS, twistAngleDeg * entry.fraction)
            xCS = kismet_math_library:GreaterGreater_VectorRotator(xCS, tubeRot)
            zCS = kismet_math_library:GreaterGreater_VectorRotator(zCS, tubeRot)

            -- Step 3: reconstruct CS rotation from two vectors — no Euler composition at all.
            local finalCS = kismet_math_library:MakeRotFromXZ(xCS, zCS)
            mesh:SetBoneRotationByName(boneFName, finalCS, EBoneSpaces.ComponentSpace)
        end
    end
end
Rig.twistForearm = uevrUtils.profiler:wrap("twistForearm", Rig.twistForearm)

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
			local parentTransform = mesh:GetBoneTransformByName(mesh:GetParentBone(f), boneSpace)
			local wTransform = mesh:GetBoneTransformByName(f, boneSpace)
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
	local mesh = active and active.mesh or nil
	if state == nil or mesh == nil then return end

	state.twistBoneVecs = state.twistBoneVecs or {}
	local lowerArmRot = mesh:GetBoneRotationByName(active.jointBone, EBoneSpaces.ComponentSpace)
	local twistBones = active.twistBones
	if lowerArmRot ~= nil and twistBones ~= nil then
		for _, entry in ipairs(twistBones) do
			local boneName = entry and entry.bone
			if boneName ~= nil and state.twistBoneVecs[boneName] == nil then
				local boneCS = mesh:GetBoneRotationByName(boneName, EBoneSpaces.ComponentSpace)
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
			local mesh = self.mesh
			--this should have been done in create
			-- if mesh == nil then
			-- 	if rigParams.mesh == "Custom" then
			-- 		if getCustomIKComponent ~= nil then
			-- 			mesh = getCustomIKComponent(self.rigId)
			-- 		end
			-- 	else
			-- 		mesh = uevrUtils.getObjectFromDescriptor(rigParams.mesh, false)
			-- 	end
			-- 	self.mesh = mesh
			-- end
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
                controller = controllers.getController(Handed.Left)
            else
                controller = controllers.getController(Handed.Right)
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

            self.activeSolvers[solverId] = {
                mesh = mesh,
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
				smoothing = solverParams["smoothing"] or 0.0,
				rotSmoothing = solverParams["rot_smoothing"] or 0.85,
                --invertForearmRoll = solverParams["invert_forearm_roll"] or false,
                --animationLocationOffset = rigParams["animation_location_offset"] and uevrUtils.vector(rigParams["animation_location_offset"]) or uevrUtils.vector(0,0,0),
				--animationRotationOffset = rigParams["animation_rotation_offset"] and uevrUtils.rotator(rigParams["animation_rotation_offset"]) or uevrUtils.rotator(0,0,0),
				state = newIKState(),
            }

            mesh.RelativeLocation = rigParams["mesh_location_offset"] and uevrUtils.vector(rigParams["mesh_location_offset"]) or uevrUtils.vector(0,0,0)
            mesh.RelativeRotation = rigParams["mesh_rotation_offset"] and uevrUtils.rotator(rigParams["mesh_rotation_offset"]) or uevrUtils.rotator(0,0,0)


			local active = self.activeSolvers[solverId]
			self:initializeSolverState(active)
			if self.defaultSolverId == nil then
				self.defaultSolverId = solverId
			end

            local initialTransforms = {}
            local boneNames = uevrUtils.getBoneNames(mesh)
            for i, boneName in ipairs(boneNames) do
                local f = uevrUtils.fname_from_string(boneName)
                table.insert(initialTransforms, {boneName = boneName, transform = mesh:GetBoneTransformByName(f, EBoneSpaces.ComponentSpace)})
            end
            self.initialTransforms = initialTransforms
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
            --             ancestorLocalTransforms[boneName] = mesh:GetBoneTransformByName(f, EBoneSpaces.ComponentSpace)
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
-- 			uevrUtils.vector(-8,0,0),         -- Offset from controller → hand bone (controller-local)
-- 			false,       -- AllowStretch (rotation-only solve cannot magically extend the arm)
-- 			0.0,  -- float
-- 			0.0,     -- float,
-- 			{  -- TwistBones: distribute wrist roll across the three forearm pronation bones
-- 				{ bone = "r_lowerTwistUp_JNT",  fraction = 0.25 }, -- nearest elbow
-- 				{ bone = "r_lowerTwistMid_JNT", fraction = 0.50 },
-- 				{ bone = "r_lowerTwistLow_JNT", fraction = 0.75 }, -- nearest wrist
-- 				--{ bone = "r_wrist_JNT", fraction = 0.90 }, -- nearest wrist
-- 				-- r_wrist_JNT is a flexion bone (rest rotation differs ~90°) — not a twist bone
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
	meshCreatedCallback = callback
end



uevrUtils.registerUEVRCallback("on_accessory_attach", function(handed, parentAttachment, socketName, attachType, loc, rot)
	accessoryStatus = accessoryStatus or {}

    -- Guard: when force-controller tracking is active, ignore the bare-hands IK socket
    -- poll. The poller fires jnt_l/r_ik_hand on CharacterMesh0 every ~300ms and would
    -- immediately clear FCT and lock the arm to the frozen body-mesh socket position.
    if forceControllerTracking[handed] and (socketName == "jnt_l_ik_hand" or socketName == "jnt_r_ik_hand") then
        return
    end

    accessoryStatus[handed] = {
        parentAttachment = parentAttachment,
        socketName = socketName,
        attachType = attachType,
        loc = loc,
        rot = rot,
    }
    -- Any real attachment (weapon, foregrip) overrides force-controller mode for this hand.
    forceControllerTracking[handed] = nil
end)

uevrUtils.registerUEVRCallback("on_accessory_detach", function(handed)
	accessoryStatus = accessoryStatus or {}
    accessoryStatus[handed] = nil
end)

uevrUtils.registerUEVRCallback("on_accessory_animation", function(handed, anim)

end)

uevrUtils.registerUEVRCallback("gunstock_transform_change", function(id, newLocation, newRotation, newOffhandLocationOffset)
    if gunstockOffsetsEnabled then
		gunstockRotation = newRotation
	end
end)

return M