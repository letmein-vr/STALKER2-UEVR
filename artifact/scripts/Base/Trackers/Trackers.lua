--require("UEHelper")
TrackersInit=true
local controllers = require("libs/controllers")

-- Initialize globals that other scripts depend on
left_hand_component = nil
right_hand_component = nil
hmd_component = nil

-- Start auto-monitoring to ensure controllers always exist
controllers.autoMonitorHands()

-- Ensure they are created immediately if possible
controllers.createController(0)
controllers.createController(1)
controllers.createController(2)

-- Initialize globals IMMEDIATELY to avoid nil access in other scripts
left_hand_component = controllers.getController(0)
right_hand_component = controllers.getController(1)
hmd_component = controllers.getController(2)

-- Update globals every tick to ensure they point to valid components
-- (In case controllers are destroyed/recreated by level changs)
uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
    left_hand_component = controllers.getController(0)
    right_hand_component = controllers.getController(1)
    
    -- Controller 2 returns SceneComponent for HMD
    hmd_component = controllers.getController(2) 
end)

-- Handle Level Changes via Controllers lib (it handles it internally, but we can hook if needed)
-- controllers.onLevelChange handled internally by libs/controllers registration

print("Trackers Initialized (Proxied to libs/controllers)")