---@diagnostic disable: unused-local
local uevrUtils = require("libs/uevr_utils")
local paramModule = require("libs/core/params")
local controllers = require("libs/controllers")
local linetracer = require("libs/linetracer")
local plugin = require("libs/core/plugin")
local mathLib = require("libs/core/math_lib")
require("libs/enums/unreal")

local M = {}

local collisionConfigDev = nil
local status = {}

local currentLogLevel = LogLevel.Error
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
	if logLevel == nil then logLevel = LogLevel.Debug end
	if logLevel <= currentLogLevel then
		uevrUtils.print("[collision] " .. text, logLevel)
	end
end

local parametersFileName = "collision_parameters"
local parameters = {
    active = false,
    channels = {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1},
    shape = 1,
    radius = 5.0,
    half_height = 20.0,
    extents = {10.0, 10.0, 10.0},
    position = {0.0, 0.0, 0.0},
    rotation = {0.0, 0.0, 0.0},
    scale = {1.0, 1.0, 1.0},
    collision_enabled = 1,
    collision_object_type = 1,
    visible = false,
    generate_overlap_events = true,
    attachTo = 2, -- 1 = left hand, 2 = right hand, 3 = head
}

COLLISION_SHAPES = {
    Sphere = 1,
    Box = 2,
    Capsule = 3,
    Sphere_Overlap_Only = 4,
    Box_Overlap_Only = 5,
    Capsule_Overlap_Only = 6,
    Custom = 7,
}
COLLISION_ATTACHMENT = {
    LeftHand = 1,
    RightHand = 2,
    Head = 3,
    Custom = 4
}
COLLISION_DETECTION_TYPE = {
    GetOverlappingComponents = 1,
    ComponentOverlapComponents = 2
}
COLLISION_SHAPE_STRINGS = {"Sphere", "Box", "Capsule", "Sphere (Overlap Only)", "Box (Overlap Only)", "Capsule (Overlap Only)", "Custom"}
COLLISION_MOBILITY_STRINGS = {"Static", "Stationary", "Movable"}
COLLISION_ATTACHMENT_STRINGS = {"Left Hand", "Right Hand", "Head", "Custom"}
COLLISION_ENABLED_STRINGS = {"No Collision", "Query Only", "Physics Only", "Query And Physics", "Probe Only", "Query And Probe"}
COLLISION_OBJECT_TYPE_STRINGS = {"World Static (0)", "World Dynamic (1)", "Pawn (2)", "Visibility (3)", "Camera (4)", "Physics Body (5)", "Vehicle (6)", "Destructible (7)", "Engine Trace Channel 1 (8)", "Engine Trace Channel 2 (9)", "Engine Trace Channel 3 (10)", "Engine Trace Channel 4 (11)", "Engine Trace Channel 5 (12)", "Engine Trace Channel 6 (13)", "Game Trace Channel 1 (14)", "Game Trace Channel 2 (15)", "Game Trace Channel 3 (16)", "Game Trace Channel 4 (17)", "Game Trace Channel 5 (18)", "Game Trace Channel 6 (19)", "Game Trace Channel 7 (20)", "Game Trace Channel 8 (21)", "Game Trace Channel 9 (22)", "Game Trace Channel 10 (23)", "Game Trace Channel 11 (24)", "Game Trace Channel 12 (25)", "Game Trace Channel 13 (26)", "Game Trace Channel 14 (27)", "Game Trace Channel 15 (28)", "Game Trace Channel 16 (29)", "Game Trace Channel 17 (30)", "Game Trace Channel 18 (31)", "Overlap All Deprecated (32)"}
COLLISION_RESPONSE_STRINGS = {"Ignore", "Overlap", "Block"}
COLLISION_CLASS_TYPES = {
    "Class /Script/Engine.SphereComponent",
    "Class /Script/Engine.BoxComponent",
    "Class /Script/Engine.CapsuleComponent",
    "Class /Script/Engine.SphereComponent",
    "Class /Script/Engine.BoxComponent",
    "Class /Script/Engine.CapsuleComponent"
}
COLLISION_DETECTION_TYPE_STRINGS = {"GetOverlappingComponents", "ComponentOverlapComponents"}

