-- Physical knife melee (2026-09-24).
--
-- While the knife is equipped, a fast swing of the dominant-hand controller (down, left or
-- right - and a forward stab) is turned into a short Right Trigger press, which is the game's
-- melee attack for the knife. The knife melee montages (MG_fp_knife_melee / _melee_stab) are
-- then sped up so the animation keeps up with the physical swing.
--
-- Detection is deliberately NOT routed through libs/gestures.lua's swipe callbacks: that
-- detector classifies every swing as BOTH left/right AND up/down (sign of each component, no
-- dominance test) and fires them as separate callbacks, so a mostly-horizontal slash with a
-- slight rise reads as "up" and there is no way to tell from one callback what the swing
-- really was. This module tracks the same thing (hand delta minus head delta, peak speed,
-- classify on deceleration) but in the HMD yaw frame and by dominant axis, and only rejects
-- swings whose dominant direction is UP (raising the arm) or BACK (pulling the hand in).
--
-- Injection follows the Avowed profile and ptm_manual_reload's X spoof: RT = 255 for a few
-- xinput polls, capped by a wall-clock deadline so a frame stall cannot turn the tap into a
-- long hold. Config lives in Config.knifeMelee (fixed-key nested table, so it persists).
require("Config.CONFIG")
local controllers = require("libs/controllers")
local uevrUtils   = require("libs/uevr_utils")

local M = {}

