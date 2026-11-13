--[[
Usage
    Drop the lib folder containing this file into your project folder
    Add code like this in your script:
		local tutorial = require('libs/tutorial')
		local intro = tutorial.new()
		intro:showOnce()

	A tutorial is a host UserWidget added to the viewport like any other top level HUD widget. It shows a series of
	images with a navigation bar of controller button icons and labels under the image. While it is open it reads
	the controller before any other script, and hides its buttons from the game and from other scripts.
	Actions run on the next engine tick.

	Open gesture
		By default a left trigger pull near the eyes (the eye scratch gesture from libs/gestures) opens any
		tutorial at any time, at the saved step (see rememberPage) or step 1. It is detected before every other
		input handler, and that trigger pull is hidden from the game and other scripts until it is released.
		Set options.openGesture = false to disable it.
		libs/gestures does not need gestures.init(); without it the gesture uses its default settings.
		tutorial:forceInteractionAtStartup(true) makes the intro wait for the open gesture: it shows
		interactionPrompt in place of the navigation bar and no button does anything until the gesture is done.
		Doing the gesture, in the intro or to open the tutorial, is remembered so the intro never waits again.

	Files are relative to the UEVR profile's data folder:
		<path>intro.png              - optional page shown before the steps
		<path>1.png .. <path>n.png   - the steps. n ends an unbroken run of numbers starting at 1
		<buttonPath>btn_<BUTTON>.png - button icons, for example btn_A.png, btn_RB.png, btn_LT.png
	Button names are A, B, X, Y, LB, RB, LT, RT, LS, RS, DPAD_UP, DPAD_DOWN, DPAD_LEFT, DPAD_RIGHT, START and BACK.
	A button without an icon file is shown as its name in brackets before the label.

	Navigation
		Each page has a navigation list. The list for a step number is used first, then the list for its page kind:
			intro  - the intro page
			first  - step 1 of several
			middle - steps between the first and the last
			last   - the last of several steps
			single - the only step
		Defaults (tutorial.DEFAULT_NAVIGATION):
			intro  = { { action = "hideAtStartup", align = "left" },
			           { action = "close", align = "right" }, { action = "start", align = "right" } }
			first  = { "close", "next" }
			middle = { "close", "back", "next" }
			last   = { "close", "back" }
			single = { "close" }
		An entry is an action name, or a table { action, button, label, hidden, align, icon }:
			action - "start", "next", "back", "skip", "close", "done", "hideAtStartup", or function(tutorial) for a
			         custom action
			button - button name. Defaults to buttons[action]
			label  - text after the icon. Defaults to labels[action]
			hidden - true keeps the button working without showing it in the navigation bar
			align  - "left", "center" or "right". Entries are grouped at the left edge, the middle or the right edge
			         of the bar, in list order. Default "center"
			icon   - icon file in buttonPath, or function(tutorial, entry) returning one, or nil for btn_<BUTTON>.png
		Actions:
			start         - go to the saved step (see rememberPage), or step 1
			next          - go to the next step, or close with "done" on the last step
			back          - go to the previous step, or to the intro from step 1
			skip          - close with reason "skipped"
			close         - close with reason "closed", or "done" on the last step
			done          - close with reason "done" and remember the tutorial as completed
			hideAtStartup - toggles the remembered completion, so showOnce skips the tutorial. Its icon is checkedIcon
			                while set and uncheckedIcon (or the button) while not
		Default buttons (tutorial.DEFAULT_BUTTONS): start = A, skip = B, next = RB, back = LB, close = B, done = A,
			hideAtStartup = Y
		Default labels (tutorial.DEFAULT_LABELS): Start, Skip, Next, Back, Close, Done, Hide at startup
		options.buttons and options.labels replace single entries of those tables. options.navigation replaces the
		lists for the page kinds and step numbers it contains.
        example:
            local help = tutorial.new({
                buttons = { next = "A", back = "X" },
                labels = { done = "Got it" },
                navigation = {
                    [3] = { "back", { action = "next", label = "Try it" }, "close" },
                    last = { "back", "done" },
                },
                onComplete = function(t) print("Tutorial finished") end,
            })

	Available functions:

    tutorial.new((optional)options) - creates a tutorial. Every option is optional:
		id                     - this tutorial's entry in tutorial_state.json, which holds { completed, interactionDone,
		                         page }. Default path without its trailing slash
		path                   - folder of the page images. Default "tutorial/"
		buttonPath             - folder of the button icons. Default path .. "buttons/"
		intro                  - "auto" shows intro.png when it exists, true always tries it, false never shows it.
		                         Default "auto"
		count                  - number of steps. Default: counted from the files in path with fs.glob
		imageSize              - longest side of the page image in slate units. Default 1100
		iconSize               - button icon size. Default 36
		fontSize               - label font size. Default 18
		textColor              - label color, "#RRGGBB" or "#RRGGBBAA". Default "#FFFFFFFF"
		font, typeface         - label font, see widgetModule text:setFont. Default the game's default font
		backgroundColor        - color of the panel behind the image and navigation bar, or false for none.
		                         Default "#000000C0"
		padding                - space between the panel edge and its contents. Default 24
		showPageCounter        - shows "step / count" at the right of the navigation bar. Default true
		checkedIcon            - hideAtStartup icon while set. Default "status_success.png"
		uncheckedIcon          - hideAtStartup icon while not set. Default nil, the button icon
		openGesture            - name in gestures.Gesture of the gesture that opens the tutorial, or false for none.
		                         Default "EYESCRATCH"
		openGestureHand        - hand that does it. Default Handed.Left
		openGestureCondition   - function(tutorial) returning false while the open gesture must not open the tutorial
		                         (the trigger pull then reaches the game and other scripts as usual). Asked only once
		                         the gesture is detected. Default nil, always allowed. (Hellraiser addition)
		openGestureDetector    - function(state, hand) returning true while the open gesture is being done, used
		                         instead of gestures.detectGestureWithState(openGesture, ...). Default nil.
		                         (Stalker 2 addition: libs/gestures reads mod-spawned controller components, which
		                         do not exist without a pawn, e.g. in the main menu)
		openGesturePage        - page it opens when no step is saved. Default 1, skipping the intro
		interactionPrompt      - text the waiting intro shows. Default "Try the gesture now"
		interactionColor       - its color. Default "#4ADE80FF"
		rememberPage           - saves the current step in tutorial_state.json. The open gesture and Start continue
		                         from it. Finishing the tutorial clears it. Default true
		zOrder                 - viewport z order. Default 100
		buttons, labels, navigation - see Navigation
		blockAllInput          - true hides every button, trigger and stick from the game while open. false hides only
		                         the buttons in the current navigation list. Default true
		triggerThreshold       - LT/RT value (0-255) that counts as pressed. Default 100
		pauseGame              - pauses the game while open. Default false
		lockView               - sets the ui module's viewLocked state while open. Default true
		disableControllerMouse - turns the ui module's controllerMouse state off while open. Default true
		lockViewPriority       - priority of the ui states above. Default 100
		preloadNext            - imports the next page's image shortly after a page is shown. Default true
		reopenAfterLevelChange - shows the same page again after a level change. Default false
		reopenDelay            - milliseconds after the level change before reopening. Default 1000
		onOpen(tutorial), onPageChanged(tutorial, page), onClose(tutorial, reason), onComplete(tutorial)
		                       - page is 0 for the intro. reason is "done", "skipped", "closed" or "level_change"

    tutorial:show((optional)page) - opens at page (0 is the intro). Defaults to the intro when it is shown,
		otherwise step 1. An open tutorial goes to page. Returns false when there is nothing to show or no host
		widget could be created. Called before the first level is detected, for example while scripts load, it
		returns true and opens the tutorial once the level is known.
    tutorial:showOnce((optional)page) - show() unless the tutorial has been completed. Returns true when it opened.
    tutorial:close((optional)reason) - closes the tutorial. reason defaults to "closed".
    tutorial:next(), tutorial:back(), tutorial:goTo(page) - navigate an open tutorial.
    tutorial:runAction(action) - runs a navigation action name or function.
    tutorial:isOpen() - true while the tutorial is showing.
    tutorial:getPage() - current page (0 for the intro), or nil when closed.
    tutorial:getCount() - number of steps. The files are counted on first use.
    tutorial:refresh() - counts the files again and drops imported images. Use after changing the files.
    tutorial:isCompleted() - true once the tutorial has closed with "done".
    tutorial:resetCompleted() - forgets completion so showOnce shows it again.
    tutorial:forceInteractionAtStartup(value) - when true, the intro waits for the open gesture until it has been
		done once. See Open gesture.
    tutorial:isAwaitingInteraction() - true while the intro is waiting for the open gesture.
    tutorial:completeInteraction() - remembers the open gesture as done and shows the normal intro bar.
    tutorial:resetInteraction() - forgets it, so a forced intro waits again.
    tutorial:getSavedPage() - the saved step, or nil.
    tutorial:resetSavedPage() - forgets the saved step.

    tutorial.closeAll() - closes every open tutorial.

    tutorial.setLogLevel(val) - sets the logging level for tutorial messages
        example:
            tutorial.setLogLevel(LogLevel.Debug)

    tutorial.print(text, (optional)logLevel) - prints a message at the given (or Debug) log level
]]--

