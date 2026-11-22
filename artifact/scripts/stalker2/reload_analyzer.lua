-- reload_analyzer.lua
-- Learns the manual-reload hand poses from the game's own reload animations (the OW2 method).
--
-- The first native reload of each reload montage (keyed by the char montage name, so tactical / empty and
-- every magazine variant learn on their own) is NOT caught by ptm_manual_reload: it plays out natively while
-- this module records every frame:
--   * every weapon rig bone (world), the rig carries the game's own jnt_l_hand / jnt_r_hand targets and the
--     carried item bones (jnt_magazine1 = the fresh mag on the AK, shells, the loader, the rocket ...);
--   * the game arms (pawn.Mesh, same skeleton as the VR hands): jnt_l_hand / jnt_r_hand (world) and every
--     finger bone local to its parent (the convention hands.setHandPose uses);
--   * the weapon's static parts: mesh, socket, relative transform, visibility.
-- At the end the record is analysed into a profile (see analyse()) and saved to data/manual_reload_learned.json.
--
-- API (_G.stalkerReloadAnalyzer): wantsReload(montageName), begin(montage, montageName), isRecording(),
--   getProfile(montageName), relearn(), profiles.

local uevrUtils = require("libs/uevr_utils")
local reloadLearn = require("stalker2.reload_learn")
local rackSlide = require("stalker2.rack_slide")

local M = {}

-- Dev: write every recorded frame to data/reload_frames_<montage>.json. OFF for release.
local DUMP_FRAMES = false
local DATA_FILE = "manual_reload_learned.json"
local MAX_FRAMES = 1200      -- ~20 s at 60 fps
local MAX_SECONDS = 20.0
local END_TAIL_S = 0.15      -- keep recording this long after the char montage stops

local profiles = nil         -- [montageName] = profile
local rec = nil              -- active recording
local relearnPending = {}    -- [montageName] = true

local function log(msg)
    pcall(function() uevr.params.functions.log_info("[ReloadAnalyzer] " .. msg) end)
end

local fnames = {}
local function fname(s)
    if fnames[s] == nil then fnames[s] = uevrUtils.fname_from_string(s) end
    return fnames[s]
end

local function isAlive(obj)
    if obj == nil then return false end
    local ok, v = pcall(function() return UEVR_UObjectHook.exists(obj) end)
    return ok and v == true
end

local function r4(v) return math.floor(v * 10000 + 0.5) / 10000 end

-- transform -> compact {x, y, z, qw, qx, qy, qz}
local function packT(tr)
    local t, q = tr.Translation, tr.Rotation
    return { r4(t.X), r4(t.Y), r4(t.Z), r4(q.W), r4(q.X), r4(q.Y), r4(q.Z) }
end

-- ---------------------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------------------
local function load()
    if profiles ~= nil then return end
    profiles = {}
    pcall(function()
        local t = json.load_file(DATA_FILE)
        if type(t) == "table" and type(t.profiles) == "table" then profiles = t.profiles end
    end)
    -- A saved failure is kept: it is a genuine "nothing to learn" (frozen / paused recordings are discarded, never
    -- saved), and dropping it made every session hand one reload of that montage back to the flat animation just to
    -- fail again (2.8: AR416 MG_fp_m16_reload*). Re-learn in Manual Reload Settings retries it.
    for name, p in pairs(profiles) do
        if type(p) ~= "table" then profiles[name] = nil end
    end
end

local function save()
    pcall(function() json.dump_file(DATA_FILE, { version = 1, profiles = profiles }, 1) end)
end

-- ---------------------------------------------------------------------------------------
-- Recording
-- ---------------------------------------------------------------------------------------
local function resolve()
    local pawn, wm, arms = nil, nil, nil
    pcall(function()
        pawn = uevr.api:get_local_pawn(0)
        arms = pawn and pawn.Mesh or nil
        local iac = pawn and pawn.ItemAppearanceComponent or nil
        wm = iac and iac.WeaponMeshInHands or nil
    end)
    return pawn, wm, arms
end

