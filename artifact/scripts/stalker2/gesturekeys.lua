-- Synthetic key presses for grip gestures (shared by presets/presetRH.lua and presetLH.lua).
--
-- History of why this is more than "key down on activate, key up on deactivate" (all 2026-09-21,
-- each step proven with the dev-panel gesture log):
--   1. Minimum hold. A quick grab leaves the zone again within a tick or two, which produced a
--      ~11 ms key tap the game sometimes dropped. The release is deferred until the key has been
--      down for GripGesture.MIN_KEY_HOLD.
--   2. Priming. Even a correctly detected gesture with a 0.14 s key hold was ignored by the game
--      (log: "HIT Flashlight +0.00s", "key L down" ... "key L up", light stayed off). The game
--      tracks the active input device; UEVR feeds it gamepad input every frame, and the first
--      keyboard event after gamepad activity is spent on switching device instead of acting
--      (Entry.lua already documents the reverse effect for an injected 'R'). So an unbound
--      "primer" key is tapped first and the real key follows GripGesture.KEY_PRIME_DELAY later.
--   3. Verified retry for weapon slots. Those have an observable outcome (the equipped weapon),
--      so if the game still ignored the press it is sent once more.
require("Config.CONFIG")
local GripGesture = require("stalker2.gripgesture")
local gameState = require("stalker2.gamestate")
local uevrUtils = require("libs/uevr_utils")

local M = {}

local WEAPON_SLOT_KEYS = { ["1"] = true, ["2"] = true, ["3"] = true, ["4"] = true, ["5"] = true, ["6"] = true }
local OUTCOME_CHECK_MS = 1500

local function equippedWeaponId()
    local id = "none"
    pcall(function()
        local mesh = gameState:GetEquippedWeapon()
        if mesh ~= nil then
            local info = gameState:GetWeaponCache(mesh)
            id = (info and info.name) or "unknown"
        end
    end)
    return tostring(id)
end

local function minHold()
    return tonumber(GripGesture.MIN_KEY_HOLD) or 0.12
end

local function primeDelay()
    return tonumber(GripGesture.KEY_PRIME_DELAY) or 0
end

--   4. Analog quiet window. Priming only holds if NO gamepad activity lands between the primer
--      and the real key: standing still that is true, but while walking/running the left stick
--      reports a non-zero axis every frame, the game flips straight back to "gamepad" and the
--      real key is again spent on the device switch ("gestures only work when I stand still").
--      So from the primer until the key is released the sticks/triggers are zeroed in
--      on_xinput_get_state (Entry.lua calls M.applyAnalogSuppression). Buttons are left alone:
--      a held button produces no new events. Costs ~0.3 s of coasting while moving.
local suppressAnalogUntil = 0
local SUPPRESS_MARGIN = 0.05 -- seconds kept quiet after the key-up

local function suppressAnalogFor(seconds)
    if GripGesture.KEY_QUIET_STICKS == false then return end
    local untilT = os.clock() + seconds
    if untilT > suppressAnalogUntil then suppressAnalogUntil = untilT end
end

-- Called from Entry.lua's on_xinput_get_state (gameplay only).
function M.applyAnalogSuppression(state)
    if suppressAnalogUntil == 0 then return end
    if os.clock() >= suppressAnalogUntil then
        suppressAnalogUntil = 0
        return
    end
    local pad = state.Gamepad
    pad.sThumbLX = 0
    pad.sThumbLY = 0
    pad.sThumbRX = 0
    pad.sThumbRY = 0
    pad.bLeftTrigger = 0
    pad.bRightTrigger = 0
end

local function sendPrimer()
    suppressAnalogFor(primeDelay() + minHold() + SUPPRESS_MARGIN)
    local primer = GripGesture.KEY_PRIMER
    if type(primer) ~= "string" or primer == "" then return end
    pcall(function()
        uevr.api:dispatch_custom_event(primer, "down")
        uevr.api:dispatch_custom_event(primer, "up")
    end)
end

