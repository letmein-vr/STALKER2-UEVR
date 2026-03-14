Config = {
	dominantHand = 1,
	sittingExperience = false,
	recoil = true,
	hapticFeedback = true,
	twoHandedAiming = true,
    -- Virtual Stock
    virtualGunstock = true,
    -- Compatibility CVars
    refractionEnabled = true,
    ssrQuality = 0, -- Default to 0 for DLSS compatibility
    waterReflections = true,
    waterRefraction = true,
    translucencyFix = false, -- r.Translucency.TemporalAA.Alpha
    swapXandB = false,
    lumenReflectionsTemporal = true,
    lumenDiffuseIndirect = true,
    antiAliasingMethod = 2, -- Default to TAA (2)
    temporalUpsampling = true, -- r.TemporalAA.Upsampling
    tsrEnabled = true, -- r.TSR.Enable
    -- Performance CVars
    postprocessingDisabled = false, -- r.postprocessing.disablematerials
    taaSmearingFixEnabled = true, -- VR edge smearing fix
    viewDistanceScale = 1.0, -- r.ViewDistanceScale
    volumetricClouds = true, -- r.VolumetricCloud
    volumetricFog = true,   -- r.VolumetricFog
    -- Eye Adaptation
    eyeAdaptationFixed = false,         -- r.EyeAdaptation.MethodOverride: false=-1 (auto), true=0 (fixed)
    eyeAdaptationIgnoreMaterials = false, -- r.EyeAdaptation.IgnoreMaterials 0/1
    lumenScreenProbeVisualize = false,  -- r.Lumen.ScreenProbeGather.VisualizeTraces 0/1
    -- Shadows
    distanceFieldShadowing = false,     -- r.DistanceFieldShadowing 0/1 (default OFF = better perf)
    globalDistanceField = false,         -- r.GlobalDistanceField 0/1 (default OFF)
    ssfsEnabled = false,                 -- r.SSFS 0/1 (default OFF)
    shadowQuality = 4,                   -- r.ShadowQuality (int) 0-4 (default high)
    dynamicGIMethod = 0,                 -- r.DynamicGlobalIlluminationMethod 0=none,1=SSGI,4=Lumen
    -- Vegetation & LOD
    grassCullScale = 0.5,               -- fg.CullDistanceScale.Grass 0.0-1.0
    foliageDensity = 0.3,               -- foliage.DensityScale 0.0-1.0
    foliageLODScale = 3.0,              -- foliage.LODDistanceScale 0.0-3.0
    rendererStabilizerEnabled = false, -- Fake Flashlight fix

    vrShadowsEnabled = false,
    cutscene2DModeEnabled = false,
    hideHUD = false,           -- VR_EnableGUI off when true
    interactiveADS = false,
    interactiveADSDistance = 30.0,

    -- Mag Collision / Physical Reloading
    magSocket1 = "jnt_magazine",
    magSocket2 = "jnt_mag_01",
    magScaleX = 0.05,
    magScaleY = 0.1,
    magScaleZ = 0.3,
    magLocalX = 0,
    magLocalY = 0,
    magLocalZ = 0,

    -- Holster variables
	scopeBrightnessAmplifier = 1.0,
	redDotBrightness = 150.0,
	scopeDiameter = 0.024,
	scopeMagnifier = 0.7,
	scopeTextureSize = 1024,
	cylinderDepth = 0.001,
	indoor = false,
	scopeActivationDistance = 15.0, -- Distance in cm to activate scope (bring to eye)
    scopeExpandingFOV = false,      -- When true: closer eye = wider scope view, constant magnification
    
    -- Red Dot Sight Settings
    redDotSize = 0.007,             -- Scale of the red dot sphere
    redDotOffsetX = 0.0,
    redDotOffsetY = 0.0,
    redDotOffsetZ = 0.0,
    redDotProfiles = {},
    
    -- Conversation Fix Settings
    enableConversationFix = true,
    conversationFOVThreshold = 80.0, -- Threshold below which we assume a conversation (zoomed camera) is active
    
    weaponSocketName = "S_Hand_R",
    weaponHandRotation = {0, 0, 0}, -- Pitch, Yaw, Roll
    weaponHandLocation = {0, 0, 0}, -- X, Y, Z
    reloadHandRotation = {-1.5, 0.6, -180.2}, -- Pitch, Yaw, Roll
    reloadHandLocation = {0, 0, 0}, -- X, Y, Z
    weaponProfiles = {}, -- Stores settings keyed by weapon name
    scopeProfiles = {}, -- Stores settings keyed by scope mesh name

	-- Gesture enable/disable settings
	gestures = {
		flashlight = true,
		primaryWeapon = true,
		secondaryWeapon = true,
		sidearmWeapon = true,
		meleeWeapon = true,
		boltAction = true,
		grenade = true,
		inventory = true,
		scanner = true,
		pda = true,
		reload = true,
		modeSwitch = true,
		nightVision = true,
		weaponCustomization = true  -- Left shoulder (left hand) + left grip = long press T
	},
    -- Weapon Mod Mesh Alignment (Silencer/Sight)
    weaponModMeshOffset = { X = 0.0, Y = 0.0, Z = 0.0 },
    weaponModMeshRotation = { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 },
    weaponModCleanupDelay = 1.0, -- Seconds to wait before cleaning up VR hand duplicate
    attachmentProfiles = {}, -- Stores per-attachment offsets keyed by clean mesh name
    -- Detector Settings
    detectorOffset = { X = -2.0, Y = 2.0, Z = -3.0 },
    detectorRotation = { Pitch = 0.0, Yaw = 0.0, Roll = 100.0 },
    detectorProfiles = {
        ["sk_detector"] = { offset = {X = -2.0, Y = 2.0, Z = -3.0}, rotation = {Pitch = 0.0, Yaw = 0.0, Roll = 100.0} },
        ["sk_detector_veles"] = { offset = {X = -2.0, Y = 2.0, Z = -3.0}, rotation = {Pitch = 0.0, Yaw = 0.0, Roll = 100.0} },
        ["sk_detector_echo"] = { offset = {X = -2.0, Y = 2.0, Z = -3.0}, rotation = {Pitch = 0.0, Yaw = 0.0, Roll = 100.0} },
        ["sk_detector_bear"] = { offset = {X = -2.0, Y = 2.0, Z = -3.0}, rotation = {Pitch = 0.0, Yaw = 0.0, Roll = 100.0} },
        ["sk_bpa_pla_01"] = { offset = {X = -2.0, Y = 2.0, Z = -3.0}, rotation = {Pitch = 0.0, Yaw = 0.0, Roll = 100.0} }, -- Bear plastic variant?
    }, -- Stores per-mesh offsets keyed by clean mesh name
    disableDetectorPose = false, -- Toggle to disable forced hand pose for configuration

    twoHandedHandPose = {
        ["jnt_l_hand_middle_01"] = {1.4002, 1.2588, -0.011},
        ["jnt_l_hand_middle_02"] = {0.0, 7.8976, 0.0},
        ["jnt_l_hand_middle_03"] = {0.0, -5.1589, 0.0},
        ["jnt_l_hand_pinky_01"] = {0.0, 5.9195, 0.0},
        ["jnt_l_hand_pinky_02"] = {0.0, -4.7578, 0.0},
        ["jnt_l_hand_pinky_03"] = {0.0, 1.363, 0.0},
        ["jnt_l_hand_ring_01"] = {2.5187, 2.5438, 0.0},
        ["jnt_l_hand_ring_02"] = {0.0, 5.8665, 0.0},
        ["jnt_l_hand_ring_03"] = {0.0, -2.6579, 0.0},
        ["jnt_l_hand_thumb_01"] = {-43.237, 6.3683, -64.8135},
        ["jnt_l_hand_thumb_02"] = {-1.2819, 11.8847, 5.6227},
        ["jnt_l_hand_thumb_03"] = {-5.1727, -19.5895, -0.1875},
        ["jnt_l_hand_index_01"] = {-1.1251, 32.2599, 0.0},
        ["jnt_l_hand_index_02"] = {0.0, 104.05, 0.0},
        ["jnt_l_hand_index_03"] = {0.0, 27.1369, 0.0}
    },
    twoHandedRifleHandPose = {
        ["jnt_l_hand_middle_01"] = {-2.3625, 45.3568, 17.9673},
        ["jnt_l_hand_middle_02"] = {-0.0062, 72.669, 0.0012},
        ["jnt_l_hand_middle_03"] = {0.0074, 29.25, 0.0008},
        ["jnt_l_hand_pinky_01"] = {-1.408, 65.0016, 11.9496},
        ["jnt_l_hand_pinky_02"] = {0.0015, 45.172, 0.0006},
        ["jnt_l_hand_pinky_03"] = {0.0, 16.52, 0.0},
        ["jnt_l_hand_ring_01"] = {-5.876, 64.2745, 13.9615},
        ["jnt_l_hand_ring_02"] = {-0.0062, 60.6228, -0.0011},
        ["jnt_l_hand_ring_03"] = {0.0075, 14.4739, 0.0006},
        ["jnt_l_hand_thumb_01"] = {-32.155, -29.7291, -55.6748},
        ["jnt_l_hand_thumb_02"] = {0.0, 19.138, 0.0},
        ["jnt_l_hand_thumb_03"] = {-0.0036, -14.3747, 0.0021},
        ["jnt_l_hand_index_01"] = {-8.9441, 39.484, 22.5675},
        ["jnt_l_hand_index_02"] = {-0.0013, 40.9039, 0.0061},
        ["jnt_l_hand_index_03"] = {0.0071, 61.8355, -0.0029}
    },
    reloadHandPose = {
        ["jnt_l_hand_middle_01"] = {4.775, 33.8838, -0.011},
        ["jnt_l_hand_middle_02"] = {0.0, 91.148, 0.0},
        ["jnt_l_hand_middle_03"] = {0.0, 26.9999, 1.1247},
        ["jnt_l_hand_pinky_01"] = {9.2749, 13.5, -6.7611},
        ["jnt_l_hand_pinky_02"] = {0.0, 91.148, 0.0},
        ["jnt_l_hand_pinky_03"] = {0.0, 26.9999, 1.1247},
        ["jnt_l_hand_ring_01"] = {9.2749, 33.8838, -0.011},
        ["jnt_l_hand_ring_02"] = {0.0, 91.148, 0.0},
        ["jnt_l_hand_ring_03"] = {0.0, 26.9999, 1.1247},
        ["jnt_l_hand_thumb_01"] = {-21.862, -22.882, -64.8135},
        ["jnt_l_hand_thumb_02"] = {-11.407, 29.885, 5.6227},
        ["jnt_l_hand_thumb_03"] = {-5.1727, 19.7849, -0.1875},
        ["jnt_l_hand_index_01"] = {1.1249, 14.26, 0.0},
        ["jnt_l_hand_index_02"] = {0.0, 81.55, 0.0},
        ["jnt_l_hand_index_03"] = {0.0, 27.1368, 0.0}
    },
    detectorHandPose = {
        ["jnt_l_hand_middle_01"] = {4.775, 0.8069, -0.011},
        ["jnt_l_hand_middle_02"] = {0.0, 62.9598, 0.0},
        ["jnt_l_hand_middle_03"] = {0.0, 66.552, 1.1246},
        ["jnt_l_hand_pinky_01"] = {4.775, 0.8069, -0.011},
        ["jnt_l_hand_pinky_02"] = {0.0, 62.9598, 0.0},
        ["jnt_l_hand_pinky_03"] = {0.0, 66.552, 1.1246},
        ["jnt_l_hand_ring_01"] = {4.775, 0.8069, -0.011},
        ["jnt_l_hand_ring_02"] = {0.0, 62.9598, 0.0},
        ["jnt_l_hand_ring_03"] = {0.0, 66.552, 1.1246},
        ["jnt_l_hand_thumb_01"] = {-47.6922, 31.4799, -147.713},
        ["jnt_l_hand_thumb_02"] = {-11.407, 29.885, 5.6227},
        ["jnt_l_hand_thumb_03"] = {-5.1727, 19.7849, -0.1877},
        ["jnt_l_hand_index_01"] = {0.0, -5.99, 0.0},
        ["jnt_l_hand_index_02"] = {0.0, 40.541, 0.0},
        ["jnt_l_hand_index_03"] = {0.0, 74.886, 0.0}
    },
    ladderHandPoseLeft = {
        ["jnt_l_hand_middle_01"] = {4.775, 33.8838, -0.011},
        ["jnt_l_hand_middle_02"] = {0.0, 91.148, 0.0},
        ["jnt_l_hand_middle_03"] = {0.0, 26.9999, 1.1247},
        ["jnt_l_hand_pinky_01"] = {9.2749, 13.5, -6.7611},
        ["jnt_l_hand_pinky_02"] = {0.0, 91.148, 0.0},
        ["jnt_l_hand_pinky_03"] = {0.0, 26.9999, 1.1247},
        ["jnt_l_hand_ring_01"] = {9.2749, 33.8838, -0.011},
        ["jnt_l_hand_ring_02"] = {0.0, 91.148, 0.0},
        ["jnt_l_hand_ring_03"] = {0.0, 26.9999, 1.1247},
        ["jnt_l_hand_thumb_01"] = {-21.862, -22.882, -64.8135},
        ["jnt_l_hand_thumb_02"] = {-11.407, 29.885, 5.6227},
        ["jnt_l_hand_thumb_03"] = {-5.1727, 19.7849, -0.1875},
        ["jnt_l_hand_index_01"] = {1.1249, 14.26, 0.0},
        ["jnt_l_hand_index_02"] = {0.0, 81.55, 0.0},
        ["jnt_l_hand_index_03"] = {0.0, 27.1368, 0.0}
    },
    ladderHandPoseRight = {
        ["jnt_r_hand_middle_01"] = {1.7867, 74.2499, 4.511},
        ["jnt_r_hand_middle_02"] = {0.0, 99.023, 0.0},
        ["jnt_r_hand_middle_03"] = {0.0, 15.0909, 0.0},
        ["jnt_r_hand_pinky_01"] = {1.7867, 70.8749, -8.9891},
        ["jnt_r_hand_pinky_02"] = {0.0, 99.023, 0.0},
        ["jnt_r_hand_pinky_03"] = {0.0, 9.4659, 0.0},
        ["jnt_r_hand_ring_01"] = {1.7867, 74.384, -6.7501},
        ["jnt_r_hand_ring_02"] = {0.0, 99.023, 0.0},
        ["jnt_r_hand_ring_03"] = {0.0, 15.0909, 0.0},
        ["jnt_r_hand_thumb_01"] = {-20.771, 16.5048, -136.8151},
        ["jnt_r_hand_thumb_02"] = {-18.8, 19.652, 12.7805},
        ["jnt_r_hand_thumb_03"] = {0.0, 20.9109, 0.0},
        ["jnt_r_hand_index_01"] = {3.1019, 31.694, 26.9729},
        ["jnt_r_hand_index_02"] = {0.0, 75.163, 0.0},
        ["jnt_r_hand_index_03"] = {0.0, 59.6249, 0.0}
    },
    montageAttachmentList = {
        ["Ladder"] = {
            left = {pos={0,0,0}, rot={0,0,0}, socket="jnt_l_ik_hand"},
            right = {pos={0,0,0}, rot={0,0,0}, socket="jnt_r_ik_hand"}
        }, -- Auto-detected climbing state
        -- Add montage names here to auto-attach hands to the pawn mesh
        -- "MontageName_01",
        -- "MontageName_02",
    },
    handTaperValue = 0.0,
}

