-- IK Arms: weapon / held item / IK hand lock (Stalker 2, 2026-10-10).
--
-- Problem: in IK mode the hands follow the weapon (stalker2/ik_arms.lua targets the rig's hand at the weapon's
-- S_Hand_R / jnt_l_hand sockets), but the two are posed at different points of a frame:
--   * the rig solves in the engine tick callback and its bones reach the renderer in the rig component's own tick,
--     so the arm drawn in frame N was solved against the weapon as it stood BEFORE frame N's world tick, i.e. where
--     frame N-1 left it;
--   * the weapon is placed afterwards, in the stereo view calculation (UObjectHook + Base/basic.lua offsets and
--     two-handed rotation), from frame N's controller pose.
-- The weapon was therefore always one frame of hand motion ahead of the hand holding it: the grip slid whenever the
-- gun moved or turned. In Hands mode the glove is a child component of the weapon, so it never showed there.
--
-- Hellraiser fixes the same lag by parenting the gun to the IK hand bone (weaponhook.lua ikHandTick). Here the gun
-- has to stay on UObjectHook - Base/basic.lua re-derives its offsets every frame (jnt_offset, recoil, virtual
-- gunstock on the HMD, two-handed rotation) - so the same result is reached from the other side: the weapon is DRAWN
-- where the visible arm pose holds it.
--   * post stereo (called from Base/basic.lua once the weapon has its final pose for the frame): that pose is
--     remembered as the true pose, and the component is moved to the recorded rig-relative pose (below) on the rig
--     mesh as it stands now - exactly what a child of the hand bone would do;
--   * when the rig solves (pre engine tick), the true pose is recorded RELATIVE TO THE RIG MESH. The solved arm is a
--     set of bones in that mesh's space, so this is where the hand holds the gun no matter how the rig moves
--     afterwards. The component is also put back on the true pose first, so the game's own tick (shots, traces,
--     animation) and the IK solve see exactly what they saw before this module existed.
-- The relative pose matters: the rig rides the pawn, so a world-space "previous frame" pose left the gun a whole
-- frame of walking / turning behind the arms (first version, 2026-10-10).
-- With Enhanced Stabilization the rig solves in the POST engine tick and those bones are drawn in the next frame,
-- so the pose recorded there is used one frame later (libs/ik.lua getTickPhase).
-- The weapon is only handled while an IK hand is actually targeting it; everything attached to it (reload proxies,
-- scope, mods) follows it as before.
--
-- Left-hand items (same day): the detector and picked-up items ride the left controller, which the left IK hand
-- trails by the same frame. They go through the same steps, from this module's own post-stereo callback:
--   * detector (hands_Detector.lua): a CHILD of the left controller component. Its true pose is controller *
--     Config.detectorOffset, re-established before every read and in the pre tick (our world-space write changes
--     its relative transform; never derive the true pose from a written one). Done with
--     K2_SetRelativeLocationAndRotation: uevrUtils.set_component_relative_transform only writes the properties,
--     the world transform would stay on our write until the controller next moves;
--   * picked-up item (physical_pickup.lua): a non-permanent UObjectHook state, which the backend re-places every
--     stereo pass and moves back to its natural place for the game thread - nothing to put back.

local uevrUtils = require('libs/uevr_utils')
local controllers = require('libs/controllers')
-- dot-form require, see ptm_manual_reload.lua
local ik = require('libs/ik')
local Config = require('Config.CONFIG')

local M = {}

local HANDS_MODE_IK = 2
local CAPTURE_PRIORITY = 1000 -- engine tick callbacks: ahead of the rig's solve (libs/ik.lua registers at priority 0)
local LATE_PRIORITY = -1000   -- post stereo: after the modules that place / read the held items
local SAME_POSE_EPSILON = 0.0005

local tickSerial = 0
-- key -> { address, truePose = world pose this frame, rendered = world pose written for drawing,
--          relative = pose on the rig mesh for the arm pose being drawn, pending = the same for the next frame }
local entries = {}

local function isEnabled()
	-- always on in IK mode (the Config.ikWeaponLock toggle was removed 2026-10-12 on request)
	return _G.getHandsMode ~= nil and _G.getHandsMode() == HANDS_MODE_IK and ik.exists()
end

local function isHandOnWeapon(hand, address)
	local handStatus = ik.getAccessoryStatus(hand)
	if handStatus == nil or handStatus.parentAttachment == nil then return false end
	local ok, same = pcall(function() return handStatus.parentAttachment:get_address() == address end)
	return ok and same
