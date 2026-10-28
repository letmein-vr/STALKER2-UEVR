local uevrUtils = require('libs/uevr_utils')
local hands = require('libs/hands')
local controllers = require('libs/controllers')
-- IK Arms mode (2026-10-04, ported from the OW2 profile): libs/ik.lua builds a PoseableMesh rig
-- copied from Pawn.Mesh (data/ik_parameters.json) and solves two-bone IK to the controllers;
-- hands_animation.lua drives its fingers. Must stay dot-form (see ptm_manual_reload.lua).
local ik = require('libs/ik')
local handsAnimation = require('libs/hands_animation')
local input = require('libs/input')
local ikArms = require('stalker2.ik_arms')
require('stalker2.ik_flashlight') -- IK mode: game flashlight follows the HMD (self-gated on the mode)
require('stalker2.ik_full_body') -- IK mode + Config.ikFullBody: game body/legs shown under the IK arms (self-gated)
local Config = require('Config.CONFIG')

local HANDS_MODE_GLOVES = 1
local HANDS_MODE_IK     = 2

local function getHandsMode()
	return (Config.handsMode == HANDS_MODE_IK) and HANDS_MODE_IK or HANDS_MODE_GLOVES
end
_G.getHandsMode = getHandsMode

-- libs/input.lua is the old IK codebase's (backup IK 4.5) module, with its input_parameters.json: it drives
-- pawn yaw and the VR camera anchor so the IK rig stays under the HMD. It is only live in IK Arms mode: in
-- Hands mode this callback keeps it disabled (results are OR'd, so true always wins) and the game + UEVR's
-- native aiming run exactly as before. In IK mode it disables it on the old IK codebase's conditions.
input.init(false) -- true = developer mode: registers the "Input Dev Config" panel (writes data/input_parameters.json)
--
-- VR_AimMethod is 0 (Game) throughout IK mode (installArmsRouter + Entry.lua aimMethodFor). Caution: if a
-- session starts in IK mode and never runs aim method 1, the first switch to Hands mode is the first switch to
-- a non-zero aim method, which makes the backend install its ProcessViewRotation hook mid-game and can freeze
-- the game (memory uevr-processviewrotation-hook-race).
local gameState = require("stalker2.gamestate") -- same instance Entry.lua updates
uevrUtils.registerUEVRCallback("is_input_disabled", function()
	if getHandsMode() ~= HANDS_MODE_IK then return true, 1000 end
	-- IK mode: exactly the old IK codebase's (backup IK 4.5, Entry.lua) conditions - cutscene, AnimMontage
	-- (also covers its 2D cutscene screen), climbing
	if gameState.isInCutscene or gameState.isAnimMontagePlaying or gameState.isClimbing then return true, 10 end
	return nil, 0
end)

local configui = require('libs/configui')

-- IK mode ladders: tick the input "Disabled" override for the whole climb, exactly like ticking it by hand.
-- The is_input_disabled callback above alone isn't enough: setDisabled(true) also clears input.lua's
-- decoupled yaw / body offset, so on re-enable the view re-seeds from the pawn's facing. Via the callback the
-- old pre-ladder yaw survived, and after climbing DOWN (pawn turned ~180) the HMD camera didn't follow the pawn.
-- A manual tick is left alone (climbOwnsOverride only when this code set it).
-- Timing matters (MCP trace 2026-10-05, climbing down): on entry (AnimClimbState 6) the game turns the pawn +
-- control rotation to face the ladder over ~12 ticks; bAnimClimbStarted only goes true AFTER that, and input.lua
-- (which writes the HMD aim into the control rotation every tick in IK mode) got one more write in, restoring the
-- pre-ladder yaw for the whole descent. So switch off on AnimClimbState ~= 0, read every tick (gameState.isClimbing
-- is throttled to every 10 ticks).
-- AnimClimbState does NOT return to 0 after a climb (read live 2026-10-12, standing on the ground: state 3,
-- bAnimClimbStarted false), so "state ~= 0" kept the override ticked for good after the first ladder. The entry is
-- taken from the state CHANGING instead: a change while not climbing opens a short window that
-- bAnimClimbStarted then takes over; a change right after a climb ended is the exit, not a new entry.
local CLIMB_ENTRY_WINDOW_S = 3.0 -- entry turn took ~12 ticks in the trace; bAnimClimbStarted follows it
local CLIMB_EXIT_IGNORE_S  = 2.0
local climbOwnsOverride = false
local lastClimbState = nil
local climbWasStarted = false
local climbEntryUntil = 0
local climbExitedAt = -1000
local function setInputOverride(val)
	input.setDisabled(val)
	pcall(configui.setValue, "uevr_input_isDisabledOverride", val, true)
end
-- The dev panel saves its "Disabled" checkbox (data/dev/input_config_dev.json) and replays it into input.lua on
-- every script load, so a tick left behind by a session that ended mid-climb would disable input for good.
setInputOverride(false)
local function isOnLadder()
	local state, started = nil, false
	pcall(function()
		local climbingData = gameState._framePawn.Mesh.AnimScriptInstance.ClimbingData
		state = climbingData.AnimClimbState
		started = climbingData.bAnimClimbStarted == true
	end)
	local now = os.clock()
	if climbWasStarted and not started then climbExitedAt = now end
	climbWasStarted = started
	if state ~= nil then
		if lastClimbState ~= nil and state ~= lastClimbState and not started
			and now - climbExitedAt > CLIMB_EXIT_IGNORE_S then
			climbEntryUntil = now + CLIMB_ENTRY_WINDOW_S
		end
		lastClimbState = state
	end
	if started then climbEntryUntil = 0 end -- bAnimClimbStarted owns it from here
	return started or gameState.isClimbing or now < climbEntryUntil
end
uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
	local onLadder = isOnLadder() -- every tick in both modes: it tracks the state changes
	local wantDisabled = getHandsMode() == HANDS_MODE_IK and onLadder
	if wantDisabled and not climbOwnsOverride then
		if not input.isDisabledOverride() then
			setInputOverride(true)
			climbOwnsOverride = true
		end
	elseif not wantDisabled and climbOwnsOverride then
		climbOwnsOverride = false
		setInputOverride(false)
	end
end)
uevrUtils.registerPreLevelChangeCallback(function(level)
	if climbOwnsOverride then
		climbOwnsOverride = false
		setInputOverride(false)
	end
end)

