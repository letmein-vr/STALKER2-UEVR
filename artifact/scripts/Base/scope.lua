require("common.assetloader")
require("Config.CONFIG")
local utils = require("common.utils")
local GameState = require("stalker2.gamestate")
local controllers = require("libs/controllers")  -- cached at module level (was inside hot function)
local uevrUtils = require("libs/uevr_utils")
local api = uevr.api

local emissive_mesh_material_name = "Material /Engine/EngineMaterials/EmissiveMeshMaterial.EmissiveMeshMaterial"
local reticule_template_material = "Material /Engine/EngineMaterials/DefaultWhiteMaterial.DefaultWhiteMaterial"


local ScopeController = {
    ftransform_c = nil,
    flinearColor_c = nil,
    fvector_c = nil,
    hitresult_c = nil,
    game_engine_class = nil,
    Statics = nil,
    Kismet = nil,
    KismetMaterialLibrary = nil,
    KismetMathLibrary = nil,
    AssetRegistryHelpers = nil,
    actor_c = nil,
    staic_mesh_component_c = nil,
    staic_mesh_c = nil,
    scene_capture_component_c = nil,
    MeshC = nil,
    StaticMeshC = nil,
    CameraManager_c = nil,

    -- Instance variables
    scope_actor = nil,
    scope_plane_component = nil,
    scene_capture_component = nil,
    render_target = nil,
    reusable_hit_result = nil,
    temp_vec3 = Vector3d.new(0, 0, 0),
    temp_vec3f = Vector3f.new(0, 0, 0),
    zero_color = nil,
    zero_transform = nil,

    -- state variables
    current_weapon = nil,
    scope_mesh = nil,
    scope_material = nil,
    left_view_location = Vector3f.new(0, 0, 0),
    right_view_location = Vector3f.new(0, 0, 0),
    material_fix_retry_timer = 0, -- Counter to retry material fixes
    reticule_actor = nil,
    reticule_mesh_component = nil,
    is_reflex_sight = false,
}

function ScopeController:new()
    local instance = {}
    setmetatable(instance, self)
    self.__index = self
    self:InitStatic()
    -- Deep Optimization Phase 2: Init Polling Variables
    instance.scopeInternalTick = 0
    instance.last_activation_result = false
    return instance
end

function ScopeController:InitStatic()
    -- Try to initialize all required objects
    self.ftransform_c = utils.find_required_object("ScriptStruct /Script/CoreUObject.Transform")
    if not self.ftransform_c then return false end

    self.fvector_c = utils.find_required_object("ScriptStruct /Script/CoreUObject.Vector")
    if not self.fvector_c then return false end

    self.flinearColor_c = utils.find_required_object("ScriptStruct /Script/CoreUObject.LinearColor")
    if not self.flinearColor_c then return false end

    self.hitresult_c = utils.find_required_object("ScriptStruct /Script/Engine.HitResult")
    if not self.hitresult_c then return false end

    self.game_engine_class = utils.find_required_object("Class /Script/Engine.GameEngine")
    if not self.game_engine_class then return false end

    self.Statics = utils.find_static_class("Class /Script/Engine.GameplayStatics")
    if not self.Statics then return false end

    self.Kismet = utils.find_static_class("Class /Script/Engine.KismetRenderingLibrary")
    if not self.Kismet then return false end

    self.KismetMaterialLibrary = utils.find_static_class("Class /Script/Engine.KismetMaterialLibrary")
    if not self.KismetMaterialLibrary then return false end

    self.KismetMathLibrary = utils.find_static_class("Class /Script/Engine.KismetMathLibrary")
    if not self.KismetMathLibrary then return false end

    self.AssetRegistryHelpers = utils.find_static_class("Class /Script/AssetRegistry.AssetRegistryHelpers")
    if not self.AssetRegistryHelpers then return false end

    self.actor_c = utils.find_required_object("Class /Script/Engine.Actor")
    if not self.actor_c then return false end

    self.staic_mesh_component_c = utils.find_required_object("Class /Script/Engine.StaticMeshComponent")
    if not self.staic_mesh_component_c then return false end

    self.staic_mesh_c = utils.find_required_object("Class /Script/Engine.StaticMesh")
    if not self.staic_mesh_c then return false end

    self.scene_capture_component_c = utils.find_required_object("Class /Script/Engine.SceneCaptureComponent2D")
    if not self.scene_capture_component_c then return false end

    self.MeshC = utils.find_required_object("Class /Script/Engine.SkeletalMeshComponent")
    if not self.MeshC then return false end

    self.StaticMeshC = utils.find_required_object("Class /Script/Engine.StaticMeshComponent")
    if not self.StaticMeshC then return false end

    self.CameraManager_c = utils.find_required_object("Class /Script/Stalker2.CameraManager")
    if not self.CameraManager_c then return false end

    -- Initialize reusable objects
    self.reusable_hit_result = StructObject.new(self.hitresult_c)
    if not self.reusable_hit_result then return false end

    self.zero_color = StructObject.new(self.flinearColor_c)
    if not self.zero_color then return false end

    self.zero_transform = StructObject.new(self.ftransform_c)
    if not self.zero_transform then return false end
    self.zero_transform.Rotation.W = 1.0
    self.zero_transform.Scale3D = self.temp_vec3:set(1.0, 1.0, 1.0)

    return true
end

function ScopeController:ResetStatic()
    self.ftransform_c = nil
    self.flinearColor_c = nil
    self.fvector_c = nil
    self.hitresult_c = nil
    self.game_engine_class = nil
    self.Statics = nil
    self.Kismet = nil
    self.KismetMaterialLibrary = nil
    self.KismetMathLibrary = nil
    self.AssetRegistryHelpers = nil
    self.actor_c = nil
    self.staic_mesh_component_c = nil
    self.staic_mesh_c = nil
    self.scene_capture_component_c = nil
    self.MeshC = nil
    self.StaticMeshC = nil
    self.CameraManager_c = nil
    self.reusable_hit_result = nil
    self.zero_color = nil
    self.zero_transform = nil
end


function ScopeController:get_render_target(world)
    self.render_target = utils.validate_object(self.render_target)
    if self.render_target == nil then
        self.render_target = self.Kismet:CreateRenderTarget2D(world, Config.scopeTextureSize, Config.scopeTextureSize, 6, self.zero_color, false)
        -- render_target.bHDR = 0;
        -- render_target.SRGB = 0;
    end
    return self.render_target
end

