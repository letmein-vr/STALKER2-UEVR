-- IK Arms router (Stalker 2, 2026-10-04).
--
-- Installed by scripts/hands.lua as the libs/hands.lua IK delegate while the IK rig (libs/ik.lua) is the
-- active arms. Every glove call Entry.lua, physical_pickup and the reload modules make (attach to weapon /
-- socket / controller, finger poses, grip animation state) lands here and is mapped onto the rig:
--
--   attachHandToMesh       -> ik.setAccessoryTarget: the arm solves to the socket instead of the controller
--   attachHandToController -> ik.clearAccessoryTarget + reset fingers, like the glove version
--   setHandPose            -> unchanged glove code, applied to the rig mesh (same skeleton, same bone names)
--   holding / anim state   -> libs/hands_animation.lua, which owns the rig's finger animations
--
-- Glove socket offsets are kept as they are tuned. A glove's hand bone sits at HB (hands_parameters
-- Location/Rotation, relative to the skeleton root) inside the glove component, and attachHandToMesh puts
-- that component at G (the offsets) on the socket:   hand = HB * G * Socket.
-- The rig puts the hand bone at E (ik_parameters end_bone_offset/end_bone_rotation) on its target, so the
-- target for a socket is L * Socket with   E * L = HB * G   ->   L = E^-1 * HB * G   (UE compose order).
-- With E == HB (the current data) that is L = G.
--
-- Montage hand attaches to the pawn body mesh (jnt_?_ik_hand / jnt_l_weapon sockets) are NOT followed:
-- the old IK snapshot froze the arm doing that. The rig stays on the controllers for those.

local uevrUtils = require('libs/uevr_utils')
local animation = require('libs/animation')
-- dot-form requires, see ptm_manual_reload.lua
local ik = require('libs/ik')
local handsAnimation = require('libs/hands_animation')

local M = {}

local HANDS_PARAMETERS_FILE = "hands_parameters"
local HANDS_PROFILE = "Main" -- scripts/hands.lua createGloves

local BONE_SPACE_COMPONENT = 1

-- ---------------------------------------------------------------------------
-- Glove definitions (data/hands_parameters.json, profile "Main", first mesh entry e.g. "Arms")
-- ---------------------------------------------------------------------------
local gloveDefinition = nil
local function getGloveDefinition()
	if gloveDefinition == nil then
		local params = json.load_file(HANDS_PARAMETERS_FILE .. ".json")
		local profile = params and params["profiles"] and params["profiles"][HANDS_PROFILE]
		for _, definition in pairs(profile or {}) do
			if type(definition) == "table" and definition["Left"] ~= nil and definition["Right"] ~= nil then
				gloveDefinition = definition
				break
			end
		end
		if gloveDefinition == nil then
			print("[IKArms] No glove definition in " .. HANDS_PARAMETERS_FILE .. ".json profile " .. HANDS_PROFILE)
			gloveDefinition = {}
		end
	end
	return gloveDefinition
end

local function getGloveHand(hand)
	return getGloveDefinition()[hand == Handed.Left and "Left" or "Right"]
end

-- ---------------------------------------------------------------------------
-- Transform helpers (kismet FTransform math, UE compose order: A * B = A local in B)
-- ---------------------------------------------------------------------------
local function arr3(t, a, b, c)
	if t == nil then return 0, 0, 0 end
	return t[a] or t[1] or 0, t[b] or t[2] or 0, t[c] or t[3] or 0
end

local function makeTransform(loc, rot)
	local x, y, z = arr3(loc, "X", "Y", "Z")
	local p, yw, r = arr3(rot, "Pitch", "Yaw", "Roll")
	local transform = uevrUtils.get_transform({X = x, Y = y, Z = z})
	local q = uevrUtils.quatFromRotator(p, yw, r)
	transform.Rotation.X = q.x
	transform.Rotation.Y = q.y
	transform.Rotation.Z = q.z
	transform.Rotation.W = q.w
	return transform
end

local function compose(a, b)
	return kismet_math_library:ComposeTransforms(a, b)
end

local function invert(t)
	return kismet_math_library:InvertTransform(t)
end

-- {X,Y,Z}, {Pitch,Yaw,Roll} plain tables
local function transformParts(t)
	local loc = kismet_math_library:TransformLocation(t, uevrUtils.vector(0, 0, 0))
	local rot = kismet_math_library:TransformRotation(t, uevrUtils.rotator(0, 0, 0))
	return {X = loc.X, Y = loc.Y, Z = loc.Z}, {Pitch = rot.Pitch, Yaw = rot.Yaw, Roll = rot.Roll}
