-- Decoupled Yaw code courtesy of Pande4360

local uevrUtils = require("libs/uevr_utils")
local mathLib = require("libs/core/math_lib")
local controllers = require("libs/controllers")
local bodyYaw = require("libs/body_yaw")
local pawnModule = require("libs/pawn")
local inputEnums = require("libs/enums/input")
local paramModule = require("libs/core/params")
local attachments = require("libs/attachments")

local M = {}

M.AimMethod = inputEnums.AimMethod
M.PawnPositionMode = inputEnums.PawnPositionMode
M.PawnRotationMode = inputEnums.PawnRotationMode
--M.MovementMethod = inputEnums.MovementMethod

local parametersFileName = "input_parameters"
local parameters = {
    isDisabledOverride = false,
    aimMethod = M.AimMethod.UEVR,
    fixSpatialAudio = true,
    rootOffset = {X=0,Y=0,Z=0},
    useSnapTurn = false,
    snapAngle = 30,
    smoothTurnSpeed = 50,
    pawnPositionMode = M.PawnPositionMode.FOLLOWS,
    pawnRotationMode = M.PawnRotationMode.RIGHT_CONTROLLER,
	pawnRotationLockedSmoothTime = 0.36,
    pawnPositionSweepMovement = true,
    pawnPositionAnimationScale = 0.2,
    headOffset = {X=0,Y=0,Z=0},
    adjustForAnimation = false,
    adjustForEyeOffset = false,
    eyeOffset = 0,
	headBoneName = "",
	rootBoneName = "",
	aimCamera = "",
	useControllerRotationPitch = 1,
	useControllerRotationYaw = 1,
	useControllerRotationRoll = 1,
	orientRotationToMovement = 1,
	useControllerDesiredRotation = 1,
--	movementMethod = M.MovementMethod.HEAD,
	optimizeBodyRotationCalculations = true,
	optimizeBodyLocationCalculations = true,
	pawnRotationModeDisableRotation = false,
	usePawnControlRotation = 1
}

local isDisabled = false

local status = {}
local rootComponent = nil
local decoupledYaw = nil
local bodyRotationOffset = 0
local bodyMesh = nil
local pawnRotationModeOverride = nil
local aimCameraOverride = nil
local lastBodyYawUpdateTime = nil

--Normally body yaw only needs to be calculated for one eye only in on_early_calculate_stereo_view_offset
--but in some cases, like Avowed when climbing, the body yaw needs to be calculated for both eyes or else the eyes desync
--This flag enables optimizations to skip the second calculation when not needed
--Also if IK hands are jittery when snap turning or moving your head quickly, try setting this to false
local optimizeBodyYawCalculations = true

local rxState = 0
local snapTurnDeadZone = 8000

local aimRotationOffset = uevrUtils.rotator(0,0,0)
local weaponRotation = nil -- externally set for WEAPON aim method

local currentHeadRotator = uevrUtils.rotator(0,0,0)

local inputConfigDev = nil
local inputConfig = nil

--this module is designed to work with these UEVR settings 
uevrUtils.set_decoupled_pitch(true)
uevrUtils.set_decoupled_pitch_adjust_ui(true)

local currentLogLevel = LogLevel.Error
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
	if logLevel == nil then logLevel = LogLevel.Debug end
	if logLevel <= currentLogLevel then
		uevrUtils.print("[input] " .. text, logLevel)
	end
end

local paramManager = paramModule.new(parametersFileName, parameters, true)
paramManager:load(true)

local function getParameter(key)
    return paramManager:getFromActiveProfile(key)
end

local function setParameter(key, value, persist)
    return paramManager:setInActiveProfile(key, value, persist)
end

local function getAimOffsetAdjustedRotation(rotation)
	if (aimRotationOffset.Pitch == nil or aimRotationOffset.Pitch == 0) and (aimRotationOffset.Yaw == nil or aimRotationOffset.Yaw == 0) and (aimRotationOffset.Roll == nil or aimRotationOffset.Roll == 0) then
		return rotation
	end
	return kismet_math_library:ComposeRotators(aimRotationOffset, rotation)

	-- --Quat_MakeFromEuler expects Roll Pitch Yaw
	-- local quat1 = kismet_math_library:Quat_MakeFromEuler(uevrUtils.vector(aimRotationOffset.Roll, aimRotationOffset.Pitch, aimRotationOffset.Yaw))
	-- local quat2 = kismet_math_library:Quat_MakeFromEuler(uevrUtils.vector(rotation.Roll, rotation.Pitch, rotation.Yaw))
	-- local quat3 = kismet_math_library:Multiply_QuatQuat(quat2, quat1)
	-- local final = kismet_math_library:Quat_Rotator(quat3)
	-- return final
end
getAimOffsetAdjustedRotation = uevrUtils.profiler:wrap("getAimOffsetAdjustedRotation", getAimOffsetAdjustedRotation)


local cameraComponent = {
	initialized = false,
	component = nil,
	originalState = nil,
	currentControllerID = nil,
	originalParent = nil,
	init = function(self)
        -- local aimCamera = getParameter("aimCamera")
        -- local aimMethod = getParameter("aimMethod")
        -- if (aimMethod == M.AimMethod.LEFT_CONTROLLER or aimMethod == M.AimMethod.RIGHT_CONTROLLER or aimMethod == M.AimMethod.HEAD) and aimCamera ~= nil and aimCamera ~= "" and aimCamera ~= "None" then
		-- 	print("Initializing aim camera component from descriptor:", aimCamera)
		-- 	self.component = uevrUtils.getObjectFromDescriptor(aimCamera)
		-- 	if self.component ~= nil then
		-- 		self.originalState = self.component.bUsePawnControlRotation
		-- 		self.initialized = true
		-- 	end
		-- else
		-- 	self.initialized = true
        -- end
    end,
	get = function(self)
		-- if self.initialized == false then
		-- 	self:init()
		-- end
		-- if uevrUtils.getValid(self.component) ~= nil then
		-- 	return self.component
		-- end
		-- return nil
	end,
	reattachToParent = function(self)
		-- print("Reattaching aim camera to original parent if needed",self.component,self.originalParent)
		-- if uevrUtils.getValid(self.component) ~= nil then
		-- 	M.print("Detaching aim camera from controller")
		-- 	self.component:DetachFromParent(false,false)
		-- 	if uevrUtils.getValid(self.originalParent) ~= nil then
		-- 		M.print("Reattaching aim camera to original parent " .. self.originalParent:get_full_name())
		-- 		self.component:K2_AttachTo(self.originalParent, uevrUtils.fname_from_string(""), 0, false)
		-- 		self.originalParent = nil
		-- 	end
		-- end
	end,
	updateAim = function(self)
		local aimCamera = getParameter("aimCamera")
        local aimMethod = getParameter("aimMethod")
		local validController = aimMethod == M.AimMethod.LEFT_CONTROLLER or aimMethod == M.AimMethod.RIGHT_CONTROLLER or aimMethod == M.AimMethod.HEAD
		local validWeapon = aimMethod == M.AimMethod.LEFT_WEAPON or aimMethod == M.AimMethod.RIGHT_WEAPON
		local validAimCamera = aimCamera ~= nil and aimCamera ~= "" and aimCamera ~= "None"
		if (validController or validWeapon) and validAimCamera then
			if self.component == nil then
				self.component = uevrUtils.getObjectFromDescriptor(aimCamera)
				if self.component ~= nil then
					self.originalState = self.component.bUsePawnControlRotation
				end
			end
		else
			if self.component ~= nil then
				self:reset()
			end
		end

		if uevrUtils.getValid(self.component) ~= nil and self.component.K2_SetWorldRotation ~= nil then
			if validController then
				local controllerID = aimMethod == M.AimMethod.LEFT_CONTROLLER and 0 or (aimMethod == M.AimMethod.RIGHT_CONTROLLER and 1 or (aimMethod == M.AimMethod.HEAD and 2 or 1))
				self.currentControllerID = controllerID

				local rotation = controllers.getControllerRotation(controllerID)
				local location = controllers.getControllerLocation(controllerID)
				if rotation ~= nil and location ~= nil then
					if aimMethod == M.AimMethod.LEFT_CONTROLLER or aimMethod == M.AimMethod.RIGHT_CONTROLLER then
						rotation = getAimOffsetAdjustedRotation(rotation)
					end
					--pcall( function() --gun for hire crashes here
						self.component:K2_SetWorldRotation(rotation, false, reusable_hit_result, false)
						self.component:K2_SetWorldLocation(location, false, reusable_hit_result, false)
					--end)
				end
			elseif validWeapon then
				--this if check does not appear to be needed
				--although it seems like if there is no weapon then location and rotation should be taken from the controller
				--so maybe its here because that was the original intention
				local attachment = attachments.getCurrentGrippedAttachment(aimMethod == M.AimMethod.LEFT_WEAPON and Handed.Left or Handed.Right)
				if attachment ~= nil then
					local controllerID = aimMethod == M.AimMethod.LEFT_WEAPON and Handed.Left or Handed.Right
					self.currentControllerID = controllerID

					local location, rotation = attachments.getActiveAttachmentTransforms(controllerID)
					rotation = getAimOffsetAdjustedRotation(rotation)

					if rotation ~= nil and location ~= nil then
						--pcall( function() --gun for hire crashes here
							self.component:K2_SetWorldRotation(rotation, false, reusable_hit_result, false)
							self.component:K2_SetWorldLocation(location, false, reusable_hit_result, false)
						--end)
					end
				end
			end
			return true
		end

		return false
	end,
	setUsePawnControlRotation = function(self, val)
		if uevrUtils.getValid(self.component) ~= nil and self.component.bUsePawnControlRotation ~= nil then
			--print(1, val, self.component:get_full_name())
			if val == nil then
				val = self.originalState
			end
			self.component.bUsePawnControlRotation = val
		end
	end,
	setRotation = function(self, rotation)
		-- if self.initialized == false then
		-- 	self:init()
		-- end
		-- if uevrUtils.getValid(self.component) ~= nil then
		-- 	--self.component.bUsePawnControlRotation = false
		-- 	self.component.RelativeRotation = rotation
		-- end
	end,
	reset = function(self)
		--print("Camera Component Reset called")
		if uevrUtils.getValid(self.component) ~= nil  then
			if self.component.AttachParent ~= nil then
				--print("Resetting camera component world transform to parent transform")
				local rotation = self.component.AttachParent:K2_GetComponentRotation()
				local location = self.component.AttachParent:K2_GetComponentLocation()
				self.component:K2_SetWorldRotation(rotation,false,reusable_hit_result,false)
				self.component:K2_SetWorldLocation(location,false,reusable_hit_result,false)
			end
			if self.originalState ~= nil and self.component.bUsePawnControlRotation ~= nil then
				self.component.bUsePawnControlRotation = self.originalState
			end
		end
		self.component = nil
		self.originalState = nil
		self.currentControllerID = nil
		self.originalParent = nil
	end
}
cameraComponent.updateAim = uevrUtils.profiler:wrap("cameraComponent.updateAim", cameraComponent.updateAim)

