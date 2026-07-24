--[[ 
Usage
    Drop the lib folder containing this file into your project folder
    Add code like this in your script:
        local linetracer = require("libs/linetracer")

    Line tracing is a common function in 3D applications. It is however, inefficient to
    have many line traces running every frame, that essentially do the same thing. This
    module allows multiple subscribers to share line traces based on camera/HMD/controllers.
    The trace is only run a single time per frame for each trace type and the results are shared
    with all subscribers, creating a very efficient system. If there are no subscribers, no traces are run.

    Custom trace types are supported: if `traceType` is not one of `linetracer.TraceType.*`, it is treated
    as a "custom" trace and `options.customCallback` must be provided. The callback should return
    `(location, rotation)` each tick which will be used as the trace origin.

    Set `includeFullDetails = true` in options if you need a fully populated hitResult (actor, normal, etc).

    Available functions:

    linetracer.subscribe(subscriberID, traceType, callback, options, priority) - subscribes to a line trace type
        subscriberID: unique identifier for this subscriber (string). Used to later unsubscribe
        traceType:
            - one of linetracer.TraceType.CAMERA, linetracer.TraceType.HMD, linetracer.TraceType.LEFT_CONTROLLER, linetracer.TraceType.RIGHT_CONTROLLER
            - OR any other string key to create a custom trace type (requires options.customCallback)
        callback: function(hitResult, hitLocation) that receives trace results each frame
        options: table containing:
            collisionChannel: number (default: 0)
            ignoreActors: table (default: {})
            traceComplex: bool (default: false)
            minHitDistance: number (default: 0)
            maxDistance: number (default: 10000)
            includeFullDetails: bool (default: false)
            customCallback: function()->(location, rotation) (required for custom trace types)
        priority: (optional) higher priority subscribers control the trace options (default: 0)
        example:
            linetracer.subscribe("reticule_system", linetracer.TraceType.CAMERA, 
                function(hitResult, hitLocation)
                    if hitLocation then
                        updateReticulePosition(hitLocation)
                    end
                end,
                { collisionChannel = 4, maxDistance = 10000 },
                10
            )

    linetracer.updateOptions(subscriberID, traceType, options, priority) - updates options for an existing subscription
        subscriberID: unique identifier for the subscriber
        traceType: the trace type being updated
        options: new options to set (replaces existing options)
        priority: (optional) new priority value
        returns: true if subscription exists and was updated, false otherwise
        example:
            linetracer.updateOptions("reticule_system", linetracer.TraceType.CAMERA, { maxDistance = 15000 }, 20)

    linetracer.unsubscribe(subscriberID, traceType) - unsubscribes from a specific trace type
        subscriberID: unique identifier for the subscriber
        traceType: the trace type to unsubscribe from
        example:
            linetracer.unsubscribe("reticule_system", linetracer.TraceType.CAMERA)

    linetracer.unsubscribeAll(subscriberID) - unsubscribes from all trace types
        subscriberID: unique identifier for the subscriber
        example:
            linetracer.unsubscribeAll("reticule_system")

    linetracer.hasSubscriptions() - checks if there are any active subscriptions
        returns: true if any subscriptions exist, false otherwise
        example:
            if linetracer.hasSubscriptions() then
                -- traces are running
            end

    linetracer.getSubscriberCount(traceType) - gets the number of subscribers for a specific trace type
        traceType: the trace type to check
        returns: number of subscribers
        example:
            local count = linetracer.getSubscriberCount(linetracer.TraceType.CAMERA)

    linetracer.getLastResult(traceType) - gets the cached result from the last trace
        traceType: the trace type to get results for
        returns: hitResult table or nil if no trace has been performed
        example:
            local hitResult = linetracer.getLastResult(linetracer.TraceType.CAMERA)
            if hitResult then
                print(hitResult.Location.X, hitResult.Location.Y, hitResult.Location.Z)
            end

    linetracer.TraceType - enum containing available trace types
        linetracer.TraceType.CAMERA - traces from player camera (not the HMD)
        linetracer.TraceType.HMD - traces from head mounted display (VR headset)
        linetracer.TraceType.LEFT_CONTROLLER - traces from left VR controller
        linetracer.TraceType.RIGHT_CONTROLLER - traces from right VR controller

    Notes:
        - Line traces are automatically updated every frame via registered tick callback
        - When multiple subscribers exist for the same trace type, the highest priority subscriber's options are used
        - All subscribers receive the same trace results regardless of their priority
        - Trace results are reused across frames for efficiency (no new allocations per tick)
        - Subscriptions are automatically cleaned up when all subscribers for a trace type are removed
    
    More Examples:
        -- Subscribe to camera-based line traces
        linetracer.subscribe("reticule_system", linetracer.TraceType.CAMERA, 
            function(hitResult, hitLocation)
                if hitLocation then
                    updateReticulePosition(hitLocation)
                end
            end,
            {
                collisionChannel = 4,
                traceComplex = false,
                maxDistance = 10000,
                ignoreActors = {pawn}
            }
        )

        -- Subscribe to left controller traces
        linetracer.subscribe("left_laser", linetracer.TraceType.LEFT_CONTROLLER,
            function(hitResult, hitLocation)
                leftLaser:updatePointer(controllerPos, hitLocation)
            end,
            { collisionChannel = 0, maxDistance = 5000 }
        )

        -- Unsubscribe when done
        linetracer.unsubscribe("reticule_system", linetracer.TraceType.CAMERA)

        -- Custom trace type (provide your own origin pose)
        linetracer.subscribe("custom_aim", "my_custom_trace", --note that "my_custom_trace" is not a predefined type but can be used elsewhere to reuse this trace
            function(hitResult, hitLocation)
                if hitLocation then
                    updateSomething(hitLocation)
                end
            end,
            {
                collisionChannel = 4,
                maxDistance = 20000,
                customCallback = function()
                    -- Return (location, rotation) for trace origin
                    return someLocation, someRotation
                end
            },
            5
        )

]]--


