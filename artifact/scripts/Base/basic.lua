require(".\\Base\\Trackers\\Trackers")
require("Config.CONFIG")
local GameState = require("stalker2.gamestate")
local uevrUtils = require("libs/uevr_utils")

local api = uevr.api
local vr = uevr.params.vr

local ignore_aiming_state = true

--Config Recoil
-- local variables for Recoil
local VertDiff=0
local RotDiff=0
local DefaultOffset= uevr.params.vr:get_mod_value("VR_ControllerPitchOffset")
local LastTickRot=0
local GunFiringState = 0
local RotStart= 0
local SkipTick=false
local VertTickCount=0
local StoppedShooting= false
local RotDiffLast=0
local VertDiffLast=0
local DefaultAimMethod= uevr.params.vr:get_mod_value("VR_AimMethod")
local PreFireAimMethod= DefaultAimMethod
local UpdatePrefireAimMethod= false

-- Cache required classes
local function find_required_object(name)
    local obj = api:find_uobject(name)
    if not obj then
        error("Cannot find " .. name)
        return nil
    end
    return obj
end

-- Required classes
local kismet_math_library = find_required_object("Class /Script/Engine.KismetMathLibrary"):get_class_default_object()
local kismet_string_library = find_required_object("Class /Script/Engine.KismetStringLibrary"):get_class_default_object()
local KismetMaterialLibrary = find_required_object("Class /Script/Engine.KismetMaterialLibrary"):get_class_default_object()
local Statics = find_required_object("Class /Script/Engine.GameplayStatics"):get_class_default_object()
local CameraManager_c = find_required_object("Class /Script/Stalker2.CameraManager")
local motion_controller_component_c = find_required_object("Class /Script/HeadMountedDisplay.MotionControllerComponent")
local actor_c = find_required_object("Class /Script/Engine.Actor")
local ftransform_c = find_required_object("ScriptStruct /Script/CoreUObject.Transform")
local game_engine_class = find_required_object("Class /Script/Engine.GameEngine")
local hitresult_c = find_required_object("ScriptStruct /Script/Engine.HitResult")
local empty_hitresult = StructObject.new(hitresult_c)
local temp_transform = StructObject.new(ftransform_c)
temp_transform.Rotation.W = 1.0
local temp_vec3 = Vector3d.new(0, 0, 0)



-- Track hand components for aiming
-- REMOVED local declarations to use GLOBALS from Trackers.lua
-- local right_hand_component = nil
-- local left_hand_component = nil
-- local right_hand_actor = nil
-- local left_hand_actor = nil
local is_using_two_handed_weapon = false

-- Helper function to get equipped weapon
local function get_equipped_weapon(pawn)
    if not pawn then return nil end
    local sk_mesh = pawn.Mesh
    if not sk_mesh then return nil end
    local anim_instance = sk_mesh.AnimScriptInstance
    if not anim_instance then return nil end
    local weapon_data = anim_instance.WeaponData
    if not weapon_data then return nil end
    -- local is_aiming = weapon_data.AimingData.bAiming
    -- print("is_aiming: " .. tostring(is_aiming))
    return weapon_data.WeaponMesh
end

local function is_aiming(pawn)
    if ignore_aiming_state then return true end
    if not pawn then return false end
    local sk_mesh = pawn.Mesh
    if not sk_mesh then return false end
    local anim_instance = sk_mesh.AnimScriptInstance
    if not anim_instance then return false end
    local weapon_data = anim_instance.WeaponData
    if not weapon_data then return false end
    return weapon_data.AimingData.bAiming
end

local function is_using_two_handed_w(pawn)
    local weapon_mesh = get_equipped_weapon(pawn)
    if not weapon_mesh then return false end
    
    local wInfo = GameState:GetWeaponCache(weapon_mesh)
    if wInfo and wInfo.isTwoHanded ~= nil then
        return wInfo.isTwoHanded
    end
    
    return true -- Fallback assumption
end


local function is_using_two_handed_weapon_alt(pawn)
    if not pawn then return false end
    local sk_mesh = pawn.Mesh
    if not sk_mesh then return false end
    local anim_instance = sk_mesh.AnimScriptInstance
    if not anim_instance then return false end
    local weapon_data = anim_instance.WeaponData
    if not weapon_data.bHasWeaponInHands then return false end
    return anim_instance.WeaponData.FirearmData.bIsLeftHandIdleUnlocked
