-- Credits: Portions of the following code courtesy of LukasBlaster where noted

--[[
Usage
    Drop the lib folder containing this file into your project folder
    Add code like this in your script:
		local widgetModule = require('libs/widget')

    Image host widgets
		UUserWidget is abstract and Lua cannot define new widget classes, so widgetModule.createImageWidget
		borrows a loaded Widget Blueprint class to act as the host. The host is chosen automatically and generically:
		it must derive directly from UserWidget and have no Blueprint event graph, so no game logic can run against
		the replaced content. The host's original widget tree is discarded and replaced with an empty CanvasPanel
		before the image is added. The chosen class is cached and re-chosen after each level change.
		To show it in world space use widgetComponent.createImageComponent (libs/widgetcomponent).
		Images and text can also be added to an existing UserWidget whose root is a CanvasPanel.

	Canvas layout
		Image:addToWidget, Image:setLayout, Text:addToWidget and Text:setLayout share one opts table:
			align     - one of widgetModule.Image.ALIGN (Text.ALIGN is the same table). Both anchors are set to that point.
			alignment - slate alignment vector2D. Defaults to the align point, which pins that point of the widget to the anchor.
			offset    - vector2D from the anchor. position is used when offset is omitted. Default (0, 0).
			zOrder    - default 999.
		A vector2D passed in place of opts (a value with an X field) is treated as position.
		addToWidget with no opts uses position (50, 50).
		setLayout and setPosition update a widget that addToWidget has already parented.

	Available functions:

    widgetModule.enableTextureCache - when true, Image:setTexture keeps imported textures by file name and reuses them.
		Default false. An entry that is no longer a Texture2D is imported again. destroyAll clears the cache.

    widgetModule.loadTexture(imageName, (optional)path) - imports "$data/" .. path .. imageName as a Texture2D and
		returns it, or nil when the import fails. path defaults to "images/". Uses the texture cache when
		enableTextureCache is true. Pass the result to image:setTextureObject.

    widgetModule.Image.ALIGN - anchor points as {x, y} from 0 to 1:
		TOP_LEFT, TOP_CENTER, TOP_RIGHT, CENTER_LEFT, CENTER, CENTER_RIGHT,
		BOTTOM_LEFT, BOTTOM_CENTER, BOTTOM_RIGHT.
		widgetModule.Text.ALIGN is the same table.

    widgetModule.Image.new(maxDim) - creates an image. Call addToWidget to parent it.
		maxDim is the longest side in slate units (default 128). Aspect ratio is preserved when a texture is set.
		widgetModule.Image.new(imageName, maxDim) also loads that file immediately via setTexture.
		Assign image.texture to an already loaded Texture2D before addToWidget to use it in place of a file import.
        example:
            local image = widgetModule.Image.new(300)
            image:setTexture("Stupefy.png")
            image:addToWidget(widget, {
                align = widgetModule.Image.ALIGN.BOTTOM_RIGHT,
                offset = uevrUtils.vector2D(-170, -100),
            })

    image:setTexture(imageName, (optional)path, (optional)hideIfMissing) - imports
		"$data/" .. path .. imageName as a Texture2D and sizes the brush so its longest side is maxDim.
		path defaults to "images/". hideIfMissing defaults to true: a failed import collapses an image that is
		already on a widget and returns false. Returns true when the texture is applied.
		Call it before or after addToWidget.

    image:setTextureObject(texture) - applies an already loaded Texture2D, such as one from widgetModule.loadTexture,
		and sizes the brush so its longest side is maxDim. Returns false, leaving the image unchanged, when texture
		is not a valid Texture2D. Call it before or after addToWidget.
    image:setVisible(visible) - shows or collapses the image. A hidden image stays collapsed when a texture is set.
		A shown image stays collapsed until it has a texture or a color.
    image:setColor(hex) - tints the image, "#RRGGBB" or "#RRGGBBAA". An image with a color and no texture
		draws as a solid rectangle of its draw size.
    image:setSize(size2D) - sets the draw size directly. A later setTexture or setTextureObject sizes it from maxDim.
    image:setRenderScale(scale) - scales the drawn image about its center without changing its layout size.
		A large maxDim scaled down this way keeps a large texture sharp at a small size.

    image:addToWidget(widget, (optional)opts) - parents a UImage on widget's CanvasPanel root.
		Returns false when widget has no CanvasPanel root or the image could not be created. See Canvas layout.

    image:setLayout(opts) - applies Canvas layout to an image addToWidget has parented, and sets the slot size to the brush.
    image:setPosition(position2D) - setLayout with that position.
    image:remove() - RemoveFromParent, then drops the image, slot and texture.

    widgetModule.Text.new((optional)text) - creates a text block. Call addToWidget to parent it.
		text defaults to "". setText, setColor, setFontSize and setFont store their values and apply them when the
		TextBlock is created, so they can be called before addToWidget.
        example:
            local label = widgetModule.Text.new("12")
            label:setColor("#F9C046FF")
            label:setFontSize(20)
            label:setFont("/Engine/EngineFonts/Roboto.Roboto", "Regular")
            label:addToWidget(widget, { align = widgetModule.Text.ALIGN.CENTER })

    text:setText(text) - sets the string. 
    text:setColor(hex) - "#RRGGBB" or "#RRGGBBAA".
    text:setFontSize(size) - slate font size.
    text:setFont((optional)fontPath, (optional)typeface) - font asset path, and a typeface name such as
		"Regular", "Bold", "Italic" or a game face such as "Body". A fontPath applies that font asset.
		A typeface applies that face. Either argument can be left nil.
    text:addToWidget(widget, (optional)opts) - parents a UTextBlock on widget's CanvasPanel root.
		The slot is auto-sized to the text. Returns false when widget has no CanvasPanel root. See Canvas layout.
    text:setLayout(opts) - applies Canvas layout to text addToWidget has parented. The slot stays auto-sized.
    text:setPosition(position2D) - setLayout with that position.
    text:remove() - RemoveFromParent, then drops the text block and slot.
    text:setVisible(visible) - shows or collapses the text block. Can be called before addToWidget.
    text:getDesiredSize() - the laid out size of the text as a vector2D, or nil before addToWidget.

    widgetModule.createHostWidget() - creates an empty host UserWidget whose root is a CanvasPanel.
		Returns hostWidget or nil if no host widget class could be found or created.
        example:
            local host = widgetModule.createHostWidget()
            image:addToWidget(host, { align = widgetModule.Image.ALIGN.CENTER })

    widgetModule.createImageWidget(imageSize) - creates a host UserWidget containing a single centered Image.
		Returns hostWidget, image or nil if no host widget class could be found or created.
		imageSize is the image's maximum dimension. The returned image is a widgetModule.Image, so use
		image:setTexture("Name.png") to change what it shows.
        example:
            local hostWidget, image = widgetModule.createImageWidget(40)

    widgetModule.destroyAll() - destroys every Image and Text this module created, and clears the texture cache
		and the cached host widget class. Called automatically before level changes and on script reset.
        example:
            widgetModule.destroyAll()

    widgetModule.findWidget(widgetTree, widgetName) - first descendant of widgetTree.RootWidget whose short
		name equals widgetName, or nil. widgetName may be a string or an FName. Replaces UWidgetTree::FindWidget.
		Walks UPanelWidget children and UContentWidget content.
        example:
            local button = widgetModule.findWidget(widget.WidgetTree, "InvisibleButton")

    widgetModule.getWidgetFromName(userWidget, widgetName) - the same search, starting at userWidget.WidgetTree.
		Replaces UUserWidget::GetWidgetFromName.
        example:
            local logo = widgetModule.getWidgetFromName(menu, "LogoImage")

    widgetModule.logWidgetDescendants(userWidget, (optional)logLevel) - logs each descendant as
		"name [Type]", indented by depth. logLevel defaults to LogLevel.Info.
        example:
            widgetModule.logWidgetDescendants(menu)

    widgetModule.getEditableFields(widget) - field descriptors for a widget editor. Each entry is
		{ id, label, kind, get, set, options, min, max, step }. Actions use invoke in place of set.
		kind is "readonly", "enum", "bool", "number", "color", "vector2", "asset" or "action".
		Every widget includes name and type, plus visibility, enabled, render opacity, remove and layout
		prepass when the widget exposes them. Image brush color, size and source are included when the
		widget exposes brush functions.
        example:
            local fields = widgetModule.getEditableFields(logo)

    widgetModule.dumpWidgetEditableFields(userWidget) - walks the widget tree, writes widget_parameters.json
		and returns the same table: { root = shortName, tree = { name, type, fields, children } }.
		Each field record stores label, kind, whether get/set/invoke exist, the current value, and enum options.
		Returns nil when userWidget or its WidgetTree is invalid.
        example:
            widgetModule.dumpWidgetEditableFields(menu)

    widgetModule.setLogLevel(val) - sets the logging level for widget messages
        example:
            widgetModule.setLogLevel(LogLevel.Debug)

    widgetModule.print(text, (optional)logLevel) - prints a message at the given (or Debug) log level
        example:
            widgetModule.print("Host widget ready")


]]--

