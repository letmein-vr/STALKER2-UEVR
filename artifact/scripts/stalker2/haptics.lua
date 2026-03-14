require("Config.CONFIG")
local BodyZonesSitting = require("gestures.bodyzonesitting")
local BodyZonesStanding = require("gestures.bodyzone")
local WeaponZones = require("gestures.weaponzones")

local function HapticLeftCB(gesture, context)
    if gesture:JustActivated() then
        local leftController = uevr.params.vr.get_left_joystick_source()
        uevr.params.vr.trigger_haptic_vibration(0.0, 0.1, 1.0, 100.0, leftController)
    end
    -- if gesture.isActive then
    --     local location = gesture.locationGesture.location
    --     print("[BodyZones] " .. gesture.name .. " is active [" .. location.x .. ", " .. location.y .. ", " .. location.z .. "]")
    -- end
end


local function HapticRightCB(gesture, context)
    if gesture:JustActivated() then
        local rightController = uevr.params.vr.get_right_joystick_source()
        uevr.params.vr.trigger_haptic_vibration(0.0, 0.1, 1.0, 100.0, rightController)
    end
    -- if gesture.isActive then
    --     local location = gesture.locationGesture.location
    --     print("[BodyZones] " .. gesture.name .. " is active [" .. location.x .. ", " .. location.y .. ", " .. location.z .. "]")
    -- end
end


local function toggleHaptic(bodyZones, weaponZones, enabled)
    local hapticFeedbackLH = enabled and HapticLeftCB or nil
    local hapticFeedbackRH = enabled and HapticRightCB or nil
    bodyZones.headZoneLH:SetExecutionCallback(hapticFeedbackLH)
    bodyZones.leftShoulderZoneLH:SetExecutionCallback(hapticFeedbackLH)
    bodyZones.rightShoulderZoneLH:SetExecutionCallback(hapticFeedbackLH)
    bodyZones.rightHipZoneLH:SetExecutionCallback(hapticFeedbackLH)
    bodyZones.leftHipZoneLH:SetExecutionCallback(hapticFeedbackLH)
    bodyZones.leftChestZoneLH:SetExecutionCallback(hapticFeedbackLH)
    bodyZones.rightChestZoneLH:SetExecutionCallback(hapticFeedbackLH)
    weaponZones.reloadZoneLH:SetExecutionCallback(hapticFeedbackLH)
    weaponZones.modeSwitchZoneLH:SetExecutionCallback(hapticFeedbackLH)

    bodyZones.headZoneRH:SetExecutionCallback(hapticFeedbackRH)
    bodyZones.leftShoulderZoneRH:SetExecutionCallback(hapticFeedbackRH)
    bodyZones.rightShoulderZoneRH:SetExecutionCallback(hapticFeedbackRH)
    bodyZones.rightHipZoneRH:SetExecutionCallback(hapticFeedbackRH)
    bodyZones.leftHipZoneRH:SetExecutionCallback(hapticFeedbackRH)
    bodyZones.leftChestZoneRH:SetExecutionCallback(hapticFeedbackRH)
    bodyZones.rightChestZoneRH:SetExecutionCallback(hapticFeedbackRH)
    weaponZones.reloadZoneRH:SetExecutionCallback(hapticFeedbackRH)
    weaponZones.modeSwitchZoneRH:SetExecutionCallback(hapticFeedbackRH)
end

local function updateHapticFeedback(enabled)
    toggleHaptic(BodyZonesSitting, WeaponZones, enabled)
    toggleHaptic(BodyZonesStanding, WeaponZones, enabled)
end

updateHapticFeedback(Config.hapticFeedback)

return {
    updateHapticFeedback = updateHapticFeedback
}

