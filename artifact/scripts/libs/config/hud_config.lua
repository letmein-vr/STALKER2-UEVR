--[[
	Player panel for libs/hud.lua ("HUD" tab in the UEVR overlay): per element on/off, size and opacity, on top of
	what the modder defined. Shown with hud.showPlayerConfiguration(panelLabel, saveFileName) after hud.init.
	Player choices save themselves (configui) to data/<saveFileName>.json and are applied through
	hud.setPlayerSetting, so the modder's element definitions are never changed.
]]--

local configui = require("libs/configui")

local M = {}

local P = "hud_player_"
local hud = nil
local panelLabel = "HUD"
local saveFile = "hud_player_config"
local registered = {} -- element ids whose callbacks exist (callbacks cannot be removed, so only added once)

local function widgetId(id, key)
	return P .. id .. "_" .. key
end

local function registerElement(id)
	if registered[id] then return end
	registered[id] = true
	configui.onCreateOrUpdate(widgetId(id, "enabled"), function(value) hud.setPlayerSetting(id, "enabled", value ~= false) end)
	configui.onCreateOrUpdate(widgetId(id, "size"), function(value) hud.setPlayerSetting(id, "sizeScale", value or 1.0) end)
	configui.onCreateOrUpdate(widgetId(id, "opacity"), function(value) hud.setPlayerSetting(id, "opacity", value or 1.0) end)
	configui.onCreateOrUpdate(widgetId(id, "always"), function(value) hud.setPlayerSetting(id, "alwaysShow", value == true) end)
end

-- true when the modder gave the element any visibility rule (only then is "Always show" offered)
local function hasRules(definition)
	local v = definition.visibility
	if type(v) ~= "table" then return false end
	local function on(rule) return type(rule) == "table" and rule.enabled == true end
	return on(v.lookAt) or on(v.facing) or on(v.distance) or v.hideWhenPaused == true or v.hideInCutscene == true
		or v.hideInUEVRMenu == true or v.hideWhenCharacterHidden == true
end

local function getLayout()
	local layout = {}
	local ids = hud.getElementIDs()
	local shown = 0
	for _, id in ipairs(ids) do
		local definition = hud.getElement(id)
		if definition ~= nil and definition.enabled ~= false then
			shown = shown + 1
			registerElement(id)
			table.insert(layout, { widgetType = "checkbox", id = widgetId(id, "enabled"), label = definition.label or id, initialValue = true })
			table.insert(layout, { widgetType = "indent", width = 20 })
			table.insert(layout, { widgetType = "slider_float", id = widgetId(id, "size"), label = "Size", range = { 0.5, 2.0 }, initialValue = 1.0, width = 160 })
			table.insert(layout, { widgetType = "slider_float", id = widgetId(id, "opacity"), label = "Opacity", range = { 0.1, 1.0 }, initialValue = 1.0, width = 160 })
			table.insert(layout, { widgetType = "checkbox", id = widgetId(id, "always"), label = "Always show (ignore when-to-show rules)", initialValue = false,
				isHidden = not hasRules(definition) })
			table.insert(layout, { widgetType = "unindent", width = 20 })
		end
	end
	if shown == 0 then
		table.insert(layout, { widgetType = "text", label = "No HUD elements are set up for this game." })
	end
	return layout
end

function M.show(hudModule, label, fileName)
	hud = hudModule
	panelLabel = label or panelLabel
	saveFile = fileName or saveFile
	-- callbacks are registered in getLayout before the panel loads its saved values, so they apply at once
	configui.create({ { panelLabel = panelLabel, saveFile = saveFile, layout = getLayout() } })
end

-- after the modder saved a changed element set: rebuild the list, keeping the player's saved choices
function M.refresh()
	if hud == nil then return end
	configui.update({ { panelLabel = panelLabel, saveFile = saveFile, layout = getLayout() } })
end

return M
