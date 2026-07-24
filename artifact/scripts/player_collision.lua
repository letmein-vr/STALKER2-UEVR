-- ---------------------------------------------------------------------------
-- Shrinks the player's physical collision capsule to allow getting closer
-- to objects/walls without being physically pushed back in VR.
-- Overrides the game's tendency to reset it during item pickups.
-- ---------------------------------------------------------------------------
local M = {}

local TARGET_RADIUS = 20.0

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
    local pawn = uevr.api:get_local_pawn(0)
    if not pawn then return end

    -- Access the primary CapsuleComponent of the ACharacter
    local capsule = pawn.CapsuleComponent
    if capsule then
        -- Read property directly. Standard radius is usually 42.0
        if capsule.CapsuleRadius ~= nil and math.abs(capsule.CapsuleRadius - TARGET_RADIUS) > 0.1 then
            -- SetCapsuleRadius is a BlueprintCallable method on UCapsuleComponent
            capsule:SetCapsuleRadius(TARGET_RADIUS, true)
        end
    end
end)

return M
