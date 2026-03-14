-- Colors for console output if supported
local colors = {
    reset = "\27[0m",
    red = "\27[31m",
    green = "\27[32m",
    yellow = "\27[33m",
    blue = "\27[34m"
}

-- Assert functions
function AssertEquals(actual, expected, message)
    if expected == actual then
        print(colors.green .. "[✓]" .. colors.reset .. " " .. message)
        return true
    else
        local msg = "Expected: " .. tostring(expected) .. ", got: " .. tostring(actual)
        print(colors.red .. "[✗]" .. colors.reset .. " " ..  msg)
        print(debug.traceback())
    end
end

function AssertTrue(value, message)
    return AssertEquals(value, true, message)
end

function AssertFalse(value, message)
    return AssertEquals(value, false, message)
end


-- Run a single test with given hand states
function RunTest(testName, testFn)
    print("\nRunning test: " .. testName)
    local success, result = pcall(testFn)
    
    if not success then
        print("✗ Test failed: " .. testName .. " with error: " .. tostring(result))
        return false
    elseif not result then
        print("✗ Test failed: " .. testName)
        return false
    else
        print("✓ Test passed: " .. testName)
        return true
    end
end