local uevrUtils = require("libs/uevr_utils")
local controllers = require("libs/controllers")

local M = {}

-- Trace types enum
M.TraceType = {
    CAMERA = "camera",
    HMD = "hmd",
    LEFT_CONTROLLER = "left_controller",
    RIGHT_CONTROLLER = "right_controller",

}

-- LineTracer class
local LineTracer = {}
LineTracer.__index = LineTracer

-- Module-level state
local activeSubscriptions = {}  -- { [traceType] = { [subscriberID] = {callback, options} } }
local reusableHitResults = {}  -- Reusable hitResult structures per trace type (also serves as result cache)

function M.new()
    local instance = setmetatable({}, LineTracer)
    return instance
end

-- Subscribe to a trace type
-- subscriberID: unique identifier for this subscriber
-- traceType: one of M.TraceType values
-- callback: function(hitResult, hitLocation, hitNormal, hitActor) to receive results
-- options: { collisionChannel, ignoreActors, traceComplex, minHitDistance, maxDistance, customCallback }
-- priority: higher values take precedence for options (default: 0)
function M.subscribe(subscriberID, traceType, callback, options, priority)
    if activeSubscriptions[traceType] == nil then
        activeSubscriptions[traceType] = {}
    end

    activeSubscriptions[traceType][subscriberID] = {
        callback = callback,
        options = options or {},
        priority = priority or 0
    }
end

-- Update options for an existing subscription
-- subscriberID: unique identifier for the subscriber
-- traceType: one of M.TraceType values
-- options: new options to set (merges with existing if partial)
-- priority: optional new priority value
function M.updateOptions(subscriberID, traceType, options, priority)
    if activeSubscriptions[traceType] == nil or activeSubscriptions[traceType][subscriberID] == nil then
        return false  -- Subscription doesn't exist
    end

    local subscription = activeSubscriptions[traceType][subscriberID]

    if options ~= nil then
        subscription.options = options
    end

    if priority ~= nil then
        subscription.priority = priority
    end

    return true
end

function M.setRotationOffset(subscriberID, traceType, rotator)
    if activeSubscriptions[traceType] == nil or activeSubscriptions[traceType][subscriberID] == nil then
        return false  -- Subscription doesn't exist
    end
    activeSubscriptions[traceType][subscriberID].options.rotationOffset = rotator
