local uevrUtils = require("libs/uevr_utils")
local configui = require("libs/configui")

local M = {}
M.__index = M

-- Constructor: Creates a new M instance
function M.new(fileName, defaultParams, autoSave)
    local self = setmetatable({}, M)
    self.fileName = fileName or "parameters"
    self.defaultParameters = uevrUtils.deepCopyTable(defaultParams or {})
    self.parameters = defaultParams or {}
    self.isDirty = false
    self.autoSaveInterval = nil
    self.widgetPrefix = ""
    self.profileIDs = {}
    self.profileChangeCallbackList = {}
    if autoSave then
        self:autoSaveInit()
    end
    return self
end

-- Saves parameters to JSON file
function M:save()
    uevrUtils.print("[parameters] Saving parameters to " .. self.fileName .. ".json")
    if self.fileName ~= nil and self.fileName ~= "" then
        json.dump_file(self.fileName .. ".json", self.parameters, 4)
    else
        uevrUtils.print("[parameters] File name not set, cannot save parameters", LogLevel.Warning)
    end
end

-- Loads parameters from JSON file
function M:load(useProfileFormat)
    uevrUtils.print("[parameters] Loading parameters from " .. self.fileName .. ".json")
    local params = json.load_file(self.fileName .. ".json")
    if params ~= nil then
        self.parameters = params
    end
    if useProfileFormat then
        self:convertToProfile()
    end
end

