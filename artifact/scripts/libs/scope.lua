--[[
Usage
	Drop the libs folder containing this file into your project folder
	Add code like this in your script:
		local scope = require("libs/scope")

	This module implements an instance-based “scope / optic” effect using a SceneCapture2D
	rendering into a RenderTarget2D, which is then displayed on an “ocular lens” mesh.

	Scopes are managed per-weapon-type via `weaponTypeID`. Multiple scope instances can
	exist at once (e.g., multiple weapons, multiple attachments). The module tracks active
	instances and can automatically route input (zoom/brightness) to the scope closest to
	the HMD.

	The module is mainly designed to provide a scope configuration UI to other systems such
	as attachments but it can be used standalone as well.

	Available module functions:

	scope.new(weaponTypeID, options) -> Scope
		Creates a new scope instance for a given weapon type and auto-creates its components.
		weaponTypeID: string key used for parameter persistence and instance grouping.
		options: table (optional) passed through to Scope:create(options). Common fields:
			disabled: bool (default from persisted "disable")
			brightness: number
			deactivateDistance: number (stored to "deactivate_distance")
			hideOcularLensOnDisable: bool (stored to "hide_ocular_lens_on_disable")

	scope.getConfigWidgets(prefix) -> table
		Returns `configui` widget descriptors for editing scope parameters.
		prefix: optional string to namespace widget IDs.

	scope.createConfigCallbacks(weaponTypeID, prefix)
		Registers `configui.onUpdate` callbacks that persist settings and update all active
		scope instances for that weaponTypeID.

	scope.getScopeCount() -> number
		Returns total number of active scope instances.

	scope.setAutoHandleInput(value)
		Enables/disables automatic input routing (zoom/brightness) to the closest active scope.

	scope.updateScopes(delta)
		Updates active state for all scopes and, if autoHandleInput is enabled, applies zoom/
		brightness input to the closest active scope.

	scope.setDefaultPitchOffset(value)
		Sets a pitch offset applied when positioning/rotating lens components.

	scope.init(isDeveloperMode, logLevel)
		Loads persisted parameters via paramManager.

	Enums:
		scope.AdjustMode.ZOOM / scope.AdjustMode.BRIGHTNESS

	Scope instance methods (returned by scope.new):
		scopeInstance:create(options) -> ocularLensComponent, objectiveLensComponent
			(Re)creates the RenderTarget, ocular lens mesh, and SceneCapture component.
		scopeInstance:destroy()
		scopeInstance:attachTo(attachmentComponent)
		scopeInstance:disable(value)
		scopeInstance:isDisplaying() -> bool

		Zoom/Brightness:
			scopeInstance:setZoom(zoom)
			scopeInstance:updateZoom(direction, delta)
			scopeInstance:setBrightness(value)
			scopeInstance:updateBrightness(direction, delta)

		Lens transforms:
			scopeInstance:setOcularLensScale(value)
			scopeInstance:setObjectiveLensRelativeRotation(rot)
			scopeInstance:setObjectiveLensRelativeLocation(vec)
			scopeInstance:setOcularLensRelativeRotation(rot)
			scopeInstance:setOcularLensRelativeLocation(vec)
			scopeInstance:showDebugMeshes(value)

		Components:
			scopeInstance:getOcularLensComponent()
			scopeInstance:getObjectiveLensComponent()
	
	Examples:
		--create
		attachmentScopes[gripHand] = scope.new(id)
		attachmentScopes[gripHand]:attachTo(attachment)

		--destroy
		if attachmentScopes[gripHand] ~= nil then
			attachmentScopes[gripHand]:destroy()
			attachmentScopes[gripHand] = nil
		end

		--get scope ui widgets as part of another module's configuration
		local scopeWidgets = scope.getConfigWidgets(widgetPrefix .. name .. "_")
		for j = 1, #scopeWidgets do
			table.insert(configDefinition[1]["layout"], scopeWidgets[j])
		end


	Notes:
		- “min_fov” is the narrowest FOV (highest zoom), “max_fov” is the widest FOV (lowest zoom).
		- Active state is automatically toggled based on HMD distance to the ocular lens
		  ("deactivate_distance").
		- This module registers an OnPreInputGetState callback to read thumbstick input and
		  prevent snap turning while adjusting.

]]--

local uevrUtils = require("libs/uevr_utils")
local controllers = require("libs/controllers")
local configui = require("libs/configui")
local paramModule = require("libs/core/params")

local M = {}

-- Scope class definition
local Scope = {}
Scope.__index = Scope

local maxZoom = 1.0
local minZoom = 0.0

local brightnessSpeed = 3.0
local maxBrightness = 8.0
local minBrightness = 0.1

local defaultPitchOffset = 0.0

local parameterDefaults = {
	min_fov = 2.0,
	max_fov = 20.0,
	brightness = 2.0,
	ocular_lens_scale = 1.0,
	objective_lens_rotation = {0.0, 0.0, 0.0},
	objective_lens_location = {0.0, 0.0, 20.0},
	ocular_lens_rotation = {0.0, 0.0, 0.0},
	ocular_lens_location = {0.0, 0.0, 20.0},
	zoom_speed = 1.0,
	zoom_exponential = 0.5,
	disable = false,
	deactivate_distance = 50.0,
	show_debug = false,
	zoom = 1.0,
	hide_ocular_lens_on_disable = true,
}

