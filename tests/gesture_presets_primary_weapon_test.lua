require("luatest")
local TestHelpers = require("test_helpers")
local GesturePresetsRH = require("stalker2.gesturepresetrh")
local GesturePresetsLH = require("stalker2.gesturepresetlh")
print("\nRunning primary weapon gesture test suite...")

-- Test 1: Left Hand Primary Weapon Gesture for left-handed users
RunTest("LH Primary Weapon Gesture Happy Case", function()
    TestHelpers.resetTestState()
    -- Set up left hand
    local leftHandPrimaryWeapon = GesturePresetsLH.primaryWeaponGesture
    TestHelpers.handStates.left.location = Vector3f.new(-5, -20, 0)
    TestHelpers.handStates.left.rotation = Vector3f.new(0, 45, 0)
    TestHelpers.handStates.left.gripActive = false

    TestHelpers.handStates.hmd.location = Vector3f.new(0, 0, 1.7)
    TestHelpers.handStates.hmd.rotation = Vector3f.new(0, 0, 0)

    -- Test left hand shoulder zone
    leftHandPrimaryWeapon:Reset()
    local Executed = 0
    leftHandPrimaryWeapon:SetExecutionCallback(function(gesture, context)
        print("Left Hand Primary Weapon Gesture Executed")
        Executed = Executed + 1
    end)

    local actors = require("gestures.motioncontrolleractors")
    actors:Update(TestHelpers.mockEngine)
    leftHandPrimaryWeapon:Update({}, {})

    AssertEquals(leftHandPrimaryWeapon.isActive, false, "Primary weapon gesture should not be active initially")
    AssertEquals(leftHandPrimaryWeapon:JustActivated(), false, "Primary weapon gesture should not be activated initially")
    
    TestHelpers.handStates.left.gripActive = true
    actors:Update(TestHelpers.mockEngine)
    leftHandPrimaryWeapon:Update({}, {})
    AssertEquals(leftHandPrimaryWeapon.isActive, true, "Primary weapon gesture should be active when grip is pressed")
    AssertEquals(leftHandPrimaryWeapon:JustActivated(), true, "Primary weapon gesture should be newly activated")
    AssertEquals(Executed, 2, "Primary weapon gesture callback should have executed")

    leftHandPrimaryWeapon:Update({}, {})
    AssertEquals(Executed, 3, "Callback should execute regardless of gesture state")

    -- Move hand out of shoulder zone
    TestHelpers.handStates.left.location.y = 10.0;
    leftHandPrimaryWeapon:Update({}, {})
    AssertEquals(leftHandPrimaryWeapon.isActive, false, "Primary weapon gesture should not be active when out of range")
    AssertEquals(leftHandPrimaryWeapon:JustDeactivated(), true, "Primary weapon gesture should be deactivated when moving out of range")
    AssertEquals(Executed, 4, "Callback should execute irrespective of gesture state")

    leftHandPrimaryWeapon:SetExecutionCallback(nil) -- Clear the callback to avoid side effects in subsequent tests
    return true
end)

-- Test 2: Right Hand Primary Weapon Gesture for right-handed users
RunTest("RH Primary Weapon Gesture Happy Case", function()
    TestHelpers.resetTestState()
    -- Set up right hand
    local rightHandPrimaryWeapon = GesturePresetsRH.primaryWeaponGesture
    TestHelpers.handStates.right.location = Vector3f.new(-10, 20, 0)
    TestHelpers.handStates.right.rotation = Vector3f.new(0, 45, 0)
    TestHelpers.handStates.right.gripActive = false

    TestHelpers.handStates.hmd.location = Vector3f.new(0, 0, 1.7)
    TestHelpers.handStates.hmd.rotation = Vector3f.new(0, 0, 0)

    -- Test right hand shoulder zone
    rightHandPrimaryWeapon:Reset()
    local Executed = 0
    rightHandPrimaryWeapon:SetExecutionCallback(function(gesture, context)
        print("Right Hand Primary Weapon Gesture Executed")
        Executed = Executed + 1
    end)

    local actors = require("gestures.motioncontrolleractors")
    actors:Update(TestHelpers.mockEngine)
    rightHandPrimaryWeapon:Update({}, {})

    AssertEquals(rightHandPrimaryWeapon.isActive, false, "Primary weapon gesture should not be active initially")
    AssertEquals(rightHandPrimaryWeapon:JustActivated(), false, "Primary weapon gesture should not be activated initially")
    
    TestHelpers.handStates.right.gripActive = true
    actors:Update(TestHelpers.mockEngine)
    rightHandPrimaryWeapon:Update({}, {})
    AssertEquals(rightHandPrimaryWeapon.isActive, true, "Primary weapon gesture should be active when grip is pressed")
    AssertEquals(rightHandPrimaryWeapon:JustActivated(), true, "Primary weapon gesture should be newly activated")
    AssertEquals(Executed, 2, "Primary weapon gesture callback should have executed once")

    rightHandPrimaryWeapon:Update({}, {})
    AssertEquals(Executed, 3, "Callback should execute regardless of gesture state")

    -- Move hand out of shoulder zone
    TestHelpers.handStates.right.location.y = -10.0;
    rightHandPrimaryWeapon:Update({}, {})
    AssertEquals(rightHandPrimaryWeapon.isActive, false, "Primary weapon gesture should not be active when out of range")
    AssertEquals(rightHandPrimaryWeapon:JustDeactivated(), true, "Primary weapon gesture should be deactivated when moving out of range")
    AssertEquals(Executed, 4, "Callback should execute irrespective of gesture state")

    rightHandPrimaryWeapon:SetExecutionCallback(nil) -- Clear the callback to avoid side effects in subsequent tests
    return true
end)