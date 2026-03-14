require("Config.CONFIG")
local MotionControllerGestures = require("gestures.motioncontrollergestures")
local gameState = require("stalker2.gamestate")  -- cached at module level (perf: avoids per-tick lookup)

-- XInputState class to manage controller state
GamepadState = {
    -- State properties
    gamepadState = nil,
    leftGripAction = nil,
    rightGripAction = nil
}

-- Constructor
function GamepadState:new()
    local instance = {}
    setmetatable(instance, self)
    self.__index = self
    instance.leftGripAction = MotionControllerGestures.LeftGripAction
    instance.rightGripAction = MotionControllerGestures.RightGripAction
    return instance
end

function GamepadState:UpdateLH(state)
    if self.leftGripAction:IsLocked() then
        self:unpressButton(XINPUT_GAMEPAD_LEFT_SHOULDER)
    end
    if self.rightGripAction:IsLocked() then
        self:unpressButton(XINPUT_GAMEPAD_RIGHT_SHOULDER)
    end
    local LTrigger= state.Gamepad.bLeftTrigger
	local RTrigger= state.Gamepad.bRightTrigger
	local rShoulder = self:isButtonPressed(XINPUT_GAMEPAD_RIGHT_SHOULDER)
	local lShoulder = self:isButtonPressed(XINPUT_GAMEPAD_LEFT_SHOULDER)
    -- Left hand dominant: Left grip is ADS. When Interactive ADS is on, proximity alone determines ADS.
    if Config.interactiveADS then
        -- Distance-only: grip not needed
        self:setLeftTrigger(_G.weaponNearHMD and 255 or 0)
    else
        -- Normal mode: grip required
        if lShoulder and _G.weaponNearHMD then
            self:setLeftTrigger(255)
        else
            self:setLeftTrigger(0)
        end
    end
    self:unpressButton(XINPUT_GAMEPAD_RIGHT_SHOULDER)
    if RTrigger > 125 then
        self:pressButton(XINPUT_GAMEPAD_LEFT_SHOULDER)
    else
        self:unpressButton(XINPUT_GAMEPAD_LEFT_SHOULDER)
    end
    self:setRightTrigger(LTrigger)
end

function GamepadState:UpdateRH(state)
    if self.leftGripAction:IsLocked() then
        self:unpressButton(XINPUT_GAMEPAD_LEFT_SHOULDER)
    end
    if self.rightGripAction:IsLocked() then
        self:unpressButton(XINPUT_GAMEPAD_RIGHT_SHOULDER)
    end
    local LTrigger= state.Gamepad.bLeftTrigger
	local rShoulder = self:isButtonPressed(XINPUT_GAMEPAD_RIGHT_SHOULDER)
    -- Right hand dominant: Right grip is ADS. When Interactive ADS is on, proximity alone determines ADS.
    if Config.interactiveADS then
        -- Distance-only: grip not needed
        self:setLeftTrigger(_G.weaponNearHMD and 255 or 0)
    else
        -- Normal mode: grip required
        if rShoulder and _G.weaponNearHMD then
            self:setLeftTrigger(255)
        else
            self:setLeftTrigger(0)
        end
    end
    self:unpressButton(XINPUT_GAMEPAD_RIGHT_SHOULDER)
    if LTrigger > 125 then
        self:pressButton(XINPUT_GAMEPAD_LEFT_SHOULDER)
    else
        self:unpressButton(XINPUT_GAMEPAD_LEFT_SHOULDER)
    end
end

-- Conversation-mode button mapping:
-- Left grip  → LB  (dialogue navigation / choice A)
-- Right grip → RB  (raw pass-through, dialogue choice B / skip)
-- Left trigger → LT (raw, not remapped to LB like normal gameplay)
-- Right trigger → RT (raw)
function GamepadState:UpdateConversation(state)
    -- Left grip (LEFT_SHOULDER) → explicitly mapped to LB.
    -- In normal gameplay UpdateRH overwrites LEFT_SHOULDER with the left trigger value,
    -- which erases the physical left grip signal. We restore the intended mapping here.
    if self.leftGripAction:IsLocked() then
        self:unpressButton(XINPUT_GAMEPAD_LEFT_SHOULDER)
    else
        local lShoulder = self:isButtonPressed(XINPUT_GAMEPAD_LEFT_SHOULDER)
        if lShoulder then
            self:pressButton(XINPUT_GAMEPAD_LEFT_SHOULDER)
        else
            self:unpressButton(XINPUT_GAMEPAD_LEFT_SHOULDER)
        end
    end
    -- Right grip (RIGHT_SHOULDER) left completely untouched → stays as raw RB.
    -- Left trigger and right trigger are also untouched → stay as raw LT / RT.
end

-- Update state from XInput
function GamepadState:Update(state)
    self.gamepadState = state
    -- Full raw pass-through during AnimMontage cutscenes (binary dialogue choices etc.)
    if gameState.isAnimMontagePlaying then
        return
    end
    -- Conversation-specific mapping: left grip → LB, everything else raw
    if gameState.isConversation then
        self:UpdateConversation(state)
        return
    end
    if Config.dominantHand == 1 then
        self:UpdateRH(state)
    else
        self:UpdateLH(state)
    end
end

-- Reset key state variables (does not modify gamepad state)
function GamepadState:Reset()
    self.gamepadState = nil
end

function GamepadState:isButtonPressed(button)
    if not self.gamepadState then
        return false
    end
    return self.gamepadState.Gamepad.wButtons & button ~= 0
end

function GamepadState:isButtonNotPressed(button)
    if not self.gamepadState then
        return false
    end
    return self.gamepadState.Gamepad.wButtons & button == 0
end

function GamepadState:pressButton(button)
    if self.gamepadState then
        self.gamepadState.Gamepad.wButtons = self.gamepadState.Gamepad.wButtons | button
    end
end

function GamepadState:unpressButton(button)
    if self.gamepadState then
        self.gamepadState.Gamepad.wButtons = self.gamepadState.Gamepad.wButtons & ~(button)
    end
end

function GamepadState:setThumbLX(value)
    if self.gamepadState then
        self.gamepadState.Gamepad.sThumbLX = value
    end
end

function GamepadState:setThumbLY(value)
    if self.gamepadState then
        self.gamepadState.Gamepad.sThumbLY = value
    end
end

function GamepadState:setThumbRX(value)
    if self.gamepadState then
        self.gamepadState.Gamepad.sThumbRX = value
    end
end

function GamepadState:setThumbRY(value)
    if self.gamepadState then
        self.gamepadState.Gamepad.sThumbRY = value
    end
end

function GamepadState:setLeftTrigger(value)
    if self.gamepadState then
        self.gamepadState.Gamepad.bLeftTrigger = value
    end
end

function GamepadState:setRightTrigger(value)
    if self.gamepadState then
        self.gamepadState.Gamepad.bRightTrigger = value
    end
end

local gamepadState = GamepadState:new()

return gamepadState
