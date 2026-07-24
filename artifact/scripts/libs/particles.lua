--[[
    local particles = require("libs/particles")

    -- Create particle system
    local plasma = particles.new({
        particleSystemAsset = "ParticleSystem /Game/Art/VFX/ParticleSystems/Weapons/Projectiles/Plasma/PS_Plasma_Ball.PS_Plasma_Ball",
        scale = {0.04, 0.04, 0.04},
        autoActivate = true
    })

    -- Set location
    plasma:setWorldLocation({100, 200, 300})

    -- Attach to mesh
    plasma:attachTo(weaponMesh, "muzzle_socket")

    -- Control parameters
    plasma:setFloatParameter("Size", 2.0)
    plasma:setVectorParameter("Color", {1, 0, 0})

    -- Cleanup
    plasma:destroy()
]]--
local uevrUtils = require("libs/uevr_utils")
require("libs/enums/unreal")

local M = {}

local ParticleSystem = {}
ParticleSystem.__index = ParticleSystem

-- Constructor for new particle system instance
-- options: {
--   particleSystemAsset: string path to particle system asset (required)
--   scale: vector {x,y,z} for particle scale (default: {1,1,1})
--   rotation: rotator {pitch,yaw,roll} for particle rotation (default: {0,0,0})
--   location: vector {x,y,z} for relative location (default: {0,0,0})
--   autoActivate: boolean (default: true)
--   collisionEnabled: ECollisionEnabled value (default: ECollisionEnabled.QueryAndPhysics)
--   collisionResponse: ECollisionResponse value (default: ECollisionResponse.Block
--   poolMethod: EPSCPoolMethod value (default: EPSCPoolMethod.None)
-- }
function M.new(options)
    options = options or {}

    if not options.particleSystemAsset then
        --error("particleSystemAsset is required")
        print("Error: particleSystemAsset is required to create ParticleSystem")
        return
    end

    local self = setmetatable({
        particleComponent = nil,
        anchorComponent = nil,
        particleSystemAsset = options.particleSystemAsset,
        scale = options.scale or {1, 1, 1},
        rotation = options.rotation or {0, 0, 0},
        location = options.location or {0, 0, 0},
        autoActivate = options.autoActivate ~= false,  -- default true
        poolMethod = options.poolMethod or EPSCPoolMethod.None,
        collisionEnabled = options.collisionEnabled or ECollisionEnabled.QueryAndPhysics,
        collisionResponse = options.collisionResponse or ECollisionResponse.Block,
    }, ParticleSystem)

    self:create()  -- auto-create components
    return self
end

-- Create the particle system components
function ParticleSystem:create()
    if self.particleComponent == nil then
        -- Create anchor component (SceneComponent to attach particle to)
        self.anchorComponent = uevrUtils.create_component_of_class("Class /Script/Engine.SceneComponent")

        if self.anchorComponent ~= nil then
            -- Load the particle system asset
            local ps = uevrUtils.getLoadedAsset(self.particleSystemAsset)

            if ps ~= nil then
                -- Spawn particle emitter attached to anchor
                self.particleComponent = Statics:SpawnEmitterAttached(
                    ps,
                    self.anchorComponent,
                    uevrUtils.fname_from_string(""),
                    uevrUtils.vector(self.location),
                    uevrUtils.rotator(self.rotation),
                    uevrUtils.vector(self.scale),
                    EAttachLocation.KeepRelativeOffset,
                    true,  -- bAutoDestroy
                    self.poolMethod,
                    true  -- bAutoActivate
                )

                if self.particleComponent ~= nil then
                    self.particleComponent:SetAutoActivate(self.autoActivate)
                    self.particleComponent.SecondsBeforeInactive = 0.0
                    self.particleComponent:SetCollisionEnabled(self.collisionEnabled)
                    self.particleComponent:SetCollisionResponseToAllChannels(self.collisionResponse)
                    self.particleComponent:SetRenderInMainPass(true)
                    self.particleComponent.bRenderInDepthPass = true
                end
            end
        end
    end
    return self.particleComponent
end

-- Attach particle system to a mesh/component
function ParticleSystem:attachTo(mesh, socketName, attachType, weld)
    local anchor = uevrUtils.getValid(self.anchorComponent)
    local m = uevrUtils.getValid(mesh)
    if anchor ~= nil and m ~= nil then
        return anchor:K2_AttachTo(m, uevrUtils.fname_from_string(socketName or ""), attachType or 0, weld or false)
    end
end

-- Get the particle component
function ParticleSystem:getParticleComponent()
    return self.particleComponent
end

-- Get the anchor component
function ParticleSystem:getAnchorComponent()
    return self.anchorComponent
end

-- Destroy the particle system
function ParticleSystem:destroy()
    if self.particleComponent ~= nil then
        local pc = uevrUtils.getValid(self.particleComponent)
        if pc ~= nil then
            -- Deactivate by setting auto-activate to false and hiding
            pc:SetAutoActivate(false)
            pc:SetVisibility(false, false)
            uevrUtils.destroyComponent(self.particleComponent, true, true)
        end
        self.particleComponent = nil
    end

    if self.anchorComponent ~= nil then
        local ac = uevrUtils.getValid(self.anchorComponent)
        if ac ~= nil then
            ac:DetachFromParent(false, false)
            uevrUtils.destroyComponent(self.anchorComponent, true, true)
        end
        self.anchorComponent = nil
    end
end

-- Set world location of the particle system
function ParticleSystem:setWorldLocation(location, sweep)
    local anchor = uevrUtils.getValid(self.anchorComponent)
    if anchor ~= nil and location ~= nil then
        anchor:K2_SetWorldLocation(uevrUtils.vector(location), sweep or false, reusable_hit_result, false)
    end
end

-- Set world rotation of the particle system
function ParticleSystem:setWorldRotation(rotation, sweep)
    local anchor = uevrUtils.getValid(self.anchorComponent)
    if anchor ~= nil and rotation ~= nil then
        anchor:K2_SetWorldRotation(uevrUtils.rotator(rotation), sweep or false, reusable_hit_result, false)
    end
end

-- Set world transform (location, rotation, scale)
function ParticleSystem:setWorldTransform(location, rotation, scale)
    local anchor = uevrUtils.getValid(self.anchorComponent)
    if anchor ~= nil then
        uevrUtils.set_component_world_transform(
            anchor,
            location and uevrUtils.vector(location),
            rotation and uevrUtils.rotator(rotation),
            scale and uevrUtils.vector(scale)
        )
    end
end

-- Set relative location
function ParticleSystem:setRelativeLocation(location)
    local anchor = uevrUtils.getValid(self.anchorComponent)
    if anchor ~= nil and location ~= nil then
        anchor.RelativeLocation = uevrUtils.vector(location)
    end
end

-- Set relative rotation
function ParticleSystem:setRelativeRotation(rotation)
    local anchor = uevrUtils.getValid(self.anchorComponent)
    if anchor ~= nil and rotation ~= nil then
        anchor.RelativeRotation = uevrUtils.rotator(rotation)
    end
end

-- Set relative scale
function ParticleSystem:setRelativeScale(scale)
    local anchor = uevrUtils.getValid(self.anchorComponent)
    if anchor ~= nil and scale ~= nil then
        anchor.RelativeScale3D = uevrUtils.vector(scale)
    end
end

-- Set particle system visibility
function ParticleSystem:setVisibility(isVisible, propagateToChildren)
    local anchor = uevrUtils.getValid(self.anchorComponent)
    if anchor ~= nil then
        anchor:SetVisibility(isVisible, propagateToChildren or false)
    end
end

-- NOTE: Methods like ActivateSystem(), DeactivateSystem(), SetFloatParameter(), etc.
-- are not available in the dumped C++ headers for this game. Particle systems
-- can be controlled via SetAutoActivate(), SetCollisionEnabled(), and visibility.

-- Set the particle system scale
function ParticleSystem:setScale(scale)
    self.scale = scale or {1, 1, 1}
    self:setRelativeScale(self.scale)
end

-- Check if particle system is valid
function ParticleSystem:isValid()
    return uevrUtils.getValid(self.particleComponent) ~= nil and uevrUtils.getValid(self.anchorComponent) ~= nil
end

return M