--[[
--this one moves the camera to the controller which seems cleaner but causes issues
--with sanp turn and gestures when pawns suddenly change
local cameraComponent = {
	initialized = false,
	component = nil,
	originalState = nil,
	currentControllerID = nil,
	originalParent = nil,
	init = function(self)
        local aimCamera = getParameter("aimCamera")
        if getParameter("aimMethod") ~= M.AimMethod.UEVR and aimCamera ~= nil and aimCamera ~= "" and aimCamera ~= "None" then
			print("Initializing aim camera component from descriptor:", aimCamera)
			self.component = uevrUtils.getObjectFromDescriptor(aimCamera)
			if self.component ~= nil then
				self.originalState = self.component.bUsePawnControlRotation
				self.initialized = true
			end
		else
			self.initialized = true
        end
    end,
	get = function(self)
		if self.initialized == false then
			self:init()
		end
		if uevrUtils.getValid(self.component) ~= nil then
			return self.component
		end
		return nil
	end,
	reattachToParent = function(self)
		print("Reattaching aim camera to original parent if needed",self.component,self.originalParent)
		if uevrUtils.getValid(self.component) ~= nil then
			M.print("Detaching aim camera from controller")
			self.component:DetachFromParent(false,false)
			if uevrUtils.getValid(self.originalParent) ~= nil then
				M.print("Reattaching aim camera to original parent " .. self.originalParent:get_full_name())
				self.component:K2_AttachTo(self.originalParent, uevrUtils.fname_from_string(""), 0, false)
				self.originalParent = nil
			end
		end
	end,
	updateAim = function(self, aimMethod)
		if self.initialized == false then
			self:init()
		end
		if self.component ~= nil then
			local controllerID = aimMethod == M.AimMethod.LEFT_CONTROLLER and 0 or (aimMethod == M.AimMethod.RIGHT_CONTROLLER and 1 or (aimMethod == M.AimMethod.HEAD and 2 or -1))
			if controllerID == -1 then
				--not using a controller for aim, reattach to parent if needed
				self:reset()
				return false
			end

			if self.originalParent == nil then
				self.originalParent = self.component.AttachParent
			end
			if self.currentControllerID ~= controllerID then
				M.print("Attaching aim camera to controller " .. controllerID)
				self.component:DetachFromParent(false,false)
				controllers.attachComponentToController(controllerID, self.component)
				uevrUtils.set_component_relative_transform(self.component, {X=0,Y=0,Z=0}, {Pitch=0,Yaw=0,Roll=0})
				self.currentControllerID = controllerID
			end
			return true
		end

		return false
	end,
	setUsePawnControlRotation = function(self, val)
		if self.component ~= nil then
			--print(1, val, self.component:get_full_name())
			if val == nil then
				val = self.originalState
			end
			self.component.bUsePawnControlRotation = val
		end
	end,
	setRotation = function(self, rotation)
		if self.initialized == false then
			self:init()
		end
		if uevrUtils.getValid(self.component) ~= nil then
			--self.component.bUsePawnControlRotation = false
			self.component.RelativeRotation = rotation
		end
	end,
	reset = function(self)
		print("Camera Component Reset called")
		if self.initialized == true then
			self:reattachToParent()
			if uevrUtils.getValid(self.component) ~= nil and self.component.bUsePawnControlRotation and self.originalState ~= nil then
				self.component.bUsePawnControlRotation = self.originalState
			end
			print("Camera Component Was Reset")
		end
		self.initialized = false
		self.component = nil
		self.originalState = nil
		self.currentControllerID = nil
		self.originalParent = nil
	end
}
]]--

local pawnSettings = nil
local function resetPawnSettings()
	cameraComponent:reset()
	if uevrUtils.getValid(pawn) ~= nil and pawnSettings ~= nil and pawn.bUseControllerRotationPitch ~= nil then
		--restore pawn settings
		--print("Restoring pawn settings")
		pawn.bUseControllerRotationPitch = pawnSettings.bUseControllerRotationPitch
		pawn.bUseControllerRotationYaw = pawnSettings.bUseControllerRotationYaw
		pawn.bUseControllerRotationRoll = pawnSettings.bUseControllerRotationRoll
		if pawn.CharacterMovement ~= nil then
			pawn.CharacterMovement.bOrientRotationToMovement = pawnSettings.bOrientRotationToMovement
			pawn.CharacterMovement.bUseControllerDesiredRotation = pawnSettings.bUseControllerDesiredRotation
		end
		pawnSettings = nil
	end
end
resetPawnSettings = uevrUtils.profiler:wrap("resetPawnSettings", resetPawnSettings)

-- local function applyDecoupledYawToPlayerController()
-- 	if pawn ~= nil then
-- 		pawn.Controller:SetControlRotation(uevrUtils.rotator(0, decoupledYaw, 0))
-- 	end
-- end
-- applyDecoupledYawToPlayerController = uevrUtils.profiler:wrap("applyDecoupledYawToPlayerController", applyDecoupledYawToPlayerController)