local uevrUtils = require('libs/uevr_utils')
local widgetModule = require('libs/widget')
-- Loaded with the lib, not on first use: UEVR resolves the profile's scripts folder only while scripts load, so a
-- require from a tick or input callback searches the game's Binaries folder and fails (Cronos: "module 'libs/ui' not
-- found" on the first show; Hellraiser never hit it because menus.lua had loaded ui.lua at startup)
local ui = require('libs/ui')

local M = {}

local currentLogLevel = LogLevel.Error
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
	if logLevel == nil then logLevel = LogLevel.Debug end
	if logLevel <= currentLogLevel then
		uevrUtils.print("[tutorial] " .. text, logLevel)
	end
end

-- Open tutorials read raw input before every other handler and clear it again after every other handler
local CAPTURE_PRIORITY = 100000
local SUPPRESS_PRIORITY = -100000
-- The open gesture is read just before open tutorials hide the controller
local GESTURE_PRIORITY = CAPTURE_PRIORITY + 1
-- A trigger held when a tutorial closes stays hidden until it falls below this
local TRIGGER_RELEASE_THRESHOLD = 30
local PRELOAD_DELAY_MS = 100
local NAV_GAP = 16
local ICON_LABEL_GAP = 8
local ITEM_GAP = 40
local stateFileName = "tutorial_state"
-- Hellraiser: libs/ui.lua keeps one custom state entry per owner, so closing the tutorial clears only its own
-- viewLocked and not one a menu script still wants (ui libs without owners ignore the extra argument)
local UI_OWNER = "tutorial"

