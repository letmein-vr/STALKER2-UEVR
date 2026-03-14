#include <iostream>

#include "Plugin.hpp"
#include "glm/fwd.hpp"
#include "utility/Module.hpp"
#include "utility/Scan.hpp"

using namespace uevr;

std::unique_ptr<Stalker2VR> g_plugin = std::make_unique<Stalker2VR>();

namespace SDK {
    enum class ERelativeTransformSpace : uint8_t
    {
        RTS_World                                = 0,
        RTS_Actor                                = 1,
        RTS_Component                            = 2,
        RTS_ParentBoneSpace                      = 3,
        RTS_MAX                                  = 4,
    };

    struct FQuat
    {
        double X;
        double Y;
        double Z;
        double W;
    };
    struct FVector
    {
        double X;
        double Y;
        double Z;
    };
    struct FTransform
    {
        FQuat Rotation;
        FVector Translation;
        unsigned __int8 Pad_38[8];
        FVector Scale3D;
        unsigned __int8 Pad_58[8];
    };

    struct SceneComponent_GetSocketTransform final
    {
        API::FName                                   InSocketName;                                      // 0x0000(0x0008)(Parm, ZeroConstructor, IsPlainOldData, NoDestructor, HasGetValueTypeHash, NativeAccessSpecifierPublic)
        ERelativeTransformSpace                       TransformSpace;                                    // 0x0008(0x0001)(Parm, ZeroConstructor, IsPlainOldData, NoDestructor, HasGetValueTypeHash, NativeAccessSpecifierPublic)
        uint8_t                                         Pad_9[0x7];                                        // 0x0009(0x0007)(Fixing Size After Last Property [ Dumper-7 ])
        FTransform                             ReturnValue;                                       // 0x0010(0x0060)(Parm, OutParm, ReturnParm, IsPlainOldData, NoDestructor, HasGetValueTypeHash, NativeAccessSpecifierPublic)
    };
    static_assert(sizeof(SceneComponent_GetSocketTransform) == 0x70, "Size mismatch");
    static_assert(offsetof(SceneComponent_GetSocketTransform, ReturnValue) == 0x10, "Offset mismatch");

    struct SceneComponent_GetSocketLocation final
    {
    public:
        API::FName                                   InSocketName;                                      // 0x0000(0x0008)(Parm, ZeroConstructor, IsPlainOldData, NoDestructor, HasGetValueTypeHash, NativeAccessSpecifierPublic)
        FVector                                ReturnValue;                                       // 0x0008(0x0018)(Parm, OutParm, ZeroConstructor, ReturnParm, IsPlainOldData, NoDestructor, HasGetValueTypeHash, NativeAccessSpecifierPublic)
    };
    static_assert(alignof(SceneComponent_GetSocketLocation) == 0x000008, "Wrong alignment on SceneComponent_GetSocketLocation");
    static_assert(sizeof(SceneComponent_GetSocketLocation) == 0x000020, "Wrong size on SceneComponent_GetSocketLocation");
    static_assert(offsetof(SceneComponent_GetSocketLocation, InSocketName) == 0x000000, "Member 'SceneComponent_GetSocketLocation::InSocketName' has a wrong offset!");
    static_assert(offsetof(SceneComponent_GetSocketLocation, ReturnValue) == 0x000008, "Member 'SceneComponent_GetSocketLocation::ReturnValue' has a wrong offset!");

    // Function Engine.SceneComponent.GetSocketQuaternion
    // 0x0030 (0x0030 - 0x0000)
    struct alignas(0x10) SceneComponent_GetSocketQuaternion final
    {
    public:
        API::FName                                   InSocketName;                                      // 0x0000(0x0008)(Parm, ZeroConstructor, IsPlainOldData, NoDestructor, HasGetValueTypeHash, NativeAccessSpecifierPublic)
        uint8_t                                         Pad_8[0x8];                                        // 0x0008(0x0008)(Fixing Size After Last Property [ Dumper-7 ])
        FQuat                                  ReturnValue;                                       // 0x0010(0x0020)(Parm, OutParm, ReturnParm, IsPlainOldData, NoDestructor, HasGetValueTypeHash, NativeAccessSpecifierPublic)
    };
    static_assert(alignof(SceneComponent_GetSocketQuaternion) == 0x000010, "Wrong alignment on SceneComponent_GetSocketQuaternion");
    static_assert(sizeof(SceneComponent_GetSocketQuaternion) == 0x000030, "Wrong size on SceneComponent_GetSocketQuaternion");
    static_assert(offsetof(SceneComponent_GetSocketQuaternion, InSocketName) == 0x000000, "Member 'SceneComponent_GetSocketQuaternion::InSocketName' has a wrong offset!");
    static_assert(offsetof(SceneComponent_GetSocketQuaternion, ReturnValue) == 0x000010, "Member 'SceneComponent_GetSocketQuaternion::ReturnValue' has a wrong offset!");

}


Stalker2VR::~Stalker2VR() {

}