local uevrUtils = require('libs/uevr_utils')
local plugin = require('libs/core/plugin')

local M = {}
M.enableTextureCache = false

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

local Image = {}
Image.__index = Image
Image.createdImages = {}
Image.textureCache = {}
Image.ALIGN = {
	TOP_LEFT      = {0,   0},
	TOP_CENTER    = {0.5, 0},
	TOP_RIGHT     = {1,   0},
	CENTER_LEFT   = {0,   0.5},
	CENTER        = {0.5, 0.5},
	CENTER_RIGHT  = {1,   0.5},
	BOTTOM_LEFT   = {0,   1},
	BOTTOM_CENTER = {0.5, 1},
	BOTTOM_RIGHT  = {1,   1},
}
function Image.new(imageName, maxDim)
	local self = setmetatable({}, Image)
	if type(imageName) == "number" and maxDim == nil then
		maxDim = imageName
		imageName = nil
	end
	self.maxDim = maxDim or 128
	self.drawSize = uevrUtils.vector2D(self.maxDim, self.maxDim)
	self.image = nil
	self.slot = nil
	self.texture = nil
	if imageName then
		self:setTexture(imageName)
	end
	table.insert(Image.createdImages, self)
	return self
end
function Image.destroyAll()
	for i = 1, #Image.createdImages do
		local inst = Image.createdImages[i]
		if inst ~= nil and inst.remove ~= nil then
			inst:remove()
		end
	end
	Image.createdImages = {}
	Image.textureCache = {}
