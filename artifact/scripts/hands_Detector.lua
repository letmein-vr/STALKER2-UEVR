local api = uevr.api
local uevrUtils = require("libs/uevr_utils")
local controllers = require("libs/controllers")
local gameState = require("stalker2.gamestate")
-- Config is loaded globally in Entry.lua, but we might need to access it if not passed.
-- Assuming Config is global or we require it. 
-- Ideally, we require it to be safe.
local Config = require("Config.CONFIG")

-- Timing: check every 0.2 seconds (adjust if hitches occur)
local CHECK_INTERVAL = 0.2
local lastCheckTime = 0

local currentDetector = nil
local currentDetectorName = nil

local function findDetectorComponent()
    local pawn = api:get_local_pawn()
    if not pawn then return nil end

    local mesh = pawn.Mesh
    if not mesh then return nil end

    return uevrUtils.getChildComponent(mesh, "Detector")
end

-- FIX (2026-09-06): finds a detector that is ALREADY attached to the left controller. Needed as a
-- self-heal path: findDetectorComponent() above only looks under the pawn's holster mesh, which is
-- empty once the detector is grabbed (it lives under the controller instead). If currentDetector
-- ever desyncs (e.g. controllers.getController(Handed.Left) returns nil for a frame while the
-- controller actor is being recreated), the quick-validation block below concludes "detached" and
-- clears currentDetector even though the detector is still physically attached - and without this,
-- nothing could ever find it again, permanently breaking RefreshTransform()'s live slider updates
-- until the item was dropped and re-grabbed.
local function findAttachedDetectorComponent()
    local leftController = controllers.getController(Handed.Left)
    if not leftController then return nil end
    return uevrUtils.getChildComponent(leftController, "Detector")
end

-- Helper: Get Clean Mesh Name
local function getDetectorName(detector)
    if not detector then return "Unknown" end
    local name = "Unknown"
    if detector.SkeletalMesh then
        name = uevrUtils.getShortName(detector.SkeletalMesh)
    elseif detector.StaticMesh then
        name = uevrUtils.getShortName(detector.StaticMesh)
    else
        name = detector:get_fname():to_string()
    end
    return string.lower(name)
end

-- Helper: Load Profile
local function loadProfile(name)
    if Config.detectorProfiles[name] then
        print("[DetectorAttach] FOUND PROFILE FOR: " .. name)
        local prof = Config.detectorProfiles[name]
        Config.detectorOffset = {X = prof.offset.X, Y = prof.offset.Y, Z = prof.offset.Z}
        Config.detectorRotation = {Pitch = prof.rotation.Pitch, Yaw = prof.rotation.Yaw, Roll = prof.rotation.Roll}
        print("[DetectorAttach] Loaded profile for: " .. name .. " -> Offset: " .. tostring(Config.detectorOffset.X))
    else
        print("[DetectorAttach] NO PROFILE FOR: " .. name .. " - Creating default.")
        -- Auto-initialize a profile for this new detector using current global defaults
        -- This ensures we don't accidentally share the 'global' value across different unknown detectors
        Config.detectorProfiles[name] = {
            offset = {X = Config.detectorOffset.X, Y = Config.detectorOffset.Y, Z = Config.detectorOffset.Z},
            rotation = {Pitch = Config.detectorRotation.Pitch, Yaw = Config.detectorRotation.Yaw, Roll = Config.detectorRotation.Roll}
        }
        Config:markDirty()
        Config:save()
    end
end

