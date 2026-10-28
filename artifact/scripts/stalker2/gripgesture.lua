--[[
    GripGesture.lua
    Base class for gestures that activate when a motion controller is in a specific zone and grip button is pressed
]]--

local GestureBase = require("gestures.gesturebase")
local motionControllers = require("gestures.motioncontrollergestures")

-- GripGesture: Base class for grip-based gestures
local GripGesture = GestureBase:new({
    name = "Grip Gesture Base",
    gripGesture = nil,
    zone = nil,
})

function GripGesture:new(config)
    -- Set up dependencies
    config = config or {}
    
    local instance = GestureBase.new(self, config)
    
    -- Verify required properties after the instance is created
    if not instance.gripGesture then
        error("gripGesture is required for GripGesture")
    end
    if not instance.zone then
        error("zone is required for GripGesture")
    end
    
    instance:AddDependency(instance.gripGesture) -- Ensure gripGesture is a dependency
    instance:AddDependency(instance.zone) -- Ensure zone is a dependency
    return instance
end

-- Diagnostics: one record per squeeze of each grip action, shared by every gesture on that grip,
-- summarised into GripGesture.debugLog when the grip is released. Shown in the dev panel
-- ("Gesture Zone Debug Coordinates") so a missed grab reports WHY it missed.
GripGesture.debugLog = {}
local DEBUG_LOG_MAX = 24
local squeezes = setmetatable({}, { __mode = "k" })

function GripGesture.log(message)
    -- Seconds within the current minute are enough to order events and keep lines short
    -- (the dev panel clips long lines).
    table.insert(GripGesture.debugLog, 1, string.format("%05.2f %s", os.clock() % 60, message))
    while #GripGesture.debugLog > DEBUG_LOG_MAX do table.remove(GripGesture.debugLog) end
end

local function shortName(name)
    local s = tostring(name or "?")
    s = s:gsub(" Weapon Gesture", ""):gsub(" Gesture", ""):gsub(" Zone", ""):gsub(" Action", "")
    return s
end