-- LT and RT use bits above the 16 XInput button bits
local LT_BIT = 0x10000
local RT_BIT = 0x20000
local BUTTON_MASKS = {
	DPAD_UP = XINPUT_GAMEPAD_DPAD_UP or 0x0001,
	DPAD_DOWN = XINPUT_GAMEPAD_DPAD_DOWN or 0x0002,
	DPAD_LEFT = XINPUT_GAMEPAD_DPAD_LEFT or 0x0004,
	DPAD_RIGHT = XINPUT_GAMEPAD_DPAD_RIGHT or 0x0008,
	START = XINPUT_GAMEPAD_START or 0x0010,
	BACK = XINPUT_GAMEPAD_BACK or 0x0020,
	LS = XINPUT_GAMEPAD_LEFT_THUMB or 0x0040,
	RS = XINPUT_GAMEPAD_RIGHT_THUMB or 0x0080,
	LB = XINPUT_GAMEPAD_LEFT_SHOULDER or 0x0100,
	RB = XINPUT_GAMEPAD_RIGHT_SHOULDER or 0x0200,
	A = XINPUT_GAMEPAD_A or 0x1000,
	B = XINPUT_GAMEPAD_B or 0x2000,
	X = XINPUT_GAMEPAD_X or 0x4000,
	Y = XINPUT_GAMEPAD_Y or 0x8000,
	LT = LT_BIT,
	RT = RT_BIT,
}

M.DEFAULT_BUTTONS = { start = "A", skip = "B", next = "RB", back = "LB", close = "B", done = "A", hideAtStartup = "Y" }
M.DEFAULT_LABELS = {
	start = "Start", skip = "Skip", next = "Next", back = "Back", close = "Close", done = "Done",
	hideAtStartup = "Hide at startup",
}
M.DEFAULT_NAVIGATION = {
	intro = {
		{ action = "hideAtStartup", align = "left" },
		{ action = "close", align = "right" },
		{ action = "start", align = "right" },
	},
	first = { "close", "next" },
	middle = { "close", "back", "next" },
	last = { "close", "back" },
	single = { "close" },
}

local DEFAULT_OPTIONS = {
	path = "tutorial/",
	intro = "auto",
	imageSize = 1100,
	iconSize = 36,
	fontSize = 18,
	textColor = "#FFFFFFFF",
	backgroundColor = "#000000C0",
	padding = 24,
	showPageCounter = true,
	checkedIcon = "status_success.png",
	openGesture = "EYESCRATCH",
	openGestureHand = Handed.Left,
	openGesturePage = 1,
	interactionPrompt = "Try the gesture now",
	interactionColor = "#4ADE80FF",
	rememberPage = true,
	zOrder = 100,
	blockAllInput = true,
	triggerThreshold = 100,
	pauseGame = false,
	lockView = true,
	lockViewPriority = 100,
	disableControllerMouse = true,
	preloadNext = true,
	reopenAfterLevelChange = false,
	reopenDelay = 1000,
}

local openTutorials = {}    -- in show order. The last one receives input
local reopenTutorials = {}  -- closed by a level change, shown again after it
local releaseMask = 0       -- buttons held when a tutorial closed, hidden until released
local pendingTutorial = nil -- input queues one action for the next engine tick
local pendingAction = nil
local pendingGesture = nil  -- tutorial whose open gesture was done, handled on the next engine tick
local gestureHand = nil     -- hand whose trigger stays hidden until released after the gesture
local gestureTutorials = {} -- tutorials with an open gesture
local gestures = require('libs/gestures') -- with the lib, see ui above
local stateData = nil -- tutorial_state.json: { [id] = { completed, interactionDone, page } }
-- uevr_utils reports the first level after a script reset as a level change, and widgets made before it are
-- destroyed, so tutorials shown before then wait for it
local levelReady = false
local deferredTutorials = {}

local function copyTable(source, overrides)
	local result = {}
	for key, value in pairs(source) do result[key] = value end
	if overrides ~= nil then
		for key, value in pairs(overrides) do result[key] = value end
	end
	return result
end

local function loadState()
	if stateData == nil then
		stateData = json.load_file(stateFileName .. ".json") or {}
	end
	return stateData
end

local function saveState()
	json.dump_file(stateFileName .. ".json", stateData or {}, 4)
end

-- This tutorial's saved fields
local function getState(self)
	local data = loadState()
	local state = data[self.id]
	if type(state) ~= "table" then
		state = {}
		data[self.id] = state
	end
	return state
end

local function setStateField(self, key, value)
	local state = getState(self)
	if state[key] == value then return end
	state[key] = value
	saveState()
end

