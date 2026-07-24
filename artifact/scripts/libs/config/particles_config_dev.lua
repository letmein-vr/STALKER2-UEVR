local uevrUtils = require("libs/uevr_utils")
local configui = require("libs/configui")
local particles = require("libs/particles")
local controllers = require("libs/controllers")

local M = {}

local configFileName = "particles_config_dev"
local configTabLabel = "Particles Config Dev"
local widgetPrefix = "uevr_particles_"

local configDefaults = {
}

local function getConfigWidgets()
    return spliceableInlineArray {
        {
            widgetType = "tree_node",
            id = widgetPrefix .. "finder_tool",
            initialOpen = false,
            label = "Particle System Finder"
        },
            { widgetType = "begin_group", id = widgetPrefix .. "finder_tool_group", isHidden = false }, { widgetType = "indent", width = 10 }, { widgetType = "text", label = "" }, { widgetType = "begin_rect", },
            {
                widgetType = "tree_node",
                id = widgetPrefix .. "finder_tool_instruction_tree",
                initialOpen = false,
                label = "Particle System Finder Instructions"
            },
                {
                    widgetType = "text",
                    id = widgetPrefix .. "finder_tool_instructions",
                    label = "Perform the search when the game reticule is currently visible on the screen. The finder will automatically search for widgets that contain the words Cursor, Reticule, Reticle or Crosshair in their name. You can also enter text in the search text box to search for additional widgets. Press the Find button to see an updated list of widgets. After selecting a widget press Toggle Visibility to see if it is the correct one. If it is, press Use Selected to use it as the Widget Class.",
                    wrapped = true
                },
            { widgetType = "tree_pop" },
            {
                widgetType = "combo",
                id = widgetPrefix .. "finder_emitter_type",
                label = "Emitters Type",
                selections = {"NiagaraSystem", "ParticleSystem"},
                initialValue = 1,
            },
            {
                widgetType = "input_text",
                id = widgetPrefix .. "finder_tool_search_text",
                label = "",
                initialValue = ""
            },
            { widgetType = "same_line", },
            {
                widgetType = "button",
                id = widgetPrefix .. "finder_tool_search_button",
                label = "Find",
                size = {80,22}
            },
            {
                widgetType = "combo",
                id = widgetPrefix .. "finder_tool_list",
                label = "Particle Emitters",
                selections = {"None"},
                initialValue = 1,
            },
            {
                widgetType = "button",
                id = widgetPrefix .. "finder_test_button",
                label = "Test",
                size = {80,22}
            },
            {
                widgetType = "button",
                id = widgetPrefix .. "finder_stop_test_button",
                label = "Stop",
                size = {80,22}
            },
        {
            widgetType = "tree_pop"
        },
    }
end

local searchText = nil
local niagaraSystems = nil
local particleSystems = nil
local niagaraNames = {}
local particleNames = {}
local function loadParticlesSystems()
    --Class /Script/Niagara.NiagaraSystem
    --Class /Script/Engine.ParticleSystem
    local results = {}
    if configui.getValue(widgetPrefix .. "finder_emitter_type") == 1 then
        niagaraSystems = uevrUtils.find_all_instances("Class /Script/Niagara.NiagaraSystem", false)
        niagaraNames = {}
        if niagaraSystems ~= nil then
            for name, niagara in pairs(niagaraSystems) do
                --print(niagara:get_full_name())
                if searchText == nil or searchText == "" or string.find(niagara:get_full_name(), searchText) then
                    table.insert(niagaraNames, niagara:get_full_name())
                end
            end
        end
        results = niagaraNames
    else
        particleSystems = uevrUtils.find_all_instances("Class /Script/Engine.ParticleSystem", false)
        particleNames = {}
        if particleSystems ~= nil then
            for name, particle in pairs(particleSystems) do
                --print(particle:get_full_name())
                if searchText == nil or searchText == "" or string.find(particle:get_full_name(), searchText) then
                    table.insert(particleNames, particle:get_full_name())
                end
            end
        end
        results = particleNames
    end
    configui.setSelections(widgetPrefix .. "finder_tool_list", results)
end

local currentParticleEmitter = nil
local function testParticleEmitter()
    local selectedIndex = configui.getValue(widgetPrefix .. "finder_tool_list")
    if selectedIndex ~= nil and selectedIndex > 0 then
        --local selectedName = configui.getSelections(widgetPrefix .. "finder_tool_list")[selectedIndex]
        if configui.getValue(widgetPrefix .. "finder_emitter_type") == 1 then
            if niagaraNames ~= nil then
                local niagara = niagaraNames[configui.getValue(widgetPrefix .. "finder_tool_list")]
                if niagara ~= nil then
                    particles.new({
                        particleSystemAsset = niagara,
                        scale = {0.04, 0.04, 0.04},
                        autoActivate = true
                    })
                end
            end
        else
            if particleNames ~= nil then
                   currentParticleEmitter = particles.new({
                        particleSystemAsset = particleNames[configui.getValue(widgetPrefix .. "finder_tool_list")],
                        scale = {0.04, 0.04, 0.04},
                        autoActivate = true
                    })
                    if currentParticleEmitter ~= nil then
                        currentParticleEmitter:attachTo(controllers.getController(Handed.Left))
                        currentParticleEmitter:setRelativeLocation({X=50, Y=0, Z=0})
                    end
               
            end
        end
    end
end

local function stopParticleEmitter()
    if currentParticleEmitter ~= nil then
        currentParticleEmitter:destroy()
    end
    currentParticleEmitter = nil
end

function M.init(isDeveloperMode, logLevel)
    if logLevel ~= nil then
        M.setLogLevel(logLevel)
    end
    if isDeveloperMode == nil and uevrUtils.getDeveloperMode() ~= nil then
        isDeveloperMode = uevrUtils.getDeveloperMode()
    end

    if isDeveloperMode then
		M.showDeveloperConfiguration(configFileName)
        loadParticlesSystems()
    else
    end
end

function M.getDeveloperConfigurationWidgets(options)
	return configui.applyOptionsToConfigWidgets(getConfigWidgets(), options)
end

function M.showDeveloperConfiguration(saveFileName, options)
	configui.createConfigPanel(configTabLabel, saveFileName, spliceableInlineArray{expandArray(M.getDeveloperConfigurationWidgets, options)})
end

configui.onUpdate(widgetPrefix .. "finder_emitter_type", function(value)
    loadParticlesSystems()
end)
configui.onUpdate(widgetPrefix .. "finder_tool_search_text", function(value)
    searchText = value
end)

configui.onUpdate(widgetPrefix .. "finder_test_button", function()
    testParticleEmitter()
    configui.setHidden(widgetPrefix .. "finder_test_button", true)
    configui.setHidden(widgetPrefix .. "finder_stop_test_button", false)
end)
configui.onUpdate(widgetPrefix .. "finder_stop_test_button", function()
    stopParticleEmitter()
    configui.setHidden(widgetPrefix .. "finder_test_button", false)
    configui.setHidden(widgetPrefix .. "finder_stop_test_button", true)
end)
return M