function ScopeController:spawn_scope_plane(world, owner, pos, rt)
    local local_scope_mesh = self.scope_actor:AddComponentByClass(self.staic_mesh_component_c, false, self.zero_transform, false)
    if local_scope_mesh == nil then
        print("Failed to spawn scope mesh")
        return
    end

    local wanted_mat = utils.find_required_object(emissive_mesh_material_name)
    if wanted_mat == nil then
        print("Failed to find material")
        return
    end
    wanted_mat.BlendMode = 7
    wanted_mat.TwoSided = 0
    --     wanted_mat.bDisableDepthTest = true
    --     --wanted_mat.MaterialDomain = 0
    --     --wanted_mat.ShadingModel = 0

    local plane = utils.find_required_object_no_cache(self.staic_mesh_c, "StaticMesh /Engine/BasicShapes/Cylinder.Cylinder")

    if plane == nil then
        print("Failed to find plane mesh")
        -- api:dispatch_custom_event("LoadAsset", "StaticMesh /Engine/BasicShapes/Cylinder.Cylinder")
        local fAssetData = CreateAssetData("/Engine/BasicShapes/Cylinder", "/Engine/BasicShapes", "Cylinder", "/Script/Engine", "StaticMesh")
        plane =  GetLoadedAsset(fAssetData)
        if plane == nil then
            print("Failed to load asset plane mesh")
            return
        end
    end
    local_scope_mesh:SetStaticMesh(plane)
    local_scope_mesh:SetVisibility(false)
    -- local_scope_mesh:SetHiddenInGame(false)
    local_scope_mesh:SetCollisionEnabled(0)

    local dynamic_material = local_scope_mesh:CreateDynamicMaterialInstance(0, wanted_mat, "ScopeMaterial")

    dynamic_material:SetTextureParameterValue("LinearColor", rt)
    local color = StructObject.new(self.flinearColor_c)
    color.R = Config.scopeBrightnessAmplifier
    color.G = Config.scopeBrightnessAmplifier
    color.B = Config.scopeBrightnessAmplifier
    color.A = Config.scopeBrightnessAmplifier
    dynamic_material:SetVectorParameterValue("Color", color)
    self.scope_plane_component = local_scope_mesh
    self.scope_material = dynamic_material
end

function ScopeController:destroy_reticule_actor()
    if self.reticule_mesh_component then
        if uevrUtils.validate_object(self.reticule_mesh_component) then
            print("[DEBUG] Destroying Reticule Component and its Actor Host...")
            local host_actor = self.reticule_mesh_component:GetOwner()
            if uevrUtils.validate_object(host_actor) then
                uevrUtils.destroy_actor(host_actor)
            else
                -- Fallback to component destruction if owner is somehow gone or not an actor
                pcall(function() self.reticule_mesh_component:K2_DestroyComponent(self.reticule_mesh_component) end)
            end
        end
        self.reticule_mesh_component = nil
    end
    -- self.reticule_actor is redundant if we destroy via GetOwner, but kept for legacy safety
    if self.reticule_actor then
        uevrUtils.destroy_actor(self.reticule_actor)
        self.reticule_actor = nil
    end
end

function ScopeController:get_or_create_reticule_component(weapon_mesh)
    if not weapon_mesh or not uevrUtils.validate_object(weapon_mesh) then return nil end
    local weapon_actor = weapon_mesh:GetOwner()
    if not weapon_actor or not uevrUtils.validate_object(weapon_actor) then return nil end

    -- ONE-TIME REFRESH: Destroy the "grey checked" bugged version once
    if uevrUtils.validate_object(self.reticule_mesh_component) and self.force_refresh_fix ~= true then
        self:destroy_reticule_actor()
        self.force_refresh_fix = true -- Only do this once per script load
    end

    -- Check if component exists and is valid
    if not uevrUtils.validate_object(self.reticule_mesh_component) then

        self.reticule_mesh_component = uevrUtils.createStaticMeshComponent("StaticMesh /Engine/EngineMeshes/Sphere.Sphere")

        if self.reticule_mesh_component then
            -- Spawn succeeded — clear any previous failure flag
            self.reticule_spawn_failed = nil

            self.reticule_mesh_component:SetCollisionEnabled(0)
            self.reticule_mesh_component.BoundsScale = 10
            
            -- Set Scale 
            local rx = Config.redDotScaleX or Config.redDotSize or 0.007
            local ry = Config.redDotScaleY or Config.redDotSize or 0.007
            local rz = Config.redDotScaleZ or Config.redDotSize or 0.007
            local scale_vec = uevrUtils.vector(rx, ry, rz)
            self.reticule_mesh_component:SetWorldScale3D(scale_vec)

            -- Set Material (ONCE)
            -- Widget3DPassThrough is the only engine material confirmed to render a visible
            -- coloured dot without requiring a texture. It responds to one of the vector
            -- parameters below (exact name uncertain — full set kept for safety).
            local wanted_mat = utils.find_required_object("Material /Engine/EngineMaterials/Widget3DPassThrough.Widget3DPassThrough")
            if not wanted_mat then
                wanted_mat = utils.find_required_object("Material /Engine/EngineMaterials/DefaultMaterial.DefaultMaterial")
            end

            if wanted_mat then
                -- Additive blend: dot colour adds to the scene, never washed out in daylight
                wanted_mat.BlendMode = 1
                self.reticule_material = self.reticule_mesh_component:CreateDynamicMaterialInstance(0, wanted_mat, uevrUtils.fname_from_string("ReticuleDMI"))
                if self.reticule_material then
                    local color = StructObject.new(self.flinearColor_c)
                    local initIntensity = Config.redDotBrightness or 150.0
                    color.R = initIntensity
                    color.G = 0.0
                    color.B = 0.0
                    color.A = 1.0
                    self.reticule_material:SetVectorParameterValue("EmissiveColor", color)
                    self.reticule_material:SetVectorParameterValue("BaseColor", color)
                    self.reticule_material:SetVectorParameterValue("Color", color)
                    self.reticule_material:SetVectorParameterValue("Tint", color)
                    self.reticule_material:SetVectorParameterValue("TintColor", color)
                    self.reticule_material:SetVectorParameterValue("LinearColor", color)
                    self.reticule_material:SetVectorParameterValue("Emissive", color)
                    self.reticule_material:SetVectorParameterValue("TintColorAndOpacity", color)
                end
            end
        else
            -- Bug B fix: Sphere.Sphere wasn't loaded yet (can happen on certain maps at load time).
            -- Flag it so Update() invalidates current_weapon on the next SECOND, forcing a retry.
            print("[Scope] Red dot spawn failed (Sphere mesh not ready) — will retry.")
            self.reticule_spawn_failed = true
        end
    end

    -- Handle Attachment (only re-attach if parent changed)
    if self.reticule_mesh_component then
        local target_parent = self.scope_mesh or weapon_mesh
        if self.reticule_mesh_component:GetAttachParent() ~= target_parent then
            local parent_mesh = target_parent
            local socket_name = "" -- Root of scope or weapon
            -- Move it 10cm forward and 7cm up to be undeniable
            local relative_offset = uevrUtils.vector(10.0, 0.0, 7.0) 
            
            if not self.scope_mesh then
                socket_name = "Muzzle"
                relative_offset = uevrUtils.vector(-35.0, 0, 8.0)
                if not weapon_mesh:DoesSocketExist(uevrUtils.fname_from_string(socket_name)) then
                    socket_name = "jnt_muzzle"
                    if not weapon_mesh:DoesSocketExist(uevrUtils.fname_from_string(socket_name)) then
                        socket_name = "" 
                    end
                end
            end

            self.reticule_mesh_component:K2_AttachToComponent(
                parent_mesh,
                uevrUtils.fname_from_string(socket_name),
                2, -- SnapToTarget Location
                2, -- SnapToTarget Rotation
                1, -- KeepWorld Scale
                true
            )
            
            self:UpdateReticulePosition()
        end
        
        self.reticule_mesh_component:SetVisibility(true)
        self.reticule_mesh_component:SetHiddenInGame(false)
    end

    return self.reticule_mesh_component
end

