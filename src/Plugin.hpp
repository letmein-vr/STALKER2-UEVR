#pragma once

#include <windows.h>

#include <memory>
#include "uevr/API.hpp"
#include "uevr/Plugin.hpp"
#include <utility/PointerHook.hpp>

#define PLUGIN_LOG_ONCE(...) { \
    static bool _logged_ = false; \
    if (!_logged_) { \
        _logged_ = true; \
        API::get()->log_info(__VA_ARGS__); \
    } }

#define PLUGIN_LOG_INFO(...) { \
        API::get()->log_info(__VA_ARGS__); \
    }

#define PLUGIN_LOG_ONCE_ERROR(...) { \
    static bool _logged_ = false; \
    if (!_logged_) { \
        _logged_ = true; \
        API::get()->log_error(__VA_ARGS__); \
    } }

// Global accessor for our plugin.
class Stalker2VR;
extern std::unique_ptr<Stalker2VR> g_plugin;

namespace SDK {
    struct FTransform;
}


class Stalker2VR : public uevr::Plugin {
public:
    Stalker2VR() = default;
    virtual ~Stalker2VR();

    void on_initialize() override;
private:
    static SDK::FTransform *on_get_weapon_forward(void *actor, SDK::FTransform *out_transform, int8_t type);
    static void on_set_scalar_value(void *materialInstance, uevr::API::FName name, float value);
    static char on_set_scalar_value_mci(void *materialCollectionInstance, uevr::API::FName name, float value);
    void hook();

    int32_t m_on_get_weapon_forward_hook_id{};
    int32_t m_on_set_scalar_value_hook_id{};
    int32_t m_on_set_scalar_value_mci_id{};
    using get_weapon_forward_t = decltype(Stalker2VR::on_get_weapon_forward);
    get_weapon_forward_t* m_original_on_get_weapon_forward{};
    using set_scalar_value_t = decltype(Stalker2VR::on_set_scalar_value);
    set_scalar_value_t* m_original_set_scalar_value{};
    using set_scalar_value_mci_t = decltype(Stalker2VR::on_set_scalar_value_mci);
    set_scalar_value_mci_t* m_original_set_scalar_value_mci{};

    bool m_scope_asset_loaded{false};
    
    // Throttle interval in seconds 
    const int ASSET_CHECK_INTERVAL_SECONDS = 5;
};