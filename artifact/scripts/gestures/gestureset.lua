--[[
    GestureSet.lua
    Manages a collection of gestures in a graph structure
]]--

local GestureSet = {
    -- Collection of root/top-level gestures
    rootGestures = {},
    
    -- Whether the controller has been initialized
    initialized = false,
}

-- Initialize the controller with a list of root gestures
function GestureSet:Init()
    --TODO
    return self
end

-- Reset all gestures to their default state
function GestureSet:Reset()
    -- Reset all gestures (both top-level and dependencies)
    local visited = {}
    for _, gesture in ipairs(self.rootGestures) do
        self:ResetGesture(gesture, visited)
    end
    return self
end

-- Helper function to reset a gesture and its dependencies
function GestureSet:ResetGesture(gesture, visited)
    if not gesture or visited[gesture.id] then
        return
    end
    
    visited[gesture.id] = true
    
    -- Reset dependencies first
    for _, dep in ipairs(gesture.dependencies or {}) do
        if dep then
            self:ResetGesture(dep, visited)
        end
    end
    gesture:Reset()
end

-- Update all gestures in the graph (depth-first)
function GestureSet:Update(context)
    local visited = {}
    
    -- Update all root gestures (which will cascade to dependencies)
    for _, gesture in ipairs(self.rootGestures) do
        if gesture then
            gesture:Update(visited, context)
        end
    end
    
    return self
end

-- Create a new instance of the controller
function GestureSet:new(config)
    config = config or {}
    setmetatable(config, self)
    self.__index = self
    return config
end

return GestureSet