--[[
    physical_pickup.lua -- Stalker 2 VR Physical Item Grab
    -------------------------------------------------------
    Flow:
      1. Move left hand to overlap a world item (UIDActor_ItemContainer).
      2. Press and HOLD left grip:
           - Item mesh hooked to left VR controller via UEVR_UObjectHook.
           - Actor position synced to hand every 80ms while held
             (keeps actor near player, prevents streaming/culling gaps).
      3. Release left grip:
           - UEVR hook removed. Actor is already at hand position.
           - Item stays where you dropped it.

    Key design decisions:
      - NO SetActorEnableCollision(false): disabling collision may trigger the
        game's item-pickup/despawn system, destroying the actor on us.
      - NO SetSimulatePhysics: these actors have bAlwaysCreatePhysicsState=false,
        bEnableGravity=false -- they're static world items, not physics objects.
      - Continuous actor position sync: UEVR hook overrides only the mesh's
        world transform cache. The actor's real stored position is unchanged.
        On hook removal UE recalculates from actor position. We keep actor
        position synced to hand every tick so hook removal leaves item in place.
--]]

local uevrUtils   = require("libs/uevr_utils")
local controllers = require("libs/controllers")
local gameState   = require("stalker2.gamestate")
local mc          = require("gestures.motioncontrollergestures")
local hands       = require("libs/hands")
local plugin      = require("libs/core/plugin")   -- TArray-capable engine calls (SphereOverlapComponents)
require("libs/enums/unreal")

local M = {}

-- Declared up here (not in the Config block below) so resolvePrototypeID's
-- debug print sees the local instead of a nil global.
local DEBUG_PRINT = false

