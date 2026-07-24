require("common.assetloader")
require("Config.CONFIG")
local utils = require("common.utils")
local GameState = require("stalker2.gamestate")
local controllers = require("libs/controllers")  -- cached at module level (was inside hot function)
local uevrUtils = require("libs/uevr_utils")
local api = uevr.api

-- Record the moment this script was loaded (or reloaded after inject).
-- Used to detect the post-injection settling window: SceneCaptureComponent2D
-- creation triggers D3D12 PSO recompilation that races with UEVR's
-- FFakeStereoRenderingHook when the renderer is still being patched.
-- Within the first 10 seconds of EITHER script lifetime OR the last level change
-- we use a much longer defer (300 frames) to outlast the renderer settle window.
local scriptLoadTime      = os.clock()
local lastLevelChangeTime = os.clock()  -- Reset on every level change; see level-change handler below

-- Widget3DPassThrough BlendMode guard: only mutate the shared engine material asset ONCE per
-- session. Repeated writes on the game thread while the render thread reads the asset cause
-- EXCEPTION_ACCESS_VIOLATION crashes (PSO state torn mid-render).
local widget3d_blendmode_set = false

local function diag(_) end  -- diagnostic logging removed

-- Warmup sphere state.
-- A tiny StaticMeshComponent (Sphere) is spawned immediately when the pawn becomes
-- ready after every level load. It exercises FScene::AddPrimitive on the render
-- thread, which populates the null FD3D12PipelineState* left in UEVR's FRenderTarget
-- double-hook chain. Without this warmup, creating our own SceneCaptureComponent2D
-- (or even the cylinder) as the FIRST new scene primitive after a level load causes
-- an access violation at 0x000000000000000c.
-- This is exactly what equipping a reflex sight weapon first was doing accidentally:
-- its reticule sphere went through FScene::AddPrimitive and cleared the null pointer.
local warmupSphereActor  = nil  -- Actor hosting the warmup sphere component
local warmupSphereDone   = true -- true = warmup completed (safe to proceed); false = in progress
                                -- Starts true so mid-session script reloads don't block unnecessarily
local warmupSphereTick   = 0   -- plain Lua counter (cannot set fields on UObject proxies)

-- Eager warmup SCC + RT created on pawn-ready to initialise the UEVR hook chain.
-- Stored SEPARATELY from scope_controller.scene_capture_component so the deferred
-- creation block always creates the REAL scope SCC (bCaptureEveryFrame=1,
-- Config.scopeTextureSize RT). These are hook-keepers only — never the active scope SCC.
local warmupSCC = nil
local warmupRT  = nil

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
    pip_reticule_component = nil,   -- Red dot sphere child of the PiP cylinder
    pip_reticule_material = nil,    -- DMI on the red dot sphere
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
    instance.pipDeferFrames = 0  -- countdown before SceneCaptureComponent2D is created
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
        -- Use uevrUtils.createRenderTarget2D - this goes through uevr.api's safe path and does NOT
        -- trigger D3D12 pipeline state recompilations that raced with UEVR's FFakeStereoRenderingHook.
        -- The old Kismet:CreateRenderTarget2D(world, ...) path caused "Failed to create PipelineState"
        -- x60+ errors and a null pointer crash in UEVR's stereo hook on first inject.
        self.render_target = uevrUtils.createRenderTarget2D({
            width  = Config.scopeTextureSize,
            height = Config.scopeTextureSize,
            format = 6, -- ETextureRenderTargetFormat.RTF_RGBA16f
        })
    end
    return self.render_target
end

function ScopeController:spawn_scope_plane(world, owner, pos, rt)
    -- Force load the Cylinder asset if it's not already in memory
    pcall(function() uevrUtils.getLoadedAsset("StaticMesh /Engine/BasicShapes/Cylinder.Cylinder") end)

    self.scope_plane_component = uevrUtils.createStaticMeshComponent("StaticMesh /Engine/BasicShapes/Cylinder.Cylinder", {visible=false, collisionEnabled=false})
    if self.scope_plane_component == nil then
        print("[Scope] Failed to spawn scope plane component")
        return
    end
    -- TranslucencySortPriority=100: renders our cylinder after the scope glass lens (priority=0)
    -- in the translucent pass. Used together with the deferred glass-hide DMI.
    self.scope_plane_component.TranslucencySortPriority = 100

    local wanted_mat = utils.find_required_object("Material /Engine/EngineMaterials/EmissiveMeshMaterial.EmissiveMeshMaterial")
    if wanted_mat then
        -- Set BlendMode and TwoSided on the shared asset BEFORE creating the DMI.
        -- The DMI inherits these properties at creation time. Without this the
        -- BlendMode is non-deterministic: hide_scope_glass() sets it to 2 (Translucent)
        -- and reset_material_to_standard() sets it to 7 — whichever ran last wins.
        -- Matches Mutar original which always sets these before CreateDynamicMaterialInstance.
        wanted_mat.BlendMode = 7
        wanted_mat.TwoSided = 0
        self.scope_material = self.scope_plane_component:CreateDynamicMaterialInstance(0, wanted_mat, "scope_material")
        if self.scope_material then
            pcall(function() self.scope_material:SetTextureParameterValue("LinearColor", rt) end)
            local color = StructObject.new(self.flinearColor_c)
            local initIntensity = Config.scopeBrightnessAmplifier or 1.0
            color.R = initIntensity
            color.G = initIntensity
            color.B = initIntensity
            color.A = 1.0
            pcall(function() self.scope_material:SetVectorParameterValue("Color", color) end)
        end
    end
end

