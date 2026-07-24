local uevrUtils = require("libs/uevr_utils")
local paramModule = require("libs/core/params")
local controllers = require("libs/controllers")

local M = {}

local status = {}

-- local parametersFileName = "physics_parameters"
-- local parameters = {
-- }
-- local paramManager = paramModule.new(parametersFileName, parameters, true)
-- paramManager:load(true)

local function createPhysicsHandle(id, parent, tranformCallback, options)
    if options == nil then options = {} end
    M.destroyPhysicsHandle(id)
--    local profileData = paramManager:get(id)
--    if profileData ~= nil then
        print("Creating physics handle for ", id)
        local physicsHandle = nil
        physicsHandle = uevrUtils.create_component_of_class("Class /Script/Engine.PhysicsHandleComponent", false, nil, false, parent)
        if physicsHandle ~= nil then
            if options.interpolationSpeed ~= nil then physicsHandle:SetInterpolationSpeed(options.interpolationSpeed) end
            if options.linearStiffness ~= nil then physicsHandle:SetLinearStiffness(options.linearStiffness) end
            if options.linearDamping ~= nil then physicsHandle:SetLinearDamping(options.linearDamping) end
            if options.angularStiffness ~= nil then physicsHandle:SetAngularStiffness(options.angularStiffness) end
            if options.angularDamping ~= nil then physicsHandle:SetAngularDamping(options.angularDamping) end

            if status.physicsHandles == nil then status.physicsHandles = {} end
            status.physicsHandles[id] = {physicsHandle = physicsHandle, canDestoryParent = parent == nil, tranformCallback = tranformCallback}
        end
--    end
end
function M.createPhysicsHandle(id, parent)
    if status.physicsHandles == nil then status.physicsHandles = {} end
    if status.physicsHandles[id] == nil then
        createPhysicsHandle(id, parent)
    end
end

function M.destroyPhysicsHandle(id)
    if status.physicsHandles == nil or status.physicsHandles[id] == nil then return end
	local physicsHandle = uevrUtils.getValid(status.physicsHandles[id]["physicsHandle"])
	if physicsHandle ~= nil then
        M.releaseComponentWithPhysicsHandle(id)
		uevrUtils.destroyComponent(physicsHandle, status.physicsHandles[id].canDestoryParent, false)
	end
	status.physicsHandles[id] = nil
end

function M.destroyAllPhysicsHandles()
    if status.physicsHandles == nil then return end
    for id, data in pairs(status.physicsHandles) do
        M.destroyPhysicsHandle(id)
    end
    status.physicsHandles = nil
end

function M.destroyAll()
    M.destroyAllPhysicsHandles()
end

function M.grabComponentWithPhysicsHandle(id, component)
    if component == nil or status.physicsHandles == nil or status.physicsHandles[id] == nil then return end
    local physicsHandle = uevrUtils.getValid(status.physicsHandles[id]["physicsHandle"])
    if physicsHandle ~= nil then
        --if you use this then the grip location will be whereever the controller is at the moment of grip
        --good if you want the object to orient to the current hand pose but suffers
        --from the fact that your hand could initially be in the center of the object (not realistic)
            --local location = controllers.getControllerLocation(Handed.Right)
            --local rotation = controllers.getControllerRotation(Handed.Right)
        --if you use this one the grip location will be the center of the gripped component
        --good if you use fixed offsets that will give a consistent hold orientation every time
            local location = component:K2_GetComponentLocation()
            local rotation = component:K2_GetComponentRotation()

        print("Grabbing component ", component:get_full_name(), "with physics handle ", physicsHandle:get_full_name(), "at location ", location.X, location.Y, location.Z, "and rotation ", rotation.Pitch, rotation.Yaw, rotation.Roll)
        physicsHandle:GrabComponentAtLocationWithRotation(component, uevrUtils.fname_from_string(""), location, rotation)
        --physicsHandle:GrabComponent(component, uevrUtils.fname_from_string("None"), location, true)
    end
end

function M.getGrabbedComponentWithPhysicsHandle(id)
    if status.physicsHandles == nil or status.physicsHandles[id] == nil then return end
    local physicsHandle = uevrUtils.getValid(status.physicsHandles[id]["physicsHandle"])
    if physicsHandle ~= nil then
        return physicsHandle:GetGrabbedComponent()
    end
    return nil
end

function M.releaseComponentWithPhysicsHandle(id)
    if status.physicsHandles == nil or status.physicsHandles[id] == nil then return end
    local physicsHandle = uevrUtils.getValid(status.physicsHandles[id]["physicsHandle"])
    if physicsHandle ~= nil then
        physicsHandle:ReleaseComponent()
    end
end

local function update()
    if status.physicsHandles ~= nil then
        for id, data in pairs(status.physicsHandles) do
            local physicsHandle = uevrUtils.getValid(data["physicsHandle"])
            if physicsHandle ~= nil then
                local grabbed = uevrUtils.getValid(physicsHandle.GetGrabbedComponent and physicsHandle:GetGrabbedComponent())
                if grabbed ~= nil then
                    local location, rotation = nil, nil
                    if data.tranformCallback ~= nil then
                        location, rotation = data.tranformCallback(id, grabbed)
                    else -- default to controller location and rotation
                        location = controllers.getControllerLocation(Handed.Right)
                        rotation = controllers.getControllerRotation(Handed.Right)
                    end
                    if location ~= nil and rotation ~= nil then
                        physicsHandle:SetTargetLocationAndRotation(location, rotation)
                    end
                end
            end
        end
    end
end

-- This should normally be enough but games using their own physics
-- may have additional requirements
function M.makeComponentPhysicsGrippable(grippedComponent)
    -- grippedComponent:SetCollisionResponseToChannel(2, 0)
    -- --component:GetOwner().bActorEnableCollision = false
    -- status.grabComponent = grippedComponent
    grippedComponent.BodyInstance.bSimulatePhysics = true
    grippedComponent.BodyInstance.bEnableGravity = true
    grippedComponent.BodyInstance.bOverrideMass = true
    grippedComponent:SetEnableGravity(true)
    --grippedComponent.BodyInstance.bUpdateKinematicFromSimulation = true
    grippedComponent:SetCollisionEnabled(ECollisionEnabled.QueryAndPhysics)
    grippedComponent:SetCollisionObjectType(ECollisionChannel.ECC_PhysicsBody)    -- or WorldDynamic
    --grippedComponent:SetMassOverrideInKg(100)
    grippedComponent:WakeAllRigidBodies()
    grippedComponent:SetMobility(EComponentMobility.Movable)
    grippedComponent:SetSimulatePhysics(true)
    grippedComponent:SetCollisionResponseToChannel(ECollisionChannel.ECC_Pawn, ECollisionResponse.Ignore)

end

function M.reset()
    M.destroyAll()
    status = {}
end

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
    update()
end)

uevrUtils.registerPreLevelChangeCallback(function(level)
	M.reset()
end)

uevr.params.sdk.callbacks.on_script_reset(function()
	M.reset()
end)

return M