-- ---------------------------------------------------------------------------
-- Item Mapping: SM mesh name substrings → XCreateItemInInventoryByID PrototypeID
-- Keys are lowercase substrings. Sorted longest-first at resolve time.
-- Verified against live RAM scans with all item types spawned in-world.
-- ---------------------------------------------------------------------------
local ITEM_MAPPING = {
    -- Consumables
    ["SM_cns_energy_drink"]             = "Energetic",
    ["SM_cns_bandage_01"]               = "Bandage",
    ["SM_cns_bread_01_d"]               = "Bread",
    ["SM_cns_bread_01"]                 = "FreshBread",
    ["SM_cns_cossacks_vodka_01_a"]      = "Vodka",
    ["SM_cns_cossacks_vodka_01_c"]      = "Vodka",
    ["SM_cns_healthbox_01"]             = "ArmyMedkit",
    ["SM_cns_healthbox_02"]             = "EcoMedkit",
    ["SM_cns_healthbox_03"]             = "Medkit",
    ["SM_cns_injector_antirad_wrap"]    = "AntiRad",
    ["SM_cns_injector_antirad"]         = "AntiRad",
    ["SM_cns_water_c"]                  = "Water",
    ["SM_cns_canned_food_g"]            = "CannedFood",
    ["SM_cns_canned_milk_b"]            = "Milk",
    ["SM_cns_pills_01_d"]               = "Hercules",
    ["SM_cns_pills_01_e"]               = "Cinnamon",
    ["SM_cns_pills_01_f"]               = "PSYBlocker",
    ["SM_cns_hercules"]                 = "Hercules",
    ["SM_cns_sausage_02_d"]             = "Sausage",
    ["SM_cns_beer_c"]                   = "Beer",

    -- Ammo (exact mesh names confirmed via RAM scan)
    ["SM_amm_bulletbox_01_12x70_fmj"]   = "A012D",
    ["SM_amm_bulletbox_01_12x70_ap"]    = "A012A",
    ["SM_amm_bulletbox_01_12x70_hp"]    = "A012E",
    ["SM_amm_bulletbox_01_45acp_fmj"]   = "A045D",
    ["SM_amm_bulletbox_01_45acp_ap"]    = "A045A",
    ["SM_amm_bulletbox_01_45acp_hp"]    = "A045E",
    ["SM_amm_bulletbox_01_9x18_fmj"]    = "A918D",
    ["SM_amm_bulletbox_01_9x18_ap"]     = "A918A",
    ["SM_amm_bulletbox_01_9x19_fmj"]    = "A919D",
    ["SM_amm_bulletbox_01_9x19_ap"]     = "A919A",
    ["SM_amm_bulletbox_01_545x39_fmj"]  = "A545D",
    ["SM_amm_bulletbox_01_545x39_ap"]   = "A545A",
    ["SM_amm_bulletbox_01_545x39_hp"]   = "A545E",
    ["SM_amm_bulletbox_01_5x56_fmj"]    = "A556D",
    ["SM_amm_bulletbox_01_5x56_ap"]     = "A556A",
    ["SM_amm_bulletbox_01_5x56_hp"]     = "A556E",
    ["SM_amm_bulletbox_01_5x56_ss"]     = "A556S",
    ["SM_amm_bulletbox_01_762x39_fmj"]  = "A762D",
    ["SM_amm_bulletbox_01_762x39_ap"]   = "A762A",
    ["SM_amm_bulletbox_01_762x39_hp"]   = "A762E",
    ["SM_amm_bulletbox_01_762x51_fmj"]  = "A762NATOD",
    ["SM_amm_bulletbox_01_762x51_ap"]   = "A762NATOA",
    ["SM_amm_bulletbox_01_762x51_ss"]   = "A762NATOS",
    ["SM_amm_bulletbox_01_762x54_fmj"]  = "A762SniperD",
    ["SM_amm_bulletbox_01_762x54_ap"]   = "A762SniperA",
    ["SM_amm_bulletbox_01_762x54_ss"]   = "A762SniperS",
    ["SM_amm_bulletbox_01_9x39_fmj"]    = "A939D",
    ["SM_amm_bulletbox_01_9x39_ap"]     = "A939A",
    ["SM_amm_bulletbox_01_9x39_hp"]     = "A939E",
    ["SM_amm_bulletbox_01_9x39_ss"]     = "A939S",
    ["SM_amm_pt_tracer"]                = "AGA",
    ["SM_amm_gl_40mm_m406"]             = "AHEDP",
    ["SM_amm_gl_40mm_vog25"]            = "AVOG",
    ["SM_amm_rpg7"]                     = "APG7V",

    -- Detectors
    ["SM_dev_detector_veles"]           = "Veles",
    ["SM_dev_detector_bear"]            = "Bear",
    ["SM_dev_detector_echo"]            = "Echo",
    ["SM_dev_detector_gilka"]           = "Gilka",

    -- Weapons - Assault Rifles (confirmed SM names from RAM scan)
    ["SM_AK74"]                         = "GunAK74_ST",
    ["SM_AKU"]                          = "GunAKU_PP",
    ["SM_GP3"]                          = "GunG37_ST",
    ["sm_m16"]                          = "GunM16_ST",
    ["sm_lav"]                          = "GunLavina_ST",
    ["SM_kha"]                          = "GunKharod_ST",
    ["sm_fora0"]                        = "GunFora_ST",
    ["sm_grim0"]                        = "GunGrim_ST",
    ["sm_dnipr"]                        = "GunDnipro_ST",
    -- Named AR variants (longer keys checked first by fuzzy sorter)
    ["ak74_korshunov"]                  = "GunAK74_Korshunov_ST",
    ["ak74_strelok"]                    = "GunAK74_Strelok_ST",
    ["m160_monolith"]                   = "Gun_RifleMonolith_AR",
    ["combatant"]                       = "Gun_Combatant_AR",
    ["drowned"]                         = "Gun_Drowned_AR",
    ["novator"]                         = "Gun_Novator_AR",
    ["gabion"]                          = "Gun_Gabion_AR",
    ["sofmod"]                          = "Gun_SOFMOD_AR",
    ["sotnyk"]                          = "Gun_Sotnyk_AR",
    ["spitfire"]                        = "Gun_Spitfire_SMG",
    ["trophy"]                          = "Gun_Trophy_AR",
    ["lummox"]                          = "Gun_Lummox_AR",
    ["decider"]                         = "Gun_Decider_AR",
    ["sharpshooter"]                    = "Gun_Sharpshooter_AR",

    -- Weapons - Pistols & Revolvers
    ["SM_APB"]                          = "GunAPB_HG",
    ["SM_PM"]                           = "GunPM_HG",
    ["SM_Kora"]                         = "GunKora_HG",
    ["SM_UDP"]                          = "GunUDP_HG",
    ["SM_Rhin"]                         = "GunRhino_HG",
    ["deadeye"]                         = "Gun_Deadeye_HG",
    ["encourage"]                       = "Gun_Encourage_HG",
    ["krivenko"]                        = "Gun_Krivenko_HG",
    ["projecty"]                        = "Gun_ProjectY_HG",
    ["nightstalker"]                    = "GunNightStalker_HG",
    ["pm_monolith"]                     = "Gun_PistolMonolith_HG",
    ["modelspecial"]                    = "Gun_ModelSpecial_HG",
    ["skif"]                            = "Gun_SkifGun_HG",

    -- Weapons - SMGs
    ["SM_vip"]                          = "GunViper_PP",
    ["SM_Bucket"]                       = "GunBucket_PP",
    ["SM_integ"]                        = "GunIntegral_PP",
    ["SM_M10"]                          = "GunM10_HG",
    ["SM_Zubr"]                         = "GunZubr_PP",
    ["gstreet"]                         = "Gun_GStreet_HG",
    ["ratkiller"]                       = "Gun_RatKiller_SMG",
    ["logarithm"]                       = "Gun_Logarithm_SMG",
    ["shakh"]                           = "Gun_Shakh_SMG",
    ["vip_monolith"]                    = "Gun_SMGMonolith_SMG",

    -- Weapons - Shotguns
    ["SM_Obrez"]                        = "GunObrez_SG",
    ["SM_Toz"]                          = "GunTOZ_SG",
    ["SM_D12"]                          = "GunD12_SG",
    ["SM_m86000"]                       = "GunM860_SG",
    ["SM_SPSA"]                         = "GunSPSA_SG",
    ["SM_Ram2"]                         = "GunRam2_SG",
    ["margach"]                         = "Gun_Margach_SG",
    ["m860_monolith"]                   = "Gun_ShotgunMonolith_SG",
    ["predator"]                        = "Gun_Predator_SG",
    ["sledgehammer"]                    = "Gun_Sledgehammer_SG",
    ["texas"]                           = "Gun_Texas_SG",

    -- Weapons - Sniper Rifles
    ["SM_mar"]                          = "GunMark_SP",
    ["SM_Gvintar"]                      = "GunGvintar_ST",
    ["SM_M701"]                         = "GunM701_SP",
    ["SM_svm"]                          = "GunSVDM_SP",
    ["SM_svu"]                          = "GunSVU_SP",
    ["SM_ThreeLine"]                    = "GunThreeLine_SP",
    ["cavalier"]                        = "Gun_Cavalier_SR",
    ["zvirolov"]                        = "Gun_Zvirolov_SR",
    ["lynx"]                            = "Gun_Lynx_SR",
    ["duga"]                            = "GunSVU_Sniper_Duga_SP",
    ["whip"]                            = "Gun_Whip_SR",

    -- Weapons - Heavy & Special
    ["SM_PKP"]                          = "GunPKP_MG",
    ["pkp_korshunov"]                   = "GunPKP_Korshunov_MG",
    ["SM_Gauss"]                        = "GunGauss_SP",
    ["gauss_scar"]                      = "GunGauss_Scar_SP",
    ["SM_RPG"]                          = "GunRpg7_GL",

    -- Armor (fuzzy faction substrings - pooled meshes)
    ["fol_hea_exo_dol"]                 = "HeavyExoskeleton_Dolg_Armor",
    ["fol_hea_exo_svo"]                 = "HeavyExoskeleton_Svoboda_Armor",
    ["fol_hea_exo_mon"]                 = "HeavyExoskeleton_Monolith_Armor",
    ["fol_bat_exo_war"]                 = "BattleExoskeleton_Varta_Armor",
    ["fol_hea_hel_mil"]                 = "Heavy_Military_Helmet",
    ["fol_hea_hel_dol"]                 = "Heavy_Duty_Helmet",
    ["fol_hea_hel_war"]                 = "Heavy_Varta_Helmet",
    ["fol_lig_hel_mil"]                 = "Light_Military_Helmet",
    ["fol_lig_hel_dol"]                 = "Light_Duty_Helmet",
    ["fol_lig_hel_ban"]                 = "Light_Bandit_Helmet",
    ["fol_bat_hel_mil"]                 = "Battle_Military_Helmet",
    ["fol_bat_dol_end"]                 = "Battle_Dolg_End_Armor",
    ["fol_hea_ano_spa"]                 = "HeavyAnomaly_Spark_Armor",
    ["fol_hea_bat_spa"]                 = "HeavyBattle_Spark_Armor",
    ["fol_ano_sci_psy"]                 = "Anomaly_Scientific_Armor_PSY_preinstalled",
    ["fol_hea2_mil"]                    = "Heavy2_Military_Armor",
    ["fol_hea_mer"]                     = "Heavy_Mercenaries_Armor",
    ["fol_hea_dol"]                     = "Heavy_Dolg_Armor",
    ["fol_hea_svo"]                     = "Heavy_Svoboda_Armor",
    ["fol_hea_mon"]                     = "HeavyAnomaly_Monolith_Armor",
    ["fol_hea_sci"]                     = "HeavyAnomaly_Scientific_Armor",
    ["fol_hea_sir"]                     = "HeavyAnomaly_SIRCA_Armor",
    ["fol_hea_war"]                     = "HeavyExoskeleton_Varta_Armor",
    ["fol_exo_dol"]                     = "Exoskeleton_Dolg_Armor",
    ["fol_exo_svo"]                     = "Exoskeleton_Svoboda_Armor",
    ["fol_exo_mon"]                     = "Exoskeleton_Monolith_Armor",
    ["fol_exo_mer"]                     = "Exoskeleton_Mercenaries_Armor",
    ["fol_ult_mer"]                     = "UltraLight_Mercenaries_Armor",
    ["fol_hel_mer"]                     = "Light_Mercenaries_Helmet",
    ["fol_hel_svo"]                     = "Heavy_Svoboda_Helmet",
    ["fol_roo_dol"]                     = "Rook_Dolg_Armor",
    ["fol_roo_svo"]                     = "Rook_Svoboda_Armor",
    ["fol_sev_dol"]                     = "SEVA_Dolg_Armor",
    ["fol_sev_svo"]                     = "SEVA_Svoboda_Armor",
    ["fol_sev_mon"]                     = "SEVA_Monolith_Armor",
    ["fol_sev_spa"]                     = "SEVA_Spark_Armor",
    ["fol_sci_sev"]                     = "SciSEVA_Scientific_Armor",
    ["fol_jac_ban"]                     = "Jacket_Bandit_Armor",
    ["fol_ski_ban"]                     = "SkinJacket_Bandit_Armor",
    ["fol_new_sta"]                     = "Newbee_Neutral_Armor",
    ["fol_tou_sta"]                     = "Zorya_Tourist_Armor",
    ["fol_jem_sta"]                     = "Jemmy_Neutral_Armor",
    ["fol_nas_sta"]                     = "Nasos_Neutral_Armor",
    ["fol_sci"]                         = "Anomaly_Scientific_Armor",
    ["fol_spa"]                         = "Battle_Spark_Armor",
    ["fol_mil"]                         = "Default_Military_Armor",
    ["fol_mer"]                         = "Light_Mercenaries_Armor",
    ["fol_war"]                         = "Battle_Varta_Armor",
    ["fol_mon"]                         = "Battle_Monolith_Armor",
    ["fol_svo"]                         = "Battle_Svoboda_Armor",
    ["fol_dol"]                         = "Battle_Dolg_Armor",
    ["fol_ban"]                         = "Middle_Bandit_Armor",
    ["fol_sta"]                         = "Zorya_Neutral_Armor",

    -- NVGs (exact SM names confirmed)
    ["SM_dev_nvg_body_gen1"]             = "NVG_Gen1",
    ["SM_dev_nvg_body_gen2"]             = "NVG_Gen2",
    ["SM_dev_nvg_body_gen3"]             = "NVG_Gen3",
    ["nvg_gen3_wp"]                      = "NVG_Gen3_WP",

    -- Attachments - Scopes (confirmed SM names from RAM scan)
    ["rds01_en_colimscope"]             = "EN_ColimScope_1",
    ["rds02_en_goloscope"]              = "EN_GoloScope_1",
    ["as01_en_x2scope"]                 = "EN_X2Scope_1",
    ["as02_en_x4scope"]                 = "EN_X4Scope_1",
    ["ss01_en_x8scope"]                 = "EN_X8Scope_1",
    ["ru_colimscope_mini"]              = "RU_ColimScope_1",
    ["ru_x2scope_1"]                    = "RU_X2Scope_1",
    ["as02_ru_x4scope"]                 = "RU_X4Scope_1",
    ["ss01_ru_x8scope"]                 = "RU_X8Scope_1",

    -- Attachments - Silencers (confirmed SM names from RAM scan)
    ["sc01_en_silen_1"]                 = "EN_Silen_1",
    ["sc02_en_silen_2"]                 = "EN_Silen_2",
    ["sc03_en_silen_3"]                 = "EN_Silen_3",
    ["sc04_en_silen_4"]                 = "EN_Silen_4",
    ["sc01_ru_silen"]                   = "RU_Silen_1",
    ["sc02_ru_silen"]                   = "RU_Silen_2",
    ["sc03_ru_silen"]                   = "RU_Silen_3",

    -- Attachments - Underbarrels (exact SM names confirmed)
    ["SM_BuckLaunch"]                    = "EN_BuckLaunch_1",
    ["SM_EN_GLaunch"]                    = "EN_GLaunch_1",
    ["SM_Ru_GLaunch"]                    = "RU_GLaunch_1",

    -- Attachments - Magazines (exact SM names confirmed)
    ["SM_smg_m1000_increased_full"]      = "GunM10_MagIncreased",
    ["SM_ar_m160_bigmag_full"]           = "GunM16_MagIncreased",
    ["SM_ar_gp3_twin_mag_full"]          = "GunGP37_MagPaired",
    ["SM_sr_carabine_mar_bigmag_full"]   = "GunMark_MagIncreased",
    ["SM_pt_apb_increased_full"]         = "GunAPB_MagIncreased",
    ["SM_pp_bucket0_increased_full"]     = "GunBucket_MagIncreased",
    ["SM_ar_kharod000_bigmag_full"]      = "GunFora_MagIncreased",
    ["SM_ar_dni_twinmag_full"]           = "GunDnipro_MagPaired",
    ["SM_sr_gauss_mag_increased_full"]   = "GunGauss_MagIncreased",
    ["SM_ar_gp3_round_mag"]              = "GunGP37_MagLarge",
    ["SM_ar_grim0_bigmag_full"]          = "GunGrim_MagIncreased",
    ["SM_ar_grim0_drumag_full"]          = "GunGrim_MagLarge",
    ["SM_ak_twinmag_full"]               = "GunAK_MagPaired",
    ["SM_ar_ak_bigmag_full"]             = "GunAK74_MagIncreased",
    ["SM_pt_udp_increasedmag_full"]      = "GunUDP_MagIncreased",
    ["SM_shg_d1200_twinmag_full"]        = "GunD12_MagPaired",
    ["SM_smg_zubr0_magincreased_full"]   = "GunZubr_MagIncreased",
    ["SM_ar_lav_mag_full"]               = "GunGvintar_MagIncreased",
    ["SM_smg_integ_increased_full"]      = "GunIntegral_MagIncreased",
    ["SM_smg_vip_bigmag_full"]           = "GunViper_MagIncreased",
    ["SM_shg_d1200_bigmag_full"]         = "GunD12_MagIncreased",
    ["SM_shg_d1200_drumag_full"]         = "GunD12_MagLarge",
    ["SM_PKP_Mag_Increased"]             = "GunPKP_MagIncreased",
    ["SM_PKP_Mag_Large"]                 = "GunPKP_MagLarge",
    ["SM_kora_mag_increased_full"]       = "GunKora_MagIncreased",
    ["SM_sr_svu_mag_increased_full"]     = "GunSVU_MagIncreased",
    ["SM_ar_kharod000_twin_mag_full"]    = "GunKharod_MagPaired",
    ["SM_ar_lav_increased_full"]         = "GunLavina_MagIncreased",
    ["SM_pt_pm_increased_full"]          = "GunPM_MagIncreased",
}