-- Returns the step count, whether intro.png exists and the step file names, or nil without fs.glob
local function scanFiles(path)
	local files = uevrUtils.getFiles(path, "png")
	if files == nil then
		M.print("fs.glob is unavailable, pass options.count to set the number of steps", LogLevel.Warning)
		return nil, nil, nil
	end
	local stepFiles = {}
	local highest = 0
	local hasIntro = false
	for _, file in ipairs(files) do
		local name = file:match("([^\\/]+)$") or file
		local digits = name:lower():match("^(%d+)%.png$")
		if digits ~= nil then
			local step = tonumber(digits) or 0
			stepFiles[step] = name
			if step > highest then highest = step end
		elseif name:lower() == "intro.png" then
			hasIntro = true
		end
	end
	local count = 0
	while stepFiles[count + 1] ~= nil do count = count + 1 end
	if highest > count then
		M.print("Step " .. (count + 1) .. " is missing in " .. path .. ", later steps are ignored", LogLevel.Warning)
	end
	M.print("Found " .. count .. " steps in " .. path .. (hasIntro and " with an intro" or ""))
	return count, hasIntro, stepFiles
end

-- Imported textures are not rooted, so ones that are not on screen can be garbage collected and imported again.
-- getValid still passes when a later import (another page) reuses a collected texture's address, so the cache
-- keeps each texture's full name and imports the file again when it no longer matches
local function getTexture(cache, fileName, path)
	local entry = cache[fileName]
	---@type any
	local texture = entry ~= nil and entry.texture or nil
	if entry == nil or uevrUtils.getValid(texture) == nil or texture.Blueprint_GetSizeX == nil or texture:get_full_name() ~= entry.fullName then
		texture = widgetModule.loadTexture(fileName, path)
		cache[fileName] = texture ~= nil and { texture = texture, fullName = texture:get_full_name() } or nil
	end
	return texture
end

local function readHeld(gamepad, threshold)
	local held = gamepad.wButtons
	if gamepad.bLeftTrigger > threshold then held = held | LT_BIT end
	if gamepad.bRightTrigger > threshold then held = held | RT_BIT end
	return held
end

local function clearInput(gamepad, mask, all)
	if all then
		gamepad.wButtons = 0
		gamepad.bLeftTrigger = 0
		gamepad.bRightTrigger = 0
		gamepad.sThumbLX = 0
		gamepad.sThumbLY = 0
		gamepad.sThumbRX = 0
		gamepad.sThumbRY = 0
		return
	end
	if mask == 0 then return end
	gamepad.wButtons = gamepad.wButtons & ~(mask & 0xFFFF)
	if mask & LT_BIT ~= 0 then gamepad.bLeftTrigger = 0 end
	if mask & RT_BIT ~= 0 then gamepad.bRightTrigger = 0 end
end

local Tutorial = {}
Tutorial.__index = Tutorial
M.Tutorial = Tutorial

local function newLabel(options)
	local label = widgetModule.Text.new("")
	label:setColor(options.textColor)
	label:setFontSize(options.fontSize)
	if options.font ~= nil or options.typeface ~= nil then
		label:setFont(options.font, options.typeface)
	end
	return label
end

function M.new(options)
	options = options or {}
	local self = setmetatable({}, Tutorial)
	local o = copyTable(DEFAULT_OPTIONS, options)
	o.buttonPath = options.buttonPath or (o.path .. "buttons/")
	self.options = o
	self.path = o.path
	self.id = o.id or (o.path:gsub("/+$", ""))
	self.buttons = copyTable(M.DEFAULT_BUTTONS, options.buttons)
	self.labels = copyTable(M.DEFAULT_LABELS, options.labels)
	self.navigation = copyTable(M.DEFAULT_NAVIGATION, options.navigation)
	self.scanned = false
	self.count = 0
	self.hasIntro = false
	self.stepFiles = {}
	self.textures = {}
	self.icons = {}
	self.navItems = {}
	self.entries = {}
	self.inputMask = 0
	self.host = nil
	self.page = nil
	self.heldMask = nil
	self.image = widgetModule.Image.new(o.imageSize)
	if o.backgroundColor then
		self.backdrop = widgetModule.Image.new(1)
		self.backdrop:setColor(o.backgroundColor)
	end
	if o.showPageCounter then
		self.counter = newLabel(o)
	end
	if o.openGesture then
		self.prompt = newLabel(o)
		self.prompt:setColor(o.interactionColor)
		self.prompt:setText(o.interactionPrompt)
		table.insert(gestureTutorials, self)
	end
	return self
end

local function ensureScanned(self)
	if self.scanned then return end
	self.scanned = true
	local count, hasIntro, stepFiles = scanFiles(self.path)
	self.stepFiles = stepFiles or {}
	self.count = self.options.count or count or 0
	local intro = self.options.intro
	if intro == false then
		self.hasIntro = false
	elseif intro == true or hasIntro == nil then
		-- without fs.glob, "auto" finds out by importing intro.png
		self.hasIntro = true
	else
		self.hasIntro = hasIntro
	end
end

local function pageFile(self, page)
	if page == 0 then return "intro.png" end
	return self.stepFiles[page] or (page .. ".png")
end

local function pageKind(self, page)
	if page == 0 then return "intro" end
	if self.count == 1 then return "single" end
	if page == 1 then return "first" end
	if page == self.count then return "last" end
	return "middle"
end