function ScopeController:UpdateReticulePosition(scopeName)
    if self.reticule_mesh_component and uevrUtils.validate_object(self.reticule_mesh_component) then
        if not scopeName and self.scope_mesh then
            if self.scope_mesh.SkeletalMesh then
                scopeName = uevrUtils.getShortName(self.scope_mesh.SkeletalMesh)
            elseif self.scope_mesh.StaticMesh then
                scopeName = uevrUtils.getShortName(self.scope_mesh.StaticMesh)
            else
                scopeName = uevrUtils.getShortName(self.scope_mesh)
            end
        end
        
        local currentProf = scopeName and Config.redDotProfiles and Config.redDotProfiles[scopeName] or {}
        local rx = currentProf.scaleX or currentProf.size or Config.redDotScaleX or Config.redDotSize or 0.007
        local ry = currentProf.scaleY or currentProf.size or Config.redDotScaleY or Config.redDotSize or 0.007
        local rz = currentProf.scaleZ or currentProf.size or Config.redDotScaleZ or Config.redDotSize or 0.007
        local scale_vec = uevrUtils.vector(rx, ry, rz)
        self.reticule_mesh_component:SetWorldScale3D(scale_vec)
        
        local offset_vec = uevrUtils.vector(currentProf.offsetX or Config.redDotOffsetX or 0.0, currentProf.offsetY or Config.redDotOffsetY or 0.0, currentProf.offsetZ or Config.redDotOffsetZ or 0.0)
        self.reticule_mesh_component:K2_SetRelativeLocation(offset_vec, false, self.reusable_hit_result, false)
        
        -- Apply Brightness dynamically
        if self.reticule_material then
            local currentBrightness = currentProf.brightness or Config.redDotBrightness or 150.0
            local color = StructObject.new(self.flinearColor_c)
            color.R = currentBrightness
            color.G = 0.0
            color.B = 0.0
            color.A = 1.0
            -- EmissiveMeshMaterial exposes "Color" as its vector parameter
            self.reticule_material:SetVectorParameterValue("Color", color)
            self.reticule_material:SetVectorParameterValue("EmissiveColor", color)
            self.reticule_material:SetVectorParameterValue("BaseColor", color)
            self.reticule_material:SetVectorParameterValue("Tint", color)
            self.reticule_material:SetVectorParameterValue("TintColor", color)
            self.reticule_material:SetVectorParameterValue("LinearColor", color)
            self.reticule_material:SetVectorParameterValue("Emissive", color)
            self.reticule_material:SetVectorParameterValue("TintColorAndOpacity", color)
        end
    end
end

