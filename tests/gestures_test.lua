-- Basic gestures test module
require("luatest")
local TestHelpers = require("test_helpers")
local gestures = require("gestures")
print("\nRunning test suite...")

-- Test 1: Right Hand Flashlight Gesture
-- RunTest("RH FlashLight Gesture Happy Case", function()
--     TestHelpers.resetTestState()
--     TestHelpers.handStates.hmd.location = Vector3f.new(0, 0, 1.7)

--     TestHelpers.preEngineTickCallback(TestHelpers.mockEngine, 0.1) -- Ensure the mock engine is set up
--     AssertEquals(TestHelpers.keyEvents["L_down"], nil, "L_down should be 0 before the test starts")

--     TestHelpers.handStates.right.gripActive = true
--     TestHelpers.preEngineTickCallback(TestHelpers.mockEngine, 0.1) 
--     AssertEquals(TestHelpers.keyEvents["L_down"], nil, "L_down should be 0 before the test starts")

--     TestHelpers.handStates.right.location = Vector3f.new(0.0, 0.0, 1.7)
--     TestHelpers.preEngineTickCallback(TestHelpers.mockEngine, 0.1)
--     AssertEquals(TestHelpers.keyEvents["L_down"], nil, "Gesture Will activate only if grip will be active in zone")

--     TestHelpers.handStates.right.gripActive = false
--     TestHelpers.preEngineTickCallback(TestHelpers.mockEngine, 0.1)
--     AssertEquals(TestHelpers.keyEvents["L_down"], nil, "Grip Deactivate but gesture Wasn't active yet")

--     TestHelpers.handStates.right.gripActive = true
--     TestHelpers.preEngineTickCallback(TestHelpers.mockEngine, 0.1)
--     AssertEquals(TestHelpers.keyEvents["L_down"], 1, "L_down should be 1 after the gesture is activated")
--     AssertEquals(TestHelpers.keyEvents["L_up"], nil, "L_up should not exist after the gesture is activated")

--     TestHelpers.preEngineTickCallback(TestHelpers.mockEngine, 0.1)
--     AssertEquals(TestHelpers.keyEvents["L_down"], 1, "Gesture Remains active")
--     AssertEquals(TestHelpers.keyEvents["L_up"], nil, "L_up should not exist while gesture is active")

--     TestHelpers.handStates.right.gripActive = false
--     TestHelpers.preEngineTickCallback(TestHelpers.mockEngine, 0.1)
--     AssertEquals(TestHelpers.keyEvents["L_down"], 1, "count does not change as gesture deactivated")
--     AssertEquals(TestHelpers.keyEvents["L_up"], 1, "When gesture is inactive we will send Key Up")
--     AssertEquals(TestHelpers.hapticEvents["left_joystick"] or 0, 0, "Haptic event for left joystick should be triggered")
--     AssertEquals(TestHelpers.hapticEvents["right_joystick"] or 0, 1, "Haptic event for right joystick should not be triggered")

--     return true
-- end)

-- Test 2: Left Hand Flashlight Gesture
RunTest("LH FlashLight Gesture Happy Case", function()
    TestHelpers.resetTestState()
    TestHelpers.handStates.hmd.location = Vector3f.new(0, 0, 1.7)

    TestHelpers.preEngineTickCallback(TestHelpers.mockEngine, 0.1)
    AssertEquals(TestHelpers.keyEvents["L_down"], nil, "L_down should be 0 before the test starts")

    TestHelpers.handStates.left.gripActive = true
    TestHelpers.preEngineTickCallback(TestHelpers.mockEngine, 0.1)
    AssertEquals(TestHelpers.keyEvents["L_down"], nil, "L_down should be 0 before the test starts")

    TestHelpers.handStates.left.location = Vector3f.new(0.0, 0.0, 1.7)
    TestHelpers.preEngineTickCallback(TestHelpers.mockEngine, 0.1)
    AssertEquals(TestHelpers.keyEvents["L_down"], nil, "Gesture Will activate only if grip will be active in zone")
    
    TestHelpers.handStates.left.gripActive = false
    TestHelpers.preEngineTickCallback(TestHelpers.mockEngine, 0.1)
    AssertEquals(TestHelpers.keyEvents["L_down"], nil, "Grip Deactivate but gesture Wasn't active yet")
    
    TestHelpers.handStates.left.gripActive = true
    TestHelpers.preEngineTickCallback(TestHelpers.mockEngine, 0.1)
    AssertEquals(TestHelpers.keyEvents["L_down"], 1, "L_down should be 1 after the gesture is activated")
    AssertEquals(TestHelpers.keyEvents["L_up"], nil, "L_up should not exist after the gesture is activated")
    
    TestHelpers.preEngineTickCallback(TestHelpers.mockEngine, 0.1)
    AssertEquals(TestHelpers.keyEvents["L_down"], 1, "Gesture Remains active")
    AssertEquals(TestHelpers.keyEvents["L_up"], nil, "L_up should not exist while gesture is active")

    TestHelpers.handStates.left.gripActive = false
    TestHelpers.preEngineTickCallback(TestHelpers.mockEngine, 0.1)
    AssertEquals(TestHelpers.keyEvents["L_down"], 1, "count does not change as gesture deactivated")
    AssertEquals(TestHelpers.keyEvents["L_up"], 1, "When gesture is inactive we will send Key Up")
    AssertEquals(TestHelpers.hapticEvents["right_joystick"] or 0, 0, "Haptic event for right joystick should be triggered")
    AssertEquals(TestHelpers.hapticEvents["left_joystick"] or 0, 1, "Haptic event for left joystick should not be triggered")
    
    return true
end)

