--Laser pointer inspiration and code snippets courtesy of Gwizdek

--[[
Usage
    Drop the libs folder containing this file into your project folder
    Add code like this in your script:
        local laser = require("libs/laser")

    This module provides a simple, reusable “laser pointer” implementation built from an
    Engine `CapsuleComponent`. It supports fixed-length lasers as well as lasers whose
    length/endpoint is driven by shared line traces via `libs/linetracer`.

    If the laser is using a traced length mode, it subscribes to `linetracer` and updates
    its endpoint each frame from the trace hit location. Optionally, it can spawn a target
    effect (currently supports `type = "particle"`) that is positioned at the laser end.

    Available functions:

    laser.new(options) -> Laser
        Creates a laser instance and auto-creates the underlying component.
        options:
            laserLengthOffset: number (default: 0)
                Additional length added to computed hit distance.
            laserColor: string|number (default: "#0000FFFF")
                Hex string or integer color; applied to CapsuleComponent.ShapeColor.
            relativePosition: FVector|table (default: vector(0,0,0))
                Component relative offset before the internal “half-height” offset.
            target: table|nil (optional)
                { type = "particle", options = <particles.new options> }
            lengthSettings: table (optional)
                type: one of laser.LengthType (default: FIXED)
                fixedLength: number (default: 50)
                lengthPercentage: number (default: 1.0)
                customTargetingFunctionID: string|nil
                    Used as the `linetracer` traceType key when using CUSTOM targeting.
                customTargetingOptions: table (optional)
                    collisionChannel, traceComplex, maxDistance, ignoreActors,
                    includeFullDetails, minHitDistance,
                    customCallback

        Notes:
            - If lengthSettings.type is not FIXED, this module will subscribe to `linetracer`.
            - For CUSTOM targeting, set `customTargetingOptions.customCallback` to a function
              returning `(location, rotation)` each tick. Any traceType key not in
              `linetracer.TraceType` will be treated as a custom trace.

    laser.setLaserLengthPercentage(val)
        Sets a global multiplier applied to all laser lengths (clamped 0.0–1.0).

    laser.LengthType - enum:
        FIXED, CAMERA, LEFT_CONTROLLER, RIGHT_CONTROLLER, HUD, CUSTOM
        (Non-standard types fall back to CUSTOM behavior and require customCallback.)

    Laser instance methods (returned by laser.new):
        laser:getComponent() -> component
        laser:destroy()
        laser:attachTo(mesh, socketName, attachType, weld)
        laser:updatePointer(origin, target)
            Manually update laser transform/length between two world points.
        laser:setTargetLocation(location)
            Updates length based on distance from component to `location` and moves target effect.
        laser:setLength(length)
        laser:setRelativePosition(pos)
        laser:setVisibility(isVisible)
        laser:setLaserLengthOffset(val)
        laser:setLaserColor(val)
        laser:updateCustomTargetingOptions(options)
        laser:getLastHitResult() -> hitResult|nil

    Examples:
        -- Fixed-length laser
        local laser = require("libs/laser")
        local myLaser = laser.new({
            laserColor = "#00FFFFFF",
            lengthSettings = { type = laser.LengthType.FIXED, fixedLength = 80 }
        })
        myLaser:attachTo(controllerMesh, "", 0, false)

        -- Camera-traced laser 
        local myLaser2 = laser.new({
            laserColor = "#FF00FFFF",
            lengthSettings = {
                type = laser.LengthType.CAMERA,
                customTargetingOptions = { collisionChannel = 0, maxDistance = 10000 }
            }
        })
        myLaser2:attachTo(controller.getController(Handed.Right))

        -- Camera-traced laser with a particle at the end
        local myLaser3 = laser.new({
            laserColor = "#FF00FFFF",
            target = { type = "particle", options = { /* particles options */ } },
            lengthSettings = {
                type = laser.LengthType.CAMERA,
                customTargetingOptions = { collisionChannel = 4, maxDistance = 10000 }
            }
        })
        myLaser3:attachTo(controller.getController(Handed.Right))

]]--

local uevrUtils = require("libs/uevr_utils")
local particles = require("libs/particles")
local linetracer = require("libs/linetracer")

local M = {}

M.LengthType = {
    FIXED = 1,
    CAMERA = 2,
    LEFT_CONTROLLER = 3,
    RIGHT_CONTROLLER = 4,
    HUD = 5,
    CUSTOM = 6
}

local laserLengthPerecentage = 1.0 --global multiplier for laser length 0.0 - 1.0

local Laser = {}
Laser.__index = Laser

local function normalizeColor(val)
    if type(val) == "string" then return val end
    return uevrUtils.intToHexString(val)
end

