-- Equipped items shown on the body (2026-10-12).
--
-- The gesture zones (gestures/bodyzone.lua) are where items are grabbed from - sidearm at the right hip, detector at
-- the right chest (left hand) - but nothing was ever there to grab. This module shows the item itself in its zone,
-- and hides it while it is in the hand, so reaching for the zone reads as taking the item off the body.
--
-- Game facts (MCP, 2026-10-12):
--   * the first-person pawn carries no holstered meshes: pawn.Mesh's children are audio components, the camera
--     and the one in-hand WeaponInHandsMesh. Every body item is a component created here.
--   * nothing on the pawn says what is in a slot. Two sources are combined:
--       1. the hands: whenever a sidearm (a mesh under .../weapons/pt/) or a detector is held, its mesh asset is
--          remembered for the slot (Config.bodyItems.slots.<slot>.mesh);
--       2. the inventory screen: while it is open, the equipment panel (native class EquipmentSlots, widget
--          W_EquipmentSlots_C) has one W_EquipmentSlotNew_C per slot as a variable named after the slot - "Pistol",
--          "Detector", also MainHand, SecondHand, Binoculars, ... Its ItemImage.ImageObj brush is a dynamic
--          material whose "Icon" texture names the item (T_inv_w_udp_body, T_dev_detector_echo). The icon is
--          read while the inventory is open and saved per slot, so a swap made there is known at once.
--     icon -> mesh: pairs are learned whenever an item with a known icon is held (Config.bodyItems.iconMeshes);
--     for a sidearm never held before, the mesh is guessed from the icon (T_inv_w_<id>_body ->
--     .../weapons/pt/<id>/SK_<id>). An item whose mesh is not known shows nothing rather than the previous item.
--   * the game only keeps the HELD weapon's assets in memory (with the PM out, SK_udp was not loaded at all), so
--     every asset shown here is loaded through AssetRegistryHelpers:GetAsset (verified via MCP; the lib's
--     uevrUtils.getLoadedAsset returned nothing for SK_pm).
--   * a weapon mesh asset has NO material of its own (the body copy of the pistol had one slot, null, and never
--     rendered); the game assigns MI_<id>_base etc. on the in-hand component. The materials seen on the held item
--     are saved per mesh (Config.bodyItems.materials) and put on the copy; for a sidearm never held, the
--     material is guessed (.../weapons/pt/<id>/MI_<id>_base). Detector meshes carry their own materials.
--   * A WEAPON'S SKELETAL MESH IS ONLY ITS RIG (read live with the UDP held, 2026-10-12): SK_udp has one empty
--     material slot and placeholder bounds, and draws nothing. The visible gun is 10+ StaticMeshComponents the
--     game attaches to the rig's sockets with zero offsets - SM_wpn_udp_SM_offset on jnt_offset (the frame),
--     ..._SM_shutter on jnt_shutter, ..._SM_trigger, ..._SM_hummer, ..._SM_titing_barrel, SM_pt_udp_mag_full on
--     jnt_magazine, ... (/Game/_Stalker_2/weapons/pistol/p_udp/), each with its own materials; spare magazine
--     components sit on the same socket with bHiddenInGame set. So while an item is held its visible static-mesh
--     children are recorded (mesh, socket, relative transform, materials) in Config.bodyItems.parts[<rig path>]
--     and the body copy is rebuilt from that list. A weapon that was never held has no list and shows nothing.
--   * hands_Detector's "Detector" component holds a body-part mesh (player/sel/.../SK_bpa_pla_01) until the real
--     detector mesh is set, so only meshes with "detector" in their path are taken for the detector slot.
--
-- Placement: the zones are boxes in an HMD-relative, yaw-only frame (X forward, Y right, Z up, cm). One anchor
-- SceneComponent is moved to that frame after every stereo pass (the gesture layer's HMD proxy only holds this
-- frame's pose there), and each item hangs on it at its zone's centre plus the slot's own offset / rotation /
-- scale, tuned in the dev panel. Same frame in Hands, IK Arms and IK + body modes.
--
-- External slots (2026-10-17): another module builds the item and says when it is out of its zone (M.setProvider);
-- this module only places / shows / hides / destroys it. Used for the manual reload's belt pouch at the left hip.
require("Config.CONFIG")
local uevrUtils = require("libs/uevr_utils")
local gameState = require("stalker2.gamestate")
local motionControllerActors = require("gestures.motioncontrolleractors")
local zonesStanding = require("gestures.bodyzone")
local zonesSitting = require("gestures.bodyzonesitting")

local M = {}

-- order = dev panel order; widget = the slot's variable on the inventory's equipment panel (sidearm and detector
-- only: grenades and the bolt have no equipment slot there, they are learned from the hands alone).
-- Zones = where each gesture grabs (presets/presetRH.lua): the grenade at the left chest (right hand), the detector
-- (left hand) and the bolt (right hand) at the right chest - the bolt's default offset keeps that pair apart.
--   grenade: the last type that was in the hand (F1 / RGD-5). Nothing tells how many are left, so it stays on the
--            body after the last one is thrown.
-- (A PDA slot was tried and dropped on request, 2026-10-12.)
--   ammo (2026-10-17): external = the item is built by another module (ptm_manual_reload.lua: the belt pouch holding
--            the next mag / shell / speedloader / rocket for a manual reload), see M.setProvider. Its placement is
--            saved per ammo type (slots.ammo.byType.<mag|shell|speedloader|rocket>) - a rocket and a pistol mag do
--            not sit the same way.
local SLOTS = {
    { key = "sidearm",  label = "Sidearm (right hip)",    zone = "rightHipZoneRH",   widget = "Pistol" },
    { key = "detector", label = "Detector (right chest)", zone = "rightChestZoneLH", widget = "Detector" },
    { key = "grenade",  label = "Grenade (left chest)",   zone = "leftChestZoneRH",  location = { 0.0, -4.0, 4.0 } },
    { key = "bolt",     label = "Bolt (right chest)",     zone = "rightChestZoneRH", location = { 0.0, 5.0, -6.0 } },
    { key = "ammo",     label = "Reload ammo pouch (left hip)", zone = "leftHipZoneLH", external = true },
}
M.SLOTS = SLOTS

local LEARN_INTERVAL_S     = 0.5
local INVENTORY_INTERVAL_S = 0.5
local REBUILD_COOLDOWN_S   = 1.0
local FOV_REAPPLY_S        = 2.0
local EMPTY                = ""    -- saved icon value of a slot the inventory showed as empty
local DATA_VERSION         = 2
local TARGET_BOUNDS_CM     = 30.0
local PARTS_AFTER_HELD_S   = 2.0   -- parts are read once the item has been in the hand this long (equip animation over)
local PAIR_AFTER_INVENTORY_S = 3.0 -- after the inventory closes the old item can still be in the hand for a moment

local function cfg()
    local c = Config.bodyItems
    if type(c) ~= "table" then
        c = {}
        Config.bodyItems = c
    end
    if type(c.slots) ~= "table" then c.slots = {} end
    if type(c.iconMeshes) ~= "table" then c.iconMeshes = {} end
    if type(c.materials) ~= "table" then c.materials = {} end
    if type(c.parts) ~= "table" then c.parts = {} end
    if c.dataVersion ~= DATA_VERSION then
        -- pairs learned by the first version were wrong (detector icons -> a body-part mesh, a sidearm icon paired
        -- with the weapon that was still in the hand right after the swap)
        c.iconMeshes = {}
        c.dataVersion = DATA_VERSION
    end
    return c
end

local function slotCfg(key)
    local slots = cfg().slots
    if type(slots[key]) ~= "table" then slots[key] = {} end
    local s = slots[key]
    if type(s.location) ~= "table" then
        -- a slot added after settings.json was first written is not in the saved table: its default offset
        -- comes from SLOTS, not from Config/CONFIG.lua (the saved "slots" table replaces that one as a whole)
        local default = { 0.0, 0.0, 0.0 }
        for _, slot in ipairs(SLOTS) do
            if slot.key == key and slot.location ~= nil then
                default = { slot.location[1], slot.location[2], slot.location[3] }
            end
        end
        s.location = default
    end
    if type(s.rotation) ~= "table" then s.rotation = { 0.0, 0.0, 0.0 } end
    if type(s.scale) ~= "number" then s.scale = 1.0 end
    return s
end
M.slotCfg = slotCfg

-- Where an item sits: the slot's own offsets, or for an external slot whose provider names a placement type, that
-- type's (started from the slot's offsets the first time the type is seen).
local currentType = {} -- [slotKey] = placement type of the item shown now (external slots)
local function placementCfg(key, placementType)
    local s = slotCfg(key)
    if placementType == nil then return s end
    if type(s.byType) ~= "table" then s.byType = {} end
    local t = s.byType[placementType]
    if type(t) ~= "table" then
        t = {}
        s.byType[placementType] = t
    end
    if type(t.location) ~= "table" then t.location = { s.location[1] or 0, s.location[2] or 0, s.location[3] or 0 } end
    if type(t.rotation) ~= "table" then t.rotation = { s.rotation[1] or 0, s.rotation[2] or 0, s.rotation[3] or 0 } end
    if type(t.scale) ~= "number" then t.scale = s.scale end
    return t