end

-- hex is "#RRGGBB" or "#RRGGBBAA"
local function linearColorFromHex(hex)
	local function channel(i, default) return (tonumber(hex:sub(i, i + 1), 16) or default) / 255 end
	return uevrUtils.color_from_rgba(channel(2, 0), channel(4, 0), channel(6, 0), channel(8, 255))
end

-- stale/recycled cache entries can pass getValid but lose Texture2D methods
local function isTexture(texture)
	return uevrUtils.getValid(texture) ~= nil and texture.Blueprint_GetSizeX ~= nil and texture.Blueprint_GetSizeY ~= nil
end

function M.loadTexture(imageName, path)
	if imageName == nil then return nil end
	if path == nil then path = "images/" end
	local fileName = path .. imageName
	-- KNOWN ISSUE: this cache can return the wrong image. Imported textures are not rooted, so one that no image
	-- is showing can be garbage collected. A later import (another file) can then reuse its address, and
	-- isTexture still passes because a valid Texture2D is there, so this file name returns the other file's
	-- texture. Comparing the cached texture's full name (see isSameLiveObject) would reject it. tutorial.lua's
	-- getTexture had the same issue.
	if M.enableTextureCache then
		local texture = Image.textureCache[fileName]
		if isTexture(texture) then return texture end
		Image.textureCache[fileName] = nil
	end
	local result = plugin.executeFunction(kismet_rendering_library, "ImportFileAsTexture2D", uevrUtils.get_world(), "$data/" .. fileName)
	local texture = result and result.ReturnValue
	if not isTexture(texture) then return nil end
	if M.enableTextureCache then
		Image.textureCache[fileName] = texture
	end
	return texture