-- Pre-sort keys longest-first so specific variants always win over base models.
-- Keys are stored lowercased in the sorted list so the fuzzy compare is
-- truly case-insensitive (grabbed names like "SM_cns_energy_drink" work too).
local ITEM_MAPPING_KEYS_SORTED = {}
local ITEM_MAPPING_LOWER = {}   -- shadow table: lowercase key → PrototypeID
for k, v in pairs(ITEM_MAPPING) do
    local lk = string.lower(k)
    ITEM_MAPPING_LOWER[lk] = v
    table.insert(ITEM_MAPPING_KEYS_SORTED, lk)
end
table.sort(ITEM_MAPPING_KEYS_SORTED, function(a, b) return #a > #b end)

-- ---------------------------------------------------------------------------
-- resolvePrototypeID: fuzzy mesh-name → PrototypeID lookup.
-- Returns nil when the item is NOT in the mapping (will drop normally).
-- ---------------------------------------------------------------------------
local function resolvePrototypeID(name, mesh)
    if name == nil then return nil end
    local lower = string.lower(name)
    -- Block armor/suits/helmets (all share the _fol_ substring).
    if string.find(lower, "_fol_", 1, true) then
        if DEBUG_PRINT then print("[pickup] resolvePrototypeID: blocked armor item: " .. name) end
        return nil
    end

    -- 1. Check for special Material overrides (skins) that share base meshes
    if mesh ~= nil then
        local function hasSkin(matStr)
            local found = false
            pcall(function()
                -- Check standard material slots
                for i = 0, 5 do
                    local mat = mesh:GetMaterial(i)
                    if mat then
                        if string.find(string.lower(mat:get_fname():to_string()), matStr, 1, true) then
                            found = true
                            break
                        end
                    end
                end
                -- Check OverrideMaterials array
                if not found and mesh.OverrideMaterials then
                    local count = mesh.OverrideMaterials:get_count()
                    for i = 1, count do
                        local mat = mesh.OverrideMaterials[i]
                        if mat then
                            if string.find(string.lower(mat:get_fname():to_string()), matStr, 1, true) then
                                found = true
                                break
                            end
                        end
                    end
                end
            end)
            return found
        end

        -- Assault Rifles
        if string.find(lower, "m160", 1, true) or string.find(lower, "_m16", 1, true) or string.find(lower, "ar416", 1, true) then
            if hasSkin("skin_monolith") then return "Gun_RifleMonolith_AR" end
        elseif string.find(lower, "ak74", 1, true) then
            if hasSkin("korshun") then return "GunAK74_Korshunov_ST" end
            if hasSkin("skin_drowned") then return "Gun_Drowned_AR" end
        elseif string.find(lower, "dnipr", 1, true) then
            if hasSkin("skin_centurion") then return "Gun_Sotnyk_AR" end
        elseif string.find(lower, "fora0", 1, true) then
            if hasSkin("skin_decider") then return "Gun_Decider_AR" end
            if hasSkin("lullaby") then return "Gun_Novator_AR" end
        elseif string.find(lower, "lavina", 1, true) then
            if hasSkin("gabion") then return "Gun_Gabion_AR" end
        elseif string.find(lower, "grim0", 1, true) then
            if hasSkin("skin_545") then return "Gun_Combatant_AR" end
        elseif string.find(lower, "lav", 1, true) then
            if hasSkin("skin_trophy") then return "Gun_Trophy_AR" end
        
        -- Sniper Rifles
        elseif string.find(lower, "gvintar", 1, true) then
            if hasSkin("skin_mercenary") then return "Gun_Merc_AR" end
            if hasSkin("veteran") then return "Gun_Veteran_AR" end
        elseif string.find(lower, "svu", 1, true) then
            if hasSkin("skin_whip") then return "Gun_Whip_SR" end
        elseif string.find(lower, "svm", 1, true) then
            if hasSkin("skin_lynx") then return "Gun_Lynx_SR" end
        elseif string.find(lower, "mar", 1, true) then
            if hasSkin("skin_partner") then return "Gun_Partner_SR" end
        
        -- Shotguns
        elseif string.find(lower, "d12", 1, true) then
            if hasSkin("margach") then return "Gun_Margach_SG" end
        elseif string.find(lower, "cracker", 1, true) then
            if hasSkin("skin_monolith") then return "Gun_ShotgunMonolith_SG" end
        elseif string.find(lower, "m860", 1, true) then
            if hasSkin("skin_predator") then return "Gun_Predator_SG" end
            if hasSkin("skin_monolith") then return "Gun_ShotgunMonolith_SG" end
        elseif string.find(lower, "ram2", 1, true) or string.find(lower, "sm_ram2", 1, true) then
            if hasSkin("skin_texas") then return "GunTexan_SG_Player" end
        elseif string.find(lower, "spsa00", 1, true) then
            if hasSkin("skin_sledgehammer") then return "Gun_Sledgehammer_SG" end
        
        -- SMGs
        elseif string.find(lower, "sm_aku", 1, true) then
            if hasSkin("skin_spitfire") then return "Gun_Spitfire_SMG" end
            if hasSkin("skin_silence") then return "Gun_Silence_SMG" end
        elseif string.find(lower, "vip", 1, true) then
            if hasSkin("monolit") then return "Gun_SMGMonolith_SMG" end
            if hasSkin("skin_shah") then return "Gun_Shakh_SMG" end
        elseif string.find(lower, "zubr0", 1, true) then
            if hasSkin("skin_ratkiller") then return "Gun_RatKiller_SMG" end
        elseif string.find(lower, "sm_integ", 1, true) or string.find(lower, "integ", 1, true) then
            if hasSkin("riemann") then return "Gun_Logarithm_SMG" end
        elseif string.find(lower, "bucket0", 1, true) then
            if hasSkin("skin_spitter") then return "Gun_Spitter_SMG" end
        
        -- Pistols
        elseif string.find(lower, "rhino", 1, true) then
            if hasSkin("skin_modcomp") then return "Gun_ModelSpecial_HG" end
        elseif string.find(lower, "ptm", 1, true) or string.find(lower, "sm_pm", 1, true) then
            if hasSkin("skin_monolith") then return "Gun_PistolMonolith_HG" end
            if hasSkin("skin_kayman") then return "Gun_ProjectY_HG" end
        elseif string.find(lower, "udp", 1, true) then
            if hasSkin("skin_deadeye") then return "Gun_Deadeye_HG" end
            if hasSkin("skin_krivenko") then return "Gun_Krivenko_HG" end
        elseif string.find(lower, "apb", 1, true) then
            if hasSkin("skin_encouragement") then return "Gun_Encourage_HG" end
        
        -- Machine Guns
        elseif string.find(lower, "pkp", 1, true) then
            if hasSkin("skin_tank") then return "Gun_Tank_MG" end
        end
    end

    -- 2. Exact match on lowercased name against lowercased keys
    if ITEM_MAPPING_LOWER[lower] then return ITEM_MAPPING_LOWER[lower] end
    -- 3. Fuzzy substring match (all keys already lowercased, sorted longest-first)
    for _, key in ipairs(ITEM_MAPPING_KEYS_SORTED) do
        if string.find(lower, key, 1, true) then
            return ITEM_MAPPING_LOWER[key]
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Ammo Quantities (Standardized rounds per pickup by PrototypeID)
-- ---------------------------------------------------------------------------
local AMMO_QUANTITIES = {
    -- 9x18mm (Pistol / SMG)
    ["A918D"] = 50, ["A918A"] = 50,
    -- 9x19mm Parabellum (Pistol / SMG)
    ["A919D"] = 50, ["A919A"] = 50,
    -- .45 ACP (Pistol / SMG)
    ["A045D"] = 50, ["A045A"] = 50, ["A045E"] = 50,
    -- 5.45x39mm (Warsaw Pact Assault Rifle)
    ["A545D"] = 30, ["A545A"] = 30, ["A545E"] = 30,
    -- 5.56x45mm NATO (Western Assault Rifle)
    ["A556D"] = 30, ["A556A"] = 30, ["A556E"] = 30, ["A556S"] = 30,
    -- 7.62x39mm (Assault Rifle / LMG)
    ["A762D"] = 30, ["A762A"] = 30, ["A762E"] = 30,
    -- 9x39mm (Subsonic / Sniper)
    ["A939D"] = 20, ["A939A"] = 20, ["A939E"] = 20, ["A939S"] = 20,
    -- 7.62x54mmR (Eastern Sniper / LMG)
    ["A762SniperD"] = 20, ["A762SniperA"] = 20, ["A762SniperS"] = 20,
    -- 7.62x51mm / .308 Win (Western Sniper)
    ["A762NATOD"] = 20, ["A762NATOA"] = 20, ["A762NATOS"] = 20,
    -- 12-Gauge (Buckshot / Slugs / Darts)
    ["A012D"] = 10, ["A012A"] = 10, ["A012E"] = 10,
    -- Gauss Battery (Railgun Ammo)
    ["AGA"] = 10,
    -- VOG-25 Grenade
    ["AVOG"] = 1,
    -- M203 Grenade
    ["AHEDP"] = 1,
    -- OG-7V Warhead (RPG Rocket)
    ["APG7V"] = 1
}

-- ---------------------------------------------------------------------------
-- injectItem: calls XCreateItemInInventoryByID
-- ---------------------------------------------------------------------------
local consoleManagerClass = nil
local function injectItem(protoID)
    if protoID == nil then return false end
    -- Guard: use a shared global so BOTH parallel script instances see the same timestamp.
    -- os.time() gives real wall-clock seconds (os.clock() is CPU time and can diverge under load).
    _G.__pickup_lastInjectTime = _G.__pickup_lastInjectTime or 0
    local now = os.time()
    if (now - _G.__pickup_lastInjectTime) < 1.0 then
        -- The second parallel script instance lands here on every pickup; it is
        -- not a failure, so return nil (not false) so the caller stays quiet.
        print("[pickup] injectItem: skipped duplicate within 1s guard")
        return nil
    end
    _G.__pickup_lastInjectTime = now
    local count = math.floor(AMMO_QUANTITIES[protoID] or 1)
    local cmd   = string.format("XCreateItemInInventoryByID %s 0 %d 1", protoID, count)
    local ok = false

    -- Primary path: the X* functions on CustomConsoleManagerRK are exec console
    -- commands, so route through the engine's ExecuteConsoleCommand (same route
    -- Entry.lua uses for cvars under the upgraded backend). This needs no object
    -- discovery at all -- the live manager instance is never UObjectHook-adopted,
    -- so the old find_all_of scan below returns nothing on this backend.
    pcall(function()
        if kismet_system_library == nil then return end
        local world = uevrUtils.get_world()
        if world == nil then return end
        kismet_system_library:ExecuteConsoleCommand(world, cmd, nil)
        ok = true
    end)

    -- Legacy fallback: direct method call on a scanned manager instance.
    -- Only reachable if the kismet library / world are unavailable.
    if not ok then
        pcall(function()
            if consoleManagerClass == nil then
                consoleManagerClass = uevrUtils.find_required_object(
                    "Class /Script/Stalker2.CustomConsoleManagerRK")
            end
            if consoleManagerClass == nil then return end
            local instances = uevrUtils.find_all_of(
                "Class /Script/Stalker2.CustomConsoleManagerRK", false)
            if instances == nil or #instances == 0 then return end
            local mgr = instances[1]
            if mgr == nil then return end
            mgr:XCreateItemInInventoryByID(protoID, false, count, 1.0)
            ok = true
        end)
    end

    if ok then
        print("[pickup] Injected: " .. cmd)
    else
        print("[pickup] WARNING: inject failed for " .. tostring(protoID) .. " (kismet library / world unavailable?)")
    end
    return ok