local function updatePawnSettings()
	if pawn ~= nil then
		if pawnSettings == nil then
			pawnSettings = {}
			pawnSettings.bUseControllerRotationPitch = pawn.bUseControllerRotationPitch
			pawnSettings.bUseControllerRotationYaw = pawn.bUseControllerRotationYaw
			pawnSettings.bUseControllerRotationRoll = pawn.bUseControllerRotationRoll
			pawnSettings.bOrientRotationToMovement = pawn.CharacterMovement and pawn.CharacterMovement.bOrientRotationToMovement or false
			pawnSettings.bUseControllerDesiredRotation = pawn.CharacterMovement and pawn.CharacterMovement.bUseControllerDesiredRotation or false
		end

		local useControllerRotationPitch = getParameter("useControllerRotationPitch")
		if useControllerRotationPitch ~= nil and useControllerRotationPitch ~= ETriState.DEFAULT then
			pawn.bUseControllerRotationPitch = useControllerRotationPitch == ETriState.TRUE
		else
			pawn.bUseControllerRotationPitch = pawnSettings.bUseControllerRotationPitch
		end
		local useControllerRotationYaw = getParameter("useControllerRotationYaw")
		if useControllerRotationYaw ~= nil and useControllerRotationYaw ~= ETriState.DEFAULT then
			pawn.bUseControllerRotationYaw = useControllerRotationYaw == ETriState.TRUE
		else
			pawn.bUseControllerRotationYaw = pawnSettings.bUseControllerRotationYaw
		end
		local useControllerRotationRoll = getParameter("useControllerRotationRoll")
		if useControllerRotationRoll ~= nil and useControllerRotationRoll ~= ETriState.DEFAULT then
			pawn.bUseControllerRotationRoll = useControllerRotationRoll == ETriState.TRUE
		else
			pawn.bUseControllerRotationRoll = pawnSettings.bUseControllerRotationRoll
		end

		if pawn.CharacterMovement ~= nil then
			local orientRotationToMovement = getParameter("orientRotationToMovement")
			if orientRotationToMovement ~= nil and orientRotationToMovement ~= ETriState.DEFAULT then
				pawn.CharacterMovement.bOrientRotationToMovement = orientRotationToMovement == ETriState.TRUE
			else
				pawn.CharacterMovement.bOrientRotationToMovement = pawnSettings.bOrientRotationToMovement
			end
			local useControllerDesiredRotation = getParameter("useControllerDesiredRotation")
			if useControllerDesiredRotation ~= nil and useControllerDesiredRotation ~= ETriState.DEFAULT then
				pawn.CharacterMovement.bUseControllerDesiredRotation = useControllerDesiredRotation == ETriState.TRUE
			else
				pawn.CharacterMovement.bUseControllerDesiredRotation = pawnSettings.bUseControllerDesiredRotation
			end
		end

		local usePawnControlRotation = getParameter("usePawnControlRotation")
		if usePawnControlRotation ~= nil and usePawnControlRotation ~= ETriState.DEFAULT then
			cameraComponent:setUsePawnControlRotation(usePawnControlRotation == ETriState.TRUE)
		else
			cameraComponent:setUsePawnControlRotation(nil)
		end
	end
	--print("Pitch",pawn.bUseControllerRotationPitch,"Yaw",pawn.bUseControllerRotationYaw,"Roll",pawn.bUseControllerRotationRoll)
end
updatePawnSettings = uevrUtils.profiler:wrap("updatePawnSettings", updatePawnSettings)

--Thses shouldn't need to be done on the tick but if they are, move them to the function above
-- setInterval(1000, function ()
-- 	local movementMethod = getParameter("movementMethod")
-- 	if movementMethod ~= nil and movementMethod ~= 1 then
-- 		uevrUtils.setUEVRParam_int("VR_MovementOrientation", movementMethod - 1)
-- 	end

-- 	--updatePawnSettings()
-- end)

local zeroRotator = uevrUtils.rotator(0,0,0)
local function updateAim()

	if aimCameraOverride ~= true and cameraComponent:updateAim() == true then
		-- if (aimRotationOffset.Pitch == nil or aimRotationOffset.Pitch == 0) and (aimRotationOffset.Yaw == nil or aimRotationOffset.Yaw == 0) and (aimRotationOffset.Roll == nil or aimRotationOffset.Roll == 0) then
		-- 	cameraComponent:setRotation(zeroRotator)
		-- else
		-- 	cameraComponent:setRotation(aimRotationOffset)
		-- end
		--cameraComponent:setRotation(getAimOffsetAdjustedRotation(uevrUtils.rotator(0,0,0)))
		if pawn ~= nil and decoupledYaw ~= nil and pawn.Controller ~= nil then
			pawn.Controller:SetControlRotation(uevrUtils.rotator(0, decoupledYaw+bodyRotationOffset, 0))
		end
	else
		--if camera component isnt handling it then use the old way
		--This way wont work for most games because yaw is ignored in most games but it does work for Hello Neighbor
		local aimMethod = getParameter("aimMethod")
		if aimMethod ~= M.AimMethod.UEVR then
			local rotation = nil
			if aimMethod == M.AimMethod.RIGHT_WEAPON then
				rotation = (weaponRotation ~= nil and weaponRotation.right ~= nil) and weaponRotation.right or controllers.getControllerRotation(Handed.Right)
			elseif aimMethod == M.AimMethod.LEFT_WEAPON then
				rotation = (weaponRotation ~= nil and weaponRotation.left ~= nil) and weaponRotation.left or controllers.getControllerRotation(Handed.Left)
			else
				local controllerID = aimMethod == M.AimMethod.LEFT_CONTROLLER and 0 or (aimMethod == M.AimMethod.HEAD and 2 or 1)
				rotation = controllers.getControllerRotation(controllerID)
				--only use aim offset adjust if aimMethod is left or right controller
				if aimMethod == M.AimMethod.LEFT_CONTROLLER or aimMethod == M.AimMethod.RIGHT_CONTROLLER then
					rotation = getAimOffsetAdjustedRotation(rotation) --things like gunstock may adjust the rotation
				end
			end
			if uevrUtils.getValid(pawn) ~= nil and pawn.Controller ~= nil and pawn.Controller.SetControlRotation ~= nil and rotation ~= nil then
				pawn.Controller:SetControlRotation(rotation) --because the previous booleans were set, aiming with the hand or head doesnt affect the rotation of the pawn
			end
		end
	end

	-- --if camera component isnt handling it then use the old way
	-- local rotation = nil
	-- local aimMethod = getParameter("aimMethod")
	-- if aimMethod == M.AimMethod.RIGHT_WEAPON then
	-- 	rotation = (weaponRotation ~= nil and weaponRotation.right ~= nil) and weaponRotation.right or controllers.getControllerRotation(Handed.Right)
	-- elseif aimMethod == M.AimMethod.LEFT_WEAPON then
	-- 	rotation = (weaponRotation ~= nil and weaponRotation.left ~= nil) and weaponRotation.left or controllers.getControllerRotation(Handed.Left)
	-- else
	-- 	local controllerID = aimMethod == M.AimMethod.LEFT_CONTROLLER and 0 or (aimMethod == M.AimMethod.HEAD and 2 or 1)
	-- 	rotation = controllers.getControllerRotation(controllerID)
	-- 	--only use aim offset adjust if aimMethod is left or right controller
	-- 	if aimMethod == M.AimMethod.LEFT_CONTROLLER or aimMethod == M.AimMethod.RIGHT_CONTROLLER then
	-- 		rotation = getAimOffsetAdjustedRotation(rotation) --things like gunstock may adjust the rotation
	-- 	end
	-- end

	-- if uevrUtils.getValid(pawn) ~= nil and pawn.Controller ~= nil and pawn.Controller.SetControlRotation ~= nil and rotation ~= nil then
	-- 	--disassociates the rotation of the pawn from the rotation set by pawn.Controller:SetControlRotation()
	-- 	pawn.bUseControllerRotationPitch = false
	-- 	pawn.bUseControllerRotationYaw = false
	-- 	pawn.bUseControllerRotationRoll = false

	-- 	if pawn.CharacterMovement ~= nil then
	-- 		pawn.CharacterMovement.bOrientRotationToMovement = false
	-- 		pawn.CharacterMovement.bUseControllerDesiredRotation = false
	-- 	end

	-- 	--Pitch is actually the only part of the rotation that is used here in games like Robocop
	-- 	--Yaw is controlled by Movement Orientation for those games (may not be true now with cameraComponent:setUsePawnControlRotation(true))
	-- 	-- Use ClientSetRotation(rotation, false) in multiplayer games?
	-- 	pawn.Controller:SetControlRotation(rotation) --because the previous booleans were set, aiming with the hand or head doesnt affect the rotation of the pawn

	-- 	--cameraComponent:setUsePawnControlRotation(true)
	-- end


	-- local rotation = nil
	-- local aimMethod = getParameter("aimMethod")
	-- if aimMethod == M.AimMethod.RIGHT_WEAPON then
	-- 	rotation = (weaponRotation ~= nil and weaponRotation.right ~= nil) and weaponRotation.right or controllers.getControllerRotation(Handed.Right)
	-- elseif aimMethod == M.AimMethod.LEFT_WEAPON then
	-- 	rotation = (weaponRotation ~= nil and weaponRotation.left ~= nil) and weaponRotation.left or controllers.getControllerRotation(Handed.Left)
	-- else
	-- 	local controllerID = aimMethod == M.AimMethod.LEFT_CONTROLLER and 0 or (aimMethod == M.AimMethod.HEAD and 2 or 1)
	-- 	rotation = controllers.getControllerRotation(controllerID)
	-- 	--only use aim offset adjust if aimMethod is left or right controller
	-- 	if aimMethod == M.AimMethod.LEFT_CONTROLLER or aimMethod == M.AimMethod.RIGHT_CONTROLLER then
	-- 		rotation = getAimOffsetAdjustedRotation(rotation) --things like gunstock may adjust the rotation
	-- 	end
	-- end

	-- if uevrUtils.getValid(pawn) ~= nil and pawn.Controller ~= nil and pawn.Controller.SetControlRotation ~= nil and rotation ~= nil then
	-- 	--disassociates the rotation of the pawn from the rotation set by pawn.Controller:SetControlRotation()
	-- 	pawn.bUseControllerRotationPitch = true
	-- 	pawn.bUseControllerRotationYaw = false
	-- 	pawn.bUseControllerRotationRoll = true

	-- 	-- if pawn.CharacterMovement ~= nil then
	-- 	-- 	pawn.CharacterMovement.bOrientRotationToMovement = false
	-- 	-- 	pawn.CharacterMovement.bUseControllerDesiredRotation = false
	-- 	-- end

	-- 	--Pitch is actually the only part of the rotation that is used here in games like Robocop
	-- 	--Yaw is controlled by Movement Orientation for those games (may not be true now with cameraComponent:setUsePawnControlRotation(true))
	-- 	-- Use ClientSetRotation(rotation, false) in multiplayer games?
	-- 	print("AIM ROTATION", rotation.Yaw)
	-- 	print("BODY ROTATION", bodyRotationOffset)
	-- 	print("DECOUPLED YAW", decoupledYaw)

	-- 	rotation.Pitch = 0
	-- 	rotation.Yaw = decoupledYaw --setting this to 0 does everything except handle snap turn, commenting it causes right controller to dictate direction
	-- 	rotation.Roll = 0
	-- 	pawn.Controller:SetControlRotation(rotation) --because the previous booleans were set, aiming with the hand or head doesnt affect the rotation of the pawn

	-- 	--cameraComponent:setUsePawnControlRotation(true)
	-- 	--cameraComponent:setRotation(rotation)
	-- end
