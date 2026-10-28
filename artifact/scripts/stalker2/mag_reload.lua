-- mag_reload.lua
-- Physical magazine reload via left-hand BoxComponent overlap + Left Grip

local utils = require("common/utils")
local uevrUtils = require("libs/uevr_utils")
local hands = require("libs/hands")

local M = {}

local BoxCompLH = nil  -- Box on left VR hand
local boxOwnerPawnAddr = nil  -- pawn address BoxCompLH was created for (reuse guard, see M.init)
local MagBox    = nil  -- Box on weapon magazine socket

-- Visual-only stand-ins for BoxCompLH/MagBox's debug display. A BoxComponent's own
-- native wireframe/solid debug draw is a collision-shape scene proxy, not a mesh -
-- it has no material to give the ForegroundFOVEnabled parameter the game's own
-- first-person meshes carry (see uevrUtils.applyForegroundFOV), so toggling
-- SetVisibility/SetHiddenInGame on the box itself renders it with the normal world
-- projection and it sits at the wrong depth relative to the hand/weapon - the same
-- issue the mag proxy meshes had. Fix: keep the real boxes permanently hidden and
-- show a small Cube static mesh, parented to the box (so it inherits the box's
-- offset/rotation/scale automatically), with the foreground-FOV fix applied.
local BoxCompLH_Visual = nil
local MagBox_Visual    = nil

local debugMode = false
local lastReloadTime = 0
local RELOAD_COOLDOWN = 1.2
local wasGripHeld = false  -- for rising-edge detection

-- Set to true just before injecting XINPUT_GAMEPAD_X on a confirmed mag overlap.
-- Entry.lua reads and resets this flag in the same engine tick that sees the
-- injected X, so it can call SendKeyDown('R') (with isReloading) instead of
-- SendReloadKey() (without isReloading). Physical X presses never set this flag.
local gestureFired = false

-- Cached result of BoxCompLH:IsOverlappingComponent(MagBox), updated once per
-- engine tick by M.updateOverlapState(). Both on_xinput_get_state and
-- tryInterceptReload read this flag to gate manual reload activation.
local handOverlapsMag = false

function M.consumeGestureFired()
    if gestureFired then
        gestureFired = false
        return true
    end
    return false
end

-- Cached BoxComponent class
local VHitBoxClass = nil
local function getBoxClass()
    if VHitBoxClass == nil then
        pcall(function()
            VHitBoxClass = utils.find_required_object("Class /Script/Engine.BoxComponent")
        end)
    end
    return VHitBoxClass
end

-- Robust liveness check: UEVR_UObjectHook.exists() catches GC'd objects that
-- utils.validate_object() misses (validate_object only checks the Lua reference).
local function isAlive(obj)
    if obj == nil then return false end
    local ok, alive = pcall(function() return UEVR_UObjectHook.exists(obj) end)
    return ok and alive
end

-- Engine's default StaticMesh Cube (/Engine/BasicShapes/Cube.Cube) is 100uu across
-- (half-size 50). A freshly-constructed BoxComponent's default BoxExtent (half-size)
-- is 32 - neither box here ever calls SetBoxExtent, so this ratio holds for both.
-- The visual's own RelativeScale3D is set to this constant; the box's own
-- RelativeScale3D/offset/rotation (cfg.handX/handY/handZ etc) is inherited on top of
-- it automatically via the parent-child attachment, so it stays in sync with no
-- extra per-tick code.
local BOX_TO_CUBE_SCALE = 32.0 / 50.0

local function getSmClass()
    local cls = nil
    pcall(function()
        cls = utils.find_required_object("Class /Script/Engine.StaticMeshComponent")
    end)
    return cls
end

