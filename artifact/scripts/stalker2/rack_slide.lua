-- Rack to chamber (2026-10-18).
--
-- After an EMPTY manual mag reload the player racks the slide / charging handle / bolt carrier before
-- the weapon fires again. ptm_manual_reload.lua holds the reload in STATE_AWAIT_RACK (native reload
-- still paused, trigger suppressed) and calls this module; nothing touches ammo - the rack only gates
-- completeBoxMagInsert, whose fast-forward does the game's own chambering.
--
-- Game facts (live MCP survey of 21 weapons, 2026-10-18):
--   * a weapon is a skeletal rig plus static-mesh parts on its joints; every moving action part hangs
--     under jnt_offset (the receiver) or under another moving part, and slides purely along the
--     receiver's X axis (racking = -X). Measure in parent-bone space (GetSocketTransform(name, 3)):
--     reload animations move the whole gun inside its component.
--   * the grab part is found by mesh-name ENDING (DLC skins keep the suffixes): handles first, then
--     slides / carriers. Parts under the grab joint in the bone tree ride with it (FORA bolt, AR latch,
--     Arev knob); a separate bolt that is not locked open rides with a handle too (Viper).
--   * pistols, AR416, Arev, Kharod, Integral, SVDM lock open when empty (the paused reload starts with
--     the part back); AK-style carriers, Viper, FORA stay closed; the M10 is open-bolt (cocked = back).
--   * travel differs per weapon (3.5 - 13.7 cm) and is LEARNED here in play: rest = joint X at still idle
--     moments, furthest back = while firing / during the game's own reload. Saved per weapon in
--     Config.rackLearned. Handles that never move with the bolt (AR416, Arev) take the bolt's
--     lock-back as their pull distance.
-- Weapon type = the rig's asset folder: weapons/pt = pistols, smg, ar = assault rifles, sr = snipers.
require("Config.CONFIG")
local uevrUtils = require("libs/uevr_utils")
local controllers = require("libs/controllers")
local quat = require("libs/core/quat_math")

local M = {}

local CATEGORIES = {
    { folder = "/weapons/pt/",  key = "pistol" },
    { folder = "/weapons/smg/", key = "smg" },
    { folder = "/weapons/ar/",  key = "ar" },
    { folder = "/weapons/sr/",  key = "sniper" },
    { folder = "/weapons/dmr/", key = "sniper" },   -- GP3A, SKP (2026-10-18 audit): the Snipers / DMRs toggle
    { folder = "/weapons/shg/", key = "shotgun" },  -- box-mag shotguns only (D12, M860 bigmag); tube-fed never racks
}
-- Grab part name endings, in priority order (a weapon with a handle is racked by the handle). Compared on the
-- CANONICAL mesh name: lowercase, trailing "_<digits>" dropped, underscores removed - so the SM_wpn_udp_SM_shutter
-- scheme and the SM_Wpn_Gp3a_BoltHandle_01 scheme (GP3A) both match; "_shutter_delay" / "_slide_lock" do not.
local GRAB_KEYS = {
    "charginghandle", "cokinghandle", "chargehandle", "bolthandle",
    "slide", "shutter", "boltaction",
    "boltcarrier",   -- SKP (DLC): SM_Wpn_Skp_Polymer_bolt_carrier on jnt_offset, the bolt rides on it (AK-style)
    "bolt",          -- last resort: D12 (SM_wpn_d1200_SM_bolt on jnt_offset = carrier + handle, Saiga-style)
}
local BOLT_KEY           = "bolt"
local OPEN_BOLT          = { "sk_m1000" }
-- never racked, whatever their folder (lowercase rig name prefixes; 2026-10-18: PKP "for now", RPG-7)
local RACK_EXEMPT        = { "sk_pkp", "sk_rpg7" }   -- lowercase rig-name prefixes: rest = cocked (back)
local RECEIVER_JOINT     = "jnt_offset"
local DEFAULT_STROKE_CM  = { pistol = 5.0, smg = 8.0, ar = 12.0, sniper = 13.0, shotgun = 12.0 }
local MIN_PULL_CM        = 0.8     -- part already back (locked open): a short pull past the lock
local LOCKED_CM          = 1.0     -- further back than this from rest = locked open
local FULL_PULL_FRACTION = 0.9
local RETURN_TIME_S      = 0.06    -- release: part springs forward
local SPRINGBACK_TIME_S  = 0.12    -- let go before a full pull: part eases back, rack again
local DEFAULT_GRAB_CM    = 12.0
-- Pistol slide-stop look (2026-10-18): the slide stop drops once the slide is pulled past the lock, the slide
-- slams fully home on release, the tilting barrel locks up as it closes, and all of it is held there until the
-- game's own (fast-forwarded) closing animation catches up. Parts by canonical name ending, pistols only:
-- UDP SM_wpn_udp_SM_lock / _titing_barrel, PM _shutter_delay, APB _delay, Kora SM_kora_SM_slide_lock / _barrel.
local STOP_KEYS          = { "slidelock", "shutterdelay", "delay", "lock" }
local BARREL_KEYS        = { "barrel" }
local STOP_TRIP_CM       = 0.3     -- pulled this far past the lock: the slide stop drops
local STOP_MOVE_S        = 0.04    -- slide stop drop / re-engage time
local SETTLE_TOL_CM      = 0.15    -- game's slide bone this close to the learned closed rest: offsets off
local SETTLE_MAX_S       = 1.0     -- give up holding after this long (offsets off regardless)
local POSE_EPS_CM        = 0.05    -- learned rest pose updates: move threshold
local POSE_EPS_DOT       = 0.99999 -- ... and rotation threshold (|quat dot|, ~0.5 deg)
-- learning
local IDLE_SAMPLE_S      = 0.25
local IDLE_AFTER_FIRE_S  = 0.6
local IDLE_AFTER_EQUIP_S = 1.5
local FIRE_WINDOW_S      = 0.35
local SAVE_EVERY_S       = 5.0
local LEARN_EPSILON_CM   = 0.05
local FIRED_TICKS_DONE   = 60      -- firing-window samples before a weapon's travel counts as learned (~1 s of fire)