end

-- Unsubscribe from a trace type
function M.unsubscribe(subscriberID, traceType)
    --print("Linetracer: Unsubscribing subscriberID =", subscriberID, "from traceType =", traceType)
    if activeSubscriptions[traceType] ~= nil then
        --print("Linetracer: Before unsubscribe, activeSubscriptions[traceType] =", traceType, activeSubscriptions[traceType][subscriberID])
        activeSubscriptions[traceType][subscriberID] = nil

        -- Clean up empty subscription tables
        if next(activeSubscriptions[traceType]) == nil then
            --print("Linetracer: No more subscribers for traceType =", traceType, "removing entry")
            activeSubscriptions[traceType] = nil
        end
    end
end

-- Unsubscribe from all trace types
function M.unsubscribeAll(subscriberID)
    --print("Linetracer: Unsubscribing all for subscriberID =", subscriberID)
    for traceType, _ in pairs(activeSubscriptions) do
        --print("Linetracer: Unsubscribing from traceType =", traceType)
        M.unsubscribe(subscriberID, traceType)
    end
end

-- Check if there are any active subscriptions
function M.hasSubscriptions()
    return next(activeSubscriptions) ~= nil
end

-- Get the number of subscribers for a specific trace type
function M.getSubscriberCount(traceType)
    if activeSubscriptions[traceType] == nil then return 0 end

    local count = 0
    for _ in pairs(activeSubscriptions[traceType]) do
        count = count + 1
    end
    return count
end

-- -- Perform camera-based line trace
-- local function performCameraTrace(options, hitResult)
--     local playerController = uevr.api:get_player_controller(0)
--     if playerController == nil then return nil end

--     local playerCameraManager = playerController.PlayerCameraManager
--     if playerCameraManager == nil or playerCameraManager.GetCameraRotation == nil then
--         return nil
--     end

--     local cameraLocation = playerCameraManager:GetCameraLocation()
--     local cameraRotation = playerCameraManager:GetCameraRotation()
--     local forwardVector = kismet_math_library:GetForwardVector(cameraRotation)

--     local result = uevrUtils.getLineTraceHitResult(
--         cameraLocation,
--         forwardVector,
--         options.collisionChannel or 0,
--         options.traceComplex or false,
--         options.ignoreActors or {},
--         options.minHitDistance,
--         options.maxDistance or 10000,
--         options.includeFullDetails or false,
--         hitResult
--     )

--     return result
-- end

-- -- Perform HMD-based line trace
-- local function performHMDTrace(options, hitResult)
--     local hmdLocation = controllers.getControllerLocation(2)  -- 2 = HMD
--     local hmdRotation = controllers.getControllerRotation(2)

--     if hmdLocation == nil or hmdRotation == nil then
--         return nil
--     end

--     local forwardVector = kismet_math_library:GetForwardVector(hmdRotation)

--     local result = uevrUtils.getLineTraceHitResult(
--         hmdLocation,
--         forwardVector,
--         options.collisionChannel or 0,
--         options.traceComplex or false,
--         options.ignoreActors or {},
--         options.minHitDistance,
--         options.maxDistance or 10000,
--         options.includeFullDetails or false,
--         hitResult
--     )

--     return result
-- end

-- -- Perform controller-based line trace
-- local function performControllerTrace(handedness, options, hitResult)
--     local controllerLocation = controllers.getControllerLocation(handedness)
--     local controllerRotation = controllers.getControllerRotation(handedness)

--     if controllerLocation == nil or controllerRotation == nil then
--         return nil
--     end

--     local forwardVector = kismet_math_library:GetForwardVector(controllerRotation)

--     local result = uevrUtils.getLineTraceHitResult(
--         controllerLocation,
--         forwardVector,
--         options.collisionChannel or 0,
--         options.traceComplex or false,
--         options.ignoreActors or {},
--         options.minHitDistance,
--         options.maxDistance or 10000,
--         options.includeFullDetails or false,
--         hitResult
--     )

--     return result
-- end

