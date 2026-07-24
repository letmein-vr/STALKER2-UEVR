local uevrUtils = require('libs/uevr_utils')

local M = {}

local currentLogLevel = LogLevel.Error
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
    if logLevel == nil then logLevel = LogLevel.Debug end
    if logLevel <= currentLogLevel then
        uevrUtils.print("[widget] " .. text, logLevel)
    end
end

local function normalizeWidgetName(widgetName)
    if widgetName == nil then return nil end
    if type(widgetName) == "string" then return widgetName end
    if type(widgetName) == "table" and widgetName.to_string ~= nil then
        local ok, str = pcall(function() return widgetName:to_string() end)
        if ok then return str end
    end
    if type(widgetName) == "userdata" and widgetName.to_string ~= nil then
        local ok, str = pcall(function() return widgetName:to_string() end)
        if ok then return str end
    end
    return tostring(widgetName)
end

local function traverseWidgetDescendants(rootWidget, visitor)
    if uevrUtils.getValid(rootWidget) == nil then return end
    if visitor == nil then return end

    local visited = {}

    local function visit(widget, depth)
        if uevrUtils.getValid(widget) == nil then return end

        local key = tostring(widget)
        if visited[key] then return end
        visited[key] = true

        if visitor(widget, depth or 0) == false then return false end

        -- UPanelWidget
        if widget.GetChildrenCount ~= nil and widget.GetChildAt ~= nil then
            local count = widget:GetChildrenCount()
            if count ~= nil and count > 0 then
                for i = 0, count - 1 do
                    if visit(widget:GetChildAt(i), (depth or 0) + 1) == false then
                        return false
                    end
                end
            end
        end

        -- UContentWidget
        if widget.GetContent ~= nil then
            if visit(widget:GetContent(), (depth or 0) + 1) == false then
                return false
            end
        end
    end

    visit(rootWidget, 0)
end

local function getWidgetTypeName(widget)
    local w = uevrUtils.getValid(widget)
    if w == nil then return "<invalid>" end
    if w.get_class == nil then return "<no_class>" end

    local ok, class = pcall(function() return w:get_class() end)
    if not ok or class == nil then return "<unknown_class>" end

    -- Prefer concise names (e.g. "Button") but fall back to full name if needed.
    if class.get_name ~= nil then
        local okName, name = pcall(function() return class:get_name() end)
        if okName and name ~= nil and name ~= "" then return name end
    end

    local short = uevrUtils.getShortName(class)
    if short ~= nil and short ~= "" then return short end

    if class.get_full_name ~= nil then
        local okFull, full = pcall(function() return class:get_full_name() end)
        if okFull and full ~= nil and full ~= "" then return full end
    end

    return tostring(class)
end

-- Replacement for UWidgetTree::FindWidget
-- Finds the first widget whose short name matches `widgetName`.
function M.findWidget(widgetTree, widgetName)
    local tree = uevrUtils.getValid(widgetTree)
    if tree == nil or uevrUtils.getValid(tree.RootWidget) == nil then
        return nil
    end

    local targetName = normalizeWidgetName(widgetName)
    if targetName == nil or targetName == "" then
        return nil
    end

    local found = nil
    traverseWidgetDescendants(tree.RootWidget, function(widget)
        if uevrUtils.getShortName(widget) == targetName then
            found = widget
            return false
        end
    end)

    return found
end

-- Replacement for UUserWidget::GetWidgetFromName
-- Finds the first widget whose short name matches `widgetName`.
function M.getWidgetFromName(userWidget, widgetName)
    local uw = uevrUtils.getValid(userWidget)
    if uw == nil then
        return nil
    end

    local tree = uevrUtils.getValid(uw.WidgetTree)
    if tree == nil then
        return nil
    end

    return M.findWidget(tree, widgetName)
end

local parametersFileName = "widget_parameters"
local function saveParameters(parameters)
	M.print("Saving widget parameters " .. parametersFileName)
	json.dump_file(parametersFileName .. ".json", parameters, 4)
end

