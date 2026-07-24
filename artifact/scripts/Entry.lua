-- Vector3f.new = function(self, x, y, z)
--     return {x=x, y=y, z=z}
-- end
package.loaded["Config.CONFIG"] = nil -- Force reload config to pick up file changes
Config = require("Config.CONFIG")
-- print("[UEVR] Reloaded Config. Conversation Threshold: " .. tostring(Config.conversationFOVThreshold))
print("[UEVR] Reloaded Config. Conversation Threshold: " .. tostring(Config.conversationFOVThreshold))
-- OpenXR / VR Params
local vr = uevr.params.vr
local thumbrestLeftHandle = vr.get_action_handle("/actions/default/in/ThumbrestTouchLeft")

local motionControllerActors = require("gestures.motioncontrolleractors")
package.loaded["stalker2.gamestate"] = nil -- Force reload gamestate
local gameState = require("stalker2.gamestate") -- Ensure gameState is available for context
local gestureSetRH = require("presets.presetRH")
local gestureSetLH = require("presets.presetLH")
local gamepadState = require("stalker2.gamepad")
local haptics = require("stalker2.haptics")
require("Base.basic")
local scopeController = require("Base.scope") -- Require the scope controller
local uevrUtils = require("libs/uevr_utils") -- REQUIRED for attachment logic
local magReload = require("stalker2.mag_reload") -- REQUIRED for attachment logic
local zoneDebug = require("stalker2.zone_debug")
require("player_collision")
-- local twoHand   = require("stalker2.two_hand")   -- Collision-based two-hand aiming
local hands = require("libs/hands")
local pawnModule = require("libs/pawn")
local inputModule = require("libs/input")
local uevrUtils = require("libs/uevr_utils")
require("MontageWildcard") -- Wildcard logic for AnimMontage visibility defaults
local controllers = require("libs/controllers")
local attachments = require("libs/attachments") -- direct access for init() and registerGrippedAttachment()
local physicalPickup = require("physical_pickup") -- proximity item pickup via grab sphere

gameState:Init()
gamepadState:Reset()

-- Explicit mapping from Weapon Profile Name -> Left Hand Pose Key
-- Keys are normalized to lowercase to ensure case-insensitive matching
local weaponPoseMapping = {
    ["sk_ak74"] = "left_grip_weapon_ak74",
    ["sk_toz34"] = "left_grip_weapon_toz34_shotgun",
    ["sk_aku"] = "left_grip_weapon_aku",
    ["sk_apb"] = "left_grip_weapon_apb_pistol",
    ["sk_bucket0"] = "left_grip_weapon_bucket",
    ["sk_d1200"] = "left_grip_weapon_d12",
    ["sk_dnipro"] = "left_grip_weapon_dnipro",
    ["sk_fora0"] = "left_grip_weapon_fora",
    ["sk_gp37"] = "left_grip_weapon_gp37",
    ["sk_grim0"] = "left_grip_weapon_grim",
    ["sk_gvi"] = "left_grip_weapon_gvintar",
    ["sk_integ"] = "left_grip_weapon_integral",
    ["sk_kharod000"] = "left_grip_weapon_kharod",
    ["sk_lav"] = "left_grip_weapon_lavina",
    ["sk_m1000"] = "left_grip_weapon_m10",
    ["sk_m160"] = "left_grip_weapon_m16",
    ["sk_m701"] = "left_grip_weapon_m701",
    ["sk_m86000"] = "left_grip_weapon_m860",
    ["sk_mar"] = "left_grip_weapon_mark",
    ["sk_obrez"] = "left_grip_weapon_topaz_sawnoff_shotgun",
    ["sk_pkp00000"] = "left_grip_weapon_pkp_lmg",
    ["sk_pm"] = "left_grip_weapon_pm_pistol",
    ["sk_ram2"] = "left_grip_weapon_ram2",
    ["sk_rhino00000"] = "left_grip_weapon_rhino",
    ["sk_spsa00"] = "left_grip_weapon_spsa_shotgun",
    ["sk_svm"] = "left_grip_weapon_svdm",
    ["sk_svu"] = "left_grip_weapon_svu",
    ["sk_udp"] = "left_grip_weapon_udp_pistol",
    ["sk_vip"] = "left_grip_weapon_viper",
    ["sk_zubr0"] = "left_grip_weapon_zubr",
    
    -- Explicitly NIL for standard grip weapons
    ["sk_f1"] = "nil",
    ["sk_rgd5"] = "nil",
    ["sk_bolt"] = "nil",
    ["sk_gauss"] = "nil",
    ["sk_knife"] = "nil",
    ["sk_rpg7"] = "nil",
}

-- Load specific hand poses from JSON
local specificHandPoses = require("data.hand_poses")
if specificHandPoses then
    print("[HandPose] Loaded specific hand poses from explicit Lua module.")
    
    -- Inject missing index finger poses as per user request (Fixes finger sticking out)
    local indexFingerOverrides = {
        ["jnt_l_hand_index_01"] = {-10.1251, 28.18, 7.5277},
        ["jnt_l_hand_index_02"] = {0.0002, 7.6146, 0.0002},
        ["jnt_l_hand_index_03"] = {-0.0007, 72.8081, 0.0001}
    }
    
    for key, weaponData in pairs(specificHandPoses) do
        -- Skip detector poses from this override, they have their own specific finger data
        if not string.find(key, "sk_detector") and weaponData["off"] then
             for boneName, rotation in pairs(indexFingerOverrides) do
                 -- Overwrite or add to ensure the finger curves correctly
                 weaponData["off"][boneName] = rotation
             end
        end
    end
else
    print("[HandPose] ERROR: Failed to require data.hand_poses!")
end

-- Helper to find specific hand pose for a weapon
local function getSpecificHandPose(weaponName, debug)
    if not weaponName then return nil end

    if Config and Config.weaponProfiles and Config.weaponProfiles[weaponName] and Config.weaponProfiles[weaponName].leftHandPose then
        if debug then print("[HandPose] FOUND DYNAMIC POSE for " .. weaponName) end
        return Config.weaponProfiles[weaponName].leftHandPose
    end

    if not specificHandPoses then return nil end
    local cleanName = string.lower(weaponName)
    
    if debug then
        print("[HandPose] Attempting to match normalized weapon: '" .. cleanName .. "'")
    end

    -- 1. Try Explicit Mapping First
    local mappedKey = weaponPoseMapping[cleanName]
    if mappedKey then
        if mappedKey == "nil" then
            if debug then print("[HandPose] Explicit mapping says NIL for this weapon.") end
            return nil
        end
        
        if specificHandPoses[mappedKey] then
             if debug then print("[HandPose] FOUND EXPLICIT MAPPED KEY: " .. mappedKey) end
             return specificHandPoses[mappedKey]["off"]
        else
             if debug then print("[HandPose] ERROR: Key found in mapping ("..mappedKey..") but NOT in existing JSON poses!") end
        end
    end

    -- 2. Fallback: Intelligent Matching (Substrings)
    -- Strip common prefixes/suffixes to get core name

    -- 2. Fallback: Iterate and find substring match
    for key, data in pairs(specificHandPoses) do
        local matchName = key:gsub("left_grip_weapon_", "")
        
        -- Check 1: Does weapon name contain key part? (e.g. Weapon 'Item_AK74' contains 'ak74')
        local forwardMatch = (matchName ~= "" and string.find(cleanName, matchName, 1, true))
        
        -- Check 2: Does key part contain weapon name? (e.g. Key 'toz34_shotgun' contains Weapon 'toz34')
        local reverseMatch = (matchName ~= "" and string.find(matchName, cleanName, 1, true))

        if forwardMatch or reverseMatch then
            if debug then
                local method = forwardMatch and "FORWARD" or "REVERSE"
                print("[HandPose] FOUND " .. method .. " MATCH! Key: " .. key .. " matches '" .. matchName .. "' vs '" .. cleanName .. "'")
            end
            return data["off"] -- Return the 'off' pose
        end
    end
    
    if debug then
        print("[HandPose] NO MATCH FOUND for: '" .. cleanName .. "'")
    end
    return nil
end

-- Right Hand Pose Logic
local rightWeaponPoseMapping = {
    ["sk_knife"] = "right_grip_knife",
    ["sk_bolt"] = "right_grip_bolt",
    ["sk_f1"] = "right_grip_grenade",
    ["sk_rgd5"] = "right_grip_grenade",
    ["sk_grenade"] = "right_grip_grenade", -- Generic guess
    ["none"] = "right_open_hand"
}

local function getSpecificRightHandPose(weaponName)
    if not specificHandPoses then return nil end
    
    -- Case 1: Bare Hands (nil weapon)
    if not weaponName then
        return specificHandPoses["right_open_hand"]["off"]
    end
    
    local cleanName = string.lower(weaponName)
    local mappedKey = rightWeaponPoseMapping[cleanName]
    
    -- Check for explicit substring matches if not mapped
    if not mappedKey then
        if string.find(cleanName, "grenade") then mappedKey = "right_grip_grenade" end
        if string.find(cleanName, "knife") then mappedKey = "right_grip_knife" end
        if string.find(cleanName, "bolt") then mappedKey = "right_grip_bolt" end
    end

    if mappedKey and specificHandPoses[mappedKey] then
         -- print("[HandPose] Right Hand Override: " .. cleanName .. " -> " .. mappedKey)
         return specificHandPoses[mappedKey]["off"]
    else
         -- print("[HandPose] No Right Hand Override for: " .. cleanName)
    end
    
    return nil
end

-- Returns true for melee/throwable items that use the bespoke cachedRHPose
-- system instead of the attachments grip-animation pipeline.
local function isMeleeItem(name)
    if not name then return false end
    local n = string.lower(name)
    return n == "sk_knife" or n == "sk_bolt" or
           string.find(n, "knife")   ~= nil or
           string.find(n, "bolt")    ~= nil or
           string.find(n, "grenade") ~= nil or
           n == "sk_f1" or n == "sk_rgd5"
end

local lastConversationState = false
local lastRightHandOverride = false
local cachedRHPose = getSpecificRightHandPose(nil)
-- Deferred grip registration flag: set true when weapon name changes so we
-- fetch the CharacterMesh on the NEXT tick (by then the engine has swapped it).
-- pendingGripRetries: how many more ticks to keep retrying if GetEquippedWeapon()
-- returns nil mid-swap (race window is typically 1-2 frames).
local pendingGripRegistration = false
local pendingGripRetries = 0

-- Populate the "Grip Animation" dropdown with the weapon profiles defined in
-- hands_parameters.json BEFORE attachments.init() calls showDeveloperConfiguration()
-- → configui.create(). If we don't do this, configui.create bakes
-- animationLabels = {"Default","None"} (the module-level initial value) into every
-- combo widget. setAnimationIDs is otherwise only called later via
-- hands.createFromConfig() (1-second interval), so there's a race: any
-- configui.update() triggered by a newly-detected weapon between that call and
-- setAnimationIDs would hard-rebuild the layout from the stale two-item list,
-- discarding whatever setSelections had patched. Calling it here (synchronously,
-- at script load) eliminates the race entirely — the same pattern used in the IK
-- codebase's Entry.lua.
do
    local handsParams = json.load_file("hands_parameters.json")
    if handsParams and handsParams["attachments"] then
        attachments.setAnimationIDs(handsParams["attachments"])
    end
end

-- Attachments Config Dev panel disabled (pass false to suppress the overlay UI).
-- The underlying attachment registration and grip animation logic still runs normally.
attachments.init(false)

-- Keep holdingAttachment[dominantHand] in sync with the active grip animation.
--
-- WHY: createInputHandler (hands.lua) builds rightAttachment like this:
--   rightAttachment = holdingAttachment[Handed.Right]
--   if rightAttachment == nil then
--       rightAttachment = getCurrentGripAnimation(Handed.Left)  <- reads index 0!
--   end
-- We register virtual grips under Config.dominantHand (Handed.Right = 1), so
-- getCurrentGripAnimation(Handed.Left = 0) always returns nil, making
-- handleInputTwoHanded treat the hand as open and apply the DEFAULT right_grip
-- animation on grip-button press -- overriding the per-weapon pose.
-- Fix: populate holdingAttachment[dominantHand] with the animation ID string
-- ("rhino", "rifle", etc.) before the xinput callback runs.
attachments.registerOnGripAnimationCallback(function(gripAnimation, gripHand)
    if gripHand == Config.dominantHand then
        local holdValue
        if type(gripAnimation) == "string" and gripAnimation ~= "" and gripAnimation ~= "attachment_none" then
            holdValue = gripAnimation       -- e.g. "rhino" -> right_grip_weapon_rhino
        elseif gripAnimation == true then
            holdValue = true                -- generic weapon grip (default extension "")
        else
            holdValue = false               -- bare hands / melee -> open-hand animation
        end
        hands.setHoldingAttachment(Config.dominantHand, holdValue)
    end
end)



local currentPreset = gestureSetRH.StandModeSetRH

local function updateConfig(config)
    haptics.updateHapticFeedback(Config.hapticFeedback)
    if Config.dominantHand == 1 then
        currentPreset = Config.sittingExperience and gestureSetRH.SitmodeSetRH or gestureSetRH.StandModeSetRH
    else
        currentPreset = Config.sittingExperience and gestureSetLH.SitModeSetLH or gestureSetLH.StandModeSetLH
    end
    -- Update scope brightness
    if scopeController then
        -- scopeController:SetScopeBrightness(config.scopeBrightnessAmplifier)
        -- scopeController:SetScopePlaneScale(config.cylinderDepth)
        -- scopeController:UpdateIndoorMode(config.indoor)
    end
end


local lastWeaponMesh = nil
local currentWeaponName = nil
local weaponCheckTimer = 0
local lastSupportHandState = false
local lastClimbingState = false
local currentScopeName = nil
local lastScopeMesh = nil
local lastTwoHandingState = false
local lastReloadState = false
local lastDetectorState = false
local lastGuitarState = false
local lastMontageState = false

local lastCutscene2DState = false
local engineTickCount = 0           -- global tick counter used for throttling enforcement calls
local levelCheckTick = 0            -- throttle IsLevelChanged check
local lastWeaponModState = false
local leftHandBones = {
    "jnt_l_hand_thumb_01", "jnt_l_hand_thumb_02", "jnt_l_hand_thumb_03",
    "jnt_l_hand_index_01", "jnt_l_hand_index_02", "jnt_l_hand_index_03",
    "jnt_l_hand_middle_01", "jnt_l_hand_middle_02", "jnt_l_hand_middle_03",
    "jnt_l_hand_ring_01", "jnt_l_hand_ring_02", "jnt_l_hand_ring_03",
    "jnt_l_hand_pinky_01", "jnt_l_hand_pinky_02", "jnt_l_hand_pinky_03"
}
local preMontageLHHandPose = nil
local lastPlayedMontageName = "None"
local isXButtonHeld = false
local isReloadMontageActive = false  -- Track if reload montage is playing
local isMagazineMontageActive = false  -- Track if magazine attach/detach montage is playing
local lastMenuState = false  -- Track menu state changes
local simulateReloadHandPosition = false  -- Track reload hand simulation toggle
local simulateTwoHandMode = false -- Track two-handed simulation toggle
local cachedLHPose = nil -- Cache the "correct" left hand pose for restoration
local savedAimMethod = nil  -- Store aim method before climbing
local lastClimbingState = false  -- Track climbing state changes
local brightnessDirty = false -- Track if brightness needs saving
local lastThrowableState = false  -- Track throwable (bolt/knife/grenade) equip state


-- Global flag to suppress item attachment during consumption montages
-- This allows items to follow pawn's animated hands instead of VR controllers
_G.SuppressItemAttachment = false

-- Helper to check if a montage should trigger attachment
local function shouldAttachForMontage(montageName)
    if not montageName or montageName == "" then return false end
    
    -- Check keyed table (new format)
    if Config.montageAttachmentList[montageName] then return true end
    
    -- Check array list (legacy format compatibility)
    for _, name in ipairs(Config.montageAttachmentList) do
        if name == montageName then return true end
    end
    
    return false
end


-- Consumption montages that need item detachment
local consumptionMontages = {
    ["MG_fp_bandage_use"] = true,
    ["MG_fp_beer_use"] = true,
    ["MG_fp_bh_stash"] = true,
    ["MG_fp_bread_use"] = true,
    ["MG_fp_canned_food_use"] = true,
    ["MG_fp_condensed_milk_use"] = true,
    ["MG_fp_energy_drink_use"] = true,
    ["MG_fp_medkit_common_use"] = true,
    ["MG_fp_pills_common_use"] = true,
    ["MG_fp_sausage_use"] = true,
    ["MG_fp_vodka_use"] = true,
    ["MG_fp_water_use"] = true
}

local function isConsumptionMontage(montageName)
    return montageName and consumptionMontages[montageName] == true
end


-- Module-level set for O(1) pistol lookup — avoids allocating a new table on every call
local pistolWeapons = {
    ["sk_pm"]  = true,
    ["sk_apb"] = true,
    ["sk_udp"] = true,
}

-- Helper to check if current weapon is a pistol
local function isPistolWeapon(weaponName)
    if not weaponName then return false end
    return pistolWeapons[string.lower(weaponName)] == true
end


local activeWeaponModMontage = nil
local modMeshScanTick = 0      -- throttles the initial mod-mesh search
local modMeshCleanupTick = 0   -- throttles the per-tick cleanup child-walk
local EMPTY_CONTEXT = {}        -- reusable empty context for GestureSet:Update (avoids 90 allocs/sec)

-- Variables for Attachment Simulation
local lastCleanAttachmentName = nil
local isSimulatingAttachment = false
local simulatedAttachmentOriginalParent = nil
local simulatedAttachmentOriginalSocket = nil

-- Global variables for attachment simulation
local detectedAttachments = {}
local selectedAttachmentValues = {}
local selectedAttachmentIndex = 1
local currentSimulationPose = nil
local showAllAttachments = false

local function GetCleanAttachmentName(name)
    if not name then return nil end
    local clean = name
    
    -- Strip Standard UE instance numbers (_123 at end)
    local s_inst = clean:find("_%d+$")
    if s_inst then clean = clean:sub(1, s_inst-1) end
    
    -- Strip GEN_VARIABLE
    local s_gen = clean:find("_GEN_VARIABLE")
    if s_gen then clean = clean:sub(1, s_gen-1) end
    
    -- Strip 32-char Hex Hash (Stalker 2 Upgrades)
    if #clean > 32 then
         local suffix = clean:sub(-32)
         -- Check if suffix is all hex chars (0-9, a-f, A-F)
         if suffix:match("^%x+$") then
              clean = clean:sub(1, -33)
         end
    end
    
    return clean
end