end

-- ---------------------------------------------------------------------------
-- Config
-- ---------------------------------------------------------------------------
local GRAB_RADIUS       = 30.0  -- cm: sphere-overlap radius around the left hand
local CHECK_INTERVAL_MS = 80    -- ms tick rate

-- Location offset (cm) and rotation offset (degrees) applied to held items,
-- relative to the left VR controller origin. Adjustable via the config UI.
local offsetLoc = {X=0.0, Y=0.0, Z=0.0}
local offsetRot = {Pitch=0.0, Yaw=0.0, Roll=0.0}

-- Index finger curl pose applied while holding an item.
-- [pitch, yaw, roll] matching the values in Config.reloadHandPose.
local GRAB_FINGER_POSE = {
    ["jnt_l_hand_index_01"] = {0.5249,  10.26,   0.0},
    ["jnt_l_hand_index_02"] = {0.0,     50.55,   0.0},
    ["jnt_l_hand_index_03"] = {0.0,     16.1368, 0.0},
}
-- Zero-rotation restore pose — clears the override on release.
local GRAB_FINGER_POSE_CLEAR = {
    ["jnt_l_hand_index_01"] = {0.0, 0.0, 0.0},
    ["jnt_l_hand_index_02"] = {0.0, 0.0, 0.0},
    ["jnt_l_hand_index_03"] = {0.0, 0.0, 0.0},
}

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
local lastGripState        = false
local releaseIsIntentional = false   -- true only on grip-up; false on menu/reset releases
local grabbed = {
    actor = nil,
    mesh  = nil
}
local grabbedItemName      = nil
local grabbedItemNameLower = nil   -- cached string.lower() so syncActorToHand never recomputes it
local grabbedActorClassName = nil
local cachedHookState      = nil   -- cached UEVR hook state, fetched once at grab time
local grabbedIsPhysicsProp = false  -- true when holding a BP_DestructibleObject_Small_C (drop-only)
-- Grab glide: nil when not gliding, else
-- {pending, pendingTicks, elapsed, duration, relRot0, relLoc0, relRot1, relLoc1}
local glide                = nil
-- The held mesh's world pose, captured every frame in the post-stereo callback.
-- Only valid there: on the game thread a hook-driven mesh reads back at its natural
-- (pre-grab) place, so a drop built from game-thread reads lands at the pick-up spot.
local heldMeshLoc          = nil   -- {X,Y,Z}
local heldMeshRot          = nil   -- {Pitch,Yaw,Roll}
local pendingDrop          = nil   -- drop pose still being re-applied after release
local GLIDE_PENDING_FALLBACK_TICKS = 3

-- ---------------------------------------------------------------------------
-- Quaternion helpers for the grab glide. Quats are {w,x,y,z}; vectors {x,y,z}.
--
-- UEVR's UObjectHook places a hooked component at (UObjectHook.cpp):
--   world_rot = hand_rot * inverse(rotation_offset)                (glm space)
--   world_loc = hand_pos + quat_converter * (world_rot * location_offset)
-- which works out to an ordinary transform RELATIVE to the controller:
--   rotation_offset = inverse(glmFromUE(relRot))
--   location_offset = ue4_to_glm(-inverse(relRot) * relLoc)
-- The glide interpolates relRot/relLoc and converts every frame. Verified against
-- a numeric re-implementation of the backend's glm code (round trip ~1e-13).
-- ---------------------------------------------------------------------------
local function qmul(a, b)
    return {
        w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
        x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
        y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
        z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
    }
end

local function qinv(q)
    return {w = q.w, x = -q.x, y = -q.y, z = -q.z}
end

local function qrot(q, x, y, z)
    -- v' = v + 2w(u x v) + 2u x (u x v)
    local tx = 2 * (q.y * z - q.z * y)
    local ty = 2 * (q.z * x - q.x * z)
    local tz = 2 * (q.x * y - q.y * x)
    return {
        x = x + q.w * tx + (q.y * tz - q.z * ty),
        y = y + q.w * ty + (q.z * tx - q.x * tz),
        z = z + q.w * tz + (q.x * ty - q.y * tx),
    }
end

local function axisQuat(rad, x, y, z)
    local s = math.sin(rad / 2)
    return {w = math.cos(rad / 2), x = x * s, y = y * s, z = z * s}
end

-- FRotator::Quaternion (degrees)
local function rotatorToQuat(p, y, r)
    local d = math.pi / 360
    local sp, cp = math.sin(p * d), math.cos(p * d)
    local sy, cy = math.sin(y * d), math.cos(y * d)
    local sr, cr = math.sin(r * d), math.cos(r * d)
    return {
        x =  cr * sp * sy - sr * cp * cy,
        y = -cr * sp * cy - sr * cp * sy,
        z =  cr * cp * sy - sr * sp * cy,
        w =  cr * cp * cy + sr * sp * sy,
    }
end