-- Traverses a UUserWidget's widget tree and logs short names of all descendants.
-- Uses UPanelWidget:GetChildrenCount/GetChildAt and UContentWidget:GetContent when available.
function M.logWidgetDescendants(userWidget, logLevel)
    if logLevel == nil then logLevel = LogLevel.Info end
    if uevrUtils.getValid(userWidget) == nil then
        M.print("userWidget is invalid", LogLevel.Warning)
        return
    end

    local tree = userWidget.WidgetTree
    if uevrUtils.getValid(tree) == nil or uevrUtils.getValid(tree.RootWidget) == nil then
        M.print("userWidget has no WidgetTree/RootWidget", LogLevel.Warning)
        return
    end

    traverseWidgetDescendants(tree.RootWidget, function(widget, depth)
        local indent = string.rep("  ", depth or 0)
        local widgetName = uevrUtils.getShortName(widget)
        local widgetType = getWidgetTypeName(widget)
        M.print(indent .. widgetName .. " [" .. widgetType .. "]", logLevel)
    end)
end

local ESlateVisibility = {
    Visible = 0,
    Collapsed = 1,
    Hidden = 2,
    HitTestInvisible = 3,
    SelfHitTestInvisible = 4,
}

local function asNumber(v, fallback)
    if type(v) == "number" then return v end
    if type(v) == "string" then
        local n = tonumber(v)
        if n ~= nil then return n end
    end
    return fallback
end

local function asVector2(value)
    if value == nil then return nil end
    if type(value) == "table" then
        local x = value.X or value.x or value[1]
        local y = value.Y or value.y or value[2]
        return uevrUtils.vector_2(asNumber(x, 0), asNumber(y, 0))
    end
    return value
end

local function asLinearColor(value)
    if value == nil then return nil end
    if type(value) == "table" then
        local r = value.R or value.r or value[1]
        local g = value.G or value.g or value[2]
        local b = value.B or value.b or value[3]
        local a = value.A or value.a or value[4]
        return uevrUtils.color_from_rgba(asNumber(r, 1), asNumber(g, 1), asNumber(b, 1), asNumber(a, 1))
    end
    return value
end

local function makeField(id, label, kind, opts)
    opts = opts or {}
    opts.id = id
    opts.label = label
    opts.kind = kind
    return opts
end

local function tryGetProperty(obj, key)
    local ok, v = pcall(function() return obj[key] end)
    if ok then return v end
    return nil
end

local function serializeValue(value)
    local t = type(value)
    if value == nil or t == "number" or t == "string" or t == "boolean" then
        return value
    end

    if t == "table" then
        -- Assume already JSON-friendly.
        return value
    end

    -- UObjects (widgets, assets, etc.)
    if t == "userdata" and value.get_class ~= nil then
        return {
            object = uevrUtils.getShortName(value),
            class = getWidgetTypeName(value),
        }
    end

    -- Try common struct-ish shapes (FVector2D, FLinearColor, etc.)
    if t == "userdata" then
        local x = tryGetProperty(value, "X")
        local y = tryGetProperty(value, "Y")
        if type(x) == "number" and type(y) == "number" then
            return { X = x, Y = y }
        end

        local r = tryGetProperty(value, "R")
        local g = tryGetProperty(value, "G")
        local b = tryGetProperty(value, "B")
        local a = tryGetProperty(value, "A")
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return { R = r, G = g, B = b, A = (type(a) == "number" and a or 1.0) }
        end
    end

    return tostring(value)
end

local function safeCall(fn)
    if fn == nil then return false, nil end
    return pcall(fn)
end

