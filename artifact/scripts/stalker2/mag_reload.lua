-- mag_reload.lua
-- Physical magazine reload via left-hand BoxComponent overlap + Left Grip

local utils = require("common/utils")

local M = {}

local BoxCompLH = nil  -- Box on left VR hand
local MagBox    = nil  -- Box on weapon magazine socket

local debugMode = false
local lastReloadTime = 0
local RELOAD_COOLDOWN = 1.2
local wasGripHeld = false  -- for rising-edge detection

-- Cached BoxComponent class
local VHitBoxClass = nil
local function getBoxClass()
    if VHitBoxClass == nil then
        pcall(function()
            VHitBoxClass = utils.find_required_object("Class /Script/Engine.BoxComponent")
        end)
    end
    return VHitBoxClass
end

-- Current active config (applied to boxes; drives UI display)
-- Hand box: global only (follows VR hand, not weapon-specific)
-- Mag box: per-weapon (size + offset relative to socket)
local cfg = {
    magSocket = "jnt_magazine",
    handX = 0.17, handY = 0.11, handZ = 0.15,
    handOffX = -4.2, handOffY = 0.3, handOffZ = -2.7,
    handRotX = 0, handRotY = 0, handRotZ = 7.0,
    magX  = 0.3, magY  = 0.2, magZ  = 0.5,
    magOffX = 0, magOffY = 0, magOffZ = 0,
}

local function applyBoxSizes()
    pcall(function()
        if utils.validate_object(BoxCompLH) then
            BoxCompLH.RelativeScale3D.X = cfg.handX
            BoxCompLH.RelativeScale3D.Y = cfg.handY
            BoxCompLH.RelativeScale3D.Z = cfg.handZ
            BoxCompLH.RelativeLocation.X = cfg.handOffX
            BoxCompLH.RelativeLocation.Y = cfg.handOffY
            BoxCompLH.RelativeLocation.Z = cfg.handOffZ
            BoxCompLH.RelativeRotation.Pitch = cfg.handRotY
            BoxCompLH.RelativeRotation.Yaw = cfg.handRotZ
            BoxCompLH.RelativeRotation.Roll = cfg.handRotX
        end
    end)
    pcall(function()
        if utils.validate_object(MagBox) then
            MagBox.RelativeScale3D.X = cfg.magX
            MagBox.RelativeScale3D.Y = cfg.magY
            MagBox.RelativeScale3D.Z = cfg.magZ
            MagBox.RelativeLocation.X = cfg.magOffX
            MagBox.RelativeLocation.Y = cfg.magOffY
            MagBox.RelativeLocation.Z = cfg.magOffZ
        end
    end)
end

-- Called once per session. left_hand_comp = motionControllerActors.left_hand_component
function M.init(pawn, left_hand_comp)
    if not utils.validate_object(pawn) then return end
    if utils.validate_object(BoxCompLH) then return end  -- already exists

    local cls = getBoxClass()
    if not cls then
        print("[MagReload] ERROR: BoxComponent class not found")
        return
    end

    if not utils.validate_object(left_hand_comp) then
        print("[MagReload] ERROR: left_hand_component is invalid")
        return
    end

    local ok, err = pcall(function()
        BoxCompLH = uevr.api:add_component_by_class(pawn, cls)
    end)
    if not ok or not utils.validate_object(BoxCompLH) then
        print("[MagReload] ERROR: BoxCompLH creation failed: " .. tostring(err))
        BoxCompLH = nil
        return
    end

    pcall(function()
        BoxCompLH:K2_AttachToComponent(left_hand_comp, "Root", 0, 0, 0, true)
    end)

    pcall(function()
        if BoxCompLH and BoxCompLH.SetGenerateOverlapEvents then
            BoxCompLH:SetGenerateOverlapEvents(true)
            BoxCompLH:SetCollisionObjectType(2) -- WorldDynamic
            BoxCompLH:SetCollisionResponseToAllChannels(1) -- Overlap everything
            BoxCompLH:SetCollisionEnabled(1)
        end
    end)

    BoxCompLH.RelativeScale3D.X = cfg.handX
    BoxCompLH.RelativeScale3D.Y = cfg.handY
    BoxCompLH.RelativeScale3D.Z = cfg.handZ

    if debugMode then
        BoxCompLH:SetHiddenInGame(false)
        BoxCompLH:SetVisibility(true, false)
        print("[MagReload] Left hand box created (visible)")
    else
        BoxCompLH:SetHiddenInGame(true)
        BoxCompLH:SetVisibility(false, false)
    end
