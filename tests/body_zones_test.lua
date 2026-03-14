require("luatest")
local TestHelpers = require("test_helpers")

print("\nRunning test suite...")

-- -- Test 1: Both hands near head with grip
RunTest("HeadZone test", function()
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
    local rhExecuted = false
    headZoneRH:SetExecutionCallback(function(gesture, context)
        print("Right Hand Head Zone Executed")
        rhExecuted = true
    end)

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
    local lhExecuted = false
    headZoneLH:SetExecutionCallback(function(gesture, context)
        print("Left Hand Head Zone Executed")
        lhExecuted = true
    end)
    
    actors:Update(TestHelpers.mockEngine)
    headZoneLH:Update({}, {})
    
    AssertEquals(headZoneLH.isActive, true, "Left hand should be detected in head zone when positioned at head level")
    
    TestHelpers.handStates.left.location.z = 100.0
    headZoneLH:Update({}, {})
    AssertEquals(headZoneLH.isActive, false, "Left hand should not be detected in head zone when far above head level")

    return true
end)