end
updateAim = uevrUtils.profiler:wrap("updateAim", updateAim)

local function saveParameter(key, value, persist, noCallbacks)
	--print("Saving Input Parameter:", key, value, persist)
	setParameter(key, value, persist)
	if not (noCallbacks == true) then
		uevrUtils.executeUEVRCallbacks("on_input_config_param_change", key, value, persist)
	end
	if key == "aimMethod" and value ~= M.AimMethod.UEVR then
		controllers.createController(0)
		controllers.createController(1)
		controllers.createController(2)
	end
	if key == "aimCamera" then
		cameraComponent:reset()
	end
	if key == "useMeshHeightForHeadOffset" then
		status["meshZOffset"] = nil
	end
end

local createConfigMonitor = doOnce(function()
	uevrUtils.registerUEVRCallback("on_input_config_param_change", function(key, value, persist)
		saveParameter(key, value, persist, true)
	end)
end, Once.EVER)

function M.init(isDeveloperMode, logLevel)
    if logLevel ~= nil then
        M.setLogLevel(logLevel)
    end
    if isDeveloperMode == nil and uevrUtils.getDeveloperMode() ~= nil then
        isDeveloperMode = uevrUtils.getDeveloperMode()
    end

    if isDeveloperMode then
        inputConfigDev = require("libs/config/input_config_dev")
        inputConfigDev.init(paramManager)
		createConfigMonitor()
    else
    end
end

function M.getConfigurationWidgets(options)
	if inputConfig == nil then
		inputConfig = require("libs/config/input_config")
	end
	createConfigMonitor()
	inputConfig.init(paramManager)
    return inputConfig.getConfigurationWidgets(options)
end

function M.showConfiguration(saveFileName, options)
	if inputConfig == nil then
		inputConfig = require("libs/config/ui_config")
	end
	createConfigMonitor()
	inputConfig.init(paramManager)
	inputConfig.showConfiguration(saveFileName, options)
end

function M.setCurrentProfile(profileID)
	paramManager:setActiveProfile(profileID)
	--if the profile changes, reset the camera component to ensure its using the correct settings
	resetPawnSettings()
end

function M.setCurrentProfileByLabel(profileLabel)
	local profileIDs, profileNames = paramManager:getProfiles()
	for i, name in ipairs(profileNames) do
		if name == profileLabel then
			M.setCurrentProfile(profileIDs[i])
			return
		end
	end
end

function M.setDisabled(val)
	--print("Input Disabled:", val)
	saveParameter("isDisabledOverride", val)
	if val then
		--this ensures the camera gets reset to the current pawn orientation when input is re-enabled
		decoupledYaw = nil
		bodyRotationOffset = 0
		lastBodyYawUpdateTime = nil
	end
end

function M.resetCapsuleComponent()
	decoupledYaw = nil
	bodyRotationOffset = 0
	lastBodyYawUpdateTime = nil
	if rootComponent ~= nil then
		rootComponent:K2_SetWorldRotation(uevrUtils.rotator(0,0,0),false,reusable_hit_result,false)
		pawn:K2_SetActorRotation(uevrUtils.rotator(0,0,0), false, reusable_hit_result, false)
	end
end

function M.isDisabled()
	return getParameter("isDisabledOverride") or isDisabled
end

local function executeIsDisabledCallback(...)
	local result, priority = uevrUtils.executeUEVRCallbacksWithPriorityBooleanResult("is_input_disabled", table.unpack({...}))
	return result
end

function M.registerIsDisabledCallback(func)
	uevrUtils.registerUEVRCallback("is_input_disabled", func)
end

local function doFixSpatialAudio()
	if getParameter("fixSpatialAudio") then
		local playerController = uevr.api:get_player_controller(0)
		local hmdController = controllers.getController(2)
		if playerController ~= nil and hmdController ~= nil then
			playerController:SetAudioListenerOverride(hmdController,uevrUtils.vector(0,0,0),uevrUtils.rotator(0,0,0))
		end
	else
		local playerController = uevr.api:get_player_controller(0)
		if playerController ~= nil then
			playerController:ClearAudioListenerOverride()
		end
	end
end



function M.setAimMethod(val)
	saveParameter("aimMethod", val)
end

function M.setUseSnapTurn(val)
	saveParameter("useSnapTurn", val)
end

function M.setSmoothTurnSpeed(val)
	saveParameter("smoothTurnSpeed", val)
end

function M.setSnapAngle(val)
	saveParameter("snapAngle", val)
end

function M.setPawnRotationMode(val)
	saveParameter("pawnRotationMode", val)
end

function M.getPawnRotationMode()
	return getParameter("pawnRotationMode")
end

function M.setOverridePawnRotationMode(val)
	pawnRotationModeOverride = val
end

function M.setAimCameraOverride(val)
	aimCameraOverride = val
end

function M.setPawnPositionMode(val)
	saveParameter("pawnPositionMode", val)
end

function M.setPawnPositionAnimationScale(val)
	saveParameter("pawnPositionAnimationScale", val)
end

function M.setAdjustForAnimation(val)
	saveParameter("adjustForAnimation", val)
end

function M.setAdjustForEyeOffset(val)
	saveParameter("adjustForEyeOffset", val)
end

function M.setEyeOffset(val)
	saveParameter("eyeOffset", val)
end

function M.setFixSpatialAudio(val)
	saveParameter("fixSpatialAudio", val)
	doFixSpatialAudio()
end

function M.setPawnPositionSweepMovement(val)
	saveParameter("pawnPositionSweepMovement", val)
end

function M.setOptimizeBodyYawCalculations(val)
	optimizeBodyYawCalculations = val
end

function M.setHeadOffset(val)
	local v = uevrUtils.vector(val)
	if v ~= nil then
		saveParameter("headOffset", {X=v.X,Y=v.Y,Z=v.Z})
	end
end

function M.setRootOffset(val)
	local v = uevrUtils.vector(val)
	if v ~= nil then
		saveParameter("rootOffset", {X=v.X,Y=v.Y,Z=v.Z})
	end
end

--This function sets the global rootComponent variable 
local function getRootComponent()
	if status.rootComponent == nil then
		local component = uevrUtils.getValid(pawn,{"RootComponent"})
		if component ~= nil and component.K2_GetComponentLocation ~= nil and component.K2_GetComponentRotation ~= nil and component.K2_SetWorldRotation ~= nil then
			status.rootComponent = component
		end
	end
	rootComponent = uevrUtils.getValid(status.rootComponent)
	if rootComponent == nil then
		status.rootComponent = nil
	end
	return rootComponent
	
	-- rootComponent = nil
	-- local component = uevrUtils.getValid(pawn,{"RootComponent"})
	-- if component ~= nil and component.K2_GetComponentLocation ~= nil and component.K2_GetComponentRotation ~= nil and component.K2_SetWorldRotation ~= nil then
	-- 	rootComponent = component
	-- end
	-- return rootComponent
end
getRootComponent = uevrUtils.profiler:wrap("getRootComponent", getRootComponent)