-- Test 3: Right Hand Primary Weapon Gesture
-- RunTest("RH Primary Weapon Gesture Integration Test", function()
--     TestHelpers.resetTestState()
--     TestHelpers.handStates.hmd.location = Vector3f.new(0, 0, 1.7)

--     TestHelpers.preEngineTickCallback(TestHelpers.mockEngine, 0.1) -- Ensure the mock engine is set up
--     AssertEquals(TestHelpers.keyEvents["3_down"], nil, "3_down should be nil before the test starts")

--     -- Set hand to right shoulder zone
--     TestHelpers.handStates.right.location = Vector3f.new(-10, 20, 0)
--     TestHelpers.preEngineTickCallback(TestHelpers.mockEngine, 0.1)
--     AssertEquals(TestHelpers.keyEvents["3_down"], nil, "3_down should still be nil when hand is positioned but no grip")

--     -- Activate grip in shoulder zone
--     TestHelpers.handStates.right.gripActive = true
--     TestHelpers.preEngineTickCallback(TestHelpers.mockEngine, 0.1)
--     AssertEquals(TestHelpers.keyEvents["3_down"], 1, "3_down should register when right grip is pressed near right shoulder")
--     AssertEquals(TestHelpers.keyEvents["3_up"], nil, "3_up should not exist after the gesture is activated")
    
--     -- Keep gesture active
--     TestHelpers.preEngineTickCallback(TestHelpers.mockEngine, 0.1)
--     AssertEquals(TestHelpers.keyEvents["3_down"], 1, "Gesture Remains active - count shouldn't change")
--     AssertEquals(TestHelpers.keyEvents["3_up"], nil, "3_up should not exist while gesture is active")

--     -- Move hand out of zone
--     TestHelpers.handStates.right.location.y = -10
--     TestHelpers.preEngineTickCallback(TestHelpers.mockEngine, 0.1)
--     AssertEquals(TestHelpers.keyEvents["3_down"], 1, "count does not change as gesture deactivated")
--     AssertEquals(TestHelpers.keyEvents["3_up"], 1, "3_up should be sent when the gesture is deactivated")
--     AssertEquals(TestHelpers.hapticEvents["right_joystick"] or 0, 1, "Haptic event for right joystick should be triggered")

--     return true
-- end)

-- Test 4: Left Hand Primary Weapon Gesture
RunTest("LH Primary Weapon Gesture Integration Test", function()
    TestHelpers.resetTestState()
    TestHelpers.handStates.hmd.location = Vector3f.new(0, 0, 1.7)

    TestHelpers.preEngineTickCallback(TestHelpers.mockEngine, 0.1) -- Ensure the mock engine is set up
    AssertEquals(TestHelpers.keyEvents["3_down"], nil, "3_down should be nil before the test starts")

    -- Set hand to left shoulder zone
    TestHelpers.handStates.left.location = Vector3f.new(-10, -20, 0)
    TestHelpers.preEngineTickCallback(TestHelpers.mockEngine, 0.1)
    AssertEquals(TestHelpers.keyEvents["3_down"], nil, "3_down should still be nil when hand is positioned but no grip")

    -- Activate grip in shoulder zone
    TestHelpers.handStates.left.gripActive = true
    TestHelpers.preEngineTickCallback(TestHelpers.mockEngine, 0.1)
    AssertEquals(TestHelpers.keyEvents["3_down"], 1, "3_down should register when left grip is pressed near left shoulder")
    AssertEquals(TestHelpers.keyEvents["3_up"], nil, "3_up should not exist after the gesture is activated")
    
    -- Keep gesture active
    TestHelpers.preEngineTickCallback(TestHelpers.mockEngine, 0.1)
    AssertEquals(TestHelpers.keyEvents["3_down"], 1, "Gesture Remains active - count shouldn't change")
    AssertEquals(TestHelpers.keyEvents["3_up"], nil, "3_up should not exist while gesture is active")

    -- Move hand out of zone
    TestHelpers.handStates.left.location.y = 10
    TestHelpers.preEngineTickCallback(TestHelpers.mockEngine, 0.1)
    AssertEquals(TestHelpers.keyEvents["3_down"], 1, "count does not change as gesture deactivated")
    AssertEquals(TestHelpers.keyEvents["3_up"], 1, "3_up should be sent when the gesture is deactivated")
    AssertEquals(TestHelpers.hapticEvents["left_joystick"] or 0, 1, "Haptic event for left joystick should be triggered")

    return true
end)