local function resolveEntries(self, page)
	local list = nil
	if page > 0 then list = self.navigation[page] end
	if list == nil then list = self.navigation[pageKind(self, page)] end
	local entries = {}
	local inputMask = 0
	for _, item in ipairs(list or {}) do
		local entry = type(item) == "table" and item or { action = item }
		local action = entry.action
		local button = entry.button or (type(action) == "string" and self.buttons[action] or nil)
		button = type(button) == "string" and button:upper() or nil
		local mask = button ~= nil and BUTTON_MASKS[button] or nil
		if mask == nil then
			M.print("Navigation entry " .. tostring(action) .. " has no valid button (" .. tostring(button) .. ")", LogLevel.Warning)
		else
			table.insert(entries, {
				action = action,
				button = button,
				mask = mask,
				label = entry.label or (type(action) == "string" and self.labels[action]) or "",
				hidden = entry.hidden == true,
				align = (entry.align == "left" or entry.align == "right") and entry.align or "center",
				icon = entry.icon,
			})
			inputMask = inputMask | mask
		end
	end
	return entries, inputMask
end

-- Sets the icon and label of each shown entry and returns the items to lay out
local function updateNavigation(self)
	local o = self.options
	local shown = {}
	for _, entry in ipairs(self.entries) do
		if not entry.hidden then
			local index = #shown + 1
			local item = self.navItems[index]
			if item == nil then
				item = { icon = widgetModule.Image.new(o.iconSize), label = newLabel(o) }
				self.navItems[index] = item
			end
			local text = entry.label
			-- drawn at the texture's own size, then scaled down to iconSize with a render scale
			local iconFile = entry.icon
			if type(iconFile) == "function" then iconFile = iconFile(self, entry) end
			if iconFile == nil and entry.action == "hideAtStartup" then
				iconFile = self:isCompleted() and o.checkedIcon or o.uncheckedIcon
			end
			local texture = getTexture(self.icons, iconFile or ("btn_" .. entry.button .. ".png"), o.buttonPath)
			if texture ~= nil then
				item.icon.maxDim = math.max(texture:Blueprint_GetSizeX(), texture:Blueprint_GetSizeY(), 1)
			end
			item.hasIcon = item.icon:setTextureObject(texture)
			if item.hasIcon then
				item.icon:setRenderScale(o.iconSize / item.icon.maxDim)
			end
			item.icon:setVisible(item.hasIcon)
			if not item.hasIcon then
				text = "[" .. entry.button .. "]" .. (text ~= "" and (" " .. text) or "")
			end
			if item.text ~= text then
				item.label:setText(text)
				item.text = text
			end
			item.label:setVisible(text ~= "")
			item.align = entry.align
			shown[index] = item
		end
	end
	for i = #shown + 1, #self.navItems do
		self.navItems[i].icon:setVisible(false)
		self.navItems[i].label:setVisible(false)
	end
	return shown
end

local function measureText(label, text, fontSize)
	local size = label:getDesiredSize()
	if size ~= nil and size.X ~= nil and size.X > 0 then return size.X end
	-- rough width when slate has not measured the text
	return #text * fontSize * 0.55
end

