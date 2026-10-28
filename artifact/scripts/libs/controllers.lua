--[[ 
Usage
	Drop the lib folder containing this file into your project folder
	At the top of your script file add 
		local controllers = require("libs/controllers")
		
	In your code call function like this
		controllers.destroyControllers()
		
	In all of the functions, controllerID=0 is the left controller, controllerID=1 is the right controller and controllerID=2 is the hmd controller
	
	Available functions:
	
	controllers.onLevelChange() - call this function when there is a level change to clean up any allocated resources
		
	controllers.createController(controllerID) - creates the left controller (controllerID=0), right controller (controllerID=1) or hmd controller (controllerID=2)		
		example:
			function on_level_change(level)
				print("Level changed\n")
				controllers.onLevelChange()
				controllers.createController(0)
				controllers.createController(1)
				controllers.createController(2) 
			end
			
	controllers.createHMDController() - same as calling controllers.createController(2)
	
	controllers.getController(controllerID) - returns the component associated with the controllerID. 
		For controllerIDs 0 and 1 this is a "Class /Script/HeadMountedDisplay.MotionControllerComponent" class. 
		For controllerID 2 this is a "Class /Script/Engine.SceneComponent" class
		example:
			local hmdComponent = controllers.getController(2)
			
	controllers.getHMDController()  - same as calling controllers.getController(2)
	
	controllers.controllerExists(controllerID) - returns true if the given controllerID is already created. 
		Same as calling controllers.getController(controllerID) ~= nil
		example:
			local hmdExists = controllers.controllerExists(2)
			
	controllers.hmdControllerExists() - same as calling controllers.controllerExists(2)
	
	controllers.destroyController(controllerID) - deallocate the resources associated the given controllerID
		example:
			controllers.destroyController(2)
	
	controllers.destroyControllers() - deallocate the resources associated with all controllers
		example:
			controllers.destroyControllers()
			
	controllers.attachComponentToController(controllerID, childComponent, (optional)socketName, (optional)attachType, (optional)weld) - attach an 
		element derived from a component class to the given controller.
		Returns true if successful
		example:
			local weapon = pawn:GetCurrentWeapon()
			if weapon ~= nil  then
				local meshComponent = weapon.SkeletalMeshComponent
				if meshComponent ~= nil then
					meshComponent:DetachFromParent(false,false)
					meshComponent:SetVisibility(true, true)
					meshComponent:SetHiddenInGame(false, true)
					weaponConnected = controllers.attachComponentToController(1, meshComponent)
					uevrUtils.set_component_relative_transform(meshComponent, {X=0,Y=0,Z=0}, {Pitch=0,Yaw=0,Roll=0})
				end
			end

	controllers.getControllerLocation(controllerID) - gets the current position FVector in world space of the given controller or nil if none found
		example:
			local rightLocation = controllers.getControllerLocation(1)
			print("X is", rightLocation.X)

	controllers.getControllerRotation(controllerID) - gets the current rotation FRotator in world space of the given controller or nil if none found
		example:
			local rightRotation = controllers.getControllerRotation(1)
			print("Yaw is", rightRotation.Yaw)

	controllers.getControllerDirection(controllerID) - gets the current forward vector FVector of the given controller or nil if none found
		example:
			local hmdDirection = controllers.getControllerDirection(2)
			print("Forward Vector is", hmdDirection.X, hmdDirection.Y, hmdDirection.Z)

	controllers.getControllerUpVector(controllerID) - gets the current up vector FVector of the given controller or nil if none found
		example:
			local rightUpVector = controllers.getControllerUpVector(1)
			print("Up Vector is", rightUpVector.X, rightUpVector.Y, rightUpVector.Z)

	controllers.getControllerRightVector(controllerID) - gets the current right vector FVector of the given controller or nil if none found
		example:
			local leftRightVector = controllers.getControllerRightVector(0)
			print("Right Vector is", leftRightVector.X, leftRightVector.Y, leftRightVector.Z)

	controllers.getControllerTargetLocation(handed, collisionChannel, ignoreActors, traceComplex, minHitDistance) - performs line trace from controller and returns hit location
		example:
			local hitLocation = controllers.getControllerTargetLocation(0, 0, {}, false, 10)

	controllers.setLogLevel(val) - sets the logging level for controller debug output
		example:
			controllers.setLogLevel(LogLevel.Info)

]]--

local uevrUtils = require("libs/uevr_utils")

local M = {}

local sourceNames = {[0]="Left",[1]="Right"}
local actors = {}

local currentLogLevel = LogLevel.Error
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
	if logLevel == nil then logLevel = LogLevel.Debug end
	if logLevel <= currentLogLevel then
		uevrUtils.print("[controllers] " .. text, logLevel)
	end
end

