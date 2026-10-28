-- Body gesture zone debug view + live tuning (2026-09-21).
--
-- The body zones (gestures/bodyzone.lua, gestures/bodyzonesitting.lua) are axis-aligned boxes in
-- an HMD-relative, YAW-ONLY frame: gestures/locationgesture.lua takes (hand - hmd) in world space
-- and rotates it by -hmdYaw, so X = forward, Y = right, Z = up, in cm, and head pitch/roll are
-- deliberately ignored. This module draws exactly that frame:
--   * one anchor SceneComponent, moved every tick to the gesture layer's HMD proxy location with
--     rotation (0, hmdYaw, 0) - the SAME source the gesture math reads, so if that proxy is ever
--     stale again the markers will visibly float away from your head instead of lying to you;
--   * a small sphere at the centre of every body zone of the active set (standing / sitting);
--   * a full-size box for the zone currently selected in the dev panel.
-- The zone tables are mutated in place (BodyZoneGesture:EvaluateInternal reads minX..maxZ every
-- tick), so slider edits take effect immediately. "Save" persists them to settings.json under
-- Config.bodyZoneOverrides[set][zoneKey]; "Reset" restores the values the zone files shipped with.
local utils = require("common.utils")
local uevrUtils = require("libs/uevr_utils")
local hands = require("libs/hands")
local motionControllerActors = require("gestures.motioncontrolleractors")
local LocationGestures = require("gestures.locationgesture")
local GripGesture = require("stalker2.gripgesture")
local zonesStanding = require("gestures.bodyzone")
local zonesSitting = require("gestures.bodyzonesitting")
require("Config.CONFIG")

local M = {}

local BASE_ZONES = {
    { key = "rightShoulderZone", label = "Right Shoulder" },
    { key = "leftShoulderZone",  label = "Left Shoulder" },
    { key = "headZone",          label = "Head" },
    { key = "rightHipZone",      label = "Right Hip" },
    { key = "leftHipZone",       label = "Left Hip" },
    { key = "leftChestZone",     label = "Left Chest" },
    { key = "rightChestZone",    label = "Right Chest" },
    { key = "lowerBackZone",     label = "Lower Back" },
}
local BASE_ZONE_LABELS = {}
for i, z in ipairs(BASE_ZONES) do BASE_ZONE_LABELS[i] = z.label end
local HAND_MODE_LABELS = { "Both hands", "Right hand only", "Left hand only" }
local BOUND_FIELDS = { "minX", "maxX", "minY", "maxY", "minZ", "maxZ" }

local MARKER_DIAMETER_CM = 6.0 -- BasicShapes meshes are 100 uu across
local RECREATE_COOLDOWN = 1.0  -- seconds between attempts to (re)build the visuals

local function zoneSets()
    return { standing = zonesStanding, sitting = zonesSitting }
end

local function activeSetName()
    return Config.sittingExperience and "sitting" or "standing"
end

local function copyBounds(zone)
    local t = {}
    for _, f in ipairs(BOUND_FIELDS) do t[f] = zone[f] end
    return t
end

local function writeBounds(zone, bounds)
    for _, f in ipairs(BOUND_FIELDS) do
        if type(bounds[f]) == "number" then zone[f] = bounds[f] end
    end
end

-- Shipped values, captured before any override is applied.
local defaults = {}
for setName, set in pairs(zoneSets()) do
    defaults[setName] = {}
    for key, zone in pairs(set) do
        if type(zone) == "table" and zone.minX ~= nil then
            defaults[setName][key] = copyBounds(zone)
        end
    end
end

function M.applySavedOverrides()
    if type(Config.bodyZoneOverrides) ~= "table" then Config.bodyZoneOverrides = {} end
    for setName, set in pairs(zoneSets()) do
        local saved = Config.bodyZoneOverrides[setName]
        if type(saved) == "table" then
            for key, bounds in pairs(saved) do
                if type(set[key]) == "table" and type(bounds) == "table" then
                    writeBounds(set[key], bounds)
                end
            end
        end
    end
end
M.applySavedOverrides()

---------------------------------------------------------------------------------------------------
-- Visuals
---------------------------------------------------------------------------------------------------
local visible = false
local selectedZoneIndex = 1
local handModeIndex = 1
local anchor = nil
local markers = {}       -- [zoneKey] = StaticMeshComponent (sphere)
local selectionBox = nil -- StaticMeshComponent (cube) for the selected zone
local builtForSet = nil
local lastBuildAttempt = 0
local cachedSphereMesh, cachedCubeMesh = nil, nil