-- Computes and applies the parallax-corrected position for the red dot every frame.
-- Performs a ray-plane intersection: casts a ray from the HMD eye position along the
-- weapon bore axis, finds where it hits the sight glass plane, and places the dot sphere
-- at that local 2D position. This makes the sight behave like a parallax-free reflex sight:
-- the dot always indicates the correct aiming direction regardless of eye angle.
-- Per-scope profile offsets (X/Y/Z) are additive fine-tuning on top.
function ScopeController:UpdateParallaxCorrection()
    if not self.scope_mesh or not self.reticule_mesh_component then return end
    if not uevrUtils.validate_object(self.scope_mesh) then return end
    if not uevrUtils.validate_object(self.reticule_mesh_component) then return end
    if not self.KismetMathLibrary or not self.fvector_c then return end

    -- 1. HMD eye position
    local eye_pos = controllers.getControllerLocation(2)
    if not eye_pos then return end

    -- 2. Sight glass centre: scope mesh world origin (the plane anchor)
    local sight_pos = self.scope_mesh:K2_GetComponentLocation()
    if not sight_pos then return end

    -- 3. Bore forward axis = scope mesh local X axis rotated to world space
    local scope_transform = self.scope_mesh:K2_GetComponentToWorld()
    if not scope_transform then return end
    local local_fwd = StructObject.new(self.fvector_c)
    local_fwd.X = 1.0; local_fwd.Y = 0.0; local_fwd.Z = 0.0
    local bore_fwd = self.KismetMathLibrary:Quat_RotateVector(scope_transform.Rotation, local_fwd)
    if not bore_fwd then return end

    -- 4. Ray-plane intersection parameter:
    --    Ray: P = eye_pos + t * bore_fwd
    --    Plane: (P - sight_pos) · bore_fwd = 0  →  t = (sight_pos - eye_pos) · bore_fwd
    local t = (sight_pos.X - eye_pos.X) * bore_fwd.X
            + (sight_pos.Y - eye_pos.Y) * bore_fwd.Y
            + (sight_pos.Z - eye_pos.Z) * bore_fwd.Z

    -- 5. Hit point in world space, expressed relative to scope mesh origin, for inverse rotation
    local loc_diff = StructObject.new(self.fvector_c)
    loc_diff.X = eye_pos.X + bore_fwd.X * t - scope_transform.Translation.X
    loc_diff.Y = eye_pos.Y + bore_fwd.Y * t - scope_transform.Translation.Y
    loc_diff.Z = eye_pos.Z + bore_fwd.Z * t - scope_transform.Translation.Z

    -- 6. Rotate into scope mesh component space via inverse quaternion
    local inv_q = self.KismetMathLibrary:Quat_Inversed(scope_transform.Rotation)
    local local_hit = self.KismetMathLibrary:Quat_RotateVector(inv_q, loc_diff)
    if not local_hit then return end

    -- 7. Look up per-scope profile — needed for both aperture cull and final offset
    local scopeName = nil
    if self.scope_mesh.SkeletalMesh then
        scopeName = uevrUtils.getShortName(self.scope_mesh.SkeletalMesh)
    elseif self.scope_mesh.StaticMesh then
        scopeName = uevrUtils.getShortName(self.scope_mesh.StaticMesh)
    end
    local prof = (scopeName and Config.redDotProfiles and Config.redDotProfiles[scopeName]) or {}

    -- 8. Aperture cull with shape auto-detection.
    --    Shape is auto-detected from scope name. Per-profile 'apertureShape' overrides this.
    --    "rectangle": abs(dy)>1 OR abs(dz)>1 — each axis is an independent hard limit.
    --    "ellipse":   dy²+dz²>1 — unit-circle test, cuts corners.
    --    colimscope_mini MUST be checked before colimscope (it's a substring).
    local SCOPE_SHAPES = {
        { "colimscope_mini", "ellipse"    },
        { "colimscope",      "rectangle"  },
        { "deadeye_scope",   "rectangle"  },
        { "goloscope",       "rectangle"  },
        { "margach_scope",   "ellipse"    },
    }
    local shape = prof.apertureShape  -- per-profile manual override
    if not shape and scopeName then
        local sn = scopeName:lower()
        for _, entry in ipairs(SCOPE_SHAPES) do
            if sn:find(entry[1], 1, true) then
                shape = entry[2]; break
            end
        end
    end
    shape = shape or "ellipse"  -- safe default

    local legacyR   = prof.apertureRadius or Config.redDotApertureRadius or 5.0
    local apertureY = prof.apertureY  or Config.redDotApertureY  or legacyR
    local apertureZ = prof.apertureZ  or Config.redDotApertureZ  or legacyR
    local centreY   = prof.apertureCentreY or Config.redDotApertureCentreY or 0.0
    local centreZ   = prof.apertureCentreZ or Config.redDotApertureCentreZ or 0.0
    local dy = (local_hit.Y - centreY) / apertureY
    local dz = (local_hit.Z - centreZ) / apertureZ
    local outside
    if shape == "rectangle" then
        outside = math.abs(dy) > 1.0 or math.abs(dz) > 1.0
    else
        outside = (dy * dy + dz * dz) > 1.0
    end
    if outside then
        -- Eye is outside the glass aperture — hide dot
        if self.reticule_visible ~= false then
            self.reticule_visible = false
            self.reticule_mesh_component:SetVisibility(false)
        end
        return
    end
    -- Eye is inside the glass aperture — ensure dot is visible
    if self.reticule_visible ~= true then
        self.reticule_visible = true
        self.reticule_mesh_component:SetVisibility(true)
        self.reticule_mesh_component:SetHiddenInGame(false)
    end

    -- 9. Apply: X = user bore-depth offset (keeps dot on glass face)
    --            Y/Z = parallax correction + user lateral fine-tuning
    self.reticule_mesh_component:K2_SetRelativeLocation(
        self.temp_vec3:set(
            prof.offsetX or Config.redDotOffsetX or 0.0,
            local_hit.Y + (prof.offsetY or Config.redDotOffsetY or 0.0),
            local_hit.Z + (prof.offsetZ or Config.redDotOffsetZ or 0.0)
        ),
        false, self.reusable_hit_result, false
    )
end

function ScopeController:SetScopeBrightness(value)
    if self.scope_material then
        local color = StructObject.new(self.flinearColor_c)
        color.R = value
        color.G = value
        color.B = value
        color.A = value
        self.scope_material:SetVectorParameterValue("Color", color)
    end
end

-- Distance-Based Scope Activation
-- Checks if scope is within activation distance of HMD
function ScopeController:IsWithinActivationDistance()
    if not self.scope_plane_component then return false end
    if not self.scope_plane_component.K2_GetComponentLocation then return false end
    
    -- Deep Optimization Phase 2: Adaptive Polling
    self.scopeInternalTick = (self.scopeInternalTick or 0) + 1
    
    -- If scope was NOT active, throttle checks to save CPU (10Hz check is sufficient for activation)
    if not self.last_activation_result and (self.scopeInternalTick % 10 ~= 0) then
        return false
    end

    -- Get HMD location using controllers library
    -- Auto-create HMD controller if missing: after mid-game injection the level-change
    -- callback that normally creates it never fires, so actors[2] stays nil and
    -- getControllerLocation(2) always returns nil until a manual workaround is done.
    local controllers_lib = controllers  -- use module-level cached require
    if not controllers_lib.hmdControllerExists() then
        controllers_lib.createHMDController()
    end
    local head_location = controllers_lib.getControllerLocation(2)  -- 2 = HMD controller
    if not head_location then return false end
    
    -- Get scope location
    local scope_location = self.scope_plane_component:K2_GetComponentLocation()
    if not scope_location then return false end
    
    -- Calculate distance (in cm)
    local dx = head_location.X - scope_location.X
    local dy = head_location.Y - scope_location.Y
    local dz = head_location.Z - scope_location.Z
    local distance = math.sqrt(dx*dx + dy*dy + dz*dz)
    
    -- Check if within activation distance
    local threshold = Config.scopeActivationDistance or 15.0
    local result = distance < threshold
    
    self.last_activation_result = result
    return result
end

function ScopeController:spawn_scene_capture_component(world, owner, pos, fov, rt)
    local local_scene_capture_component = self.scope_actor:AddComponentByClass(self.scene_capture_component_c, false, self.zero_transform, false)
    if local_scene_capture_component == nil then
        print("Failed to spawn scene capture")
        return
    end
    local_scene_capture_component.TextureTarget = rt
    local_scene_capture_component.FOVAngle = fov
    local_scene_capture_component.bCacheVolumetricCloudsShadowMaps = true;
    -- local_scene_capture_component.bCachedDistanceFields = 1;
    local_scene_capture_component.bUseRayTracingIfEnabled = false;
    -- local_scene_capture_component.PrimitiveRenderMode = 2; -- 0 - legacy, 1 - other
    -- local_scene_capture_component.CaptureSource = 1;
    local_scene_capture_component.bAlwaysPersistRenderingState = true;
    local_scene_capture_component.bEnableVolumetricCloudsCapture = false;
    local_scene_capture_component.bCaptureEveryFrame = 1;

    -- post processing
    local_scene_capture_component.PostProcessSettings.bOverride_MotionBlurAmount = true
    local_scene_capture_component.PostProcessSettings.MotionBlurAmount = 0.0 -- Disable motion blur
    local_scene_capture_component.PostProcessSettings.bOverride_ScreenSpaceReflectionIntensity = true
    local_scene_capture_component.PostProcessSettings.ScreenSpaceReflectionIntensity = 0.0 -- Disable screen space reflections
    local_scene_capture_component.PostProcessSettings.bOverride_AmbientOcclusionIntensity = true
    local_scene_capture_component.PostProcessSettings.AmbientOcclusionIntensity = 0.0 -- Disable ambient occlusion
    local_scene_capture_component.PostProcessSettings.bOverride_BloomIntensity = true
    local_scene_capture_component.PostProcessSettings.BloomIntensity = 0.0
    local_scene_capture_component.PostProcessSettings.bOverride_LensFlareIntensity = true
    local_scene_capture_component.PostProcessSettings.LensFlareIntensity = 0.0 -- Disable lens flares
    local_scene_capture_component.PostProcessSettings.bOverride_VignetteIntensity = true
    local_scene_capture_component.PostProcessSettings.VignetteIntensity = 0.0 -- Disable vignette

    -- Fix for Floating/HMD-Tracking Scope View:
    -- Ensure component ignores Pawn rotation and relies strictly on parent (Weapon) attachment
    pcall(function() local_scene_capture_component:SetAbsolute(false, false, false) end)
    pcall(function() local_scene_capture_component.bUsePawnControlRotation = false end)

    local_scene_capture_component:SetVisibility(false)
    self.scene_capture_component = local_scene_capture_component
end

function ScopeController:spawn_scope(game_engine, pawn)
    local viewport = game_engine.GameViewport
    if viewport == nil then
        print("Viewport is nil")
        return
    end

    local world = viewport.World
    if world == nil then
        print("World is nil")
        return
    end

    if not pawn then
        -- print("pawn is nil")
        return
    end

    local rt = self:get_render_target(world)

    if rt == nil then
        print("Failed to get render target destroying actors")
        self.scope_actor = utils.destroy_actor(self.scope_actor)
        self.scope_plane_component = nil
        self.scene_capture_component = nil
        return
    end

    local pawn_pos = pawn:K2_GetActorLocation()
    if not utils.validate_object(self.scope_actor) then
        self.scope_actor = utils.destroy_actor(self.scope_actor)
        self.scope_plane_component = nil
        self.scene_capture_component = nil
        self.scope_actor = utils.spawn_actor(world, self.actor_c, self.temp_vec3:set(0, 0, 0), 1, nil)
        if self.scope_actor == nil then
            print("Failed to spawn scope actor")
            return
        end
    end

    if not utils.validate_object(self.scope_plane_component) then
        print("scope_plane_component is invalid -- recreating")
        self:spawn_scope_plane(world, nil, pawn_pos, rt)
    end

    if not utils.validate_object(self.scene_capture_component) then
        print("spawn_scene_capture_component is invalid -- recreating")
        local fov = (pawn.Camera and pawn.Camera.FieldOfView) or 90.0
        self:spawn_scene_capture_component(world, nil, pawn_pos, fov, rt)
    end

end


-- Helper to reset material to original state (BlendMode 7) for standard scopes
function ScopeController:reset_material_to_standard()
    local wanted_mat = utils.find_required_object(emissive_mesh_material_name)
    if wanted_mat then
        wanted_mat.BlendMode = 7 -- Opaque/Masked usually
        wanted_mat.TwoSided = 0
    end
end

-- New Standalone Function: Scans weapon and applies material fixes INDEPENDENTLY of PIP
function ScopeController:scan_and_fix_materials(weapon_mesh)
    if not weapon_mesh then return end
    
    local found_any = false

    -- Helper to process a mesh
    local function process_mesh(mesh)
        if not mesh or not UEVR_UObjectHook.exists(mesh) then return false end
        
        -- Bug C fix: prefer the StaticMesh ASSET name (stable across saves),
        -- fall back to the component instance FName only if no asset is found.
        local name = nil
        if mesh.StaticMesh and UEVR_UObjectHook.exists(mesh.StaticMesh) then
            name = mesh.StaticMesh:get_fname():to_string():lower()
        end
        -- Fallback to component FName
        if not name or name == "" or name == "none" then
            name = mesh:get_fname():to_string():lower()
        end

        if name:find("deadeye_scope") or name:find("goloscope") or name:find("colimscope") or name:find("margach_scope") then  
             
             local min_index = 1
             if name:find("goloscope") then min_index = 2 
             elseif name:find("colimscope_mini") then min_index = 1
             elseif name:find("colimscope") then min_index = 2
             elseif name:find("deadeye_scope") then min_index = 1
             elseif name:find("margach_scope") then min_index = 2 end
             
             -- PERF: Only run the expensive transparency fix (DMI creation, SetCastShadow etc.)
             -- when the scope component address has actually changed. Quick re-scans from the
             -- heartbeat just re-flag without repeating the costly UE material calls.
             local mesh_addr = mesh:get_address()
             if mesh_addr ~= self.transparency_fix_applied_addr then
                 -- Dump materials once for diagnostics
                 if not self.has_dumped_scope_mats then
                     self.has_dumped_scope_mats = true
                     print("\n[DEBUG-MAT] --- DUMPING SCOPE MATERIALS FOR: " .. name .. " ---")
                     local num_mats2 = mesh:GetNumMaterials()
                     for mi = 0, num_mats2 - 1 do
                         local mat2 = mesh:GetMaterial(mi)
                         if mat2 then
                             print(string.format("[DEBUG-MAT] [%d]: %s", mi, mat2:get_fname():to_string()))
                         else
                             print(string.format("[DEBUG-MAT] [%d]: NIL", mi))
                         end
                     end
                     print("[DEBUG-MAT] --- END MATERIAL DUMP ---\n")
                 end

                 pcall(function() self:apply_transparency_fix(mesh, min_index) end)
                 pcall(function()
                       mesh:SetCastShadow(false)
                       mesh:SetRenderCustomDepth(false)
                 end)
                 self.transparency_fix_applied_addr = mesh_addr
                 print("[DEBUG] Reflex Sight Detected (transparency fix applied): " .. name)
             end
             
            -- Flag as reflex sight for red dot logic
             self.is_reflex_sight = true
             self.scope_mesh = mesh
             return true
        end
        return false
    end
    
    self.is_reflex_sight = false -- Reset before scan
    
    -- ROOT CAUSE FIX (confirmed via MCP live inspection):
    -- Scope attachments (goloscope, colimscope, etc.) are children of WeaponInHandsMesh,
    -- NOT of WeaponData.WeaponMesh (what weapon_mesh is). We must scan WeaponInHandsMesh too.
    local weapon_in_hands = GameState:GetWeaponInHandsMesh()
    
    -- Helper: scan a mesh's direct children and one level of grandchildren
    local function scan_mesh_children(parent_mesh)
        if not parent_mesh then return end
        local children = parent_mesh.AttachChildren
        if not children then return end
        for i = 1, #children do
            local child = children[i]
            if child and UEVR_UObjectHook.exists(child) then
                if process_mesh(child) then
                    print("[DEBUG] FOUND FIX TARGET: " .. child:get_fname():to_string())
                    found_any = true
                end
                if child.AttachChildren then
                    for j = 1, #child.AttachChildren do
                        local gc = child.AttachChildren[j]
                        if gc and UEVR_UObjectHook.exists(gc) then
                            if process_mesh(gc) then
                                print("[DEBUG] FOUND FIX TARGET (Nested): " .. gc:get_fname():to_string())
                                found_any = true
                            end
                        end
                    end
                end
            end
        end
    end

    -- 1. Primary scan: WeaponInHandsMesh (where scope SMCs actually live)
    if weapon_in_hands then
        scan_mesh_children(weapon_in_hands)
    end

    -- 2. Also check Main Scope Mesh via GameState cache (fallback for non-HandsOnly weapons)
    if not found_any then
        local main_scope = GameState:get_scope_mesh(weapon_mesh)
        if main_scope then
            if process_mesh(main_scope) then found_any = true end
        end
    end

    -- 3. Fallback: scan weapon_mesh children (WeaponData.WeaponMesh path, legacy)
    if not found_any then
        scan_mesh_children(weapon_mesh)
    end
    
    if not found_any then
         -- Always reset to standard if no target scope is found
         print("DEBUG: No transparent scope found. Resetting material.")
         self:reset_material_to_standard()
    end
    
    return found_any
end

function ScopeController:attach_components_to_weapon(weapon_mesh)
    if not weapon_mesh then return end

    -- Run the material fix logic first (Decoupled)
    local is_transparent_scope = self:scan_and_fix_materials(weapon_mesh)

    -- Detect and destroy scene capture if it's a transparency scope
    -- Detect and destroy scene capture if it's a transparency scope
    if is_transparent_scope then
         if self.scene_capture_component then
             -- Safety Check: Ensure component is valid before accessing
             if UEVR_UObjectHook.exists(self.scene_capture_component) then
                 if self.scene_capture_component.K2_DestroyComponent then
                     pcall(function() self.scene_capture_component:K2_DestroyComponent(self.scene_capture_component) end)
                 else
                     pcall(function() 
                        self.scene_capture_component:DetachFromParent(true, true)
                        self.scene_capture_component:SetVisibility(false)
                     end)
                 end
             end
             self.scene_capture_component = nil 
         end
         -- Return early to skip PIP attachment
         return
    end

    -- Attach scene capture to weapon (Only for normal scopes)
    if self.scene_capture_component ~= nil then
        local socketName = "Muzzle"
        if not weapon_mesh:DoesSocketExist(socketName) then
             -- print("[Scope] WARNING: Muzzle socket missing, attaching to Root")
             socketName = nil 
        end

        self.scene_capture_component:K2_AttachToComponent(
            weapon_mesh,
            socketName,
            2, -- Location rule
            2, -- Rotation rule
            0, -- Scale rule
            true -- Weld simulated bodies
        )
        self.scene_capture_component:K2_SetRelativeRotation(self.temp_vec3:set(0, 0, 90), false, self.reusable_hit_result, false)
        self.scene_capture_component:K2_SetRelativeLocation(self.temp_vec3:set(0.5, 0, 0), false, self.reusable_hit_result, false)
        self.scene_capture_component:SetVisibility(false)
    end

    -- Attach plane to weapon
    if self.scope_plane_component then
        -- Find main scope mesh for attachment (prefer one with socket)
        self.scope_mesh = GameState:get_scope_mesh(weapon_mesh)
        
        local parent_mesh = self.scope_mesh
        local socketName = "OpticCutoutSocket"

        -- Critical Fallback: If scope mesh is not found, attach to weapon mesh to prevent floating
        if parent_mesh == nil then
             print("[Scope] WARNING: Scope Mesh not found! Falling back to Weapon Mesh")
             parent_mesh = weapon_mesh
             socketName = "Muzzle" -- Try Muzzle, better than Root (Hand)
        end
        
        -- Check if socket exists on the chosen parent
        if not parent_mesh:DoesSocketExist(socketName) then
             socketName = nil -- Fallback to Root
        end
        
        -- Get ALL scope meshes to ensure we mask everything (lens caps, glass, etc.)
        local all_scope_meshes = GameState:get_all_scope_meshes(weapon_mesh)
        if all_scope_meshes then
            for _, mesh in ipairs(all_scope_meshes) do
                -- print("Masking scope mesh: " .. mesh:get_fname():to_string())
                mesh:SetScalarParameterValueOnMaterials("SightMaskScale", 0.0)
            end
        end

        self.scope_plane_component:K2_AttachToComponent(
            parent_mesh,
            socketName,
            2, -- Location rule
            2, -- Rotation rule
            2, -- Scale rule
            true -- Weld simulated bodies
        )
        
        -- Fix for Floating Plane:
        pcall(function() self.scope_plane_component:SetAbsolute(false, false, false) end)
        pcall(function() self.scope_plane_component.bUsePawnControlRotation = false end)
        self.scope_plane_component:K2_SetRelativeRotation(self.temp_vec3:set(0, 90, 90), false, self.reusable_hit_result, false)
        self.scope_plane_component:K2_SetRelativeLocation(self.temp_vec3:set(Config.cylinderDepth, 0, 0), false, self.reusable_hit_result, false)
        self.scope_plane_component:SetWorldScale3D(self.temp_vec3:set(Config.scopeDiameter, Config.scopeDiameter, Config.cylinderDepth))
        self.scope_plane_component:SetVisibility(false)
    end
end

-- Helper function moved to outer scope
function ScopeController:apply_transparency_fix(mesh, min_material_index)
    if not mesh then return end
    
    local num_materials = mesh:GetNumMaterials()
    
    local wanted_mat = utils.find_required_object(emissive_mesh_material_name)
    if not wanted_mat then 
        print("[Scope] Failed to find Translucent Template Material")
        return 
    end
    
    -- Force Translucent for the scope fix
    wanted_mat.BlendMode = 2 -- Translucent
    wanted_mat.TwoSided = 0
    wanted_mat.MaterialDomain = 0 -- Surface
    
     for i = min_material_index, num_materials - 1 do
        -- CHECK: Is the material already fixed?
        local current_mat = mesh:GetMaterial(i)
        local needs_fix = true
        
        if current_mat then
            local mat_name = current_mat:get_fname():to_string()
            if mat_name:find("ScopeFixDMI") then
                needs_fix = false  
                -- print("DEBUG: Material " .. i .. " is already fixed: " .. mat_name)
            else
                print("DEBUG: Material " .. i .. " needs fix. Current: " .. mat_name)
            end
        else
            print("DEBUG: Material " .. i .. " is nil")
        end
        
        if needs_fix then
            print("[ScopeFix] Applying transparency to material index " .. i .. " on " .. mesh:get_fname():to_string())
            local dmi_name = uevrUtils.fname_from_string("ScopeFixDMI_" .. tostring(i))
            local dmi = mesh:CreateDynamicMaterialInstance(i, wanted_mat, dmi_name)
            if dmi then
                local zero_color = StructObject.new(self.flinearColor_c)
                zero_color.R = 0.0
                zero_color.G = 0.0
                zero_color.B = 0.0
                zero_color.A = 0.0 -- Invisible
                dmi:SetVectorParameterValue("Color", zero_color)
            else
                print("DEBUG: Failed to create DMI for index " .. i)
            end
        end
    end
end


function ScopeController:update_scope_state(pawn, weapon_mesh)
    -- Robust Time-Based Heartbeat (Runs once per second)
    local current_time = os.clock()
    if not self.last_scan_time or (current_time - self.last_scan_time > 1.0) then
         self.last_scan_time = current_time
         if weapon_mesh then
             -- PERF: Skip the expensive full re-scan if we already know this is a reflex sight
             -- and the scope mesh is still alive. Only re-scan if:
             --   a) scope not yet detected (is_reflex_sight=false)
             --   b) scope_mesh was invalidated
             --   c) safety re-scan every 30 seconds (catches hot-swaps that bypass weapon_changed)
             local scope_confirmed = self.is_reflex_sight
                 and self.scope_mesh
                 and UEVR_UObjectHook.exists(self.scope_mesh)
             local needs_rescan = not scope_confirmed
             if not needs_rescan then
                 self.heartbeat_rescan_tick = (self.heartbeat_rescan_tick or 0) + 1
                 if self.heartbeat_rescan_tick >= 30 then
                     self.heartbeat_rescan_tick = 0
                     needs_rescan = true  -- safety net: re-check every 30 seconds
                 end
             end
             if needs_rescan then
                 self:attach_components_to_weapon(weapon_mesh)
             end
         end
    end

    -- Distance-based activation: Scope only renders when close to HMD
    local current_scope_state = self:IsWithinActivationDistance()
    
    if current_scope_state then
        -- Throttle FOV update to every 3 ticks: FOV only changes during ADS transitions (slow)
        if self.scopeInternalTick % 3 == 0 then
            self:Recalculate_FOV(pawn)
        end
    end
    if self.scope_plane_component ~= nil then
        self.scope_plane_component:SetVisibility(current_scope_state)
        self.scope_plane_component:SetHiddenInGame(not current_scope_state)
    end
    if self.scene_capture_component ~= nil then
        self.scene_capture_component:SetVisibility(current_scope_state)
        self.scene_capture_component:SetHiddenInGame(not current_scope_state)
    end
