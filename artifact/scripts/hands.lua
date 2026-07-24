local uevrUtils = require('libs/uevr_utils')
local hands = require('libs/hands')
local controllers = require('libs/controllers')

function on_level_change(level)
	controllers.createController(0)
	controllers.createController(1)
	hands.reset()

	local paramsFile = 'hands_parameters' -- found in the [game profile]/data directory
	local configName = 'Main' -- the name you gave your config
	local animationName = 'Shared' -- the name you gave your animation
	hands.createFromConfig(paramsFile, configName, animationName)
end

-- NOTE: on_xinput_get_state intentionally removed from this wrapper.
-- Entry.lua's createInputHandler registers the correct weapon-aware xinput
-- callback (via uevrUtils.registerOnInputGetStateCallback with allowAutoHandle=true)
-- which handles right_grip_weapon_rhino etc. correctly.
-- Having a second on_xinput_get_state here calling hands.handleInput(state, false, ...)
-- permanently set autoHandleInput=false, disabling the correct handler entirely.