-- Spawn a red dot sphere and attach it to the current scope mesh.
-- Position and scale are updated every frame from Config sliders.
function ScopeController:spawn_pip_reticule()
    if not utils.validate_object(self.scope_mesh) then
        print("[PipReticule] Scope mesh not ready")
        return
    end

    local ok, err = pcall(function()
        -- 1. Create sphere SMC (identical to reflex sight)
        local comp = uevrUtils.createStaticMeshComponent(
            "StaticMesh /Engine/EngineMeshes/Sphere.Sphere")
        if not comp then
            print("[PipReticule] SMC creation failed")
            return
        end
        comp:SetCollisionEnabled(0)
        comp.BoundsScale = 10

        -- 2. Material with Additive blend (identical to reflex sight)
        local mat = utils.find_required_object(
            "Material /Engine/EngineMaterials/Widget3DPassThrough.Widget3DPassThrough")
        if mat then
            if not widget3d_blendmode_set then
                mat.BlendMode = 1           -- Additive (write once — render-thread safe)
                widget3d_blendmode_set = true
            end
            local dmi = comp:CreateDynamicMaterialInstance(
                0, mat, uevrUtils.fname_from_string("PipDotDMI"))
            if dmi then
                local color = StructObject.new(self.flinearColor_c)
                local b  = Config.pipDotBrightness or 150.0
                local cr = (Config.pipDotColorR or 1.0) * b
                local cg = (Config.pipDotColorG or 0.0) * b
                local cb = (Config.pipDotColorB or 0.0) * b
                color.R = cr; color.G = cg; color.B = cb; color.A = 1.0
                dmi:SetVectorParameterValue("EmissiveColor",       color)
                dmi:SetVectorParameterValue("Color",               color)
                dmi:SetVectorParameterValue("BaseColor",           color)
                dmi:SetVectorParameterValue("Tint",                color)
                dmi:SetVectorParameterValue("TintColorAndOpacity", color)
                self.pip_reticule_material = dmi
            end
        end

        -- 3. Initial scale
        local sx = Config.pipDotScaleX or 0.000010
        local sy = Config.pipDotScaleY or 0.0002
        local sz = Config.pipDotScaleZ or 0.0002
        comp:SetWorldScale3D(uevrUtils.vector(sx, sy, sz))

        -- 4. Attach to scope mesh (same as reflex sight)
        comp:K2_AttachToComponent(
            self.scope_mesh,
            uevrUtils.fname_from_string(""),
            2, 2, 1, true)

        -- 5. Initial offset
        local ox = Config.pipDotOffsetX or -13.0
        local oy = Config.pipDotOffsetY or 0.8
        local oz = Config.pipDotOffsetZ or 8.3
        comp:K2_SetRelativeLocation(
            uevrUtils.vector(ox, oy, oz), false, self.reusable_hit_result, false)

        comp:SetVisibility(false)
        comp:SetHiddenInGame(true)
        self.pip_reticule_component = comp
        print("[PipReticule] Spawned and attached to scope mesh")
    end)
    if not ok then
        print("[PipReticule] Spawn error: " .. tostring(err))
    end
end