local currentLogLevel = LogLevel.Error
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
	if logLevel == nil then logLevel = LogLevel.Debug end
	if logLevel <= currentLogLevel then
		uevrUtils.print("[scope] " .. text, logLevel)
	end
end

local parametersFileName = "scope_parameters"
local parameters = {}
local paramManager = paramModule.new(parametersFileName, parameters, true)

local activeScopeInstances = {}  -- Table to track all active scope instances by weaponTypeID
local activeScopeCount = 0

-- Module-level parameter functions (shared by weapon type ID)
local function saveParameter(scopeID, key, value, persist)
	paramManager:set({"scopes", scopeID, key}, value, persist)
end

local function getParameter(scopeID, key)
	local value = paramManager:get({"scopes", scopeID, key})
    return value or parameterDefaults[key]
end

-- Constructor for new scope instance
function M.new(weaponTypeID, options)
	local instance = setmetatable({}, Scope)

	instance.weaponTypeID = weaponTypeID or ""
	instance.sceneCaptureComponent = nil
	instance.scopeMeshComponent = nil
	instance.scopeDebugComponent = nil
	instance.currentActiveState = true
	instance.isDisabled = true

	-- Auto-create the scope components
	instance:create(options)

	-- Register this scope instance
    if instance.weaponTypeID ~= "" then
        if activeScopeInstances[instance.weaponTypeID] == nil then
            activeScopeInstances[instance.weaponTypeID] = {}
        end
        table.insert(activeScopeInstances[instance.weaponTypeID], instance)
    end
	activeScopeCount = M.getScopeCount()

	return instance
end


-- local function saveSettings()
-- 	json.dump_file("uevrlib_scope_settings.json", settings)
-- 	M.print("Scope settings saved")
-- end

-- local timeSinceLastSave = 0
-- local isDirty = false
-- local function checkUpdates(delta)
-- 	timeSinceLastSave = timeSinceLastSave + delta
-- 	--prevent spamming save
-- 	if isDirty == true and timeSinceLastSave > 1.0 then
-- 		saveSettings()
-- 		isDirty = false
-- 		timeSinceLastSave = 0
-- 	end
-- end

-- function loadSettings()
-- 	settings = json.load_file("uevrlib_scope_settings.json")
-- 	if settings == nil then settings = {} end
-- end

M.AdjustMode =
{
    ZOOM = 0,
    BRIGHTNESS = 1,
}

local ETextureRenderTargetFormat = {
    RTF_R8 = 0,
    RTF_RG8 = 1,
    RTF_RGBA8 = 2,
    RTF_RGBA8_SRGB = 3,
    RTF_R16f = 4,
    RTF_RG16f = 5,
    RTF_RGBA16f = 6,
    RTF_R32f = 7,
    RTF_RG32f = 8,
    RTF_RGBA32f = 9,
    RTF_RGB10A2 = 10,
    RTF_MAX = 11,
}

function M.getConfigWidgets(prefix)
    prefix = prefix or ""
    return {
        {
            widgetType = "checkbox",
            id = prefix .. "scope_show_debug",
            label = "Show Objective Lens Debug Mesh",
            initialValue = false
        },
        {
            widgetType = "slider_float",
            id = prefix .. "scope_min_fov",
            label = "Max Zoom FOV",
            range = {0.01, 30},
            initialValue = parameterDefaults.min_fov
        },
        {
            widgetType = "slider_float",
            id = prefix .. "scope_max_fov",
            label = "Min Zoom FOV",
            range = {0.01, 30},
            initialValue = parameterDefaults.max_fov
        },
        {
            widgetType = "slider_float",
            id = prefix .. "scope_brightness",
            label = "Brightness",
            range = {0, 10},
            initialValue = parameterDefaults.brightness
        },
        {
            widgetType = "slider_float",
            id = prefix .. "scope_ocular_lens_scale",
            label = "Scale",
            range = {0.1, 10},
            initialValue = parameterDefaults.ocular_lens_scale
        },
        {
            widgetType = "drag_float3",
            id = prefix .. "scope_objective_lens_rotation",
            label = "Objective Lens Rotation",
            speed = 0.1,
            range = {-90, 90},
            initialValue = parameterDefaults.objective_lens_rotation
        },
        {
            widgetType = "drag_float3",
            id = prefix .. "scope_objective_lens_location",
            label = "Objective Lens Location",
            speed = 0.05,
            range = {-100, 100},
            initialValue = parameterDefaults.objective_lens_location
        },
        {
            widgetType = "drag_float3",
            id = prefix .. "scope_ocular_lens_rotation",
            label = "Ocular Lens Rotation",
            speed = 0.1,
            range = {-90, 90},
            initialValue = parameterDefaults.ocular_lens_rotation
        },
        {
            widgetType = "drag_float3",
            id = prefix .. "scope_ocular_lens_location",
            label = "Ocular Lens Location",
            speed = 0.05,
            range = {-100, 100},
            initialValue = parameterDefaults.ocular_lens_location
        },
        -- {
        --     widgetType = "checkbox",
        --     id = prefix .. "scope_disable",
        --     label = "Disable",
        --     initialValue = false
        -- },
        {
            widgetType = "slider_float",
            id = prefix .. "scope_zoom_speed",
            label = "Zoom Speed",
            range = {0, 2},
            initialValue = parameterDefaults.zoom_speed
        },
        {
            widgetType = "slider_float",
            id = prefix .. "scope_zoom_exponential",
            label = "Zoom Exponential",
            range = {0, 1},
            initialValue = parameterDefaults.zoom_exponential
        },
        {
            widgetType = "slider_float",
            id = prefix .. "scope_deactivate_distance",
            label = "Deactivate distance",
            range = {0, 100},
            initialValue = parameterDefaults.deactivate_distance
        },
        {
            widgetType = "checkbox",
            id = prefix .. "scope_hide_ocular_lens_on_disable",
            label = "Hide Ocular Lens on Disable",
            initialValue = parameterDefaults.hide_ocular_lens_on_disable
        },
    }