end

-- Dev panel: the offsets the sliders edit for this slot right now, and the placement type they belong to (nil for
-- the normal slots).
function M.placementCfg(key)
    return placementCfg(key, currentType[key]), currentType[key]
end

-- External slots: provider() -> source, or nil + a status note. source = {
--   signature = string (the item is rebuilt when it changes), label = short text for the status line,
--   type = placement type or nil, hidden = true while the item is out of its zone (in the hand),
--   build = function(pawn) -> component, parts (components attached under it; destroyed with it) }
-- Called from update() every gameplay tick, so keep it cheap.
local providers = {}
function M.setProvider(key, provider)
    providers[key] = provider
end

function M.isEnabled()
    return cfg().enabled ~= false
end

-- data/body_items_log.txt (last 150 lines): state changes only. Off unless Config.bodyItems.debugLog is set.
local logLines = {}
local function log(text)
    if cfg().debugLog ~= true then return end
    table.insert(logLines, string.format("%.3f %s", os.clock(), tostring(text)))
    while #logLines > 150 do table.remove(logLines, 1) end
    pcall(function() fs.write("body_items_log.txt", table.concat(logLines, "\n") .. "\n") end)
end

-- ---------------------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------------------
local anchor = nil
local anchorPawnAddress = nil
local items = {}            -- [slotKey] = { component, assetAddress, fovAt, shown }
local assetCache = {}       -- [path] = true (exists) / false (could not be found or loaded this session); never the object
local inHand = {}           -- [slotKey] = true while that slot's item is the one in the hand
local nextLearnAt = 0
local nextInventoryAt = 0
local lastBuildAttempt = 0
local configDirty = false
local status = {}           -- [slotKey] = text for the dev panel
local heldSince = {}        -- [mesh path] = os.clock() since which it has been in the hand without a break
local partsCaptured = {}    -- [mesh path] = true once its parts were read this session

local function forget()
    anchor, anchorPawnAddress = nil, nil
    items = {}