end

local function readPose(component)
	local loc, rot = component:K2_GetComponentLocation(), component:K2_GetComponentRotation()
	if loc == nil or rot == nil then return nil end
	return { X = loc.X, Y = loc.Y, Z = loc.Z, Pitch = rot.Pitch, Yaw = rot.Yaw, Roll = rot.Roll }
end

local function writePose(component, pose)
	component:K2_SetWorldLocationAndRotation(uevrUtils.vector(pose.X, pose.Y, pose.Z),
		uevrUtils.rotator(pose.Pitch, pose.Yaw, pose.Roll), false, reusable_hit_result, false)
end

local function samePose(a, b)
	return math.abs(a.X - b.X) < SAME_POSE_EPSILON and math.abs(a.Y - b.Y) < SAME_POSE_EPSILON
		and math.abs(a.Z - b.Z) < SAME_POSE_EPSILON and math.abs(a.Pitch - b.Pitch) < SAME_POSE_EPSILON
		and math.abs(a.Yaw - b.Yaw) < SAME_POSE_EPSILON and math.abs(a.Roll - b.Roll) < SAME_POSE_EPSILON
end

-- rigid transform (unit scale) of a pose table
local function makeTransform(pose)
	return kismet_math_library:MakeTransform(uevrUtils.vector(pose.X, pose.Y, pose.Z),
		uevrUtils.rotator(pose.Pitch, pose.Yaw, pose.Roll), uevrUtils.vector(1, 1, 1))
end

local function transformPose(transform, pose)
	local loc = kismet_math_library:TransformLocation(transform, uevrUtils.vector(pose.X, pose.Y, pose.Z))
	local rot = kismet_math_library:TransformRotation(transform, uevrUtils.rotator(pose.Pitch, pose.Yaw, pose.Roll))
	return { X = loc.X, Y = loc.Y, Z = loc.Z, Pitch = rot.Pitch, Yaw = rot.Yaw, Roll = rot.Roll }
end

local function getRigPose()
	local rig = ik.getCurrentMesh()
	if rig == nil or rig.K2_GetComponentLocation == nil then return nil end
	return readPose(rig)
end

-- a world pose in the rig mesh's space, with the rig mesh where it is now
local function worldToRelative(pose)
	local rigPose = getRigPose()
	if rigPose == nil or pose == nil then return nil end
	return transformPose(kismet_math_library:InvertTransform(makeTransform(rigPose)), pose)
end

-- a rig-relative pose back in world space, with the rig mesh where it is now
local function relativeToWorld(relative)
	local rigPose = getRigPose()
	if rigPose == nil then return nil end
	return transformPose(makeTransform(rigPose), relative)
end

-- Post stereo, component at its true pose for this frame: remember it and draw the component where the arm pose
-- being drawn holds it. alwaysFresh: the caller has just re-established the true pose, so a read can never be our
-- own earlier write.
local function place(key, component, alwaysFresh)
	local address = component:get_address()
	local entry = entries[key]
	if entry == nil or entry.address ~= address then
		entry = { address = address }
		entries[key] = entry
	end
	local pose = readPose(component)
	if pose == nil then return end
	if entry.tick ~= tickSerial then
		entry.tick = tickSerial
	elseif not alwaysFresh and entry.rendered ~= nil and samePose(pose, entry.rendered) then
		-- called again in the same frame and UObjectHook has not re-placed the component since our write: this
		-- is the rendering pose, not a new sample
		return
	end
	entry.truePose = pose

	if entry.relative ~= nil then
		local render = relativeToWorld(entry.relative)
		if render ~= nil then
			writePose(component, render)
			entry.rendered = render
		end
	end
end

-- ---------------------------------------------------------------------------
-- Weapon
-- ---------------------------------------------------------------------------
-- the equipped weapon component, only while it is still the one being tracked (also keeps a freed component from
-- being touched after a save load)
local function getTrackedWeapon(entry)
	local weapon = uevr.api:get_local_pawn(0).Mesh.AnimScriptInstance.WeaponData.WeaponMesh
	if weapon == nil or weapon:get_address() ~= entry.address then return nil end
	return weapon
end