local function release(gesture, key, note)
    gameState:SendKeyUp(key)
    GripGesture.log("key " .. tostring(key) .. " up " .. note)
    gesture.gripGesture:Unlock()
    gesture.keyState = nil
    gesture.keyDownAt = nil
    gesture.releaseRequested = false
end

-- Releases now, or once the key has been down for the minimum hold.
local function scheduleRelease(gesture, key, token)
    local heldFor = os.clock() - (gesture.keyDownAt or 0)
    local remaining = minHold() - heldFor
    if remaining > 0 then
        uevrUtils.setTimeout(math.ceil(remaining * 1000), function()
            if gesture.keyPressToken == token and gesture.keyState == "down" and not gesture.isActive then
                release(gesture, key, "(min hold)")
            end
        end)
    else
        release(gesture, key, string.format("after %.2fs", heldFor))
    end
end

-- One complete tap that is not tied to the gesture's state (used for the verified retry).
local function tap(key)
    sendPrimer()
    uevrUtils.setTimeout(math.ceil(primeDelay() * 1000) + 1, function()
        gameState:SendKeyDown(key)
        uevrUtils.setTimeout(math.ceil(minHold() * 1000) + 1, function()
            gameState:SendKeyUp(key)
        end)
    end)
end

local function watchOutcome(key, allowRetry)
    if not WEAPON_SLOT_KEYS[tostring(key)] then return end
    local before = equippedWeaponId()
    uevrUtils.setTimeout(OUTCOME_CHECK_MS, function()
        local after = equippedWeaponId()
        if after ~= before then
            GripGesture.log("key " .. tostring(key) .. " OK: " .. before .. " -> " .. after)
        elseif allowRetry and GripGesture.KEY_RETRY ~= false then
            GripGesture.log("key " .. tostring(key) .. " IGNORED (still " .. after .. ") - retrying")
            tap(key)
            watchOutcome(key, false)
        else
            GripGesture.log("key " .. tostring(key) .. " IGNORED by game (still " .. after .. ")")
        end
    end)
end

local function pressNow(gesture, key, token)
    if gesture.keyPressToken ~= token then return end -- superseded by a newer activation
    suppressAnalogFor(minHold() + SUPPRESS_MARGIN)
    gameState:SendKeyDown(key)
    gesture.keyState = "down"
    gesture.keyDownAt = os.clock()
    GripGesture.log("key " .. tostring(key) .. " down")
    watchOutcome(key, true)
    if gesture.releaseRequested then
        scheduleRelease(gesture, key, token)
    end
end

-- key: luakey key name ('L', '3', "0x1B" ...). gesture_config_key: optional Config.gestures flag.
function M.createKeyPressCB(key, gesture_config_key)
    return function(gesture, context)
        if gesture:JustActivated() then
            -- Config gate applies to ACTIVATION ONLY. It used to sit above both branches,
            -- which meant toggling a gesture off in the dev UI while its key was held DOWN
            -- skipped the release below and stranded that key actuated in UE's input system.
            if gesture_config_key and not Config.gestures[gesture_config_key] then
                return
            end
            gesture.keyPressToken = (gesture.keyPressToken or 0) + 1
            local token = gesture.keyPressToken
            gesture.releaseRequested = false
            gesture.gripGesture:Lock()

            local delay = primeDelay()
            if delay > 0 then
                gesture.keyState = "priming"
                sendPrimer()
                uevrUtils.setTimeout(math.ceil(delay * 1000), function()
                    pressNow(gesture, key, token)
                end)
            else
                pressNow(gesture, key, token)
            end
        elseif gesture:JustDeactivated() then
            if gesture.keyState == "priming" then
                -- Real key not down yet: pressNow() will schedule the release itself.
                gesture.releaseRequested = true
            elseif gesture.keyState == "down" then
                scheduleRelease(gesture, key, gesture.keyPressToken)
            else
                -- Nothing was sent (config-gated activation). Release unconditionally anyway -
                -- never gate a key-up on config.
                gameState:SendKeyUp(key)
                gesture.gripGesture:Unlock()
            end
        end
    end
end

return M
