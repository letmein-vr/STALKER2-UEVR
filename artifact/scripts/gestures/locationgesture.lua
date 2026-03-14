local utils = require("common.utils")
local GestureBase = require("gestures.gesturebase")
local motionControllers = require("gestures.motioncontrollergestures")

-- Base Location Gesture class
local LocationGestureBase = GestureBase:new({
    name = "Location Gesture Base",
    location = Vector3f.new(0, 0, 0),
    rotation = Vector3f.new(0, 0, 0),
    weaponLocation = Vector3f.new(0, 0, 0)
})

function LocationGestureBase:new(config)
    config = config or {}
    config.location = Vector3f.new(0, 0, 0)
    config.rotation = Vector3f.new(0, 0, 0)
    config.weaponLocation = Vector3f.new(0, 0, 0)
    config.kismet_math_library = utils.find_static_class("Class /Script/Engine.KismetMathLibrary")
    local instance = GestureBase.new(self, config)
    return instance
end

-- Left Hand Location Gesture
local LeftHandLocationGesture = LocationGestureBase:new({
    name = "Left Hand Location",
    leftHand = nil,
    hmd = nil
})

function LeftHandLocationGesture:new(config)
    config = config or {}
    -- Populate dependencies from fields
    config.leftHand = motionControllers.LeftMotionControllerGesture
    config.hmd = motionControllers.HMDGesture

    local instance = GestureBase.new(self, config)
    instance:AddDependency(instance.leftHand)
    instance:AddDependency(instance.hmd)
    return instance
end

function LeftHandLocationGesture:EvaluateInternal(context)
    if not self.leftHand or not self.hmd then
        return false
    end

    -- Calculate HMD-relative position
    local rotDiff = self.hmd.rotation.y
    local dx = self.leftHand.location.x - self.hmd.location.x
    local dy = self.leftHand.location.y - self.hmd.location.y
    
    self.location.x = dx * math.cos(-rotDiff/180*math.pi) - dy * math.sin(-rotDiff/180*math.pi)
    self.location.y = dx * math.sin(-rotDiff/180*math.pi) + dy * math.cos(-rotDiff/180*math.pi)
    self.location.z = self.leftHand.location.z - self.hmd.location.z
    
    return true
end

-- Right Hand Location Gesture
local RightHandLocationGesture = LocationGestureBase:new({
    name = "Right Hand Location",
    rightHand = nil,
    hmd = nil
})

function RightHandLocationGesture:new(config)
    config = config or {}
    config.rightHand = motionControllers.RightMotionControllerGesture
    config.hmd = motionControllers.HMDGesture

    local instance = GestureBase.new(self, config)
    instance:AddDependency(instance.rightHand)
    instance:AddDependency(instance.hmd)
    return instance
end

function RightHandLocationGesture:EvaluateInternal(context)
    if not self.rightHand or not self.hmd then
        return false
    end

    -- Calculate HMD-relative position
    local rotDiff = self.hmd.rotation.y
    local dx = self.rightHand.location.x - self.hmd.location.x
    local dy = self.rightHand.location.y - self.hmd.location.y
    
    self.location.x = dx * math.cos(-rotDiff/180*math.pi) - dy * math.sin(-rotDiff/180*math.pi)
    self.location.y = dx * math.sin(-rotDiff/180*math.pi) + dy * math.cos(-rotDiff/180*math.pi)
    self.location.z = self.rightHand.location.z - self.hmd.location.z
    
    return true
end

-- Left Hand Weapon Location Gesture
local LeftHandRelativeToRightLocationGesture = LocationGestureBase:new({
    name = "Left Hand Weapon Location",
    leftHand = nil,
    rightHand = nil,
    weaponLocation = Vector3f.new(0, 0, 0)
})

function LeftHandRelativeToRightLocationGesture:new(config)
    config = config or {}
    -- Populate dependencies from fields
    config.leftHand = motionControllers.LeftMotionControllerGesture
    config.rightHand = motionControllers.RightMotionControllerGesture
    local instance = GestureBase.new(self, config)
    instance:AddDependency(instance.leftHand)
    instance:AddDependency(instance.rightHand)
    return instance
end

function LeftHandRelativeToRightLocationGesture:EvaluateInternal(context)
    if not self.leftHand or not self.rightHand or
       not self.leftHand.isActive or not self.rightHand.isActive then
        return false
    end

    local right_hand_rotation_q = self.kismet_math_library:Conv_RotatorToQuaternion(self.rightHand.rotation)
    local right_hand_rotation_inv_q = self.kismet_math_library:Quat_Inversed(right_hand_rotation_q)
    local location_diff = self.leftHand.location - self.rightHand.location
    self.weaponLocation = self.kismet_math_library:Quat_RotateVector(right_hand_rotation_inv_q, location_diff)
    return true
end

-- Right Hand Weapon Location Gesture
local RightHandRelativeToLeftLocationGesture = LocationGestureBase:new({
    name = "Right Hand Weapon Location",
    rightHand = nil,
    leftHand = nil,
    weaponLocation = Vector3f.new(0, 0, 0)
})

function RightHandRelativeToLeftLocationGesture:new(config)
    config = config or {}
    -- Populate dependencies from fields
    config.leftHand = motionControllers.LeftMotionControllerGesture
    config.rightHand = motionControllers.RightMotionControllerGesture
    local instance = GestureBase.new(self, config)
    instance:AddDependency(instance.leftHand)
    instance:AddDependency(instance.rightHand)
    return instance
end

function RightHandRelativeToLeftLocationGesture:EvaluateInternal(context)
    if not self.rightHand or not self.leftHand then
        return false
    end

    local left_hand_rotation_q = self.kismet_math_library:Conv_RotatorToQuaternion(self.leftHand.rotation)
    local left_hand_rotation_inv_q = self.kismet_math_library:Quat_Inversed(left_hand_rotation_q)
    local location_diff = self.rightHand.location - self.leftHand.location
    self.weaponLocation = self.kismet_math_library:Quat_RotateVector(left_hand_rotation_inv_q, location_diff)    
    return true
end

local LeftHand = LeftHandLocationGesture:new()
local RightHand = RightHandLocationGesture:new()
local LeftHandRelativeToRight = LeftHandRelativeToRightLocationGesture:new()
local RightHandRelativeToLeft = RightHandRelativeToLeftLocationGesture:new()

return {
    LeftHand = LeftHand,
    RightHand = RightHand,
    LeftHandRelativeToRightLocationGesture = LeftHandRelativeToRight,
    RightHandRelativeToLeftLocationGesture = RightHandRelativeToLeft
}