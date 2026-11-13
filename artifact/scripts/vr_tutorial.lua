-- VR tutorial (2026-11-13): image pages explaining the VR controls. A port of the Cronos / Hellraiser vr_tutorial.lua
-- (libs/tutorial.lua = jbusfield's Atomic Heart lib + the Hellraiser gate option + the Cronos slot-0 guard).
-- Pages: data/tutorial/intro.png + 1.png .. N.png (counted at runtime), icons data/tutorial/buttons/. They are rendered
-- from the repo art (screenshots/) by UnrealVRMod\0. Stalker 2 Tutorial\make_pages.ps1.
--
--   * First start: shown once at the first level, and the intro waits until the player has done the open gesture once
--     (forceInteractionAtStartup). Finishing it ("Done" on the last page) or "Hide at startup" stops the automatic
--     show; data/tutorial_state.json remembers that, the gesture and the last page.
--   * Any time: left controller up to the eyes + left trigger opens it again at the saved page (within 15 cm in
--     front of the HMD, from the tracking poses: detectEyesGesture below). The trigger has to be PULLED there: a left trigger that is
--     already held (weapon wheel, lean) when the hand passes the eyes never opens it. Refused in menus, the
--     inventory / PDA, conversations, cutscenes, climbing, consumable / guitar animations, while two-handing,
--     holding a magazine or a picked-up item, and with the binoculars up. A refused pull reaches the game as usual.
--   * While open: every button is kept from the game and the other scripts (A next / start / done, X back, B close,
--     Y hide at startup; physical buttons: the dispatcher runs before Entry.lua's X/B swap) and the game is paused
--     (panel option). A paused game is a menu to gamestate.lua, so Entry.lua switches to game aim + static UI as for
--     the pause menu and restores HMD aim + follow view when the tutorial closes and the game resumes.
--   * UI placement: the page sits at UI_X_Offset / UI_Y_Offset 0.213 / 0 while open (Cronos' pick; the HUD rests at
--     0.425 to the right) and the exact previous values are restored on close or script reset.
-- Panel: "Stalker 2 VR" > "VR Tutorial" (Entry.lua) - show now, gesture on/off, pause on/off, show again at the next
-- start. The two options are Config.tutorial.gesture / .pause (settings.json).

local uevrUtils = require('libs/uevr_utils')
local tutorial = require('libs/tutorial')
Config = require("Config.CONFIG") -- same spelling as Entry.lua (gotcha: two spellings = two Config tables)
local gameState = require("stalker2.gamestate")
local okReload, ptmReload = pcall(require, "stalker2.ptm_manual_reload")
local okBinoculars, binoculars = pcall(require, "stalker2.binoculars")
local okPickup, physicalPickup = pcall(require, "physical_pickup")

local function option(key)
	local t = Config ~= nil and Config.tutorial or nil
	return t == nil or t[key] ~= false
end

local function call(module, ok, name)
	if not ok or type(module) ~= "table" or type(module[name]) ~= "function" then return false end
	local success, result = pcall(module[name])
	return success and result == true
end

-- Rising edge of the left trigger, from the raw pad before the tutorial's gesture check (priority 100001) and every
-- other handler. gestures.lua's face detector uses the same threshold (128).
local TRIGGER_THRESHOLD = 128
local leftTriggerWasDown = false
local leftTriggerPulled = false
uevrUtils.registerOnPreInputGetStateCallback(function(retval, userIndex, state)
	if userIndex ~= nil and userIndex ~= 0 then return end
	local down = state.Gamepad.bLeftTrigger > TRIGGER_THRESHOLD
	leftTriggerPulled = down and not leftTriggerWasDown
	leftTriggerWasDown = down
end, 100002)

local function isPausedOrMenu()
	local ok, result = pcall(function()
		local world = uevrUtils.get_world()
		if Statics ~= nil and world ~= nil and Statics:IsGamePaused(world) then return true end
		local pc = uevr.api:get_player_controller(0)
		return pc ~= nil and pc.bShowMouseCursor == true
	end)
	return ok and result == true
end

-- The open gesture from the runtime's tracking poses, not libs/gestures: that one reads the mod-spawned HMD and hand
-- components (libs/controllers), which are only made once there is a pawn (so never in the main menu, where the
-- first-start intro waits for this gesture), and the HMD component's direction can freeze on this backend (see
-- controllers.ensureHMDState). Same test as gestures.lua EYESCRATCH: trigger past 128, hand within 15 cm of the HMD
-- and in front of it (direction dot > 0.85). Pose space: metres, Y up, the HMD looks down -Z.
local EYES_DISTANCE = 0.15
local EYES_FORWARD_DOT = 0.85
local headPos, headRot, handPos, handRot = nil, nil, nil, nil

local function detectEyesGesture(state, hand)
	local isLeft = hand == Handed.Left
	if (isLeft and state.Gamepad.bLeftTrigger or state.Gamepad.bRightTrigger) <= TRIGGER_THRESHOLD then return false end
	local ok, result = pcall(function()
		local vr = uevr.params.vr
		if headPos == nil then
			headPos, headRot = Vector3f.new(0, 0, 0), Quaternionf.new(0, 0, 0, 0)
			handPos, handRot = Vector3f.new(0, 0, 0), Quaternionf.new(0, 0, 0, 0)
		end
		vr.get_pose(vr.get_hmd_index(), headPos, headRot)
		vr.get_pose(isLeft and vr.get_left_controller_index() or vr.get_right_controller_index(), handPos, handRot)
		local dx, dy, dz = handPos.X - headPos.X, handPos.Y - headPos.Y, handPos.Z - headPos.Z
		local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
		if distance >= EYES_DISTANCE or distance < 0.0001 then return false end
		-- HMD forward = (0, 0, -1) rotated by the HMD quaternion
		local x, y, z, w = headRot.X, headRot.Y, headRot.Z, headRot.W
		local fx = -2 * (w * y + z * x)
		local fy = 2 * (w * x - z * y)
		local fz = -1 + 2 * (x * x + y * y)
		return (fx * dx + fy * dy + fz * dz) / distance > EYES_FORWARD_DOT
	end)
	return ok and result == true
end

-- false while the left trigger near the eyes belongs to something else (asked only once the gesture is detected)
local function gestureAllowed()
	if not option("gesture") then return false end
	if not leftTriggerPulled then return false end
	local gs = gameState
	if gs.inMenu or gs.isInventoryPDA or gs.isConversation or gs.isInCutscene or gs.isClimbing
		or gs.isAnimMontagePlaying or gs.isMontageAttached or gs.isGuitarEquipped then return false end
	if gs.isTwoHanding or TwoHandedStateActive == true then return false end
	if call(ptmReload, okReload, "isHolding") or call(ptmReload, okReload, "isRackGripping") then return false end
	if call(physicalPickup, okPickup, "isGrabbing") then return false end
	if call(binoculars, okBinoculars, "isActive") then return false end
	if isPausedOrMenu() then return false end
	return true
end

-- Place the UI for the tutorial while it is open (see the header)
local UI_OFFSET_KEYS = { "UI_X_Offset", "UI_Y_Offset" }
local TUTORIAL_OFFSETS = { UI_X_Offset = "0.213000", UI_Y_Offset = "0.000000" }
local savedOffsets = nil

local function centreUI()
	if savedOffsets ~= nil then return end
	local ok = pcall(function()
		local saved = {}
		for _, key in ipairs(UI_OFFSET_KEYS) do saved[key] = uevr.params.vr:get_mod_value(key) end
		savedOffsets = saved
		for _, key in ipairs(UI_OFFSET_KEYS) do uevr.params.vr.set_mod_value(key, TUTORIAL_OFFSETS[key]) end
	end)
	if not ok then savedOffsets = nil end
end

local function restoreUI()
	if savedOffsets == nil then return end
	local saved = savedOffsets
	savedOffsets = nil
	for _, key in ipairs(UI_OFFSET_KEYS) do
		if saved[key] ~= nil then pcall(function() uevr.params.vr.set_mod_value(key, saved[key]) end) end
	end
end

-- The page host: libs/widget borrows a widget class and replaces its tree. Its own search finds nothing here (the
-- object scan sees only adopted objects on this backend, and Stalker's widgets derive from native game classes),
-- so it is named: W_Image_C has no Blueprint graph and its parent is the native ImageWidget. Checked live 2026-11-13
-- (and used as a raw host by the HUD tool). Its style manager and default icon would act on the ImageObj child,
-- which the replaced tree no longer has, so both are off before it is constructed.
require('libs/widget').setHostWidgetClass(
	"WidgetBlueprintGeneratedClass /Game/GameLite/FPS_Game/UIRemaster/CommonWidgets/W_Image.W_Image_C",
	function(host)
		pcall(function() host.bEnableStyleManager = false end)
		pcall(function() host.bSetDefaultIcon = false end)
	end)

local t = tutorial.new({
	imageSize = 1536,
	pauseGame = option("pause"),
	lockView = false,               -- Entry.lua owns UI_FollowView (menu / cutscene transitions); libs/ui.lua is not set up here
	disableControllerMouse = false, -- Stalker's ui.lua has no custom states
	buttons = { start = "A", next = "A", done = "A", back = "X", close = "B", skip = "B", hideAtStartup = "Y" },
	openGestureDetector = detectEyesGesture,
	openGestureCondition = gestureAllowed,
	onOpen = function() centreUI() end,
	onClose = function() restoreUI() end,
})
t:forceInteractionAtStartup(true)
t:showOnce()

-- the lib's own script-reset teardown skips onClose
uevr.params.sdk.callbacks.on_script_reset(restoreUI)

-- Panel buttons run while UEVR draws its overlay: widgets are made on the next engine tick instead
local pending = nil
uevrUtils.registerPreEngineTickCallback(function()
	t.options.pauseGame = option("pause")
	if pending == nil then return end
	local action = pending
	pending = nil
	if action == "show" then
		t:show(t:getSavedPage() or 1)
	elseif action == "reset" then
		t:resetCompleted()
		t:resetInteraction()
		t:resetSavedPage()
	end
end)

_G.stalkerVRTutorial = {
	requestShow = function() pending = "show" end,
	requestReset = function() pending = "reset" end,
	statusText = function()
		local ok, completed = pcall(function() return t:isCompleted() end)
		if ok and completed then return "Shown at start: no (finished or hidden)" end
		return "Shown at start: yes"
	end,
}