-- options.target = {type="particle", options={...}} -- optional target to spawn at laser end
function M.new(options)
    options = options or {}
    local self = setmetatable({
        component = nil,
        targetComponent = nil,
        laserLengthOffset = options.laserLengthOffset or 0,
        laserColor = normalizeColor(options.laserColor or "#0000FFFF"),
        relativePosition = options.relativePosition or uevrUtils.vector(0,0,0),
        target = options.target or nil,
        lengthSettings = {
            type = (options.lengthSettings and options.lengthSettings.type) or M.LengthType.FIXED,
            fixedLength = (options.lengthSettings and options.lengthSettings.fixedLength) or 50,
            lengthPercentage = (options.lengthSettings and options.lengthSettings.lengthPercentage) or 1.0,
            customTargetingFunctionID = (options.lengthSettings and options.lengthSettings.customTargetingFunctionID) or nil,
            customTargetingOptions = {
                collisionChannel = (options.lengthSettings and options.lengthSettings.customTargetingOptions and options.lengthSettings.customTargetingOptions.collisionChannel) or 0,
                traceComplex = (options.lengthSettings and options.lengthSettings.customTargetingOptions and options.lengthSettings.customTargetingOptions.traceComplex) or false,
                maxDistance = (options.lengthSettings and options.lengthSettings.customTargetingOptions and options.lengthSettings.customTargetingOptions.maxDistance) or 10000,
                ignoreActors = (options.lengthSettings and options.lengthSettings.customTargetingOptions and options.lengthSettings.customTargetingOptions.ignoreActors) or {},
                includeFullDetails = (options.lengthSettings and options.lengthSettings.customTargetingOptions and options.lengthSettings.customTargetingOptions.includeFullDetails) or false,
                minHitDistance = (options.lengthSettings and options.lengthSettings.customTargetingOptions and options.lengthSettings.customTargetingOptions.minHitDistance) or 0,
                customCallback = (options.lengthSettings and options.lengthSettings.customTargetingOptions and options.lengthSettings.customTargetingOptions.customCallback) or nil
            }
        },
        lineTracerCallbackFn = nil,
        isActiveTrace = false,

    }, Laser)

    self:create() -- auto-create component
    return self
end

function Laser:lineTracerCallback(hitResult, hitLocation)
    --print("Laser:lineTracerCallback called with hitResult =", hitResult, "hitLocation =", hitLocation)
    if hitLocation ~= nil then
        self:setTargetLocation(hitLocation)
    end
    self.lastHitResult = hitResult
end

function Laser:getLastHitResult()
    return self.lastHitResult
end

function Laser:getLineTraceType()
    local lineTraceType = self.lengthSettings.type == M.LengthType.CAMERA and linetracer.TraceType.CAMERA or
        self.lengthSettings.type == M.LengthType.LEFT_CONTROLLER and linetracer.TraceType.LEFT_CONTROLLER or
        self.lengthSettings.type == M.LengthType.RIGHT_CONTROLLER and linetracer.TraceType.RIGHT_CONTROLLER or
        self.lengthSettings.type == M.LengthType.HUD and linetracer.TraceType.HUD or
        nil
    return lineTraceType
end

function Laser:create()
    if self.component == nil then
        self.component = uevrUtils.create_component_of_class("Class /Script/Engine.CapsuleComponent")
        local c = uevrUtils.getValid(self.component)
        if c ~= nil then
            c:SetCapsuleSize(0.1, 0, true)
            c:SetVisibility(true, true)
            c:SetHiddenInGame(false, false)
            c.bAutoActivate = true
            c:SetGenerateOverlapEvents(false)
            c:SetCollisionEnabled(ECollisionEnabled.NoCollision)
            c:SetRenderInMainPass(true)
            c.bRenderInDepthPass = true
            c.ShapeColor = uevrUtils.hexToColor(self.laserColor)

            c:SetRenderCustomDepth(true)
            c:SetCustomDepthStencilValue(100)
            c:SetCustomDepthStencilWriteMask(ERendererStencilMask.ERSM_255)
            c:SetCapsuleHalfHeight(50, false) -- give it an initial length so it can be seen even if settings are bad
            c.RelativeRotation = uevrUtils.rotator(90, 0, 0)
            self:setRelativePosition(uevrUtils.vector(0,0,0))

            self.attachmentComponent = uevrUtils.create_component_of_class("Class /Script/Engine.SceneComponent")
            if self.attachmentComponent ~= nil then
                c:K2_AttachTo(self.attachmentComponent, uevrUtils.fname_from_string(""), 0, false)
            end

        end

    end
    if self.target ~= nil then
        if self.targetComponent == nil then
            if self.target.type == "particle" then
                self.targetComponent = particles.new(self.target.options or {})
            end
            -- self.targetComponent = particles.new({
            --     particleSystemAsset = "ParticleSystem /Game/Art/VFX/ParticleSystems/Weapons/Projectiles/Plasma/PS_Plasma_Ball.PS_Plasma_Ball",
            --     scale = {0.04, 0.04, 0.04},
            --     autoActivate = true
            -- })
        end
    end

    if self.lengthSettings.type ~= M.LengthType.FIXED then
        -- Create and store the callback function once
        if self.lineTracerCallbackFn == nil then
            self.lineTracerCallbackFn = function(hitResult, hitLocation)
                return self:lineTracerCallback(hitResult, hitLocation)
            end
        end

        self.lineTraceType = self:getLineTraceType()
        if self.lineTraceType == nil then --its a custom type
        --if theres no custom callback then treat it as fixed
            if self.lengthSettings.customTargetingOptions.customCallback == nil then
                print("No custom callback found for laser line tracer, defaulting to FIXED length")
                self.lineTraceType = M.LengthType.FIXED
            end
            self.lineTraceType = self.lengthSettings.customTargetingFunctionID or tostring(self) -- just need a unique id
        end
        if self.lineTraceType ~= M.LengthType.FIXED then
            self.isActiveTrace = true
            --print("Subscribing laser line tracer: " .. tostring(self.lineTraceType))
            linetracer.subscribe(tostring(self), self.lineTraceType,
            self.lineTracerCallbackFn,
            self.lengthSettings.customTargetingOptions, 1)
        end
    end

    if self.lengthSettings.type == M.LengthType.FIXED then
        self:setLength(self.lengthSettings.fixedLength)
    end

    return self.component
