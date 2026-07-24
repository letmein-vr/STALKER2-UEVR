local uevrUtils = require("libs/uevr_utils")
local controllers = require("libs/controllers")
local attachments = require("libs/attachments")
--local paramModule = require("libs/core/params")
local accessoriesConfigDev = require("libs/config/accessories_config_dev")

local M = {}

local status = {}
local accessoryStatus = {}

-- Getting accessory parameters from config file currently
-- local parametersFileName = "accessories_parameters"
-- local parameters = {}
-- local paramManager = paramModule.new(parametersFileName, parameters, true)

-- Toggle for verbose marker/montage diagnostics.
-- Keep this false unless you are actively debugging marker timing/selection.
local MARKER_DEBUG = false
local function markerDebugPrint(msg)
	if MARKER_DEBUG then
		print(msg)
	end
end

if MARKER_DEBUG then
	print("[MarkerDebug] accessories.lua loaded; MARKER_DEBUG enabled")
end

local currentLogLevel = LogLevel.Error
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
	if logLevel == nil then logLevel = LogLevel.Debug end
	if logLevel <= currentLogLevel then
		uevrUtils.print("[accessories] " .. text, logLevel)
	end
end

function M.getPrimaryMarkerParams(accessoryParams)
	if accessoryParams == nil then return nil end
	if type(accessoryParams.markers) == "table" then
		return accessoryParams.markers[1]
	end
	return accessoryParams
end

function M.resolveMarkerParamsForTime(accessoryParams, currentTime)
	if accessoryParams == nil then return nil, nil end
	local markers = accessoryParams.markers
	if type(markers) ~= "table" then
		return accessoryParams, 1
	end
	if currentTime == nil then
		return markers[1], 1
	end

	local hasAnyRange = false
	local fallback = markers[1]
	for i, marker in ipairs(markers) do
		local startTime = marker.start_time or 0
		local endTime = marker.end_time or 0
		if startTime ~= 0 or endTime ~= 0 then
			hasAnyRange = true
			if currentTime >= startTime and currentTime <= endTime then
				return marker, i
			end
		else
			fallback = fallback or marker
		end
	end

	if hasAnyRange then
		return nil, nil
	end
	return fallback, 1
end

function M.accessoryHasTimeMarkers(accessoryParams)
	if accessoryParams == nil then return false end
	local markers = accessoryParams.markers
	if type(markers) == "table" then
		for _, marker in ipairs(markers) do
			local startTime = marker.start_time or 0
			local endTime = marker.end_time or 0
			if startTime ~= 0 or endTime ~= 0 then
				return true
			end
		end
		return false
	end
	local startTime = accessoryParams["start_time"] or 0
	local endTime = accessoryParams["end_time"] or 0
	return (startTime ~= 0 or endTime ~= 0)
end

function M.getAccessoryParams(accessoryID)
    return accessoriesConfigDev.getAccessoryParams(accessoryID)
    -- local accessoriesList = paramManager:get("accessories") or {}
    -- for attachmentID, accessories in pairs(accessoriesList) do
    --     for aID, accessoryParams in pairs(accessories) do
    --         if aID == accessoryID then
    --             return accessoryParams
    --         end
    --     end
    -- end
    -- return nil
end

function M.getAccessoriesForAttachment(attachmentID)
    return accessoriesConfigDev.getAccessoriesForAttachment(attachmentID)
    -- if attachmentID == nil or attachmentID == "" then
    --     return {}
    -- end
    -- return paramManager:get({"accessories", attachmentID}) or {}
end

function M.getAccessoryParamsForAttachment(attachmentID, accessoryID)
    return accessoriesConfigDev.getAccessoryParamsForAttachment(attachmentID, accessoryID)
    -- if attachmentID == nil or accessoryID == nil then
    --     return nil
    -- end
    -- local list = paramManager:get({"accessories", attachmentID})
    -- return list and list[accessoryID] or nil
end