local function getCachedController(controllerID)
	local actor = actors[controllerID]
	local found = nil
	-- Property reads on an actor the engine is mid-destroying throw a C++ exception
	-- (exists() alone doesn't rule that out on this UEVR build - see isLiveComponent).
	pcall(function()
		if actor ~= nil and UEVR_UObjectHook.exists(actor) then
			local components = actor.BlueprintCreatedComponents
			if components ~= nil then
				for index, component in pairs(components) do
					if component ~= nil then
						if controllerID == 2 then
							found = component
							return
						else
							-- PERF (2026-09-08): get_class caches the find_uobject result; find_required_object did not,
							-- and this runs per component per call from every per-tick getController(id, true) caller.
							if component:is_a(uevrUtils.get_class("Class /Script/HeadMountedDisplay.MotionControllerComponent")) then
								found = component
								return
							end
						end
					end
				end
			end
		end
	end)
	return found
end


local function destroyActor(actor)
	if actor ~= nil then
		pcall(function()
			local components = actor.BlueprintCreatedComponents
			for index, component in pairs(components) do
				if component ~= nil then
					M.print("Destroying controller component " .. component:get_full_name()) 
					pcall(function()
						if actor.K2_DestroyComponent ~= nil then
							actor:K2_DestroyComponent(component)
							M.print("HMD Controller component destroyed")
						end
					end)	
				end
			end
			if actor.K2_DestroyActor ~= nil then
				actor:K2_DestroyActor()
				M.print("HMD Controller actor destroyed")
			end
		end)	
	end
end

local function createControllerComponent(parentActor, sourceName, handIndex)	
	local sourceNameStr = sourceName or "Unknown"
	local handIndexStr = handIndex ~= nil and tostring(handIndex) or "Unknown"
	M.print("Creating controller " .. sourceNameStr .. " " .. handIndexStr) -- thanks to Lukasblaster
	if parentActor ~= nil then
		local motionControllerComponent = uevrUtils.create_component_of_class("Class /Script/HeadMountedDisplay.MotionControllerComponent", true, uevrUtils.get_transform(), false, parentActor)
		--local motionControllerComponent = parentActor:AddComponentByClass(uevrUtils.get_class("Class /Script/HeadMountedDisplay.MotionControllerComponent"), true, uevrUtils.get_transform(), false)
		if motionControllerComponent ~= nil then
			motionControllerComponent:SetCollisionEnabled(0, false)
			--motionControllerComponent:SetCollisionResponseToAllChannels(0)
			motionControllerComponent.MotionSource = uevrUtils.fname_from_string(sourceName)
			if motionControllerComponent.Hand ~= nil then
				motionControllerComponent.Hand = handIndex
			end
			
			M.print("Controller created")
			return motionControllerComponent
		end
	else
		M.print("Couldn't create controller because parentActor was nil")
	end
	return nil
end

local function createHMDControllerComponent()	
	M.print("Creating HMD controller")
	local hmdIndex = 2
	local parentActor = uevrUtils.spawn_actor(uevrUtils.get_transform(), 1, nil)
	if parentActor ~= nil then
		M.print("Created HMD controller actor " .. parentActor:get_full_name())
		local motionControllerComponent = uevrUtils.create_component_of_class("Class /Script/Engine.SceneComponent", true, uevrUtils.get_transform(), false, parentActor)
		--local motionControllerComponent = parentActor:AddComponentByClass(uevrUtils.get_class("Class /Script/Engine.SceneComponent"), true, uevrUtils.get_transform(), false)
		if motionControllerComponent ~= nil then
			local hmdState = UEVR_UObjectHook.get_or_add_motion_controller_state(motionControllerComponent)	
			if hmdState ~= nil then
				hmdState:set_hand(hmdIndex) 
				hmdState:set_permanent(true)
				actors[hmdIndex] = parentActor
				M.print("Controller created")
				return motionControllerComponent
			else
				M.print("HMD Controller state creation failed", LogLevel.Warning)
			end	
		else
			M.print("HMD Controller component creation failed", LogLevel.Warning)
		end
	else
		M.print("HMD Controller actor creation failed", LogLevel.Warning)
	end
	destroyActor(parentActor)
	return nil
end

local function createActor(controllerID)
	actors[controllerID] = uevrUtils.spawn_actor(uevrUtils.get_transform(), 1, nil)
	return actors[controllerID]
end

local function resetMotionControllers()
	M.print("Removing all motion controller states")
	if UEVR_UObjectHook.remove_all_motion_controller_states ~= nil then
		UEVR_UObjectHook.remove_all_motion_controller_states()
	end
end

local createAutoCreationMonitor = doOnce(function()
    uevrUtils.setInterval(1000, function()
        M.ensureHMDState()
        if M.controllerExists(Handed.Left, false) == false then
            M.createController(Handed.Left)
        end
        if M.controllerExists(Handed.Right, false) == false then
            M.createController(Handed.Right)
        end
    end)
end, Once.EVER)

function M.autoMonitorHands()
	createAutoCreationMonitor()
end

function M.onLevelChange()
	resetMotionControllers()
	-- Explicitly destroy the old actors (M.destroyControllers(), not just
	-- M.resetControllers()) rather than only forgetting the Lua-side actors[]
	-- references. This runs from the registered pre-level-change callback below,
	-- while the old world is still valid - the safe moment to actually tear these
	-- down. Skipping the destroy left a real deferred-GC race: the old
	-- MotionControllerComponent can still pass UEVR_UObjectHook.exists() for a few
	-- frames after the level change even though it's orphaned from the destroyed
	-- world, and M.createController()'s uncached existence check
	-- (M.controllerExists(id, false), a raw find_all_of scan independent of
	-- actors[]) can rediscover it and have M.restoreExistingComponents() re-adopt
	-- it into actors[id]. Any later K2_AttachTo onto that stale controller then
	-- throws (matches "Exception in on_pre_engine_tick: ... in method
	-- 'K2_AttachTo'" reports). Same class of bug already fixed for
	-- BoxCompLH/MagBox in stalker2/mag_reload.lua - don't trust "still alive" to
	-- mean "still valid" across a level transition, destroy and recreate instead.
    M.destroyControllers()
end

function M.getHMDController()
	return getCachedController(2)
end


-- A component can still be enumerated by find_all_of - and even pass exists(), which on
-- this UEVR build ADOPTS unknown pointers rather than rejecting them (log.txt: "[UObjectHook]
-- Adopted untracked UObject from plugin exists()") - for a few frames after the engine
-- destroyed it. The gesture layer (gestures/motioncontrolleractors.lua) spawns its OWN
-- left/right MotionControllerComponents, and Entry.lua's on_script_reset destroys them; if
-- the uncached scan below then hands one of those corpses out as "the left controller",
-- everything attached to it afterwards (hand PMC, detector) is orphaned the moment it
-- finishes dying - a frozen-but-still-animating hand. KismetSystemLibrary::IsValid is the
-- engine's canonical check (false for pending-kill objects, safe to call while the object
-- is still allocated) and is the primary test here; bRegistered is kept as a cheap extra
-- but is NOT in the reflected property set on this build (absent from live component
-- dumps), so it reads nil and is a no-op - don't rely on it alone. Property/method calls
-- on a dead component throw, so the whole check is pcall'd and a throw counts as dead.
local function isLiveComponent(component)
	local live = false
	pcall(function()
		if component == nil or not UEVR_UObjectHook.exists(component) then return end
		if kismet_system_library ~= nil and kismet_system_library.IsValid ~= nil
		   and not kismet_system_library:IsValid(component) then return end
		if component.bRegistered == false then return end
		live = true
	end)
	return live
end

-- Re-arm the HMD SceneComponent's UObjectHook motion-controller state (hand=2).
-- On the joeyhodge/AFW backend (Stalker 2 lazy UObjectHook guard) every state is keyed by the
-- component's GUObjectArray (InternalIndex, SerialNumber) captured at get_or_add time. A freshly
-- spawned component has SerialNumber 0 - the engine only allocates one the first time something
-- takes a TWeakObjectPtr to it. input.lua's SetAudioListenerOverride does exactly that a moment
-- after we create the HMD component, so the captured (index, 0) identity stops matching and the
-- per-tick prune drops the state ("Pruned 1 stale motion-controller attachment identities" in
-- log.txt). The component then sits at world origin forever: the audio listener is ~600 km from
-- the player (every spatialized sound inaudible), scope.lua's distance check never passes, etc.
-- get_or_add re-keys a mismatched entry with the CURRENT identity but hands back a default state
-- (hand 0, not permanent), so hand/permanent are re-applied every time. Idempotent and cheap.
function M.ensureHMDState()
	local comp = getCachedController(2)
	if comp == nil or not isLiveComponent(comp) then return false end
	local ok = pcall(function()
		local state = UEVR_UObjectHook.get_or_add_motion_controller_state(comp)
		if state ~= nil then
			state:set_hand(2)
			state:set_permanent(true)
		end
	end)
	return ok
end

function M.getController(controllerID, useCached)
	if useCached == true then
		return getCachedController(controllerID)
	else
		if controllerID == 2 then
			return M.getHMDController()
		else
			-- Prefer our own component once actors[] holds a live one. The world scan
			-- below returns the FIRST Left/Right-source MotionControllerComponent in
			-- GUObjectArray order, and this project has two independent sets: ours, and
			-- the gesture layer's (gestures/motioncontrolleractors.lua spawns its own).
			-- Which set the scan hits first varies per reset cycle, so hands.lua, the
			-- detector and Trackers.lua could each end up on a different "left controller"
			-- - and the gesture layer's set is destroyed by Entry.lua's on_script_reset,
			-- orphaning whatever got attached to it (the stuck-left-hand-after-reset bug).
			-- Ours persist across a script reset (no reset handler here by design), so
			-- resolving to them is both deterministic and reset-safe.
			local own = getCachedController(controllerID)
			if own ~= nil and isLiveComponent(own) then
				return own
			end
			M.print("Getting controller without cache")
			local controllers = uevrUtils.find_all_of("Class /Script/HeadMountedDisplay.MotionControllerComponent", false)
			if controllers ~= nil then
				for index, controller in pairs(controllers) do
					-- find_all_of can return components the engine has already destroyed
					-- (seen after an in-game script reset); touching one throws a C++
					-- exception, so validate and pcall the property reads.
					if isLiveComponent(controller) then
						local matched = false
						pcall(function()
							if controller.Hand ~= nil then
								matched = (controller.Hand == controllerID)
							else
								matched = (controller.MotionSource:to_string() == sourceNames[controllerID])
							end
						end)
						if matched then
							return controller
						end
					end
				end
			
			end
		end
	end

	return nil
end

--called after a script restart
function M.restoreExistingComponents()
	for i = 0, 1 do
		if getCachedController(i) == nil then
			local controller = M.getController(i)
			if controller ~= nil then
				-- After a script reset the motion-controller state can still point at a
				-- component the engine has since destroyed; any method call on it (even
				-- get_full_name) throws a C++ exception. Validate first and pcall the rest.
				if isLiveComponent(controller) then
					pcall(function()
						-- M.print isnt ready at this point so just use print
						local owner = controller:GetOwner()
						if owner then
							print("Restoring existing controller " .. i .. ": " .. controller:get_full_name() .. " " .. owner:get_full_name())
							actors[i] = owner
						else
							print("Restoring existing controller " .. i .. ": " .. controller:get_full_name() .. " (No Owner)")
						end
					end)
				else
					print("Skipping restore of controller " .. i .. ": stale component after script reset")
				end
			end
		end
	end
end

function M.hmdControllerExists()
	return M.getHMDController() ~= nil
end

function M.controllerExists(controllerID, useCached)
	--return M.getController(controllerID, false) ~= nil

	if useCached == nil then useCached = true end
	local controller = M.getController(controllerID, useCached)
	-- if useCached == true and controller == nil then
		-- controller = M.getController(controllerID, false)
	-- end
	return controller ~= nil
end

function M.createHMDController()
	local controller = nil
	if not M.hmdControllerExists() then
		controller = createHMDControllerComponent()
	end
	return controller
end

local function createRightControllerComponent()	
	createControllerComponent(createActor(1), "Right", 1)
end
local function createLeftControllerComponent()	
	createControllerComponent(createActor(0), "Left", 0)
end

function M.createController(controllerID)
	M.print("Creating controller " ..  controllerID)
	if controllerID == 2 then
		return M.createHMDController()
	else
		local controller = nil
		if not M.controllerExists(controllerID, true) then
			if not M.controllerExists(controllerID, false) then
				controller = createControllerComponent(createActor(controllerID), sourceNames[controllerID], controllerID)
			else
				M.restoreExistingComponents()
			end
		end
		return controller
	end
end

function M.destroyController(controllerID)
	destroyActor(actors[controllerID])
	actors[controllerID] = nil
end

function M.destroyControllers()
	M.destroyController(0)
	M.destroyController(1)
	M.destroyController(2)
	M.resetControllers()
end

function M.resetControllers()
	actors[0] = nil
	actors[1] = nil
	actors[2] = nil
	actors = {}
end

--controllerID 0-left, 1-right, 2-head
function M.attachComponentToController(controllerID, childComponent, socketName, attachType, weld, createIfNotExists)
	if socketName == nil then socketName = "" end
	if attachType == nil then attachType = 0 end
	if weld == nil then weld = false end
	if childComponent ~= nil then
		M.print("Attaching component " .. childComponent:get_full_name() .. " to controller " .. controllerID)
		local controller = M.getController(controllerID)
		if controller == nil and createIfNotExists == true then
			controller = M.createController(controllerID)
		end
		if controller ~= nil then
			-- Right after a script reset / level change the controller can pass isLiveComponent()
			-- and still be mid-teardown (e.g. the gesture layer's set that Entry.lua's
			-- on_script_reset destroys in the same moment, picked up by the uncached scan above
			-- because our own actors[] is empty after the reset). K2_AttachTo then throws a C++
			-- exception out of on_pre_engine_tick ("Last Script Error ... in method 'K2_AttachTo'")
			-- and the caller never reaches its own failure handling, leaving the freshly created
			-- hand mesh orphaned. Report it as "not attached" instead: hands.createComponent
			-- already discards the component and retries on its 1 s timer when this returns false.
			local ok, attached = pcall(function()
				return childComponent:K2_AttachTo(controller, uevrUtils.fname_from_string(socketName), attachType, weld)
			end)
			if not ok then
				M.print("K2_AttachTo threw for controller " .. controllerID .. " (component mid-teardown) - caller will retry", LogLevel.Warning)
				return false
			end
			return attached
		else
			M.print("Could not attach component to controller " .. controllerID .. " because controller is nil")
		end
	else
		M.print("Could not attach component to controller " .. controllerID .. "  because childComponent is nil")
	end
	return false
end

-- returns an FVector or nil
-- HMD fallback (2026-09-08): on the joeyhodge backend the mod-spawned HMD SceneComponent
-- (createHMDControllerComponent, driven by UEVR_UObjectHook motion-controller state, hand=2)
-- never moves - K2_GetComponentLocation and RelativeLocation both stay 0,0,0 while the
-- Left/Right MotionControllerComponents track normally. Anything measuring distance to the
-- head (PiP scope activation, parallax red dot) silently failed. The pawn camera component
-- is placed at the HMD by UEVR every frame, so use it whenever the HMD component reads as
-- the origin. Falls back to PlayerCameraManager if the pawn has no Camera field.
local function hmdFallbackLocation()
	local loc = nil
	pcall(function()
		local pawn = uevr.api:get_local_pawn(0)
		if pawn ~= nil and pawn.Camera ~= nil then
			loc = pawn.Camera:K2_GetComponentLocation()
		end
	end)
	if loc == nil then
		pcall(function()
			local pc = uevr.api:get_player_controller(0)
			if pc ~= nil and pc.PlayerCameraManager ~= nil then
				loc = pc.PlayerCameraManager:GetCameraLocation()
			end
		end)
	end
	return loc
end

function M.getControllerLocation(controllerID)
	local controller = M.getController(controllerID, true)
	if controller ~= nil then
		local loc = controller:K2_GetComponentLocation()
		if controllerID == 2 and loc ~= nil and loc.X == 0 and loc.Y == 0 and loc.Z == 0 then
			local fb = hmdFallbackLocation()
			if fb ~= nil then return fb end
		end
		return loc
	-- else
		-- --try getting the pose directly
		-- local index = uevrUtils.getControllerIndex(controllerID)
		-- if index ~= nil then
			-- uevr.params.vr.get_pose(index, temp_vec3f, temp_quatf)
			-- return uevrUtils.vector(temp_vec3f.X,temp_vec3f.Y,temp_vec3f.Z)
		-- end	
	end
	return nil
end

function M.getControllerRotation(controllerID)
	local controller = M.getController(controllerID, true)
	if controller ~= nil then
		return controller:K2_GetComponentRotation()
	-- else
		-- --try getting the pose directly
		-- local index = uevrUtils.getControllerIndex(controllerID)
		-- if index ~= nil then
			-- uevr.params.vr.get_pose(index, temp_vec3f, temp_quatf)
			-- local poseQuat = uevrUtils.quat(temp_quatf.Z, temp_quatf.X, -temp_quatf.Y, -temp_quatf.W)  --reordered terms to convert UEVR to unreal coord system
			-- local poseRotator = kismet_math_library:Quat_Rotator(poseQuat)
			-- return poseRotator
		-- end	
	end
	return nil
end

function M.getControllerDirection(controllerID)
	local controller = M.getController(controllerID, true)
	if controller ~= nil then
		return kismet_math_library:GetForwardVector(M.getControllerRotation(controllerID))
	end
	return nil
end

function M.getControllerUpVector(controllerID)
	local controller = M.getController(controllerID, true)
	if controller ~= nil then
		return kismet_math_library:GetUpVector(M.getControllerRotation(controllerID))
	end
	return nil
end

function M.getControllerRightVector(controllerID)
	local controller = M.getController(controllerID, true)
	if controller ~= nil then
		return kismet_math_library:GetRightVector(M.getControllerRotation(controllerID))
	end
	return nil
end

function M.getControllerTargetLocation(handed, collisionChannel, ignoreActors, traceComplex, minHitDistance)
	if not M.controllerExists(handed) then
		M.createController(handed)
	end
	local direction = M.getControllerDirection(handed)
	if direction ~= nil then
		local startLocation = M.getControllerLocation(handed)
		if startLocation ~= nil then
			return uevrUtils.getTargetLocation(startLocation, direction, collisionChannel, ignoreActors, traceComplex, minHitDistance)
		else
			M.print("Error in getControllerTargetLocation. Controller location was nil")
		end
	else
		M.print("Error in getControllerTargetLocation. Controller direction was nil")
	end
	return nil
end

-- returns an float or nil
function M.getDistanceFromController(controllerID, component)
	if component ~= nil then
		local loc1 = M.getControllerLocation(controllerID)
		if loc1 ~= nil then
			local loc2 = component:K2_GetComponentLocation()
			if loc2 ~= nil then
				return uevrUtils.distanceBetween(loc1, loc2)
			end
		end
	end
	return nil
end


local isRestored = false
uevrUtils.registerPreLevelChangeCallback(function(level)
	M.print("Pre-Level changed in controllers")
	M.onLevelChange()
	if not isRestored then
		M.restoreExistingComponents()
		isRestored = true
	end
end)

uevrUtils.registerLevelChangeCallback(function(level)
	M.createController(0)
	M.createController(1)
	M.createController(2)
end)

return M






-- function createHMDComponent()
	-- pawn = uevr.api:get_local_pawn(0)
	-- if hmdActor ~= nil then 
		-- destroyHMDComponent()
	-- end
	-- if pawn ~= nil then
		-- print("Create HMD component called\n")
		-- local pos = pawn:K2_GetActorLocation()
		-- if hmdActor == nil then
			-- hmdActor = uevrUtils.spawn_actor( uevrUtils.get_transform({X=pos.X, Y=pos.Y, Z=pos.Z}), 1, nil)
		-- end
		-- if hmdActor == nil then
			-- print("Failed to spawn HMD actor\n")
		-- else
			-- temp_transform.Translation = pos
			-- temp_transform.Rotation.W = 1.0
			-- temp_transform.Scale3D = Vector3f.new(1.0, 1.0, 1.0)
			-- if hmdComponent == nil then
				-- local scene_component_c = uevrUtils.find_required_object("Class /Script/Engine.SceneComponent")
				-- hmdComponent = hmdActor:AddComponentByClass(scene_component_c, true, temp_transform, false)
				-- --hmdComponent = uevr.api:add_component_by_class(hmdActor, scene_component_c)
				-- --scene_component_c = uevr.api:add_component_by_class(hmdActor, scene_component_c)	
			-- end
			-- if hmdComponent == nil then
				-- print("Failed to add HMD component\n")
			-- else
				-- hmdState = UEVR_UObjectHook.get_or_add_motion_controller_state(hmdComponent)	
				-- if hmdState ~= nil then
					-- hmdState:set_hand(2) -- HMD
					-- hmdState:set_permanent(true)
				-- else 
					-- print("Failed to add hmdComponent to motion controller\n")
				-- end
				-- --hmdActor:FinishAddComponent(hmdComponent, false, temp_transform)
			-- end

		-- end
	-- end
	-- if hmdActor ~= nil and hmdComponent ~= nil and hmdState ~= nil then
		-- print("HMD Component created\n")
		-- return true
	-- else
		-- print("HMD Component creation failed\n")
	-- end
	-- return false
-- end

-- function destroyHMDComponent()
	-- print("Destroying HMD Component\n")
	-- if hmdComponent ~= nil and UEVR_UObjectHook.exists(hmdComponent) then
		-- print("Disconnecting component from VR HMD\n")
		-- pcall(function()
			-- UEVR_UObjectHook.remove_motion_controller_state(hmdComponent)
			-- hmdState = nil
			-- print("Motion Control state disconnected from HMD\n")	
		-- end)	
		-- print("Destroying hmdComponent\n")
		-- pcall(function()
			-- if hmdComponent.K2_DestroyComponent ~= nil then
				-- local scene_component_c = uevrUtils.find_required_object("Class /Script/Engine.SceneComponent")
				-- hmdComponent:K2_DestroyComponent(scene_component_c)
				-- hmdComponent = nil
				-- print("hmdComponent destroyed\n")
			-- else
				-- print("Could not destroy hmdComponent.\n")
			-- end
		-- end)	
	-- end
	-- print("Destroying hmdActor\n")
	-- if hmdActor ~= nil and UEVR_UObjectHook.exists(hmdActor) then
		-- pcall(function()
			-- if hmdActor.K2_DestroyActor ~= nil then
				-- hmdActor:K2_DestroyActor()
			-- end
			-- hmdActor = nil
		-- end)	
	-- end
	-- if hmdState == nil and hmdComponent == nil and hmdActor == nil then
		-- print("HMD component destroyed\n")
	-- else
		-- print("HMD component was not properly destroyed ",hmdState,hmdComponent,hmdActor,"\n")
	-- end
	-- hmdState = nil
	-- hmdComponent = nil
	-- hmdActor = nil
-- end






-- local hmdActor = nil
-- local leftActor = nil
-- local rightActor = nil
--local leftComponent = nil
-- local function destroyActorComponentsByClass(actor, compClass)
	-- print("Destroying controller components\n")
	-- if actor ~= nil and actor.K2_GetComponentsByClass ~= nil then
		-- local components = actor:K2_GetComponentsByClass(compClass)
		-- print("Components=",components,"\n")
		-- if components ~= nil then
			-- for index, component in pairs(components) do
				-- if component ~= nil then
					-- print("Destroying controller component",component:get_full_name(),"\n")
					-- pcall(function()
						-- if actor.K2_DestroyComponent ~= nil then
							-- actor:K2_DestroyComponent(component)
							-- print("Controller component destroyed\n")
						-- end
					-- end)	
				-- end
			-- end
		-- end 
	-- end
-- end

-- local function destroyActor(actor)
	-- print("Destroying controller actor",actor,"\n")
	-- if actor ~= nil and UEVR_UObjectHook.exists(actor) then
		-- destroyActorComponentsByClass(actor, motion_controller_component_c)
		-- --destroyActorComponentsByClass(actor, static_mesh_component_c)
		-- pcall(function()
			-- if actor.K2_DestroyActor ~= nil then
				-- actor:K2_DestroyActor()
			-- end
			-- actor = nil
			-- print("Controller actor destroyed",actor,"\n")
		-- end)	
		-- if actor ~= nil then print("Controller actor was not destroyed in an expected way\n") end
	-- end
	-- return nil
-- end


-- function M.attachComponentToController()
	-- --print(rightMotionControllerComponent)
	-- local pos = pawn:K2_GetActorLocation()				
	-- --if hmdComponent == nil then
		-- local static_mesh_component_c = uevr.api:find_uobject("Class /Script/Engine.StaticMeshComponent")
		-- local static_mesh = uevr.api:find_uobject("StaticMesh /Engine/EngineMeshes/Sphere.Sphere")

		-- hmdComponent = rightActor:AddComponentByClass(static_mesh_component_c, true, uevrUtils.get_transform(nil, nil, {X=0.1, Y=0.1, Z=0.1}), false)
		-- hmdComponent:SetCollisionEnabled(0)
		-- hmdComponent:SetStaticMesh(static_mesh)
		
		-- --local scene_component_c = find_required_object("Class /Script/Engine.SceneComponent")
		-- --hmdComponent = rightActor:AddComponentByClass(scene_component_c, true, temp_transform, false)
-- --debugModule.dumpObject(hmdComponent)
		
		-- -- hmdComponent = Statics:SpawnObject(static_mesh_component_c, rightMotionControllerComponent)
		-- -- hmdComponent:K2_SetWorldTransform(temp_transform, false, reusable_hit_result, false)
		-- -- hmdComponent:SetCollisionEnabled(0)
		-- -- hmdComponent:SetStaticMesh(static_mesh)
		-- -- hmdComponent.LDMaxDrawDistance=1500.0
		-- -- hmdComponent.CachedMaxDrawDistance=1500.0
		-- --hmdComponent.CreationMethod=2
		
		-- hmdComponent:K2_AttachTo(rightMotionControllerComponent, uevrUtils.fname_from_string(""), 1, false)

-- -- debugModule.dumpObject(hmdComponent)
	-- --end

-- end


--function M.createLeftActor(pawn)
	-- if leftActor ~= nil then 
		-- destroyHMDActor()
	-- end
	-- local hmdComponent = nil
	-- local hmdState = nil
	-- if pawn ~= nil then
		-- print("Create HMD actor called\n")
		-- local pos = pawn:K2_GetActorLocation()
		-- if leftActor == nil then
			-- leftActor = spawn_actor( pos, 1, nil)
		-- end
		-- if leftActor == nil then
			-- print("Failed to spawn HMD actor\n")
		-- else
			-- temp_transform.Translation = pos
			-- temp_transform.Rotation.W = 1.0
			-- temp_transform.Scale3D = Vector3f.new(0.1, 0.1, 0.1)
			    
				-- -- left_hand_component = api:add_component_by_class(left_hand_actor, motion_controller_component_c)
				-- -- left_hand_component.MotionSource = kismet_string_library:Conv_StringToName("Left")
				-- -- if left_hand_component.Hand ~= nil then
					-- -- left_hand_component.Hand = 0
					-- -- right_hand_component.Hand = 1
				-- -- end
				
			-- if hmdComponent == nil then
				-- local static_mesh_component_c = uevr.api:find_uobject("Class /Script/Engine.StaticMeshComponent")
				-- local static_mesh = uevr.api:find_uobject("StaticMesh /Engine/EngineMeshes/Sphere.Sphere")

				-- -- hmdComponent = leftActor:AddComponentByClass(static_mesh_component_c, true, temp_transform, false)
				-- -- hmdComponent:SetCollisionEnabled(0)
				-- -- hmdComponent:SetStaticMesh(static_mesh, true)
				-- -- --local scene_component_c = find_required_object("Class /Script/Engine.SceneComponent")
				-- -- --hmdComponent = leftActor:AddComponentByClass(scene_component_c, true, temp_transform, false)
-- -- debugModule.dumpObject(hmdComponent)
				
				-- hmdComponent = Statics:SpawnObject(static_mesh_component_c, leftActor)
				-- hmdComponent:K2_SetWorldTransform(temp_transform, false, reusable_hit_result, false)
				-- hmdComponent:SetCollisionEnabled(0)
				-- hmdComponent:SetStaticMesh(static_mesh)
				-- hmdComponent.LDMaxDrawDistance=1500.0
				-- hmdComponent.CachedMaxDrawDistance=1500.0
				-- hmdComponent.CreationMethod=2
				-- leftComponent = hmdComponent

			-- end
			-- if hmdComponent == nil then
				-- print("Failed to add HMD component\n")
			-- else
				-- hmdState = UEVR_UObjectHook.get_or_add_motion_controller_state(hmdComponent)	
				-- if hmdState ~= nil then
					-- hmdState:set_hand(0) -- left
					-- hmdState:set_permanent(true)
				-- else 
					-- print("Failed to add leftActor to motion controller\n")
				-- end
				-- --leftActor:FinishAddComponent(hmdComponent, false, temp_transform)
			-- end

		-- end
	-- end
	-- if leftActor ~= nil and hmdComponent ~= nil and hmdState ~= nil then
		-- print("HMD Component created\n")
		-- print(hmdComponent:get_full_name(),"\n")
		-- return true
	-- else
		-- print("HMD Component creation failed\n")
	-- end
	-- return false
-- end



-- local hmd_actor = nil -- The purpose of the HMD actor is to accurately track the HMD's world transform
-- local left_hand_actor = nil
-- local right_hand_actor = nil
-- local left_hand_component = nil
-- local right_hand_component = nil
-- local hmd_component = nil

-- local function spawn_actor(world_context, actor_class, location, collision_method, owner)
    -- temp_transform.Translation = location
    -- temp_transform.Rotation.W = 1.0
    -- temp_transform.Scale3D = Vector3f.new(1.0, 1.0, 1.0)

    -- local actor = Statics:BeginDeferredActorSpawnFromClass(world_context, actor_class, temp_transform, collision_method, owner)

    -- if actor == nil then
        -- print("Failed to spawn actor")
        -- return nil
    -- end

    -- Statics:FinishSpawningActor(actor, temp_transform)
    -- print("Spawned actor")

    -- return actor
-- end

-- local function reset_hand_actors()
    -- -- We are using pcall on this because for some reason the actors are not always valid
    -- -- even if exists returns true
    -- if left_hand_actor ~= nil and UEVR_UObjectHook.exists(left_hand_actor) then
        -- pcall(function()
            -- if left_hand_actor.K2_DestroyActor ~= nil then
                -- left_hand_actor:K2_DestroyActor()
            -- end
        -- end)
    -- end

    -- if right_hand_actor ~= nil and UEVR_UObjectHook.exists(right_hand_actor) then
        -- pcall(function()
            -- if right_hand_actor.K2_DestroyActor ~= nil then
                -- right_hand_actor:K2_DestroyActor()
            -- end
        -- end)
    -- end

    -- if hmd_actor ~= nil and UEVR_UObjectHook.exists(hmd_actor) then
        -- pcall(function()
            -- if hmd_actor.K2_DestroyActor ~= nil then
                -- hmd_actor:K2_DestroyActor()
            -- end
        -- end)
    -- end

    -- left_hand_actor = nil
    -- right_hand_actor = nil
    -- hmd_actor = nil
    -- right_hand_component = nil
    -- left_hand_component = nil
-- end

-- function M.onLevelChange()
    -- left_hand_actor = nil
    -- right_hand_actor = nil
    -- left_hand_component = nil
    -- right_hand_component = nil
	-- --M.spawn_hand_actors()
	-- M.createController(0)
	-- M.createController(1)
-- end

-- function M.spawn_hand_actors()
    -- local game_engine = UEVR_UObjectHook.get_first_object_by_class(game_engine_class)

    -- local viewport = game_engine.GameViewport
    -- if viewport == nil then
        -- print("Viewport is nil")
        -- return
    -- end

    -- local world = viewport.World
    -- if world == nil then
        -- print("World is nil")
        -- return
    -- end

    -- reset_hand_actors()

    -- local pawn = uevr.api:get_local_pawn(0)

    -- if pawn == nil then
        -- --print("Pawn is nil")
        -- return
    -- end

    -- local pos = pawn:K2_GetActorLocation()

    -- left_hand_actor = spawn_actor(world, actor_c, pos, 1, nil)

    -- if left_hand_actor == nil then
        -- print("Failed to spawn left hand actor")
        -- return
    -- end

    -- right_hand_actor = spawn_actor(world, actor_c, pos, 1, nil)

    -- if right_hand_actor == nil then
        -- print("Failed to spawn right hand actor")
        -- return
    -- end

    -- hmd_actor = spawn_actor(world, actor_c, pos, 1, nil)

    -- if hmd_actor == nil then
        -- print("Failed to spawn hmd actor")
        -- return
    -- end

    -- print("Spawned hand actors")

    -- -- Add scene components to the hand actors
    -- left_hand_component = uevr.api:add_component_by_class(left_hand_actor, motion_controller_component_c)
    -- right_hand_component = uevr.api:add_component_by_class(right_hand_actor, motion_controller_component_c)
    -- hmd_component = uevr.api:add_component_by_class(hmd_actor, scene_component_c)

    -- if left_hand_component == nil then
        -- print("Failed to add left hand scene component")
        -- return
    -- end

    -- if right_hand_component == nil then
        -- print("Failed to add right hand scene component")
        -- return
    -- end

    -- if hmd_component == nil then
        -- print("Failed to add hmd scene component")
        -- return
    -- end

    -- left_hand_component.MotionSource = kismet_string_library:Conv_StringToName("Left")
    -- right_hand_component.MotionSource = kismet_string_library:Conv_StringToName("Right")

    -- -- Not all engine versions have the Hand property
    -- if left_hand_component.Hand ~= nil then
        -- left_hand_component.Hand = 0
        -- right_hand_component.Hand = 1
    -- end

    -- print("Added scene components")

    -- -- -- The HMD is the only one we need to add manually as UObjectHook doesn't support motion controller components as the HMD
    -- -- local hmdstate = UEVR_UObjectHook.get_or_add_motion_controller_state(hmd_component)

    -- -- if hmdstate then
        -- -- hmdstate:set_hand(2) -- HMD
        -- -- hmdstate:set_permanent(true)
    -- -- end

    -- print(string.format("%x", left_hand_actor:get_address()) .. " " .. string.format("%x", right_hand_actor:get_address()) .. " " .. string.format("%x", hmd_actor:get_address()))
-- end