end

-- Called on every weapon equip.
-- boxCfg (optional table) overrides current sizes/offsets for this weapon:
--   { magX, magY, magZ, magOffX, magOffY, magOffZ }
function M.update_weapon_collision(pawn, weapon_mesh, boxCfg)
    if not utils.validate_object(pawn) then return end
    if not utils.validate_object(weapon_mesh) then return end

    local cls = getBoxClass()
    if not cls then return end

    -- Apply per-weapon config if provided, else keep current
    if boxCfg then
        if boxCfg.magSocket then cfg.magSocket = boxCfg.magSocket end
        if boxCfg.magX   then cfg.magX   = boxCfg.magX   end
        if boxCfg.magY   then cfg.magY   = boxCfg.magY   end
        if boxCfg.magZ   then cfg.magZ   = boxCfg.magZ   end
        if boxCfg.magOffX then cfg.magOffX = boxCfg.magOffX end
        if boxCfg.magOffY then cfg.magOffY = boxCfg.magOffY end
        if boxCfg.magOffZ then cfg.magOffZ = boxCfg.magOffZ end
        if boxCfg.handX  then cfg.handX  = boxCfg.handX  end
        if boxCfg.handY  then cfg.handY  = boxCfg.handY  end
        if boxCfg.handZ  then cfg.handZ  = boxCfg.handZ  end
        if boxCfg.handOffX then cfg.handOffX = boxCfg.handOffX end
        if boxCfg.handOffY then cfg.handOffY = boxCfg.handOffY end
        if boxCfg.handOffZ then cfg.handOffZ = boxCfg.handOffZ end
        if boxCfg.handRotX then cfg.handRotX = boxCfg.handRotX end
        if boxCfg.handRotY then cfg.handRotY = boxCfg.handRotY end
        if boxCfg.handRotZ then cfg.handRotZ = boxCfg.handRotZ end
    end

    -- Create MagBox once; keep it alive and re-attach on weapon change
    if not utils.validate_object(MagBox) then
        local ok, err = pcall(function()
            MagBox = uevr.api:add_component_by_class(pawn, cls)
        end)
        if not ok or not utils.validate_object(MagBox) then
            print("[MagReload] ERROR: MagBox creation failed: " .. tostring(err))
            MagBox = nil
            return
        end
    end

    -- Re-attach with SnapToTarget (rule 2) to forcefully re-parent to new weapon mesh
    pcall(function()
        if weapon_mesh:DoesSocketExist(cfg.magSocket) then
            MagBox:K2_AttachToComponent(weapon_mesh, cfg.magSocket, 2, 2, 2, false)
            print("[MagReload] MagBox attached to: " .. cfg.magSocket)
        elseif weapon_mesh:DoesSocketExist("jnt_magazine") then
            -- Fallback 1
            MagBox:K2_AttachToComponent(weapon_mesh, "jnt_magazine", 2, 2, 2, false)
            print("[MagReload] MagBox attached to fallback: jnt_magazine")
        elseif weapon_mesh:DoesSocketExist("jnt_mag_tab") then
            -- Fallback 2
            MagBox:K2_AttachToComponent(weapon_mesh, "jnt_mag_tab", 2, 2, 2, false)
            print("[MagReload] MagBox attached to fallback: jnt_mag_tab")
        else
            print("[MagReload] WARNING: socket '" .. cfg.magSocket .. "' (and fallbacks) not found on weapon")
        end
    end)

    pcall(function()
        if MagBox and MagBox.SetGenerateOverlapEvents then
            MagBox:SetGenerateOverlapEvents(true)
            MagBox:SetCollisionObjectType(2) -- WorldDynamic
            MagBox:SetCollisionResponseToAllChannels(1) -- Overlap everything
            MagBox:SetCollisionEnabled(1)
        end
    end)

    -- Apply size and offset
    applyBoxSizes()

    if debugMode then
        MagBox:SetHiddenInGame(false)
        MagBox:SetVisibility(true, false)
    else
        MagBox:SetHiddenInGame(true)
        MagBox:SetVisibility(false, false)
    end