end

function M.createConfigCallbacks(id, prefix)
	configui.onUpdate(prefix .. "scope_min_fov", function(value)
		saveParameter(id, "min_fov", value, true)
		-- Note: After multi-scope refactor, setZoom needs to be called on specific scope instance
	end)

	configui.onUpdate(prefix .. "scope_max_fov", function(value)
		saveParameter(id, "max_fov", value, true)
		-- Note: After multi-scope refactor, setZoom needs to be called on specific scope instance
	end)

	configui.onUpdate(prefix .. "scope_zoom_speed", function(value)
		saveParameter(id, "zoom_speed", value, true)
	end)

	configui.onUpdate(prefix .. "scope_zoom_exponential", function(value)
		saveParameter(id, "zoom_exponential", value, true)
	end)

	configui.onUpdate(prefix .. "scope_ocular_lens_scale", function(value)
		saveParameter(id, "ocular_lens_scale", value, true)
		if activeScopeInstances[id] ~= nil then
			for _, scope in ipairs(activeScopeInstances[id]) do
				scope:setOcularLensScale(value)
			end
		end
	end)

	configui.onUpdate(prefix .. "scope_brightness", function(value)
		saveParameter(id, "brightness", value, true)
		if activeScopeInstances[id] ~= nil then
			for _, scope in ipairs(activeScopeInstances[id]) do
				scope:setBrightness(value)
			end
		end
	end)

	configui.onUpdate(prefix .. "scope_objective_lens_rotation", function(value)
		saveParameter(id, "objective_lens_rotation", {value.Pitch, value.Yaw, value.Roll}, true)
        if activeScopeInstances[id] ~= nil then
            for _, scope in ipairs(activeScopeInstances[id]) do
                scope:setObjectiveLensRelativeRotation(value)
            end
        end
	end)

	configui.onUpdate(prefix .. "scope_objective_lens_location", function(value)
		saveParameter(id, "objective_lens_location", {value.X, value.Y, value.Z}, true)
        if activeScopeInstances[id] ~= nil then
            for _, scope in ipairs(activeScopeInstances[id]) do
                scope:setObjectiveLensRelativeLocation(value)
            end
        end
	end)

	configui.onUpdate(prefix .. "scope_ocular_lens_rotation", function(value)
		saveParameter(id, "ocular_lens_rotation", {value.Pitch, value.Yaw, value.Roll}, true)
        if activeScopeInstances[id] ~= nil then
            for _, scope in ipairs(activeScopeInstances[id]) do
                scope:setOcularLensRelativeRotation(value)
            end
        end
	end)

	configui.onUpdate(prefix .. "scope_ocular_lens_location", function(value)
		saveParameter(id, "ocular_lens_location", {value.X, value.Y, value.Z}, true)
        if activeScopeInstances[id] ~= nil then
            for _, scope in ipairs(activeScopeInstances[id]) do
                scope:setOcularLensRelativeLocation(value)
            end
        end
	end)

	configui.onUpdate(prefix .. "scope_disable", function(value)
		saveParameter(id, "disable", value, true)
		M.print("Scope disable set to " .. tostring(value))
        if activeScopeInstances[id] ~= nil then
            for _, scope in ipairs(activeScopeInstances[id]) do
                scope:disable(value)
            end
        end
	end)

	configui.onUpdate(prefix .. "scope_deactivate_distance", function(value)
		saveParameter(id, "deactivate_distance", value, true)
	end)

	configui.onUpdate(prefix .. "scope_hide_ocular_lens_on_disable", function(value)
		saveParameter(id, "hide_ocular_lens_on_disable", value, true)
	end)

	configui.onUpdate(prefix .. "scope_show_debug", function(value)
		saveParameter(id, "show_debug", value, true)
		-- Note: After multi-scope refactor, showDebugMeshes needs to be called on specific scope instance
		if activeScopeInstances[id] ~= nil then
			for _, scope in ipairs(activeScopeInstances[id]) do
				scope:showDebugMeshes(value)
			end
		end
	end)
end

