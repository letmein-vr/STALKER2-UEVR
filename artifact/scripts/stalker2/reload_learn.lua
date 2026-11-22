-- reload_learn.lua
-- Pure analysis of a recorded native reload (reload_analyzer.lua) into manual-reload hand poses. No UE calls, so it
-- also runs offline on a data/reload_frames_*.json dump.
--
-- Input record: { weaponBones = {names}, frames = { {t, w = {bone = packed}, a = {jnt_l_hand, jnt_r_hand},
--   f = {fingerBone = packed (local to parent)}, v = {...}} }, parts = { {mesh, socket, loc, rot} }, rackJoint = name|nil }
-- packed transform = {x, y, z, qw, qx, qy, qz} (world, or parent-local for fingers).
--
-- Output profile:
--   item  = { bone, mesh, meshLoc, meshRot, grip = T (game jnt_l_hand in the item bone), t0, t1, travel }
--   fingers = { [bone] = {pitch, yaw, roll} }   the left fingers while carrying the item (hands.setHandPose format)
--   rack  = { joint, grip = T (jnt_l_hand in the rack joint), fingers, t, pull } | nil
-- T = { t = {x,y,z}, q = {w,x,y,z} } in UE compose order.

local quat = require("libs/core/quat_math")

local M = {}

-- carry window: the hand-in-bone transform stays within these of the window's first frame
local CARRY_POS_CM = 0.8
local CARRY_ANG_DEG = 5.0
local CARRY_MIN_S = 0.25
local CARRY_MIN_TRAVEL_CM = 5.0   -- the bone must move this far in the receiver over the window (parked parts don't count)
local RACK_HAND_CM = 25.0         -- the hand must be this close to the rack joint while it is pulled
local RACK_MIN_PULL_CM = 1.0
local RELEASE_LOOKBACK_S = 0.5    -- slingshot release: where the hand held the locked-back part before letting go
local RELEASE_MAX_STEP = 1.5      -- ... and how still it must have been (cm + deg/10 per frame)
local SKIP_BONES = { jnt_offset = true, jnt_l_hand = true, jnt_r_hand = true }
local RECEIVER = "jnt_offset"
-- the finger bones the hand-pose system models (the _meta bones stay at the mesh pose, see hands_parameters.json)
local FINGERS = { "thumb", "index", "middle", "ring", "pinky" }

local function T(p) return { t = { x = p[1], y = p[2], z = p[3] }, q = { w = p[4], x = p[5], y = p[6], z = p[7] } } end
local function compose(a, b)
    local r = quat.rotate(b.q, a.t.x, a.t.y, a.t.z)
    return { q = quat.mul(b.q, a.q), t = { x = r.x + b.t.x, y = r.y + b.t.y, z = r.z + b.t.z } }
end
local function inverse(a)
    local qi = quat.inv(a.q)
    local r = quat.rotate(qi, a.t.x, a.t.y, a.t.z)
    return { q = qi, t = { x = -r.x, y = -r.y, z = -r.z } }
end
local function relative(a, b) return compose(a, inverse(b)) end   -- a expressed in b
local function dist(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end
local function angle(qa, qb)
    local d = math.abs(qa.w * qb.w + qa.x * qb.x + qa.y * qb.y + qa.z * qb.z)
    if d > 1 then d = 1 end
    return math.deg(2 * math.acos(d))
end
local function r3(v) return math.floor(v * 1000 + 0.5) / 1000 end
local function r6(v) return math.floor(v * 1e6 + 0.5) / 1e6 end
local function packOut(x)
    return { t = { x = r3(x.t.x), y = r3(x.t.y), z = r3(x.t.z) },
             q = { w = r6(x.q.w), x = r6(x.q.x), y = r6(x.q.y), z = r6(x.q.z) } }
end
M.compose, M.inverse, M.relative = compose, inverse, relative

local function fingerBoneList(side)
    local out = {}
    for _, f in ipairs(FINGERS) do
        for i = 1, 3 do table.insert(out, string.format("jnt_%s_hand_%s_%02d", side, f, i)) end
    end
    return out
end
M.leftFingerBones = fingerBoneList("l")

local function fingersAt(frame, side)
    local out = {}
    for _, b in ipairs(fingerBoneList(side)) do
        local p = frame.f and frame.f[b]
        if p then
            local pitch, yaw, roll = quat.toRotator({ w = p[4], x = p[5], y = p[6], z = p[7] })
            out[b] = { r3(pitch), r3(yaw), r3(roll) }
        end
    end
    return out
end
M.fingersAt = fingersAt

-- per frame: receiver, hand and every bone in the receiver frame.
-- The hand is the weapon rig's own jnt_l_hand: the authored "left hand on the gun" target, animated by the same
-- weapon montage as the mag / slide, so it is consistent with them. Rifles IK the arms onto it (AK74: arms hand =
-- rig hand, 0 cm / <1.5 deg); pistols animate the arms on their own, 2-12 cm and ~32 deg off it, with the hand
-- drifting along the mag (UDP), while the rig hand holds the mag dead still. The arms hand is the fallback.
local function prepare(rec)
    local out = {}
    for i, f in ipairs(rec.frames) do
        local R = f.w[RECEIVER] and T(f.w[RECEIVER])
        local hp = (f.w and f.w.jnt_l_hand) or (f.a and f.a.jnt_l_hand)
        local rp = (f.w and f.w.jnt_r_hand) or (f.a and f.a.jnt_r_hand)
        local H = hp and T(hp)
        if R and H then
            local fr = { i = i, t = f.t, raw = f, hand = relative(H, R), bones = {} }
            fr.handL = fr.hand
            fr.handR = rp and relative(T(rp), R) or nil
            for _, b in ipairs(rec.weaponBones) do
                if f.w[b] then fr.bones[b] = relative(T(f.w[b]), R) end
            end
            table.insert(out, fr)
        end
    end
    return out
end

-- A bone that carries the magazine: its part mesh or its name says so. Breaks near-ties in favour of the mag over a
-- round riding on it (D12: jnt_bullet on the mag ends its carry with jnt_clip_base).
local function isMagBone(rec, bone)
    local lb = string.lower(bone)
    if string.find(lb, "mag", 1, true) or string.find(lb, "clip", 1, true) then return true end
    for _, p in ipairs(rec.parts or {}) do
        if p.socket == bone and string.find(string.lower(p.mesh or ""), "mag", 1, true) then return true end
    end
    return false
end

-- Candidate ordering: the carry that ends LAST wins (the fresh item goes in at the end of the reload); within
-- ITEM_TIE_S the mag bone, then the longer travel.
local ITEM_TIE_S = 0.15
local function better(a, b)
    if b == nil then return true end
    if math.abs(a.endT - b.endT) > ITEM_TIE_S then return a.endT > b.endT end
    if a.mag ~= b.mag then return a.mag end
    return a.w.travel > b.w.travel
end

-- Mirror a right-hand transform in an item / part frame onto the left hand. The arms skeleton is a behaviour mirror
-- (MCP 2026-11-21: jnt_l_hand / jnt_r_hand and every finger have equal local rotations and negated translations), so
-- left = M * right * F with M = the Y reflection (the gun's side axis) and F = -I:
--   position (x, -y, z); rotation = (M R M) * (M F) = q(w, -x, y, -z) * 180 deg about Y.
local Q_Y180 = { w = 0, x = 0, y = 1, z = 0 }
local function mirrorToLeft(g)
    return { t = { x = g.t.x, y = -g.t.y, z = g.t.z }, q = quat.mul({ w = g.q.w, x = -g.q.x, y = g.q.y, z = -g.q.z }, Q_Y180) }
end
M.mirrorToLeft = mirrorToLeft

-- longest-travel steady carry windows of `bone` by the hand frames[i][hk]; returns a list of { s, e, travel }
local function carryWindows(frames, bone, hk)
    local wins = {}
    local i = 1
    while i <= #frames do
        local b0 = frames[i].bones[bone]
        if not b0 then i = i + 1 else
            local g0 = frames[i][hk] and relative(frames[i][hk], b0)
            if g0 == nil then i = i + 1; goto continue end
            local j = i
            while j + 1 <= #frames do
                local b, h = frames[j + 1].bones[bone], frames[j + 1][hk]
                if not b or not h then break end
                local g = relative(h, b)
                if dist(g.t, g0.t) > CARRY_POS_CM or angle(g.q, g0.q) > CARRY_ANG_DEG then break end
                j = j + 1
            end
            if j > i then
                local travel = 0
                for k = i + 1, j do travel = math.max(travel, dist(frames[k].bones[bone].t, b0.t)) end
                local dur = frames[j].t - frames[i].t
                if dur >= CARRY_MIN_S and travel >= CARRY_MIN_TRAVEL_CM then
                    table.insert(wins, { s = i, e = j, travel = travel, dur = dur })
                end
                -- diagnostics: the longest steady stretch of this bone, kept or not
                if wins.longest == nil or dur > wins.longest.dur then wins.longest = { dur = dur, travel = travel, t = frames[i].t } end
            end
            i = j + 1
        end
        ::continue::
    end
    return wins
end

-- The carried item = the bone whose carry window ends LAST (the fresh mag / shell / loader goes in at the end of
-- the reload; an old mag pulled out earlier loses). Ties: the longer travel.
local function findItem(rec, frames, hk)
    local best = nil
    for _, b in ipairs(rec.weaponBones) do
        if not SKIP_BONES[b] and b ~= rec.weaponBones[1] then
            for _, w in ipairs(carryWindows(frames, b, hk)) do
                local cand = { bone = b, w = w, endT = frames[w.e].t, mag = isMagBone(rec, b) }
                if better(cand, best) then best = cand end
            end
        end
    end
    return best
end

-- Loose carry (fallback when no bone has a strict window). Pistols: the arms and the gun animate separately and only
-- roughly agree, and the palm slides along the mag while it goes in, so the hand-in-mag drifts 1-5 cm per frame.
-- Carry frames: the bone is off its final (seated) pose, near the hand, and the hand-in-bone changes by less than
-- LOOSE_STEP_CM / LOOSE_STEP_DEG per frame (a bone reused for the new mag teleports into the hand, which breaks it).
-- Returns { bone, w = {s, e, travel, dur}, grip = frame index } with the grip at the steadiest frame of the first
-- LOOSE_HOLD_SHARE of the carry (the mag held on its way from the pouch, before the palm pushes it in).
local LOOSE_OFF_SEAT_CM = 3.0
local LOOSE_HAND_CM = 30.0
local LOOSE_STEP_CM = 7.0
local LOOSE_STEP_DEG = 25.0
local LOOSE_MIN_S = 0.2
local LOOSE_HOLD_SHARE = 0.6
local LOOSE_SPREAD_CM = 6.0      -- max hand-in-bone spread over a loose carry

local function looseCarry(rec, frames, hk)
    local best = nil
    for _, b in ipairs(rec.weaponBones) do
        local seat = frames[#frames].bones[b]
        if not SKIP_BONES[b] and b ~= rec.weaponBones[1] and seat then
            local ok, g = {}, {}
            for k, fr in ipairs(frames) do
                local bk, hand = fr.bones[b], fr[hk]
                if bk and hand then
                    g[k] = relative(hand, bk)
                    ok[k] = dist(bk.t, seat.t) > LOOSE_OFF_SEAT_CM and dist(hand.t, bk.t) <= LOOSE_HAND_CM
                end
            end
            local k = 1
            while k <= #frames do
                if ok[k] then
                    local e = k
                    while e + 1 <= #frames and ok[e + 1] and dist(g[e + 1].t, g[e].t) <= LOOSE_STEP_CM
                          and angle(g[e + 1].q, g[e].q) <= LOOSE_STEP_DEG do
                        e = e + 1
                    end
                    -- Trim the grab / release transients off the ends (the hand closing on the mag moves it a few cm in
                    -- the hand for a frame or two: AR416 MG_fp_m16_reload*), then judge the remaining core [s, f].
                    local s, f = k, e
                    local m = math.floor((k + e) / 2)
                    while s < m and dist(g[s].t, g[m].t) > LOOSE_SPREAD_CM do s = s + 1 end
                    while f > m and dist(g[f].t, g[m].t) > LOOSE_SPREAD_CM do f = f - 1 end
                    local dur = frames[f].t - frames[s].t
                    local lo, hi = math.huge, 0
                    for i = s, f do
                        local d = dist(frames[i].bones[b].t, seat.t)
                        lo, hi = math.min(lo, d), math.max(hi, d)
                    end
                    local travel = hi - lo
                    -- the hand must move with it (a hand parked on the fore-end next to a moving mag is no carry)
                    local handTravel = 0
                    for i = s + 1, f do handTravel = math.max(handTravel, dist(frames[i][hk].t, frames[s][hk].t)) end
                    -- ... and hold it: the hand-in-bone offset spreads far less than the bone travels
                    local mid = g[math.floor((s + f) / 2)]
                    local spread = 0
                    for i = s, f do spread = math.max(spread, dist(g[i].t, mid.t)) end
                    if dur >= LOOSE_MIN_S and travel >= CARRY_MIN_TRAVEL_CM and handTravel >= CARRY_MIN_TRAVEL_CM
                       and spread <= math.min(LOOSE_SPREAD_CM, 0.5 * travel) then
                        local endT = frames[f].t
                        local cand = { bone = b, w = { s = s, e = f, travel = travel, dur = dur }, endT = endT, mag = isMagBone(rec, b) }
                        if better(cand, best) then
                            -- steadiest frame (smallest neighbour-to-neighbour change) in the hold share of the carry
                            local last = math.max(s + 1, math.min(f - 1, s + math.floor((f - s) * LOOSE_HOLD_SHARE)))
                            local pick, score = math.max(s, math.min(f, s + 1)), math.huge
                            for i = s + 1, last do
                                if g[i - 1] and g[i + 1] then
                                    local sc = dist(g[i + 1].t, g[i - 1].t) + angle(g[i + 1].q, g[i - 1].q) / 10
                                    if sc < score then pick, score = i, sc end
                                end
                            end
                            cand.grip = pick
                            best = cand
                        end
                    end
                    k = e + 1
                else
                    k = k + 1
                end
            end
        end
    end
    return best
end

local function partOn(rec, bone)
    local pick = nil
    for _, p in ipairs(rec.parts or {}) do
        if p.socket == bone then
            local lower = string.lower(p.mesh or "")
            if pick == nil or (string.find(lower, "empty", 1, true) == nil and string.find(string.lower(pick.mesh), "empty", 1, true) ~= nil) then
                pick = p
            end
        end
    end
    return pick
end

-- Rack: the frame the game's left hand has pulled the rack joint a quarter of the way (it holds the handle then).
-- hand position in the receiver (far away when this hand is missing, so it never qualifies)
local FAR = { x = 1e6, y = 1e6, z = 1e6 }
local function HT(fr, hk) return fr[hk] and fr[hk].t or FAR end

local function findRack(rec, frames, hk)
    local joint = rec.rackJoint
    if joint == nil or #frames < 2 then return nil end
    local final = frames[#frames].bones[joint]
    if final == nil then return nil end
    local disp = {}
    for k, fr in ipairs(frames) do disp[k] = fr.bones[joint] and dist(fr.bones[joint].t, final.t) or 0 end
    -- the pull: the joint moves away from where it ends up beyond where it started (a locked-open slide starts back)
    local base = disp[1]
    local maxD, maxK = base, nil
    for k = 2, #frames do
        if disp[k] > maxD and dist(HT(frames[k], hk), frames[k].bones[joint].t) <= RACK_HAND_CM then maxD, maxK = disp[k], k end
    end
    if maxK == nil or maxD - base < RACK_MIN_PULL_CM then
        -- No pull past the start: a slide locked back that the game's hand grabs and lets go (slingshot, UDP).
        -- Grip = the steadiest hand-on-part frame in the RELEASE_LOOKBACK_S before the part starts home.
        if base < RACK_MIN_PULL_CM then return nil end
        local release = nil
        for k = 2, #frames do
            if disp[k] < base - 0.2 then release = k; break end
        end
        if release == nil then return nil end
        local pick, score = nil, math.huge
        for k = release - 1, 2, -1 do
            if frames[release].t - frames[k].t > RELEASE_LOOKBACK_S then break end
            local bk, bp = frames[k].bones[joint], frames[k - 1].bones[joint]
            if bk and bp and frames[k - 1][hk] and dist(HT(frames[k], hk), bk.t) <= RACK_HAND_CM then
                local g, gp = relative(frames[k][hk], bk), relative(frames[k - 1][hk], bp)
                local s = dist(g.t, gp.t) + angle(g.q, gp.q) / 10
                if s < score then pick, score = k, s end
            end
        end
        if pick == nil or score > RELEASE_MAX_STEP then return nil end
        local fr = frames[pick]
        return {
            joint = joint, kind = "release",
            grip = packOut(relative(fr[hk], fr.bones[joint])),
            fingers = fingersAt(fr.raw, "l"),
            handDist = r3(dist(HT(fr, hk), fr.bones[joint].t)), t = fr.t, pull = r3(base),
        }
    end
    local want = base + 0.25 * (maxD - base)
    local pick = maxK
    for k = 2, maxK do
        if disp[k] >= want and disp[k] >= disp[k - 1] - 0.05
           and dist(HT(frames[k], hk), frames[k].bones[joint].t) <= RACK_HAND_CM then
            pick = k
            break
        end
    end
    local fr = frames[pick]
    return {
        joint = joint,
        grip = packOut(relative(fr[hk], fr.bones[joint])),
        fingers = fingersAt(fr.raw, "l"),
        handDist = r3(dist(HT(fr, hk), fr.bones[joint].t)), t = fr.t, pull = r3(maxD - base),
    }
end

function M.analyse(rec)
    local frames = prepare(rec)
    if #frames < 10 then return nil, "too few frames" end
    local prof = { version = 1, rig = rec.rig, frames = #frames }
    -- either hand may carry the item (D12: the right hand swaps the mag); a right-hand grip is mirrored onto the left
    local item, how, side = nil, nil, nil
    for _, hk in ipairs({ "handL", "handR" }) do
        local c = findItem(rec, frames, hk)
        if c and better(c, item) then item, how, side = c, "steady", hk end
    end
    if item == nil then
        for _, hk in ipairs({ "handL", "handR" }) do
            local c = looseCarry(rec, frames, hk)
            if c and better(c, item) then item, how, side = c, "loose", hk end
        end
    end
    if item then
        local w = item.w
        local mid = frames[item.grip or math.floor((w.s + w.e) / 2)]
        local grip = relative(mid[side], mid.bones[item.bone])
        local right = side == "handR"
        if right then grip = mirrorToLeft(grip) end
        local part = partOn(rec, item.bone)
        prof.item = {
            bone = item.bone, grip = packOut(grip),
            mesh = part and part.mesh or nil,
            meshLoc = part and part.loc or { 0, 0, 0 }, meshRot = part and part.rot or { 0, 0, 0 },
            t0 = frames[w.s].t, t1 = frames[w.e].t, travel = r3(w.travel), how = how, gripT = mid.t,
            hand = right and "right (mirrored)" or "left",
        }
        if right then
            -- behaviour-mirrored skeleton: the right finger locals ARE the left ones
            prof.fingers = {}
            for name, rot in pairs(fingersAt(mid.raw, "r")) do prof.fingers[(name:gsub("^jnt_r_hand_", "jnt_l_hand_"))] = rot end
        else
            prof.fingers = fingersAt(mid.raw, "l")
        end
    end
    -- the rack hand = the one on the part. A right-hand rack is not learned: mirroring would put the left hand on the
    -- far side of a side-mounted handle, so the left hand stays as grabbed with the tuned rack pose.
    -- A hand that never leaves its place (the right hand on a pistol grip, close to the slide) is not the rack hand.
    local function moves(hk)
        local first, far = frames[1][hk], 0
        if first == nil then return false end
        for _, fr in ipairs(frames) do
            if fr[hk] then far = math.max(far, dist(fr[hk].t, first.t)) end
        end
        return far >= CARRY_MIN_TRAVEL_CM
    end
    local rackL = moves("handL") and findRack(rec, frames, "handL") or nil
    local rackR = moves("handR") and findRack(rec, frames, "handR") or nil
    if rackR and (rackL == nil or rackR.handDist < rackL.handDist) then
        prof.rackByRightHand = true
    else
        prof.rack = rackL
    end
    if prof.item == nil and prof.rack == nil then
        -- say why: each bone's longest steady hand-in-bone stretch (needs >= CARRY_MIN_S and >= CARRY_MIN_TRAVEL_CM)
        local parts = {}
        for _, b in ipairs(rec.weaponBones) do
            if not SKIP_BONES[b] and b ~= rec.weaponBones[1] then
                local l = carryWindows(frames, b, "handL").longest
                if l and l.dur > 0.05 then table.insert(parts, { s = string.format("%s %.2fs/%.1fcm@%.2f", b, l.dur, l.travel, l.t), d = l.dur }) end
            end
        end
        table.sort(parts, function(a, b) return a.d > b.d end)
        local txt = {}
        for i = 1, math.min(4, #parts) do txt[i] = parts[i].s end
        return nil, "nothing learned (no carried item, no rack); longest holds: " .. table.concat(txt, ", ")
    end
    return prof
end

return M