local function joinKeys(t)
    local names = {}
    for name in pairs(t) do names[#names + 1] = name end
    table.sort(names)
    return table.concat(names, ", ")
end

function GripGesture:TrackSqueeze(now)
    local grip = self.gripGesture
    local rec = squeezes[grip]
    if grip:JustActivated() and (rec == nil or rec.done) then
        rec = { riseAt = now, zones = {}, leftBefore = {}, done = false, lockedAtRise = grip:IsLocked() }
        squeezes[grip] = rec
    end
    if rec == nil or rec.done then return nil end

    if grip.isActive then
        -- Only gestures that actually DO something take part in the diagnosis; zones that are
        -- merely evaluated (e.g. the weapon reload zone, whose callback is disabled) would
        -- otherwise log a "miss" on every ordinary two-hand grab.
        if self.executionCallBack ~= nil then
            if self.zone.isActive then
                rec.zones[shortName(self.zone.name)] = true
            elseif self.zoneActiveAt ~= nil and self.zoneActiveAt < rec.riseAt and (rec.riseAt - self.zoneActiveAt) < 1.0 then
                rec.leftBefore[self.zone.name] = string.format("%s %.2fs", shortName(self.zone.name), rec.riseAt - self.zoneActiveAt)
            end
            if self.excludeAction and self.excludeAction.isActive and self.zone.isActive then rec.excluded = true end
        end
        return rec
    end

    -- Grip released: close the record and report it once.
    rec.done = true
    local gripName = shortName(grip.name or "grip")
    if rec.activatedBy ~= nil then
        GripGesture.log(string.format("HIT %s +%.2fs held %.2fs", shortName(rec.activatedBy), rec.activatedAfter or 0, now - rec.riseAt))
    elseif next(rec.zones) ~= nil then
        local why = rec.excluded and "trigger held" or (rec.lockedAtRise and "grip locked" or "locked/too old")
        GripGesture.log(string.format("MISS %s in [%s]: %s", gripName, joinKeys(rec.zones), why))
    elseif next(rec.leftBefore) ~= nil then
        local parts = {}
        for _, text in pairs(rec.leftBefore) do parts[#parts + 1] = text end
        GripGesture.log(string.format("MISS %s left zone early: %s", gripName, table.concat(parts, "; ")))
    end
    return nil
end

function GripGesture:EvaluateInternal(context)
    local now = os.clock()
    if self.zone.isActive then
        self.zoneActiveAt = now
    end
    local squeeze = self:TrackSqueeze(now)

    -- If an excludeAction is provided and currently active, suppress this gesture entirely.
    -- This prevents LeftGripAction gestures from firing when LT is pressed (UEVR maps LT
    -- to the same /actions/default/in/Grip OpenVR action as the physical grip button).
    if self.excludeAction and self.excludeAction.isActive then
        return false
    end
    -- Timing tolerance (2026-09-21). The original rule needed the grip's rising edge and
    -- "hand inside the zone" to land on the SAME engine tick:
    --     not locked and gripGesture:JustActivated() and zone.isActive
    -- A fast reach-and-squeeze breaks that in both directions. The grip action is analog and
    -- trips early in the squeeze, so on a quick grab the edge usually fires a few ticks BEFORE
    -- the hand crosses into the zone (edge consumed, gesture never fires, even though the zone
    -- haptic then buzzes and the grip is held). And when pulling a weapon off the shoulder the
    -- hand can already be leaving the zone when the edge registers. Both windows are now
    -- tolerated; the squeeze is consumed on activation so it can only fire one gesture once.
    if self.gripGesture:JustActivated() then
        self.gripRiseAt = now
        self.graceCandidate = false
    elseif not self.gripGesture.isActive then
        self.gripRiseAt = nil -- squeeze released: nothing left to act on
        self.graceCandidate = false
    end

    -- Physical throws (stalker2/physical_throw.lua, 2026-10-12): with a grenade / bolt in hand the right grip is
    -- also the underarm throw, and its wind-up starts at the hip - right inside the sidearm zone. A right-grip
    -- gesture that would fire is therefore held until the grip is let go: released with the hand still = the
    -- gesture after all, released in a swing = the throw, and the gesture is dropped.
    if self.deferredFire then
        if self.gripGesture.isActive then return false end
        self.deferredFire = false
        return not (_G.physicalThrowWasSwing ~= nil and _G.physicalThrowWasSwing())
    end

    if self.wasActive then
        return self.zone.isActive and self.gripGesture.isActive
    end

    if self.gripRiseAt ~= nil and self.gripGesture.isActive and not self.gripGesture:IsLocked()
       and (now - self.gripRiseAt) <= GripGesture.GRIP_EARLY_GRACE then
        local fire = false
        if self.zone.isActive then
            fire = true
        elseif self.zoneActiveAt ~= nil and (now - self.zoneActiveAt) <= GripGesture.ZONE_EXIT_GRACE then
            -- "Just left the zone" only counts when no zone on this grip is active RIGHT NOW: a
            -- hand that brushed the chest zone on its way to the shoulder must fire the shoulder
            -- gesture, and evaluation order between gestures is arbitrary. So a grace candidate
            -- waits one tick, by which time every gesture has reported into the shared squeeze
            -- record, and stands down if any zone was active during this squeeze.
            if not self.graceCandidate then
                self.graceCandidate = true
            elseif squeeze == nil or next(squeeze.zones) == nil then
                fire = true
            end
        end
        if fire then
            if squeeze ~= nil and squeeze.activatedBy == nil then
                squeeze.activatedBy = tostring(self.name)
                squeeze.activatedAfter = now - self.gripRiseAt
            end
            self.gripRiseAt = nil
            self.graceCandidate = false
            if self.gripGesture == motionControllers.RightGripAction
               and _G.physicalThrowDefersGrip ~= nil and _G.physicalThrowDefersGrip() then
                self.deferredFire = true -- decided when the grip is released (see above)
                return false
            end
            return true
        end
    end
    return false
end

-- Seconds. GRIP_EARLY_GRACE: how long a squeeze started OUTSIDE the zone stays valid while the
-- hand travels into it. ZONE_EXIT_GRACE: how recently the hand must have been in the zone for a
-- squeeze that registers just after leaving it to still count - this is the quick "touch and go"
-- grab: the buzz fires on entry, human reaction to it is ~0.2 s, and by then a fast hand is
-- already on its way out. MIN_KEY_HOLD: shortest synthetic key press (used by the presets).
-- Defaults live in Config.gestureTiming and are tunable/saved from the dev panel.
require("Config.CONFIG")
local timing = (Config and Config.gestureTiming) or {}
GripGesture.GRIP_EARLY_GRACE = tonumber(timing.gripEarlyGrace) or 0.30
GripGesture.ZONE_EXIT_GRACE = tonumber(timing.zoneExitGrace) or 0.35
GripGesture.MIN_KEY_HOLD = tonumber(timing.minKeyHold) or 0.12
-- Key delivery (see stalker2/gesturekeys.lua): primer tap + delay before the real key, and the
-- verified retry for weapon-slot keys.
GripGesture.KEY_PRIME_DELAY = tonumber(timing.keyPrimeDelay) or 0.15
GripGesture.KEY_PRIMER = type(timing.keyPrimer) == "string" and timing.keyPrimer or "0x87"
GripGesture.KEY_RETRY = timing.keyRetry ~= false
-- Zero sticks/triggers while a gesture key is being delivered (gesturekeys.lua, step 4).
GripGesture.KEY_QUIET_STICKS = timing.keyQuietSticks ~= false

return GripGesture