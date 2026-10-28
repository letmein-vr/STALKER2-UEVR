local utils = require("common.utils")

MotionControllerActors = {}

-- Helper functions for finding objects

-- Initialize the module
function MotionControllerActors:new()
    local instance = {}
    setmetatable(instance, self)
    self.__index = self

    instance.hmd_actor = nil
    instance.left_hand_actor = nil
    instance.right_hand_actor = nil
    instance.left_hand_component = nil
    instance.right_hand_component = nil
    instance.hmd_component = nil
    
    -- Required UObject classes
    instance.game_engine_class = utils.find_required_object("Class /Script/Engine.GameEngine")
    instance.actor_c = utils.find_required_object("Class /Script/Engine.Actor")
    instance.motion_controller_component_c = utils.find_required_object("Class /Script/HeadMountedDisplay.MotionControllerComponent")
    instance.scene_component_c = utils.find_required_object("Class /Script/Engine.SceneComponent")
    instance.ftransform_c = utils.find_required_object("ScriptStruct /Script/CoreUObject.Transform")
    instance.zero_transform = StructObject.new(instance.ftransform_c)
    instance.kismet_string_library = utils.find_static_class("Class /Script/Engine.KismetStringLibrary")
    instance.statics = utils.find_static_class("Class /Script/Engine.GameplayStatics")

    return instance
end

-- Spawn an actor at the given location
function MotionControllerActors:spawn_actor(world_context, actor_class, location, collision_method, owner)
    self.zero_transform.Translation = location
    self.zero_transform.Rotation.W = 1.0 -- Set rotation to identity
    self.zero_transform.Scale3D = Vector3f.new(1.0, 1.0, 1.0) -- Default scale

    local actor = self.statics:BeginDeferredActorSpawnFromClass(world_context, actor_class, self.zero_transform, collision_method, owner)
    if actor == nil then
        print("Failed to spawn actor")
        return nil
    end

    self.statics:FinishSpawningActor(actor, self.zero_transform)
    return actor
end

-- Get the game world
function MotionControllerActors:GetWorld(engine)
    if not engine then
        return nil
    end

    local viewport = engine.GameViewport
    if not viewport then
        return nil
    end

    return viewport.World
end

-- Reset all hand actors
function MotionControllerActors:Reset()
    self.inited = false

    -- We are using pcall on this because for some reason the actors are not always valid
    -- even if exists returns true
    if self.left_hand_actor ~= nil and UEVR_UObjectHook.exists(self.left_hand_actor) then
        pcall(function()
            if self.left_hand_actor.K2_DestroyActor ~= nil then
                self.left_hand_actor:K2_DestroyActor()
            end
        end)
    end

    if self.right_hand_actor ~= nil and UEVR_UObjectHook.exists(self.right_hand_actor) then
        pcall(function()
            if self.right_hand_actor.K2_DestroyActor ~= nil then
                self.right_hand_actor:K2_DestroyActor()
            end
        end)
    end

    if self.hmd_actor ~= nil and UEVR_UObjectHook.exists(self.hmd_actor) then
        pcall(function()
            if self.hmd_actor.K2_DestroyActor ~= nil then
                self.hmd_actor:K2_DestroyActor()
            end
        end)
    end

    self.left_hand_actor = nil
    self.right_hand_actor = nil
    self.hmd_actor = nil
    self.left_hand_component = nil
    self.right_hand_component = nil
    self.hmd_component = nil
end

-- Forget the hand actors WITHOUT touching them. For a level change: the old world's actors
-- were freed with it, and on this backend exists() still passes for freed objects (and the
-- address may already belong to a new-world object), so Reset()'s K2_DestroyActor must not
-- run on them. Update() respawns a fresh set in the new world on the next tick.
function MotionControllerActors:Invalidate()
    self.inited = false
    self.left_hand_actor = nil
    self.right_hand_actor = nil
    self.hmd_actor = nil
    self.left_hand_component = nil
    self.right_hand_component = nil
    self.hmd_component = nil
end

-- Check if any hand actors have been deleted and return if they need to be respawned
function MotionControllerActors:Validate()
    -- Check the components too, not just the actors: after an in-game script reset
    -- the actor can still report alive while its component has been destroyed, and
    -- any property access on the dead component throws a C++ exception.
    local function alive(obj)
        if obj == nil then return false end
        local ok, exists = pcall(UEVR_UObjectHook.exists, obj)
        return ok and exists
    end

    if self.left_hand_actor ~= nil and (not alive(self.left_hand_actor) or not alive(self.left_hand_component)) then
        self.left_hand_actor = nil
        self.left_hand_component = nil
    end

    if self.right_hand_actor ~= nil and (not alive(self.right_hand_actor) or not alive(self.right_hand_component)) then
        self.right_hand_actor = nil
        self.right_hand_component = nil
    end

    if self.hmd_actor ~= nil and (not alive(self.hmd_actor) or not alive(self.hmd_component)) then
        self.hmd_actor = nil
        self.hmd_component = nil
    end
    
    local needs_respawn = self.left_hand_actor == nil or self.right_hand_actor == nil or self.hmd_actor == nil
    if needs_respawn then
        self.inited = false
    end
    return needs_respawn
end