local paramManager = paramModule.new(parametersFileName, parameters, true)
paramManager:load(true)

local function getParameter(key)
    return paramManager:getFromActiveProfile(key)
end

local function setParameter(key, value, persist)
    return paramManager:setInActiveProfile(key, value, persist)
end

local function setColliderProperties(collider, id)
    local profileData = paramManager:get(id)
    if profileData ~= nil then
        print("Setting collider properties for ", id, "Radius", profileData.radius, "Shape", profileData.shape, "Collision Object Type", profileData.collision_object_type - 1, "Collision Enabled", profileData.collision_enabled - 1, "Channels", profileData.channels, "Visible", profileData.visible, "Generate Overlap Events", profileData.generate_overlap_events, "Attach To", profileData.attachTo)
        if collider.SetSphereRadius ~= nil then
            collider:SetSphereRadius(profileData.radius, false)
        elseif collider.SetBoxExtent ~= nil then
            if profileData.extents == nil then profileData.extents = {10, 10, 10} end
            collider:SetBoxExtent(uevrUtils.vector(profileData.extents[1], profileData.extents[2], profileData.extents[3]), false)
        elseif collider.SetCapsuleRadius ~= nil then
            if profileData.half_height == nil then profileData.half_height = 20 end
            collider:SetCapsuleRadius(profileData.radius, profileData.half_height, false)
        end

        if profileData.shape == COLLISION_SHAPES.Sphere or profileData.shape == COLLISION_SHAPES.Box or profileData.shape == COLLISION_SHAPES.Capsule or profileData.shape == COLLISION_SHAPES.Custom then
            collider:SetCollisionObjectType(profileData.collision_object_type - 1)--ECollisionChannel.ECC_Pawn)       -- ECC_Pawn
            collider:SetCollisionEnabled(profileData.collision_enabled - 1)          -- QueryOnly
            collider:SetCollisionResponseToAllChannels(0)
            for index, channel in ipairs(profileData.channels) do
                collider:SetCollisionResponseToChannel(index - 1, channel - 1)
                --print("Collision response to channel ", index - 1, ": ", channel - 1)
            end
            collider.bGenerateOverlapEvents = profileData.generate_overlap_events
        end
        collider:SetVisibility(profileData.visible)
        --collider:SetMassOverrideInKg(uevrUtils.fname_from_string(""), 50, true)
        --uevrUtils.set_component_relative_transform(collider, profileData.position, profileData.rotation)
        --uevrUtils.set_component_relative_transform(collider, uevrUtils.vector(30,30,30), profileData.rotation)
        status.colliders[id].position = uevrUtils.vector(profileData.position)
        status.colliders[id].rotation = uevrUtils.rotator(profileData.rotation)
        status.colliders[id].handed = profileData.attachTo - 1
    end
end

local function createCollider(id, collisionParent)
    M.destroy(id)
    local profileData = paramManager:get(id)
    if profileData ~= nil then
        print("Creating collider for ", id)
        local collider = nil
        if profileData.shape ~= COLLISION_SHAPES.Custom then
            collider = uevrUtils.create_component_of_class(COLLISION_CLASS_TYPES[profileData.shape], false, nil, false, collisionParent)
        else
            --collider = uevrUtils.create_component_of_class(profileData.custom_class, false, nil, false, collisionParent)
        end
        if collider ~= nil then
            if status.colliders == nil then status.colliders = {} end
            status.colliders[id] = {collider = collider, canDestoryParent = collisionParent == nil}
            setColliderProperties(collider, id)
        end
    end
end




