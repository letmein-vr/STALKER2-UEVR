require("Config.CONFIG")
local GestureBase = require("gestures.gesturebase")

-- Base Body Zone Gesture class
local BodyZoneGesture = GestureBase:new({
    name = "Body Zone Gesture Base",
    locationGesture = nil,
    
    -- Zone boundaries
    minX = 0,
    maxX = 0,
    minY = 0,
    maxY = 0,
    minZ = 0,
    maxZ = 0
})

function BodyZoneGesture:new(config)
    config = config or {}
    -- Populate dependencies from fields
    if not config.locationGesture then
        error("locationGesture is required for BodyZoneGesture")
    end
    local instance = GestureBase.new(self, config)
    instance:AddDependency(instance.locationGesture)
    return instance
end

function BodyZoneGesture:EvaluateInternal(context)
    if not self.locationGesture or not self.locationGesture.isActive then
        return false
    end

    local x = self.locationGesture.location.x
    local y = self.locationGesture.location.y
    local z = self.locationGesture.location.z

    return x >= self.minX and x <= self.maxX and
           y >= self.minY and y <= self.maxY and
           z >= self.minZ and z <= self.maxZ
end

-- Base Weapon Zone Gesture class
local WeaponZoneGesture = GestureBase:new({
    name = "Weapon Zone Gesture Base",
    weaponLocationGesture = nil,
    
    -- Zone boundaries
    minX = 0,
    maxX = 0,
    minY = 0,
    maxY = 0,
    minZ = 0,
    maxZ = 0
})

function WeaponZoneGesture:new(config)
    config = config or {}
    if not config.weaponLocationGesture then
        error("weaponLocationGesture is required for WeaponZoneGesture")
    end
    local instance = GestureBase.new(self, config)
    instance:AddDependency(instance.weaponLocationGesture) -- Ensure weaponLocationGesture is a dependency
    return instance
end

function WeaponZoneGesture:EvaluateInternal(context)
    if not self.weaponLocationGesture or not self.weaponLocationGesture.isActive then
        return false
    end

    local x = self.weaponLocationGesture.weaponLocation.x
    local y = self.weaponLocationGesture.weaponLocation.y
    local z = self.weaponLocationGesture.weaponLocation.z

    return x >= self.minX and x <= self.maxX and
           y >= self.minY and y <= self.maxY and
           z >= self.minZ and z <= self.maxZ
end

return {
    BodyZoneGesture = BodyZoneGesture,
    WeaponZoneGesture = WeaponZoneGesture
}