end

-- REMOVED: reset_hand_actors, spawn_actor, spawn_hand_actors 
-- These are now handled by Trackers.lua (via libs/controllers)

local function fix_effects(world)
    if not KismetMaterialLibrary then
        print("cached objects are null")
        return
    end
    local game_encamera_manager = UEVR_UObjectHook.get_first_object_by_class(CameraManager_c)
    if not game_encamera_manager then return end
    local fov_mpc = game_encamera_manager.FovMPC
    if not fov_mpc then return end
    local fov_collection = fov_mpc.Collection
    if not fov_collection then return end
    KismetMaterialLibrary:SetScalarParameterValue(world, fov_collection, "IsFOVEnabled", 0.0)
end


-- Helper function to calculate socket offset
local function update_weapon_offset(weapon_mesh, pawn)
    if not weapon_mesh then return end

    local virtualGunstock = Config.virtualGunstock and GameState:is_scope_active(pawn)
    
    -- Check for weapon mod animations (silencer, sight)
    -- User requested to REMOVE the weapon detachment logic. 
    -- The weapon should stay with the controller.
    -- if GameState.isWeaponModMontageActive then
    --    return
    -- end

    local offset = Vector3f.new(0, 0, 0)
    if virtualGunstock then
        -- offset = kismet_math_library:Subtract_VectorVector(default_transform.Translation, offset_transform.Translation)
        local parent_transform = weapon_mesh:GetSocketTransform(weapon_mesh.AttachSocketName, 0)
        -- Optimization: Use Cached Scope Look-up
        local weaponInfo = GameState:GetWeaponCache(weapon_mesh)
        local scope_mesh = weaponInfo and weaponInfo.scope
        
        local child_transform
        if scope_mesh then
            child_transform = scope_mesh:GetSocketTransform("OpticCutoutSocket", 0)
        else
            child_transform = weapon_mesh:GetSocketTransform("AimSocket", 0)
        end
        local offset_transform = kismet_math_library:MakeRelativeTransform(child_transform, parent_transform)
        offset = offset_transform.Translation
        offset.x = offset.x - 3.5
    else
        local parent_transform = weapon_mesh:GetSocketTransform(weapon_mesh.AttachSocketName, 0)
        local child_transform = weapon_mesh:GetSocketTransform("jnt_offset", 0)
        local offset_transform = kismet_math_library:MakeRelativeTransform(child_transform, parent_transform)
        offset = offset_transform.Translation
    end
    -- Get socket transforms

    -- from UE to UEVR X->Z Y->-X, Z->-Y
    -- Z - forward, X - negative right, Y - negative up
    local lossy_offset = Vector3f.new(offset.y, offset.z+VertDiff, -offset.x)
    -- Apply the offset to the weapon using motion controller state
    UEVR_UObjectHook.get_or_add_motion_controller_state(weapon_mesh):set_hand(virtualGunstock and 2 or Config.dominantHand)
    UEVR_UObjectHook.get_or_add_motion_controller_state(weapon_mesh):set_location_offset(lossy_offset)
    UEVR_UObjectHook.get_or_add_motion_controller_state(weapon_mesh):set_permanent(true)
end

local last_level = nil

-- Tick callback for effects and creating hand components if needed
uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
    local viewport = engine.GameViewport
    if viewport then
        local world = viewport.World
        if world then
            local level = world.PersistentLevel
            fix_effects(world)
            if last_level ~= level then
                print("Level changed ..")
                -- reset_hand_actors() -- Handled by Trackers/Controllers
            end
            last_level = level
        end
    end

    -- REMOVED: Spawn hand components if needed
    -- Handled by Trackers.lua

    -- Check if weapon is two-handed (simplified logic, might need adjustment based on your game's weapon system)
    local pawn = api:get_local_pawn(0)
    if pawn and pawn.Mesh then
        local weapon_mesh = get_equipped_weapon(pawn)
        if weapon_mesh then
            weapon_mesh.CastShadow = false
            weapon_mesh.bCastContactShadow = false
            weapon_mesh.bCastDynamicShadow = Config.vrShadowsEnabled
            weapon_mesh:SetCastShadow(Config.vrShadowsEnabled)
            weapon_mesh.bCastStaticShadow = false
            -- smg/pistols considered one-handed if you want 2-handed aim with smg use is_using_two_handed_w(pawn)
            is_using_two_handed_weapon = is_using_two_handed_w(pawn)
        end
    end
end)

