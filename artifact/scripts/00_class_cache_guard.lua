--[[
	00_class_cache_guard.lua - stops uevrlib's get_class() handing out FREED Blueprint classes after a level / save load.

	Why: uevrlib's get_class(name) caches every find_uobject() result forever. Native classes (" /Script/") live for the
	whole session, but Blueprint classes and assets from /Game packages are freed and reloaded at a new address on every
	level or save load. The cached pointer keeps "working" until its memory is reused; then the engine faults INSIDE the
	call it was passed to. UEVR swallows that fault halfway through UObject::ProcessEvent, which leaves the game thread's
	Blueprint frame state corrupt - Hellraiser 2026-10-15: lost controller input on one load, no pawn spawned (under the
	map) on the next. Found with a 1 Hz GetAllWidgetsOfClass(W_ItemSize_C) test: bug on load 3 with the cached class,
	14 clean loads with the class looked up again after every level change.

	How: wraps get_class on uevr_utils and uevr_lib (whichever have one - older lib layouts keep a second cache in
	uevr_utils) without touching the lib files. Every non-native name looked up is remembered; on each level change those
	names are marked stale, and the next lookup of a stale name passes clearCache = true so the lib asks find_uobject
	again. Everything that goes through get_class benefits: find_default_instance, find_first_of, find_all_of, etc.

	Level changes are caught twice: uevr_utils' own pre-tick check (via a top-priority pre-level-change callback, which
	also switches that check on in libs that skip it when nobody listens) and this script's own post-tick check, because a
	save load happens INSIDE the engine tick and other scripts' post-tick code would otherwise run on the new level first.
	The file name sorts first so this loads (and registers its post-tick callback) before every other script.

	Not covered: classes a script keeps in its OWN variables (keep them in get_class, never in a local across loads), and
	Lua hook / xinput callbacks that fire during the load itself. Pure Lua; delete once uevrlib fixes get_class itself.
]]

local uevrUtils = require('libs/uevr_utils')
local okLib, uevrLib = pcall(require, 'libs/core/uevr_lib')
if not okLib then uevrLib = nil end

local seenNames = {}    -- non-native names looked up since the session started
local staleByTable = {} -- wrapped module table -> { [name] = true } entries to refresh on their next lookup
local wrapped = {}      -- names of the wrapped modules, for the log line

local nativeByName = {} -- get_class runs in hot paths: remember the answer per name

local function isNative(name)
	local native = nativeByName[name]
	if native == nil then
		native = string.find(name, " /Script/", 1, true) ~= nil
		nativeByName[name] = native
	end
	return native
end

local function wrapGetClass(moduleTable, label)
	if type(moduleTable) ~= "table" or type(moduleTable.get_class) ~= "function" or staleByTable[moduleTable] ~= nil then
		return
	end
	local original = moduleTable.get_class
	local stale = {}
	staleByTable[moduleTable] = stale
	moduleTable.get_class = function(name, clearCache)
		if type(name) == "string" and not isNative(name) then
			seenNames[name] = true
			if stale[name] then
				stale[name] = nil
				clearCache = true
			elseif clearCache then
				stale[name] = nil
			end
		end
		return original(name, clearCache)
	end
	table.insert(wrapped, label)
end

wrapGetClass(uevrUtils, "uevr_utils")
wrapGetClass(uevrLib, "uevr_lib")

if #wrapped == 0 then
	print("[class_cache_guard] INACTIVE: no get_class(name, clearCache) found in uevr_utils / uevr_lib - stale /Game classes are NOT guarded")
	return
end
print("[class_cache_guard] active: wrapped get_class in " .. table.concat(wrapped, " + "))

local lastLevel = nil

local function markStale(level)
	if level == nil or level == lastLevel then return end
	lastLevel = level
	for _, stale in pairs(staleByTable) do
		for name in pairs(seenNames) do
			stale[name] = true
		end
	end
end

local function currentLevel()
	local level = nil
	pcall(function()
		local world = uevrUtils.get_world()
		if world ~= nil then level = world.PersistentLevel end
	end)
	return level
end

-- Highest priority: runs before every other script's level change code, which may look classes up again.
uevrUtils.registerPreLevelChangeCallback(function(level)
	markStale(level)
end, math.huge)

uevr.sdk.callbacks.on_post_engine_tick(function(engine, delta)
	markStale(currentLevel())
end)