local function checkMontageProximity(hand, accessoryParams, currentAttachment)
	local validDistance = true
	local activationHand = accessoryParams.activation_hand or 1
	if activationHand == 10 or (activationHand == 8 and hand == Handed.Left) or (activationHand == 9 and hand == Handed.Right) then
		return true
	end

	local activationDistance = accessoryParams.activation_distance or 0.0
	-- activation_hand:
	--  1=None
	--  2=Left Hand Proximity
	--  3=Right Hand Proximity
	--  4=Either Hand Proximity
	--  5=Left Hand Proximity During Montage Only
	--  6=Right Hand Proximity During Montage Only
	--  7=Either Hand Proximity During Montage Only
	--  8=Left Hand Always
	--  9=Right Hand Always
	-- 10=Either Hand Always
	local handOk =
		(activationHand == 4) or
		(activationHand == 2 and hand == Handed.Left) or
		(activationHand == 3 and hand == Handed.Right) or
		(activationHand == 7) or
		(activationHand == 5 and hand == Handed.Left) or
		(activationHand == 6 and hand == Handed.Right)
	if handOk and activationHand ~= 1 and activationDistance ~= nil and activationDistance > 0 then
		validDistance = false
		local controllerLoc = controllers.getControllerLocation(hand)
		if controllerLoc == nil then
			markerDebugPrint("[MarkerDebug] Proximity failed: controllerLoc nil; hand=" .. tostring(hand))
			return false
		end

		local targetLoc = nil
		local targetRot = nil
		local socketName = accessoryParams.socket_name or ""

		if socketName ~= "" and currentAttachment.GetSocketLocation ~= nil then
			targetLoc = currentAttachment:GetSocketLocation(uevrUtils.fname_from_string(socketName))
			targetRot = currentAttachment:GetSocketRotation(uevrUtils.fname_from_string(socketName))
		elseif currentAttachment.K2_GetComponentLocation ~= nil then
			targetLoc = currentAttachment:K2_GetComponentLocation()
			targetRot = currentAttachment:K2_GetComponentRotation()
		end
		if targetLoc ~= nil then
			targetLoc = targetLoc + uevrUtils.rotateVector(uevrUtils.vector(accessoryParams.location or {0,0,0}), targetRot)
			--targetLoc = targetLoc + uevrUtils.vector(accessoryParams.location or {0,0,0})
			local d = uevrUtils.distanceBetween(controllerLoc, targetLoc)
			if d ~= nil and d <= activationDistance then
				validDistance = true
			else
				markerDebugPrint("[MarkerDebug] Proximity failed: hand=" .. tostring(hand) ..
					" d=" .. tostring(d) ..
					" activationDistance=" .. tostring(activationDistance) ..
					" socket=" .. tostring(socketName))
			end
		else
			markerDebugPrint("[MarkerDebug] Proximity failed: targetLoc nil; hand=" .. tostring(hand) .. " socket=" .. tostring(socketName))
		end
	end
	return validDistance
end

local function executeIsRightAccessoryCallback(...)
	return uevrUtils.executeUEVRCallbacksWithPriorityResult("active_right_accessory", table.unpack({...}))
end

local function executeIsLeftAccessoryCallback(...)
	return uevrUtils.executeUEVRCallbacksWithPriorityResult("active_left_accessory", table.unpack({...}))
end

local function resolveAccessoryMarkerParamsForAttach(accessoryParams, useMontageProximity, animInstance, montageObject, markerIndexOverride, strictMontageTime)
	if accessoryParams == nil then return nil, nil end

	-- (1) Preview override / explicit marker selection
	if markerIndexOverride ~= nil then
		local markers = accessoryParams.markers
		if type(markers) == "table" and #markers > 0 then
			local idx = tonumber(markerIndexOverride) or 1
			if idx < 1 then idx = 1 end
			if idx > #markers then idx = #markers end
			return markers[idx], idx
		end
	end

	-- (2) Montage-time window selection
	if useMontageProximity then
		if animInstance == nil or montageObject == nil or animInstance.Montage_GetPosition == nil then
			if strictMontageTime then
				return nil, nil
			end
		else
			local ok, currentTime = pcall(function()
				return animInstance:Montage_GetPosition(montageObject)
			end)
			if ok then
				local markerParams, markerIndex = M.resolveMarkerParamsForTime(accessoryParams, currentTime)
				-- If any time windows exist but none match, resolveMarkerParamsForTime returns nil.
				-- Treat that as an intentional "detach".
				if markerParams == nil then
					return nil, nil
				end
				return markerParams, markerIndex
			elseif strictMontageTime then
				return nil, nil
			end
		end
	end

	-- (3) Default / non-windowed fallback
	local markerParams = M.getPrimaryMarkerParams(accessoryParams)
	return markerParams, (markerParams ~= nil and 1 or nil)
