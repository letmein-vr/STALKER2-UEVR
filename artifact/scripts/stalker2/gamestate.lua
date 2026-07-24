local utils = require("common.utils")
local uevrUtils = require("libs/uevr_utils")

local GameStateManager = {
    -- State tracking
    inMenu = false,
    isInventoryPDA = false,
    initialized = false,
    last_level = nil,
    StaticMeshC = nil,
    isReloading = false,
    isTwoHanding = false,
    isDetectorEquipped = false,
    isMontageAttached = false,
    isClimbing = false,
    isConversation = false,
    isGuitarEquipped = false,
    isWeaponModMontageActive = false,
    isInCutscene = false,
    isWildcardMontageActive = false,
    isAnimMontagePlaying = false, -- Specifically for "AnimMontage" in name
    isGrenadeThrowMontageActive = false, -- Set by Entry.lua montage callback
    isAiming = false, -- New state to track ADS
    -- Cache for conversation camera optimization
    lastPawnAddress = nil,
    cachedConversationCamera = nil,
    -- UIManagerEx cache (for OpenViews-based menu detection)
    uiManager = nil,
    uiManagerClass = nil,
    -- Tick counters for throttling
    climbingTick = 0,
    inventoryTick = 0,
    guitarTick = 0,
    montageTick = 0,
    convTick = 0,
    cutsceneTick = 0,
    aimTick = 0,
    -- API reference
    api = nil
}

-- Initialize the GameStateManager
function GameStateManager:Init()
    self.api = uevr.api
    self.inMenu = false
    self.isInventoryPDA = false
    self.last_level = nil
    self.isDetectorEquipped = false
    self.isMontageAttached = false
    self.isClimbing = false
    self.isConversation = false
    self.isGuitarEquipped = false
    self.isInCutscene = false
    self.isGrenadeThrowMontageActive = false
    self.isWildcardMontageActive = false
    self.isAiming = false
    self.lastPawnAddress = nil
    self.cachedConversationCamera = nil
    self.uiManager = nil
    self.uiManagerClass = nil
    self.climbingTick = 0
    self.inventoryTick = 0
    self.guitarTick = 0
    self.montageTick = 0
    self.convTick = 0
    self.cutsceneTick = 0
    self.aimTick = 0
    self.conversationEndTicks = 0
    self.weaponCache = {} -- Cache for weapon details (Name, Scope)
    self.initialized = true
    self.StaticMeshC = utils.find_required_object("Class /Script/Engine.StaticMeshComponent")
    -- print("GameStateManager initialized")
end

-- Get Cached Weapon Info (Name, Scope)
function GameStateManager:GetWeaponCache(weaponMesh)
    if not weaponMesh then return nil end
    local address = weaponMesh:get_address()
    
    -- Ensure info table exists
    if not self.weaponCache[address] then
        self.weaponCache[address] = {}
        
        -- 1. Get Name (Only needs to happen once per weapon mesh address)
        if weaponMesh.SkeletalMesh then
             self.weaponCache[address].name = uevrUtils.getShortName(weaponMesh.SkeletalMesh)
        else
            local owner = weaponMesh:GetOwner()
            if owner then
                self.weaponCache[address].name = uevrUtils.getShortName(owner)
            end
        end
        -- 2. Cache Two-Handed Status
        self.weaponCache[address].isTwoHanded = true -- default
        if weaponMesh.AnimScriptInstance then
            local cl = weaponMesh.AnimScriptInstance:get_class()
            if cl then
                local className = cl:get_full_name()
                if className and string.find(className, "/Weapons/pt/", 1, true) then
                    self.weaponCache[address].isTwoHanded = false
                end
            end
        end
    end
    
    -- 3. Dynamically Update Scope (MUST check every time because attachments swap dynamically)
    local current_scope = self:get_scope_mesh(weaponMesh)
    self.weaponCache[address].scope = current_scope

    return self.weaponCache[address]
end