-- Returns a list of editable fields/actions for a widget.
-- This is intended as a backend for a future GUI-based widget editor.
--
-- Field format (convention):
--   {
--     id = "visibility",
--     label = "Visibility",
--     kind = "enum" | "number" | "bool" | "color" | "vector2" | "asset" | "action" | "readonly",
--     get = function() return ... end,          -- optional
--     set = function(value) ... end,           -- optional
--     options = { {label=..., value=...}, ...} -- for enum
--     min/max/step                             -- for number
--   }
function M.getEditableFields(widget)
    local w = uevrUtils.getValid(widget)
    if w == nil then return {} end

    local fields = {}

    -- Always include some identity info
    table.insert(fields, makeField("name", "Name", "readonly", {
        get = function() return uevrUtils.getShortName(w) end,
    }))
    table.insert(fields, makeField("type", "Type", "readonly", {
        get = function() return getWidgetTypeName(w) end,
    }))

    -- Base UWidget fields (use functions where possible)
    if w.SetVisibility ~= nil or w.Visibility ~= nil then
        table.insert(fields, makeField("visibility", "Visibility", "enum", {
            options = {
                { label = "Visible", value = ESlateVisibility.Visible },
                { label = "Collapsed", value = ESlateVisibility.Collapsed },
                { label = "Hidden", value = ESlateVisibility.Hidden },
                { label = "HitTestInvisible", value = ESlateVisibility.HitTestInvisible },
                { label = "SelfHitTestInvisible", value = ESlateVisibility.SelfHitTestInvisible },
            },
            get = function()
                return w.Visibility
            end,
            set = function(value)
                local v = asNumber(value, ESlateVisibility.Visible)
                if w.SetVisibility ~= nil then
                    w:SetVisibility(v)
                else
                    w.Visibility = v
                end
            end,
        }))
    end

    if w.SetIsEnabled ~= nil or w.bIsEnabled ~= nil or w.GetIsEnabled ~= nil then
        table.insert(fields, makeField("enabled", "Enabled", "bool", {
            get = function()
                if w.GetIsEnabled ~= nil then
                    return w:GetIsEnabled()
                end
                return w.bIsEnabled
            end,
            set = function(value)
                local b = value == true
                if w.SetIsEnabled ~= nil then
                    w:SetIsEnabled(b)
                else
                    w.bIsEnabled = b
                end
            end,
        }))
    end

    if w.SetRenderOpacity ~= nil or w.RenderOpacity ~= nil or w.GetRenderOpacity ~= nil then
        table.insert(fields, makeField("renderOpacity", "Render Opacity", "number", {
            min = 0.0,
            max = 1.0,
            step = 0.01,
            get = function()
                if w.GetRenderOpacity ~= nil then
                    return w:GetRenderOpacity()
                end
                return w.RenderOpacity
            end,
            set = function(value)
                local v = asNumber(value, 1.0)
                if w.SetRenderOpacity ~= nil then
                    w:SetRenderOpacity(v)
                else
                    w.RenderOpacity = v
                end
            end,
        }))
    end

    if w.RemoveFromParent ~= nil then
        table.insert(fields, makeField("removeFromParent", "Remove From Parent", "action", {
            invoke = function() w:RemoveFromParent() end,
        }))
    end

    if w.ForceLayoutPrepass ~= nil then
        table.insert(fields, makeField("forceLayoutPrepass", "Force Layout Prepass", "action", {
            invoke = function() w:ForceLayoutPrepass() end,
        }))
    end

    -- UImage adapter (first pass)
    local looksLikeImage = (w.SetBrushFromTexture ~= nil) or (w.SetBrushSize ~= nil) or (w.SetColorAndOpacity ~= nil) or (w.Brush ~= nil and w.ColorAndOpacity ~= nil)
    if looksLikeImage then
        -- ColorAndOpacity (FLinearColor)
        if w.SetColorAndOpacity ~= nil or w.ColorAndOpacity ~= nil then
            table.insert(fields, makeField("imageColorAndOpacity", "Image Color+Opacity", "color", {
                get = function()
                    return w.ColorAndOpacity
                end,
                set = function(value)
                    local c = asLinearColor(value)
                    if c == nil then return end
                    if w.SetColorAndOpacity ~= nil then
                        w:SetColorAndOpacity(c)
                    else
                        w.ColorAndOpacity = c
                    end
                end,
            }))
        end

        -- Brush size
        if w.SetBrushSize ~= nil or w.GetBrushSize ~= nil or (w.Brush ~= nil and w.Brush.ImageSize ~= nil) then
            table.insert(fields, makeField("brushSize", "Brush Size", "vector2", {
                get = function()
                    if w.GetBrushSize ~= nil then
                        return w:GetBrushSize()
                    end
                    if w.Brush ~= nil then
                        return w.Brush.ImageSize
                    end
                    return nil
                end,
                set = function(value)
                    local v = asVector2(value)
                    if v == nil then return end
                    if w.SetBrushSize ~= nil then
                        w:SetBrushSize(v)
                    elseif w.Brush ~= nil then
                        w.Brush.ImageSize = v
                    end
                end,
            }))
        end

        -- Brush resource (texture)
        if w.SetBrushFromTexture ~= nil then
            table.insert(fields, makeField("setBrushFromTexture", "Set Brush From Texture", "asset", {
                assetClass = "Class /Script/Engine.Texture2D",
                set = function(assetPath)
                    if type(assetPath) ~= "string" or assetPath == "" then return end
                    local tex = uevrUtils.getLoadedAsset(assetPath)
                    if tex ~= nil then
                        w:SetBrushFromTexture(tex, true)
                    end
                end,
            }))
        end

        -- Brush resource (material)
        if w.SetBrushFromMaterial ~= nil then
            table.insert(fields, makeField("setBrushFromMaterial", "Set Brush From Material", "asset", {
                assetClass = "Class /Script/Engine.MaterialInterface",
                set = function(assetPath)
                    if type(assetPath) ~= "string" or assetPath == "" then return end
                    local mat = uevrUtils.getLoadedAsset(assetPath)
                    if mat ~= nil then
                        w:SetBrushFromMaterial(mat)
                    end
                end,
            }))
        end

        if w.GetDynamicMaterial ~= nil then
            table.insert(fields, makeField("getDynamicMaterial", "Get Dynamic Material", "action", {
                invoke = function() return w:GetDynamicMaterial() end,
            }))
        end
    end

    return fields
