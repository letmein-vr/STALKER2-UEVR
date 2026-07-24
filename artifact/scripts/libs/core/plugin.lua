
--[[
    This module allows you call any function in the game's SDK without limitations such
    as the TArray issue that may exist in native lua calls. Notice that this module itself
    does not require the rest of uevrUtils in order to be used in your project. The function
    takes any valid uevr/unreal objects and structures with or without uevrUtils.

    Can be called Asynchronously or Synchronously
    Examples:
        local plugin = require("libs/core/plugin")

        plugin.showDebug = true
        local location = component:K2_GetComponentLocation()
        local radius = 20
        local objectTypes = {0,5,14,19}
        local classFilter = uevrUtils.get_class("Class /Script/Engine.PrimitiveComponent")
        local ignoreActors = {pawn}
        local foundComponents = {}
    
        -- Asynchronous call
        local resultCallback = plugin.executeFunctionAsync(kismet_system_library, "SphereOverlapComponents", uevrUtils.get_world(), location, radius, objectTypes, classFilter, ignoreActors, foundComponents)
        resultCallback(function(result)
            local components = result.OutComponents or {}
            for i = 1, #components do
                local comp = components[i]
                print("Component:", comp:get_full_name())
            end
        end)

        -- Synchronous call
        local result = plugin.executeFunction(kismet_system_library, "SphereOverlapComponents", uevrUtils.get_world(), location, radius, objectTypes, classFilter, ignoreActors, foundComponents)
        if result ~= nil then
            local components = result.OutComponents or {}
            for i = 1, #components do
                local comp = components[i]
                print("Component:", comp:get_full_name())
            end
        end

]]--
local M = {}

M.showDebug = false

local pendingExecuteFunctionCallbacks = {}

local function guid()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function (c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end)
end

local function convertInputStruct(arg)
    local out = {}
	if arg.get_struct ~= nil then
		local childProperty = arg:get_struct():get_child_properties()
		if childProperty == nil then
			--ValueStr = string.format("%s %s %s\n\t%s", UEVR_UStruct.static_class(Value):get_full_name(), Value, Value:get_struct(), "<Empty>")
			print("!!!Empty structure childProperty found", arg)
---@diagnostic disable-next-line: cast-local-type
            out = string.format("%s", "")
		else
			while childProperty ~= nil do
                local propName = childProperty:get_fname():to_string()
                if M.showDebug then print(propName,childProperty:get_class():get_name()) end
                if childProperty:get_class():get_name() == "ArrayProperty" then
                    out[propName] = M.convertInputParams(arg[propName])
                elseif childProperty:get_class():get_name() == "StructProperty" then
                    out[propName] = convertInputStruct(arg[propName])
                else
                    out[propName] = arg[propName]
                end
				childProperty = childProperty:get_next()
			end
		end
	elseif string.match(string.format("%s",arg), "sol.glm::vec<3,float,0>*" ) then
		out = {X=arg.X, Y=arg.Y, Z=arg.Z }
	elseif string.match(string.format("%s",arg), "sol.glm::vec<3,double,0>*" ) then
		out = {X=arg.X, Y=arg.Y, Z=arg.Z }
	else
		print("!!!Unknown Struct type found!!!",UEVR_UStruct.static_class(arg):get_full_name(), arg)
		print(type(arg),arg:get_field_name())
	end
    return out
end

--loop through all args recursively and convert any uobject to its address
local function convertInputParams(argsArray)
	for i, arg in ipairs(argsArray) do
		if M.showDebug then print("Argument is type", type(arg)) end
		if type(arg) == "userdata" then
            if arg.get_struct ~= nil then
	            if M.showDebug then print("this object is a struct") end
                argsArray[i] = convertInputStruct(arg)
	        elseif arg.get_address then --its an object whose address can be retrieved
			    argsArray[i] = arg:get_address()
            elseif string.match(string.format("%s",arg), "sol.glm::vec<3,float,0>*" ) then
                argsArray[i] = {X=arg.X, Y=arg.Y, Z=arg.Z }
            elseif string.match(string.format("%s",arg), "sol.glm::vec<3,double,0>*" ) then
                argsArray[i] = {X=arg.X, Y=arg.Y, Z=arg.Z }
            end

		end
		if type(arg) == "table" then
			convertInputParams(arg)
		end
	end