--VR_SwapControllerInputs check this to see if user has chosen left hand full input swap in the UEVR UI
local function updateDecoupledYaw(state, rotationHand)
	if rotationHand == nil then rotationHand = Handed.Right end
	local yawChange = 0
	if decoupledYaw ~= nil then
		local thumbLX = state.Gamepad.sThumbLX
		local thumbLY = state.Gamepad.sThumbLY
		local thumbRX = state.Gamepad.sThumbRX
		local thumbRY = state.Gamepad.sThumbRY

		if rotationHand == Handed.Left then
			thumbLX = state.Gamepad.sThumbRX
			thumbLY = state.Gamepad.sThumbRY
			thumbRX = state.Gamepad.sThumbLX
			thumbRY = state.Gamepad.sThumbLY
		end

		if getParameter("useSnapTurn") then
			local snapAngle = getParameter("snapAngle") or 45
			if thumbRX > snapTurnDeadZone and rxState == 0 then
				yawChange = snapAngle
				rxState=1
			elseif thumbRX < -snapTurnDeadZone and rxState == 0 then
				yawChange = -snapAngle
				rxState=1
			elseif thumbRX <= snapTurnDeadZone and thumbRX >=-snapTurnDeadZone then
				rxState=0
			end
		else
			local smoothTurnRate = getParameter("smoothTurnSpeed") / 12.5
			local rate = thumbRX/32767
			rate =  rate*rate*rate*rate
			if thumbRX > 2200 then
				yawChange = (rate * smoothTurnRate)
			end
			if thumbRX < -2200 then
				yawChange =  -(rate * smoothTurnRate)
			end
		end

		--keep the decoupled yaw in the range of -180 to 180
		decoupledYaw = uevrUtils.clampAngle180(decoupledYaw + yawChange)
	end
	return yawChange
end
updateDecoupledYaw = uevrUtils.profiler:wrap("updateDecoupledYaw", updateDecoupledYaw)

local function initDecoupledYaw()
	if decoupledYaw == nil then
		if rootComponent ~= nil then
			local rotator = rootComponent:K2_GetComponentRotation()
			decoupledYaw = rotator.Yaw
		end
	end
end
initDecoupledYaw = uevrUtils.profiler:wrap("initDecoupledYaw", initDecoupledYaw)

local function getBodyMesh()
	if bodyMesh == nil then
		bodyMesh = pawnModule.getBodyMesh()
	end
	return bodyMesh
end
getBodyMesh = uevrUtils.profiler:wrap("getBodyMesh", getBodyMesh)

-- When a pawn runs, the animation can move the mesh ahead of the pawn, allowing you to
-- see down the neck hole if you are looking down. This function calculates an offset by which a pawn's
-- mesh can be moved to keep the neck in its proper place with respect to the pawn. Concept courtesy of Pande4360
local function getAnimationHeadDelta(pawn, pawnYaw)
	local headBoneName = getParameter("headBoneName")
	local rootBoneName = getParameter("rootBoneName")
	if headBoneName ~= "" and rootBoneName ~= "" and getParameter("adjustForAnimation") == true then
		local mesh = getBodyMesh()
		if mesh ~= nil then
			local baseRotationOffsetRotatorYaw = 0
			if pawn.BaseRotationOffset ~= nil then
				local baseRotationOffsetRotator = kismet_math_library:Quat_Rotator(pawn.BaseRotationOffset)
				if baseRotationOffsetRotator ~= nil then
					baseRotationOffsetRotatorYaw = baseRotationOffsetRotator.Yaw
				end
			end

			--local pawnPos = rootComponent:K2_GetComponentLocation()
			local headSocketLocation = mesh:GetSocketLocation(uevrUtils.fname_from_string(headBoneName))
			local rootSocketLocation = mesh:GetSocketLocation(uevrUtils.fname_from_string(rootBoneName))
			local socketDelta = uevrUtils.vector(headSocketLocation.Y - rootSocketLocation.Y, headSocketLocation.X - rootSocketLocation.X, headSocketLocation.Z - rootSocketLocation.Z)
			socketDelta = kismet_math_library:RotateAngleAxis(socketDelta, pawnYaw - baseRotationOffsetRotatorYaw, uevrUtils.vector(0,0,1))
			--print(headBoneName, rootBoneName, socketDelta.X, socketDelta.Y, socketDelta.Z)
			return socketDelta
		end
	end
	return uevrUtils.vector(0,0,0)
end
getAnimationHeadDelta = uevrUtils.profiler:wrap("getAnimationHeadDelta", getAnimationHeadDelta)

--because the eyes may not be centered on the origin, an hmd rotation can cause unexpected movement of the pawn mesh. This compensates for that movement
local function getEyeOffsetDelta(pawn, pawnYaw)
	local adjustForEyeOffset = getParameter("adjustForEyeOffset")
	if adjustForEyeOffset == true then
		local eyeOffset = getParameter("eyeOffset")
		local eyeOffsetScale = (pawn.BaseTranslationOffset and pawn.BaseTranslationOffset.X or 0) + eyeOffset
		local eyeVector = kismet_math_library:Conv_RotatorToVector(uevrUtils.rotator(currentHeadRotator.Pitch, pawnYaw - currentHeadRotator.Yaw, currentHeadRotator.Roll))
		eyeVector = eyeVector * eyeOffsetScale
		--print("EYE1",eyeVector.X,eyeVector.Y,eyeVector.Z)
		return eyeVector
	else
		return uevrUtils.vector(0,0,0)
	end
end
getEyeOffsetDelta = uevrUtils.profiler:wrap("getEyeOffsetDelta", getEyeOffsetDelta)

local function getPawnRotationMode()
	return pawnRotationModeOverride ~= nil and pawnRotationModeOverride or getParameter("pawnRotationMode")
end

local function getBodyRotationSmoothingDelta(delta)
	if delta ~= nil and delta > 0 then
		lastBodyYawUpdateTime = os.clock()
		return delta
	end

	local now = os.clock()
	local fallbackDelta = lastBodyYawUpdateTime ~= nil and (now - lastBodyYawUpdateTime) or nil
	lastBodyYawUpdateTime = now

	if fallbackDelta == nil or fallbackDelta <= 0 then
		return 1 / 90
	end

	return math.min(fallbackDelta, 0.05)
end

local function smoothBodyRotationOffset(targetOffset, delta)
	targetOffset = uevrUtils.clampAngle180(targetOffset or 0)

	local smoothTime = getParameter("pawnRotationLockedSmoothTime") or 0
	if smoothTime <= 0 then
		return targetOffset
	end

	local smoothingDelta = getBodyRotationSmoothingDelta(delta)
	local alpha = 1 - math.exp(-smoothingDelta / smoothTime)
	local angleDelta = uevrUtils.clampAngle180(targetOffset - bodyRotationOffset)

	if math.abs(angleDelta) < 0.01 then
		return targetOffset
	end

	return uevrUtils.clampAngle180(bodyRotationOffset + angleDelta * math.min(1, alpha))
end

