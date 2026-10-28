local uevrUtils = require("libs/uevr_utils")
local attachments = require("libs/attachments")
local animation = require("libs/animation")

local M = {}

local holdingAttachment = {}
local inputHandlerAnimID = {}
local activeComponents = {}
local autoHandleInput = true
local disableAnimations = false --used during hand configuration to prevent loaded animation from interfering
local inputLocked = {} -- per-hand lock for the input-driven lerps, see M.setInputLocked
local heldInput = {} -- per-hand {grip, trigger, thumb} last seen by handleInputForHands (non-holding hands only)
local thumbLerpSuppressed = {} -- per-hand, see M.setThumbLerpSuppressed


local currentLogLevel = LogLevel.Error
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
	if logLevel == nil then logLevel = LogLevel.Debug end
	if logLevel <= currentLogLevel then
		uevrUtils.print("[hands_animation] " .. text, logLevel)
	end
end

local function getAnimIDSuffix(animID)
	local arr = uevrUtils.splitStr(animID, "_")
	return #arr > 0 and arr[#arr] or nil
end


-- This needs to be called externally
function M.createAnimationHandler(animID, component, handAnimations)
    if component == nil then
        M.print("No component provided for animation handler creation for animID: " .. tostring(animID), LogLevel.Error)
        return
    end
    local suffix = getAnimIDSuffix(animID)
    if suffix ~= nil then inputHandlerAnimID[animID] = suffix end
    -- A component can carry several animIDs: the IK rig registers left_arms AND right_arms on its one
    -- arms mesh. Keep a list so destroyAnimationHandler releases all of them (a single slot let the
    -- second registration overwrite the first). (Stalker 2 port, 2026-10-04.)
    if component ~= nil then
        local ids = activeComponents[component] or {}
        ids[#ids + 1] = animID
        activeComponents[component] = ids
    end
    animation.add(animID, component, handAnimations)
	animation.initialize(animID, component)
end

function M.destroyAnimationHandler(component)
    if component == nil then return end
    local ids = activeComponents[component]
    if ids ~= nil then
        for _, animID in ipairs(ids) do
            inputHandlerAnimID[animID] = nil
            animation.detachComponent(animID) -- drop the dead component + cancel its running lerps
        end
        activeComponents[component] = nil
    end
end

function M.reset()
	autoHandleInput = true
    disableAnimations = false
	inputLocked = {}
	thumbLerpSuppressed = {}
	inputHandlerAnimID = {}
    holdingAttachment = {}
    activeComponents = {}
end

function M.exists()
    return next(inputHandlerAnimID) ~= nil
end

local function forEachUniqueTarget(callback)
	local handledTargets = {}
	for _, target in pairs(inputHandlerAnimID) do
		if target ~= nil and not handledTargets[target] then
			handledTargets[target] = true
			callback(target)
		end
	end
end

local createInputHandler = doOnce(function()
	attachments.registerOnGripAnimationCallback(function(gripAnimation, gripHand)
		M.print("Grip animation changed to " .. (gripAnimation and tostring(gripAnimation) or "None") .. " for " .. (gripHand == Handed.Left and "Left" or "Right") .. " hand", LogLevel.Debug)
		--print("Grip animation changed to ", gripAnimation, gripHand)
		M.updateAnimationState(gripHand)
	end)

	uevrUtils.registerOnPreInputGetStateCallback(function(retval, user_index, state)
		-- Only the real pad. XInputGetState is polled for pad slots 0..3; the other slots carry no
		-- controller (and on some backends stale/garbage button data), and every extra call re-drove the
		-- grip/trigger animations with a different state each frame (lerps restarted at alpha 1.0 every
		-- frame -> weapon poses stuck "on").
		if user_index ~= 0 then return end
		if autoHandleInput and M.exists() then
			local rightAttachment = holdingAttachment[Handed.Right] or attachments.getCurrentGripAnimation(Handed.Right)
			local leftAttachment = holdingAttachment[Handed.Left] or attachments.getCurrentGripAnimation(Handed.Left)
			--M.handleInput(state, attachment, Handed.Right, nil, true)
			M.handleInputForHands(state, rightAttachment, leftAttachment, nil, true)
		end
	end, 10) --high priority to intercept messages before possible remapper
end, Once.EVER)
createInputHandler()

local function getAttachmentStateAndExtension(attachment)
	local isHoldingAttachment = false
	local attachmentExtension = ""
	if type(attachment) == "boolean" then
		isHoldingAttachment = attachment
	elseif type(attachment) == "string" and attachment ~= "attachment_none" then
		isHoldingAttachment = true
		if attachment ~= "" then
			attachmentExtension = "_" .. attachment
		end
	end
	return isHoldingAttachment, attachmentExtension
end

function M.setAutoHandleInput(val)
	autoHandleInput = val
end

-- Per-hand lock for the input-driven grip/trigger/thumb lerps. two_handed.lua locks the LEFT hand while
-- it is two-handing: the left trigger is the grab button there, so the handler would otherwise keep the
-- left weapon-trigger pose curled for the whole grab. The hand keeps whatever pose was last applied
-- (updateAnimationState / setHoldingAttachment still work while locked).
function M.setInputLocked(hand, locked)
	inputLocked[hand] = locked and true or nil
end
function M.isInputLocked(hand)
	return inputLocked[hand] == true
end

function M.disableAnimations(value)
	disableAnimations = value
end

-- skipUpdate: only record it, like the glove hands.setHoldingAttachment (Stalker 2's Entry.lua sets the
-- state and refreshes separately, sometimes with a pose applied in between).
function M.setHoldingAttachment(hand, val, skipUpdate)
	holdingAttachment[hand] = val
	if skipUpdate ~= true then
		M.updateAnimationState(hand)
	end
end

-- Stalker 2: while Entry.lua's thumb pose owns a hand (two-handing, mag grip) the thumbrest-touch lerp
-- must not stomp thumb_01..03. Same switch as the glove hands.setThumbLerpSuppressed.
function M.setThumbLerpSuppressed(hand, suppressed)
	thumbLerpSuppressed[hand] = suppressed == true or nil
end

function M.updateAnimationState(hand)
	if M.exists() then
		local attachment = holdingAttachment[hand]
		if attachment == nil then
			attachment = attachments.getCurrentGripAnimation(hand)
		end
		M.print("Updating animation state for " .. (hand == Handed.Left and "Left" or "Right") .. " hand with attachment: " .. (type(attachment) == "string" and attachment or tostring(attachment)), LogLevel.Debug)
		local isHoldingAttachment, attachmentExtension = getAttachmentStateAndExtension(attachment)
		M.print("Is holding attachment: " .. tostring(isHoldingAttachment), LogLevel.Debug)

		if isHoldingAttachment then
			forEachUniqueTarget(function(target)
				local handStr = hand == Handed.Left and "left" or "right"
				animation.resetAnimation(handStr.."_"..target, handStr.."_grip_weapon" .. attachmentExtension, true) --forces an update regardless of current state
				animation.resetAnimation(handStr.."_"..target, handStr.."_trigger_weapon" .. attachmentExtension, true) --forces an update regardless of current state
				animation.pose(handStr .. "_" .. target, "grip_" .. handStr .. "_weapon" .. attachmentExtension)
			end)
		else
			forEachUniqueTarget(function(target)
				local handStr = hand == Handed.Left and "left" or "right"
				local animID = handStr .. "_" .. target
				animation.pose(animID, "open_" .. handStr)
				-- the open pose turns grip/trigger/thumb off, but their input states still say "pressed", so a button
				-- held through this refresh (OW2 fires it ~250 ms after LB/LT reach the game) left the hand open until
				-- re-pressed. Re-apply whatever is still held in the same tick (no lerp, so the open pose never renders)
				-- and keep the input states in sync with what is shown.
				local held = heldInput[hand] or {}
				for _, part in ipairs({"grip", "trigger", "thumb"}) do
					local animName = handStr .. "_" .. part
					if held[part] then animation.animate(animID, animName, "on") end
					animation.resetAnimation(animID, animName, held[part] == true)
				end
			end)
		end
	end
end
M.updateAnimationState = uevrUtils.profiler:wrap("Hand Animations: updateAnimationState", M.updateAnimationState)

function M.handleInputForHands(state, rightAttachment, leftAttachment, overrideTrigger, allowAutoHandle)
	if allowAutoHandle ~= true then
		autoHandleInput = false --if something else is calling this then dont auto handle input
	end
	if disableAnimations then
		--print("Animations are disabled, skipping handleInputForHands")
		return true
	end

	if overrideTrigger == nil then overrideTrigger = false end
	local animDuration = 0.1
	forEachUniqueTarget(function(target)
		for hand = Handed.Left, Handed.Right do
			local handStr = hand == Handed.Right and "right" or "left"
			if inputLocked[hand] then goto next_hand end
			--do not use ternary operators like this. If right attachment is nil then it will always pick leftAttachment for Handed.Right == true
			--local attachment = hand == Handed.Right and rightAttachment or leftAttachment
			local attachment = nil
			if hand == Handed.Right then attachment = rightAttachment else attachment = leftAttachment end
			local isHoldingAttachment, attachmentExtension = getAttachmentStateAndExtension(attachment)
			--print("Handling input for " .. handStr .. " hand, attachment: " .. (type(attachment) == "string" and attachment or tostring(attachment)) .. ", isHoldingAttachment: " .. tostring(isHoldingAttachment) .. ", attachmentExtension: " .. attachmentExtension)

			if not isHoldingAttachment then
				local weaponHandTriggerValue = (hand == Handed.Right or overrideTrigger) and state.Gamepad.bRightTrigger or state.Gamepad.bLeftTrigger
				local triggerDown = weaponHandTriggerValue > 100
				local gripDown = uevrUtils.isButtonPressed(state, hand == Handed.Right and XINPUT_GAMEPAD_RIGHT_SHOULDER or XINPUT_GAMEPAD_LEFT_SHOULDER)
				animation.updateAnimation(handStr.."_"..target, handStr.."_trigger", triggerDown, {duration=animDuration})
				animation.updateAnimation(handStr.."_"..target, handStr.."_grip", gripDown, {duration=animDuration})

				local weaponhandController = uevr.params.vr.get_right_joystick_source()
				if not (hand == Handed.Right) then weaponhandController = uevr.params.vr.get_left_joystick_source() end
				local weaponhandRest = uevr.params.vr.get_action_handle(hand == Handed.Right and "/actions/default/in/ThumbrestTouchRight" or "/actions/default/in/ThumbrestTouchLeft")
				local thumbDown = uevr.params.vr.is_action_active(weaponhandRest, weaponhandController)
				if not thumbLerpSuppressed[hand] then
					animation.updateAnimation(handStr.."_"..target, handStr.."_thumb", thumbDown, {duration=animDuration})
				end
				heldInput[hand] = {grip = gripDown, trigger = triggerDown, thumb = thumbDown == true}
			else
				local weaponHandTriggerValue = (hand == Handed.Right or overrideTrigger) and state.Gamepad.bRightTrigger or state.Gamepad.bLeftTrigger
				animation.updateAnimation(handStr.."_"..target, handStr.."_trigger_weapon" .. attachmentExtension, weaponHandTriggerValue > 100, {duration=animDuration})
				local isButtonPressed = uevrUtils.isButtonPressed(state, hand == Handed.Right and XINPUT_GAMEPAD_RIGHT_SHOULDER or XINPUT_GAMEPAD_LEFT_SHOULDER)
				animation.updateAnimation(handStr.."_"..target, handStr.."_grip_weapon" .. attachmentExtension, isButtonPressed, {duration=animDuration})
			end
			::next_hand::
		end
	end)
end

--deprecated
function M.handleInput(state, attachment, hand, overrideTrigger, allowAutoHandle)
	if allowAutoHandle ~= true then
		autoHandleInput = false --if something else is calling this then dont auto handle input
	end
	if disableAnimations then
		--print("Animations are disabled, skipping handleInput")
		return true
	end

	local isHoldingAttachment, attachmentExtension = getAttachmentStateAndExtension(attachment)

	if hand == nil then hand = Handed.Right end
	if overrideTrigger == nil then overrideTrigger = false end
	local isRightHanded = hand == Handed.Right
	local weaponHandStr = isRightHanded and "right" or "left"
	local offHandStr = isRightHanded and "left" or "right"
	local animDuration = 0.1
	forEachUniqueTarget(function(target)
		local offhandTriggerValue = (isRightHanded or overrideTrigger) and state.Gamepad.bLeftTrigger or state.Gamepad.bRightTrigger
		animation.updateAnimation(offHandStr.."_"..target, offHandStr.."_trigger", offhandTriggerValue > 100, {duration=animDuration})

		animation.updateAnimation(offHandStr.."_"..target, offHandStr.."_grip", uevrUtils.isButtonPressed(state, isRightHanded and XINPUT_GAMEPAD_LEFT_SHOULDER or XINPUT_GAMEPAD_RIGHT_SHOULDER), {duration=animDuration})

		local offhandController = uevr.params.vr.get_left_joystick_source()
		if not isRightHanded then offhandController = uevr.params.vr.get_right_joystick_source() end
		local offhandRest = uevr.params.vr.get_action_handle(isRightHanded and "/actions/default/in/ThumbrestTouchLeft" or "/actions/default/in/ThumbrestTouchRight")
		animation.updateAnimation(offHandStr.."_"..target, offHandStr.."_thumb", uevr.params.vr.is_action_active(offhandRest, offhandController), {duration=animDuration})

		if not isHoldingAttachment then
			local weaponHandTriggerValue = (isRightHanded or overrideTrigger) and state.Gamepad.bRightTrigger or state.Gamepad.bLeftTrigger
			animation.updateAnimation(weaponHandStr.."_"..target, weaponHandStr.."_trigger", weaponHandTriggerValue > 100, {duration=animDuration})

			animation.updateAnimation(weaponHandStr.."_"..target, weaponHandStr.."_grip", uevrUtils.isButtonPressed(state, isRightHanded and XINPUT_GAMEPAD_RIGHT_SHOULDER or XINPUT_GAMEPAD_LEFT_SHOULDER), {duration=animDuration})

			local weaponhandController = uevr.params.vr.get_right_joystick_source()
			if not isRightHanded then weaponhandController = uevr.params.vr.get_left_joystick_source() end
			local weaponhandRest = uevr.params.vr.get_action_handle(isRightHanded and "/actions/default/in/ThumbrestTouchRight" or "/actions/default/in/ThumbrestTouchLeft")
			animation.updateAnimation(weaponHandStr.."_"..target, weaponHandStr.."_thumb", uevr.params.vr.is_action_active(weaponhandRest, weaponhandController), {duration=animDuration})
		else
			local weaponHandTriggerValue = (isRightHanded or overrideTrigger) and state.Gamepad.bRightTrigger or state.Gamepad.bLeftTrigger
			animation.updateAnimation(weaponHandStr.."_"..target, weaponHandStr.."_trigger_weapon" .. attachmentExtension, weaponHandTriggerValue > 100, {duration=animDuration})
			if uevrUtils.isButtonPressed(state, isRightHanded and XINPUT_GAMEPAD_RIGHT_SHOULDER or XINPUT_GAMEPAD_LEFT_SHOULDER) then
				animation.resetAnimation(weaponHandStr.."_"..target, weaponHandStr.."_grip_weapon" .. attachmentExtension, false) --forces an update regardless of current state
--print("Here",weaponHandStr.."_"..target,weaponHandStr.."_grip_weapon" .. attachmentExtension)
				animation.updateAnimation(weaponHandStr.."_"..target, weaponHandStr.."_grip_weapon" .. attachmentExtension, true, {duration=animDuration})
			end
		end
	end)
end

uevrUtils.registerUEVRCallback("on_module_montage_change", function(montageObject, montageName, label, animInstance)
	if montageName == nil or montageName == "" then
		M.updateAnimationState(Handed.Left)
		M.updateAnimationState(Handed.Right)
	end
end)

uevr.params.sdk.callbacks.on_script_reset(function()
	M.reset()
end)

uevrUtils.registerPreLevelChangeCallback(function(level)
	M.reset()
end)

return M