-- Reset the GameStateManager state
function GameStateManager:Reset()
    self:Init()
    self.climbingTick = 0
    -- print("GameStateManager reset")
end

-- Update function to be called on engine tick
function GameStateManager:Update()
    -- Resolve pawn and weapon ONCE per tick and cache them.
    -- All sub-functions read self._framePawn / self._frameWeapon instead of
    -- making their own C++ bridge calls, halving total round-trips per tick.
    self._framePawn   = self:GetLocalPawn()
    self._frameWeapon = self:GetEquippedWeapon()

    self:CheckMenuState()
    self:CheckInventoryPDAState()
    self:CheckClimbingState()
    self:CheckConversationState()
    self:CheckGuitarState()
    self:CheckAimingState() -- Check ADS state
    -- Throttled: Only re-check isInCutscene every 10 ticks (~100ms)
    self.cutsceneTick = self.cutsceneTick + 1
    if self.cutsceneTick % 10 == 0 then
        self.isInCutscene = uevrUtils.isInCutscene()
    end

    -- Failsafe: Cleanup wildcard state if no montage is playing
    -- Throttled to every 10 ticks to avoid per-frame string allocs
    self.montageTick = self.montageTick + 1
    if (self.isWildcardMontageActive or self.isAnimMontagePlaying) and self.montageTick % 10 == 0 then
        local p = self._framePawn  -- use cached pawn
        local currentMontage = (p and p.GetCurrentMontage) and p:GetCurrentMontage() or nil

        if not currentMontage then
            self.isWildcardMontageActive = false
            self.isAnimMontagePlaying = false
        else
            local mName = uevrUtils.getShortName(currentMontage)
            if mName and string.find(string.lower(mName), "animmontage") then
                self.isAnimMontagePlaying = true
            else
                self.isAnimMontagePlaying = false
            end
        end
    end
end

-- Check if the player is in a menu (pause menu, main menu, or loading screen).
-- Uses two instant signals via UIManagerEx.OpenViews and pawn presence:
--   1. OpenViews contains W_PauseMenuMainView_C  → pause menu
--   2. No active player pawn                     → main menu / loading screen
function GameStateManager:CheckMenuState()
    local uiMgr = self:GetUIManager()
    local hasPauseMenu = false
    if uiMgr then
        local openViews = uiMgr.OpenViews
        if openViews then
            for _, view in ipairs(openViews) do
                local ok, cls = pcall(function()
                    return view:get_class():get_fname():to_string()
                end)
                if ok then
                    if cls == "W_PauseMenuMainView_C" then hasPauseMenu = true end
                end
            end
        end
    end

    -- 1. Pause menu
    if hasPauseMenu then
        self.inMenu = true
        return
    end

    -- 2. Main menu / loading screen: no active player pawn exists
    if not self._framePawn then
        self.inMenu = true
        return
    end

    self.inMenu = false
end

-- Get or find the live UIManagerEx instance (cached per session)
function GameStateManager:GetUIManager()
    -- Return cached instance if still valid
    if self.uiManager and utils.validate_object(self.uiManager) then
        return self.uiManager
    end
    self.uiManager = nil
    -- Find class once
    if not self.uiManagerClass then
        self.uiManagerClass = uevr.api:find_uobject("Class /Script/Stalker2.UIManagerEx")
    end
    if not self.uiManagerClass then return nil end
    -- Iterate instances, skip CDO
    local instances = UEVR_UObjectHook.get_objects_by_class(self.uiManagerClass, false)
    for _, inst in ipairs(instances) do
        if not string.find(inst:get_full_name(), "Default__") then
            self.uiManager = inst
            return inst
        end
    end
    return nil
end