-- Centers the image and navigation bar on screen with the backdrop behind them
local function layoutPage(self, shown)
	local o = self.options
	local host = self.host
	local center = widgetModule.Image.ALIGN.CENTER
	local imageW, imageH = self.image.drawSize.X, self.image.drawSize.Y

	-- items are grouped at the left edge, the middle and the right edge of the bar
	local groups = { left = { width = 0 }, center = { width = 0 }, right = { width = 0 } }
	for _, item in ipairs(shown) do
		local width = item.hasIcon and o.iconSize or 0
		item.labelX = nil
		if item.text ~= "" then
			item.label:addToWidget(host, { align = center, zOrder = 2 })
			if item.hasIcon then width = width + ICON_LABEL_GAP end
			item.labelX = width
			width = width + measureText(item.label, item.text, o.fontSize)
		end
		item.width = width
		local group = groups[item.align] or groups.center
		group.width = group.width + (#group > 0 and ITEM_GAP or 0) + width
		table.insert(group, item)
	end
	local rowW, groupCount = 0, 0
	for _, group in pairs(groups) do
		if #group > 0 then
			rowW = rowW + group.width
			groupCount = groupCount + 1
		end
	end
	local barW = math.max(imageW, rowW + math.max(groupCount - 1, 0) * ITEM_GAP)

	local navH = math.max(o.iconSize, o.fontSize * 1.5)
	local totalH = imageH + NAV_GAP + navH
	local top = -totalH / 2
	local navY = top + imageH + NAV_GAP + navH / 2
	local leftCenter = uevrUtils.vector2D(0, 0.5)

	self.image:addToWidget(host, { align = center, alignment = uevrUtils.vector2D(0.5, 0), offset = uevrUtils.vector2D(0, top), zOrder = 1 })

	local function placeGroup(group, x)
		for _, item in ipairs(group) do
			if item.hasIcon then
				-- the render scale shrinks the icon about its center, so place it by its center
				item.icon:addToWidget(host, { align = center, offset = uevrUtils.vector2D(x + o.iconSize / 2, navY), zOrder = 2 })
			end
			if item.labelX ~= nil then
				item.label:setLayout({ align = center, alignment = leftCenter, offset = uevrUtils.vector2D(x + item.labelX, navY), zOrder = 2 })
			end
			x = x + item.width + ITEM_GAP
		end
	end
	placeGroup(groups.left, -barW / 2)
	placeGroup(groups.center, -groups.center.width / 2)
	placeGroup(groups.right, barW / 2 - groups.right.width)

	if self.counter ~= nil then
		self.counter:setVisible(self.page > 0)
		if self.page > 0 then
			-- right edge of the bar, left of any right aligned items
			local counterX = barW / 2 - (#groups.right > 0 and (groups.right.width + ITEM_GAP) or 0)
			self.counter:setText(self.page .. " / " .. self.count)
			self.counter:addToWidget(host, { align = center, alignment = uevrUtils.vector2D(1, 0.5), offset = uevrUtils.vector2D(counterX, navY), zOrder = 2 })
		end
	end

	if self.prompt ~= nil then
		local awaiting = self:isAwaitingInteraction()
		self.prompt:setVisible(awaiting)
		if awaiting then
			self.prompt:addToWidget(host, { align = center, offset = uevrUtils.vector2D(0, navY), zOrder = 2 })
			barW = math.max(barW, measureText(self.prompt, o.interactionPrompt, o.fontSize))
		end
	end

	if self.backdrop ~= nil then
		self.backdrop:setSize(uevrUtils.vector2D(barW + o.padding * 2, totalH + o.padding * 2))
		self.backdrop:addToWidget(host, { align = center, zOrder = 0 })
	end
end

function Tutorial:isOpen()
	return self.host ~= nil
end

function Tutorial:getPage()
	return self.page
end

function Tutorial:getCount()
	ensureScanned(self)
	return self.count
end

function Tutorial:refresh()
	self.scanned = false
	self.textures = {}
	self.icons = {}
	ensureScanned(self)
end

local function setCompleted(self, completed)
	setStateField(self, "completed", completed or nil)
end

function Tutorial:isCompleted()
	return getState(self).completed == true
end

function Tutorial:resetCompleted()
	setCompleted(self, false)
end



function Tutorial:forceInteractionAtStartup(value)
	self.forceInteraction = value ~= false
end

function Tutorial:isAwaitingInteraction()
	return self.forceInteraction == true and self.prompt ~= nil and self.host ~= nil and self.page == 0
		and getState(self).interactionDone ~= true
end

-- An intro waiting for the open gesture shows the prompt in place of the navigation bar, and no button works
local function refreshNavigation(self)
	if self:isAwaitingInteraction() then
		self.entries, self.inputMask = {}, 0
	else
		self.entries, self.inputMask = resolveEntries(self, self.page)
	end
	layoutPage(self, updateNavigation(self))
end

function Tutorial:completeInteraction()
	local wasAwaiting = self:isAwaitingInteraction()
	setStateField(self, "interactionDone", true)
	if wasAwaiting then refreshNavigation(self) end
end

function Tutorial:resetInteraction()
	setStateField(self, "interactionDone", nil)
end

function Tutorial:getSavedPage()
	local page = getState(self).page
	if type(page) == "number" and page >= 1 then return page end
	return nil
end

function Tutorial:resetSavedPage()
	setStateField(self, "page", nil)
end

-- The saved step when rememberPage is on, otherwise defaultPage
local function resumePage(self, defaultPage)
	if self.options.rememberPage then
		return self:getSavedPage() or defaultPage
	end
	return defaultPage
end

function Tutorial:goTo(page)
	if self.host == nil or page == nil then return false end
	local firstPage = self.hasIntro and 0 or 1
	if page < firstPage then page = firstPage end
	if page > self.count then page = self.count end

	local texture = getTexture(self.textures, pageFile(self, page), self.path)
	if texture == nil and page == 0 then
		M.print("No intro.png in " .. self.path, self.options.intro == true and LogLevel.Warning or LogLevel.Debug)
		self.hasIntro = false
		if self.count < 1 then
			self:close("closed")
			return false
		end
		page = 1
		texture = getTexture(self.textures, pageFile(self, page), self.path)
	end
	if self.image:setTextureObject(texture) then
		self.image:setVisible(true)
	else
		M.print("Could not import " .. self.path .. pageFile(self, page), LogLevel.Warning)
		self.image:setVisible(false)
	end

	self.page = page
	if self.options.rememberPage and page > 0 then
		setStateField(self, "page", page)
	end
	refreshNavigation(self)

	if self.options.onPageChanged ~= nil then
		self.options.onPageChanged(self, page)
	end
	if self.options.preloadNext and page < self.count and self.page == page then
		uevrUtils.delay(PRELOAD_DELAY_MS, function()
			if self.host ~= nil and self.page == page then
				getTexture(self.textures, pageFile(self, page + 1), self.path)
			end
		end)
	end
	return true
end

function Tutorial:next()
	if self.host == nil then return end
	if self.page >= self.count then
		self:close("done")
	else
		self:goTo(self.page + 1)
	end
end

function Tutorial:back()
	if self.host == nil then return end
	if self.page > (self.hasIntro and 0 or 1) then
		self:goTo(self.page - 1)
	end
end

function Tutorial:runAction(action)
	if type(action) == "function" then
		action(self)
	elseif action == "start" then
		self:goTo(resumePage(self, 1))
	elseif action == "next" then
		self:next()
	elseif action == "back" then
		self:back()
	elseif action == "skip" then
		self:close("skipped")
	elseif action == "close" then
		self:close(self.page ~= nil and self.page > 0 and self.page >= self.count and "done" or "closed")
	elseif action == "done" then
		self:close("done")
	elseif action == "hideAtStartup" then
		setCompleted(self, not self:isCompleted())
		-- redraw the bar so the icon shows the new state
		refreshNavigation(self)
	else
		M.print("Unknown action " .. tostring(action), LogLevel.Warning)
	end
end

function Tutorial:show(page)
	ensureScanned(self)
	if self.count < 1 and not self.hasIntro then
		M.print("No tutorial images found in " .. self.path, LogLevel.Warning)
		return false
	end
	if not levelReady then
		self.deferredPage = page
		if not self.deferred then
			self.deferred = true
			table.insert(deferredTutorials, self)
		end
		return true
	end
	if page == nil then page = self.hasIntro and 0 or 1 end
	if self.host ~= nil then return self:goTo(page) end

	local host = widgetModule.createHostWidget()
	if host == nil then
		M.print("No host widget available for the tutorial", LogLevel.Warning)
		return false
	end
	host:AddToViewport(self.options.zOrder)
	self.host = host
	if ui == nil then ui = require('libs/ui') end
	-- the host borrows a game widget class, so keep ui from treating it as that game widget
	ui.ignoreWidget(host)
	if self.options.lockView then
		ui.setCustomState("viewLocked", true, self.options.lockViewPriority, UI_OWNER)
		self.lockedView = true
	end
	if self.options.disableControllerMouse then
		ui.setCustomState("controllerMouse", false, self.options.lockViewPriority, UI_OWNER)
		self.disabledControllerMouse = true
	end
	self.heldMask = nil
	table.insert(openTutorials, self)

	if self.options.pauseGame and Statics ~= nil and not Statics:IsGamePaused(uevrUtils.get_world()) then
		Statics:SetGamePaused(uevrUtils.get_world(), true)
		self.pausedGame = true
	end
	if self.options.onOpen ~= nil then
		self.options.onOpen(self)
	end
	return self:goTo(page)
end

function Tutorial:showOnce(page)
	if self:isCompleted() then return false end
	return self:show(page)
end

-- Removes the widgets and stops input handling without running callbacks
local function teardown(self)
	for i = #openTutorials, 1, -1 do
		if openTutorials[i] == self then table.remove(openTutorials, i) end
	end
	if self.heldMask ~= nil then
		releaseMask = releaseMask | self.heldMask
	end
	self.heldMask = nil
	if pendingTutorial == self then
		pendingTutorial, pendingAction = nil, nil
	end
	if self.pausedGame then
		if Statics ~= nil then Statics:SetGamePaused(uevrUtils.get_world(), false) end
		self.pausedGame = false
	end
	if self.lockedView and ui ~= nil then
		ui.setCustomState("viewLocked", nil, nil, UI_OWNER)
		self.lockedView = false
	end
	if self.disabledControllerMouse and ui ~= nil then
		ui.setCustomState("controllerMouse", nil, nil, UI_OWNER)
		self.disabledControllerMouse = false
	end

	self.image:remove()
	if self.backdrop ~= nil then self.backdrop:remove() end
	if self.counter ~= nil then self.counter:remove() end
	if self.prompt ~= nil then self.prompt:remove() end
	for _, item in ipairs(self.navItems) do
		item.icon:remove()
		item.label:remove()
	end
	if ui ~= nil and self.host ~= nil then
		ui.unignoreWidget(self.host)
	end
	if uevrUtils.getValid(self.host) ~= nil then
		self.host:RemoveFromParent()
	end
	self.host = nil
	self.page = nil
	self.entries = {}
	self.inputMask = 0
	self.textures = {}
	self.icons = {}
end

function Tutorial:close(reason)
	self.deferred = false
	if self.host == nil then return end
	reason = reason or "closed"
	teardown(self)
	M.print("Closed " .. self.id .. " (" .. reason .. ")")
	if reason == "done" then
		setCompleted(self, true)
		if self.options.rememberPage then self:resetSavedPage() end
	end
	if self.options.onClose ~= nil then
		self.options.onClose(self, reason)
	end
	if reason == "done" and self.options.onComplete ~= nil then
		self.options.onComplete(self)
	end
end

function M.closeAll()
	for i = #openTutorials, 1, -1 do
		openTutorials[i]:close("closed")
	end
end

-- Only XInput slot 0 carries the VR controllers. A game that also polls slots 1-3 gets released pads there, and
-- reading those would make every held button look newly pressed on the next slot-0 call (Cronos addition; newer
-- uevr_utils.lua filters this in its dispatcher already)
local function isVRSlot(userIndex)
	return userIndex == nil or userIndex == 0
end

-- Input is read before every other handler. Buttons held when a page opens do not count as presses
local function captureInput(retval, userIndex, state)
	if not isVRSlot(userIndex) then return end
	local tutorial = openTutorials[#openTutorials]
	if tutorial == nil and releaseMask == 0 then return end
	local gamepad = state.Gamepad
	if releaseMask ~= 0 then
		releaseMask = releaseMask & readHeld(gamepad, TRIGGER_RELEASE_THRESHOLD)
		clearInput(gamepad, releaseMask, false)
	end
	if tutorial == nil then return end

	local held = readHeld(gamepad, tutorial.options.triggerThreshold)
	local pressed = tutorial.heldMask ~= nil and (held & ~tutorial.heldMask) or 0
	tutorial.heldMask = held
	clearInput(gamepad, tutorial.inputMask, tutorial.options.blockAllInput)

	if pressed ~= 0 and pendingTutorial == nil then
		for _, entry in ipairs(tutorial.entries) do
			if pressed & entry.mask ~= 0 then
				pendingTutorial, pendingAction = tutorial, entry.action
				return
			end
		end
	end
end

-- Detects the open gesture for closed tutorials and for an intro waiting for it. Runs before captureInput, which
-- hides the controller from everything after it while a tutorial is open
local function captureGesture(retval, userIndex, state)
	if not isVRSlot(userIndex) then return end
	local gamepad = state.Gamepad
	if gestureHand ~= nil then
		local isLeft = gestureHand == Handed.Left
		if (isLeft and gamepad.bLeftTrigger or gamepad.bRightTrigger) < TRIGGER_RELEASE_THRESHOLD then
			gestureHand = nil
		elseif isLeft then
			gamepad.bLeftTrigger = 0
		else
			gamepad.bRightTrigger = 0
		end
		return
	end
	if pendingGesture ~= nil then return end
	for _, tutorial in ipairs(gestureTutorials) do
		if tutorial.host == nil or tutorial:isAwaitingInteraction() then
			if gestures == nil then gestures = require('libs/gestures') end
			local id = gestures.Gesture[tutorial.options.openGesture]
			local hand = tutorial.options.openGestureHand
			local condition = tutorial.options.openGestureCondition
			local detector = tutorial.options.openGestureDetector
			local detected = false
			if detector ~= nil then
				detected = detector(state, hand) == true
			else
				detected = id ~= nil and gestures.detectGestureWithState(id, state, hand, true)
			end
			if detected and (tutorial.host ~= nil or condition == nil or condition(tutorial) ~= false) then
				gestureHand = hand
				if hand == Handed.Left then gamepad.bLeftTrigger = 0 else gamepad.bRightTrigger = 0 end
				pendingGesture = tutorial
				return
			end
		end
	end
end

-- Clears anything other handlers pressed while a tutorial is open
local function suppressInput(retval, userIndex, state)
	if not isVRSlot(userIndex) then return end
	local tutorial = openTutorials[#openTutorials]
	if tutorial == nil then
		if releaseMask ~= 0 then clearInput(state.Gamepad, releaseMask, false) end
		return
	end
	clearInput(state.Gamepad, tutorial.inputMask | releaseMask, tutorial.options.blockAllInput)
end

-- Widget changes run on the engine tick rather than inside the input callback
local function runPendingAction()
	if pendingGesture ~= nil then
		local tutorial = pendingGesture
		pendingGesture = nil
		if tutorial.host == nil then
			tutorial:completeInteraction()
			tutorial:show(resumePage(tutorial, tutorial.options.openGesturePage))
		else
			tutorial:completeInteraction()
		end
	end
	if pendingTutorial == nil then return end
	local tutorial, action = pendingTutorial, pendingAction
	pendingTutorial, pendingAction = nil, nil
	if tutorial.host ~= nil then
		tutorial:runAction(action)
	end
end

uevrUtils.registerOnPreInputGetStateCallback(captureGesture, GESTURE_PRIORITY)
uevrUtils.registerOnPreInputGetStateCallback(captureInput, CAPTURE_PRIORITY)
uevrUtils.registerOnPostInputGetStateCallback(suppressInput, SUPPRESS_PRIORITY)
uevrUtils.registerPreEngineTickCallback(runPendingAction)

uevrUtils.registerPreLevelChangeCallback(function()
	for i = #openTutorials, 1, -1 do
		local tutorial = openTutorials[i]
		if tutorial.options.reopenAfterLevelChange then
			tutorial.reopenPage = tutorial.page
			table.insert(reopenTutorials, tutorial)
			teardown(tutorial)
		else
			tutorial:close("level_change")
		end
	end
end)

uevrUtils.registerLevelChangeCallback(function()
	levelReady = true
	for _, tutorial in ipairs(deferredTutorials) do
		if tutorial.deferred then
			tutorial.deferred = false
			tutorial:show(tutorial.deferredPage)
		end
	end
	deferredTutorials = {}
	for _, tutorial in ipairs(reopenTutorials) do
		local page = tutorial.reopenPage
		tutorial.reopenPage = nil
		uevrUtils.delay(tutorial.options.reopenDelay, function()
			if tutorial.host == nil then tutorial:show(page) end
		end)
	end
	reopenTutorials = {}
end)

uevr.params.sdk.callbacks.on_script_reset(function()
	for i = #openTutorials, 1, -1 do
		teardown(openTutorials[i])
	end
	reopenTutorials = {}
	releaseMask = 0
end)

-- Nested timings are inclusive. Toggle and report with uevrUtils.profiler.
-- The input and tick callbacks stay unwrapped so idle frames are not profiled.
scanFiles = uevrUtils.profiler:wrap("Tutorial: scan files", scanFiles)
getTexture = uevrUtils.profiler:wrap("Tutorial: get texture", getTexture)
updateNavigation = uevrUtils.profiler:wrap("Tutorial: update navigation", updateNavigation)
layoutPage = uevrUtils.profiler:wrap("Tutorial: layout page", layoutPage)
teardown = uevrUtils.profiler:wrap("Tutorial: teardown", teardown)

Tutorial.show = uevrUtils.profiler:wrap("Tutorial: show", Tutorial.show)
Tutorial.goTo = uevrUtils.profiler:wrap("Tutorial: go to page", Tutorial.goTo)
Tutorial.close = uevrUtils.profiler:wrap("Tutorial: close", Tutorial.close)
Tutorial.runAction = uevrUtils.profiler:wrap("Tutorial: run action", Tutorial.runAction)

return M