-- find_instance_of/find_all_of only search objects ALREADY resident in memory -
-- unlike /Engine/BasicShapes/Cylinder (which Base/scope.lua's PiP scope already
-- loads for its own tube mesh), nothing else in this game references the Cube
-- asset, so it was never loaded and a plain find_instance_of lookup silently
-- returned nil (SetStaticMesh(nil) - visual created but with no mesh, invisible
-- even when shown).
--
-- Both uevrUtils.getLoadedAsset()'s own return value (AssetRegistryHelpers:GetAsset())
-- AND a follow-up find_instance_of/find_all_of scan turned out unreliable here -
-- confirmed live via MCP (a direct GUObjectArray search) that the Cube StaticMesh
-- WAS genuinely resident in memory while find_all_of's class-enumeration
-- (UEVR_UObjectHook.get_objects_by_class) still wasn't returning it, i.e. that
-- enumeration doesn't reliably pick up an asset the instant it's force-loaded.
-- uevr.api:find_uobject() (a direct by-name lookup, the same call M.get_class()
-- already relies on everywhere) doesn't have that problem - use it instead, after
-- getLoadedAsset's blocking call has forced the asset to actually be loaded.
local cachedCubeMesh = nil
local function getCubeMesh()
    if not isAlive(cachedCubeMesh) then
        cachedCubeMesh = nil
        pcall(function()
            uevrUtils.getLoadedAsset("StaticMesh /Engine/BasicShapes/Cube.Cube")
            cachedCubeMesh = uevr.api:find_uobject("StaticMesh /Engine/BasicShapes/Cube.Cube")
        end)
    end
    return cachedCubeMesh
end