-- Moving weapon offset and two-handed logic to on_post_calculate_stereo_view_offset
uevr.sdk.callbacks.on_post_calculate_stereo_view_offset(function(device, view_index, world_to_meters, position, rotation, is_double)
    if not vr.is_hmd_active() or view_index ~= 1 then
        return
    end

    local pawn = api:get_local_pawn(0)
    if not pawn or not pawn.Mesh then
        return
    end

    local equipped_weapon = get_equipped_weapon(pawn)
    if not equipped_weapon then
        return
    end

    -- First apply the original weapon offset logic
    update_weapon_offset(equipped_weapon, pawn)

    -- Globals from Trackers.lua
    if not left_hand_component or not right_hand_component then
        return
    end
    
    -- Two handed weapon aiming (like rifles and shotguns)
    if Config.twoHandedAiming and TwoHandedStateActive and is_using_two_handed_weapon and is_aiming(pawn) then
        local dominant_hand_component
        if Config.dominantHand == 1 then dominant_hand_component = right_hand_component else dominant_hand_component = left_hand_component end
        local off_hand_component
        if Config.dominantHand == 1 then off_hand_component = left_hand_component else off_hand_component = right_hand_component end
        local dominant_hand_pos = dominant_hand_component:K2_GetComponentLocation()
        local off_hand_pos = off_hand_component:K2_GetComponentLocation()
        local dir_to_dominant_hand = (off_hand_pos - dominant_hand_pos):normalized()
        local dominant_hand_rotation = dominant_hand_component:K2_GetComponentRotation()

        local root = equipped_weapon
        local weapon_up_vector = root:GetUpVector()
        local new_direction_rot = kismet_math_library:MakeRotFromXZ(dir_to_dominant_hand, weapon_up_vector)

        local dir_to_dominant_hand_q = kismet_math_library:Conv_RotatorToQuaternion(new_direction_rot)
        local dominant_hand_q = kismet_math_library:Conv_RotatorToQuaternion(dominant_hand_rotation)

        local delta_q = kismet_math_library:Quat_Inversed(kismet_math_library:Multiply_QuatQuat(dominant_hand_q, kismet_math_library:Quat_Inversed(dir_to_dominant_hand_q)))

        local original_grip_position = off_hand_pos
        local delta_to_grip = original_grip_position - root:K2_GetComponentLocation()
        local delta_rotated_q = kismet_math_library:Quat_RotateVector(delta_q, delta_to_grip)

        local current_rotation = root:K2_GetComponentRotation()
        local current_rot_q = kismet_math_library:Conv_RotatorToQuaternion(current_rotation)
        local new_rot_q = kismet_math_library:Multiply_QuatQuat(delta_q, current_rot_q)

        current_rotation = kismet_math_library:Quat_Rotator(new_rot_q)
        root:K2_SetWorldRotation(current_rotation, false, empty_hitresult, false)

        -- local new_weapon_position = original_grip_position - delta_rotated_q
        -- root:K2_SetWorldLocation(new_weapon_position, false, empty_hitresult, false)

        --detach_flashlight(my_pawn) -- Not gonna detach... for now

    end
end)

-- Reset callback
uevr.sdk.callbacks.on_script_reset(function()
    print("Resetting weapon offset and two-handed aiming script")
    -- Cleanup hand components
    reset_hand_actors()
end)


-- weapon.bCastContactShadow = false
-- weapon.bCastDynamicShadow = false
-- weapon.bCastStaticShadow = false
-- weapon.bAffectDynamicIndirectLighting = false
-- weapon.bAffectDistanceFieldLighting = false

-- Helper Function for recoil calculation

function PositiveIntegerMask(text)
	return text:gsub("[^%-%d]", "")
end



local function ApplyRecoilRecovery()
	if GunFiringState ~= 1 then
		local durationa=20

		if VertTickCount<durationa then
			local decrementVert = VertDiffLast / durationa
			local decrementRot  = RotDiffLast / durationa
			VertTickCount=VertTickCount+1
			VertDiff = VertDiffLast-decrementVert*VertTickCount
			RotDiff = RotDiffLast - decrementRot*VertTickCount
		elseif VertTickCount>=durationa then
				VertDiff=0
				RotDiff=0
		end
		local FinalAngle=tostring(PositiveIntegerMask(DefaultOffset)/1000000-RotDiff)
		uevr.params.vr.set_mod_value("VR_ControllerPitchOffset", FinalAngle)
	else VertTickCount=0
	end
