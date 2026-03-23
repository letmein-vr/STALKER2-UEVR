local uevrUtils = require('libs/uevr_utils')
local controllers = require('libs/controllers')
local configui = require('libs/configui')
local reticule = require('libs/reticule')
local hands = require('libs/hands')
local attachments = require('libs/attachments')
local input = require('libs/input')
local flickerFixer = require('libs/flicker_fixer')
local animation = require('libs/animation')
local montage = require('libs/montage')
local pawn = require('libs/pawn')
local ui = require('libs/ui')

local isDeveloperMode = true

montage.init(isDeveloperMode)
pawn.init(isDeveloperMode)