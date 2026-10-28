-- VR binoculars (2026-09-22, per-model profiles 2026-09-23).
--
-- The flat game's binocular view is a whole-camera FOV change plus a post-process vignette
-- (CameraManager MID_MI_PP_Binoculars_01/02/03). In VR that would zoom the entire headset view and
-- amplify head rotation, so the native "raise" is never triggered (the left trigger is inert while
-- the binoculars are held - confirmed live). Instead the binoculars are treated as a two-lens
-- picture-in-picture optic:
--   * ONE SceneCaptureComponent2D anchored at bone `jnt_offset` of the WeaponInHandsMesh, looking
--     down the binoculars' axis, capturing into one render target (same capture recipe as
--     Base/scope.lua - every 5.5.4 fix in there is deliberately repeated here);
--   * TWO spawned cylinder discs at the eyepieces, both showing that render target. The game's own
--     binocular mesh is a single-material StaticMeshComponent with no lens slot, so nothing on it
--     is touched. Eyepiece anchors differ per model (see ANCHOR_CANDIDATES): DevBinocular_01 has
--     jnt_l_lens / jnt_r_lens, DevBinocular_02 has jnt_ring_01 / jnt_ring_02 (one per barrel, 7.7 cm
--     apart); anything else falls back to both discs on jnt_offset with a lateral separation.
--   * No "raise to eyes" mode: the discs are parented to the binoculars, so bringing them to the
--     face physically fills the view and lowering them shrinks it to a window. Never head-locked.
--   * Zoom = discrete capture-FOV steps (profile.zoomFOVs), R3 (right stick click) cycles
--     1 -> 2 -> 3 -> 1 while held, one short haptic per step.
--   * Gating: capture runs (bCaptureEveryFrame) while a lens is within sleepDistance of the HMD and
--     stops beyond it (discs just hold the last frame). Manual CaptureScene() from Lua is a no-op
--     on this build.
--
-- Tuning is PER MODEL: Config.binoculars.profiles[<skeletal asset name>] holds capture/disc
-- transforms, disc size, brightness and zoom steps. A model seen for the first time is seeded from
-- the top-level Config.binoculars values (which are the DevBinocular_01 tuning from 2026-09-23).
-- Global settings (enabled, sleepDistance, textureSize, screenPercentage, haptics) stay top-level.
--
-- Anatomy (memory: stalker2-binoculars-anatomy): the WeaponInHandsMesh component is recycled for
-- every weapon, so everything is keyed on the ASSET name, never the component address.
local utils = require("common.utils")
local uevrUtils = require("libs/uevr_utils")
local controllers = require("libs/controllers")
require("Config.CONFIG")

local M = {}

local ASSET_MATCH = "binocular"          -- lower-cased skeletal-asset name substring
local CAPTURE_BONE = "jnt_offset"
-- Eyepiece anchor pairs, tried in order; first pair whose bones both exist wins. If none does,
-- both discs go on FALLBACK_BONE with +-discSeparation/2 along the bone's Y axis.
local ANCHOR_CANDIDATES = {
    { "jnt_l_lens", "jnt_r_lens" },   -- DevBinocular_01
    { "jnt_ring_01", "jnt_ring_02" }, -- DevBinocular_02 (one per barrel)
}
local FALLBACK_BONE = "jnt_offset"
local CYLINDER_ASSET = "StaticMesh /Engine/BasicShapes/Cylinder.Cylinder"
local EMISSIVE_MATERIAL = "Material /Engine/EngineMaterials/EmissiveMeshMaterial.EmissiveMeshMaterial"

-- GPU objects must not be the first new scene primitive after a level load / inject (UEVR
-- FRenderTarget double-hook, see Base/scope.lua). The scope controller spawns a warmup sphere on
-- pawn-ready, so by the time a player has equipped binoculars that has run; we still keep a
-- defer, and a much longer one inside the post-load settling window.
local DEFER_FRAMES = 45
local SETTLE_DEFER_FRAMES = 300
local SETTLE_WINDOW_SECONDS = 10.0

local scriptLoadTime = os.clock()
local lastLevelChangeTime = os.clock()

