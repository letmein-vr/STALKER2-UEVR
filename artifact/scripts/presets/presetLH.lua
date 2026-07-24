--[[
    GesturePresetsLH.lua
    Left-handed gesture presets using the GripGesture base class
]]--

require("Config.CONFIG")
local GripGesture = require("stalker2.gripgesture")
local TwoHandedAimGesture = require("stalker2.twohandedaim")

local BodyZonesSitting = require("gestures.bodyzonesitting")
local BodyZonesStanding =  require("gestures.bodyzone")
local WeaponZones = require("gestures.weaponzones")
local motionControllers = require("gestures.motioncontrollergestures")
local gameState = require("stalker2.gamestate")
local GestureSet = require("gestures.gestureset")
local uevrUtils = require("libs/uevr_utils")
local function createKeyPresExecutionCB(key, gesture_config_key)
    return function(gesture, context)
        if gesture_config_key and not Config.gestures[gesture_config_key] then
            return
        end
        if gesture:JustActivated() then
            gameState:SendKeyDown(key)
            gesture.gripGesture:Lock()
        elseif gesture:JustDeactivated() then
            gameState:SendKeyUp(key)
            gesture.gripGesture:Unlock()
        end
    end
end

local function createKeyHoldExecutionCB(key, hold_duration, gesture_config_key)
    return function(gesture, context)
        if gesture_config_key and not Config.gestures[gesture_config_key] then
            return
        end
        if gesture:JustActivated() then
            gameState:SendKeyDown(key)
            gesture.gripGesture:Lock()
            -- Auto-release after duration if it's a simulated long press
            if hold_duration and hold_duration > 0 then
                uevrUtils.setTimeout(hold_duration, function()
                    gameState:SendKeyUp(key)
                    gesture.gripGesture:Unlock()
                end)
            end
        elseif gesture:JustDeactivated() then
            if not hold_duration or hold_duration == 0 then
                gameState:SendKeyUp(key)
                gesture.gripGesture:Unlock()
            end
        end
    end
end

local function twoHandedAimingCB(gesture, context)
    if gesture:JustActivated() then
        TwoHandedStateActive = true
        gameState.isTwoHanding = true
        gesture.rightGripGesture:Lock()
    elseif gesture:JustDeactivated() then
        TwoHandedStateActive = false
        gameState.isTwoHanding = false
        gesture.rightGripGesture:Unlock()
    end
end