end

function M.attachHandToAccessory(handed, accessoryID, useMontageProximity, animInstance, montageObject, markerIndexOverride)
    if accessoryID == nil then
        --detach hand
		--print("Detaching hand ", handed, " from accessory")
        --local hand = M.getHandComponent(handed)
		--local statusKey = "hand_" .. tostring(handed)
		--if accessoryStatus[statusKey] ~= nil then
			markerDebugPrint("[MarkerDebug] Detaching hand=" .. tostring(handed) .. " (restoring previous parent/socket)")
			--restoreHandSnapshot(handed)
			uevrUtils.executeUEVRCallbacks("on_accessory_detach", handed)
		--end
		-- Reset grip animation to open hand
		--holdingAttachment[handed] = nil
		uevrUtils.executeUEVRCallbacks("on_accessory_animation", handed, nil)
		if type(accessoryStatus["gripAnimationOverride"]) == "table" then
			accessoryStatus["gripAnimationOverride"][handed] = nil
		end
		--M.updateAnimationState(handed)
    else
		--print("Attaching hand ", handed, " to accessory ", accessoryID)
        --local hand = M.getHandComponent(handed)
		--if hand ~= nil then
            local currentAttachment = attachments.getCurrentGrippedAttachment(Handed.Right)
           	if currentAttachment ~= nil then
				local attachmentID = attachments.getAttachmentIDFromAttachment(currentAttachment)
				local accessoryParams = (attachmentID ~= nil and attachmentID ~= "") and M.getAccessoryParamsForAttachment(attachmentID, accessoryID) or nil
				if accessoryParams == nil then
					accessoryParams = M.getAccessoryParams(accessoryID)
					if accessoryParams ~= nil then
						markerDebugPrint("[MarkerDebug] WARNING: accessoryID=" .. tostring(accessoryID) .. " not found under attachmentID=" .. tostring(attachmentID) .. "; using global lookup")
					end
				end

				if accessoryParams == nil then
					return
				end
				--check if we're using timelines with montages and if so, check if we have a valid time
				local markerParams = nil
				local markerIndex = nil
				markerParams, markerIndex = resolveAccessoryMarkerParamsForAttach(accessoryParams, useMontageProximity, animInstance, montageObject, markerIndexOverride)
				if markerParams == nil then
					local currentTime = nil
					if useMontageProximity and animInstance ~= nil and montageObject ~= nil and animInstance.Montage_GetPosition ~= nil then
						local ok, t = pcall(function()
							return animInstance:Montage_GetPosition(montageObject)
						end)
						if ok then currentTime = t end
					end
					markerDebugPrint("[MarkerDebug] Marker resolve returned nil; detaching. hand=" .. tostring(handed) ..
						" accessoryID=" .. tostring(accessoryID) ..
						" useMontageProximity=" .. tostring(useMontageProximity) ..
						" time=" .. tostring(currentTime) ..
						" markerIndexOverride=" .. tostring(markerIndexOverride))
					local markers = accessoryParams and accessoryParams.markers
					if type(markers) == "table" and #markers > 0 then
						for idx, m in ipairs(markers) do
							markerDebugPrint("[MarkerDebug]  marker[" .. tostring(idx) .. "] start=" .. tostring(m.start_time) ..
								" end=" .. tostring(m.end_time) ..
								" socket=" .. tostring(m.socket_name) ..
								" grip_animation=" .. tostring(m.grip_animation))
						end
					end
					-- outside any marker time range; detach
					M.attachHandToAccessory(handed, nil)
					return
				end

				--check proximity
				local proximityOK = true
				if useMontageProximity then proximityOK = checkMontageProximity(handed, markerParams, currentAttachment) end
				if proximityOK then
					markerDebugPrint("[MarkerDebug] Attaching hand=" .. tostring(handed) ..
						" accessoryID=" .. tostring(accessoryID) ..
						" markerIndex=" .. tostring(markerIndex) ..
						" socket=" .. tostring(markerParams.socket_name or "") ..
						" grip_animation=" .. tostring(markerParams.grip_animation))
					--local statusKey = "hand_" .. tostring(handed)
					-- Only snapshot the base state once per activation chain.
					-- if accessoryStatus[statusKey] == nil then
					-- 	saveHandSnapshot(handed, statusKey)
					-- end

					--attachHandToTarget(handed, currentAttachment, socketName, markerParams.attach_type or 0, markerParams.location or {0,0,0}, markerParams.rotation or {0,0,0})
					uevrUtils.executeUEVRCallbacks("on_accessory_attach", handed, currentAttachment, markerParams.socket_name or "", markerParams.attach_type or 0, markerParams.location or {0,0,0}, markerParams.rotation or {0,0,0})
					
					-- Set grip animation from accessory params
					local gripAnim = markerParams.grip_animation
					uevrUtils.executeUEVRCallbacks("on_accessory_animation", handed, (gripAnim and gripAnim ~= "") and gripAnim or nil)
					--holdingAttachment[handed] = (gripAnim and gripAnim ~= "") and gripAnim or nil
					accessoryStatus["gripAnimationOverride"] = accessoryStatus["gripAnimationOverride"] or {}
					if type(gripAnim) == "string" and gripAnim ~= "" then
						local p = tonumber(markerParams.grip_priority)
						if p == nil then p = 1 end
						accessoryStatus["gripAnimationOverride"][handed] = { active = true, priority = p }
					else
						accessoryStatus["gripAnimationOverride"][handed] = nil
					end
					--M.updateAnimationState(handed)
				elseif useMontageProximity then
					--stop the current montage
					--holdingAttachment[handed] = nil
					uevrUtils.executeUEVRCallbacks("on_accessory_animation", handed, nil)
					if type(accessoryStatus["gripAnimationOverride"]) == "table" then
						accessoryStatus["gripAnimationOverride"][handed] = nil
					end
					--M.updateAnimationState(handed)
					-- if handed == Handed.Left then
					-- 	accessoryStatus["leftProximityAnimationOverride"] = false
					-- else
					-- 	accessoryStatus["rightProximityAnimationOverride"] = false
					-- end
					--M.print("Hand is not within activation distance for this accessory.", LogLevel.Warning)
				end
            end
        --end
    end
    --M.print("Accessory ID: " .. tostring(accessoryID) .. " not found for attachment.", LogLevel.Warning)