-- Check if player is in inventory, PDA, storage/stash, or trader menu
-- Primary: UIManagerEx.OpenViews (covers W_Inventory_C, W_PDABookView_C, W_Trade_C)
-- Fallback: HandItemData triple-flag (original method, if UIManagerEx unavailable)
-- Optimized: Runs every 2 ticks (approx 20ms) to ensure instantaneous detection
function GameStateManager:CheckInventoryPDAState()
    self.inventoryTick = self.inventoryTick + 1
    if self.inventoryTick % 2 ~= 0 then
        return -- Skip check, maintain previous state
    end

    -- Primary: UIManagerEx.OpenViews
    -- Covers: player backpack, storage box/stash (W_Inventory_C),
    --         PDA/Journal (W_PDABookView_C), Trader (W_Trade_C)
    local uiMgr = self:GetUIManager()
    if uiMgr then
        local openViews = uiMgr.OpenViews
        if openViews then
            for _, view in ipairs(openViews) do
                local ok, cls = pcall(function()
                    return view:get_class():get_fname():to_string()
                end)
                if ok and cls then
                    if cls == "W_Inventory_C"   -- Player backpack, storage box, stash
                    or cls == "W_PDABookView_C" -- PDA / Journal
                    or cls == "W_Trade_C" then  -- Trader menu
                        self.isInventoryPDA = true
                        return
                    end
                end
            end
        end
        self.isInventoryPDA = false
        return
    end

    -- Fallback: HandItemData triple-flag (used when UIManagerEx is unavailable)
    -- Guard: any equipped weapon trips all three flags simultaneously → false positive
    local weaponMesh = self._frameWeapon  -- use cached weapon (resolved once in Update)
    if weaponMesh then
        self.isInventoryPDA = false
        return
    end

    local pawn = self._framePawn  -- use cached pawn
    if pawn and pawn.Mesh and pawn.Mesh.AnimScriptInstance and
       pawn.Mesh.AnimScriptInstance.HandItemData then
        local check1 = pawn.Mesh.AnimScriptInstance.HandItemData.bHasItemInHands
        local check2 = pawn.Mesh.AnimScriptInstance.HandItemData.bIsUsesLeftHand
        local check3 = pawn.Mesh.AnimScriptInstance.HandItemData.bIsUsesRightHand
        if check1 and check2 and check3 then
            self.isInventoryPDA = true
        else
            self.isInventoryPDA = false
        end
    end
end
 
-- Check if player is aiming (ADS)
-- Throttled to every 3 ticks: ADS transitions are input-driven (slow), sub-frame precision not needed
function GameStateManager:CheckAimingState()
    self.aimTick = self.aimTick + 1
    if self.aimTick % 3 ~= 0 then return end
    local pawn = self._framePawn  -- use cached pawn
    if pawn and pawn.Mesh and pawn.Mesh.AnimScriptInstance and 
       pawn.Mesh.AnimScriptInstance.WeaponData and 
       pawn.Mesh.AnimScriptInstance.WeaponData.AimingData then
        self.isAiming = pawn.Mesh.AnimScriptInstance.WeaponData.AimingData.bAiming or false
    else
        self.isAiming = false
    end
end

-- Check if player is climbing a ladder
-- Optimized: Runs every 10 ticks (approx 100ms)
function GameStateManager:CheckClimbingState()
    self.climbingTick = self.climbingTick + 1
    if self.climbingTick % 10 ~= 0 then
        return -- Skip check, maintain previous state
    end

    self.isClimbing = false
    local pawn = self._framePawn  -- use cached pawn
    if pawn and pawn.Mesh and pawn.Mesh.AnimScriptInstance then
        local animInstance = pawn.Mesh.AnimScriptInstance
        
        -- Attempt to access ClimbingData via reflection
        local climbingData = animInstance["ClimbingData"]
        if climbingData then
            -- bAnimClimbStarted is a boolean property in this struct
            if climbingData["bAnimClimbStarted"] == true then
                self.isClimbing = true
            end
        end
    end
end

