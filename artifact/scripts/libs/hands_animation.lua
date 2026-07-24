local uevrUtils = require("libs/uevr_utils")
local attachments = require("libs/attachments")
local animation = require("libs/animation")

local M = {}

local holdingAttachment = {}
local inputHandlerAnimID = {}
local activeComponents = {}
local autoHandleInput = true
local disableAnimations = false --used during hand configuration to prevent loaded animation from interfering


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
    activeComponents[component] = animID
    animation.add(animID, component, handAnimations)
	animation.initialize(animID, component)
end

function M.destroyAnimationHandler(component)
    local animID = activeComponents[component]
    if animID ~= nil then
        inputHandlerAnimID[animID] = nil
    end
end

function M.reset()
	autoHandleInput = true
    disableAnimations = false
	inputHandlerAnimID = {}
    holdingAttachment = {}
    activeComponents = {}
end

function M.exists()
    return next(inputHandlerAnimID) ~= nil
end

local createInputHandler = doOnce(function()
	attachments.registerOnGripAnimationCallback(function(gripAnimation, gripHand)
		M.print("Grip animation changed to " .. (gripAnimation and tostring(gripAnimation) or "None") .. " for " .. (gripHand == Handed.Left and "Left" or "Right") .. " hand", LogLevel.Debug)
		--print("Grip animation changed to ", gripAnimation, gripHand)
		M.updateAnimationState(gripHand)
	end)

	uevrUtils.registerOnPreInputGetStateCallback(function(retval, user_index, state)
		if autoHandleInput and M.exists() then
			-- Resolve the effective attachment for each hand: prefer the attachments
			-- system's weapon-specific animation (e.g. "rhino") over generic holding
			-- states (nil, true, "attachment_none"), so trigger presses fire
			-- right_trigger_weapon_rhino instead of the bare right_trigger.
			local function resolveAttachment(hand)
				local h = holdingAttachment[hand]
				if h == nil or h == true or h == "attachment_none" then
					local spec = attachments.getCurrentGripAnimation(hand)
					if spec ~= nil and spec ~= false and spec ~= true then
						return spec
					end
				end
				return h
			end
			local rightAttachment = resolveAttachment(Handed.Right)
			local leftAttachment = resolveAttachment(Handed.Left)
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

function M.disableAnimations(value)
	disableAnimations = value
end

function M.setHoldingAttachment(hand, val)
	holdingAttachment[hand] = val
	M.updateAnimationState(hand)
end

function M.updateAnimationState(hand)
	if M.exists() then
		local attachment = holdingAttachment[hand]
		-- For unspecified (nil), generic holding (true), or explicitly-cleared
		-- ("attachment_none") states, check whether the attachments system has a
		-- specific weapon animation configured (e.g. "rhino" selected in the UI).
		-- This lets the "Grip Animation" dropdown override all three default states.
		-- Entry.lua sets "attachment_none" on every weapon change (line 1850), so
		-- without this check the dropdown selection would never take effect.
		if attachment == nil or attachment == true or attachment == "attachment_none" then
			local specificAnim = attachments.getCurrentGripAnimation(hand)
			if specificAnim ~= nil and specificAnim ~= false and specificAnim ~= true then
				-- Specific weapon animation configured — use it.
				attachment = specificAnim
			end
			-- If no specific animation is configured, keep attachment as-is:
			--   nil              → getCurrentGripAnimation already returned nil/false → open hand
			--   true             → generic grip_right_weapon pose
			--   "attachment_none"→ open hand (intentionally cleared)
		end
		M.print("Updating animation state for " .. (hand == Handed.Left and "Left" or "Right") .. " hand with attachment: " .. (type(attachment) == "string" and attachment or tostring(attachment)), LogLevel.Debug)
		local isHoldingAttachment, attachmentExtension = getAttachmentStateAndExtension(attachment)
		M.print("Is holding attachment: " .. tostring(isHoldingAttachment), LogLevel.Debug)

		if isHoldingAttachment then
			for id, target in pairs(inputHandlerAnimID) do
				local handStr = hand == Handed.Left and "left" or "right"
				animation.resetAnimation(handStr.."_"..target, handStr.."_grip_weapon" .. attachmentExtension, true) --forces an update regardless of current state
				animation.resetAnimation(handStr.."_"..target, handStr.."_trigger_weapon" .. attachmentExtension, true) --forces an update regardless of current state
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
	for id, target in pairs(inputHandlerAnimID) do
		for hand = Handed.Left, Handed.Right do
			local handStr = hand == Handed.Right and "right" or "left"
			--do not use ternary operators like this. If right attachment is nil then it will always pick leftAttachment for Handed.Right == true
			--local attachment = hand == Handed.Right and rightAttachment or leftAttachment
			local attachment = nil
			if hand == Handed.Right then attachment = rightAttachment else attachment = leftAttachment end
			local isHoldingAttachment, attachmentExtension = getAttachmentStateAndExtension(attachment)
			--print("Handling input for " .. handStr .. " hand, attachment: " .. (type(attachment) == "string" and attachment or tostring(attachment)) .. ", isHoldingAttachment: " .. tostring(isHoldingAttachment) .. ", attachmentExtension: " .. attachmentExtension)

			if not isHoldingAttachment then
				local weaponHandTriggerValue = (hand == Handed.Right or overrideTrigger) and state.Gamepad.bRightTrigger or state.Gamepad.bLeftTrigger
				animation.updateAnimation(handStr.."_"..target, handStr.."_trigger", weaponHandTriggerValue > 100, {duration=animDuration})
				animation.updateAnimation(handStr.."_"..target, handStr.."_grip", uevrUtils.isButtonPressed(state, hand == Handed.Right and XINPUT_GAMEPAD_RIGHT_SHOULDER or XINPUT_GAMEPAD_LEFT_SHOULDER), {duration=animDuration})

				local weaponhandController = uevr.params.vr.get_right_joystick_source()
				if not (hand == Handed.Right) then weaponhandController = uevr.params.vr.get_left_joystick_source() end
				local weaponhandRest = uevr.params.vr.get_action_handle(hand == Handed.Right and "/actions/default/in/ThumbrestTouchRight" or "/actions/default/in/ThumbrestTouchLeft")
				animation.updateAnimation(handStr.."_"..target, handStr.."_thumb", uevr.params.vr.is_action_active(weaponhandRest, weaponhandController), {duration=animDuration})
			else
				local weaponHandTriggerValue = (hand == Handed.Right or overrideTrigger) and state.Gamepad.bRightTrigger or state.Gamepad.bLeftTrigger
				animation.updateAnimation(handStr.."_"..target, handStr.."_trigger_weapon" .. attachmentExtension, weaponHandTriggerValue > 100, {duration=animDuration})
				local isButtonPressed = uevrUtils.isButtonPressed(state, hand == Handed.Right and XINPUT_GAMEPAD_RIGHT_SHOULDER or XINPUT_GAMEPAD_LEFT_SHOULDER)
				animation.updateAnimation(handStr.."_"..target, handStr.."_grip_weapon" .. attachmentExtension, isButtonPressed, {duration=animDuration})
			end
		end
	end
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
	for id, target in pairs(inputHandlerAnimID) do
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
	end
end

uevrUtils.registerUEVRCallback("on_module_montage_change", function(montageObject, montageName, label, animInstance)
	if montageName == nil or montageName == "" then
		-- Only reset grip state on montage-end when the per-frame auto-input handler
		-- is NOT active. When autoHandleInput = true, the handler calls
		-- animation.updateAnimation() every tick and naturally maintains grip/trigger
		-- state. Calling animation.pose() here while autoHandleInput is true causes
		-- the trigger finger to flicker: pose() resets the trigger to "off" between
		-- every tick the auto-handler lerps it to "on" (pressed), producing a stutter.
		-- Stalker 2 fires many short montages (idle, breathing, recoil) so this
		-- callback fires very frequently and the fight is visible.
		if not autoHandleInput then
			M.updateAnimationState(Handed.Left)
			M.updateAnimationState(Handed.Right)
		end
	end
end)

uevr.params.sdk.callbacks.on_script_reset(function()
	M.reset()
end)

uevrUtils.registerPreLevelChangeCallback(function(level)
	M.reset()
end)

return M