-- uevrUtils.applyForegroundFOV (via fixMeshFOV) only converts a mesh's OWN material
-- to a dynamic instance when that material is already a MaterialInstanceConstant -
-- our cube's default material (/Engine/BasicShapes/BasicShapeMaterial) is a plain
-- base Material, so that conversion silently never happens (confirmed live: the
-- visual's OverrideMaterials stayed empty, ForegroundFOVEnabled was never set).
-- And even if it did convert, BasicShapeMaterial almost certainly doesn't
-- implement ForegroundFOVEnabled in its shader graph at all - it's a generic
-- engine default, not one of this game's own materials - so setting the
-- parameter on it would likely be a silent no-op with zero visual effect anyway.
--
-- Confirmed live via MCP (comparing both hand PoseableMeshComponents against the
-- weapon mesh) that ForegroundFOVEnabled=1.0 baked into the material itself (not
-- bForeground, which is false on both hands - a red herring) is what the game's
-- own first-person meshes actually rely on. So instead of trying to retrofit our
-- generic cube's own material, just borrow material slot 0 straight off the live
-- left hand mesh - it's always present in VR and already has the parameter set
-- correctly by the game itself.
local cachedForegroundMaterial = nil
local function getForegroundMaterial()
    if not isAlive(cachedForegroundMaterial) then
        cachedForegroundMaterial = nil
        pcall(function()
            local handMesh = hands.getHandComponent(Handed.Left)
            if isAlive(handMesh) then
                local materials = handMesh:GetMaterials()
                if materials ~= nil and materials[1] ~= nil then
                    cachedForegroundMaterial = materials[1]
                end
            end
        end)
    end
    return cachedForegroundMaterial
end

-- Creates a hidden-by-default Cube visual proxy attached to parentBox (SnapToTarget,
-- then scaled to BOX_TO_CUBE_SCALE so it visually matches the box's collision
-- volume). Returns nil on any failure - callers already tolerate a nil visual
-- (debug display just won't show anything, collision/overlap logic is unaffected).
local function createDebugVisualCube(ownerPawn, parentBox)
    if not utils.validate_object(ownerPawn) or not isAlive(parentBox) then return nil end
    local smClass = getSmClass()
    if not smClass then return nil end
    local visual = nil
    local ok = pcall(function()
        visual = uevr.api:add_component_by_class(ownerPawn, smClass)
    end)
    if not ok or not isAlive(visual) then return nil end
    pcall(function()
        visual:SetStaticMesh(getCubeMesh())
        visual:SetCollisionEnabled(0)
        visual:K2_AttachToComponent(parentBox, uevrUtils.fname_from_string("None"), 2, 2, 2, true)
        visual.RelativeScale3D.X = BOX_TO_CUBE_SCALE
        visual.RelativeScale3D.Y = BOX_TO_CUBE_SCALE
        visual.RelativeScale3D.Z = BOX_TO_CUBE_SCALE
        local fovMaterial = getForegroundMaterial()
        if fovMaterial ~= nil then
            visual:SetMaterial(0, fovMaterial)
        end
        visual:SetHiddenInGame(true)
        visual:SetVisibility(false, false)
    end)
    return visual
end

-- Debug visuals only exist while debug mode is on (2026-10-15): a hidden cube under the pawn body mesh was shown
-- again by code that shows the body with propagate-to-children (textured box under the pistol mag, debug off).
-- Nothing left hidden can be shown by accident.
local function destroyDebugVisual(visual)
    if isAlive(visual) then
        pcall(function() visual:K2_DestroyComponent(visual) end)
    end
    return nil
end

-- Shows/hides a visual proxy while forcing its real (collision-only) box to stay
-- permanently hidden, since the box's own native debug draw is what has the wrong
-- render depth in the first place.
local function setDebugVisualVisible(box, visual, val)
    if isAlive(box) then
        pcall(function()
            box:SetHiddenInGame(true)
            box:SetVisibility(false, false)
        end)
    end
    if isAlive(visual) then
        pcall(function()
            visual:SetHiddenInGame(not val)
            visual:SetVisibility(val, false)
        end)
    end
end

-- Current active config (applied to boxes; drives UI display)
-- Hand box: global only (follows VR hand, not weapon-specific)
-- Mag box: per-weapon (size + offset relative to socket)
local cfg = {
    magSocket = "jnt_magazine",
    handX = 0.17, handY = 0.11, handZ = 0.15,
    handOffX = -4.2, handOffY = 0.3, handOffZ = -2.7,
    handRotX = 0, handRotY = 0, handRotZ = 7.0,
    magX  = 0.3, magY  = 0.2, magZ  = 0.5,
    magOffX = 0, magOffY = 0, magOffZ = 0,
}

local function applyBoxSizes()
    pcall(function()
        if isAlive(BoxCompLH) then
            BoxCompLH.RelativeScale3D.X = cfg.handX
            BoxCompLH.RelativeScale3D.Y = cfg.handY
            BoxCompLH.RelativeScale3D.Z = cfg.handZ
            BoxCompLH.RelativeLocation.X = cfg.handOffX
            BoxCompLH.RelativeLocation.Y = cfg.handOffY
            BoxCompLH.RelativeLocation.Z = cfg.handOffZ
            BoxCompLH.RelativeRotation.Pitch = cfg.handRotY
            BoxCompLH.RelativeRotation.Yaw = cfg.handRotZ
            BoxCompLH.RelativeRotation.Roll = cfg.handRotX
        end
    end)
    pcall(function()
        if isAlive(MagBox) then
            MagBox.RelativeScale3D.X = cfg.magX
            MagBox.RelativeScale3D.Y = cfg.magY
            MagBox.RelativeScale3D.Z = cfg.magZ
            MagBox.RelativeLocation.X = cfg.magOffX
            MagBox.RelativeLocation.Y = cfg.magOffY
            MagBox.RelativeLocation.Z = cfg.magOffZ
        end
    end)
end

-- Called on every weapon equip. left_hand_comp = motionControllerActors.left_hand_component
-- Always destroys and recreates BoxCompLH to fix the level-load GC race:
-- After a level transition, the old BoxCompLH may still pass isAlive() (not yet GC'd)
-- but is orphaned from the old world - overlaps never fire. By always recreating,
-- we guarantee the box is attached to the current pawn/hand in the current world.
-- This mirrors how update_weapon_collision() handles MagBox.
function M.init(pawn, left_hand_comp)
    -- print("[MagReload] init() called")

    if not utils.validate_object(pawn) then
        print("[MagReload] ERROR: init() pawn invalid")
        return
    end

    -- PERF (2026-09-21): reuse BoxCompLH across weapon switches when it is alive AND still
    -- belongs to the same pawn object. The destroy-and-recreate below exists for the
    -- level-load GC race (old component alive in GUObjectArray but orphaned from the dead
    -- world) - a level load always hands us a NEW pawn object, so comparing the owning pawn
    -- address keeps that protection while dropping the per-equip component churn (destroy
    -- + add_component + attach + collision setup + debug visual, all on the game thread).
    -- Same fix the IK tree carries (memory: stalker2-ik-perf-optimizations).
    -- exists()/isAlive is NOT a liveness test on this backend (old-world objects pass it), so
    -- the reuse is additionally gated on the engine's own IsValid and on the box still being
    -- owned by this exact pawn; anything unexpected falls through to destroy-and-recreate.
    if isAlive(BoxCompLH) and boxOwnerPawnAddr ~= nil and boxOwnerPawnAddr == pawn:get_address()
       and utils.validate_object(left_hand_comp) then
        local reused = false
        pcall(function()
            if kismet_system_library == nil or not kismet_system_library:IsValid(BoxCompLH) then return end
            local owner = BoxCompLH:GetOwner()
            if owner == nil or owner:get_address() ~= pawn:get_address() then return end
            BoxCompLH:K2_AttachToComponent(left_hand_comp, "Root", 0, 0, 0, true)
            reused = true
        end)
        if reused then
            return
        end
    end

    -- Always destroy the existing BoxCompLH before recreating.
    -- Do NOT skip if isAlive: after a level load the old component can still be alive
    -- in GUObjectArray (GC is deferred) but orphaned from the destroyed world, causing
    -- IsOverlappingComponent() to silently return false every tick.
    if BoxCompLH ~= nil then
        pcall(function()
            if isAlive(BoxCompLH_Visual) and BoxCompLH_Visual.K2_DestroyComponent then
                BoxCompLH_Visual:K2_DestroyComponent(BoxCompLH_Visual)
            end
        end)
        BoxCompLH_Visual = nil
        pcall(function()
            if isAlive(BoxCompLH) and BoxCompLH.K2_DestroyComponent then
                BoxCompLH:K2_DestroyComponent(BoxCompLH)
            end
        end)
        BoxCompLH = nil
        print("[MagReload] init() destroyed old BoxCompLH (recreating for new world/pawn)")
    end

    local cls = getBoxClass()
    if not cls then
        print("[MagReload] ERROR: BoxComponent class not found")
        return
    end
    -- print("[MagReload] BoxComponent class OK")

    if not utils.validate_object(left_hand_comp) then
        print("[MagReload] ERROR: left_hand_component is invalid")
        return
    end
    -- print("[MagReload] left_hand_comp OK: " .. tostring(left_hand_comp:get_full_name()))

    local ok, err = pcall(function()
        BoxCompLH = uevr.api:add_component_by_class(pawn, cls)
    end)
    if not ok or not isAlive(BoxCompLH) then
        print("[MagReload] ERROR: BoxCompLH creation failed: " .. tostring(err))
        BoxCompLH = nil
        return
    end
    boxOwnerPawnAddr = pawn:get_address()
    -- print("[MagReload] BoxCompLH created OK")

    pcall(function()
        BoxCompLH:K2_AttachToComponent(left_hand_comp, "Root", 0, 0, 0, true)
    end)
    -- print("[MagReload] BoxCompLH attached to left hand")

    pcall(function()
        if BoxCompLH and BoxCompLH.SetGenerateOverlapEvents then
            BoxCompLH:SetGenerateOverlapEvents(true)
            BoxCompLH:SetCollisionObjectType(2) -- WorldDynamic
            BoxCompLH:SetCollisionResponseToAllChannels(1) -- Overlap everything
            BoxCompLH:SetCollisionEnabled(1)
        end
    end)

    BoxCompLH.RelativeScale3D.X = cfg.handX
    BoxCompLH.RelativeScale3D.Y = cfg.handY
    BoxCompLH.RelativeScale3D.Z = cfg.handZ

    BoxCompLH_Visual = destroyDebugVisual(BoxCompLH_Visual)
    if debugMode then BoxCompLH_Visual = createDebugVisualCube(pawn, BoxCompLH) end

    setDebugVisualVisible(BoxCompLH, BoxCompLH_Visual, debugMode)
    if debugMode then
        print("[MagReload] Left hand box created (visible, debug mode)")
    end
end

-- Called on every weapon equip.
-- boxCfg (optional table) overrides current sizes/offsets for this weapon:
--   { magX, magY, magZ, magOffX, magOffY, magOffZ }
function M.update_weapon_collision(pawn, weapon_mesh, boxCfg, profileSocket)
    -- print("[MagReload] update_weapon_collision() called")

    if not utils.validate_object(pawn) then
        print("[MagReload] ERROR: update_weapon_collision() pawn invalid")
        return
    end
    if not utils.validate_object(weapon_mesh) then
        print("[MagReload] ERROR: update_weapon_collision() weapon_mesh invalid")
        return
    end

    local cls = getBoxClass()
    if not cls then
        print("[MagReload] ERROR: update_weapon_collision() BoxComponent class not found")
        return
    end

    -- Apply per-weapon config if provided, else keep current
    if boxCfg then
        if boxCfg.magSocket then cfg.magSocket = boxCfg.magSocket end
        if boxCfg.magX   then cfg.magX   = boxCfg.magX   end
        if boxCfg.magY   then cfg.magY   = boxCfg.magY   end
        if boxCfg.magZ   then cfg.magZ   = boxCfg.magZ   end
        if boxCfg.magOffX then cfg.magOffX = boxCfg.magOffX end
        if boxCfg.magOffY then cfg.magOffY = boxCfg.magOffY end
        if boxCfg.magOffZ then cfg.magOffZ = boxCfg.magOffZ end
        if boxCfg.handX  then cfg.handX  = boxCfg.handX  end
        if boxCfg.handY  then cfg.handY  = boxCfg.handY  end
        if boxCfg.handZ  then cfg.handZ  = boxCfg.handZ  end
        if boxCfg.handOffX then cfg.handOffX = boxCfg.handOffX end
        if boxCfg.handOffY then cfg.handOffY = boxCfg.handOffY end
        if boxCfg.handOffZ then cfg.handOffZ = boxCfg.handOffZ end
        if boxCfg.handRotX then cfg.handRotX = boxCfg.handRotX end
        if boxCfg.handRotY then cfg.handRotY = boxCfg.handRotY end
        if boxCfg.handRotZ then cfg.handRotZ = boxCfg.handRotZ end
    end

    -- Create MagBox once; keep it alive and re-attach on weapon change.
    -- Use isAlive() to catch GC'd objects that utils.validate_object() misses.
    if not isAlive(MagBox) then
        if MagBox ~= nil then
            print("[MagReload] MagBox was dead (GC'd) -- recreating")
        end
        MagBox = nil
        local ok, err = pcall(function()
            MagBox = uevr.api:add_component_by_class(pawn, cls)
        end)
        if not ok or not isAlive(MagBox) then
            print("[MagReload] ERROR: MagBox creation failed: " .. tostring(err))
            MagBox = nil
            return
        end
        -- Enable collision on MagBox so UE registers overlaps with BoxCompLH.
        -- Both boxes must have GenerateOverlapEvents=true and matching collision
        -- channels for IsOverlappingComponent() to return correct results.
        pcall(function()
            MagBox:SetGenerateOverlapEvents(true)
            MagBox:SetCollisionObjectType(2)           -- WorldDynamic (matches BoxCompLH)
            MagBox:SetCollisionResponseToAllChannels(1) -- ECR_Overlap
            MagBox:SetCollisionEnabled(1)              -- Query Only
        end)
        MagBox_Visual = destroyDebugVisual(MagBox_Visual)
        if debugMode then MagBox_Visual = createDebugVisualCube(pawn, MagBox) end
        -- print("[MagReload] MagBox created and collision enabled")
    else
        -- print("[MagReload] MagBox already alive, re-attaching")
    end

    -- Re-attach with SnapToTarget (rule 2) to forcefully re-parent to new weapon mesh
    local attached = false
    pcall(function()
        if weapon_mesh:DoesSocketExist(cfg.magSocket) then
            MagBox:K2_AttachToComponent(weapon_mesh, cfg.magSocket, 2, 2, 2, false)
            -- print("[MagReload] MagBox attached to: " .. cfg.magSocket)
            attached = true
        elseif profileSocket ~= nil and profileSocket ~= "" and weapon_mesh:DoesSocketExist(profileSocket) then
            -- Weapon-profile socket (ptm_manual_reload WEAPON_PROFILES magSocket), for weapons that
            -- have none of the magazine/bullet sockets below. First user: the RPG-7, whose only
            -- ammo socket (jnt_ammo_move) rides the reload animation, so the static "Muzzle"
            -- socket - where a rocket physically goes in - is the insert target instead.
            -- Checked after the saved per-weapon socket so a user override in settings.json wins.
            MagBox:K2_AttachToComponent(weapon_mesh, profileSocket, 2, 2, 2, false)
            attached = true
        elseif weapon_mesh:DoesSocketExist("jnt_magazine") then
            -- Fallback 1: standard mag socket
            MagBox:K2_AttachToComponent(weapon_mesh, "jnt_magazine", 2, 2, 2, false)
            -- print("[MagReload] MagBox attached to fallback: jnt_magazine")
            attached = true
        elseif weapon_mesh:DoesSocketExist("jnt_magazine_master") then
            -- Fallback 1b: newer socket-naming convention (SK_Skp confirmed via MCP -
            -- AttachSocketName on its live WeaponAttachmentSM_Wpn_SKP_MagDefault_Full/
            -- Empty components). Checked before jnt_mag_tab/jnt_clip_base/jnt_bullet
            -- since those are more specialized/coincidental fallbacks (jnt_bullet in
            -- particular is meant for tube-fed shotguns' live shells, not box mags,
            -- and would otherwise false-positive-match on this weapon).
            MagBox:K2_AttachToComponent(weapon_mesh, "jnt_magazine_master", 2, 2, 2, false)
            -- print("[MagReload] MagBox attached to fallback: jnt_magazine_master")
            attached = true
        elseif weapon_mesh:DoesSocketExist("jnt_mag_tab") then
            -- Fallback 2: mag-tab socket (some SMGs)
            MagBox:K2_AttachToComponent(weapon_mesh, "jnt_mag_tab", 2, 2, 2, false)
            -- print("[MagReload] MagBox attached to fallback: jnt_mag_tab")
            attached = true
        elseif weapon_mesh:DoesSocketExist("jnt_clip_base") then
            -- Fallback 3: clip-base socket (SK_m86000 bigmag, SK_svdm, SK_grim0 confirmed via MCP)
            MagBox:K2_AttachToComponent(weapon_mesh, "jnt_clip_base", 2, 2, 2, false)
            -- print("[MagReload] MagBox attached to fallback: jnt_clip_base")
            attached = true
        elseif weapon_mesh:DoesSocketExist("jnt_bullet") then
            -- Fallback 4: live shell socket (RAM-2, M860 standard tube-fed)
            MagBox:K2_AttachToComponent(weapon_mesh, "jnt_bullet", 2, 2, 2, false)
            -- print("[MagReload] MagBox attached to fallback: jnt_bullet")
            attached = true
        elseif weapon_mesh:DoesSocketExist("jnt_bullet_01") then
            -- Fallback 5: Obrez double-barrel socket naming (underscore + leading zero)
            MagBox:K2_AttachToComponent(weapon_mesh, "jnt_bullet_01", 2, 2, 2, false)
            -- print("[MagReload] MagBox attached to fallback: jnt_bullet_01")
            attached = true
        elseif weapon_mesh:DoesSocketExist("jnt_clip_base_second") then
            -- Fallback 4: second clip-base socket (SK_grim0 twin-mag variant)
            MagBox:K2_AttachToComponent(weapon_mesh, "jnt_clip_base_second", 2, 2, 2, false)
            -- print("[MagReload] MagBox attached to fallback: jnt_clip_base_second")
            attached = true
        else
            print("[MagReload] WARNING: no mag socket found on weapon: " .. weapon_mesh:get_full_name())
        end
    end)

    if not attached then
        -- Log weapon name to help identify why no socket matched
        pcall(function()
            print("[MagReload] WARNING: MagBox not attached for weapon: " .. weapon_mesh:get_full_name())
        end)
    end

    pcall(function()
        if MagBox and MagBox.SetGenerateOverlapEvents then
            MagBox:SetGenerateOverlapEvents(true)
            MagBox:SetCollisionObjectType(2) -- WorldDynamic
            MagBox:SetCollisionResponseToAllChannels(1) -- Overlap everything
            MagBox:SetCollisionEnabled(1)
        end
    end)

    -- Apply size and offset
    applyBoxSizes()

    setDebugVisualVisible(MagBox, MagBox_Visual, debugMode)
end

function M.check_reload_input(state, pawn)
    -- DISABLED: We are bypassing the legacy gesture reload system to implement True Manual Reloads
    return false
end

-- Called once per engine tick from Entry.lua (before ptmReload.on_pre_engine_tick).
-- Queries UE's physics overlap between the left-hand box and the mag socket box,
-- then caches the result so both on_xinput_get_state and tryInterceptReload can
-- read it without making repeated UObject calls.
function M.updateOverlapState()
    handOverlapsMag = false
    if not isAlive(BoxCompLH) or not isAlive(MagBox) then return end
    pcall(function()
        handOverlapsMag = BoxCompLH:IsOverlappingComponent(MagBox)
    end)
end

-- Returns the cached overlap result from the most recent updateOverlapState() call.
-- true  = left hand box is physically overlapping the weapon mag socket box.
-- false = no overlap (or boxes not yet initialised).
function M.isHandOverlappingMag()
    return handOverlapsMag
end

-- Returns the world location of MagBox (the collision box attached to the weapon mag socket).
-- ptm_manual_reload uses this for the insertion distance check instead of querying
-- GetSocketLocation itself, so both systems reference the exact same point in world space
-- and the socket name does not need to be duplicated in the ptm profile table.
-- Returns nil if MagBox is not alive.
function M.getMagBoxLocation()
    local loc = nil
    if isAlive(MagBox) then
        pcall(function() loc = MagBox:K2_GetComponentLocation() end)
    end
    return loc
end

-- The weapon socket MagBox is actually attached to (FName), i.e. whichever tier of the
-- socket chain in update_weapon_collision won. ptm_manual_reload's shell insert glide
-- seats shells at this socket. Returns nil if MagBox is not alive.
function M.getMagBoxSocketName()
    local name = nil
    if isAlive(MagBox) then
        pcall(function() name = MagBox.AttachSocketName end)
    end
    return name
end

-- Return a copy of the current active config (for UI display)
function M.get_config()
    return {
        magSocket = cfg.magSocket,
        handX = cfg.handX, handY = cfg.handY, handZ = cfg.handZ,
        handOffX = cfg.handOffX, handOffY = cfg.handOffY, handOffZ = cfg.handOffZ,
        handRotX = cfg.handRotX, handRotY = cfg.handRotY, handRotZ = cfg.handRotZ,
        magX  = cfg.magX,  magY  = cfg.magY,  magZ  = cfg.magZ,
        magOffX = cfg.magOffX, magOffY = cfg.magOffY, magOffZ = cfg.magOffZ,
    }
end

-- Apply sizes and offsets immediately (called from UI sliders)
function M.set_config(newCfg)
    if newCfg.magSocket then cfg.magSocket = newCfg.magSocket end
    if newCfg.handX   then cfg.handX   = newCfg.handX   end
    if newCfg.handY   then cfg.handY   = newCfg.handY   end
    if newCfg.handZ   then cfg.handZ   = newCfg.handZ   end
    if newCfg.handOffX then cfg.handOffX = newCfg.handOffX end
    if newCfg.handOffY then cfg.handOffY = newCfg.handOffY end
    if newCfg.handOffZ then cfg.handOffZ = newCfg.handOffZ end
    if newCfg.handRotX then cfg.handRotX = newCfg.handRotX end
    if newCfg.handRotY then cfg.handRotY = newCfg.handRotY end
    if newCfg.handRotZ then cfg.handRotZ = newCfg.handRotZ end
    if newCfg.magX    then cfg.magX    = newCfg.magX    end
    if newCfg.magY    then cfg.magY    = newCfg.magY    end
    if newCfg.magZ    then cfg.magZ    = newCfg.magZ    end
    if newCfg.magOffX then cfg.magOffX = newCfg.magOffX end
    if newCfg.magOffY then cfg.magOffY = newCfg.magOffY end
    if newCfg.magOffZ then cfg.magOffZ = newCfg.magOffZ end
    applyBoxSizes()
end

function M.set_debug(val)
    debugMode = val
    if val then
        local pawn = uevr.api:get_local_pawn(0)
        if pawn ~= nil then
            if not isAlive(BoxCompLH_Visual) and isAlive(BoxCompLH) then BoxCompLH_Visual = createDebugVisualCube(pawn, BoxCompLH) end
            if not isAlive(MagBox_Visual) and isAlive(MagBox) then MagBox_Visual = createDebugVisualCube(pawn, MagBox) end
        end
    else
        BoxCompLH_Visual = destroyDebugVisual(BoxCompLH_Visual)
        MagBox_Visual = destroyDebugVisual(MagBox_Visual)
    end
    -- setDebugVisualVisible() itself uses isAlive() and tolerates a dead/nil box or
    -- visual (utils.validate_object() misses GC'd UE objects, which would otherwise
    -- crash the subsequent SetHiddenInGame() call with "attempt to call a nil value").
    setDebugVisualVisible(BoxCompLH, BoxCompLH_Visual, val)
    setDebugVisualVisible(MagBox, MagBox_Visual, val)
end

function M.get_debug()
    return debugMode
end

-- Expose the left hand box so two_hand.lua can share it
function M.get_hand_box()
    return BoxCompLH
end

-- Expose liveness check for callers that need to know if boxes are ready
function M.boxes_alive()
    return isAlive(BoxCompLH) and isAlive(MagBox)
end

return M
