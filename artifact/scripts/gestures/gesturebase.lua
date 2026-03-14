--[[
    GestureBase.lua
    Base class for all gestures in the gesture system
]]--
local global_id_sequence = 0

GestureBase = {
    -- Unique identifier for the gesture
    id = nil,

    -- Name for this gesture (for debugging)
    name = "Generic Gesture",

    -- Whether this gesture is currently active/detected
    isActive = false,

    -- Previous state for detecting transitions
    wasActive = false,

    -- Whether the gesture is locked in its current state
    isLocked = false,

    --TODO might be a good idea to have it in different type of classes
    executionCallBack = nil,

    -- List of dependencies (other gestures this one depends on)
    dependencies = {}
}

function GestureBase:Update(visited, context)
    if visited[self.id] then
        return
    end
    visited[self.id] = true
    for _, dep in ipairs(self.dependencies) do
        if dep then
            dep:Update(visited, context)
        end
    end
    self:Evaluate(context)
    self:Execute(context)
end

function GestureBase:Execute(context)
    if self.executionCallBack then
        self.executionCallBack(self, context)
    end
end

-- Update the gesture state (should be called from GestureGraph)
function GestureBase:Evaluate(context)
    -- Save previous state
    self.wasActive = self.isActive

    -- Evaluate current state
    self.isActive = self:EvaluateInternal(context)

    -- Return true if state changed
    return self.isActive
end

function GestureBase:EvaluateInternal(context)
    return false
end

-- Lock the gesture in its current state
function GestureBase:Lock()
    self.isLocked = true
end

-- Unlock the gesture to allow state changes
function GestureBase:Unlock()
    self.isLocked = false
end

function GestureBase:IsLocked()
    return self.isLocked
end

function GestureBase:Reset()
    self.isActive = false
    self.wasActive = false
    self.isLocked = false
end

-- Returns true if gesture just became active this frame
function GestureBase:JustActivated()
    return self.isActive and not self.wasActive
end

-- Returns true if gesture just became inactive this frame
function GestureBase:JustDeactivated()
    return not self.isActive and self.wasActive
end

function GestureBase:SetExecutionCallback(callback)
    if callback and type(callback) ~= "function" then
        error("Execution callback must be a function")
    end
    self.executionCallBack = callback
    return self -- Allow method chaining
end

function GestureBase:AddDependency(dependency)
    table.insert(self.dependencies, dependency)
    return self -- Allow method chaining
end


-- Create a new instance of the gesture
function GestureBase:new(config)
    config = config or {}
    config.dependencies = config.dependencies or {}
    global_id_sequence = global_id_sequence + 1
    config.id = global_id_sequence
    setmetatable(config, self)
    self.__index = self
    return config
end

return GestureBase