local function scanWeaponAttachments()
    local weapon = gameState:GetEquippedWeapon()
    if not weapon then 
        detectedAttachments = {}
        selectedAttachmentValues = {}
        local selectedAttachmentIndex = 1
        return 
    end
    
    local found = {}
    local values = {}
    
    if weapon.AttachChildren then
        for _, child in ipairs(weapon.AttachChildren) do
            if child and UEVR_UObjectHook.exists(child) then
                local name = child:get_fname():to_string()
                local lowerName = string.lower(name)
                -- Broad filter for relevant attachments
                if showAllAttachments or lowerName:find("silencer") or lowerName:find("sight") or lowerName:find("scope") or lowerName:find("mag") or lowerName:find("suppressor") or lowerName:find("optic") or lowerName:find("b_w_") then
                     table.insert(found, {name=name, mesh=child})
                     table.insert(values, name)
                end
            end
        end
    end
    detectedAttachments = found
    selectedAttachmentValues = values
    
    if selectedAttachmentIndex > #detectedAttachments then selectedAttachmentIndex = 1 end
    if #detectedAttachments > 0 and selectedAttachmentIndex == 0 then selectedAttachmentIndex = 1 end
end

local function toggleAttachmentSimulation(enable)
    local pawn = gameState:GetLocalPawn()
    if not pawn then 
        isSimulatingAttachment = false
        return 
    end
    
    local leftHand = hands.getHandComponent(0)
    if not leftHand then 
        print("[Simulate] Could not find Left Hand Component")
        isSimulatingAttachment = false
        return 
    end
    
    if enable then
        -- Ensure we have up-to-date attachments
        if #detectedAttachments == 0 then scanWeaponAttachments() end
        
        if #detectedAttachments == 0 then
            print("[Simulate] No attachments found on weapon.")
            isSimulatingAttachment = false
            return
        end
        
        local targetData = detectedAttachments[selectedAttachmentIndex]
        if not targetData then
             print("[Simulate] Invalid attachment selection.")
             isSimulatingAttachment = false
             return
        end

        local targetMesh = targetData.mesh
        local targetName = targetData.name

        if targetMesh and UEVR_UObjectHook.exists(targetMesh) then
            simulatedAttachmentOriginalParent = targetMesh.AttachParent
            local socketName = targetMesh.AttachSocketName
            simulatedAttachmentOriginalSocket = socketName and socketName:to_string() or "None"
            
            print("[Simulate] Hijacking attachment: " .. targetName .. " from " .. simulatedAttachmentOriginalSocket)
            
            targetMesh:DetachFromParent(true, true)
            targetMesh:K2_AttachToComponent(leftHand, uevrUtils.fname_from_string("None"), 2, true) 
            
            attachedModMesh = targetMesh
            isSimulatingAttachment = true
            
            -- Setup Profile Name
            local cleanName = GetCleanAttachmentName(targetName)
            
            -- Store clean name for profile lookup
            lastCleanAttachmentName = cleanName
            currentAttachmentName = cleanName

            
            -- Determine and Set Hand Pose
            local weapon = gameState:GetEquippedWeapon()
            local weaponName = weapon and weapon:get_fname():to_string()
            currentSimulationPose = getSpecificHandPose(weaponName)
            
            if currentSimulationPose then
                hands.setHandPose(0, currentSimulationPose)
            else
                hands.setHoldingAttachment(0, true)
            end
        else
             print("[Simulate] Target mesh invalid.")
             isSimulatingAttachment = false
        end
    else
        -- Restore
        if attachedModMesh and simulatedAttachmentOriginalParent and UEVR_UObjectHook.exists(attachedModMesh) then
             print("[Simulate] Restoring attachment to: " .. simulatedAttachmentOriginalSocket)
             
             attachedModMesh:DetachFromParent(true, true)
             attachedModMesh:K2_AttachToComponent(simulatedAttachmentOriginalParent, uevrUtils.fname_from_string(simulatedAttachmentOriginalSocket), 2, true)
        end
        
        -- Always cleanup state
        attachedModMesh = nil
        currentAttachmentName = nil 
        isSimulatingAttachment = false
        simulatedAttachmentOriginalParent = nil
        simulatedAttachmentOriginalSocket = nil
        currentSimulationPose = nil
        
        -- Release Grip pose
        hands.setHoldingAttachment(0, false)
    end
end

-- Montage change callback
uevrUtils.registerMontageChangeCallback(function(montage, montageName)
    if montageName and montageName ~= "" then
        lastPlayedMontageName = montageName
    end

    -- Check if this is a reload montage
    if montageName and string.lower(montageName):find("reload") then
        isReloadMontageActive = true
        -- print("Reload montage detected: " .. montageName)
    else
        isReloadMontageActive = false
    end
    
    -- Check if this is a magazine attach/detach montage
    if montageName and montageName:find("_mag_") and (montageName:find("_attach") or montageName:find("_detach")) then
        isMagazineMontageActive = true
        -- print("Magazine montage detected: " .. montageName)
    else
        isMagazineMontageActive = false
    end

    -- Check for weapon modification montages (silencer, sight, scope, suppressor, grenade launcher)
    if montageName and (string.lower(montageName):find("silencer") or string.lower(montageName):find("sight") or string.lower(montageName):find("scope") or string.lower(montageName):find("suppress") or string.lower(montageName):find("grenlaunch") or string.lower(montageName):find("gren_launch") or string.lower(montageName):find("bucklaunch")) then
        isWeaponModMontageActive = true
        gameState.isWeaponModMontageActive = true
        activeWeaponModMontage = montage -- Capture montage object
        -- print("Weapon Mod montage detected: " .. montageName)
    else
        isWeaponModMontageActive = false
        gameState.isWeaponModMontageActive = false
        activeWeaponModMontage = nil
    end

    -- Grenade throw montage detection — prevents isConversation false-positive
    -- (grenade arming zooms camera below conversation FOV threshold)
    local grenadeThrowMontages = {
        ["MG_fp_rgd5_light_throw"] = true,
        ["MG_fp_rgd5_one_hand_light_throw"] = true,
        ["MG_fp_rgd5_strong_throw"] = true,
        ["MG_fp_f1_light_throw"] = true,
        ["MG_fp_f1_strong_throw"] = true,
    }
    gameState.isGrenadeThrowMontageActive = (montageName and grenadeThrowMontages[montageName]) and true or false
    if gameState.isGrenadeThrowMontageActive then
        -- print("[GrenadeFix] Grenade throw montage detected: " .. montageName .. " - suppressing conversation FOV check")
    end


    -- Handle consumption montages - suppress item attachment so items follow pawn animation
    if isConsumptionMontage(montageName) then
        if not _G.SuppressItemAttachment then
            -- print("[Consumption] Montage started: " .. montageName .. " - Suppressing item attachment")
            _G.SuppressItemAttachment = true
        end
    else
        -- Not a consumption montage - allow item attachment
        if _G.SuppressItemAttachment then
            -- print("[Consumption] Montage ended - Re-enabling item attachment")
            _G.SuppressItemAttachment = false
        end
    end

    if shouldAttachForMontage(montageName) then
        -- print("Montage attached: " .. montageName)
        gameState.isMontageAttached = true
    else
        -- Only clear if we were attached? Or just always clear if not a matching montage?
        -- Assuming any other montage (or stopping) means we should detach 
        -- UNLESS multiple layers are playing? For simplicity, if the MAIN montage changes to something else, we detach.
        -- We might need a more robust check if montages overlap, but for now:
        if gameState.isMontageAttached then
             -- print("Montage detached: " .. tostring(montageName))
             gameState.isMontageAttached = false
        end
    end
end)

-- Register callbacks to control hand/arm visibility during climbing
-- Hide VR hands when climbing or playing guitar
hands.registerIsHiddenCallback(function()
    if gameState.isClimbing or gameState.isGuitarEquipped then
        return true, 10  -- Hide hands, high priority
    end
    return nil, 0  -- Default behavior
end)

-- Show pawn arms when climbing or playing guitar
pawnModule.registerIsPawnArmsHiddenCallback(function()
    if gameState.isClimbing or gameState.isGuitarEquipped then
        return false, 10  -- Show pawn arms, high priority
    end
    return nil, 0  -- Default behavior
end)

-- Helper to save current settings to profile
local function saveWeaponProfile()
    if currentWeaponName then
        if not Config.weaponProfiles[currentWeaponName] then Config.weaponProfiles[currentWeaponName] = {} end
        local profile = Config.weaponProfiles[currentWeaponName]
        profile.socket = Config.weaponSocketName
        profile.rotation = {Config.weaponHandRotation[1], Config.weaponHandRotation[2], Config.weaponHandRotation[3]}
        profile.location = {Config.weaponHandLocation[1], Config.weaponHandLocation[2], Config.weaponHandLocation[3]}
        profile.reloadSocket = Config.reloadSocketName
        profile.disableReloadAttachment = Config.disableReloadAttachment
        profile.reloadRotation = {Config.reloadHandRotation[1], Config.reloadHandRotation[2], Config.reloadHandRotation[3]}
        profile.reloadLocation = {Config.reloadHandLocation[1], Config.reloadHandLocation[2], Config.reloadHandLocation[3]}

        -- Save mag box config from mag_reload module
        local boxCfg = magReload.get_config()
        profile.magBox = {
            magSocket = boxCfg.magSocket,
            handX = boxCfg.handX, handY = boxCfg.handY, handZ = boxCfg.handZ,
            handOffX = boxCfg.handOffX, handOffY = boxCfg.handOffY, handOffZ = boxCfg.handOffZ,
            handRotX = boxCfg.handRotX, handRotY = boxCfg.handRotY, handRotZ = boxCfg.handRotZ,
            magX  = boxCfg.magX,  magY  = boxCfg.magY,  magZ  = boxCfg.magZ,
            magOffX = boxCfg.magOffX, magOffY = boxCfg.magOffY, magOffZ = boxCfg.magOffZ,
        }

        -- Save Scope Settings (Per Scope if available, otherwise just global config update - handled by Config:Save())
        if currentScopeName then
            -- print("Saving Scope Profile for: " .. currentScopeName)
            if not Config.scopeProfiles[currentScopeName] then Config.scopeProfiles[currentScopeName] = {} end
            local scopeProf = Config.scopeProfiles[currentScopeName]
            scopeProf.scopeOffset = Config.cylinderDepth
            scopeProf.scopeOffsetY = Config.cylinderOffsetY
            scopeProf.scopeOffsetZ = Config.cylinderOffsetZ
            scopeProf.scopeScale = Config.scopeDiameter
            scopeProf.scopeTubeDepth = Config.cylinderTubeDepth
            scopeProf.scopeMagnifier = Config.scopeMagnifier
            scopeProf.scopeBrightness = Config.scopeBrightnessAmplifier
        end
        
        Config:markDirty()
        Config:save()
    end
end

local lastCutsceneAimState = false  -- tracks aim method override separately from 2D toggle

local function handleCutscene2DMode()
    local isAnimPlaying = gameState.isAnimMontagePlaying

    -- Always switch aim method to Game during AnimMontage cutscenes, regardless of 2D toggle
    if isAnimPlaying ~= lastCutsceneAimState then
        if isAnimPlaying then
            uevr.params.vr.set_mod_value("VR_AimMethod", "0")     -- Game aim during cutscene
            uevr.params.vr.set_mod_value("UI_FollowView", "false") -- Disable follow view
        else
            uevr.params.vr.set_mod_value("VR_AimMethod", "1")     -- Restore HMD aim
            uevr.params.vr.set_mod_value("UI_FollowView", "true")  -- Restore follow view
        end
        lastCutsceneAimState = isAnimPlaying
    end

    -- 2D screen mode + stabilisation: only when toggle is enabled
    local is2DDesired = Config.cutscene2DModeEnabled and isAnimPlaying
    if is2DDesired ~= lastCutscene2DState then
        if is2DDesired then
            -- print("[Accessibility] AnimMontage detected, switching to 2D screen mode")
            uevrUtils.set_2D_mode(true)
            uevr.params.vr.set_mod_value("VR_DecoupledPitch", "false") -- Stop vertical drift
            uevr.params.vr.recenter_view()
            uevrUtils.enableCameraLerp(true, true, true, true)
        else
            -- print("[Accessibility] AnimMontage ended, restoring 3D mode")
            uevrUtils.set_2D_mode(false)
            uevr.params.vr.set_mod_value("VR_DecoupledPitch", "true")  -- Restore decoupled pitch
            uevrUtils.enableCameraLerp(false, true, true, true)
        end
        lastCutscene2DState = is2DDesired
    end
end

