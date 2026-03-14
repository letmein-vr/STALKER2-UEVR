local utils = require("common.utils")
local scopeController = require("Base.scope") -- Require the scope controller
local pawn = uevr.api:get_local_pawn(0)
if not pawn then
    print("No pawn found")
    return
end


local staic_mesh_component_c = utils.find_required_object("Class /Script/Engine.StaticMeshComponent")
local function get_scope_mesh(parent_mesh)
    if not parent_mesh then return nil end

    local child_components = parent_mesh.AttachChildren
    if not child_components then return nil end

    for _, component in ipairs(child_components) do
        if component:is_a(staic_mesh_component_c) and string.find(component:get_fname():to_string(), "scope") then
            return component
        end
    end

    return nil
end

local function GetEquippedWeapon()
    if not pawn then return nil end
    local sk_mesh = pawn.Mesh
    if not sk_mesh then return nil end
    local anim_instance = sk_mesh.AnimScriptInstance
    if not anim_instance then return nil end
    local weapon_mesh = anim_instance.WeaponData.WeaponMesh
    return weapon_mesh
end

-- local weapon_mesh = GetEquippedWeapon()
-- local scope_mesh = get_scope_mesh(weapon_mesh)
-- print("Scope mesh found:", scope_mesh and scope_mesh:get_fname():to_string() or "None")
-- local materials = scope_mesh:GetMaterials()
-- scope_mesh:SetReverseCulling(true) -- Enable reverse culling for the scope mesh
-- scope_mesh:SetScalarParameterValueOnMaterials("TransitionOffset", 0.4)
-- scope_mesh:SetScalarParameterValueOnMaterials("SightParallaxDepth", 10000.0)

-- for i, material in ipairs(materials) do
--     print("Material " .. i .. ": " .. material:get_fname():to_string())
--     -- You can modify the material properties here if needed
--     -- For example, you can set a new texture or change the color
--     if i == 1 then
--         local parent = material.Parent
--         -- parent.BasePropertyOverrides.bOverride_OpacityMaskClipValue = 1
--         -- parent.BasePropertyOverrides.OpacityMaskClipValue = 0.99
--         -- -- parent.BasePropertyOverrides.bOverride_ShadingModel = 1
--         -- -- parent.BasePropertyOverrides.ShadingModel = 1 -- Set to Unlit
--        local material_copy = scope_mesh:CreateAndSetMaterialInstanceDynamicFromMaterial(i - 1, parent)
--         material_copy:SetScalarParameterValue("TransitionOffset", 0.01)
--         -- material_copy:SetScalarParameterValue("GlassReflectionInt", 0.0)
--         material_copy:SetScalarParameterValue("GlassRoughness", 0.0)
--         -- scope_mesh:SetMaterial(i - 1, material_copy)
--     end

-- end

local params = {
    GlassMetallic        = 0.4,
    GlassRoughness       = 0.01,
    GlassReflectionInt   = 0.005,
    GlassOpacity         = 0.2,
    TransitionOffset     = 0.3,
    SightMaskScale       = 2.05,
    SMHardness           = 50.0,
    SightParallaxDepth   = -3.0,
    SightMaskID          = 0.0,
    SightScale           = 0.3,
    RefractionDepthBias  = 0.0,
}

local param_keys = {
    "GlassMetallic",
    "GlassRoughness",
    "GlassReflectionInt",
    "GlassOpacity",
    "TransitionOffset",
    "SightMaskScale",
    "SMHardness",
    "SightParallaxDepth",
    "SightMaskID",
    "SightScale",
    "RefractionDepthBias",
}

local cur_param = 1
-- Config UI as a collapsing header
uevr.sdk.callbacks.on_draw_ui(function()
    local weapon_mesh = GetEquippedWeapon()
    if not weapon_mesh then
        return
    end
    local scope_mesh = get_scope_mesh(weapon_mesh)
    if not scope_mesh then
        return
    end

    local paramChanged, newValue = imgui.combo("Param To Edit", cur_param, param_keys)
    if paramChanged then
        cur_param = newValue
    end
    local param_name = param_keys[cur_param]
    local valueChanged, newValue = imgui.drag_float("Edit: " .. param_name .. " (Debug)", params[param_name], 0.1, -100.0, 100.0, "%.5f")
    if valueChanged then
        params[param_name] = newValue
        scope_mesh:SetScalarParameterValueOnMaterials(param_name, newValue)
    end

end)