local lateYaw = false
--this is called from both on_pre_engine_tick and on_early_calculate_stereo_view_offset but K2_SetWorldRotation can only be called once per tick
--because of the currentOffset ~= bodyRotationOffset check
local function updateBodyYaw(delta)
	local pawnRotationMode = getPawnRotationMode() -- getParameter("pawnRotationMode")
	if pawnRotationMode ~= M.PawnRotationMode.NONE then
		if decoupledYaw~= nil and rootComponent ~= nil then
			local currentOffset = bodyRotationOffset
			if delta ~= nil and delta > 0 then
				lastBodyYawUpdateTime = os.clock()
			end
			if lateYaw then
				if pawnRotationMode == M.PawnRotationMode.SIMPLE then
					bodyRotationOffset = bodyYaw.update(bodyRotationOffset, currentHeadRotator.Yaw - decoupledYaw, delta)
				elseif pawnRotationMode == M.PawnRotationMode.ADVANCED then
					--bodyRotationOffset = smoothBodyRotationOffset(bodyYaw.updateAdvanced(bodyRotationOffset, currentHeadRotator.Yaw - decoupledYaw, controllers.getControllerLocation(2), controllers.getControllerLocation(0),  controllers.getControllerLocation(1), delta), delta)
					bodyRotationOffset = bodyYaw.updateAdvanced(bodyRotationOffset, currentHeadRotator.Yaw - decoupledYaw, controllers.getControllerLocation(2), controllers.getControllerLocation(0),  controllers.getControllerLocation(1), delta)
				else
					local aimMethod = getParameter("aimMethod")
					if pawnRotationMode == M.PawnRotationMode.LOCKED then
						bodyRotationOffset = smoothBodyRotationOffset(currentHeadRotator.Yaw - decoupledYaw, delta)
					elseif pawnRotationMode == M.PawnRotationMode.LEFT_CONTROLLER then
	--TODO this seems wrong. Why is aim affecting body rotation?
						local rotation = (aimMethod == M.AimMethod.LEFT_WEAPON and weaponRotation ~= nil and weaponRotation.left ~= nil) and weaponRotation.left or controllers.getControllerRotation(Handed.Left)
						--did this to fix robocop. what happens with hello neighbor?
						if rotation ~= nil then
							local final = aimMethod ~= M.AimMethod.LEFT_WEAPON and getAimOffsetAdjustedRotation(rotation) or rotation
							bodyRotationOffset = smoothBodyRotationOffset(final.Yaw - decoupledYaw, delta)
						end
						--if rotation ~= nil then bodyRotationOffset = rotation.Yaw - decoupledYaw end
					elseif pawnRotationMode == M.PawnRotationMode.RIGHT_CONTROLLER then
	--TODO this seems wrong. Why is aim affecting body rotation?
						local rotation = (aimMethod == M.AimMethod.RIGHT_WEAPON and weaponRotation ~= nil and weaponRotation.right ~= nil) and weaponRotation.right or controllers.getControllerRotation(Handed.Right)
	--					local rotation = controllers.getControllerRotation(Handed.Right)
						--did this to fix robocop. what happens with hello neighbor? (even though hello neighbor doesnt need gunstock adjustments)
						if rotation ~= nil then
							local final = aimMethod ~= M.AimMethod.RIGHT_WEAPON and getAimOffsetAdjustedRotation(rotation) or rotation
							bodyRotationOffset = smoothBodyRotationOffset(final.Yaw - decoupledYaw, delta)
						end
						--if rotation ~= nil then bodyRotationOffset = rotation.Yaw - decoupledYaw end
					end
				end
				pcall(function()
					if currentOffset ~= bodyRotationOffset and rootComponent.K2_SetWorldRotation ~= nil then
						rootComponent:K2_SetWorldRotation(uevrUtils.rotator(0,decoupledYaw+bodyRotationOffset,0),false,reusable_hit_result,false)
					end
				end)
				return
			end
			if delta ~= nil then
				if pawnRotationMode == M.PawnRotationMode.SIMPLE then
					bodyRotationOffset = bodyYaw.update(bodyRotationOffset, currentHeadRotator.Yaw - decoupledYaw, delta)
				elseif pawnRotationMode == M.PawnRotationMode.ADVANCED then
					--bodyRotationOffset = smoothBodyRotationOffset(bodyYaw.updateAdvanced(bodyRotationOffset, currentHeadRotator.Yaw - decoupledYaw, controllers.getControllerLocation(2), controllers.getControllerLocation(0),  controllers.getControllerLocation(1), delta), delta)
					bodyRotationOffset = bodyYaw.updateAdvanced(bodyRotationOffset, currentHeadRotator.Yaw - decoupledYaw, controllers.getControllerLocation(2), controllers.getControllerLocation(0),  controllers.getControllerLocation(1), delta)
				end
				-- record last real tick time for fallback smoothing when delta is unavailable
				--lastBodyYawUpdateTime = os.clock()
			else
				local aimMethod = getParameter("aimMethod")
				if pawnRotationMode == M.PawnRotationMode.LOCKED then
					bodyRotationOffset = smoothBodyRotationOffset(currentHeadRotator.Yaw - decoupledYaw, delta)
				elseif pawnRotationMode == M.PawnRotationMode.LEFT_CONTROLLER then
--TODO this seems wrong. Why is aim affecting body rotation?
					local rotation = (aimMethod == M.AimMethod.LEFT_WEAPON and weaponRotation ~= nil and weaponRotation.left ~= nil) and weaponRotation.left or controllers.getControllerRotation(Handed.Left)
					--did this to fix robocop. what happens with hello neighbor?
					if rotation ~= nil then
						local final = aimMethod ~= M.AimMethod.LEFT_WEAPON and getAimOffsetAdjustedRotation(rotation) or rotation
						bodyRotationOffset = smoothBodyRotationOffset(final.Yaw - decoupledYaw, delta)
					end
					--if rotation ~= nil then bodyRotationOffset = rotation.Yaw - decoupledYaw end
				elseif pawnRotationMode == M.PawnRotationMode.RIGHT_CONTROLLER then
--TODO this seems wrong. Why is aim affecting body rotation?
					local rotation = (aimMethod == M.AimMethod.RIGHT_WEAPON and weaponRotation ~= nil and weaponRotation.right ~= nil) and weaponRotation.right or controllers.getControllerRotation(Handed.Right)
--					local rotation = controllers.getControllerRotation(Handed.Right)
					--did this to fix robocop. what happens with hello neighbor? (even though hello neighbor doesnt need gunstock adjustments)
					if rotation ~= nil then
						local final = aimMethod ~= M.AimMethod.RIGHT_WEAPON and getAimOffsetAdjustedRotation(rotation) or rotation
						bodyRotationOffset = smoothBodyRotationOffset(final.Yaw - decoupledYaw, delta)
					end
					--if rotation ~= nil then bodyRotationOffset = rotation.Yaw - decoupledYaw end
				end
			end
			pcall(function()
				if currentOffset ~= bodyRotationOffset and rootComponent.K2_SetWorldRotation ~= nil then
					rootComponent:K2_SetWorldRotation(uevrUtils.rotator(0,decoupledYaw+bodyRotationOffset,0),false,reusable_hit_result,false)
				end
			end)
		end
	else
		bodyRotationOffset = 0
	end
end
updateBodyYaw = uevrUtils.profiler:wrap("updateBodyYaw", updateBodyYaw)

function M.getRotationOffset()
	if decoupledYaw ~= nil and bodyRotationOffset ~= nil then
		return decoupledYaw+bodyRotationOffset
	end
	return 0
end

local function vectorRotate_Quat(vec, quat)
	return mathLib.vectorRotate_Quat(vec, quat, false)
end
vectorRotate_Quat = uevrUtils.profiler:wrap("Input vectorRotate_Quat", vectorRotate_Quat)

local function updatePawnPositionRoomscale(world_to_meters)
	local pawnPositionMode = getParameter("pawnPositionMode")
	if pawnPositionMode ~= M.PawnPositionMode.NONE and rootComponent ~= nil and decoupledYaw ~= nil then
		uevr.params.vr.get_standing_origin(temp_vec3f)

		local origin = {X=temp_vec3f.X,Y=temp_vec3f.Y,Z=temp_vec3f.Z}
		temp_quatf:set(0,0,0,0)
		uevr.params.vr.get_pose(uevr.params.vr.get_hmd_index(), temp_vec3f, temp_quatf)

		--delta is how much the real world position of the hmd is changed from the real world origin
		local delta = {X=(temp_vec3f.X-origin.X)*world_to_meters, Y=(temp_vec3f.Y-origin.Y)*world_to_meters, Z=(temp_vec3f.Z-origin.Z)*world_to_meters}
		-- local dist = delta.X*delta.X + delta.Y*delta.Y
		-- print(dist)
		-- temp_quatf contains how much the rotation of the hmd is relative to the real world vr coordinate system
		--local poseQuat = uevrUtils.quat(temp_quatf.Z, temp_quatf.X, -temp_quatf.Y, -temp_quatf.W)  --reordered terms to convert UEVR to unreal coord system
		--local poseRotator = kismet_math_library:Quat_Rotator(poseQuat)
		--print("POSE",poseRotator.Pitch, poseRotator.Yaw, poseRotator.Roll) --this is in the Unreal coord system

		temp_quatf:set(0,0,0,0)
		uevr.params.vr.get_rotation_offset(temp_quatf) --This is how much the head was twisted from the pose quat the last time "recenter view" was performed
		--local headQuat = uevrUtils.quat(temp_quatf.Z, temp_quatf.X, -temp_quatf.Y, temp_quatf.W) --reordered terms to convert UEVR to unreal coord system
		--local headRotator = kismet_math_library:Quat_Rotator(headQuat)
		--print("HEAD",headRotator.Pitch, headRotator.Yaw, headRotator.Roll) --this is in the Unreal coord system

		--rotate the delta by the amount of the hmd offset
		
		local forwardVector = vectorRotate_Quat({X=-delta.Z, Y=delta.X, Z=delta.Y}, {X=temp_quatf.Z, Y=temp_quatf.X, Z=-temp_quatf.Y, W=temp_quatf.W}) -- kismet_math_library:Quat_RotateVector(headQuat, uevrUtils.vector(-delta.Z, delta.X, delta.Y)) --converts UEVR to Unreal coord system
		--local forwardVector = vectorRotate_Quat(headQuat, uevrUtils.vector(-delta.Z, delta.X, delta.Y)) -- kismet_math_library:Quat_RotateVector(headQuat, uevrUtils.vector(-delta.Z, delta.X, delta.Y)) --converts UEVR to Unreal coord system

		--add the decoupledYaw yaw rotation to the delta vector
		forwardVector = kismet_math_library:RotateAngleAxis( forwardVector,  decoupledYaw, uevrUtils.vector(0,0,1))
		--local dist = forwardVector.X*forwardVector.X + forwardVector.Y*forwardVector.Y
		--if dist > 2.0 then
			--print("Here",dist)
			forwardVector.Z = 0 --do not affect up/down
			pcall(function()
				if pawnPositionMode == M.PawnPositionMode.ANIMATED  then
					if uevrUtils.getValid(pawn) ~= nil and pawn.AddMovementInput ~= nil then
						pawn:AddMovementInput(forwardVector, getParameter("pawnPositionAnimationScale"), false) --dont need to check for pawn because if rootComponent exists then pawn exists
					end
				elseif pawnPositionMode == M.PawnPositionMode.FOLLOWS and rootComponent.K2_AddWorldOffset ~= nil then
					--pcall(function()
					if uevrUtils.getValid(rootComponent) ~= nil then
						rootComponent:K2_AddWorldOffset(forwardVector, getParameter("pawnPositionSweepMovement"), reusable_hit_result, false)
					end
					--end)
					--rootComponent:K2_SetWorldLocation(uevrUtils.vector(pawnPos.X+forwardVector.X,pawnPos.Y+forwardVector.Y,pawnPos.Z),pawnPositionSweepMovement,reusable_hit_result,false)
				end
			end)

			--temp_vec3f has the get_pose location
			temp_vec3f.Y = origin.Y --dont affect the up_down position
			uevr.params.vr.set_standing_origin(temp_vec3f)
		--end
	end