-- Shortest-path slerp
local function qslerp(a, b, t)
    local bw, bx, by, bz = b.w, b.x, b.y, b.z
    local dot = a.w * bw + a.x * bx + a.y * by + a.z * bz
    if dot < 0 then
        dot = -dot
        bw, bx, by, bz = -bw, -bx, -by, -bz
    end
    local s0, s1
    if dot > 0.9995 then
        s0, s1 = 1 - t, t
    else
        local theta = math.acos(dot)
        local sinTheta = math.sin(theta)
        s0 = math.sin((1 - t) * theta) / sinTheta
        s1 = math.sin(t * theta) / sinTheta
    end
    local w = s0 * a.w + s1 * bw
    local x = s0 * a.x + s1 * bx
    local y = s0 * a.y + s1 * by
    local z = s0 * a.z + s1 * bz
    local len = math.sqrt(w * w + x * x + y * y + z * z)
    if len > 0 then w, x, y, z = w / len, x / len, y / len, z / len end
    return {w = w, x = x, y = y, z = z}
end

-- UE-space rotation <-> UEVR glm-space rotation (UESDK Math.hpp ue4_to_glm, up to sign)
local function glmFromUE(q) return {w = q.w, x = -q.y, y = -q.z, z = q.x} end
local function ueFromGlm(g) return {w = g.w, x = g.z, y = -g.x, z = -g.y} end

-- What the Lua binding builds from a Vector3f rotation offset:
-- glm::quat(glm::yawPitchRoll(-e.y, e.x, -e.z))  ==  qY(-yaw) * qX(pitch) * qZ(-roll)
local function glmFromEulerRad(pitch, yaw, roll)
    return qmul(qmul(axisQuat(-yaw, 0, 1, 0), axisQuat(pitch, 1, 0, 0)), axisQuat(-roll, 0, 0, 1))
end

-- Profile offsets (cm / degrees, hook space) -> transform relative to the controller (UE space)
local function relativeFromOffsets(lx, ly, lz, pitch, yaw, roll)
    local relRot = ueFromGlm(qinv(glmFromEulerRad(math.rad(pitch), math.rad(yaw), math.rad(roll))))
    -- glm_to_ue4(location_offset) = (-z, x, y)
    local u = qrot(relRot, -lz, lx, ly)
    return relRot, {x = -u.x, y = -u.y, z = -u.z}
end

-- Transform relative to the controller (UE space) -> hook offsets
-- Returns location {x,y,z} (glm space) and rotation quat {w,x,y,z} (glm space)
local function offsetsFromRelative(relRot, relLoc)
    local u = qrot(qinv(relRot), -relLoc.x, -relLoc.y, -relLoc.z)
    -- ue4_to_glm(u) = (y, z, -x)
    return {x = u.y, y = u.z, z = -u.x}, qinv(glmFromUE(relRot))
end
-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------
function M.isHovering() return false end  -- hover detection removed (scan is grip-down only)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function isGrabbing()
    return grabbed.mesh ~= nil
end

local function dbg(msg)
    if DEBUG_PRINT then print("[pickup] " .. msg) end
end