end

-- exists() passes for a new object that reuses a freed address; the full name rejects it
local function isSameLiveObject(obj, fullName)
	return uevrUtils.getValid(obj) ~= nil and fullName ~= nil and obj:get_full_name() == fullName
end

-- The image and its slot, only while they are still the ones addToWidget created
local function liveImage(image)
	return isSameLiveObject(image.image, image.imageName) and image.image or nil
end
local function liveSlot(image)
	return isSameLiveObject(image.slot, image.slotName) and image.slot or nil
end

-- UImage::SetBrushSize is gone from UE 5.6 (Hellraiser): SetDesiredSizeOverride (UE 5.x) sets the same desired size
local function setBrushSize(widget, size)
	if widget.SetBrushSize ~= nil then
		widget:SetBrushSize(size)
	elseif widget.SetDesiredSizeOverride ~= nil then
		widget:SetDesiredSizeOverride(size)
	end
end

-- Collapsed while hidden or while there is nothing to draw
local function updateImageVisibility(image)
	local widget = liveImage(image)
	if widget == nil then return end
	local visible = not image.hidden and (image.texture ~= nil or image.color ~= nil)
	widget:SetVisibility(visible and 0 or 1) -- Visible or Collapsed
end

function Image:setTextureObject(texture)
	if not isTexture(texture) then return false end
	self.texture = texture
	local w, h = texture:Blueprint_GetSizeX(), texture:Blueprint_GetSizeY()
	if w > 0 and h > 0 then
		local scale = self.maxDim / math.max(w, h)
		self.drawSize = uevrUtils.vector2D(w * scale, h * scale)
	else
		self.drawSize = uevrUtils.vector2D(self.maxDim, self.maxDim)
	end
	local widget = liveImage(self)
	if widget ~= nil then
		widget:SetBrushFromTexture(texture, true)
		setBrushSize(widget, self.drawSize)
		updateImageVisibility(self)
		local slot = liveSlot(self)
		if slot ~= nil then
			slot:SetSize(self.drawSize)
		end
	end
	return true
end

function Image:setTexture(imageName, path, hideIfMissing)
	if hideIfMissing == nil then hideIfMissing = true end
	if self:setTextureObject(M.loadTexture(imageName, path)) then return true end
	local widget = hideIfMissing and liveImage(self) or nil
	if widget ~= nil then
		widget:SetVisibility(1) -- Collapsed
	end
	return false
end

function Image:setVisible(visible)
	self.hidden = visible == false
	updateImageVisibility(self)
end

-- Without a texture the image draws as a solid rectangle of this color
function Image:setColor(hex)
	if type(hex) ~= "string" then return end
	self.color = hex
	local widget = liveImage(self)
	if widget ~= nil then
		widget:SetColorAndOpacity(linearColorFromHex(hex))
		updateImageVisibility(self)
	end
end

function Image:setRenderScale(scale)
	self.renderScale = scale
	local widget = liveImage(self)
	if widget ~= nil then
		widget:SetRenderScale(uevrUtils.vector2D(scale, scale))
	end
end

function Image:setSize(size2D)
	if size2D == nil then return end
	self.drawSize = uevrUtils.vector2D(size2D.X, size2D.Y)
	local widget = liveImage(self)
	if widget ~= nil then
		setBrushSize(widget, self.drawSize)
		local slot = liveSlot(self)
		if slot ~= nil then
			slot:SetSize(self.drawSize)
		end
	end
end