end

-- The skeleton root in the rig's component space, without the hide_body scale (the rig is a copy of
-- Pawn.Mesh in its default pose, like the glove component). Cached per rig mesh.
local rootCache = {address = nil, transform = nil}
local function getRootTransform(mesh)
	if mesh == nil then return nil end
	local address = mesh:get_address()
	if rootCache.address ~= address then
		local ok, transform = pcall(function()
			local rootCS = mesh:GetBoneTransformByName(mesh:GetBoneName(0), BONE_SPACE_COMPONENT)
			local t = uevrUtils.get_transform({X = rootCS.Translation.X, Y = rootCS.Translation.Y, Z = rootCS.Translation.Z})
			t.Rotation.X = rootCS.Rotation.X
			t.Rotation.Y = rootCS.Rotation.Y
			t.Rotation.Z = rootCS.Rotation.Z
			t.Rotation.W = rootCS.Rotation.W
			return t
		end)
		if not ok or transform == nil then return nil end
		rootCache.address = address
		rootCache.transform = transform
	end
	return rootCache.transform
end

-- HB: the glove hand bone inside the glove component
local function getGloveHandTransform(hand, mesh)
	local definition = getGloveHand(hand)
	local root = getRootTransform(mesh)
	if definition == nil or root == nil then return nil end
	return compose(makeTransform(definition["Location"], definition["Rotation"]), root)
end

-- L = E^-1 * HB * G. Recomputed only when an input changes (Entry re-attaches every few frames on some paths).
local offsetCache = {}
local function convertGloveOffset(hand, rotationOffset, locationOffset)
	local mesh = ik.getCurrentMesh()
	local endLoc, endRot = ik.getEndBoneOffset(hand)
	local gx, gy, gz = arr3(locationOffset, "X", "Y", "Z")
	local gp, gyw, gr = arr3(rotationOffset, "Pitch", "Yaw", "Roll")
	if mesh == nil or endLoc == nil then
		-- no rig yet: use the glove offsets as they are (exact while E == HB)
		return {X = gx, Y = gy, Z = gz}, {Pitch = gp, Yaw = gyw, Roll = gr}
	end
	local key = table.concat({tostring(mesh:get_address()), gx, gy, gz, gp, gyw, gr,
		endLoc.X, endLoc.Y, endLoc.Z, endRot.Pitch, endRot.Yaw, endRot.Roll}, ",")
	local cached = offsetCache[hand]
	if cached ~= nil and cached.key == key then return cached.loc, cached.rot end

	local loc, rot = {X = gx, Y = gy, Z = gz}, {Pitch = gp, Yaw = gyw, Roll = gr}
	local ok, err = pcall(function()
		local gloveHand = getGloveHandTransform(hand, mesh)
		if gloveHand == nil then return end
		local endTransform = makeTransform(endLoc, endRot)
		local gloveOffset = makeTransform(loc, rot)
		loc, rot = transformParts(compose(compose(invert(endTransform), gloveHand), gloveOffset))
	end)
	if not ok then print("[IKArms] Offset conversion failed, using glove offsets: " .. tostring(err)) end
	offsetCache[hand] = {key = key, loc = loc, rot = rot}
	return loc, rot
end

-- ---------------------------------------------------------------------------
-- Glove-origin anchors (hands.getHandAttachParent): a scene component on the rig's hand bone at HB^-1,
-- i.e. exactly where the glove component's origin would be, for things attached at socket "None" with
-- glove-tuned offsets (weapon-mod mesh, attachment simulator).
-- ---------------------------------------------------------------------------
local anchors = {} -- [hand] = {component, meshAddress}

local function destroyAnchor(hand)
	local anchor = anchors[hand]
	anchors[hand] = nil
	if anchor == nil then return end
	pcall(function()
		-- hand game-owned children (weapon-mod mesh) back to the world first; destroying the anchor
		-- with children would destroy their owner actors
		local children = anchor.component.AttachChildren
		for i = #(children or {}), 1, -1 do
			children[i]:DetachFromParent(true, false)
		end
	end)
	uevrUtils.detachAndDestroyComponent(anchor.component, true, false)
end