bool is_scope_active() {
    auto pawn = API::get()->get_local_pawn(0);
    if(!pawn) return false;
    auto scope_component = pawn->get_property_data(L"PlayerOpticScopeComponent");
    if(!scope_component) return false;
    auto scope_active = *(uint8_t*)(*(uintptr_t*)scope_component + 0xA8);
    return scope_active;
}

bool level_changed(API::UEngine* engine) {
    static API::UObject* last_level = nullptr;
    if(!engine) return false;

    auto viewport_client = engine->get_property<API::UObject*>(L"GameViewport");
    if(!viewport_client) return false;
    auto world = viewport_client->get_property<API::UObject*>(L"World");
    if(!world) return false;
    auto level = world->get_property<API::UObject*>(L"PersistentLevel");
    if(level != last_level) {
        last_level = level;
        return true;
    }
    return false;
}

API::UObject* get_weapon_in_hands() {
    struct {
        API::UClass* c;
        API::TArray<API::UObject*> return_value{};
    } component_params;
    component_params.c = API::get()->find_uobject<API::UClass>(L"Class /Script/Engine.SkeletalMeshComponent");

    const auto pawn = API::get()->get_local_pawn(0);

    if (component_params.c != nullptr && pawn != nullptr) {
        // either or.
        pawn->call_function(L"K2_GetComponentsByClass", &component_params);

        if (component_params.return_value.empty()) {
            API::get()->log_error("Failed to find any SkeletalMeshComponents");
        }

        for (auto mesh : component_params.return_value) {
            auto name = mesh->get_fname()->to_string();
            if(name.contains(L"WeaponInHands")) {
                return mesh;
            }
        }
    } else {
        API::get()->log_error("Failed to find SkeletalMeshComponent class or local pawn");
    }
    return nullptr;
}

SDK::FTransform get_socket_transform(API::UObject* mesh, std::wstring_view socket_name, uint8_t transform_space = 0) {
    {
        SDK::SceneComponent_GetSocketTransform socket_params{};

        socket_params.InSocketName = API::FName{socket_name};
        socket_params.TransformSpace = (SDK::ERelativeTransformSpace)transform_space;
        mesh->call_function(L"GetSocketTransform", &socket_params);
        return socket_params.ReturnValue;
    }
}

SDK::FTransform* Stalker2VR::on_get_weapon_forward(/*SDK::APC*/void* actor, SDK::FTransform* out_transform,/* this flag is not used in any way*/ int8_t type) {
    auto original_fn = g_plugin->m_original_on_get_weapon_forward;
    auto res = original_fn(actor, out_transform, type);

    auto weapon = get_weapon_in_hands();
    if(weapon) {
        /* another candidate is AimSocket */
        auto socket_transform = get_socket_transform(weapon, L"Muzzle", 0);
        res->Rotation = socket_transform.Rotation;
        res->Translation = socket_transform.Translation;
    }
    return res;
}

char Stalker2VR::on_set_scalar_value_mci(void *materialCollectionInstance, uevr::API::FName name, float value) {

    static uevr::API::FName fOpticScopePhase{L"OpticScope_Phase", uevr::API::FName::EFindName::Find};

    auto original_fn = g_plugin->m_original_set_scalar_value_mci;
    //TODO check for hmd active
    if(name == fOpticScopePhase && is_scope_active()) {
        value = 1.0f;
    }
    return original_fn(materialCollectionInstance, name, value);
}


void Stalker2VR::on_set_scalar_value(void *materialInstance, uevr::API::FName name, float value) {
    auto original_fn = g_plugin->m_original_set_scalar_value;
    static uevr::API::FName fOpticCutOutEnabled{L"OpticCutoutEnabled", uevr::API::FName::EFindName::Find};
    static uevr::API::FName fLensFlare{L"Lens_Flare", uevr::API::FName::EFindName::Find};
    //TODO check for hmd active
    if ((name == fLensFlare || name == fOpticCutOutEnabled) && is_scope_active()) {
        value = 0.0f;
    }
    original_fn(materialInstance, name, value);
}

void Stalker2VR::on_initialize() {
    PLUGIN_LOG_ONCE("Stalker2VR::on_initialize()");
    hook();
    // Asset loading moved to on_pre_engine_tick for stability
}

// using StaticLoadObject_t = uevr::API::UObject* (*)(uevr::API::UClass* ObjectClass, uevr::API::UObject* InOuter, const wchar_t *inName,const wchar_t *Filename, int32_t LoadFlags, struct UPackageMap* Sandbox, bool bAllowObjectReconciliation, const struct FLinkerInstancingContext* InstancingContext);

// void Stalker2VR::on_pre_engine_tick(uevr::API::UGameEngine* engine, float delta) {
//     static unsigned int monotonic = 0;
//     if(!m_scope_asset_loaded || (monotonic++ > 50 && (monotonic = 0, level_changed(engine)))) {
//         std::cout << "Level changed" << std::endl;
//         load_asset();
//     }
// }