end

function ScopeController:GetRelativeLocation(component, point)
    local pomponent_transform = component:K2_GetComponentToWorld()
    local pomponent_rotation_inv_q = self.KismetMathLibrary:Quat_Inversed(pomponent_transform.Rotation)
    local location_diff = StructObject.new(self.fvector_c)
    location_diff.X = point.X - pomponent_transform.Translation.X
    location_diff.Y = point.Y - pomponent_transform.Translation.Y
    location_diff.Z = point.Z - pomponent_transform.Translation.Z
    local relative_location = self.KismetMathLibrary:Quat_RotateVector(pomponent_rotation_inv_q, location_diff)
    return relative_location
end

function ScopeController:UpdateIndoorMode(indoor)
    if self.scene_capture_component then
        self.scene_capture_component.CaptureSource = indoor and 8 or 0
    end
end

-- function ScopeController:CalcActorScreenSizeSqUE(actor, eye)
--     if motionControllerActors:GetHMD() == nil then
--         return 1.0
--     end
--     local projection_matrix = UEVR_Matrix4x4f.new()
--     uevr.params.vr.get_ue_projection_matrix(eye, projection_matrix)
--     -- col is zero indexed, row is one indexed....
--     local ScreenMultiple = math.max(0.5 * projection_matrix[0][1], 0.5 * projection_matrix[1][2]);
--     -- local origin = StructObject.new(self.fvector_c)
--     local boxextent = StructObject.new(self.fvector_c)
--     local origin = self.scope_plane_component:K2_GetComponentLocation()
--     actor:GetActorBounds(false, origin, boxextent, false)
--     local radius = math.max(boxextent.X, boxextent.Y, boxextent.Z)
--     -- local radius = 100.0 * 0.025 * 0.5
--     local hmd_component= motionControllerActors:GetHMD()
--     local relative_location = self:GetRelativeLocation(hmd_component, origin)
--     local distance = math.max(0.01, relative_location.X)
--     local distance_squared = math.max(0.1, distance * distance * projection_matrix[2][4])
--     local screen_radius_squared = (ScreenMultiple * radius * ScreenMultiple * radius) / distance_squared
--     return screen_radius_squared
-- end