local function refreshActiveColliders()
    if status.colliders == nil then
        status.colliders = {}
    end

    local ids = paramManager:getProfiles()
    local profileIds = {}
    for i = 1, #ids do
        profileIds[ids[i]] = true
    end

    local toDestroy = {}
    for id in pairs(status.colliders) do
        local profileData = paramManager:get(id)
        if not profileIds[id] or profileData == nil or not profileData.active then
            table.insert(toDestroy, id)
        end
    end
    for i = 1, #toDestroy do
        M.destroy(toDestroy[i])
    end

    local collisionParent = uevrUtils.getValid(pawn)
    for i = 1, #ids do
        local id = ids[i]
        local profileData = paramManager:get(id)
        if profileData ~= nil and profileData.active and status.colliders[id] == nil then
            createCollider(id, collisionParent)
        end
    end
end

local createConfigMonitor = doOnce(function()
	uevrUtils.registerUEVRCallback("on_collision_config_param_change", function(key, value)
		setParameter(key, value, true)
        if key == "active" then
            refreshActiveColliders()
        elseif key == "shape" or key == "attachTo" then
            local id = paramManager:getActiveProfile()
            --createCollider(id)
            M.destroy(id)
            refreshActiveColliders()
        else
            local id = paramManager:getActiveProfile()
            if status.colliders and status.colliders[id] then
                setColliderProperties(status.colliders[id].collider, id)
            end
        end
	end)
end, Once.EVER)

paramManager:registerProfileChangeCallback(function(profileParams)
    --refresh the colliders on profile change in case a profile was added or deleted
    refreshActiveColliders()
end)

function M.init(isDeveloperMode, logLevel)
	if logLevel ~= nil then
        M.setLogLevel(logLevel)
    end
    if isDeveloperMode == nil and uevrUtils.getDeveloperMode() ~= nil then
        isDeveloperMode = uevrUtils.getDeveloperMode()
    end

    if isDeveloperMode then
        collisionConfigDev = require("libs/config/collision_config_dev")
        collisionConfigDev.init(paramManager)
		createConfigMonitor()
    else
    end

    refreshActiveColliders()
end

-- function M.create(id, collisionParent, handed)
--     if collisionParent ~= nil then
-- 		M.destroy(id)
-- 		local collider = uevrUtils.create_component_of_class("Class /Script/Engine.SphereComponent", false, nil, false, collisionParent)
-- 		if collider ~= nil then
-- 			collider:SetSphereRadius(40.0, false)
-- 			collider:SetCollisionObjectType(0)--ECollisionChannel.ECC_Pawn)       -- ECC_Pawn
-- 			collider:SetCollisionEnabled(ECollisionEnabled.QueryAndPhysics)          -- QueryOnly
-- 			collider:SetCollisionResponseToAllChannels(0)
-- 			-- collider:SetCollisionResponseToChannel(0, ECollisionResponse.Block)  -- WorldStatic / walls
-- 			-- collider:SetCollisionResponseToChannel(1, ECollisionResponse.Block)  -- WorldDynamic / door mesh
-- 			-- collider:SetCollisionResponseToChannel(14, ECollisionResponse.Overlap) -- GameTraceChannel6 / NP pre-hit detector
-- 			collider:SetCollisionResponseToChannel(19, ECollisionResponse.Overlap) -- GameTraceChannel6 / NP pre-hit detector
-- 			--collider:SetCollisionResponseToChannel(27, ECollisionResponse.Overlap) -- GameTraceChannel6 / NP pre-hit detector

--             collider:SetVisibility(true)

--             collider.bGenerateOverlapEvents = true

-- 			if status.colliders == nil then status.colliders = {} end
-- 			status.colliders[id] = {collider = collider, handed = handed}
--             return collider
-- 		end
-- 	end

-- end

function M.destroy(id)
    if status.colliders == nil or status.colliders[id] == nil then return end
	local collider = uevrUtils.getValid(status.colliders[id]["collider"])
	if collider ~= nil then
		uevrUtils.destroyComponent(collider, status.colliders[id].canDestoryParent, false)
	end
	status.colliders[id] = nil