-- Live state
local equippedMesh = nil        -- the WeaponInHandsMesh while binoculars are held
local equippedName = nil        -- skeletal asset short name, also the profile key
local anchorBones = nil         -- {leftBone, rightBone} resolved for this model
local anchorShared = false      -- true when both discs sit on the same (fallback) bone
local deferFrames = 0
local renderTarget = nil
local captureComponent = nil
local discs = {}                -- index -> StaticMeshComponent
local discMaterials = {}        -- index -> MID
local captureMode = nil         -- "near" | "far"
local tick = 0
local zoomArmed = true
local lastDistance = nil
local reusableHitResult = nil
local hitResultClass = nil
local lastFailure = nil

---------------------------------------------------------------------------------------------------
-- Config
---------------------------------------------------------------------------------------------------
-- Per-model tunables (live in Config.binoculars.profiles[name]; top-level copies are the seed).
local PROFILE_DEFAULTS = {
    captureLocation = { 0.0, 0.0, 0.0 },     -- relative to jnt_offset, cm
    captureRotation = { 0.0, 0.0, 90.0 },    -- Pitch, Yaw, Roll
    discLocation = { 0.0, 0.0, 0.0 },        -- relative to each anchor bone, cm (applies to both)
    discRotation = { 0.0, 90.0, 90.0 },      -- Pitch, Yaw, Roll (scope.lua cylinder orientation)
    -- Per-disc extras on top of the shared values (models whose two anchor bones are not
    -- symmetric, e.g. DevBinocular_02 where the left eyepiece sits further back than the right).
    discOffsetLeft = { 0.0, 0.0, 0.0 },
    discOffsetRight = { 0.0, 0.0, 0.0 },
    discRotOffsetLeft = { 0.0, 0.0, 0.0 },
    discRotOffsetRight = { 0.0, 0.0, 0.0 },
    discDiameter = 0.032,                    -- cylinder scale; 100 uu base -> 3.2 cm disc
    discDepth = 0.001,
    discSeparation = 6.8,                    -- cm between discs when they share one anchor bone
    brightness = 1.0,
    exposureBias = 0.0,                      -- capture AutoExposureBias override (stops, pre-tonemap)
    zoomFOVs = { 20.0, 10.0, 5.0 },          -- capture FOV per zoom step (deg), widest first
    zoomIndex = 1,
}
-- Global settings.
local GLOBAL_DEFAULTS = {
    enabled = true,
    sleepDistance = 60.0,                    -- cm lens->HMD: stop capturing beyond this
    textureSize = 512,
    screenPercentage = 50.0,
    haptics = true,
    profiles = {},
}

