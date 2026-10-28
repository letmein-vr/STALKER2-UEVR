--[[
	Developer panel for libs/hud.lua ("HUD Dev" tab in the UEVR overlay). Loaded by hud.init(true, ...).

	Everything goes through hud.lua's public API, so whatever the panel does a script can do too. The panel keeps no
	game objects, only class paths, child names and numbers, so it is safe across level and save loads.

	Edits are live and NOT saved until Save is pressed (data/hud_parameters.json). Revert reloads the saved set.
	Placement and appearance apply immediately; mode, widget, bounds and target need the element rebuilt, which
	happens REBUILD_DELAY seconds after the last change so dragging a value does not rebuild every frame.
]]--

local uevrUtils = require("libs/uevr_utils")
local configui = require("libs/configui")
local controllers = require("libs/controllers")

local M = {}

local P = "hud_dev_"
local PANEL_ID = "hud_dev_panel"
local REBUILD_DELAY = 0.4
local CHILD_LIST_LIMIT = 400

local hud = nil
local currentId = nil
local elementIds = {}
local widgetClasses = {}		-- full class paths behind the widget dropdown
local childNames = {}			-- child names behind the child dropdown (index 1 = whole widget)
local pendingEdits = {}			-- key -> { time, fn } rebuild-type edits waiting for REBUILD_DELAY
local loadingUI = false			-- true while the fields are filled from a definition

local modeValues = { "hide", "direct", "region" }
local modeLabels = { "Hide", "Direct (whole widget)", "Region (copy a part)" }
local targetValues = { "left_controller", "right_controller", "hmd", "left_hand", "right_hand", "pawn_mesh", "custom" }
local targetLabels = { "Left controller", "Right controller", "HMD", "Left hand", "Right hand", "Pawn mesh", "Custom (callback)" }
local boundsLabels = { "The child's own box", "Content (every visible part inside it)" }
local blendLabels = { "Opaque", "Masked", "Transparent" }
local exposureValues = { "none", "postprocess", "script" }
local exposureLabels = { "None (manual stops only)", "Post process (games with pinned exposure)", "Set by a script (game specific)" }

--------------------------- helpers ---------------------------

local function indexOf(list, value, default)
	for i, v in ipairs(list) do if v == value then return i end end
	return default
end

local function shortName(path)
	if path == nil then return "" end
	return path:match("%.([^%.]+)$") or path
end