local function createPreset(bodyZones, weaponZones, sittingExperience)
    -- Create left-hand gesture instances
    local nightVisionGestureLH = GripGesture:new({
        name = "Night Vision Gesture (LH)",
        gripGesture = motionControllers.LeftGripAction,
        zone = bodyZones.headZoneLH
    })

    local flashlightGestureRH = GripGesture:new({
        name = "Flashlight Gesture (RH)",
        gripGesture = motionControllers.RightGripAction,
        zone = bodyZones.headZoneRH
    })

    local primaryWeaponGestureLH = GripGesture:new({
        name = "Primary Weapon Gesture (LH)",
        gripGesture = motionControllers.LeftGripAction,
        zone = bodyZones.leftShoulderZoneLH
    })

    local secondaryWeaponGestureLH = GripGesture:new({
        name = "Secondary Weapon Gesture (LH)",
        gripGesture = motionControllers.LeftGripAction,
        zone = bodyZones.rightShoulderZoneLH  -- Left hand on right shoulder
    })

    local sidearmWeaponGestureLH = GripGesture:new({
        name = "Sidearm Weapon Gesture (LH)",
        gripGesture = motionControllers.LeftGripAction,
        zone = bodyZones.leftHipZoneLH
    })

    local meleeWeaponGestureRH = GripGesture:new({
        name = "Melee Weapon Gesture (LH)",
        gripGesture = motionControllers.RightGripAction,
        zone = bodyZones.rightHipZoneRH
    })

    local boltActionGestureLH = GripGesture:new({
        name = "Bolt Action Gesture (LH)",
        gripGesture = motionControllers.LeftGripAction,
        zone = bodyZones.leftChestZoneLH
    })

    local grenadeGestureRH = GripGesture:new({
        name = "Grenade Gesture (RH)",
        gripGesture = motionControllers.RightGripAction,
        zone = bodyZones.rightChestZoneRH
    })

    local inventoryGestureRH = GripGesture:new({
        name = "Inventory Gesture (RH)",
        gripGesture = motionControllers.RightGripAction,
        zone = bodyZones.leftShoulderZoneRH
    })

    local dpadLeftGestureRH = GripGesture:new({
        name = "D-Pad Left Gesture (RH)",
        gripGesture = motionControllers.RightGripAction,
        zone = bodyZones.rightShoulderZoneRH
    })

    local scannerGestureRH = GripGesture:new({
        name = "Scanner Gesture (RH)",
        gripGesture = motionControllers.RightGripAction,
        zone = bodyZones.leftChestZoneRH
    })

    local pdaGestureLH = GripGesture:new({
        name = "PDA Gesture (LH)",
        gripGesture = motionControllers.LeftGripAction,
        zone = bodyZones.rightChestZoneLH
    })

    local reloadGestureLH = GripGesture:new({
        name = "Reload Gesture (LH)",
        gripGesture = motionControllers.RightGripAction,
        zone = weaponZones.reloadZoneLH
    })

    local modeSwitchZoneLH = GripGesture:new({
        name = "Mode Switch Gesture (LH)",
        gripGesture = motionControllers.RightGripAction,
        zone = weaponZones.modeSwitchZoneLH
    })

    local twoHandedAimGestureLH = TwoHandedAimGesture:new({
        name = "Two-Handed Aim Gesture (LH)",
        leftGripGesture = motionControllers.LeftGripAction,
        rightGripGesture = motionControllers.RightGripAction,
        zone = weaponZones.barrelZoneLH
    })

    nightVisionGestureLH:SetExecutionCallback(createKeyHoldExecutionCB('L', 1000, 'nightVision'))
    flashlightGestureRH:SetExecutionCallback(createKeyPresExecutionCB('L', 'flashlight'))
    primaryWeaponGestureLH:SetExecutionCallback(createKeyPresExecutionCB('3', 'primaryWeapon'))
    secondaryWeaponGestureLH:SetExecutionCallback(createKeyPresExecutionCB('4', 'secondaryWeapon'))
    sidearmWeaponGestureLH:SetExecutionCallback(createKeyPresExecutionCB('2', 'sidearmWeapon'))
    meleeWeaponGestureRH:SetExecutionCallback(createKeyPresExecutionCB('1', 'meleeWeapon'))
    boltActionGestureLH:SetExecutionCallback(createKeyPresExecutionCB('6', 'boltAction'))
    grenadeGestureRH:SetExecutionCallback(createKeyPresExecutionCB('5', 'grenade'))

    inventoryGestureRH:SetExecutionCallback(createKeyPresExecutionCB('I', 'inventory'))
    -- dpadLeftGestureRH:SetExecutionCallback(createKeyPresExecutionCB('D'))
    scannerGestureRH:SetExecutionCallback(createKeyPresExecutionCB('7', 'scanner'))
    pdaGestureLH:SetExecutionCallback(createKeyPresExecutionCB('M', 'pda'))
    reloadGestureLH:SetExecutionCallback(createKeyPresExecutionCB('R', 'reload'))
    modeSwitchZoneLH:SetExecutionCallback(createKeyPresExecutionCB('B', 'modeSwitch'))

    twoHandedAimGestureLH:SetExecutionCallback(twoHandedAimingCB)

    if sittingExperience then
        return GestureSet:new({
            rootGestures = {
                twoHandedAimGestureLH,
                nightVisionGestureLH,
                flashlightGestureRH,
                primaryWeaponGestureLH,
                secondaryWeaponGestureLH,
                sidearmWeaponGestureLH,
                meleeWeaponGestureRH,
                boltActionGestureLH,
                grenadeGestureRH,
                inventoryGestureRH,
                scannerGestureRH,
                pdaGestureLH,
                reloadGestureLH,
                modeSwitchZoneLH
            }
        })
    else
        return GestureSet:new({
            rootGestures = {
                twoHandedAimGestureLH,
                nightVisionGestureLH,
                flashlightGestureRH,
                primaryWeaponGestureLH,
                secondaryWeaponGestureLH,
                sidearmWeaponGestureLH,
                meleeWeaponGestureRH,
                boltActionGestureLH,
                grenadeGestureRH,
                inventoryGestureRH,
                scannerGestureRH,
                pdaGestureLH,
                reloadGestureLH,
                modeSwitchZoneLH
            }
        })
    end
end

local SitModeSetLH = createPreset(BodyZonesSitting, WeaponZones, true)
local StandModeSetLH = createPreset(BodyZonesStanding, WeaponZones, false)

return {
    SitModeSetLH = SitModeSetLH,
    StandModeSetLH = StandModeSetLH
}
