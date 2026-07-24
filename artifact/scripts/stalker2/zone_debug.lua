-- We do not require uobjecthook as a module, it is typically accessed raw or via uevr API
local utils = require("common.utils")
local motionControllerActors = require("gestures.motioncontrolleractors")
local weaponZones = require("gestures.weaponzones")

local M = {}
local isVisible = false
local debugBoxes = {}
local BoxCompClass = nil

local function getBoxClass()
    if BoxCompClass then return BoxCompClass end
    BoxCompClass = uevr.api:find_uobject("Class /Script/Engine.BoxComponent")
    return BoxCompClass
end

-- Create a box for a specific zone and attach to the specified parent
local function create_box(pawn, parent_comp, zone, colorObj)
    local cls = getBoxClass()
    if not cls then return nil end

    local ok, box = pcall(function()
        return uevr.api:add_component_by_class(pawn, cls)
    end)
    if not ok or not utils.validate_object(box) then return nil end

    pcall(function()
        box:K2_AttachToComponent(parent_comp, "Root", 0, 0, 0, true)
    end)

    box:SetCollisionResponseToAllChannels(0) -- Disable physics/overlap completely
    box:SetGenerateOverlapEvents(false)
    box:SetCollisionEnabled(0)

    -- Calculate scale and location
    -- UE default box half-extent is 32 -> total size 64
    local sizeX = zone.maxX - zone.minX
    local sizeY = zone.maxY - zone.minY
    local sizeZ = zone.maxZ - zone.minZ

    local centerX = (zone.minX + zone.maxX) / 2
    local centerY = (zone.minY + zone.maxY) / 2
    local centerZ = (zone.minZ + zone.maxZ) / 2

    box.RelativeScale3D.X = sizeX / 64.0
    box.RelativeScale3D.Y = sizeY / 64.0
    box.RelativeScale3D.Z = sizeZ / 64.0

    box.RelativeLocation.X = centerX
    box.RelativeLocation.Y = centerY
    box.RelativeLocation.Z = centerZ

    -- UE box visualization usually inherits class colors, but we can just unhide it
    box.bHiddenInGame = not isVisible

    return box
end

function M.init(pawn)
    if not utils.validate_object(pawn) then return end
    if #debugBoxes > 0 then return end -- Already initialized

    local leftParent = motionControllerActors.left_hand_component
    local rightParent = motionControllerActors.right_hand_component

    if not utils.validate_object(leftParent) or not utils.validate_object(rightParent) then
        return
    end

    -- RH gestures use right hand as origin (LeftHandRelativeToRightLocationGesture)
    table.insert(debugBoxes, create_box(pawn, rightParent, weaponZones.barrelZoneRH))
    table.insert(debugBoxes, create_box(pawn, rightParent, weaponZones.reloadZoneRH))
    table.insert(debugBoxes, create_box(pawn, rightParent, weaponZones.modeSwitchZoneRH))

    -- LH gestures use left hand as origin (RightHandRelativeToLeftLocationGesture)
    table.insert(debugBoxes, create_box(pawn, leftParent, weaponZones.barrelZoneLH))
    table.insert(debugBoxes, create_box(pawn, leftParent, weaponZones.reloadZoneLH))
    table.insert(debugBoxes, create_box(pawn, leftParent, weaponZones.modeSwitchZoneLH))
end

function M.set_visible(visible)
    isVisible = visible
    for _, box in ipairs(debugBoxes) do
        if utils.validate_object(box) then
            box.bHiddenInGame = not visible
        end
    end
end

function M.is_visible()
    return isVisible
end

return M