local function deepCopy(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for k, v in pairs(value) do copy[k] = deepCopy(v) end
	return copy
end

local function vec(value, count)
	local native = configui.getNativeValue(value)
	if type(native) ~= "table" then return nil end
	local result = {}
	for i = 1, count do result[i] = native[i] or native[({ "x", "y", "z", "w" })[i]] or native[({ "X", "Y", "Z", "W" })[i]] or 0 end
	return result
end

-- imgui text does not wrap on its own
local function wrap(text, width)
	local lines = {}
	for paragraph in (text .. "\n"):gmatch("(.-)\n") do
		local line = ""
		for word in paragraph:gmatch("%S+") do
			if #line > 0 and #line + #word + 1 > width then
				table.insert(lines, line)
				line = word
			else
				line = #line > 0 and (line .. " " .. word) or word
			end
		end
		table.insert(lines, line)
	end
	return table.concat(lines, "\n")
end

local function setUI(id, value)
	configui.setValue(P .. id, value, true) -- no callbacks: filling the form must not write back
end

local function currentDefinition()
	return currentId ~= nil and hud.getElement(currentId) or nil
end

local function setStatus(text)
	configui.setLabel(P .. "status", text)
end

local function markUnsaved()
	setStatus("Unsaved changes - press Save to keep them")
end

-- applies at once (transform, appearance): cheap, done while dragging
local function editLive(path, value)
	if currentId == nil or loadingUI then return end
	hud.setElementValue(currentId, path, value)
	markUnsaved()
end

-- rebuilds the element: applied once the value has stopped changing
local function editRebuild(path, value)
	if currentId == nil or loadingUI then return end
	local id = currentId
	local key = id .. "|" .. table.concat(type(path) == "table" and path or { path }, ".")
	pendingEdits[key] = { time = os.clock() + REBUILD_DELAY, fn = function()
		if hud.getElement(id) ~= nil then hud.setElementValue(id, path, value) end
	end }
	markUnsaved()
end

--------------------------- widget picker ---------------------------

local function userWidgetClass()
	return uevrUtils.get_class("Class /Script/UMG.UserWidget")
end

local function refreshWidgetList()
	local filter = string.lower(configui.getValue(P .. "widget_filter") or "")
	local seen, list = {}, {}
	local function add(path, note)
		if path == nil or seen[path] then return end
		local name = shortName(path)
		if filter ~= "" and not string.find(string.lower(name), filter, 1, true) then return end
		seen[path] = true
		table.insert(list, { path = path, label = name .. (note or "") })
	end
	pcall(function()
		local found = {}
		WidgetBlueprintLibrary:GetAllWidgetsOfClass(uevrUtils.get_world(), found, userWidgetClass(), true)
		for _, widget in ipairs(found) do
			pcall(function() add(widget:get_class():get_full_name()) end)
		end
	end)
	-- widgets already moved into a HUD element are in no viewport, so they come from the definitions
	for _, id in ipairs(hud.getElementIDs()) do
		local definition = hud.getElement(id)
		if definition ~= nil and definition.widget ~= nil then add(definition.widget.class, "  (in a HUD element)") end
	end
	table.sort(list, function(a, b) return a.label < b.label end)
	widgetClasses = {}
	local labels = {}
	for i, item in ipairs(list) do widgetClasses[i] = item.path labels[i] = item.label end
	if #labels == 0 then labels = { "(press Find, nothing listed yet)" } end
	configui.setSelections(P .. "widget_list", labels)
	setUI("widget_list", 1)
	configui.setLabel(P .. "widget_count", #widgetClasses .. " widgets")
end

-- the live root instance of a widget class (top level or moved into a HUD element)
local function findRootWidget(path)
	local class = uevrUtils.get_class(path, true)
	if class == nil then return nil end
	local result = nil
	pcall(function()
		local found = {}
		WidgetBlueprintLibrary:GetAllWidgetsOfClass(uevrUtils.get_world(), found, class, false)
		for _, widget in ipairs(found) do
			if widget:GetParent() == nil then result = widget break end
		end
		if result == nil then result = found[1] end
	end)
	return result
end

-- same walk as libs/widget.lua findWidget (panel children and content, not the trees of nested UserWidgets),
-- so every listed name is one hud.lua can find
local function refreshChildList()
	local definition = currentDefinition()
	childNames = { "" }
	local labels = { "(whole widget)" }
	local root = definition ~= nil and definition.widget ~= nil and definition.widget.class ~= nil and findRootWidget(definition.widget.class) or nil
	if root ~= nil then
		pcall(function()
			local counts, entries = {}, {}
			local function visit(widget, depth)
				if widget == nil or #entries >= CHILD_LIST_LIMIT then return end
				local name = widget:get_fname():to_string()
				counts[name] = (counts[name] or 0) + 1
				table.insert(entries, { name = name, depth = depth })
				if widget.GetChildrenCount ~= nil then -- content widgets are panels too: content = child 0, listed once
					for i = 0, widget:GetChildrenCount() - 1 do visit(widget:GetChildAt(i), depth + 1) end
				elseif widget.GetContent ~= nil then
					local content = widget:GetContent()
					if content ~= nil then visit(content, depth + 1) end
				end
			end
			local tree = root.WidgetTree
			if tree ~= nil and tree.RootWidget ~= nil then visit(tree.RootWidget, 0) end
			for _, entry in ipairs(entries) do
				table.insert(childNames, entry.name)
				-- a name used twice finds the first one only
				table.insert(labels, string.rep("  ", entry.depth) .. entry.name .. (counts[entry.name] > 1 and "  (name used twice)" or ""))
			end
		end)
	end
	-- a part picked by Search can sit inside a nested widget (a path), which this list does not walk into
	local child = definition ~= nil and definition.widget ~= nil and definition.widget.child or ""
	if child ~= "" and indexOf(childNames, child, nil) == nil then
		table.insert(childNames, 2, child)
		table.insert(labels, 2, (child:gsub("/", " > ")) .. "  (from Search)")
	end
	configui.setSelections(P .. "child_list", labels)
	setUI("child_list", indexOf(childNames, child or "", 1))
	configui.setLabel(P .. "child_count", root ~= nil and (#childNames - 1) .. " parts" or "widget not on screen now")
end

--------------------------- search ---------------------------

local SEARCH_LIMIT = 200
local searchResults = {}	-- plain data from hud.findParts or the picker: class + child, no game objects kept

-- one line of the Result list: r = { class, child, className, width, height, drawn, hidden, faded, ambiguous }
local function resultLabel(r)
	local label = shortName(r.class) .. (r.child ~= nil and ("  >  " .. (r.child:gsub("/", " > "))) or "  (whole widget)")
	label = label .. "  [" .. tostring(r.className) .. "]"
	if r.width ~= nil then label = label .. string.format("  %.0fx%.0f", r.width, r.height) end
	if not r.drawn then
		label = label .. (r.hidden and "  (hidden now)" or (r.faded and "  (faded out now)" or "  (no size now)"))
	end
	if r.ambiguous then label = label .. "  (name used twice: picks the first)" end
	return label
end

local function runSearch()
	local text = configui.getValue(P .. "search_text") or ""
	searchResults = {}
	local labels = {}
	if text:match("^%s*$") then
		configui.setSelections(P .. "search_list", { "(type a word and press Search)" })
		setUI("search_list", 1)
		configui.setLabel(P .. "search_count", "")
		return
	end
	local started = os.clock()
	local results, visited, total = hud.findParts(text:match("^%s*(.-)%s*$"), { limit = SEARCH_LIMIT })
	local milliseconds = (os.clock() - started) * 1000
	for i, r in ipairs(results) do
		searchResults[i] = { class = r.class, child = r.child }
		labels[i] = resultLabel(r)
	end
	if #labels == 0 then labels = { "(nothing found)" } end
	configui.setSelections(P .. "search_list", labels)
	setUI("search_list", 1)
	configui.setLabel(P .. "search_count", string.format("%d found%s in %d widgets (%.0f ms)",
		total or #results, (total or 0) > #results and (", first " .. #results .. " listed") or "", visited, milliseconds))
end

--------------------------- identify (blink a part) ---------------------------

local BLINK_STEPS, BLINK_INTERVAL = 6, 0.25
local blink = nil -- { widget, world, original, step, nextTime }

local function stopBlink(restore)
	if blink == nil then return end
	local b = blink
	blink = nil
	-- a level or save load replaced the widget: forget it, never touch it
	if restore and uevrUtils.get_world() == b.world and uevrUtils.getValid(b.widget) ~= nil then
		pcall(function() b.widget:SetRenderOpacity(b.original) end)
	end
end

-- blinks a part three times (render opacity, so the layout does not move), wherever it is drawn: on the flat HUD
-- or, when an element already uses the widget, in VR. child = name or path inside the widget, nil = whole widget
local function startBlink(class, child)
	stopBlink(true)
	if class == nil then return end
	local part = hud.findWidgetPart(class, child)
	if part == nil or part.SetRenderOpacity == nil then
		setStatus("Identify: that part does not exist right now")
		return
	end
	local original = 1.0
	pcall(function() original = part:GetRenderOpacity() end)
	blink = { widget = part, world = uevrUtils.get_world(), original = original, step = 0, nextTime = os.clock() }
end

local function updateBlink()
	if blink == nil then return end
	if uevrUtils.get_world() ~= blink.world or uevrUtils.getValid(blink.widget) == nil then
		blink = nil -- level changed: forget, never touch
		return
	end
	local now = os.clock()
	if now < blink.nextTime then return end
	blink.step = blink.step + 1
	if blink.step > BLINK_STEPS then
		stopBlink(true)
		return
	end
	local opacity = (blink.step % 2 == 1) and 0.0 or blink.original
	pcall(function() blink.widget:SetRenderOpacity(opacity) end)
	blink.nextTime = now + BLINK_INTERVAL
end

--------------------------- controller picker ---------------------------

-- Aim the right controller at the flat HUD (UEVR's UI panel) and hold still on a part: after PICK_DWELL seconds it is
-- picked and listed with all its parents in the Result list (deepest first), ready for "Use this result". The part
-- under the ray pulses meanwhile. Holding still picks instead of a button, so no game input fires (the trigger shoots
-- in most games).
-- Ray to panel: UEVR places the panel (src/mods/vr/OverlayComponent.cpp, generate_slate_quad) at X/Y offset and
-- minus distance in view space when UI Follows View is on, or in stage space turned by the recenter offset when it
-- is off. The "off" maths follows jbusfield's widget finder (Hogwarts Legacy libs/config/widgetcomponent_config_dev.lua).
-- Only what is on the flat screen can be picked: widgets already moved into HUD elements are not.
local PICK_INTERVAL, PICK_DWELL, PICK_PULSE, PICK_WALK_LIMIT, PICK_ROOTS_REFRESH = 0.15, 1.5, 0.2, 3000, 1.0
local PICK_DEFAULT_ANGLE = -90 -- degrees from the grip's handle axis to the pointing direction (see aimOnPanel; -90 confirmed on Quest, 2026-10-16)
local picking = nil		-- while on: { lastTest, hover, roots, rootsTime, controllersTried }
local uevrMenuOpen = true	-- the picker is switched on from the menu; uevrlib reports when the menu closes
local pickSlate = nil
local mathLib = nil

local lastPickStatus = nil
local function setPickStatus(text)
	configui.setLabel(P .. "pick_status", text)
	-- also into the HUD log (the dev loaders route hud.print to a file), once per change, so a test can be read later
	if text ~= lastPickStatus and text ~= "" then pcall(hud.print, "[picker] " .. text) end
	lastPickStatus = text
end

local function modValue(name)
	local ok, value = pcall(function() return uevr.params.vr:get_mod_value(name) end)
	return ok and tostring(value or "") or ""
end

local function modNumber(name)
	return tonumber(string.match(modValue(name), "[%-%d%.]+")) or 0
end

local function modFlag(name)
	local value = string.lower(modValue(name))
	return value:find("true", 1, true) ~= nil or value:match("^%s*1") ~= nil
end

local function addressOf(object)
	local ok, address = pcall(function() return object:get_address() end)
	return ok and address or nil
end

-- v turned by the unit quaternion q (the device's own frame -> tracking space)
local function rotate(v, q)
	local x, y, z, w = q.X, q.Y, q.Z, q.W
	local tx, ty, tz = 2 * (y * v.Z - z * v.Y), 2 * (z * v.X - x * v.Z), 2 * (x * v.Y - y * v.X)
	return {
		X = v.X + w * tx + (y * tz - z * ty),
		Y = v.Y + w * ty + (z * tx - x * tz),
		Z = v.Z + w * tz + (x * ty - y * tx),
	}
end

-- v turned by the inverse of the unit quaternion q (tracking space -> the device's own frame)
local function unrotate(v, q)
	local x, y, z, w = -q.X, -q.Y, -q.Z, q.W
	local tx, ty, tz = 2 * (y * v.Z - z * v.Y), 2 * (z * v.X - x * v.Z), 2 * (x * v.Y - y * v.X)
	return {
		X = v.X + w * tx + (y * tz - z * ty),
		Y = v.Y + w * ty + (z * tx - x * tz),
		Z = v.Z + w * tz + (x * ty - y * tx),
	}
end

-- Where the right controller's aim ray meets UEVR's UI panel: { u (0 left .. 1 right), v (0 top .. 1 bottom), onPanel,
-- meters = distance along the ray to the panel's plane, unitsPerMeter = game units per tracking meter } or
-- { problem = text } when the picker cannot work at all
local function aimOnPanel()
	local vr = uevr.params.vr
	if modNumber("UI_OverlayType") ~= 0 then return { problem = "UEVR's UI is a cylinder (Overlay Type): only the flat quad is supported" } end
	-- the game's HMD and right controller components carry the beam (it is drawn in the world)
	local hmdRotation = controllers.getControllerRotation(2)
	local handRotation = controllers.getControllerRotation(Handed.Right)
	if (hmdRotation == nil or handRotation == nil) and not picking.controllersTried then
		picking.controllersTried = true
		pcall(controllers.createController, 2)
		pcall(controllers.createController, Handed.Right)
		hmdRotation = controllers.getControllerRotation(2)
		handRotation = controllers.getControllerRotation(Handed.Right)
	end
	if hmdRotation == nil or handRotation == nil then return { problem = "No HMD / right controller component" } end
	vr.get_pose(vr.get_hmd_index(), temp_vec3f, temp_quatf)
	local hmdPos = { X = temp_vec3f.X, Y = temp_vec3f.Y, Z = temp_vec3f.Z }
	local hmdRot = { X = temp_quatf.X, Y = temp_quatf.Y, Z = temp_quatf.Z, W = temp_quatf.W }
	vr.get_pose(vr.get_right_controller_index(), temp_vec3f, temp_quatf)
	local handPos = { X = temp_vec3f.X, Y = temp_vec3f.Y, Z = temp_vec3f.Z }
	local handRot = { X = temp_quatf.X, Y = temp_quatf.Y, Z = temp_quatf.Z, W = temp_quatf.W }
	if handRot.X == 0 and handRot.Y == 0 and handRot.Z == 0 and handPos.X == 0 and handPos.Y == 0 and handPos.Z == 0 then
		return { problem = "The right controller has no pose (asleep or not tracked)" }
	end
	-- The ray comes from the physical controller's pose. The game's controller component is NOT used for the direction:
	-- in Outer Worlds 2 it pointed about 55 degrees away from the real controller (2026-10-16), so every ray landed on
	-- empty HUD space. The pose Lua gets is the GRIP pose (UEVR binds get_pose to the grip transform; the aim pose is not
	-- bound): its -Z runs up the handle (OpenXR: through the fist, little finger to thumb), so the pointing direction is
	-- -Z tilted about the grip's X axis towards -Y by the beam angle (-90 = straight out of the front on Quest, adjustable).
	-- The beam is drawn along this same ray, so whatever the beam touches is what gets picked.
	local angle = math.rad(tonumber(configui.getValue(P .. "pick_angle")) or PICK_DEFAULT_ANGLE)
	local forward = rotate({ X = 0, Y = math.sin(angle), Z = -math.cos(angle) }, handRot)
	local dirHead = unrotate(forward, hmdRot) -- in the head's frame (OpenXR axes: x right, y up, -z forward)
	local start, dir
	if modFlag("UI_FollowView") then
		-- the panel lives in view space: express the hand in the head's frame
		start = unrotate({ X = handPos.X - hmdPos.X, Y = handPos.Y - hmdPos.Y, Z = handPos.Z - hmdPos.Z }, hmdRot)
		dir = dirHead
	else
		if mathLib == nil then mathLib = require("libs/core/math_lib") end
		vr.get_rotation_offset(temp_quatf)
		local uiRotation = { X = temp_quatf.X, Y = temp_quatf.Y, Z = temp_quatf.Z, W = temp_quatf.W }
		vr.get_standing_origin(temp_vec3f)
		start = mathLib.vectorRotate_Quat({ X = handPos.X - temp_vec3f.X, Y = handPos.Y - temp_vec3f.Y, Z = handPos.Z - temp_vec3f.Z }, uiRotation, false)
		dir = mathLib.vectorRotate_Quat(forward, uiRotation, false)
	end
	-- game units per tracking meter (world scale), from the hand-to-head distance measured both ways; for the beam
	local unitsPerMeter = nil
	pcall(function()
		local handUE, headUE = controllers.getControllerLocation(Handed.Right), controllers.getControllerLocation(2)
		local dx, dy, dz = handUE.X - headUE.X, handUE.Y - headUE.Y, handUE.Z - headUE.Z
		local tx, ty, tz = handPos.X - hmdPos.X, handPos.Y - hmdPos.Y, handPos.Z - hmdPos.Z
		local tracked = math.sqrt(tx * tx + ty * ty + tz * tz)
		if tracked > 0.1 then unitsPerMeter = math.sqrt(dx * dx + dy * dy + dz * dz) / tracked end
	end)
	local result = { onPanel = false, unitsPerMeter = unitsPerMeter }
	-- the ray in the right controller component's frame, for the beam: head frame -> game head axes (x forward,
	-- y right, z up) -> world through the game's HMD component -> the controller component's frame
	pcall(function()
		local world = kismet_math_library:GreaterGreater_VectorRotator(uevrUtils.vector(-dirHead.Z, dirHead.X, dirHead.Y), hmdRotation)
		local localDir = kismet_math_library:LessLess_VectorRotator(world, handRotation)
		result.beamDir = { X = localDir.X, Y = localDir.Y, Z = localDir.Z }
	end)
	if start == nil or dir == nil or dir.Z == 0 then return result end
	local t = (-modNumber("UI_Distance") - start.Z) / dir.Z
	if t <= 0 then return result end
	result.meters = t
	local height = modNumber("UI_Size")
	local width = height * vr.get_ui_width() / vr.get_ui_height()
	if height <= 0 or width <= 0 then return result end
	result.u = (start.X + dir.X * t - modNumber("UI_X_Offset")) / width + 0.5
	result.v = 0.5 - (start.Y + dir.Y * t - modNumber("UI_Y_Offset")) / height
	result.onPanel = result.u >= 0 and result.u <= 1 and result.v >= 0 and result.v <= 1
	return result
end

-- The beam: two crossed thin strips of the engine plane (visible from any side) on the right controller, drawn with the
-- engine's two sided widget material showing a small white render target of our own, tinted. Nothing is loaded by
-- path: the plane and the widget material are what the Region displays already use in every game. Never gated on
-- getValid (new objects fail it for seconds on some backends): direct references, forgotten on a level change.
local BEAM_MESH = "StaticMesh /Engine/BasicShapes/Plane.Plane"
local BEAM_WIDTH, BEAM_MISS_LENGTH = 0.4, 150.0
local beamColors = { hit = { 0.3, 2.0, 0.3 }, panel = { 2.0, 1.6, 0.2 }, miss = { 2.0, 0.25, 0.25 } }
local beam = nil -- { strips = { a, b }, mid, world, color, visible }

local function destroyBeam()
	if beam == nil then return end
	local b = beam
	beam = nil
	if uevrUtils.get_world() ~= b.world then return end -- went with its level: never touch
	pcall(function() uevrUtils.detachAndDestroyComponent(b.strips[1], true, false) end) -- its actor holds both strips
end

local function createBeam()
	local controller = controllers.getController(Handed.Right, true) or controllers.getController(Handed.Right)
	if controller == nil then return nil end
	local created = {}
	local ok, err = pcall(function()
		local first = uevrUtils.createStaticMeshComponent(BEAM_MESH, { visible = true, collisionEnabled = false, tag = "uevrlib_hud_picker" })
		if first == nil then return end
		created[1] = first
		local owner = first:GetOwner()
		local second = uevrUtils.createStaticMeshComponent(BEAM_MESH, { visible = true, collisionEnabled = false, parent = owner, tag = "uevrlib_hud_picker" })
		created[2] = second
		local parentMaterial = uevrUtils.find_default_instance("Class /Script/UMG.WidgetComponent").TranslucentMaterial
		local white = kismet_rendering_library:CreateRenderTarget2D(uevrUtils.get_world(), 4, 4, 3, uevrUtils.color_from_rgba(1, 1, 1, 1), false, false)
		local mid = first:CreateDynamicMaterialInstance(0, parentMaterial, uevrUtils.fname_from_string(""))
		mid:SetTextureParameterValue(uevrUtils.fname_from_string("SlateUI"), white)
		mid:SetScalarParameterValue(uevrUtils.fname_from_string("OpacityFromTexture"), 1.0)
		for _, strip in ipairs(created) do
			if strip ~= first then strip:SetMaterial(0, mid) end
			if strip.SetCastShadow ~= nil then strip:SetCastShadow(false) end
			strip:K2_AttachTo(controller, uevrUtils.fname_from_string(""), 0, false)
		end
		beam = { strips = created, mid = mid, world = uevrUtils.get_world(), visible = true }
	end)
	if not ok or beam == nil then
		pcall(hud.print, "[picker] beam could not be made: " .. tostring(ok and "no mesh component" or err))
		if created[1] ~= nil then pcall(function() uevrUtils.detachAndDestroyComponent(created[1], true, false) end) end
		beam = nil
	else
		pcall(hud.print, "[picker] beam made")
	end
	return beam
end

-- lengthCm along direction (in the controller component's frame; default its +X), colour = "hit" / "panel" / "miss",
-- nil length hides it
local function updateBeam(lengthCm, color, direction)
	if beam ~= nil and uevrUtils.get_world() ~= beam.world then beam = nil end -- level changed: forget
	if lengthCm == nil then
		if beam ~= nil and beam.visible then
			for _, strip in ipairs(beam.strips) do pcall(function() strip:SetVisibility(false, false) end) end
			beam.visible = false
		end
		return
	end
	if beam == nil and createBeam() == nil then return end
	if not beam.visible then
		for _, strip in ipairs(beam.strips) do pcall(function() strip:SetVisibility(true, false) end) end
		beam.visible = true
	end
	-- plane: 100 x 100 in its X/Y; strip one flat, strip two turned 90 degrees about the beam
	local scale = { lengthCm / 100.0, BEAM_WIDTH / 100.0, 1 }
	pcall(function()
		local d = direction or { X = 1, Y = 0, Z = 0 }
		local r = kismet_math_library:Conv_VectorToRotator(uevrUtils.vector(d.X, d.Y, d.Z))
		local middle = { d.X * lengthCm / 2, d.Y * lengthCm / 2, d.Z * lengthCm / 2 }
		uevrUtils.set_component_relative_transform(beam.strips[1], middle, { r.Pitch, r.Yaw, 0 }, scale)
		uevrUtils.set_component_relative_transform(beam.strips[2], middle, { r.Pitch, r.Yaw, 90 }, scale)
	end)
	if color ~= beam.color then
		beam.color = color
		local c = beamColors[color] or beamColors.miss
		pcall(function() beam.mid:SetVectorParameterValue(uevrUtils.fname_from_string("TintColorAndOpacity"), uevrUtils.color_from_rgba(c[1], c[2], c[3], 1)) end)
	end
end

-- panel position -> absolute (desktop) space, where cached geometry lives. There is no ViewportToAbsolute, so the
-- mapping comes from two reference points (as in jbusfield's finder)
local function panelToAbsolute(u, v)
	local world = uevrUtils.get_world()
	---@diagnostic disable-next-line: undefined-field
	local viewportSize = WidgetLayoutLibrary:GetViewportSize(world)
	if pickSlate == nil then pickSlate = uevrUtils.find_default_instance("Class /Script/UMG.SlateBlueprintLibrary") end
	if pickSlate == nil or viewportSize == nil then return nil end
	local p0, p1 = {}, {}
	pickSlate:AbsoluteToViewport(world, uevrUtils.vector2D(0, 0), p0, {})
	pickSlate:AbsoluteToViewport(world, uevrUtils.vector2D(1000, 1000), p1, {})
	local a, b = p0.result or p0, p1.result or p1
	if a.X == nil or b.X == nil or b.X == a.X or b.Y == a.Y then return nil end
	return uevrUtils.vector2D((u * viewportSize.X - a.X) * 1000 / (b.X - a.X), (v * viewportSize.Y - a.Y) * 1000 / (b.Y - a.Y))
end

local function pickRoots()
	local now = os.clock()
	if picking.roots ~= nil and now - picking.rootsTime < PICK_ROOTS_REFRESH then return picking.roots end
	local roots = {}
	pcall(function()
		local found = {}
		WidgetBlueprintLibrary:GetAllWidgetsOfClass(uevrUtils.get_world(), found, userWidgetClass(), true)
		for _, widget in ipairs(found) do
			if widget:IsInViewport() then table.insert(roots, widget) end
		end
	end)
	picking.roots, picking.rootsTime = roots, now
	return roots
end

-- The smallest drawn widget under the point, with its chain of parents (deepest first) as { widget, path } where
-- path is the part path hud.lua takes (nil = the top level widget itself). Only widgets that contain the point (or
-- have no size, which can still hold drawn children) are walked into, so a test visits a few hundred widgets at most.
local function hitTest(point)
	local best, visited, stack = nil, 0, {}
	local hoverKey = picking.hover ~= nil and picking.hover.key or nil
	local function visit(widget, rootClass, prefix, depth, isRoot)
		if widget == nil or visited >= PICK_WALK_LIMIT then return end
		visited = visited + 1
		local visibility = widget.GetVisibility ~= nil and widget:GetVisibility() or nil
		if visibility == 1 or visibility == 2 then return end -- collapsed / hidden: nothing below is drawn
		-- faded out widgets are skipped, except the one the picker itself is pulsing
		if widget.GetRenderOpacity ~= nil and widget:GetRenderOpacity() < 0.05 and addressOf(widget) ~= hoverKey then return end
		local name = widget:get_fname():to_string()
		local path = nil
		if not isRoot then path = prefix == "" and name or (prefix .. "/" .. name) end
		local geometry = widget:GetCachedGeometry()
		local size = pickSlate:GetAbsoluteSize(geometry)
		local hasSize = size.X >= 1 and size.Y >= 1
		local inside = hasSize and pickSlate:IsUnderLocation(geometry, point)
		table.insert(stack, { widget = widget, path = path })
		if inside then
			local area = size.X * size.Y
			if best == nil or area < best.area or (area == best.area and depth >= best.depth) then
				local chain = {}
				for i = #stack, 1, -1 do chain[#chain + 1] = stack[i] end
				best = { area = area, depth = depth, widget = widget, class = rootClass, chain = chain }
			end
		end
		if inside or not hasSize then
			local tree = widget.WidgetTree -- a nested UserWidget: its parts are one path step further in
			if tree ~= nil and tree.RootWidget ~= nil then
				visit(tree.RootWidget, rootClass, isRoot and "" or path, depth + 1, false)
			elseif widget.GetChildrenCount ~= nil then
				for i = 0, widget:GetChildrenCount() - 1 do visit(widget:GetChildAt(i), rootClass, prefix, depth + 1, false) end
			elseif widget.GetContent ~= nil then
				visit(widget:GetContent(), rootClass, prefix, depth + 1, false)
			end
		end
		table.remove(stack)
	end
	for _, root in ipairs(pickRoots()) do
		pcall(function() visit(root, root:get_class():get_full_name(), "", 0, true) end)
		stack = {}
	end
	return best, visited
end

-- hovered part: pulses its render opacity; restored when the hover moves on (world-guarded like the blink)
local function setHover(hit)
	local old = picking ~= nil and picking.hover or nil
	if old ~= nil then
		if uevrUtils.get_world() == old.world and uevrUtils.getValid(old.widget) ~= nil then
			pcall(function() old.widget:SetRenderOpacity(old.original) end)
		end
		picking.hover = nil
	end
	if hit == nil or picking == nil then return end
	local original = 1.0
	pcall(function() original = hit.widget:GetRenderOpacity() end)
	local now = os.clock()
	picking.hover = { widget = hit.widget, key = addressOf(hit.widget), world = uevrUtils.get_world(), original = original,
		since = now, nextPulse = now, dimmed = false }
end

local function updateHoverPulse(now)
	local hover = picking ~= nil and picking.hover or nil
	if hover == nil or now < hover.nextPulse then return end
	if uevrUtils.get_world() ~= hover.world or uevrUtils.getValid(hover.widget) == nil then
		picking.hover = nil -- level changed: forget, never touch
		return
	end
	hover.dimmed = not hover.dimmed
	pcall(function() hover.widget:SetRenderOpacity(hover.dimmed and hover.original * 0.3 or hover.original) end)
	hover.nextPulse = now + PICK_PULSE
end

local function stopPicking()
	destroyBeam()
	if picking == nil then return end
	setHover(nil)
	picking = nil
end

-- the picked part and its parents into the Result list, deepest first
local function finishPick(hit)
	stopPicking()
	setUI("pick_on", false)
	searchResults = {}
	local labels = {}
	for _, entry in ipairs(hit.chain) do
		local r = { class = hit.class, child = entry.path, drawn = true }
		pcall(function()
			r.className = entry.widget:get_class():get_fname():to_string()
			local size = pickSlate:GetLocalSize(entry.widget:GetCachedGeometry())
			r.width, r.height = size.X, size.Y
			r.drawn = r.width >= 1 and r.height >= 1
			-- a name used twice in one tree: the path finds the first one, which may not be this widget
			local found = hud.findWidgetPart(hit.class, entry.path)
			r.ambiguous = found ~= nil and addressOf(found) ~= addressOf(entry.widget)
		end)
		table.insert(searchResults, { class = r.class, child = r.child })
		table.insert(labels, resultLabel(r))
	end
	configui.setSelections(P .. "search_list", labels)
	setUI("search_list", 1)
	configui.setLabel(P .. "search_count", "Picked with the controller: the part first, then its parents")
	setPickStatus("Picked " .. labels[1])
	startBlink(hit.class, hit.chain[1].path)
end

local function updatePicker()
	if picking == nil then return end
	local now = os.clock()
	updateHoverPulse(now)
	if now - picking.lastTest < PICK_INTERVAL then return end
	picking.lastTest = now
	local aim = aimOnPanel()
	if aim.problem ~= nil then
		setHover(nil)
		updateBeam(nil)
		setPickStatus(aim.problem)
		return
	end
	-- the beam ends where the ray meets the panel (game units per tracking meter from the hand-to-head distance)
	local panelLength = aim.meters ~= nil and aim.unitsPerMeter ~= nil and aim.meters * aim.unitsPerMeter or nil
	if uevrMenuOpen then
		-- the menu covers the HUD: no picking, but the beam stays so its angle can be tuned with the slider
		setHover(nil)
		updateBeam(aim.onPanel and panelLength or BEAM_MISS_LENGTH, aim.onPanel and "panel" or "miss", aim.beamDir)
		return
	end
	if not aim.onPanel then
		setHover(nil)
		updateBeam(BEAM_MISS_LENGTH, "miss", aim.beamDir)
		return
	end
	local point = panelToAbsolute(aim.u, aim.v)
	local hit, visited = nil, 0
	if point ~= nil then hit, visited = hitTest(point) end
	updateBeam(panelLength or BEAM_MISS_LENGTH, hit ~= nil and "hit" or "panel", aim.beamDir)
	-- shown when the menu is opened again: where the ray landed and what is under it
	local where = string.format("u %.2f v %.2f", aim.u, aim.v) .. (point ~= nil and string.format(" -> %.0f, %.0f", point.X, point.Y) or " -> (no mapping)")
	if hit == nil then
		setHover(nil)
		setPickStatus("Aim " .. where .. ": nothing drawn there (" .. visited .. " widgets tested)")
		return
	end
	local key = addressOf(hit.widget)
	if picking.hover == nil or picking.hover.key ~= key then
		setHover(hit)
		local size = pickSlate:GetAbsoluteSize(hit.widget:GetCachedGeometry())
		setPickStatus(string.format("Aim %s: %s %.0fx%.0f (%d widgets tested)", where, hit.widget:get_fname():to_string(), size.X, size.Y, visited))
		return
	end
	if now - picking.hover.since >= PICK_DWELL then finishPick(hit) end
end

local function startPicking()
	stopPicking()
	stopBlink(true)
	picking = { lastTest = 0, rootsTime = 0 }
	uevrMenuOpen = true
	setPickStatus("Close the UEVR menu, aim at a part of the flat HUD and hold still for " .. PICK_DWELL .. " s")
end

--------------------------- bones and sockets ---------------------------

local boneNames = {}

local function refreshBoneList()
	local names = hud.getTargetSocketNames(currentDefinition())
	local filter = string.lower(configui.getValue(P .. "bone_filter") or "")
	boneNames = {}
	local labels = {}
	if names == nil then
		labels = { "(target not available right now)" }
	else
		for _, name in ipairs(names) do
			if filter == "" or string.find(string.lower(name), filter, 1, true) then
				table.insert(boneNames, name)
				table.insert(labels, name)
			end
		end
		if #labels == 0 then labels = { "(nothing matches the filter)" } end
	end
	configui.setSelections(P .. "bone_list", labels)
	local definition = currentDefinition()
	local socket = definition ~= nil and definition.target ~= nil and definition.target.socket or nil
	setUI("bone_list", indexOf(boneNames, socket, 1))
	configui.setLabel(P .. "bone_count", names ~= nil and (#boneNames .. " of " .. #names) or "")
end

--------------------------- form ---------------------------

-- live factors of the selected element's rules, so angles can be tuned while looking at it
local function updateVisibilityReadout()
	local info = currentId ~= nil and hud.getElementInfo(currentId) or nil
	local debug = info ~= nil and info.visibilityDebug or nil
	if debug == nil then
		configui.setLabel(P .. "vis_readout", info == nil and "Element not built" or "No rules (or Always show): always shown")
		return
	end
	local function f(value) return value == nil and "-" or string.format("%.2f", value) end
	configui.setLabel(P .. "vis_readout", string.format("Now: look %s | facing %s | distance %s | states %s | target %s | shown %s",
		f(debug.lookAt), f(debug.facing), f(debug.distance), debug.state == 0 and "HIDE" or "ok", f(debug.target), f(info.visibility)))
end

local function showTargetGroups(targetType)
	local hasSockets = targetType == "left_hand" or targetType == "right_hand" or targetType == "pawn_mesh" or targetType == "custom"
	configui.hideWidget(P .. "bone_group", not hasSockets)
end

local function showModeGroups(mode)
	configui.hideWidget(P .. "region_group", mode ~= "region")
	configui.hideWidget(P .. "direct_group", mode ~= "direct")
	configui.hideWidget(P .. "child_group", mode == "direct")
	configui.hideWidget(P .. "placement_group", mode == "hide")
end

-- "Rest of this widget" only means something for the whole widget: hidden (and switched off) once a part is picked
local function updateRestOption()
	local definition = currentDefinition()
	local hasPart = definition ~= nil and definition.widget ~= nil and definition.widget.child ~= nil and definition.widget.child ~= ""
	configui.hideWidget(P .. "rest_group", hasPart)
	if hasPart and definition.regionRest == true and not loadingUI then
		hud.setElementValue(currentId, "regionRest", nil)
		setUI("region_rest", false)
		markUnsaved()
	end
end

local function updateInfo()
	local definition = currentDefinition()
	if definition == nil then
		configui.setLabel(P .. "info", "No element selected")
		return
	end
	local text = "Widget: " .. (definition.widget ~= nil and shortName(definition.widget.class) or "(none)")
	if definition.widget ~= nil and definition.widget.child ~= nil and definition.widget.child ~= "" then
		text = text .. "  >  " .. definition.widget.child
	end
	local info = hud.getElementInfo(currentId)
	if info == nil then
		text = text .. "\nState: not built (widget not on screen, element off, or target missing)"
	else
		text = text .. "\nState: " .. tostring(info.mode) .. (info.pending and " (waiting for the first draw)" or " built")
		if info.rect ~= nil then
			text = text .. string.format("\nCopied area: %.0f x %.0f at %.0f, %.0f", info.rect[3], info.rect[4], info.rect[1], info.rect[2])
		end
		if info.warning ~= nil then text = text .. "\nWARNING: " .. info.warning end
	end
	configui.setLabel(P .. "info", wrap(text, 90))
end

local function loadForm()
	local definition = currentDefinition()
	loadingUI = true
	pcall(function()
		if definition == nil then return end
		local widget = definition.widget or {}
		local target = definition.target or {}
		local transform = definition.transform or {}
		local appearance = definition.appearance or {}
		setUI("label", definition.label or definition.id)
		setUI("enabled", definition.enabled ~= false)
		setUI("mode", indexOf(modeValues, definition.mode, 3))
		setUI("region_rest", definition.regionRest == true)
		setUI("bounds", definition.regionBounds == "content" and 2 or 1)
		setUI("padding", definition.regionPadding or 0)
		setUI("resolution", definition.resolutionScale or 1)
		setUI("fixed_area", definition.region ~= nil)
		setUI("region", definition.region or { 0, 0, 400, 200 })
		setUI("tint", appearance.tint or { 1, 1, 1 })
		local visibility = definition.visibility or {}
		local look, face, dist = visibility.lookAt or {}, visibility.facing or {}, visibility.distance or {}
		setUI("fade_time", visibility.fadeTime or 0.25)
		setUI("look_on", look.enabled == true)
		setUI("look_angles", { look.inner or 15, look.outer or 30 })
		setUI("look_min", look.minimum or 0)
		setUI("face_on", face.enabled == true)
		setUI("face_angles", { face.inner or 40, face.outer or 70 })
		setUI("face_min", face.minimum or 0)
		setUI("dist_on", dist.enabled == true)
		setUI("dist_range", { dist.near or 40, dist.far or 70 })
		setUI("dist_min", dist.minimum or 0)
		setUI("hide_paused", visibility.hideWhenPaused == true)
		setUI("hide_cutscene", visibility.hideInCutscene == true)
		setUI("hide_menu", visibility.hideInUEVRMenu == true)
		setUI("hide_hidden", visibility.hideWhenCharacterHidden == true)
		setUI("custom_draw", definition.drawSize ~= nil)
		setUI("draw_size", definition.drawSize or { 1920, 1080 })
		setUI("desired_size", definition.drawAtDesiredSize == true)
		setUI("target", indexOf(targetValues, target.type, 1))
		setUI("socket", target.socket or "")
		setUI("position", transform.position or { 0, 0, 0 })
		setUI("rotation", transform.rotation or { 0, 0, 0 })
		setUI("width", transform.widthCm or 12)
		setUI("opacity", appearance.opacity or 1)
		setUI("brightness", appearance.brightness or 0)
		setUI("exposure", appearance.exposure ~= false)
		setUI("exposure_strength", appearance.exposureStrength or 1)
		setUI("max_tint", appearance.maxTint or 0)
		setUI("blend", (appearance.blendMode or 2) + 1)
		setUI("two_sided", appearance.twoSided ~= false)
		setUI("sort", appearance.sortPriority or 0)
		showModeGroups(definition.mode)
		showTargetGroups(target.type)
		configui.setLabel(P .. "widget_current", "Selected: " .. (widget.class ~= nil and shortName(widget.class) or "(none - pick one below)"))
	end)
	loadingUI = false
	refreshChildList()
	refreshBoneList()
	updateRestOption()
	updateInfo()
end

local function refreshElementList(selectId)
	elementIds = hud.getElementIDs()
	local labels = {}
	for i, id in ipairs(elementIds) do
		local definition = hud.getElement(id)
		labels[i] = (definition ~= nil and definition.label or id) .. (definition ~= nil and definition.enabled == false and "  (off)" or "")
	end
	if #labels == 0 then labels = { "(no elements - press New)" } end
	configui.setSelections(P .. "element", labels)
	currentId = selectId
	if currentId == nil or hud.getElement(currentId) == nil then currentId = elementIds[1] end
	setUI("element", indexOf(elementIds, currentId, 1))
	loadForm()
end

local function newId(base)
	local n = 1
	while hud.getElement(base .. "_" .. n) ~= nil do n = n + 1 end
	return base .. "_" .. n
end

--------------------------- layout ---------------------------

local function section(id, label, open)
	return { widgetType = "tree_node", id = P .. id, label = label, initialOpen = open == true }
end

local function getLayout()
	return {
		{ widgetType = "text", id = P .. "status", label = "No unsaved changes" },
		{ widgetType = "button", id = P .. "save", label = "Save", size = { 90, 24 } },
		{ widgetType = "same_line" },
		{ widgetType = "button", id = P .. "revert", label = "Revert to saved", size = { 130, 24 } },
		{ widgetType = "same_line" },
		{ widgetType = "checkbox", id = P .. "master", label = "HUD elements on", initialValue = true },

		section("elements_node", "Elements", true),
			{ widgetType = "combo", id = P .. "element", label = "Element", selections = { "(none)" }, initialValue = 1, width = 260 },
			{ widgetType = "button", id = P .. "new", label = "New", size = { 70, 22 } },
			{ widgetType = "same_line" },
			{ widgetType = "button", id = P .. "duplicate", label = "Duplicate", size = { 90, 22 } },
			{ widgetType = "same_line" },
			{ widgetType = "button", id = P .. "delete", label = "Delete", size = { 70, 22 } },
			{ widgetType = "input_text", id = P .. "label", label = "Name (shown to players)", initialValue = "", width = 260 },
			{ widgetType = "checkbox", id = P .. "enabled", label = "Element on", initialValue = true },
			{ widgetType = "text", id = P .. "info", label = "No element selected" },
		{ widgetType = "tree_pop" },

		section("widget_node", "Game widget", true),
			{ widgetType = "text", id = P .. "widget_current", label = "Selected: (none)" },
			{ widgetType = "input_text", id = P .. "search_text", label = "Search parts", initialValue = "", width = 180 },
			{ widgetType = "same_line" },
			{ widgetType = "button", id = P .. "search_go", label = "Search", size = { 80, 22 } },
			{ widgetType = "same_line" },
			{ widgetType = "text", id = P .. "search_count", label = "(names and types, e.g. health, ammo, compass)" },
			{ widgetType = "combo", id = P .. "search_list", label = "Result", selections = { "(type a word and press Search)" }, initialValue = 1, width = 520 },
			{ widgetType = "button", id = P .. "search_use", label = "Use this result", size = { 140, 22 } },
			{ widgetType = "same_line" },
			{ widgetType = "button", id = P .. "search_identify", label = "Identify (blink it)", size = { 140, 22 } },
			{ widgetType = "checkbox", id = P .. "pick_on", label = "Pick with the right controller (aim at the flat HUD, hold still 1.5 s)", initialValue = false },
			{ widgetType = "drag_float", id = P .. "pick_angle", label = "Beam angle (degrees down from the handle; adjust until it points out the front)", speed = 0.5, range = { -150, 150 }, initialValue = -90, width = 120 },
			{ widgetType = "text", id = P .. "pick_status", label = "" },
			{ widgetType = "spacing" },
			{ widgetType = "input_text", id = P .. "widget_filter", label = "Filter", initialValue = "", width = 180 },
			{ widgetType = "same_line" },
			{ widgetType = "button", id = P .. "widget_find", label = "Find HUD widgets", size = { 140, 22 } },
			{ widgetType = "same_line" },
			{ widgetType = "text", id = P .. "widget_count", label = "" },
			{ widgetType = "combo", id = P .. "widget_list", label = "Widget", selections = { "(press Find)" }, initialValue = 1, width = 360 },
			{ widgetType = "button", id = P .. "widget_use", label = "Use this widget", size = { 140, 22 } },
			{ widgetType = "begin_group", id = P .. "child_group", isHidden = false },
				{ widgetType = "combo", id = P .. "child_list", label = "Part", selections = { "(whole widget)" }, initialValue = 1, width = 360 },
				{ widgetType = "same_line" },
				{ widgetType = "text", id = P .. "child_count", label = "" },
				{ widgetType = "button", id = P .. "identify", label = "Identify (blink the part)", size = { 180, 22 } },
			{ widgetType = "end_group" },
		{ widgetType = "tree_pop" },

		section("mode_node", "Mode", true),
			{ widgetType = "combo", id = P .. "mode", label = "Mode", selections = modeLabels, initialValue = 3, width = 220 },
			{ widgetType = "begin_group", id = P .. "region_group", isHidden = false },
				{ widgetType = "begin_group", id = P .. "rest_group", isHidden = false },
					{ widgetType = "checkbox", id = P .. "region_rest", label = "Rest of this widget (all but the parts other elements show)", initialValue = false },
				{ widgetType = "end_group" },
				{ widgetType = "combo", id = P .. "bounds", label = "Copied area", selections = boundsLabels, initialValue = 1, width = 280 },
				{ widgetType = "drag_float", id = P .. "padding", label = "Padding (px)", speed = 0.5, range = { 0, 128 }, initialValue = 8, width = 120 },
				{ widgetType = "drag_float", id = P .. "resolution", label = "Resolution scale", speed = 0.05, range = { 0.25, 4 }, initialValue = 2, width = 120 },
				{ widgetType = "checkbox", id = P .. "fixed_area", label = "Fixed area (instead of the part's own rectangle)", initialValue = false },
				{ widgetType = "drag_float4", id = P .. "region", label = "Area x, y, width, height (source px)", speed = 1, range = { 0, 8192 }, initialValue = { 0, 0, 400, 200 }, width = 320 },
			{ widgetType = "end_group" },
			{ widgetType = "begin_group", id = P .. "direct_group", isHidden = true },
				{ widgetType = "checkbox", id = P .. "custom_draw", label = "Custom draw size (default: screen layout size)", initialValue = false },
				{ widgetType = "drag_float2", id = P .. "draw_size", label = "Draw size", speed = 1, range = { 16, 8192 }, initialValue = { 1920, 1080 }, width = 200 },
				{ widgetType = "checkbox", id = P .. "desired_size", label = "Draw at the widget's desired size", initialValue = false },
			{ widgetType = "end_group" },
		{ widgetType = "tree_pop" },

		{ widgetType = "begin_group", id = P .. "placement_group", isHidden = false },
		section("target_node", "Attach to", true),
			{ widgetType = "combo", id = P .. "target", label = "Target", selections = targetLabels, initialValue = 1, width = 220 },
			{ widgetType = "begin_group", id = P .. "bone_group", isHidden = true },
				{ widgetType = "input_text", id = P .. "socket", label = "Bone / socket", initialValue = "", width = 180 },
				{ widgetType = "input_text", id = P .. "bone_filter", label = "Filter", initialValue = "", width = 120 },
				{ widgetType = "same_line" },
				{ widgetType = "button", id = P .. "bone_refresh", label = "List bones", size = { 100, 22 } },
				{ widgetType = "same_line" },
				{ widgetType = "text", id = P .. "bone_count", label = "" },
				{ widgetType = "combo", id = P .. "bone_list", label = "Pick", selections = { "(press List bones)" }, initialValue = 1, width = 260 },
			{ widgetType = "end_group" },
		{ widgetType = "tree_pop" },

		section("placement_node", "Placement", true),
			{ widgetType = "drag_float3", id = P .. "position", label = "Position (cm)", speed = 0.1, range = { -300, 300 }, initialValue = { 0, 0, 0 }, width = 260 },
			{ widgetType = "drag_float3", id = P .. "rotation", label = "Rotation (pitch, yaw, roll)", speed = 0.5, range = { -360, 360 }, initialValue = { 0, 0, 0 }, width = 260 },
			{ widgetType = "drag_float", id = P .. "width", label = "Width (cm)", speed = 0.1, range = { 0.5, 300 }, initialValue = 12, width = 120 },
		{ widgetType = "tree_pop" },

		section("appearance_node", "Appearance", false),
			{ widgetType = "slider_float", id = P .. "opacity", label = "Opacity", range = { 0, 1 }, initialValue = 1, width = 160 },
			{ widgetType = "drag_float3", id = P .. "tint", label = "Tint (R, G, B; 1 = unchanged)", speed = 0.01, range = { 0, 4 }, initialValue = { 1, 1, 1 }, width = 220 },
			{ widgetType = "drag_float", id = P .. "brightness", label = "Brightness (stops)", speed = 0.05, range = { -8, 8 }, initialValue = 0, width = 120 },
			{ widgetType = "checkbox", id = P .. "exposure", label = "Exposure compensation", initialValue = true },
			{ widgetType = "drag_float", id = P .. "exposure_strength", label = "Exposure strength", speed = 0.01, range = { 0, 2 }, initialValue = 1, width = 120 },
			{ widgetType = "drag_float", id = P .. "max_tint", label = "Max brightness multiplier (0 = no cap)", speed = 0.1, range = { 0, 256 }, initialValue = 0, width = 120 },
			{ widgetType = "combo", id = P .. "blend", label = "Blend mode", selections = blendLabels, initialValue = 3, width = 160 },
			{ widgetType = "checkbox", id = P .. "two_sided", label = "Two sided", initialValue = true },
			{ widgetType = "slider_int", id = P .. "sort", label = "Sort priority", range = { -10, 10 }, initialValue = 0, width = 160 },
		{ widgetType = "tree_pop" },
		{ widgetType = "end_group" },

		section("visibility_node", "When to show", false),
			{ widgetType = "text", id = P .. "vis_readout", label = "No rules: always shown" },
			{ widgetType = "drag_float", id = P .. "fade_time", label = "Fade time (s)", speed = 0.01, range = { 0, 3 }, initialValue = 0.25, width = 120 },
			{ widgetType = "checkbox", id = P .. "look_on", label = "When looked at (glance)", initialValue = false },
			{ widgetType = "drag_float2", id = P .. "look_angles", label = "Full within / gone beyond (degrees from view)", speed = 0.2, range = { 0, 180 }, initialValue = { 15, 30 }, width = 200 },
			{ widgetType = "slider_float", id = P .. "look_min", label = "Minimum opacity##look", range = { 0, 1 }, initialValue = 0, width = 160 },
			{ widgetType = "checkbox", id = P .. "face_on", label = "When its front faces the eyes (wrist turn)", initialValue = false },
			{ widgetType = "drag_float2", id = P .. "face_angles", label = "Full within / gone beyond (degrees)", speed = 0.2, range = { 0, 180 }, initialValue = { 40, 70 }, width = 200 },
			{ widgetType = "slider_float", id = P .. "face_min", label = "Minimum opacity##face", range = { 0, 1 }, initialValue = 0, width = 160 },
			{ widgetType = "checkbox", id = P .. "dist_on", label = "When close to the head", initialValue = false },
			{ widgetType = "drag_float2", id = P .. "dist_range", label = "Full within / gone beyond (cm)", speed = 0.5, range = { 0, 500 }, initialValue = { 40, 70 }, width = 200 },
			{ widgetType = "slider_float", id = P .. "dist_min", label = "Minimum opacity##dist", range = { 0, 1 }, initialValue = 0, width = 160 },
			{ widgetType = "checkbox", id = P .. "hide_paused", label = "Hide while the game is paused", initialValue = false },
			{ widgetType = "checkbox", id = P .. "hide_cutscene", label = "Hide during cutscenes", initialValue = false },
			{ widgetType = "checkbox", id = P .. "hide_menu", label = "Hide while the UEVR menu is open", initialValue = false },
			{ widgetType = "checkbox", id = P .. "hide_hidden", label = "Hide while the player character is hidden", initialValue = false },
		{ widgetType = "tree_pop" },

		section("global_node", "All elements", false),
			{ widgetType = "combo", id = P .. "exposure_source", label = "Exposure source", selections = exposureLabels, initialValue = 1, width = 320 },
			{ widgetType = "drag_float", id = P .. "global_stops", label = "Global brightness (stops)", speed = 0.05, range = { -8, 8 }, initialValue = 0, width = 120 },
			{ widgetType = "slider_int", id = P .. "redraw_rate", label = "VR redraws per second (0 = every frame; 30-45 saves GPU time)", range = { 0, 120 }, initialValue = 0, width = 160 },
			{ widgetType = "text", id = P .. "stats", label = "Cost: measuring..." },
		{ widgetType = "tree_pop" },
	}
end

--------------------------- callbacks ---------------------------

local function registerCallbacks()
	configui.onUpdate(P .. "save", function()
		hud.saveParameters()
		if hud.refreshPlayerConfiguration ~= nil then hud.refreshPlayerConfiguration() end
		setStatus("Saved at " .. os.date("%H:%M:%S"))
	end)
	configui.onUpdate(P .. "revert", function()
		pendingEdits = {}
		hud.revertParameters()
		setUI("exposure_source", indexOf(exposureValues, hud.getExposureSourceName(), 1))
		setUI("global_stops", hud.getExposureStops())
		setUI("redraw_rate", hud.getRedrawRate ~= nil and hud.getRedrawRate() or 0)
		refreshElementList(currentId)
		setStatus("Reverted to the saved set")
	end)
	configui.onUpdate(P .. "master", function(value) hud.setEnabled(value) end)

	configui.onUpdate(P .. "element", function(index)
		currentId = elementIds[index]
		loadForm()
	end)
	configui.onUpdate(P .. "new", function()
		local id = newId("element")
		hud.addElement({
			id = id, label = id, mode = hud.Mode.REGION, widget = {},
			regionPadding = 8, resolutionScale = 2,
			target = { type = hud.Target.LEFT_CONTROLLER },
			transform = { position = { 0, 0, 8 }, rotation = { 0, 180, 0 }, widthCm = 12 },
			appearance = { exposure = true, twoSided = true },
		})
		refreshElementList(id)
		markUnsaved()
	end)
	configui.onUpdate(P .. "duplicate", function()
		local definition = currentDefinition()
		if definition == nil then return end
		local copy = deepCopy(definition)
		copy.id = newId(definition.id)
		copy.label = (definition.label or definition.id) .. " copy"
		hud.addElement(copy)
		refreshElementList(copy.id)
		markUnsaved()
	end)
	configui.onUpdate(P .. "delete", function()
		if currentId == nil then return end
		hud.removeElement(currentId)
		refreshElementList(nil)
		markUnsaved()
	end)
	configui.onUpdate(P .. "label", function(value)
		local definition = currentDefinition()
		if definition == nil or loadingUI then return end
		definition.label = value -- display only, no rebuild
		markUnsaved()
	end)
	configui.onUpdate(P .. "enabled", function(value)
		if currentId == nil or loadingUI then return end
		hud.setElementEnabled(currentId, value)
		markUnsaved()
	end)

	configui.onUpdate(P .. "widget_find", function() refreshWidgetList() end)
	configui.onUpdate(P .. "widget_use", function()
		local path = widgetClasses[configui.getValue(P .. "widget_list") or 1]
		if path == nil or currentId == nil then return end
		local definition = currentDefinition()
		definition.widget = { class = path } -- a new widget starts as the whole widget, no part picked
		hud.setElementValue(currentId, { "widget", "class" }, path)
		markUnsaved()
		loadForm()
	end)
	configui.onUpdate(P .. "child_list", function(index)
		local name = childNames[index]
		local hasPart = name ~= nil and name ~= ""
		local definition = currentDefinition()
		configui.hideWidget(P .. "rest_group", hasPart)
		if hasPart and definition ~= nil and definition.regionRest == true then
			editLive("regionRest", nil)
			setUI("region_rest", false)
		end
		editRebuild({ "widget", "child" }, hasPart and name or nil)
	end)

	configui.onUpdate(P .. "mode", function(index)
		showModeGroups(modeValues[index])
		editRebuild("mode", modeValues[index])
	end)
	configui.onUpdate(P .. "region_rest", function(value) editLive("regionRest", value == true or nil) end)
	configui.onUpdate(P .. "bounds", function(index) editRebuild("regionBounds", index == 2 and "content" or nil) end)
	configui.onUpdate(P .. "padding", function(value) editRebuild("regionPadding", value) end)
	configui.onUpdate(P .. "resolution", function(value) editRebuild("resolutionScale", value) end)
	configui.onUpdate(P .. "custom_draw", function(value)
		editRebuild("drawSize", value and vec(configui.getValue(P .. "draw_size"), 2) or nil)
	end)
	configui.onUpdate(P .. "draw_size", function(value)
		if configui.getValue(P .. "custom_draw") then editRebuild("drawSize", vec(value, 2)) end
	end)
	configui.onUpdate(P .. "desired_size", function(value) editRebuild("drawAtDesiredSize", value) end)

	configui.onUpdate(P .. "identify", function()
		local definition = currentDefinition()
		if definition == nil or definition.widget == nil then return end
		local child = childNames[configui.getValue(P .. "child_list") or 1]
		startBlink(definition.widget.class, (child ~= nil and child ~= "") and child or nil)
	end)

	configui.onUpdate(P .. "search_go", function() runSearch() end)
	configui.onUpdate(P .. "pick_on", function(value)
		if value then
			startPicking()
		else
			stopPicking()
			setPickStatus("")
		end
	end)
	configui.onUpdate(P .. "search_identify", function()
		local result = searchResults[configui.getValue(P .. "search_list") or 1]
		if result ~= nil then startBlink(result.class, result.child) end
	end)
	configui.onUpdate(P .. "search_use", function()
		local result = searchResults[configui.getValue(P .. "search_list") or 1]
		if result == nil then return end
		if currentId == nil or hud.getElement(currentId) == nil then
			setStatus("Press New first, then Use this result")
			return
		end
		local definition = currentDefinition()
		definition.widget = { class = result.class, child = result.child }
		local name = result.child ~= nil and result.child:match("([^/]+)$") or shortName(result.class)
		if definition.label == nil or definition.label == definition.id then definition.label = name end
		hud.setElementValue(currentId, { "widget", "child" }, result.child) -- rebuilds with the new widget
		markUnsaved()
		refreshElementList(currentId)
	end)

	-- visibility rules: each rule is written as a whole from its widgets (no rebuild, read every frame)
	local function writeRule(name, onId, rangeId, minId, firstKey, secondKey)
		local range = vec(configui.getValue(P .. rangeId), 2) or { 0, 0 }
		editLive({ "visibility", name }, {
			enabled = configui.getValue(P .. onId) == true,
			[firstKey] = range[1], [secondKey] = math.max(range[2], range[1] + 0.1),
			minimum = configui.getValue(P .. minId) or 0,
		})
	end
	for _, rule in ipairs({
		{ "lookAt", "look_on", "look_angles", "look_min", "inner", "outer" },
		{ "facing", "face_on", "face_angles", "face_min", "inner", "outer" },
		{ "distance", "dist_on", "dist_range", "dist_min", "near", "far" },
	}) do
		local name, onId, rangeId, minId, firstKey, secondKey = table.unpack(rule)
		for _, widget in ipairs({ onId, rangeId, minId }) do
			configui.onUpdate(P .. widget, function() writeRule(name, onId, rangeId, minId, firstKey, secondKey) end)
		end
	end
	configui.onUpdate(P .. "fade_time", function(value) editLive({ "visibility", "fadeTime" }, value) end)
	configui.onUpdate(P .. "hide_paused", function(value) editLive({ "visibility", "hideWhenPaused" }, value) end)
	configui.onUpdate(P .. "hide_cutscene", function(value) editLive({ "visibility", "hideInCutscene" }, value) end)
	configui.onUpdate(P .. "hide_menu", function(value) editLive({ "visibility", "hideInUEVRMenu" }, value) end)
	configui.onUpdate(P .. "hide_hidden", function(value) editLive({ "visibility", "hideWhenCharacterHidden" }, value) end)

	configui.onUpdate(P .. "fixed_area", function(value)
		if not value then
			editRebuild("region", nil)
			return
		end
		-- start from the rectangle being copied now, so ticking the box changes nothing until it is edited
		local info = currentId ~= nil and hud.getElementInfo(currentId) or nil
		local area = info ~= nil and info.rect ~= nil and { info.rect[1], info.rect[2], info.rect[3], info.rect[4] } or vec(configui.getValue(P .. "region"), 4)
		local definition = currentDefinition()
		local padding = definition ~= nil and definition.regionPadding or 0
		if info ~= nil and info.rect ~= nil then -- the copied rectangle includes the padding, the definition does not
			area = { area[1] + padding, area[2] + padding, area[3] - 2 * padding, area[4] - 2 * padding }
		end
		setUI("region", area)
		editRebuild("region", area)
	end)
	configui.onUpdate(P .. "region", function(value)
		if configui.getValue(P .. "fixed_area") then editRebuild("region", vec(value, 4)) end
	end)
	configui.onUpdate(P .. "tint", function(value) editLive({ "appearance", "tint" }, vec(value, 3)) end)

	configui.onUpdate(P .. "bone_refresh", function() refreshBoneList() end)
	configui.onUpdate(P .. "bone_filter", function() refreshBoneList() end)
	configui.onUpdate(P .. "bone_list", function(index)
		local name = boneNames[index]
		if name == nil then return end
		setUI("socket", name)
		editRebuild({ "target", "socket" }, name)
	end)

	configui.onUpdate(P .. "target", function(index)
		showTargetGroups(targetValues[index])
		editRebuild({ "target", "type" }, targetValues[index])
	end)
	configui.onUpdate(P .. "socket", function(value) editRebuild({ "target", "socket" }, value ~= "" and value or nil) end)

	configui.onUpdate(P .. "position", function(value) editLive({ "transform", "position" }, vec(value, 3)) end)
	configui.onUpdate(P .. "rotation", function(value) editLive({ "transform", "rotation" }, vec(value, 3)) end)
	configui.onUpdate(P .. "width", function(value) editLive({ "transform", "widthCm" }, value) end)

	configui.onUpdate(P .. "opacity", function(value) editLive({ "appearance", "opacity" }, value) end)
	configui.onUpdate(P .. "brightness", function(value) editLive({ "appearance", "brightness" }, value) end)
	configui.onUpdate(P .. "exposure", function(value) editLive({ "appearance", "exposure" }, value) end)
	configui.onUpdate(P .. "exposure_strength", function(value) editLive({ "appearance", "exposureStrength" }, value) end)
	configui.onUpdate(P .. "max_tint", function(value) editLive({ "appearance", "maxTint" }, value > 0 and value or nil) end)
	configui.onUpdate(P .. "blend", function(index) editLive({ "appearance", "blendMode" }, index - 1) end)
	configui.onUpdate(P .. "two_sided", function(value) editLive({ "appearance", "twoSided" }, value) end)
	configui.onUpdate(P .. "sort", function(value) editLive({ "appearance", "sortPriority" }, value) end)

	configui.onUpdate(P .. "exposure_source", function(index)
		hud.setExposureSourceName(exposureValues[index])
		markUnsaved()
	end)
	configui.onUpdate(P .. "global_stops", function(value)
		hud.setExposureStops(value)
		markUnsaved()
	end)
	configui.onUpdate(P .. "redraw_rate", function(value)
		hud.setRedrawRate(value)
		markUnsaved()
	end)
end

--------------------------- init ---------------------------

local infoTimer = 0
local readoutTimer = 0
function M.init(hudModule)
	hud = hudModule
	registerCallbacks()
	configui.create({ { panelLabel = "HUD Dev", id = PANEL_ID, layout = getLayout() } })
	setUI("exposure_source", indexOf(exposureValues, hud.getExposureSourceName(), 1))
	setUI("global_stops", hud.getExposureStops())
	setUI("redraw_rate", hud.getRedrawRate ~= nil and hud.getRedrawRate() or 0)
	refreshElementList(nil)

	uevr.params.sdk.callbacks.on_script_reset(function()
		stopBlink(true) -- a part blinked away must not stay invisible
		stopPicking() -- nor one the picker was pulsing
	end)
	-- the picker waits while the UEVR menu covers the HUD
	uevrUtils.registerUEVRUIChangeCallback(function(value)
		uevrMenuOpen = value == true
		if picking ~= nil then pcall(hud.print, "[picker] UEVR menu " .. (uevrMenuOpen and "open: paused" or "closed: aiming")) end
	end)

	uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
		local now = os.clock()
		for key, edit in pairs(pendingEdits) do
			if now >= edit.time then
				pendingEdits[key] = nil
				pcall(edit.fn)
			end
		end
		pcall(updateBlink)
		local ok, err = pcall(updatePicker)
		if not ok and picking ~= nil then -- report once and stop, rather than fail every tick
			stopPicking()
			setUI("pick_on", false)
			setPickStatus("Picker stopped: " .. tostring(err))
		end
		readoutTimer = readoutTimer + delta
		if readoutTimer >= 0.2 then
			readoutTimer = 0
			pcall(updateVisibilityReadout)
		end
		infoTimer = infoTimer + delta
		if infoTimer >= 1.0 then -- the state line follows builds, rebuilds and level loads
			infoTimer = 0
			pcall(updateInfo)
			pcall(function()
				local s = hud.getStats ~= nil and hud.getStats() or nil
				if s ~= nil then
					configui.setLabel(P .. "stats", string.format("Cost: %.2f ms of Lua per frame (average), %.1f Region copies per frame", s.averageMs, s.copiesPerFrame))
				end
			end)
		end
	end)
end

return M