end

local function GetGunFiringState()
	local pawn = api:get_local_pawn(0)
	GunFiringState = 0  -- Default: not firing. Stays 0 if pcall fails (throwable has no WeaponPushbackData)
	pcall(function()
	GunFiringState = pawn.Mesh.AnimScriptInstance.WeaponPushbackData.State
	end)
end

local function UpdateOnStoppedShooting()
	if GunFiringState==3 and StoppedShooting==false then
		RotDiffLast= RotDiff
		--VertDiffLast= VertDiff

		StoppedShooting= true
	elseif GunFiringState ~= 3 then
		StoppedShooting=false
	end
end

local function ApplyRecoil()

	--if SkipTick then
	--uevr.params.vr.set_mod_value("VR_AimMethod" , PreFireAimMethod)
	--SkipTick=false
	--end

	if RotDiff~=0 then
		if UpdatePrefireAimMethod ==false then
				PreFireAimMethod=uevr.params.vr:get_mod_value("VR_AimMethod")
				UpdatePrefireAimMethod=true
		end
			uevr.params.vr.set_mod_value("VR_AimMethod" , "0")
	else
		if UpdatePrefireAimMethod == true then
			uevr.params.vr.set_mod_value("VR_AimMethod" , PreFireAimMethod)
		end
		UpdatePrefireAimMethod = false
	end

	if GunFiringState == 1 then
		local FinalAngle=tostring(PositiveIntegerMask(DefaultOffset)/1000000-RotDiff)
		uevr.params.vr.set_mod_value("VR_ControllerPitchOffset", FinalAngle)
		VertDiff = math.tan(RotDiff*math.pi/180)* 25
		VertDiffLast=VertDiff
	end
end



----------------------------------------------

-- Returns true when bolt, knife, or grenade is equipped
-- Recoil must be fully disabled for these: they have no WeaponPushbackData
-- and the aim-method capture in ApplyRecoil() picks up a stale "0" from the
-- brief menu state during quick-select, then restores to that incorrect value.
local function isThrowableEquipped()
	local pawn = api:get_local_pawn(0)
	if not pawn then return false end
	local ok, result = pcall(function()
		local weaponMesh = pawn.Mesh.AnimScriptInstance.WeaponData.WeaponMesh
		-- No weapon equipped (bare hands): skip recoil entirely.
		-- During holster animations WeaponPushbackData.State can be stale/non-zero
		-- which causes RotDiff to build and ApplyRecoil to push aim to Game (0).
		if not weaponMesh or not weaponMesh.SkeletalMesh then return true end
		local name = string.lower(weaponMesh.SkeletalMesh:get_fname():to_string())
		return  name:find("bolt")    ~= nil
		     or name:find("knife")   ~= nil
		     or name:find("sk_f1")   ~= nil
		     or name:find("sk_rgd")  ~= nil
		     or name:find("grenade") ~= nil
	end)
	return ok and result == true
end



--Callback for calculating Recoil
uevr.params.sdk.callbacks.on_early_calculate_stereo_view_offset(
function(device, view_index, world_to_meters, position, rotation, is_double)

	-- Skip ALL recoil logic for throwables. They have no WeaponPushbackData so
	-- GunFiringState goes stale, and ApplyRecoil() captures the wrong aim method.
	if isThrowableEquipped() then
		GunFiringState = 0
		RotDiff = 0
		RotStart = rotation.x  -- keep in sync so no stale jump on next gun equip
		UpdatePrefireAimMethod = false  -- discard any stale aim-method snapshot
		return
	end

	GetGunFiringState()
	if GunFiringState== 0 then
		RotStart= rotation.x
	end
	RotDiff = RotStart - rotation.x

	if Config.recoil then
		ApplyRecoil()
		UpdateOnStoppedShooting()
		ApplyRecoilRecovery()
	end

end)

--callback to disable up down with stick while shooting
uevr.sdk.callbacks.on_xinput_get_state(
function(retval, user_index, state)


	if GunFiringState	~=0 then
		state.Gamepad.sThumbRY =0
	end


end)