end

local function alive(obj)
    if obj == nil then return false end
    local ok, r = pcall(function() return obj:get_full_name() ~= nil end)
    return ok and r
end

local function setShown(item, shown)
    if item.shown == shown then return end
    item.shown = shown
    pcall(function()
        item.component:SetHiddenInGame(not shown, true)
        item.component:SetVisibility(shown, true)
    end)
end

-- ---------------------------------------------------------------------------------------
-- Which mesh a slot shows
-- ---------------------------------------------------------------------------------------
-- sidearm icon T_inv_w_udp_body -> "udp"
local function sidearmIconId(icon)
    if type(icon) ~= "string" then return nil end
    local id = string.match(string.lower(icon), "^t_inv_w_(.-)_body$") or string.match(string.lower(icon), "^t_inv_w_(.+)$")
    if id == nil or id == "" then return nil end
    return id
end

-- T_inv_w_udp_body    -> SkeletalMesh /Game/_STALKER2/SkeletalMeshes/weapons/pt/udp/SK_udp.SK_udp
-- T_dev_detector_echo -> SkeletalMesh /Game/_STALKER2/SkeletalMeshes/weapons/items/detector_echo/SK_detector_echo.SK_detector_echo
local function guessPath(key, icon)
    if key == "sidearm" then
        local id = sidearmIconId(icon)
        if id == nil then return nil end
        return "SkeletalMesh /Game/_STALKER2/SkeletalMeshes/weapons/pt/" .. id .. "/SK_" .. id .. ".SK_" .. id
    elseif key == "detector" then
        local name = string.match(string.lower(icon), "^t_dev_(detector_.+)$")
        if name == nil then return nil end
        return "SkeletalMesh /Game/_STALKER2/SkeletalMeshes/weapons/items/" .. name .. "/SK_" .. name .. ".SK_" .. name
    end
    return nil
end

-- SK_udp's folder holds MI_udp_base
local function guessMaterialPath(meshPath)
    local folder, id = string.match(meshPath, "^SkeletalMesh (/Game/_STALKER2/SkeletalMeshes/weapons/pt/[^/]+/)SK_([^%.]+)%.")
    if folder == nil then return nil end
    return "MaterialInstanceConstant " .. folder .. "MI_" .. id .. "_base.MI_" .. id .. "_base"
end

local loadAsset -- defined below