local function setSlotLayout(slot, opts)
	opts = opts or {}

	local offset = opts.offset or opts.position or uevrUtils.vector2D(0, 0)
	local align = opts.align

	local ax, ay = 0, 0
	if align ~= nil then
		if type(align) ~= "table" or align[1] == nil then return false end
		ax, ay = align[1], align[2]
	end

	local pt = uevrUtils.vector2D(ax, ay)
	local anchors = slot:GetAnchors()
	anchors.Minimum = pt
	anchors.Maximum = pt
	slot:SetAnchors(anchors)
	slot:SetAlignment(opts.alignment or pt)
	slot:SetPosition(offset)
	slot:SetZOrder(opts.zOrder or 999)
	return true
end

function Image:setLayout(opts)
	local slot = liveSlot(self)
	if slot == nil then return end
	if setSlotLayout(slot, opts) then
		slot:SetSize(self.drawSize)
	end
end

function Image:addToWidget(widget, opts)
	if widget == nil or widget.WidgetTree == nil then return false end
	local panel = widget.WidgetTree.RootWidget
	if panel == nil or panel.AddChildToCanvas == nil then return false end
	if self.image == nil then
		self.image = uevrUtils.spawn_object("Class /Script/UMG.Image", widget.WidgetTree)
		if self.image == nil then return false end
		self.imageName = self.image:get_full_name()
		if self.texture ~= nil then
			self.image:SetBrushFromTexture(self.texture, true)
		end
		setBrushSize(self.image, self.drawSize)
		if self.color ~= nil then
			self.image:SetColorAndOpacity(linearColorFromHex(self.color))
		end
		if self.renderScale ~= nil then
			self.image:SetRenderScale(uevrUtils.vector2D(self.renderScale, self.renderScale))
		end
		if self.hidden or (self.texture == nil and self.color == nil) then
			self.image:SetVisibility(1) -- Collapsed until shown and given a texture or color
		end
		self.slot = panel:AddChildToCanvas(self.image)
		self.slotName = self.slot ~= nil and self.slot:get_full_name() or nil
	end
	if opts ~= nil and opts.X ~= nil then
		opts = { position = opts }
	end
	self:setLayout(opts or { position = uevrUtils.vector2D(50, 50) })
	return true
end

function Image:setPosition(position2D)
	self:setLayout({ position = position2D })
end

function Image:remove()
	local widget = liveImage(self)
	if widget ~= nil and widget.RemoveFromParent ~= nil then
		widget:RemoveFromParent()
	end
	self.image = nil
	self.imageName = nil
	self.slot = nil
	self.slotName = nil
	self.texture = nil
end

M.Image = Image

local Text = {}
Text.__index = Text
Text.createdTexts = {}
Text.ALIGN = Image.ALIGN
function Text.new(text)
	local self = setmetatable({}, Text)
	self.text = text or ""
	self.textBlock = nil
	self.slot = nil
	table.insert(Text.createdTexts, self)
	return self
end
function Text.destroyAll()
	for i = 1, #Text.createdTexts do
		local inst = Text.createdTexts[i]
		if inst ~= nil and inst.remove ~= nil then
			inst:remove()
		end
	end
	Text.createdTexts = {}
end

-- Native UEVR Lua cannot marshal FText, so SetText goes through the plugin
function Text:setText(text)
	self.text = text or ""
	if isSameLiveObject(self.textBlock, self.textBlockName) then
		plugin.executeFunction(self.textBlock, "SetText", self.text)
	end
end

-- hex is "#RRGGBB" or "#RRGGBBAA"
function Text:setColor(hex)
	self.color = hex
	if self.textBlock == nil or type(hex) ~= "string" then return end
	local color = self.textBlock.ColorAndOpacity
	color.SpecifiedColor = linearColorFromHex(hex)
	self.textBlock:SetColorAndOpacity(color)
end