-- local configDefinition = {
-- 	{
-- 		panelLabel = "Scope Config", 
-- 		saveFile = "uevrlib_config_scope",
-- 		isHidden=false,
-- 		layout = 
-- 		{		
-- 			{
-- 				widgetType = "checkbox",
-- 				id = "uevr_lib_scope_create_demo",
-- 				label = "Create left hand demo",
-- 				initialValue = false
-- 			},
-- 			{
-- 				widgetType = "checkbox",
-- 				id = "uevr_lib_scope_show_debug",
-- 				label = "Show debug meshes",
-- 				initialValue = false
-- 			},
-- 			{
-- 				widgetType = "slider_float",
-- 				id = "uevr_lib_scope_fov",
-- 				label = "FOV",
-- 				range = {0.01, 30},
-- 				initialValue = 2
-- 			},
-- 			{
-- 				widgetType = "slider_float",
-- 				id = "uevr_lib_scope_brightness",
-- 				label = "Brightness",
-- 				range = {0, 10},
-- 				initialValue = 2
-- 			},
-- 			{
-- 				widgetType = "slider_float",
-- 				id = "uevr_lib_scope_ocular_lens_scale",
-- 				label = "Scale",
-- 				range = {0.1, 10},
-- 				initialValue = 1
-- 			},
-- 			{
-- 				widgetType = "drag_float3",
-- 				id = "uevr_lib_scope_objective_lens_rotation",
-- 				label = "Objective Lens Rotation",
-- 				speed = 0.5,
-- 				range = {-90, 90},
-- 				initialValue = {0.0, 0.0, 0.0}
-- 			},
-- 			{
-- 				widgetType = "drag_float3",
-- 				id = "uevr_lib_scope_objective_lens_location",
-- 				label = "Objective Lens Location",
-- 				speed = 0.5,
-- 				range = {-100, 100},
-- 				initialValue = {0.0, 0.0, 0.0}
-- 			},
-- 			{
-- 				widgetType = "drag_float3",
-- 				id = "uevr_lib_scope_ocular_lens_rotation",
-- 				label = "Ocular Lens Rotation",
-- 				speed = 0.5,
-- 				range = {-90, 90},
-- 				initialValue = {0.0, 0.0, 0.0}
-- 			},
-- 			{
-- 				widgetType = "drag_float3",
-- 				id = "uevr_lib_scope_ocular_lens_location",
-- 				label = "Ocular Lens Location",
-- 				speed = 0.05,
-- 				range = {-100, 100},
-- 				initialValue = {0.0, 0.0, 0.0}
-- 			},
-- 			{
-- 				widgetType = "checkbox",
-- 				id = "uevr_lib_scope_disable",
-- 				label = "Disable",
-- 				initialValue = false
-- 			},
-- 			{
-- 				widgetType = "slider_float",
-- 				id = "uevr_lib_scope_deactivate_distance",
-- 				label = "Deactivate distance",
-- 				range = {0, 100},
-- 				initialValue = 15
-- 			},
-- 			{
-- 				widgetType = "slider_float",
-- 				id = "uevr_lib_scope_zoom_speed",
-- 				label = "Zoom Speed",
-- 				range = {0, 2},
-- 				initialValue = zoomSpeed
-- 			},
-- 			{
-- 				widgetType = "slider_float",
-- 				id = "uevr_lib_scope_zoom_exponential",
-- 				label = "Zoom Exponential",
-- 				range = {0, 1},
-- 				initialValue = zoomExponential
-- 			},
-- 		}	
-- 	}
-- }

--configui.create(configDefinition)
-- configui.setValue("uevr_lib_scope_create_demo", false)
-- configui.setValue("uevr_lib_scope_disable", false)

-- configui.onUpdate("uevr_lib_scope_fov", function(value)
-- 	M.setFOV(value)
-- end)

-- configui.onUpdate("uevr_lib_scope_zoom_speed", function(value)
-- 	zoomSpeed = value
-- end)

-- configui.onUpdate("uevr_lib_scope_zoom_exponential", function(value)
-- 	zoomExponential = value
-- end)

-- configui.onUpdate("uevr_lib_scope_ocular_lens_scale", function(value)
-- 	M.setOcularLensScale(value)
-- end)

-- configui.onUpdate("uevr_lib_scope_brightness", function(value)
-- 	M.setBrightness(value)
-- end)

-- configui.onUpdate("uevr_lib_scope_objective_lens_rotation", function(value)
-- 	M.setObjectiveLensRelativeRotation(value)
-- end)

-- configui.onUpdate("uevr_lib_scope_objective_lens_location", function(value)
-- 	M.setObjectiveLensRelativeLocation(value)
-- end)

-- configui.onUpdate("uevr_lib_scope_ocular_lens_rotation", function(value)
-- 	M.setOcularLensRelativeRotation(value)
-- end)

-- configui.onUpdate("uevr_lib_scope_ocular_lens_location", function(value)
-- 	M.setOcularLensRelativeLocation(value)
-- end)

-- configui.onUpdate("uevr_lib_scope_disable", function(value)
-- 	M.disable(value)
-- end)

-- configui.onUpdate("uevr_lib_scope_deactivate_distance", function(value)
-- 	M.setDeactivateDistance(value)
-- end)

-- configui.onUpdate("uevr_lib_scope_show_debug", function(value)
-- 	M.destroy()
-- 	if configui.getValue("uevr_lib_scope_create_demo") == true then
-- 		M.create()
-- 		M.attachToLeftHand()
-- 	end
-- end)