-- The asset path (= the asset's full name) the slot should show, or nil for nothing.
local function wantedPath(key)
    local s = slotCfg(key)
    if s.icon == EMPTY then return nil, "slot is empty" end
    if type(s.icon) == "string" then
        -- the path the icon's name stands for, when such an asset exists; else a pair learned from the hands
        local guess = guessPath(key, s.icon)
        if guess ~= nil and loadAsset(guess) ~= nil then return guess end
        local known = cfg().iconMeshes[s.icon]
        if known ~= nil then return known end
        return nil, "new item " .. s.icon .. " - draw it once"
    end
    if type(s.mesh) == "string" and s.mesh ~= "" then return s.mesh end
    return nil, "not seen yet - draw it once or open the inventory"
end

-- A missed lookup costs hundreds of ms on this backend, so a path that failed is not tried again this session.
local assetRegistryHelpers = nil
-- loadAsset(path)        -> truthy when the asset exists (answer cached for the session)
-- loadAsset(path, true)  -> the asset object, fetched NOW. Objects are never cached: the game unloads a weapon's
-- assets as soon as nothing uses them (after swapping the UDP for the PM its part meshes were gone, and a copy built
-- from the cached objects got 1 part out of 9 - 2026-10-12). Only our own components keep an asset alive.
loadAsset = function(path, needObject)
    local cached = assetCache[path]
    if cached == false then return nil end
    if cached == true and not needObject then return true end
    local object, why = nil, nil
    local ok, err = pcall(function()
        if assetRegistryHelpers == nil then
            assetRegistryHelpers = uevrUtils.find_default_instance("Class /Script/AssetRegistry.AssetRegistryHelpers")
        end
        if assetRegistryHelpers == nil then why = "no AssetRegistryHelpers" return end
        local assetData = uevrUtils.getAssetDataFromPath(path)
        if assetData == nil then why = "no AssetData struct" return end
        -- returns the asset, loading its package first when it is not in memory
        object = assetRegistryHelpers:GetAsset(assetData)
    end)
    if not ok then why = tostring(err) end
    if cached == nil or (object == nil) ~= (cached == false) then
        log((object ~= nil and "found " or ("could NOT load (" .. tostring(why or "not found") .. ") ")) .. path)
    end
    assetCache[path] = object ~= nil
    return object
end

-- The asset behind a material on a live component: dynamic instances (the game's, or our own FOV fix) are
-- per-component objects, their Parent is what can be saved and loaded again.
local materialInstanceDynamicClass = nil
local function materialAssetName(material)
    if materialInstanceDynamicClass == nil then
        materialInstanceDynamicClass = uevrUtils.get_class("Class /Script/Engine.MaterialInstanceDynamic")
    end
    local m = material
    for _ = 1, 4 do
        if m == nil or materialInstanceDynamicClass == nil or not m:is_a(materialInstanceDynamicClass) then break end
        m = m.Parent
    end
    if m == nil then return nil end
    return m:get_full_name()
end

local function rememberMaterials(path, component)
    local names = {}
    local materials = component:GetMaterials()
    for i = 1, #(materials or {}) do
        names[i] = materialAssetName(materials[i]) or ""
    end
    if #names == 0 then return end
    local saved = cfg().materials[path]
    if type(saved) == "table" and table.concat(saved, "|") == table.concat(names, "|") then return end
    cfg().materials[path] = names
    configDirty = true
    log("materials of " .. path .. ": " .. table.concat(names, " | "))
end

-- The visible parts of a held item: its static-mesh children that are shown right now.
local staticMeshComponentClass = nil
local destroyItemsOfPath -- defined with the components below

local function rememberParts(path, component)
    if staticMeshComponentClass == nil then
        staticMeshComponentClass = uevrUtils.get_class("Class /Script/Engine.StaticMeshComponent")
    end
    if staticMeshComponentClass == nil then return end
    local parts = {}
    local children = component.AttachChildren
    for i = 1, #(children or {}) do
        local child = children[i]
        pcall(function()
            if child == nil or not child:is_a(staticMeshComponentClass) then return end
            local mesh = child.StaticMesh
            if mesh == nil or child.bHiddenInGame == true or child.bVisible == false then return end
            local meshName = mesh:get_full_name()
            if string.find(meshName, " /Game/", 1, true) == nil then return end -- not engine shapes (debug markers)
            local rl, rr, rs = child.RelativeLocation, child.RelativeRotation, child.RelativeScale3D
            local materials = {}
            local list = child:GetMaterials()
            for j = 1, #(list or {}) do materials[j] = materialAssetName(list[j]) or "" end
            table.insert(parts, {
                mesh = meshName, socket = child.AttachSocketName:to_string(),
                location = { rl.X, rl.Y, rl.Z }, rotation = { rr.Pitch, rr.Yaw, rr.Roll }, scale = { rs.X, rs.Y, rs.Z },
                materials = materials,
            })
        end)
    end
    partsCaptured[path] = true
    local saved = cfg().parts[path]
    -- never replace a list with a shorter one (a part can be hidden mid-animation, e.g. the magazine in a reload)
    if #parts == 0 or (type(saved) == "table" and #saved >= #parts) then return end
    cfg().parts[path] = parts
    configDirty = true
    log("parts of " .. path .. ": " .. tostring(#parts))
    destroyItemsOfPath(path) -- rebuilt with the parts on the next update
end

local inventoryClosedAt = 0 -- last moment the inventory was seen open

-- What is held right now: remember it (and its materials) for its slot, pair it with the slot's inventory icon.
local function remember(key, meshAsset, component)
    if meshAsset == nil then return end
    local path = nil
    pcall(function() path = meshAsset:get_full_name() end)
    if type(path) ~= "string" or path == "" then return end
    assetCache[path] = true
    if component ~= nil then
        pcall(rememberMaterials, path, component)
        local now = os.clock()
        if heldSince[path] == nil then heldSince[path] = now end
        if not partsCaptured[path] and now - heldSince[path] >= PARTS_AFTER_HELD_S then
            local ok, err = pcall(rememberParts, path, component)
            if not ok then
                partsCaptured[path] = true
                log("parts of " .. path .. " could not be read: " .. tostring(err))
            end
        end
    end
    local s = slotCfg(key)
    if s.mesh ~= path then
        s.mesh = path
        configDirty = true
        log(key .. " in hand: " .. path)
    end
    if s.icon == EMPTY then
        s.icon = nil -- the inventory said empty, yet the item is in the hand: that reading is out of date
        configDirty = true
    elseif type(s.icon) == "string" then
        -- right after the inventory closes the previous item can still be in the hand
        if os.clock() - inventoryClosedAt < PAIR_AFTER_INVENTORY_S then return end
        local guess = guessPath(key, s.icon)
        if guess ~= nil and loadAsset(guess) ~= nil then
            if guess ~= path then
                -- the icon stands for another item: the slot changed without the inventory being read (trader, loot)
                log(key .. ": icon " .. s.icon .. " is out of date (holding " .. path .. ")")
                s.icon = nil
                configDirty = true
            end
            return
        end
        local map = cfg().iconMeshes
        if map[s.icon] ~= path then
            log("learned " .. s.icon .. " = " .. path .. (map[s.icon] ~= nil and (" (was " .. map[s.icon] .. ")") or ""))
            map[s.icon] = path
            configDirty = true
        end
    end
end

local function learn()
    for _, slot in ipairs(SLOTS) do inHand[slot.key] = false end
    local heldBefore = heldSince
    heldSince = {}
    local function keepHeld(asset)
        local path = asset:get_full_name()
        heldSince[path] = heldBefore[path] or os.clock()
    end

    pcall(function()
        local weapon = gameState._frameWeapon
        local asset = weapon and weapon.SkeletalMesh or nil
        if asset == nil then return end
        -- by the asset's folder, not the weapon cache's one-handed flag: that flag is taken from the anim
        -- instance, which lags behind the mesh when the single weapon component is recycled on a switch
        local path = string.lower(asset:get_full_name())
        local isSidearm = string.find(path, "/weapons/pt/", 1, true) ~= nil
        if not isSidearm then
            -- a non-pistol in the sidearm slot (some SMGs): the slot's icon id names it
            local id = sidearmIconId(slotCfg("sidearm").icon)
            isSidearm = id ~= nil and string.find(path, "sk_" .. id, 1, true) ~= nil
        end
        local key = isSidearm and "sidearm" or nil
        if key == nil then
            local name = string.lower(asset:get_fname():to_string())
            if string.find(name, "bolt", 1, true) ~= nil then
                key = "bolt"
            elseif string.find(name, "sk_f1", 1, true) ~= nil or string.find(name, "sk_rgd", 1, true) ~= nil
                or string.find(name, "grenade", 1, true) ~= nil then
                key = "grenade"
            end
        end
        if key ~= nil then
            keepHeld(asset)
            remember(key, asset, weapon)
            inHand[key] = true
        end
    end)


    pcall(function()
        local detectorSystem = _G.DetectorSystem
        local detector = detectorSystem ~= nil and detectorSystem.GetCurrentDetector() or nil
        if detector == nil or not UEVR_UObjectHook.exists(detector) then return end
        inHand.detector = gameState.isDetectorEquipped == true
        local asset = detector.SkeletalMesh
        if asset == nil or not inHand.detector then return end
        -- the component carries a body-part mesh (SK_bpa_pla_01) until the detector's own mesh is set
        if string.find(string.lower(asset:get_full_name()), "detector", 1, true) == nil then return end
        keepHeld(asset)
        remember("detector", asset, detector)
    end)
end

-- ---------------------------------------------------------------------------------------
-- Inventory screen: which item is in each slot
-- ---------------------------------------------------------------------------------------
local equipmentSlotsClass = nil
local iconParameter = nil

-- the icon texture name of one equipment slot widget; EMPTY when the slot shows no item, nil when unreadable
local function readSlotIcon(slotWidget)
    local image = slotWidget.ItemImage
    if image == nil then return nil end
    if image:IsVisible() ~= true then return EMPTY end
    local imageObj = image.ImageObj
    local material = imageObj and imageObj.Brush and imageObj.Brush.ResourceObject or nil
    if material == nil or material.K2_GetTextureParameterValue == nil then return nil end
    if iconParameter == nil then iconParameter = uevrUtils.fname_from_string("Icon") end
    local texture = material:K2_GetTextureParameterValue(iconParameter)
    if texture == nil then return nil end
    return texture:get_fname():to_string()
end

-- Only called while the inventory is open. Widget enumeration is kept out of every other state on purpose:
-- polling it while a level streamed in once hung the game thread (see gamestate.lua UpdateMenuState).
local function readInventory()
    if WidgetBlueprintLibrary == nil then return end
    if equipmentSlotsClass == nil then equipmentSlotsClass = uevrUtils.get_class("Class /Script/Stalker2.EquipmentSlots") end
    if equipmentSlotsClass == nil then return end
    local world = uevrUtils.get_world()
    if world == nil then return end
    inventoryClosedAt = os.clock()
    local found = {}
    WidgetBlueprintLibrary:GetAllWidgetsOfClass(world, found, equipmentSlotsClass, false)
    for _, panel in ipairs(found) do
        local visible = false
        pcall(function() visible = panel:IsVisible() == true end)
        if visible then
            for _, slot in ipairs(SLOTS) do
                local ok, icon = pcall(function()
                    if slot.widget == nil then return nil end
                    local slotWidget = panel[slot.widget]
                    if slotWidget == nil then return nil end
                    return readSlotIcon(slotWidget)
                end)
                if ok and icon ~= nil then
                    local s = slotCfg(slot.key)
                    if s.icon ~= icon then
                        s.icon = icon
                        configDirty = true
                        log(slot.key .. " in inventory: " .. (icon == EMPTY and "(empty)" or icon))
                    end
                end
            end
            return
        end
    end
end

-- ---------------------------------------------------------------------------------------
-- Components
-- ---------------------------------------------------------------------------------------
local skeletalComponentClass, staticComponentClass, sceneComponentClass = nil, nil, nil
local skeletalMeshClass = nil

local function ensureAnchor(pawn)
    local pawnAddress = pawn:get_address()
    if anchor ~= nil and anchorPawnAddress == pawnAddress then return true end
    -- new pawn (level change, save load): the old components went with the old pawn - never touch them
    forget()
    local now = os.clock()
    if now - lastBuildAttempt < REBUILD_COOLDOWN_S then return false end
    lastBuildAttempt = now
    if sceneComponentClass == nil then sceneComponentClass = uevrUtils.get_class("Class /Script/Engine.SceneComponent") end
    if sceneComponentClass == nil then return false end
    local created = nil
    pcall(function()
        created = uevr.api:add_component_by_class(pawn, sceneComponentClass)
        created:SetAbsolute(true, true, true)
    end)
    if created == nil then return false end
    anchor, anchorPawnAddress = created, pawnAddress
    return true
end

local function destroyItem(key)
    local item = items[key]
    items[key] = nil
    if item == nil then return end
    for _, part in ipairs(item.parts or {}) do
        pcall(function()
            if part.K2_DestroyComponent ~= nil then part:K2_DestroyComponent(part) end
        end)
    end
    pcall(function()
        if item.component.K2_DestroyComponent ~= nil then item.component:K2_DestroyComponent(item.component) end
    end)
end

destroyItemsOfPath = function(path)
    for key, item in pairs(items) do
        if item.path == path then destroyItem(key) end
    end
end

-- The recorded static-mesh parts of a rig, attached to the copy's sockets. Returns the created components.
local function createParts(pawn, component, path)
    local created = {}
    local parts = cfg().parts[path]
    if type(parts) ~= "table" then return created, 0 end
    if staticComponentClass == nil then staticComponentClass = uevrUtils.get_class("Class /Script/Engine.StaticMeshComponent") end
    local skipped, failed = 0, 0
    for _, part in ipairs(parts) do
        local ok, err = pcall(function()
            -- The loose round and its ejected case (SM_wpn_udp_SM_bullet / _bullet_shell on jnt_bullet /
            -- jnt_bullet_shell) only make sense under the weapon's animation: in the copy's reference pose they
            -- hang next to the gun (first visible run, 2026-10-12).
            local socket = string.lower(part.socket or "")
            if string.find(socket, "bullet", 1, true) ~= nil or string.find(socket, "shell", 1, true) ~= nil then
                skipped = skipped + 1
                return
            end
            local mesh = loadAsset(part.mesh, true)
            if mesh == nil then failed = failed + 1 return end
            local child = uevr.api:add_component_by_class(pawn, staticComponentClass)
            child:SetStaticMesh(mesh)
            for j, name in ipairs(part.materials or {}) do
                if type(name) == "string" and name ~= "" then
                    local material = loadAsset(name, true)
                    if material ~= nil then child:SetMaterial(j - 1, material) end
                end
            end
            child:SetCollisionEnabled(0)
            pcall(function() child:SetCastShadow(Config.vrShadowsEnabled == true) end)
            child:K2_AttachToComponent(component, uevrUtils.fname_from_string(part.socket or "None"), 0, 0, 0, false)
            local l, r, s = part.location or {}, part.rotation or {}, part.scale or {}
            child:K2_SetRelativeLocationAndRotation(uevrUtils.vector(l[1] or 0, l[2] or 0, l[3] or 0),
                uevrUtils.rotator(r[1] or 0, r[2] or 0, r[3] or 0), false, reusable_hit_result, false)
            child:SetRelativeScale3D(uevrUtils.vector(s[1] or 1, s[2] or 1, s[3] or 1))
            table.insert(created, child)
        end)
        if not ok then
            failed = failed + 1
            log("part " .. tostring(part.mesh) .. " failed: " .. tostring(err))
        end
    end
    if failed > 0 then log(tostring(failed) .. " part(s) of " .. path .. " could not be built") end
    return created, #parts - skipped
end

-- Weapon mesh assets have empty material slots: fill them from what the held item had (or the guess).
local function applyMaterials(component, asset)
    local path = asset:get_full_name()
    local names = cfg().materials[path]
    if type(names) ~= "table" then return end
    for i, name in ipairs(names) do
        if type(name) == "string" and name ~= "" then
            local current = nil
            pcall(function() current = component:GetMaterial(i - 1) end)
            if current == nil then
                local material = loadAsset(name, true)
                if material ~= nil then component:SetMaterial(i - 1, material) end
            end
        end
    end
end

local function createItem(pawn, key, asset)
    if skeletalMeshClass == nil then skeletalMeshClass = uevrUtils.get_class("Class /Script/Engine.SkeletalMesh") end
    local isSkeletal = skeletalMeshClass ~= nil and asset:is_a(skeletalMeshClass)
    local component = nil
    local boundsNote = "bounds ?"
    local ok, err = pcall(function()
        if isSkeletal then
            if skeletalComponentClass == nil then skeletalComponentClass = uevrUtils.get_class("Class /Script/Engine.SkeletalMeshComponent") end
            component = uevr.api:add_component_by_class(pawn, skeletalComponentClass)
            if component.SetSkeletalMeshAsset ~= nil then
                component:SetSkeletalMeshAsset(asset)
            else
                component:SetSkeletalMesh(asset)
            end
        else
            if staticComponentClass == nil then staticComponentClass = uevrUtils.get_class("Class /Script/Engine.StaticMeshComponent") end
            component = uevr.api:add_component_by_class(pawn, staticComponentClass)
            component:SetStaticMesh(asset)
        end
        applyMaterials(component, asset)
        component:SetCollisionEnabled(0)
        pcall(function() component:SetCastShadow(Config.vrShadowsEnabled == true) end)
        -- Weapon mesh assets ship with placeholder bounds (SK_pm: a flat 0.07 cm box, no physics asset), so the
        -- copy was culled as soon as that point left the view / as too small - it never rendered (MCP 2026-10-12:
        -- WasRecentlyRendered false, component bounds radius 0.77 cm even at BoundsScale 8). The bounds are
        -- scaled up to a sphere of about TARGET_BOUNDS_CM around the item.
        local boundsScale = 8.0
        pcall(function()
            local radius = asset.ExtendedBounds.SphereRadius
            if type(radius) == "number" and radius < TARGET_BOUNDS_CM / 8.0 then
                boundsScale = math.min(TARGET_BOUNDS_CM / math.max(radius, 0.01), 2000.0)
            end
        end)
        if component.SetBoundsScale ~= nil then component:SetBoundsScale(boundsScale) else component.BoundsScale = boundsScale end
        boundsNote = string.format("bounds x%.0f", boundsScale)
        component:K2_AttachToComponent(anchor, uevrUtils.fname_from_string("None"), 0, 0, 0, false)
    end)
    if not ok or component == nil then
        status[key] = "could not create the mesh: " .. tostring(err)
        log(key .. ": " .. status[key])
        return nil
    end
    local path = asset:get_full_name()
    local parts, wanted = createParts(pawn, component, path)
    -- a mesh with an empty material slot and no parts is a bare rig: nothing of it draws
    local rigOnly = false
    pcall(function() rigOnly = component:GetNumMaterials() > 0 and component:GetMaterial(0) == nil end)
    local item = { component = component, assetAddress = asset:get_address(), fovAt = 0, shown = nil, path = path,
        parts = parts, partsWanted = wanted, rigOnly = rigOnly }
    items[key] = item
    local materialNote = "?"
    pcall(function()
        local count, filled = component:GetNumMaterials(), 0
        for i = 0, count - 1 do
            if component:GetMaterial(i) ~= nil then filled = filled + 1 end
        end
        materialNote = tostring(filled) .. "/" .. tostring(count)
    end)
    log(key .. ": created " .. asset:get_fname():to_string() .. " (materials " .. materialNote .. ", " .. boundsNote .. ", parts " .. tostring(#parts) .. "/" .. tostring(wanted) .. ")")
    return item
end

-- same depth / FOV treatment as the hands, weapon and detector (Entry.lua applyForegroundFOVFixExperiment); the
-- materials can finish streaming after the component exists, hence the re-apply
local function fixFOV(item)
    local now = os.clock()
    if now - item.fovAt < FOV_REAPPLY_S then return end
    item.fovAt = now
    pcall(function() uevrUtils.fixMeshFOV(item.component, "ForegroundFOVEnabled", 0.0, true, false, false) end)
end

-- K2_SetRelative...: plain writes to the Relative* properties only reach the world transform (and the renderer)
-- when the parent next moves, which left a freshly placed item at the anchor's origin for a frame
local function place(key, zoneKey, item)
    local set = Config.sittingExperience and zonesSitting or zonesStanding
    local zone = set[zoneKey]
    if zone == nil then return end
    local s = placementCfg(key, item.placementType)
    local c = item.component
    c:K2_SetRelativeLocationAndRotation(
        uevrUtils.vector((zone.minX + zone.maxX) / 2 + (s.location[1] or 0), (zone.minY + zone.maxY) / 2 + (s.location[2] or 0),
            (zone.minZ + zone.maxZ) / 2 + (s.location[3] or 0)),
        uevrUtils.rotator(s.rotation[1] or 0, s.rotation[2] or 0, s.rotation[3] or 0), false, reusable_hit_result, false)
    if c.RelativeScale3D.X ~= s.scale then
        c:SetRelativeScale3D(uevrUtils.vector(s.scale, s.scale, s.scale))
    end
end

local function hideAll()
    for _, item in pairs(items) do setShown(item, false) end
end

-- Scripted "AnimMontage" sequences and climbing hide the hands (scripts/hands.lua); the body items go with them
-- (2026-10-27).
local function hiddenByScene()
    return gameState.isAnimMontagePlaying or gameState.isClimbing
end

-- ---------------------------------------------------------------------------------------
-- Frame hooks
-- ---------------------------------------------------------------------------------------
local lastTickAt = 0
local lastShownState = {}
local levelChangedAt = os.clock()
local LEVEL_SETTLE_S = 10.0

local function saveIfDirty()
    if not configDirty then return end
    configDirty = false
    pcall(function()
        Config:markDirty()
        Config:save()
    end)
end

-- An external slot: its provider says what to show and builds it; placed, FOV-fixed and hidden here like the rest.
local externalRetryAt = {} -- [slotKey] = os.clock() before which a failed build is not retried
local function updateExternal(pawn, slot)
    local key = slot.key
    local item = items[key]
    local source, note = nil, nil
    if slotCfg(key).enabled ~= false and providers[key] ~= nil then
        local ok, r1, r2 = pcall(providers[key])
        if ok then source, note = r1, r2 else note = "provider failed: " .. tostring(r1) end
    end
    if source == nil then
        if item ~= nil then
            destroyItem(key)
            log(key .. ": removed (" .. tostring(note) .. ")")
        end
        status[key] = note or "hidden"
        return
    end
    if item ~= nil and item.signature ~= source.signature then
        destroyItem(key)
        item = nil
    end
    if item == nil then
        local now = os.clock()
        if (externalRetryAt[key] or 0) > now then return end
        local ok, component, parts = pcall(source.build, pawn)
        if ok and component ~= nil then
            ok = pcall(function()
                component:K2_AttachToComponent(anchor, uevrUtils.fname_from_string("None"), 0, 0, 0, false)
            end)
        end
        if not ok or component == nil then
            externalRetryAt[key] = now + REBUILD_COOLDOWN_S
            status[key] = "could not build: " .. tostring(ok and "nothing built" or component)
            log(key .. ": " .. status[key])
            if ok and component ~= nil then
                items[key] = { component = component, parts = parts or {} }
                destroyItem(key)
            end
            return
        end
        item = { component = component, parts = parts or {}, fovAt = 0, shown = nil, signature = source.signature }
        items[key] = item
        log(key .. ": built " .. tostring(source.signature))
    end
    item.placementType = source.type
    currentType[key] = source.type
    place(key, slot.zone, item)
    fixFOV(item)
    local show = source.hidden ~= true
    setShown(item, show)
    status[key] = (show and "showing " or "in hand: ") .. tostring(source.label or source.signature)
        .. (source.type and (" (" .. source.type .. ")") or "")
end

-- A slot whose item is learned from the hands / the inventory screen.
local function updateLearned(pawn, slot)
    local key = slot.key
    local s = slotCfg(key)
    local path, note = nil, nil
    if s.enabled ~= false then path, note = wantedPath(key) end
    local exists = path ~= nil and loadAsset(path) ~= nil
    local item = items[key]
    if not exists then
        if item ~= nil then destroyItem(key) end
        status[key] = note or (path ~= nil and ("could not load " .. path) or "hidden")
        return
    end
    if item ~= nil and item.path ~= path then
        destroyItem(key)
        item = nil
    end
    if item == nil then
        local asset = loadAsset(path, true)
        if asset ~= nil then item = createItem(pawn, key, asset) end
    end
    if item == nil then return end
    place(key, slot.zone, item)
    fixFOV(item)
    local show = not inHand[key]
    setShown(item, show)
    local shortName = string.match(path, "%.([^%.]+)$") or path
    status[key] = (show and "showing " or "in hand: ") .. shortName
    if (key == "sidearm" or key == "grenade" or key == "bolt") and item.partsWanted == 0 and item.rigOnly then
        -- a weapon rig draws nothing by itself
        status[key] = shortName .. ": parts not known yet - hold it for a few seconds once"
    end
    if lastShownState[key] ~= show then
        lastShownState[key] = show
        log(key .. (show and ": shown on the body" or ": hidden (in hand)"))
    end
end

-- The component of a slot's item while it is shown on the body, else nil (the reload module glides a grabbed mag
-- out of the pouch from here).
function M.getShownComponent(key)
    local item = items[key]
    if item == nil or item.shown ~= true then return nil end
    return item.component
end

-- Build hold (2026-10-18). Nothing is created or rebuilt (items, the reload pouch, the anchor) until
-- BUILD_HOLD_FRAMES gameplay frames AND BUILD_HOLD_S have passed since the last hold: the first tick
-- after the backpack closes, and the suit-swap detection / hands-rig rebuild in Entry.lua. Crash
-- 2026-10-18: closing the backpack after a suit swap rebuilt the sidearm copy and the Rhino pouch in
-- the very tick the pawn was being rebuilt; the engine faulted inside the component setup calls, UEVR
-- swallowed it, and the half-built components crashed the render-submission worker threads.
local BUILD_HOLD_FRAMES = 10
local BUILD_HOLD_S      = 0.25
local frameCount        = 0
local holdUntilFrame    = 0
local holdUntilTime     = 0
local wasInInventory    = false

function M.holdBuilds()
    holdUntilFrame = frameCount + BUILD_HOLD_FRAMES
    holdUntilTime  = os.clock() + BUILD_HOLD_S
end

local function buildsHeld()
    return frameCount < holdUntilFrame or os.clock() < holdUntilTime
end

-- Called from Entry.lua's on_pre_engine_tick (gameplay only).
function M.update()
    lastTickAt = os.clock()
    frameCount = frameCount + 1
    if not M.isEnabled() then
        if next(items) ~= nil then hideAll() end
        return
    end
    local pawn = uevr.api:get_local_pawn(0)
    if pawn == nil then return end
    if hiddenByScene() then
        if next(items) ~= nil then hideAll() end
        return
    end

    local now = os.clock()
    if gameState.isInventoryPDA then -- hidden, and read, by the post-stereo callback below
        wasInInventory = true
        return
    end
    if wasInInventory then
        -- backpack just closed: the game swaps equipment / suit meshes now
        wasInInventory = false
        M.holdBuilds()
    end
    if now >= nextLearnAt then
        nextLearnAt = now + LEARN_INTERVAL_S
        learn()
        saveIfDirty()
    end

    -- existing items stay as they are (placed by the anchor, shown/hidden as last set) until the hold ends
    if buildsHeld() then return end

    if not ensureAnchor(pawn) then return end
    for _, slot in ipairs(SLOTS) do
        if slot.external then
            updateExternal(pawn, slot)
        else
            updateLearned(pawn, slot)
        end
    end
end

-- The anchor follows the head here: the gesture layer's HMD proxy is written by UObjectHook in the stereo pass and
-- only holds the current frame's pose afterwards.
uevrUtils.registerPostCalculateStereoViewCallback(function(device, view_index)
    -- Inventory open: read which items sit in the slots. Done here because Entry.lua's gameplay tick (update())
    -- may not run while a screen is up. Never within LEVEL_SETTLE_S of a level change (see readInventory).
    if gameState.isInventoryPDA and M.isEnabled() then
        local now = os.clock()
        if now >= nextInventoryAt and now - levelChangedAt > LEVEL_SETTLE_S and uevr.api:get_local_pawn(0) ~= nil then
            nextInventoryAt = now + INVENTORY_INTERVAL_S
            local ok, err = pcall(readInventory)
            if not ok then log("inventory read failed: " .. tostring(err)) end
            saveIfDirty()
        end
    end
    if anchor == nil then return end
    -- menus, cutscenes, death: Entry.lua's gameplay tick stops calling update()
    if os.clock() - lastTickAt > 0.25 or gameState.inMenu or gameState.isInventoryPDA or gameState.isInCutscene
       or hiddenByScene() then
        if next(items) ~= nil then
            hideAll()
            lastShownState = {}
        end
        return
    end
    pcall(function()
        local loc = motionControllerActors:GetLocationByIndex(0)
        local rot = motionControllerActors:GetRotationByIndex(0)
        if loc == nil or rot == nil then return end
        anchor:K2_SetWorldLocationAndRotation(uevrUtils.vector(loc.x, loc.y, loc.z), uevrUtils.rotator(0, rot.y, 0), false, reusable_hit_result, false)
    end)
end)

function M.getStatus(key)
    if providers[key] ~= nil then return status[key] or "-" end
    local s = slotCfg(key)
    local icon = s.icon == EMPTY and "(empty)" or (s.icon or "not read yet")
    return (status[key] or "-") .. " | inventory: " .. icon
end

-- Dev panel "forget": the slot shows nothing until its item is drawn again or the inventory is opened.
function M.forgetSlot(key)
    local s = slotCfg(key)
    if type(s.mesh) == "string" then
        cfg().parts[s.mesh] = nil
        partsCaptured[s.mesh] = nil
    end
    s.mesh, s.icon = nil, nil
    destroyItem(key)
    status[key] = "forgotten"
end

-- World references die with the level; never touch them afterwards, just forget them.
function M.onLevelChange()
    forget()
    assetCache = {}
    lastShownState = {}
    levelChangedAt = os.clock()
end

function M.destroy()
    for _, slot in ipairs(SLOTS) do destroyItem(slot.key) end
    pcall(function()
        if anchor ~= nil and anchor.K2_DestroyComponent ~= nil then anchor:K2_DestroyComponent(anchor) end
    end)
    forget()
end

return M
