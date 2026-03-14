-- Common test helpers for UEVR Lua tests
local TestHelpers = {
    preEngineTickCallback = nil,
    scriptResetCallback = nil,
    xinputStateCallback = nil,
    leftHandComponent = nil,
    rightHandComponent = nil,
    keyEvents = {},
    hapticEvents = {}, -- Track haptic feedback events
    gamepadState = {
        Gamepad = {
            wButtons = 0,
            bLeftTrigger = 0,
            bRightTrigger = 0,
            sThumbLX = 0,
            sThumbLY = 0,
            sThumbRX = 0,
            sThumbRY = 0
        }
    }
}

-- Mock UEVR_UObjectHook
_G.UEVR_UObjectHook = {
    on_post_uobject_hook = function(callback)
        return true
    end,
    get_or_add_motion_controller_state = function()
        return {
            motionSource = "motionSource",
            renderComponent = {},
            hand = 0,
            set_hand = function(self, hand)
                self.hand = hand
            end,
            set_permanent = function(self, permanent)
                self.permanent = permanent
            end
        }
    end,
    exists = function() return true end
}

-- Mock Vector3f
_G.Vector3f = {
    new = function(x, y, z)
        return {x = x or 0, y = y or 0, z = z or 0}
    end
}

-- Hand state variables that can be modified before each test
TestHelpers.handStates = {
    left = {
        location = Vector3f.new(0, 0, 0),
        rotation = Vector3f.new(0, 0, 0),
        gripActive = false
    },
    right = {
        location = Vector3f.new(0, 0, 0),
        rotation = Vector3f.new(0, 0, 0),
        gripActive = false
    },
    hmd = {
        location = Vector3f.new(0, 0, 0),
        rotation = Vector3f.new(0, 0, 0)
    }
}

-- Mock StructObject for Vector3f operations
_G.StructObject = {
    new = function(self)
        return {
            Translation = Vector3f.new(0, 0, 0),
            Rotation = {
                X = 0,
                Y = 0,
                Z = 0,
                W = 1
            },
            Scale3D = Vector3f.new(1, 1, 1)
        }
    end
}

-- Create mock static classes that will be returned by find_static_class
local mockStatics = {
    BeginDeferredActorSpawnFromClass = function(self, world_context, actor_class, transform, collision_method, owner)
        return {
            K2_DestroyActor = function() end
        }
    end,
    FinishSpawningActor = function(self, actor, transform)
        return actor
    end,
    Conv_StringToName = function(self, str)
        return str
    end
}

-- Mock required objects that will be returned by find_required_object
local mockRequiredObject = {
    name = "MockObject",
    position = Vector3f.new(0, 0, 0),
    getComponent = function(self, componentName)
        return {
            name = componentName,
            enabled = true,
            setEnabled = function(enabled) end
        }
    end
}

-- Override package.loaded to provide our mocked modules
package.loaded["common.utils"] = {
    find_required_object = function(path)
        return mockRequiredObject
    end,
    find_static_class = function(path)
        return mockStatics
    end
}