uevr.sdk.callbacks.on_pre_engine_tick(
    function(engine, delta)
        engineTickCount = engineTickCount + 1

        if gameState:IsLevelChanged(engine) then
            print("Level changed, resetting game state and motion controllers")
            currentPreset:Reset()
            motionControllerActors:Reset() -- Reset the motion controller actors
            gamepadState:Reset()
            -- Reset aim-method state machine so stale lastMenuState from the previous
            -- session doesn't suppress the menu-exit enforce window on load.
            lastMenuState = false
            lastConversationState = false
            lastClimbingState = false
            lastGuitarState = false
            _G.menuExitEnforceTicks = 0
            -- Force HMD aim immediately and hold it for 60 ticks (~1 s at 60 Hz).
            -- This stops the exo spawn-animation or any other load-time montage from
            -- briefly setting VR_AimMethod=0 and causing UEVR to lock in a wrong yaw.
            uevr.params.vr.set_mod_value("VR_AimMethod", "1")
            _G.levelLoadEnforceTicks = 60
        else
            gameState:Update()
            handleCutscene2DMode()
            motionControllerActors:Update(engine)

            -- Exoskeleton camera fix: the exo skeleton's jnt_camera bone has a -90° Yaw
            -- baked in, which makes UEVR think game-forward is 90° left of the pawn facing,
            -- causing thumbstick forward to move the character right instead of forward.
            -- Uses gameState._framePawn (safe cached ref from Update() above — nil when no pawn).
            local camFixPawn = gameState._framePawn
            if camFixPawn then
                local camComp = camFixPawn.Camera
                if camComp then
                    local relRot = camComp.RelativeRotation
                    if relRot and (relRot.Yaw < -0.1 or relRot.Yaw > 0.1) then
                        relRot.Yaw = 0.0
                    end
                end
            end


            -- Collision-based two-hand aiming: check foregrip box overlap each tick
            -- local pawnForTH = uevr.api:get_local_pawn(0)
            -- if pawnForTH then twoHand.update(pawnForTH) end
            
            -- Handle aim method switching for menus
            local currentMenuState = gameState.inMenu or gameState.isInventoryPDA
            if currentMenuState ~= lastMenuState then
                if currentMenuState then
                    -- Entering menu - switch to Game aim for fixed UI
                    uevr.params.vr.set_mod_value("VR_AimMethod", "0")  -- Game aim (fixed UI)
                    uevr.params.vr.set_mod_value("UI_FollowView", "false")  -- Game aim (fixed UI)
                    -- print("Menu opened - switched to Game aim method (0)")
                    _G.menuExitEnforceTicks = 0  -- cancel any pending HMD re-assertion
                else
                    -- Exiting menu - restore to HMD aim for gameplay
                    uevr.params.vr.set_mod_value("VR_AimMethod", "1")  -- HMD aim
                    uevr.params.vr.set_mod_value("UI_FollowView", "true")  -- Game aim (fixed UI)
                    -- print("Menu closed - restored to HMD aim method (1)")
                    -- ADS lockout: prevent Interactive ADS from firing immediately on menu close
                    -- (player's weapon hand may still be near HMD from navigating the UI)
                    _G.weaponNearHMD = false
                    _G.adsLockoutTicks = 30  -- ~500ms at 60Hz
                    -- Fix 3: deferred re-assertion — keeps HMD sticky for 15 ticks so that
                    -- conversation/climbing continuous enforcement can't stomp the restore
                    -- on the same frame or within the next ~165ms.
                    _G.menuExitEnforceTicks = 15
                end
                lastMenuState = currentMenuState
            end

            -- Fix 3: re-assert HMD aim each tick during the post-menu-close window.
            -- Outlasts conversation hysteresis (30 ticks) and UIManagerEx sync delays.
            if (_G.menuExitEnforceTicks or 0) > 0 then
                _G.menuExitEnforceTicks = _G.menuExitEnforceTicks - 1
                if not gameState.isClimbing then
                    uevr.params.vr.set_mod_value("VR_AimMethod", "1")
                end
            end

            -- Level-load enforce: hold HMD aim for 60 ticks after every level load/save-load.
            -- Takes priority over all other AimMethod=0 enforcement (montage, conversation,
            -- climbing, guitar) so the exo spawn animation can't rotate the player on load.
            if (_G.levelLoadEnforceTicks or 0) > 0 then
                _G.levelLoadEnforceTicks = _G.levelLoadEnforceTicks - 1
                uevr.params.vr.set_mod_value("VR_AimMethod", "1")
            end

            -- Continuous Enforcement: Ensure aim method stays at 0 while in UI
            -- Throttled to every 10 ticks to avoid per-tick C++ bridge calls
            if currentMenuState and engineTickCount % 10 == 0 then
                 uevr.params.vr.set_mod_value("VR_AimMethod", "0")
            end
            
            -- 0. Handle Guitar state - suppress item attachment while playing
            local currentGuitarState = gameState.isGuitarEquipped
            if currentGuitarState ~= lastGuitarState then
                -- print("[Guitar] State changed: " .. tostring(lastGuitarState) .. " -> " .. tostring(currentGuitarState))
                
                if currentGuitarState then
                    -- Started Playing
                    if not _G.SuppressItemAttachment then
                         -- print("[Guitar] Started - Suppressing item attachment")
                         _G.SuppressItemAttachment = true
                    end
                else
                    -- Stopped Playing
                    -- print("[Guitar] Ended")
                    
                    -- Restore Item Attachment (unless climbing or consuming)
                    if not gameState.isClimbing and not isConsumptionMontage(lastPlayedMontageName) then
                        -- print("[Guitar] Re-enabling item attachment")
                        _G.SuppressItemAttachment = false
                    end

                    -- Restore Aim Method (unless in Menu or Conversation or Climbing)
                    if not currentMenuState and not gameState.isConversation and not gameState.isClimbing then
                        uevr.params.vr.set_mod_value("VR_AimMethod", "1")  -- HMD aim
                        -- print("[Guitar] Restored HMD aim method (1)")
                    end
                end
                lastGuitarState = currentGuitarState
            end


            -- Maintain state for Guitar (throttled to every 10 ticks)
            if currentGuitarState and (_G.levelLoadEnforceTicks or 0) == 0 and engineTickCount % 10 == 0 then
                uevr.params.vr.set_mod_value("VR_AimMethod", "0")
            end


            -- Handle climbing state - suppress item attachment during ladder climbing
            -- Track state changes for debugging
            -- Handle climbing state - suppress item attachment during ladder climbing
            local currentClimbingState = gameState.isClimbing
            
            -- 1. Handle State Transitions (Event Driven)
            if currentClimbingState ~= lastClimbingState then
                -- print("[Climbing] State changed: " .. tostring(lastClimbingState) .. " -> " .. tostring(currentClimbingState))
                
                if currentClimbingState then
                    -- Started Climbing
                    if not _G.SuppressItemAttachment then
                         -- print("[Climbing] Started - Suppressing item attachment")
                         _G.SuppressItemAttachment = true
                    end
                else
                    -- Stopped Climbing
                    -- print("[Climbing] Ended")
                    
                    -- Restore Item Attachment (unless consuming)
                    if not isConsumptionMontage(lastPlayedMontageName) then
                        -- print("[Climbing] Re-enabling item attachment")
                        _G.SuppressItemAttachment = false
                    end

                    -- Restore Aim Method (unless in Menu or Conversation)
                    if not currentMenuState and not gameState.isConversation then
                        uevr.params.vr.set_mod_value("VR_AimMethod", "1")  -- HMD aim
                        -- print("[Climbing] Restored HMD aim method (1)")
                    else
                        -- print("[Climbing] Skipping aim restore - Menu/Conversation active")
                    end
                end
                lastClimbingState = currentClimbingState
            end
            
            -- 2. Maintain State (Frame Driven, throttled to every 10 ticks)
            if gameState.isClimbing and (_G.levelLoadEnforceTicks or 0) == 0 and engineTickCount % 10 == 0 then
                uevr.params.vr.set_mod_value("VR_AimMethod", "0")
            end


            -- Handle Conversation State (Game Aim for Zoomed FOV)
            local currentConversationState = gameState.isConversation
            if currentConversationState ~= lastConversationState then
                if currentConversationState then
                    -- print("Conversation/Zoom Detected (" .. tostring(Config.conversationFOVThreshold).." deg) - Switched to Game Aim")
                    if (_G.levelLoadEnforceTicks or 0) == 0 then
                        uevr.params.vr.set_mod_value("VR_AimMethod", "0")
                    end
                else
                    -- print("Conversation/Zoom Ended - Restoring Aim Method")
                    if not gameState.isClimbing and not currentMenuState then
                        uevr.params.vr.set_mod_value("VR_AimMethod", "1")
                    end
                end
                lastConversationState = currentConversationState
            end

            -- Fix 2: gate on not currentMenuState so this can't stomp a menu-close HMD restore
            -- during the conversation hysteresis window (~300ms after FOV returns to normal).
            -- Also gate on levelLoadEnforceTicks==0 to prevent false conversation detects on load.
            if gameState.isConversation and not currentMenuState
            and (_G.levelLoadEnforceTicks or 0) == 0 and engineTickCount % 10 == 0 then
                 uevr.params.vr.set_mod_value("VR_AimMethod", "0")
            end

            -- Interactive ADS distance check: evaluate if right controller is near HMD
            -- Throttled to 5 ticks. Suppressed for 30 ticks after weapon switch to prevent
            -- stale weaponNearHMD=true from immediately triggering ADS on new weapon.
            if Config.interactiveADS and engineTickCount % 5 == 0 then
                if (_G.adsLockoutTicks or 0) > 0 then
                    _G.adsLockoutTicks = _G.adsLockoutTicks - 1
                    _G.weaponNearHMD = false  -- keep ADS disabled during lockout
                else
                    if not controllers.hmdControllerExists() then
                        controllers.createHMDController()
                    end
                    local head_loc = controllers.getControllerLocation(2) -- HMD
                    local right_loc = controllers.getControllerLocation(1) -- Right Controller
                    if head_loc and right_loc then
                        local dx = head_loc.X - right_loc.X
                        local dy = head_loc.Y - right_loc.Y
                        local dz = head_loc.Z - right_loc.Z
                        local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
                        _G.weaponNearHMD = (dist <= (Config.interactiveADSDistance or 30.0))
                    else
                        _G.weaponNearHMD = true -- fallback if missing tracking
                    end
                end
            elseif not Config.interactiveADS then
                _G.weaponNearHMD = true
            end

            -- Throwable Aim Enforcement: bolt/knife/grenade must always use HMD aim.
            -- These items have no WeaponPushbackData, cause FOV dips, and trigger
            -- false isInventoryPDA/isConversation states. Positive enforcement is
            -- simpler and more reliable than suppressing each system individually.
            -- Throwable / bare hands HMD enforcement.
            -- Covers: bolt, knife, grenade (trajectory view zooms FOV, no WeaponPushbackData),
            -- and bare hands (holster animation leaves stale GunFiringState).
            local currentThrowableState = (currentWeaponName == nil)  -- bare hands
            if currentWeaponName then
                local n = currentWeaponName:lower()
                currentThrowableState = n:find("bolt") ~= nil
                    or n:find("knife")   ~= nil
                    or n:find("sk_f1")   ~= nil
                    or n:find("sk_rgd")  ~= nil
                    or n:find("grenade") ~= nil
            end
            if currentThrowableState ~= lastThrowableState then
                if currentThrowableState then
                    -- Throwable equipped: switch to HMD aim (yields to cutscene, climbing, conversation)
                    if not gameState.isAnimMontagePlaying and not gameState.isClimbing
                    and not gameState.isConversation then
                        uevr.params.vr.set_mod_value("VR_AimMethod", "1")
                        -- print("[Throwable] Equipped - enforcing HMD aim (1)")
                    end
                else
                    -- Throwable unequipped (bare hands or new weapon): restore HMD
                    -- unless another system needs Game aim
                    if not currentMenuState and not gameState.isClimbing
                    and not gameState.isConversation and not gameState.isGuitarEquipped then
                        uevr.params.vr.set_mod_value("VR_AimMethod", "1")
                        -- print("[Throwable] Unequipped - restored HMD aim (1)")
                    end
                end
                lastThrowableState = currentThrowableState
            end
            -- Continuous enforcement every 10 ticks while throwable active (yields to menus, cutscenes, climbing, conversation)
            if currentThrowableState and not currentMenuState
            and not gameState.isAnimMontagePlaying and not gameState.isClimbing
            and not gameState.isConversation and engineTickCount % 10 == 0 then
                uevr.params.vr.set_mod_value("VR_AimMethod", "1")
            end

            -- Use the weapon already resolved this tick by gameState:Update() — avoids a redundant C++ bridge call
            local currentWeaponMesh = gameState._frameWeapon
            local weaponChanged = currentWeaponMesh ~= lastWeaponMesh
            local wInfo = nil
            local currentScopeMesh = nil
            
            if currentWeaponMesh ~= nil then
                 wInfo = gameState:GetWeaponCache(currentWeaponMesh)
                 if wInfo then currentScopeMesh = wInfo.scope end
            end
            
            local scopeChanged = currentScopeMesh ~= lastScopeMesh

            if weaponChanged or scopeChanged then
                -- print("Weapon or Scope changed") -- Debug log
                if currentWeaponMesh ~= nil then
                    -- Weapon equipped
                    if wInfo then
                        currentWeaponName = wInfo.name
                    end
                    
                    if currentWeaponName then
                        -- Load Weapon Profile if exists (only on weapon change)
                        if weaponChanged then
                            -- Clear weapon cache on weapon swap: prevents stale data and memory accumulation
                            -- Cache is only useful for the current weapon so wiping it is always safe
                            gameState.weaponCache = {}

                            -- Interactive ADS lockout: prevent stale weaponNearHMD from immediately
                            -- triggering ADS on the new weapon before the player has raised it
                            _G.weaponNearHMD = false
                            _G.adsLockoutTicks = 30  -- ~500ms at 60Hz
                            if Config.weaponProfiles[currentWeaponName] then
                                -- print("Loading saved profile for " .. currentWeaponName)
                                local profile = Config.weaponProfiles[currentWeaponName]
                                if profile.socket then Config.weaponSocketName = profile.socket end
                                if profile.rotation then Config.weaponHandRotation = {profile.rotation[1], profile.rotation[2], profile.rotation[3]} end
                                if profile.location then Config.weaponHandLocation = {profile.location[1], profile.location[2], profile.location[3]} end
                                if profile.reloadSocket then Config.reloadSocketName = profile.reloadSocket end
                                if profile.disableReloadAttachment ~= nil then Config.disableReloadAttachment = profile.disableReloadAttachment else Config.disableReloadAttachment = false end
                                if profile.reloadRotation then Config.reloadHandRotation = {profile.reloadRotation[1], profile.reloadRotation[2], profile.reloadRotation[3]} end
                                if profile.reloadLocation then Config.reloadHandLocation = {profile.reloadLocation[1], profile.reloadLocation[2], profile.reloadLocation[3]} end
                            else
                                 -- print("No profile for " .. currentWeaponName .. ", resetting to defaults")
                                 -- Reset to defaults to avoid carry-over from previous weapon
                                 Config.weaponSocketName = "S_Hand_R"
                                 Config.weaponHandRotation = {0, 0, 0}
                                 Config.weaponHandLocation = {0, 0, 0}
                                 Config.reloadHandRotation = {-1.5, 0.6, -180.2}
                                 Config.reloadHandLocation = {0, 0, 0}
                                 Config.reloadSocketName = "jnt_l_hand"
                                 Config.disableReloadAttachment = false
                            end
                        end
                        
                        -- Load Scope Settings (on weapon or scope change)
                        if Config.weaponProfiles[currentWeaponName] or not Config.weaponProfiles[currentWeaponName] then
                            -- Reset Scope Defaults first
                            Config.cylinderDepth = 0.001
                            Config.scopeDiameter = 0.024
                            Config.scopeMagnifier = 0.7
                            Config.scopeBrightnessAmplifier = 1.0

                            -- Attempt to find attached scope (From Cache)
                            local scopeMesh = currentScopeMesh
                            currentScopeName = nil
                            
                            if scopeMesh then
                                if scopeMesh.SkeletalMesh then
                                    currentScopeName = uevrUtils.getShortName(scopeMesh.SkeletalMesh)
                                elseif scopeMesh.StaticMesh then
                                    currentScopeName = uevrUtils.getShortName(scopeMesh.StaticMesh)
                                else
                                    currentScopeName = uevrUtils.getShortName(scopeMesh)
                                end
                                
                                -- Sanitize cleaning of generated suffixes (e.g. CEA96A1...)
                                if currentScopeName then
                                    local cleanName = currentScopeName:gsub("[_]*%x%x%x%x%x%x%x%x+$", "")
                                    if cleanName ~= currentScopeName then
                                        -- print("Sanitized scope name: " .. currentScopeName .. " -> " .. cleanName)
                                        currentScopeName = cleanName
                                    end
                                end
                                
                                -- If we have a scope name, check for profile
                                if currentScopeName and Config.scopeProfiles[currentScopeName] then
                                    -- print("Loading Scope Profile for: " .. currentScopeName)
                                    local sProf = Config.scopeProfiles[currentScopeName]
                                    if sProf.scopeOffset then Config.cylinderDepth = sProf.scopeOffset end
                                    if sProf.scopeOffsetY then Config.cylinderOffsetY = sProf.scopeOffsetY else Config.cylinderOffsetY = 0.0 end
                                    if sProf.scopeOffsetZ then Config.cylinderOffsetZ = sProf.scopeOffsetZ else Config.cylinderOffsetZ = 0.0 end
                                    if sProf.scopeScale then Config.scopeDiameter = sProf.scopeScale end
                                    if sProf.scopeTubeDepth then Config.cylinderTubeDepth = sProf.scopeTubeDepth else Config.cylinderTubeDepth = 0.001 end
                                    if sProf.scopeMagnifier then Config.scopeMagnifier = sProf.scopeMagnifier end
                                    if sProf.scopeBrightness then Config.scopeBrightnessAmplifier = sProf.scopeBrightness end
                                end
                            end

                            -- Force update scope controller immediately to prevent race condition
                            if scopeController then
                                scopeController:SetScopePlaneScale(Config.cylinderDepth)
                            end
                        end
                    else
                        print("Could not identify weapon name, using defaults")
                        currentWeaponName = nil
                        Config.weaponSocketName = "S_Hand_R"
                        Config.weaponHandRotation = {0, 0, 0}
                        Config.weaponHandLocation = {0, 0, 0}
                        Config.reloadHandRotation = {-1.5, 0.6, -180.2}
                        Config.reloadHandLocation = {0, 0, 0}
                        Config.reloadSocketName = "jnt_l_hand"
                        Config.disableReloadAttachment = false
                    end

                    hands.attachHandToMesh(Config.dominantHand, currentWeaponMesh, Config.weaponSocketName, Config.weaponHandRotation, Config.weaponHandLocation)

                    -- Fix: right hand index finger sometimes shows in wrong pose after weapon switch.
                    -- The grip animation callback from attachments fires asynchronously and may arrive
                    -- before the attachment has fully settled, leaving the hand in its default bind pose.
                    -- Re-evaluating the animation state 150ms later ensures the correct finger pose is applied.
                    local snapWeaponMesh = currentWeaponMesh
                    uevrUtils.setTimeout(150, function()
                        if currentWeaponMesh == snapWeaponMesh then
                            hands.updateAnimationState(Handed.Right)
                        end
                    end)

                    -- Initialize mag reload collision boxes
                    local pawnForMag = uevr.api:get_local_pawn(0)
                    if pawnForMag then
                        magReload.init(pawnForMag, motionControllerActors.left_hand_component)
                        zoneDebug.init(pawnForMag)
                        -- Load per-weapon mag box config, fallback to global defaults
                        local weapBoxCfg = nil
                        if currentWeaponName and Config.weaponProfiles[currentWeaponName] then
                            weapBoxCfg = Config.weaponProfiles[currentWeaponName].magBox
                        end
                        if not weapBoxCfg then
                            weapBoxCfg = {
                                handX = Config.magHandBoxX or 0.17,
                                handY = Config.magHandBoxY or 0.11,
                                handZ = Config.magHandBoxZ or 0.15,
                                handOffX = Config.magHandOffX or -4.2,
                                handOffY = Config.magHandOffY or 0.3,
                                handOffZ = Config.magHandOffZ or -2.7,
                                handRotX = Config.magHandRotX or 0.0,
                                handRotY = Config.magHandRotY or 0.0,
                                handRotZ = Config.magHandRotZ or 7.0,
                                magX = Config.magScaleX or 0.3,
                                magY = Config.magScaleY or 0.2,
                                magZ = Config.magScaleZ or 0.5,
                                magOffX = Config.magLocalX or 0,
                                magOffY = Config.magLocalY or 0,
                                magOffZ = Config.magLocalZ or 0,
                            }
                        end
                        magReload.update_weapon_collision(pawnForMag, currentWeaponMesh, weapBoxCfg)

                        -- Two-hand foregrip box (per-weapon)
                        -- local thCfg = nil
                        -- if currentWeaponName and Config.weaponProfiles[currentWeaponName] then
                        --     thCfg = Config.weaponProfiles[currentWeaponName].twoHandBox
                        -- end
                        -- twoHand.update_weapon_collision(pawnForMag, currentWeaponMesh, thCfg)
                    end

                    -- Dynamic Pose Capture
                    local capWeaponMesh = currentWeaponMesh
                    local capWeaponName = currentWeaponName
                    uevrUtils.setTimeout(500, function()
                        -- Ensure weapon hasn't changed since timeout started, and we aren't in a montage, menu, or attachment mod animation
                        if capWeaponMesh == gameState:GetEquippedWeapon() and capWeaponName and not gameState.isMontageAttached and not gameState.inMenu and not gameState.isInventoryPDA and not isWeaponModMontageActive and not isMagazineMontageActive then
                            local pawn = gameState:GetLocalPawn()
                            if pawn and pawn.Mesh then
                                -- leftHandBones is now defined at the top level
                                local pose = hands.capturePoseFromMesh(pawn.Mesh, leftHandBones)
                            if pose then
                                -- Guard: Only save if the pose isn't a "fist" (simple heuristic: if most fingers are extremely curled)
                                -- For now, we rely on the montage/menu guard which is more reliable.
                                
                                if not Config.weaponProfiles[capWeaponName] then
                                    Config.weaponProfiles[capWeaponName] = {}
                                end
                                Config.weaponProfiles[capWeaponName].leftHandPose = pose
                                cachedLHPose = pose -- Update cache with new valid capture
                                -- print("[HandPose] Dynamically captured and cached left hand pose for " .. capWeaponName)
                                -- Debug: Verify the structure of the captured pose
                                for k, v in pairs(pose) do
                                    -- print("  " .. tostring(k) .. " = {" .. tostring(v[1]) .. ", " .. tostring(v[2]) .. ", " .. tostring(v[3]) .. "}")
                                    break -- Just print one to verify the structure
                                end
                                saveWeaponProfile()
                            end
                            end
                        end
                    end)
                else
                    -- Weapon unequipped, attach hand back to controller
                    hands.attachHandToController(Config.dominantHand)
                    currentWeaponName = nil
                    currentScopeName = nil
                    lastScopeMesh = nil
                end
                lastWeaponMesh = currentWeaponMesh
                lastScopeMesh = currentScopeMesh
            end
            
            if not gameState.isInventoryPDA and not gameState.inMenu then
                currentPreset:Update(EMPTY_CONTEXT)
                
                -- X-Button to R-Key mapping.
                -- If the X press was injected by the mag gesture (gestureFired flag set),
                -- call SendKeyDown('R') which sets isReloading=true → left-hand attachment.
                -- If it's a physical X press, call SendReloadKey() which pulses R to the
                -- game WITHOUT setting isReloading → no hand flicker.
                if XINPUT_GAMEPAD_X then
                    local isXPressed = gamepadState:isButtonPressed(XINPUT_GAMEPAD_X)
                    if isXPressed and not isXButtonHeld then
                        isXButtonHeld = true
                        if magReload.consumeGestureFired() then
                            gameState:SendKeyDown('R')   -- mag gesture: isReloading=true, hand attaches
                        else
                            gameState:SendReloadKey()    -- physical X: R fires, no hand attachment
                        end
                    elseif not isXPressed and isXButtonHeld then
                        isXButtonHeld = false
                        gameState:SendKeyUp('R')         -- resets isReloading if it was set
                    end
                end

                -- Shortcut to RESET poisoned hand poses (NumPad 0)
                -- We register this once to handle the keyboard event
                doOnce(function()
                    register_key_bind("NumPadZero", function()
                        if currentWeaponName and Config.weaponProfiles[currentWeaponName] then
                            Config.weaponProfiles[currentWeaponName].leftHandPose = nil
                            cachedLHPose = getSpecificHandPose(currentWeaponName) -- Re-load from JSON fallback
                            if cachedLHPose then
                                hands.setHandPose(0, cachedLHPose)
                            end
                            -- print("[HandPose] RESET dynamic pose for " .. currentWeaponName .. ". Reverting to JSON default.")
                            saveWeaponProfile()
                        end
                    end)
                end, Once.EVER)

                -- Specialized logic for hand attachment and pose
                local currentMontageState = gameState.isMontageAttached

                -- Fallback heartbeat for abruptly aborted montages (e.g., knockdown ragdolls)
                if currentMontageState and not gameState.isClimbing then
                     local pawn = gameState:GetLocalPawn()
                     if pawn and pawn.Mesh and pawn.Mesh.AnimScriptInstance then
                          local ok, isPlaying = pcall(function() return pawn.Mesh.AnimScriptInstance:IsAnyMontagePlaying() end)
                          if ok and isPlaying == false then
                               -- print("[MontageFallback] Detected stuck montage state. Forcing reset.")
                               gameState.isMontageAttached = false
                               currentMontageState = false
                          end
                     end
                end

                -- Climbing Override
                if gameState.isClimbing then
                    currentMontageState = true
                    lastPlayedMontageName = "Ladder"
                end
                local currentDetectorState = gameState.isDetectorEquipped
                local currentSupportHandState = gameState.isReloading or gameState.isTwoHanding or isReloadMontageActive or isMagazineMontageActive or isWeaponModMontageActive
                local currentReloadState = gameState.isReloading or isReloadMontageActive or isMagazineMontageActive or isWeaponModMontageActive
                local currentTwoHandingState = gameState.isTwoHanding

                -- Montage Attachment (Highest Priority, affects BOTH hands)
                if currentMontageState ~= lastMontageState then
                    local pawn = gameState:GetLocalPawn()
                    if pawn and pawn.Mesh then
                        if currentMontageState then
                            -- Cache the CURRENTLY APPLIED pose before the montage takes over
                            -- If we already have a profile-loaded pose or a dynamic one, it's already in cachedLHPose
                            -- But if we just equipped, we ensure it's up to date
                            if not cachedLHPose then
                                cachedLHPose = getSpecificHandPose(currentWeaponName)
                            end

                            if cachedLHPose then
                                -- print("[HandPose] Montage Start: Cached current LH pose for recovery.")
                            end

                            -- invalidating last state ensures that when we exit the montage, 
                            -- the check (current ~= last) will typically be true if buttons are held,
                            -- forcing a re-attach to the weapon.
                            lastSupportHandState = false 
                            lastReloadState = false
                            lastTwoHandingState = false
                            lastDetectorState = false

                            -- Determine Offsets
                            local leftRot = {0,0,0}
                            local leftLoc = {0,0,0}
                            local rightRot = {0,0,0}
                            local rightLoc = {0,0,0}
                            
                            -- Load from Config if available
                            local montageConfig = Config.montageAttachmentList[lastPlayedMontageName]
                            local lSocket = "jnt_l_ik_hand"
                            local rSocket = "jnt_r_ik_hand"

                            -- Override for Weapon Mods (Silencer/Sight)
                            if isWeaponModMontageActive then
                                lSocket = "jnt_l_weapon"
                            end

                            if montageConfig then
                                -- Deep copy values to avoid reference issues
                                if montageConfig.left then
                                     if montageConfig.left.rot then leftRot = {table.unpack(montageConfig.left.rot)} end
                                     if montageConfig.left.pos then leftLoc = {table.unpack(montageConfig.left.pos)} end
                                     if montageConfig.left.socket then lSocket = montageConfig.left.socket end
                                end
                                if montageConfig.right then
                                     if montageConfig.right.rot then rightRot = {table.unpack(montageConfig.right.rot)} end
                                     if montageConfig.right.pos then rightLoc = {table.unpack(montageConfig.right.pos)} end
                                     if montageConfig.right.socket then rSocket = montageConfig.right.socket end
                                end
                            end

                            -- Attach BOTH hands to Pawn mesh
                            hands.attachHandToMesh(0, pawn.Mesh, lSocket, leftRot, leftLoc) -- Left Hand
                            hands.attachHandToMesh(1, pawn.Mesh, rSocket, rightRot, rightLoc) -- Right Hand
                            
                            -- Apply Hand Poses (Ladder Specific)
                            if lastPlayedMontageName == "Ladder" then
                                if Config.ladderHandPoseLeft then hands.setHandPose(0, Config.ladderHandPoseLeft) end
                                if Config.ladderHandPoseRight then hands.setHandPose(1, Config.ladderHandPoseRight) end
                            end
                        else
                            -- Detach hands
                            hands.setInitialTransform(0)
                            hands.setInitialTransform(1)
                            hasAttachedModMesh = false -- Reset state on montage exit

                            -- Re-attach Dominant Hand to Weapon if equipped
                            local currentWeaponMesh = gameState:GetEquippedWeapon()
                            if currentWeaponMesh then
                                hands.attachHandToMesh(Config.dominantHand, currentWeaponMesh, Config.weaponSocketName, Config.weaponHandRotation, Config.weaponHandLocation)
                                -- Force 'Holding' state first as a generic baseline (fixes open hand after climbing).
                                -- This must come BEFORE registerGrippedAttachment: the grip animation
                                -- callback (Entry.lua) will overwrite this with the specific ID string
                                -- (e.g. "rhino") so the xinput handler applies the correct per-weapon pose.
                                hands.setHoldingAttachment(Config.dominantHand, true)
                                -- Now restore the per-weapon grip animation. The gripAnimationCallback
                                -- fires synchronously here and sets holdingAttachment to e.g. "rhino",
                                -- overriding the generic true above.
                                if not isMeleeItem(currentWeaponName) then
                                    attachments.registerGrippedAttachment(Config.dominantHand, currentWeaponMesh, currentWeaponName)
                                end
                                hands.updateAnimationState(Config.dominantHand)

                                
                                -- Non-dominant hand goes to controller (unless support logic catches it)
                                local offHand = 1 - Config.dominantHand
                                hands.attachHandToController(offHand)
                                
                                if isSimulatingAttachment and offHand == 0 then
                                     if currentSimulationPose then
                                         hands.setHandPose(0, currentSimulationPose)
                                     else
                                         hands.setHoldingAttachment(0, true)
                                         hands.updateAnimationState(0)
                                     end
                                end
                            else
                                -- No weapon, both to controllers
                                hands.attachHandToController(0)
                                if isSimulatingAttachment then
                                     if currentSimulationPose then
                                         hands.setHandPose(0, currentSimulationPose)
                                     else
                                         hands.setHoldingAttachment(0, true)
                                         hands.updateAnimationState(0)
                                     end
                                end
                                hands.attachHandToController(1)
                            end
                            
                            -- Right Hand Override Logic (Knife, Bolt, Grenade, Bare Hands)
                            -- Apply customized pose to dominant hand if applicable
                            local rhPose = getSpecificRightHandPose(currentWeaponName)
                            if rhPose then
                                hands.setHandPose(Config.dominantHand, rhPose)
                            end
                        end
                    end
                    lastMontageState = currentMontageState
                end

                -- Continuous Check for Weapon Mod Mesh Attachment
                -- Handles race condition where montage starts before specific mod flag is set
                if isWeaponModMontageActive then
                    if not hasAttachedModMesh then
                        -- Throttle: scan every 3 ticks (~33ms at 90Hz) to avoid 90Hz AttachChildren walks
                        modMeshScanTick = modMeshScanTick + 1
                        if modMeshScanTick % 3 ~= 0 then goto modMeshScanDone end
                        local pawn = gameState:GetLocalPawn()
                        -- print("[Debug] Continuous Check: Searching for Mod Mesh...")
                        local modMesh = gameState:get_weapon_attachment_mesh(pawn)
                        if modMesh then
                            local leftHandComp = hands.getHandComponent(0) -- 0 is Left Hand
                            if leftHandComp then
                                -- print("[Debug] Attaching Mod Mesh to Left VR Hand")
                                modMesh:DetachFromParent(true, true)
                                modMesh:K2_AttachToComponent(leftHandComp, uevrUtils.fname_from_string("None"), 2, true) -- SnapToTarget
                                
                                hasAttachedModMesh = true
                                attachedModMesh = modMesh -- Store reference for cleanup
                                
                                -- Load Profile
                                local rawName = modMesh:get_fname():to_string()
                                local cleanName = GetCleanAttachmentName(rawName)
                                
                                currentAttachmentName = cleanName
                                -- print("[Debug] Loading Profile for Attachment: " .. cleanName)
                                
                                if Config.attachmentProfiles[cleanName] then
                                    -- print("[Debug] Profile Found! Applying offsets.")
                                    local prof = Config.attachmentProfiles[cleanName]
                                    Config.weaponModMeshOffset = {X=prof.offset.X, Y=prof.offset.Y, Z=prof.offset.Z}
                                    Config.weaponModMeshRotation = {Pitch=prof.rotation.Pitch, Yaw=prof.rotation.Yaw, Roll=prof.rotation.Roll}
                                    if prof.cleanupDelay then
                                        Config.weaponModCleanupDelay = prof.cleanupDelay
                                    end
                                else
                                    -- print("[Debug] No Profile Found. Resetting offsets.")
                                    Config.weaponModMeshOffset = {X=0.0, Y=0.0, Z=0.0}
                                    Config.weaponModMeshRotation = {Pitch=0.0, Yaw=0.0, Roll=0.0}
                                    Config.weaponModCleanupDelay = 1.0
                                end

                                -- Apply User Configurable Offset/Rotation
                                uevrUtils.set_component_relative_transform(modMesh, Config.weaponModMeshOffset, Config.weaponModMeshRotation)
                            end
                        end
                        ::modMeshScanDone::
                    elseif attachedModMesh and not isSimulatingAttachment then
                         -- NEW ATTACHMENT DETECTION CLEANUP (with delay)
                         -- Throttle: child-walk every 10 ticks (~111ms). Delay requires >0.5s anyway.
                         modMeshCleanupTick = modMeshCleanupTick + 1
                         if modMeshCleanupTick % 10 == 0 then
                         if UEVR_UObjectHook.exists(attachedModMesh) then
                             local currentWeaponMesh = gameState:GetEquippedWeapon()
                             if currentWeaponMesh and currentWeaponMesh.AttachChildren then
                                 -- Get the clean name pattern we're looking for
                                 local cleanName = currentAttachmentName
                                 
                                 -- Search weapon's children for matching attachment
                                 for _, child in ipairs(currentWeaponMesh.AttachChildren) do
                                     if child and UEVR_UObjectHook.exists(child) then
                                         local childName = child:get_fname():to_string()
                                         -- Check if this child matches our attachment pattern
                                         if cleanName and string.find(childName, cleanName, 1, true) then
                                             -- Check if enough time has passed (0.5 seconds)
                                             if not attachedModMeshTime then
                                                 attachedModMeshTime = os.clock()
                                             end
                                             
                                             local elapsed = os.clock() - attachedModMeshTime
                                             if elapsed >= Config.weaponModCleanupDelay then
                                                 -- print("[Debug] Found new attachment on weapon: " .. childName)
                                                 -- print("[Debug] Cleaning up VR hand duplicate (after " .. string.format("%.2f", elapsed) .. "s)")
                                                 
                                                 -- Destroy the duplicate mesh attached to VR hand
                                                 if attachedModMesh.K2_DestroyComponent then
                                                     attachedModMesh:K2_DestroyComponent(attachedModMesh)
                                                 else
                                                     attachedModMesh:DetachFromParent(true, true)
                                                     attachedModMesh:SetHiddenInGame(true, true)
                                                 end
                                                 
                                                 -- Save the name for simulation before clearing
                                                 lastCleanAttachmentName = currentAttachmentName
                                                 
                                                 attachedModMesh = nil
                                                 hasAttachedModMesh = false
                                                 currentAttachmentName = nil
                                                 attachedModMeshTime = nil
                                             end
                                             break
                                         end
                                     end
                                 end
                             end
                         else
                             -- Mesh no longer exists, clean up reference
                             attachedModMesh = nil
                             hasAttachedModMesh = false
                             currentAttachmentName = nil
                             attachedModMeshTime = nil
                         end
                         end -- throttle gate (modMeshCleanupTick % 10)
                    end
                elseif hasAttachedModMesh then
                     -- Cleanup: Montage ended, but flag is still true. Destroy the mesh!
                     -- print("[Debug] Weapon Mod Montage Ended - Cleaning up Mod Mesh")
                     if attachedModMesh then
                         if UEVR_UObjectHook.exists(attachedModMesh) then 
                             -- Attempt to destroy the component to remove the floating copy
                             -- If K2_DestroyComponent is available (standard UE function)
                             if attachedModMesh.K2_DestroyComponent then
                                 attachedModMesh:K2_DestroyComponent(attachedModMesh)
                             else
                                 -- Fallback: Detach and Hide
                                 attachedModMesh:DetachFromParent(true, true)
                                 attachedModMesh:SetHiddenInGame(true, true)
                             end
                         end
                         attachedModMesh = nil
                     end
                     hasAttachedModMesh = false
                end

                -- If Montage is active, skip other hand logic to prevent fighting
                if not currentMontageState then
                    if currentSupportHandState ~= lastSupportHandState or 
                       currentReloadState ~= lastReloadState or 
                       currentTwoHandingState ~= lastTwoHandingState or
                       currentDetectorState ~= lastDetectorState or
                        currentWeaponName ~= lastWeaponName or
                        lastMontageState or
                        (not isWeaponModMontageActive and lastWeaponModState) then -- Re-evaluate if we just exited a montage or weapon mod animation

                        -- Cache the pose update when weapon changes (or state refreshes)
                        if currentWeaponName ~= lastWeaponName or lastMontageState then
                             cachedRHPose = getSpecificRightHandPose(currentWeaponName)
                             -- For bare hands: apply the open-palm baseline immediately as a
                             -- one-shot reset so fingers start from the correct resting position.
                             -- The per-frame block below intentionally skips bare-hand
                             -- re-application so handleInputTwoHanded() can drive finger
                             -- animations (trigger curl, grip, thumbrest) freely on top.
                             if cachedRHPose and not currentWeaponName then
                                 hands.setHandPose(Config.dominantHand, cachedRHPose)
                             end
                             -- Defer grip registration by one tick so the CharacterMesh
                             -- component has time to update before we capture it.
                             pendingGripRegistration = true
                         pendingGripRetries = 5  -- retry up to 5 ticks if weapon mesh not ready yet
                        end

                        
                        local weaponMesh = gameState:GetEquippedWeapon()
                        local supportHand = 1 - Config.dominantHand
                        if currentWeaponName ~= lastWeaponName then
                            -- print("[HandPose] Weapon Name Changed: '" .. tostring(lastWeaponName) .. "' -> '" .. tostring(currentWeaponName) .. "'")
                        end

                        if currentSupportHandState or currentDetectorState then
                            -- Attachment logic (Weapon only)
                            if (currentSupportHandState and (currentSupportHandState ~= lastSupportHandState or lastMontageState)) or (currentTwoHandingState and currentWeaponName ~= lastWeaponName) then
                                if weaponMesh then
                                    if not Config.disableReloadAttachment then
                                        hands.attachHandToMesh(supportHand, weaponMesh, Config.reloadSocketName or "jnt_l_hand", Config.reloadHandRotation, Config.reloadHandLocation)
                                        -- Force pose restoration (Prefer cached pose to avoid "montage-clobbered" captures)
                                        local handPose = cachedLHPose or getSpecificHandPose(currentWeaponName)
                                        if handPose then
                                            hands.setHandPose(supportHand, handPose)
                                            -- print("[HandPose] Restored CORRECT pose for " .. tostring(currentWeaponName))
                                        end
                                    else
                                        -- If disabled, ensure we are on controller (detach from gun if needed)
                                        hands.attachHandToController(supportHand)
                                        -- hands.setInitialTransform(supportHand) -- Optional: Reset offsets if needed
                                    end
                                end

                                -- Debug Pose Matching on State Start
                                if currentTwoHandingState and currentWeaponName then
                                    -- getSpecificHandPose(currentWeaponName, true)
                                end
                            end
                            
                            -- Return to controller logic (If detector is just active without reload/two-handing)
                            if not currentSupportHandState and currentDetectorState then
                                 hands.attachHandToController(supportHand)
                            end
                        else
                            -- Detach handlers if we just stopped using support/detector
                            local supportHand = 1 - Config.dominantHand
                            hands.attachHandToController(supportHand)
                            hands.setInitialTransform(supportHand)
                            -- Clear the stale animation lock so the xinput handler drives free-hand
                            -- finger animation (left_grip / left_trigger) instead of the static
                            -- grip_left_weapon pose from the last reload/two-hand session.
                            -- Without this, holdingAttachment[supportHand] stays truthy (true / weapon
                            -- ID string), handleInputTwoHanded treats the hand as weapon-gripping, and
                            -- left_grip/left_trigger inputs are permanently ignored — freezing the hand
                            -- in an open pose regardless of controller input.
                            hands.setHoldingAttachment(supportHand, false)
                            hands.updateAnimationState(supportHand)  -- triggers open_left, enables finger lerps
                        end
                        
                        lastSupportHandState = currentSupportHandState
                        lastReloadState = currentReloadState
                        lastTwoHandingState = currentTwoHandingState
                        lastDetectorState = currentDetectorState
                        lastWeaponName = currentWeaponName
                        lastWeaponModState = isWeaponModMontageActive
                    end

                    -- Deferred grip registration: fires one tick after weapon name changed,
                    -- then retries up to pendingGripRetries more times if the weapon mesh is not ready.
                    -- Uses gameState._frameWeapon (cached at top of this tick) instead of a fresh
                    -- GetEquippedWeapon() call to avoid per-call nil races.
                    if pendingGripRegistration then
                        local weaponComp = gameState._frameWeapon
                        -- print("[DIAG-PENDING] pendingGripRegistration tick: weaponComp=", tostring(weaponComp and weaponComp:get_full_name() or "NIL"), " currentWeaponName=", tostring(currentWeaponName), " retries=", tostring(pendingGripRetries))
                        if weaponComp ~= nil and currentWeaponName and not isMeleeItem(currentWeaponName) then
                            -- Got a valid mesh — register and stop retrying
                            pendingGripRegistration = false
                            pendingGripRetries = 0
                            attachments.registerGrippedAttachment(Config.dominantHand, weaponComp, currentWeaponName)
                        elseif currentWeaponName == nil or isMeleeItem(currentWeaponName) then
                            -- No firearm expected — unregister immediately
                            pendingGripRegistration = false
                            pendingGripRetries = 0
                            attachments.unregisterGrippedAttachment(Config.dominantHand)
                        elseif pendingGripRetries > 0 then
                            -- weaponComp still nil but weapon is expected: retry next tick
                            pendingGripRetries = pendingGripRetries - 1
                            -- leave pendingGripRegistration = true so we try again
                        else
                            -- Out of retries — give up, leave existing registration intact
                            print("[DIAG-PENDING] OUT OF RETRIES - giving up on grip registration for", tostring(currentWeaponName))
                            pendingGripRegistration = false
                        end
                    end

                    -- FORCE RIGHT HAND POSE OVERRIDE
                    -- Melee / throwable items (knife, bolt, grenade): apply their static grip
                    -- every frame so the hand stays locked in the correct shape regardless of
                    -- what handleInputTwoHanded() does with the finger lerps.
                    --
                    -- Bare hands (cachedRHPose set but currentWeaponName == nil): the baseline
                    -- open-palm pose was already applied once in the weapon-change block above.
                    -- Do NOT re-apply here — doing so would erase the 100ms finger-curl lerp
                    -- that handleInputTwoHanded() is running in the xinput callback, leaving
                    -- fingers permanently frozen in the static open-palm shape.
                    if cachedRHPose then
                        if currentWeaponName then
                            -- Melee / throwable: lock fingers in the static grip every frame
                            hands.setHandPose(Config.dominantHand, cachedRHPose)
                        end
                        -- Either way, record that an override is active
                        lastRightHandOverride = true
                    elseif lastRightHandOverride then
                        -- Override released (switched to a firearm) -> re-sync grip pose
                        hands.updateAnimationState(Config.dominantHand)
                        lastRightHandOverride = false
                    end
                    
                    -- Pose Logic (Run every frame to ensure persistence)
                    if currentSupportHandState or currentDetectorState then
                         local supportHand = 1 - Config.dominantHand
                         
                         if currentDetectorState then
                             if not Config.disableDetectorPose then
                                 local detPose = nil
                                 if _G.DetectorSystem then
                                     local detName = _G.DetectorSystem.GetCurrentDetectorName()
                                     if detName and specificHandPoses[detName] then
                                         detPose = specificHandPoses[detName]["off"]
                                     end
                                 end
                                 
                                 if detPose then
                                     hands.setHandPose(supportHand, detPose)
                                 else
                                     hands.setHandPose(supportHand, Config.detectorHandPose)
                                 end
                             end
                         elseif currentReloadState then
                             hands.setHandPose(supportHand, Config.reloadHandPose)
                         elseif currentTwoHandingState then
                             -- Try to get session-cached pose first, then weapon-specific profile pose
                             local specificPose = cachedLHPose or getSpecificHandPose(currentWeaponName)
                             if specificPose then
                                 hands.setHandPose(supportHand, specificPose)
                             else
                                 -- Fallback: Use rifle pose for non-pistols, pistol pose for pistols
                                 -- print("[HandPose] FALLBACK TRIGGERED for: " .. tostring(currentWeaponName))
                                 if isPistolWeapon(currentWeaponName) then
                                     hands.setHandPose(supportHand, Config.twoHandedHandPose)
                                 else
                                     hands.setHandPose(supportHand, Config.twoHandedRifleHandPose)
                                 end
                             end
                         else
                             hands.setInitialTransform(supportHand)
                         end
                    end
            end
        end
    end
end)

uevr.sdk.callbacks.on_xinput_get_state(function(retval, user_index, state)
    -- X <-> B swap (applied unconditionally before any guards)
    if state ~= nil and Config.swapXandB then
        local buttons = state.Gamepad.wButtons
        local hasX = (buttons & 0x4000) ~= 0 -- XINPUT_GAMEPAD_X
        local hasB = (buttons & 0x2000) ~= 0 -- XINPUT_GAMEPAD_B
        if hasX then
            buttons = buttons & ~0x4000
            buttons = buttons | 0x2000
        elseif hasB then
            buttons = buttons & ~0x2000
            buttons = buttons | 0x4000
        end
        state.Gamepad.wButtons = buttons
    end

    if gameState.inMenu or gameState.isInventoryPDA then return end

    -- Mag reload input check
    local dpawn = uevr.api:get_local_pawn(0)
    if dpawn then
        magReload.check_reload_input(state, dpawn)
    end

    -- Scope Brightness Control (Left Thumbrest modifier + right stick Y)
    local isModifierPressed = false
    if vr.is_using_controllers() and vr.is_openxr() then
        local leftControllerSource = vr.get_left_joystick_source()
        if vr.is_action_active(thumbrestLeftHandle, leftControllerSource) then
            isModifierPressed = true
        end
    end

    if gameState:is_scope_active(gameState:GetLocalPawn()) and isModifierPressed then
        local ry = state.Gamepad.sThumbRY
        if math.abs(ry) > 4000 then
            local delta = (ry / 32768.0) * 0.02
            Config.scopeBrightnessAmplifier = math.max(0.0, math.min(3.0, Config.scopeBrightnessAmplifier + delta))
            if scopeController then
                scopeController:SetScopeBrightness(Config.scopeBrightnessAmplifier)
            end
            state.Gamepad.sThumbRY = 0
            brightnessDirty = true
        end
    elseif brightnessDirty then
        saveWeaponProfile()
        brightnessDirty = false
        -- print("Scope Brightness Saved: " .. tostring(Config.scopeBrightnessAmplifier))
    end

    gamepadState:Update(state)
end)

uevr.sdk.callbacks.on_script_reset(function()
    -- print("Resetting")
    currentPreset:Reset()
    gameState:Reset() -- Reset the game state to initial conditions
    motionControllerActors:Reset() -- Reset the motion controller actors
    gamepadState:Reset()
end)

-- Load config at script init
updateConfig(Config)

-- Helper to set integer console variables (live)
local function set_cvar_int(cvar, value)
    local console_manager = uevr.api:get_console_manager()
    local var = console_manager:find_variable(cvar)
    if var ~= nil then
        var:set_int(value)
    end
end

-- Helper to set float console variables (live)
local function set_cvar_float(cvar, value)
    local console_manager = uevr.api:get_console_manager()
    local var = console_manager:find_variable(cvar)
    if var ~= nil then
        var:set_float(value)
    end
end

local function apply_compatibility_cvars()
    -- Reflections & Water
    set_cvar_int("r.RefractionQuality",             Config.refractionEnabled and 1 or 0)
    set_cvar_int("r.SSR.Quality",                   Config.ssrQuality)
    set_cvar_int("r.Water.SingleLayer.Reflections", Config.waterReflections and 1 or 0)
    set_cvar_int("r.Water.SingleLayer.Refraction",  Config.waterRefraction and 1 or 0)
    set_cvar_int("r.Translucency.TemporalAA.Alpha", Config.translucencyFix and 1 or 0)
    -- Lighting & GI
    set_cvar_int("r.Lumen.Reflections.Temporal",    Config.lumenReflectionsTemporal and 1 or 0)
    set_cvar_int("r.Lumen.DiffuseIndirect.Allow",   Config.lumenDiffuseIndirect and 1 or 0)
    set_cvar_int("r.Lumen.ScreenProbeGather.VisualizeTraces", Config.lumenScreenProbeVisualize and 1 or 0)
    -- Eye Adaptation
    set_cvar_int("r.EyeAdaptation.MethodOverride",  Config.eyeAdaptationFixed and 0 or -1)
    set_cvar_int("r.EyeAdaptation.IgnoreMaterials", Config.eyeAdaptationIgnoreMaterials and 1 or 0)
    -- Atmosphere
    set_cvar_int("r.VolumetricCloud",               Config.volumetricClouds and 1 or 0)
    set_cvar_int("r.VolumetricFog",                 Config.volumetricFog and 1 or 0)
    -- Shadows
    set_cvar_int("r.DistanceFieldShadowing",        Config.distanceFieldShadowing and 1 or 0)
    set_cvar_int("r.GlobalDistanceField",           Config.globalDistanceField and 1 or 0)
    set_cvar_int("r.SSFS",                          Config.ssfsEnabled and 1 or 0)
    set_cvar_int("r.ShadowQuality",                 Config.shadowQuality or 4)
    set_cvar_int("r.DynamicGlobalIlluminationMethod", Config.dynamicGIMethod or 0)
    -- Post-Process & Performance
    set_cvar_int("r.postprocessing.disablematerials", Config.postprocessingDisabled and 1 or 0)
    
    -- VR TAA / TSR Temporal History Smearing Fixes
    if Config.taaSmearingFixEnabled then
        set_cvar_int("r.TSR.History.ScreenPercentage", 100)
        set_cvar_int("r.TemporalAA.HistoryScreenPercentage", 100)
        set_cvar_int("r.TSR.Velocity.Extrapolation", 1)
    else
        set_cvar_int("r.TSR.History.ScreenPercentage", 0)
        set_cvar_int("r.TemporalAA.HistoryScreenPercentage", 0)
        set_cvar_int("r.TSR.Velocity.Extrapolation", 0)
    end

    -- Float CVars
    set_cvar_float("r.ViewDistanceScale",            Config.viewDistanceScale or 1.0)
    set_cvar_float("fg.CullDistanceScale.Grass",     Config.grassCullScale or 1.0)
    set_cvar_float("foliage.DensityScale",           Config.foliageDensity or 1.0)
    set_cvar_float("foliage.LODDistanceScale",       Config.foliageLODScale or 1.0)
end

-- Config UI as a collapsing header
uevr.lua.add_script_panel("Stalker 2 VR", function()
    imgui.push_style_color(0, 0xFF00FF00) -- Text color: Green
    local headerOpen = imgui.collapsing_header("Stalker 2 VR Config")
    imgui.pop_style_color(1)
    if not headerOpen then return end

    local changed = false

    -- 1. Gameplay Experience Options
    imgui.text("Gameplay Experience Options:")
    
    local sitChanged, newSit = imgui.checkbox("Sitting Experience", Config.sittingExperience)
    if sitChanged then Config.sittingExperience = newSit; changed = true end

    local cut2DChanged, newCut2D = imgui.checkbox("2D Screen Cutscenes (Virtual Desktop only)", Config.cutscene2DModeEnabled)
    if cut2DChanged then Config.cutscene2DModeEnabled = newCut2D; changed = true end

    local hudChanged, newHideHUD = imgui.checkbox("Hide HUD (HUD Toggle)", Config.hideHUD)
    if hudChanged then
        Config.hideHUD = newHideHUD
        uevr.params.vr.set_mod_value("VR_EnableGUI", newHideHUD and "false" or "true")
        changed = true
    end

    local interactiveADSChanged, newInteractiveADS = imgui.checkbox("Interactive ADS (Aim by raising weapon)", Config.interactiveADS)
    if interactiveADSChanged then Config.interactiveADS = newInteractiveADS; changed = true end

    if Config.interactiveADS then
        local adsDistChanged, newAdsDist = imgui.slider_float("ADS Activation Distance (cm)", Config.interactiveADSDistance or 30.0, 10.0, 60.0)
        if adsDistChanged then Config.interactiveADSDistance = newAdsDist; changed = true end
    end

    local swapChanged, newSwap = imgui.checkbox("Swap X and B Buttons", Config.swapXandB)
    if swapChanged then Config.swapXandB = newSwap; changed = true end


    local hapticChanged, newHaptic = imgui.checkbox("Haptic Feedback (Gestures)", Config.hapticFeedback)
    if hapticChanged then Config.hapticFeedback = newHaptic; changed = true end

    local recoilChanged, newRecoil = imgui.checkbox("Recoil", Config.recoil)
    if recoilChanged then Config.recoil = newRecoil; changed = true end

    local twoHandedChanged, newTwoHanded = imgui.checkbox("Two-Handed Aiming", Config.twoHandedAiming)
    if twoHandedChanged then Config.twoHandedAiming = newTwoHanded; changed = true end

    local shadowsChanged, newShadows = imgui.checkbox("VR Hand & Weapon Shadows", Config.vrShadowsEnabled)
    if shadowsChanged then Config.vrShadowsEnabled = newShadows; changed = true end
    imgui.text("Enables dynamic shadows cast by VR hands and weapons. May reduce performance.")

    local stabChanged, newStab = imgui.checkbox("Renderer Stabilizer (Fake Flashlight)", Config.rendererStabilizerEnabled)
    if stabChanged then
        Config.rendererStabilizerEnabled = newStab
        changed = true
        -- Apply immediately: spawn or destroy the fake light
        if newStab then
            spawnRendererStabilizer()
        else
            destroyRendererStabilizer()
        end
    end
    imgui.text("Attaches an invisible point light to the player to fix temporal 'trailing lines' glitches.")

    local rdChanged, newRD = imgui.checkbox("Enable custom Red Dot Reticule and scope material fix", Config.reflexEnabled ~= false)
    if rdChanged then Config.reflexEnabled = newRD; Config:save() end

    local pipChanged, newPip = imgui.checkbox("Enable PiP Scopes (cylinder + scene capture rendering)", Config.pipScopesEnabled ~= false)
    if pipChanged then
        Config.pipScopesEnabled = newPip
        -- When disabling, immediately destroy all active PiP components (cylinder, RT, SCC)
        if not newPip and scopeController then
            pcall(function() scopeController:Reset() end)
        end
        changed = true
    end
    imgui.text("Disable to turn off all PiP scope rendering (no render target, no scene capture, no cylinder).")

    imgui.spacing()
    imgui.separator()
    imgui.spacing()

    -- 2. Gestures Toggles
    if imgui.collapsing_header("Gestures Toggles") then
        local flashlightChanged, newFlashlight = imgui.checkbox("Flashlight (head using right hand)", Config.gestures.flashlight)
        if flashlightChanged then Config.gestures.flashlight = newFlashlight; changed = true end

        local nvChanged, newNV = imgui.checkbox("Night Vision (head using left hand)", Config.gestures.nightVision)
        if nvChanged then Config.gestures.nightVision = newNV; changed = true end

        local primaryWeaponChanged, newPrimaryWeapon = imgui.checkbox("Primary Weapon (right shoulder using right hand)", Config.gestures.primaryWeapon)
        if primaryWeaponChanged then Config.gestures.primaryWeapon = newPrimaryWeapon; changed = true end

        local secondaryWeaponChanged, newSecondaryWeapon = imgui.checkbox("Secondary Weapon (left shoulder using right hand)", Config.gestures.secondaryWeapon)
        if secondaryWeaponChanged then Config.gestures.secondaryWeapon = newSecondaryWeapon; changed = true end

        local sidearmWeaponChanged, newSidearmWeapon = imgui.checkbox("Sidearm Weapon (right hip using right hand)", Config.gestures.sidearmWeapon)
        if sidearmWeaponChanged then Config.gestures.sidearmWeapon = newSidearmWeapon; changed = true end

        local meleeWeaponChanged, newMeleeWeapon = imgui.checkbox("Melee Weapon (left hip using left hand)", Config.gestures.meleeWeapon)
        if meleeWeaponChanged then Config.gestures.meleeWeapon = newMeleeWeapon; changed = true end

        local boltActionChanged, newBoltAction = imgui.checkbox("Bolts (right chest using right hand)", Config.gestures.boltAction)
        if boltActionChanged then Config.gestures.boltAction = newBoltAction; changed = true end

        local grenadeChanged, newGrenade = imgui.checkbox("Grenade (left chest using left hand)", Config.gestures.grenade)
        if grenadeChanged then Config.gestures.grenade = newGrenade; changed = true end

        local inventoryChanged, newInventory = imgui.checkbox("Inventory Backpack (right shoulder using left hand)", Config.gestures.inventory)
        if inventoryChanged then Config.gestures.inventory = newInventory; changed = true end

        local scannerChanged, newScanner = imgui.checkbox("Detector (right chest using left hand)", Config.gestures.scanner)
        if scannerChanged then Config.gestures.scanner = newScanner; changed = true end

        local pdaChanged, newPda = imgui.checkbox("PDA (left chest using right hand)", Config.gestures.pda)
        if pdaChanged then Config.gestures.pda = newPda; changed = true end

        local reloadChanged, newReload = imgui.checkbox("Reload (magazine using off-hand)", Config.gestures.reload)
        if reloadChanged then Config.gestures.reload = newReload; changed = true end

        local modeSwitchChanged, newModeSwitch = imgui.checkbox("Mode Switch (weapon fire mode using left hand)", Config.gestures.modeSwitch)
        if modeSwitchChanged then Config.gestures.modeSwitch = newModeSwitch; changed = true end

        local weaponCustomChanged, newWeaponCustom = imgui.checkbox("Weapon Customization (left shoulder using left hand)", Config.gestures.weaponCustomization)
        if weaponCustomChanged then Config.gestures.weaponCustomization = newWeaponCustom; changed = true end

        if Config.pickupInventoryEnabled == nil then Config.pickupInventoryEnabled = true end
        local invChanged, invVal = imgui.checkbox("Add Item to Inventory (release grabbed item over left shoulder)", Config.pickupInventoryEnabled)
        if invChanged then Config.pickupInventoryEnabled = invVal; changed = true end
    end

    -- 3. Compatibility CVars
    if imgui.collapsing_header("Compatibility CVars") then

        -- ── Reflections & Water ──────────────────────────────────────────
        if imgui.tree_node("Reflections & Water") then
            local refChanged, newRef = imgui.checkbox("Enable Refraction (r.RefractionQuality)", Config.refractionEnabled)
            if refChanged then Config.refractionEnabled = newRef; set_cvar_int("r.RefractionQuality", newRef and 1 or 0); changed = true end
            imgui.text("OFF = fixes DLSS flickering in rain/puddles.")

            local ssrChanged, newSsr = imgui.slider_int("SSR Quality (r.SSR.Quality)", Config.ssrQuality, 0, 4)
            if ssrChanged then Config.ssrQuality = newSsr; set_cvar_int("r.SSR.Quality", newSsr); changed = true end
            imgui.text("0=off  1=low  2=med  3=high  4=max. Higher values can cause DLSS glitter.")

            local waterRefChanged, newWaterRef = imgui.checkbox("Water Reflections (r.Water.SingleLayer.Reflections)", Config.waterReflections)
            if waterRefChanged then Config.waterReflections = newWaterRef; set_cvar_int("r.Water.SingleLayer.Reflections", newWaterRef and 1 or 0); changed = true end

            local waterRefrChanged, newWaterRefr = imgui.checkbox("Water Refraction (r.Water.SingleLayer.Refraction)", Config.waterRefraction)
            if waterRefrChanged then Config.waterRefraction = newWaterRefr; set_cvar_int("r.Water.SingleLayer.Refraction", newWaterRefr and 1 or 0); changed = true end
            imgui.text("OFF = fixes rain/puddle streaking artifacts.")

            local transChanged, newTrans = imgui.checkbox("Translucency TAA Alpha (r.Translucency.TemporalAA.Alpha)", Config.translucencyFix)
            if transChanged then Config.translucencyFix = newTrans; set_cvar_int("r.Translucency.TemporalAA.Alpha", newTrans and 1 or 0); changed = true end
            imgui.text("ON = helps reduce DLSS ghosting on rain drops.")

            imgui.tree_pop()
        end

        -- ── Lighting & Global Illumination ───────────────────────────────
        if imgui.tree_node("Lighting & Global Illumination") then
            local lumenTempChanged, newLumenTemp = imgui.checkbox("Lumen Reflections Temporal (r.Lumen.Reflections.Temporal)", Config.lumenReflectionsTemporal)
            if lumenTempChanged then Config.lumenReflectionsTemporal = newLumenTemp; set_cvar_int("r.Lumen.Reflections.Temporal", newLumenTemp and 1 or 0); changed = true end
            imgui.text("Temporal filtering on Lumen reflections. OFF reduces shimmer but loses quality.")

            local lumenDiffChanged, newLumenDiff = imgui.checkbox("Lumen Diffuse Indirect GI (r.Lumen.DiffuseIndirect.Allow)", Config.lumenDiffuseIndirect)
            if lumenDiffChanged then Config.lumenDiffuseIndirect = newLumenDiff; set_cvar_int("r.Lumen.DiffuseIndirect.Allow", newLumenDiff and 1 or 0); changed = true end
            imgui.text("OFF = disables Lumen Global Illumination. Big perf gain, loses dynamic GI.")

            local lspvChanged, newLspv = imgui.checkbox("Lumen Screen Probe Visualization (r.Lumen.ScreenProbeGather.VisualizeTraces)", Config.lumenScreenProbeVisualize)
            if lspvChanged then Config.lumenScreenProbeVisualize = newLspv; set_cvar_int("r.Lumen.ScreenProbeGather.VisualizeTraces", newLspv and 1 or 0); changed = true end
            imgui.text("Keep OFF for normal play. ON shows debug Lumen probe traces on screen.")

            local dgiChanged, newDgi = imgui.slider_int("Dynamic GI Method (r.DynamicGlobalIlluminationMethod)", Config.dynamicGIMethod or 0, 0, 4)
            if dgiChanged then Config.dynamicGIMethod = newDgi; set_cvar_int("r.DynamicGlobalIlluminationMethod", newDgi); changed = true end
            imgui.text("0=None(off)  1=SSGI  2=RTGI  3=Plugin  4=Lumen. Default 0 for VR performance.")

            imgui.tree_pop()
        end


        -- ── Eye Adaptation (per-eye brightness mismatch fix) ─────────────
        if imgui.tree_node("Eye Adaptation") then
            local eafChanged, newEaf = imgui.checkbox("Fix Eye Adaptation (r.EyeAdaptation.MethodOverride = 0)", Config.eyeAdaptationFixed)
            if eafChanged then Config.eyeAdaptationFixed = newEaf; set_cvar_int("r.EyeAdaptation.MethodOverride", newEaf and 0 or -1); changed = true end
            imgui.text("ON = forces fixed exposure. Eliminates left/right eye brightness mismatch.")

            local eaiChanged, newEai = imgui.checkbox("Eye Adaptation Ignore Materials (r.EyeAdaptation.IgnoreMaterials)", Config.eyeAdaptationIgnoreMaterials)
            if eaiChanged then Config.eyeAdaptationIgnoreMaterials = newEai; set_cvar_int("r.EyeAdaptation.IgnoreMaterials", newEai and 1 or 0); changed = true end
            imgui.text("ON = ignores materials when computing exposure. Reduces per-eye variance.")

            imgui.tree_pop()
        end

        -- ── Atmosphere ───────────────────────────────────────────────────
        if imgui.tree_node("Atmosphere") then
            local cloudChanged, newCloud = imgui.checkbox("Volumetric Clouds (r.VolumetricCloud)", Config.volumetricClouds)
            if cloudChanged then Config.volumetricClouds = newCloud; set_cvar_int("r.VolumetricCloud", newCloud and 1 or 0); changed = true end
            imgui.text("OFF = disables volumetric sky clouds. Improves outdoor performance.")

            local fogChanged, newFog = imgui.checkbox("Volumetric Fog (r.VolumetricFog)", Config.volumetricFog)
            if fogChanged then Config.volumetricFog = newFog; set_cvar_int("r.VolumetricFog", newFog and 1 or 0); changed = true end
            imgui.text("OFF = disables volumetric fog. Reduces VR ghosting/haloing in foggy areas.")

            imgui.tree_pop()
        end

        -- ── Shadows ──────────────────────────────────────────────────────
        if imgui.tree_node("Shadows") then
            local dfsChanged, newDfs = imgui.checkbox("Distance Field Shadowing (r.DistanceFieldShadowing)", Config.distanceFieldShadowing)
            if dfsChanged then Config.distanceFieldShadowing = newDfs; set_cvar_int("r.DistanceFieldShadowing", newDfs and 1 or 0); changed = true end
            imgui.text("OFF = disables soft DF shadows. Improves performance; shadows become PCF only.")

            local gdfChanged, newGdf = imgui.checkbox("Global Distance Field (r.GlobalDistanceField)", Config.globalDistanceField)
            if gdfChanged then Config.globalDistanceField = newGdf; set_cvar_int("r.GlobalDistanceField", newGdf and 1 or 0); changed = true end
            imgui.text("OFF = disables Global DF used by Lumen and AO. Perf gain, may reduce GI quality.")

            local ssfsChanged, newSsfs = imgui.checkbox("SSFS (r.SSFS)", Config.ssfsEnabled)
            if ssfsChanged then Config.ssfsEnabled = newSsfs; set_cvar_int("r.SSFS", newSsfs and 1 or 0); changed = true end
            imgui.text("Screen Space Feature Shading. OFF may help with flickering.")

            local sqChanged, newSq = imgui.slider_int("Shadow Quality (r.ShadowQuality)", Config.shadowQuality or 3, 0, 4)
            if sqChanged then Config.shadowQuality = newSq; set_cvar_int("r.ShadowQuality", newSq); changed = true end
            imgui.text("0=no shadows  1=very low  2=low  3=medium (default)  4=high/cinematic")

            imgui.tree_pop()
        end

        -- ── Vegetation & Draw Distance ────────────────────────────────────
        if imgui.tree_node("Vegetation & Draw Distance") then
            local vdChanged, newVD = imgui.slider_float("View Distance Scale (r.ViewDistanceScale)", Config.viewDistanceScale or 1.0, 0.0, 1.0)
            if vdChanged then Config.viewDistanceScale = newVD; set_cvar_float("r.ViewDistanceScale", newVD); changed = true end
            imgui.text("Lower values reduce draw distance. Performance gain at cost of pop-in.")

            local gcChanged, newGc = imgui.slider_float("Grass Cull Distance (fg.CullDistanceScale.Grass)", Config.grassCullScale or 1.0, 0.0, 1.0)
            if gcChanged then Config.grassCullScale = newGc; set_cvar_float("fg.CullDistanceScale.Grass", newGc); changed = true end
            imgui.text("Lower values cull grass closer to camera. Performance gain outdoors.")

            local fdChanged, newFd = imgui.slider_float("Foliage Density (foliage.DensityScale)", Config.foliageDensity or 1.0, 0.0, 1.0)
            if fdChanged then Config.foliageDensity = newFd; set_cvar_float("foliage.DensityScale", newFd); changed = true end
            imgui.text("Lower values reduce foliage density. Performance gain in vegetated areas.")

            local flChanged, newFl = imgui.slider_float("Foliage LOD Distance (foliage.LODDistanceScale)", Config.foliageLODScale or 1.0, 0.0, 3.0)
            if flChanged then Config.foliageLODScale = newFl; set_cvar_float("foliage.LODDistanceScale", newFl); changed = true end
            imgui.text("Controls how far foliage LOD transitions occur. Lower = more aggressive LOD.")

            imgui.tree_pop()
        end

        -- ── Post-Process ─────────────────────────────────────────────────
        if imgui.tree_node("Post-Process") then
            local ppDisableChanged, newPPDisable = imgui.checkbox("Disable Post-Processing Materials (r.postprocessing.disablematerials)", Config.postprocessingDisabled)
            if ppDisableChanged then Config.postprocessingDisabled = newPPDisable; set_cvar_int("r.postprocessing.disablematerials", newPPDisable and 1 or 0); changed = true end
            imgui.text("Disables extra scene post processing (fog, color grading, etc).")
            
            local taaFixChanged, newTaaFix = imgui.checkbox("Fix TAA/TSR VR Edge Smearing", Config.taaSmearingFixEnabled)
            if taaFixChanged then 
                Config.taaSmearingFixEnabled = newTaaFix
                if newTaaFix then
                    set_cvar_int("r.TSR.History.ScreenPercentage", 100)
                    set_cvar_int("r.TemporalAA.HistoryScreenPercentage", 100)
                    set_cvar_int("r.TSR.Velocity.Extrapolation", 1)
                else
                    set_cvar_int("r.TSR.History.ScreenPercentage", 0)
                    set_cvar_int("r.TemporalAA.HistoryScreenPercentage", 0)
                    set_cvar_int("r.TSR.Velocity.Extrapolation", 0)
                end
                changed = true 
            end
            imgui.text("ON = Fixes peripheral smearing trails when moving head. Minor perf cost.")
            imgui.text("ON = disables all post-process materials. Performance gain; may change visual look.")

            imgui.tree_pop()
        end

    end


    imgui.spacing()
    imgui.separator()
    imgui.spacing()


    -- 3. Debug Dev Config
    if imgui.collapsing_header("Debug Dev Config") then

        if currentWeaponName then
            imgui.text("Current Weapon: " .. currentWeaponName)
        else
            imgui.text("Current Weapon: None")
        end
        imgui.separator()

        -- Weapon Hand Alignment (Main Hand)
        if imgui.tree_node("Weapon Hand Alignment (Main Hand)") then
            local socketChanged, newSocket = imgui.input_text("Weapon Attach Socket", Config.weaponSocketName)
            if socketChanged then
                Config.weaponSocketName = newSocket
                changed = true
                saveWeaponProfile()
                local currentWeaponMesh = gameState:GetEquippedWeapon()
                if currentWeaponMesh ~= nil then
                     hands.attachHandToMesh(Config.dominantHand, currentWeaponMesh, Config.weaponSocketName, Config.weaponHandRotation)
                end
            end

            local rotChanged = false
            local rPitchChanged, newRPitch = imgui.drag_float("Hand Pitch", Config.weaponHandRotation[1], 0.1)
            if rPitchChanged then Config.weaponHandRotation[1] = newRPitch; rotChanged = true end
            local rYawChanged, newRYaw = imgui.drag_float("Hand Yaw", Config.weaponHandRotation[2], 0.1)
            if rYawChanged then Config.weaponHandRotation[2] = newRYaw; rotChanged = true end
            local rRollChanged, newRRoll = imgui.drag_float("Hand Roll", Config.weaponHandRotation[3], 0.1)
            if rRollChanged then Config.weaponHandRotation[3] = newRRoll; rotChanged = true end
            
            if rotChanged then
                changed = true
                saveWeaponProfile()
                local currentWeaponMesh = gameState:GetEquippedWeapon()
                if currentWeaponMesh ~= nil then
                     hands.attachHandToMesh(Config.dominantHand, currentWeaponMesh, Config.weaponSocketName, Config.weaponHandRotation, Config.weaponHandLocation)
                end
            end

            local locChanged = false
            local lXChanged, newLX = imgui.drag_float("Hand Loc X", Config.weaponHandLocation[1], 0.1)
            if lXChanged then Config.weaponHandLocation[1] = newLX; locChanged = true end
            local lYChanged, newLY = imgui.drag_float("Hand Loc Y", Config.weaponHandLocation[2], 0.1)
            if lYChanged then Config.weaponHandLocation[2] = newLY; locChanged = true end
            local lZChanged, newLZ = imgui.drag_float("Hand Loc Z", Config.weaponHandLocation[3], 0.1)
            if lZChanged then Config.weaponHandLocation[3] = newLZ; locChanged = true end
            
            if locChanged then
                changed = true
                saveWeaponProfile()
                local currentWeaponMesh = gameState:GetEquippedWeapon()
                if currentWeaponMesh ~= nil then
                     hands.attachHandToMesh(Config.dominantHand, currentWeaponMesh, Config.weaponSocketName, Config.weaponHandRotation, Config.weaponHandLocation)
                end
            end
            imgui.tree_pop()
        end

        -- Support Hand Offsets (Non-Dominant)
        if imgui.tree_node("Support Hand Offsets (Non-Dominant)") then
            local relSocketChanged, newRelSocket = imgui.input_text("Reload Attach Socket", Config.reloadSocketName or "jnt_l_hand")
            if relSocketChanged then Config.reloadSocketName = newRelSocket; changed = true; saveWeaponProfile() end

            local disableRelChanged, newDisableRel = imgui.checkbox("Disable Left Hand Attachment", Config.disableReloadAttachment)
            if disableRelChanged then Config.disableReloadAttachment = newDisableRel; changed = true; saveWeaponProfile() end
            
            local reloadRotChanged = false
            local relPitchChanged, newRelPitch = imgui.drag_float("Reload Pitch", Config.reloadHandRotation[1], 0.1)
            if relPitchChanged then Config.reloadHandRotation[1] = newRelPitch; reloadRotChanged = true end
            local relYawChanged, newRelYaw = imgui.drag_float("Reload Yaw", Config.reloadHandRotation[2], 0.1)
            if relYawChanged then Config.reloadHandRotation[2] = newRelYaw; reloadRotChanged = true end
            local relRollChanged, newRelRoll = imgui.drag_float("Reload Roll", Config.reloadHandRotation[3], 0.1)
            if relRollChanged then Config.reloadHandRotation[3] = newRelRoll; reloadRotChanged = true end
            local reloadLocChanged = false
            local relXChanged, newRelX = imgui.drag_float("Reload Loc X", Config.reloadHandLocation[1], 0.1)
            if relXChanged then Config.reloadHandLocation[1] = newRelX; reloadLocChanged = true end
            local relYChanged, newRelY = imgui.drag_float("Reload Loc Y", Config.reloadHandLocation[2], 0.1)
            if relYChanged then Config.reloadHandLocation[2] = newRelY; reloadLocChanged = true end
            local relZChanged, newRelZ = imgui.drag_float("Reload Loc Z", Config.reloadHandLocation[3], 0.1)
            if relZChanged then Config.reloadHandLocation[3] = newRelZ; reloadLocChanged = true end

            if reloadRotChanged or reloadLocChanged then
                changed = true
                saveWeaponProfile()
                local currentWeaponMesh = gameState:GetEquippedWeapon()
                if currentWeaponMesh ~= nil then
                    local supportHand = 1 - Config.dominantHand
                    -- Only update if the hand is currently attached (simulation or isHoldingAttachment)
                    if simulateReloadHandPosition or simulateTwoHandMode or isHoldingAttachment then
                        hands.attachHandToMesh(supportHand, currentWeaponMesh, Config.reloadSocketName or "jnt_l_hand", Config.reloadHandRotation, Config.reloadHandLocation)
                    end
                end
            end
            imgui.tree_pop()
        end

        local reloadRotChanged = false -- For simulation update logic
        local reloadLocChanged = false
        local relSocketChanged = false

        -- Simulation Toggles
        local simReloadChanged, newSimReload = imgui.checkbox("Simulate Reload Hand Position", simulateReloadHandPosition)
        if simReloadChanged then
            simulateReloadHandPosition = newSimReload
            local supportHand = 1 - Config.dominantHand
            if simulateReloadHandPosition then
                local currentWeaponMesh = gameState:GetEquippedWeapon()
                if currentWeaponMesh ~= nil then
                    hands.attachHandToMesh(supportHand, currentWeaponMesh, Config.reloadSocketName or "jnt_l_hand", Config.reloadHandRotation, Config.reloadHandLocation)
                    hands.setHandPose(supportHand, Config.reloadHandPose)
                end
            else
                hands.attachHandToController(supportHand)
                hands.setInitialTransform(supportHand)
            end
        end

        local sim2HChanged, newSim2H = imgui.checkbox("Simulate 2-Handed Mode", simulateTwoHandMode)
        if sim2HChanged then
            simulateTwoHandMode = newSim2H
            local supportHand = 1 - Config.dominantHand
            if simulateTwoHandMode then
                 if simulateReloadHandPosition then simulateReloadHandPosition = false end
                 local currentWeaponMesh = gameState:GetEquippedWeapon()
                 if currentWeaponMesh ~= nil then
                     hands.attachHandToMesh(supportHand, currentWeaponMesh, Config.reloadSocketName or "jnt_l_hand", Config.reloadHandRotation, Config.reloadHandLocation)
                     local specificPose = getSpecificHandPose(currentWeaponName)
                     if specificPose then hands.setHandPose(supportHand, specificPose)
                     else
                         if isPistolWeapon(currentWeaponName) then hands.setHandPose(supportHand, Config.twoHandedHandPose)
                         else hands.setHandPose(supportHand, Config.twoHandedRifleHandPose) end
                     end
                 end
            else
                hands.attachHandToController(supportHand)
                hands.setInitialTransform(supportHand)
            end
        end
        imgui.separator()

        -- Mag Reload Box
        if imgui.tree_node("Mag Reload Box Sizes & Offsets") then
            local bc = magReload.get_config()
            local bcChanged = false
            imgui.text("Attach Socket Name")
            local sockChanged, newSock = imgui.input_text("Socket##mag", bc.magSocket)
            if sockChanged then bc.magSocket = newSock; bcChanged = true end
            local isMagDebug = magReload.get_debug()
            local changedMagDebug, newMagDebug = imgui.checkbox("Show UE Debug Wireframes##mag", isMagDebug)
            if changedMagDebug then magReload.set_debug(newMagDebug) end
            
            imgui.text("Left Hand Box (scale)")
            local hxC, newHX = imgui.drag_float("Hand X##mag", bc.handX, 0.01, 0.01, 5.0)
            local hyC, newHY = imgui.drag_float("Hand Y##mag", bc.handY, 0.01, 0.01, 5.0)
            local hzC, newHZ = imgui.drag_float("Hand Z##mag", bc.handZ, 0.01, 0.01, 5.0)
            if hxC then bc.handX = newHX; bcChanged = true end
            if hyC then bc.handY = newHY; bcChanged = true end
            if hzC then bc.handZ = newHZ; bcChanged = true end
            
            imgui.separator()
            imgui.text("Left Hand Box (offset from hand socket)")
            local hOxC, newHOX = imgui.drag_float("Off X##hand", bc.handOffX or 0, 0.1, -50.0, 50.0)
            local hOyC, newHOY = imgui.drag_float("Off Y##hand", bc.handOffY or 0, 0.1, -50.0, 50.0)
            local hOzC, newHOZ = imgui.drag_float("Off Z##hand", bc.handOffZ or 0, 0.1, -50.0, 50.0)
            if hOxC then bc.handOffX = newHOX; bcChanged = true end
            if hOyC then bc.handOffY = newHOY; bcChanged = true end
            if hOzC then bc.handOffZ = newHOZ; bcChanged = true end

            imgui.separator()
            imgui.text("Mag Socket Box (scale)")
            local mxC, newMX = imgui.drag_float("Mag X##mag", bc.magX, 0.01, 0.01, 5.0)
            local myC, newMY = imgui.drag_float("Mag Y##mag", bc.magY, 0.01, 0.01, 5.0)
            local mzC, newMZ = imgui.drag_float("Mag Z##mag", bc.magZ, 0.01, 0.01, 5.0)
            if mxC then bc.magX = newMX; bcChanged = true end
            if myC then bc.magY = newMY; bcChanged = true end
            if mzC then bc.magZ = newMZ; bcChanged = true end

            imgui.separator()
            imgui.text("Mag Socket Box (offset from socket)")
            local oxC, newOX = imgui.drag_float("Off X##mag", bc.magOffX, 0.1, -50.0, 50.0)
            local oyC, newOY = imgui.drag_float("Off Y##mag", bc.magOffY, 0.1, -50.0, 50.0)
            local ozC, newOZ = imgui.drag_float("Off Z##mag", bc.magOffZ, 0.1, -50.0, 50.0)
            if oxC then bc.magOffX = newOX; bcChanged = true end
            if oyC then bc.magOffY = newOY; bcChanged = true end
            if ozC then bc.magOffZ = newOZ; bcChanged = true end

            if bcChanged then magReload.set_config(bc) end
            imgui.tree_pop()
        end

        -- Weapon Mod Alignment
        if imgui.tree_node("Weapon Mod Alignment (Silencer/Sight)") then
            if currentAttachmentName then imgui.text("Editing Profile: " .. currentAttachmentName)
            else imgui.text("No Attachment Detected") end
            if imgui.button("Scan for Attachments") then scanWeaponAttachments() end
            local showAllChanged, newShowAll = imgui.checkbox("Show All", showAllAttachments)
            if showAllChanged then showAllAttachments = newShowAll; scanWeaponAttachments() end
            if #detectedAttachments > 0 then
                local ch, newIdx = imgui.combo("Select Attachment", selectedAttachmentIndex, selectedAttachmentValues)
                if ch then selectedAttachmentIndex = newIdx end
                local simChanged, newSim = imgui.checkbox("Simulate Attachment Position", isSimulatingAttachment)
                if simChanged then toggleAttachmentSimulation(newSim) end
            end

            local modOffsetChanged = false
            local modRotChanged = false
            
            -- Mod Offset
            local modXChanged, newModX = imgui.drag_float("Mod Offset X", Config.weaponModMeshOffset.X, 0.1)
            if modXChanged then Config.weaponModMeshOffset.X = newModX; modOffsetChanged = true end
            local modYChanged, newModY = imgui.drag_float("Mod Offset Y", Config.weaponModMeshOffset.Y, 0.1)
            if modYChanged then Config.weaponModMeshOffset.Y = newModY; modOffsetChanged = true end
            local modZChanged, newModZ = imgui.drag_float("Mod Offset Z", Config.weaponModMeshOffset.Z, 0.1)
            if modZChanged then Config.weaponModMeshOffset.Z = newModZ; modOffsetChanged = true end
            
            -- Mod Rotation
            local modPitchChanged, newModPitch = imgui.drag_float("Mod Pitch", Config.weaponModMeshRotation.Pitch, 0.1)
            if modPitchChanged then Config.weaponModMeshRotation.Pitch = newModPitch; modRotChanged = true end
            local modYawChanged, newModYaw = imgui.drag_float("Mod Yaw", Config.weaponModMeshRotation.Yaw, 0.1)
            if modYawChanged then Config.weaponModMeshRotation.Yaw = newModYaw; modRotChanged = true end
            local modRollChanged, newModRoll = imgui.drag_float("Mod Roll", Config.weaponModMeshRotation.Roll, 0.1)
            if modRollChanged then Config.weaponModMeshRotation.Roll = newModRoll; modRotChanged = true end
            
            -- Cleanup Delay
            local modDelayChanged, newModDelay = imgui.slider_float("Cleanup Delay (s)", Config.weaponModCleanupDelay, 0.5, 10.0)
            if modDelayChanged then Config.weaponModCleanupDelay = newModDelay; changed = true end
            
            if modOffsetChanged or modRotChanged then
                changed = true
                -- Update active mesh immediately if attached
                if attachedModMesh and UEVR_UObjectHook.exists(attachedModMesh) then
                     uevrUtils.set_component_relative_transform(attachedModMesh, Config.weaponModMeshOffset, Config.weaponModMeshRotation)
                end
                -- Save to Profile (Auto-Save)
                if currentAttachmentName then
                    if not Config.attachmentProfiles[currentAttachmentName] then Config.attachmentProfiles[currentAttachmentName] = {} end
                    local prof = Config.attachmentProfiles[currentAttachmentName]
                    prof.offset = {X = Config.weaponModMeshOffset.X, Y = Config.weaponModMeshOffset.Y, Z = Config.weaponModMeshOffset.Z}
                    prof.rotation = {Pitch = Config.weaponModMeshRotation.Pitch, Yaw = Config.weaponModMeshRotation.Yaw, Roll = Config.weaponModMeshRotation.Roll}
                    prof.cleanupDelay = Config.weaponModCleanupDelay
                    Config:markDirty()
                    Config:save()
                end
            end
            -- Also save cleanup delay changes to profile
            if modDelayChanged and currentAttachmentName then
                if not Config.attachmentProfiles[currentAttachmentName] then Config.attachmentProfiles[currentAttachmentName] = {} end
                Config.attachmentProfiles[currentAttachmentName].cleanupDelay = Config.weaponModCleanupDelay
                Config:markDirty()
                Config:save()
            end
            imgui.tree_pop()
        end

        -- Scope Settings
        if imgui.tree_node("Scope Settings") then
            if currentScopeName then
                imgui.text("Scope: " .. currentScopeName)
            else
                imgui.text("Scope: Default / None")
            end
            if currentWeaponName then
                imgui.text("Weapon: " .. currentWeaponName)
            end
            imgui.separator()
            
            local bChanged, nB = imgui.slider_float("Scope Brightness", Config.scopeBrightnessAmplifier, 0.0, 3.0)
            if bChanged then Config.scopeBrightnessAmplifier = nB; changed = true end
            
            local dChanged, nD = imgui.drag_float("Scope Offset (X)", Config.cylinderDepth, 0.1, -30.0, 30.0, "%.3f")
            if dChanged then Config.cylinderDepth = nD; changed = true; saveWeaponProfile(); if scopeController then scopeController:SetScopePlaneScale(Config.cylinderDepth) end end

            local dyChanged, nDy = imgui.drag_float("Scope Offset (Y)", Config.cylinderOffsetY, 0.1, -30.0, 30.0, "%.3f")
            if dyChanged then Config.cylinderOffsetY = nDy; changed = true; saveWeaponProfile(); if scopeController then scopeController:SetScopePlaneScale(Config.cylinderDepth) end end

            local dzChanged, nDz = imgui.drag_float("Scope Offset (Z)", Config.cylinderOffsetZ, 0.1, -30.0, 30.0, "%.3f")
            if dzChanged then Config.cylinderOffsetZ = nDz; changed = true; saveWeaponProfile(); if scopeController then scopeController:SetScopePlaneScale(Config.cylinderDepth) end end
            
            local diaChanged, nDia = imgui.drag_float("Scope Scale", Config.scopeDiameter, 0.001, 0.001, 0.1, "%.3f")
            if diaChanged then Config.scopeDiameter = nDia; changed = true; saveWeaponProfile(); if scopeController then scopeController:SetScopePlaneScale(Config.cylinderDepth) end end

            local tdChanged, nTd = imgui.drag_float("Scope Tube Depth", Config.cylinderTubeDepth, 0.0001, 0.0001, 0.1, "%.4f")
            if tdChanged then Config.cylinderTubeDepth = nTd; changed = true; saveWeaponProfile(); if scopeController then scopeController:SetScopePlaneScale(Config.cylinderDepth) end end
            
            local mChanged, nM = imgui.drag_float("Scope Magnifier", Config.scopeMagnifier, 0.001, 0.0, 2.0, "%.3f")
            if mChanged then Config.scopeMagnifier = nM; changed = true; saveWeaponProfile() end
            
            local disChanged, nDis = imgui.slider_float("Scope Activation Distance (cm)", Config.scopeActivationDistance, 5.0, 100.0)
            if disChanged then Config.scopeActivationDistance = nDis; changed = true end

            local efovChanged, nEfov = imgui.checkbox("Expanding FOV (closer = wider view, constant zoom)", Config.scopeExpandingFOV)
            if efovChanged then Config.scopeExpandingFOV = nEfov; changed = true end

            imgui.spacing()
            imgui.separator()
            imgui.text("PiP Reticule Dot")

            -- Resolve current values: scope profile first, then global defaults
            if not Config.scopeProfiles then Config.scopeProfiles = {} end
            local pipProf = (currentScopeName and Config.scopeProfiles[currentScopeName]) or {}

            local curOX  = pipProf.pipDotOffsetX  or Config.pipDotOffsetX  or -13.0
            local curOY  = pipProf.pipDotOffsetY  or Config.pipDotOffsetY  or   0.8
            local curOZ  = pipProf.pipDotOffsetZ  or Config.pipDotOffsetZ  or   8.3
            local curSX  = pipProf.pipDotScaleX   or Config.pipDotScaleX   or 0.000010
            local curSY  = pipProf.pipDotScaleY   or Config.pipDotScaleY   or 0.0002
            local curSZ  = pipProf.pipDotScaleZ   or Config.pipDotScaleZ   or 0.0002
            local curB   = pipProf.pipDotBrightness or Config.pipDotBrightness or 150.0
            local curR   = pipProf.pipDotColorR   or Config.pipDotColorR   or 1.0
            local curG   = pipProf.pipDotColorG   or Config.pipDotColorG   or 0.0
            local curCB  = pipProf.pipDotColorB   or Config.pipDotColorB   or 0.0

            local dotXChanged,  nDotX  = imgui.drag_float("Dot Offset X##pipdot",  curOX,  0.1,     -50.0,  50.0,  "%.2f")
            local dotYChanged,  nDotY  = imgui.drag_float("Dot Offset Y##pipdot",  curOY,  0.01,    -50.0,  50.0,  "%.2f")
            local dotZChanged,  nDotZ  = imgui.drag_float("Dot Offset Z##pipdot",  curOZ,  0.1,     -50.0,  50.0,  "%.2f")
            local dotSXChanged, nDotSX = imgui.drag_float("Dot Scale X##pipdot",   curSX,  0.000001, 0.00001, 0.5, "%.6f")
            local dotSYChanged, nDotSY = imgui.drag_float("Dot Scale Y##pipdot",   curSY,  0.000001, 0.00001, 0.5, "%.6f")
            local dotSZChanged, nDotSZ = imgui.drag_float("Dot Scale Z##pipdot",   curSZ,  0.000001, 0.00001, 0.5, "%.6f")
            imgui.spacing()
            local dotBChanged,  nDotB  = imgui.slider_float("Dot Brightness##pipdot", curB, 0.0, 2000.0, "%.1f")
            local dotRChanged,  nDotR  = imgui.drag_float("Dot Color R##pipdot",    curR,  0.01, 0.0, 1.0, "%.2f")
            local dotGChanged,  nDotG  = imgui.drag_float("Dot Color G##pipdot",    curG,  0.01, 0.0, 1.0, "%.2f")
            local dotCBChanged, nDotCB = imgui.drag_float("Dot Color B##pipdot",    curCB, 0.01, 0.0, 1.0, "%.2f")

            -- Save to scope profile (or global if no scope active)
            local function savePipDot(key, val)
                if currentScopeName then
                    if not Config.scopeProfiles[currentScopeName] then Config.scopeProfiles[currentScopeName] = {} end
                    Config.scopeProfiles[currentScopeName][key] = val
                else
                    Config[key] = val
                end
                changed = true; saveWeaponProfile()
            end

            if dotXChanged  then savePipDot("pipDotOffsetX",   nDotX)  end
            if dotYChanged  then savePipDot("pipDotOffsetY",   nDotY)  end
            if dotZChanged  then savePipDot("pipDotOffsetZ",   nDotZ)  end
            if dotSXChanged then savePipDot("pipDotScaleX",    nDotSX) end
            if dotSYChanged then savePipDot("pipDotScaleY",    nDotSY) end
            if dotSZChanged then savePipDot("pipDotScaleZ",    nDotSZ) end
            if dotBChanged  then savePipDot("pipDotBrightness",nDotB)  end
            if dotRChanged  then savePipDot("pipDotColorR",    nDotR)  end
            if dotGChanged  then savePipDot("pipDotColorG",    nDotG)  end
            if dotCBChanged then savePipDot("pipDotColorB",    nDotCB) end

            -- Live-apply colour/brightness to DMI
            if (dotBChanged or dotRChanged or dotGChanged or dotCBChanged)
               and scopeController and scopeController.pip_reticule_material
               and uevrUtils.validate_object(scopeController.pip_reticule_material) then
                local dmi   = scopeController.pip_reticule_material
                local b     = (dotBChanged  and nDotB)  or curB
                local r     = ((dotRChanged  and nDotR)  or curR)  * b
                local g     = ((dotGChanged  and nDotG)  or curG)  * b
                local cb    = ((dotCBChanged and nDotCB) or curCB) * b
                local color = StructObject.new(scopeController.flinearColor_c)
                color.R = r; color.G = g; color.B = cb; color.A = 1.0
                dmi:SetVectorParameterValue("EmissiveColor",       color)
                dmi:SetVectorParameterValue("Color",               color)
                dmi:SetVectorParameterValue("BaseColor",           color)
                dmi:SetVectorParameterValue("Tint",                color)
                dmi:SetVectorParameterValue("TintColorAndOpacity", color)
            end

            imgui.tree_pop()
        end

        -- Red Dot Sight Settings
        if imgui.tree_node("Red Dot Sight Settings") then
            if currentScopeName then
                imgui.text("Scope: " .. currentScopeName)
            else
                imgui.text("Scope: Default / None")
            end
            imgui.separator()

            -- Use Profile values if available, otherwise global defaults
            local currentProf = Config.redDotProfiles[currentScopeName] or {}
            local rsx = currentProf.scaleX or currentProf.size or Config.redDotScaleX or Config.redDotSize or 0.007
            local rsy = currentProf.scaleY or currentProf.size or Config.redDotScaleY or Config.redDotSize or 0.007
            local rsz = currentProf.scaleZ or currentProf.size or Config.redDotScaleZ or Config.redDotSize or 0.007
            local rx = currentProf.offsetX or Config.redDotOffsetX or 0.0
            local ry = currentProf.offsetY or Config.redDotOffsetY or 0.0
            local rz = currentProf.offsetZ or Config.redDotOffsetZ or 0.0

            -- Scale
            local sxChanged, nSX = imgui.drag_float("Red Dot Scale X", rsx, 0.0001, 0.0001, 1.0, "%.4f")
            if sxChanged then 
                if currentScopeName then
                    if not Config.redDotProfiles[currentScopeName] then Config.redDotProfiles[currentScopeName] = {} end
                    Config.redDotProfiles[currentScopeName].scaleX = nSX
                else
                    Config.redDotScaleX = nSX
                end
                changed = true
                saveWeaponProfile()
            end
            
            local syChanged, nSY = imgui.drag_float("Red Dot Scale Y", rsy, 0.0001, 0.0001, 1.0, "%.4f")
            if syChanged then 
                if currentScopeName then
                    if not Config.redDotProfiles[currentScopeName] then Config.redDotProfiles[currentScopeName] = {} end
                    Config.redDotProfiles[currentScopeName].scaleY = nSY
                else
                    Config.redDotScaleY = nSY
                end
                changed = true
                saveWeaponProfile()
            end
            
            local szChanged, nSZ = imgui.drag_float("Red Dot Scale Z", rsz, 0.0001, 0.0001, 1.0, "%.4f")
            if szChanged then 
                if currentScopeName then
                    if not Config.redDotProfiles[currentScopeName] then Config.redDotProfiles[currentScopeName] = {} end
                    Config.redDotProfiles[currentScopeName].scaleZ = nSZ
                else
                    Config.redDotScaleZ = nSZ
                end
                changed = true
                saveWeaponProfile()
            end

            -- Live apply scale if dragging
            if (sxChanged or syChanged or szChanged) and scopeController and scopeController.UpdateReticulePosition then 
                scopeController:UpdateReticulePosition(currentScopeName) 
            end
            
            -- Brightness
            local rb = currentProf.brightness or Config.redDotBrightness or 150.0
            local bChanged, nB = imgui.slider_float("Red Dot Brightness", rb, 10.0, 2000.0)
            if bChanged then
                if currentScopeName then
                    if not Config.redDotProfiles[currentScopeName] then Config.redDotProfiles[currentScopeName] = {} end
                    Config.redDotProfiles[currentScopeName].brightness = nB
                else
                    Config.redDotBrightness = nB
                end
                changed = true
                saveWeaponProfile()
                if scopeController and scopeController.UpdateReticulePosition then 
                    scopeController:UpdateReticulePosition(currentScopeName) 
                end
            end
            
            -- Offsets
            local oxChanged, nOX = imgui.drag_float("Red Dot Offset X", rx, 0.1, -100.0, 100.0)
            if oxChanged then 
                if currentScopeName then
                    if not Config.redDotProfiles[currentScopeName] then Config.redDotProfiles[currentScopeName] = {} end
                    Config.redDotProfiles[currentScopeName].offsetX = nOX
                else
                    Config.redDotOffsetX = nOX
                end
                changed = true
                saveWeaponProfile()
            end
            local oyChanged, nOY = imgui.drag_float("Red Dot Offset Y", ry, 0.1, -100.0, 100.0)
            if oyChanged then 
                if currentScopeName then
                    if not Config.redDotProfiles[currentScopeName] then Config.redDotProfiles[currentScopeName] = {} end
                    Config.redDotProfiles[currentScopeName].offsetY = nOY
                else
                    Config.redDotOffsetY = nOY
                end
                changed = true
                saveWeaponProfile()
            end
            local ozChanged, nOZ = imgui.drag_float("Red Dot Offset Z", rz, 0.1, -100.0, 100.0)
            if ozChanged then 
                if currentScopeName then
                    if not Config.redDotProfiles[currentScopeName] then Config.redDotProfiles[currentScopeName] = {} end
                    Config.redDotProfiles[currentScopeName].offsetZ = nOZ
                else
                    Config.redDotOffsetZ = nOZ
                end
                changed = true
                saveWeaponProfile()
            end

            -- Live apply offsets if dragging
            if (oxChanged or oyChanged or ozChanged) and scopeController and scopeController.UpdateReticulePosition then
                scopeController:UpdateReticulePosition(currentScopeName)
            end

            imgui.separator()

            -- Elliptical Aperture
            imgui.text("Aperture — controls when the dot hides as eye moves off-axis.")
            local raY = currentProf.apertureY or Config.redDotApertureY or currentProf.apertureRadius or Config.redDotApertureRadius or 5.0
            local raZ = currentProf.apertureZ or Config.redDotApertureZ or currentProf.apertureRadius or Config.redDotApertureRadius or 5.0
            local rcY = currentProf.apertureCentreY or Config.redDotApertureCentreY or 0.0
            local rcZ = currentProf.apertureCentreZ or Config.redDotApertureCentreZ or 0.0

            local ayChanged, nAY = imgui.slider_float("Aperture Width (Y)", raY, 0.5, 30.0, "%.2f")
            if ayChanged then
                if currentScopeName then
                    if not Config.redDotProfiles[currentScopeName] then Config.redDotProfiles[currentScopeName] = {} end
                    Config.redDotProfiles[currentScopeName].apertureY = nAY
                else Config.redDotApertureY = nAY end
                changed = true; saveWeaponProfile()
            end

            local azChanged, nAZ = imgui.slider_float("Aperture Height (Z)", raZ, 0.5, 30.0, "%.2f")
            if azChanged then
                if currentScopeName then
                    if not Config.redDotProfiles[currentScopeName] then Config.redDotProfiles[currentScopeName] = {} end
                    Config.redDotProfiles[currentScopeName].apertureZ = nAZ
                else Config.redDotApertureZ = nAZ end
                changed = true; saveWeaponProfile()
            end
            imgui.text("Width/Height: how far off horizontal/vertical axis before dot hides.")

            imgui.spacing()

            local cYChanged, nCY = imgui.drag_float("Aperture Centre Y", rcY, 0.1, -15.0, 15.0, "%.2f")
            if cYChanged then
                if currentScopeName then
                    if not Config.redDotProfiles[currentScopeName] then Config.redDotProfiles[currentScopeName] = {} end
                    Config.redDotProfiles[currentScopeName].apertureCentreY = nCY
                else Config.redDotApertureCentreY = nCY end
                changed = true; saveWeaponProfile()
            end

            local cZChanged, nCZ = imgui.drag_float("Aperture Centre Z", rcZ, 0.1, -15.0, 15.0, "%.2f")
            if cZChanged then
                if currentScopeName then
                    if not Config.redDotProfiles[currentScopeName] then Config.redDotProfiles[currentScopeName] = {} end
                    Config.redDotProfiles[currentScopeName].apertureCentreZ = nCZ
                else Config.redDotApertureCentreZ = nCZ end
                changed = true; saveWeaponProfile()
            end
            imgui.text("Centre: shifts the ellipse origin to compensate for scope mesh misalignment.")

            imgui.spacing()

            -- Shape: auto-detected or per-profile override
            local SHAPE_OPTIONS = { "auto", "ellipse", "rectangle" }
            local currentShape = currentProf.apertureShape or "auto"
            local currentShapeIdx = 0
            for i, v in ipairs(SHAPE_OPTIONS) do
                if v == currentShape then currentShapeIdx = i - 1; break end
            end
            local autoLabel = ""
            if not currentProf.apertureShape and currentScopeName then
                local sn = currentScopeName:lower()
                local detected = "ellipse"
                if sn:find("colimscope_mini", 1, true) then detected = "ellipse"
                elseif sn:find("colimscope", 1, true) then detected = "rectangle"
                elseif sn:find("deadeye_scope", 1, true) then detected = "rectangle"
                elseif sn:find("goloscope", 1, true) then detected = "rectangle"
                end
                autoLabel = " (auto: " .. detected .. ")"
            end
            imgui.text("Aperture Shape" .. autoLabel)
            local shapeChanged, newShapeIdx = imgui.combo("##apertureShape", currentShapeIdx, SHAPE_OPTIONS)
            if shapeChanged then
                local newShape = SHAPE_OPTIONS[newShapeIdx + 1]
                if currentScopeName then
                    if not Config.redDotProfiles[currentScopeName] then Config.redDotProfiles[currentScopeName] = {} end
                    Config.redDotProfiles[currentScopeName].apertureShape = (newShape ~= "auto") and newShape or nil
                end
                changed = true; saveWeaponProfile()
            end

            imgui.tree_pop()
        end

        -- Animation & Montage Control
        if imgui.tree_node("Animation & Montage Control") then
            if lastPlayedMontageName ~= "None" then
                imgui.text("Last Montage: " .. tostring(lastPlayedMontageName))
                if imgui.button("Copy Montage Name") then imgui.set_clipboard_text(lastPlayedMontageName) end
                
                local montageData = Config.montageAttachmentList[lastPlayedMontageName]
                if montageData or shouldAttachForMontage(lastPlayedMontageName) then
                    if imgui.tree_node("Edit Montage Offsets") then
                        if not montageData then
                            montageData = { left = {pos={0,0,0}, rot={0,0,0}, socket="jnt_l_ik_hand"}, right = {pos={0,0,0}, rot={0,0,0}, socket="jnt_r_ik_hand"} }
                            Config.montageAttachmentList[lastPlayedMontageName] = montageData
                            changed = true
                        end
                        
                        local function v3c(label, val)
                            local c = false
                            local v1c, v1 = imgui.drag_float(label.." X", val[1], 0.1)
                            if v1c then val[1] = v1; c = true end
                            local v2c, v2 = imgui.drag_float(label.." Y", val[2], 0.1)
                            if v2c then val[2] = v2; c = true end
                            local v3c, v3 = imgui.drag_float(label.." Z", val[3], 0.1)
                            if v3c then val[3] = v3; c = true end
                            return c
                        end

                        imgui.text("Left Hand")
                        if v3c("L Pos", montageData.left.pos) then changed = true end
                        if v3c("L Rot", montageData.left.rot) then changed = true end
                        imgui.text("Right Hand")
                        if v3c("R Pos", montageData.right.pos) then changed = true end
                        if v3c("R Rot", montageData.right.rot) then changed = true end
                        imgui.tree_pop()
                    end
                else
                    if imgui.button("Enable Hand Attachment for this Montage") then
                        Config.montageAttachmentList[lastPlayedMontageName] = { left = {pos={0,0,0}, rot={0,0,0}, socket="jnt_l_ik_hand"}, right = {pos={0,0,0}, rot={0,0,0}, socket="jnt_r_ik_hand"} }
                        changed = true
                    end
                end
            end
            if imgui.button("Scan All Meshes for Montages") then
                local pawn = gameState:GetLocalPawn()
                if pawn then
                    -- print("Scanning for montages...")
                    -- (Scan logic intentionally omitted for brevity in UI, but could be restored if needed)
                end
            end
            imgui.tree_pop()
        end

        -- Detector Settings
        if _G.DetectorSystem then
            if imgui.tree_node("Detector Settings") then
                local currentDetName = _G.DetectorSystem.GetCurrentDetectorName()
                if currentDetName then imgui.text("Editing: " .. currentDetName) 
                else imgui.text("No Detector Found") end
                
                local dChanged = false
                
                -- Position
                local dPX, nDPX = imgui.drag_float("Detector Pos X", Config.detectorOffset.X, 0.1)
                if dPX then Config.detectorOffset.X = nDPX; dChanged = true end
                local dPY, nDPY = imgui.drag_float("Detector Pos Y", Config.detectorOffset.Y, 0.1)
                if dPY then Config.detectorOffset.Y = nDPY; dChanged = true end
                local dPZ, nDPZ = imgui.drag_float("Detector Pos Z", Config.detectorOffset.Z, 0.1)
                if dPZ then Config.detectorOffset.Z = nDPZ; dChanged = true end
                
                -- Rotation
                local dPitch, nDPitch = imgui.drag_float("Detector Pitch", Config.detectorRotation.Pitch, 0.5)
                if dPitch then Config.detectorRotation.Pitch = nDPitch; dChanged = true end
                local dYaw, nDYaw = imgui.drag_float("Detector Yaw", Config.detectorRotation.Yaw, 0.5)
                if dYaw then Config.detectorRotation.Yaw = nDYaw; dChanged = true end
                local dRoll, nDRoll = imgui.drag_float("Detector Roll", Config.detectorRotation.Roll, 0.5)
                if dRoll then Config.detectorRotation.Roll = nDRoll; dChanged = true end
                
                -- Disable Pose
                local detPoseChanged, newDetPose = imgui.checkbox("Disable Hand Pose Override", Config.disableDetectorPose)
                if detPoseChanged then Config.disableDetectorPose = newDetPose; changed = true end
                
                if dChanged then 
                    changed = true; 
                    _G.DetectorSystem.RefreshTransform() 
                    -- Auto-save to profile
                    if currentDetName then
                        if not Config.detectorProfiles[currentDetName] then Config.detectorProfiles[currentDetName] = {} end
                        local prof = Config.detectorProfiles[currentDetName]
                        prof.offset = {X = Config.detectorOffset.X, Y = Config.detectorOffset.Y, Z = Config.detectorOffset.Z}
                        prof.rotation = {Pitch = Config.detectorRotation.Pitch, Yaw = Config.detectorRotation.Yaw, Roll = Config.detectorRotation.Roll}
                        Config:markDirty()
                        Config:save()
                    end
                end
                imgui.tree_pop()
            end
        end

        -- Gesture Zone Debug
        if imgui.tree_node("Gesture Zone Debug Coordinates") then
             local locG = require("gestures.locationgesture")
             local LtoR = locG.LeftHandRelativeToRightLocationGesture
             if LtoR and LtoR.isActive then
                 imgui.text(string.format("L rel R: X:%.2f Y:%.2f Z:%.2f", LtoR.weaponLocation.x, LtoR.weaponLocation.y, LtoR.weaponLocation.z))
             end
             local isVis = zoneDebug.is_visible()
             local chVis, nVis = imgui.checkbox("Show UE Debug Boxes for Zones", isVis)
             if chVis then zoneDebug.set_visible(nVis) end
             imgui.tree_pop()
        end

        -- Pickup Items
        if imgui.tree_node("Pickup Items") then
            imgui.text("Offsets applied to held items relative to the left controller.")
            
            if Config.pickupItemLocation == nil then Config.pickupItemLocation = {0.0, 0.0, 0.0} end
            if Config.pickupItemRotation == nil then Config.pickupItemRotation = {0.0, 0.0, 0.0} end
            if Config.pickupItemProfiles == nil then Config.pickupItemProfiles = {} end

            local ok, pickup = pcall(require, "physical_pickup")
            local itemName = nil
            local actorName = nil
            if ok and pickup and pickup.getGrabbedItemName then
                itemName = pickup.getGrabbedItemName()
                if pickup.getGrabbedActorClassName then
                    actorName = pickup.getGrabbedActorClassName()
                end
            end

            imgui.separator()
            if itemName then
                imgui.text("Currently Holding: " .. itemName)
                if actorName then
                    imgui.text("Actor Class: " .. actorName)
                end
                imgui.text("Offsets below apply specifically to this item.")
                if Config.pickupItemProfiles[itemName] == nil then
                    local defLoc = {Config.pickupItemLocation[1], Config.pickupItemLocation[2], Config.pickupItemLocation[3]}
                    local defRot = {Config.pickupItemRotation[1], Config.pickupItemRotation[2], Config.pickupItemRotation[3]}
                    
                    local lowerName = string.lower(itemName)
                    if string.find(lowerName, "bulletbox") or string.find(lowerName, "amm_") then
                        defLoc = {5.4, -2.0, 2.9}
                        defRot = {-83.6, 0.0, 177.5}
                    elseif string.find(lowerName, "notes") then
                        defLoc = {-9.3, -3.8, -12.3}
                        defRot = {-83.2, 0.0, 84.4}
                    elseif string.find(lowerName, "notepad") then
                        defLoc = {3.5, 0.5, 10.2}
                        defRot = {-83.8, 0.5, -89.3}
                    elseif string.find(lowerName, "pda") then
                        defLoc = {-15.1, -2.1, -1.5}
                        defRot = {-80.8, -0.9, -2.1}
                    elseif string.find(lowerName, "nvg") then
                        defLoc = {-0.6, -0.8, 7.4}
                        defRot = {-86.7, -88.0, -2.3}
                    elseif string.find(lowerName, "silen") then
                        defLoc = {-3.1, -2.9, -6.4}
                        defRot = {-100.2, 0.0, -2.2}
                    elseif string.find(lowerName, "photo") then
                        defLoc = {-1.4, -4.1, 9.5}
                        defRot = {-79.7, -77.8, -12.1}
                    elseif string.find(lowerName, "flashdrive") or string.find(lowerName, "usb") then
                        defLoc = {-3.0, 4.0, -5.7}
                        defRot = {98.5, 13.8, 0.8}
                    elseif string.find(lowerName, "keys") then
                        defLoc = {3.9, -3.5, 5.8}
                        defRot = {-87.1, 5.8, -77.1}
                    elseif string.find(lowerName, "fol") and string.find(lowerName, "mas") and string.find(lowerName, "fac") then
                        defLoc = {-0.8, 0.2, 9.2}
                        defRot = {-63.5, -71.1, -31.6}
                    elseif string.find(lowerName, "fol") and string.find(lowerName, "fac") then
                        defLoc = {-1.0, 10.4, 11.7}
                        defRot = {3.8, -98.8, -33.5}
                    elseif string.find(lowerName, "fol") then
                        defLoc = {13.6, 12.6, 20.5}
                        defRot = {-82.0, 0.0, -100.6}
                    end

                    Config.pickupItemProfiles[itemName] = {
                        location = defLoc,
                        rotation = defRot
                    }
                    changed = true
                end

                if imgui.button("Reset Item to Default Offsets") then
                    Config.pickupItemProfiles[itemName] = nil
                    changed = true
                end
            else
                imgui.text("Nothing currently held.")
                imgui.text("Offsets below are global defaults for unconfigured items.")
            end
            imgui.separator()

            local locRef = Config.pickupItemLocation
            local rotRef = Config.pickupItemRotation
            if itemName and Config.pickupItemProfiles[itemName] then
                locRef = Config.pickupItemProfiles[itemName].location
                rotRef = Config.pickupItemProfiles[itemName].rotation
            end

            local pickupChanged = false
            local pLXc, pLXv = imgui.drag_float("Item Loc X##pickup", locRef[1], 0.1)
            if pLXc then locRef[1] = pLXv; pickupChanged = true end
            local pLYc, pLYv = imgui.drag_float("Item Loc Y##pickup", locRef[2], 0.1)
            if pLYc then locRef[2] = pLYv; pickupChanged = true end
            local pLZc, pLZv = imgui.drag_float("Item Loc Z##pickup", locRef[3], 0.1)
            if pLZc then locRef[3] = pLZv; pickupChanged = true end

            imgui.separator()

            local pRPc, pRPv = imgui.drag_float("Item Pitch##pickup", rotRef[1], 0.1)
            if pRPc then rotRef[1] = pRPv; pickupChanged = true end
            local pRYc, pRYv = imgui.drag_float("Item Yaw##pickup",   rotRef[2], 0.1)
            if pRYc then rotRef[2] = pRYv; pickupChanged = true end
            local pRRc, pRRv = imgui.drag_float("Item Roll##pickup",  rotRef[3], 0.1)
            if pRRc then rotRef[3] = pRRv; pickupChanged = true end

            if pickupChanged then
                changed = true
                -- physical_pickup reads the profile from Config directly on the next tick,
                -- but we update offset defaults just in case.
                if not itemName and ok and pickup and pickup.setOffset then
                    pickup.setOffset(locRef[1], locRef[2], locRef[3], rotRef[1], rotRef[2], rotRef[3])
                end
            end

            imgui.separator()

            if Config.pickupItemGrabRadius == nil then Config.pickupItemGrabRadius = 15.0 end
            local pickupRadiusChanged = false
            local pRadC, pRadV = imgui.drag_float("Grab Radius (cm)##pickup", Config.pickupItemGrabRadius, 0.5, 1.0, 100.0)
            if pRadC then Config.pickupItemGrabRadius = pRadV; pickupRadiusChanged = true end

            if pickupRadiusChanged then
                changed = true
                if ok and pickup and pickup.setRadius then
                    pickup.setRadius(Config.pickupItemGrabRadius)
                end
            end
            imgui.tree_pop()
        end
    end

    if changed then
        updateConfig(Config)
        Config:markDirty()
        Config:save()
    end
end)

-- ============================================================
-- Renderer Stabilizer (Fake Flashlight)
-- Spawns an invisible PointLightComponent attached to the pawn.
-- The presence of a dynamic point light forces UE's renderer to
-- keep refreshing its temporal history buffer each frame, which
-- stops the "trailing lines" glitch that appears with TAA/TSR.
-- ============================================================
local rendererStabilizerComponent = nil

function spawnRendererStabilizer()
    if rendererStabilizerComponent ~= nil then return end  -- already alive this session
    local p = uevr.api:get_local_pawn(0)
    if p == nil then return end

    local ok, result = pcall(function()
        -- create_component_of_class with parent=p calls AddComponentByClass internally,
        -- which registers the component as a child of the pawn actor.
        -- manualAttachment=true means UE does NOT auto-attach it further.
        -- We do NOT call K2_AttachToComponent to p.Mesh afterwards — that second
        -- attachment was creating ghost PointLightComponents when it raced against
        -- the Mesh not yet being ready. Attaching to the pawn root is sufficient.
        local comp = uevrUtils.create_component_of_class(
            "Class /Script/Engine.PointLightComponent",
            true,   -- manualAttachment (no additional auto-attach)
            nil,    -- relativeTransform (default)
            false,  -- deferredFinish
            p       -- parent = player pawn actor
        )
        if comp == nil then
            print("[RendererStabilizer] ERROR: create_component_of_class returned nil")
            return nil
        end
        comp:SetIntensity(0.001)   -- near-zero: invisible but non-zero so UE won't cull it
        comp:SetAttenuationRadius(100000.0)
        comp:SetCastShadows(false)
        comp:SetVisibility(true)
        print("[RendererStabilizer] Spawned fake PointLightComponent successfully (Radius 100k)")
        return comp
    end)

    if ok and result then
        rendererStabilizerComponent = result
    elseif not ok then
        print("[RendererStabilizer] ERROR during spawn: " .. tostring(result))
    end
end

function destroyRendererStabilizer()
    if rendererStabilizerComponent ~= nil then
        -- Nil the reference FIRST so any failure in the destroy call below
        -- does not leave a stale non-nil pointer that blocks future spawns.
        local comp = rendererStabilizerComponent
        rendererStabilizerComponent = nil
        pcall(function()
            uevrUtils.destroyComponent(comp, false)
        end)
        -- print("[RendererStabilizer] Destroyed fake PointLightComponent")
    end
end

-- Clean up BEFORE the Lua state is torn down on script reload.
-- This prevents the native UE component from persisting as an orphan.
uevr.params.sdk.callbacks.on_script_reset(function()
    destroyRendererStabilizer()
end)

-- On level change the pawn is recreated so the component is gone.
-- Nil the reference so the re-spawn interval can create a fresh one.
uevrUtils.registerPreLevelChangeCallback(function()
    rendererStabilizerComponent = nil
end)

-- Re-spawn after level transitions: poll until pawn is ready again.
-- Only fires when component is genuinely absent (post level-change or first load).
uevrUtils.setInterval(5000, function()
    if Config.rendererStabilizerEnabled and rendererStabilizerComponent == nil then
        spawnRendererStabilizer()
    end
end)

-- Initialize CVars on script start
apply_compatibility_cvars()

-- Spawn renderer stabilizer on script load if enabled in saved config
if Config.rendererStabilizerEnabled then
    delay(2000, function()
        spawnRendererStabilizer()
    end)
end



-- ============================================================
-- Suit Change Detection — VR Hand Mesh Rebuild
-- Watches pawn.Mesh.SkeletalMesh for asset changes that occur
-- when the player equips a different suit. When detected,
-- destroys the current VR hand PoseableMeshComponents and
-- re-arms the auto-create system so they are rebuilt from the
-- new mesh (picking up the new sleeve/glove textures).
-- ============================================================
local lastSuitSkeletalMesh = nil
uevrUtils.setInterval(1000, function()
    local p = uevr.api:get_local_pawn(0)
    if p == nil or p.Mesh == nil then return end
    local currentSkelMesh = p.Mesh.SkeletalMesh
    if currentSkelMesh == nil then return end

    if lastSuitSkeletalMesh ~= nil and currentSkelMesh ~= lastSuitSkeletalMesh then
        local meshName = "unknown"
        local ok, nm = pcall(function() return currentSkelMesh:get_full_name() end)
        if ok and nm then meshName = nm end
        print("[SuitDetect] SkeletalMesh changed to: " .. meshName .. " — rebuilding VR hands")
        -- Small delay to ensure UE has fully finished swapping the mesh asset
        -- before we read bone data for the new poseable components.
        delay(500, function()
            hands.rebuildHands()
        end)
    end
    lastSuitSkeletalMesh = currentSkelMesh
end)