local function boneNames(mesh, filter)
    local out = {}
    pcall(function()
        local n = mesh:GetNumBones()
        for i = 0, n - 1 do
            local name = mesh:GetBoneName(i):to_string()
            if filter == nil or filter(name) then table.insert(out, name) end
        end
    end)
    return out
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
                local l, r = child.RelativeLocation, child.RelativeRotation
                table.insert(parts, {
                    comp = child,
                    mesh = mesh:get_full_name(),
                    socket = child.AttachSocketName:to_string(),
                    loc = { r4(l.X), r4(l.Y), r4(l.Z) },
                    rot = { r4(r.Pitch), r4(r.Yaw), r4(r.Roll) },
                })
            end)
        end
    end)
    return parts
end

function M.begin(montage, montageName)
    load()
    local pawn, wm, arms = resolve()
    if wm == nil or arms == nil then return false end
    -- never learn from paused meshes (a caught reload left paused): every frame would be the same pose
    local paused = false
    pcall(function() paused = arms.bPauseAnims == true or wm.bPauseAnims == true end)
    if paused then
        log("not recording " .. tostring(montageName) .. ": animations are paused")
        return false
    end
    local rigName = nil
    pcall(function() rigName = wm.SkeletalMesh:get_fname():to_string() end)
    local animInst = nil
    pcall(function() animInst = arms.AnimScriptInstance end)
    local fingerFilter = function(n)
        return (string.find(n, "^jnt_l_hand_") or string.find(n, "^jnt_r_hand_")) ~= nil
    end
    rec = {
        montageName = montageName, rig = rigName, montage = montage, animInst = animInst,
        wm = wm, arms = arms, wmAddr = wm:get_address(),
        weaponBones = boneNames(wm),
        fingerBones = boneNames(arms, fingerFilter),
        parts = scanParts(wm),
        rackJoint = rackSlide.getGrabJoint(wm),
        frames = {}, t = 0, startClock = os.clock(), stoppedAt = nil,
    }
    pcall(function() rec.montageLength = montage:GetPlayLength() end)
    for _, b in ipairs(rec.fingerBones) do
        pcall(function() rec.fingerParents = rec.fingerParents or {}; rec.fingerParents[b] = arms:GetParentBone(fname(b)):to_string() end)
    end
    log(string.format("recording %s (rig %s, %d weapon bones, %d finger bones, %d parts)", tostring(montageName),
        tostring(rigName), #rec.weaponBones, #rec.fingerBones, #rec.parts))
    return true
end

local function recordFrame()
    local wm, arms = rec.wm, rec.arms
    if not isAlive(wm) or not isAlive(arms) then rec.aborted = "mesh gone"; return false end
    local f = { t = r4(os.clock() - rec.startClock) }
    pcall(function() f.mp = r4(rec.animInst:Montage_GetPosition(rec.montage)) end)
    local wb = {}
    for _, b in ipairs(rec.weaponBones) do
        pcall(function() wb[b] = packT(wm:GetSocketTransform(fname(b), 0)) end)
    end
    f.w = wb
    local ab = {}
    pcall(function() ab.jnt_l_hand = packT(arms:GetSocketTransform(fname("jnt_l_hand"), 0)) end)
    pcall(function() ab.jnt_r_hand = packT(arms:GetSocketTransform(fname("jnt_r_hand"), 0)) end)
    f.a = ab
    local fl = {}
    for _, b in ipairs(rec.fingerBones) do
        pcall(function() fl[b] = packT(arms:GetSocketTransform(fname(b), 3)) end)
    end
    f.f = fl
    local vis = {}
    for i, p in ipairs(rec.parts) do
        local v = nil
        pcall(function() v = p.comp:IsVisible() and not p.comp.bHiddenInGame end)
        vis[i] = v and 1 or 0
    end
    f.v = vis
    table.insert(rec.frames, f)
    return true
end

local function montagePlaying()
    local playing = false
    pcall(function() playing = rec.animInst:Montage_IsPlaying(rec.montage) end)
    return playing
end

local function finish(reason)
    local r = rec
    rec = nil
    if r == nil then return end
    log(string.format("recording %s ended (%s): %d frames, %.2f s", tostring(r.montageName), reason, #r.frames,
        r.frames[#r.frames] and r.frames[#r.frames].t or 0))
    if r.aborted or #r.frames < 10 then return end
    -- a frozen record (nothing moved: paused or stalled animation) teaches nothing and is not saved as a failure
    do
        local a, b = r.frames[1].w, r.frames[#r.frames].w
        local moved = false
        for _, f in ipairs(r.frames) do
            local h0, h = a.jnt_l_hand, f.w.jnt_l_hand
            local o0, o = a.jnt_offset, f.w.jnt_offset
            if h0 and h and o0 and o then
                local dh = math.abs((h[1] - o[1]) - (h0[1] - o0[1])) + math.abs((h[2] - o[2]) - (h0[2] - o0[2]))
                    + math.abs((h[3] - o[3]) - (h0[3] - o0[3]))
                if dh > 2 then moved = true; break end
            end
        end
        if not moved then
            log("recording " .. tostring(r.montageName) .. " discarded: nothing moved (paused / frozen animation)")
            return
        end
    end
    local partsOut = {}
    for i, p in ipairs(r.parts) do partsOut[i] = { mesh = p.mesh, socket = p.socket, loc = p.loc, rot = p.rot } end
    if DUMP_FRAMES then
        local safe = string.gsub(tostring(r.montageName), "[^%w_%-]", "_")
        pcall(function()
            json.dump_file("reload_frames_" .. safe .. ".json", {
                montageName = r.montageName, rig = r.rig, montageLength = r.montageLength,
                weaponBones = r.weaponBones, fingerBones = r.fingerBones, fingerParents = r.fingerParents,
                parts = partsOut, frames = r.frames,
            }, 0)
        end)
    end
    local ok, prof, why = pcall(reloadLearn.analyse, {
        rig = r.rig, weaponBones = r.weaponBones, frames = r.frames, parts = partsOut, rackJoint = r.rackJoint })
    if ok and type(prof) == "table" then
        prof.montage = r.montageName
        profiles[r.montageName] = prof
        relearnPending[r.montageName] = nil
        save()
        log(string.format("learned %s: item %s, rack %s", tostring(r.montageName),
            prof.item and prof.item.bone or "-", prof.rack and prof.rack.joint or "-"))
    else
        -- nothing usable: remember that, so the reload is not held back for learning again
        profiles[r.montageName] = { version = 1, rig = r.rig, montage = r.montageName, failed = tostring(ok and why or prof) }
        relearnPending[r.montageName] = nil
        save()
        log("nothing learned from " .. tostring(r.montageName) .. ": " .. tostring(ok and why or prof))
    end
end

-- Post-stereo, view 0: after the world tick, so the frame's animation is in.
uevrUtils.registerPostCalculateStereoViewCallback(function(device, view_index)
    if rec == nil or view_index ~= 0 then return end
    local _, wm = resolve()
    if wm == nil or wm:get_address() ~= rec.wmAddr then finish("weapon changed"); return end
    if not recordFrame() then finish(rec.aborted or "error"); return end
    local t = os.clock() - rec.startClock
    if #rec.frames >= MAX_FRAMES or t > MAX_SECONDS then finish("limit"); return end
    if not montagePlaying() then
        rec.stoppedAt = rec.stoppedAt or os.clock()
        if os.clock() - rec.stoppedAt > END_TAIL_S then finish("montage ended") end
    else
        rec.stoppedAt = nil
    end
end)

-- ---------------------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------------------
function M.isRecording() return rec ~= nil end

-- true: let this native reload play out and learn from it
function M.wantsReload(montageName)
    if rec ~= nil or type(montageName) ~= "string" or montageName == "" then return false end
    load()
    return profiles[montageName] == nil or relearnPending[montageName] == true
end

function M.getProfile(montageName)
    load()
    return montageName and profiles[montageName] or nil
end

-- Any learned profile of this weapon rig that has `need` ("item" / "rack"; nil = either). Used before a reload of
-- this weapon was caught (hip grab of a tube-fed shell, the pouch) or when the played montage taught nothing.
function M.findForRig(rig, need)
    load()
    local best = nil
    for _, p in pairs(profiles) do
        if p.rig == rig and not p.failed and (need == nil or p[need] ~= nil) then
            -- prefer a tactical record (the plain mag swap) for the item
            if best == nil or (need == "item" and string.find(string.lower(p.montage or ""), "tactical", 1, true)) then best = p end
        end
    end
    return best
end

-- Re-learn the given montage, or every one when nil.
function M.relearn(montageName)
    load()
    if montageName then
        relearnPending[montageName] = true
    else
        for name in pairs(profiles) do relearnPending[name] = true end
    end
end

function M.profiles() load(); return profiles end

_G.stalkerReloadAnalyzer = M
return M