local function createGloves()
	local paramsFile = 'hands_parameters' -- found in the [game profile]/data directory
	local configName = 'Main' -- the name you gave your config
	local animationName = 'Shared' -- the name you gave your animation
	hands.createFromConfig(paramsFile, configName, animationName)
end

-- Rig created: same depth/FOV treatment the glove PMCs get (Entry.lua applyForegroundFOVFixExperiment),
-- VR shadow setting, and a deferred grip-pose refresh - a fresh rig otherwise stays in the open pose
-- until the next grip/trigger edge (animation.lua's per-animID state survives the rebuild).
ik.registerOnMeshCreatedCallback(function(meshList, rig)
	for _, mesh in ipairs(meshList or {}) do
		pcall(function() uevrUtils.fixMeshFOV(mesh, "ForegroundFOVEnabled", 0.0, false, false, false) end)
		pcall(function()
			mesh.bCastDynamicShadow = Config.vrShadowsEnabled
			mesh:SetCastShadow(Config.vrShadowsEnabled)
		end)
	end
	-- the glove InitialTransform finger rest pose (the gloves get it on creation), then the grip state
	pcall(ikArms.setInitialTransform, Handed.Left)
	pcall(ikArms.setInitialTransform, Handed.Right)
	for _, ms in ipairs({300, 1200}) do
		uevrUtils.setTimeout(ms, function()
			pcall(handsAnimation.updateAnimationState, Handed.Left)
			pcall(handsAnimation.updateAnimationState, Handed.Right)
		end)
	end
	print("[HandsMode] IK rig created (" .. tostring(#(meshList or {})) .. " mesh(es)).")
end)
ik.registerOnDestroyCallback(function(rig)
	ikArms.onRigDestroyed()
end)

-- Step 3: in IK mode stalker2/ik_arms.lua takes the glove calls (see libs/hands.lua setIKDelegate), and
-- the raw accessory events reach the rig only through it (glove offsets converted).
local function installArmsRouter()
	local isIK = getHandsMode() == HANDS_MODE_IK
	hands.setIKDelegate(isIK and ikArms or nil)
	ik.setHandleAccessoryEvents(not isIK)
	-- the glove listeners route the accessory events to the rig; they must exist even if no glove was ever made
	if isIK then hands.ensureInputHandler() end
	-- IK: roomscale on as in the old IK codebase (backup IK 4.5) - input_parameters pawnPositionMode 1 = NONE,
	-- UEVR moves the pawn under the head. Movement orientation stays Game (0) in BOTH modes: in IK, input.lua
	-- already turns the pawn with the head (pawnRotationMode SIMPLE), so HMD orientation (1) applied the head
	-- yaw to movement twice (same double yaw as OW2, memory outerworlds2-movement-orientation-double-yaw).
	-- Plain per-frame settings - unlike VR_AimMethod no hook is installed.
	uevr.params.vr.set_mod_value("VR_RoomscaleMovement", isIK and "true" or "false")
	uevr.params.vr.set_mod_value("VR_MovementOrientation", "0")
	-- IK: Game aim (0) - input.lua drives aim/view; UEVR's HMD aim (1) on top breaks head turning. Entry.lua
	-- keeps it there (aimMethodFor). Hands: left to Entry.lua's normal handling (it re-asserts 1 in gameplay).
	if isIK then uevr.params.vr.set_mod_value("VR_AimMethod", "0") end
	if not isIK then
		ik.clearAccessoryTarget(Handed.Left)
		ik.clearAccessoryTarget(Handed.Right)
	end
end

-- true = dev mode: registers the IK configuration panel (writes data/ik_parameters.json).
ik.init(false, LogLevel.Warning)
ik.setAutoCreateArms(getHandsMode() == HANDS_MODE_IK)
installArmsRouter()
if getHandsMode() == HANDS_MODE_IK then
	-- before libs/hands.lua's 1 s auto-create timer can build gloves on a fresh script load
	hands.setAutoCreateHands(false)
	hands.destroyHands()
end

-- Puts the current mode into effect. Gloves and rig both register the left_arms/right_arms
-- animation IDs, so only one may exist at a time.
local function applyHandsMode()
	controllers.createController(0)
	controllers.createController(1)
	if getHandsMode() == HANDS_MODE_IK then
		hands.setAutoCreateHands(false)
		hands.destroyHands()
		installArmsRouter()
		ik.setAutoCreateArms(true) -- ik.lua's 1 s poll builds the rig
		print("[HandsMode] IK Arms")
	else
		installArmsRouter()
		ik.setAutoCreateArms(false)
		if ik.exists() then ik.destroyAll() end
		hands.setAutoCreateHands(true)
		hands.reset()
		createGloves()
		print("[HandsMode] Glove hands")
	end
	-- the new arms start on the controllers: re-run Entry's equip path to re-grip the weapon
	if _G.reattachWeaponHand ~= nil then _G.reattachWeaponHand() end
end

-- Runtime switch from the dev panel. Deferred one tick: the panel runs on the draw thread, and
-- component creation/destruction requested there can be dropped.
_G.setHandsMode = function(mode)
	Config.handsMode = (mode == HANDS_MODE_IK) and HANDS_MODE_IK or HANDS_MODE_GLOVES
	uevrUtils.setTimeout(1, applyHandsMode)
end

-- Suit swap (Entry.lua's SkeletalMesh watcher): rebuild whichever arms are active.
_G.ikRebuild = function()
	if ik.exists() then ik.destroyAll() end -- auto-create rebuilds it within ~1 s
end

function on_level_change(level)
	controllers.createController(0)
	controllers.createController(1)
	hands.reset()
	if getHandsMode() == HANDS_MODE_IK then
		hands.setAutoCreateHands(false)
		ik.setAutoCreateArms(true)
	else
		hands.setAutoCreateHands(true)
		createGloves()
	end
end

-- NOTE: on_xinput_get_state intentionally removed from this wrapper.
-- Entry.lua's createInputHandler registers the correct weapon-aware xinput
-- callback (via uevrUtils.registerOnInputGetStateCallback with allowAutoHandle=true)
-- which handles right_grip_weapon_rhino etc. correctly.
-- Having a second on_xinput_get_state here calling hands.handleInput(state, false, ...)
-- permanently set autoHandleInput=false, disabling the correct handler entirely.