-- configui.onUpdate("uevr_lib_scope_create_demo", function(value)
-- 	M.destroy()
-- 	if value == true then
-- 		M.create()
-- 		M.attachToLeftHand()
-- 	end
-- end)
local function executeActiveScope(...)
	uevrUtils.executeUEVRCallbacks("scope_active_change", table.unpack({...}))
end

function M.getScopeCount()
    local count = 0
    for weaponTypeID, scopes in pairs(activeScopeInstances) do
        count = count + #scopes
    end
    return count
end


function Scope:setFOV(value)
	if uevrUtils.getValid(self.sceneCaptureComponent) ~= nil then
		self.sceneCaptureComponent.FOVAngle = value
	end
end

-- min_fov and max_fov may be confusing. min_fov is the narrowest field of view (highest zoom), max_fov is the widest field of view (lowest zoom)
function Scope:setZoom(zoom)
	local ratio = zoom / maxZoom
	local exponentialRatio = ratio ^ getParameter(self.weaponTypeID, "zoom_exponential")
	local currentFOV = getParameter(self.weaponTypeID, "max_fov") + exponentialRatio * (getParameter(self.weaponTypeID, "min_fov") - getParameter(self.weaponTypeID, "max_fov"))

	self:setFOV(currentFOV)
	if self.weaponTypeID ~= nil and self.weaponTypeID ~= "" then
		saveParameter(self.weaponTypeID, "zoom", zoom, true)
	end
end

function Scope:updateZoom(zoomDirection, delta)
	if zoomDirection ~= 0 then
		local currentZoom = getParameter(self.weaponTypeID, "zoom")
		currentZoom = currentZoom + (1 * getParameter(self.weaponTypeID, "zoom_speed") * zoomDirection * delta)
		currentZoom = math.max(minZoom, math.min(maxZoom, currentZoom))

		self:setZoom(currentZoom)
		if self.weaponTypeID ~= nil and self.weaponTypeID ~= "" then
			saveParameter(self.weaponTypeID, "zoom", currentZoom, true)
		end
	end
end

function Scope:updateBrightness(brightnessDirection, delta)
	if brightnessDirection ~= 0 then
		local currentBrightness = getParameter(self.weaponTypeID, "brightness")
		currentBrightness = currentBrightness + (1 * brightnessSpeed * brightnessDirection * delta)
		currentBrightness = math.max(minBrightness, math.min(maxBrightness, currentBrightness))

		self:setBrightness(currentBrightness)
		if self.weaponTypeID ~= nil and self.weaponTypeID ~= "" then
			saveParameter(self.weaponTypeID, "brightness", currentBrightness, true)
		end
	end
end