local function copyValue(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = copyValue(x) end
    return t
end

local function fillDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then target[k] = copyValue(v) end
    end
    return target
end

local function cfg()
    if type(Config.binoculars) ~= "table" then Config.binoculars = {} end
    local c = Config.binoculars
    fillDefaults(c, GLOBAL_DEFAULTS)
    if type(c.profiles) ~= "table" then c.profiles = {} end
    return c
end

-- Seed for a model seen for the first time: the top-level Config.binoculars values (legacy
-- single-model tuning) where present, else PROFILE_DEFAULTS.
local function seedProfile()
    local c = cfg()
    local p = {}
    for k, v in pairs(PROFILE_DEFAULTS) do
        if c[k] ~= nil then p[k] = copyValue(c[k]) else p[k] = copyValue(v) end
    end
    return p
end

-- Active profile: the equipped model's, else a scratch view of the seed for the dev panel.
local scratchProfile = nil
local function prof()
    local c = cfg()
    if equippedName then
        local p = c.profiles[equippedName]
        if p == nil then
            p = seedProfile()
            c.profiles[equippedName] = p
        end
        return fillDefaults(p, PROFILE_DEFAULTS)
    end
    if scratchProfile == nil then scratchProfile = seedProfile() end
    return scratchProfile
end

local function saveConfig()
    Config:markDirty()
    Config:save()
end

---------------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------------
local function log(msg)
    print("[Binoculars] " .. tostring(msg))
end

local function fail(msg)
    if msg ~= lastFailure then
        log(msg)
        lastFailure = msg
    end
end

-- Guarded property write (a UPROPERTY missing on this build throws straight out of the caller).
local function setp(obj, name, value)
    local ok, err = pcall(function() obj[name] = value end)
    if not ok then log("property write skipped: " .. tostring(name) .. " (" .. tostring(err) .. ")") end
    return ok
end

local function setpp(obj, name, value)
    local ok, err = pcall(function() obj.PostProcessSettings[name] = value end)
    if not ok then log("PostProcessSettings write skipped: " .. tostring(name) .. " (" .. tostring(err) .. ")") end
    return ok
end

local function valid(o)
    return o ~= nil and UEVR_UObjectHook.exists(o)
end

local function hitResult()
    if reusableHitResult ~= nil then return reusableHitResult end
    pcall(function()
        hitResultClass = hitResultClass or utils.find_required_object("ScriptStruct /Script/Engine.HitResult")
        if hitResultClass then reusableHitResult = StructObject.new(hitResultClass) end
    end)
    return reusableHitResult
end

local function setRelative(component, loc, rot)
    pcall(function() component:SetAbsolute(false, false, false) end)
    pcall(function() component.bUsePawnControlRotation = false end)
    pcall(function()
        component:K2_SetRelativeRotation(uevrUtils.rotator(rot[1], rot[2], rot[3]), false, hitResult(), false)
        component:K2_SetRelativeLocation(uevrUtils.vector(loc[1], loc[2], loc[3]), false, hitResult(), false)
    end)
end

local function attachToBone(component, parent, boneName)
    local ok = pcall(function()
        component:K2_AttachToComponent(
            parent,
            uevrUtils.fname_from_string(boneName),
            2,    -- SnapToTarget location
            2,    -- SnapToTarget rotation
            0,    -- KeepRelative scale
            false -- no weld
        )
    end)
    return ok
end

local function socketExists(mesh, name)
    local exists = false
    pcall(function() exists = mesh:DoesSocketExist(uevrUtils.fname_from_string(name)) == true end)
    return exists
end

-- Pick the eyepiece anchor bones for the equipped skeleton.
local function resolveAnchors(mesh)
    for _, pair in ipairs(ANCHOR_CANDIDATES) do
        if socketExists(mesh, pair[1]) and socketExists(mesh, pair[2]) then
            return { pair[1], pair[2] }, false
        end
    end
    return { FALLBACK_BONE, FALLBACK_BONE }, true
end

function M.isBinocularsName(name)
    if name == nil then return false end
    return string.find(string.lower(tostring(name)), ASSET_MATCH, 1, true) ~= nil
end

function M.isBinocularsMesh(mesh)
    if not valid(mesh) then return false end
    local name = nil
    pcall(function()
        local asset = mesh.SkeletalMesh or mesh.SkinnedAsset
        if asset then name = uevrUtils.getShortName(asset) end
    end)
    return M.isBinocularsName(name)
end

function M.isActive()
    return equippedMesh ~= nil
end

function M.hasComponents()
    return valid(captureComponent) and valid(discs[1]) and valid(discs[2])
end

---------------------------------------------------------------------------------------------------
-- Creation / destruction
---------------------------------------------------------------------------------------------------
local function destroyComponent(component)
    if valid(component) then
        pcall(function() component:K2_DestroyComponent(component) end)
    end
end

-- Order matters: capture first (it must never outlive its render target as an actively
-- capturing orphan), then the discs, then the render target reference.
local function destroyComponents()
    if valid(captureComponent) then
        setp(captureComponent, "bCaptureEveryFrame", false)
        setp(captureComponent, "bCaptureOnMovement", false)
        destroyComponent(captureComponent)
    end
    captureComponent = nil
    for i = 1, #discs do destroyComponent(discs[i]) end
    discs = {}
    discMaterials = {}
    renderTarget = nil
    captureMode = nil
end

local function forgetComponents()
    captureComponent = nil
    discs = {}
    discMaterials = {}
    renderTarget = nil
    captureMode = nil
end

local function createRenderTarget()
    local c = cfg()
    local rt = nil
    pcall(function()
        rt = uevrUtils.createRenderTarget2D({ width = c.textureSize, height = c.textureSize, format = 6 }) -- RTF_RGBA16f
    end)
    return rt
end

local function applyBrightness()
    local p = prof()
    for _, mid in ipairs(discMaterials) do
        if valid(mid) then
            pcall(function()
                mid:SetVectorParameterValue(uevrUtils.fname_from_string("Color"),
                    uevrUtils.color_from_rgba(p.brightness, p.brightness, p.brightness, 1.0))
            end)
        end
    end
end

local function createDisc(index, rt)
    pcall(function() uevrUtils.getLoadedAsset(CYLINDER_ASSET) end)
    local comp = uevrUtils.createStaticMeshComponent(CYLINDER_ASSET, { visible = false, collisionEnabled = false })
    if comp == nil then
        fail("failed to create lens disc " .. index)
        return nil
    end
    pcall(function() comp:SetCastShadow(false) end)
    setp(comp, "TranslucencySortPriority", 100)

    local mat = utils.find_required_object(EMISSIVE_MATERIAL)
    if mat then
        -- BlendMode MUST be 0 (Opaque) on UE 5.5 - see Base/scope.lua spawn_scope_plane.
        pcall(function() mat.BlendMode = 0; mat.TwoSided = 0 end)
        local mid = nil
        pcall(function() mid = comp:CreateDynamicMaterialInstance(0, mat, "binoculars_lens_material") end)
        if mid then
            pcall(function() mid:SetTextureParameterValue(uevrUtils.fname_from_string("LinearColor"), rt) end)
            discMaterials[index] = mid
        end
    end
    return comp
end

local function createCapture(rt)
    local c = cfg()
    local p = prof()
    local comp = uevrUtils.createSceneCaptureComponent({ visible = false, collisionEnabled = false })
    if comp == nil then
        fail("failed to create scene capture")
        return nil
    end
    -- Disable per-frame capture FIRST so a failure part-way through can never leave an
    -- actively-capturing orphan behind.
    setp(comp, "bCaptureEveryFrame", false)
    setp(comp, "bCaptureOnMovement", false)
    setp(comp, "TextureTarget", rt)
    setp(comp, "FOVAngle", p.zoomFOVs[p.zoomIndex] or p.zoomFOVs[1] or 20.0)
    setp(comp, "bUseRayTracingIfEnabled", false)
    setp(comp, "bAlwaysPersistRenderingState", true)
    setp(comp, "bEnableVolumetricCloudsCapture", false)
    setp(comp, "CaptureSource", 8) -- SCS_FinalColorHDR: tonemapped, carries auto-exposure

    setpp(comp, "bOverride_MotionBlurAmount", true)
    setpp(comp, "MotionBlurAmount", 0.0)
    setpp(comp, "bOverride_ScreenSpaceReflectionIntensity", true)
    setpp(comp, "ScreenSpaceReflectionIntensity", 0.0)
    setpp(comp, "bOverride_AmbientOcclusionIntensity", true)
    setpp(comp, "AmbientOcclusionIntensity", 0.0)
    setpp(comp, "bOverride_BloomIntensity", true)
    setpp(comp, "BloomIntensity", 0.0)
    setpp(comp, "bOverride_LensFlareIntensity", true)
    setpp(comp, "LensFlareIntensity", 0.0)
    setpp(comp, "bOverride_VignetteIntensity", true)
    setpp(comp, "VignetteIntensity", 0.0)
    -- Exposure bias: pre-tonemap brightness in stops (the disc Color multiplier only scales the
    -- already-tonemapped image and clips to white).
    setpp(comp, "bOverride_AutoExposureBias", true)
    setpp(comp, "AutoExposureBias", tonumber(p.exposureBias) or 0.0)

    local sp = math.max(25.0, math.min(100.0, tonumber(c.screenPercentage) or 50.0))
    if sp < 100.0 then
        setpp(comp, "bOverride_ScreenPercentage", true)
        setpp(comp, "ScreenPercentage", sp)
    end
    setpp(comp, "bOverride_DynamicGlobalIlluminationMethod", true)
    setpp(comp, "DynamicGlobalIlluminationMethod", 0)
    setpp(comp, "bOverride_ReflectionMethod", true)
    setpp(comp, "ReflectionMethod", 0)

    -- MUST be visible: a SceneCaptureComponent2D with bVisible=false never captures, the render
    -- target stays black. (Confirmed 2026-09-23 by diffing against the working scope capture -
    -- the ONLY differing flag was bVisible. Base/scope.lua creates its capture hidden too but
    -- flips it visible once the scope activates.)
    pcall(function() comp:SetVisibility(true) end)
    return comp
end

local function applyDiscTransforms()
    local p = prof()
    for i, disc in ipairs(discs) do
        if valid(disc) then
            local extraLoc = (i == 1) and p.discOffsetLeft or p.discOffsetRight
            local extraRot = (i == 1) and p.discRotOffsetLeft or p.discRotOffsetRight
            local loc = {
                p.discLocation[1] + extraLoc[1],
                p.discLocation[2] + extraLoc[2],
                p.discLocation[3] + extraLoc[3],
            }
            local rot = {
                p.discRotation[1] + extraRot[1],
                p.discRotation[2] + extraRot[2],
                p.discRotation[3] + extraRot[3],
            }
            if anchorShared then
                -- both discs on one bone: spread them along the bone's Y (lateral) axis
                loc[2] = loc[2] + (i == 1 and -0.5 or 0.5) * (p.discSeparation or 6.8)
            end
            setRelative(disc, loc, rot)
            uevrUtils.set_component_relative_scale(disc, { p.discDiameter, p.discDiameter, p.discDepth })
        end
    end
end

local function applyCaptureTransform()
    local p = prof()
    if valid(captureComponent) then
        setRelative(captureComponent, p.captureLocation, p.captureRotation)
    end
end

local function applyExposure()
    local p = prof()
    if valid(captureComponent) then
        setpp(captureComponent, "bOverride_AutoExposureBias", true)
        setpp(captureComponent, "AutoExposureBias", tonumber(p.exposureBias) or 0.0)
    end
end

local function applyZoom()
    local p = prof()
    if p.zoomIndex < 1 then p.zoomIndex = 1 end
    if p.zoomIndex > #p.zoomFOVs then p.zoomIndex = #p.zoomFOVs end
    if valid(captureComponent) then
        setp(captureComponent, "FOVAngle", p.zoomFOVs[p.zoomIndex])
    end
end

local function createComponents()
    if not valid(equippedMesh) then return false end
    -- NOTE: bRegistered is NOT a reflected property on this build (reads nil); Base/scope.lua's
    -- "registered" check only tests pcall's success flag, so it was never a real gate either.
    -- The deferred countdown is what keeps creation clear of the equip edge.

    anchorBones, anchorShared = resolveAnchors(equippedMesh)

    local rt = createRenderTarget()
    if rt == nil then
        fail("render target creation failed")
        return false
    end
    renderTarget = rt

    for i = 1, 2 do
        local disc = createDisc(i, rt)
        if disc == nil then
            destroyComponents()
            return false
        end
        discs[i] = disc
        if not attachToBone(disc, equippedMesh, anchorBones[i]) then
            fail("attach to " .. anchorBones[i] .. " failed")
            destroyComponents()
            return false
        end
    end
    applyDiscTransforms()
    applyBrightness()

    local cap = createCapture(rt)
    if cap == nil then
        destroyComponents()
        return false
    end
    captureComponent = cap
    if not attachToBone(cap, equippedMesh, CAPTURE_BONE) then
        fail("attach capture to " .. CAPTURE_BONE .. " failed")
        destroyComponents()
        return false
    end
    applyCaptureTransform()
    applyZoom()

    for _, disc in ipairs(discs) do
        pcall(function() disc:SetVisibility(true) end)
    end
    captureMode = nil -- force the gating pass to apply capture flags
    lastFailure = nil
    log("components created for " .. tostring(equippedName) .. " (discs on " .. anchorBones[1] .. " / " .. anchorBones[2]
        .. (anchorShared and ", shared bone with separation" or "") .. ")")
    return true
end

---------------------------------------------------------------------------------------------------
-- Equip tracking
---------------------------------------------------------------------------------------------------
local function settleDefer()
    local now = os.clock()
    if (now - scriptLoadTime) < SETTLE_WINDOW_SECONDS or (now - lastLevelChangeTime) < SETTLE_WINDOW_SECONDS then
        return SETTLE_DEFER_FRAMES
    end
    return DEFER_FRAMES
end

local function beginEquip(mesh, name)
    equippedMesh = mesh
    equippedName = name
    anchorBones = nil
    anchorShared = false
    deferFrames = settleDefer()
    zoomArmed = true
    lastDistance = nil
    prof() -- make sure the profile exists (seeded on first sight of this model)
    log("equipped " .. tostring(name) .. ", creating in " .. deferFrames .. " frames")
end

local function endEquip()
    if equippedMesh ~= nil then log("unequipped") end
    destroyComponents()
    equippedMesh = nil
    equippedName = nil
    anchorBones = nil
    anchorShared = false
    deferFrames = 0
end

---------------------------------------------------------------------------------------------------
-- Capture gating
---------------------------------------------------------------------------------------------------
local function lensDistanceToHMD()
    if not controllers.hmdControllerExists() then
        pcall(controllers.createHMDController)
    end
    local head = controllers.getControllerLocation(2)
    if head == nil then return nil end
    local best = nil
    for _, disc in ipairs(discs) do
        if valid(disc) then
            local loc = nil
            pcall(function() loc = disc:K2_GetComponentLocation() end)
            if loc then
                local dx, dy, dz = head.X - loc.X, head.Y - loc.Y, head.Z - loc.Z
                local d = math.sqrt(dx * dx + dy * dy + dz * dz)
                if best == nil or d < best then best = d end
            end
        end
    end
    return best
end

-- Capture policy: bCaptureEveryFrame while the lenses are within sleepDistance of the HMD, off
-- beyond it (the discs then just hold the last frame). Manual CaptureScene() calls from Lua were
-- tried for a reduced-rate mid band and produced nothing on this build, so the only reliable
-- lever is the flag.
local function setCaptureMode(mode)
    if mode == captureMode then return end
    captureMode = mode
    if not valid(captureComponent) then return end
    setp(captureComponent, "bCaptureEveryFrame", mode ~= "far")
end

local function updateGating()
    local c = cfg()
    -- Distance sampled at ~10 Hz; the flag only flips on a band change.
    if tick % 6 ~= 0 then return end
    local d = lensDistanceToHMD()
    lastDistance = d
    if d == nil then
        setCaptureMode("near") -- no HMD fix: never leave the lenses dead
    elseif d < c.sleepDistance then
        setCaptureMode("near")
    else
        setCaptureMode("far")
    end
end

---------------------------------------------------------------------------------------------------
-- Public per-tick entry point. weaponMesh/weaponName are Entry.lua's already-resolved values.
---------------------------------------------------------------------------------------------------
function M.update(weaponMesh, weaponName, inMenu)
    tick = tick + 1
    local c = cfg()

    local isBinos = c.enabled and weaponMesh ~= nil and M.isBinocularsName(weaponName)
    if isBinos and not valid(weaponMesh) then isBinos = false end

    if isBinos then
        -- Model swap on the recycled component shows up as a NAME change with the same mesh.
        if equippedMesh ~= weaponMesh or equippedName ~= weaponName then
            endEquip()
            beginEquip(weaponMesh, weaponName)
        end
    else
        if equippedMesh ~= nil then endEquip() end
        return
    end

    if inMenu then return end -- world frozen: don't count down or touch components

    -- A component died under us (level change, pawn rebuild): drop references and re-arm.
    if (captureComponent ~= nil or #discs > 0) and not M.hasComponents() then
        log("component lost, rebuilding")
        destroyComponents()
        deferFrames = settleDefer()
    end

    if not M.hasComponents() then
        if deferFrames > 0 then
            deferFrames = deferFrames - 1
            return
        end
        if not createComponents() then
            deferFrames = 60 -- retry in a second
        end
        return
    end

    updateGating()
end

---------------------------------------------------------------------------------------------------
-- Zoom input: R3 (right stick click) cycles the zoom steps 1 -> 2 -> 3 -> 1 while the binoculars
-- are held. Edge-triggered on the press, and the button is swallowed so the game never sees it.
-- (Right-stick up/down was the first attempt but did not register in-headset, 2026-09-23.)
---------------------------------------------------------------------------------------------------
local RIGHT_THUMB = XINPUT_GAMEPAD_RIGHT_THUMB or 0x0080
function M.on_xinput_get_state(state)
    if equippedMesh == nil or state == nil then return end
    local c = cfg()
    local p = prof()
    local pressed = uevrUtils.isButtonPressed(state, RIGHT_THUMB)
    if pressed then
        if zoomArmed then
            zoomArmed = false
            p.zoomIndex = p.zoomIndex + 1
            if p.zoomIndex > #p.zoomFOVs then p.zoomIndex = 1 end
            applyZoom()
            if c.haptics ~= false then
                pcall(uevrUtils.triggerHapticVibration, Handed.Right, 0.0, 0.08, 1.0, 0.6)
            end
            saveConfig()
        end
        uevrUtils.unpressButton(state, RIGHT_THUMB)
    else
        zoomArmed = true
    end
end

---------------------------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------------------------
function M.onLevelChange()
    lastLevelChangeTime = os.clock()
    -- The pawn is recreated; the old components are gone with it. Never touch them.
    forgetComponents()
    equippedMesh = nil
    equippedName = nil
    anchorBones = nil
    anchorShared = false
    deferFrames = 0
end

function M.destroy()
    endEquip()
end

---------------------------------------------------------------------------------------------------
-- Dev panel
---------------------------------------------------------------------------------------------------
local function drag3(label, t, speed, min, max, fmt)
    local changed = false
    local names = { "X", "Y", "Z" }
    if fmt == "rot" then names = { "Pitch", "Yaw", "Roll" } end
    for i = 1, 3 do
        local ch, v = imgui.drag_float(label .. " " .. names[i] .. "##binoc" .. label .. i, t[i], speed, min, max, "%.2f")
        if ch then t[i] = v; changed = true end
    end
    return changed
end

function M.drawUI()
    local c = cfg()
    local p = prof()
    local changed = false

    imgui.text(equippedMesh and ("Equipped: " .. tostring(equippedName)) or "Not equipped (showing seed values)")
    if equippedMesh then
        imgui.text("Components: " .. (M.hasComponents() and "live" or ("pending (" .. deferFrames .. ")")))
        if anchorBones then
            imgui.text("Disc anchors: " .. anchorBones[1] .. " / " .. anchorBones[2] .. (anchorShared and " (shared, separated)" or ""))
        end
        imgui.text("Capture mode: " .. tostring(captureMode) .. "  lens->HMD: " .. (lastDistance and string.format("%.1f cm", lastDistance) or "n/a"))
        if lastFailure then imgui.text("Last problem: " .. lastFailure) end
    end
    imgui.text("Tuning below is saved per model under Config.binoculars.profiles.")

    local enCh, en = imgui.checkbox("Enable VR binoculars (PiP lenses)##binoc", c.enabled ~= false)
    if enCh then c.enabled = en; changed = true end

    imgui.separator()
    imgui.text("Zoom steps (capture FOV, degrees; widest first)")
    for i = 1, #p.zoomFOVs do
        local ch, v = imgui.drag_float("Step " .. i .. " FOV##binoczoom" .. i, p.zoomFOVs[i], 0.1, 1.0, 90.0, "%.1f")
        if ch then p.zoomFOVs[i] = v; changed = true; applyZoom() end
    end
    local ziCh, zi = imgui.slider_int("Current step##binoc", p.zoomIndex, 1, #p.zoomFOVs)
    if ziCh then p.zoomIndex = zi; changed = true; applyZoom() end

    imgui.separator()
    imgui.text("Capture (relative to bone " .. CAPTURE_BONE .. ")")
    if drag3("Capture Loc", p.captureLocation, 0.1, -50.0, 50.0) then changed = true; applyCaptureTransform() end
    if drag3("Capture Rot", p.captureRotation, 0.5, -180.0, 180.0, "rot") then changed = true; applyCaptureTransform() end

    imgui.separator()
    imgui.text("Lens discs (relative to each anchor bone)")
    if drag3("Disc Loc", p.discLocation, 0.05, -20.0, 20.0) then changed = true; applyDiscTransforms() end
    if drag3("Disc Rot", p.discRotation, 0.5, -180.0, 180.0, "rot") then changed = true; applyDiscTransforms() end
    local dCh, dv = imgui.drag_float("Disc Diameter##binoc", p.discDiameter, 0.001, 0.005, 0.2, "%.3f")
    if dCh then p.discDiameter = dv; changed = true; applyDiscTransforms() end
    local tCh, tv = imgui.drag_float("Disc Depth##binoc", p.discDepth, 0.0001, 0.0001, 0.05, "%.4f")
    if tCh then p.discDepth = tv; changed = true; applyDiscTransforms() end
    if anchorShared or not equippedMesh then
        local sepCh, sepv = imgui.drag_float("Disc Separation (shared-bone models, cm)##binoc", p.discSeparation, 0.05, 0.0, 20.0, "%.2f")
        if sepCh then p.discSeparation = sepv; changed = true; applyDiscTransforms() end
    end
    if imgui.tree_node("Per-disc extra offsets (left / right)##binoc") then
        imgui.text("Added on top of Disc Loc / Disc Rot for that disc only.")
        if drag3("Left Disc Loc", p.discOffsetLeft, 0.05, -20.0, 20.0) then changed = true; applyDiscTransforms() end
        if drag3("Left Disc Rot", p.discRotOffsetLeft, 0.5, -180.0, 180.0, "rot") then changed = true; applyDiscTransforms() end
        if drag3("Right Disc Loc", p.discOffsetRight, 0.05, -20.0, 20.0) then changed = true; applyDiscTransforms() end
        if drag3("Right Disc Rot", p.discRotOffsetRight, 0.5, -180.0, 180.0, "rot") then changed = true; applyDiscTransforms() end
        imgui.tree_pop()
    end
    local bCh, bv = imgui.slider_float("Brightness##binoc", p.brightness, 0.0, 100.0)
    if bCh then p.brightness = bv; changed = true; applyBrightness() end
    local ebCh, ebv = imgui.slider_float("Exposure Bias (stops, pre-tonemap)##binoc", p.exposureBias or 0.0, -5.0, 10.0, "%.2f")
    if ebCh then p.exposureBias = ebv; changed = true; applyExposure() end

    imgui.separator()
    imgui.text("Global")
    local sCh, sv = imgui.slider_float("Sleep distance (cm lens->HMD, capture stops beyond)##binoc", c.sleepDistance, 20.0, 200.0)
    if sCh then c.sleepDistance = sv; changed = true end
    local hCh, hv = imgui.checkbox("Haptic on zoom step##binoc", c.haptics ~= false)
    if hCh then c.haptics = hv; changed = true end
    imgui.text("Texture size / screen % apply on next equip: " .. tostring(c.textureSize) .. " / " .. tostring(c.screenPercentage))

    imgui.separator()
    if imgui.button("Save##binoc") then saveConfig() end
    imgui.same_line()
    if imgui.button("Rebuild components##binoc") then
        destroyComponents()
        deferFrames = 5
    end
    imgui.same_line()
    if imgui.button("Reset this model to seed##binoc") then
        if equippedName then
            c.profiles[equippedName] = nil
            prof()
        else
            scratchProfile = nil
        end
        applyDiscTransforms(); applyCaptureTransform(); applyZoom(); applyBrightness()
        saveConfig()
    end

    if changed then Config:markDirty() end
end

return M