end

function Laser:destroy()
    local c = uevrUtils.getValid(self.component)
    if c ~= nil then
        c:DetachFromParent(false,false)
        uevrUtils.destroyComponent(self.component, true, true)
        self.component = nil
    end
    if self.targetComponent ~= nil then
        self.targetComponent:destroy()
        self.targetComponent = nil
    end
    if self.attachmentComponent ~= nil then
        uevrUtils.destroyComponent(self.attachmentComponent, true, true)
        self.attachmentComponent = nil
    end
    self.isActiveTrace = false
    linetracer.unsubscribeAll(tostring(self))
end

function Laser:attachTo(mesh, socketName, attachType, weld)
    --local c = uevrUtils.getValid(self.component)
    local c = uevrUtils.getValid(self.attachmentComponent)
    local m = uevrUtils.getValid(mesh)
    if c ~= nil and m ~= nil then
		return c:K2_AttachTo(m, uevrUtils.fname_from_string(socketName or ""), attachType or 0, weld or false)
    end
end

function Laser:getComponent()
    return self.component
end

function Laser:updateCustomTargetingOptions(options)
    if options == nil then return end

    linetracer.updateOptions(tostring(self), self.lineTraceType, options)
end

-- Normally the laser will update itself via line tracer, but this allows manual updating
-- Generally a good idea to disable line tracing when using this function with Laser:setActiveTrace(false)
-- or use FIXED mode
function Laser:draw(origin, target)
    local c = uevrUtils.getValid(self.component)
    if c ~= nil and origin ~= nil and target ~= nil then
        local hitDistance = kismet_math_library:Vector_Distance(origin, target) + self.laserLengthOffset
        c:SetCapsuleHalfHeight(hitDistance / 2, false)
        c:K2_SetWorldLocation(
            uevrUtils.vector(
                origin.X + ((target.X-origin.X)/2),
                origin.Y + ((target.Y-origin.Y)/2),
                origin.Z + ((target.Z-origin.Z)/2)
            ),
            false, reusable_hit_result, false
        )
        local rotation = kismet_math_library:Conv_VectorToRotator(
            uevrUtils.vector(target.X-origin.X, target.Y-origin.Y, target.Z-origin.Z)
        )
        rotation.Pitch = rotation.Pitch + 90
        c:K2_SetWorldRotation(rotation, false, reusable_hit_result, false)
    end
end

function Laser:updateRelativePositionOffset()
    local c = uevrUtils.getValid(self.component)
    if c ~= nil and c.GetUnscaledCapsuleHalfHeight ~= nil then
        c.RelativeLocation = uevrUtils.vector(self.relativePosition)
        c.RelativeLocation.X = c.RelativeLocation.X + c:GetUnscaledCapsuleHalfHeight()
    end
end

function Laser:setRelativePosition(pos)
    local c = uevrUtils.getValid(self.component)
    if c ~= nil then
        self.relativePosition = pos
        self:updateRelativePositionOffset()
    end
end
function Laser:setRelativeRotation(rot)
    local c = uevrUtils.getValid(self.attachmentComponent)
    if c ~= nil then
        c.RelativeRotation = rot
    end
end

function Laser:setLength(length)
    local c = uevrUtils.getValid(self.component)
    if c ~= nil and c.SetCapsuleHalfHeight then
        c:SetCapsuleHalfHeight((length / 2) * (laserLengthPerecentage * (self.lengthSettings.lengthPercentage or 1.0) / 2), false)
    end