-- ---------------------------------------------------------------------------------------
-- Config
-- ---------------------------------------------------------------------------------------
local function rackCfg()
    if type(Config.rackToChamber) ~= "table" then
        Config.rackToChamber = { pistol = true, smg = true, ar = true, sniper = true, shotgun = true }
    end
    return Config.rackToChamber
end

local function learnedFor(meshName)
    if type(Config.rackLearned) ~= "table" then Config.rackLearned = {} end
    if type(Config.rackLearned[meshName]) ~= "table" then Config.rackLearned[meshName] = {} end
    return Config.rackLearned[meshName]
end

local function grabRadius()
    return Config.rackGrabRadius or DEFAULT_GRAB_CM
end

-- ---------------------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------------------
local fnames = {}
local function fname(s)
    if fnames[s] == nil then fnames[s] = uevrUtils.fname_from_string(s) end
    return fnames[s]
end

local function endsWith(s, suffix)
    return #s >= #suffix and string.sub(s, -#suffix) == suffix
end

local function objAddr(obj)
    if obj == nil then return nil end
    local ok, a = pcall(function() return obj:get_address() end)
    return ok and a or nil
end

local function resolveWeapon()
    local wm = nil
    pcall(function()
        local pawn = uevr.api:get_local_pawn(0)
        local iac = pawn and pawn.ItemAppearanceComponent or nil
        wm = iac and iac.WeaponMeshInHands or nil
    end)
    return wm
end

-- joint X relative to its parent bone (the receiver for every action part surveyed)
local function jointX(wm, joint)
    local x = nil
    pcall(function() x = wm:GetSocketTransform(fname(joint), 3).Translation.X end)
    return x
end

-- Rigid transforms as { q = {w,x,y,z}, t = {x,y,z} } in UE compose order (compose(a, b) = a, then b - FTransform
-- A * B), so a part's world transform is compose(partRelative, jointWorld). Scale is 1 on every part involved.
local function tCompose(a, b)
    local r = quat.rotate(b.q, a.t.x, a.t.y, a.t.z)
    return { q = quat.mul(b.q, a.q), t = { x = r.x + b.t.x, y = r.y + b.t.y, z = r.z + b.t.z } }
end

local function tInverse(a)
    local qi = quat.inv(a.q)
    local r = quat.rotate(qi, a.t.x, a.t.y, a.t.z)
    return { q = qi, t = { x = -r.x, y = -r.y, z = -r.z } }
end

-- joint transform relative to its parent bone
local function jointLocal(wm, joint)
    local out = nil
    pcall(function()
        local tr = wm:GetSocketTransform(fname(joint), 3)
        local q, t = tr.Rotation, tr.Translation
        out = { q = { w = q.W, x = q.X, y = q.Y, z = q.Z }, t = { x = t.X, y = t.Y, z = t.Z } }
    end)
    return out
end

-- ---------------------------------------------------------------------------------------
-- Weapon info (per rig asset): category, grab joint, bolt joint. Joint names only - no part
-- component is kept across frames (the game destroys / recycles them on a weapon swap).
-- ---------------------------------------------------------------------------------------
-- Keyed by the rig asset's NAME, never its address (2026-10-18): rig assets are unloaded / reloaded across weapon
-- swaps and a reloaded one can land at an address another weapon used before - the Arev inherited a non-rackable
-- weapon's cached "no" (no rack, nothing learned) until a script reset.
local infoCache = {}   -- [rig asset name] = info | false (false = not a rackable weapon type)
local infoRetryAt = {} -- [rig asset name] = os.clock() of the next scan when the parts were not attached yet
local INFO_RETRY_S = 1.0