-- Test 5: Right Hand Secondary Weapon Gesture
-- RunTest("RH Secondary Weapon Gesture Integration Test", function()
--     TestHelpers.resetTestState()
--     TestHelpers.handStates.hmd.location = Vector3f.new(0, 0, 1.7)

--     TestHelpers.preEngineTickCallback(TestHelpers.mockEngine, 0.1) -- Ensure the mock engine is set up
--     AssertEquals(TestHelpers.keyEvents["4_down"], nil, "4_down should be nil before the test starts")

--     -- Set hand to left shoulder zone
--     TestHelpers.handStates.right.location = Vector3f.new(-10, -20, 0)
--     TestHelpers.preEngineTickCallback(TestHelpers.mockEngine, 0.1)
--     AssertEquals(TestHelpers.keyEvents["4_down"], nil, "4_down should still be nil when hand is positioned but no grip")

--     -- Activate grip in shoulder zone
--     TestHelpers.handStates.right.gripActive = true
--     TestHelpers.preEngineTickCallback(TestHelpers.mockEngine, 0.1)
--     AssertEquals(TestHelpers.keyEvents["4_down"], 1, "4_down should register when right grip is pressed near left shoulder")
--     AssertEquals(TestHelpers.keyEvents["4_up"], nil, "4_up should not exist after the gesture is activated")
    
--     -- Keep gesture active
--     TestHelpers.preEngineTickCallback(TestHelpers.mockEngine, 0.1)
--     AssertEquals(TestHelpers.keyEvents["4_down"], 1, "Gesture Remains active - count shouldn't change")
--     AssertEquals(TestHelpers.keyEvents["4_up"], nil, "4_up should not exist while gesture is active")

--     -- Move hand out of zone
--     TestHelpers.handStates.right.location.y = 10
--     TestHelpers.preEngineTickCallback(TestHelpers.mockEngine, 0.1)
--     AssertEquals(TestHelpers.keyEvents["4_down"], 1, "count does not change as gesture deactivated")
--     AssertEquals(TestHelpers.keyEvents["4_up"], 1, "4_up should be sent when the gesture is deactivated")
--     AssertEquals(TestHelpers.hapticEvents["right_joystick"] or 0, 1, "Haptic event for right joystick should be triggered")

--     return true
-- end)

-- Test 6: Left Hand Secondary Weapon Gesture
RunTest("LH Secondary Weapon Gesture Integration Test", function()
    TestHelpers.resetTestState()
    TestHelpers.handStates.hmd.location = Vector3f.new(0, 0, 1.7)

    TestHelpers.preEngineTickCallback(TestHelpers.mockEngine, 0.1) -- Ensure the mock engine is set up
    AssertEquals(TestHelpers.keyEvents["4_down"], nil, "4_down should be nil before the test starts")

    -- Set hand to right shoulder zone
    TestHelpers.handStates.left.location = Vector3f.new(-10, 20, 0)
    TestHelpers.preEngineTickCallback(TestHelpers.mockEngine, 0.1)
    AssertEquals(TestHelpers.keyEvents["4_down"], nil, "4_down should still be nil when hand is positioned but no grip")

    -- Activate grip in shoulder zone
    TestHelpers.handStates.left.gripActive = true
    TestHelpers.preEngineTickCallback(TestHelpers.mockEngine, 0.1)
    AssertEquals(TestHelpers.keyEvents["4_down"], 1, "4_down should register when left grip is pressed near right shoulder")
    AssertEquals(TestHelpers.keyEvents["4_up"], nil, "4_up should not exist after the gesture is activated")
    
    -- Keep gesture active
    TestHelpers.preEngineTickCallback(TestHelpers.mockEngine, 0.1)
    AssertEquals(TestHelpers.keyEvents["4_down"], 1, "Gesture Remains active - count shouldn't change")
    AssertEquals(TestHelpers.keyEvents["4_up"], nil, "4_up should not exist while gesture is active")

    -- Move hand out of zone
    TestHelpers.handStates.left.location.y = -10
    TestHelpers.preEngineTickCallback(TestHelpers.mockEngine, 0.1)
    AssertEquals(TestHelpers.keyEvents["4_down"], 1, "count does not change as gesture deactivated")
    AssertEquals(TestHelpers.keyEvents["4_up"], 1, "4_up should be sent when the gesture is deactivated")
    AssertEquals(TestHelpers.hapticEvents["left_joystick"] or 0, 1, "Haptic event for left joystick should be triggered")

    return true
end)
