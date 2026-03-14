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

function GripGesture:EvaluateInternal(context)
    local justActivated = not self.gripGesture:IsLocked() and self.gripGesture:JustActivated() and self.zone.isActive
    if justActivated then
        return true
    end
    return self.wasActive and self.zone.isActive and self.gripGesture.isActive
end

return GripGesture