local function assetName(asset)
    local name = nil
    pcall(function() name = asset:get_fname():to_string() end)
    return name
end

-- lowercase, trailing "_<digits>" dropped, underscores removed (see GRAB_KEYS)
local function canonicalName(name)
    local s = string.gsub(string.lower(name), "_%d+$", "")
    return (string.gsub(s, "_", ""))
end

local function scanParts(wm)
    local parts = {}
    pcall(function()
        local children = wm.AttachChildren
        for i = 1, #(children or {}) do
            local child = children[i]
            pcall(function()
                local mesh = child.StaticMesh
                if mesh == nil then return end
                table.insert(parts, {
                    component = child,
                    key = canonicalName(mesh:get_fname():to_string()),
                    socket = child.AttachSocketName:to_string(),
                })
            end)
        end
    end)
    return parts
end

local function findGrab(parts)
    for _, ending in ipairs(GRAB_KEYS) do
        for _, part in ipairs(parts) do
            if endsWith(part.key, ending) then return part, ending end
        end
    end
    return nil
end

local function findBolt(parts)
    for _, part in ipairs(parts) do
        if endsWith(part.key, BOLT_KEY) then return part end
    end
    return nil
end

local function parentJoint(wm, joint)
    local parent = nil
    pcall(function() parent = wm:GetParentBone(fname(joint)):to_string() end)
    if parent == "None" or parent == "" then return nil end
    return parent
end

-- true when joint hangs (at any depth) under ancestor, without passing the receiver
local function isUnder(wm, joint, ancestor)
    for _ = 1, 8 do
        local parent = parentJoint(wm, joint)
        if parent == nil or parent == RECEIVER_JOINT then return false end
        if parent == ancestor then return true end
        joint = parent
    end
    return false
end

