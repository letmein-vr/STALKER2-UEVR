-- `Config` below is a GLOBAL, and this file also runs Config:load() at module scope, so every
-- execution builds a fresh table and replaces the global. Lua keys package.loaded by the literal
-- module string, so requiring this file under two spellings ("Config.CONFIG" vs "Config/CONFIG")
-- executes it twice: files holding a `local Config` from the first load keep writing to the
-- orphaned first table while everything reading the global sees the second. That split silently
-- broke the dev-UI detector sliders (edits landed on one table, hands_Detector.lua applied the
-- other). This guard makes a second execution return the existing instance instead.
if Config ~= nil and Config.detectorProfiles ~= nil then return Config end

Config = {
	dominantHand = 1,
	sittingExperience = false,
	recoil = true,
	hapticFeedback = true,
	twoHandedAiming = true,
	handsMode = 1,  -- 1 = glove hands, 2 = IK arms (scripts/hands.lua, libs/ik.lua + data/ik_parameters.json)
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
    -- IK Arms mode flashlight (stalker2/ik_flashlight.lua, ported from the old IK codebase): offsets the
    -- HMD-tracked spotlight in the look direction so it's past the weapon, reversing the shadow direction.
    -- Positive Forward = light moves ahead (reverses weapon shadow), Up = light moves up, Right = light moves right.
    flashlightForwardOffset = 0.0,   -- cm
    flashlightUpOffset = 0.0,        -- cm
    flashlightRightOffset = 0.0,     -- cm
    ikFullBody = false,              -- IK Arms mode: show the game's own body/legs under the IK arms (stalker2/ik_full_body.lua)
    ikFullBodyShoulderSmoothing = 0.35, -- seconds; IK full body: filters the body's walk / jump animation out of the IK shoulders (0 = exact pin)
    ikFullBodyShoulderHeight = 0.0,  -- cm; IK full body: raises (+) / lowers (-) the IK shoulders relative to the body's
    ikFullBodyShoulderWidth = 0.0,   -- cm; IK full body: each IK shoulder pushed outward (+) / inward (-)
    ikFullBodyShoulderForward = 0.0, -- cm; IK full body: IK shoulders pushed forward (+) / back (-)

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
	scopeExposureBias = 0.0,          -- PiP capture AutoExposureBias override (stops, pre-tonemap); per-scope via scopeProfiles.scopeExposureBias
	scopeBrightnessMigratedToneMapped = false, -- one-shot: reset per-scope brightness after the capture-source change (see migration at end of file)
	redDotBrightness = 150.0,
	scopeDiameter = 0.024,
	scopeMagnifier = 0.7,
	scopeTextureSize = 512,
	scopeCaptureScreenPercentage = 50.0, -- internal render scale of the PiP capture (post-process override); 100 = full 512x512
	cylinderDepth = 0.001,
	cylinderOffsetY = 0.0,
	cylinderOffsetZ = 0.0,
	cylinderTubeDepth = 0.001,
	indoor = false,
	scopeActivationDistance = 15.0, -- Distance in cm to activate scope (bring to eye)
    scopeExpandingFOV = false,      -- When true: closer eye = wider scope view, constant magnification
    
    -- Red Dot Sight Settings
    redDotSize = 0.007,             -- Scale of the red dot sphere
    redDotScaleX = 0.007,
    redDotScaleY = 0.007,
    redDotScaleZ = 0.007,
    redDotOffsetX = 0.0,
    redDotOffsetY = 0.0,
    redDotOffsetZ = 0.0,
    redDotApertureRadius = 5.0,     -- Legacy fallback radius (used if Y/Z not set)
    redDotApertureY = 5.0,          -- Elliptical aperture horizontal semi-axis (UU)
    redDotApertureZ = 5.0,          -- Elliptical aperture vertical semi-axis (UU)
    redDotApertureCentreY = 0.0,    -- Aperture ellipse centre horizontal offset (UU)
    redDotApertureCentreZ = 0.0,    -- Aperture ellipse centre vertical offset (UU)
    redDotProfiles = {},
    reflexEnabled = true,             -- enables reflex glass material fix AND the red dot reticule
    pipScopesEnabled = true,          -- enables PiP scope rendering (cylinder + SceneCaptureComponent2D)
    pipOnGlass = true,                -- PiP picture on the scope's own glass instead of the separate cylinder (Base/scope.lua)
    pipGlassCaptureRoll = 0.0,        -- scope camera roll (degrees) for the picture on the glass (cylinder mode uses 90)

    -- Conversation Fix Settings
    enableConversationFix = true,
    conversationFOVThreshold = 80.0, -- Threshold below which we assume a conversation (zoomed camera) is active
    
    weaponSocketName = "S_Hand_R",
    weaponHandRotation = {0, 0, 0}, -- Pitch, Yaw, Roll
    weaponHandLocation = {0, 0, 0}, -- X, Y, Z
    reloadHandRotation = {-1.5, 0.6, -180.2}, -- Pitch, Yaw, Roll
    reloadHandLocation = {0, 0, 0}, -- X, Y, Z
    supportHandBlendTime = 0.12, -- seconds the off hand glides onto/off the weapon (two-handing, reload); 0 = instant snap
    fingerCurlTime = 0.3, -- seconds the off hand's fingers take to curl into the two-handed grip; 0 = instant
    weaponProfiles = {}, -- Stores settings keyed by weapon name
    scopeProfiles = {}, -- Stores settings keyed by scope mesh name

    -- Physical Pickup Item Offsets
    -- Applied to grabbed items relative to the left VR controller origin.
    pickupItemLocation = {0.0, 0.0, 0.0}, -- X, Y, Z offset in cm
    pickupItemRotation = {0.0, 0.0, 0.0}, -- Pitch, Yaw, Roll offset in degrees
    pickupItemProfiles = {},              -- specific offsets per mesh name,
    bodyZoneOverrides = {},               -- dev-panel edits to the body gesture zones: [set][zoneKey] = {minX..maxZ} (stalker2/body_zone_debug.lua)
    -- VR binoculars: two PiP lens discs + one scene capture (stalker2/binoculars.lua). Nested table:
    -- every key must exist here or update_from_table() drops the saved value.
    binoculars = {
        enabled = true,
        captureLocation = { 0.0, 0.0, 0.0 },   -- relative to bone jnt_offset (cm)
        captureRotation = { 0.0, 0.0, 90.0 },  -- Pitch, Yaw, Roll
        discLocation = { 0.0, 0.0, 0.0 },      -- relative to jnt_l_lens / jnt_r_lens (cm)
        discRotation = { 0.0, 90.0, 90.0 },    -- Pitch, Yaw, Roll
        discDiameter = 0.032,                  -- cylinder scale (100 uu base)
        discDepth = 0.001,
        brightness = 1.0,
        zoomFOVs = { 20.0, 10.0, 5.0 },        -- capture FOV per zoom step, widest first
        zoomIndex = 1,
        nearDistance = 20.0,                   -- cm lens->HMD: capture every frame
        sleepDistance = 60.0,                  -- cm lens->HMD: stop capturing
        midCaptureInterval = 4,                -- frames between captures in between
        textureSize = 512,
        screenPercentage = 50.0,
        zoomStickThreshold = 20000,
        haptics = true,
        discSeparation = 6.8,                  -- cm between discs when a model has no per-eye bones
        exposureBias = 0.0,                    -- capture AutoExposureBias override (stops, pre-tonemap); per model via profiles
        profiles = {},                         -- per skeletal-asset tuning: [SK_DevBinocular_0N] = {captureLocation, ..., zoomFOVs}
    },
    -- Grip-gesture timing tolerances in seconds (stalker2/gripgesture.lua, tunable in the dev panel)
    gestureTiming = {
        gripEarlyGrace = 0.30, -- squeeze started this long BEFORE the hand reached the zone still counts
        zoneExitGrace = 0.35,  -- squeeze registering this long AFTER the hand left the zone still counts
        minKeyHold = 0.12,     -- shortest synthetic key press a grip gesture may produce
        keyPrimeDelay = 0.15,  -- an unbound primer key is tapped this long before the real key (0 = off; 0.08 was too short, 0.15 confirmed in-headset); see stalker2/gesturekeys.lua
        keyPrimer = "0x87",    -- luakey name of the primer: VK_F24, bound to nothing
        keyRetry = true,       -- weapon-slot keys: press once more if the equipped weapon did not change
        keyQuietSticks = true, -- zero sticks/triggers while a gesture key is delivered, so moving doesn't flip the game back to gamepad mode and eat the key
    },

    pickupItemGrabRadius = 15.0,          -- Sphere radius around left hand for picking up items
    pickupDropKeepsPose = true,           -- dropped items keep the held rotation/offset; false = drop from controller origin (old)
    pickupGlideTime = 0.15,               -- seconds a grabbed item glides into the hand (physical_pickup.lua); 0 = instant snap

    -- Physical Pickup: Add to Inventory (shoulder zone)
    pickupInventoryEnabled = true,        -- When true, releasing item over left shoulder adds it to inventory

    -- Manual Reload master switch. false = legacy reload: the native montage plays through
    -- with the left hand attached to the weapon's jnt_l_hand socket (X button or the
    -- reload gesture starts it).
    enableManualReload = true,

    -- Manual Reload: PTM Proxy Mag Offsets
    -- Relative to the jnt_l_hand socket on the left hand PMC.
    ptmMagProxyLocation = {-4.000, 4.000, -1.000}, -- X, Y, Z in cm
    ptmMagProxyRotation = {-35.000, 0.000, 10.000},  -- Pitch, Yaw, Roll in degrees
    -- true: parent the held/ejected mag proxy to the left VR hand mesh's jnt_l_hand bone
    -- (follows the posed hand and any hand-mesh offsets). false: parent it to the left
    -- MotionControllerComponent (legacy; the socket name is ignored there). The
    -- ptmMagProxyLocation/Rotation offsets are relative to whichever parent is used,
    -- so expect to retune them after switching.
    ptmAttachProxyToHandMesh = true,
    -- Box-mag insert glide (ptm_manual_reload.lua STATE_INSERTING): on a near-socket release the
    -- fresh mag eases into a pre-seat pose backed out ptmInsertDepth cm along ptmInsertAxis
    -- (weapon component space, pointing OUT of the magwell), then slides straight in.
    -- WEAPON_PROFILES insertAxis/insertDepth override per weapon. 0 glide time = instant snap.
    ptmInsertGlideTime = 0.16,
    ptmInsertDepth = 6.0,
    -- Fresh mag released within this many cm of its seat (the hidden real mag) inserts; further away it drops.
    ptmInsertDistance = 12.0,
    ptmInsertAxis = {0.0, 0.0, -1.0},
    -- Box-mag INSERT fast-forward rate for the rest of the native reload (both meshes). Higher =
    -- fewer visible sped-up frames after the mag seats. Per weapon: weaponProfiles[name].ptmFinishRate
    -- (and .ptmInsertGlideTime overrides ptmInsertGlideTime). Tube-fed weapons stay at 15x.
    ptmFinishRate = 100.0,
    -- Dev aid for bare-socket seats (Rhino speedloader): seconds the proxy is parked on its seat
    -- before the reload completes, following weaponProfiles[name].ptmSeatLoc/ptmSeatRot live. 0 = off.
    ptmSeatPreviewHold = 0.0,
    -- Rhino (flickToClose profiles): after the speedloader seats, the reload only completes when
    -- the right hand flicks to the right (closing the cylinder). false = completes on seat (old).
    ptmFlickToClose = true,
    ptmFlickCloseSpeed = 150.0,           -- cm/s sideways speed of the gun tip / top that counts as a flick

    -- Physical knife melee (stalker2/knife_melee.lua): a fast swing of the dominant hand
    -- (down / left / right / forward stab, never up or pull-back) injects a short Right
    -- Trigger press while the knife is equipped, and the knife melee montages play at animRate.
    knifeMelee = {
        enabled  = true,
        minSpeed = 180.0,   -- cm/s hand speed (relative to the head) needed to count as a swing
        cooldown = 0.35,    -- seconds between accepted swings
        animRate = 20.0,    -- char + knife mesh GlobalAnimRateScale while a knife melee montage plays
        log      = false,   -- trace swings / montages into log.txt (luakey echo channel)
    },

    -- Equipped items shown on the body (stalker2/body_items.lua): each slot's item sits at the centre of its
    -- gesture zone plus location (X forward, Y right, Z up, cm) / rotation (pitch, yaw, roll) / scale.
    -- "mesh" is learned when the item is drawn and saved here; do not edit by hand.
    bodyItems = {
        enabled = true,
        slots = {
            sidearm  = { enabled = true, location = { 0.0, 0.0, 0.0 }, rotation = { -90.0, 0.0, 0.0 }, scale = 1.0 },
            detector = { enabled = true, location = { 0.0, 0.0, 0.0 }, rotation = { 0.0, 0.0, 0.0 }, scale = 1.0 },
            grenade  = { enabled = true, location = { 0.0, -4.0, 4.0 }, rotation = { 0.0, 0.0, 0.0 }, scale = 1.0 },
            bolt     = { enabled = true, location = { 0.0, 5.0, -6.0 }, rotation = { 0.0, 0.0, 0.0 }, scale = 1.0 },
            -- manual reload belt pouch (left hip); placement kept per ammo type in byType.<mag|shell|speedloader|rocket>
            ammo     = { enabled = true, location = { 0.0, 0.0, 0.0 }, rotation = { 0.0, 0.0, 0.0 }, scale = 1.0 },
        },
        iconMeshes = {},   -- learned: inventory icon name -> mesh asset path
        materials = {},    -- learned: mesh asset path -> material asset paths (weapon meshes have none of their own)
        parts = {},        -- learned: weapon rig path -> its visible static-mesh parts (mesh, socket, transform, materials)
        dataVersion = 0,
        debugLog = false,  -- true: write data/body_items_log.txt (state changes only)
    },

    -- Rack to chamber (stalker2/rack_slide.lua): after an EMPTY manual reload the slide / charging handle must be
    -- racked with the left hand before the weapon fires. On/off per weapon type (rig folder pt / smg / ar / sr + dmr / shg box-mag).
    rackToChamber = { pistol = true, smg = true, ar = true, sniper = true, shotgun = true },
    rackGrabRadius = 12.0,   -- cm: left controller to the slide / handle part when the grip is pressed
    rackLearned = {},        -- learned per weapon rig: joint -> { idleMax, idleMin, minX } (parent-bone space, cm)

    -- Physical throws (stalker2/physical_throw.lua): with a grenade or the bolt equipped, Right Trigger is
    -- held back from the game; swing and release it to throw with the hand velocity (relative to the head).
    physicalThrow = {
        enabled    = true,
        speedScale = 3.5,     -- throw speed = hand speed x this
        floorSpeed = 600.0,   -- cm/s: slowest throw
        underSpeedScale = 2.0,   -- underarm throw (right grip): hand speed x this
        underFloorSpeed = 250.0, -- cm/s: slowest underarm throw
        maxSpeed   = 2500.0,  -- cm/s: fastest throw
        minSpeed   = 120.0,   -- cm/s hand speed below which a release throws nothing
        assist     = 0.5,     -- 0..1: pull the throw direction toward where the player looks
        arc        = 8.0,     -- deg added upward
        spawnDist  = 20.0,    -- cm from the hand along the throw
        animRate   = 20.0,    -- char + item mesh GlobalAnimRateScale from the release until the projectile appears
        catchUp    = true,    -- start the projectile where it would be after the game delay (max 0.15 s)
        stabilizeCamera = true, -- camera shake / camera animation modifiers off from the release until just after the launch
        debugLog   = false,   -- data/physical_throw_log.txt
    },

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
		weaponCustomization = true,  -- Left shoulder (left hand) + left grip = long press T
		escapeCombo = true  -- Right thumbrest touch + Left stick click (L3) = Escape tap
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
    -- Left hand pose while holding the proxy mag during PTM manual reload (STATE_INSERTING)
    ptmMagGripPose = {
        ["jnt_l_hand_middle_01"] = {4.5817, 51.4692, 8.374},
        ["jnt_l_hand_middle_02"] = {-7.2718, 58.668, -5.9066},
        ["jnt_l_hand_middle_03"] = {-0.0017, 18.6615, -0.0025},
        ["jnt_l_hand_pinky_01"]  = {5.0183, 55.5751, 9.9387},
        ["jnt_l_hand_pinky_02"]  = {-2.3861, 61.288, -0.7981},
        ["jnt_l_hand_pinky_03"]  = {-0.0077, -14.0313, 1.3448},
        ["jnt_l_hand_ring_01"]   = {7.826, 48.3769, 7.3875},
        ["jnt_l_hand_ring_02"]   = {-9.0802, 61.4639, 5.7804},
        ["jnt_l_hand_ring_03"]   = {-0.1015, 10.8169, -0.7777},
        ["jnt_l_hand_thumb_01"]  = {-31.935, -21.5777, -38.0991},
        ["jnt_l_hand_thumb_02"]  = {20.7813, 25.6351, -2.595},
        ["jnt_l_hand_thumb_03"]  = {-2.5784, 27.0653, 1.5038},
        ["jnt_l_hand_index_01"]  = {1.1249, 14.26, 0.0},
        ["jnt_l_hand_index_02"]  = {0.0, 81.55, 0.0},
        ["jnt_l_hand_index_03"]  = {0.0, 27.1368, 0.0}
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
			-- rackLearned (rack_slide.lua, per weapon rig): its default is {}, so the nested-table branch below
			-- dropped every saved weapon on load and the rack relearned from scratch each session.
			if (k == "weaponProfiles" or k == "montageAttachmentList" or k == "scopeProfiles" or k == "attachmentProfiles" or k == "redDotProfiles" or k == "pickupItemProfiles" or k == "bodyZoneOverrides" or k == "rackLearned") and type(v) == "table" then
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

function Config:markDirty()
	self._dirty = true
end

function Config:save()
	if not self._dirty then return end  -- skip encode if nothing changed
	self._dirty = false
	local t = get_config_fields(self)
	pcall(function()
		json.dump_file(configFilePath, t, 4)
	end)
end

Config:load()

-- Migration: Force update threshold if it's the old default (75.0 or 80.0) which is too high
if Config.conversationFOVThreshold == 80.0 or Config.conversationFOVThreshold == 55.0 or Config.conversationFOVThreshold == 75.0 then
    Config.conversationFOVThreshold = 71.0
    Config:markDirty()
    Config:save()
    print("[Config] Migrated conversationFOVThreshold to 71.0")
end

-- Migration (2026-09-08): the PiP SceneCapture now captures FinalColorHDR (post-tonemap, auto-
-- exposed) instead of raw pre-tonemap scene colour. Every saved per-scope brightness (0.02-1.3)
-- was compensating for that raw radiance and is now wrong; reset all of them to 1.0 exactly once.
if Config.scopeBrightnessMigratedToneMapped ~= true then
    local n = 0
    Config.scopeBrightnessAmplifier = 1.0
    if type(Config.scopeProfiles) == "table" then
        for _, prof in pairs(Config.scopeProfiles) do
            if type(prof) == "table" and prof.scopeBrightness ~= nil then
                prof.scopeBrightness = 1.0
                n = n + 1
            end
        end
    end
    Config.scopeBrightnessMigratedToneMapped = true
    Config:markDirty()
    Config:save()
    print("[Config] Migrated scope brightness to 1.0 for tonemapped capture (" .. n .. " profiles)")
end

return Config