end


-- Goal: re-apply current “active_*_accessory” when preview pokes,
-- even if the GUID didn’t change (so transforms update live).
local function refreshAccessoryForHand(handed, force)
	local activeAccessory = nil
	if handed == Handed.Right then
		activeAccessory = select(1, executeIsRightAccessoryCallback())
	else
		activeAccessory = select(1, executeIsLeftAccessoryCallback())
	end

	local key = (handed == Handed.Right) and "activeRightAccessory" or "activeLeftAccessory"

	if force then
		-- IMPORTANT: detach first so we restore original state,
		-- then attach again so it saves original state correctly.
		--TODO This is ugly to detach, reattach. look for a better way
		M.attachHandToAccessory(handed, nil)
		M.attachHandToAccessory(handed, activeAccessory)
		accessoryStatus[key] = activeAccessory
		return
	end

	-- Normal behavior (only on change)
	if activeAccessory ~= accessoryStatus[key] then
		accessoryStatus[key] = activeAccessory
		M.attachHandToAccessory(handed, activeAccessory)
	end
end

uevrUtils.registerUEVRCallback("on_accessory_preview_changed", function(handed, accessoryID, enabled, markerIndex)
	local key = (handed == Handed.Right) and "activeRightAccessory" or "activeLeftAccessory"
	if enabled then
		M.attachHandToAccessory(handed, nil)
		M.attachHandToAccessory(handed, accessoryID, false, nil, nil, markerIndex)
		accessoryStatus[key] = accessoryID
		return
	end

	-- preview off: restore whatever the normal active accessory is
	refreshAccessoryForHand(handed, true)
end)

-----------------------------------------------------------

-- Proximity accessory activation ---------------------------------
local PROXIMITY_ACCESSORY_PRIORITY = 1