-- Base/basic.lua, post stereo (last view of the frame), after the weapon offsets and the two-handed rotation.
function M.onWeaponPlaced(weapon)
	if weapon == nil or not isEnabled() then entries.weapon = nil return end
	local address = weapon:get_address()
	if not (isHandOnWeapon(Handed.Right, address) or isHandOnWeapon(Handed.Left, address)) then entries.weapon = nil return end
	place("weapon", weapon, false)
end

-- ---------------------------------------------------------------------------
-- Left-hand items
-- ---------------------------------------------------------------------------
local function isAlive(component)
	return component ~= nil and UEVR_UObjectHook.exists(component)
end

-- the detector, only while it hangs on the left controller (hands_Detector.lua also tracks it while unattached)
local function getDetector()
	local detectorSystem = _G.DetectorSystem
	local detector = detectorSystem ~= nil and detectorSystem.GetCurrentDetector() or nil
	if not isAlive(detector) then return nil end
	local controller = controllers.getController(Handed.Left)
	local parent = detector.AttachParent
	if controller == nil or parent == nil or parent:get_address() ~= controller:get_address() then return nil end
	return detector
end

-- detector back on its true pose: controller * Config.detectorOffset / detectorRotation (hands_Detector.lua)
local function resetDetector(detector)
	local loc, rot = Config.detectorOffset, Config.detectorRotation
	if loc == nil or rot == nil then return end
	detector:K2_SetRelativeLocationAndRotation(uevrUtils.vector(loc.X, loc.Y, loc.Z),
		uevrUtils.rotator(rot.Pitch, rot.Yaw, rot.Roll), false, reusable_hit_result, false)
end

-- the mesh physical_pickup.lua currently has hooked to the left controller. The script exists twice (UEVR
-- auto-load + Entry.lua's require), so each instance registers a getter.
local function getPickupMesh()
	for _, getter in ipairs(_G.PickupHeldMeshGetters or {}) do
		local mesh = getter()
		if mesh ~= nil then
			return isAlive(mesh) and mesh or nil
		end
	end
	return nil
end

uevrUtils.registerPostCalculateStereoViewCallback(function(device, view_index)
	if not isEnabled() then
		entries.detector = nil
		entries.pickup = nil
		return
	end
	local ok = pcall(function()
		local detector = getDetector()
		if detector ~= nil then
			resetDetector(detector)
			place("detector", detector, true)
		else
			entries.detector = nil
		end
	end)
	if not ok then entries.detector = nil end
	ok = pcall(function()
		local mesh = getPickupMesh()
		if mesh ~= nil then
			place("pickup", mesh, false)
		else
			entries.pickup = nil
		end
	end)
	if not ok then entries.pickup = nil end
end, LATE_PRIORITY)

-- ---------------------------------------------------------------------------
-- Engine tick
-- ---------------------------------------------------------------------------
-- pre engine tick, before the rig solves: components back on their true pose, then (rig solving in this tick)
-- record where the arm pose that is about to be solved holds them
uevrUtils.registerPreEngineTickCallback(function(engine, delta)
	tickSerial = tickSerial + 1
	if next(entries) == nil then return end
	if not isEnabled() then entries = {} return end
	local postPhase = ik.getTickPhase() == "post"

	for key, entry in pairs(entries) do
		local ok = pcall(function()
			if key == "weapon" then
				local weapon = getTrackedWeapon(entry)
				if weapon == nil then error("weapon changed") end
				if entry.rendered ~= nil and entry.truePose ~= nil then writePose(weapon, entry.truePose) end
			elseif key == "detector" then
				local detector = getDetector()
				if detector == nil then error("detector gone") end
				if entry.rendered ~= nil then resetDetector(detector) end
			end
			entry.rendered = nil
			if postPhase then
				entry.relative = entry.pending -- solved after the previous world tick, drawn in this frame
			else
				entry.relative = worldToRelative(entry.truePose)
			end
		end)
		if not ok then entries[key] = nil end
	end
end, CAPTURE_PRIORITY)

-- Enhanced Stabilization: the rig solves here, for the next frame
uevrUtils.registerPostEngineTickCallback(function(engine, delta)
	if next(entries) == nil or ik.getTickPhase() ~= "post" then return end
	for key, entry in pairs(entries) do
		local ok = pcall(function()
			entry.pending = worldToRelative(entry.truePose)
		end)
		if not ok then entries[key] = nil end
	end
end, CAPTURE_PRIORITY)

uevrUtils.registerPreLevelChangeCallback(function(level)
	entries = {}
end)

return M