-- Check if guitar is equipped
-- Throttled to every 30 ticks (~300ms): guitar equip/unequip is slow, sub-frame precision not needed
function GameStateManager:CheckGuitarState()
    self.guitarTick = self.guitarTick + 1
    if self.guitarTick % 30 ~= 0 then return end
    -- 1. Check standard weapon path (uses cached weapon)
    local weaponMesh = self._frameWeapon
    if weaponMesh then
        local wInfo = self:GetWeaponCache(weaponMesh)
        if wInfo and wInfo.name and string.find(string.lower(wInfo.name), "guitar") then
            -- if not self.isGuitarEquipped then print("[GameState] Guitar detected via WeaponData") end
            self.isGuitarEquipped = true
            return
        end
    end

    -- 2. Check "In Hands" mesh (Detectors, Guitars, etc) — pass cached pawn to avoid re-fetch
    local handMesh = self:GetWeaponInHandsMesh(self._framePawn)
    if handMesh then
        local wInfo = self:GetWeaponCache(handMesh)
        if wInfo and wInfo.name and string.find(string.lower(wInfo.name), "guitar") then
            -- if not self.isGuitarEquipped then print("[GameState] Guitar detected via HandItemData") end
            self.isGuitarEquipped = true
            return
        end
    end
    
    -- 3. Check for "Guitar" component path (fallback)
    local pawn = self._framePawn  -- use cached pawn
    if pawn then
        -- Collect all potential meshes
        local components = {}
        if pawn.Mesh then table.insert(components, pawn.Mesh) end
        
        -- Add all child components of Mesh and Root
        local pMesh = pawn.Mesh
        if pMesh and pMesh.AttachChildren then
            for _, child in ipairs(pMesh.AttachChildren) do table.insert(components, child) end
        end
        local pRoot = pawn.RootComponent
        if pRoot and pRoot.AttachChildren then
            for _, child in ipairs(pRoot.AttachChildren) do table.insert(components, child) end
        end
        
        -- Scan names AND asset paths
        for _, comp in ipairs(components) do
            local name = comp:get_fname():to_string()
            local lowerName = string.lower(name)
            
            -- Check 1: Component name contains "guitar" or "WeaponInHandsMesh"
            local isPotentiallyGuitar = string.find(lowerName, "guitar") or string.find(lowerName, "weaponinhandsmesh")
            
            if isPotentiallyGuitar then
                -- Check 2: Verify underlying asset path for "guitar"
                local assetPath = ""
                if comp.SkeletalMesh then
                    assetPath = string.lower(comp.SkeletalMesh:get_full_name())
                elseif comp.StaticMesh then
                    assetPath = string.lower(comp.StaticMesh:get_full_name())
                end

                if string.find(assetPath, "guitar") then
                    -- if not self.isGuitarEquipped then print("[GameState] Guitar detected via Asset Path: " .. assetPath .. " (Comp: " .. name .. ")") end
                    self.isGuitarEquipped = true
                    return
                end
            end
        end

        -- 3. Check Attached Actors
        -- (This is a bit more expensive/complex in LuaVR/UEVR sometimes)
        -- But let's try searching children for Actor wrappers if they exist
    end

    if self.isGuitarEquipped then print("[GameState] Guitar lost") end
    self.isGuitarEquipped = false
end

