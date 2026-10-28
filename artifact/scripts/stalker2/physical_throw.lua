-- Physical throws for grenades and bolts (2026-10-12; method from the Hellraiser profile's throwables.lua).
--
-- While a grenade (F1 / RGD-5) or the bolt is equipped and the option is on:
--   * Right Trigger is kept from the game while it is held (no aiming arc, no throw);
--   * the player swings the hand and lets go of the trigger: the hand's velocity at the release (relative to the
--     head, so walking / turning does not count) becomes the throw. RT is then tapped for the game, which plays
--     its strong-throw montage (sped up, so the delay is short) and spawns its own projectile;
--   * the spawned projectile is moved to the hand and given the swing's velocity.
-- A release with the hand (almost) still throws nothing - that is the way to change your mind.
-- The right grip (RB = the game's underarm / weak throw) works the same way: hold it, swing, let go. The game then
-- plays its underarm throw (RB is tapped instead of RT) and the toss uses its own, gentler speed settings.
--
-- Game facts (MCP, 2026-10-12):
--   * thrown objects are native actors spawned by the throw montage: Class /Script/Stalker2.Grenade (root
--     StaticMeshComponent, GrenadeExplosionComponent, TimeToExplosion) and Class /Script/Stalker2.Bolt
--     (BoltComponent). No actor of either class exists while the item is only held (that is the pawn's
--     WeaponInHandsMesh). Both carry PhysicsInteractionComponent / HittableComponent, i.e. physics bodies.
--   * the throw input is native on the pawn (Class /Script/Stalker2.PC: PressThrowStrong / ReleaseThrowStrong,
--     ...Weak); RT = strong throw, LT = weak throw. LT is left alone.
--   * native classes: there is no Blueprint BeginPlay to hook (Hellraiser's spawn hook), and freshly spawned
--     actors are invisible to get_objects_by_class (deferred adoption, see physical_pickup.lua). The projectile
--     is found with a sphere overlap around the head, against a baseline taken at the release (bolts already
--     lying around are not ours).
require("Config.CONFIG")
local controllers = require("libs/controllers")
local uevrUtils   = require("libs/uevr_utils")
local plugin      = require("libs/core/plugin")   -- TArray-capable engine calls (SphereOverlapComponents)
local mc          = require("gestures.motioncontrollergestures")

local M = {}

local RT_THRESHOLD      = 100     -- 0..255
local GRIP_BUTTON       = 0x0200  -- XINPUT_GAMEPAD_RIGHT_SHOULDER = right grip = the game's underarm (weak) throw
local TAP_POLLS         = 3       -- xinput polls the injected RT is held (knife_melee.lua / ptm X spoof)
local TAP_MAX_HOLD      = 0.25    -- seconds: hard cap on the injected hold
local SAMPLE_WINDOW_S   = 0.06    -- hand velocity = motion over this window
local PEAK_WINDOW_S     = 0.12    -- best windowed velocity this long before the release counts
local SPAWN_WAIT_S      = 2.0     -- give up looking for the projectile after this
local SEARCH_RADIUS     = 400.0   -- cm around the head
local CATCHUP_MAX_S     = 0.15    -- never start the projectile further along its path than this
local RATE_MAX_S        = 1.5     -- unconditional restore deadline for the animation speed
local HOLD_S            = 0.2     -- keep our velocity this long if the game writes its own after the spawn
local GRAVITY_Z         = -980.0
local TICK_STALE_S      = 0.25    -- no gameplay tick for this long (menu, cutscene): RT passes through
local STABILIZE_AFTER_S = 0.6     -- camera shakes stay off this long after the projectile was launched
local STABILIZE_MAX_S   = 3.0     -- unconditional end of the camera window

local function cfg()
    local c = Config.physicalThrow
    if type(c) ~= "table" then
        c = {}
        Config.physicalThrow = c
    end
    return c
end

local function num(key, default)
    local v = tonumber(cfg()[key])
    if v == nil then return default end
    return v
end

function M.isEnabled()
    return cfg().enabled ~= false
end

-- data/physical_throw_log.txt (last 200 lines), while "debugLog" is on. Off by default; the key was "log"
-- (default on) until 2026-10-12 - renamed so a saved `log = true` no longer applies.
local logLines = {}
local function log(text)
    if cfg().debugLog ~= true then return end
    table.insert(logLines, string.format("%.3f %s", os.clock(), tostring(text)))
    while #logLines > 200 do table.remove(logLines, 1) end
    pcall(function() fs.write("physical_throw_log.txt", table.concat(logLines, "\n") .. "\n") end)
end

local function vlen(v) return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end

-- ---------------------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------------------
local equipped        = false
local equippedName    = nil
local lastWeaponName  = false   -- false = never checked (nil is a valid "bare hands" value)
local lastTickAt      = 0
local rtHeld          = false   -- real RT, as the player holds it
local gripHeld        = false   -- real right grip (RB)
local waitAllUp       = false   -- a release was taken: RT and grip must both come up before the next one
local releaseRequested = false  -- "over" (RT) / "under" (grip): set by the input callback, consumed by the tick
local tapPollsLeft, tapDeadline = 0, 0
local tapKind         = "over"  -- which game input the tap presses: RT (strong throw) or RB (underarm throw)
local pending         = nil     -- { pos, vel, at, handSpeed, known = { [address] = true } }
local corrected       = nil     -- { actor, comp, vel, gameVel, at, reapplied }
local lastThrow       = { text = "none yet", at = 0 }
function M.getLastThrow() return lastThrow end
function M.isThrowableEquipped() return equipped end

local function setLast(text)
    lastThrow.text, lastThrow.at = text, os.clock()
end

-- ---------------------------------------------------------------------------------------
-- Hand velocity (relative to the head)
-- ---------------------------------------------------------------------------------------
local samples  = {}   -- { t, X, Y, Z } of hand - head, newest last
local lastHand = nil  -- world position of the hand at the newest sample
local lastGaze = nil  -- head forward at the newest sample
local bestVel  = nil  -- { t, X, Y, Z }: fastest windowed velocity within PEAK_WINDOW_S

local function clearSamples()
    samples, lastHand, lastGaze, bestVel = {}, nil, nil, nil
end

local function sampleHand()
    local hp = controllers.getControllerLocation(Config.dominantHand or 1)
    local hd = controllers.getControllerLocation(2)
    local hr = controllers.getControllerRotation(2)
    if hp == nil or hd == nil or hr == nil then clearSamples() return end
    local now = os.clock()
    local newest = samples[#samples]
    if newest ~= nil and now - newest.t > 0.1 then clearSamples() end
    lastHand = { X = hp.X, Y = hp.Y, Z = hp.Z }
    local g = kismet_math_library:GetForwardVector(hr)
    lastGaze = { X = g.X, Y = g.Y, Z = g.Z }
    table.insert(samples, { t = now, X = hp.X - hd.X, Y = hp.Y - hd.Y, Z = hp.Z - hd.Z })
    while #samples > 1 and now - samples[1].t > 0.3 do table.remove(samples, 1) end

    local cur = samples[#samples]
    local old = nil
    for i = #samples - 1, 1, -1 do
        old = samples[i]
        if cur.t - old.t >= SAMPLE_WINDOW_S then break end
    end
    if old == nil or cur.t - old.t < 0.005 then return end
    local dt = cur.t - old.t
    local v = { t = now, X = (cur.X - old.X) / dt, Y = (cur.Y - old.Y) / dt, Z = (cur.Z - old.Z) / dt }
    if bestVel == nil or now - bestVel.t > PEAK_WINDOW_S or vlen(v) >= vlen(bestVel) then bestVel = v end
end

-- ---------------------------------------------------------------------------------------
-- Animation speed: the game spawns the projectile from its throw montage. Character mesh and the item's own
-- mesh both animate (see knife_melee.lua), so both run faster from the release until the projectile appears.
-- ---------------------------------------------------------------------------------------
local rateActive, rateAt = false, 0

local function setRates(rate)
    pcall(function()
        local pawn = uevr.api:get_local_pawn(0)
        local cm = pawn and pawn.Mesh or nil
        local ai = cm and cm.AnimScriptInstance or nil
        local wm = ai and ai.WeaponData and ai.WeaponData.WeaponMesh or nil
        if cm ~= nil then cm.GlobalAnimRateScale = rate end
        if wm ~= nil then wm.GlobalAnimRateScale = rate end
    end)
end

local function restoreRate()
    if not rateActive then return end
    rateActive = false
    setRates(1.0)
end

local function startRate()
    local rate = num("animRate", 20.0)
    if rate <= 1.0 then return end
    rateActive, rateAt = true, os.clock()
    setRates(rate)
end

-- ---------------------------------------------------------------------------------------
-- Camera: the throw montage shakes the view (first headset run 2026-10-12). From the release until shortly after
-- the launch the camera manager's shake and camera-animation modifiers are disabled and running shakes are stopped
-- every tick (PlayerCameraManager.ModifierList = CameraModifier_LookAt, CameraAnimationCameraModifier,
-- CameraModifier_CameraShake - MCP 2026-10-12). The log line at the end of the window says how many shakes were
-- seen, to tell a camera shake from an animated camera bone.
-- ---------------------------------------------------------------------------------------
local STABILIZE_CLASSES = { CameraModifier_CameraShake = true, CameraAnimationCameraModifier = true }
local stabilize = nil   -- { startedAt, endAt, modifiers = { modifier, ... }, manager, shakesSeen }

-- Second headset run: no shake was ever active - the view moves because the pawn's Camera component hangs on the
-- character mesh's jnt_camera bone (bUsePawnControlRotation false, zero relative transform; MCP 2026-10-12), and
-- the throw montage animates that bone. For the window the camera is parked on the capsule instead, exactly where
-- it is at the release (it still moves and turns with the pawn), and goes back onto the bone afterwards.
local function holdCamera(st)
    pcall(function()
        local pawn = uevr.api:get_local_pawn(0)
        local camera, mesh, root = pawn.Camera, pawn.Mesh, pawn.RootComponent
        if camera == nil or mesh == nil or root == nil then return end
        local parent = camera.AttachParent
        if parent == nil or parent:get_address() ~= mesh:get_address() then return end -- not on the bone: leave it
        local rl, rr = camera.RelativeLocation, camera.RelativeRotation
        st.camera = { component = camera, parent = mesh, socket = camera.AttachSocketName,
            loc = { X = rl.X, Y = rl.Y, Z = rl.Z }, rot = { Pitch = rr.Pitch, Yaw = rr.Yaw, Roll = rr.Roll } }
        camera:K2_AttachTo(root, uevrUtils.fname_from_string("None"), 1, false) -- 1 = KeepWorldPosition
    end)
end

-- Back onto the bone without a pop (third run: a slight jolt at the hand-back): attached where it is, then its
-- relative transform eases to the original one over CAMERA_BLEND_S.
local CAMERA_BLEND_S = 0.25
local cameraBlend = nil   -- { component, from = {loc, rot}, to = {loc, rot}, startedAt }

local function setCameraRelative(component, loc, rot)
    component:K2_SetRelativeLocationAndRotation(uevrUtils.vector(loc.X, loc.Y, loc.Z),
        uevrUtils.rotator(rot.Pitch, rot.Yaw, rot.Roll), false, reusable_hit_result, false)
end

local function angleStep(from, to, alpha)
    local d = (to - from) % 360
    if d > 180 then d = d - 360 end
    return from + d * alpha
end

local function updateCameraBlend()
    local b = cameraBlend
    if b == nil then return end
    local alpha = math.min((os.clock() - b.startedAt) / CAMERA_BLEND_S, 1)
    local eased = alpha * alpha * (3 - 2 * alpha) -- smoothstep
    local ok = pcall(function()
        setCameraRelative(b.component,
            { X = b.from.loc.X + (b.to.loc.X - b.from.loc.X) * eased, Y = b.from.loc.Y + (b.to.loc.Y - b.from.loc.Y) * eased,
              Z = b.from.loc.Z + (b.to.loc.Z - b.from.loc.Z) * eased },
            { Pitch = angleStep(b.from.rot.Pitch, b.to.rot.Pitch, eased), Yaw = angleStep(b.from.rot.Yaw, b.to.rot.Yaw, eased),
              Roll = angleStep(b.from.rot.Roll, b.to.rot.Roll, eased) })
    end)
    if alpha >= 1 or not ok then cameraBlend = nil end
end

-- immediate = true: straight onto the original relative transform (script reset, a new throw starting)
local function releaseCamera(st, immediate)
    local held = st.camera
    st.camera = nil
    if held == nil then return false end
    return pcall(function()
        if immediate then
            held.component:K2_AttachTo(held.parent, held.socket, 0, false) -- 0 = KeepRelativeOffset
            setCameraRelative(held.component, held.loc, held.rot)
            return
        end
        held.component:K2_AttachTo(held.parent, held.socket, 1, false) -- 1 = KeepWorldPosition
        local rl, rr = held.component.RelativeLocation, held.component.RelativeRotation
        cameraBlend = { component = held.component, startedAt = os.clock(),
            from = { loc = { X = rl.X, Y = rl.Y, Z = rl.Z }, rot = { Pitch = rr.Pitch, Yaw = rr.Yaw, Roll = rr.Roll } },
            to = { loc = held.loc, rot = held.rot } }
    end)
end

-- a blend still running when the camera is needed again (next throw) or the script goes away: finish it now
local function finishCameraBlend()
    local b = cameraBlend
    cameraBlend = nil
    if b ~= nil then pcall(setCameraRelative, b.component, b.to.loc, b.to.rot) end
end

local function endStabilize(immediate)
    local st = stabilize
    stabilize = nil
    if st == nil then return end
    for _, modifier in ipairs(st.modifiers) do
        pcall(function() modifier:EnableModifier() end)
    end
    local hadCamera = st.camera ~= nil
    local cameraBack = releaseCamera(st, immediate)
    log(string.format("camera window ended after %.0f ms: %d modifier(s) re-enabled, most active shakes seen %d, camera %s",
        (os.clock() - st.startedAt) * 1000, #st.modifiers, st.shakesSeen,
        hadCamera and (cameraBack and "back on its bone" or "FAILED to re-attach") or "was not held"))
end

local function startStabilize()
    if cfg().stabilizeCamera == false then return end
    if stabilize ~= nil then endStabilize(true) end
    finishCameraBlend()
    local st = { startedAt = os.clock(), endAt = os.clock() + STABILIZE_MAX_S, modifiers = {}, shakesSeen = 0 }
    pcall(function()
        local pc = uevr.api:get_player_controller(0)
        local manager = pc and pc.PlayerCameraManager or nil
        if manager == nil then return end
        st.manager = manager
        local list = manager.ModifierList
        for i = 1, #list do
            local modifier = list[i]
            if modifier ~= nil and STABILIZE_CLASSES[modifier:get_class():get_fname():to_string()] then
                local wasDisabled = false
                pcall(function() wasDisabled = modifier:IsDisabled() end)
                if not wasDisabled then -- one somebody else switched off stays off
                    modifier:DisableModifier(true)
                    table.insert(st.modifiers, modifier)
                end
            end
        end
        manager:StopAllCameraShakes(true)
    end)
    holdCamera(st)
    stabilize = st
end

local function updateStabilize()
    local st = stabilize
    if st == nil then return end
    local now = os.clock()
    if now >= st.endAt then
        -- the rest of the throw montage (follow-through, at normal speed again) still animates the camera bone:
        -- stay until the character has no montage left, up to the hard limit
        local montagePlaying = false
        pcall(function() montagePlaying = uevr.api:get_local_pawn(0):GetCurrentMontage() ~= nil end)
        if not montagePlaying or now - st.startedAt >= STABILIZE_MAX_S then endStabilize() return end
    end
    if st.manager == nil then return end
    pcall(function() -- diagnostic only
        local shake = st.manager.CachedCameraShakeMod
        local active = shake and shake.ActiveShakes or nil
        if active ~= nil and #active > st.shakesSeen then st.shakesSeen = #active end
    end)
    pcall(function() st.manager:StopAllCameraShakes(true) end)
end

-- ---------------------------------------------------------------------------------------
-- Finding the spawned projectile
-- ---------------------------------------------------------------------------------------
local grenadeClass, boltClass, primitiveClass = nil, nil, nil
local OVERLAP_OBJECT_TYPES = {}
for i = 0, 23 do OVERLAP_OBJECT_TYPES[#OVERLAP_OBJECT_TYPES + 1] = i end

local function ensureClasses()
    if grenadeClass == nil then grenadeClass = uevrUtils.get_class("Class /Script/Stalker2.Grenade") end
    if boltClass == nil then boltClass = uevrUtils.get_class("Class /Script/Stalker2.Bolt") end
    if primitiveClass == nil then primitiveClass = uevrUtils.get_class("Class /Script/Engine.PrimitiveComponent") end
    return primitiveClass ~= nil and (grenadeClass ~= nil or boltClass ~= nil)
end

-- thrown grenade / bolt actors near the head: { [address] = actor }, plus the number of overlapped components
local function scanProjectiles()
    local found, count = {}, 0
    if not ensureClasses() or kismet_system_library == nil then return found, -1 end
    local world = uevrUtils.get_world()
    local center = controllers.getControllerLocation(2)
    if world == nil or center == nil then return found, -1 end
    local pawn = uevr.api:get_local_pawn(0)
    local result = nil
    local ok, err = pcall(function()
        result = plugin.executeFunction(kismet_system_library, "SphereOverlapComponents",
            world, center, SEARCH_RADIUS, OVERLAP_OBJECT_TYPES, primitiveClass, { pawn }, {})
    end)
    if not ok or result == nil then
        return found, -1
    end
    local comps = result.OutComponents or {}
    count = #comps
    for i = 1, count do
        pcall(function()
            local actor = comps[i]:GetOwner()
            if actor == nil then return end
            if (grenadeClass ~= nil and actor:is_a(grenadeClass)) or (boltClass ~= nil and actor:is_a(boltClass)) then
                found[actor:get_address()] = actor
            end
        end)
    end
    return found, count
end

local function projectileBody(actor)
    local comp = nil
    pcall(function() comp = actor.StaticMeshComponent end)   -- Grenade
    if comp == nil then pcall(function() comp = actor.BoltComponent end) end
    if comp == nil then pcall(function() comp = actor.RootComponent end) end
    return comp
end

local noneName = nil
local function getBodyVelocity(comp)
    if noneName == nil then noneName = uevrUtils.fname_from_string("None") end
    local v = comp:GetPhysicsLinearVelocity(noneName)
    return { X = v.X, Y = v.Y, Z = v.Z }
end

local function setBodyVelocity(comp, vel)
    if noneName == nil then noneName = uevrUtils.fname_from_string("None") end
    comp:SetPhysicsLinearVelocity(uevrUtils.vector(vel.X, vel.Y, vel.Z), false, noneName)
end

-- start point along the release path after `t` seconds; stops short of anything in the way
local function catchUp(pos, vel, t, ignore)
    local p = { X = pos.X + vel.X * t, Y = pos.Y + vel.Y * t, Z = pos.Z + vel.Z * t + 0.5 * GRAVITY_Z * t * t }
    local v = { X = vel.X, Y = vel.Y, Z = vel.Z + GRAVITY_Z * t }
    local d = { X = p.X - pos.X, Y = p.Y - pos.Y, Z = p.Z - pos.Z }
    local dist = vlen(d)
    if dist < 1 then return pos, vel end
    local n = { X = d.X / dist, Y = d.Y / dist, Z = d.Z / dist }
    local hit = nil
    pcall(function()
        hit = uevrUtils.getTargetLocation(uevrUtils.vector(pos.X, pos.Y, pos.Z), uevrUtils.vector(n.X, n.Y, n.Z), 0, ignore, false, 0, dist)
    end)
    if hit ~= nil then
        local hd = vlen({ X = hit.X - pos.X, Y = hit.Y - pos.Y, Z = hit.Z - pos.Z })
        if hd < dist - 1 then
            local back = math.max(hd - 10, 0)
            return { X = pos.X + n.X * back, Y = pos.Y + n.Y * back, Z = pos.Z + n.Z * back }, vel
        end
    end
    return p, v
end

local function launch(actor, p)
    local now = os.clock()
    local comp = projectileBody(actor)
    if comp == nil then
        log("projectile without a body component: " .. actor:get_full_name())
        setLast("projectile found but it has no mesh")
        return
    end
    local className = actor:get_class():get_fname():to_string()
    local simulating, gameVel, at = nil, { X = 0, Y = 0, Z = 0 }, actor:K2_GetActorLocation()
    pcall(function() simulating = comp:IsSimulatingPhysics(uevrUtils.fname_from_string("None")) end)
    pcall(function() gameVel = getBodyVelocity(comp) end)

    local pos, vel = p.pos, p.vel
    local speed = vlen(vel)
    local dist = num("spawnDist", 20.0)
    pos = { X = pos.X + vel.X / speed * dist, Y = pos.Y + vel.Y / speed * dist, Z = pos.Z + vel.Z / speed * dist }
    if cfg().catchUp ~= false then
        pos, vel = catchUp(pos, vel, math.min(now - p.at, CATCHUP_MAX_S), { uevr.api:get_local_pawn(0), actor })
    end

    local rot = actor:K2_GetActorRotation()
    actor:K2_SetActorLocationAndRotation(uevrUtils.vector(pos.X, pos.Y, pos.Z), rot, false, reusable_hit_result, true)
    local ok, err = pcall(setBodyVelocity, comp, vel)
    corrected = { actor = actor, comp = comp, vel = vel, gameVel = gameVel, at = now, reapplied = 0 }
    if stabilize ~= nil then stabilize.endAt = now + STABILIZE_AFTER_S end

    setLast(string.format("%s: hand %.0f -> %.0f cm/s, game took %.0f ms", className, p.handSpeed, speed, (now - p.at) * 1000))
    log(string.format("%s body %s simulating=%s setVelocity=%s; release->found %.0f ms; game vel (%.0f %.0f %.0f) = %.0f cm/s at (%.0f %.0f %.0f) -> vel (%.0f %.0f %.0f) at (%.0f %.0f %.0f)",
        className, comp:get_fname():to_string(), tostring(simulating), ok and "ok" or tostring(err), (now - p.at) * 1000,
        gameVel.X, gameVel.Y, gameVel.Z, vlen(gameVel), at.X, at.Y, at.Z, vel.X, vel.Y, vel.Z, pos.X, pos.Y, pos.Z))
end

local function searchProjectile()
    local p = pending
    if p == nil then return end
    local now = os.clock()
    -- which montages the game played after the tap (tells a refused throw from a missed projectile)
    pcall(function()
        local montage = uevr.api:get_local_pawn(0):GetCurrentMontage()
        local name = montage and uevrUtils.getShortName(montage) or "-"
        if p.montages[name] == nil then
            p.montages[name] = true
            table.insert(p.montageList, string.format("%s@%.0fms", name, (now - p.at) * 1000))
        end
    end)
    if now - p.at > SPAWN_WAIT_S then
        pending = nil
        restoreRate()
        endStabilize()
        setLast("no projectile appeared after the release")
        log(string.format("no projectile within %.1f s of the release (last scan: %s components; montages: %s)",
            SPAWN_WAIT_S, tostring(p.lastCount), table.concat(p.montageList, " ")))
        return
    end
    local found, count = scanProjectiles()
    p.lastCount = count
    for address, actor in pairs(found) do
        if not p.known[address] then
            pending = nil
            restoreRate()
            local ok, err = pcall(launch, actor, p)
            if not ok then
                log("launch failed: " .. tostring(err))
                setLast("launch failed: " .. tostring(err))
            end
            return
        end
    end
end

-- the game writing its own velocity after we set ours (impulse applied a tick after the spawn): put ours back
local function holdVelocity()
    local c = corrected
    if c == nil then return end
    local t = os.clock() - c.at
    if t > HOLD_S or c.reapplied >= 2 then corrected = nil return end
    local v = getBodyVelocity(c.comp)
    local expected = { X = c.vel.X, Y = c.vel.Y, Z = c.vel.Z + GRAVITY_Z * t }
    local off = vlen({ X = v.X - expected.X, Y = v.Y - expected.Y, Z = v.Z - expected.Z })
    if off < math.max(150.0, vlen(expected) * 0.25) then return end
    -- only when the new velocity looks like the game's own throw, not like a bounce off something: either it is
    -- (nearly) the velocity the game had given it, or the game had not given it one yet when we found it
    local gameSpeed = vlen(c.gameVel)
    local likeGame = gameSpeed < 50
    if not likeGame then
        local d = vlen({ X = v.X - c.gameVel.X, Y = v.Y - c.gameVel.Y, Z = v.Z - (c.gameVel.Z + GRAVITY_Z * t) })
        likeGame = d < gameSpeed * 0.25
    end
    if likeGame then
        setBodyVelocity(c.comp, expected)
        c.reapplied = c.reapplied + 1
        log(string.format("game velocity (%.0f %.0f %.0f) appeared %.0f ms after the launch - ours put back", v.X, v.Y, v.Z, t * 1000))
    else
        corrected = nil
    end
end

-- ---------------------------------------------------------------------------------------
-- Release
-- ---------------------------------------------------------------------------------------
local function handleRelease()
    local under = releaseRequested == "under"
    releaseRequested = false
    local v = bestVel
    if v == nil or lastHand == nil or os.clock() - v.t > PEAK_WINDOW_S then
        setLast("no hand motion measured - nothing thrown")
        return
    end
    local handSpeed = vlen(v)
    if handSpeed < num("minSpeed", 120.0) then
        setLast(string.format("hand too slow (%.0f cm/s) - nothing thrown", handSpeed))
        log(string.format("release at %.0f cm/s: below the minimum, nothing thrown", handSpeed))
        return
    end
    -- underarm (grip): a gentler toss with its own scale and floor, so a grenade can be dropped close
    local scale = under and num("underSpeedScale", 2.0) or num("speedScale", 3.5)
    local floor = under and num("underFloorSpeed", 250.0) or num("floorSpeed", 600.0)
    local speed = math.min(math.max(handSpeed * scale, floor), num("maxSpeed", 2500.0))
    -- direction: the hand's, pulled toward the gaze (a late release bends the swing down / sideways), then raised
    local d = { X = v.X / handSpeed, Y = v.Y / handSpeed, Z = v.Z / handSpeed }
    local a = num("assist", 0.5)
    if lastGaze ~= nil and a > 0 then
        d = { X = d.X + (lastGaze.X - d.X) * a, Y = d.Y + (lastGaze.Y - d.Y) * a, Z = d.Z + (lastGaze.Z - d.Z) * a }
    end
    local r = kismet_math_library:Conv_VectorToRotator(uevrUtils.vector(d.X, d.Y, d.Z))
    local f = kismet_math_library:GetForwardVector(uevrUtils.rotator(math.min(r.Pitch + num("arc", 8.0), 89.0), r.Yaw, 0))

    local known, count = scanProjectiles()
    local knownSet = {}
    for address in pairs(known) do knownSet[address] = true end
    pending = { pos = lastHand, vel = { X = f.X * speed, Y = f.Y * speed, Z = f.Z * speed }, at = os.clock(),
        handSpeed = handSpeed, known = knownSet, lastCount = count, montages = {}, montageList = {} }
    startStabilize()
    startRate()
    tapKind = under and "under" or "over"
    tapPollsLeft, tapDeadline = TAP_POLLS, os.clock() + TAP_MAX_HOLD
    log(string.format("release (%s, %s): hand %.0f cm/s -> throw %.0f cm/s, %s tapped; baseline scan %s components",
        tostring(equippedName), under and "underarm" or "overarm", handSpeed, speed, under and "RB" or "RT", tostring(count)))
end

-- ---------------------------------------------------------------------------------------
-- Frame / input hooks
-- ---------------------------------------------------------------------------------------
local function isThrowableName(name)
    if type(name) ~= "string" then return false end
    local n = string.lower(name)
    return string.find(n, "bolt", 1, true) ~= nil or string.find(n, "sk_f1", 1, true) ~= nil
        or string.find(n, "sk_rgd", 1, true) ~= nil or string.find(n, "grenade", 1, true) ~= nil
end

local function updateEquipped(weaponName)
    if weaponName == lastWeaponName then return end
    lastWeaponName = weaponName
    equippedName = weaponName
    local now = isThrowableName(weaponName)
    if now ~= equipped then
        equipped = now
        -- a throw in flight keeps its projectile search (the game switches to the next grenade / bare hands)
        releaseRequested, tapPollsLeft = false, 0
        clearSamples()
    end
end

-- Called from Entry.lua's on_pre_engine_tick (gameplay only). weaponName = Entry's currentWeaponName.
function M.on_pre_engine_tick(delta, weaponName)
    lastTickAt = os.clock()
    updateEquipped(weaponName)

    if pending ~= nil then
        local ok, err = pcall(searchProjectile)
        if not ok then pending = nil restoreRate() log("search failed: " .. tostring(err)) end
    end
    if corrected ~= nil then
        local ok = pcall(holdVelocity)
        if not ok then corrected = nil end
    end
    if rateActive and os.clock() - rateAt > RATE_MAX_S then restoreRate() end
    updateStabilize()
    updateCameraBlend()

    if not equipped or not M.isEnabled() then
        releaseRequested = false
        return
    end
    local ok, err = pcall(function()
        sampleHand()
        if releaseRequested then handleRelease() end
    end)
    if not ok then releaseRequested = false log("tick: " .. tostring(err)) end
end

-- Called from Entry.lua's on_xinput_get_state after the other input modules.
function M.on_xinput_get_state(state)
    if state == nil then return end
    local pad = state.Gamepad
    local down = pad.bRightTrigger > RT_THRESHOLD
    local gripDown = (pad.wButtons & GRIP_BUTTON) ~= 0
    if tapPollsLeft > 0 then
        if os.clock() > tapDeadline then
            tapPollsLeft = 0
        else
            if tapKind == "under" then
                pad.wButtons = pad.wButtons | GRIP_BUTTON
                pad.bRightTrigger = 0
            else
                pad.bRightTrigger = 255
                pad.wButtons = pad.wButtons & ~GRIP_BUTTON
            end
            tapPollsLeft = tapPollsLeft - 1
            rtHeld, gripHeld = down, gripDown
            return
        end
    end
    if not equipped or not M.isEnabled() or os.clock() - lastTickAt > TICK_STALE_S then
        rtHeld, gripHeld, waitAllUp = down, gripDown, false
        return
    end
    -- one throw per hold: after a release (thrown or not) both inputs must come up before the next one arms
    if waitAllUp then
        if not down and not gripDown then waitAllUp = false end
    elseif rtHeld and not down then
        releaseRequested, waitAllUp = "over", gripDown
    elseif gripHeld and not gripDown then
        -- a grip that a body-zone gesture claimed (holster etc.) is taken off the pad by the gesture code:
        -- that is not the player letting go
        local claimed = false
        pcall(function() claimed = mc.RightGripAction:IsLocked() end)
        if not claimed then releaseRequested = "under" end
        waitAllUp = down
    end
    rtHeld, gripHeld = down, gripDown
    pad.bRightTrigger = 0
    pad.wButtons = pad.wButtons & ~GRIP_BUTTON
end

-- stalker2/gripgesture.lua: right-grip body-zone gestures wait for the grip release while the grip is a throw
-- input, and are dropped when that release was a swing (same test handleRelease uses for "thrown or not").
_G.physicalThrowDefersGrip = function()
    return equipped and M.isEnabled() and os.clock() - lastTickAt <= TICK_STALE_S
end
_G.physicalThrowWasSwing = function()
    local v = bestVel
    return v ~= nil and os.clock() - v.t <= PEAK_WINDOW_S and vlen(v) >= num("minSpeed", 120.0)
end

-- World references die with the level (save load, death): forget them, never touch them. Without this a throw
-- that was still in its camera window when the player died put the OLD pawn's camera back on its bone, restored
-- the old camera manager's modifiers and polled the old projectile after the reload.
function M.onLevelChange()
    pending, corrected, releaseRequested, tapPollsLeft = nil, nil, false, 0
    stabilize, cameraBlend = nil, nil
    rateActive = false
    clearSamples()
end

function M.reset()
    pending, corrected, releaseRequested, tapPollsLeft = nil, nil, false, 0
    clearSamples()
    restoreRate()
    endStabilize(true)
    finishCameraBlend()
end

return M
