local GestureBase = require("gestures.gesturebase")
local motionControllerActors = require("gestures.motioncontrolleractors")

-- Base Motion Controller Gesture class
local MotionControllerGesture = GestureBase:new({
    name = "Motion Controller Base",
    controllerIndex = 0,
    location = Vector3f.new(0, 0, 0),
    rotation = Vector3f.new(0, 0, 0),
    pastLocation = Vector3f.new(0, 0, 0),
    pastRotation = Vector3f.new(0, 0, 0)
})

function MotionControllerGesture:EvaluateInternal(context)    
    -- Store past values
    self.pastLocation = Vector3f.new(self.location.x, self.location.y, self.location.z)
    self.pastRotation = Vector3f.new(self.rotation.x, self.rotation.y, self.rotation.z)
    
    -- Get current position and rotation
    self.location = motionControllerActors:GetLocationByIndex(self.controllerIndex)
    self.rotation = motionControllerActors:GetRotationByIndex(self.controllerIndex)
    
    return self.location ~= nil and self.rotation ~= nil
end

-- Left Motion Controller Gesture
local LeftMotionControllerGesture = MotionControllerGesture:new({
    name = "Left Motion Controller",
    controllerIndex = 1
})

-- Right Motion Controller Gesture
local RightMotionControllerGesture = MotionControllerGesture:new({
    name = "Right Motion Controller",
    controllerIndex = 2
})

-- HMD Gesture
local HMDGesture = MotionControllerGesture:new({
    name = "HMD",
    controllerIndex = 0
})

-- Base Joystick State Gesture class
local MotionControllerAction = GestureBase:new({
    name = "Joystick Action",
    controllerIndex = 0,
    handle_name = "",
    handle = nil,
    controller = nil,
    isInitialized = false,
})

function MotionControllerAction:InitHandle()
    if not self.isInitialized and self.handle_name then
        self.handle = uevr.params.vr.get_action_handle(self.handle_name)
        if self.controllerIndex == 1 then
            self.controller = uevr.params.vr.get_left_joystick_source()
        else
            self.controller = uevr.params.vr.get_right_joystick_source()
        end
        self.isInitialized = true
    end
end

function MotionControllerAction:EvaluateInternal(context)
    self:InitHandle()
    if not self.isInitialized then
        return false -- Not initialized yet
    end
    return uevr.params.vr.is_action_active(self.handle, self.controller)
end

function MotionControllerAction:Reset()
    GestureBase.Reset(self)
    self.handle = nil
    self.controller = nil
    self.isInitialized = false
end

local LeftGripAction = MotionControllerAction:new({
    name = "Left Grip Action",
    controllerIndex = 1,
    handle_name = "/actions/default/in/Grip"
})

local RightGripAction = MotionControllerAction:new({
    name = "Right Grip Action",
    controllerIndex = 2,
    handle_name = "/actions/default/in/Grip"
})

local LeftTriggerAction = MotionControllerAction:new({
    name = "Left Trigger Action",
    controllerIndex = 1,
    handle_name = "/actions/default/in/Trigger"
})

local RightTriggerAction = MotionControllerAction:new({
    name = "Right Trigger Action",
    controllerIndex = 2,
    handle_name = "/actions/default/in/Trigger"
})

return {
    LeftMotionControllerGesture = LeftMotionControllerGesture,
    RightMotionControllerGesture = RightMotionControllerGesture,
    HMDGesture = HMDGesture,
    LeftGripAction = LeftGripAction,
    RightGripAction = RightGripAction,
    LeftTriggerAction = LeftTriggerAction,
    RightTriggerAction = RightTriggerAction
}