-- local function distance(from, to)
--     local dx = from.X - to.X
--     local dy = from.Y - to.Y
--     local dz = from.Z - to.Z
--     return math.sqrt(dx * dx + dy * dy + dz * dz)
-- end

-- function ScopeController:GetViewDistance(eye)
--     local origin = self.scope_plane_component:K2_GetComponentLocation()
--     return distance(origin, eye == 0 and self.left_view_location or self.right_view_location)
-- end

-- function ScopeController:CalcActorScreenSizeSq(actor, eye)
--     if motionControllerActors:GetHMD() == nil then
--         return 1.0
--     end
--     local projection_matrix = UEVR_Matrix4x4f.new()
--     uevr.params.vr.get_ue_projection_matrix(eye, projection_matrix)
--     -- col is zero indexed, row is one indexed....
--     local tanFov = 2.0 / projection_matrix[0][1];
--     -- local tanHalfFov = math.tan(math.atan(tanFov) * 0.5);
--     local origin = StructObject.new(self.fvector_c)
--     local boxextent = StructObject.new(self.fvector_c)
--     actor:GetActorBounds(false, origin, boxextent, false)
--     -- local origin = self.scope_plane_component:K2_GetComponentLocation()
--     local hmd_component= motionControllerActors:GetHMD()
--     local relative_location = self:GetRelativeLocation(hmd_component, origin)
--     local radius = math.max(boxextent.X, boxextent.Y, boxextent.Z)
--     -- local radius = 100.0 * Config.scopeDiameter * 0.5
--     local distance = relative_location.X  -- - projection_matrix[2][4]
--     local distance = math.max(0.01, distance)
--     -- local distance_squared = distance * distance  * projection_matrix[2][4]
--     local screen_radius_squared = (2.0 * radius) / (tanFov * distance)
--     return screen_radius_squared -- 1.5 is magic number which does not make any sense
-- end