local function forgetVisuals()
    anchor = nil
    markers = {}
    selectionBox = nil
    builtForSet = nil
end

local function loadBasicShape(path)
    local mesh = nil
    pcall(function()
        uevrUtils.getLoadedAsset(path)
        mesh = uevr.api:find_uobject(path)
    end)
    return mesh
end

local function getSphereMesh()
    if cachedSphereMesh == nil then cachedSphereMesh = loadBasicShape("StaticMesh /Engine/BasicShapes/Sphere.Sphere") end
    return cachedSphereMesh
end

local function getCubeMesh()
    if cachedCubeMesh == nil then cachedCubeMesh = loadBasicShape("StaticMesh /Engine/BasicShapes/Cube.Cube") end
    return cachedCubeMesh
end

-- Debug material: a grey, see-through surface. UMG's 3D-widget material is the one translucent
-- engine material that is always cooked into a shipping build; with OpacityFromTexture = 0 its
-- opacity is just TintColorAndOpacity.a, which makes it a generic tintable translucent shader.
-- Depth is fine with a plain engine material because Entry.lua forces ForegroundFOVEnabled = 0 on
-- the VR hands and weapon (see stalker2-depth-rendering-fixes), i.e. everything renders with the
-- normal projection. Fallbacks, in order: opaque grey BasicShapeMaterial, then slot 0 of the
-- left-hand mesh (the old look).
local DEBUG_MATERIAL_PATHS = {
    "MaterialInstanceConstant /Engine/EngineMaterials/Widget3DPassThrough_Translucent.Widget3DPassThrough_Translucent",
    "Material /Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial",
}
local MARKER_ALPHA = 0.75 -- small spheres: mostly solid so they are easy to spot
local BOX_ALPHA = 0.22    -- selected-zone box: see-through so it never blocks the view
local GREY = 0.45
local cachedDebugMaterial = nil

local function getDebugMaterial()
    if cachedDebugMaterial == nil then
        cachedDebugMaterial = false
        for _, path in ipairs(DEBUG_MATERIAL_PATHS) do
            local material = nil
            pcall(function()
                uevrUtils.getLoadedAsset(path)
                material = uevr.api:find_uobject(path)
            end)
            if material ~= nil then
                cachedDebugMaterial = material
                break
            end
        end
    end
    if cachedDebugMaterial then return cachedDebugMaterial end

    local material = nil
    pcall(function()
        local handMesh = hands.getHandComponent(Handed.Left)
        if handMesh ~= nil then
            local materials = handMesh:GetMaterials()
            if materials ~= nil then material = materials[1] end
        end
    end)
    return material
end

-- Gives the component its own dynamic instance and tints it grey at the given opacity. Every step
-- is best-effort: a parameter the material doesn't have is simply ignored by the engine.
local function applyDebugMaterial(component, alpha)
    local material = getDebugMaterial()
    if material == nil then return end
    pcall(function()
        local mid = component:CreateAndSetMaterialInstanceDynamicFromMaterial(0, material)
        if mid == nil then
            component:SetMaterial(0, material)
            return
        end
        pcall(function() mid:SetScalarParameterValue(uevrUtils.fname_from_string("OpacityFromTexture"), 0.0) end)
        pcall(function()
            mid:SetVectorParameterValue(uevrUtils.fname_from_string("TintColorAndOpacity"), uevrUtils.color_from_rgba(GREY, GREY, GREY, alpha))
        end)
        pcall(function()
            mid:SetVectorParameterValue(uevrUtils.fname_from_string("Color"), uevrUtils.color_from_rgba(GREY, GREY, GREY, alpha))
        end)
    end)
end

local function setShown(component, shown)
    pcall(function()
        component:SetHiddenInGame(not shown, false)
        component:SetVisibility(shown, false)
    end)
end

local function createMesh(pawn, mesh, alpha)
    local smClass = utils.find_required_object("Class /Script/Engine.StaticMeshComponent")
    local component = uevr.api:add_component_by_class(pawn, smClass)
    component:SetStaticMesh(mesh)
    component:SetCollisionEnabled(0)
    pcall(function() component:SetCastShadow(false) end)
    component:K2_AttachToComponent(anchor, uevrUtils.fname_from_string("None"), 0, 0, 0, false)
    applyDebugMaterial(component, alpha)
    return component
