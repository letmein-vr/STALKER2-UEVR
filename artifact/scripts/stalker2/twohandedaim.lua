--[[
    GripGesture.lua
    Base class for gestures that activate when a motion controller is in a specific zone and grip button is pressed
]]--

local GestureBase = require("gestures.gesturebase")
local motionControllers = require("gestures.motioncontrollergestures")

-- GripGesture: Base class for grip-based gestures
local TwoHandedAimGesture = GestureBase:new({
    name = "Double Grip Gesture Base",
    leftGripGesture = nil,
    rightGripGesture = nil,
    zone = nil,
})

function TwoHandedAimGesture:new(config)
    -- Set up dependencies
    config = config or {}
    
    local instance = GestureBase.new(self, config)
    
    -- Verify required properties after the instance is created
    if not instance.leftGripGesture then
        error("gripGesture is required for GripGesture")
    end
    if not instance.rightGripGesture then
        error("gripGesture is required for GripGesture")
    end
    if not instance.zone then
        error("zone is required for GripGesture")
    end
    
    instance:AddDependency(instance.leftGripGesture) -- Ensure gripGesture is a dependency
    instance:AddDependency(instance.rightGripGesture) -- Ensure gripGesture is a dependency
    instance:AddDependency(instance.zone) -- Ensure zone is a dependency
    return instance
end

-- Weapons that must never enter two-handed mode (2026-09-21). Keys are lowercase prefixes of the
-- weapon's SkeletalMesh short name, the same naming ptm_manual_reload.lua's WEAPON_PROFILES uses.
-- The RPG-7 is shoulder-fired one-handed here, and its muzzle is also the manual-reload insert
-- target, so a left grip near the tube must stay free for the rocket instead of snapping into a
-- two-handed aim. A saved Config.weaponProfiles[<name>].disableTwoHanding = true does the same
-- for any other weapon without touching this table.
local NO_TWO_HANDING = {
    "sk_rpg7",
}

local function isTwoHandingDisabledForEquippedWeapon()
    local disabled = false
    pcall(function()
        local gameState = require("stalker2.gamestate")
        local mesh = gameState._frameWeapon
        if mesh == nil then return end
        local info = gameState:GetWeaponCache(mesh)
        local name = info and info.name
        if type(name) ~= "string" then return end
        local profile = Config and Config.weaponProfiles and Config.weaponProfiles[name]
        if profile and profile.disableTwoHanding == true then
            disabled = true
            return
        end
        local lower = string.lower(name)
        for _, prefix in ipairs(NO_TWO_HANDING) do
            if string.sub(lower, 1, #prefix) == prefix then
                disabled = true
                return
            end
        end
    end)
    return disabled
end

function TwoHandedAimGesture:EvaluateInternal(context)
    -- Nothing to decide unless the left grip is held - keeps the weapon lookup below off the
    -- idle path entirely.
    if not self.leftGripGesture.isActive then
        return false
    end
    -- No weapon, nothing to two-hand (2026-10-27). The sticky "still gripping" case below kept
    -- two-handing on after a Burer stripped the weapon, so Entry.lua left the off hand targeted on
    -- the stripped mesh while it flew away (IK left arm stretched out after it).
    if require("stalker2.gamestate")._frameWeapon == nil then
        return false
    end
    -- the left hand is reaching for the slide / charging handle (manual reload rack to chamber)
    if _G.ptmBlocksTwoHanding ~= nil and _G.ptmBlocksTwoHanding() then
        return false
    end
    -- Checked for the sticky "still gripping" case too, so switching TO such a weapon while
    -- two-handing drops the mode instead of carrying it over.
    if (self.zone.isActive or self.wasActive) and isTwoHandingDisabledForEquippedWeapon() then
        return false
    end
    -- Modified: Removed self.rightGripGesture check per user request.
    -- Only Left Grip + Proximity Zone is needed.
    local justActivated = not self.leftGripGesture:IsLocked() and self.leftGripGesture.isActive and self.zone.isActive
    if justActivated then
        return true
    end
    -- Maintain state if Left Grip is still held (removed right grip check here too)
    -- Check if we should deactivate based on zone? Usually gestures stick until grip release.
    -- If we want "sticky" behavior where you can move hand away from zone while gripping:
    return self.wasActive and self.leftGripGesture.isActive 
end

return TwoHandedAimGesture