end
updatePawnPositionRoomscale = uevrUtils.profiler:wrap("updatePawnPositionRoomscale", updatePawnPositionRoomscale)

local function updateMeshRelativePosition()
	if rootComponent ~= nil and decoupledYaw ~= nil then
		local mesh = getBodyMesh()
		if mesh ~= nil then
			pcall(function()
				--the next line can fail even when checking for rootComprootComponent.K2_GetComponentRotation ~= nil so wrap in pcall
				local pawnRot = rootComponent:K2_GetComponentRotation()
				local animationDelta = getAnimationHeadDelta(pawn, pawnRot.Yaw)
				local eyeOffsetDelta = getEyeOffsetDelta(pawn, pawnRot.Yaw)

				temp_vec3:set(0, 0, 1) --the axis to rotate around
				--headOffset is a global defining how far the head is offset from the mesh
				local headOffset = uevrUtils.vector(getParameter("headOffset"))
				local forwardVector = kismet_math_library:RotateAngleAxis(headOffset, pawnRot.Yaw - bodyRotationOffset - decoupledYaw, temp_vec3)
				local x = -forwardVector.X
				local y = -forwardVector.Y
				if animationDelta ~= nil and eyeOffsetDelta ~= nil then
					x = x + animationDelta.X + eyeOffsetDelta.X
					y = y - animationDelta.Y - eyeOffsetDelta.Y
				end
				--print("AAAAAAAAAAAAA",animationDelta ~= nil, getParameter("useMeshHeightForHeadOffset"), status["meshZOffset"] == nil)
				if animationDelta ~= nil and getParameter("useMeshHeightForHeadOffset") and status["meshZOffset"] == nil then
					status["meshZOffset"] = animationDelta.Z / 2 - 90 + (headOffset and headOffset.Z or 0)
					print("Calculated meshZOffset:", status["meshZOffset"])
				end
				--dont worry about Z here. Z is applied directly to the RootComponent later
				mesh.RelativeLocation.X = x
				mesh.RelativeLocation.Y = y
			end)
		end
	end
end
updateMeshRelativePosition = uevrUtils.profiler:wrap("updateMeshRelativePosition", updateMeshRelativePosition)

function M.setAimRotationOffset(offset)
	aimRotationOffset = uevrUtils.rotator(offset)
end

function M.setWeaponRotation(leftRotation, rightRotation)
	weaponRotation = {
		left = uevrUtils.rotator(leftRotation),
		right = uevrUtils.rotator(rightRotation)
	}
	-- if weaponRotation.right ~= nil then
	-- 	weaponRotation.right.Yaw = weaponRotation.right.Yaw + 90
	-- 	local roll = weaponRotation.right.Pitch
	-- 	weaponRotation.right.Pitch = -weaponRotation.right.Roll
	-- 	weaponRotation.right.Roll = roll
	-- end
	--print("Weapon Rotation Set", weaponRotation.left.Pitch, weaponRotation.left.Yaw, weaponRotation.left.Roll, weaponRotation.right.Pitch, weaponRotation.right.Yaw, weaponRotation.right.Roll)
end

local function updateIsDisabled()
	local disabled = getParameter("isDisabledOverride") or executeIsDisabledCallback() or false
	if isDisabled ~= disabled then
		isDisabled = disabled
		--uevr.params.vr.recenter_view()
		M.resetView()
		resetPawnSettings()
	end
end

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
	--set the global rootComponent variable on the earliest tick callback so it will be valid everywhere
	getRootComponent()

	--calculate the controller rotation here so it is available for updateBodyYaw and updateAim?

	updateIsDisabled()
	if not isDisabled then --and getParameter("aimMethod") ~= M.AimMethod.UEVR then
		initDecoupledYaw()
		updatePawnSettings()
		updateAim()
		updateBodyYaw(delta)
	end

end)

local function getVRCameraOffsets()
	if bodyRotationOffset ~= nil and rootComponent ~= nil and uevrUtils.getValid(rootComponent) ~= nil and rootComponent.K2_GetComponentLocation ~= nil then
		local pawnPos = rootComponent:K2_GetComponentLocation()
		local pawnRot = rootComponent:K2_GetComponentRotation()

		local capsuleHeight = rootComponent.CapsuleHalfHeight or 0

		local forwardVector = {X=0,Y=0,Z=0}
		local rootOffset = getParameter("rootOffset")
		if rootOffset ~= nil then
			if rootOffset.X ~= 0 and rootOffset.Y ~= 0 then
				temp_vec3f:set(rootOffset.X, rootOffset.Y, rootOffset.Z) -- the vector representing the offset adjustment
				temp_vec3:set(0, 0, 1) --the axis to rotate around
				forwardVector = kismet_math_library:RotateAngleAxis(temp_vec3f, pawnRot.Yaw - bodyRotationOffset, temp_vec3)
			end
			--print("Current",status["meshZOffset"])
			return  pawnPos.x + forwardVector.X, pawnPos.y + forwardVector.Y, pawnPos.z + rootOffset.Z + capsuleHeight + getParameter("headOffset").Z + (status["meshZOffset"] or 0), 0, pawnRot.Yaw - bodyRotationOffset, 0
		end
	end
end
getVRCameraOffsets = uevrUtils.profiler:wrap("getVRCameraOffsets", getVRCameraOffsets)

uevr.params.sdk.callbacks.on_early_calculate_stereo_view_offset(function(device, view_index, world_to_meters, position, rotation, is_double)
	if not isDisabled then --and getParameter("aimMethod") ~= M.AimMethod.UEVR then
		--print(optimizeBodyYawCalculations == false, getParameter("optimizeBodyRotationCalculations") ~= true, view_index)
		if lateYaw == false and optimizeBodyYawCalculations == false or getParameter("optimizeBodyRotationCalculations") ~= true or view_index == 1 then
			updateBodyYaw()
		end
		if getParameter("optimizeBodyLocationCalculations") ~= true or view_index == 1 then
			updatePawnPositionRoomscale(world_to_meters)
		end

		if lateYaw == false and view_index == 1 then
			updateMeshRelativePosition()
		end

		local pawnRotationMode = getPawnRotationMode() -- getParameter("pawnRotationMode")
		if pawnRotationMode ~= M.PawnRotationMode.NONE then
			--Change the UEVR camera position and rotation to align with the pawn
			local x, y, z, pitch, yaw, roll = getVRCameraOffsets()
			position.x = x
			position.y = y
			position.z = z
			if getParameter("pawnRotationModeDisableRotation") ~= true then
				rotation.Pitch = pitch
				rotation.Yaw = yaw
				rotation.Roll = roll
			end
		end

		--Change the UEVR camera position and rotation to align with the pawn
		-- if bodyRotationOffset ~= nil and rootComponent ~= nil and uevrUtils.getValid(rootComponent) ~= nil and rootComponent.K2_GetComponentLocation ~= nil then
		-- 	local pawnPos = rootComponent:K2_GetComponentLocation()
		-- 	local pawnRot = rootComponent:K2_GetComponentRotation()

		-- 	local capsuleHeight = rootComponent.CapsuleHalfHeight or 0

		-- 	local forwardVector = {X=0,Y=0,Z=0}
		-- 	local rootOffset = getParameter("rootOffset")
		-- 	if rootOffset ~= nil then
		-- 		if rootOffset.X ~= 0 and rootOffset.Y ~= 0 then
		-- 			temp_vec3f:set(rootOffset.X, rootOffset.Y, rootOffset.Z) -- the vector representing the offset adjustment
		-- 			temp_vec3:set(0, 0, 1) --the axis to rotate around
		-- 			forwardVector = kismet_math_library:RotateAngleAxis(temp_vec3f, pawnRot.Yaw - bodyRotationOffset, temp_vec3)
		-- 		end

		-- 		position.x = pawnPos.x + forwardVector.X
		-- 		position.y = pawnPos.y + forwardVector.Y
		-- 		position.z = pawnPos.z + rootOffset.Z + capsuleHeight + getParameter("headOffset").Z
		-- 		rotation.Pitch = 0--pawnRot.Pitch 
		-- 		rotation.Yaw = pawnRot.Yaw - bodyRotationOffset
		-- 		rotation.Roll = 0--pawnRot.Roll 	

		-- 	end
		-- end
	end

	--Change the UEVR camera position and rotation to align with the pawn root component
	-- if rootComponent ~= nil then
	-- 	local offsetYaw = 0
	-- 	if not isDisabled and aimMethod ~= M.AimMethod.UEVR and bodyRotationOffset ~= nil then
	-- 		offsetYaw = bodyRotationOffset
	-- 	end

	-- 	local pawnPos = rootComponent:K2_GetComponentLocation()	
	-- 	local pawnRot = rootComponent:K2_GetComponentRotation()					

	-- 	temp_vec3f:set(rootOffset.X, rootOffset.Y, rootOffset.Z) -- the vector representing the offset adjustment
	-- 	temp_vec3:set(0, 0, 1) --the axis to rotate around
	-- 	local forwardVector = kismet_math_library:RotateAngleAxis(temp_vec3f, pawnRot.Yaw - offsetYaw, temp_vec3)

	-- 	position.x = pawnPos.x + forwardVector.X
	-- 	position.y = pawnPos.y + forwardVector.Y
	-- 	position.z = pawnPos.z + forwardVector.Z

	-- 	rotation.Pitch = 0--pawnRot.Pitch 
	-- 	rotation.Yaw = pawnRot.Yaw - offsetYaw
	-- 	rotation.Roll = 0--pawnRot.Roll 	
	-- end

end)