local function proximityAccessoryForHand(hand)
	local attachmentHand = Handed.Right
    local attachment = attachments.getCurrentGrippedAttachment(attachmentHand)
    if attachment == nil then return nil end

    local attachmentID = attachments.getAttachmentIDFromAttachment(attachment)-- attachments.getActiveAttachmentID(attachmentHand)
    if attachmentID == nil or attachmentID == "" then return nil end

    local list = M.getAccessoriesForAttachment(attachmentID)
    if list == nil then return nil end

    local bestAccessoryID = nil
    local bestDistance = nil

    for accessoryID, accessoryParams in pairs(list) do
		local markerParams = M.getPrimaryMarkerParams(accessoryParams) or accessoryParams
		local activationHand = markerParams.activation_hand or 1

		--if using one of the "always" options then just use this as the best option
		if activationHand == 10 or (activationHand == 8 and hand == Handed.Left) or (activationHand == 9 and hand == Handed.Right) then
			bestAccessoryID = accessoryID
			break
		end

		local activationDistance = markerParams.activation_distance or 0.0

        -- activation_hand: 1=None, 2=Left, 3=Right, 4=Either
        local handOk =
            (activationHand == 4) or
            (activationHand == 2 and hand == Handed.Left) or
            (activationHand == 3 and hand == Handed.Right)

        if handOk and activationHand ~= 1 and activationDistance ~= nil and activationDistance > 0 then
			local controllerLoc = controllers.getControllerLocation(hand)
			if controllerLoc == nil then return nil end

            local targetLoc = nil
            local targetRot = nil
			local socketName = markerParams.socket_name or ""

            if socketName ~= "" and attachment.GetSocketLocation ~= nil then
				targetRot = attachment:GetSocketRotation(uevrUtils.fname_from_string(socketName))
                targetLoc = attachment:GetSocketLocation(uevrUtils.fname_from_string(socketName))
            elseif attachment.K2_GetComponentLocation ~= nil then
				targetRot = attachment:K2_GetComponentRotation()
                targetLoc = attachment:K2_GetComponentLocation()
            end

            if targetLoc ~= nil then
				local loc = uevrUtils.vector(markerParams.location or {0,0,0})
				if status["offhandOffset"] ~= nil and status["offhandOffset"][attachmentID] then
					local offhandOffset = uevrUtils.vector(status["offhandOffset"][attachmentID])
					if loc ~= nil and offhandOffset ~= nil then
						--print("Applying offhand offset for attachment ", attachmentID, offhandOffset.X, offhandOffset.Y, offhandOffset.Z)
						loc.X = loc.X + offhandOffset.X
						loc.Y = loc.Y + offhandOffset.Y
						loc.Z = loc.Z + offhandOffset.Z
					end
				end
				targetLoc = targetLoc + uevrUtils.rotateVector(loc, targetRot)
                local d = uevrUtils.distanceBetween(controllerLoc, targetLoc)
                if d ~= nil and d <= activationDistance then
                    if bestDistance == nil or d < bestDistance then
                        bestDistance = d
                        bestAccessoryID = accessoryID
                    end
                end
            end
        end
    end

    return bestAccessoryID
end

-- Feed proximity as another "opinion" into the same montage/preview resolution path.
uevrUtils.registerUEVRCallback("active_left_accessory", function()
	local id = proximityAccessoryForHand(Handed.Left)
    if id ~= nil then
        return id, PROXIMITY_ACCESSORY_PRIORITY
    end
end)

uevrUtils.registerUEVRCallback("active_right_accessory", function()
	local id = proximityAccessoryForHand(Handed.Right)
    if id ~= nil then
        return id, PROXIMITY_ACCESSORY_PRIORITY
    end
end)

