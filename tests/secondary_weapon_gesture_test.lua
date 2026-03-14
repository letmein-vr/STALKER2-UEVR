require("luatest")
local TestHelpers = require("test_helpers")
local SecondaryWeaponGesture = require("stalker2.secondaryweapon")
print("\nRunning secondary weapon gesture test suite...")

-- Test 1: Right Hand Secondary Weapon Gesture for right-handed users
RunTest("RH Secondary Weapon Gesture Happy Case", function()
    TestHelpers.resetTestState()
    -- Set up right hand - For right-handed secondary weapon, hand must be in left shoulder zone
    local rightHandSecondaryWeapon = SecondaryWeaponGesture.secondaryWeaponGestureRH
    
    -- Use values that match the left shoulder zone definition in bodyzone.lua
    -- (-10 to 20 X, -30 to -10 Y, -10 to 20 Z)
    TestHelpers.handStates.right.location = Vector3f.new(-5, -20, 0) 
    TestHelpers.handStates.right.rotation = Vector3f.new(0, 45, 0)
    TestHelpers.handStates.right.gripActive = false

    TestHelpers.handStates.hmd.location = Vector3f.new(0, 0, 1.7)
    TestHelpers.handStates.hmd.rotation = Vector3f.new(0, 0, 0)

    -- Test right hand with left shoulder zone
    rightHandSecondaryWeapon:Reset()
    local Executed = 0
    rightHandSecondaryWeapon:SetExecutionCallback(function(gesture, context)
        print("Right Hand Secondary Weapon Gesture Executed")
        Executed = Executed + 1
    end)

    local actors = require("gestures.motioncontrolleractors")
    actors:Update(TestHelpers.mockEngine)
    rightHandSecondaryWeapon:Update({}, {})

    AssertEquals(rightHandSecondaryWeapon.isActive, false, "Secondary weapon gesture should not be active initially")
    AssertEquals(rightHandSecondaryWeapon:JustActivated(), false, "Secondary weapon gesture should not be activated initially")
    
    TestHelpers.handStates.right.gripActive = true
    actors:Update(TestHelpers.mockEngine)
    rightHandSecondaryWeapon:Update({}, {})
    AssertEquals(rightHandSecondaryWeapon.isActive, true, "Secondary weapon gesture should be active when grip is pressed")
    AssertEquals(rightHandSecondaryWeapon:JustActivated(), true, "Secondary weapon gesture should be newly activated")
    rightHandSecondaryWeapon:Update({}, {})
    -- Move hand out of shoulder zone to Y=10 (outside the -30 to -10 range)
    TestHelpers.handStates.right.location.y = 10.0;
    rightHandSecondaryWeapon:Update({}, {})
    AssertEquals(rightHandSecondaryWeapon.isActive, false, "Secondary weapon gesture should not be active when out of range")
    AssertEquals(rightHandSecondaryWeapon:JustDeactivated(), true, "Secondary weapon gesture should be deactivated when moving out of range")
    AssertEquals(Executed, 4, "Callback should execute irrespective of gesture state")

    rightHandSecondaryWeapon:SetExecutionCallback(nil) -- Clear the callback to avoid side effects in subsequent tests
    return true
end)

-- Test 2: Left Hand Secondary Weapon Gesture for left-handed users
RunTest("LH Secondary Weapon Gesture Happy Case", function()
    TestHelpers.resetTestState()
    -- Set up left hand - For left-handed secondary weapon, hand must be in right shoulder zone
    local leftHandSecondaryWeapon = SecondaryWeaponGesture.secondaryWeaponGestureLH
    
    -- Use values that match the right shoulder zone definition in bodyzone.lua
    -- (-10 to 20 X, 10 to 30 Y, -10 to 20 Z)
    TestHelpers.handStates.left.location = Vector3f.new(-5, 20, 0)
    TestHelpers.handStates.left.rotation = Vector3f.new(0, 45, 0)
    TestHelpers.handStates.left.gripActive = false

    TestHelpers.handStates.hmd.location = Vector3f.new(0, 0, 1.7)
    TestHelpers.handStates.hmd.rotation = Vector3f.new(0, 0, 0)

    -- Test left hand right shoulder zone
    leftHandSecondaryWeapon:Reset()
    local Executed = 0
    leftHandSecondaryWeapon:SetExecutionCallback(function(gesture, context)
        print("Left Hand Secondary Weapon Gesture Executed")
        Executed = Executed + 1
    end)

    local actors = require("gestures.motioncontrolleractors")
    actors:Update(TestHelpers.mockEngine)
    leftHandSecondaryWeapon:Update({}, {})

    AssertEquals(leftHandSecondaryWeapon.isActive, false, "Secondary weapon gesture should not be active initially")
    AssertEquals(leftHandSecondaryWeapon:JustActivated(), false, "Secondary weapon gesture should not be activated initially")
    
    TestHelpers.handStates.left.gripActive = true
    actors:Update(TestHelpers.mockEngine)
    leftHandSecondaryWeapon:Update({}, {})
    AssertEquals(leftHandSecondaryWeapon.isActive, true, "Secondary weapon gesture should be active when grip is pressed")
    AssertEquals(leftHandSecondaryWeapon:JustActivated(), true, "Secondary weapon gesture should be newly activated")

    leftHandSecondaryWeapon:Update({}, {})
    -- Move hand out of right shoulder zone to Y=-10 (outside the 10 to 30 range)
    TestHelpers.handStates.left.location.y = -10.0;
    leftHandSecondaryWeapon:Update({}, {})
    AssertEquals(leftHandSecondaryWeapon.isActive, false, "Secondary weapon gesture should not be active when out of range")
    AssertEquals(leftHandSecondaryWeapon:JustDeactivated(), true, "Secondary weapon gesture should be deactivated when moving out of range")
    AssertEquals(Executed, 4, "Callback should execute irrespective of gesture state")

    leftHandSecondaryWeapon:SetExecutionCallback(nil) -- Clear the callback to avoid side effects in subsequent tests
    return true
end)