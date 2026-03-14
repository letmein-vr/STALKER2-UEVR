-- Basic gestures test module
require("luatest")
local TestHelpers = require("test_helpers")

print("\nRunning test suite...")

RunTest("Left Grip Action", function()
    TestHelpers.resetTestState()

    local MotionControllerGestures = require("gestures.motioncontrollergestures")
    local leftGripAction = MotionControllerGestures.LeftGripAction

    leftGripAction:Reset()
    TestHelpers.handStates.left.gripActive = false

    leftGripAction:Update({}, {})
    AssertEquals(leftGripAction:JustDeactivated(), false, "Left grip action should not report as just deactivated when never active")
    
    -- Create a new visited table for first update
    leftGripAction:Update({}, {})
    AssertEquals(leftGripAction.isActive, false, "Left grip action should not be active when grip button is not pressed")
    AssertEquals(leftGripAction:JustDeactivated(), false, "Left grip action should not report as just deactivated when never active")

    -- Now let's test activation
    TestHelpers.handStates.left.gripActive = true

    -- Create a new visited table for second update
    leftGripAction:Update({}, {})
    AssertEquals(leftGripAction.isActive, true, "Left grip action should become active when grip button is pressed")
    AssertEquals(leftGripAction:JustActivated(), true, "Left grip action should report as just activated when grip becomes active")
    return true
end)

RunTest("Right Grip Action", function()
    TestHelpers.resetTestState()

    local MotionControllerGestures = require("gestures.motioncontrollergestures")
    local rightGripAction = MotionControllerGestures.RightGripAction

    rightGripAction:Reset()
    TestHelpers.handStates.right.gripActive = false

    rightGripAction:Update({}, {})
    AssertEquals(rightGripAction:JustDeactivated(), false, "Right grip action should not report as just deactivated when never active")
    
    -- Create a new visited table for first update
    rightGripAction:Update({}, {})
    AssertEquals(rightGripAction.isActive, false, "Right grip action should not be active when grip button is not pressed")
    AssertEquals(rightGripAction:JustDeactivated(), false, "Right grip action should not report as just deactivated when never active")
    -- Now let's test activation
    TestHelpers.handStates.right.gripActive = true

    -- Create a new visited table for second update
    rightGripAction:Update({}, {})
    AssertEquals(rightGripAction.isActive, true, "Right grip action should become active when grip button is pressed")
    AssertEquals(rightGripAction:JustActivated(), true, "Right grip action should report as just activated when grip becomes active")
    rightGripAction:SetExecutionCallback(nil)
    return true
end)

RunTest("Both hands near head with grip", function()
    TestHelpers.resetTestState()
    -- Set up left hand
    TestHelpers.handStates.left.location = Vector3f.new(0.0, 0.0, 1.7)
    TestHelpers.handStates.left.rotation = Vector3f.new(0, 45, 0)
    TestHelpers.handStates.left.gripActive = true
    
    -- Set up right hand
    TestHelpers.handStates.right.location = Vector3f.new(-0.0, 0.0, 1.7)
    TestHelpers.handStates.right.rotation = Vector3f.new(0, -45, 0)
    TestHelpers.handStates.right.gripActive = true

    TestHelpers.handStates.hmd.location = Vector3f.new(0, 0, 1.7)
    TestHelpers.handStates.hmd.rotation = Vector3f.new(0, 0, 0)

    local MotionControllerGestures = require("gestures.bodyzone")
    local headZoneRH = MotionControllerGestures.headZoneRH
    local headZoneLH = MotionControllerGestures.headZoneLH
    local actors = require("gestures.motioncontrolleractors")

    -- Test right hand head zone
    headZoneRH:Reset()
    actors:Update(TestHelpers.mockEngine)
    headZoneRH:Update({}, {})

    AssertEquals(headZoneRH.isActive, true, "Right hand should be detected in head zone when positioned at head level")

    TestHelpers.handStates.right.location.z = 100.0
    headZoneRH:Update({}, {})
    AssertEquals(headZoneRH.isActive, false, "Right hand should not be detected in head zone when far above head level")
    
    -- Reset right hand position
    TestHelpers.handStates.right.location.z = 1.7
    
    -- Test left hand head zone
    headZoneLH:Reset()
    actors:Update(TestHelpers.mockEngine)
    headZoneLH:Update({}, {})
    
    AssertEquals(headZoneLH.isActive, true, "Left hand should be detected in head zone when positioned at head level")
    
    TestHelpers.handStates.left.location.z = 100.0
    headZoneLH:Update({}, {})
    AssertEquals(headZoneLH.isActive, false, "Left hand should not be detected in head zone when far above head level")

    return true
end)
