--require("UEHelper")
TrackersInit=true
local controllers = require("libs/controllers")

-- Initialize globals that other scripts depend on
left_hand_component = nil
right_hand_component = nil
hmd_component = nil

-- Start auto-monitoring to ensure controllers always exist
controllers.autoMonitorHands()

-- DO NOT create controllers here in the main chunk: spawning actors at script-load
-- time (pre-first-tick, on the d3d-init thread) deadlocks the game under newer UEVR
-- builds (deferred-UObject-adoption mode). Creation is deferred to the first
-- engine tick below; autoMonitorHands() above also retries every second after that.
local controllersInitialized = false

-- Update globals every tick to ensure they point to valid components
-- (In case controllers are destroyed/recreated by level changs)
uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
    if not controllersInitialized then
        controllersInitialized = true
        controllers.createController(0)
        controllers.createController(1)
        controllers.createController(2)
    end
    -- Cached lookup first: getController(id) with no second arg is a full find_all_of
    -- scan of every MotionControllerComponent in the world, and this ran three of them
    -- EVERY tick. Fall back to the scan only while the cache is empty (the first tick
    -- or two after a script reset, before createController() has re-adopted the
    -- surviving actors into controllers' actors[] table).
    left_hand_component = controllers.getController(0, true) or controllers.getController(0)
    right_hand_component = controllers.getController(1, true) or controllers.getController(1)

    -- Controller 2 returns SceneComponent for HMD
    hmd_component = controllers.getController(2)
end)

-- Handle Level Changes via Controllers lib (it handles it internally, but we can hook if needed)
-- controllers.onLevelChange handled internally by libs/controllers registration

print("Trackers Initialized (Proxied to libs/controllers)")