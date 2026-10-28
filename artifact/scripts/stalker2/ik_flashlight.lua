-- IK Arms mode flashlight (2026-10-04), ported from the old IK codebase (backup IK 4.5, Entry.lua
-- handleFlashlightAttachment).
--
-- In IK mode the pawn body yaws on its own (input.lua SIMPLE body yaw) and UEVR aim is Game (0), so the game's
-- flashlight - a SpotLightComponent named "SpotLight" on the pawn - would point where the body faces. While IK
-- mode is active it is detached and moved every tick to the pawn camera's location with the HMD's rotation,
-- plus Config.flashlightForward/Up/RightOffset (cm, along the look direction; a forward offset puts the light
-- past the weapon so its shadow falls behind it). The game still switches the light on/off (L / gesture).
--
-- Differences from the old code: runs only in IK mode and puts the light back on its original parent/socket
-- when leaving it. The light and camera are read from the pawn's own properties (pawn.SpotLight - the main,
-- intensity 27, on the SpringArm; pawn.Camera) instead of find_all_of: on this backend UObjectHook defers
-- adoption of existing objects, and find_all_of's class lists never contained the pawn's lights (MCP
-- objects_by_class returned 0 SpotLightComponents while the pawn had two), so the old lookup found nothing.
-- (pawn.SpotLight1 is a weak fill light already parented to the camera.)

local uevrUtils = require('libs/uevr_utils')
local controllers = require('libs/controllers')
local Config = require('Config.CONFIG')

local M = {}

local HANDS_MODE_IK = 2

local state = {
	pawnAddress = nil,
	light = nil,
	camera = nil,
	original = nil, -- {parent, socket, loc, rot} to restore when leaving IK mode
}

local function isIKMode()
	return _G.getHandsMode ~= nil and _G.getHandsMode() == HANDS_MODE_IK
end

local function addressOf(object)
	local ok, address = pcall(function() return object:get_address() end)
	return ok and address or nil
end

-- Liveness without UObjectHook.exists(), which can reject freshly loaded pawn parts on this backend (as ik.lua)
local function isAlive(object)
	if object == nil then return false end
	local ok, name = pcall(function() return object:get_full_name() end)
	return ok and name ~= nil
end

local function getPawnComponent(pawn, propertyName)
	local ok, component = pcall(function() return pawn[propertyName] end)
	if ok and isAlive(component) then return component end
	return nil
end

-- Back on its original parent at its original relative transform
local function restoreLight()
	local light, original = state.light, state.original
	if light ~= nil and original ~= nil and isAlive(light) and isAlive(original.parent) then
		pcall(function()
			-- 6-param K2_AttachToComponent (see Entry.lua's mod-mesh attach): KeepRelative x3, no weld
			light:K2_AttachToComponent(original.parent, uevrUtils.fname_from_string(original.socket), 0, 0, 0, false)
			light:K2_SetRelativeLocationAndRotation(uevrUtils.vector(original.loc), uevrUtils.rotator(original.rot), false,
				uevrUtils.get_reuseable_struct_object("ScriptStruct /Script/Engine.HitResult"), false)
		end)
	end
	state.light = nil
	state.original = nil
end

local function detachLight(light)
	local original = nil
	pcall(function()
		local parent = light.AttachParent
		if parent ~= nil then
			local socket = light.AttachSocketName
			original = {
				parent = parent,
				socket = socket ~= nil and socket:to_string() or "None",
				loc = {X = light.RelativeLocation.X, Y = light.RelativeLocation.Y, Z = light.RelativeLocation.Z},
				rot = {Pitch = light.RelativeRotation.Pitch, Yaw = light.RelativeRotation.Yaw, Roll = light.RelativeRotation.Roll},
			}
		end
		-- Sever it from the body mesh so it's a free-floating world object
		light:DetachFromParent(true, false)
	end)
	state.light = light
	state.original = original
end

local function placeLight()
	local light, camera = state.light, state.camera
	local camLoc = camera:K2_GetComponentLocation()

	-- the native motion controller component on the HMD
	local headRot = controllers.getControllerRotation(2)
	if headRot == nil then
		controllers.createController(2) -- not spawned yet: create it and use the camera for this tick
		headRot = camera:K2_GetComponentRotation()
	end

	local loc = camLoc
	local fwdOff = Config.flashlightForwardOffset or 0
	local upOff = Config.flashlightUpOffset or 0
	local rightOff = Config.flashlightRightOffset or 0
	if fwdOff ~= 0 or upOff ~= 0 or rightOff ~= 0 then
		local pr, yr = math.rad(headRot.Pitch), math.rad(headRot.Yaw)
		local cp, sp = math.cos(pr), math.sin(pr)
		local cy, sy = math.cos(yr), math.sin(yr)
		-- UE basis vectors from the rotator (roll ignored)
		local fX, fY, fZ = cp * cy, cp * sy, sp -- forward
		local rX, rY = sy, -cy -- right (horizontal)
		local uX, uY, uZ = -sp * cy, -sp * sy, cp -- up
		loc = {
			X = camLoc.X + fX * fwdOff + rX * rightOff + uX * upOff,
			Y = camLoc.Y + fY * fwdOff + rY * rightOff + uY * upOff,
			Z = camLoc.Z + fZ * fwdOff + uZ * upOff,
		}
	end

	local hitResult = uevrUtils.get_reuseable_struct_object("ScriptStruct /Script/Engine.HitResult")
	light:K2_SetWorldLocation(loc, false, hitResult, false)
	light:K2_SetWorldRotation(headRot, false, hitResult, false)
end

local function update()
	if not isIKMode() then
		if state.light ~= nil then restoreLight() end
		return
	end

	local pawn = uevr.api:get_local_pawn(0)
	if pawn == nil then return end
	local pawnAddress = addressOf(pawn)
	if pawnAddress ~= state.pawnAddress then
		-- new pawn (load / respawn): the old light and camera died with the old one
		state.pawnAddress = pawnAddress
		state.light, state.original, state.camera = nil, nil, nil
	end

	if state.light ~= nil and not isAlive(state.light) then state.light, state.original = nil, nil end
	if state.camera ~= nil and not isAlive(state.camera) then state.camera = nil end

	if state.camera == nil then
		state.camera = getPawnComponent(pawn, "Camera")
	end
	if state.light == nil then
		local light = getPawnComponent(pawn, "SpotLight")
		if light ~= nil then detachLight(light) end
	end
	if state.light == nil or state.camera == nil then return end

	local ok, err = pcall(placeLight)
	if not ok then print("[IKFlashlight] place failed: " .. tostring(err)) end
end

uevrUtils.registerPreEngineTickCallback(function(engine, delta)
	update()
end)

-- The light and camera die with the level (the old code reset its hook on level change too)
uevrUtils.registerPreLevelChangeCallback(function(level)
	state.pawnAddress, state.light, state.original, state.camera = nil, nil, nil, nil
end)

-- Script reset: put the light back while the old state can still reach it
uevr.params.sdk.callbacks.on_script_reset(function()
	if state.light ~= nil then restoreLight() end
end)

return M