-- Set up mock UEVR SDK with API
_G.uevr = {
    sdk = {
        callbacks = {
            on_pre_engine_tick = function(callback)
                TestHelpers.preEngineTickCallback = callback
                return true
            end,
            on_script_reset = function(callback)
                TestHelpers.scriptResetCallback = callback
                return true
            end,
            on_xinput_get_state = function(callback)
                TestHelpers.xinputStateCallback = callback
                return true
            end
        }
    },
    api = {
        find_uobject = function(path)
            return {
                get_full_name = function() return path end,
                get_class = function() return "MockClass" end,
                is_valid = function() return true end,
                get_class_default_object = function()
                    return {
                        get_full_name = function() return "MockClass_CDO" end,
                        get_class = function() return "MockClass" end,
                        is_valid = function() return true end
                    }
                end,
                K2_GetActorLocation = function()
                    return Vector3f.new(0, 0, 0)
                end
            }
        end,
        get_engine = function()
            return TestHelpers.mockEngine
        end,
        get_local_pawn = function(index)
            return {
                K2_GetActorLocation = function()
                    return Vector3f.new(0, 0, 0)
                end
            }
        end,
        add_component_by_class = function(actor, class)
            local component = {
                K2_GetComponentLocation = function(self)
                    if self.MotionSource == "Left" then  -- Left hand
                        return TestHelpers.handStates.left.location
                    elseif self.MotionSource == "Right" then
                        return TestHelpers.handStates.right.location
                    else
                        return TestHelpers.handStates.hmd.location
                    end
                end,
                K2_GetComponentRotation = function(self)
                    if actor.Hand == 0 then  -- Left hand
                        return TestHelpers.handStates.left.rotation
                    else  -- Right hand
                        return TestHelpers.handStates.right.rotation
                    end
                end,
                MotionSource = "",
                Hand = actor.Hand or 0,
                isActive = true  -- Ensure the component is marked as active
            }
            
            -- Store components for test manipulation
            if actor.Hand == 0 then
                TestHelpers.leftHandComponent = component
            else
                TestHelpers.rightHandComponent = component
            end
            
            return component
        end,
        dispatch_custom_event = function(instance, eventName, params)
            local key = eventName  .. "_" .. params  
            if not TestHelpers.keyEvents[key] then
                TestHelpers.keyEvents[key] = 0
            end
            TestHelpers.keyEvents[key] = TestHelpers.keyEvents[key] + 1 
        end,
    },
    params = {
        vr = {
            get_action_handle = function(handle_name)
                return handle_name
            end,
            get_left_joystick_source = function()
                return "left_joystick"
            end,
            get_right_joystick_source = function()
                return "right_joystick"
            end,
            is_action_active = function(handle, controller)
                if handle == "/actions/default/in/Grip" then
                    if controller == "left_joystick" then
                        return TestHelpers.handStates.left.gripActive
                    elseif controller == "right_joystick" then
                        return TestHelpers.handStates.right.gripActive
                    end
                end
                return false
            end,
            trigger_haptic_vibration = function(start_delay, duration, frequency, amplitude, controller)
                TestHelpers.hapticEvents[controller] = (TestHelpers.hapticEvents[controller] or 0) + 1
                return true
            end
        }
    }
}

-- Create mock engine for testing with proper GameViewport structure
TestHelpers.mockEngine = {
    deltaTime = 0.016,
    GameViewport = {
        World = {
            actors = {},
            getActor = function(self, id)
                return self.actors[id]
            end,
            addActor = function(self, actor)
                self.actors[actor.id] = actor
            end,
            removeActor = function(self, id)
                self.actors[id] = nil
            end
        }
    }
}

-- Reset test state before each test
function TestHelpers.resetTestState()
    -- Reset hand states to default positions
    TestHelpers.handStates.left.location = Vector3f.new(0, 0, 0)
    TestHelpers.handStates.left.rotation = Vector3f.new(0, 0, 0)
    TestHelpers.handStates.left.gripActive = false
    
    TestHelpers.handStates.right.location = Vector3f.new(0, 0, 0)
    TestHelpers.handStates.right.rotation = Vector3f.new(0, 0, 0)
    TestHelpers.handStates.right.gripActive = false
    
    TestHelpers.handStates.hmd.location = Vector3f.new(0, 0, 0)
    TestHelpers.handStates.hmd.rotation = Vector3f.new(0, 0, 0)
    TestHelpers.keyEvents = {}
    TestHelpers.hapticEvents = {} -- Reset haptic events

    -- Reset gamepad state
    TestHelpers.gamepadState = {
        Gamepad = {
            wButtons = 0,
            bLeftTrigger = 0,
            bRightTrigger = 0,
            sThumbLX = 0,
            sThumbLY = 0,
            sThumbRX = 0,
            sThumbRY = 0
        }
    }
end

return TestHelpers