function ScopeController:Recalculate_FOV(c_pawn)
    if self.scope_actor == nil or self.scene_capture_component == nil then return end

    local disc_radius_cm = Config.scopeDiameter * 50.0  -- cylinder base radius = 50 UU at scale 1
    local captured_fov = nil

    if Config.scopeExpandingFOV and self.scope_plane_component
    and UEVR_UObjectHook.exists(self.scope_plane_component) then
        -- EXPANDING FOV MODE:
        -- capture_FOV tracks the disc's live angular size from the HMD.
        -- Effect: closer eye → wider scope view, but every object in the scope stays
        -- the same apparent size (magnification = 1/scopeMagnifier, constant with distance).
        local head_loc = controllers.getControllerLocation(2)
        local scope_loc = nil
        pcall(function() scope_loc = self.scope_plane_component:K2_GetComponentLocation() end)
        if head_loc and scope_loc then
            local dx = head_loc.X - scope_loc.X
            local dy = head_loc.Y - scope_loc.Y
            local dz = head_loc.Z - scope_loc.Z
            local dist = math.max(math.sqrt(dx*dx + dy*dy + dz*dz), 0.1)
            local disc_fov_deg = math.deg(math.atan(disc_radius_cm / dist)) * 2.0
            captured_fov = math.max(1.0, math.min(170.0, disc_fov_deg * Config.scopeMagnifier))
        end
    end

    if captured_fov == nil then
        -- FIXED CONTENT MODE (default):
        -- capture_FOV is locked to the disc's angular size at the activation distance.
        -- Same world content is framed regardless of HMD distance.
        -- Objects inside appear larger as you lean in (the disc physically fills more of your view).
        local ref_dist = math.max(Config.scopeActivationDistance or 15.0, 0.5)
        local disc_fov_at_ref = math.deg(math.atan(disc_radius_cm / ref_dist)) * 2.0
        captured_fov = math.max(1.0, math.min(170.0, disc_fov_at_ref * Config.scopeMagnifier))
    end

    self.scene_capture_component.FOVAngle = captured_fov
end