function M.getHandAttachParent(hand)
	local mesh = ik.getCurrentMesh()
	if mesh == nil then return nil end
	local address = mesh:get_address()
	local anchor = anchors[hand]
	if anchor ~= nil and anchor.meshAddress == address and uevrUtils.validate_object(anchor.component) ~= nil then
		return anchor.component
	end
	destroyAnchor(hand)

	local gloveHand = getGloveHandTransform(hand, mesh)
	if gloveHand == nil then return nil end
	local component = uevrUtils.create_component_of_class("Class /Script/Engine.SceneComponent")
	if component == nil then return nil end
	local ok = pcall(function()
		local boneName = getGloveHand(hand)["Name"] or (hand == Handed.Left and "jnt_l_hand" or "jnt_r_hand")
		component:K2_AttachTo(mesh, uevrUtils.fname_from_string(boneName), 0, false) -- KeepRelative
		local loc, rot = transformParts(invert(gloveHand))
		-- K2_SetRelative* (not the raw RelativeLocation/Rotation writes of set_component_relative_transform):
		-- it updates the world transform NOW. The raw writes only showed up after the rig's next child
		-- update, so a caller reading the anchor in the frame it was created (the first rack after a
		-- script reset) got the bare hand-bone frame - wrong hand rotation on that first slide grab.
		component:K2_SetRelativeLocationAndRotation(uevrUtils.vector(loc.X, loc.Y, loc.Z),
			uevrUtils.rotator(rot.Pitch, rot.Yaw, rot.Roll), false, reusable_hit_result, false)
	end)
	if not ok then
		uevrUtils.detachAndDestroyComponent(component, true, false)
		return nil
	end
	anchors[hand] = {component = component, meshAddress = address}
	return component
end

-- ---------------------------------------------------------------------------
-- Delegate interface (libs/hands.lua)
-- ---------------------------------------------------------------------------
function M.getHandComponent(hand)
	return ik.getCurrentMesh() -- one rig mesh carries both arms
end

local function isPawnBodyMesh(mesh)
	local ok, isBody = pcall(function()
		return pawn ~= nil and pawn.Mesh ~= nil and mesh:get_address() == pawn.Mesh:get_address()
	end)
	return ok and isBody
end

local function sameParent(handStatus, mesh, socketName)
	if handStatus == nil or handStatus.releasing then return false end
	local ok, same = pcall(function()
		return handStatus.parentAttachment:get_address() == mesh:get_address()
	end)
	return ok and same and (handStatus.socketName or "") == (socketName or "")
end

-- blendTime (seconds, 0/nil = snap) = the glove attachHandToMeshBlended duration
function M.attachHandToMesh(hand, mesh, socketName, rotationOffset, locationOffset, blendTime)
	if mesh == nil then return end
	if isPawnBodyMesh(mesh) then
		ik.clearAccessoryTarget(hand)
		return
	end
	local loc, rot = convertGloveOffset(hand, rotationOffset, locationOffset)
	local handStatus = ik.getAccessoryStatus(hand)
	if sameParent(handStatus, mesh, socketName) then
		-- already on this socket (per-frame re-attaches, dev-panel previews): take the new offsets
		-- without restarting a running glide
		handStatus.loc = loc
		handStatus.rot = rot
		return
	end
	ik.setAccessoryTarget(hand, mesh, socketName, 0, loc, rot, blendTime)
end

function M.attachHandToController(hand, blendTime)
	ik.clearAccessoryTarget(hand, blendTime)
	-- like the glove version: default finger pose, then the hand's current animation state
	M.setInitialTransform(hand)
	M.updateAnimationState(hand)
end

function M.setInitialTransform(hand)
	local mesh = ik.getCurrentMesh()
	local initialTransform = getGloveDefinition()["InitialTransform"]
	if mesh == nil or initialTransform == nil then return end
	animation.initializeBones(mesh, initialTransform[hand == Handed.Left and "left_hand" or "right_hand"])
end

function M.updateAnimationState(hand)
	handsAnimation.updateAnimationState(hand)
end

function M.setHoldingAttachment(hand, val)
	handsAnimation.setHoldingAttachment(hand, val, true)
end

function M.setThumbLerpSuppressed(hand, suppressed)
	handsAnimation.setThumbLerpSuppressed(hand, suppressed)
end

function M.setInputLocked(hand, locked)
	handsAnimation.setInputLocked(hand, locked)
end

-- Rig destroyed (mode switch, suit swap, level change): drop what was built on it
function M.onRigDestroyed()
	destroyAnchor(Handed.Left)
	destroyAnchor(Handed.Right)
	rootCache = {address = nil, transform = nil}
	offsetCache = {}
end

return M
