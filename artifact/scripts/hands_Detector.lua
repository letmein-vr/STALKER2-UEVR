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
        -- Even if already attached, ensure transform is up to date (Real-time editing)
         uevrUtils.set_component_relative_transform(detector, Config.detectorOffset, Config.detectorRotation)
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
        print("[DetectorAttach] Attached " .. currentDetectorName .. " to left controller.")
    end
    
    return success
end

--------------------------------------------------------------------------------
-- Fast tick-based check
--------------------------------------------------------------------------------
uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
    -- Start Interface for Entry.lua
    _G.DetectorSystem = {
        GetCurrentDetector = function() return currentDetector end,
        GetCurrentDetectorName = function() return currentDetectorName end,
        RefreshTransform = function() 
            if currentDetector and UEVR_UObjectHook.exists(currentDetector) then
                 uevrUtils.set_component_relative_transform(currentDetector, Config.detectorOffset, Config.detectorRotation)
            end
        end
    }
    -- End Interface

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
        if leftController and currentDetector.AttachParent == leftController then
            return -- Still attached
        end
        
        currentDetector = nil
        currentDetectorName = nil
        gameState.isDetectorEquipped = false
        print("[DetectorAttach] Detector detached/unequipped")
    end
    
    -- Search
    local detector = findDetectorComponent()
    if detector then
        currentDetector = detector
        gameState.isDetectorEquipped = true
        attachDetector(detector)
    end
end)

print("[DetectorAttach] Loaded - checking every " .. CHECK_INTERVAL .. "s")