local function checkAccessories(isMontage, animInstance, montageObject)
	local rawActiveRightAccessory, priority = executeIsRightAccessoryCallback()
	local rightMonitor = status["montageMonitor"] and status["montageMonitor"][Handed.Right]
	if rightMonitor ~= nil and rightMonitor["accessoryID"] ~= rawActiveRightAccessory then
		status["montageMonitor"][Handed.Right] = nil
	end
	local activeRightAccessory = rawActiveRightAccessory
	--M.print("Checked active right accessory: " .. tostring(activeRightAccessory) .. " with priority " .. tostring(priority))

	if status["montageMonitor"] and status["montageMonitor"][Handed.Right] and status["montageMonitor"][Handed.Right]["valid"] == false then
		activeRightAccessory = nil
	end
    if activeRightAccessory ~= accessoryStatus["activeRightAccessory"] then
        accessoryStatus["activeRightAccessory"] = activeRightAccessory
        M.print("Active right accessory changed to: " .. tostring(activeRightAccessory))
		local monitor = status["montageMonitor"] and status["montageMonitor"][Handed.Right]
		M.attachHandToAccessory(Handed.Right, activeRightAccessory, isMontage, animInstance or (monitor and monitor["animInstance"]), montageObject or (monitor and monitor["montageObject"]))
    end

	local rawActiveLeftAccessory, priority = executeIsLeftAccessoryCallback()
	local leftMonitor = status["montageMonitor"] and status["montageMonitor"][Handed.Left]
	if leftMonitor ~= nil and leftMonitor["accessoryID"] ~= rawActiveLeftAccessory then
		status["montageMonitor"][Handed.Left] = nil
	end
	local activeLeftAccessory = rawActiveLeftAccessory
	--M.print("Checked active left accessory: " .. tostring(activeLeftAccessory) .. " with priority " .. tostring(priority))
	if status["montageMonitor"] and status["montageMonitor"][Handed.Left] and status["montageMonitor"][Handed.Left]["valid"] == false then
		activeLeftAccessory = nil
	end
    if activeLeftAccessory ~= accessoryStatus["activeLeftAccessory"] then
        accessoryStatus["activeLeftAccessory"] = activeLeftAccessory
        M.print("Active left accessory changed to: " .. tostring(activeLeftAccessory))
		local monitor = status["montageMonitor"] and status["montageMonitor"][Handed.Left]
		M.attachHandToAccessory(Handed.Left, activeLeftAccessory, isMontage, animInstance or (monitor and monitor["animInstance"]), montageObject or (monitor and monitor["montageObject"]))
    end
end

local function activateMontageMonitor(montageObject, animInstance, accessoryID, accessoryParams, handed)
	status["montageMonitor"] = status["montageMonitor"] or {}
	status["montageMonitor"][handed] = {}
	status["montageMonitor"][handed]["montageObject"] = montageObject
	status["montageMonitor"][handed]["animInstance"] = animInstance
	status["montageMonitor"][handed]["accessoryID"] = accessoryID
	status["montageMonitor"][handed]["accessoryParams"] = accessoryParams
	status["montageMonitor"][handed]["valid"] = nil
	status["montageMonitor"][handed]["markerIndex"] = nil
end