// void Stalker2VR::load_asset() {
//     auto mod = utility::get_executable();
//     // StaticLoadObject
//     static const auto func_signature = "40 55 53 56 57 41 54 41 55 41 56 41 57 48 8D AC 24 58 FE FF FF 48 81 EC A8 02 00 00 48 8B 05 ? ? ? ? 48 33 C4 48 89 85 98";
//     static auto static_load_asset_func = utility::scan(mod, func_signature);
//     if(!static_load_asset_func) {
//         PLUGIN_LOG_ONCE_ERROR("Failed to find StaticLoadObject function");
//         return;
//     }
//     auto func = (StaticLoadObject_t)static_load_asset_func.value();
//     auto static_mesh_cl = API::get()->find_uobject<API::UClass>(L"Class /Script/Engine.StaticMesh");

//     if(!static_mesh_cl) {
//         PLUGIN_LOG_ONCE_ERROR("Failed to find StaticMesh class");
//         return;
//     }

//     auto cylinder = func(static_mesh_cl, nullptr, L"/Engine/BasicShapes/Cylinder.Cylinder", nullptr, 0, nullptr, true, nullptr);

//     if(!cylinder) {
//         PLUGIN_LOG_ONCE_ERROR("Failed to load cylinder");
//         return;
//     }
//     PLUGIN_LOG_ONCE("Loaded cylinder");
//     m_scope_asset_loaded = true;
// }

// void Stalker2VR::on_custom_event(const char *event_name, const char *event_data) {
//     static std::chrono::steady_clock::time_point last_load_asset_time{};
//     const auto current_time = std::chrono::steady_clock::now();

//     // Check if enough time has passed since the last event (1 second)
//     if (event_name == std::string("LoadAsset") && (current_time - last_load_asset_time) >= std::chrono::seconds(1)) {
//         last_load_asset_time = current_time;
//         m_scope_asset_loaded = false;
//     }
// }

void Stalker2VR::hook() {
    const auto mod      = utility::get_executable();

    // auto apc = (API::UClass*)API::get()->find_uobject(L"Class /Script/Stalker2.PC");
    // auto obj = apc->get_class_default_object();
    // auto vtable = *(uintptr_t**)obj;
    //    auto source_of_damage = vtable[307];
   // 48 89 5C 24 18 57 48 81 EC 90 00 00 00 48 8B 05 ? ? ? ? 48 33 C4 48 89 84 24 80 00 00 00 48 8B FA 48 8B D9 48 8D 54
   static auto const get_weapon_origin_pattern = "48 89 5C 24 18 57 48 81 EC 90 00 00 00 48 8B 05 ? ? ? ? 48 33 C4 48 89 84 24 80 00 00 00 48 8B FA 48 8B D9 48 8D 54";
   static auto get_weapon_origin_func_addr = utility::scan(mod, get_weapon_origin_pattern);

   if(get_weapon_origin_func_addr) {
        m_on_get_weapon_forward_hook_id = API::get()->param()->functions->register_inline_hook((void*)get_weapon_origin_func_addr.value(), (void*)&on_get_weapon_forward, (void**)&m_original_on_get_weapon_forward);
        if(m_on_get_weapon_forward_hook_id == -1) {
            PLUGIN_LOG_ONCE_ERROR("Failed to hook on_get_weapon_forward");
        }
   } else {
        PLUGIN_LOG_ONCE_ERROR("Failed to find get_weapon_origin function");
   }

//    const auto func_addr = (uintptr_t )mod + 0x4aebaa0;
    // UMaterialInstanceDynamic::SetScalarParameterValue
    static const auto set_scalar_value_func_signature = "40 53 48 81 EC C0 00 00 00 48 8B D9 0F";
    static auto set_scalar_value_func = utility::scan(mod, set_scalar_value_func_signature);
    if(set_scalar_value_func) {
        m_on_set_scalar_value_hook_id = API::get()->param()->functions->register_inline_hook((void*)set_scalar_value_func.value(), (void*)&on_set_scalar_value, (void**)&m_original_set_scalar_value);
        if(m_on_set_scalar_value_hook_id == -1) {
            PLUGIN_LOG_ONCE_ERROR("Failed to hook on_set_scalar_value");
        }
    } else {
        PLUGIN_LOG_ONCE_ERROR("Failed to find set_scalar_value function");
    }
    // const auto func_addr2 = (uintptr_t )mod + 0x4b505d0; // 4b505d0
    // UMaterialParameterCollectionInstance::SetScalarParameterValue
    static const auto set_scalar_value_mci_func_signature = "F3 0F 11 54 24 18 48 89 54 24 10 53 55 56 48";
    static auto set_scalar_value_mci_func = utility::scan(mod, set_scalar_value_mci_func_signature);
    if(set_scalar_value_mci_func) {
        m_on_set_scalar_value_mci_id = API::get()->param()->functions->register_inline_hook((void*)set_scalar_value_mci_func.value(), (void*)&on_set_scalar_value_mci, (void**)&m_original_set_scalar_value_mci);
        if(m_on_set_scalar_value_mci_id == -1) {
            PLUGIN_LOG_ONCE_ERROR("Failed to hook m_on_set_scalar_value_mci_id");
        }
    } else {
        PLUGIN_LOG_ONCE_ERROR("Failed to find set_scalar_value_mci function");
    }

}