local TRIGGER_POLLS    = 3      -- xinput polls the trigger is held (ptm's X spoof uses 3)
local TRIGGER_MAX_HOLD = 0.25   -- seconds: hard cap on the injected hold

local function cfg()
    local c = Config.knifeMelee
    if type(c) ~= "table" then
        c = {}
        Config.knifeMelee = c
    end
    return c
end

function M.isEnabled()
    return cfg().enabled ~= false
end

-- Debug log that actually reaches UEVR's log.txt: Lua print() does not, but luakey.dll echoes
-- every custom event it receives ("LuaKey: Received Custom Event: <name> <data>"). A multi-char
-- event name with data that is not exactly "up"/"down" is ignored by the patched luakey and by
-- uevr_utils.dll (only ExecuteFunction_* names are RPCs), so this is a pure log line.
local function dbg(text)
    if not cfg().log then return end
    pcall(function() uevr.api:dispatch_custom_event("KnifeMelee", tostring(text)) end)
end
M.dbg = dbg

-- Per-tick montage trace for N ticks after a swing (log mode only).
local traceTicksLeft = 0
local traceTick = 0
local function traceMontage()
    if traceTicksLeft <= 0 then return end
    traceTicksLeft = traceTicksLeft - 1
    traceTick = traceTick + 1
    pcall(function()
        local pawn = uevr.api:get_local_pawn(0)
        if pawn == nil then return end
        local m = pawn:GetCurrentMontage()
        local name = m and uevrUtils.getShortName(m) or "-"
        local cm = pawn.Mesh
        local rate = cm and cm.GlobalAnimRateScale or -1
        local wm = cm and cm.AnimScriptInstance and cm.AnimScriptInstance.WeaponData and cm.AnimScriptInstance.WeaponData.WeaponMesh
        local wname = "-"
        if wm and wm.AnimScriptInstance and wm.AnimScriptInstance.GetCurrentActiveMontage then
            local wmon = wm.AnimScriptInstance:GetCurrentActiveMontage()
            wname = wmon and uevrUtils.getShortName(wmon) or "-"
        end
        dbg(string.format("trace t+%d char=%s rate=%s weapon=%s", traceTick, name, tostring(rate), wname))
    end)
end

-- ---------------------------------------------------------------------------------------
-- Equip tracking
-- ---------------------------------------------------------------------------------------
local knifeEquipped   = false
local lastWeaponName  = false   -- false = never checked (nil is a valid "bare hands" value)

local function updateEquipped(weaponName)
    if weaponName == lastWeaponName then return end
    lastWeaponName = weaponName
    knifeEquipped = type(weaponName) == "string" and string.find(string.lower(weaponName), "knife", 1, true) ~= nil
    if not knifeEquipped then
        M.reset()
    end
end

function M.isKnifeEquipped()
    return knifeEquipped
end

-- ---------------------------------------------------------------------------------------
-- Swing detection
-- ---------------------------------------------------------------------------------------
local prevHandPos   = nil
local prevHeadPos   = nil
local prevHeadYaw   = nil
local peakSpeed     = 0
local peakDir       = nil   -- unit vector of the fastest sample, HMD yaw frame (X fwd, Y right, Z up)
local cooldownLeft  = 0

local lastSwing = { kind = "-", speed = 0, at = 0 }   -- dev-panel readout
function M.getLastSwing() return lastSwing end

local function clearMotion()
    prevHandPos, prevHeadPos, prevHeadYaw = nil, nil, nil
    peakSpeed, peakDir = 0, nil
end

local function rotateInverseYaw(v, yawDeg)
    local r = -math.rad(yawDeg)
    local c, s = math.cos(r), math.sin(r)
    return { X = v.X * c - v.Y * s, Y = v.X * s + v.Y * c, Z = v.Z }
end

-- Returns "down" | "left" | "right" | "stab" for an accepted swing, or nil (up / pull-back).
local function classify(dir)
    local ax, ay, az = math.abs(dir.X), math.abs(dir.Y), math.abs(dir.Z)
    if az >= ax and az >= ay then
        if dir.Z > 0 then return nil end     -- raising the arm: never an attack
        return "down"
    elseif ay >= ax then
        return dir.Y < 0 and "left" or "right"
    else
        if dir.X < 0 then return nil end     -- pulling the hand back toward the body
        return "stab"
    end
end

-- Trigger injection state (consumed in on_xinput_get_state).
local triggerPollsLeft  = 0
local triggerDeadline   = 0

local function fireAttack(kind, speed)
    triggerPollsLeft = TRIGGER_POLLS
    triggerDeadline  = os.clock() + TRIGGER_MAX_HOLD
    lastSwing.kind, lastSwing.speed, lastSwing.at = kind, speed, os.clock()
    dbg(string.format("%s swing %.0f cm/s -> RT", kind, speed))
    traceTicksLeft, traceTick = 45, 0
end

local function detect(delta)
    if delta == nil or delta <= 0 then return end
    local c = cfg()
    if cooldownLeft > 0 then
        cooldownLeft = cooldownLeft - delta
        clearMotion()
        return
    end

    local hand = Config.dominantHand or 1
    local handPos = controllers.getControllerLocation(hand)
    local headPos = controllers.getControllerLocation(2)
    local headRot = controllers.getControllerRotation(2)
    if handPos == nil or headPos == nil or headRot == nil then
        clearMotion()
        return
    end
    -- Copy: the controller helpers may hand back live/reused structs.
    local hp = { X = handPos.X, Y = handPos.Y, Z = handPos.Z }
    local hd = { X = headPos.X, Y = headPos.Y, Z = headPos.Z }
    local yaw = headRot.Yaw

    if prevHandPos == nil or prevHeadPos == nil or prevHeadYaw == nil then
        prevHandPos, prevHeadPos, prevHeadYaw = hp, hd, yaw
        return
    end

    -- Snap turn / large head yaw jump: throw the sample away.
    local dYaw = math.abs(yaw - prevHeadYaw)
    if dYaw > 180 then dYaw = 360 - dYaw end
    if dYaw > 45 then
        prevHandPos, prevHeadPos, prevHeadYaw = hp, hd, yaw
        peakSpeed, peakDir = 0, nil
        return
    end

    -- Hand motion with the head's (i.e. the pawn's) own motion removed, in the head yaw frame.
    local dw = { X = (hp.X - prevHandPos.X) - (hd.X - prevHeadPos.X),
                 Y = (hp.Y - prevHandPos.Y) - (hd.Y - prevHeadPos.Y),
                 Z = (hp.Z - prevHandPos.Z) - (hd.Z - prevHeadPos.Z) }
    local dl = rotateInverseYaw(dw, yaw)
    local dist = math.sqrt(dl.X * dl.X + dl.Y * dl.Y + dl.Z * dl.Z)
    local speed = dist / delta
    prevHandPos, prevHeadPos, prevHeadYaw = hp, hd, yaw

    local minSpeed = tonumber(c.minSpeed) or 180
    if speed > minSpeed and speed > peakSpeed and dist > 0 then
        -- Still accelerating: remember the fastest sample and its direction.
        peakSpeed = speed
        peakDir = { X = dl.X / dist, Y = dl.Y / dist, Z = dl.Z / dist }
        return
    end

    -- First sample slower than the peak (or back under the threshold): the swing has peaked,
    -- classify it now rather than waiting for the hand to stop (same early-fire idea as
    -- libs/gestures.lua's punch detector - keeps the attack close to the physical hit).
    if peakSpeed > 0 and peakDir ~= nil then
        local kind = classify(peakDir)
        local pk, pd = peakSpeed, peakDir
        peakSpeed, peakDir = 0, nil
        if kind ~= nil then
            fireAttack(kind, pk)
            cooldownLeft = tonumber(c.cooldown) or 0.35
        else
            dbg(string.format("ignored swing %.0f cm/s dir(%.2f %.2f %.2f)", pk, pd.X, pd.Y, pd.Z))
        end
    end
end

-- ---------------------------------------------------------------------------------------
-- Montage speed-up
-- ---------------------------------------------------------------------------------------
-- Two anim instances are involved, and the VISIBLE swing is the second one (log.txt trace,
-- 2026-09-24):
--   * character mesh (pawn.Mesh, AnimBP_Player_C) plays MG_fp_knife_melee - this is what
--     pawn:GetCurrentMontage() / the montage-change callback report;
--   * the knife's own SkeletalMeshComponent (AnimScriptInstance.WeaponData.WeaponMesh, the
--     recycled WeaponInHandsMesh) plays MG_knife_fp_melee for ~40 ticks, and the VR hand mesh is
--     attached to that mesh's jnt_r_hand bone, so its montage is the arm motion the player sees.
-- Montage_SetPlayRate through the plugin bridge had no visible effect, so both meshes get their
-- GlobalAnimRateScale raised (the property ptm_manual_reload already drives at 100x for reload
-- fast-forwards) for as long as either mesh is still playing a knife melee montage. Because the
-- weapon component is recycled across weapons, the restore to 1.0 is unconditional on unequip,
-- reset and a wall-clock safety deadline - a stale 10x there would speed up the next weapon.
local rateActive         = false
local rateSafetyDeadline = 0
local RATE_MAX_SECONDS   = 1.5   -- knife melee montages are well under a second at 1x

