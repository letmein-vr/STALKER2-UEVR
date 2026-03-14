
local uevrUtils = require("libs/uevr_utils")
local configui = require("libs/configui")

local M = {}

local configFileName = "input_config"
local configTabLabel = "Input Config"
local widgetPrefix = "uevr_input_config_"

local configDefaults = {
    useSnapTurn = true,
    snapAngle = 45,
    smoothTurnSpeed = 50,
}

local function getConfigWidgets()
    return spliceableInlineArray {
        {
            widgetType = "checkbox",
            id = widgetPrefix .. "useSnapTurn",
            label = "Use Snap Turn",
            initialValue = configDefaults["useSnapTurn"]
        },
        {
            widgetType = "slider_int",
            id = widgetPrefix .. "snapAngle",
            label = "Snap Turn Angle",
            speed = 1.0,
            range = {2, 180},
            initialValue = configDefaults["snapAngle"]
        },
        {
            widgetType = "slider_int",
            id = widgetPrefix .. "smoothTurnSpeed",
            label = "Smooth Turn Speed",
            speed = 1.0,
            range = {1, 200},
            initialValue = configDefaults["smoothTurnSpeed"]
        },
    }
end

local function updateSetting(key, value)
    uevrUtils.executeUEVRCallbacks("on_input_config_param_change", key, value, true)
end

local function updateUIState(key)
    local exKey = widgetPrefix .. key
    if key == "useSnapTurn" then
        configui.hideWidget(widgetPrefix .. "snapAngle", not configui.getValue(exKey))
        configui.hideWidget(widgetPrefix .. "smoothTurnSpeed", configui.getValue(exKey))
    end
end

configui.onUpdate(widgetPrefix .. "useSnapTurn", function(value)
    updateSetting("useSnapTurn", value)
    updateUIState("useSnapTurn")
end)

configui.onUpdate(widgetPrefix .. "snapAngle", function(value)
    updateSetting("snapAngle", value)
end)

configui.onUpdate(widgetPrefix .. "smoothTurnSpeed", function(value)
    updateSetting("smoothTurnSpeed", value)
end)

configui.onCreate(widgetPrefix .. "useSnapTurn", function(value)
    --print("Creating useSnapTurn widget")
    configui.setValue(widgetPrefix .. "useSnapTurn", configDefaults["useSnapTurn"], true)
    updateUIState("useSnapTurn")
end)

configui.onCreate(widgetPrefix .. "snapAngle", function(value)
    configui.setValue(widgetPrefix .. "snapAngle", configDefaults["snapAngle"], true)
end)

configui.onCreate(widgetPrefix .. "smoothTurnSpeed", function(value)
    configui.setValue(widgetPrefix .. "smoothTurnSpeed", configDefaults["smoothTurnSpeed"], true)
end)


function M.init(m_paramManager)
    configDefaults = m_paramManager and m_paramManager:getAllActiveProfileParams() or {}

	m_paramManager:registerProfileChangeCallback(function(profileParams)
        for key, value in pairs(profileParams) do
            configui.setValue(widgetPrefix .. key, value, true)
            updateUIState(key)
        end
	end)
     -- M.showConfiguration(configFileName)
    -- for key, value in pairs(parameters) do
    --     updateUIState(key)
    --     configui.setValue(widgetPrefix .. key, value, true)
    -- end
end

function M.getConfigurationWidgets(options)
	return configui.applyOptionsToConfigWidgets(getConfigWidgets(), options)
end

function M.showConfiguration(saveFileName, options)
	local configDefinition = {
		{
			panelLabel = configTabLabel,
			saveFile = saveFileName,
			layout = spliceableInlineArray{
				expandArray(M.getConfigurationWidgets, options)
			}
		}
	}
	configui.create(configDefinition)
end

uevrUtils.registerUEVRCallback("on_input_config_param_change", function(key, value)
    configui.setValue(widgetPrefix .. key, value, true)
    updateUIState(key)
end)

return M