-- Font and Size FName casing varies between game sessions
local function applyFont(text)
	if text.textBlock == nil or (text.fontSize == nil and text.fontPath == nil and text.typeface == nil) then return end
	local font = text.textBlock.Font or text.textBlock.font
	if text.fontSize ~= nil then
		if font.Size ~= nil then font.Size = text.fontSize else font.size = text.fontSize end
	end
	if text.fontPath ~= nil then
		local fontObject = uevrUtils.getLoadedAsset(text.fontPath)
		if fontObject ~= nil then font.FontObject = fontObject end
	end
	if text.typeface ~= nil then
		font.TypefaceFontName = uevrUtils.fname_from_string(text.typeface)
	end
	text.textBlock:SetFont(font)
end

function Text:setFontSize(size)
	self.fontSize = size
	applyFont(self)
end

-- fontPath is a font asset path e.g. "/Engine/EngineFonts/Roboto.Roboto", typeface is optional e.g. "Regular", "Bold", "Italic"
function Text:setFont(fontPath, typeface)
	self.fontPath = fontPath
	self.typeface = typeface
	applyFont(self)
end

function Text:setLayout(opts)
	if self.slot == nil then return end
	if setSlotLayout(self.slot, opts) then
		self.slot:SetAutoSize(true)
	end
end

function Text:addToWidget(widget, opts)
	if widget == nil or widget.WidgetTree == nil then return false end
	local panel = widget.WidgetTree.RootWidget
	if panel == nil or panel.AddChildToCanvas == nil then return false end
	if self.textBlock == nil then
		self.textBlock = uevrUtils.spawn_object("Class /Script/UMG.TextBlock", widget.WidgetTree)
		if self.textBlock == nil then return false end
		self.textBlockName = self.textBlock:get_full_name()
		self.slot = panel:AddChildToCanvas(self.textBlock)
		self:setText(self.text)
		if self.color ~= nil then self:setColor(self.color) end
		applyFont(self)
		if self.hidden then self.textBlock:SetVisibility(1) end -- Collapsed
	end
	if opts ~= nil and opts.X ~= nil then
		opts = { position = opts }
	end
	self:setLayout(opts or { position = uevrUtils.vector2D(50, 50) })
	return true
end

function Text:setPosition(position2D)
	self:setLayout({ position = position2D })
end

function Text:remove()
	if uevrUtils.getValid(self.textBlock) ~= nil and self.textBlock.RemoveFromParent ~= nil then
		self.textBlock:RemoveFromParent()
	end
	self.textBlock = nil
	self.textBlockName = nil
	self.slot = nil
end

function Text:setVisible(visible)
	self.hidden = visible == false
	if self.textBlock ~= nil then
		self.textBlock:SetVisibility(self.hidden and 1 or 0) -- Collapsed or Visible
	end
end

-- Lays out the text block first so the size matches the current text and font
function Text:getDesiredSize()
	if self.textBlock == nil then return nil end
	if self.textBlock.ForceLayoutPrepass ~= nil then
		self.textBlock:ForceLayoutPrepass()
	end
	return self.textBlock:GetDesiredSize()
end

M.Text = Text

-----------------------------------------------------------------
-- Inspiration and portions of the following code courtesy of LukasBlaster
local hostWidgetClassName = nil
-- Stalker 2 addition: a host class named by the game script, resolved by its full path (uevr.api:find_uobject).
-- The search below enumerates objects with class:get_objects_matching, which returns nothing on the
-- UObjectHook-adoption backend (it only sees adopted objects), and the game's widgets derive from its own
-- native widget classes anyway. prepare(hostWidget) runs on each new host before its tree is replaced.
local preferredHostClassName = nil
local preferredHostPrepare = nil
function M.setHostWidgetClass(className, prepare)
	preferredHostClassName = className
	preferredHostPrepare = prepare
	hostWidgetClassName = nil
end

