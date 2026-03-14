-- two_hand.lua
-- Collision-box based two-handed aiming.
-- A ForegripBox is attached to a configurable weapon socket.
-- When the left hand (BoxCompLH from mag_reload) overlaps ForegripBox,
-- TwoHandedStateActive is set true and two-hand aiming engages.
-- No left grip button required.

local utils = require("common/utils")
local magReload = require("stalker2.mag_reload")
local gameState = require("stalker2.gamestate")

local M = {}

local ForegripBox = nil  -- Box on weapon foregrip socket

local debugMode = false

-- Current active config
local cfg = {
    socket  = "jnt_l_hand",  -- default foregrip socket
    scaleX  = 0.5, scaleY = 0.5, scaleZ = 0.5,
    offX    = 0,   offY   = 0,   offZ   = 0,
    rotX    = 0,   rotY   = 0,   rotZ   = 0,
}

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

local function applyBoxConfig()
    if utils.validate_object(ForegripBox) then
        ForegripBox.RelativeScale3D.X = cfg.scaleX
        ForegripBox.RelativeScale3D.Y = cfg.scaleY
        ForegripBox.RelativeScale3D.Z = cfg.scaleZ
        ForegripBox.RelativeLocation.X = cfg.offX
        ForegripBox.RelativeLocation.Y = cfg.offY
        ForegripBox.RelativeLocation.Z = cfg.offZ
        ForegripBox.RelativeRotation.Pitch = cfg.rotY
        ForegripBox.RelativeRotation.Yaw   = cfg.rotZ
        ForegripBox.RelativeRotation.Roll  = cfg.rotX
    end
end

-- Called on weapon equip. boxCfg (optional) = per-weapon config table.
function M.update_weapon_collision(pawn, weapon_mesh, boxCfg)
    if not utils.validate_object(pawn) then return end
    if not utils.validate_object(weapon_mesh) then return end

    local cls = getBoxClass()
    if not cls then return end

    -- Apply per-weapon config if provided
    if boxCfg then
        if boxCfg.socket  then cfg.socket  = boxCfg.socket  end
        if boxCfg.scaleX  then cfg.scaleX  = boxCfg.scaleX  end
        if boxCfg.scaleY  then cfg.scaleY  = boxCfg.scaleY  end
        if boxCfg.scaleZ  then cfg.scaleZ  = boxCfg.scaleZ  end
        if boxCfg.offX    then cfg.offX    = boxCfg.offX    end
        if boxCfg.offY    then cfg.offY    = boxCfg.offY    end
        if boxCfg.offZ    then cfg.offZ    = boxCfg.offZ    end
        if boxCfg.rotX    then cfg.rotX    = boxCfg.rotX    end
        if boxCfg.rotY    then cfg.rotY    = boxCfg.rotY    end
        if boxCfg.rotZ    then cfg.rotZ    = boxCfg.rotZ    end
    end

    -- Create ForegripBox once, re-attach on weapon change
    if ForegripBox == nil or not UEVR_UObjectHook.exists(ForegripBox) then
        local ok, err = pcall(function()
            ForegripBox = uevr.api:add_component_by_class(pawn, cls)
        end)
        if not ok or not utils.validate_object(ForegripBox) then
            print("[TwoHand] ERROR: ForegripBox creation failed: " .. tostring(err))
            ForegripBox = nil
            return
        end
    end

    -- Re-attach to weapon socket (SnapToTarget = rule 2)
    pcall(function()
        if weapon_mesh:DoesSocketExist(cfg.socket) then
            ForegripBox:K2_AttachToComponent(weapon_mesh, cfg.socket, 2, 2, 2, false)
            print("[TwoHand] ForegripBox attached to: " .. cfg.socket)
        else
            print("[TwoHand] WARNING: socket '" .. cfg.socket .. "' not found on weapon")
        end
    end)

    ForegripBox:SetGenerateOverlapEvents(true)
    ForegripBox:SetCollisionResponseToAllChannels(1)
    ForegripBox:SetCollisionObjectType(0)
    ForegripBox:SetCollisionEnabled(1)

    applyBoxConfig()

    ForegripBox.bHiddenInGame = not debugMode
end

-- Called every tick from on_pre_engine_tick.
-- Checks overlap between BoxCompLH (left hand) and ForegripBox.
-- Sets TwoHandedStateActive and gameState.isTwoHanding accordingly.
function M.update(pawn)
    if not utils.validate_object(ForegripBox) then return end

    local handBox = magReload.get_hand_box()
    if not utils.validate_object(handBox) then return end

    -- Distance Early-Out Optimization
    -- Safe threshold: 3600 (approx 60cm distance)
    local ok, hLoc, fLoc = pcall(function()
        return handBox:K2_GetComponentLocation(), ForegripBox:K2_GetComponentLocation()
    end)
    
    if ok and hLoc and fLoc then
        local dx = hLoc.x - fLoc.x
        local dy = hLoc.y - fLoc.y
        local dz = hLoc.z - fLoc.z
        local distSq = dx*dx + dy*dy + dz*dz
        if distSq > 3600 then 
            if TwoHandedStateActive then
                TwoHandedStateActive = false
                gameState.isTwoHanding = false
                if debugMode then print("[TwoHand] Two-hand RELEASED (Distance Out)") end
            end
            return
        end
    end

    local overlapping = {}
    pcall(function()
        handBox:GetOverlappingComponents(overlapping)
    end)

    local isOverlapping = false
    local foregripAddress = ForegripBox:get_address()
    for _, comp in ipairs(overlapping) do
        if comp and UEVR_UObjectHook.exists(comp) then
            if comp:get_address() == foregripAddress then
                isOverlapping = true
                break
            end
        end
    end

    local wasActive = TwoHandedStateActive
    if isOverlapping and not TwoHandedStateActive then
        TwoHandedStateActive = true
        gameState.isTwoHanding = true
        if debugMode then print("[TwoHand] Two-hand ENGAGED") end
    elseif not isOverlapping and TwoHandedStateActive then
        TwoHandedStateActive = false
        gameState.isTwoHanding = false
        if debugMode then print("[TwoHand] Two-hand RELEASED") end
    end
end

function M.get_config()
    return {
        socket = cfg.socket,
        scaleX = cfg.scaleX, scaleY = cfg.scaleY, scaleZ = cfg.scaleZ,
        offX   = cfg.offX,   offY   = cfg.offY,   offZ   = cfg.offZ,
        rotX   = cfg.rotX,   rotY   = cfg.rotY,   rotZ   = cfg.rotZ,
    }
end

function M.set_config(newCfg)
    if newCfg.socket  then cfg.socket  = newCfg.socket  end
    if newCfg.scaleX  then cfg.scaleX  = newCfg.scaleX  end
    if newCfg.scaleY  then cfg.scaleY  = newCfg.scaleY  end
    if newCfg.scaleZ  then cfg.scaleZ  = newCfg.scaleZ  end
    if newCfg.offX    then cfg.offX    = newCfg.offX    end
    if newCfg.offY    then cfg.offY    = newCfg.offY    end
    if newCfg.offZ    then cfg.offZ    = newCfg.offZ    end
    if newCfg.rotX    then cfg.rotX    = newCfg.rotX    end
    if newCfg.rotY    then cfg.rotY    = newCfg.rotY    end
    if newCfg.rotZ    then cfg.rotZ    = newCfg.rotZ    end
    applyBoxConfig()
end

function M.set_debug(val)
    debugMode = val
    if utils.validate_object(ForegripBox) then
        ForegripBox.bHiddenInGame = not val
    end
end

return M