-- -- zoomType - 0 in, 1 out
-- -- zoomSpeed - 1.0 is default
-- function M.zoom(zoomType, zoomSpeed)
	-- if zoomType == nil then zoomType = 0 end
	-- if zoomSpeed == nil then zoomSpeed = 1.0 end

	-- ratio = currentZoom / MaxZoom
	-- exponentialRatio = ratio ^ exponent_value -- where exponent_value is typically less than 1 for gradual increase, >1 for steeper curve {Link: according to GitHub https://rikunert.github.io/exponential_scaler}
	-- currentFOV = minFOV + exponentialRatio * (MaxFOV - minFOV)
-- end


-- function M.zoomIn(zoomSpeed)
	-- M.zoom(0, zoomSpeed)
-- end

-- function M.zoomOut(zoomSpeed)
	-- M.zoom(1, zoomSpeed)
-- end

function Scope:getOcularLensComponent()
	return self.scopeMeshComponent
end

function Scope:getObjectiveLensComponent()
	return self.sceneCaptureComponent
end

function Scope:destroy()
	if self.sceneCaptureComponent ~= nil then
		uevrUtils.detachAndDestroyComponent(self.sceneCaptureComponent, true, true)
	end
	if self.scopeMeshComponent ~= nil then
		uevrUtils.detachAndDestroyComponent(self.scopeMeshComponent, true, true)
	end
	if self.scopeDebugComponent ~= nil then
		uevrUtils.detachAndDestroyComponent(self.scopeDebugComponent, true, true)
	end

	    -- Unregister this scope instance
    if self.weaponTypeID ~= "" and activeScopeInstances[self.weaponTypeID] ~= nil then
        for i, scope in ipairs(activeScopeInstances[self.weaponTypeID]) do
            if scope == self then
                table.remove(activeScopeInstances[self.weaponTypeID], i)
                -- Clean up empty table
                if #activeScopeInstances[self.weaponTypeID] == 0 then
                    activeScopeInstances[self.weaponTypeID] = nil
                end
                break
            end
        end
    end
	activeScopeCount = M.getScopeCount()

	self:reset()
	executeActiveScope(false)
end

function Scope:reset()
	self.sceneCaptureComponent = nil
	self.scopeMeshComponent = nil
	self.scopeDebugComponent = nil
	self.currentActiveState = true
	self.isDisabled = true
end

function Scope:disable(value)
	self.isDisabled = true
	if uevrUtils.getValid(self.sceneCaptureComponent) ~= nil and self.sceneCaptureComponent.SetVisibility ~= nil then
		self.sceneCaptureComponent:SetVisibility(not value, false)
		self.isDisabled = value
	end
	if uevrUtils.getValid(self.scopeMeshComponent) ~= nil and self.scopeMeshComponent.SetVisibility ~= nil then
		local val = value
		if getParameter(self.weaponTypeID, "hide_ocular_lens_on_disable") == false then
			val = false
		end
		self.scopeMeshComponent:SetVisibility(not val)
	end
	if uevrUtils.getValid(self.scopeDebugComponent) ~= nil and self.scopeDebugComponent.SetVisibility ~= nil then
		local val = value
		if getParameter(self.weaponTypeID, "show_debug") == false then
			val = true
		end
		--self.scopeDebugComponent:SetVisibility(not val)
		if val == true then
			self:destroyOcularLensDebugMesh()
		else
			self:createOcularLensDebugMesh()
		end

	end
	executeActiveScope(not value)
end

function Scope:setOcularLensScale(value)
	if uevrUtils.getValid(self.scopeMeshComponent) ~= nil and value ~= nil then
		uevrUtils.set_component_relative_scale(self.scopeMeshComponent, {value*0.05,value*0.05,value*0.001})
	end
end

function Scope:setObjectiveLensRelativeRotation(value)
	value = uevrUtils.vector(value)
	if uevrUtils.getValid(self.sceneCaptureComponent) ~= nil and value ~= nil then
		uevrUtils.set_component_relative_rotation(self.sceneCaptureComponent, {value.X - 90 + defaultPitchOffset,value.Y,value.Z})
	end
end

function Scope:setObjectiveLensRelativeLocation(value)
	value = uevrUtils.vector(value)
	if uevrUtils.getValid(self.sceneCaptureComponent) ~= nil and value ~= nil then
		uevrUtils.set_component_relative_location(self.sceneCaptureComponent, {value.X,value.Y,value.Z})
	end
end

function Scope:setOcularLensRelativeRotation(value)
	value = uevrUtils.vector(value)
	if uevrUtils.getValid(self.scopeMeshComponent) ~= nil and value ~= nil then
		uevrUtils.set_component_relative_rotation(self.scopeMeshComponent, {value.X + defaultPitchOffset,value.Y,value.Z})
	end
end

local function activeStateChanged(isActive)
	-- Called when active state changes
end

function Scope:updateActiveState()
	local isActive = true
	if uevrUtils.getValid(self.scopeMeshComponent) == nil or uevrUtils.getValid(self.sceneCaptureComponent) == nil or self.scopeMeshComponent.K2_GetComponentLocation == nil then
		isActive = false
	else
		local deactivateDistance = getParameter(self.weaponTypeID, "deactivate_distance")
		local headLocation = controllers.getControllerLocation(2)
		local ocularLensLocation = self.scopeMeshComponent:K2_GetComponentLocation()
		if headLocation ~= nil and ocularLensLocation ~= nil then
			local distance = kismet_math_library:Vector_Distance(headLocation, ocularLensLocation)
			isActive = distance < deactivateDistance
		end
	end
	if isActive ~= self.currentActiveState then
		self:disable(not isActive)
		activeStateChanged(isActive)
	end
	self.currentActiveState = isActive
end

function Scope:isDisplaying()
	return not self.isDisabled
end

function Scope:setOcularLensRelativeLocation(value)
	value = uevrUtils.vector(value)
	if uevrUtils.getValid(self.scopeMeshComponent) ~= nil and value ~= nil then
		uevrUtils.set_component_relative_location(self.scopeMeshComponent, {value.X,value.Y,value.Z})
	end
end

function Scope:setBrightness(value)
	local scopeMaterial = self.scopeMeshComponent:GetMaterial(0)
	if scopeMaterial ~= nil then
		local color = uevrUtils.color_from_rgba(value, value, value, value)
		scopeMaterial:SetVectorParameterValue("Color", color)
	end
end

EAttachmentRule = {
    KeepRelative = 0,
    KeepWorld = 1,
    SnapToTarget = 2,
    EAttachmentRule_MAX = 3,
}

function Scope:createOcularLens(renderTarget2D, options)
	if options == nil then options = {} end
	--TODO getting a value from configui seems wrong
	if options.scale == nil then options.scale = configui.getValue("uevr_lib_scope_ocular_lens_scale") end
	if options.brightness == nil then options.brightness = getParameter(self.weaponTypeID, "brightness") end

	uevrUtils.getLoadedAsset("StaticMesh /Engine/BasicShapes/Cylinder.Cylinder")
	self.scopeMeshComponent = uevrUtils.createStaticMeshComponent("StaticMesh /Engine/BasicShapes/Cylinder.Cylinder", {visible=false, collisionEnabled=false} )
	if uevrUtils.getValid(self.scopeMeshComponent) ~= nil then
		self:setOcularLensScale(options.scale)

		local templateMaterial = uevrUtils.find_required_object("Material /Engine/EngineMaterials/EmissiveMeshMaterial.EmissiveMeshMaterial")
		if templateMaterial ~= nil then
			templateMaterial:set_property("BlendMode", 0)
			templateMaterial:set_property("TwoSided", false)

---@diagnostic disable-next-line: need-check-nil
			local scopeMaterial = self.scopeMeshComponent:CreateDynamicMaterialInstance(0, templateMaterial, "scope_material")
			scopeMaterial:SetTextureParameterValue("LinearColor", renderTarget2D)
			self:setBrightness(options.brightness)
		end
		M.print("scopeMeshComponent created")
	else
		M.print("Could not create scopeMeshComponent")
	end
end

function Scope:createOcularLensDebugMesh()
	if self.scopeDebugComponent == nil and uevrUtils.getValid(self.sceneCaptureComponent) ~= nil then
		self.scopeDebugComponent = uevrUtils.createStaticMeshComponent("StaticMesh /Engine/BasicShapes/Cylinder.Cylinder", {visible=true, collisionEnabled=false})
		if self.scopeDebugComponent ~= nil then
			self.scopeDebugComponent:K2_AttachTo(self.sceneCaptureComponent, uevrUtils.fname_from_string(""), EAttachmentRule.KeepRelative, false)
			uevrUtils.set_component_relative_transform(self.scopeDebugComponent, {0.5,0,0}, {Pitch=90, Yaw=0, Roll=0}, {0.01 ,0.01, 0.01})
			--self.scopeDebugComponent:SetVisibility(getParameter(self.weaponTypeID, "show_debug"))
		end
	end
end

function Scope:destroyOcularLensDebugMesh()
	if self.scopeDebugComponent ~= nil then
		uevrUtils.detachAndDestroyComponent(self.scopeDebugComponent, true, true)
		self.scopeDebugComponent = nil
	end
end

function Scope:createObjectiveLens(renderTarget2D, options)
	if options == nil then options = {} end
	if options.fov == nil then options.fov = getParameter(self.weaponTypeID, "fov") end

	self.sceneCaptureComponent = uevrUtils.createSceneCaptureComponent({visible=false, collisionEnabled=false})
	if uevrUtils.getValid(self.sceneCaptureComponent) ~= nil then
		self.sceneCaptureComponent.TextureTarget = renderTarget2D
		self:updateZoom(1, 0)
		self:setObjectiveLensRelativeRotation(getParameter(self.weaponTypeID, "objective_lens_rotation"))

		if getParameter(self.weaponTypeID, "show_debug") == true then
			self:createOcularLensDebugMesh()
		end
		-- self.scopeDebugComponent = uevrUtils.createStaticMeshComponent("StaticMesh /Engine/BasicShapes/Cylinder.Cylinder", {visible=true, collisionEnabled=false})
		-- if self.scopeDebugComponent ~= nil then
		-- 	self.scopeDebugComponent:K2_AttachTo(self.sceneCaptureComponent, uevrUtils.fname_from_string(""), EAttachmentRule.KeepRelative, false)
		-- 	uevrUtils.set_component_relative_transform(self.scopeDebugComponent, {0.5,0,0}, {Pitch=90, Yaw=0, Roll=0}, {0.01 ,0.01, 0.01})
		-- 	self.scopeDebugComponent:SetVisibility(getParameter(self.weaponTypeID, "show_debug"))
		-- end

		M.print("sceneCaptureComponent created")
	else
		M.print("sceneCaptureComponent not created")
	end
end

function Scope:showDebugMeshes(value)
	if value == false then
		self:destroyOcularLensDebugMesh()
	else
		self:createOcularLensDebugMesh()
	end
	-- if uevrUtils.getValid(self.scopeDebugComponent) ~= nil then
	-- 	self.scopeDebugComponent:SetVisibility(value)
	-- end
end

function Scope:attachTo(attachment)
	M.print("Found scope settings. Creating scope")
	local ocularLensComponent, objectiveLensComponent = self:getOcularLensComponent(), self:getObjectiveLensComponent()
	if objectiveLensComponent ~= nil then
		objectiveLensComponent:K2_AttachToComponent(
				attachment,
				"",
				0, -- Location rule
				0, -- Rotation rule
				0, -- Scale rule
				false -- Weld simulated bodies
			)
	else
		M.print("Objective lens component creation failed")
	end
	if ocularLensComponent ~= nil then
		ocularLensComponent:K2_AttachToComponent(
				attachment,
				"",
				0, -- Location rule
				0, -- Rotation rule
				0, -- Scale rule
				false -- Weld simulated bodies
			)
	else
		M.print("Ocular lens component creation failed")
	end
	self:setObjectiveLensRelativeRotation(getParameter(self.weaponTypeID, "objective_lens_rotation"))
	self:setObjectiveLensRelativeLocation(getParameter(self.weaponTypeID, "objective_lens_location"))
	self:setOcularLensRelativeRotation(getParameter(self.weaponTypeID, "ocular_lens_rotation"))
	self:setOcularLensRelativeLocation(getParameter(self.weaponTypeID, "ocular_lens_location"))
	self:setOcularLensScale(getParameter(self.weaponTypeID, "ocular_lens_scale"))

	M.print("Scope created")
end

-- options example { disabled=true, fov=2.0, brightness=2.0, scale=1.0, deactivateDistance=15, hideOcularLensOnDisable=true}
function Scope:create(options)
	self:destroy()

	if options == nil then options = {} end
	if options.brightness == nil then options.brightness = 1.0 end

	if options.deactivateDistance then
		saveParameter(self.weaponTypeID, "deactivate_distance", options.deactivateDistance, false)
	end
	if options.hideOcularLensOnDisable then
		saveParameter(self.weaponTypeID, "hide_ocular_lens_on_disable", options.hideOcularLensOnDisable, false)
	end

	local renderTarget2D = uevrUtils.createRenderTarget2D({width=1024, height=1024, format=ETextureRenderTargetFormat.RTF_RGBA16f})
	self:createOcularLens(renderTarget2D, options)
	self:createObjectiveLens(renderTarget2D, options)

	local disabled = options ~= nil and (options.disabled == true) or getParameter(self.weaponTypeID, "disable") == true
	self:disable(disabled)

	return self:getOcularLensComponent(), self:getObjectiveLensComponent()
end

function Scope:attachToLeftHand()
	local headConnected = controllers.attachComponentToController(Handed.Left, self:getObjectiveLensComponent(), nil, nil, nil, true)
	local leftConnected = controllers.attachComponentToController(Handed.Left, self:getOcularLensComponent(), nil, nil, nil, true)
end

-- Input state tracking for multi-scope support
local autoHandleInput = true
local scopeAdjustDirection = 0
local scopeAdjustMode = M.AdjustMode.ZOOM
local leftControls = false

function M.setAutoHandleInput(value)
	autoHandleInput = value
end

-- Find the scope closest to the HMD/head position
local function findClosestScopeToHead()
	if activeScopeCount == 0 then return nil end

    local headLocation = controllers.getControllerLocation(2)
    if headLocation == nil then return nil end

    local closestScope = nil
    local closestDistance = math.huge

    for weaponTypeID, scopes in pairs(activeScopeInstances) do
        for _, scope in ipairs(scopes) do
            if scope ~= nil and scope:isDisplaying() then
                local ocularLens = scope:getOcularLensComponent()
                if uevrUtils.getValid(ocularLens) ~= nil and ocularLens.K2_GetComponentLocation ~= nil then
                    local scopeLocation = ocularLens:K2_GetComponentLocation()
                    if scopeLocation ~= nil then
                        local distance = kismet_math_library:Vector_Distance(headLocation, scopeLocation)
                        if distance < closestDistance then
                            closestDistance = distance
                            closestScope = scope
                        end
                    end
                end
            end
        end
    end

    return closestScope
end

-- Update multiple scopes - call from attachments or main loop
-- Handles input routing to closest scope
function M.updateScopes(delta)
    if autoHandleInput and activeScopeCount > 0 then
        -- Update active state for all scopes
        for weaponTypeID, scopes in pairs(activeScopeInstances) do
            for _, scope in ipairs(scopes) do
                if scope ~= nil then
                    scope:updateActiveState()
                end
            end
        end

        -- Find closest scope for input routing
        local closestScope = findClosestScopeToHead()

        -- Handle input for the closest scope
        if closestScope ~= nil then
            if scopeAdjustMode == M.AdjustMode.BRIGHTNESS then
                closestScope:updateBrightness(scopeAdjustDirection, delta)
            elseif scopeAdjustMode == M.AdjustMode.ZOOM then
                closestScope:updateZoom(scopeAdjustDirection, delta)
            end
        end
    end
end

function M.setDefaultPitchOffset(value)
	defaultPitchOffset = value
end

-- -- Deprecated singleton-style functions kept for backward compatibility
-- -- These will operate on the "current" scope if set
-- local currentScopeID = ""
-- function M.setActive(id)
-- 	currentScopeID = id
-- end

-- function M.isActive()
-- 	return currentScopeID ~= nil and currentScopeID ~= ""
-- end

-- -- Legacy singleton destroy function
-- function M.destroy()
-- 	-- This is kept for backward compatibility
-- 	-- New code should call scope:destroy() on the instance
-- 	M.print("M.destroy() called - consider using scope:destroy() on instance instead")
-- end

-- function M.reset()
-- 	currentScopeID = ""
-- end

-- uevrUtils.registerLevelChangeCallback(function(level)
-- 	M.reset()
-- end)

function M.init(isDeveloperMode, logLevel)
    paramManager:load()
end

-- uevrUtils.registerUEVRCallback("attachment_grip_changed", function(id, gripHand)
-- 	M.setActive("")
-- end)

-- uevr.params.sdk.callbacks.on_script_reset(function()
-- 	-- Note: Individual scopes should be destroyed by their owners
-- 	-- This is mainly for cleanup of any legacy singleton state
-- 	M.reset()
-- end)

uevrUtils.registerOnPreInputGetStateCallback(function(retval, user_index, state)
	if autoHandleInput == false or activeScopeCount == 0 then
		return
	end

	scopeAdjustDirection = 0
	local thumbY = state.Gamepad.sThumbRY
	if leftControls then
		thumbY = state.Gamepad.sThumbLY
	end

	if thumbY >= 10000 or thumbY <= -10000 then
		scopeAdjustDirection = thumbY/32768
	end

	-- prevent annoying accidental snap turn when making adjustments
	if scopeAdjustDirection ~= 0 then
		state.Gamepad.sThumbRX = 0
	end

	scopeAdjustMode = M.AdjustMode.ZOOM
	local dpadMethod = uevr.params.vr:get_mod_value("VR_DPadShiftingMethod")
	if uevrUtils.isThumbpadTouched(state, string.find(dpadMethod,"1") and Handed.Right or Handed.Left) then
		scopeAdjustMode = M.AdjustMode.BRIGHTNESS
	end
end, 11)

function on_post_engine_tick(engine, delta)
	M.updateScopes(delta)
end

return M