-- UUserWidget is abstract and Lua cannot define new widget classes, so borrow a loaded Widget Blueprint class.
-- Direct UserWidget children with no ubergraph have no native or Blueprint logic to run against the replaced tree.
local function getGenericUserWidgetClassName()
	if hostWidgetClassName ~= nil then return hostWidgetClassName end
	if preferredHostClassName ~= nil then
		local cls = uevrUtils.get_class(preferredHostClassName)
		if cls ~= nil then
			hostWidgetClassName = preferredHostClassName
			M.print("Using host widget class " .. hostWidgetClassName)
			return hostWidgetClassName
		end
		M.print("Host widget class " .. preferredHostClassName .. " is not loaded, searching", LogLevel.Warning)
	end
	local userWidgetName = "Class /Script/UMG.UserWidget"
	local blueprintClass = uevrUtils.get_class("Class /Script/UMG.WidgetBlueprintGeneratedClass")
	-- Including defaults yields a CDO for every loaded widget class, live or not
	for _, widget in pairs(uevrUtils.find_all_instances(userWidgetName, true) or {}) do
		local cls = widget:get_class()
		local super = cls:get_super_struct()
        --check that the widget we are trying to hijack does not aleady have blueprint functions or c++ functions
        --that might cause unexpected behavior. If no widgets are found using this restriction for some reason this check could be relaxed
		--native classes have no UberGraphFunction field at all, so require a Blueprint class
		if super ~= nil and super:get_full_name() == userWidgetName and cls:is_a(blueprintClass) and cls.UberGraphFunction == nil then
			hostWidgetClassName = cls:get_full_name()
			M.print("Using host widget class " .. hostWidgetClassName)
			return hostWidgetClassName
		end
	end
	M.print("No host widget class found", LogLevel.Warning)
end

-- Creates an empty host UserWidget. The host's original tree is replaced with a fresh CanvasPanel root
function M.createHostWidget()
	local className = getGenericUserWidgetClassName()
	if className == nil then return nil end
	local hostWidget = uevrUtils.getValid(uevrUtils.createWidget(className))
	if hostWidget == nil then return nil end
	if preferredHostPrepare ~= nil and className == preferredHostClassName then
		preferredHostPrepare(hostWidget)
	end
	hostWidget.WidgetTree.RootWidget = uevrUtils.spawn_object("Class /Script/UMG.CanvasPanel", hostWidget.WidgetTree)
	return hostWidget
end

-- Creates a host UserWidget containing a centered Image
function M.createImageWidget(imageSize)
	local hostWidget = M.createHostWidget()
	if hostWidget == nil then return nil end
	local image = Image.new(imageSize)
	image:addToWidget(hostWidget, { align = Image.ALIGN.CENTER })
	return hostWidget, image
end
-----------------------------------------------------------------

function M.destroyAll()
	Image.destroyAll()
	Text.destroyAll()
	hostWidgetClassName = nil
end

uevrUtils.registerPreLevelChangeCallback(function()
	M.destroyAll()
end)

uevr.params.sdk.callbacks.on_script_reset(function()
	M.destroyAll()
end)




















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

-- Nested timings are inclusive. Toggle and report with uevrUtils.profiler.
setSlotLayout = uevrUtils.profiler:wrap("Widget: set slot layout", setSlotLayout)
applyFont = uevrUtils.profiler:wrap("Widget: apply font", applyFont)
getGenericUserWidgetClassName = uevrUtils.profiler:wrap("Widget: find host class", getGenericUserWidgetClassName)
traverseWidgetDescendants = uevrUtils.profiler:wrap("Widget: traverse descendants", traverseWidgetDescendants)
saveParameters = uevrUtils.profiler:wrap("Widget: save parameters", saveParameters)

Image.new = uevrUtils.profiler:wrap("Widget: new image", Image.new)
Image.destroyAll = uevrUtils.profiler:wrap("Widget: destroy images", Image.destroyAll)
Image.setTexture = uevrUtils.profiler:wrap("Widget: set texture", Image.setTexture)
Image.setLayout = uevrUtils.profiler:wrap("Widget: set image layout", Image.setLayout)
Image.addToWidget = uevrUtils.profiler:wrap("Widget: add image", Image.addToWidget)
Image.remove = uevrUtils.profiler:wrap("Widget: remove image", Image.remove)
M.loadTexture = uevrUtils.profiler:wrap("Widget: load texture", M.loadTexture)
Image.setTextureObject = uevrUtils.profiler:wrap("Widget: set texture object", Image.setTextureObject)
Image.setVisible = uevrUtils.profiler:wrap("Widget: set image visibility", Image.setVisible)
Image.setColor = uevrUtils.profiler:wrap("Widget: set image color", Image.setColor)
Image.setSize = uevrUtils.profiler:wrap("Widget: set image size", Image.setSize)
Image.setRenderScale = uevrUtils.profiler:wrap("Widget: set image render scale", Image.setRenderScale)

