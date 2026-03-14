local function find_required_object(name)
    local obj = uevr.api:find_uobject(name)
    if not obj then
        error("Cannot find " .. name)
        return nil
    end

    return obj
end

local function find_required_object_no_cache(class, full_name)
    local matches = class:get_objects_matching(false)
    for i, obj in ipairs(matches) do
        if obj ~= nil and obj:get_full_name() == full_name then
            return obj
        end
    end
    return nil
end

local function find_static_class(name)
    local cl = find_required_object(name)
    if cl and cl.get_class_default_object then
        return cl:get_class_default_object()
    end
    return nil
end


local function validate_object(object)
    if object == nil or not UEVR_UObjectHook.exists(object) then
        return nil
    else
        return object
    end
end

local function destroy_actor(actor)
    if actor ~= nil and not UEVR_UObjectHook.exists(actor) then
        pcall(function()
            if actor.K2_DestroyActor ~= nil then
                actor:K2_DestroyActor()
            end
        end)
    end
    return nil
end

local Statics = find_static_class("Class /Script/Engine.GameplayStatics")
local ftransform_c = find_required_object("ScriptStruct /Script/CoreUObject.Transform")
local zero_transform = StructObject.new(ftransform_c)
local temp_vec3 = Vector3d.new(0, 0, 0)
zero_transform.Rotation.W = 1.0
zero_transform.Scale3D = temp_vec3:set(1.0, 1.0, 1.0)

local function spawn_actor(world_context, actor_class, location, collision_method, owner)

    local actor = Statics:BeginDeferredActorSpawnFromClass(world_context, actor_class, zero_transform, collision_method, owner)

    if actor == nil then
        print("Failed to spawn actor")
        return nil
    end

    Statics:FinishSpawningActor(actor, zero_transform)
    print("Spawned actor")

    return actor
end

return {
    find_required_object = find_required_object,
    find_required_object_no_cache = find_required_object_no_cache,
    find_static_class = find_static_class,
    validate_object = validate_object,
    destroy_actor = destroy_actor,
    spawn_actor = spawn_actor
}