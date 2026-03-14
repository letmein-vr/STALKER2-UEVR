local uevrUtils = require("libs/uevr_utils")
local pawnModule = require("libs/pawn")
local hands = require("libs/hands")

local M = {}

-- State tracking
local isWildcardMontageActive = false
local wildcardPriority = 100 -- Higher priority to override libs/montage.lua and other defaults

-- List of specific montages to include in this logic
local specificMontages = {
    ["AM_fp_topaz_in"] = true,
    ["MG_fp_int_notebook"] = true,
    ["AM_fp_topaz_out"] = true,
    ["MG_fp_dead_body_pickup"] = true,
    ["MG_fp_BedOnBed"] = true,
    ["MG_fp_common_burer_attack_drag_weapon"] = true,
    -- Included: specific interactive animations
    ["MG_fp_que_azimut_repeater"] = true,
    ["MG_fp_injector_wounded_heal"] = true,
    ["MG_fp_psy_locator_use"] = true,
}

-- Helper to check if name contains "AnimMontage" or is in the specific list
local function checkWildcard(montageName)
    if not montageName then return false end
    
    -- Check specific list
    if specificMontages[montageName] then
        return true
    end

    -- Check wildcard pattern
    if string.find(montageName, "AnimMontage") or string.find(montageName, "radio") then
        return true
    end

    -- Interaction animations (stashes, keycards, etc.)
    if string.find(montageName, "MG_fp_bh_") then
        -- Exceptions for standard weapon transitions, movement/utility animations, and crouching idles
        if montageName == "MG_fp_bh_equip" or montageName == "MG_fp_bh_unequip" 
           or montageName == "MG_fp_bh_flashlight" or montageName == "MG_fp_bh_jump" 
           or montageName == "MG_fp_bh_jump_end" or montageName == "MG_fp_bh_safe_idle"
           or string.find(montageName, "lowcrouch") then
            return false
        end
        return true
    end

    -- Inclusion for dialogue montages
    if string.lower(montageName):find("dialogue") then
        return true
    end
    
    return false
end

local gameState = require("stalker2.gamestate")

-- 1. Track Montage Changes
uevrUtils.registerMontageChangeCallback(function(montage, montageName)
    local wasActive = isWildcardMontageActive
    isWildcardMontageActive = checkWildcard(montageName)
    gameState.isWildcardMontageActive = isWildcardMontageActive
    
    -- Case-insensitive check for AnimMontage
    local isAnim = (montageName ~= nil and string.find(string.lower(montageName), "animmontage") ~= nil)
    gameState.isAnimMontagePlaying = isAnim
    
    if montageName then
        print("[Accessibility-Debug] Montage Changed: " .. tostring(montageName) .. " (isAnimMontage=" .. tostring(isAnim) .. ")")
    end

    if isWildcardMontageActive and not wasActive then
        -- print("[MontageWildcard] Start: Desired Aim Method -> Game (0)")
        -- uevr.params.vr.set_mod_value("VR_AimMethod", "0") -- Handled by Entry.lua AimManager
        pawnModule.hideArms(false)
    elseif wasActive and not isWildcardMontageActive then
        -- print("[MontageWildcard] End: Desired Aim Method -> HMD (1)")
        -- uevr.params.vr.set_mod_value("VR_AimMethod", "1") -- Handled by Entry.lua AimManager
        pawnModule.hideArms(true)
    end
    
    -- print("[MontageWildcard] Activated for: " .. tostring(montageName))
end)

-- 2. Register Visibility Callbacks with Low Priority

-- Hands: Hidden (true) when active
hands.registerIsHiddenCallback(function()
    if isWildcardMontageActive then
        return true, wildcardPriority
    end
    return nil
end)

-- Pawn Arms: Visible (false) when active
pawnModule.registerIsPawnArmsHiddenCallback(function()
    if isWildcardMontageActive then
        return false, wildcardPriority
    end
    return nil
end)

-- Pawn Arm Bones: Visible (false) when active
pawnModule.registerIsArmBonesHiddenCallback(function()
    if isWildcardMontageActive then
        return false, wildcardPriority
    end
    return nil
end)

return M