-- Check if player is in a conversation (zoomed FOV)
-- Optimized with caching to avoid per-frame component scanning
-- Throttled to every 5 ticks (~50ms): fast enough to feel instant, reduces FOV bridge calls
function GameStateManager:CheckConversationState()
    -- Config guard FIRST: ensures isConversation is always reset when feature is disabled,
    -- even on skipped ticks (prevents aim method getting stuck in wrong state)
    if not Config.enableConversationFix then
        self.isConversation = false
        return
    end
    self.convTick = self.convTick + 1
    if self.convTick % 5 ~= 0 then return end

    -- Use frame-cached weapon/pawn resolved once at the top of Update() to avoid
    -- redundant C++ bridge calls (GetEquippedWeapon calls GetLocalPawn internally).
    local throwableMesh = self._frameWeapon
    if throwableMesh then
        local tInfo = self:GetWeaponCache(throwableMesh)
        if tInfo and tInfo.name then
            local n = string.lower(tInfo.name)
            if n:find("bolt") or n:find("knife") or n:find("sk_f1") or n:find("sk_rgd") or n:find("grenade") then
                self.isConversation = false
                self.conversationEndTicks = 31
                return
            end
        end
    end

    local pawn = self._framePawn
    if not pawn then
        self.isConversation = false
        self.cachedConversationCamera = nil
        self.lastPawnAddress = nil
        return
    end


    -- Check if pawn identity changed (respawn, load, etc.)
    local pawnAddress = pawn:get_address()
    if pawnAddress ~= self.lastPawnAddress then
        self.cachedConversationCamera = nil
        self.lastPawnAddress = pawnAddress
        self.conversationEndTicks = 0
        -- print("[UEVR] Pawn changed, invalidated conversation camera cache")
    end

    -- 1. Try PlayerCameraManager (Recommended for UE5)
    local playerController = pawn.Controller
    if playerController ~= nil then
        local cameraManager = playerController.PlayerCameraManager
        if cameraManager ~= nil then
             local fov = cameraManager.FOVAngle
             if fov and type(fov) == "number" and fov > 0 then
                 local threshold = Config.conversationFOVThreshold or 71.0
                 -- IGNORE FOV drop if player is aiming (ADS)
                 if self.isAiming then 
                     self.isConversation = false
                     self.conversationEndTicks = 31 -- reset end ticks
                     return
                 end
                 -- IGNORE FOV drop during grenade throw (arming zooms camera below threshold)
                 if self.isGrenadeThrowMontageActive then
                     self.isConversation = false
                     self.conversationEndTicks = 31
                     return
                 end

                 if fov < threshold then
                     self.isConversation = true
                     self.conversationEndTicks = 0
                 else
                     -- Hysteresis: wait ~0.5s before assuming conversation ended
                     self.conversationEndTicks = (self.conversationEndTicks or 0) + 1
                     if self.conversationEndTicks > 30 then
                         self.isConversation = false
                     end
                 end
                 return -- Using PCM is usually sufficient and more reliable
             end
        end
    end

    -- 2. Fallback: Try Cached Camera
    if self.cachedConversationCamera then
        local fov = self.cachedConversationCamera["FieldOfView"]
        if fov and type(fov) == "number" then
            local threshold = Config.conversationFOVThreshold or 71.0
            if fov < threshold then
                self.isConversation = true
                self.conversationEndTicks = 0
            else
                self.conversationEndTicks = (self.conversationEndTicks or 0) + 1
                if self.conversationEndTicks > 30 then
                    self.isConversation = false
                end
            end
            return -- Success, skip scan
        else
            -- Cache invalid (component destroyed?), force rescan
            self.cachedConversationCamera = nil
        end
    end
    
    -- 3. Scan for Camera (if cache empty or invalid)
    if pawn.Mesh then
        -- Helper to check a component and populate cache if found
        local function checkComp(comp)
            if not comp then return false end
            local name = comp:get_fname():to_string()
            
            if string.find(name, "Camera") then
                 local fov = comp["FieldOfView"]
                 if fov and type(fov) == "number" then
                     -- Found a valid camera, cache it!
                     self.cachedConversationCamera = comp
                     
                     local threshold = Config.conversationFOVThreshold or 71.0
                     -- print("Found Camera: " .. name .. " | FOV: " .. tostring(fov) .. " | Thresh: " .. tostring(threshold))
                     if fov < threshold then
                         return true
                     end
                 end
            end
            return false
        end

        local foundCamera = false

        -- Scan RootComponent Children
        if pawn.RootComponent and pawn.RootComponent.AttachChildren then
            for _, child in ipairs(pawn.RootComponent.AttachChildren) do
                if checkComp(child) then
                    self.isConversation = true
                    foundCamera = true
                    return
                end
            end
        end
        
        -- Scan Mesh Attach Children
        if not foundCamera and pawn.Mesh and pawn.Mesh.AttachChildren then
             for _, child in ipairs(pawn.Mesh.AttachChildren) do
                if checkComp(child) then
                    self.isConversation = true
                    foundCamera = true
                    return
                end
            end
        end
        
        -- Direct Reflection fallback
        if not foundCamera then
             local camComp = pawn["Camera"]
             if checkComp(camComp) then
                 self.isConversation = true
                 return
             end
        end
    end
    
    self.isConversation = false
