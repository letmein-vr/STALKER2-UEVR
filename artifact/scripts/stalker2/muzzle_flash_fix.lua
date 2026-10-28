-- Muzzle flash stays on the barrel (2026-10-18).
--
-- The muzzle flash is one persistent NiagaraComponent, re-attached to the recycled WeaponInHandsMesh at socket
-- "MuzzleFOV" (within 0.2 cm of "Muzzle"). On every shot the game's native code rewrites its RelativeLocation with
-- its first-person-FOV correction: the spot where the FOV-squashed weapon's muzzle would appear, worked out from the
-- camera. In VR the gun is not where that assumes (and the depth fix renders it at its true position), so the flash
-- landed 0 - 13 cm off the barrel, worst with the gun turned away from the view (live MCP watch, 2026-10-18).
--
-- Fix: in the post-stereo callback (this frame's transforms, render state not sent yet) snap the flash back onto its
-- socket. The flash cards, sparks and glow simulate in local space and follow at once; the smoke puff and the short
-- flash light are world-space emitters, so their first frame still starts where the game put them.
--
-- Cost: a children scan of the held weapon once a second; per frame one RelativeLocation read per cached flash
-- component, and a write only right after a shot.
--
-- Laser sights (NS_LaserAim_FPP on "LaserSocket", 2026-10-18): the game moves that component EVERY frame to the end
-- point of its own aim (oriented to the hit surface) and the beam is drawn from the gun to it - but that aim does not
-- follow the barrel in VR (dot ~26 deg off in a live sample). Here: one line trace per frame straight out of
-- LaserSocket, and the component is placed at the hit (facing the surface normal) or at max range. Its Ray / RayDot
-- emitters are world space (computed in the particle update, which by default runs after the game's write), so the
-- component is also switched to tick FIRST: its update then runs at the start of the frame on the end point set here
-- the frame before. Live-confirmed 1:1 with the barrel (Viper, 2026-10-18); the override alone did nothing.
local uevrUtils = require("libs/uevr_utils")

local M = {}

local SCAN_INTERVAL_S = 1.0
local EPS_CM = 0.001
local LASER_SOCKET = "LaserSocket"
local LASER_RANGE_CM = 10000.0
local LASER_TICK_FIRST = 2   -- ENiagaraTickBehavior::ForceTickFirst (default 0 = UsePrereqs)

local niagaraClass = nil
local flashes = {}      -- NiagaraComponents on the held weapon attached at a muzzle socket
local lasers = {}       -- NiagaraComponents on the held weapon running a laser-aim system
local laserWeapon = nil -- the weapon the lasers hang on (their LaserSocket is read from it)
local nextScanAt = 0

local function resolveWeapon()
    local wm = nil
    pcall(function()
        local pawn = uevr.api:get_local_pawn(0)
        local iac = pawn and pawn.ItemAppearanceComponent or nil
        wm = iac and iac.WeaponMeshInHands or nil
    end)
    return wm
end

local function scan()
    flashes = {}
    lasers = {}
    laserWeapon = nil
    local wm = resolveWeapon()
    if wm == nil then return end
    if niagaraClass == nil then
        niagaraClass = uevrUtils.get_class("Class /Script/Niagara.NiagaraComponent")
        if niagaraClass == nil then return end
    end
    pcall(function()
        local children = wm.AttachChildren
        for i = 1, #(children or {}) do
            local child = children[i]
            pcall(function()
                if child:is_a(niagaraClass) then
                    local socket = string.lower(child.AttachSocketName:to_string())
                    if string.find(socket, "muzzle", 1, true) then
                        table.insert(flashes, child)
                    else
                        local asset = child.Asset
                        local name = asset and string.lower(asset:get_fname():to_string()) or ""
                        if string.find(name, "laser", 1, true) then
                            table.insert(lasers, child)
                            -- tick FIRST: the particle update then runs at the start of the frame, on the end point
                            -- placeLaser set last frame, before the game's own write later in the tick
                            if child.TickBehavior ~= LASER_TICK_FIRST then child:SetTickBehavior(LASER_TICK_FIRST) end
                        end
                    end
                end
            end)
        end
    end)
    if #lasers > 0 then laserWeapon = wm end
end

-- Laser end point from the barrel: hit point facing the surface, else max range facing back along the beam.
local function placeLaser(c)
    if not c:IsActive() then return end
    local wm = laserWeapon
    if uevrUtils.validate_object(wm) == nil then return end
    local fn = uevrUtils.fname_from_string(LASER_SOCKET)
    local start = wm:GetSocketLocation(fn)
    local fwd = kismet_math_library:GetForwardVector(wm:GetSocketRotation(fn))
    local pawn = uevr.api:get_local_pawn(0)
    local hit = uevrUtils.getLineTraceHitResult(start, fwd, 0, false, pawn and { pawn } or {}, nil, LASER_RANGE_CM)
    local loc, rot
    if hit ~= nil then
        local l, n = hit.Location, hit.ImpactNormal
        loc = uevrUtils.vector(l.X, l.Y, l.Z)
        rot = kismet_math_library:MakeRotFromX(uevrUtils.vector(n.X, n.Y, n.Z))
    else
        loc = uevrUtils.vector(start.X + fwd.X * LASER_RANGE_CM, start.Y + fwd.Y * LASER_RANGE_CM,
            start.Z + fwd.Z * LASER_RANGE_CM)
        rot = kismet_math_library:MakeRotFromX(uevrUtils.vector(-fwd.X, -fwd.Y, -fwd.Z))
    end
    c:K2_SetWorldLocationAndRotation(loc, rot, false, reusable_hit_result, false)
end

uevrUtils.registerPostCalculateStereoViewCallback(function(device, view_index)
    if view_index ~= 0 then return end
    local now = os.clock()
    if now >= nextScanAt then
        nextScanAt = now + SCAN_INTERVAL_S
        scan()
    end
    for i = 1, #flashes do
        local c = flashes[i]
        pcall(function()
            if uevrUtils.validate_object(c) == nil then return end
            local r = c.RelativeLocation
            if math.abs(r.X) > EPS_CM or math.abs(r.Y) > EPS_CM or math.abs(r.Z) > EPS_CM then
                c:K2_SetRelativeLocation(uevrUtils.vector(0, 0, 0), false, reusable_hit_result, false)
            end
        end)
    end
    for i = 1, #lasers do
        local c = lasers[i]
        if uevrUtils.validate_object(c) ~= nil then pcall(placeLaser, c) end
    end
end)

-- components die with the level: forget them, rescan on the next frame
uevrUtils.registerPreLevelChangeCallback(function(level)
    flashes = {}
    lasers = {}
    laserWeapon = nil
    nextScanAt = 0
end)

return M