-- Character montage is "MG_fp_knife_melee[_stab]", weapon montage is "MG_knife_fp_melee": match
-- on both words rather than one fixed order.
local function isKnifeMeleeMontage(name)
    if type(name) ~= "string" or name == "" then return false end
    local n = string.lower(name)
    return string.find(n, "knife", 1, true) ~= nil and string.find(n, "melee", 1, true) ~= nil
end

local function resolveMeshes()
    local pawn = uevr.api:get_local_pawn(0)
    local cm = pawn and pawn.Mesh or nil
    local ai = cm and cm.AnimScriptInstance or nil
    local wm = ai and ai.WeaponData and ai.WeaponData.WeaponMesh or nil
    return pawn, cm, wm
end

local function weaponMontageName(wm)
    local name = nil
    pcall(function()
        local wai = wm and wm.AnimScriptInstance
        if wai == nil then return end
        local m = wai:GetCurrentActiveMontage()
        if m ~= nil then name = uevrUtils.getShortName(m) end
    end)
    return name
end

local function charMontageName(pawn)
    local name = nil
    pcall(function()
        local m = pawn and pawn:GetCurrentMontage()
        if m ~= nil then name = uevrUtils.getShortName(m) end
    end)
    return name
end

local function setRates(rate)
    pcall(function()
        local _, cm, wm = resolveMeshes()
        if cm ~= nil then cm.GlobalAnimRateScale = rate end
        if wm ~= nil then wm.GlobalAnimRateScale = rate end
    end)
end

local function restoreRate()
    if not rateActive then return end
    rateActive = false
    setRates(1.0)
    dbg("char + weapon mesh rate restored to 1.0")
end

-- Entry.lua's registerMontageChangeCallback forwards every change here.
function M.onMontageChange(montage, montageName)
    if not M.isEnabled() or not knifeEquipped then
        restoreRate()
        return
    end
    dbg("montage change -> " .. tostring(montageName ~= "" and montageName or "nil"))
    if montage ~= nil and isKnifeMeleeMontage(montageName) then
        local rate = tonumber(cfg().animRate) or 20.0
        if rate <= 0 then rate = 1.0 end
        rateActive = true
        rateSafetyDeadline = os.clock() + RATE_MAX_SECONDS
        setRates(rate)
        dbg("montage " .. tostring(montageName) .. " -> GlobalAnimRateScale x" .. tostring(rate) .. " (char + weapon mesh)")
    end
    -- A change to nil / another montage does NOT restore here: the weapon mesh montage outlives
    -- the character one. updateRate() below ends the window once both are gone.
end

-- Per tick while the speed-up is active: keep both meshes at the rate (the weapon montage can
-- start a tick after the character one) and end the window once neither mesh is still playing
-- a knife melee montage.
local function updateRate()
    if not rateActive then return end
    if os.clock() > rateSafetyDeadline then
        restoreRate()
        return
    end
    local pawn, cm, wm = resolveMeshes()
    if pawn == nil then restoreRate() return end
    local cName = charMontageName(pawn)
    local wName = weaponMontageName(wm)
    if isKnifeMeleeMontage(cName) or isKnifeMeleeMontage(wName) then
        local rate = tonumber(cfg().animRate) or 20.0
        if rate <= 0 then rate = 1.0 end
        pcall(function()
            if cm ~= nil and cm.GlobalAnimRateScale ~= rate then cm.GlobalAnimRateScale = rate end
            if wm ~= nil and wm.GlobalAnimRateScale ~= rate then wm.GlobalAnimRateScale = rate end
        end)
    else
        restoreRate()
    end
end

-- ---------------------------------------------------------------------------------------
-- Frame / input hooks
-- ---------------------------------------------------------------------------------------
-- Called from Entry.lua's on_pre_engine_tick (gameplay only). weaponName = Entry's
-- currentWeaponName (nil for bare hands).
function M.on_pre_engine_tick(delta, weaponName)
    updateEquipped(weaponName)
    if not knifeEquipped or not M.isEnabled() then return end

    traceMontage()
    updateRate()

    detect(delta)
end

-- Called from Entry.lua's on_xinput_get_state after the other input modules, so the
-- injected trigger is not zeroed by the gesture-key analog quiet window.
function M.on_xinput_get_state(state)
    if triggerPollsLeft <= 0 or state == nil then return end
    if os.clock() > triggerDeadline then
        triggerPollsLeft = 0
        return
    end
    state.Gamepad.bRightTrigger = 255
    triggerPollsLeft = triggerPollsLeft - 1
end

function M.reset()
    clearMotion()
    cooldownLeft = 0
    triggerPollsLeft = 0
    restoreRate()
end

return M