TwoHandedStateActive = false

local configFilePath = "settings.json"

-- Helper to get only config fields (exclude functions and internal fields)
local function get_config_fields(self)
	local t = {}
	for k, v in pairs(self) do
		if type(v) ~= "function" and string.sub(k, 1, 1) ~= "_" then
			t[k] = v
		end
	end
	return t
end

function Config:update_from_table(tbl)
	for k, v in pairs(tbl) do
		if self[k] ~= nil then
			if (k == "weaponProfiles" or k == "montageAttachmentList" or k == "scopeProfiles" or k == "attachmentProfiles" or k == "redDotProfiles") and type(v) == "table" then
				-- Dynamic map, allow adding all keys
				for profile_k, profile_v in pairs(v) do
					self[k][profile_k] = profile_v
				end
			elseif type(v) == "table" and type(self[k]) == "table" then
				-- Handle nested tables (like gestures)
				for nested_k, nested_v in pairs(v) do
					if self[k][nested_k] ~= nil then
						self[k][nested_k] = nested_v
					end
				end
			else
				self[k] = v
			end
		end
	end
end

function Config:load()
	local loaded = nil
	pcall(function()
		loaded = json.load_file(configFilePath)
	end)
	if loaded then
		self:update_from_table(loaded)
	end
end

function Config:save()
	local t = get_config_fields(self)
	pcall(function()
		json.dump_file(configFilePath, t, 4)
	end)
end

Config:load()

-- Migration: Force update threshold if it's the old default (75.0 or 80.0) which is too high
if Config.conversationFOVThreshold == 80.0 or Config.conversationFOVThreshold == 55.0 or Config.conversationFOVThreshold == 75.0 then
    Config.conversationFOVThreshold = 71.0
    Config:save()
    print("[Config] Migrated conversationFOVThreshold to 71.0")
end

return Config