local function traceFromLocationRotation(location, rotation, options, hitResult)
    if location == nil or rotation == nil then
        return nil
    end

    if options.rotationOffset ~= nil then
	    rotation = kismet_math_library:ComposeRotators(options.rotationOffset, rotation)
    end

    local forwardVector = kismet_math_library:GetForwardVector(rotation)

    return uevrUtils.getLineTraceHitResult(
        location,
        forwardVector,
        options.collisionChannel or 0,
        options.traceComplex or false,
        options.ignoreActors or {},
        options.minHitDistance or 0,
        options.maxDistance or 10000,
        options.includeFullDetails or false,
        hitResult
    )
end

local function performCameraTrace(options, hitResult)
    local playerController = uevr.api:get_player_controller(0)
    if playerController == nil then return nil end

    local pcm = playerController.PlayerCameraManager
    if pcm == nil or pcm.GetCameraRotation == nil then return nil end

    return traceFromLocationRotation( pcm:GetCameraLocation(), pcm:GetCameraRotation(), options, hitResult)
end

local function performHMDTrace(options, hitResult)
    return traceFromLocationRotation(controllers.getControllerLocation(2), controllers.getControllerRotation(2), options, hitResult)
end

local function performControllerTrace(handedness, options, hitResult)
    return traceFromLocationRotation( controllers.getControllerLocation(handedness), controllers.getControllerRotation(handedness), options, hitResult)
end

local function performCustomTrace(options, hitResult)
    if options.customCallback == nil then
        return nil
    end
    local location, rotation = options.customCallback()
    return traceFromLocationRotation(location, rotation, options, hitResult)
end

-- Execute a trace for a specific type and notify subscribers
local function executeTrace(traceType, subscribers)
    if subscribers == nil or next(subscribers) == nil then
        return
    end

    -- Find highest priority subscriber and use their options
    local highestPriority = -math.huge
    local highestPriorityOptions = {}
    for subscriberID, subData in pairs(subscribers) do
        local priority = subData.priority or 0
        if priority > highestPriority then
            highestPriority = priority
            highestPriorityOptions = subData.options
        end
    end
    local mergedOptions = highestPriorityOptions

    -- Get or create reusable hitResult for this trace type
    if reusableHitResults[traceType] == nil then
        reusableHitResults[traceType] = uevrUtils.get_struct_object("ScriptStruct /Script/Engine.HitResult")
    end
    local hitResult = reusableHitResults[traceType]

    -- Perform the appropriate trace
    -- linetrace returns a hitResult and a location vector. Even if the trace hits nothing, location is the end point of the trace
    local result = nil
    local location = nil
    if traceType == M.TraceType.CAMERA then
        result, location = performCameraTrace(mergedOptions, hitResult)
    elseif traceType == M.TraceType.HMD then
        result, location = performHMDTrace(mergedOptions, hitResult)
    elseif traceType == M.TraceType.LEFT_CONTROLLER then
        result, location = performControllerTrace(Handed.Left, mergedOptions, hitResult)
    elseif traceType == M.TraceType.RIGHT_CONTROLLER then
        result, location = performControllerTrace(Handed.Right, mergedOptions, hitResult)
    else
        result, location = performCustomTrace(mergedOptions, hitResult)
    end

    --print(location, result, traceType)
    -- Notify all subscribers
    --if result ~= nil then
        -- local hitLocation = result.Location or result.ImpactPoint
        -- local hitNormal = result.Normal or result.ImpactNormal
        -- local hitActor = result.HitObjectHandle and result.HitObjectHandle.Actor

        for subscriberID, subData in pairs(subscribers) do
            --print("Linetracer notifying subscriber:", subscriberID, "for trace type:", traceType)
            if subData.callback ~= nil then
                subData.callback(result, location)
            end
        end
    --end
end

-- Update all active traces (call from tick)
function M.update(delta)
    if not M.hasSubscriptions() then
        return
    end

    for traceType, subscribers in pairs(activeSubscriptions) do
        executeTrace(traceType, subscribers)
    end
end

-- Get cached trace result for a type (useful if you want result without waiting for callback)
function M.getLastResult(traceType)
    return reusableHitResults[traceType]
end

-- Register tick callback
uevrUtils.registerPreEngineTickCallback(function(engine, delta)
    M.update(delta)
end)

return M