Text.new = uevrUtils.profiler:wrap("Widget: new text", Text.new)
Text.destroyAll = uevrUtils.profiler:wrap("Widget: destroy texts", Text.destroyAll)
Text.setText = uevrUtils.profiler:wrap("Widget: set text", Text.setText)
Text.setColor = uevrUtils.profiler:wrap("Widget: set text color", Text.setColor)
Text.setFontSize = uevrUtils.profiler:wrap("Widget: set font size", Text.setFontSize)
Text.setFont = uevrUtils.profiler:wrap("Widget: set font", Text.setFont)
Text.setLayout = uevrUtils.profiler:wrap("Widget: set text layout", Text.setLayout)
Text.addToWidget = uevrUtils.profiler:wrap("Widget: add text", Text.addToWidget)
Text.remove = uevrUtils.profiler:wrap("Widget: remove text", Text.remove)
Text.setVisible = uevrUtils.profiler:wrap("Widget: set text visibility", Text.setVisible)
Text.getDesiredSize = uevrUtils.profiler:wrap("Widget: get text size", Text.getDesiredSize)

M.createHostWidget = uevrUtils.profiler:wrap("Widget: create host", M.createHostWidget)
M.createImageWidget = uevrUtils.profiler:wrap("Widget: create image widget", M.createImageWidget)
M.destroyAll = uevrUtils.profiler:wrap("Widget: destroy all", M.destroyAll)
M.findWidget = uevrUtils.profiler:wrap("Widget: find widget", M.findWidget)
M.getWidgetFromName = uevrUtils.profiler:wrap("Widget: get widget from name", M.getWidgetFromName)
M.logWidgetDescendants = uevrUtils.profiler:wrap("Widget: log descendants", M.logWidgetDescendants)
M.getEditableFields = uevrUtils.profiler:wrap("Widget: get editable fields", M.getEditableFields)
M.dumpWidgetEditableFields = uevrUtils.profiler:wrap("Widget: dump editable fields", M.dumpWidgetEditableFields)

return M

--[[
[info] CanvasPanel_0
[info]   InvisibleButton
[info]   LogoContainer
[info]     LogoImage
[info]   PressKeyPromptOverlay
[info]     PressKeyPrompt
[info]     XboxTextblockContainer
[info]       LeftSidePrompt
[info]       Image_0
[info]       RightSidePrompt
[info]   GammaSelection
[info]   ContentOverlay
[info]     MainOptions
[info]     ExtraOptions
[info]     DeliverablesOptions
[info]     MenuDLCManager
[info]     UserNameTextBlock
[info]     VersionTextBlock
[info]   AutosaveSplashOverlay
[info]     VerticalBox_0
[info]       AutosaveSplashText
[info]       SavingSpinnerWidget
[info]   CreditsWidget
[info]   LegalWidget
[info]   SavingWidget_BP
]]--
-- register_key_bind("F2", function()
-- 	local userWidget = uevrUtils.getActiveWidgetByClass("WidgetBlueprintGeneratedClass /Game/UI/Menus/MainMenu/MainMenu.MainMenu_C")
-- 	if userWidget ~= nil then
-- 		print("Main menu widget found:")
-- 		--widgetModule.logWidgetDescendants(userWidget)
-- 		widgetModule.dumpWidgetEditableFields(userWidget)
-- 	else
-- 		print("No main menu widget found")
-- 	end
-- end)