function ScopeController:Update(engine)
    -- Self-healing: if ResetStatic() was called without a matching InitStatic()
    -- (e.g. after on_script_reset when the require cache keeps the old instance),
    -- re-initialise here so Update() doesn't silently fail inside pcall.
    if not self.Statics then
        if not self:InitStatic() then return end
    end
    local c_pawn = api:get_local_pawn(0)
    local weapon_mesh = GameState:GetEquippedWeapon()
    if weapon_mesh then
        -- Bug B fix: if a previous reticule spawn failed (Sphere mesh not loaded yet),
        -- invalidate current_weapon once per ~second so weapon_changed fires and retries the spawn.
        if self.reticule_spawn_failed then
            self.reticule_spawn_retry_tick = (self.reticule_spawn_retry_tick or 0) + 1
            if self.reticule_spawn_retry_tick % 60 == 0 then
                self.current_weapon = nil  -- force weapon_changed = true next tick
            end
        end

        -- fix_materials(weapon_mesh)
        local weapon_changed = not self.current_weapon or weapon_mesh.AnimScriptInstance ~= self.current_weapon.AnimScriptInstance
        -- Check for a live scope swap (user detached one and attached another)
        -- Capture whether we had NO scope before this detection runs.
        -- Used below to distinguish scope ADD (nil->scope, always refresh)
        -- from scope SWAP (A->B, keep ADS gate so we don't force-spawn while idle).
        local had_no_scope = (self.tracked_main_mesh_addr == nil)
        local current_true_scope = GameState:get_scope_mesh(weapon_mesh)
        local was_scope_swapped = false
        if current_true_scope then
            local scope_addr = current_true_scope:get_address()
            if self.tracked_main_mesh_addr ~= scope_addr then
                was_scope_swapped = true
                self.tracked_main_mesh_addr = scope_addr
                self:destroy_reticule_actor()
            end
        elseif self.tracked_main_mesh_addr ~= nil then
            was_scope_swapped = true
            self.tracked_main_mesh_addr = nil
            self:destroy_reticule_actor()
        end

        -- Bug E fix: get_scope_mesh may return nil for nested scopes (on rails), but
        -- scan_and_fix_materials() may already have set self.scope_mesh from its deeper scan.
        -- If that happened and we haven't tracked it yet, treat it as a new scope ADD.
        if not current_true_scope and self.scope_mesh and UEVR_UObjectHook.exists(self.scope_mesh) then
            local deep_addr = self.scope_mesh:get_address()
            if self.tracked_main_mesh_addr ~= deep_addr then
                was_scope_swapped = true
                had_no_scope = true  -- treat as fresh add so ADS gate is bypassed
                self.tracked_main_mesh_addr = deep_addr
                self:destroy_reticule_actor()
            end
        end

        -- Scope ADD (no scope -> scope): always refresh regardless of ADS state.
        -- Scope SWAP (A -> B): keep is_scope_active gate to avoid re-spawning while idle.
        local scope_changed = was_scope_swapped and (had_no_scope or GameState:is_scope_active(c_pawn))
        if weapon_changed or scope_changed then

            -- Update current weapon reference
            self.current_weapon = weapon_mesh

            -- Clear transparency addr so apply_transparency_fix always runs fresh on weapon change
            -- (needed for save loads where scope addr may be identical to previous session)
            self.transparency_fix_applied_addr = nil
            self.heartbeat_rescan_tick = 0  -- reset safety rescan counter

            -- Attempt to attach components
            self:spawn_scope(engine, c_pawn)
            self:attach_components_to_weapon(weapon_mesh)
            -- H4: invalidate reticule visibility cache on weapon/scope change
            self.reticule_visible = nil
            
            -- PERF: Only run the material retry loop for non-reflex scopes.
            -- For reflex sights, scope detection is done inside scan_and_fix_materials;
            -- the retry loop calls get_all_scope_meshes on WeaponData.WeaponMesh which is
            -- the WRONG mesh (scopes live on WeaponInHandsMesh) and causes 6 redundant
            -- UE bridge traversals over 60 frames.
            if not self.is_reflex_sight then
                self.material_fix_retry_timer = 60
            else
                self.material_fix_retry_timer = 0
            end
        end
        
        -- H3 perf: pass weapon_mesh into update_scope_state to avoid redundant GetEquippedWeapon()
        self:update_scope_state(c_pawn, weapon_mesh)

        if self.is_reflex_sight and self.scope_mesh then
            self:get_or_create_reticule_component(weapon_mesh)
            
            if self.reticule_mesh_component then
                -- H4 perf: dirty-check — only call bridge when visibility state changes
                if self.reticule_visible ~= true then
                    self.reticule_visible = true
                    self.reticule_mesh_component:SetVisibility(true)
                    self.reticule_mesh_component:SetHiddenInGame(false)
                end

                -- Parallax correction: reposition dot every frame so it indicates the
                -- correct aim point regardless of HMD angle relative to the bore axis
                self:UpdateParallaxCorrection()

                -- Status verification (Parallax Info)
                if self.scopeInternalTick % 120 == 0 then
                    local loc = self.reticule_mesh_component:K2_GetComponentLocation()
                    local parent = self.reticule_mesh_component:GetAttachParent()
                    local hmd_pos = controllers.getControllerLocation(2)
                    local dist = hmd_pos and uevrUtils.distanceBetween(loc, hmd_pos) or -1
                end
            end
        else
            -- Hide if not a reflex sight
            if self.reticule_mesh_component then
                -- H4 perf: dirty-check — only call bridge when visibility state changes
                if self.reticule_visible ~= false then
                    self.reticule_visible = false
                    self.reticule_mesh_component:SetVisibility(false)
                end
            end
        end
        -- Continuous Material Fix Retry (Fixes glitch on first equip OR after settings change)
        -- PERF: Skipped entirely for reflex sights (material_fix_retry_timer forced to 0 above).
        -- The retry loop uses get_all_scope_meshes(weapon_mesh) which scans the wrong mesh for
        -- reflex sights; scopes live on WeaponInHandsMesh, not WeaponData.WeaponMesh.
        if self.material_fix_retry_timer and self.material_fix_retry_timer > 0 then
             self.material_fix_retry_timer = self.material_fix_retry_timer - 1
             if self.material_fix_retry_timer % 10 == 0 then -- Check every 10 frames
                 if self.current_weapon then
                      local all_scope_meshes = GameState:get_all_scope_meshes(self.current_weapon)
                      if all_scope_meshes then
                          for _, mesh in ipairs(all_scope_meshes) do
                              local name = mesh:get_fname():to_string():lower()
                              if name:find("holo") or name:find("deadeye_scope") or name:find("colimator") or name:find("goloscope") then
                                   pcall(function()
                                        mesh:SetScalarParameterValueOnMaterials("Refraction", 0.0)
                                        mesh:SetScalarParameterValueOnMaterials("Specular", 0.0)
                                        mesh:SetScalarParameterValueOnMaterials("Roughness", 0.0)
                                        mesh:SetScalarParameterValueOnMaterials("Metallic", 0.0)
                                        mesh:SetScalarParameterValueOnMaterials("SightMaskScale", 0.0)
                                   end)
                              end
                          end
                      end
                 end
             end
        else
            -- Low frequency check (every 100 frames ~ 1 sec) to catch settings changes (e.g. DLSS toggle)
            if self.scopeInternalTick % 100 == 0 then
                self.material_fix_retry_timer = 2 -- Pulse the fixer briefly
            end
        end
    else
        -- Weapon was removed/unequipped
        if self.current_weapon then
            self.current_weapon = nil
            self.scope_mesh = nil
            self.tracked_main_mesh_addr = nil -- Flush address tracking
            self:destroy_reticule_actor()    -- Kill the ball immediately
        end
    end
    -- Pass weapon_mesh so the 1-second heartbeat inside update_scope_state actually fires.
    -- Previously this was called without weapon_mesh, making the heartbeat re-scan dead code.
    self:update_scope_state(c_pawn, weapon_mesh)
end

function ScopeController:Reset()
    self.scope_actor = utils.destroy_actor(self.scope_actor)
    self:destroy_reticule_actor()
    self.scope_plane_component = nil
    self.scene_capture_component = nil
    self.render_target = nil
    self.scope_mesh = nil
    self.current_weapon = nil
    self.scope_material = nil
    self.is_reflex_sight = false
    -- Clear detection / dirty-check state so the next Update() treats everything as new
    self.tracked_main_mesh_addr = nil
    self.reticule_visible = nil
    self.force_refresh_fix = nil
    self.heartbeatTick = 0
    self.has_dumped_scope_mats = nil
    -- Clear spawn-retry state (Bug B fix)
    self.reticule_spawn_failed = nil
    self.reticule_spawn_retry_tick = nil
    -- Clear perf-gate state
    self.transparency_fix_applied_addr = nil
    self.heartbeat_rescan_tick = nil
end

function ScopeController:SetScopePlaneScale(depth)
    if self.scope_plane_component then
        self.scope_plane_component:SetWorldScale3D(self.temp_vec3:set(Config.scopeDiameter, Config.scopeDiameter, depth))
        self.scope_plane_component:K2_SetRelativeLocation(self.temp_vec3:set(depth, 0, 0), false, self.reusable_hit_result, false)
    end
end

local scope_controller = ScopeController:new()

local callback_tick = 0
uevr.sdk.callbacks.on_pre_engine_tick(
	function(engine, delta)
        -- callback_tick = callback_tick + 1
        -- if callback_tick % 120 == 0 then -- reduced frequency to 2s
        --     print("[DEBUG] Scope Tick Callback Alive: " .. callback_tick)
        -- end

        local success, err = pcall(function()
            if GameState:IsLevelChanged(engine) then
                -- print("[DEBUG] Level Changed - Resetting Logic")
                scope_controller:Reset()
            end
            -- print("[DEBUG] Calling Update (InternalTick: " .. tostring(scope_controller.scopeInternalTick) .. ")")
            scope_controller:Update(engine)
        end)
        
        if not success then
        end
    end
)

-- uevr.sdk.callbacks.on_post_calculate_stereo_view_offset(function(device, view_index, world_to_meters, position, rotation, is_double)
--     if not vr.is_hmd_active() then
--         return
--     end
--     if view_index == 0 then
--         scope_controller.left_view_location.x = position.x
--         scope_controller.left_view_location.y = position.y
--         scope_controller.left_view_location.z = position.z
--     elseif view_index == 1 then
--         scope_controller.right_view_location.x = position.x
--         scope_controller.right_view_location.y = position.y
--         scope_controller.right_view_location.z = position.z
--     end
-- end)


uevr.sdk.callbacks.on_script_reset(function()
    scope_controller:Reset()
    scope_controller:ResetStatic()
    -- Re-initialise statics immediately so the first tick after reset doesn't fail.
    -- (If the require cache keeps the old instance, Update()'s self-healing guard
    -- also covers this, but explicit init here is safer.)
    scope_controller:InitStatic()
end)


return scope_controller