end

function Laser:setVisibility(isVisible)
    local c = uevrUtils.getValid(self.component)
    if c ~= nil then
        c:SetVisibility(isVisible, false)
    end
    if self.targetComponent ~= nil then
        self.targetComponent:setVisibility(isVisible)
    end
end

function Laser:setActiveTrace(isActive)
    --print("Laser:setActiveTrace called with isActive =",self, isActive)
    if self.isActiveTrace == isActive then
        return
    end
    self.isActiveTrace = isActive

    if isActive and self.lineTraceType ~= M.LengthType.FIXED then
        linetracer.subscribe(tostring(self), self.lineTraceType,
            self.lineTracerCallbackFn,
            self.lengthSettings.customTargetingOptions, 1)
    else
        linetracer.unsubscribeAll(tostring(self))
    end

end

function Laser:setLaserLengthOffset(val)
    self.laserLengthOffset = val or 0
end

function Laser:setLaserColor(val)
    self.laserColor = normalizeColor(val)
    local c = uevrUtils.getValid(self.component)
    if c ~= nil then
        c.ShapeColor = uevrUtils.hexToColor(self.laserColor)
    end
end

-- Note that this function does not actually draw the laser to the target location
-- It finds the distance to the target location and sets the laser length accordingly
-- If you want to draw a laser between two points, use Laser:draw(origin, target)
function Laser:setTargetLocation(location)
    --calculate the distance between the laser's current location and the target location and set the distance from that
    local c = uevrUtils.getValid(self.component)
    if c ~= nil and location ~= nil and c.K2_GetComponentLocation ~= nil then
        local cWorldLocation = c:K2_GetComponentLocation()
        local hitDistance = kismet_math_library:Vector_Distance(cWorldLocation, location) + self.laserLengthOffset
        self:setLength(hitDistance * 1.9) --not sure why 1.9 is the right number here. Maybe has to do with endcaps?
        self:updateRelativePositionOffset()

        if self.targetComponent ~= nil then
            self.targetComponent:setWorldLocation(location)
        end
    end

    -- if particleComponent == nil then
    --     particleComponent = particles.new({
    --         particleSystemAsset = "ParticleSystem /Game/Art/VFX/ParticleSystems/Weapons/Projectiles/Plasma/PS_Plasma_Ball.PS_Plasma_Ball",
    --         scale = {0.04, 0.04, 0.04},
    --         autoActivate = true
    --     })
    -- end
    -- if particleComponent ~= nil then
    --     particleComponent:setWorldLocation(location)
    -- end
    -- if debugSphereComponent == nil then
	-- 	--debugSphereComponent = uevrUtils.createStaticMeshComponent("StaticMesh /Engine/EngineMeshes/Sphere.Sphere")
    --     debugSphereComponent = uevrUtils.create_component_of_class("Class /Script/Engine.SceneComponent")
    --     --"Class /Script/Engine.SceneComponent")--
	-- 	if debugSphereComponent ~= nil then
    --         -- debugSphereComponent.BoundsScale = 10
    --         -- debugSphereComponent:SetVisibility(true,true)
    --         -- debugSphereComponent:SetHiddenInGame(false,true)
	-- 		-- uevrUtils.set_component_relative_transform(debugSphereComponent, nil, nil, {X=0.01, Y=0.01, Z=0.01})
	-- 		-- --uevrUtils.set_component_relative_transform(debugSphereComponent, nil, nil, {X=1, Y=1, Z=1})
    --     end

    --     local ps = uevrUtils.getLoadedAsset("ParticleSystem /Game/Art/VFX/ParticleSystems/Weapons/Projectiles/Plasma/PS_Plasma_Ball.PS_Plasma_Ball")
    --     particleComponent = Statics:SpawnEmitterAttached(
    --         ps, debugSphereComponent, uevrUtils.fname_from_string(""), uevrUtils.vector(0, 0, 0 ), uevrUtils.rotator(0, 0, 0), uevrUtils.vector( 0.04, 0.04, 0.04 ), 0, true, 0, true)

    --     if particleComponent ~= nil then
    --         particleComponent:SetAutoActivate(true)
    --         particleComponent.SecondsBeforeInactive = 0.0
    --         particleComponent:SetCollisionEnabled(3)
    --         particleComponent:SetCollisionResponseToAllChannels(2)
    --         particleComponent:SetRenderInMainPass(true)
    --         particleComponent.bRenderInDepthPass = true
    --     end

    -- end
    -- if debugSphereComponent ~= nil then
    --     debugSphereComponent:K2_SetWorldLocation(location, false, reusable_hit_result, false)
    -- end


end

function M.setLaserLengthPercentage(val)
    laserLengthPerecentage = math.max(0.0, math.min(1.0, val or 1.0))
end

return M