-- FIX (2026-09-06): once a detector is reparented off the pawn's CharacterMesh0 onto the
-- left MotionControllerComponent, two native primitive-component properties left over from its
-- pawn-attached state make it fully invisible in the main pass (it still casts a shadow, since
-- shadow-caster rendering uses the mesh's real geometry/bounds independently):
--   1. bForeground=true - the game's native first-person "foreground" render-pass flag. Correct
--      for meshes still parented under CharacterMesh0 (weapon, WeaponInHandsMesh - both keep
--      bForeground=true and render fine there), but the working VR hand PoseableMeshComponents
--      (also attached to a MotionControllerComponent) all ship with bForeground=false. Confirmed
--      via live MCP: flipping the detector's bForeground to false via the real SetForeground()
--      UFunction (not a raw field write - see stalker2-depth-rendering-fixes memory on why the
--      real setter matters for render-state toggles) did not by itself fix visibility.
--   2. bUseAttachParentBound=true - makes the component reuse its AttachParent's bounds for
--      frustum culling instead of computing its own. The parent is a MotionControllerComponent,
--      a non-rendered SceneComponent with ~zero bounds, so the detector was being frustum-culled
--      out of the main pass every frame. The working hand PMCs have this false. A raw field write
--      is sufficient here (unlike bRenderInDepthPass) because the component's transform updates
--      every tick while attached to a moving controller, which naturally re-derives bounds.
-- Confirmed live in-headset: both together (not just bForeground alone) make the mesh visible.
local function fixDetectorVisibility(detector)
    if not detector then return end
    if detector.bForeground then
        detector:call("SetForeground", false)
    end
    if detector.bUseAttachParentBound then
        detector.bUseAttachParentBound = false
    end
end

--------------------------------------------------------------------------------
-- Attach detector to left controller
--------------------------------------------------------------------------------
local function attachDetector(detector)
    if not detector then return false end
    
    -- Skip PDA
    if detector.SkeletalMesh then
        local meshName = detector.SkeletalMesh:get_full_name()
        if meshName and string.find(string.lower(meshName), "pda") then
            print("[DetectorAttach] Skipping PDA (not a detector)")
            return false
        end
    end
    
    -- Skip attachment during consumption montages
    if _G.SuppressItemAttachment then
        print("[DetectorAttach] Skipping attachment - consumption montage active")
        return false
    end
    
    local leftController = controllers.getController(Handed.Left)
    if not leftController then return false end
    
    if detector.AttachParent == leftController then
        -- FIX (2026-09-06): re-identify if this is a self-heal (currentDetectorName was lost to a
        -- desync but the detector never actually left the controller) - do NOT do this
        -- unconditionally, since loadProfile() replaces Config.detectorOffset/Rotation wholesale
        -- and would stomp live in-progress slider edits every check interval otherwise.
        if not currentDetectorName then
            currentDetectorName = getDetectorName(detector)
            loadProfile(currentDetectorName)
        end
        -- Even if already attached, ensure transform is up to date (Real-time editing)
         uevrUtils.set_component_relative_transform(detector, Config.detectorOffset, Config.detectorRotation)
        -- EXPERIMENT (2026-09-06): same ForegroundFOVEnabled=0 fix as hands/weapon/reload-proxies
        -- (see Entry.lua's applyForegroundFOVFixExperiment). Live-confirmed via MCP: detector
        -- materials (MI_detector_*, MI_DetectorGlass, etc.) ship at the native ForegroundFOVEnabled=1
        -- despite the detector being a re-parented world item, not a real first-person asset - same
        -- wrong-default class as the weapon/hands materials. Cheap/idempotent, safe to reapply here
        -- every check interval alongside the transform refresh.
        uevrUtils.fixMeshFOV(detector, "ForegroundFOVEnabled", 0.0, true, false, false)
        fixDetectorVisibility(detector)
        return true
    end
    
    -- Identify
    currentDetectorName = getDetectorName(detector)
    loadProfile(currentDetectorName)

    -- Store original scale
    local originalScale = {
        X = detector.RelativeScale3D.X,
        Y = detector.RelativeScale3D.Y,
        Z = detector.RelativeScale3D.Z
    }
    
    -- Detach and attach to controller
    detector:DetachFromParent(false, false)
    local success = controllers.attachComponentToController(Handed.Left, detector, "", 2, false)
    
    if success then
        -- Restore original scale
        detector.RelativeScale3D.X = originalScale.X
        detector.RelativeScale3D.Y = originalScale.Y
        detector.RelativeScale3D.Z = originalScale.Z
        
        detector.BoundsScale = 50.0
        detector.ForcedLodModel = 1
        uevrUtils.set_component_relative_transform(detector, Config.detectorOffset, Config.detectorRotation)
        -- EXPERIMENT (2026-09-06): see comment on the "already attached" branch above.
        uevrUtils.fixMeshFOV(detector, "ForegroundFOVEnabled", 0.0, true, false, false)
        fixDetectorVisibility(detector)
        print("[DetectorAttach] Attached " .. currentDetectorName .. " to left controller.")
    end
    
    return success
end

--------------------------------------------------------------------------------
-- Fast tick-based check
--------------------------------------------------------------------------------
-- Start Interface for Entry.lua
-- PERF (2026-09-08): built once at load instead of every tick. The closures read
-- currentDetector/currentDetectorName by upvalue, so they always see live values.
_G.DetectorSystem = {
    GetCurrentDetector = function() return currentDetector end,
    GetCurrentDetectorName = function() return currentDetectorName end,
    RefreshTransform = function()
        -- Re-resolve if currentDetector desynced, rather than no-op'ing until the next
        -- periodic check (up to CHECK_INTERVAL later) picks it back up.
        if not (currentDetector and UEVR_UObjectHook.exists(currentDetector)) then
            currentDetector = findAttachedDetectorComponent()
        end
        if currentDetector and UEVR_UObjectHook.exists(currentDetector) then
             uevrUtils.set_component_relative_transform(currentDetector, Config.detectorOffset, Config.detectorRotation)
        end
    end
}
-- End Interface

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
    lastCheckTime = lastCheckTime + delta
    
    if lastCheckTime < CHECK_INTERVAL then
         -- Real-time update for UI editing
         if currentDetector and UEVR_UObjectHook.exists(currentDetector) then
             -- Only update if values changed? Or every frame to be smooth?
             -- Optimally only on change, but Entry.lua will handle the UI change detection.
             -- Here we just ensure it respects the global config if it's attached.
             -- To save perf, we only do this if a flag is set? 
             -- For now, let's trust Entry.lua to call RefreshTransform() when UI changes.
         end
        return
    end
    lastCheckTime = 0
    
    -- Quick validation
    if currentDetector then
        if not UEVR_UObjectHook.exists(currentDetector) then
            currentDetector = nil
            currentDetectorName = nil
            gameState.isDetectorEquipped = false
            return
        end
        
        local leftController = controllers.getController(Handed.Left)
        if not leftController then
            -- FIX (2026-09-06): controller transiently missing (e.g. being recreated by
            -- controllers.lua's auto-creation monitor) - do NOT conclude "detached" from this
            -- alone, or currentDetector gets wiped even though the detector never actually left
            -- the controller, permanently breaking RefreshTransform() until a drop/re-grab.
            return
        end
        if currentDetector.AttachParent == leftController then
            return -- Still attached
        end

        currentDetector = nil
        currentDetectorName = nil
        gameState.isDetectorEquipped = false
        print("[DetectorAttach] Detector detached/unequipped")
    end

    -- Search: an unattached detector on the pawn's holster mesh, OR (self-heal) one that's already
    -- grabbed but whose currentDetector tracking was lost above.
    local detector = findDetectorComponent() or findAttachedDetectorComponent()
    if detector then
        currentDetector = detector
        gameState.isDetectorEquipped = true
        attachDetector(detector)
    end
end)

print("[DetectorAttach] Loaded - checking every " .. CHECK_INTERVAL .. "s")