
-- requires tarray_helper.dll to be in the plugins folder
-- stubs are in place in the dll to handle "GetAllSocketNames" as a property and "GetAllSocketNames(int float, string)" as a method with parameters

local M = {}

local pendingTArrayCallbacks = {}

uevr.sdk.callbacks.on_lua_event(function(eventName, eventData)
    --updateLuaEvent(eventName, eventData)
    --parse event name on : if first object is "GetTArray" then it's a tarray result event
    local splitEvent = M.splitStr(eventName, ":")
    if #splitEvent > 1 and splitEvent[1] == "GetTArray" then
        --executeUEVRCallbacks("on_tarray_result", splitEvent[3], splitEvent[4], json.load_string(eventData))
        local objectName = splitEvent[3]
        local methodName = splitEvent[4]
        local arrayData = json.load_string(eventData)
        local key = objectName .. "|" .. methodName
        local cb = pendingTArrayCallbacks[key]
        if cb then
            pendingTArrayCallbacks[key] = nil
            cb(arrayData)
        end
    end
end)

function M.splitStr(inputstr, sep)
   	if sep == nil then
      	sep = '%s'
   	end
   	local t={}
   	if inputstr ~= nil then
		for str in string.gmatch(inputstr, '([^'..sep..']+)')
		do
			table.insert(t, str)
		end
   	end
   	return t
end

function M.dispatchTArrayCall(arrayType, object, objectMethod, ...)
	local params = {...}
	local paramTypes = {}
	for i, param in ipairs(params) do
		table.insert(paramTypes, type(param))
	end
	local paramTypesStr = table.concat(paramTypes, ",")
	local eventName = "GetTArray:" .. arrayType .. ":" .. object:get_full_name() .. ":" .. objectMethod
	if paramTypesStr ~= "" then
		eventName = eventName .. ":" .. paramTypesStr
	end
	local eventData = json.dump_string(params)
	uevr.api:dispatch_custom_event(eventName, eventData	)
end

function M.registerCallback(callback, arrayType, object, objectMethod, ...)
    --initRouter()
    if object == nil then
        print("TArray.registerCallback: object is nil")
        return
    end
    local key = object:get_full_name() .. "|" .. objectMethod
    pendingTArrayCallbacks[key] = callback
    M.dispatchTArrayCall(arrayType, object, objectMethod, ...)
end


--local routerInstalled = false

-- local function updateLuaEvent(eventName, eventData)
-- 	if hasUEVRCallbacks("on_tarray_result") then
-- 		--parse event name on : if first object is "GetTArray" then it's a tarray result event
-- 		local splitEvent = M.splitStr(eventName, ":")
-- 		if #splitEvent > 1 and splitEvent[1] == "GetTArray" then
-- 			executeUEVRCallbacks("on_tarray_result", splitEvent[3], splitEvent[4], json.load_string(eventData))
-- 		end
-- 	end
-- end

-- function M.registerTArrayCallback(func, priority)
-- 	registerUEVRCallback("on_tarray_result", func, priority)
-- end

---------------------------------------------
-- manual method
-- stubs are in place in the dll to handle "GetAllSocketNames" as a property and "GetAllSocketNames(int float, string)" as a method with parameters
-- register_key_bind("F1", function()
-- 	uevrUtils.getTArray("FName", pawn.Mesh, "GetAllSocketNames()")
-- end)

-- uevrUtils.registerTArrayCallback(function(objectName, methodName, arrayData)
-- 	print("TArray Callback for object: " .. tostring(objectName) .. " Method: " .. tostring(methodName))
-- 	if arrayData == nil then
-- 		print("No data received")
-- 		return
-- 	end
-- 	for i, v in ipairs(arrayData) do
-- 		print("Socket " .. i .. ": " .. tostring(v))
-- 	end
-- end)
---------------------------------------------
-- Move this to core?
--------------------------------

-- local function initRouter()
--     if routerInstalled then return end
--     routerInstalled = true

--     M.registerTArrayCallback(function(objectName, methodName, arrayData)
--         local key = objectName .. "|" .. methodName
--         local cb = pendingTArrayCallbacks[key]
--         if cb then
--             pendingTArrayCallbacks[key] = nil
--             cb(arrayData)
--         end
--     end)
-- end

return M