-- Initialize hand actors
function MotionControllerActors:Init(engine)
    local world = self:GetWorld(engine)
    if not world then
        print("World is nil")
        self.inited = false
        return false
    end

    local pawn = uevr.api:get_local_pawn(0)
    if not pawn then
        -- print("Pawn is nil")
        self.inited = false
        return false
    end

    local pos = pawn:K2_GetActorLocation()

    -- Create actors
    self.left_hand_actor = self:spawn_actor(world, self.actor_c, pos, 1, nil)
    self.right_hand_actor = self:spawn_actor(world, self.actor_c, pos, 1, nil)
    self.hmd_actor = self:spawn_actor(world, self.actor_c, pos, 1, nil)

    if not self.left_hand_actor or not self.right_hand_actor or not self.hmd_actor then
        print("Failed to spawn actors")
        self.inited = false
        return false
    end

    -- Add scene components
    self.left_hand_component = uevr.api:add_component_by_class(self.left_hand_actor, self.motion_controller_component_c)
    self.right_hand_component = uevr.api:add_component_by_class(self.right_hand_actor, self.motion_controller_component_c)
    self.hmd_component = uevr.api:add_component_by_class(self.hmd_actor, self.scene_component_c)

    if not self.left_hand_component or not self.right_hand_component or not self.hmd_component then
        print("Failed to add components")
        self.inited = false
        return false
    end

    -- Set up motion sources
    self.left_hand_component.MotionSource = self.kismet_string_library:Conv_StringToName("Left")
    self.right_hand_component.MotionSource = self.kismet_string_library:Conv_StringToName("Right")

    -- Not all engine versions have the Hand property
    if self.left_hand_component.Hand ~= nil then
        self.left_hand_component.Hand = 0
        self.right_hand_component.Hand = 1
    end

    -- The HMD is the only one we need to add manually as UObjectHook doesn't support motion controller components as the HMD
    local hmdstate = UEVR_UObjectHook.get_or_add_motion_controller_state(self.hmd_component)
    if hmdstate then
        hmdstate:set_hand(2) -- HMD
        hmdstate:set_permanent(true)
    end

    self.inited = true
    return true
end

-- Update function to check and reinitialize if needed
function MotionControllerActors:Update(engine)
    if not self.inited or self:Validate() then
        self:Init(engine)
    end
    self:EnsureHMDState()
end

-- Re-arm the HMD SceneComponent's UObjectHook motion-controller state (hand=2). On the
-- joeyhodge/AFW backend a state is keyed by the component's GUObjectArray (index, serial)
-- captured at get_or_add time; a fresh component has serial 0 until something takes a weak
-- pointer to it, after which the backend prunes the state as "stale" (log: "Pruned N stale
-- motion-controller attachment identities"). Validate() only checks the component is alive,
-- so the loss went unnoticed: the HMD proxy froze wherever it was (seen live 2026-09-21: 11 m
-- from the camera, state nil) and every HMD-relative body zone was measured against that
-- stale point - the "gestures are hit and miss" bug. Same fix as libs/controllers.lua
-- ensureHMDState: get_or_add re-keys a mismatched entry but returns a DEFAULT state, so
-- hand/permanent are re-applied. Throttled; the getter is a cheap map lookup when present.
local hmdStateCheckTick = 0
function MotionControllerActors:EnsureHMDState()
    hmdStateCheckTick = hmdStateCheckTick + 1
    if hmdStateCheckTick % 30 ~= 0 then return end
    local comp = self.hmd_component
    if comp == nil then return end
    pcall(function()
        if not UEVR_UObjectHook.exists(comp) then return end
        if UEVR_UObjectHook.get_motion_controller_state ~= nil
           and UEVR_UObjectHook.get_motion_controller_state(comp) ~= nil then
            return
        end
        local hmdstate = UEVR_UObjectHook.get_or_add_motion_controller_state(comp)
        if hmdstate then
            hmdstate:set_hand(2)
            hmdstate:set_permanent(true)
            print("[MotionControllerActors] Re-armed HMD motion-controller state")
        end
    end)
end


-- Get hand component by index (0=HMD, 1=Left, 2=Right)
function MotionControllerActors:GetHandComponent(index)
    if index == 0 then
        return self.hmd_component
    elseif index == 1 then
        return self.left_hand_component
    elseif index == 2 then
        return self.right_hand_component
    end
    return nil
end

-- Get location by index (0=HMD, 1=Left, 2=Right)
function MotionControllerActors:GetLocationByIndex(index)
    local component = self:GetHandComponent(index)
    if component then
        -- The method-existence probe must be inside the pcall too: on a destroyed
        -- component the __index metamethod itself throws.
        local success, result = pcall(function()
            if component.K2_GetComponentLocation == nil then return nil end
            return component:K2_GetComponentLocation()
        end)
        if success then
            return result
        end
    end
    return nil
end

-- Get rotation by index (0=HMD, 1=Left, 2=Right)
function MotionControllerActors:GetRotationByIndex(index)
    local component = self:GetHandComponent(index)
    if component then
        local success, result = pcall(function()
            if component.K2_GetComponentRotation == nil then return nil end
            return component:K2_GetComponentRotation()
        end)
        if success then
            return result
        end
    end
    return nil
end

-- Legacy functions for compatibility
function MotionControllerActors:GetLeftHand()
    return self.left_hand_component
end

function MotionControllerActors:GetRightHand()
    return self.right_hand_component
end

function MotionControllerActors:GetHMD()
    return self.hmd_component
end

local my_controllers = MotionControllerActors:new()

-- Return the module
return my_controllers
