local ZonedGestures = require("gestures.basezones")
local LocationGestures = require("gestures.locationgesture")

-- Weapon Zone Instances
local reloadZoneRH = ZonedGestures.WeaponZoneGesture:new({
    name = "Weapon Reload Zone (RH)",
    weaponLocationGesture = LocationGestures.LeftHandRelativeToRightLocationGesture,
    minX = -15,
    maxX = 25,
    minY = -12,
    maxY = 12,
    minZ = -30,
    maxZ = 0
})

local reloadZoneLH = ZonedGestures.WeaponZoneGesture:new({
    name = "Weapon Reload Zone (LH)",
    weaponLocationGesture = LocationGestures.RightHandRelativeToLeftLocationGesture,
    minX = -15,
    maxX = 25,
    minY = -12,
    maxY = 12,
    minZ = -30,
    maxZ = 0
})

local modeSwitchZoneRH = ZonedGestures.WeaponZoneGesture:new({
    name = "Weapon Mode Switch Zone (RH)",
    weaponLocationGesture = LocationGestures.LeftHandRelativeToRightLocationGesture,
    minX = -5,
    maxX = 10,
    minY = -12,
    maxY = 12,
    minZ = 0,
    maxZ = 10
})

local modeSwitchZoneLH = ZonedGestures.WeaponZoneGesture:new({
    name = "Weapon Mode Switch Zone (LH)",
    weaponLocationGesture = LocationGestures.RightHandRelativeToLeftLocationGesture,
    minX = -5,
    maxX = 10,
    minY = -12,
    maxY = 12,
    minZ = 0,
    maxZ = 10
})

local barrelZoneRH = ZonedGestures.WeaponZoneGesture:new({
    name = "Weapon Barrel Zone (RH)",
    weaponLocationGesture = LocationGestures.LeftHandRelativeToRightLocationGesture,
    minX = 15,
    maxX = 45,
    minY = -15,
    maxY = 15,
    minZ = 0,
    maxZ = 25
})

local barrelZoneLH = ZonedGestures.WeaponZoneGesture:new({
    name = "Weapon Barrel Zone (LH)",
    weaponLocationGesture = LocationGestures.RightHandRelativeToLeftLocationGesture,
    minX = 15,
    maxX = 45,
    minY = -15,
    maxY = 15,
    minZ = 0,
    maxZ = 25
})

return {
    reloadZoneRH = reloadZoneRH,
    reloadZoneLH = reloadZoneLH,
    modeSwitchZoneRH = modeSwitchZoneRH,
    modeSwitchZoneLH = modeSwitchZoneLH,
    barrelZoneRH = barrelZoneRH,
    barrelZoneLH = barrelZoneLH
}