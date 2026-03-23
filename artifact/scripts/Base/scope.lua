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
        print("[DEBUG] Creating Red Dot Component (Persistent)...")

        self.reticule_mesh_component = uevrUtils.createStaticMeshComponent("StaticMesh /Engine/BasicShapes/Sphere.Sphere")

        if self.reticule_mesh_component then
            print("[DEBUG] Reticule Component Created Successfully")
            self.reticule_mesh_component:SetCollisionEnabled(0)
            self.reticule_mesh_component.BoundsScale = 10
            
            -- Set Scale 
            local rx = Config.redDotScaleX or Config.redDotSize or 0.007
            local ry = Config.redDotScaleY or Config.redDotSize or 0.007
            local rz = Config.redDotScaleZ or Config.redDotSize or 0.007
            local scale_vec = uevrUtils.vector(rx, ry, rz)
            self.reticule_mesh_component:SetWorldScale3D(scale_vec)

            -- Set Material (ONCE)
            -- Set Material (ONCE)
            -- Apply our robust UI material that accepts colors and bypasses physical render culling
            local wanted_mat = utils.find_required_object("Material /Engine/EngineMaterials/Widget3DPassThrough.Widget3DPassThrough")
            
            -- If somehow the widget material is missing, fallback to generic checkerboard so we don't crash
            if not wanted_mat then
                local default_mat_name = "Material /Engine/EngineMaterials/DefaultMaterial.DefaultMaterial"
                wanted_mat = utils.find_required_object(default_mat_name)
            end

            if wanted_mat then
                print("[DEBUG] Applying Base Material: " .. wanted_mat:get_fname():to_string())
                
                -- Only force blend mode if using the generic engine material
                if wanted_mat:get_fname():to_string() == "DefaultMaterial" then
                    wanted_mat.BlendMode = 0 
                end
                
                
                self.reticule_material = self.reticule_mesh_component:CreateDynamicMaterialInstance(0, wanted_mat, uevrUtils.fname_from_string("ReticuleDMI"))
                if self.reticule_material then
                    -- Apply a massive Emissive magnitude to overwrite any physical textures (like dirt) if we fell back
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
            self.reticule_material:SetVectorParameterValue("TintColorAndOpacity", color)  -- specifically for Widget3DPassThrough
                    
                    print("[DEBUG] DMI Created and Colored RED (".. wanted_mat:get_fname():to_string() ..")")
                else
                    print("[DEBUG] ERROR: Failed to create DMI for Reticule")
                end
            else
                print("[DEBUG] ERROR: Failed to find base material")
            end
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
            print("[DEBUG] Attached Reticule to: " .. parent_mesh:get_fname():to_string())
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
        
        local name = mesh:get_fname():to_string():lower()
        if name:find("deadeye_scope") or name:find("goloscope") or name:find("colimscope") or name:find("margach_scope") then  
             
             local min_index = 1
             if name:find("goloscope") then min_index = 2 
             elseif name:find("colimscope_mini") then min_index = 1
             elseif name:find("colimscope") then min_index = 2
             elseif name:find("deadeye_scope") then min_index = 1
             elseif name:find("margach_scope") then min_index = 2 end
             
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
             
            -- Flag as reflex sight for red dot logic
             self.is_reflex_sight = true
             self.scope_mesh = mesh
             print("[DEBUG] Reflex Sight Detected: " .. name)
             return true
        end
        return false
    end
    
    self.is_reflex_sight = false -- Reset before scan
    
    -- 1. Check Main Scope Mesh (via GameState cache)
    local main_scope = GameState:get_scope_mesh(weapon_mesh)
    if main_scope then
        if process_mesh(main_scope) then found_any = true end
    end
    
    if weapon_mesh.AttachChildren then
         local children = weapon_mesh.AttachChildren
         -- print("[DEBUG] Deep Scan: Main Weapon " .. weapon_mesh:get_fname():to_string() .. " has " .. #children .. " children")
         for i = 1, #children do
             local child = children[i]
             -- Just check existence, don't enforce StaticMesh property presence
             if child and UEVR_UObjectHook.exists(child) then
                 local cName = child:get_fname():to_string()
                 -- print("[DEBUG] Inspecting Child: " .. cName)
                 if process_mesh(child) then 
                     print("[DEBUG] FOUND FIX TARGET: " .. cName)
                     found_any = true 
                 end
             end
             
             -- Check for nested attachments
             if child and child.AttachChildren then
                 local grand_children = child.AttachChildren
                 for j = 1, #grand_children do
                     local grand_child = grand_children[j]
                     if grand_child and UEVR_UObjectHook.exists(grand_child) then
                         local gcName = grand_child:get_fname():to_string()
                         -- print("[DEBUG] Inspecting GrandChild: " .. gcName)
                         if process_mesh(grand_child) then 
                             print("[DEBUG] FOUND FIX TARGET (Nested): " .. gcName)
                             found_any = true 
                         end
                     end
                 end
             end
         end
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
         -- Use weapon_mesh passed from Update() to avoid a redundant GetEquippedWeapon() call
         if weapon_mesh then
             self:attach_components_to_weapon(weapon_mesh) 
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
    local c_pawn = api:get_local_pawn(0)
    local weapon_mesh = GameState:GetEquippedWeapon()
    if weapon_mesh then
        -- fix_materials(weapon_mesh)
        local weapon_changed = not self.current_weapon or weapon_mesh.AnimScriptInstance ~= self.current_weapon.AnimScriptInstance
        -- Check for a live scope swap (user detached one and attached another)
        local current_true_scope = GameState:get_scope_mesh(weapon_mesh)
        local was_scope_swapped = false
        if current_true_scope then
            local scope_addr = current_true_scope:get_address()
            if self.tracked_main_mesh_addr ~= scope_addr then
                print(string.format("[Scope] Scope swap detected: %s -> %s", tostring(self.tracked_main_mesh_addr), tostring(scope_addr)))
                was_scope_swapped = true
                self.tracked_main_mesh_addr = scope_addr
                self:destroy_reticule_actor()
            end
        elseif self.tracked_main_mesh_addr ~= nil then
            print("[Scope] Scope removed")
            was_scope_swapped = true
            self.tracked_main_mesh_addr = nil
            self:destroy_reticule_actor()
        end

        local scope_changed = was_scope_swapped and GameState:is_scope_active(c_pawn)
        if weapon_changed or scope_changed then
            print(string.format("[Scope] Refresh triggered: weapon_changed=%s, scope_changed=%s", tostring(weapon_changed), tostring(scope_changed)))
            print("Previous weapon: " .. (self.current_weapon and self.current_weapon:get_fname():to_string() or "none"))
            print("New weapon: " .. weapon_mesh:get_fname():to_string())

            -- Update current weapon reference
            self.current_weapon = weapon_mesh

            -- Attempt to attach components
            self:spawn_scope(engine, c_pawn)
            self:attach_components_to_weapon(weapon_mesh)
            
            -- Reset retry timer to force material updates for a few frames
            self.material_fix_retry_timer = 60 
        end
        
        -- Red Dot Sight (Reflex) logic with deep diagnostics
        if self.scopeInternalTick % 60 == 0 then
            print(string.format("[DEBUG] REFLEX STATUS: is_reflex=%s | scope_mesh=%s | reticule=%s",
                tostring(self.is_reflex_sight), 
                tostring(self.scope_mesh ~= nil),
                tostring(self.reticule_mesh_component ~= nil)))
        end

        if self.is_reflex_sight and self.scope_mesh then
            self:get_or_create_reticule_component(weapon_mesh)
            
            if self.reticule_mesh_component then
                -- Dirty-check: only call C++ bridge when visibility state changes
                if self.reticule_visible ~= true then
                    self.reticule_mesh_component:SetVisibility(true)
                    self.reticule_mesh_component:SetHiddenInGame(false)
                    self.reticule_visible = true
                end
                
                -- Status verification (Parallax Info)
                if self.scopeInternalTick % 120 == 0 then
                    local loc = self.reticule_mesh_component:K2_GetComponentLocation()
                    local parent = self.reticule_mesh_component:GetAttachParent()
                    local hmd_pos = controllers.getControllerLocation(2)
                    local dist = hmd_pos and uevrUtils.distanceBetween(loc, hmd_pos) or -1
                    
                    print(string.format("[DEBUG] Red Dot: Loc=%.1f,%.1f,%.1f | DistToHMD=%.1f | Parent=%s", 
                        loc.X, loc.Y, loc.Z, dist, parent and parent:get_fname():to_string() or "NONE"))
                end
            end
        else
            -- Hide if not a reflex sight
            if self.reticule_mesh_component then
                if self.reticule_visible ~= false then
                    self.reticule_mesh_component:SetVisibility(false)
                    self.reticule_visible = false
                end
            end
        end
        -- Continuous Material Fix Retry (Fixes glitch on first equip OR after settings change)
        if self.material_fix_retry_timer and self.material_fix_retry_timer > 0 then
             self.material_fix_retry_timer = self.material_fix_retry_timer - 1
             if self.material_fix_retry_timer % 10 == 0 then -- Check every 10 frames
                 -- Re-run the material patching logic
                 if self.current_weapon then
                      local all_scope_meshes = GameState:get_all_scope_meshes(self.current_weapon)
                      if all_scope_meshes then
                          for _, mesh in ipairs(all_scope_meshes) do
                              local name = mesh:get_fname():to_string():lower()
                              if name:find("holo") or name:find("deadeye_scope") or name:find("colimator") or name:find("goloscope") then
                                   pcall(function()
                                        -- Force update material params to combat DLSS artifacts
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
            print("Weapon unequipped - Cleaning up Reticule")
            self.current_weapon = nil
            self.scope_mesh = nil
            self.tracked_main_mesh_addr = nil -- Flush address tracking
            self:destroy_reticule_actor()    -- Kill the ball immediately
        end
    end
    -- Pass the already-fetched weapon_mesh down to avoid a second GetEquippedWeapon() call
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
             print("ERROR: ScopeController crashed: " .. tostring(err))
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
    print("Resetting")
    scope_controller:Reset()
    scope_controller:ResetStatic()
end)


return scope_controller