-- Sets a parameter value and marks as dirty for autosave
function M:set(key, value, persist)
    if type(key) == "table" then
        local field = self.parameters
        for i = 1, #key-1 do
            local k = key[i]
            if type(field[k]) ~= "table" then
                field[k] = {}   -- auto-create missing table
            end
            field = field[k]
        end
        field[key[#key]] = value
    else
        self.parameters[key] = value
    end
    self.isDirty = persist == nil and false or persist
end

-- Gets a parameter value by key
function M:get(key)
    if type(key) == "table" then
        local field = self.parameters
        for i = 1, #key do
            field = field[key[i]]
            if field == nil then return nil end
        end
        return field
    else
        return self.parameters[key]
    end
end

--allows converting existing flat parameters to profile-based
--profiles of parameters is a common pattern, so this allows migrating existing flat parameters
--while abstracting the details of profiles for the individual classes that use this params manager
function M:convertToProfile()
    local activeProfile = self:get({"_profileState", "currentEditingProfile"})
    if activeProfile == nil then -- if the profile doesnt exist, set to default
        local existingParams = uevrUtils.deepCopyTable(self.parameters)

        self:set({"_profileState", "currentEditingProfile"}, "default", true)
        activeProfile = "default"
        local activeLabel = self:get({"_profileLabels", activeProfile})
        if activeLabel == nil then
            self:set({"_profileLabels", activeProfile}, "Default", true)
        end

        for key, value in pairs(existingParams) do
            self:set({activeProfile, key}, value, false)
            self:set(key, nil, false)
        end
        self.isDirty = true
    end
end

function M:getActiveProfile()
    local activeProfile = self:get({"_profileState", "currentEditingProfile"})
    return activeProfile
end

function M:deleteProfile(profileID)
    if profileID == nil or profileID == "" then
        return
    end
    self:set(profileID, nil, true)
    self:set({"_profileLabels", profileID}, nil, true)
end

function M:setActiveProfile(profileId)
    if self:get(profileId) == nil then
        M:createProfile(profileId, profileId == "default" and "Default" or "New Profile")
    end
    self:set({"_profileState", "currentEditingProfile"}, profileId, true)

    for index, func in ipairs(self.profileChangeCallbackList) do
        func(self:getAllActiveProfileParams())
    end
    -- if self.profileChangeCallback then
    --     self.profileChangeCallback(self:getAllActiveProfileParams())
    -- end

    self:updateProfileUI(true)

end

function M:createProfile(profileId, profileLabel)
    if self:get(profileId) == nil then
        self:set(profileId, {}, true)
    end
	self:set({"_profileLabels", profileId}, profileLabel or "New Profile", true)
end

function M:getProfiles()
    local ids = {}
    local names = {}
    local currentIndex = 1
    local activeProfile = self:get({"_profileState", "currentEditingProfile"})
    for key, value in pairs(self.parameters) do
        if key ~= "_profileState" and key ~= "_profileLabels" then
            table.insert(ids, key)
            local label = self:get({"_profileLabels", key})
            table.insert(names, label or key)
            if key == activeProfile then
                currentIndex = #ids
            end
        end
    end
    return ids, names, currentIndex
end

function M:getAllActiveProfileParams()
    local activeProfile = self:getActiveProfile()
    return self:get(activeProfile) or {}
end

function M:getFromActiveProfile(key)
    return self:get({self:getActiveProfile(), key})
    -- if activeProfile == "default" and self:get(activeProfile) == nil then
    --     return self:get(key) -- Fallback to global if default profile not set
    -- else
    --     return self:get({activeProfile, key})
    -- end
    -- if type(key) == "table" then
    --     local fullKey = {activeProfile}
    --     for _, k in ipairs(key) do
    --         table.insert(fullKey, k)
    --     end
    --     return self:get(fullKey)
    -- else
    --     return self:get({activeProfile, key})
    -- end
end

function M:setInActiveProfile(key, value, persist)
    self:set({self:getActiveProfile(), key}, value, persist)
    -- if type(key) == "table" then
    --     local fullKey = {activeProfile}
    --     for _, k in ipairs(key) do
    --         table.insert(fullKey, k)
    --     end
    --     self:set(fullKey, value, persist)
    -- else
    --     self:set({activeProfile, key}, value, persist)
    -- end
end

function M.getProfilePreConfigurationWidgets(widgetPrefix)
    return spliceableInlineArray{
		{ widgetType = "indent", width = 10 },
		{ widgetType = "new_line" },
		{
			widgetType = "combo",
			id = widgetPrefix .. "active_profile",
			label = "Current Profile",
			selections = {"None"},
			initialValue = 1,
			width = 200
		},
		{ widgetType = "same_line" },
		{
			widgetType = "button",
			id = widgetPrefix .. "rename_profile",
			label = "Rename"
		},
		{
			widgetType = "begin_group",
			id = widgetPrefix .. "rename_profile_group",
			isHidden = true
		},
			{
				widgetType = "input_text",
				id = widgetPrefix .. "rename_profile_input",
				label = "",
				initialValue = "",
				width = 200
			},
			{ widgetType = "same_line" },
			{
				widgetType = "button",
				id = widgetPrefix .. "rename_profile_update",
				label = "Update"
			},
		{
			widgetType = "end_group"
		},
    }
end

function M.getProfilePostConfigurationWidgets(widgetPrefix)
    return spliceableInlineArray{
		{
			widgetType = "button",
			id = widgetPrefix .. "new_profile",
			label = "New Profile"
		},
		{ widgetType = "same_line" },
		{
			widgetType = "button",
			id = widgetPrefix .. "duplicate_profile",
			label = "Duplicate Profile"
		},
		{ widgetType = "same_line" },
		{
			widgetType = "button",
			id = widgetPrefix .. "delete_profile",
			label = "Delete Profile"
		},
		{ widgetType = "unindent", width = 10 },
    }
end

function M:registerProfileChangeCallback(profileChangeCallback)
    if type(profileChangeCallback) ~= "function" then
        print("[params] Invalid profile change callback registration")
        return
    end
    local exists = false
    for index, func in ipairs(self.profileChangeCallbackList) do
        if func == profileChangeCallback then
            exists = true
            break
        end
    end
    if not exists then
        table.insert(self.profileChangeCallbackList, profileChangeCallback)
    end
end

function M:setupProfileUpdateHandlers(widgetPrefix)

    configui.onUpdate(widgetPrefix .. "active_profile", function(value)
            self:setActiveProfile(self.profileIDs[value])
    end)

    configui.onUpdate(widgetPrefix .. "rename_profile", function()
        configui.setHidden(widgetPrefix .. "rename_profile_group", false)
        local currentProfileIndex = configui.getValue(widgetPrefix .. "active_profile")
        local currentProfileID = self.profileIDs[currentProfileIndex]
        local currentProfileLabel = self:get({"_profileLabels", currentProfileID}) or currentProfileID
        configui.setValue(widgetPrefix .. "rename_profile_input", currentProfileLabel)
    end)

    configui.onUpdate(widgetPrefix .. "rename_profile_update", function()
        local newLabel = configui.getValue(widgetPrefix .. "rename_profile_input")
        local currentProfileIndex = configui.getValue(widgetPrefix .. "active_profile")
        local currentProfileID = self.profileIDs[currentProfileIndex]
        self:set({"_profileLabels", currentProfileID}, newLabel, true)
        configui.setHidden(widgetPrefix .. "rename_profile_group", true)

        self:updateProfileUI()
    end)

    configui.onUpdate(widgetPrefix .. "new_profile", function()
        local newProfileID = uevrUtils.guid()
        self:createProfile(newProfileID, "New Profile")

        -- Copy all settings from default profile to new profile
        for key, value in pairs(self.defaultParameters) do
            --print("Copying default param:", key, value)
            self:set({newProfileID, key}, value, true)
        end
        self:setActiveProfile(newProfileID)
    end)

    configui.onUpdate(widgetPrefix .. "duplicate_profile", function()
        local activeProfileID = self:getActiveProfile()
        local newProfileID = uevrUtils.generateUUID()
        self:createProfile(newProfileID, "Duplicate Profile")

        -- Copy all settings from active profile to new profile
        for key, value in pairs(self.parameters[activeProfileID] or {}) do
            self:set({newProfileID, key}, value, true)
        end
    end)

    configui.onUpdate(widgetPrefix .. "delete_profile", function()
        self:deleteProfile(self:getActiveProfile())
        self:setActiveProfile("default")
    end)

end

function M:initProfileHandler(widgetPrefix, profileChangeCallback)
    self.widgetPrefix = widgetPrefix or ""
    self:registerProfileChangeCallback(profileChangeCallback)
	self:setupProfileUpdateHandlers(widgetPrefix)
	self:updateProfileUI()

    for index, func in ipairs(self.profileChangeCallbackList) do
        func(self:getAllActiveProfileParams())
    end
end

--local profileIDs = {}
function M:updateProfileUI(noCallbacks)
	local ids, names, current = self:getProfiles()
	self.profileIDs = ids
	configui.setSelections(self.widgetPrefix .. "active_profile", names)
	configui.setValue(self.widgetPrefix .. "active_profile", current, noCallbacks)
end

function M:getAll()
    return self.parameters
end

-- Initializes autosave with a timer
function M:autoSaveInit(interval)
    interval = interval or 1000  -- Default 1 second
    self.autoSaveInterval = uevrUtils.setInterval(interval, function()
        if self.isDirty then
            self:save()
            self.isDirty = false
        end
    end)
end

-- Stops autosave
function M:autoSaveStop()
    if self.autoSaveInterval then
        uevrUtils.clearInterval(self.autoSaveInterval)
        self.autoSaveInterval = nil
    end
end

return M