end

-- Traverses a UUserWidget's widget tree and dumps a JSON-friendly table:
--
-- {
--   root = "RootWidgetName",
--   widgets = {
--     {
--       name = "Foo",
--       type = "Button",
--       depth = 2,
--       fields = {
--         visibility = { kind="enum", value=0 },
--         renderOpacity = { kind="number", value=1.0 },
--         ...
--       }
--     },
--     ...
--   }
-- }
--
-- Then writes it out using saveParameters(parameters).
function M.dumpWidgetEditableFields(userWidget)
    local uw = uevrUtils.getValid(userWidget)
    if uw == nil then
        M.print("userWidget is invalid", LogLevel.Warning)
        return nil
    end

    local tree = uw.WidgetTree
    if uevrUtils.getValid(tree) == nil or uevrUtils.getValid(tree.RootWidget) == nil then
        M.print("userWidget has no WidgetTree/RootWidget", LogLevel.Warning)
        return nil
    end

    local parameters = {
        root = uevrUtils.getShortName(tree.RootWidget),
        tree = nil,
    }

    local function buildNode(w)

        local node = {
            name = uevrUtils.getShortName(w),
            type = getWidgetTypeName(w),
            fields = {},
            children = {},
        }

        local editable = M.getEditableFields(w)
        for _, field in ipairs(editable) do
            local id = field.id or field.label or tostring(#node.fields + 1)
            local record = {
                label = field.label,
                kind = field.kind,
                hasGet = field.get ~= nil,
                hasSet = field.set ~= nil,
                hasInvoke = field.invoke ~= nil,
            }

            if field.get ~= nil then
                local ok, value = safeCall(function() return field.get() end)
                if ok then
                    record.value = serializeValue(value)
                else
                    record.error = "get_failed"
                end
            end

            if field.kind == "enum" and field.options ~= nil then
                record.options = field.options
            end

            node.fields[id] = record
        end

        return node
    end

    -- Build nested tree using traversal order + depth.
    -- Depth stack holds the latest node at each depth.
    local stack = {}
    traverseWidgetDescendants(tree.RootWidget, function(widget, depth)
        local w = uevrUtils.getValid(widget)
        if w == nil then return end

        local d = depth or 0
        local node = buildNode(w)

        if d == 0 then
            parameters.tree = node
            stack[1] = node
            return
        end

        -- Ensure stack reflects current depth.
        -- Parent of depth d is at stack[d].
        for i = #stack, d + 1, -1 do
            stack[i] = nil
        end

        local parent = stack[d]
        if parent == nil then
            -- Fallback: attach to root if depth is inconsistent.
            parent = stack[1]
        end

        if parent ~= nil then
            table.insert(parent.children, node)
        end

        stack[d + 1] = node
    end)

    saveParameters(parameters)
    M.print("Dumped widget editable fields tree to " .. parametersFileName .. ".json", LogLevel.Info)
    return parameters
end

return M