end

function M.check_reload_input(state, pawn)
    if not utils.validate_object(BoxCompLH) then return false end
    if not utils.validate_object(MagBox) then return false end

    local leftGrip = (state.Gamepad.wButtons & XINPUT_GAMEPAD_LEFT_SHOULDER) ~= 0
    local gripJustPressed = leftGrip and not wasGripHeld
    wasGripHeld = leftGrip

    -- Only evaluate on the frame grip is first pressed (rising edge)
    -- This means two-handing (grip pressed at foregrip, no mag overlap) never fires.
    -- Reload only fires when you deliberately press grip right at the magazine.
    if not gripJustPressed then return false end

    -- Also skip if TwoHandedStateActive just in case grip pressed during two-hand transition
    if TwoHandedStateActive then return false end

    -- Cooldown
    local now = os.clock()
    if (now - lastReloadTime) < RELOAD_COOLDOWN then return false end

    local overlapping = {}
    pcall(function()
        BoxCompLH:GetOverlappingComponents(overlapping)
    end)

    local magFullName = MagBox:get_full_name()
    for _, comp in ipairs(overlapping) do
        if comp and UEVR_UObjectHook.exists(comp) then
            if comp:get_full_name() == magFullName then
                lastReloadTime = now
                if debugMode then print("[MagReload] Reload triggered!") end
                state.Gamepad.wButtons = state.Gamepad.wButtons | XINPUT_GAMEPAD_X
                return true
            end
        end
    end

    return false
end

-- Return a copy of the current active config (for UI display)
function M.get_config()
    return {
        magSocket = cfg.magSocket,
        handX = cfg.handX, handY = cfg.handY, handZ = cfg.handZ,
        handOffX = cfg.handOffX, handOffY = cfg.handOffY, handOffZ = cfg.handOffZ,
        handRotX = cfg.handRotX, handRotY = cfg.handRotY, handRotZ = cfg.handRotZ,
        magX  = cfg.magX,  magY  = cfg.magY,  magZ  = cfg.magZ,
        magOffX = cfg.magOffX, magOffY = cfg.magOffY, magOffZ = cfg.magOffZ,
    }
end

-- Apply sizes and offsets immediately (called from UI sliders)
function M.set_config(newCfg)
    if newCfg.magSocket then cfg.magSocket = newCfg.magSocket end
    if newCfg.handX   then cfg.handX   = newCfg.handX   end
    if newCfg.handY   then cfg.handY   = newCfg.handY   end
    if newCfg.handZ   then cfg.handZ   = newCfg.handZ   end
    if newCfg.handOffX then cfg.handOffX = newCfg.handOffX end
    if newCfg.handOffY then cfg.handOffY = newCfg.handOffY end
    if newCfg.handOffZ then cfg.handOffZ = newCfg.handOffZ end
    if newCfg.handRotX then cfg.handRotX = newCfg.handRotX end
    if newCfg.handRotY then cfg.handRotY = newCfg.handRotY end
    if newCfg.handRotZ then cfg.handRotZ = newCfg.handRotZ end
    if newCfg.magX    then cfg.magX    = newCfg.magX    end
    if newCfg.magY    then cfg.magY    = newCfg.magY    end
    if newCfg.magZ    then cfg.magZ    = newCfg.magZ    end
    if newCfg.magOffX then cfg.magOffX = newCfg.magOffX end
    if newCfg.magOffY then cfg.magOffY = newCfg.magOffY end
    if newCfg.magOffZ then cfg.magOffZ = newCfg.magOffZ end
    applyBoxSizes()
end

function M.set_debug(val)
    debugMode = val
    if utils.validate_object(BoxCompLH) then 
        BoxCompLH:SetHiddenInGame(not val) 
        BoxCompLH:SetVisibility(val, false)
    end
    if utils.validate_object(MagBox) then 
        MagBox:SetHiddenInGame(not val) 
        MagBox:SetVisibility(val, false)
    end
end

function M.get_debug()
    return debugMode
end

-- Expose the left hand box so two_hand.lua can share it
function M.get_hand_box()
    return BoxCompLH
end

return M