end

function M.destroyAll()
    if status.colliders == nil then return end
    for id, data in pairs(status.colliders) do
        M.destroy(id)
    end
    status.colliders = nil
end

function M.reset()
    M.destroyAll()
    status = {}
end

function M.getLocation(id)
    if status.colliders == nil or status.colliders[id] == nil then
        return nil
    end
    local collider = uevrUtils.getValid(status.colliders[id]["collider"])
    if collider ~= nil then
        return collider:K2_GetComponentLocation()
    end
    return nil
end

local function updateColliders()
	if status.colliders ~= nil then

        local locations = {}
        local rotations = {}
        for id, data in pairs(status.colliders) do
            if data.handed ~= nil then
                if locations[data.handed] == nil then
                    if data.handed < 3 then
                        locations[data.handed] = controllers.getControllerLocation(data.handed)
                    else
                        --if custom, call back to the main.lua to get the position
                    end
                end
                if rotations[data.handed] == nil then
                    if data.handed < 3 then
                        rotations[data.handed] = controllers.getControllerRotation(data.handed)
                    else
                        --if custom, call back to the main.lua to get the rotation
                    end
                end
                local collider = data.collider
                if uevrUtils.getValid(collider) ~= nil and collider.K2_SetWorldLocation ~= nil then
                    -- Treat the collider as a child of the controller: data.position and
                    -- data.rotation are local offsets in the controller's space.
                    local loc, rot = mathLib.childWorldTransform(locations[data.handed], rotations[data.handed], data.position, data.rotation)

                    if rot then collider:K2_SetWorldRotation(rot, true, reusable_hit_result, false) end
                    if loc then collider:K2_SetWorldLocation(loc, true, reusable_hit_result, false) end
                end
            end
        end
    end
end