local function checkSegmentedMontage(montageObject, montageName, label, animInstance)
	markerDebugPrint("[MarkerDebug] Montage change: montageName=" .. tostring(montageName) .. " label=" .. tostring(label))
	if animInstance == nil then
		print("Animation instance is nil in checkSegmentedMontage. Check comments in updateMontage() in uevrUtils")
	else
		local grippedAttachment = attachments.getCurrentGrippedAttachment(Handed.Right)
		local grippedAttachmentID = attachments.getAttachmentIDFromAttachment(grippedAttachment)
				local activeRightAccessory, priority = executeIsRightAccessoryCallback()
		markerDebugPrint("[MarkerDebug] active_right_accessory returned id=" .. tostring(activeRightAccessory) .. " priority=" .. tostring(priority))
		if activeRightAccessory ~= nil then
			local accessoryParams = (grippedAttachmentID ~= nil and grippedAttachmentID ~= "") and M.getAccessoryParamsForAttachment(grippedAttachmentID, activeRightAccessory) or nil
			if accessoryParams == nil then
				accessoryParams = M.getAccessoryParams(activeRightAccessory)
				if accessoryParams ~= nil then
					markerDebugPrint("[MarkerDebug] WARNING: Right accessoryID=" .. tostring(activeRightAccessory) .. " not found under attachmentID=" .. tostring(grippedAttachmentID) .. "; using global lookup")
				end
			end
			if accessoryParams ~= nil then
				if M.accessoryHasTimeMarkers(accessoryParams) then
					markerDebugPrint("[MarkerDebug] Activating montage monitor: hand=Right accessoryID=" .. tostring(activeRightAccessory))
					activateMontageMonitor(montageObject, animInstance, activeRightAccessory, accessoryParams, Handed.Right)
				else
					markerDebugPrint("[MarkerDebug] No time markers: hand=Right accessoryID=" .. tostring(activeRightAccessory))
					local markers = accessoryParams.markers
					if type(markers) == "table" and #markers > 0 then
						for idx, m in ipairs(markers) do
							markerDebugPrint("[MarkerDebug]  marker[" .. tostring(idx) .. "] start=" .. tostring(m.start_time) ..
								" end=" .. tostring(m.end_time) ..
								" socket=" .. tostring(m.socket_name) ..
								" grip_animation=" .. tostring(m.grip_animation))
						end
					end
				end
			else
				markerDebugPrint("[MarkerDebug] Accessory params nil: hand=Right accessoryID=" .. tostring(activeRightAccessory))
			end
		else
			markerDebugPrint("[MarkerDebug] No active accessory: hand=Right")
			local gripped = attachments.getCurrentGrippedAttachment(Handed.Right)
			local grippedName = (gripped ~= nil and gripped.get_full_name ~= nil) and gripped:get_full_name() or tostring(gripped)
			markerDebugPrint("[MarkerDebug] Current gripped attachment (Right hand)=" .. tostring(grippedName))
			markerDebugPrint("[MarkerDebug] Current gripped attachmentID=" .. tostring(attachments.getAttachmentIDFromAttachment(gripped)))
		end
		local activeLeftAccessory, priority = executeIsLeftAccessoryCallback()
		markerDebugPrint("[MarkerDebug] active_left_accessory returned id=" .. tostring(activeLeftAccessory) .. " priority=" .. tostring(priority))
		if activeLeftAccessory ~= nil then
			local accessoryParams = (grippedAttachmentID ~= nil and grippedAttachmentID ~= "") and M.getAccessoryParamsForAttachment(grippedAttachmentID, activeLeftAccessory) or nil
			if accessoryParams == nil then
				accessoryParams = M.getAccessoryParams(activeLeftAccessory)
				if accessoryParams ~= nil then
					markerDebugPrint("[MarkerDebug] WARNING: Left accessoryID=" .. tostring(activeLeftAccessory) .. " not found under attachmentID=" .. tostring(grippedAttachmentID) .. "; using global lookup")
				end
			end
			if accessoryParams ~= nil then
				if M.accessoryHasTimeMarkers(accessoryParams) then
					markerDebugPrint("[MarkerDebug] Activating montage monitor: hand=Left accessoryID=" .. tostring(activeLeftAccessory))
					activateMontageMonitor(montageObject, animInstance, activeLeftAccessory, accessoryParams, Handed.Left)
				else
					markerDebugPrint("[MarkerDebug] No time markers: hand=Left accessoryID=" .. tostring(activeLeftAccessory))
					local markers = accessoryParams.markers
					if type(markers) == "table" and #markers > 0 then
						for idx, m in ipairs(markers) do
							markerDebugPrint("[MarkerDebug]  marker[" .. tostring(idx) .. "] start=" .. tostring(m.start_time) ..
								" end=" .. tostring(m.end_time) ..
								" socket=" .. tostring(m.socket_name) ..
								" grip_animation=" .. tostring(m.grip_animation))
						end
					end
				end
			else
				markerDebugPrint("[MarkerDebug] Accessory params nil: hand=Left accessoryID=" .. tostring(activeLeftAccessory))
			end
		else
			markerDebugPrint("[MarkerDebug] No active accessory: hand=Left")
			local gripped = attachments.getCurrentGrippedAttachment(Handed.Right)
			local grippedName = (gripped ~= nil and gripped.get_full_name ~= nil) and gripped:get_full_name() or tostring(gripped)
			markerDebugPrint("[MarkerDebug] Current gripped attachment (Right hand)=" .. tostring(grippedName))
			markerDebugPrint("[MarkerDebug] Current gripped attachmentID=" .. tostring(attachments.getAttachmentIDFromAttachment(gripped)))
		end
	end
end

uevrUtils.registerUEVRCallback("on_module_montage_change", function(montageObject, montageName, label, animInstance)
	checkSegmentedMontage(montageObject, montageName, label, animInstance)

	checkAccessories(montageName ~= nil and montageName ~= "", animInstance, montageObject) --sending this param allows for montage based proximity checks
	if montageName == nil or montageName == "" then
		--montage ended, if we had a proximity override active, re-check proximity to see if we need to re-apply it
		-- accessoryStatus["leftProximityAnimationOverride"] = nil
		-- accessoryStatus["rightProximityAnimationOverride"] = nil
		status["montageMonitor"] = nil
		-- M.updateAnimationState(Handed.Left)
		-- M.updateAnimationState(Handed.Right)
	end
end)

