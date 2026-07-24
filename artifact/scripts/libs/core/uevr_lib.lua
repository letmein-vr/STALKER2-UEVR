
local M = {}

local classCache = {}
local structCache = {}

function M.clearClassCache(className)
    classCache[className] = nil
end

function M.find_required_object(name)
    local obj = uevr.api:find_uobject(name)
    if not obj then
        M.print("Cannot find " .. name)
        return nil
    end

    return obj
end

--uses caching
function M.get_class(name, clearCache)
	if name == nil then return nil end
	if clearCache or classCache[name] == nil then
		local ok, result = pcall(function()
			return uevr.api:find_uobject(name)
		end)
		if not ok then
			print("[uevr_utils] Error finding class in get_class handled properly", name, result)
			return nil
		end
		classCache[name] = result
		--classCache[name] = uevr.api:find_uobject(name)
	end
    return classCache[name]
end

function M.find_default_instance(className)
	local class =  M.get_class(className)
	if class ~= nil and class.get_first_object_matching ~= nil then
		return class:get_class_default_object()
	end
	return nil
end

function M.find_first_instance(className, includeDefault)
	local class =  M.get_class(className)
	if class ~= nil and class.get_first_object_matching ~= nil then
		return class:get_first_object_matching(includeDefault)
	end
	return nil
end

function M.find_all_instances(className, includeDefault)
	local class =  M.get_class(className)
	if class ~= nil and class.get_objects_matching ~= nil then
		return class:get_objects_matching(includeDefault)
	end
	return nil
end

function M.find_first_of(className, includeDefault)
	if includeDefault == nil then includeDefault = false end
	local class =  M.get_class(className)
	if class ~= nil then
		return UEVR_UObjectHook.get_first_object_by_class(class, includeDefault)
	end
	return nil
end

function M.find_all_of(className, includeDefault)
	if includeDefault == nil then includeDefault = false end
	local class =  M.get_class(className)
	if class ~= nil then
		return UEVR_UObjectHook.get_objects_by_class(class, includeDefault)
	end
	return {}
end

function M.get_reuseable_struct_object(structClassName)
	if structCache[structClassName] == nil then
		local class = M.get_class(structClassName)
		if class ~= nil then
			structCache[structClassName] = StructObject.new(class)
		end
	end
	return structCache[structClassName]
end

function M.get_struct_object(structClassName, reuseable)
	if reuseable == true then
		return M.get_reuseable_struct_object(structClassName)
	end
	local class = M.get_class(structClassName)
	if class ~= nil then
		return StructObject.new(class)
	end
	return nil
end

local function splitOnLastPeriod(input)
    local lastPeriodIndex = input:match(".*()%.") -- Find the last period's position
    if not lastPeriodIndex then
        return input, nil -- No period found
    end
    local beforePeriod = input:sub(1, lastPeriodIndex - 1)
    local afterPeriod = input:sub(lastPeriodIndex + 1)
    return beforePeriod, afterPeriod
end

function M.find_instance_of(className, objectName)
	--check if the objectName is a short name
	local isShortName = string.find(objectName, '.', 1, true) == nil
	local instances = M.find_all_of(className, true)
	for i, instance in ipairs(instances) do
		if isShortName then
			local before, after = splitOnLastPeriod(instance:get_full_name())
			if after ~= nil and after == objectName then
				return instance
			end
		else
			if instance:get_full_name() == objectName then
				return instance
			end
		end
	end
	return nil
end

return M