-- Destroy the PiP reticule sphere SMC cleanly.
function ScopeController:destroy_pip_reticule()
    if self.pip_reticule_component and uevrUtils.validate_object(self.pip_reticule_component) then
        pcall(function()
            self.pip_reticule_component:K2_DestroyComponent(self.pip_reticule_component)
        end)
    end
    self.pip_reticule_component = nil
    self.pip_reticule_material = nil
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
                -- BlendMode is set at most once per session (shared asset — render-thread safety)
                if not widget3d_blendmode_set then
                    wanted_mat.BlendMode = 1
                    widget3d_blendmode_set = true
                end
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
    
    -- Get scope world location from the NATIVE scope mesh.
    -- Indiana-style: query the real game mesh (always has correct world coords),
    -- NOT the dynamically spawned cylinder which returns relative-space coords.
    local scope_location = nil
    if self.scope_mesh and UEVR_UObjectHook.exists(self.scope_mesh) then
        scope_location = self.scope_mesh:K2_GetComponentLocation()
    elseif self.current_weapon and UEVR_UObjectHook.exists(self.current_weapon) then
        scope_location = self.current_weapon:K2_GetComponentLocation()
    end
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
    diag("[Scope-Diag] spawn_scene_capture_component: ENTER")
    -- Use uevrUtils.createSceneCaptureComponent - stable uevr.api path, no D3D12 crash.
    -- Old code used scope_actor:AddComponentByClass which triggered pipeline recompilations.
    local comp = uevrUtils.createSceneCaptureComponent({visible=false, collisionEnabled=false})
    diag("[Scope-Diag] after createSceneCaptureComponent -> " .. tostring(comp ~= nil))
    if comp == nil then
        print("[Scope] Failed to spawn scene capture component")
        return
    end
    diag("[Scope-Diag] before TextureTarget = rt")
    comp.TextureTarget = rt
    diag("[Scope-Diag] after TextureTarget = rt")
    comp.FOVAngle = fov
    comp.bCacheVolumetricCloudsShadowMaps = true
    comp.bUseRayTracingIfEnabled = false
    comp.bAlwaysPersistRenderingState = true
    comp.bEnableVolumetricCloudsCapture = false
    comp.bCaptureEveryFrame = 1
    comp.CaptureSource = 1  -- SCS_SceneColorHDRInSceneCapture: capture after TAA/TSR runs

    -- post processing
    comp.PostProcessSettings.bOverride_MotionBlurAmount = true
    comp.PostProcessSettings.MotionBlurAmount = 0.0
    comp.PostProcessSettings.bOverride_ScreenSpaceReflectionIntensity = true
    comp.PostProcessSettings.ScreenSpaceReflectionIntensity = 0.0
    comp.PostProcessSettings.bOverride_AmbientOcclusionIntensity = true
    comp.PostProcessSettings.AmbientOcclusionIntensity = 0.0
    comp.PostProcessSettings.bOverride_BloomIntensity = true
    comp.PostProcessSettings.BloomIntensity = 0.0
    comp.PostProcessSettings.bOverride_LensFlareIntensity = true
    comp.PostProcessSettings.LensFlareIntensity = 0.0
    comp.PostProcessSettings.bOverride_VignetteIntensity = true
    comp.PostProcessSettings.VignetteIntensity = 0.0

    -- Disable Lumen GI and Lumen Reflections in the secondary (PIP) render pass.
    -- PostProcessSettings overrides are standard UPROPERTYs reachable via UEVR's
    -- reflection — same mechanism as BloomIntensity / MotionBlurAmount above.
    -- ShowFlags bitfields (comp.ShowFlags.X) are NOT accessible this way (C++ bit
    -- fields, not UPROPERTY members) — those pcalls silently fail.
    -- DynamicGlobalIlluminationMethod: 0=None, 1=SSGI, 2=Plugin, 3=Lumen
    -- ReflectionMethod:                0=None, 1=SSR,  2=Lumen
    comp.PostProcessSettings.bOverride_DynamicGlobalIlluminationMethod = true
    comp.PostProcessSettings.DynamicGlobalIlluminationMethod = 0  -- None: disables Lumen GI
    comp.PostProcessSettings.bOverride_ReflectionMethod = true
    comp.PostProcessSettings.ReflectionMethod = 0                 -- None: disables Lumen reflections

    pcall(function() comp:SetAbsolute(false, false, false) end)
    pcall(function() comp.bUsePawnControlRotation = false end)

    comp:SetVisibility(false)
    diag("[Scope-Diag] spawn_scene_capture_component: EXIT")
    self.scene_capture_component = comp
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
        return
    end

    -- Guard: only create PIP components if a scope is actually mounted on the weapon.
    -- Without this, the cylinder and SceneCaptureComponent2D spawn for every weapon
    -- equip (including scopeless pistols/shotguns) because spawn_scope() fires on every
    -- weapon_changed event with no scope-presence check.
    -- Check weapon_mesh first, then WeaponInHandsMesh (where scope attachments actually live).
    local weapon_mesh_for_check = GameState:GetEquippedWeapon()
    local scope_present = false
    if weapon_mesh_for_check then
        scope_present = (GameState:get_scope_mesh(weapon_mesh_for_check) ~= nil)
        if not scope_present then
            local hands = GameState:GetWeaponInHandsMesh()
            if hands then
                scope_present = (GameState:get_scope_mesh(hands) ~= nil)
            end
        end
    end
    if not scope_present then
        -- No scope attached — ensure defer ticker stays dormant.
        self.pipDeferFrames = 0
        return
    end

    -- PiP scopes entirely disabled: tear down any existing components and bail out.
    -- Checked here (after scope_present) so we don't Reset on every scopeless weapon equip.
    if Config.pipScopesEnabled == false then
        self:Reset()
        return
    end

    local pawn_pos = pawn:K2_GetActorLocation()

    -- Defer ALL GPU work (render target, cylinder, SceneCaptureComponent2D) to the
    -- per-frame ticker in Update(). All three register GPU resources with D3D12 and
    -- can trigger PSO recompilation that races with UEVR's FFakeStereoRenderingHook
    -- during the renderer-settle window after injection OR after a level change.
    -- Crash signature: 0x000000000000000c (null FD3D12PipelineState dereference).
    -- Nothing GPU-related may be created synchronously on the weapon-equip frame.
    local anyMissing = not utils.validate_object(self.render_target)
                    or not utils.validate_object(self.scene_capture_component)
                    or not utils.validate_object(self.scope_plane_component)
    if anyMissing then
        if self.pipDeferFrames == 0 then
            -- Use whichever settle reference is more recent: initial script injection
            -- or the last level change.  lastLevelChangeTime is reset by the level-change
            -- handler each time IsLevelChanged() fires, so the first PIP scope equip
            -- after ANY level load always uses the long 300-frame defer (~3.3s at 90fps)
            -- regardless of how long the scripts have been running overall.
            local now = os.clock()
            local timeSinceSettle = math.min(now - scriptLoadTime, now - lastLevelChangeTime)
            local deferFrames = timeSinceSettle < 10.0 and 300 or 30
            self.pipDeferFrames = deferFrames
            print(string.format("[Scope] GPU creation deferred -- ticker armed (%d frames, %.1fs since settle)", deferFrames, timeSinceSettle))
        end
        -- Skip ALL GPU work here; both cylinder and SceneCaptureComponent2D
        -- are created in the per-frame ticker in Update() when the countdown fires.
        return
    else
        -- Both components already exist: reset defer counter.
        self.pipDeferFrames = 0
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