end

local function placeMarker(component, zone)
    component.RelativeLocation.X = (zone.minX + zone.maxX) / 2
    component.RelativeLocation.Y = (zone.minY + zone.maxY) / 2
    component.RelativeLocation.Z = (zone.minZ + zone.maxZ) / 2
    local s = MARKER_DIAMETER_CM / 100.0
    component.RelativeScale3D.X = s
    component.RelativeScale3D.Y = s
    component.RelativeScale3D.Z = s
end

local function placeBox(component, zone)
    component.RelativeLocation.X = (zone.minX + zone.maxX) / 2
    component.RelativeLocation.Y = (zone.minY + zone.maxY) / 2
    component.RelativeLocation.Z = (zone.minZ + zone.maxZ) / 2
    component.RelativeScale3D.X = math.max(0.01, (zone.maxX - zone.minX) / 100.0)
    component.RelativeScale3D.Y = math.max(0.01, (zone.maxY - zone.minY) / 100.0)
    component.RelativeScale3D.Z = math.max(0.01, (zone.maxZ - zone.minZ) / 100.0)
end

-- The zone whose numbers the sliders show: RH variant unless "Left hand only" is selected.
local function primaryZoneKey()
    local base = BASE_ZONES[selectedZoneIndex].key
    return base .. (handModeIndex == 3 and "LH" or "RH")
end

local function editedZoneKeys()
    local base = BASE_ZONES[selectedZoneIndex].key
    if handModeIndex == 2 then return { base .. "RH" } end
    if handModeIndex == 3 then return { base .. "LH" } end
    return { base .. "RH", base .. "LH" }
end

local function buildVisuals()
    local pawn = uevr.api:get_local_pawn(0)
    if pawn == nil then return false end
    local sphere, cube = getSphereMesh(), getCubeMesh()
    if sphere == nil or cube == nil then return false end

    local sceneClass = utils.find_required_object("Class /Script/Engine.SceneComponent")
    anchor = uevr.api:add_component_by_class(pawn, sceneClass)
    if anchor == nil then return false end
    anchor:SetAbsolute(true, true, true)

    local setName = activeSetName()
    local set = zoneSets()[setName]
    -- One marker per distinct RH/LH pair position is enough for orientation, but the two
    -- variants can legitimately differ (head zone), so every zone gets its own.
    for key, zone in pairs(set) do
        if type(zone) == "table" and zone.minX ~= nil then
            local marker = createMesh(pawn, sphere, MARKER_ALPHA)
            placeMarker(marker, zone)
            markers[key] = marker
        end
    end
    selectionBox = createMesh(pawn, cube, BOX_ALPHA)
    builtForSet = setName
    return true
end

function M.setVisible(value)
    visible = value == true
    if not visible then
        for _, marker in pairs(markers) do setShown(marker, false) end
        if selectionBox ~= nil then setShown(selectionBox, false) end
    end
end

function M.isVisible()
    return visible
end

-- World references die with the level; never touch them afterwards (see the stale-object notes
-- in the stalker2-gotchas skill), just forget them and rebuild on demand.
function M.onLevelChange()
    forgetVisuals()
end

function M.destroy()
    pcall(function()
        for _, marker in pairs(markers) do
            if marker.K2_DestroyComponent ~= nil then marker:K2_DestroyComponent(marker) end
        end
        if selectionBox ~= nil and selectionBox.K2_DestroyComponent ~= nil then selectionBox:K2_DestroyComponent(selectionBox) end
        if anchor ~= nil and anchor.K2_DestroyComponent ~= nil then anchor:K2_DestroyComponent(anchor) end
    end)
    forgetVisuals()
end

-- Call once per engine tick (cheap no-op while the debug view is off).
function M.update()
    if not visible then return end

    if anchor == nil or builtForSet ~= activeSetName() then
        local now = os.clock()
        if now - lastBuildAttempt < RECREATE_COOLDOWN then return end
        lastBuildAttempt = now
        if anchor ~= nil then M.destroy() end
        local ok, built = pcall(buildVisuals)
        if not ok or not built then
            forgetVisuals()
            return
        end
    end

    local ok = pcall(function()
        local loc = motionControllerActors:GetLocationByIndex(0)
        local rot = motionControllerActors:GetRotationByIndex(0)
        if loc == nil or rot == nil then return end
        anchor:K2_SetWorldLocationAndRotation(uevrUtils.vector(loc.x, loc.y, loc.z), uevrUtils.rotator(0, rot.y, 0), false, reusable_hit_result, false)

        local set = zoneSets()[builtForSet]
        for key, marker in pairs(markers) do
            placeMarker(marker, set[key])
            setShown(marker, true)
        end
        local selected = set[primaryZoneKey()]
        if selected ~= nil then
            placeBox(selectionBox, selected)
            setShown(selectionBox, true)
        end
    end)
    if not ok then forgetVisuals() end -- a component died under us: rebuild after the cooldown