end


function GameStateManager:is_scope_active(pawn)
    if not pawn then return false end
    local optical_scope = pawn.PlayerOpticScopeComponent
    if not optical_scope then return false end
    local scope_active = optical_scope:read_byte(0xA8, 1)
    if scope_active > 0 then
        return true
    end
    return false
end

function GameStateManager:get_scope_mesh(parent_mesh)
    if not parent_mesh then return nil end

    local child_components = parent_mesh.AttachChildren
    if not child_components then return nil end
    
    local sm_class = self.StaticMeshC
    if not sm_class then
        local utils = require("common.utils")
        sm_class = utils.find_required_object("Class /Script/Engine.StaticMeshComponent")
    end

    -- Single-pass: prefer component with OpticCutoutSocket, fall back to first scope found
    -- Bug D fix: search grandchildren too so nested scopes (on rails) are found.
    local fallback = nil
    for _, component in ipairs(child_components) do
        if sm_class and component:is_a(sm_class) and string.find(component:get_fname():to_string(), "scope") then
            if component:DoesSocketExist("OpticCutoutSocket") then
                return component  -- best match, return immediately
            elseif not fallback then
                fallback = component  -- keep first scope as fallback
            end
        end
        -- Search one level deeper (grandchildren) — handles scopes on rails/silencers
        if component and component.AttachChildren then
            for _, grandchild in ipairs(component.AttachChildren) do
                if sm_class and grandchild:is_a(sm_class) and string.find(grandchild:get_fname():to_string(), "scope") then
                    if grandchild:DoesSocketExist("OpticCutoutSocket") then
                        return grandchild
                    elseif not fallback then
                        fallback = grandchild
                    end
                end
            end
        end
    end
    return fallback
end

function GameStateManager:get_all_scope_meshes(parent_mesh)
    local scope_meshes = {}
    if not parent_mesh then return scope_meshes end

    local child_components = parent_mesh.AttachChildren
    if not child_components then return scope_meshes end
    
    local sm_class = self.StaticMeshC
    if not sm_class then
        local utils = require("common.utils")
        sm_class = utils.find_required_object("Class /Script/Engine.StaticMeshComponent")
    end

    for _, component in ipairs(child_components) do
        if sm_class and component:is_a(sm_class) and string.find(component:get_fname():to_string(), "scope") then
            table.insert(scope_meshes, component)
        end
    end

    return scope_meshes
end

function GameStateManager:get_weapon_attachment_mesh(pawn)
    if not pawn then return nil end

    -- Inline helper: check one component against attachment name/socket criteria
    local function checkComp(component)
        local compName = component:get_fname():to_string()
        -- Check 1: Name-based (transient silencer/sight meshes carry WeaponAttachment in name)
        if string.find(compName, "WeaponAttachment") and
           (string.find(compName, "silen") or string.find(compName, "sight") or string.find(compName, "scope")) then
            -- print("[Debug] Found Attachment Mesh by Name: " .. compName)
            return component
        end
        -- Check 2: Socket-based fallback
        if component:is_a(self.StaticMeshC) and component.AttachSocketName then
            local socketName = component.AttachSocketName:to_string()
            if socketName == "jnt_l_weapon" then
                -- print("[Debug] Found Attachment Mesh by Socket: " .. compName)
                return component
            end
        end
        return nil
    end

    -- Scan RootComponent children directly (no intermediate table)
    if pawn.RootComponent and pawn.RootComponent.AttachChildren then
        for _, comp in ipairs(pawn.RootComponent.AttachChildren) do
            local result = checkComp(comp)
            if result then return result end
        end
    end

    -- Scan Mesh children directly
    if pawn.Mesh and pawn.Mesh.AttachChildren then
        for _, comp in ipairs(pawn.Mesh.AttachChildren) do
            local result = checkComp(comp)
            if result then return result end
        end
    end

    return nil