-- ---------------------------------------------------------------------------
-- Grab candidate discovery -- engine-side sphere overlap around the left hand.
--
-- WHY NOT find_all_of / UEVR_UObjectHook.get_objects_by_class:
--   Under the upgraded UEVR backend (game on UE 5.5.4) UObjectHook defers
--   adoption of all pre-existing UObjects ("Deferring initial adoption of
--   ~100k existing UObjects; using on-demand common-root tracking"). Class
--   scans therefore only ever see objects the mod itself created or touched,
--   so a scan for UIDActor_ItemContainer returned {} forever and pickups went
--   silently dead. KismetSystemLibrary:SphereOverlapComponents is answered by
--   the engine's physics scene and does not care about adoption. Its TArray
--   out-param can't be marshalled by native Lua calls, so it goes through
--   libs/core/plugin.lua (uevr_utils.dll), exactly like libs/collision.lua.
--
-- World items in v2.0 are BP_StaticItemContainer_C actors whose super chain is
-- InteractableItemContainer -> UIDActor_ItemContainer -> Actor, so the class
-- test below is an is_a() check, not an exact-class match.
-- ---------------------------------------------------------------------------
local itemClass               = nil  -- Class /Script/Stalker2.UIDActor_ItemContainer (cached)
local physicsInteractionClass = nil  -- Class /Script/Stalker2.PhysicsInteractionComponent (cached)
local primitiveClass          = nil  -- Class /Script/Engine.PrimitiveComponent (cached)

-- EObjectTypeQuery indices to overlap against. Item meshes use collision profile
-- "Items" with ObjectType 1 (WorldDynamic); physics props vary. 0..5 are the
-- engine channels (WorldStatic, WorldDynamic, Pawn, PhysicsBody, Vehicle,
-- Destructible), 6..23 are GameTraceChannel1..18 which this game defines.
local OVERLAP_OBJECT_TYPES = {}
for i = 0, 23 do OVERLAP_OBJECT_TYPES[#OVERLAP_OBJECT_TYPES + 1] = i end

local function ensureFinderClasses()
    if itemClass == nil then
        itemClass = uevrUtils.get_class("Class /Script/Stalker2.UIDActor_ItemContainer")
    end
    if physicsInteractionClass == nil then
        physicsInteractionClass = uevrUtils.get_class("Class /Script/Stalker2.PhysicsInteractionComponent")
    end
    if primitiveClass == nil then
        primitiveClass = uevrUtils.get_class("Class /Script/Engine.PrimitiveComponent")
    end
    return itemClass ~= nil and primitiveClass ~= nil
end

-- Returns the list of PrimitiveComponents overlapping a GRAB_RADIUS sphere at
-- handLoc, or nil when the query could not run.
local function sphereOverlapAtHand(handLoc)
    if kismet_system_library == nil then
        dbg("sphereOverlapAtHand: kismet_system_library is nil")
        return nil
    end
    local world = uevrUtils.get_world()
    if world == nil then
        dbg("sphereOverlapAtHand: world is nil")
        return nil
    end
    local ignoreActors = {}
    if pawn ~= nil then ignoreActors[1] = pawn end

    local result = nil
    local ok, err = pcall(function()
        result = plugin.executeFunction(kismet_system_library, "SphereOverlapComponents",
            world, handLoc, GRAB_RADIUS, OVERLAP_OBJECT_TYPES, primitiveClass, ignoreActors, {})
    end)
    if not ok then
        dbg("sphereOverlapAtHand: executeFunction threw: " .. tostring(err))
        return nil
    end
    if result == nil then
        dbg("sphereOverlapAtHand: no result (plugin dll not loaded?)")
        return nil
    end
    return result.OutComponents or {}
end

-- Classify one overlapped component's owner.
-- Returns actor, kind ("container" | "prop") or nil when it is not grabbable.
local function classifyOwner(comp)
    local actor = nil
    pcall(function() actor = comp:GetOwner() end)
    if actor == nil then return nil end

    -- 1. Inventory item containers (BP_StaticItemContainer_C etc.)
    local isContainer = false
    pcall(function() isContainer = actor:is_a(itemClass) end)
    if isContainer then
        local isActive = true
        pcall(function()
            local ic = actor.InteractionComponent
            if ic ~= nil and ic.bIsInteractionActive == false then isActive = false end
        end)
        if not isActive then return nil end
        return actor, "container"
    end

    -- 2. World physics props (BP_DestructibleObject_Small_C: tin cans, buckets...).
    --    They own a PhysicsInteractionComponent but have no InteractionComponent.
    if physicsInteractionClass == nil then return nil end
    local hasInteraction = false
    pcall(function() hasInteraction = actor.InteractionComponent ~= nil end)
    if hasInteraction then return nil end
    local hasPhysicsInteraction = false
    pcall(function()
        local pic = actor:GetComponentByClass(physicsInteractionClass)
        hasPhysicsInteraction = pic ~= nil
    end)
    if not hasPhysicsInteraction then
        pcall(function() hasPhysicsInteraction = actor.PhysicsInteractionComponent ~= nil end)
    end
    if hasPhysicsInteraction then return actor, "prop" end
    return nil
end

-- ---------------------------------------------------------------------------
-- findNearbyGrabbable: ONLY called on grip-down (rising edge).
-- Returns actor, isPhysicsProp. Item containers take priority over props;
-- within a kind, the actor whose root is closest to the hand wins.
-- ---------------------------------------------------------------------------
local function findNearbyGrabbable(handLoc)
    if not ensureFinderClasses() then
        dbg("findNearbyGrabbable: required classes not found")
        return nil, false
    end
    local comps = sphereOverlapAtHand(handLoc)
    if comps == nil or #comps == 0 then
        dbg("findNearbyGrabbable: no overlapping components")
        return nil, false
    end

    local seen = {}
    local bestContainer, bestContainerDist = nil, math.huge
    local bestProp,      bestPropDist      = nil, math.huge

    for i = 1, #comps do
        local comp = comps[i]
        if comp ~= nil then
            local actor, kind = classifyOwner(comp)
            if actor ~= nil then
                local addr = nil
                pcall(function() addr = actor:get_address() end)
                local key = addr or actor
                if not seen[key] then
                    seen[key] = true
                    local d = math.huge
                    pcall(function()
                        local pos = actor:K2_GetActorLocation()
                        local dx = pos.X - handLoc.X
                        local dy = pos.Y - handLoc.Y
                        local dz = pos.Z - handLoc.Z
                        d = math.sqrt(dx*dx + dy*dy + dz*dz)
                    end)
                    if kind == "container" then
                        if d < bestContainerDist then bestContainerDist, bestContainer = d, actor end
                    elseif kind == "prop" then
                        if d < bestPropDist then bestPropDist, bestProp = d, actor end
                    end
                end
            end
        end
    end

    if bestContainer ~= nil then return bestContainer, false end
    if bestProp ~= nil then return bestProp, true end
    dbg("findNearbyGrabbable: " .. #comps .. " components overlapped, none grabbable")
    return nil, false
end

-- ---------------------------------------------------------------------------
-- Grab
-- Hook mesh to left VR controller. Do NOT touch collision or physics --
-- the game's item system may destroy the actor if it detects those changes.
-- ---------------------------------------------------------------------------
-- Hooks the mesh to the left controller and caches the state.
local function startHook(mesh)
    cachedHookState = nil
    local ok = pcall(function()
        local state = UEVR_UObjectHook.get_or_add_motion_controller_state(mesh)
        state:set_hand(Handed.Left)
        state:set_permanent(false)
        cachedHookState = state
    end)
    return ok and cachedHookState ~= nil
end

local function doGrab(actor, isPhysicsProp)
    if actor == nil then return false end
    pendingDrop = nil -- a new grab wins over a drop pose still being re-applied

    local mesh = nil
    -- UIDActor_ItemContainer exposes the mesh as .MeshComponent.
    -- BP_DestructibleObject_Small_C has NO .MeshComponent — use .StaticMeshComponent instead.
    -- RootComponent is intentionally excluded — it is always non-nil on any Actor and
    -- would silently grab the wrong object if MeshComponent happened to be nil.
    pcall(function() mesh = actor.MeshComponent end)
    if mesh == nil then
        pcall(function() mesh = actor.StaticMeshComponent end)
    end
    if mesh == nil then
        dbg("doGrab: no mesh component found")
        return false
    end

    local glideTime = (Config and Config.pickupGlideTime) or 0.15
    if glideTime > 0 then
        -- The hook is started by the post-stereo callback, where the controller pose
        -- is real, with offsets that keep the item exactly where it is; it then glides in.
        glide = {pending = true, pendingTicks = 0, elapsed = 0, duration = glideTime}
    else
        -- Cache the hook state at grab time so syncActorToHand never calls
        -- get_or_add_motion_controller_state (an allocation) on every tick.
        if not startHook(mesh) then
            dbg("doGrab: UEVR_UObjectHook failed")
            return false
        end
    end

    grabbed.actor       = actor
    grabbed.mesh        = mesh
    grabbedIsPhysicsProp = isPhysicsProp == true

    -- Extract Item Name
    pcall(function()
        if mesh.StaticMesh then
            grabbedItemName = mesh.StaticMesh:get_fname():to_string()
        elseif mesh.SkeletalMesh then
            grabbedItemName = mesh.SkeletalMesh:get_fname():to_string()
        else
            local fullName = mesh:get_full_name()
            local match = string.match(fullName, "%.([^%.]+)$")
            if match then grabbedItemName = match end
        end
    end)
    if not grabbedItemName then
        pcall(function() grabbedItemName = actor:get_fname():to_string() end)
    end

    -- Cache lowercase once here so syncActorToHand never re-lowercases on every tick.
    grabbedItemNameLower = grabbedItemName and string.lower(grabbedItemName) or nil

    pcall(function() grabbedActorClassName = actor:get_class():get_fname():to_string() end)

    print("[pickup] Grabbed: " .. (grabbedItemName or "unknown") .. " [" .. (grabbedActorClassName or "unknown") .. "]")
    if grabbedIsPhysicsProp then
        print("[pickup] PhysicsProp grab — drop-only mode")
    end
    
    -- Debug Materials
    if grabbedItemName and string.find(string.lower(grabbedItemName), "m16") then
        print("[pickup] DEBUG: M16 Materials:")
        pcall(function()
            for i = 0, 5 do
                local mat = mesh:GetMaterial(i)
                if mat then
                    print("[pickup] DEBUG: Material " .. tostring(i) .. " = " .. tostring(mat:get_fname():to_string()))
                else
                    print("[pickup] DEBUG: Material " .. tostring(i) .. " = nil")
                end
            end
        end)
    end

    -- Curl the left index finger while holding the item. With a glide the curl is
    -- eased in alongside the item (stepGlide); without one it snaps as before.
    if glide == nil then
        pcall(function() hands.setHandPose(Handed.Left, GRAB_FINGER_POSE) end)
    end

    return true
end

-- Resolves the held item's hook offsets: per-mesh profile, then name heuristics,
-- then the global pickupItemLocation/Rotation. Location in cm, rotation in degrees,
-- both in UEVR motion-controller-state offset space (what set_location_offset /
-- set_rotation_offset take).
local function resolveItemOffsets()
    -- Use the pre-lowercased name cached at grab time (no per-tick string allocation).
    local nameLower = grabbedItemNameLower or ""

    local cLocX, cLocY, cLocZ = offsetLoc.X, offsetLoc.Y, offsetLoc.Z
    local cPitch, cYaw, cRoll = offsetRot.Pitch, offsetRot.Yaw, offsetRot.Roll

    if Config then
        local p = Config.pickupItemProfiles and grabbedItemName and Config.pickupItemProfiles[grabbedItemName]
        if p then
            cLocX, cLocY, cLocZ = p.location[1], p.location[2], p.location[3]
            cPitch, cYaw, cRoll = p.rotation[1], p.rotation[2], p.rotation[3]
        else
            if string.find(nameLower, "bulletbox") or string.find(nameLower, "amm_") then
                cLocX, cLocY, cLocZ = 5.4, -2.0, 2.9
                cPitch, cYaw, cRoll = -83.6, 0.0, 177.5
            elseif string.find(nameLower, "notepad") then
                cLocX, cLocY, cLocZ = 3.5, 0.5, 10.2
                cPitch, cYaw, cRoll = -83.8, 0.5, -89.3
            elseif string.find(nameLower, "notes") then
                cLocX, cLocY, cLocZ = -9.3, -3.8, -12.3
                cPitch, cYaw, cRoll = -83.2, 0.0, 84.4
            elseif string.find(nameLower, "pda") then
                cLocX, cLocY, cLocZ = -15.1, -2.1, -1.5
                cPitch, cYaw, cRoll = -80.8, -0.9, -2.1
            elseif string.find(nameLower, "nvg") then
                cLocX, cLocY, cLocZ = -0.6, -0.8, 7.4
                cPitch, cYaw, cRoll = -86.7, -88.0, -2.3
            elseif string.find(nameLower, "silen") then
                cLocX, cLocY, cLocZ = -3.1, -2.9, -6.4
                cPitch, cYaw, cRoll = -100.2, 0.0, -2.2
            elseif string.find(nameLower, "photo") then
                cLocX, cLocY, cLocZ = -1.4, -4.1, 9.5
                cPitch, cYaw, cRoll = -79.7, -77.8, -12.1
            elseif string.find(nameLower, "flashdrive") or string.find(nameLower, "usb") then
                cLocX, cLocY, cLocZ = -3.0, 4.0, -5.7
                cPitch, cYaw, cRoll = 98.5, 13.8, 0.8
            elseif string.find(nameLower, "keys") then
                cLocX, cLocY, cLocZ = 3.9, -3.5, 5.8
                cPitch, cYaw, cRoll = -87.1, 5.8, -77.1
            elseif string.find(nameLower, "fol") and string.find(nameLower, "mas") and string.find(nameLower, "fac") then
                cLocX, cLocY, cLocZ = -0.8, 0.2, 9.2
                cPitch, cYaw, cRoll = -63.5, -71.1, -31.6
            elseif string.find(nameLower, "fol") and string.find(nameLower, "fac") then
                cLocX, cLocY, cLocZ = -1.0, 10.4, 11.7
                cPitch, cYaw, cRoll = 3.8, -98.8, -33.5
            elseif string.find(nameLower, "fol") then
                cLocX, cLocY, cLocZ = 13.6, 12.6, 20.5
                cPitch, cYaw, cRoll = -82.0, 0.0, -100.6
            else
                if Config.pickupItemLocation then
                    cLocX, cLocY, cLocZ = Config.pickupItemLocation[1], Config.pickupItemLocation[2], Config.pickupItemLocation[3]
                end
                if Config.pickupItemRotation then
                    cPitch, cYaw, cRoll = Config.pickupItemRotation[1], Config.pickupItemRotation[2], Config.pickupItemRotation[3]
                end
            end
        end
    end
    return cLocX, cLocY, cLocZ, cPitch, cYaw, cRoll
end

-- Writes the resolved offsets to the hook state exactly as the profiles were tuned
-- (Euler radians -> the binding's yawPitchRoll path).
local function applyItemOffsets(state)
    local cLocX, cLocY, cLocZ, cPitch, cYaw, cRoll = resolveItemOffsets()
    state:set_location_offset(Vector3f.new(cLocX, cLocY, cLocZ))
    state:set_rotation_offset(Vector3f.new(
        math.rad(cPitch),
        math.rad(cYaw),
        math.rad(cRoll)))
end

local function clearGrabState()
    grabbed.actor        = nil
    grabbed.mesh         = nil
    grabbedItemName      = nil
    grabbedItemNameLower = nil
    cachedHookState      = nil
    releaseIsIntentional = false
    grabbedIsPhysicsProp = false
    glide                = nil
    heldMeshLoc          = nil
    heldMeshRot          = nil
end

-- Sync the UEVR hook offsets to the sliders dynamically, and sync the actor's
-- world position to the mesh's visual position.
local function syncActorToHand()
    if not isGrabbing() then return end
    local actor = grabbed.actor
    local mesh  = grabbed.mesh
    if actor == nil or mesh == nil then return end

    -- CRASH GUARD: Validate the actor pointer is still alive before touching it.
    -- A stale/GC'd actor pointer causes a hard engine crash, not a Lua error.
    local actorAlive = false
    pcall(function()
        -- K2_GetActorLocation is a lightweight read; if the actor was GC'd this
        -- pcall catches the access violation and we force a clean release.
        local _ = actor:K2_GetActorLocation()
        actorAlive = true
    end)
    if not actorAlive then
        dbg("syncActorToHand: actor pointer went stale — forcing release")
        clearGrabState()
        pcall(function() hands.setHandPose(Handed.Left, GRAB_FINGER_POSE_CLEAR) end)
        return
    end

    -- Hook not started yet (glide waiting for the post-stereo callback): the mesh
    -- is still where it was in the world, nothing to sync.
    if cachedHookState == nil then return end

    -- 1. Apply offsets using the hook state cached at grab time. Skipped while the
    -- grab glide owns the offsets; it writes these exact values when it finishes.
    if glide == nil then
        pcall(function() applyItemOffsets(cachedHookState) end)
    end

    -- 2. Sync the actor's underlying transform to the mesh's current visual transform.
    pcall(function()
        local meshLoc = mesh:K2_GetComponentLocation()
        local meshRot = mesh:K2_GetComponentRotation()
        if meshLoc ~= nil then
            if meshRot ~= nil then
                actor:K2_SetActorLocationAndRotation(meshLoc, meshRot, false, {}, false)
            else
                actor:K2_SetActorLocation(meshLoc, false, {}, false)
            end
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Grab glide
-- Instead of the item jumping onto the hand, the hook starts with offsets that
-- keep it exactly where it lies, then eases them to the profile offsets over
-- Config.pickupGlideTime. The interpolation runs in controller space, so moving
-- the hand during the glide never makes the item chase it.
-- Runs from the post-stereo callback: the left MotionControllerComponent is only
-- at its real pose there (UObjectHook writes it in pre-stereo).
-- ---------------------------------------------------------------------------
local function writeGlideOffsets(state, relRot, relLoc)
    local loc, rot = offsetsFromRelative(relRot, relLoc)
    state:set_location_offset(Vector3f.new(loc.x, loc.y, loc.z))
    -- A Vector4f is cast straight onto UEVR_Quaternionf {w,x,y,z}, so pass w first
    state:set_rotation_offset(Vector4f.new(rot.w, rot.x, rot.y, rot.z))
end

-- Fallback when the glide can't start properly: the old snap.
local function snapInsteadOfGlide()
    glide = nil
    if cachedHookState == nil and not startHook(grabbed.mesh) then
        dbg("glide: UEVR_UObjectHook failed, dropping grab")
        clearGrabState()
        pcall(function() hands.setHandPose(Handed.Left, GRAB_FINGER_POSE_CLEAR) end)
        return
    end
    pcall(function() applyItemOffsets(cachedHookState) end)
    pcall(function() hands.setHandPose(Handed.Left, GRAB_FINGER_POSE) end)
end

-- Finger curl blend: setHandPose walks each bone through UFunction calls, so the
-- interpolated curl is pushed at most every FINGER_STEP_SECONDS, not every frame.
local FINGER_STEP_SECONDS = 0.033

local function applyFingerBlend(t)
    local pose = {}
    for bone, target in pairs(GRAB_FINGER_POSE) do
        pose[bone] = {target[1] * t, target[2] * t, target[3] * t}
    end
    pcall(function() hands.setHandPose(Handed.Left, pose) end)
end

local function beginGlide()
    local mesh = grabbed.mesh
    local ctrl = controllers.getController(Handed.Left)
    if mesh == nil or ctrl == nil then
        snapInsteadOfGlide()
        return
    end

    local ok = pcall(function()
        local hLoc = ctrl:K2_GetComponentLocation()
        local hRot = ctrl:K2_GetComponentRotation()
        local iLoc = mesh:K2_GetComponentLocation()
        local iRot = mesh:K2_GetComponentRotation()
        local hQ = rotatorToQuat(hRot.Pitch, hRot.Yaw, hRot.Roll)
        local iQ = rotatorToQuat(iRot.Pitch, iRot.Yaw, iRot.Roll)
        local hQi = qinv(hQ)
        glide.relRot0 = qmul(hQi, iQ)
        glide.relLoc0 = qrot(hQi, iLoc.X - hLoc.X, iLoc.Y - hLoc.Y, iLoc.Z - hLoc.Z)
        glide.relRot1, glide.relLoc1 = relativeFromOffsets(resolveItemOffsets())
    end)
    if not ok then
        snapInsteadOfGlide()
        return
    end

    if not startHook(mesh) then
        snapInsteadOfGlide()
        return
    end
    glide.pending = false
    glide.elapsed = 0
    -- Frame 0: the offsets that leave the item where it is
    if not pcall(writeGlideOffsets, cachedHookState, glide.relRot0, glide.relLoc0) then
        snapInsteadOfGlide()
    end
end

local function stepGlide()
    if glide == nil or not isGrabbing() then
        glide = nil
        return
    end
    if glide.pending then
        beginGlide()
        return
    end
    local state = cachedHookState
    if state == nil then
        glide = nil
        return
    end

    local alpha = math.min(glide.elapsed / glide.duration, 1)
    if alpha >= 1 then
        -- Land exactly on the tuned profile offsets (same values syncActorToHand writes)
        -- and the exact grab curl
        glide = nil
        pcall(function() applyItemOffsets(state) end)
        pcall(function() hands.setHandPose(Handed.Left, GRAB_FINGER_POSE) end)
        return
    end

    local eased = 1 - (1 - alpha) ^ 3 -- ease-out cubic

    if glide.lastFingerAt == nil or glide.elapsed - glide.lastFingerAt >= FINGER_STEP_SECONDS then
        glide.lastFingerAt = glide.elapsed
        applyFingerBlend(eased)
    end
    local a, b = glide.relLoc0, glide.relLoc1
    local relLoc = {
        x = a.x + (b.x - a.x) * eased,
        y = a.y + (b.y - a.y) * eased,
        z = a.z + (b.z - a.z) * eased,
    }
    if not pcall(writeGlideOffsets, state, qslerp(glide.relRot0, glide.relRot1, eased), relLoc) then
        glide = nil
        pcall(function() applyItemOffsets(state) end)
        pcall(function() hands.setHandPose(Handed.Left, GRAB_FINGER_POSE) end)
    end
end

local glideSteppedThisFrame = false

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
    glideSteppedThisFrame = false
    if glide == nil then return end
    if glide.pending then
        glide.pendingTicks = glide.pendingTicks + 1
        if glide.pendingTicks >= GLIDE_PENDING_FALLBACK_TICKS then
            -- No stereo callback (no HMD / view callbacks not firing): don't leave
            -- the item unhooked, just snap it like before.
            snapInsteadOfGlide()
        end
    else
        glide.elapsed = glide.elapsed + (delta or 0)
    end
end)

uevrUtils.registerPostCalculateStereoViewCallback(function(device, view_index)
    if glideSteppedThisFrame or (glide == nil and cachedHookState == nil) then return end
    glideSteppedThisFrame = true
    if glide ~= nil then stepGlide() end

    -- Remember where the held item really is this frame, for the drop
    local mesh = grabbed.mesh
    if cachedHookState ~= nil and mesh ~= nil then
        pcall(function()
            local l = mesh:K2_GetComponentLocation()
            local r = mesh:K2_GetComponentRotation()
            heldMeshLoc = {X = l.X, Y = l.Y, Z = l.Z}
            heldMeshRot = {Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll}
        end)
    end
end)

-- ---------------------------------------------------------------------------
-- Inventory Shoulder Zone
-- Custom wider zone for the "toss item to backpack" gesture.
-- Isolated from the shared bodyzone.lua zones so tuning this never affects
-- other gestures (reloading, holstering, etc.).
--
-- Coordinates are HMD-relative (cm), same convention as locationgesture.lua:
--   X = forward(+) / back(-)   Y = left(-)  / right(+)   Z = up(+) / down(-)
--
-- Shared bodyzone leftShoulderZoneLH:  minX=-10 maxX=20  minY=-30 maxY=-10  minZ=-20 maxZ=-5
-- This zone (wider):                   minX=-20 maxX=30  minY=-50 maxY=-5   minZ=-30 maxZ=10
-- ---------------------------------------------------------------------------
local INV_ZONE = { minX=-20, maxX=30, minY=-50, maxY=-5, minZ=-30, maxZ=10 }

local function isInInventoryShoulderZone()
    local ok = false
    pcall(function()
        local lh  = mc.LeftMotionControllerGesture
        local hmd = mc.HMDGesture
        if not lh or not hmd then return end
        if not lh.isActive or not hmd.isActive then return end

        -- Rotate hand offset by HMD yaw so coordinates are body-relative
        local rotDiff = hmd.rotation.y
        local rad     = -rotDiff / 180.0 * math.pi
        local dx = lh.location.x - hmd.location.x
        local dy = lh.location.y - hmd.location.y
        local rx =  dx * math.cos(rad) - dy * math.sin(rad)
        local ry =  dx * math.sin(rad) + dy * math.cos(rad)
        local rz = lh.location.z - hmd.location.z

        ok = rx >= INV_ZONE.minX and rx <= INV_ZONE.maxX
         and ry >= INV_ZONE.minY and ry <= INV_ZONE.maxY
         and rz >= INV_ZONE.minZ and rz <= INV_ZONE.maxZ
    end)
    return ok
end

-- ---------------------------------------------------------------------------
-- Release
-- If item is in ITEM_MAPPING AND this is an intentional grip-up release:
--   → destroy the world actor, inject XCreateItemInInventoryByID
-- Otherwise:
--   → drop item in world (existing behaviour)
-- ---------------------------------------------------------------------------
-- Drop pose re-application (see the world-drop branch of doRelease). Counted on both
-- pre- and post-engine tick, so 6 = ~3 frames.
local DROP_REAPPLY_TICKS = 6

local function applyDropPose(drop)
    pcall(function()
        if drop.rot ~= nil then
            drop.actor:K2_SetActorRotation(uevrUtils.rotator(drop.rot.Pitch, drop.rot.Yaw, drop.rot.Roll), false)
        end
        if drop.loc ~= nil then
            drop.actor:K2_SetActorLocation(uevrUtils.vector(drop.loc.X, drop.loc.Y, drop.loc.Z), false, {}, false)
        end
    end)
end

local function stepPendingDrop()
    local drop = pendingDrop
    if drop == nil then return end
    applyDropPose(drop)
    drop.ticks = drop.ticks - 1
    if drop.ticks <= 0 then pendingDrop = nil end
end

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta) stepPendingDrop() end)
uevr.sdk.callbacks.on_post_engine_tick(function(engine, delta) stepPendingDrop() end)

local function doRelease()
    if not isGrabbing() then return end

    local actor    = grabbed.actor
    local mesh     = grabbed.mesh
    local itemName = grabbedItemName  -- snapshot before we nil state
    local intentional = releaseIsIntentional

    -- Check zone BEFORE clearing any state
    local inShoulderZone = isInInventoryShoulderZone()
    local invEnabled = (Config == nil) or (Config.pickupInventoryEnabled ~= false)
    -- Physics props are always drop-only — skip inventory injection entirely.
    local protoID = nil
    if not grabbedIsPhysicsProp then
        protoID = (intentional and inShoulderZone and invEnabled) and resolvePrototypeID(itemName, mesh) or nil
    end

    -- Snapshot what the drop path needs, then clear state (safe before the branch).
    -- hookActive is false when the grab glide never got to start the hook (grip
    -- released within a frame or two): the item never moved, so leave it alone.
    local hookActive = cachedHookState ~= nil
    local dropLoc, dropRot = heldMeshLoc, heldMeshRot
    clearGrabState()

    -- Restore index finger regardless of path
    pcall(function() hands.setHandPose(Handed.Left, GRAB_FINGER_POSE_CLEAR) end)

    if protoID ~= nil then
        -- IN ZONE: suppress the world actor completely.
        -- K2_DestroyActor alone is not enough: the game's UDA/item-management layer
        -- owns UIDActor_ItemContainer and may respawn the shell at the original
        -- world location. So we layer multiple suppressions:
        --   1. Hide actor & mesh so it's invisible even if respawned.
        --   2. Teleport it deep underground so it can't be interacted with.
        --   3. Attempt K2_DestroyActor last (best-effort; may be a no-op).
        pcall(function() actor:SetActorHiddenInGame(true) end)
        pcall(function() mesh:SetVisibility(false, true) end)
        pcall(function() actor:SetActorEnableCollision(false) end)
        pcall(function() actor:K2_SetActorLocation({X=0.0, Y=0.0, Z=-100000.0}, false, {}, false) end)
        pcall(function() actor:K2_DestroyActor() end)
        local injected = injectItem(protoID)
        if injected then
            
            -- Play a short haptic vibration on the left controller
            pcall(function()
                -- Use the standard UEVR Utils helper, which safely fetches the correct OpenXR/SteamVR source
                uevrUtils.triggerHapticVibration(Handed.Left, 0.0, 0.3, 1.0, 100.0)
            end)
            
        elseif injected == false then
            -- nil = duplicate-guard skip (other script instance already injected); only warn on a real failure
            print("[pickup] WARNING: inject failed for " .. protoID .. " (kismet library / world unavailable?)")
        end
    else
        -- OUT OF ZONE (or non-intentional / unmapped): sync actor to hand one
        -- last time then remove hook so the item drops naturally in the world.
        if intentional and not inShoulderZone then
            print("[pickup] Released outside shoulder zone -- dropping in world")
        end
        if hookActive then
            -- Keep the held pose: drop from where the item actually was in the hand
            -- (post-stereo capture) instead of the controller origin. Rotation first,
            -- then the same K2_SetActorLocation call as before so the drop itself is
            -- unchanged. pickupDropKeepsPose = false restores the old origin drop.
            local keepPose = (Config == nil) or (Config.pickupDropKeepsPose ~= false)
            local drop = {actor = actor, ticks = DROP_REAPPLY_TICKS}
            if keepPose and dropRot ~= nil then
                drop.rot = {Pitch = dropRot.Pitch, Yaw = dropRot.Yaw, Roll = dropRot.Roll}
            end
            pcall(function()
                if keepPose and dropLoc ~= nil then
                    drop.loc = {X = dropLoc.X, Y = dropLoc.Y, Z = dropLoc.Z}
                else
                    local c = controllers.getControllerLocation(Handed.Left)
                    if c ~= nil then drop.loc = {X = c.X, Y = c.Y, Z = c.Z} end
                end
            end)
            applyDropPose(drop)
            pcall(function()
                UEVR_UObjectHook.remove_motion_controller_state(mesh)
            end)
            -- A non-permanent hook queues a game-thread job on every stereo pass that writes the
            -- item's ORIGINAL transform back, and a job queued before the unhook can still run
            -- after it (it only checks the component exists) -> the item snapped back to where it
            -- was picked up. Re-assert the drop pose for a few ticks so it lands after any of those.
            pendingDrop = drop
        end
    end
end

-- ---------------------------------------------------------------------------
-- XInput: left grip = XINPUT_GAMEPAD_LEFT_SHOULDER (0x0100)
-- (No XInput hook needed — grip is read from the gesture system's .isActive state)

-- ---------------------------------------------------------------------------
-- Main tick (throttled to CHECK_INTERVAL_MS)
-- ---------------------------------------------------------------------------
local function tick()
    if gameState.inMenu or gameState.isInventoryPDA then
        if isGrabbing() then
            doRelease()  -- clears finger pose internally
        end
        return
    end

    syncActorToHand()

    local handLoc     = controllers.getControllerLocation(Handed.Left)
    local gripPressed = mc.LeftGripAction.isActive and not mc.LeftTriggerAction.isActive
    local gripDown    = gripPressed and not lastGripState   -- rising edge: grip just pressed
    local gripUp      = not gripPressed and lastGripState   -- falling edge: grip just released

    if isGrabbing() then
        -- Hold to grab: intentional release on grip-up only
        if gripUp then
            releaseIsIntentional = true
            doRelease()
        end
    elseif gripDown and handLoc ~= nil then
        -- One engine sphere-overlap on the single frame grip is pressed.
        -- Item containers take priority over world physics props.
        local target, isProp = findNearbyGrabbable(handLoc)
        if target ~= nil then
            doGrab(target, isProp)
        end
    end

    lastGripState = gripPressed
end

setInterval(CHECK_INTERVAL_MS, tick)

-- ---------------------------------------------------------------------------
-- Cleanup
-- ---------------------------------------------------------------------------
uevrUtils.registerPreLevelChangeCallback(function()
    if isGrabbing() then doRelease() end
    lastGripState = false
end)

uevr.params.sdk.callbacks.on_script_reset(function()
    if isGrabbing() then doRelease() end
end)

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------
function M.isGrabbing()     return isGrabbing() end
function M.getGrabbedItem() return grabbed.actor end
-- The mesh while it is hooked to the left controller (nil before the grab glide has started the hook).
-- stalker2/ik_weapon_sync.lua draws it locked to the left IK hand; this script exists twice (UEVR auto-load +
-- Entry.lua's require), so every instance registers its getter.
function M.getHeldMesh()
    if cachedHookState == nil then return nil end
    return grabbed.mesh
end
_G.PickupHeldMeshGetters = _G.PickupHeldMeshGetters or {}
table.insert(_G.PickupHeldMeshGetters, M.getHeldMesh)
function M.getGrabbedItemName() return grabbedItemName end
function M.getGrabbedActorClassName() return grabbedActorClassName end
function M.setDebug(val)    DEBUG_PRINT = val end
function M.setRadius(r)
    GRAB_RADIUS = r
end

--- Set the location and rotation offset applied to held items.
--- Called by the config UI sliders (hot-applied without reload).
function M.setOffset(lx, ly, lz, pitch, yaw, roll)
    offsetLoc.X     = lx    or 0.0
    offsetLoc.Y     = ly    or 0.0
    offsetLoc.Z     = lz    or 0.0
    offsetRot.Pitch = pitch or 0.0
    offsetRot.Yaw   = yaw   or 0.0
    offsetRot.Roll  = roll  or 0.0
end

function M.getOffset()
    return offsetLoc.X, offsetLoc.Y, offsetLoc.Z,
           offsetRot.Pitch, offsetRot.Yaw, offsetRot.Roll
end

-- Load initial offsets from Config if available
pcall(function()
    if Config and Config.pickupItemGrabRadius then
        M.setRadius(Config.pickupItemGrabRadius)
    end
end)

return M