-- Monitor for activation distance changes (since montage callbacks won't fire when proximity changes).
uevrUtils.setInterval(300, function()
	local isMontage = (status["montageMonitor"] ~= nil)
	checkAccessories(isMontage)
end)
-- ----------------------------------------------------------------

-- If an accessory marker has set an explicit grip animation (e.g. "sniper"),
-- that pose must trump montage-driven CopyPoseFromSkeletalComponent.
-- This must be accessory-scoped (NOT based on holdingAttachment, which is shared).
uevrUtils.registerUEVRCallback("is_hands_animating_from_mesh", function(hand)
	local gripOverride = accessoryStatus["gripAnimationOverride"]
	if type(gripOverride) ~= "table" then return end
	local entry = gripOverride[hand]
	if type(entry) ~= "table" or entry.active ~= true then return end
	local p = tonumber(entry.priority)
	if p == nil then p = 1 end
	return false, p
end)


uevrUtils.registerPostEngineTickCallback(function(engine, delta)
	if status["montageMonitor"] ~= nil then
		local changed = {
			[Handed.Left] = false,
			[Handed.Right] = false
		}
		for i = Handed.Left, Handed.Right do
			if status["montageMonitor"][i] ~= nil then
				local monitor = status["montageMonitor"][i]
				local valid = true
				local markerIndex = nil
				local accessoryID = monitor["accessoryID"]
				local accessoryParams = monitor["accessoryParams"]
				local montageObject = monitor["montageObject"]
				local animInstance = monitor["animInstance"]

				if accessoryID == nil then
					-- stop monitoring this hand
					status["montageMonitor"][i] = nil
				else
					local prevValid = monitor["valid"]
					local prevMarkerIndex = monitor["markerIndex"]
					local markerParams = nil
					markerParams, markerIndex = resolveAccessoryMarkerParamsForAttach(accessoryParams, true, animInstance, montageObject, nil, true)
					valid = (markerParams ~= nil)

					if prevValid ~= valid or prevMarkerIndex ~= markerIndex then
						monitor["valid"] = valid
						monitor["markerIndex"] = markerIndex
						changed[i] = true
					end

					if changed[i] then
						local currentTime = nil
						if animInstance ~= nil and montageObject ~= nil and animInstance.Montage_GetPosition ~= nil then
							local ok, t = pcall(function()
								return animInstance:Montage_GetPosition(montageObject)
							end)
							if ok then currentTime = t end
						end
						markerDebugPrint("[MarkerDebug] Monitor change: hand=" .. tostring(i) ..
							" accessoryID=" .. tostring(accessoryID) ..
							" time=" .. tostring(currentTime) ..
							" valid " .. tostring(prevValid) .. " -> " .. tostring(valid) ..
							" markerIndex " .. tostring(prevMarkerIndex) .. " -> " .. tostring(markerIndex))
						-- Apply changes even if accessoryID didn't change (marker swap).
						local shouldAttach = valid and accessoryID or nil
						M.attachHandToAccessory(i, shouldAttach, true, animInstance, montageObject, markerIndex)
						local key = (i == Handed.Right) and "activeRightAccessory" or "activeLeftAccessory"
						accessoryStatus[key] = shouldAttach
					end
				end
			end
		end
	end
end)

uevrUtils.registerPreLevelChangeCallback(function(level)
	accessoryStatus = {}
	status = {}
end)

uevrUtils.registerUEVRCallback("gunstock_transform_change", function(id, newLocation, newRotation, newOffhandLocationOffset)
	if status["offhandOffset"] == nil then status["offhandOffset"] = {} end
	status["offhandOffset"][id] = newOffhandLocationOffset
end)


-- Passing these functions through but modules can also just call accessories_config_dev directly.
function M.init(isDeveloperMode, logLevel, caller)
    accessoriesConfigDev.init(isDeveloperMode, logLevel, caller)
end

function M.getConfigWidgets(id, prefix, width)
    return accessoriesConfigDev.getConfigWidgets(id, prefix, width)
end

function M.createConfigCallbacks(id, prefix)
    accessoriesConfigDev.createConfigCallbacks(id, prefix)
end

return M