end

-- Get current world time
function GameStateManager:GetWorldTime()
    local engine = self.api:get_engine()
    if engine and engine.GameViewport and engine.GameViewport.World and
       engine.GameViewport.World.GameState then
        return engine.GameViewport.World.GameState.ReplicatedWorldTimeSeconds
    end
    return 0
end

-- Get local player pawn
function GameStateManager:GetLocalPawn()
    return self.api:get_local_pawn(0)
end

function GameStateManager:IsLevelChanged(engine)
    local viewport = engine.GameViewport
    if viewport then
        local world = viewport.World
        if world then
            local level = world.PersistentLevel
            if self.last_level ~= level then
                self.last_level = level
                return true
            end
        end
    end
    return false
end

-- Send a key press (down or up)
function GameStateManager:SendKeyPress(key_value, key_up)
    local key_up_string = "down"
    if key_up == true then
        key_up_string = "up"
    end

    -- Specialized handling for Reload: Pulse the key once to the game, but keep state for hand attachment
    if key_value == 'R' then
        if not key_up then
            -- Trigger once (Pulse)
            self.api:dispatch_custom_event(key_value, "down")
            self.api:dispatch_custom_event(key_value, "up")
            self.isReloading = true
        else
            -- Release internal state only
            self.isReloading = false
        end
        return -- Handled
    end

    self.api:dispatch_custom_event(key_value, key_up_string)
end

-- Send key down
function GameStateManager:SendKeyDown(key_value)
    self:SendKeyPress(key_value, false)
end

-- Send key up
function GameStateManager:SendKeyUp(key_value)
    self:SendKeyPress(key_value, true)
end

-- Pulse R to the game WITHOUT setting isReloading.
-- Used by the physical X-button → R mapping so the game gets its reload key
-- but the VR hand attachment logic is NOT triggered. Hand attachment only fires
-- when a genuine mag-gesture reload sets isReloading via SendKeyDown('R').
function GameStateManager:SendReloadKey()
    self.api:dispatch_custom_event('R', 'down')
    self.api:dispatch_custom_event('R', 'up')
    -- isReloading intentionally NOT set here.
end

-- Get current equipped weapon
function GameStateManager:GetEquippedWeapon()
    local pawn = self:GetLocalPawn()
    if not pawn then return nil end
    local sk_mesh = pawn.Mesh
    if not sk_mesh then return nil end
    local anim_instance = sk_mesh.AnimScriptInstance
    if not anim_instance then return nil end
    -- Guard WeaponData: can be nil during cutscenes, death, or level transitions
    local weapon_data = anim_instance.WeaponData
    if not weapon_data then return nil end
    local weapon_mesh = weapon_data.WeaponMesh
    return weapon_mesh
end

-- Get current weapon in hands mesh (for items like guitar/detector)
-- Optional cachedPawn: pass self._framePawn to avoid a redundant GetLocalPawn() bridge call
function GameStateManager:GetWeaponInHandsMesh(cachedPawn)
    local pawn = cachedPawn or self:GetLocalPawn()
    if not pawn then return nil end
    local sk_mesh = pawn.Mesh
    if not sk_mesh then return nil end
    local anim_instance = sk_mesh.AnimScriptInstance
    if not anim_instance then return nil end
    
    -- ItemMesh in HandItemData struct
    if anim_instance.HandItemData and anim_instance.HandItemData.WeaponMesh then
        return anim_instance.HandItemData.WeaponMesh
    end
    return nil

end

-- Get game engine
function GameStateManager:GetEngine()
    return self.api:get_engine()
end

-- Create a new instance
function GameStateManager:new()
    local instance = {}
    setmetatable(instance, self)
    self.__index = self
    instance:Init()
    return instance
end

return GameStateManager