end

---------------------------------------------------------------------------------------------------
-- Dev panel
---------------------------------------------------------------------------------------------------
local function saveOverrides()
    if type(Config.bodyZoneOverrides) ~= "table" then Config.bodyZoneOverrides = {} end
    for setName, set in pairs(zoneSets()) do
        local out = {}
        for key, shipped in pairs(defaults[setName]) do
            local zone = set[key]
            local changed = false
            for _, f in ipairs(BOUND_FIELDS) do
                if zone[f] ~= shipped[f] then changed = true end
            end
            if changed then out[key] = copyBounds(zone) end
        end
        Config.bodyZoneOverrides[setName] = out
    end
    Config:markDirty()
    Config:save()
end

local function activeZoneNames(locationGestureZonesHandSuffix)
    local names = {}
    local set = zoneSets()[activeSetName()]
    for _, base in ipairs(BASE_ZONES) do
        local zone = set[base.key .. locationGestureZonesHandSuffix]
        if zone ~= nil and zone.isActive then names[#names + 1] = base.label end
    end
    return #names > 0 and table.concat(names, ", ") or "-"
end

-- Grip-gesture timing: tolerances + a log of the last squeezes, so a missed quick grab says why.
local function drawTimingUI()
    imgui.separator()
    imgui.text("Grip gesture timing (seconds). HIT/MISS lines appear when you release the grip.")
    if type(Config.gestureTiming) ~= "table" then Config.gestureTiming = {} end

    local e1, early = imgui.drag_float("Squeeze-before-zone grace##griptiming", GripGesture.GRIP_EARLY_GRACE, 0.01, 0.0, 1.0)
    if e1 then GripGesture.GRIP_EARLY_GRACE = early; Config.gestureTiming.gripEarlyGrace = early end
    local e2, exit = imgui.drag_float("Squeeze-after-leaving-zone grace##griptiming", GripGesture.ZONE_EXIT_GRACE, 0.01, 0.0, 1.0)
    if e2 then GripGesture.ZONE_EXIT_GRACE = exit; Config.gestureTiming.zoneExitGrace = exit end
    local e3, hold = imgui.drag_float("Minimum key hold##griptiming", GripGesture.MIN_KEY_HOLD, 0.01, 0.0, 0.5)
    if e3 then GripGesture.MIN_KEY_HOLD = hold; Config.gestureTiming.minKeyHold = hold end
    local e4, prime = imgui.drag_float("Primer key lead time (0 = off)##griptiming", GripGesture.KEY_PRIME_DELAY, 0.01, 0.0, 0.5)
    if e4 then GripGesture.KEY_PRIME_DELAY = prime; Config.gestureTiming.keyPrimeDelay = prime end
    local e5, retry = imgui.checkbox("Retry weapon-slot key if the game ignored it##griptiming", GripGesture.KEY_RETRY)
    if e5 then GripGesture.KEY_RETRY = retry; Config.gestureTiming.keyRetry = retry end
    local e6, quiet = imgui.checkbox("Quiet sticks while a gesture key is sent (fixes gestures while moving)##griptiming", GripGesture.KEY_QUIET_STICKS)
    if e6 then GripGesture.KEY_QUIET_STICKS = quiet; Config.gestureTiming.keyQuietSticks = quiet end

    if imgui.button("Save Timing##griptiming") then
        Config:markDirty()
        Config:save()
    end
    if imgui.button("Clear Log##griptiming") then
        for i = #GripGesture.debugLog, 1, -1 do GripGesture.debugLog[i] = nil end
    end
    if #GripGesture.debugLog == 0 then
        imgui.text("(no squeezes logged yet)")
    end
    for _, line in ipairs(GripGesture.debugLog) do
        imgui.text(line)
    end
end

-- Draws the controls INSIDE an already-open imgui tree node.
function M.drawUI()
    local setName = activeSetName()
    local set = zoneSets()[setName]

    drawTimingUI()

    imgui.separator()
    imgui.text("Body zones (" .. setName .. " set). Frame: X forward, Y right, Z up,")
    imgui.text("in cm from the headset, yaw only (head pitch/roll ignored).")

    local visChanged, newVisible = imgui.checkbox("Show body zone markers + selected zone box", visible)
    if visChanged then M.setVisible(newVisible) end

    local rh, lh = LocationGestures.RightHand, LocationGestures.LeftHand
    if rh ~= nil and rh.location ~= nil then
        imgui.text(string.format("Right hand: X %.1f  Y %.1f  Z %.1f   in: %s", rh.location.x, rh.location.y, rh.location.z, activeZoneNames("RH")))
    end
    if lh ~= nil and lh.location ~= nil then
        imgui.text(string.format("Left hand:  X %.1f  Y %.1f  Z %.1f   in: %s", lh.location.x, lh.location.y, lh.location.z, activeZoneNames("LH")))
    end

    local zoneChanged, newZoneIndex = imgui.combo("Zone##bodyzone", selectedZoneIndex, BASE_ZONE_LABELS)
    if zoneChanged then selectedZoneIndex = newZoneIndex end
    local handChanged, newHandIndex = imgui.combo("Applies to##bodyzone", handModeIndex, HAND_MODE_LABELS)
    if handChanged then handModeIndex = newHandIndex end

    local primary = set[primaryZoneKey()]
    if primary == nil then
        imgui.text("This zone does not exist in the " .. setName .. " set.")
        return
    end

    local cx, cy, cz = (primary.minX + primary.maxX) / 2, (primary.minY + primary.maxY) / 2, (primary.minZ + primary.maxZ) / 2
    local sx, sy, sz = primary.maxX - primary.minX, primary.maxY - primary.minY, primary.maxZ - primary.minZ

    local c1, ncx = imgui.drag_float("Centre X (forward)##bodyzone", cx, 0.25, -150.0, 150.0)
    local c2, ncy = imgui.drag_float("Centre Y (right)##bodyzone", cy, 0.25, -150.0, 150.0)
    local c3, ncz = imgui.drag_float("Centre Z (up)##bodyzone", cz, 0.25, -200.0, 150.0)
    local s1, nsx = imgui.drag_float("Size X##bodyzone", sx, 0.25, 2.0, 200.0)
    local s2, nsy = imgui.drag_float("Size Y##bodyzone", sy, 0.25, 2.0, 200.0)
    local s3, nsz = imgui.drag_float("Size Z##bodyzone", sz, 0.25, 2.0, 200.0)

    if c1 or c2 or c3 or s1 or s2 or s3 then
        -- Apply as DELTAS so "Both hands" keeps any intentional RH/LH asymmetry (head zone).
        local dcx, dcy, dcz = (c1 and ncx or cx) - cx, (c2 and ncy or cy) - cy, (c3 and ncz or cz) - cz
        local dsx, dsy, dsz = (s1 and nsx or sx) - sx, (s2 and nsy or sy) - sy, (s3 and nsz or sz) - sz
        for _, key in ipairs(editedZoneKeys()) do
            local zone = set[key]
            if zone ~= nil then
                zone.minX = zone.minX + dcx - dsx / 2; zone.maxX = zone.maxX + dcx + dsx / 2
                zone.minY = zone.minY + dcy - dsy / 2; zone.maxY = zone.maxY + dcy + dsy / 2
                zone.minZ = zone.minZ + dcz - dsz / 2; zone.maxZ = zone.maxZ + dcz + dsz / 2
            end
        end
    end

    imgui.text(string.format("Bounds: X %.1f..%.1f  Y %.1f..%.1f  Z %.1f..%.1f", primary.minX, primary.maxX, primary.minY, primary.maxY, primary.minZ, primary.maxZ))

    if imgui.button("Save Zones##bodyzone") then saveOverrides() end
    if imgui.button("Reset This Zone to Default##bodyzone") then
        for _, key in ipairs(editedZoneKeys()) do
            if set[key] ~= nil and defaults[setName][key] ~= nil then writeBounds(set[key], defaults[setName][key]) end
        end
        saveOverrides()
    end
    if imgui.button("Reset ALL Body Zones to Default##bodyzone") then
        for name, zones in pairs(zoneSets()) do
            for key, shipped in pairs(defaults[name]) do writeBounds(zones[key], shipped) end
        end
        saveOverrides()
    end
end

return M