local function checkCollisionEvent(id)
    if status.colliders == nil or status.colliders[id] == nil or status.colliders[id].isDisabled == true then return end

    local foundComponents = {}
    --print("Calling checkCollisionEvents for Collider", id)
    local data = status.colliders[id]
    local collider = data.collider
    local profileData = paramManager:get(id)
    if profileData ~= nil then
        if profileData.shape == COLLISION_SHAPES.Sphere_Overlap_Only then
            --static bool SphereOverlapComponents(const class UObject* WorldContextObject, const struct FVector& SpherePos, float SphereRadius, const TArray<EObjectTypeQuery>& ObjectTypes, class UClass* ComponentClassFilter, const TArray<class AActor*>& ActorsToIgnore, TArray<class UPrimitiveComponent*>* OutComponents);
            local location = collider:K2_GetComponentLocation()
            local radius = profileData.radius
            local classFilter = uevrUtils.get_class("Class /Script/Engine.PrimitiveComponent")
            local objectTypes = {}
            local ignoreActors = {pawn}
            for i = 1, #profileData.channels do
                if profileData.channels[i] ~= 1 then
                    table.insert(objectTypes, i - 1)
                end
            end
            --plugin.showDebug = true
            -- local resultCallback = plugin.executeFunctionAsync(kismet_system_library, "SphereOverlapComponents", uevrUtils.get_world(), location, radius, objectTypes, classFilter, ignoreActors, foundComponents)
            -- resultCallback(function(result)
            --     local components = result.OutComponents or {}
            --     local collisionComponentNames = {}
            --     for i = 1, #components do
            --         local comp = components[i]
            --         local name = comp:get_full_name():match(".*/([^/]+)$") or comp:get_full_name()
            --         table.insert(collisionComponentNames, name)
            --         table.insert(foundComponents, comp)
            --     end
            --     if collisionConfigDev ~= nil and id == paramManager:getActiveProfile() then
            --         collisionConfigDev.setCollisionComponentNames(collisionComponentNames)
            --     end
            -- end)
            local result = plugin.executeFunction(kismet_system_library, "SphereOverlapComponents", uevrUtils.get_world(), location, radius, objectTypes, classFilter, ignoreActors, foundComponents)
            if result ~= nil then
                local components = result.OutComponents or {}
                local collisionComponentNames = {}
                for i = 1, #components do
                    local comp = components[i]
                    local name = comp:get_full_name():match(".*/([^/]+)$") or comp:get_full_name()
                    table.insert(collisionComponentNames, name)
                    table.insert(foundComponents, comp)
                end
                if collisionConfigDev ~= nil and id == paramManager:getActiveProfile() then
                    collisionConfigDev.setCollisionComponentNames(collisionComponentNames)
                end
            end

        elseif profileData.collision_detection_type == COLLISION_DETECTION_TYPE.ComponentOverlapComponents then
            --static bool ComponentOverlapComponents(class UPrimitiveComponent* Component, const struct FTransform& ComponentTransform, const TArray<EObjectTypeQuery>& ObjectTypes, class UClass* ComponentClassFilter, const TArray<class AActor*>& ActorsToIgnore, TArray<class UPrimitiveComponent*>* OutComponents);
            local ignoreActors = {pawn}
            --local objectTypes = {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31}
            --local objectTypes = {0, 1, 4, 5, 6, 18, 19, 20}
            --local objectTypes = {20}
            local objectTypes = {}
            for i = 1, #profileData.channels do
                if profileData.channels[i] ~= 1 then
                    table.insert(objectTypes, i - 1)
                end
            end
            -- print the objectTypes array as a comma separated string
            --print("Object types: " .. table.concat(objectTypes, ", "))
            local transform = collider:K2_GetComponentToWorld()
            local location = collider:K2_GetComponentLocation()
            local classFilter = uevrUtils.get_class("Class /Script/Engine.PrimitiveComponent")
            --print("  Using ComponentOverlapComponents", kismet_system_library, "on collider", collider, "with transform ", location.X, location.Y, location.Z)
            --plugin.showDebug = true
            -- local resultCallback = plugin.executeFunctionAsync(kismet_system_library, "ComponentOverlapComponents", collider, transform, objectTypes, classFilter, ignoreActors, foundComponents)
            -- resultCallback(function(result)
            --     local components = result.OutComponents or {}
            --     local collisionComponentNames = {}
            --     for i = 1, #components do
            --         local comp = components[i]
            --         local name = comp:get_full_name():match(".*/([^/]+)$") or comp:get_full_name()
            --         table.insert(collisionComponentNames, name)
            --         table.insert(foundComponents, comp)
            --     end
            --     if collisionConfigDev ~= nil and id == paramManager:getActiveProfile() then
            --         collisionConfigDev.setCollisionComponentNames(collisionComponentNames)
            --     end
            -- end)
            local result = plugin.executeFunction(kismet_system_library, "ComponentOverlapComponents", collider, transform, objectTypes, classFilter, ignoreActors, foundComponents)
            if result ~= nil then
                local components = result.OutComponents or {}
                local collisionComponentNames = {}
                for i = 1, #components do
                    local comp = components[i]
                    local name = comp:get_full_name():match(".*/([^/]+)$") or comp:get_full_name()
                    table.insert(collisionComponentNames, name)
                    table.insert(foundComponents, comp)
                end
                if collisionConfigDev ~= nil and id == paramManager:getActiveProfile() then
                    collisionConfigDev.setCollisionComponentNames(collisionComponentNames)
                end
            end
        elseif profileData.collision_detection_type == COLLISION_DETECTION_TYPE.GetOverlappingComponents then
            local overlappingComponents = {}
            local collisionComponentNames = {}
            print("  Using GetOverlappingComponents")
            collider:GetOverlappingComponents(overlappingComponents)
            print("Overlapping components for collider ", overlappingComponents, overlappingComponents and #overlappingComponents or 0)
            if overlappingComponents ~= nil then
                for _, comp in ipairs(overlappingComponents) do
                    print("  Component:", comp:get_full_name(), comp:GetCollisionObjectType())
                    if comp.StaticMesh ~= nil then
                        print("   Static Mesh", comp.StaticMesh:get_full_name())
                    end
                    local name = comp:get_full_name():match(".*/([^/]+)$") or comp:get_full_name()
                    table.insert(collisionComponentNames, name)

                    table.insert(foundComponents, comp)
                end
            end
            if collisionConfigDev ~= nil and id == paramManager:getActiveProfile() then
                collisionConfigDev.setCollisionComponentNames(collisionComponentNames)
            end
        end
    end
    return foundComponents
end

local function checkCollisionEvents()
    if status.colliders ~= nil then
        for id, _ in pairs(status.colliders) do
            checkCollisionEvent(id)
            --static bool CapsuleOverlapComponents(const class UObject* WorldContextObject, const struct FVector& CapsulePos, float Radius, float HalfHeight, const TArray<EObjectTypeQuery>& ObjectTypes, class UClass* ComponentClassFilter, const TArray<class AActor*>& ActorsToIgnore, TArray<class UPrimitiveComponent*>* OutComponents);
            -- kismet_system_library:CapsuleOverlapComponents(uevrUtils.get_world(), location, 50.0, 100.0, objectTypes, classFilter, ignoreActors, foundComponents);

            -- -- kismet_system_library:ComponentOverlapComponents(collider, transform, objectTypes, classFilter, ignoreActors, foundComponents)
            -- print("Found components for collider ", foundComponents, foundComponents and #foundComponents or 0)
            --     if foundComponents ~= nil then
            --         for i = 1, #foundComponents do
            --             local comp = foundComponents[i]
            --             print("  Component:", comp:get_full_name())
            --         end
            --     end

            -- if collider ~= nil and collider.GetOverlappingComponents ~= nil then
            --     local overlappingComponents = {}
            --     collider:GetOverlappingComponents(overlappingComponents)
            --     print("Overlapping components for collider ", overlappingComponents, overlappingComponents and #overlappingComponents or 0)
            --     if overlappingComponents ~= nil then
            --         for _, comp in ipairs(overlappingComponents) do
            --             print(comp:get_full_name())
            --         end
            --     end

            --     local overlappingActors = {}
            --     collider:GetOverlappingActors(overlappingActors, uevrUtils.get_class("Class /Script/Engine.Actor"))
            --     print("Overlapping actors for collider ", overlappingActors, overlappingActors and #overlappingActors or 0)
            --     if overlappingActors ~= nil then
            --         for _, actor in ipairs(overlappingActors) do
            --             print(actor:get_full_name())
            --         end
            --     end
            -- end
        end
    end

    -- if status.physicsHandles ~= nil then
    --     for id, data in pairs(status.physicsHandles) do
    --         local physicsHandle = uevrUtils.getValid(data["physicsHandle"])
    --         if physicsHandle ~= nil then
    --             local component = physicsHandle:GetGrabbedComponent()
    --             -- if component ~= nil then
    --             --     print("Grabbed component ", component:get_full_name())
    --             --     print("Mobility:", component.Mobility)
    --             --     print("CollisionEnabled:", component:GetCollisionEnabled())
    --             --     print("IsSimulatingPhysics:", component:IsAnySimulatingPhysics())
    --             --     print("Location:", component:K2_GetComponentLocation().X, component:K2_GetComponentLocation().Y, component:K2_GetComponentLocation().Z)
    --             -- else
    --             --     print("No grabbed component for physics handle ", physicsHandle:get_full_name())
    --             -- end
    --         end
    --     end
    -- end
	--void GetOverlappingActors(TArray<class AActor*>* OverlappingActors, TSubclassOf<class AActor> ClassFilter) const;
	--void GetOverlappingComponents(TArray<class UPrimitiveComponent*>* OutOverlappingComponents) const;
end

-- function M.preparePickupMeshForHandle(grippedComponent)
--     grippedComponent:SetMobility(EComponentMobility.Movable)
--     grippedComponent:SetCollisionEnabled(ECollisionEnabled.QueryAndPhysics)
--     grippedComponent:SetCollisionObjectType(ECollisionChannel.ECC_PhysicsBody)
--     grippedComponent.BodyInstance.bSimulatePhysics = true
--     grippedComponent.BodyInstance.bEnableGravity = false
--     grippedComponent:SetEnableGravity(false)
--     grippedComponent:WakeAllRigidBodies()
--     grippedComponent:SetSimulatePhysics(false)
--     grippedComponent:SetCollisionResponseToChannel(ECollisionChannel.ECC_Pawn, ECollisionResponse.Ignore)
-- end

function M.getProfileIDByLabel(label)
    local profileIDs, profileNames = paramManager:getProfiles()
    for i, name in ipairs(profileNames) do
        if name == label then
            return profileIDs[i]
        end
    end
    return ""
end


function M.getCollisionComponents(id)
    return checkCollisionEvent(id)
end

function M.getCollisionComponentsByLabel(label)
    return checkCollisionEvent(M.getProfileIDByLabel(label))
end

function M.disableCollision(id, val)
    local colliderData = status.colliders[id]
    if colliderData ~= nil then
         colliderData.isDisabled = val
    end
 end
 
 function M.disableCollisionByLabel(label, val)
     return M.disableCollision(M.getProfileIDByLabel(label), val)
 end
 
 function M.setCollisionResponseToChannel(id, channel, val)
    local colliderData = status.colliders[id]
    if colliderData ~= nil and uevrUtils.getValid(colliderData.collider) ~= nil then
         colliderData.collider:SetCollisionResponseToChannel(channel, val)
    end
 end
 
 function M.setCollisionResponseToChannelByLabel(label, channel, val)
     return M.setCollisionResponseToChannel(M.getProfileIDByLabel(label), channel, val)
 end
 
 --[[
Last hit result component:      SphereComponent /Game/Maps/Main/L_Main/_Generated_/91LGCG2O28ROM7AEMXYG0M8A8.L_Main.PersistentLevel.BP_OxygenPlant_C_UAID_3C7C3FF5ADFD562002_1564875206.SphereCollision
Collision enabled:      3       Collision channel:      1       Overlap events enabled: true
Collision response to channel   1       :       2
Collision response to channel   2       :       2
Collision response to channel   3       :       2
Collision response to channel   4       :       2
Collision response to channel   5       :       2
Collision response to channel   6       :       2
Collision response to channel   7       :       2
Collision response to channel   9       :       2
Collision response to channel   10      :       2
Collision response to channel   11      :       2
Collision response to channel   12      :       2
Collision response to channel   13      :       2
Collision response to channel   14      :       2
Collision response to channel   15      :       2
Collision response to channel   16      :       2
Collision response to channel   19      :       2
Collision response to channel   20      :       2
Collision response to channel   22      :       2
Collision response to channel   24      :       2
Collision response to channel   27      :       2
Collision response to channel   30      :       2
Collision response to channel   31      :       2
Collision response to channel   32      :       128
Overlapping components for collider     table: 00000288D15B2430 0
Overlapping actors for collider         table: 00000288D15B2DB0 0
Overlapping components for collider     table: 00000288D15B27B0 0
Overlapping actors for collider         table: 00000288D15B26F0 0

]]--
function M.checkCollisionEvents()
    checkCollisionEvents()
end

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
    updateColliders()
end)

-- uevr.sdk.callbacks.on_post_engine_tick(function(engine, delta)
--     checkCollisionEvents()
-- end)

setInterval(1000,function()
    --checkInteraction()
    checkCollisionEvents()
end)

uevrUtils.registerPreLevelChangeCallback(function(level)
	M.reset()
    refreshActiveColliders()
end)

uevr.params.sdk.callbacks.on_script_reset(function()
	M.reset()
end)

return M