end
function M.convertInputParams(argsArray)
    convertInputParams(argsArray)
end

-- function M.executeFunction(callerObject, functionName, ...)
-- 	local argsArray = {...}
-- 	-- The last item in the array is the callback function, get it and remove it from the argsArray
-- 	local callback = nil
-- 	if #argsArray > 0 and type(argsArray[#argsArray]) == "function" then
-- 		callback = argsArray[#argsArray]
-- 		table.remove(argsArray, #argsArray)
-- 	end

-- 	convertInputParams(argsArray)

-- 	local data =
-- 	{
-- 		debug = M.showDebug,
-- 		caller_object = callerObject:get_address(),
-- 		function_name = functionName,
-- 		params = argsArray
-- 	}
--     if M.showDebug then print("ExecuteFunction dispatching for function:\n", functionName, json.dump_string(data)) end
-- 	local callID = "ExecuteFunction_" .. guid()
-- 	pendingExecuteFunctionCallbacks[callID] = callback
-- 	uevr.api:dispatch_custom_event(callID, json.dump_string(data))
-- end

-- local function convertData(dataType, dataValue)
--     if dataType == "ObjectProperty" then 
--         return uevr.api:to_uobject(dataValue)
--     else
--         return dataValue
--     end
-- end
-- local function convertResultData(inData)
--     local outData = {}
--     for key, data in inData do
--         outData[key] = {}
--         if type(data) == "table" then

--         else
--             outData[key] = convertData(data.type, data.value)
--         end
--     end
-- end

local function convertResultDataType(dataType, dataValue)
    if dataType == "ObjectProperty" then
        return uevr.api:to_uobject(dataValue)

    -- FIX: Intercept StructProperties and force the recursion to process its inner fields
    elseif dataType == "StructProperty" then
        if type(dataValue) == "table" then
            return M.convertResultData(dataValue)
        else
            return dataValue
        end

    else
        return dataValue
    end
end

-- Helper function to check if a table represents a {"type": ..., "value": ...} property block
local function isPropertyBlock(t)
    return type(t) == "table" and t.type ~= nil and t.value ~= nil
end

function M.convertResultData(inData)
    -- Base case: if it's a property block, unpack it immediately
    if isPropertyBlock(inData) then
        return convertResultDataType(inData.type, inData.value)
    end

    -- If it's a regular table (either an array or an object map), process its children
    if type(inData) == "table" then
        local outData = {}
        for key, data in pairs(inData) do
            outData[key] = M.convertResultData(data)
        end
        return outData
    end

    -- Fallback for raw primitive data types
    return inData
end

local function printTableStructure(tbl, indent)
    indent = indent or ""

    for key, val in pairs(tbl) do
        local valType = type(val)

        if valType == "table" then
            -- Check if it's an array-like table or a standard dictionary
            if #val > 0 then
                print(string.format("%s[\"%s\"] = Array (Size: %d):", indent, tostring(key), #val))
            else
                print(string.format("%s[\"%s\"] = Dictionary/Table:", indent, tostring(key)))
            end
            -- Recursively print inner elements
            printTableStructure(val, indent .. "    ")

        elseif valType == "userdata" then
            -- This validates that uevr.api:to_uobject() successfully converted the value
            print(string.format("%s[\"%s\"] = %s (Userdata/UObject Instance)", indent, tostring(key), tostring(val)))

        else
            -- Print primitive types like booleans, strings, or numbers
            print(string.format("%s[\"%s\"] = %s (%s)", indent, tostring(key), tostring(val), valType))
        end
    end
end
-- uevr.sdk.callbacks.on_lua_event(function(eventName, eventData)
--     if M.showDebug then print("--------- ExecuteFunction raw return value -------------:\n", eventData) end
-- 	if pendingExecuteFunctionCallbacks[eventName] ~= nil then
--         local result = M.convertResultData(json.load_string(eventData))
--         if M.showDebug then
--             print("--------- ExecuteFunction Converted structure -------------")
--             printTableStructure(result)
--         end
--         pendingExecuteFunctionCallbacks[eventName](result)
-- 		pendingExecuteFunctionCallbacks[eventName] = nil
--     end
-- end)


local AsyncRegistry = {}

function M.executeFunctionAsync(callerObject, functionName, ...)
    local argsArray = {...}
	convertInputParams(argsArray)

	local data =
	{
		debug = M.showDebug,
		caller_object = callerObject:get_address(),
		function_name = functionName,
		params = argsArray
	}
    if M.showDebug then print("ExecuteFunction dispatching for function:\n", functionName, json.dump_string(data)) end
	local callID = "ExecuteFunction_" .. guid()

    -- Initialize the task state inside our registry under its unique ID
    AsyncRegistry[callID] = {
        completed = false,
        finalResult = nil,
        registeredCallback = nil
    }
    if M.showDebug then print("AsyncRegistry entry created", callID) end

	uevr.api:dispatch_custom_event(callID, json.dump_string(data))

    -- 2. Return the tracking function
    return function(userCallback)
        local task = AsyncRegistry[callID]

        -- Safety check in case the task was deleted before this was called
        if not task then
            print("Warning: Task " .. callID .. " no longer exists.")
            return
        end

        if task.completed then
            -- If finished early, run it and immediately clean up
            userCallback(task.finalResult)
            AsyncRegistry[callID] = nil
        else
            -- Otherwise, store the callback to be executed later
            task.registeredCallback = userCallback
        end
    end
end

function M.executeFunction(callerObject, functionName, ...)
    local argsArray = {...}
	convertInputParams(argsArray)

	local data =
	{
		debug = M.showDebug,
		caller_object = callerObject:get_address(),
		function_name = functionName,
		params = argsArray
	}
    if M.showDebug then print("ExecuteFunction dispatching for function:\n", functionName, json.dump_string(data)) end
	local callID = "ExecuteFunction_" .. guid()

    -- Initialize the task state inside our registry under its unique ID
    AsyncRegistry[callID] = {
        completed = false,
        finalResult = nil,
        registeredCallback = nil,
        delayedCleanup = false
    }
    if M.showDebug then print("AsyncRegistry entry created", callID) end

	uevr.api:dispatch_custom_event(callID, json.dump_string(data))

    local result = AsyncRegistry[callID].finalResult
    AsyncRegistry[callID] = nil
    return result
end


uevr.sdk.callbacks.on_lua_event(function(eventName, eventData)
    if M.showDebug then print("on_lua_event", eventName, eventData) end
    local id = eventName
    local task = AsyncRegistry[id]

    -- Safety check: Ensure the task wasn't cancelled/deleted prematurely
    if not task then return end

    if M.showDebug then print("--------- ExecuteFunction raw return value -------------:\n", eventData) end
    local result = M.convertResultData(json.load_string(eventData))
    if M.showDebug then
        print("--------- ExecuteFunction Converted structure -------------")
        printTableStructure(result)
    end

    task.completed = true
    task.finalResult = result

    -- If the user already attached their callback, fire it now
    if task.registeredCallback then
        task.registeredCallback(result)
        --Free the memory immediately after execution
        AsyncRegistry[id] = nil
    elseif task.delayedCleanup ~= false then
        -- If the user did not attach their callback in an async call, free the memory after 2 seconds
        -- The delay function is implemented in uevr_utils.lua. If you dont want to use
        -- uevr_utils.lua then make sure you always use the return callback from the 
        -- ExecuteFunctionAsync call or else memory will leak
        if delay ~= nil then
            delay(2000, function()
                AsyncRegistry[id] = nil
            end)
        end
    end
end)

return M