-- Hide the scope glass lens by replacing its material slot with an invisible DMI.
-- Must be called AFTER the SCC is fully initialised (i.e. after the deferred fire fires,
-- or on weapon-swap when the SCC already exists). Safe to call multiple times — skips
-- slots that already carry our ScopeGlassHideDMI.
function ScopeController:hide_scope_glass(weapon_mesh)
    local emissive_mat = utils.find_required_object(emissive_mesh_material_name)
    if not emissive_mat then
        print("[Scope] hide_scope_glass: emissive_mat not found")
        return
    end
    emissive_mat.BlendMode = 2
    emissive_mat.TwoSided = 0
    emissive_mat.MaterialDomain = 0
    local glass_meshes = GameState:get_all_scope_meshes(weapon_mesh)
    if not glass_meshes then return end
    for _, smesh in ipairs(glass_meshes) do
        local snm = smesh:GetNumMaterials()
        for ss = 0, snm - 1 do
            local sm = smesh:GetMaterial(ss)
            if sm then
                -- Skip slots already carrying our hide DMI
                local already = sm:get_fname():to_string():find("ScopeGlassHideDMI")
                if not already then
                    local par_ok, par = pcall(function() return sm.Parent end)
                    local par_name = (par_ok and par and uevrUtils.validate_object(par)) and par:get_fname():to_string() or ""
                    if par_name:lower():find("glass") then
                        local dmi_name = uevrUtils.fname_from_string("ScopeGlassHideDMI")
                        local ok_dmi, dmi = pcall(function()
                            return smesh:CreateDynamicMaterialInstance(ss, emissive_mat, dmi_name)
                        end)
                        if ok_dmi and dmi then
                            local zero_color = StructObject.new(self.flinearColor_c)
                            zero_color.R = 0.0; zero_color.G = 0.0; zero_color.B = 0.0; zero_color.A = 0.0
                            pcall(function() dmi:SetVectorParameterValue("Color", zero_color) end)
                            print("[Scope] Glass lens hidden (slot " .. ss .. ")")
                        else
                            print("[Scope] WARNING: glass DMI creation failed on slot " .. ss)
                        end
                    end
                end
            end
        end
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
             
             -- Apply the transparency fix and shadow suppression only when enabled.
             -- is_reflex_sight is still set (see below) so PIP scope never activates on reflex sights.
             local mesh_addr = mesh:get_address()
             if Config.reflexEnabled ~= false then
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
             else
                 -- Material fix disabled: reset addr so fix re-runs when re-enabled
                 self.transparency_fix_applied_addr = nil
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

    -- Find scope mesh first -- both components attach to it (Indiana-style)
    self.scope_mesh = GameState:get_scope_mesh(weapon_mesh)
    if not self.scope_mesh then
        local hands_mesh = GameState:GetWeaponInHandsMesh()
        if hands_mesh then
            self.scope_mesh = GameState:get_scope_mesh(hands_mesh)
        end
    end

    local parent_mesh = self.scope_mesh
    if parent_mesh == nil then
        print("[Scope] WARNING: Scope Mesh not found! Falling back to Weapon Mesh")
        parent_mesh = weapon_mesh
    end

    -- Set material parameters and hide glass-named components for PIP scopes.
    -- We cannot use CreateDynamicMaterialInstance on PIP scope glass slots (crashes the
    -- game's PIP render pipeline). Instead, hide components whose name contains "glass"
    -- or "lens" — these are dedicated glass components, separate from the scope body mesh.
    -- Set material parameters on all scope meshes.
    -- Glass DMI creation is intentionally deferred to the pipDeferFrames fire (~30 frames
    -- after weapon equip) to avoid racing with the game's own PIP SCC initialization.
    local all_scope_meshes = GameState:get_all_scope_meshes(weapon_mesh)
    if all_scope_meshes then
        for _, mesh in ipairs(all_scope_meshes) do
            mesh:SetScalarParameterValueOnMaterials("SightMaskScale", 0.0)
            mesh:SetScalarParameterValueOnMaterials("Deactivate_RT", 0.0)
        end
    end



    -- Attach SceneCapture to weapon Muzzle socket (objective/front lens end, naturally forward-facing)
    -- Guard: only attach the SCC when the cylinder (scope_plane_component) is ALSO ready.
    -- If we attach the SCC before the cylinder exists (e.g. when called from the weapon-change
    -- handler before the deferred fire), K2_AttachToComponent queues a render command that
    -- modifies the FPrimitiveSceneProxy while UEVR's hook chain is in an unsafe state →
    -- crash at 0x0C on the render thread ~30 frames later.
    -- The deferred fire always calls attach_components_to_weapon AFTER creating both
    -- scope_plane_component AND scene_capture_component, so the attach is safe there.
    local plane_ready = utils.validate_object(self.scope_plane_component)
    if self.scene_capture_component ~= nil and plane_ready then
        local wm_ok = UEVR_UObjectHook.exists(weapon_mesh)
        local wm_registered = wm_ok and pcall(function()
            local reg = weapon_mesh.bRegistered
            return reg
        end)
        if wm_ok and wm_registered then
            local socketName = "Muzzle"
            if not weapon_mesh:DoesSocketExist(socketName) then
                socketName = nil
            end
            pcall(function()
                self.scene_capture_component:K2_AttachToComponent(
                    weapon_mesh,
                    socketName,
                    2,    -- SnapToTarget (position at socket)
                    2,    -- SnapToTarget (rotation from socket)
                    0,    -- KeepRelative scale
                    false -- no weld
                )
            end)
            self.scene_capture_component:K2_SetRelativeRotation(self.temp_vec3:set(0, 0, 90), false, self.reusable_hit_result, false)
            self.scene_capture_component:K2_SetRelativeLocation(self.temp_vec3:set(0, 0, 0), false, self.reusable_hit_result, false)
            self.scene_capture_component:SetVisibility(false)
            print("[Scope] SceneCapture attached to Muzzle socket (objective lens end)")
        else
            print("[Scope] WARNING: weapon_mesh not registered -- skipping SceneCapture attach (will retry next heartbeat)")
        end
    elseif self.scene_capture_component ~= nil and not plane_ready then
        -- Cylinder not ready yet (called from weapon-change handler before deferred fire).
        -- Skip the attach now; the deferred fire will call attach_components_to_weapon
        -- again once the cylinder exists and both will be attached together safely.
        diag("[Scope-Diag] attach: SCC exists but cylinder not ready -- deferring SCC attach to deferred fire")
    end

    -- Attach ocular lens cylinder to scope mesh (Indiana-style: KeepRelative, no socket, no weld)
    -- Guard: verify parent_mesh is still registered before attaching.
    if self.scope_plane_component then
        local pm_ok = UEVR_UObjectHook.exists(parent_mesh)
        local pm_registered = pm_ok and pcall(function()
            local reg = parent_mesh.bRegistered
            return reg
        end)
        if pm_ok and pm_registered then
            pcall(function()
                self.scope_plane_component:K2_AttachToComponent(
                    parent_mesh,
                    "OpticCutoutSocket",  -- attach to the scope's optic cutout socket
                    0,   -- KeepRelative
                    0,   -- KeepRelative
                    0,   -- KeepRelative
                    false -- no weld
                )
            end)
            local ocl_loc = Config.ocularLensLocation or {Config.cylinderDepth, Config.cylinderOffsetY or 0.0, Config.cylinderOffsetZ or 0.0}
            pcall(function() self.scope_plane_component:SetAbsolute(false, false, false) end)
            pcall(function() self.scope_plane_component.bUsePawnControlRotation = false end)
            self.scope_plane_component:K2_SetRelativeRotation(self.temp_vec3:set(0, 90, 90), false, self.reusable_hit_result, false)
            self.scope_plane_component:K2_SetRelativeLocation(self.temp_vec3:set(ocl_loc[1], ocl_loc[2], ocl_loc[3]), false, self.reusable_hit_result, false)
            local tubeDepth = Config.cylinderTubeDepth or 0.001
            uevrUtils.set_component_relative_scale(self.scope_plane_component, {Config.scopeDiameter, Config.scopeDiameter, tubeDepth})
            self.scope_plane_component:SetVisibility(false)
            print("[Scope] Ocular lens cylinder attached to scope mesh (KeepRelative)")
        else
            print("[Scope] WARNING: parent_mesh not registered -- skipping cylinder attach (will retry next heartbeat)")
        end
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
         end -- if weapon_mesh
    end -- heartbeat

    -- Distance-based activation: Scope only renders when close to HMD
    -- ALSO require the game's own PlayerOpticScopeComponent flag so that ADS
    -- (which brings the weapon close to the HMD) does not accidentally trigger
    -- the PIP cylinder — ADS does NOT set is_scope_active, looking through
    -- the optic lens does.
    local current_scope_state = self:IsWithinActivationDistance()
                             and GameState:is_scope_active(pawn)
    
    if current_scope_state then
        -- Throttle FOV update to every 3 ticks: FOV only changes during ADS transitions (slow)
        if self.scopeInternalTick % 3 == 0 then
            self:Recalculate_FOV(pawn)
        end
    end
    -- SCC LIFECYCLE: destroy the SceneCaptureComponent2D after sustained inactivity so
    -- it cannot issue GPU draw calls while UEVR's stereo hook is mid-frame during ADS.
    -- SetVisibility/CaptureEveryFrame are insufficient — the SCC still holds GPU
    -- resources that UEVR's render-thread hook can race against.
    --
    -- Destroy threshold : 30 frames (~330 ms at 90 fps) of continuous inactivity.
    --   → Absorbs brief look-aways without destroying/recreating.
    --   → ADS press → weapon raises → scope leaves HMD distance → 30 frames elapses
    --     → SCC destroyed cleanly before any render conflict can occur.
    --
    -- Re-create threshold: 5 frames of continuous confirmed-active state.
    --   → Arms pipDeferFrames=5 → existing deferred-spawn block recreates the SCC.
    --   → scope_plane_component and render_target are still alive; only SCC is missing.
    if current_scope_state then
        self.scc_inactive_frames = 0
        if not utils.validate_object(self.scene_capture_component) then
            -- SCC is gone — count confirmed-active frames before re-arming the spawn
            self.scc_active_confirm = (self.scc_active_confirm or 0) + 1
            if self.scc_active_confirm >= 5 and self.pipDeferFrames == 0 then
                self.scc_active_confirm = 0
                self.pipDeferFrames = 5   -- deferred-spawn block will recreate SCC
                -- print("[Scope] SCC recreate armed (5-frame defer) after scope reactivation")
            end
        else
            self.scc_active_confirm = 0
            -- SCC exists and scope is active: ensure it is capturing
            if self.scc_capture_state ~= true then
                self.scc_capture_state = true
                pcall(function()
                    self.scene_capture_component.CaptureEveryFrame = true
                    self.scene_capture_component.CaptureOnMovement  = true
                end)
            end
        end
    else
        self.scc_active_confirm = 0
        self.scc_inactive_frames = (self.scc_inactive_frames or 0) + 1

        if self.scene_capture_component ~= nil
           and UEVR_UObjectHook.exists(self.scene_capture_component) then
            -- Immediately stop GPU captures on the first inactive frame
            if self.scc_capture_state ~= false then
                self.scc_capture_state = false
                pcall(function()
                    self.scene_capture_component.CaptureEveryFrame = false
                    self.scene_capture_component.CaptureOnMovement  = false
                end)
            end
            -- After 30 continuous inactive frames: destroy the SCC entirely
            if self.scc_inactive_frames >= 30 then
                pcall(function()
                    self.scene_capture_component:K2_DestroyComponent(self.scene_capture_component)
                end)
                self.scene_capture_component = nil
                self.scc_capture_state = nil
                self.scc_inactive_frames = 0
                print("[Scope] SCC destroyed after 30 inactive frames (ADS/idle guard)")
            end
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
    -- PiP reticule dot: show/hide + update offset and scale every frame (identical pattern to reflex UpdateReticulePosition)
    if self.pip_reticule_component ~= nil and utils.validate_object(self.pip_reticule_component) then
        self.pip_reticule_component:SetVisibility(current_scope_state)
        self.pip_reticule_component:SetHiddenInGame(not current_scope_state)
        if current_scope_state then
            -- Resolve per-scope profile then global fallback (mirrors Entry.lua logic)
            -- Use the mesh ASSET name (not the component name) to match currentScopeName in the UI
            local sName = nil
            if self.scope_mesh then
                if self.scope_mesh.SkeletalMesh then
                    sName = uevrUtils.getShortName(self.scope_mesh.SkeletalMesh)
                elseif self.scope_mesh.StaticMesh then
                    sName = uevrUtils.getShortName(self.scope_mesh.StaticMesh)
                else
                    sName = uevrUtils.getShortName(self.scope_mesh)
                end
            end
            local sProf = (sName and Config.scopeProfiles and Config.scopeProfiles[sName]) or {}
            -- Offset (relative to attached scope mesh root)
            local ox = sProf.pipDotOffsetX or Config.pipDotOffsetX or -13.0
            local oy = sProf.pipDotOffsetY or Config.pipDotOffsetY or   0.8
            local oz = sProf.pipDotOffsetZ or Config.pipDotOffsetZ or   8.3
            self.pip_reticule_component:K2_SetRelativeLocation(
                uevrUtils.vector(ox, oy, oz), false, self.reusable_hit_result, false)
            -- Scale
            local sx = sProf.pipDotScaleX or Config.pipDotScaleX or 0.000010
            local sy = sProf.pipDotScaleY or Config.pipDotScaleY or 0.0002
            local sz = sProf.pipDotScaleZ or Config.pipDotScaleZ or 0.0002
            self.pip_reticule_component:SetWorldScale3D(uevrUtils.vector(sx, sy, sz))
        end
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
    if self.scene_capture_component == nil then return end

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
        -- Search weapon_mesh children first, then WeaponInHandsMesh (where x8scope etc. live).
        local current_true_scope = GameState:get_scope_mesh(weapon_mesh)
        if not current_true_scope then
            local hands_mesh = GameState:GetWeaponInHandsMesh()
            if hands_mesh then
                current_true_scope = GameState:get_scope_mesh(hands_mesh)
            end
        end
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
        if not current_true_scope and self.scope_mesh and UEVR_UObjectHook.exists(self.scope_mesh) then
            local deep_addr = self.scope_mesh:get_address()
            if self.tracked_main_mesh_addr ~= deep_addr then
                was_scope_swapped = true
                had_no_scope = true
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
            self.pipDeferFrames = 0  -- reset PSO defer countdown for new equip cycle
            self.glass_hide_applied = false  -- re-apply glass hide for new scope mesh
            self.scc_capture_state = nil    -- re-arm CaptureEveryFrame dirty-check for new scope

            -- Teardown stale PIP components when switching to a scopeless weapon.
            -- Without this, the cylinder and SceneCaptureComponent2D persist from the
            -- previous scoped weapon and silently re-attach to pistols/shotguns etc.
            local new_scope = GameState:get_scope_mesh(weapon_mesh)
            if not new_scope then
                local hands_check = GameState:GetWeaponInHandsMesh()
                if hands_check then new_scope = GameState:get_scope_mesh(hands_check) end
            end
            -- Always destroy the PiP reticule dot on any weapon/scope change.
            -- If we only destroy it in the scopeless branch, switching PIP→reflex leaves
            -- the old pip_reticule_component alive. On return to PIP scope,
            -- validate_object() returns true for the stale component and the deferred
            -- guard blocks re-spawning it, so the dot never reappears.
            self:destroy_pip_reticule()
            if not new_scope then
                -- No scope on new weapon — destroy lingering components now.
                if self.scene_capture_component and UEVR_UObjectHook.exists(self.scene_capture_component) then
                    pcall(function() self.scene_capture_component:K2_DestroyComponent(self.scene_capture_component) end)
                end
                self.scene_capture_component = nil
                if self.scope_plane_component and UEVR_UObjectHook.exists(self.scope_plane_component) then
                    pcall(function() self.scope_plane_component:K2_DestroyComponent(self.scope_plane_component) end)
                end
                self.scope_plane_component = nil
                self.scope_material = nil
                self.render_target = nil
                print("[Scope] Scopeless weapon equipped -- PIP components destroyed")
            end

            -- Attempt to attach components (spawn_scope will guard itself if no scope present)
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

        -- Per-frame deferred creation ticker.
        -- spawn_scope() is only called once (on weapon-change) and only arms the countdown.
        -- This block runs every frame and does the actual countdown + GPU primitive creation.
        -- Both the cylinder (scope_plane_component) and SceneCaptureComponent2D are created
        -- here so that neither registers an FPrimitiveSceneProxy during the D3D12 settle window.
        if self.pipDeferFrames and self.pipDeferFrames > 0 and Config.pipScopesEnabled ~= false then
            local bothReady = utils.validate_object(self.render_target)
                          and utils.validate_object(self.scene_capture_component)
                          and utils.validate_object(self.scope_plane_component)
            if bothReady then
                -- All GPU resources exist (created externally or by a previous pass).
                self.pipDeferFrames = 0
            else
                -- UEVR FRenderTarget HOOK-SAFE GATE
                -- On every level load UEVR re-creates its SceneCaptureComponent2D and
                -- re-hooks the FRenderTarget vtable. Due to a UEVR bug the vtable is
                -- always double-hooked at this point, leaving a stale null
                -- FD3D12PipelineState* in the hook chain. Any new StaticMeshComponent
                -- or SceneCaptureComponent2D created as the FIRST new scene primitive
                -- after a level load crashes at 0x000000000000000c.
                --
                -- Fix: a warmup sphere StaticMeshComponent is spawned the moment the
                -- pawn becomes ready after each level load (see pawn-ready block in the
                -- tick callback below). It goes through FScene::AddPrimitive, which
                -- populates the null pointer. After 2 ticks it is destroyed and
                -- warmupSphereDone is set true. We block the countdown until then.
                if not warmupSphereDone then
                    -- Warmup still in progress — keep countdown frozen.
                elseif GameState.inMenu then
                    -- World is frozen (loading/transition) — don't count down.
                else
                    self.pipDeferFrames = self.pipDeferFrames - 1
                end

                if self.pipDeferFrames <= 0 then
                    self.pipDeferFrames = 0
                    if not warmupSphereDone then
                        self.pipDeferFrames = 10  -- Re-arm; warmup should finish imminently
                    else
                        -- print("[Scope] PSO defer elapsed -- creating cylinder + SceneCaptureComponent2D now")
                        local viewport = engine.GameViewport
                        local world = viewport and viewport.World
                        if world and c_pawn then
                            local pawn_pos = c_pawn:K2_GetActorLocation()
                            local rt = self:get_render_target(world)
                            if rt then
                                if not utils.validate_object(self.scope_plane_component) then
                                    self:spawn_scope_plane(world, nil, pawn_pos, rt)
                                end
                                -- Spawn PiP reticule dot — only for PIP scopes, not reflex sights
                                if not utils.validate_object(self.pip_reticule_component) then
                                    local scopeName = self.scope_mesh and uevrUtils.getShortName(self.scope_mesh) or ""
                                    local isReflex = scopeName:find("colimscope") or scopeName:find("deadeye_scope")
                                                  or scopeName:find("goloscope")  or scopeName:find("margach_scope")
                                    if not isReflex then
                                        self:spawn_pip_reticule()
                                    end
                                end
                                if not utils.validate_object(self.scene_capture_component) then
                                    local fov = (c_pawn.Camera and c_pawn.Camera.FieldOfView) or 90.0
                                    self:spawn_scene_capture_component(world, nil, pawn_pos, fov, rt)
                                end
                                self:attach_components_to_weapon(weapon_mesh)
                                -- Apply glass hide now that SCC is fully initialised
                                self:hide_scope_glass(weapon_mesh)
                                self.glass_hide_applied = true

                            end
                        end
                    end
                end
            end
        end

        -- Glass hide: independent of the defer block so it fires on weapon-swap too.
        -- On weapon-swap, pipDeferFrames is already 0 and the SCC is still valid
        -- (was created for the previous scoped weapon). The weapon-changed block sets
        -- glass_hide_applied=false, so this check immediately re-applies the hide for
        -- the new scope mesh without waiting for another defer countdown.
        if not self.glass_hide_applied
           and not self.is_reflex_sight
           and not (self.pipDeferFrames and self.pipDeferFrames > 0)
           and utils.validate_object(self.scene_capture_component)
           and weapon_mesh
        then
            self:hide_scope_glass(weapon_mesh)
            self.glass_hide_applied = true
        end

        -- PiP reticule respawn: independent of the defer block, same pattern as
        -- glass_hide_applied above.  The deferred block only fires when GPU components
        -- are missing (anyMissing=true in spawn_scope).  On a PIP→PIP weapon swap the
        -- scope_plane_component is still valid so pipDeferFrames stays 0 and the
        -- deferred fire never executes — yet pip_reticule_component was just destroyed
        -- by destroy_pip_reticule() in the weapon-changed branch.
        -- This independent check catches that case (and PIP→no-scope→PIP) every frame.
        if not self.is_reflex_sight
           and Config.pipScopesEnabled ~= false
           and not (self.pipDeferFrames and self.pipDeferFrames > 0)
           and utils.validate_object(self.scope_mesh)
           and not utils.validate_object(self.pip_reticule_component)
        then
            local scopeName = uevrUtils.getShortName(self.scope_mesh) or ""
            local isReflex = scopeName:find("colimscope") or scopeName:find("deadeye_scope")
                          or scopeName:find("goloscope")  or scopeName:find("margach_scope")
            if not isReflex then
                self:spawn_pip_reticule()
            end
        end

        if self.is_reflex_sight and self.scope_mesh and Config.reflexEnabled ~= false then
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
            -- Reticule disabled mid-session: destroy existing sphere so it doesn't persist
            if self.reticule_mesh_component and Config.reflexEnabled == false then
                self:destroy_reticule_actor()
            end
            -- Hide if not a reflex sight
            if self.reticule_mesh_component then
                -- H4 perf: dirty-check — only call bridge when visibility state changes
                if self.reticule_visible ~= false then
                    self.reticule_visible = false
                    self.reticule_mesh_component:SetVisibility(false)
                end
            end
        end
        -- Continuous Material Fix Retry
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
    self:destroy_pip_reticule()
    self.scene_capture_component = nil
    self.render_target = nil
    self.pipDeferFrames = 0     -- Ensure a fresh defer is computed on the next equip cycle
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
    if self.scope_plane_component and uevrUtils.validate_object(self.scope_plane_component) then
        local y = Config.cylinderOffsetY or 0.0
        local z = Config.cylinderOffsetZ or 0.0
        self.scope_plane_component:K2_SetRelativeLocation(self.temp_vec3:set(Config.cylinderDepth, y, z), false, self.reusable_hit_result, false)
        local tubeDepth = Config.cylinderTubeDepth or 0.001
        uevrUtils.set_component_relative_scale(self.scope_plane_component, {Config.scopeDiameter, Config.scopeDiameter, tubeDepth})
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
                -- Mark that we are waiting for the pawn to become valid on the new level.
                -- lastLevelChangeTime will be updated a second time when the pawn is first
                -- seen after the load completes (see pawn-ready guard below).
                lastLevelChangeTime = os.clock()  -- Pessimistic early stamp (transition start)
                -- Reset warmup gate so a fresh warmup sphere is spawned when pawn appears
                warmupSphereDone  = false
                if warmupSphereActor and UEVR_UObjectHook.exists(warmupSphereActor) then
                    pcall(function() uevrUtils.destroy_actor(warmupSphereActor) end)
                end
                warmupSphereActor = nil
                scope_controller.pawnReadyAfterLoad = false
                scope_controller:Reset()
            end
            -- Pawn-ready guard: once the pawn becomes valid after a level change, stamp the
            -- REAL settle time. IsLevelChanged fires at transition START (PersistentLevel swap),
            -- but UEVR's FFakeStereoRenderingHook only becomes stable after the level fully
            -- loads and the pawn exists. Using the pawn-ready moment means the 10-second
            -- window (and the 300-frame defer) are measured from when the renderer is actually
            -- stable, not from when the loading screen appeared.
            -- pawnReadyAfterLoad is nil on first script load (before any level change).
            -- It is set to false by the IsLevelChanged handler. In both cases we want
            -- to spawn the warmup sphere as soon as the pawn is valid.
            if scope_controller.pawnReadyAfterLoad ~= true then
                local pawn = api:get_local_pawn(0)
                if pawn and UEVR_UObjectHook.exists(pawn) then
                    lastLevelChangeTime = os.clock()  -- Definitive stamp: level fully loaded
                    scope_controller.pawnReadyAfterLoad = true
                    scope_controller.pipDeferFrames = 0  -- Discard any countdown started before pawn was ready
                    print("[Scope] Pawn ready after level load -- settle window restarted")

                    -- Spawn warmup sphere to exercise the EmissiveMeshMaterial Translucent PSO
                    -- before the scope cylinder creates a DMI from it.
                    --
                    -- ROOT CAUSE: apply_transparency_fix() sets EmissiveMeshMaterial to
                    -- BlendMode=2 (Translucent) and calls CreateDynamicMaterialInstance on
                    -- it. This compiles the Translucent D3D12 PSO. Without a reflex sight
                    -- being equipped first, the cylinder's spawn_scope_plane() is the FIRST
                    -- Translucent DMI creation after a level load, and it crashes reading a
                    -- null FD3D12PipelineState* at offset 0xC.
                    -- FScene::AddPrimitive alone (from our previous invisible sphere) does
                    -- NOT compile PSOs -- only a VISIBLE mesh with the target material does.
                    warmupSphereDone = false
                    warmupSphereTick = 0
                    local ok, result = pcall(function()
                        local comp = uevrUtils.createStaticMeshComponent(
                            "StaticMesh /Engine/EngineMeshes/Sphere.Sphere",
                            {visible = true, collisionEnabled = false}  -- MUST be visible to compile PSO
                        )
                        if comp then
                            -- Apply EmissiveMeshMaterial in Translucent mode.
                            -- This compiles the exact D3D12 PSO that spawn_scope_plane()
                            -- needs when it calls CreateDynamicMaterialInstance later.
                            local emissiveMat = utils.find_required_object(emissive_mesh_material_name)
                            if emissiveMat then
                                emissiveMat.BlendMode = 2  -- Translucent (same as apply_transparency_fix)
                                emissiveMat.TwoSided = 0
                                comp:CreateDynamicMaterialInstance(0, emissiveMat, uevrUtils.fname_from_string("WarmupDMI"))
                            end
                            -- Scale to microscopic so it is invisible to the player
                            comp:SetWorldScale3D(uevrUtils.vector(0.0001, 0.0001, 0.0001))
                        end
                        return comp
                    end)
                    if ok and result then
                        warmupSphereActor = result:GetOwner()
                        print("[Scope] Warmup sphere spawned -- waiting 2 ticks before destroying")
                    else
                        -- Sphere mesh not ready yet (rare); skip warmup, unblock immediately
                        warmupSphereDone = true
                        print("[Scope] Warmup sphere creation failed -- skipping warmup")
                    end
                end
            end

            -- Warmup sphere lifecycle: mark done after 2 ticks so deferred ticker can start,
            -- but do NOT destroy the sphere -- keep it alive permanently as a "hook keeper".
            -- UEVR hooks StaticMeshComponent vtables per-instance. Destroying the sphere
            -- leaves a dangling pointer in UEVR's hook chain. When the game later registers
            -- the PIP scope's own SMC, UEVR traverses the broken chain → crash at 0x0C.
            -- The reflex sight reticule sphere fixed this accidentally by staying alive.
            if not warmupSphereDone then
                if warmupSphereActor and UEVR_UObjectHook.exists(warmupSphereActor) then
                    warmupSphereTick = warmupSphereTick + 1
                    if warmupSphereTick >= 2 then
                        -- Restore material state but KEEP the sphere alive
                        pcall(function()
                            local emissiveMat = utils.find_required_object(emissive_mesh_material_name)
                            if emissiveMat then emissiveMat.BlendMode = 7 end
                        end)
                        warmupSphereDone = true
                        diag("[Scope-Diag] warmup sphere kept alive as hook keeper -- SMC hook chain now valid")

                        -- ── EAGER SCC WARMUP ─────────────────────────────────────────
                        local viewport = engine.GameViewport
                        local world = viewport and viewport.World
                        -- Create a tiny hook-keeper SCC + RT to initialise the UEVR SCC
                        -- hook chain. Stored in warmupSCC/warmupRT — NOT in
                        -- scope_controller.scene_capture_component/render_target — so the
                        -- deferred creation block always makes the real scope SCC fresh
                        -- (bCaptureEveryFrame=1, Config.scopeTextureSize resolution).
                        if world and not utils.validate_object(warmupSCC) then
                            diag("[Scope-Diag] warmup: creating hook-keeper SCC + RT (separate from scope SCC)")
                            pcall(function()
                                if not utils.validate_object(warmupRT) then
                                    warmupRT = uevrUtils.createRenderTarget2D({
                                        width  = 64,
                                        height = 64,
                                        format = 6,
                                    })
                                    diag("[Scope-Diag] warmup: hook-keeper RT created -> " .. tostring(warmupRT ~= nil))
                                end
                                local comp = uevrUtils.createSceneCaptureComponent({visible=false, collisionEnabled=false})
                                diag("[Scope-Diag] warmup: hook-keeper SCC created -> " .. tostring(comp ~= nil))
                                if comp and warmupRT then
                                    comp.TextureTarget = warmupRT
                                    comp.bUseRayTracingIfEnabled = false
                                    comp.bEnableVolumetricCloudsCapture = false
                                    comp.bAlwaysPersistRenderingState = true
                                    comp.bCacheVolumetricCloudsShadowMaps = true
                                    comp.bCaptureEveryFrame = 0  -- hook-keeper: no per-frame cost
                                    pcall(function() comp:SetAbsolute(false, false, false) end)
                                    pcall(function() comp.bUsePawnControlRotation = false end)
                                    comp:SetVisibility(false)
                                    warmupSCC = comp  -- hook-keeper only; NOT the active scope SCC
                                    diag("[Scope-Diag] warmup: hook-keeper SCC stored (scope_controller.scene_capture_component left nil)")
                                end
                            end)
                        end
                    end
                else
                    -- Actor gone (GC/level teardown) — unblock without a sphere
                    warmupSphereActor = nil
                    warmupSphereDone  = true
                end
            end
            -- print("[DEBUG] Calling Update (InternalTick: " .. tostring(scope_controller.scopeInternalTick) .. ")")
            scope_controller:Update(engine)
        end)
        
        if not success then
            print("[Scope] tick error: " .. tostring(err))
        end
    end
)

-- (Previously contained a now-removed on_post_calculate_stereo_view_offset callback
--  that attempted to gate SCC creation on stereo health. That approach was incorrect
--  because the callback fires even during UEVR's broken double-hook state. The actual
--  gate is now the UObject pool check for a pre-existing SceneCaptureComponent2D.)



uevr.sdk.callbacks.on_script_reset(function()
    scope_controller:Reset()
    scope_controller:ResetStatic()
    scope_controller:InitStatic()
    -- Keep warmupSphereActor alive -- it is a permanent hook keeper.
    -- Destroying it would leave UEVR's SMC hook chain dangling.
    -- Just nil the Lua reference so the pawn-ready block can spawn a fresh
    -- one if needed (level change will have torn down the old actor anyway).
    warmupSphereActor = nil
    warmupSphereTick  = 0
    warmupSphereDone  = true  -- Mid-session reload: assume warm
    warmupSCC = nil  -- Keep hook-keeper alive in engine; just nil the Lua reference
    warmupRT  = nil
 end)


return scope_controller
