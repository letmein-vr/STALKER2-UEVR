-- IK Arms mode full body (2026-10-05): shows the game's own animated body and legs under the IK arms.
--
-- Pawn.Mesh (body + arms + head, one mesh) normally stays hidden in IK mode (pawn_parameters hidePawnBodyMesh /
-- hidePawnArmsMesh, render-pass flags) while the IK rig draws only the arms. With Config.ikFullBody on in IK mode:
--   * Pawn.Mesh is shown through pawn.lua's own callbacks (is_pawn_body_hidden / is_pawn_arms_hidden = false),
--     with its arms hidden from the upper arm down (is_arms_bones_hidden = true, pawn_parameters
--     pawnUpperArmLeft/Right) and its neck + head hidden here (camera sits inside the head).
--   * libs/ik.lua puts the rig's clavicles on Pawn.Mesh's every tick (ik.setFullBodySource), so the IK arms start
--     at the visible body's shoulders.
--   * While the rig is hidden (climbing, guitar - is_hands_hidden) the body's own arms show instead, as before.
--   * ForegroundFOVEnabled 0 on the body's materials while shown (same depth fix as the rig), 1 when hidden again.
-- Hands mode and IK without the toggle are untouched: every callback returns nil then, so pawn.lua falls back to
-- pawn_parameters.json.

local uevrUtils = require('libs/uevr_utils')
-- dot-form requires, see ptm_manual_reload.lua
local ik = require('libs/ik')
local Config = require('Config.CONFIG')

local M = {}

local HANDS_MODE_IK = 2
local HEAD_BONE = "jnt_neck" -- hides jnt_head with it
local PRIORITY = 100

local state = {
	active = false,
	headHiddenOn = nil, -- address of the Pawn.Mesh the head was hidden on
}

local function isAlive(object)
	if object == nil then return false end
	local ok, name = pcall(function() return object:get_full_name() end)
	return ok and name ~= nil
end

local function addressOf(object)
	local ok, address = pcall(function() return object:get_address() end)
	return ok and address or nil
end

-- Read straight off the pawn: UObjectHook.exists() can reject freshly loaded pawn parts on this backend
local function getBodyMesh()
	local p = uevr.api:get_local_pawn(0)
	if p == nil then return nil end
	local ok, mesh = pcall(function() return p.Mesh end)
	if ok and isAlive(mesh) then return mesh end
	return nil
end

local function isWanted()
	return Config.ikFullBody == true and _G.getHandsMode ~= nil and _G.getHandsMode() == HANDS_MODE_IK
end

local function isRigHidden()
	return uevrUtils.executeUEVRCallbacksWithPriorityBooleanResult("is_hands_hidden") == true
end

function M.isActive()
	return state.active
end

uevrUtils.registerUEVRCallback("is_pawn_body_hidden", function()
	if state.active then return false, PRIORITY end
	return nil, 0
end)

uevrUtils.registerUEVRCallback("is_pawn_arms_hidden", function()
	if state.active then return false, PRIORITY end
	return nil, 0
end)

uevrUtils.registerUEVRCallback("is_arms_bones_hidden", function()
	if state.active then return not isRigHidden(), PRIORITY end
	return nil, 0
end)

-- Shoulder smoothing (2026-10-12). Unarmed, the body's walk / jump animation swings its clavicles, and the IK arms
-- pinned to them bobbed (gone with the full body off). Each clavicle is low-pass filtered in the body
-- mesh's own space, so capsule movement and turning pass straight through and only the animation is smoothed.
-- Config.ikFullBodyShoulderSmoothing = time constant in seconds, 0 = exact pin as before.
local SMOOTHING_DEFAULT_S = 0.35
local SMOOTHING_RESET_S = 0.5 -- no sample for this long (rig hidden, pause): start again from the live pose
local smoothed = {}
ik.setFullBodyShoulderFilter(function(index, worldTransform, source)
	local tau = tonumber(Config.ikFullBodyShoulderSmoothing) or SMOOTHING_DEFAULT_S
	if tau <= 0 then
		smoothed[index] = nil
		return nil
	end
	local meshToWorld = source:K2_GetComponentToWorld()
	local rel = kismet_math_library:MakeRelativeTransform(worldTransform, meshToWorld)
	local now, address = os.clock(), addressOf(source)
	local prev = smoothed[index]
	if prev ~= nil and prev.address == address and now - prev.time < SMOOTHING_RESET_S then
		local alpha = 1 - math.exp(-(now - prev.time) / tau)
		rel = kismet_math_library:TLerp(prev.transform, rel, alpha, 0) -- 0 = QuatInterp
	end
	smoothed[index] = { transform = rel, time = now, address = address }
	return kismet_math_library:ComposeTransforms(rel, meshToWorld)
end)

-- Shoulder height (2026-10-12): with the full body on, the rig's own mesh offset (IK dev panel) has no effect - the
-- clavicles are pinned to the body - so the pinned points get their own offsets, in cm: height (negative = lower),
-- width (each shoulder pushed outward, 2026-10-12 as in the Hellraiser profile) and forward.
ik.setFullBodyShoulderOffset(function()
	return tonumber(Config.ikFullBodyShoulderWidth) or 0,
		tonumber(Config.ikFullBodyShoulderForward) or 0,
		tonumber(Config.ikFullBodyShoulderHeight) or 0
end)

local function setForegroundFOV(mesh, value)
	pcall(function() uevrUtils.fixMeshFOV(mesh, "ForegroundFOVEnabled", value, false, false, false) end)
end

local function activate(mesh)
	state.active = true
	ik.setFullBodySource(getBodyMesh)
	setForegroundFOV(mesh, 0.0)
	print("[IKFullBody] on")
end

local function deactivate()
	state.active = false
	ik.setFullBodySource(nil)
	local mesh = getBodyMesh()
	if mesh ~= nil then
		if state.headHiddenOn ~= nil and addressOf(mesh) == state.headHiddenOn then
			pcall(function() mesh:UnHideBoneByName(uevrUtils.fname_from_string(HEAD_BONE)) end)
		end
		setForegroundFOV(mesh, 1.0)
	end
	state.headHiddenOn = nil
	-- the rig's clavicles keep the body's last pose; rebuild it from its reference pose (auto-created within ~1 s)
	if ik.exists() then ik.destroyAll() end
	print("[IKFullBody] off")
end

uevrUtils.setInterval(100, function()
	local wanted = isWanted()
	local mesh = wanted and getBodyMesh() or nil
	if wanted and mesh ~= nil then
		if not state.active then activate(mesh) end
		-- (re)hide the head on the current body mesh (a new pawn after a load or respawn)
		local address = addressOf(mesh)
		if state.headHiddenOn ~= address then
			local ok = pcall(function() mesh:HideBoneByName(uevrUtils.fname_from_string(HEAD_BONE), 0) end)
			if ok then
				state.headHiddenOn = address
				setForegroundFOV(mesh, 0.0)
			end
		end
	elseif state.active and not wanted then
		deactivate()
	end
end)

uevrUtils.registerPreLevelChangeCallback(function(level)
	state.headHiddenOn = nil -- the level's pawn mesh is replaced
end)

return M