uevr.sdk.callbacks.on_post_calculate_stereo_view_offset(function(device, view_index, world_to_meters, position, rotation, is_double)
	--currentHeadRotator = rotation -- this doesnt work	
	currentHeadRotator.Pitch = rotation.Pitch
	currentHeadRotator.Yaw = rotation.Yaw
	currentHeadRotator.Roll = rotation.Roll
end)

uevr.sdk.callbacks.on_post_engine_tick(function(engine, delta)
	if lateYaw then
		if not isDisabled then
			updateBodyYaw(delta)
			--updateBodyYaw()
			updateMeshRelativePosition()
		end
	end

	-- if not isDisabled then --and pawnRotationMode ~= M.PawnRotationMode.NONE then
	-- 	if decoupledYaw~= nil and rootComponent ~= nil then
	-- 		rootComponent:K2_SetWorldRotation(uevrUtils.rotator(0,decoupledYaw+bodyRotationOffset,0),false,reusable_hit_result,false)
	-- 	end
	-- end

end)

--without this the right controller left/right stick movement does nothing
uevr.sdk.callbacks.on_xinput_get_state(function(retval, user_index, state)
	--local pawnRotationMode = getPawnRotationMode() -- getParameter("pawnRotationMode")
	if not isDisabled then --and pawnRotationMode ~= M.PawnRotationMode.NONE then
		local yawChange = updateDecoupledYaw(state)
		if yawChange ~= 0 and decoupledYaw~= nil and rootComponent ~= nil and getParameter("pawnRotationModeDisableRotation") ~= true then
			rootComponent:K2_SetWorldRotation(uevrUtils.rotator(0,decoupledYaw+bodyRotationOffset,0),false,reusable_hit_result,false)
		end
	end
end)


-- register_key_bind("F1", function()
    -- print("F1 pressed\n")
	-- --pawn:StartBulletTime(0.0, 50.0, false, 1.0, 0.4, 2.0)
	-- --rootComponent:K2_SetWorldLocation(uevrUtilsvector(lastPosition),false,reusable_hit_result,false)
	-- local rootComponent = uevrUtils.getValid(pawn,{"RootComponent"})
	-- if rootComponent ~= nil then
		-- rootComponent:K2_AddWorldOffset(uevrUtils.vector(deltaX,deltaY,0), true, reusable_hit_result, false);
	-- end
-- end)


uevrUtils.registerPreLevelChangeCallback(function(level)
	decoupledYaw = nil
	bodyRotationOffset = 0
	lastBodyYawUpdateTime = nil
	bodyMesh = nil
	cameraComponent:reset()
end)

uevr.params.sdk.callbacks.on_script_reset(function()
	status = {}
	decoupledYaw = nil
	bodyRotationOffset = 0
	lastBodyYawUpdateTime = nil
	bodyMesh = nil
	cameraComponent:reset()
	resetPawnSettings()
end)

function M.resetView()
	decoupledYaw = nil
	bodyRotationOffset = 0
	lastBodyYawUpdateTime = nil
	uevr.params.vr.recenter_view()
end

uevrUtils.registerLevelChangeCallback(function(level)
	status = {}
	if getParameter("aimMethod") ~= M.AimMethod.UEVR then
		controllers.createController(0)
		controllers.createController(1)
		controllers.createController(2)
	end

	doFixSpatialAudio()
end)

uevrUtils.registerUEVRCallback("gunstock_transform_change", function(id, newLocation, newRotation, newOffhandLocationOffset)
	--only handle gunstock transform changes if aim method is left or right controller since
	--if its left or right weapon, the weapon already has the gunstock adjustments applied
    local aimMethod = getParameter("aimMethod")
	if aimMethod == M.AimMethod.LEFT_CONTROLLER or aimMethod == M.AimMethod.RIGHT_CONTROLLER then
		M.setAimRotationOffset(newRotation)
	end
end)

uevrUtils.registerUEVRCallback("on_pawn_param_change", function(name, value)
	--if the pawn body mesh changes, clear the cached bodyMesh variable so a new one can be obtained on the next tick
	if name == "bodyMeshName" then
		bodyMesh = nil
	end
end)

uevrUtils.registerUEVRCallback("attachment_grip_rotation_change", function(leftRotation, rightRotation)
	M.setWeaponRotation(leftRotation, rightRotation)
end)


return M

	-- local controllerID = 1
	-- local rotation1 = controllers.getControllerRotation(controllerID)
	-- local direction1 = controllers.getControllerDirection(controllerID)
	-- local location1 = controllers.getControllerLocation(controllerID)
	-- local rotation2 = nil
	-- local location2 = nil
	-- local direction2 = nil
	-- local index = uevrUtils.getControllerIndex(controllerID)
	-- if index ~= nil then
		-- uevr.params.vr.get_pose(index, temp_vec3f, temp_quatf)
		-- local poseQuat = uevrUtils.quat(temp_quatf.Z, temp_quatf.X, -temp_quatf.Y, -temp_quatf.W)  --reordered terms to convert UEVR to unreal coord system
		-- print(temp_quatf.X,temp_quatf.Y,temp_quatf.Z,temp_quatf.W)
		-- direction2 = kismet_math_library:Quat_RotateVector(poseQuat, uevrUtils.vector(1, 0, 0)) --converts UEVR to Unreal coord system
		-- location2 = uevrUtils.vector(temp_vec3f.X*100,temp_vec3f.Z*100,temp_vec3f.Y*100)
		-- location2 = kismet_math_library:Quat_RotateVector(poseQuat,location2) --converts UEVR to Unreal coord system
		-- rotation2 = kismet_math_library:Quat_Rotator(poseQuat)
	-- end	
	-- uevr.params.vr.get_rotation_offset(temp_quatf) --This is how much the head was twisted from the pose quat the last time "recenter view" was performed
	-- local headQuat = uevrUtils.quat(temp_quatf.Z, temp_quatf.X, -temp_quatf.Y, temp_quatf.W) --reordered terms to convert UEVR to unreal coord system
	-- local headRotator = kismet_math_library:Quat_Rotator(headQuat)

	-- if rotation1 ~= nil then
		-- print("ROT1",rotation1.Pitch,rotation1.Yaw,rotation1.Roll)
	-- end
	-- -- if rotation2 ~= nil then
		-- -- print("ROT2",rotation2.Pitch,rotation2.Yaw,rotation2.Roll)
	-- -- end
	-- -- if location1 ~= nil then
		-- -- print("LOC1",location1.X,location1.Y,location1.Z)
	-- -- end
	-- -- if location2 ~= nil then
		-- -- print("LOC2",location2.X,location2.Y,location2.Z)
	-- -- end
	-- -- if direction1 ~= nil then
		-- -- print("DIR1",direction1.X,direction1.Y,direction1.Z)
	-- -- end
	-- -- if direction2 ~= nil then
		-- -- print("DIR2",direction2.X,direction2.Y,direction2.Z)
	-- -- end
	-- -- if headRotator ~= nil then
		-- -- print("HEAD",headRotator.Pitch,headRotator.Yaw,headRotator.Roll)
	-- -- end