local function weaponInfo(wm)
    local asset = nil
    pcall(function() asset = wm.SkeletalMesh end)
    if asset == nil then return nil end
    local key = assetName(asset)
    if key == nil then return nil end
    local cached = infoCache[key]
    if cached ~= nil then return cached or nil end
    if (infoRetryAt[key] or 0) > os.clock() then return nil end
    local info = false
    local retry = false
    pcall(function()
        local rigName = string.lower(asset:get_fname():to_string())
        for _, prefix in ipairs(RACK_EXEMPT) do
            if string.sub(rigName, 1, #prefix) == prefix then return end
        end
        local path = string.lower(asset:get_full_name())
        local category = nil
        for _, c in ipairs(CATEGORIES) do
            if string.find(path, c.folder, 1, true) then category = c.key end
        end
        if category == nil then return end
        local parts = scanParts(wm)
        local grab, ending = findGrab(parts)
        if grab == nil then
            -- right after a swap the parts may not be attached yet: look again shortly, don't cache a "no"
            retry = true
            return
        end
        local bolt = findBolt(parts)
        local meshName = asset:get_fname():to_string()
        local lowerName = string.lower(meshName)
        local openBolt = false
        for _, prefix in ipairs(OPEN_BOLT) do
            if string.sub(lowerName, 1, #prefix) == prefix then openBolt = true end
        end
        local isHandle = string.find(ending, "handle", 1, true) ~= nil
        -- The drive joint is what the rack moves and what the learning measures. Normally the grab joint; when
        -- the grab part rides on the bolt (GP3A: jnt_bolt_handle -> jnt_bolt_part -> jnt_bolt -> jnt_offset)
        -- it is the bolt joint - the handle alone only moves relative to the bolt, never along the receiver.
        local driveJoint = grab.socket
        if bolt ~= nil and bolt.socket ~= grab.socket and isUnder(wm, grab.socket, bolt.socket) then
            driveJoint = bolt.socket
        end
        -- pistols: slide stop + tilting barrel, unless they already ride on the slide
        local function cosmeticJoint(keys)
            if category ~= "pistol" then return nil end
            for _, k in ipairs(keys) do
                for _, part in ipairs(parts) do
                    if part ~= grab and endsWith(part.key, k) and part.socket ~= driveJoint
                       and not isUnder(wm, part.socket, driveJoint) then
                        return part.socket
                    end
                end
            end
            return nil
        end
        info = {
            meshName = meshName, category = category, openBolt = openBolt,
            grabJoint = grab.socket, grabEnding = ending, grabIsHandle = isHandle, driveJoint = driveJoint,
            boltJoint = (bolt ~= nil and bolt.socket ~= grab.socket and bolt.socket ~= driveJoint)
                and bolt.socket or nil,
            stopJoint = cosmeticJoint(STOP_KEYS), barrelJoint = cosmeticJoint(BARREL_KEYS),
        }
    end)
    if retry then
        infoRetryAt[key] = os.clock() + INFO_RETRY_S
        return nil
    end
    infoCache[key] = info
    return info or nil
end

function M.categoryEnabled(info)
    return info ~= nil and rackCfg()[info.category] ~= false
end

-- ---------------------------------------------------------------------------------------
-- Learning (Entry.lua gameplay tick). Cheap: nothing unless a supported weapon is held; one or two
-- GetSocketTransform calls every IDLE_SAMPLE_S when idle, every tick only while firing / reloading.
-- ---------------------------------------------------------------------------------------
local learnWeaponAddr, learnAssetName = nil, nil
local equipAt = 0
local lastTriggerAt = -100
local nextIdleSample = 0
local learnDirty = false
local nextSaveAt = 0

local function learnJoint(wm, meshName, joint, idle, moving)
    if joint == nil then return end
    local x = jointX(wm, joint)
    if x == nil then return end
    local L = learnedFor(meshName)
    if type(L[joint]) ~= "table" then L[joint] = {} end
    local j = L[joint]
    if idle then
        if j.idleMax == nil or x > j.idleMax + LEARN_EPSILON_CM then j.idleMax = x; learnDirty = true end
        if j.idleMin == nil or x < j.idleMin - LEARN_EPSILON_CM then j.idleMin = x; learnDirty = true end
    end
    if moving or idle then
        if j.minX == nil or x < j.minX - LEARN_EPSILON_CM then j.minX = x; learnDirty = true end
    end
end

-- Rest pose (parent-bone space) of a slide stop / tilting barrel, sampled only while the slide sits closed at
-- its learned rest: L[joint].idlePose = { t = {x,y,z}, q = {w,x,y,z} }.
local function learnPose(wm, meshName, joint)
    if joint == nil then return end
    local cur = jointLocal(wm, joint)
    if cur == nil then return end
    local L = learnedFor(meshName)
    if type(L[joint]) ~= "table" then L[joint] = {} end
    local old = L[joint].idlePose
    if type(old) == "table" and type(old.t) == "table" and type(old.q) == "table" then
        local dx, dy, dz = cur.t.x - old.t.x, cur.t.y - old.t.y, cur.t.z - old.t.z
        local dot = math.abs(cur.q.w * old.q.w + cur.q.x * old.q.x + cur.q.y * old.q.y + cur.q.z * old.q.z)
        if math.sqrt(dx * dx + dy * dy + dz * dz) < POSE_EPS_CM and dot > POSE_EPS_DOT then return end
    end
    L[joint].idlePose = cur
    learnDirty = true
end

local function learnCosmetics(wm, info)
    if info.stopJoint == nil and info.barrelJoint == nil then return end
    local rest = (learnedFor(info.meshName)[info.driveJoint] or {}).idleMax
    local x = jointX(wm, info.driveJoint)
    if rest == nil or x == nil or math.abs(rest - x) > SETTLE_TOL_CM then return end   -- slide not closed
    learnPose(wm, info.meshName, info.stopJoint)
    learnPose(wm, info.meshName, info.barrelJoint)
end

-- A weapon is fully learned once its drive part (and bolt) have a closed rest AND ~1 s of firing samples
-- (the furthest-back travel), and a pistol's slide stop / barrel have their rest pose. Persisted per joint
-- (fired = true), so a learned weapon costs nothing here in later sessions; "Forget" relearns everything.
local doneByName = {}   -- [rig asset name] = true: fully learned, learnTick returns at once
local firedTicks = {}   -- [meshName] = firing-window samples this session (not saved)

local function jointDone(L, joint, needFired)
    local j = joint and L[joint]
    if joint == nil then return true end
    if type(j) ~= "table" or j.idleMax == nil then return false end
    return not needFired or j.fired == true
end

local function learnedComplete(info)
    local L = learnedFor(info.meshName)
    return jointDone(L, info.driveJoint, true) and jointDone(L, info.boltJoint, true)
        and (info.stopJoint == nil or (type(L[info.stopJoint]) == "table" and L[info.stopJoint].idlePose ~= nil))
        and (info.barrelJoint == nil or (type(L[info.barrelJoint]) == "table" and L[info.barrelJoint].idlePose ~= nil))
end

local function countFiring(info)
    local n = (firedTicks[info.meshName] or 0) + 1
    firedTicks[info.meshName] = n
    if n ~= FIRED_TICKS_DONE then return end
    local L = learnedFor(info.meshName)
    for _, joint in ipairs({ info.driveJoint, info.boltJoint }) do
        if type(L[joint]) == "table" and L[joint].fired ~= true then
            L[joint].fired = true
            learnDirty = true
        end
    end
end

-- triggerHeld: right trigger down (raw, before any suppression); reloading: the game's reload is playing;
-- idle: the manual reload state machine is idle (nothing paused / fast-forwarded); weaponMesh: the weapon in
-- hands if the caller already has it (gameState._frameWeapon, the same component), else looked up here.
function M.learnTick(delta, triggerHeld, reloading, idle, weaponMesh)
    local now = os.clock()
    local wm = weaponMesh or resolveWeapon()
    if wm == nil then return end
    local wAddr = objAddr(wm)
    local asset = nil
    pcall(function() asset = wm.SkeletalMesh end)
    local aName = asset and assetName(asset) or nil
    if wAddr ~= learnWeaponAddr or aName ~= learnAssetName then
        learnWeaponAddr, learnAssetName = wAddr, aName
        equipAt = now
    end
    if aName == nil or doneByName[aName] then return end   -- fully learned: nothing to do
    local info = weaponInfo(wm)
    if info == nil then return end
    if learnedComplete(info) then
        doneByName[aName] = true
        return
    end
    if triggerHeld then lastTriggerAt = now end

    local firing = (now - lastTriggerAt) < FIRE_WINDOW_S
    local moving = firing or reloading
    local stillIdle = idle and not reloading and (now - lastTriggerAt) > IDLE_AFTER_FIRE_S
        and (now - equipAt) > IDLE_AFTER_EQUIP_S
    if moving then
        learnJoint(wm, info.meshName, info.driveJoint, false, true)
        learnJoint(wm, info.meshName, info.boltJoint, false, true)
        if firing and not reloading then countFiring(info) end
    elseif stillIdle and now >= nextIdleSample then
        nextIdleSample = now + IDLE_SAMPLE_S
        learnJoint(wm, info.meshName, info.driveJoint, true, false)
        learnJoint(wm, info.meshName, info.boltJoint, true, false)
        learnCosmetics(wm, info)
    end

    if learnDirty and now >= nextSaveAt then
        nextSaveAt = now + SAVE_EVERY_S
        learnDirty = false
        pcall(function()
            Config:markDirty()
            Config:save()
        end)
    end
end

-- ---------------------------------------------------------------------------------------
-- The rack
-- ---------------------------------------------------------------------------------------
-- nil when not racking, else {
--   weaponAddr, wm, parts = {{component, base = {x,y,z}}}, grabComponent,
--   dMax, dRelease, phase = "waiting" | "pulling" | "returning" | "springback" | "done",
--   d, startDist, full, fromD, toD, phaseAt, phaseTime }
local rack = nil

local function receiverFrame(wm)
    local anchor, axis = nil, nil
    pcall(function()
        local l = wm:GetSocketLocation(fname(RECEIVER_JOINT))
        local r = wm:GetSocketRotation(fname(RECEIVER_JOINT))
        local fwd = quat.rotate(quat.fromRotator(r.Pitch, r.Yaw, r.Roll), 1, 0, 0)
        anchor = { x = l.X, y = l.Y, z = l.Z }
        axis = { x = -fwd.x, y = -fwd.y, z = -fwd.z }   -- racking direction (toward the stock)
    end)
    return anchor, axis
end

local function pullDistance(wm)
    local ctrl = controllers.getControllerLocation(Handed.Left)
    if ctrl == nil then return nil end
    local anchor, axis = receiverFrame(wm)
    if anchor == nil then return nil end
    return (ctrl.X - anchor.x) * axis.x + (ctrl.Y - anchor.y) * axis.y + (ctrl.Z - anchor.z) * axis.z
end

local function applyOffset(d)
    for _, part in ipairs(rack.parts) do
        pcall(function()
            part.component:K2_SetRelativeLocation(uevrUtils.vector(part.base.x - d, part.base.y, part.base.z),
                false, reusable_hit_result, false)
        end)
    end
end

local function haptic(hand, duration, amplitude)
    pcall(function() uevrUtils.triggerHapticVibration(hand, 0, duration, 1000, amplitude) end)
end

-- ---------------------------------------------------------------------------------------
-- Left hand on the grab part while pulling. libs/hands attachHandToMesh takes a GLOVE offset (glove
-- component origin relative to the parent); gloves parent to the part with it, IK (ik_arms delegate)
-- targets the arm at part * offset converted for the rig. hands.getHandAttachParent is that glove-origin
-- frame in both modes, so its transform relative to the part at grab time keeps the hand exactly where
-- it is - no per-weapon offsets. The pull still reads the controller; only the drawn hand rides the part.
-- ---------------------------------------------------------------------------------------
local handAttached = false

local function attachHand()
    local ok, err = pcall(function()
        local hands = require("libs/hands")
        local anchor = hands.getHandAttachParent(Handed.Left)
        if anchor == nil then return end
        local part = rack.grabComponent
        local pl, pr = part:K2_GetComponentLocation(), part:K2_GetComponentRotation()
        local gl, gr = anchor:K2_GetComponentLocation(), anchor:K2_GetComponentRotation()
        local partInv = quat.inv(quat.fromRotator(pr.Pitch, pr.Yaw, pr.Roll))
        local loc = quat.rotate(partInv, gl.X - pl.X, gl.Y - pl.Y, gl.Z - pl.Z)
        local p, y, r = quat.toRotator(quat.mul(partInv, quat.fromRotator(gr.Pitch, gr.Yaw, gr.Roll)))
        hands.attachHandToMesh(Handed.Left, part, "None", { p, y, r }, { loc.x, loc.y, loc.z })
        handAttached = true
    end)
    if not ok then print("[RackSlide] Hand attach failed: " .. tostring(err)) end
end

-- Back to the controller with the usual support-hand glide.
local function detachHand()
    if not handAttached then return end
    handAttached = false
    pcall(function()
        require("libs/hands").attachHandToControllerBlended(Handed.Left, Config.supportHandBlendTime)
    end)
end

-- true when this weapon wants a rack after a reload of the given kind
function M.shouldRack(weaponMesh, reloadWasEmpty)
    if not reloadWasEmpty or weaponMesh == nil then return false end
    local info = weaponInfo(weaponMesh)
    return info ~= nil and M.categoryEnabled(info)
end

-- Sets up the rack on the held weapon (paused native reload). false = this weapon cannot be racked.
function M.begin(weaponMesh)
    if rack ~= nil then M.finish(rack.weaponAddr == objAddr(weaponMesh)) end   -- a settle still running
    local info = weaponInfo(weaponMesh)
    if info == nil then return false end
    local parts = scanParts(weaponMesh)
    local grab = nil
    for _, part in ipairs(parts) do
        if part.socket == info.grabJoint and endsWith(part.key, info.grabEnding) then grab = part end
    end
    if grab == nil then return false end

    local L = learnedFor(info.meshName)
    local gl = L[info.driveJoint] or {}
    local curX = jointX(weaponMesh, info.driveJoint)
    if curX == nil then return false end
    local rest = info.openBolt and gl.idleMin or gl.idleMax
    if rest == nil then rest = curX end

    -- how far back from where the part sits now
    local stroke = (gl.minX ~= nil) and (curX - gl.minX) or 0
    local boltLocked = false
    if info.boltJoint ~= nil then
        local bl = L[info.boltJoint] or {}
        local boltX = jointX(weaponMesh, info.boltJoint)
        if boltX ~= nil and bl.idleMax ~= nil then
            local boltLock = bl.idleMax - boltX
            if boltLock > LOCKED_CM then
                boltLocked = true
                -- a handle that never moves with the bolt (AR416, Arev) travels as far as the bolt is open
                if info.grabIsHandle and stroke < LOCKED_CM then stroke = boltLock end
            end
        end
    end
    local lockedBack = (rest - curX) > LOCKED_CM
    if stroke < LOCKED_CM and not lockedBack and not boltLocked then
        stroke = DEFAULT_STROKE_CM[info.category] or 8.0   -- nothing learned yet for a closed action
    end
    local dMax = math.max(stroke, MIN_PULL_CM)
    -- where the part settles on release, measured back from now: closed / locked actions return to where
    -- they are (the reload fast-forward closes a locked one); an open bolt stays at its cocked rest
    local dRelease = math.max(0, curX - rest)
    if dRelease > dMax then dRelease = dMax end
    -- pistols locked open with a learned closed rest: the slide slams fully home (negative = forward of now)
    -- and is held there until the game's closing animation catches up (see M.complete)
    local slam = info.category == "pistol" and lockedBack and gl.idleMax ~= nil
    if slam then dRelease = curX - rest end

    -- parts moving with the grab part: everything on or under the drive joint, plus a bolt that is not locked open
    local moving = { grab }
    for _, part in ipairs(parts) do
        if part ~= grab then
            local onDrive = part.socket == info.driveJoint or isUnder(weaponMesh, part.socket, info.driveJoint)
            local looseBolt = info.grabIsHandle and not boltLocked and part.socket == info.boltJoint
            if onDrive or looseBolt then table.insert(moving, part) end
        end
    end
    local entries = {}
    for _, part in ipairs(moving) do
        pcall(function()
            local r = part.component.RelativeLocation
            table.insert(entries, { component = part.component, base = { x = r.X, y = r.Y, z = r.Z } })
        end)
    end
    if #entries == 0 then return false end

    -- slide stop / tilting barrel parts with a learned rest pose (slam pistols only)
    local cosmetics = {}
    if slam then
        for _, spec in ipairs({ { joint = info.stopJoint, kind = "stop" }, { joint = info.barrelJoint, kind = "barrel" } }) do
            local idle = spec.joint and (L[spec.joint] or {}).idlePose
            if type(idle) == "table" and type(idle.t) == "table" and type(idle.q) == "table" then
                for _, part in ipairs(parts) do
                    if part.socket == spec.joint then
                        pcall(function()
                            local l, r = part.component.RelativeLocation, part.component.RelativeRotation
                            table.insert(cosmetics, {
                                kind = spec.kind, joint = spec.joint, component = part.component, idle = idle,
                                baseLoc = { x = l.X, y = l.Y, z = l.Z },
                                baseRot = { p = r.Pitch, y = r.Yaw, r = r.Roll },
                                rel = { q = quat.fromRotator(r.Pitch, r.Yaw, r.Roll), t = { x = l.X, y = l.Y, z = l.Z } },
                                alpha = 0,
                            })
                        end)
                    end
                end
            end
        end
    end

    local asset = nil
    pcall(function() asset = weaponMesh.SkeletalMesh end)
    rack = {
        weaponAddr = objAddr(weaponMesh), assetAddr = objAddr(asset), wm = weaponMesh, parts = entries,
        grabComponent = grab.component, driveJoint = info.driveJoint, rest = rest,
        dMax = dMax, dRelease = dRelease, phase = "waiting", d = 0, full = false,
        slam = slam, lockCm = rest - curX, cosmetics = cosmetics, stopA = 0, frameAt = os.clock(),
    }
    return true
end

-- A cosmetic part shown alpha of the way from its animated pose (0) to its learned rest pose (1). Recomputed
-- against the joint's LIVE local transform, so it stays at rest while the game animation moves the joint:
-- part relative' = relative * idle * inverse(current)  =>  world = relative * idle * parent.
local function setCosmetic(c, alpha)
    if alpha <= 0 and c.alpha <= 0 then return end
    c.alpha = alpha
    pcall(function()
        if alpha <= 0 then
            c.component:K2_SetRelativeLocationAndRotation(uevrUtils.vector(c.baseLoc.x, c.baseLoc.y, c.baseLoc.z),
                uevrUtils.rotator(c.baseRot.p, c.baseRot.y, c.baseRot.r), false, reusable_hit_result, false)
            return
        end
        local cur = jointLocal(rack.wm, c.joint)
        if cur == nil then return end
        local target = tCompose(tCompose(c.rel, c.idle), tInverse(cur))
        local b = c.rel.t
        local q = quat.slerp(c.rel.q, target.q, alpha)
        local p, y, r = quat.toRotator(q)
        c.component:K2_SetRelativeLocationAndRotation(
            uevrUtils.vector(b.x + (target.t.x - b.x) * alpha, b.y + (target.t.y - b.y) * alpha, b.z + (target.t.z - b.z) * alpha),
            uevrUtils.rotator(p, y, r), false, reusable_hit_result, false)
    end)
end

local function restoreCosmetics()
    for _, c in ipairs(rack.cosmetics) do
        c.alpha = math.max(c.alpha, 0.001)   -- force the write
        setCosmetic(c, 0)
    end
end

-- Slide stop: drops past the lock while pulling, re-engages on a springback, stays down once racked.
-- Barrel: locks up with the slide's progress from the lock to closed.
local function updateCosmetics(dt)
    if #rack.cosmetics == 0 then return end
    local phase = rack.phase
    local stopTarget = 1
    if phase == "waiting" or phase == "springback" then
        stopTarget = 0
    elseif phase == "pulling" then
        stopTarget = (rack.d >= math.min(STOP_TRIP_CM, rack.dMax * 0.5)) and 1 or 0
    end
    local step = dt / STOP_MOVE_S
    if rack.stopA < stopTarget then rack.stopA = math.min(stopTarget, rack.stopA + step)
    elseif rack.stopA > stopTarget then rack.stopA = math.max(stopTarget, rack.stopA - step) end

    local barrelA = 0
    if phase == "returning" then
        barrelA = (rack.lockCm > 0) and math.max(0, math.min(1, -rack.d / rack.lockCm)) or 1
    elseif phase == "done" or phase == "settle" then
        barrelA = 1
    end
    for _, c in ipairs(rack.cosmetics) do
        setCosmetic(c, c.kind == "stop" and rack.stopA or barrelA)
    end
end

function M.isActive() return rack ~= nil end
function M.isGripping() return rack ~= nil and rack.phase == "pulling" end
function M.isDone() return rack ~= nil and rack.phase == "done" end

-- Left grip pressed: grab when the controller is close enough to the grab part.
function M.tryGrab()
    if rack == nil or rack.phase ~= "waiting" then return false end
    local ok = false
    pcall(function()
        local ctrl = controllers.getControllerLocation(Handed.Left)
        local p = rack.grabComponent:K2_GetComponentLocation()
        if ctrl == nil or p == nil then return end
        local dx, dy, dz = ctrl.X - p.X, ctrl.Y - p.Y, ctrl.Z - p.Z
        if math.sqrt(dx * dx + dy * dy + dz * dz) > grabRadius() then return end
        local dist = pullDistance(rack.wm)
        if dist == nil then return end
        rack.startDist = dist
        rack.d = 0
        rack.full = false
        rack.phase = "pulling"
        ok = true
    end)
    if ok then
        attachHand()
        haptic(Handed.Left, 0.02, 0.4)
    end
    return ok
end

local function startPhase(phase, toD, time)
    rack.phase = phase
    rack.fromD = rack.d
    rack.toD = toD
    rack.phaseAt = os.clock()
    rack.phaseTime = time
end

-- Left grip released: a full pull racks it, a short one springs back for another try.
function M.release()
    if rack == nil or rack.phase ~= "pulling" then return end
    detachHand()
    if rack.full then
        startPhase("returning", rack.dRelease, RETURN_TIME_S)
        haptic(Handed.Right, 0.06, 1.0)
    else
        startPhase("springback", 0, SPRINGBACK_TIME_S)
    end
end

-- Slide release (pistols, left X): instead of racking, drop the slide off the slide stop - same result as a
-- full rack (stop down, slide slams home, barrel locks up, then complete). Only from a locked-open pistol
-- with a learned closed rest (the slam case), and only while the hand is not on the slide.
function M.canSlideRelease()
    return rack ~= nil and rack.slam == true and rack.phase == "waiting"
end

function M.slideRelease()
    if not M.canSlideRelease() then return false end
    detachHand()
    rack.full = true
    rack.d = 0
    startPhase("returning", rack.dRelease, RETURN_TIME_S)
    haptic(Handed.Right, 0.06, 1.0)
    return true
end

-- Restores the parts (only when they still belong to the held weapon) and forgets the rack.
-- restore = false after a weapon switch / level change: the old parts may already be gone.
function M.finish(restore)
    detachHand()   -- always: an attached hand must leave a part that is about to be recycled
    if rack ~= nil and restore then
        applyOffset(0)
        restoreCosmetics()
    end
    rack = nil
end

-- Racked (phase "done"), the reload is about to complete. A slammed pistol slide keeps being held at its
-- closed rest - stop down, barrel up - while the completion's fast-forwarded animation closes the real bones;
-- the post-stereo "settle" phase lets go once they arrive. Everything else restores now, as before.
function M.complete()
    detachHand()
    if rack == nil then return end
    if rack.slam then
        rack.phase = "settle"
        rack.phaseAt = os.clock()
        return
    end
    M.finish(true)
end

function M.weaponAddr() return rack and rack.weaponAddr or nil end

-- World references and asset addresses die with the level: forget, never touch.
function M.onLevelChange()
    rack = nil
    handAttached = false   -- hands / ik drop their own attach state with the level
    infoCache = {}
    infoRetryAt = {}
    doneByName = {}
    learnWeaponAddr, learnAssetName = nil, nil
end

-- Dev panel "Forget learned rack travel": every weapon relearns from scratch.
function M.forgetLearned()
    Config.rackLearned = {}
    doneByName = {}
    firedTicks = {}
    pcall(function()
        Config:markDirty()
        Config:save()
    end)
end

-- Post-stereo: the left controller and the weapon only hold this frame's poses here.
uevrUtils.registerPostCalculateStereoViewCallback(function(device, view_index)
    if rack == nil or view_index ~= 0 then return end
    local now = os.clock()
    local dt = now - (rack.frameAt or now)
    rack.frameAt = now
    if rack.phase == "settle" then
        -- the reload has completed (ptm is idle): same weapon and parts still? otherwise forget, never touch
        local wm = resolveWeapon()
        local asset = nil
        pcall(function() asset = wm and wm.SkeletalMesh end)
        if objAddr(wm) ~= rack.weaponAddr or objAddr(asset) ~= rack.assetAddr then
            rack = nil
            return
        end
        local x = jointX(rack.wm, rack.driveJoint)
        if x == nil or math.abs(x - rack.rest) <= SETTLE_TOL_CM or (now - rack.phaseAt) > SETTLE_MAX_S then
            M.finish(true)   -- the game's bones are closed (or we stop waiting): offsets off
            return
        end
        rack.d = x - rack.rest   -- hold the slide at its closed rest over the animated bone
        applyOffset(rack.d)
        updateCosmetics(dt)
        return
    end
    updateCosmetics(dt)
    if rack.phase == "pulling" then
        local dist = pullDistance(rack.wm)
        if dist == nil then return end
        local d = dist - rack.startDist
        if d < 0 then d = 0 elseif d > rack.dMax then d = rack.dMax end
        rack.d = d
        applyOffset(d)
        if not rack.full and d >= rack.dMax * FULL_PULL_FRACTION then
            rack.full = true
            haptic(Handed.Left, 0.04, 0.8)
        end
    elseif rack.phase == "returning" or rack.phase == "springback" then
        local t = (os.clock() - rack.phaseAt) / rack.phaseTime
        if t >= 1 then
            rack.d = rack.toD
            applyOffset(rack.d)
            rack.phase = (rack.phase == "returning") and "done" or "waiting"
            return
        end
        local e = (rack.phase == "returning") and (t * t) or (1 - (1 - t) ^ 2)
        rack.d = rack.fromD + (rack.toD - rack.fromD) * e
        applyOffset(rack.d)
    end
end)

return M
