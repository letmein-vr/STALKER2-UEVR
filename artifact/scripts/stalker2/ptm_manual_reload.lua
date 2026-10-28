-- ptm_manual_reload.lua
-- Physical Mag Reload - Left-Grip driven state machine.
--
-- EJECT:    left grip PRESSED + hand overlapping MagBox (STATE_IDLE)
--           -> hide weapon mag, spawn empty proxy in left hand (EJECT_HOLD)
--           -> grip RELEASED -> proxy detaches, kinematic fall (DROPPING_EMPTY)
--           -> proxy hits floor -> destroyed (DROPPED)
--
-- HIP GRAB: left grip PRESSED + left hand in leftHipZoneLH (STATE_DROPPED)
--           -> spawn full proxy in left hand (HIP_HOLD)
--           -> grip RELEASED near socket -> INSERT, reload complete (IDLE)
--           -> grip RELEASED far -> proxy destroyed, must return to hip (DROPPED)
--
-- AUTO:     empty-clip native montage intercepted -> proxy auto-ejects,
--           kinematic fall -> DROPPED -> player must hip-grab to reload

local utils     = require("common/utils")
local uevrUtils = require("libs/uevr_utils")
local plugin    = require("libs/core/plugin")
-- Must stay dot-form: "Config/CONFIG" is a distinct package.loaded key from "Config.CONFIG",
-- so the slash spelling runs CONFIG.lua a second time, building a second Config table whose
-- module-scope `Config = {...}` then hijacks the global every other file reads through.
local Config    = require("Config.CONFIG")
local magReload = require("stalker2.mag_reload")
local quat      = require("libs/core/quat_math")
local controllers = require("libs/controllers")
local bodyItems = require("stalker2.body_items")
local rackSlide = require("stalker2.rack_slide")

local M = {}

-- Optional per-weapon overrides, keyed by SkeletalMesh get_fname().
-- Only needed to supply charMontage fallback paths for tactical-first ammo
-- replenishment (before the player has ever run dry on that weapon).
-- Mag meshes and proxy mesh are always auto-discovered at runtime - no
-- entry here is required for a weapon to support manual reload.
-- Comprehensive weapon → charMontage map derived from montage_parameters.json.
-- Each entry uses the TACTICAL reload montage as it is shortest and still fires
-- AnimNotify_WeaponAction (which replenishes ammo).  The tactical path is also
-- the montage the native engine uses for non-empty clip reloads, so it is the
-- correct counterpart for our physical tac-reload gesture.
-- Source: data/montage_parameters.json (all class_name entries containing "reload").
local WEAPON_PROFILES = {
    -- ── Pistols (pt) ─────────────────────────────────────────────────────────
    ["sk_pm"]       = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/pt/pm/Reload/TwoHands/MG_fp_pm_reload_tactical.MG_fp_pm_reload_tactical" },
    ["sk_udp"]      = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/pt/udp/Reload/TwoHands/MG_fp_udp_reload_tactical.MG_fp_udp_reload_tactical" },
    ["sk_apb"]      = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/pt/apb/Reload/TwoHands/MG_fp_apb_reload_tactical.MG_fp_apb_reload_tactical" },
    ["sk_kora"]     = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/pt/Kora/Reload/TwoHands/MG_fp_kora_reload_tactical.MG_fp_kora_reload_tactical" },
    -- Rhino revolver - no tactical variant, use base reload. seatOnSocket: the speedloader
    -- insert glide seats on the MagBox socket + per-weapon seat offset (see startInsertGlide).
    -- flickToClose: once the speedloader is seated it stays in the cylinder (STATE_AWAIT_CLOSE)
    -- until the right hand flicks to the right, then the reload completes (Config.ptmFlickToClose).
    ["sk_rhino"]    = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/pt/rhino/Reload/TwoHands/MG_fp_rhino_double_action_reload.MG_fp_rhino_double_action_reload", openCylinderTime = 0.5, introJumpTicks = 125, seatOnSocket = true, flickToClose = true },
    -- ── Submachine Guns (smg) ─────────────────────────────────────────────────
    ["sk_aku"]      = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/smg/aku/Reload/MG_fp_aku_reload_tactical.MG_fp_aku_reload_tactical" },
    ["sk_vip"]      = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/smg/viper/Reload/MG_fp_viper_reload_tactical.MG_fp_viper_reload_tactical" },
    ["sk_viper"]    = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/smg/viper/Reload/MG_fp_viper_reload_tactical.MG_fp_viper_reload_tactical" },
    ["sk_integral"] = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/smg/integral/Reload/MG_fp_integral_reload_tactical.MG_fp_integral_reload_tactical" },
    -- Integral A: fname is SK_integ (NOT SK_integral). Keep both keys in case a longer variant exists.
    ["sk_integ"]    = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/smg/integral/Reload/MG_fp_integral_reload_tactical.MG_fp_integral_reload_tactical" },
    ["sk_bucket"]   = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/smg/bucket/Reload/MG_fp_bucket_reload_tactical.MG_fp_bucket_reload_tactical" },
    ["sk_m10"]      = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/smg/m10/Reload/TwoHands/MG_fp_m10_reload_tactical.MG_fp_m10_reload_tactical" },
    ["sk_zubr"]     = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/smg/zubr/Reload/MG_fp_zubr_reload_tactical.MG_fp_zubr_reload_tactical" },
    -- Fora-230: MCP-confirmed 2026-09-04. IMPORTANT - this is a REAL PREFIX-MATCH BUG
    -- FIX, not just an ambiguity-pin like SKP/GP3A/Arev above: this weapon's fname is
    -- SK_Fora230 (lowercase "sk_fora230", 10 chars), which starts with the existing
    -- 7-char "sk_fora" key (the unrelated AR "Fora" rifle, ar/fora/ folder) - without
    -- this longer explicit entry, M.init()'s descending-length prefix matcher would
    -- silently match Fora-230 (an SMG) against the AR Fora's charMontage, an entirely
    -- wrong montage path. Two tactical-scored candidates also exist here
    -- (MagDefault_Tactical_01 / MagIncreased_Tactical_01, smg/Fora230/Reload/) - no
    -- capacity-upgrade attachment was present on the live scan, so pinned to
    -- MagDefault_Tactical. Mag body meshes are SM_Wpn_Fora230_Mag_Full_01/_Empty_01 -
    -- already matched by the existing _mag_full/_mag_empty pattern, no
    -- collectMagMeshes() change needed.
    ["sk_fora230"]  = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/smg/Fora230/Reload/MG_FP_Player_Fora230_Reload-MagDefault_Tactical_01.MG_FP_Player_Fora230_Reload-MagDefault_Tactical_01" },
    -- ── Assault Rifles (ar) ───────────────────────────────────────────────────
    ["sk_ak74"]     = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/ar/ak74/reload/MG_fp_ak74_reload_tactical.MG_fp_ak74_reload_tactical" },
    ["sk_m160"]     = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/ar/m16/Reload/MG_fp_m16_reload_tactical.MG_fp_m16_reload_tactical" },
    ["sk_m16"]      = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/ar/m16/Reload/MG_fp_m16_reload_tactical.MG_fp_m16_reload_tactical" },
    ["sk_fora"]     = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/ar/fora/Reload/MG_fp_fora_reload_tactical.MG_fp_fora_reload_tactical" },
    ["sk_gp37"]     = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/ar/gp37/reload/MG_fp_gp37_reload_tactical.MG_fp_gp37_reload_tactical" },
    ["sk_grim"]     = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/ar/grim/Reload/MG_fp_grim_reload_tactical.MG_fp_grim_reload_tactical" },
    ["sk_gvintar"]  = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/ar/gvintar/Reload/MG_fp_gvintar_reload_tactical.MG_fp_gvintar_reload_tactical" },
    -- VS Vintar: fname is SK_gvi (NOT SK_gvintar). Montage folder is still ar/gvintar/.
    ["sk_gvi"]      = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/ar/gvintar/Reload/MG_fp_gvintar_reload_tactical.MG_fp_gvintar_reload_tactical" },
    ["sk_kharod"]   = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/ar/kharod/Reload/MG_fp_kharod_reload_tactical.MG_fp_kharod_reload_tactical" },
    ["sk_lavina"]   = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/ar/lavina/Reload/MG_fp_lavina_reload_tactical.MG_fp_lavina_reload_tactical" },
    -- AS Lavina: fname is SK_lav (NOT SK_lavina). Montage folder is still ar/lavina/.
    ["sk_lav"]      = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/ar/lavina/Reload/MG_fp_lavina_reload_tactical.MG_fp_lavina_reload_tactical" },
    ["sk_dnipro"]   = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/ar/dnipro/Reload/MG_fp_dnipro_reload_tactical.MG_fp_dnipro_reload_tactical" },
    -- Arev: MCP-confirmed 2026-09-04, standard detachable box-magazine weapon, not
    -- tube-fed. Worse tie-break risk than SKP/GP3A above: SIX reload montages exist
    -- (MagDefault/MagIncreased/MagHuge x base/_Tactical, all sharing a "_BL01_01"
    -- suffix that is NOT a capacity marker - just this weapon's fixed animator-rig
    -- id), three of which ("_Tactical_") would tie-score identically in
    -- discoverReloadMontage() without this entry. No mag-capacity attachment was
    -- present on the live weapon scan (only the base jnt_magazine_master mag pair),
    -- so pinned to the Default-capacity tactical montage as the base-equipped state.
    -- Mag body meshes are SM_Wpn_Arev_Mag_Full_01/_Empty_01 on jnt_magazine_master -
    -- already matched by the existing _mag_full/_mag_empty pattern in
    -- collectMagMeshes() (unlike SKP/GP3A, no naming-pattern fix was needed here).
    ["sk_arev"]     = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/ar/Arev/Reload/MG_FP_Player_Arev_Reload-MagDefault_Tactical_BL01_01.MG_FP_Player_Arev_Reload-MagDefault_Tactical_BL01_01" },
    -- ── Shotguns (shg) ────────────────────────────────────────────────────────
    ["sk_d12"]      = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/shg/d12/Reload/MG_fp_d12_reload_tactical.MG_fp_d12_reload_tactical" },
    -- M860 standard (tube-fed) and M860 "bigmag" (detachable box mag) are SEPARATE
    -- ATTACHMENTS on the exact same weapon, not separate weapons - MCP-confirmed
    -- 2026-08-16 by equipping both live and reading SkeletalMesh:get_fname() on each:
    -- BOTH report "SK_m86000". The prefix matcher can never tell them apart by name -
    -- sk_m860 (7 chars) is consequently unreachable, since any "SK_m86000..." weapon
    -- always matches the longer "sk_m86000" (9 chars) key first. sk_m860's entry below
    -- is kept only as a DATA SOURCE, referenced directly (not via the matcher) by the
    -- runtime AttachChildren scan in M.init() - see isM860BigmagEquipped().
    -- introJumpTicks is an untuned starting guess (proportioned like SPSA's, since this
    -- montage is a near-identical 2.994s vs RAM2's 5.3s) - watch it in-game and adjust.
    ["sk_m86000"]   = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/shg/m860/Reload/MG_fp_m860_reload_increased_tactical.MG_fp_m860_reload_increased_tactical" },
    ["sk_m860"]     = { isTubeFed = true, openCylinderTime = true, introJumpTicks = 1,
                        charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/shg/m860/Reload/MG_fp_m860_reload_tactical.MG_fp_m860_reload_tactical" },
    -- MCP-confirmed 2026-08-17 (live, equipped): break-action double-barrel, same shape
    -- as TOZ-34 - linear 5.8s montage (Default->Ejected->Inserted, ReEjected->ReInserted,
    -- no self-looping section), 3x AnimNotify_WeaponAction baked into the one pass. Live
    -- shells SM_wpn_obrez_SM_bullet_01/_02 on jnt_bullet_01/jnt_bullet_02 (sm_wpn_ prefix,
    -- no sm_amm_) - covered by the generic isTubeFed filter already, and jnt_bullet_01 is
    -- already a native fallback tier in mag_reload.lua's socket chain (no override needed
    -- at all, not even the settings.json-side one TOZ-34 has). Same reloadStartOnOverlap /
    -- hideShellsDuringReload / shellsPerGrab treatment as TOZ-34, per user request ("same
    -- method"). introJumpTicks proportioned off TOZ-34's tuned 32 since the montage length
    -- is identical (5.8s both) - still just a starting guess, watch and adjust.
    ["sk_obrez"]    = { isTubeFed = true, openCylinderTime = true, introJumpTicks = 72,
                        reloadStartOnOverlap = true, hideShellsDuringReload = true, shellsPerGrab = 2,
                        charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/shg/obrez/Reload/MG_fp_obrez_reload_tactical.MG_fp_obrez_reload_tactical" },
    -- openCylinderTime here is only ever checked for truthiness (see Rhino's comment
    -- below) - it's what triggers the animJumpActive "let the intro play, then freeze"
    -- sequence in tryInterceptReload. introJumpTicks is interpreted as ticks at a 60fps
    -- reference and converted to a real-seconds duration (see ANIM_JUMP_REFERENCE_FPS) -
    -- defaults to 120 (Rhino's current tuned value) if omitted.
    ["sk_ram2"]     = { isTubeFed = true, openCylinderTime = true, introJumpTicks = 30,
                        charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/shg/ram2/Reload/MG_fp_ram2_reload_tactical.MG_fp_ram2_reload_tactical" },
    -- MCP-confirmed 2026-08-16 (live, while equipped): tactical montage 2.667s, sections
    -- Default->In->In(loop)->Out/SingleBulletOut - identical shape to RAM2's. Live shell is
    -- on jnt_bullet (SM_amm_spsa00_SM_bullet) - already in mag_reload.lua's socket fallback
    -- chain, so no magSocket override needed. introJumpTicks is an untuned starting guess
    -- (half of RAM2's 30, since this montage is roughly half RAM2's length) - watch it
    -- in-game and adjust.
    ["sk_spsa"]     = { isTubeFed = true, openCylinderTime = true, introJumpTicks = 1,
                        charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/shg/spsa/Reload/MG_fp_spsa_reload_tactical.MG_fp_spsa_reload_tactical" },
    -- MCP-confirmed 2026-08-16 (live, both equipped): break-action double-barrel, so the
    -- tactical montage is LINEAR (Default->Ejected->ReEjected, no self-looping "In" section
    -- like the pump guns) with 2x AnimNotify_WeaponAction baked into that one pass - both
    -- barrels load in a single fast-forward, which is correct here (2-shell capacity, no
    -- repeat-per-shell loop to jump back into). Live shells on jnt_bullet1/jnt_bullet2
    -- (sm_wpn_ prefix, no sm_amm_) - already covered by the generic isTubeFed filter, no
    -- code changes needed there. magSocket is NOT set here - ptm_manual_reload.lua never
    -- reads a profile.magSocket field; the actual box socket is Config.weaponProfiles
    -- (settings.json) driven and already set to "jnt_ejector" for this weapon.
    -- reloadStartOnOverlap: per user request, start the reload the same way as the
    -- Rhino/box-mag EJECT trigger (grip + weapon-box overlap) rather than the hip-zone
    -- start every other isTubeFed weapon uses - shell-grab-to-insert once parked is still
    -- always hip-zone, same as the others.
    ["sk_toz34"]    = { isTubeFed = true, openCylinderTime = true, introJumpTicks = 55,
                        reloadStartOnOverlap = true, hideShellsDuringReload = true, shellsPerGrab = 2,
                        charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/shg/toz34/Reload/MG_fp_toz34_reload_tactical.MG_fp_toz34_reload_tactical" },
    -- ── Sniper / Marksman Rifles (sr) ────────────────────────────────────────
    ["sk_mark"]     = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/sr/mark/Reload/MG_fp_mark_reload_tactical.MG_fp_mark_reload_tactical" },
    -- Mark 1 EMR: fname is SK_mar (NOT SK_mark). Montage folder is still sr/mark/.
    ["sk_mar"]      = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/sr/mark/Reload/MG_fp_mark_reload_tactical.MG_fp_mark_reload_tactical" },
    -- SVDm sniper: weapon fname is SK_svm (NOT SK_svdm). Montage folder is still sr/svdm/.
    -- Discovery key will be "svm" which is a substring of "svdm" montage names -> still matches.
    ["sk_svm"]      = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/sr/svdm/Reload/MG_fp_svdm_reload_tactical.MG_fp_svdm_reload_tactical" },
    ["sk_svu"]      = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/sr/svu/Reload/MG_fp_svu_reload_tactical.MG_fp_svu_reload_tactical" },
    ["sk_m701"]     = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/sr/m701/Reload/MG_fp_m701_reload_tactical.MG_fp_m701_reload_tactical" },
    -- ── Designated Marksman Rifles (dmr) ──────────────────────────────────────
    -- SKP: MCP-confirmed 2026-09-04, standard detachable box-magazine weapon
    -- (Default/Increased capacity variants), not tube-fed. Without this entry,
    -- discoverReloadMontage()'s scoring gives MG_FP_Player_Skp_Reload-MagDefault_
    -- Tactical_01 and -MagIncreased_Tactical_01 an identical score (both +2 for
    -- "tactical", nothing else to break the tie), so the fallback picks whichever
    -- the native object scan happens to return first - not necessarily the montage
    -- matching the actually-equipped magazine. On this weapon's first PTM reload
    -- of a session (before any native reload has primed interceptedCharMontage),
    -- INSERT falls into the direct char-only Montage_Play path; a mismatched
    -- montage there froze the game entirely (animations stuck, no weapon switch
    -- possible). Pin explicitly to the Default-capacity tactical montage, matching
    -- this weapon's actual default-equipped magazine.
    -- Mag body meshes are SM_Wpn_SKP_MagDefault_Full_01/_Empty_01 on
    -- jnt_magazine_master - see the magdefault_full/magdefault_empty pattern
    -- added to collectMagMeshes() above (2026-09-04) for why a dedicated
    -- pattern was needed instead of relying on the generic _mag_full/_mag_empty
    -- match.
    ["sk_skp"]      = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/dmr/skp/Reload/MG_FP_Player_Skp_Reload-MagDefault_Tactical_01.MG_FP_Player_Skp_Reload-MagDefault_Tactical_01" },
    -- GP3A: MCP-confirmed 2026-09-04, standard detachable box-magazine weapon, not
    -- tube-fed - same class of issue as SKP above, but with THREE tactical-scored
    -- reload montages instead of two: MG_FP_Player_Gp3a_Reload-MagDefault_Tactical_01,
    -- -MagIncreased_Tactical_01, and -MagHuge_01 (the last has no "tactical" in its
    -- name so it doesn't tie-score with the other two, but Default vs Increased still
    -- would without this entry). Pin explicitly to the Default-capacity tactical
    -- montage, matching this weapon's actual default-equipped magazine (live-confirmed:
    -- equipped mag mesh was SM_Wpn_Gp3A_MagDefault_Full_01, not the Increased/Huge
    -- variant). Mag body meshes are SM_Wpn_Gp3A_MagDefault_Full_01/_Empty_01 on
    -- jnt_magazine_master (plus a duplicate pair on jnt_magazine_slave) - already
    -- covered by the magdefault_full/magdefault_empty pattern added to
    -- collectMagMeshes() above, no further changes needed there. Note the montage
    -- asset root differs from SKP's - this weapon's char-side reload lives under
    -- Player/AnimSequences/dmr/GP3A/Reload/ (capital GP3A), not dmr/skp/ lowercase -
    -- do not assume a shared casing convention across weapons in the same category.
    ["sk_gp3a"]     = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/dmr/GP3A/Reload/MG_FP_Player_Gp3a_Reload-MagDefault_Tactical_01.MG_FP_Player_Gp3a_Reload-MagDefault_Tactical_01" },
    -- MCP-confirmed 2026-08-17 (live, equipped): bolt-action internal magazine, NOT a
    -- detachable box mag - both char-side reload montages (base 7.0s, tactical 7.4667s)
    -- have sections Default->In->In(loop)->Out/SingleBulletOut with 2x AnimNotify_WeaponAction
    -- baked into the looping "In" section - identical shape to RAM2/SPSA/M860's tube-fed
    -- montages (one bullet loaded per loop pass). Weapon-mesh side additionally has separate
    -- reload_clips/unload_clips (stripper-clip, single linear pass, no loop) and
    -- reload_single_bullet/unload montages, but reload_montages.txt (the native-reload
    -- montage set actually reachable from the base game) only lists the base/tactical pair
    -- above, so the clip montages are not in play here - treat this exactly like the
    -- pump-action tube-fed shotguns (RAM2/SPSA), not the break-action ones (TOZ-34/Obrez):
    -- no reloadStartOnOverlap - there's no separate magazine part to grab, the loose-round
    -- hip-grab is the whole gesture. introJumpTicks proportioned off TOZ-34's tuned 45 for
    -- its 5.8s montage, scaled to this weapon's 7.4667s tactical montage - still just a
    -- starting guess, watch it in-game and adjust.
    ["sk_threeline"]= { isTubeFed = true, openCylinderTime = true, introJumpTicks = 65,
                        charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/sr/ThreeLine/Reload/MG_fp_threeline_reload_tactical.MG_fp_threeline_reload_tactical" },
    -- Gauss - no tactical variant, use base reload
    ["sk_gauss"]    = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/sr/gauss/Reload/MG_fp_gauss_reload.MG_fp_gauss_reload" },
    -- ── Machine Guns (mg) ─────────────────────────────────────────────────────
    ["sk_pkp"]      = { charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/mg/pkp/Reload/MG_fp_pkp_magdefault_reload.MG_fp_pkp_magdefault_reload" },
    -- ── Grenade Launchers (gl) ────────────────────────────────────────────────
    -- RPG-7, MCP live-scanned 2026-09-21 (equipped). Single-round launcher, no detachable part:
    --   * children of SK_rpg7: SM_wpn_rpg7_SM_offset/hammer/ring/trigger plus the rocket itself,
    --     SM_amm_rpg7, on socket jnt_ammo_move (component "WeaponAttachmentSM_amm_rpg7...").
    --   * sockets: NONE of the magazine/bullet sockets mag_reload.lua looks for (no
    --     jnt_magazine*, jnt_mag_tab, jnt_clip_base, jnt_bullet*) - that is why the manual reload
    --     never worked: the MagBox had nothing to attach to, so no overlap could ever register.
    --     jnt_ammo_move rides the reload animation, so the static "Muzzle" socket is used as the
    --     insert target (magSocket), which is also where a rocket physically goes in.
    --   * exactly ONE char-side reload montage (no tactical variant, so no tie-break risk):
    --     6.33 s, sections Default->Inserted->ReInserted, AnimNotify_WeaponAction at 3.31 s.
    -- Nothing is swapped out, one round is added - the tube-fed flow, not the box-mag one: grab
    -- a rocket at the hip, bring it to the muzzle, release. The rocket mesh is hidden while the
    -- native reload is parked (hideShellsDuringReload) because the native animation carries it in
    -- with a hand that does not exist in VR. introJumpTicks = 1 freezes straight away, well before
    -- the 3.31 s notify; the INSERT fast-forward then crosses it and the game adds the round.
    -- ammoMeshPattern: the rocket matches none of the mag/shell name patterns in
    -- collectMagMeshes(). proxyMesh: fallback for the held rocket when no live child is found.
    -- seatOnSocket: the insert glide seats the rocket on the Muzzle socket + the per-weapon seat
    -- offset (dev panel), not on the hidden rocket mesh - that rides jnt_ammo_move, which the
    -- paused reload montage holds wherever it froze.
    ["sk_rpg7"]     = { isTubeFed = true, openCylinderTime = true, introJumpTicks = 1,
                        hideShellsDuringReload = true, magSocket = "Muzzle", seatOnSocket = true,
                        ammoMeshPattern = "sm_amm_rpg7",
                        proxyMesh = "StaticMesh /Game/_Stalker_2/weapons/grenade_launcher/SM_gl_rpg7/AnimMesh/SM_amm_rpg7.SM_amm_rpg7",
                        charMontage = "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/gl/rpg7/Reload/MG_fp_rpg7_reload.MG_fp_rpg7_reload" },
}

-- Constants
local GRIP_BUTTON        = XINPUT_GAMEPAD_LEFT_SHOULDER
local X_BUTTON           = 0x4000   -- XINPUT_GAMEPAD_X: reload / mag kick-out; pistol slide release in STATE_AWAIT_RACK
local INSERT_DISTANCE_CM = 12.0
local DROP_GRAVITY_CM    = 980.0   -- cm/s², UE default gravity for kinematic drop

-- Tube-fed (isTubeFed): no eject/drop step - nothing is swapped out, shells are
-- only ever added. Grabbing a shell at the hip spoofs a native reload and parks
-- (pauses) it; bringing the shell to the loading port and releasing unpauses and
-- fast-forwards it. See the INSERT block in on_pre_engine_tick for why it has to
-- work this way rather than playing a montage directly.
--
-- 15x matches the rate the box-magazine INSERT already uses for isTubeFed
-- weapons: 100x overflows the weapon AnimBP's self-looping In->In section's
-- native section-change callbacks and crashes. Raise cautiously.
local SHELL_INSERT_RATE     = 20.0
local SHELL_INSERT_DURATION = 0.7    -- seconds of real time to hold the fast-forward
-- Lateral offset (proxy-local units) between shells for profiles with shellsPerGrab > 1
-- (TOZ-34: both barrels load from one grab). Untuned starting guess - same rough scale
-- as the Rhino moon-clip's radius=1.4 - watch in-game and adjust.
local SHELL_GRAB_SPACING    = 2.5

local DEFAULT_LOC = {-4.000, 4.000, -1.000}
local DEFAULT_ROT = {-35.000, 0.000, 10.000}

local function getProxyLoc() return Config.ptmMagProxyLocation or DEFAULT_LOC end
local function getProxyRot() return Config.ptmMagProxyRotation or DEFAULT_ROT end

-- State Machine
local STATE_IDLE           = 0
local STATE_EJECT_HOLD     = 1
local STATE_DROPPING_EMPTY = 2
local STATE_DROPPED        = 3
local STATE_HIP_HOLD       = 4
local STATE_SHELL_HOLD     = 5   -- isTubeFed only: holding one shell, grabbed straight from hip, no eject/drop precursor
local STATE_INSERTING      = 6   -- box mags: fresh proxy gliding from the hand into the magwell before the reload completes
local STATE_AWAIT_CLOSE    = 7   -- flickToClose profiles (Rhino): loader seated, waiting for a right-hand flick to close
local STATE_AWAIT_RACK     = 8   -- box mags after an EMPTY reload: mag seated, waiting for the slide / handle rack (rack_slide.lua)

local currentState = STATE_IDLE

-- Reload diagnostics (2026-10-27, hunting an intermittent "fresh mag won't go into the magwell").
-- Event-only lines in log.txt, prefixed [ReloadDiag]: state changes, left-grip edges while a reload is
-- active, the HIP_HOLD release decision and insert-glide exits. print() never reaches log.txt on this
-- build; log_info does. Set false to silence once the cause is found.
local RELOAD_DIAG = false
local STATE_NAMES = {[0] = "IDLE", "EJECT_HOLD", "DROPPING_EMPTY", "DROPPED", "HIP_HOLD", "SHELL_HOLD",
    "INSERTING", "AWAIT_CLOSE", "AWAIT_RACK"}
local function diag(fmt, ...)
    if not RELOAD_DIAG then return end
    local msg = string.format(fmt, ...)
    pcall(function() uevr.params.functions.log_info(string.format("[ReloadDiag] %.3f %s", os.clock(), msg)) end)
end
local function stateName(s) return STATE_NAMES[s] or tostring(s) end
local diagLastState = STATE_IDLE

-- Box-mag insert glide (STATE_INSERTING). On a near-socket release the fresh proxy is
-- re-parented in place onto the REAL mag's socket, eased to a "pre-seat" pose backed out
-- along the insertion axis (align), then slid straight in to the real mag's transform
-- (seat). On the seat frame the real mags are unhidden and the proxy destroyed - same mesh
-- asset, same transform, so the swap is invisible - then the normal INSERT completion runs.
-- nil when not inserting, else
-- {pending, pendingTicks, elapsed, duration, proxy, weaponMesh, targetChild,
--  fromLoc, fromQuat, preLoc, toLoc, toQuat, toRot}
local insertGlide = nil
-- STATE_AWAIT_CLOSE (flickToClose profiles): nil, else
-- {proxy (may be nil), profile, weaponAddr, elapsed, last = {tip, top} | nil, hits}
local awaitClose = nil
-- Rack to chamber: the intercepted native reload was the EMPTY one (montage name without "tactical" -
-- the game picks it from its own chamber state), the left grip was pressed while waiting for the rack,
-- and the raw right trigger (for rack_slide.lua's travel learning).
local reloadWasEmpty    = false
local rackGrabRequested = false
local rackSlideReleaseRequested = false   -- STATE_AWAIT_RACK: X pressed on a pistol (slide release), handled in the tick
local rawTriggerHeld    = false
-- Hip grab glide (2026-10-17): the fresh mag / shell taken from the belt pouch starts where the pouch item was and
-- eases into its place in the hand. nil, else
-- {proxy, pouch, pending, pendingTicks, elapsed, duration, fromLoc, fromQuat, fromScale, toLoc, toQuat}
local grabGlide = nil
local DEFAULT_GRAB_GLIDE_TIME = 0.12
local INSERT_PENDING_FALLBACK_TICKS = 3
local INSERT_ALIGN_FRACTION         = 0.55  -- share of the glide spent aligning; the rest is the straight seat
local DEFAULT_INSERT_AXIS           = {0.0, 0.0, -1.0} -- weapon component space, points OUT of the magwell
local DEFAULT_INSERT_DEPTH          = 6.0   -- cm the pre-seat pose is backed out along the axis
local DEFAULT_INSERT_GLIDE_TIME     = 0.16  -- seconds; 0 = old instant snap

-- Runtime vars
local ejectProxy    = nil
local droppingProxy = nil
local heldProxy     = nil
local shellProxy    = nil        -- isTubeFed only: the single shell currently held in STATE_SHELL_HOLD
local magMeshes     = {}
local dropVelocity  = 0          -- cm/s, kinematic drop speed accumulator
local dropProxyReady = false     -- true once initial world-location has been set
local leftHandComp  = nil
local activeProfile = nil

-- Input state
local currentButtons = 0
local wasGripHeld    = false
local wasGripXinput  = false
local wasXXinput     = false
local xLatchedForSlideRelease = false   -- X that released a pistol slide: masked from the game until let go
local handInHipZone  = false

-- Reload anim state
local tacticalReloadTriggerTime = 0
local reloadCooldownEndTime     = 0
local interceptedCharMontage    = nil
-- One-tick deferred resets: after INSERT runs meshes at 1000x, next tick resets rates to 1.0.
-- These are FLAGS, not object handles: the char mesh / weapon mesh they act on are
-- re-resolved from the pawn when the deferred action fires (see isAlive() note).
local charAnimFastForwardArmed  = false -- fast-forward char mesh on next tick (deferred by 1 tick)
local charAnimResetArmed        = false
local charAnimResetTime         = 0    -- os.clock() deadline to restore charMesh GlobalAnimRateScale
local weaponAnimResetArmed      = false
local weaponAnimResetTime       = 0    -- os.clock() deadline to restore weaponMesh GlobalAnimRateScale
-- Box-mag INSERT fast-forward: rate both meshes run at to burn through the rest of the
-- reload, and how long it's held. The window is sized from the reload montage's length at
-- that rate (+ margin for the anim thread) instead of a flat 0.15 s, so the meshes don't keep
-- running their idle at 100x after the reload is already over (the visible "sped-up" frames).
local DEFAULT_FINISH_RATE       = 100.0
local FINISH_WINDOW_MARGIN      = 0.05  -- s; anim-thread lag allowance (see charAnimResetArmed)
local FINISH_WINDOW_MAX         = 0.15  -- s; the old fixed window, also the fallback
local finishRate                = DEFAULT_FINISH_RATE
local finishWindow              = FINISH_WINDOW_MAX
-- Intro-jump ("let the reload animation play a bit, then freeze") is timed in real
-- seconds, NOT engine ticks. It used to be a raw per-`on_pre_engine_tick`-call counter
-- (animJumpPhase incrementing to animJumpTargetTicks), which made the freeze point
-- framerate-dependent: at introJumpTicks=58 the window lasted ~0.97s at 60fps but
-- ~1.7s at 34fps, since both meshes play unpaused at 1.0x for the whole window and
-- ticks arrive at very different real rates depending on framerate. Profile authors
-- still tune a "ticks" number (kept for backward compatibility with every existing
-- WEAPON_PROFILES entry) but it's now interpreted as ticks-at-a-60fps-reference and
-- converted to a target duration in seconds, so the freeze lands at the same point in
-- the animation regardless of the player's actual framerate.
local ANIM_JUMP_REFERENCE_FPS   = 60
local animJumpActive            = false -- true while the intro-jump window is running
local animJumpElapsed           = 0.0   -- accumulated real seconds since the jump started
local animJumpTargetSeconds     = 2.0   -- per-reload target, set from p.introJumpTicks / ANIM_JUMP_REFERENCE_FPS
local spoofingTacticalReload    = false
local forceNativeReloadTicks    = 0
-- Wall-clock cap on the spoofed-X hold. forceNativeReloadTicks alone counts POLLS,
-- not time - and the game decides short-vs-long press by wall-clock duration. If a
-- frame stalls while the spoof is mid-flight (the montage discovery scan used to do
-- exactly this on the first reload of a session), those few polls stretch across
-- hundreds of ms and the engine reads our reload spoof as a LONG press of X, firing
-- whatever long-press action is bound on top of the reload (quick-use consumable).
-- The deadline is armed on the first poll that ACTUALLY injects X - not when the
-- spoof is requested - so a stall occurring before delivery can't expire the press
-- before the engine has seen it at all.
local FORCE_RELOAD_MAX_HOLD     = 0.12  -- seconds; well under any long-press threshold
local forceNativeReloadDeadline = 0
-- Master switch (Config.enableManualReload, pushed in via M.setEnabled). When false the
-- whole FSM is inert: native reloads are never intercepted/paused, so Entry.lua's legacy
-- path (support hand attached to the weapon's jnt_l_hand socket, following the montage)
-- takes over on its own because isActive()/isHolding() stay false. Only the spoofed-X
-- drain in on_xinput_get_state keeps running, for M.spoofNativeReload (gesture reload).
local enabled                   = true
local lastInitLeftHand          = nil -- last M.init args, replayed when re-enabled after an abort
local lastInitWeaponName        = nil
-- isTubeFed: set when grabbing a shell deliberately spoofed a native reload, so
-- tryInterceptReload can tell our own request apart from an unprompted one.
local tubeFedSpoofPending       = false
-- isTubeFed: true while a native reload is parked (montages playing but paused),
-- waiting for the player to bring a shell to the loading port.
local tubeFedReloadParked       = false
-- Deferred montage pre-warm: if find_uobject / dynamic discovery fails at init
-- (asset not yet streamed), we retry periodically until this deadline.
local montagePrewarmDeadline    = 0
local lastDiscoveryAttempt      = 0   -- os.clock() of last get_objects_by_class scan
local cachedAnimMontageClass    = nil -- AnimMontage UClass (fetched once per session)
-- Per-session cache: weaponId -> discovered AnimMontage UObject (or false = confirmed absent)
local discoveryCache            = {}

-- PERF (2026-09-21): uevr.api:find_uobject is a hash lookup on a HIT (~0 ms) but falls back to a
-- full GUObjectArray walk on a MISS - measured live at ~360 ms per miss on the game thread.
-- The reload montage of a freshly equipped weapon is usually NOT in memory until the game
-- has played it once, so every equip took a 360 ms miss here (plus a 0.5 s-cadence retry
-- loop of further misses for 10 s) - the "FPS drops hard for half a second on every weapon
-- switch". Misses are now remembered per name for MISS_RETRY_SECONDS so the same lookup can
-- stall at most once per window; tryInterceptReload still fills cachedCharMontage passively.
local MISS_RETRY_SECONDS = 30.0
local findMissUntil = {}
local function findUObjectCached(name)
    if not name then return nil end
    local now = os.clock()
    if (findMissUntil[name] or 0) > now then return nil end
    local ok, obj = pcall(function() return uevr.api:find_uobject(name) end)
    if ok and obj then
        findMissUntil[name] = nil
        return obj
    end
    findMissUntil[name] = now + MISS_RETRY_SECONDS
    return nil
end
local discoveryMissUntil = {}
-- Ghost-play demand-load: when find_uobject returns nil (asset not streamed yet),
-- we play the montage at 0.001x rate for one tick to force UE5 to load its package,
-- then stop it and retry find_uobject.
local ghostPlayPending          = false  -- true = need to issue the 0.001x Montage_Play
local ghostPlayStopPending      = false  -- true = ghost play issued, need to stop + retry

-- Helpers

-- Liveness check for MOD-CREATED objects ONLY (proxies, hand/controller components):
-- those are adopted by UObjectHook when created through the UEVR API, so exists() is
-- a reliable set-membership test that never touches the object's memory.
--
-- DO NOT call this on game-owned pointers held across frames (weapon mesh, its mag
-- children, char mesh, anim instances). Under the current backend exists() *adopts*
-- an unknown pointer by reading it, and the bridge's own validity check reads
-- InternalIndex through the pointer before bounds-checking - on a freed pointer both
-- are the access-violation crash (game +0x2201c9a, UEVRBackend +0xe3f24). Game-owned
-- objects are re-resolved from the live pawn chain at the moment of use instead.
local function isAlive(obj)
    if obj == nil then return false end
    local ok, alive = pcall(function() return UEVR_UObjectHook.exists(obj) end)
    return ok and alive
end

-- Pointer value of a UObject handle (no dereference) - used to remember which
-- game-owned objects we were working with so they can be re-matched against a
-- freshly resolved set later, instead of holding the handle itself.
local function objAddr(obj)
    if obj == nil then return nil end
    local ok, addr = pcall(function() return obj:get_address() end)
    if ok then return addr end
    return nil
end

-- Fresh lookup of the equipped weapon mesh from the live pawn chain. Unlike
-- getPistolWeaponMesh() this does not require an active profile, so it is safe
-- from reset()/abort paths too.
local function resolveWeaponMesh(pawn)
    if pawn == nil then
        pawn = uevr.api:get_local_pawn(0)
        if pawn == nil then return nil end
    end
    local wm = nil
    pcall(function()
        local sk = pawn.Mesh
        if not sk then return end
        local anim = sk.AnimScriptInstance
        if not anim then return end
        local wd = anim.WeaponData
        if not wd then return end
        wm = wd.WeaponMesh
    end)
    return wm
end

-- Returns the live child of weaponMesh whose address matches addr, or nil if the
-- weapon no longer has such a child (weapon switched, children recreated).
local function findLiveChildByAddr(weaponMesh, addr)
    if weaponMesh == nil or addr == nil then return nil end
    local found = nil
    pcall(function()
        local children = weaponMesh.AttachChildren
        if not children then return end
        for _, child in ipairs(children) do
            if child and objAddr(child) == addr then
                found = child
                return
            end
        end
    end)
    return found
end

local cachedWeaponMeshAddr = nil  -- address (number) of the weapon mesh magMeshes was collected from

-- Performance caches: avoid repeated find_uobject UObject-array scans and
-- redundant C++ calls into the engine every tick.
local cachedSmClass           = nil   -- StaticMeshComponent class (constant per session)
local cachedMagMeshWeapon     = nil   -- skelMesh ptr for which magMeshes was last built
local magMeshesCurrentlyHidden = false -- prevents redundant SetVisibility calls each tick

-- Returns the StaticMeshComponent UClass, scanning the UObject array only once.
local function getSmClass()
    if not cachedSmClass then
        cachedSmClass = uevr.api:find_uobject("Class /Script/Engine.StaticMeshComponent")
    end
    return cachedSmClass
end

-- Returns the AnimMontage UClass, fetched once per session.
local function getAnimMontageClass()
    if not cachedAnimMontageClass then
        cachedAnimMontageClass = uevr.api:find_uobject("Class /Script/Engine.AnimMontage")
        if cachedAnimMontageClass then
            print("[Reload][Discovery] AnimMontage UClass found.")
        else
            print("[Reload][Discovery] WARNING: AnimMontage UClass not found yet.")
        end
    end
    return cachedAnimMontageClass
end

-- Dynamically discovers the best char-mesh reload AnimMontage for a given weapon.
-- weaponId: the SK_xxx name from the profile (e.g. "SK_aku").
-- Returns a live AnimMontage UObject, or nil.
--
-- Strategy:
--   1. Strip "SK_" prefix to get the weapon key (e.g. "aku").
--   2. Iterate all AnimMontage objects currently loaded in GUObjectArray.
--   3. Filter: name must contain the weapon key AND "reload".
--              name must contain "fp_" (first-person char-mesh montage).
--              name must NOT contain "weapon" (avoids weapon-mesh variants).
--   4. Score: +2 for "tactical", +1 for "twohand" or "two_hand".
--   5. Return the highest-scoring candidate (first on tie).
--
-- Result is cached in discoveryCache[weaponId] for the session.
-- Returns false (not nil) when a scan was done but nothing was found, so
-- callers can distinguish "not scanned yet" from "scanned, confirmed absent".
local function discoverReloadMontage(weaponId)
    -- Return cached result immediately (including confirmed-absent = false).
    if discoveryCache[weaponId] ~= nil then
        return discoveryCache[weaponId] or nil
    end
    -- PERF (2026-09-21): a failed scan is remembered for MISS_RETRY_SECONDS (callers nil the
    -- cache entry to force a rescan, which used to mean a full GUObjectArray walk per reload).
    if (discoveryMissUntil[weaponId] or 0) > os.clock() then return nil end
    discoveryMissUntil[weaponId] = os.clock() + MISS_RETRY_SECONDS

    local montageClass = getAnimMontageClass()
    if not montageClass then
        print("[Reload][Discovery][" .. weaponId .. "] Skipping scan - AnimMontage class not available yet.")
        return nil
    end

    -- Strip the 'sk_' prefix to get the weapon key used in montage names.
    -- NOTE: the old comment here claimed weaponId is always lowercase. It is NOT -
    -- weaponId = p.id, and M.init() sets activeProfile.id = weaponName, the RAW
    -- SkeletalMesh fname ("SK_ThreeLine"). Only `lowerName` is lowercased, for the
    -- profile-table prefix match. So a lowercase-only gsub("^sk_") never stripped
    -- anything, leaving key = "SK_ThreeLine", which was then searched for with
    -- string.find(lower, key) against an ALL-LOWERCASE haystack - so it could never
    -- match and dynamic discovery failed 100% of the time, for every weapon.
    -- Because a failed scan deliberately does not cache a negative result (see below),
    -- this re-ran a full GUObjectArray scan at init AND again at hip-hold AND again at
    -- INSERT, on every reload until the passive auto-intercept finally populated
    -- cachedCharMontage - i.e. it stalled frames throughout the FIRST reload of a
    -- session and then went quiet, which is exactly when the spoofed-X hold was being
    -- stretched into a long press. Lowercase first, then strip.
    local key = string.lower(weaponId):gsub("^sk_", "")
    print("[Reload][Discovery][" .. weaponId .. "] Scanning all loaded AnimMontages for key='" .. key .. "' + 'reload' + 'fp_'...")

    -- CRASH GUARD: UEVR_UObjectHook.get_objects_by_class is a native GUObjectArray scan that
    -- can throw (not just return nil) in the window right after a script reload / weapon-mesh
    -- GC race - the same class of native exception uevrUtils.find_all_of already pcalls for
    -- (see stalker2-uevr-upgrade-compat memory). This call site bypassed that wrapper by going
    -- straight to UEVR_UObjectHook, so an unlucky manual reload could throw all the way up
    -- through M.init() to Entry.lua's on_pre_engine_tick with no pcall boundary anywhere in
    -- between - "Exception in on_pre_engine_tick" in the UEVR log. Fixed 2026-09-08.
    local ok, objects = pcall(function() return UEVR_UObjectHook.get_objects_by_class(montageClass, false) end)
    if not ok then
        print("[Reload][Discovery][" .. weaponId .. "] get_objects_by_class threw: " .. tostring(objects) .. " - will retry later.")
        return nil
    end
    if not objects then
        print("[Reload][Discovery][" .. weaponId .. "] get_objects_by_class returned nil.")
        return nil
    end

    print("[Reload][Discovery][" .. weaponId .. "] Total AnimMontage objects in memory: " .. #objects)

    local bestObj   = nil
    local bestScore = -1

    for _, obj in ipairs(objects) do
        local ok, fullName = pcall(function() return obj:get_full_name() end)
        if ok and fullName then
            local lower = string.lower(fullName)
            -- Must match weapon key, 'reload', and 'fp_' (char-mesh montage).
            -- Must NOT contain 'weapon' (those are weapon-mesh montages, not char-mesh).
            if  string.find(lower, key,      1, true)
            and string.find(lower, "reload", 1, true)
            and string.find(lower, "fp_",    1, true)
            and not string.find(lower, "weapon", 1, true) then
                local score = 0
                if string.find(lower, "tactical",  1, true) then score = score + 2 end
                if string.find(lower, "twohand",   1, true) or
                   string.find(lower, "two_hand",  1, true) then score = score + 1 end
                print("[Reload][Discovery][" .. weaponId .. "]   CANDIDATE (score=" .. score .. "): " .. fullName)
                if score > bestScore then
                    bestScore = score
                    bestObj   = obj
                end
            end
        end
    end

    if bestObj then
        local ok2, name2 = pcall(function() return bestObj:get_full_name() end)
        print("[Reload][Discovery][" .. weaponId .. "] >>> SELECTED (score=" .. bestScore .. "): " .. (ok2 and name2 or "?"))
        discoveryCache[weaponId] = bestObj
        return bestObj
    else
        print("[Reload][Discovery][" .. weaponId .. "] No matching montage found in " .. #objects .. " objects. Will retry later.")
        -- Do NOT cache false here - leave nil so the next call retries.
        return nil
    end
end

-- Returns the equipped weapon SkeletalMeshComponent if an active ptm profile
-- is set (i.e. init() found a matching profile for the current weapon).
-- Profile detection is now done once in init() via direct table lookup;
-- this function is a fast nil-guard that also fetches the live mesh pointer.
local function getPistolWeaponMesh(pawn)
    if not activeProfile then return nil end
    local wm = nil
    pcall(function()
        local sk = pawn.Mesh
        if not sk then return end
        local anim = sk.AnimScriptInstance
        if not anim then return end
        local wd = anim.WeaponData
        if not wd then return end
        wm = wd.WeaponMesh
    end)
    return wm
end

-- Collects all AttachChildren whose name ends with _mag_full or _mag_empty.
-- Confirmed safe across 9 weapons via MCP live scan - avoids false positives
-- such as SM_magazine_t (moving magazine-release tab on AK-pattern weapons).
-- MCP-confirmed 2026-09-04 (SKP, live): this weapon's mag body meshes are
-- named SM_Wpn_SKP_MagDefault_Full_01 / _Empty_01 (on jnt_magazine_master,
-- x2 each - a visibility-toggle pair) - "magdefault_full"/"magdefault_empty",
-- NOT "_mag_full"/"_mag_empty", so none of the patterns above matched and
-- collectMagMeshes returned zero meshes for it (mag never hid on eject, and
-- the proxy had no mesh to borrow since profile.proxyMesh wasn't set either).
-- Added a dedicated magdefault_full/magdefault_empty pattern below rather
-- than patching sk_skp alone, since this is a naming convention that could
-- recur on other weapons.
-- quiet: no debug prints (the belt pouch looks the ammo mesh up while idle).
local function collectMagMeshes(weaponMesh, profile, quiet)
    local mags = {}
    local allNames = {}
    pcall(function()
        local children = weaponMesh.AttachChildren
        if not children then
            if not quiet then print("[DBG][collectMagMeshes] AttachChildren is nil") end
            return
        end
        for _, child in ipairs(children) do
            if child then
                local ok2, name = pcall(function() return child:get_full_name() end)
                if ok2 and name then
                    table.insert(allNames, name)
                    local lower = string.lower(name)
                    if string.find(lower, "_mag_full",       1, true)
                    or string.find(lower, "_mag_empty",      1, true)
                    or string.find(lower, "_mag_half",       1, true)
                    or string.find(lower, "_round_mag",      1, true)
                    or string.find(lower, "bigmag_full",     1, true)
                    or string.find(lower, "bigmag_empty",    1, true)
                    or string.find(lower, "increased_full",  1, true)
                    or string.find(lower, "increased_empty", 1, true)
                    or string.find(lower, "_increasedmag_",  1, true)
                    or string.find(lower, "twinmag_",        1, true)
                    or string.find(lower, "drumag_full",     1, true)
                    or string.find(lower, "drumag_empty",    1, true)
                    or string.find(lower, "magdefault_full", 1, true)
                    or string.find(lower, "magdefault_empty",1, true)
                    -- GP3A's Huge-capacity mag: SM_Wpn_Gp3a_MagHuge_Full_01/_Empty_01 (MCP-
                    -- confirmed 2026-09-07, same naming-convention gap as magdefault_full/empty
                    -- above - "maghuge_full" doesn't contain "_mag_full" either).
                    or string.find(lower, "maghuge_full",    1, true)
                    or string.find(lower, "maghuge_empty",   1, true) then
                        table.insert(mags, { addr = objAddr(child), name = name })
                    elseif profile and profile.id and string.find(string.lower(profile.id), "sk_rhino", 1, true) then
                        if (string.find(lower, "sm_bullet", 1, true) and not string.find(lower, "extractor", 1, true))
                        or (string.find(lower, "sm_loader", 1, true) and not string.find(lower, "injector", 1, true))
                        or string.find(lower, "sm_drum_lock", 1, true) then
                            table.insert(mags, { addr = objAddr(child), name = name })
                        end
                    elseif profile and profile.isTubeFed then
                        -- Tube-fed shotguns: live shells named SM_amm_*_SM_bullet or SM_wpn_*_SM_bullet.
                        -- Unified filter: match sm_bullet but exclude spent casings (_shell suffix).
                        -- Covers: RAM-2 (sm_amm_), SPSA (sm_amm_), M860 std (sm_amm_),
                        --         TOZ-34 (sm_wpn_), Obrez (sm_wpn_).
                        -- SK_m86000 (bigmag) does NOT have isTubeFed so routes to bigmag_full/empty above.
                        if string.find(lower, "sm_bullet", 1, true)
                        and not string.find(lower, "_shell", 1, true) then
                            table.insert(mags, { addr = objAddr(child), name = name })
                        elseif profile.ammoMeshPattern and string.find(lower, profile.ammoMeshPattern, 1, true) then
                            -- Per-profile round mesh that is not named like a shell (RPG-7 rocket).
                            table.insert(mags, { addr = objAddr(child), name = name })
                        end
                    end
                end
            end
        end
    end)
    if quiet then return mags end
    print("[DBG][collectMagMeshes] scanned " .. #allNames .. " children, found " .. #mags .. " mag mesh(es).")
    print("[DBG][collectMagMeshes] scanned " .. #allNames .. " children, found " .. #mags .. " mag mesh(es).")
    if #mags == 0 and #allNames > 0 then
        for i, n in ipairs(allNames) do
            print("[DBG][collectMagMeshes]   child[" .. i .. "]: " .. n)
        end
    end
    return mags
end

-- meshes: the {addr, name} entries collected by collectMagMeshes. The entries are
-- matched against the weapon's CURRENT AttachChildren by address, so a child that
-- was destroyed/recreated since collection is simply skipped - the remembered
-- handle is never dereferenced.
local function setMagMeshesHidden(meshes, hidden, weaponMesh)
    if #meshes == 0 then return end
    weaponMesh = weaponMesh or resolveWeaponMesh(nil)
    if weaponMesh == nil then return end
    local live = {}
    pcall(function()
        local children = weaponMesh.AttachChildren
        if not children then return end
        for _, child in ipairs(children) do
            local a = objAddr(child)
            if a then live[a] = child end
        end
    end)
    for _, entry in ipairs(meshes) do
        local mesh = live[entry.addr]
        if mesh ~= nil then
            pcall(function()
                if hidden == false then
                    local name = string.lower(entry.name or "")
                    -- Skip spent casings on un-hide (INSERT phase).
                    -- sm_shell: Rhino extractor shells.
                    -- _bullet_shell: tube-fed shotgun spent casings (SPSA, M860, RAM-2, TOZ-34, Obrez).
                    if string.find(name, "sm_shell",      1, true)
                    or string.find(name, "_bullet_shell", 1, true) then
                        return
                    end
                end
                mesh:SetVisibility(not hidden, false)
                mesh:SetHiddenInGame(hidden, false)
            end)
        end
    end
end

local function isRhinoProfile(profile)
    return profile ~= nil and profile.id ~= nil and string.find(string.lower(profile.id), "sk_rhino", 1, true) ~= nil
end

-- Box mags carry a full AND an empty mag mesh on the same socket (SM_pt_udp_mag_full / _mag_empty,
-- ..._MagDefault_Full_01 / _Empty_01, bigmag_full / bigmag_empty ...), one shown at a time. Their order in
-- AttachChildren is not fixed, so the old "first mag child" pick gave the ejected mag a FULL mesh on some weapons
-- (2026-10-17) and could give the fresh one an empty mesh. The fresh mag (hand + belt pouch) takes the full
-- one, the ejected mag the empty one. Rhino / tube-fed rounds have no full / empty pairs: first live child, as before.
-- wantEmpty: returns nil when the weapon has no empty mag mesh (caller falls back to the full one).
local function pickMagAsset(weaponMesh, profile, wantEmpty)
    if weaponMesh == nil then return nil end
    local entries = magMeshes
    if #entries == 0 or cachedWeaponMeshAddr ~= objAddr(weaponMesh) then
        entries = collectMagMeshes(weaponMesh, profile, true)
    end
    local first, full, empty = nil, nil, nil
    for _, entry in ipairs(entries) do
        local child = findLiveChildByAddr(weaponMesh, entry.addr)
        local mesh = nil
        if child ~= nil then pcall(function() mesh = child.StaticMesh end) end
        if mesh ~= nil then
            first = first or mesh
            local name = string.lower(entry.name or "")
            pcall(function() name = name .. " " .. string.lower(mesh:get_fname():to_string()) end)
            if string.find(name, "empty", 1, true) ~= nil then
                empty = empty or mesh
            else
                full = full or mesh
            end
        end
    end
    if (profile and profile.isTubeFed) or isRhinoProfile(profile) then
        if wantEmpty then return nil end
        return first
    end
    if wantEmpty then return empty end
    return full or first
end

local aggregateChildren = {}

local function destroyProxy(proxy, pawn)
    if isAlive(proxy) then
        local children = aggregateChildren[proxy]
        if children then
            for _, child in ipairs(children) do
                if child and isAlive(child) then
                    pcall(function()
                        child:SetHiddenInGame(true)
                        if child.K2_DestroyComponent then
                            child:K2_DestroyComponent(child)
                        end
                    end)
                end
            end
        end
        aggregateChildren[proxy] = nil
        pcall(function() proxy:SetHiddenInGame(true) end)
        pcall(function()
            if proxy.K2_DestroyComponent ~= nil then
                proxy:K2_DestroyComponent(proxy)
            end
        end)
    end
    return nil
end

-- UPDATED 2026-09-04: previously set ForegroundFOVEnabled=1.0 here to match the
-- game's own "_fov"-suffixed weapon/hand materials. That assumption turned out to
-- be backwards - live MCP investigation (see Entry.lua's applyForegroundFOVFixExperiment)
-- confirmed forcing the REAL weapon mesh and both VR hand PMCs to
-- ForegroundFOVEnabled=0 (normal world-depth rendering, bypassing the engine's
-- separate first-person-primitive projection) is what actually fixes VR hands/weapon
-- rendering at the correct depth relative to the world. A proxy built with
-- SetStaticMesh only gets the asset's default material (MI_pm_base etc.), where this
-- parameter is unset (defaults to 0 in the shader, but MID conversion + an explicit
-- write make that guaranteed rather than assumed) - give every proxy the same
-- corrected value the weapon/hands now use, not the old (wrong) 1.0.
local function applyForegroundFOV(comp)
    if not isAlive(comp) then return end
    pcall(function()
        uevrUtils.fixMeshFOV(comp, "ForegroundFOVEnabled", 0.0, false, false, false)
    end)
end

local function spawnMagProxy(pawn, profile, isHipGrab, weaponMesh)
    weaponMesh = weaponMesh or resolveWeaponMesh(pawn)
    local smClass = getSmClass()
    if not smClass then
        print("[Reload] ERROR: StaticMeshComponent class not found")
        return nil
    end
    local proxy
    local ok = pcall(function()
        proxy = uevr.api:add_component_by_class(pawn, smClass)
    end)
    if not ok or not isAlive(proxy) then
        print("[Reload] ERROR: add_component_by_class failed")
        return nil
    end
    if not profile.cachedMeshAsset then
        profile.cachedMeshAsset = pickMagAsset(weaponMesh, profile, false)
        if profile.cachedMeshAsset then
            print("[Reload][" .. profile.id .. "] Proxy mesh auto-discovered from the weapon's mag children.")
        end
        if not profile.cachedMeshAsset and profile.proxyMesh then
            profile.cachedMeshAsset = findUObjectCached(profile.proxyMesh)
        end
    end
    -- The ejected (old) mag shows the empty mag mesh when the weapon has one. false = looked, none.
    local meshAsset = profile.cachedMeshAsset
    if not isHipGrab and not profile.isTubeFed and not isRhinoProfile(profile) then
        if profile.cachedEmptyMeshAsset == nil then
            profile.cachedEmptyMeshAsset = pickMagAsset(weaponMesh, profile, true) or false
        end
        if profile.cachedEmptyMeshAsset then meshAsset = profile.cachedEmptyMeshAsset end
    end

    if isRhinoProfile(profile) and isHipGrab then
        if not profile.cachedLoaderAsset and weaponMesh then
            pcall(function()
                local children = weaponMesh.AttachChildren
                if children then
                    for _, child in ipairs(children) do
                        local ok, name = pcall(function() return child:get_full_name() end)
                        if ok and name then
                            local lower = string.lower(name)
                            if string.find(lower, "sm_loader", 1, true) and not string.find(lower, "injector", 1, true) then
                                profile.cachedLoaderAsset = child.StaticMesh
                            elseif string.find(lower, "sm_bullet", 1, true) and not string.find(lower, "extractor", 1, true) and not profile.cachedBulletAsset then
                                profile.cachedBulletAsset = child.StaticMesh
                            end
                        end
                    end
                end
            end)
        end
        if profile.cachedMeshAsset then
            pcall(function() proxy:SetStaticMesh(profile.cachedMeshAsset) end)
            
            local childProxies = {}
            
            -- Spawn 6 bullet proxies in a parametric circle
            if profile.cachedBulletAsset then
                local radius = 1.4      -- Adjust circle radius
                local depthX = -1.0     -- Adjust depth into the loader
                local angleStep = (2 * math.pi) / 6
                local angleOffset = 0.5 -- Rotational phase offset for the ring
                
                for i = 1, 6 do
                    pcall(function()
                        local bp = uevr.api:add_component_by_class(pawn, smClass)
                        bp:SetStaticMesh(profile.cachedBulletAsset)
                        bp:SetCollisionEnabled(0)
                        bp:SetHiddenInGame(false)
                        applyForegroundFOV(bp)
                        -- bWeldSimulatedBodies false: the bullets have no collision, nothing to weld. Welding
                        -- touched their physics bodies, and while the pawn was mid-rebuild (backpack closed +
                        -- suit swap, 2026-10-18) the engine faulted in that path on 3 of 6 bullets; UEVR swallowed
                        -- it and the half-built bullets crashed the render-submission worker threads.
                        bp:K2_AttachToComponent(proxy, uevrUtils.fname_from_string("None"), 2, 2, 2, false)
                        
                        local angle = (i - 1) * angleStep + angleOffset
                        bp.RelativeLocation.X = depthX
                        bp.RelativeLocation.Y = radius * math.cos(angle)
                        bp.RelativeLocation.Z = radius * math.sin(angle)
                        table.insert(childProxies, bp)
                    end)
                end
            end
            aggregateChildren[proxy] = childProxies
        else
            if profile.cachedMeshAsset then pcall(function() proxy:SetStaticMesh(profile.cachedMeshAsset) end) end
        end
    else
        if meshAsset then
            pcall(function() proxy:SetStaticMesh(meshAsset) end)
        end
    end

    pcall(function() proxy:SetCollisionEnabled(0) end)
    proxy:SetHiddenInGame(false)
    applyForegroundFOV(proxy)
    return proxy
end

-- Resolves the component the proxy should be parented to. Prefers the left VR hand
-- mesh (a PoseableMeshComponent, so "jnt_l_hand" resolves as a real bone socket and
-- the mag follows the posed hand); falls back to the left MotionControllerComponent
-- when the hand mesh doesn't exist yet or Config.ptmAttachProxyToHandMesh is off.
-- Resolved per call rather than cached: hand meshes are destroyed/recreated on
-- level change and suit change (hands.rebuildHands), so a cached pointer goes stale.
local function getProxyParent()
    if Config.ptmAttachProxyToHandMesh ~= false then
        local ok, handMesh = pcall(function()
            local hands = require("libs/hands")
            return hands.getHandComponent(Handed.Left)
        end)
        if ok and isAlive(handMesh) then
            return handMesh
        end
    end
    return leftHandComp
end

local function attachProxyToHand(proxy)
    if not isAlive(proxy) then return end
    local parent = getProxyParent()
    if not isAlive(parent) then return end
    pcall(function()
        proxy:K2_AttachToComponent(parent, uevrUtils.fname_from_string("jnt_l_hand"), 2, 2, 2, true)
        local loc = getProxyLoc()
        local rot = getProxyRot()
        proxy.RelativeLocation.X = loc[1]
        proxy.RelativeLocation.Y = loc[2]
        proxy.RelativeLocation.Z = loc[3]
        proxy.RelativeRotation.Pitch = rot[1]
        proxy.RelativeRotation.Yaw   = rot[2]
        proxy.RelativeRotation.Roll  = rot[3]
    end)
end

-- ---------------------------------------------------------------------------
-- The game's own mag drop (found 2026-10-17, M160, live MCP). The weapon-side reload montage
-- (e.g. MG_m16_fp_reload_tactical) carries an AnimNotify_EjectMagazine (~1.07 s in) that spawns
-- an EjectedMagazine actor - a physics mag with a 15 s Lifetime - at MagEjectSocket. Our eject
-- pauses the native reload at 0.0, so the INSERT fast-forward crosses that notify and the game
-- dropped a second (full) mag out of the magwell after every manual reload (user report: "tumbles and
-- bounces on the floor"). The mag is HIDDEN, not deleted (on request) - the game destroys it itself
-- when its Lifetime runs out.
-- Tried and failed (2026-10-17):
--   * disabling the notify (FAnimNotifyEvent.NotifyTriggerChance = 0): montage.Notifies reads as
--     nil in mod Lua, and raw read_*/write_* are bounds-checked to the object's own size;
--   * hiding it on the next pre-engine tick: visible for a frame or two - it spawns mid-frame in
--     the anim update, after our tick;
--   * spawning it hidden via the class default object's bHidden: the spawned mags still had
--     bHidden false.
-- So it is hidden from the post-stereo callback: that runs after the world tick that spawned it
-- and before the frame's render state is sent (BeginRenderingViewFamily), so it never shows.
-- Cost: nothing outside a reload. beginEjectHideWindow snapshots the EjectedMagazines that already
-- exist (one class-filtered GetAllActorsOfClass); then one lookup per callback until the first new
-- one near the pawn is hidden (one eject notify per reload) or EJECT_HIDE_WINDOW_S runs out.
-- ---------------------------------------------------------------------------
local EJECTED_MAG_CLASS    = "Class /Script/Stalker2.EjectedMagazine"
local EJECT_HIDE_WINDOW_S  = 0.6   -- the fast-forward lasts <= FINISH_WINDOW_MAX + one tick
local EJECT_HIDE_RADIUS_SQ = 300.0 * 300.0  -- cm^2 around the pawn (leaves NPC reloads alone)
local ejectHideUntil = 0    -- os.clock() until which a new EjectedMagazine is hidden (0 = off)
local ejectKnown     = {}   -- [address] = true for the ones that existed at the insert / were checked

local function ejectedMagazines()
    local ok, list = pcall(uevrUtils.getAllActorsOfClass, EJECTED_MAG_CLASS)
    if ok and type(list) == "table" then return list end
    return {}
end

local function beginEjectHideWindow()
    ejectKnown = {}
    for _, actor in ipairs(ejectedMagazines()) do
        local addr = objAddr(actor)
        if addr then ejectKnown[addr] = true end
    end
    ejectHideUntil = os.clock() + EJECT_HIDE_WINDOW_S
end

local function endEjectHideWindow()
    ejectHideUntil = 0
    ejectKnown = {}
end

-- Actor handles are used within this call only.
local function hideNewEjectedMagazine()
    if os.clock() > ejectHideUntil then
        endEjectHideWindow()
        return
    end
    local list = ejectedMagazines()
    if #list == 0 then return end
    local pawnLoc = nil
    pcall(function() pawnLoc = uevr.api:get_local_pawn(0):K2_GetActorLocation() end)
    for _, actor in ipairs(list) do
        local addr = objAddr(actor)
        if addr and not ejectKnown[addr] then
            ejectKnown[addr] = true
            local hidden = false
            pcall(function()
                if pawnLoc ~= nil then
                    local l = actor:K2_GetActorLocation()
                    local dx, dy, dz = l.X - pawnLoc.X, l.Y - pawnLoc.Y, l.Z - pawnLoc.Z
                    if dx * dx + dy * dy + dz * dz > EJECT_HIDE_RADIUS_SQ then return end
                end
                actor:SetActorHiddenInGame(true)
                hidden = true
            end)
            if hidden then
                endEjectHideWindow()
                return
            end
        end
    end
end

uevrUtils.registerPostCalculateStereoViewCallback(function(device, view_index)
    if ejectHideUntil > 0 then hideNewEjectedMagazine() end
end)

local function doAbort(pawn, weaponMesh)
    if ejectProxy    then ejectProxy    = destroyProxy(ejectProxy,    pawn) end
    if droppingProxy then droppingProxy = destroyProxy(droppingProxy, pawn) end
    if heldProxy     then heldProxy     = destroyProxy(heldProxy,     pawn) end
    if shellProxy    then shellProxy    = destroyProxy(shellProxy,    pawn) end
    if insertGlide then
        if insertGlide.proxy then destroyProxy(insertGlide.proxy, pawn) end
        insertGlide = nil
    end
    if awaitClose then
        if awaitClose.proxy then destroyProxy(awaitClose.proxy, pawn) end
        awaitClose = nil
    end
    grabGlide = nil
    -- the rack's parts are only touched while they still belong to the held weapon
    rackSlide.finish(weaponMesh ~= nil and objAddr(weaponMesh) == rackSlide.weaponAddr())
    rackGrabRequested = false
    rackSlideReleaseRequested = false
    tubeFedSpoofPending = false
    tubeFedReloadParked = false
    animJumpActive       = false
    animJumpElapsed      = 0.0
    -- Cancel any in-flight spoofed-X hold. Aborting while the injection is still
    -- counting down would keep feeding the reload button to the engine after the
    -- FSM has given up on the reload.
    forceNativeReloadTicks    = 0
    forceNativeReloadDeadline = 0
    spoofingTacticalReload    = false
    setMagMeshesHidden(magMeshes, false, weaponMesh)
    magMeshesCurrentlyHidden = false
    magMeshes = {}
    if weaponMesh then
        pcall(function()
            weaponMesh.bPauseAnims = false
            weaponMesh.GlobalAnimRateScale = 1.0
        end)
    end
    if interceptedCharMontage then
        pcall(function()
            local abortPawn = pawn or uevr.api:get_local_pawn(0)
            if abortPawn and abortPawn.Mesh then
                abortPawn.Mesh.bPauseAnims = false
                abortPawn.Mesh.GlobalAnimRateScale = 1.0
            end
        end)
        interceptedCharMontage = nil
    end
    charAnimResetArmed   = false
    weaponAnimResetArmed = false
    dropVelocity   = 0
    dropProxyReady = false
    diag("ABORT from %s (weapon %s)\n%s", stateName(currentState), tostring(activeProfile and activeProfile.id),
        debug.traceback("", 2))
    activeProfile        = nil
    currentState         = STATE_IDLE
    print("[Reload] Aborted - reset to IDLE.")
end

-- Public API

-- Level / save load (called from Entry.lua's level change block): forget - never touch - the engine objects this module
-- keeps between reloads. The reload montages and the proxy / shell / loader meshes are /Game assets the game frees and
-- reloads at a new address on a load; an old pointer keeps "working" until its memory is reused, then the engine faults
-- inside Montage_Play / SetStaticMesh and UEVR swallows the fault halfway through ProcessEvent, which corrupts the game
-- thread's Blueprint state (found on Hellraiser 2026-10-15: lost input, then no pawn spawned, after save loads).
-- activeProfile is only replaced on a detected weapon change, and a load can bring back the same weapon name on a
-- recycled component, so its caches are dropped here; they are looked up again on their next use.
function M.onLevelChange()
    endEjectHideWindow()
    rackSlide.onLevelChange()
    rackGrabRequested = false
    rackSlideReleaseRequested = false
    if activeProfile then
        activeProfile.cachedCharMontage = nil
        activeProfile.cachedMeshAsset   = nil
        activeProfile.cachedEmptyMeshAsset = nil
        activeProfile.pouchSignature    = nil
        activeProfile.cachedBulletAsset = nil
        activeProfile.cachedLoaderAsset = nil
    end
    interceptedCharMontage = nil
end

function M.isActive()
    -- tubeFedReloadParked covers the isTubeFed "ran dry unprompted" case: the native
    -- reload is parked (montage frozen) but currentState is still STATE_IDLE because the
    -- player hasn't grabbed a shell yet. Entry.lua's hand-attach logic gates on this
    -- function specifically to detach the support hand from the weapon's jnt_l_hand
    -- socket back to the controller while a reload is in progress (see the
    -- "not ptmReload.isActive()" check around the reload-attachment block) - without this,
    -- a two-handed shotgun that runs dry leaves the left hand visually stuck to the gun
    -- instead of freeing it to reach for a shell.
    return currentState ~= STATE_IDLE or tubeFedReloadParked
end

-- True while player is physically gripping any proxy mag/shell (eject, fresh, or shell).
-- Used by Entry.lua to override left hand pose for mag grip fingers.
-- Insert-target socket declared by the active weapon profile (nil for almost every weapon:
-- mag_reload.lua's own socket chain covers them). Entry.lua passes it to update_weapon_collision.
function M.getActiveMagSocket()
    return activeProfile and activeProfile.magSocket or nil
end

function M.isHolding()
    -- STATE_INSERTING counts: the fingers keep their mag grip while the mag is pushed home;
    -- so does gripping the slide / handle during a rack
    return currentState == STATE_EJECT_HOLD or currentState == STATE_HIP_HOLD or currentState == STATE_SHELL_HOLD
        or currentState == STATE_INSERTING
        or (currentState == STATE_AWAIT_RACK and rackSlide.isGripping())
end

-- Left hand on the slide / handle (Entry.lua poses it with the weapon's rack grip pose instead of the mag grip)
function M.isRackGripping()
    return currentState == STATE_AWAIT_RACK and rackSlide.isGripping()
end

-- For rack_slide.lua's travel learning (Entry.lua tick): raw right trigger, and whether the manual
-- reload is idle (nothing paused / fast-forwarded).
function M.isTriggerHeld()
    return rawTriggerHeld
end

function M.isIdleForLearning()
    return currentState == STATE_IDLE and not tubeFedReloadParked and not animJumpActive
        and not charAnimResetArmed and not weaponAnimResetArmed
end

-- twohandedaim.lua: no two-handed aim while the left hand reaches for the slide / handle
_G.ptmBlocksTwoHanding = function()
    return currentState == STATE_AWAIT_RACK
end

-- Called from Entry.lua each tick (after currentPreset:Update) to cache
-- leftHipZoneLH.isActive for the grip-press hip-zone transition check.
function M.setHandInHipZone(val)
    handInHipZone = val
end

function M.isEnabled()
    return enabled
end

-- Enable/disable the manual reload system (dev-panel checkbox / Config.enableManualReload).
-- Disabling mid-reload aborts cleanly: proxies destroyed, mag meshes unhidden, anims
-- unpaused - the parked native montage then simply plays out and finishes the reload.
-- Aborts whatever the manual reload has going and restores what it forced on the character mesh.
-- doAbort only restores the char mesh when interceptedCharMontage is set; the intro-jump and INSERT
-- fast-forward windows touch it without that, so restore it unconditionally here.
local function abortAndRestore(pawn, weaponMesh)
    if not (M.isActive() or animJumpActive or charAnimFastForwardArmed or charAnimResetArmed
            or weaponAnimResetArmed or magMeshesCurrentlyHidden) then
        return
    end
    pcall(function()
        if pawn and pawn.Mesh then
            pawn.Mesh.bPauseAnims = false
            pawn.Mesh.GlobalAnimRateScale = 1.0
        end
    end)
    charAnimFastForwardArmed = false
    doAbort(pawn, weaponMesh)
end

-- The equipped weapon went away (Entry.lua weapon-unequipped branch): holstered, or stripped mid-reload
-- by a Burer's drag-weapon attack (2026-10-27). Only an equip re-inits this module, so the reload stayed
-- parked with the character mesh paused - which froze the game's own Burer montage on it too. The
-- outgoing weapon mesh is left alone: the game is already detaching / destroying it.
function M.onWeaponLost()
    abortAndRestore(uevr.api:get_local_pawn(0), nil)
end

function M.setEnabled(val)
    val = val and true or false
    if val == enabled then return end
    enabled = val
    if not enabled then
        local pawn = uevr.api:get_local_pawn(0)
        local wm = nil
        pcall(function() wm = resolveWeaponMesh(pawn) end)
        abortAndRestore(pawn, wm)
        print("[Reload] Manual reload DISABLED - falling back to native montage reload.")
    else
        -- doAbort() clears activeProfile; without a re-init the system would stay dead
        -- until the next weapon equip.
        if not activeProfile and lastInitWeaponName then
            M.init(lastInitLeftHand, lastInitWeaponName)
        end
        print("[Reload] Manual reload ENABLED.")
    end
end

-- Gesture reload for legacy (manual reload disabled) mode: inject a short X press through
-- the same spoof the manual system uses. NOT the old 'R' key - that forced the game into
-- Keyboard/Mouse mode and caused ghost inputs. No-op while manual reload is enabled (the
-- mag-overlap grip is the EJECT trigger there).
function M.spoofNativeReload()
    if enabled or forceNativeReloadTicks > 0 then return false end
    forceNativeReloadTicks    = 3
    forceNativeReloadDeadline = 0
    return true
end

-- M860 standard vs bigmag can't be told apart by weapon name (both report
-- SK_m86000 - see the WEAPON_PROFILES comment above sk_m86000/sk_m860). The only
-- live signal is whether the weapon mesh's AttachChildren include the bigmag
-- StaticMeshes (SM_shg_m86000_bigmag_full / _bigmag_empty) - MCP-confirmed present
-- only on the bigmag variant, absent entirely on the standard tube-fed one.
local function isM860BigmagEquipped()
    local isBigmag = false
    pcall(function()
        local pawn = uevr.api:get_local_pawn(0)
        local wm = pawn and pawn.Mesh and pawn.Mesh.AnimScriptInstance
                   and pawn.Mesh.AnimScriptInstance.WeaponData
                   and pawn.Mesh.AnimScriptInstance.WeaponData.WeaponMesh
        if not wm or not wm.AttachChildren then return end
        for _, child in ipairs(wm.AttachChildren) do
            local ok, name = pcall(function() return child:get_full_name() end)
            if ok and name and string.find(string.lower(name), "bigmag_", 1, true) then
                isBigmag = true
                return
            end
        end
    end)
    return isBigmag
end

-- FIX (2026-09-07): GP3A can be equipped with three interchangeable magazine capacities
-- (MagDefault/MagIncreased/MagHuge, all detachable box mags on the same socket - unlike
-- M860's bigmag which is a distinct WEAPON_PROFILES key entirely). The WEAPON_PROFILES
-- entry below statically pins charMontage to MagDefault_Tactical_01 (needed to break a
-- 3-way tie-score in discoverReloadMontage() - see the comment above that entry), but per
-- "Known caveat" in the reload-system skill, that pin is a PERMANENT override for the
-- whole session, not just a first-reload fallback - M.init() eagerly resolves
-- cachedCharMontage from it before any reload happens, so tryInterceptReload()'s passive
-- auto-intercept (which would otherwise capture whatever montage the engine actually
-- picked) never fires for this weapon. Confirmed live 2026-09-07: with a MagHuge mag
-- actually equipped, the game froze mid-reload and could not complete it - the pinned
-- MagDefault montage plus the native engine's own Huge-capacity reload evidently fight
-- over the animation slot rather than one cleanly winning. This detects the live-equipped
-- capacity the same way isM860BigmagEquipped() above detects bigmag, so M.init() can
-- splice in the matching montage instead of the static pin.
local function detectGp3aMagVariant()
    local variant = "MagDefault"
    pcall(function()
        local pawn = uevr.api:get_local_pawn(0)
        local wm = pawn and pawn.Mesh and pawn.Mesh.AnimScriptInstance
                   and pawn.Mesh.AnimScriptInstance.WeaponData
                   and pawn.Mesh.AnimScriptInstance.WeaponData.WeaponMesh
        if not wm or not wm.AttachChildren then return end
        for _, child in ipairs(wm.AttachChildren) do
            local ok, name = pcall(function() return child:get_full_name() end)
            if ok and name then
                local lower = string.lower(name)
                if string.find(lower, "maghuge_", 1, true) then
                    variant = "MagHuge"
                    return
                elseif string.find(lower, "magincreased_", 1, true) then
                    variant = "MagIncreased"
                    return
                end
            end
        end
    end)
    return variant
end

-- weaponName: the get_fname() string of the currently equipped weapon
-- (e.g. "SK_pm"). Passed from Entry.lua on weapon switch.
-- Creates a profile for ANY weapon - no hardcoded whitelist required.
-- WEAPON_PROFILES overrides are merged in if available (charMontage fallback).
function M.init(leftHand, weaponName)
    -- A weapon switch mid-reload bypasses doAbort() entirely (Entry.lua calls this
    -- unconditionally on equip), so any state we forced onto the OUTGOING weapon/
    -- character mesh must be restored here too, or it's left corrupted forever:
    -- a mag mesh stays permanently hidden (magMeshes discarded without un-hiding),
    -- or an anim rate scale stays pinned at 15x-100x from the INSERT fast-forward
    -- (weaponAnimResetArmed/charAnimResetArmed discarded without restoring to
    -- 1.0) - a stuck 100x rate blows out that mesh's animated bounds enough for UE
    -- to cull it as off-screen, which reads as "the weapon mesh went invisible",
    -- intermittently, whenever a weapon switch lands inside the short deferred-
    -- reset window right after an INSERT. Also destroy live proxies instead of
    -- just discarding the pointers, which previously leaked them.
    if #magMeshes > 0 then
        setMagMeshesHidden(magMeshes, false)
    end
    do
        local resetPawn = uevr.api:get_local_pawn(0)
        if weaponAnimResetArmed then
            local wmNow = resolveWeaponMesh(resetPawn)
            if wmNow then
                pcall(function()
                    wmNow.bPauseAnims         = false
                    wmNow.GlobalAnimRateScale = 1.0
                end)
            end
        end
        if (charAnimResetArmed or charAnimFastForwardArmed) and resetPawn then
            pcall(function()
                local cm = resetPawn.Mesh
                if cm then cm.GlobalAnimRateScale = 1.0 end
            end)
        end
    end
    if ejectProxy    then destroyProxy(ejectProxy,    nil) end
    if droppingProxy then destroyProxy(droppingProxy, nil) end
    if heldProxy     then destroyProxy(heldProxy,     nil) end
    if shellProxy    then destroyProxy(shellProxy,    nil) end
    -- A switch mid insert glide: the recycled WeaponInHandsMesh keeps its address, so the
    -- glide's own weapon check can't catch it - drop the gliding proxy here.
    if insertGlide then
        if insertGlide.proxy then destroyProxy(insertGlide.proxy, nil) end
        insertGlide = nil
    end
    if awaitClose then
        if awaitClose.proxy then destroyProxy(awaitClose.proxy, nil) end
        awaitClose = nil
    end
    grabGlide = nil
    -- a switch mid-rack: the recycled weapon component keeps its address but gets new parts - the old
    -- ones are not touched again
    rackSlide.finish(false)
    rackGrabRequested = false
    rackSlideReleaseRequested = false
    reloadWasEmpty    = false

    lastInitLeftHand   = leftHand
    lastInitWeaponName = weaponName
    leftHandComp  = leftHand
    currentState  = STATE_IDLE
    ejectProxy    = nil
    droppingProxy = nil
    heldProxy     = nil
    shellProxy    = nil
    magMeshes     = {}
    -- NOTE: wasGripHeld and wasGripXinput are intentionally NOT reset here.
    -- If the grip button is physically held at the moment init() fires (e.g. the player
    -- is holding left grip while switching weapons), resetting these to false produces a
    -- phantom gripPressed=true on the very next xinput poll. That unsuppressed press
    -- reaches the game engine and can trigger consumables or other quick-use actions.
    -- The values self-correct on the very next on_xinput_get_state call regardless.
    handInHipZone            = false
    currentButtons           = 0
    interceptedCharMontage   = nil
    charAnimFastForwardArmed = false
    charAnimResetArmed       = false
    charAnimResetTime        = 0
    weaponAnimResetArmed     = false
    weaponAnimResetTime      = 0
    dropVelocity               = 0
    dropProxyReady           = false
    magMeshesCurrentlyHidden = false
    cachedWeaponMeshAddr     = nil
    montagePrewarmDeadline   = 0
    spoofingTacticalReload   = false
    forceNativeReloadTicks   = 0
    forceNativeReloadDeadline = 0
    tubeFedSpoofPending      = false
    tubeFedReloadParked      = false
    -- A weapon switch mid-intro-jump would otherwise leave animJumpActive true while
    -- getPistolWeaponMesh(pawn) now resolves to the NEW weapon - same class of bug as
    -- the mag-mesh/anim-rate restoration above, so reset it here too.
    animJumpActive           = false
    animJumpElapsed          = 0.0

    if weaponName then
        -- Always create a profile. Merge in any known override (charMontage fallback etc).
        -- Weapons NOT in WEAPON_PROFILES get a minimal auto-discover profile.
        local lowerName = string.lower(weaponName)
        
        -- UE5 can append instance numbers (e.g., SK_grim0 instead of SK_grim).
        -- We sort keys by length descending to match the longest exact prefix.
        local keys = {}
        for k in pairs(WEAPON_PROFILES) do table.insert(keys, k) end
        table.sort(keys, function(a, b) return #a > #b end)
        
        local existing    = nil
        local matchedKey  = nil
        for _, key in ipairs(keys) do
            if string.sub(lowerName, 1, #key) == key then
                existing   = WEAPON_PROFILES[key]
                matchedKey = key
                print("[Reload] Profile lookup matched prefix '" .. key .. "' for weapon '" .. weaponName .. "'.")
                break
            end
        end

        if existing then
            -- Create a fresh profile instance and shallow-copy template properties.
            -- Fixes level-load bug where cached UObjects (like cachedCharMontage) persisted
            -- globally and crashed the game when trying to play on a dead memory pointer.
            activeProfile = {}
            for k, v in pairs(existing) do activeProfile[k] = v end
            activeProfile.id = weaponName
        else
            -- Unknown weapon: create a fresh anonymous profile.
            -- It will auto-discover mag meshes and proxy mesh at runtime.
            activeProfile = { id = weaponName }
        end

        -- M860 disambiguation: matchedKey "sk_m86000" covers BOTH variants (see
        -- isM860BigmagEquipped comment above) - it's only really the bigmag profile
        -- if the live weapon mesh actually carries bigmag meshes. Otherwise splice in
        -- the tube-fed data from sk_m860's (normally-unreachable) table entry.
        -- proxyVariant: which of the two the held proxy is (box mag / single shell) - Entry.lua keeps
        -- the proxy hand offsets per variant (getProxyVariant).
        if matchedKey == "sk_m86000" then
            activeProfile.proxyVariant = isM860BigmagEquipped() and "bigmag" or "tube"
            activeProfile.variantCheckKey = matchedKey
        end
        if matchedKey == "sk_m86000" and activeProfile.proxyVariant == "tube" then
            local tubeProfile = WEAPON_PROFILES["sk_m860"]
            for k, v in pairs(tubeProfile) do activeProfile[k] = v end
            activeProfile.cachedCharMontage = nil  -- different montage - don't reuse sk_m86000's cache
            print("[Reload] SK_m86000 has no bigmag attached - using tube-fed (sk_m860) profile instead.")
        end

        -- FIX (2026-09-07): GP3A's static charMontage pin only covers MagDefault - splice
        -- in the correct montage for whichever capacity is actually equipped right now,
        -- rather than always playing/waiting on the pinned Default montage. See
        -- detectGp3aMagVariant() above for why this exists (confirmed freeze on MagHuge).
        if matchedKey == "sk_gp3a" then
            local variant = detectGp3aMagVariant()
            if variant ~= "MagDefault" then
                activeProfile.charMontage =
                    "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/dmr/GP3A/Reload/MG_FP_Player_Gp3a_Reload-"
                    .. variant .. "_Tactical_01.MG_FP_Player_Gp3a_Reload-" .. variant .. "_Tactical_01"
                activeProfile.cachedCharMontage = nil  -- different montage than the shared table's cache
                print("[Reload] SK_gp3a equipped with " .. variant .. " magazine - using matching reload montage.")
            end
        end

        -- Reset per-session discovery caches so a new weapon gets fresh auto-discovery.
        -- cachedCharMontage is deliberately PRESERVED on the shared WEAPON_PROFILES table
        -- between equips (find_uobject result is session-stable once loaded).
        activeProfile.cachedMeshAsset = nil
        activeProfile.cachedEmptyMeshAsset = nil

        -- Clear any stale discovery-cache entry for this weapon so a fresh scan
        -- is performed if the previous attempt returned nil.
        discoveryCache[weaponName] = nil
        ghostPlayPending           = false
        ghostPlayStopPending       = false

        -- Attempt immediate montage lookup at init time.
        -- Path 1: exact find_uobject via static charMontage path (weapons in WEAPON_PROFILES).
        -- Path 2: dynamic discovery via get_objects_by_class scan (all other weapons).
        -- If both fail, the auto-intercept path in tryInterceptReload() will populate
        -- cachedCharMontage the first time the engine fires a native reload montage.
        -- NOTE: LoadAsset_Blocking removed - it is a synchronous disk stall that freezes
        -- the game thread and kills FPS. Trust the passive intercept cache instead.
        if not activeProfile.cachedCharMontage then
            -- Try static path first (fast single hash lookup, no iteration).
            if activeProfile.charMontage then
                local ok, result = pcall(function()
                    return findUObjectCached(activeProfile.charMontage)
                end)
                if ok then
                    activeProfile.cachedCharMontage = result
                else
                    print("[Reload] find_uobject exception during init for " .. weaponName .. " (GC race?) - will retry at eject time.")
                end
                if activeProfile.cachedCharMontage then
                    print("[Reload] Pre-warmed charMontage via static path for " .. weaponName .. ".")
                end
            end
            -- Fall back to dynamic discovery if static path missing or returned nil.
            -- This is a full GUObjectArray scan so we only do it ONCE at init, not per-tick.
            if not activeProfile.cachedCharMontage then
                activeProfile.cachedCharMontage = discoverReloadMontage(weaponName)
                if activeProfile.cachedCharMontage then
                    print("[Reload] Pre-warmed charMontage via dynamic discovery for " .. weaponName .. ".")
                else
                    -- Still not found - rely on passive auto-intercept to populate it.
                    -- Schedule a lightweight find_uobject-only retry (no GUObjectArray scan)
                    -- for weapons with a known static charMontage path.
                    if activeProfile.charMontage then
                        montagePrewarmDeadline  = os.clock() + 10.0
                        lastDiscoveryAttempt    = 0
                        print("[Reload] charMontage not yet in memory for " .. weaponName .. " - scheduling deferred find_uobject retry.")
                    end
                end
            end
        else
            print("[Reload] charMontage already cached for " .. weaponName .. ".")
        end

        print("[Reload] Initialized for weapon: " .. weaponName)
    else
        activeProfile = nil
        print("[Reload] No weapon - reload disabled.")
    end
end

-- Which variant of a multi-variant weapon is held, for per-variant settings (Entry.lua: proxy hand
-- offsets). "bigmag" / "tube" for SK_m86000 (both variants share the mesh name - see
-- isM860BigmagEquipped), nil for every other weapon. Called every gameplay tick: re-checks at most
-- once per VARIANT_RECHECK_S, only for such a weapon and only while no reload is running - the
-- bigmag meshes can attach after the equip, and an inventory swap keeps the weapon name (so M.init
-- would not run). On a change the profile is rebuilt, which also swaps the reload data
-- (box mag vs tube-fed).
local VARIANT_RECHECK_S = 1.0
local variantRecheckAt  = 0
function M.getProxyVariant()
    local p = activeProfile
    if p == nil or p.variantCheckKey == nil then return nil end
    local now = os.clock()
    if now >= variantRecheckAt and currentState == STATE_IDLE and not tubeFedReloadParked
       and not animJumpActive and not charAnimResetArmed and not weaponAnimResetArmed then
        variantRecheckAt = now + VARIANT_RECHECK_S
        local live = isM860BigmagEquipped() and "bigmag" or "tube"
        if live ~= p.proxyVariant then
            print("[Reload] " .. tostring(p.id) .. " variant changed " .. tostring(p.proxyVariant) .. " -> " .. live .. ", re-initialising.")
            M.init(lastInitLeftHand, lastInitWeaponName)
            return activeProfile and activeProfile.proxyVariant or nil
        end
    end
    return p.proxyVariant
end

-- tryInterceptReload: auto empty-clip path.
-- Pauses anims, ejects empty proxy immediately (no grip required),
-- enters STATE_DROPPING_EMPTY.
function M.tryInterceptReload(charMontage, montageName)
    if not enabled then return end

    -- Suppress the callback fired by our own Montage_Play (tactical insert path).
    if (os.clock() - tacticalReloadTriggerTime) < 0.5 then
        print("[Reload] Suppressing intercept - self-triggered replenishment montage.")
        return
    end

    -- Ignore if already mid-reload.
    if currentState ~= STATE_IDLE then
        print("[Reload] tryInterceptReload ignored - already in state " .. currentState .. ".")
        return
    end

    -- Rack to chamber: the game starts its EMPTY reload (MG_fp_m16_reload) or the tactical one
    -- (MG_fp_m16_reload_tactical) from its own chamber state - an empty one needs a rack after the insert.
    reloadWasEmpty = type(montageName) == "string" and string.find(string.lower(montageName), "tactical", 1, true) == nil

    local pawn = uevr.api:get_local_pawn(0)
    if not pawn then return end

    local wm = getPistolWeaponMesh(pawn)
    if not wm or not activeProfile then return end

    local p = activeProfile

    -- FIX (2026-09-07): M.init() only detects GP3A's mag capacity at weapon-equip time, so
    -- a mag swap that doesn't trigger a re-equip (holstering isn't required to swap mags)
    -- would otherwise reload with a stale pinned montage. Re-check right as each reload
    -- actually starts, while the real mag mesh is still attached (eject hasn't run yet).
    if p.id and string.find(string.lower(p.id), "sk_gp3a", 1, true) then
        local variant = detectGp3aMagVariant()
        local expectedMontage =
            "AnimMontage /Game/_STALKER2/Animations/Player/AnimSequences/dmr/GP3A/Reload/MG_FP_Player_Gp3a_Reload-"
            .. variant .. "_Tactical_01.MG_FP_Player_Gp3a_Reload-" .. variant .. "_Tactical_01"
        if p.charMontage ~= expectedMontage then
            p.charMontage = expectedMontage
            p.cachedCharMontage = nil
            print("[Reload][" .. p.id .. "] Mag capacity changed to " .. variant .. " since last check - re-pinning reload montage.")
        end
    end

    -- Passively cache the charMontage UObject handed to us by the engine callback.
    -- This is free (no find_uobject scan) and populates the montage for the tactical
    -- path without any hardcoded asset path in the profile table.
    -- KNOWN CAVEAT (MCP-confirmed 2026-09-04, on a bigmag-equipped Arev): for any
    -- weapon with a static `charMontage` pin in WEAPON_PROFILES (sk_skp/sk_gp3a/
    -- sk_arev/sk_fora230 - added to disambiguate multiple same-scored "_Tactical"
    -- candidates), M.init() eagerly pre-resolves p.cachedCharMontage from that pin
    -- BEFORE this function ever runs. That means the `not p.cachedCharMontage` guard
    -- below is already false by the time a real reload fires, so this passive-cache
    -- path - which would otherwise capture whichever montage the engine ACTUALLY
    -- picked for the currently-equipped magazine - never overwrites the pin. In
    -- effect, the static pin is not just a first-reload fallback: it's a permanent
    -- override for the rest of the session on that weapon, even if the player later
    -- equips a bigger-capacity magazine (e.g. a "bigmag"-skinned Arev) that the
    -- native engine would have chosen a different (MagIncreased/MagHuge) montage
    -- for. Believed cosmetic-only (AnimNotify_WeaponAction replenishes ammo
    -- generically, not by literal round-count against the animation, and the pinned
    -- montage is a real resolvable AnimMontage, not a null reference) - NOT verified
    -- to be crash-safe under this exact scenario via live in-game testing. If a
    -- capacity-variant weapon's reload animation looks visibly wrong specifically
    -- after equipping a magazine upgrade, this is the first place to look. A real
    -- fix would mean only eager-caching in M.init() when the profile has no known
    -- capacity variants, letting this passive path govern otherwise - not attempted
    -- here since it touches shared logic for all 4 pinned weapons and needs live
    -- verification against a capacity-upgraded weapon before trusting it.
    if charMontage and not p.cachedCharMontage then
        p.cachedCharMontage = charMontage
        print("[Reload][" .. p.id .. "] Cached charMontage from auto-intercept callback.")
    end

    -- Pause char mesh and weapon anims. If openCylinderTime is set, initiate the
    -- time-based intro jump (play unpaused for animJumpTargetSeconds, then freeze).
    pcall(function()
        local charMesh = pawn.Mesh
        if not charMesh then return end
        local charAnimInst = charMesh.AnimScriptInstance
        if charAnimInst ~= nil and charMontage then
            if p.openCylinderTime then
                animJumpActive        = true
                animJumpElapsed       = 0.0
                animJumpTargetSeconds = (p.introJumpTicks or 120) / ANIM_JUMP_REFERENCE_FPS
                charMesh.bPauseAnims = false
                if wm ~= nil then wm.bPauseAnims = false end
                print("[Reload][" .. p.id .. "] Auto-intercept: Jump sequence started (target=" .. string.format("%.3f", animJumpTargetSeconds) .. "s).")
            else
                charMesh.bPauseAnims = true
                interceptedCharMontage = charMontage
                print("[Reload][" .. p.id .. "] charMesh.bPauseAnims=true (auto intercept).")
                if wm ~= nil then
                    wm.bPauseAnims = true
                    print("[Reload][" .. p.id .. "] Weapon anims PAUSED (auto intercept).")
                end
            end
        end
    end)

    -- isTubeFed: the pause block above has now PARKED a live native reload - both
    -- the char montage and its weapon-mesh counterpart are playing but frozen.
    -- That parked pair is exactly what the INSERT fast-forward needs: the
    -- ammo-replenish notify only works when both halves are running together
    -- (playing the char montage alone null-derefs in the native handler).
    --
    -- Skip the mag-eject work below - there is no magazine to hide, drop or
    -- replace, only shells to add. EXCEPT hideShellsDuringReload weapons (TOZ-34):
    -- unlike RAM2/SPSA/M860 where the tube's shells deliberately stay visible
    -- throughout, break-action shells look wrong sitting visible in an open,
    -- mid-reload action - hide them here, unhidden again at INSERT.
    if p.isTubeFed then
        tubeFedReloadParked = true
        if p.hideShellsDuringReload then
            if cachedWeaponMeshAddr ~= objAddr(wm) or #magMeshes == 0 then
                magMeshes = collectMagMeshes(wm, p)
                cachedWeaponMeshAddr = objAddr(wm)
            end
            if #magMeshes > 0 then
                setMagMeshesHidden(magMeshes, true, wm)
                magMeshesCurrentlyHidden = true
                print("[Reload][" .. p.id .. "] Tube-fed: hiding " .. #magMeshes .. " shell mesh(es) for reload.")
            end
        end
        if tubeFedSpoofPending then
            tubeFedSpoofPending = false
            currentState = STATE_SHELL_HOLD
            print("[Reload][" .. p.id .. "] Tube-fed: reload parked -> STATE_SHELL_HOLD (shell in hand).")
        else
            -- Unprompted native reload (ran dry). Stay IDLE with the reload parked;
            -- the player loads it by grabbing shells from the hip.
            print("[Reload][" .. p.id .. "] Tube-fed: native reload parked - grab a shell from the hip to load.")
        end
        return
    end

    -- Collect and hide real mag meshes.
    -- Only re-scan weapon children if the weapon mesh pointer has changed.
    if cachedWeaponMeshAddr ~= objAddr(wm) or #magMeshes == 0 then
        magMeshes = collectMagMeshes(wm, p)
        cachedWeaponMeshAddr = objAddr(wm)
    end
    if #magMeshes > 0 then
        setMagMeshesHidden(magMeshes, true, wm)
        magMeshesCurrentlyHidden = true
        print("[Reload][" .. p.id .. "] Auto-intercept: hiding " .. #magMeshes .. " mag mesh(es).")
    else
        -- No mag meshes found - weapon doesn't support physical reload. Bail out cleanly.
        print("[Reload][" .. p.id .. "] Auto-intercept: no _mag_full/_mag_empty children - skipping.")
        return
    end

    local proxy = spawnMagProxy(pawn, p, false, wm)
    if proxy then
        if spoofingTacticalReload then
            ejectProxy = proxy
            attachProxyToHand(ejectProxy)
            print("[Reload][" .. p.id .. "] Tactical proxy spawned and attached to left hand.")
        else
            droppingProxy   = proxy
            dropVelocity    = 0
            dropProxyReady  = false
            local magLoc = magReload.getMagBoxLocation()
            if magLoc then
                pcall(function() proxy:K2_SetWorldLocation(magLoc, false, reusable_hit_result, true) end)
                dropProxyReady = true
            end
            print("[Reload][" .. p.id .. "] Auto-eject proxy spawned. Advancing to STATE_DROPPING_EMPTY.")
        end
    else
        print("[Reload][" .. p.id .. "] WARNING: Failed to spawn proxy for auto-intercept.")
    end

    if spoofingTacticalReload then
        spoofingTacticalReload = false
        currentState = STATE_EJECT_HOLD
        print("[Reload][" .. p.id .. "] Spoofed native reload intercepted -> STATE_EJECT_HOLD.")
    else
        currentState = STATE_DROPPING_EMPTY
        print("[Reload][" .. p.id .. "] Native reload intercepted -> STATE_DROPPING_EMPTY.")
    end
end

-- on_xinput_get_state
-- Handles button suppression during hold states, grip-press state transitions,
-- and EJECT_HOLD grip-release -> DROPPING_EMPTY transition.
function M.on_xinput_get_state(state)
    local buttons = state.Gamepad.wButtons
    currentButtons = buttons
    rawTriggerHeld = (state.Gamepad.bRightTrigger or 0) > 30

    if forceNativeReloadTicks > 0 then
        local now = os.clock()
        if forceNativeReloadDeadline == 0 then
            -- First delivering poll: arm the wall-clock cap from here.
            forceNativeReloadDeadline = now + FORCE_RELOAD_MAX_HOLD
        end
        if now >= forceNativeReloadDeadline then
            -- Held too long in real time (stalled frame). Release NOW and drop any
            -- remaining tick budget - a press the engine reads as "long" triggers the
            -- consumable/quick-use action bound to long-press.
            forceNativeReloadTicks    = 0
            forceNativeReloadDeadline = 0
        else
            state.Gamepad.wButtons = state.Gamepad.wButtons | 0x4000 -- XINPUT_GAMEPAD_X
            forceNativeReloadTicks = forceNativeReloadTicks - 1
            if forceNativeReloadTicks == 0 then forceNativeReloadDeadline = 0 end
        end
    end

    local gripDown    = (buttons & GRIP_BUTTON) ~= 0
    local gripPressed = gripDown and not wasGripXinput
    wasGripXinput     = gripDown
    -- X (the reload / mag kick-out button; read before the spoofed-X injection above)
    local xDown       = (buttons & X_BUTTON) ~= 0
    local xPressed    = xDown and not wasXXinput
    wasXXinput        = xDown
    -- An X that released the slide stays hidden from the game until it is let go: the slide moves and the
    -- reload completes while it is still held, and a game-side X landing mid-completion left the weapon unable
    -- to fire (a normal press outlasts the 0.06 s slam).
    if xLatchedForSlideRelease then
        if xDown then
            state.Gamepad.wButtons = state.Gamepad.wButtons & ~X_BUTTON
        else
            xLatchedForSlideRelease = false
        end
    end

    -- Disabled: only the spoofed-X drain above stays alive (M.spoofNativeReload).
    if not enabled then return end

    -- STATE_EJECT_HOLD: suppress grip + trigger every frame.
    -- Release detection is handled in on_pre_engine_tick via currentButtons
    -- (captured above, before gamepadState:Update remaps LEFT_SHOULDER from trigger state).
    if currentState == STATE_EJECT_HOLD then
        -- Mask off the CURRENT button word, not the `buttons` snapshot taken at the top
        -- of this function: that snapshot predates the spoofed-X injection above, so
        -- writing it back silently discarded the X for this poll while still having
        -- consumed a tick of its budget - delivering the spoof as a ragged
        -- down/up/down edge instead of one clean press. The four suppression sites
        -- further down already do it this way.
        state.Gamepad.wButtons      = state.Gamepad.wButtons & ~GRIP_BUTTON
        state.Gamepad.bRightTrigger = 0
        return
    end

    -- STATE_HIP_HOLD: suppress grip + trigger every frame.
    -- Grip release handled in on_pre_engine_tick (needs distance check).
    -- STATE_INSERTING (box-mag glide into the magwell) is suppressed the same way.
    -- STATE_AWAIT_CLOSE too: no firing with the cylinder still open.
    -- STATE_AWAIT_RACK: no firing before the rack; a grip press there asks for a slide / handle grab
    -- (distance checked in on_pre_engine_tick), the release is read there from currentButtons.
    if currentState == STATE_HIP_HOLD or currentState == STATE_INSERTING or currentState == STATE_AWAIT_CLOSE
       or currentState == STATE_AWAIT_RACK then
        if currentState == STATE_AWAIT_RACK and gripPressed then rackGrabRequested = true end
        -- pistols: X drops the slide off the slide stop instead of racking it (handled in the tick); the game
        -- never sees that X (a long press there is its quick-use action)
        if currentState == STATE_AWAIT_RACK and rackSlide.canSlideRelease() then
            if xPressed then
                rackSlideReleaseRequested = true
                xLatchedForSlideRelease = true
            end
            state.Gamepad.wButtons = state.Gamepad.wButtons & ~X_BUTTON
        end
        -- Same reasoning as STATE_EJECT_HOLD above - preserve the injected X.
        state.Gamepad.wButtons      = state.Gamepad.wButtons & ~GRIP_BUTTON
        state.Gamepad.bRightTrigger = 0
        return
    end

    -- STATE_SHELL_HOLD: suppress grip + trigger every frame.
    -- Grip release handled in on_pre_engine_tick (needs distance check to the tube socket).
    if currentState == STATE_SHELL_HOLD then
        state.Gamepad.wButtons      = buttons & ~GRIP_BUTTON
        state.Gamepad.bRightTrigger = 0
        return
    end

    -- Block trigger during other active reload states.
    if currentState ~= STATE_IDLE then
        state.Gamepad.bRightTrigger = 0
    end

    -- STATE_IDLE, isTubeFed weapons.
    -- No eject/drop precursor - there's nothing to eject, only shells to add.
    -- Checked before the box-magazine path below so tube-fed weapons never fall
    -- into the mag-overlap branch there.
    --
    -- Starting the reload (no native reload parked yet) spoofs one (X) rather than
    -- entering STATE_SHELL_HOLD directly. That spoof is what starts the coordinated
    -- char+weapon montage pair; tryInterceptReload then parks (pauses) it. INSERT
    -- later just unpauses and fast-forwards that parked pair - the same proven
    -- sequence the box-magazine path uses.
    --
    -- Two different starting gestures, selected per-profile via reloadStartOnOverlap:
    --   default (hip zone)      - grip + hand at the hip starts the reload directly
    --                              (RAM2, SPSA, M860 - matches "grab a shell" as one
    --                              continuous motion with no separate start step).
    --   reloadStartOnOverlap    - grip + hand overlapping the weapon's own MagBox
    --                              starts it (TOZ-34) - same start gesture as the
    --                              Rhino/box-mag EJECT trigger just below, since the
    --                              player asked for "grab the gun like a normal
    --                              reload" as the explicit start beat, THEN reach to
    --                              the hip for shells once it's parked.
    -- Grabbing a shell once already parked is always hip-zone, regardless of the
    -- weapon's start gesture - there's nothing left on the gun to grab by then.
    if currentState == STATE_IDLE and gripPressed
       and activeProfile and activeProfile.isTubeFed then
        if tubeFedReloadParked then
            if handInHipZone then
                currentState = STATE_SHELL_HOLD
                print("[Reload][" .. activeProfile.id .. "] Left grip + hip zone -> STATE_SHELL_HOLD (reload already parked).")
                state.Gamepad.wButtons      = state.Gamepad.wButtons & ~GRIP_BUTTON
                state.Gamepad.bRightTrigger = 0
                return
            end
        else
            local startGripped = activeProfile.reloadStartOnOverlap
                                  and magReload.isHandOverlappingMag()
                                  or (not activeProfile.reloadStartOnOverlap and handInHipZone)
            if startGripped then
                tubeFedSpoofPending    = true
                forceNativeReloadTicks = 3
                print("[Reload][" .. activeProfile.id .. "] Left grip start gesture -> spoofing native reload to park montages.")
                state.Gamepad.wButtons      = state.Gamepad.wButtons & ~GRIP_BUTTON
                state.Gamepad.bRightTrigger = 0
                return
            end
        end
    end

    -- STATE_IDLE: eject trigger.
    -- Left grip pressed + hand overlapping mag -> SPOOF X BUTTON, suppress immediately.
    if currentState == STATE_IDLE and gripPressed and magReload.isHandOverlappingMag()
       and not (activeProfile and activeProfile.isTubeFed) then
        if activeProfile then
            spoofingTacticalReload = true
            forceNativeReloadTicks = 3
            state.Gamepad.wButtons      = state.Gamepad.wButtons & ~GRIP_BUTTON
            state.Gamepad.bRightTrigger = 0
            print("[Reload][" .. activeProfile.id .. "] Left grip + mag overlap -> Triggering spoofed native reload.")
            return
        end
    end

    -- STATE_DROPPED: hip zone grab.
    -- Left grip pressed + hand in left hip zone -> HIP_HOLD, suppress immediately.
    if currentState == STATE_DROPPED and gripPressed and handInHipZone then
        currentState = STATE_HIP_HOLD
        state.Gamepad.wButtons      = state.Gamepad.wButtons & ~GRIP_BUTTON
        state.Gamepad.bRightTrigger = 0
        print("[Reload] Left grip + hip zone -> STATE_HIP_HOLD (fresh mag from hip).")
        return
    end
end

-- on_pre_engine_tick
-- Handles deferred anim resets, proxy spawning (first tick of hold states),
-- kinematic fall physics, and HIP_HOLD grip-release insert/drop logic.
-- Per-weapon tuning saved by the dev panel in Config.weaponProfiles[<weapon name>] (the same
-- table Entry.lua's saveWeaponProfile uses; lastInitWeaponName is that key, passed to M.init).
local function getWeaponTuning()
    if lastInitWeaponName == nil or Config.weaponProfiles == nil then return nil end
    return Config.weaponProfiles[lastInitWeaponName]
end

local function getFinishRate()
    local wp = getWeaponTuning()
    local r = (wp and wp.ptmFinishRate) or Config.ptmFinishRate or DEFAULT_FINISH_RATE
    if r < 1 then r = 1 end
    return r
end

-- Box-mag INSERT completion: un-hide the real mags, then replenish ammo by playing / fast-
-- forwarding the native reload. Shared by the instant snap and by the end of the insert glide.
-- Moved verbatim out of the STATE_HIP_HOLD release branch (2026-10-03).
local function completeBoxMagInsert(pawn, weaponMesh, p)
    setMagMeshesHidden(magMeshes, false, weaponMesh)
    magMeshesCurrentlyHidden = false
    magMeshes = {}

    pcall(function()
        local charMesh = pawn.Mesh
        if not charMesh then
            print("[DBG][INSERT] pawn.Mesh is nil - cannot replenish ammo")
            return
        end
        local charAnimInst = charMesh.AnimScriptInstance
        if charAnimInst == nil then
            print("[DBG][INSERT] charAnimInst is nil - cannot replenish ammo")
            return
        end

        -- The fast-forward below crosses the game's AnimNotify_EjectMagazine: hide the mag it
        -- spawns (see beginEjectHideWindow).
        beginEjectHideWindow()

        print("[DBG][INSERT] handling weaponMesh + charMesh bPauseAnims")
        -- For tube-fed shotguns: can't use 100x because the weapon AnimBP has a
        -- self-looping In->In section that overflows native section-change callbacks
        -- at 100x and crashes. Use a safe lower rate (15x) instead - fast enough
        -- to feel snappy, slow enough not to crash the loop.
        -- For all other weapons: use 100x as usual.
        -- Box mags: per-weapon finish rate (dev panel, default 100x). The window starts at the
        -- old 0.15 s and is shortened below once the montage length is known.
        weaponMesh.bPauseAnims = false
        if p and p.isTubeFed then
            finishRate   = DEFAULT_FINISH_RATE
            finishWindow = FINISH_WINDOW_MAX
            weaponMesh.GlobalAnimRateScale = 15.0
            weaponAnimResetArmed           = true
            weaponAnimResetTime            = os.clock() + 0.8
        else
            finishRate   = getFinishRate()
            finishWindow = FINISH_WINDOW_MAX
            weaponMesh.GlobalAnimRateScale = finishRate
            weaponAnimResetArmed           = true
            weaponAnimResetTime            = os.clock() + finishWindow
        end
        charMesh.bPauseAnims = false

        -- Montage assets are package-owned; they only go away on level change,
        -- which clears interceptedCharMontage via reset(). No exists() probe.
        local isAutoPath   = interceptedCharMontage ~= nil
        local montageToPlay = isAutoPath and interceptedCharMontage or nil
        interceptedCharMontage = nil
        print("[DBG][INSERT] isAutoPath=" .. tostring(isAutoPath) .. " montageToPlay from intercept=" .. tostring(montageToPlay ~= nil))
        if not montageToPlay then
            print("[DBG][INSERT] TACTICAL path - cachedCharMontage=" .. tostring(p.cachedCharMontage ~= nil) .. " charMontage=" .. tostring(p.charMontage))
            -- 1. Static find_uobject (for WEAPON_PROFILES entries with a known path).
            -- NOTE: LoadAsset_Blocking removed - it is a synchronous disk stall.
            -- If find_uobject returns nil here, the montage is not yet in memory.
            -- The dynamic discovery fallback below will attempt a GUObjectArray scan.
            if not p.cachedCharMontage and p.charMontage then
                print("[DBG][INSERT] Trying static find_uobject: " .. p.charMontage)
                p.cachedCharMontage = findUObjectCached(p.charMontage)
                if p.cachedCharMontage then
                    print("[DBG][INSERT] Static find_uobject succeeded.")
                else
                    print("[DBG][INSERT] Static find_uobject returned nil - falling through to discovery.")
                end
            end
            -- 2. Dynamic discovery fallback (scans all loaded AnimMontages by name pattern).
            if not p.cachedCharMontage and p.id then
                print("[DBG][INSERT] Static path failed/absent - attempting final dynamic discovery for " .. p.id)
                discoveryCache[p.id] = nil  -- clear stale nil so rescan runs
                p.cachedCharMontage = discoverReloadMontage(p.id)
                print("[DBG][INSERT] Dynamic discovery result: " .. tostring(p.cachedCharMontage ~= nil))
            end
            -- 3. Read directly from the AnimBP instance properties.
            -- The character AnimBP stores the active weapon's reload montage in known
            -- fields populated at weapon equip time. Try common property names.
            if not p.cachedCharMontage then
                print("[DBG][INSERT] Trying AnimBP property read...")
                local animBpMontage = nil
                pcall(function()
                    -- Try the most common property names from Stalker2 ABP.
                    animBpMontage = charAnimInst.ReloadMontage
                        or charAnimInst.ReloadTacticalMontage
                        or charAnimInst.CharMontage
                        or charAnimInst.CurrentReloadMontage
                end)
                if animBpMontage ~= nil then
                    p.cachedCharMontage = animBpMontage
                    print("[DBG][INSERT] AnimBP property read succeeded: " .. tostring(animBpMontage:get_full_name()))
                else
                    print("[DBG][INSERT] AnimBP property read returned nil.")
                end
            end
            montageToPlay = p.cachedCharMontage
            print("[DBG][INSERT] final montageToPlay=" .. tostring(montageToPlay ~= nil))
        end

        if montageToPlay then
            -- Size the fast-forward window from the montage's real length at finishRate,
            -- so both meshes drop back to 1x right after the reload ends instead of running
            -- their idle at finishRate for the rest of a fixed 0.15 s.
            if not (p and p.isTubeFed) then
                local len = nil
                pcall(function() len = montageToPlay:GetPlayLength() end)
                if type(len) ~= "number" or len <= 0 then
                    pcall(function() len = montageToPlay.SequenceLength end)
                end
                if type(len) == "number" and len > 0 then
                    finishWindow = math.min(FINISH_WINDOW_MAX,
                        math.max(FINISH_WINDOW_MARGIN, len / finishRate + FINISH_WINDOW_MARGIN))
                    weaponAnimResetTime = os.clock() + finishWindow
                    print(string.format("[DBG][INSERT] finish: rate=%.0fx montage=%.2fs window=%.3fs", finishRate, len, finishWindow))
                end
            end
            print("[DBG][INSERT] setting GlobalAnimRateScale=1.0, calling Montage_Play, deferring fast-forward")
            tacticalReloadTriggerTime  = os.clock()
            charMesh.GlobalAnimRateScale = 1.0
            local playOk, playErr = pcall(function()
                plugin.executeFunction(charAnimInst, "Montage_Play", montageToPlay, 1.0)
            end)
            print("[DBG][INSERT] Montage_Play pcall result: ok=" .. tostring(playOk) .. (playOk and "" or " err=" .. tostring(playErr)))
            charAnimFastForwardArmed = true
            local pathLabel = isAutoPath and "AUTO" or "TACTICAL"
            print("[Reload][" .. p.id .. "] " .. pathLabel .. ": Inserted. Montage_Play started natively.")
        else
            print("[Reload][" .. p.id .. "] INSERT: charMontage unavailable - ammo not replenished.")
        end
    end)

    activeProfile         = activeProfile  -- keep alive for back-to-back reloads
    reloadCooldownEndTime = os.clock() + 1.0
    currentState          = STATE_IDLE
    print("[Reload][" .. p.id .. "] Mag inserted! Reload complete.")
end

-- Box-mag insert done (glide seated or snap): after an EMPTY reload on a weapon type with "rack to
-- chamber" on, the mag shows in the gun and the reload waits in STATE_AWAIT_RACK (native reload still
-- paused, trigger suppressed) until the slide / handle is racked; otherwise it completes as before.
local function completeOrRack(pawn, weaponMesh, p)
    -- box mags only: tube-fed / Rhino reloads never rack (shotgun folder holds pump + box-mag guns alike)
    local boxMag = not (p and (p.isTubeFed or isRhinoProfile(p)))
    if boxMag and rackSlide.shouldRack(weaponMesh, reloadWasEmpty) and rackSlide.begin(weaponMesh) then
        setMagMeshesHidden(magMeshes, false, weaponMesh)
        magMeshesCurrentlyHidden = false
        magMeshes = {}
        rackGrabRequested = false
        rackSlideReleaseRequested = false
        currentState = STATE_AWAIT_RACK
        print("[Reload][" .. tostring(p and p.id) .. "] Mag seated - waiting for the rack.")
        return
    end
    completeBoxMagInsert(pawn, weaponMesh, p)
end

-- Per tick while STATE_AWAIT_RACK. Grab on a grip press near the slide / handle, rack on release
-- (rack_slide.lua drives the part in post-stereo), complete once the part has sprung forward.
local function stepAwaitRack(pawn, weaponMesh, gripReleased)
    local p = activeProfile
    -- weapon gone / switched, or rack-to-chamber switched off for this type mid-wait: complete
    local sameWeapon = weaponMesh ~= nil and objAddr(weaponMesh) == rackSlide.weaponAddr()
    if not sameWeapon or not rackSlide.isActive() or not rackSlide.shouldRack(weaponMesh, true) then
        rackSlide.finish(sameWeapon)
        rackGrabRequested = false
        rackSlideReleaseRequested = false
        completeBoxMagInsert(pawn, weaponMesh, p)
        return
    end
    if rackGrabRequested then
        rackGrabRequested = false
        rackSlide.tryGrab()
    end
    if rackSlideReleaseRequested then
        rackSlideReleaseRequested = false
        if rackSlide.slideRelease() then   -- no-op once the hand is on the slide
            print("[Reload][" .. tostring(p and p.id) .. "] Slide release (X).")
        end
    end
    if gripReleased then
        rackSlide.release()
    end
    if rackSlide.isDone() then
        rackSlide.complete()   -- a slammed pistol slide stays held closed until the completion closes the bones
        print("[Reload][" .. tostring(p and p.id) .. "] Racked - completing the reload.")
        completeBoxMagInsert(pawn, weaponMesh, p)
    end
end

-- Tube-fed shell INSERT completion: cancel the intro jump, un-park and fast-forward the parked
-- native reload (that's what adds the ammo), un-hide hidden shells. Shared by the instant snap
-- and by the end of the shell insert glide. Moved verbatim out of STATE_SHELL_HOLD (2026-10-03).
-- The caller sets currentState.
local function completeShellInsert(pawn, weaponMesh, p)
    -- Cancel a still-running intro-jump sequence (openCylinderTime/
    -- introJumpTicks - see the shell-grab print above). If the player
    -- releases fast, animJumpActive can still be running when INSERT
    -- fires; left alone it would force bPauseAnims=true again partway
    -- into the fast-forward below, cutting the notify-crossing
    -- playback short and leaving ammo un-replenished. INSERT takes over
    -- pause/rate control from here, so the intro sequence's job is done.
    if animJumpActive then
        animJumpActive  = false
        animJumpElapsed = 0.0
        print("[Reload][" .. p.id .. "] Intro-jump sequence cancelled - INSERT taking over.")
    end

    pcall(function()
        local charMesh = pawn.Mesh
        if not charMesh then return end
        local charAnimInst = charMesh.AnimScriptInstance
        if charAnimInst == nil then return end

        -- 15x, not 100x: the weapon AnimBP's self-looping In->In
        -- section overflows native section-change callbacks at 100x
        -- and crashes (same reason the box-mag path special-cases
        -- isTubeFed).
        if weaponMesh ~= nil then
            weaponMesh.bPauseAnims         = false
            weaponMesh.GlobalAnimRateScale = SHELL_INSERT_RATE
            weaponAnimResetArmed           = true
            weaponAnimResetTime            = os.clock() + SHELL_INSERT_DURATION
        end
        charMesh.bPauseAnims         = false
        charMesh.GlobalAnimRateScale = SHELL_INSERT_RATE
        charAnimResetArmed           = true
        charAnimResetTime            = os.clock() + SHELL_INSERT_DURATION
        print("[Reload][" .. p.id .. "] Shell inserted - parked reload fast-forwarded at " .. SHELL_INSERT_RATE .. "x.")
    end)

    -- Unhide shell meshes hidden at park time (hideShellsDuringReload
    -- weapons only - magMeshes stays empty for RAM2/SPSA/M860 so this is a
    -- no-op there). Same timing as the box-mag INSERT path uses.
    if #magMeshes > 0 then
        setMagMeshesHidden(magMeshes, false)
        magMeshesCurrentlyHidden = false
        magMeshes = {}
    end

    -- The parked reload is now running itself out.
    tubeFedReloadParked    = false
    interceptedCharMontage = nil
end

-- ---------------------------------------------------------------------------
-- Box-mag insert glide (STATE_INSERTING) - see the insertGlide declaration.
-- ---------------------------------------------------------------------------
local function getInsertGlideTime()
    local wp = getWeaponTuning()
    if wp and wp.ptmInsertGlideTime ~= nil then return wp.ptmInsertGlideTime end
    local v = Config.ptmInsertGlideTime
    if v == nil then return DEFAULT_INSERT_GLIDE_TIME end
    return v
end

-- Precedence: per-weapon dev-panel override (weaponProfiles[name].ptmInsertAxis/Depth), then
-- WEAPON_PROFILES insertAxis/insertDepth, then the global dev-panel values.
local function getInsertAxis(p)
    local wp = getWeaponTuning()
    local a = (wp and wp.ptmInsertAxis) or (p and p.insertAxis) or Config.ptmInsertAxis or DEFAULT_INSERT_AXIS
    local x, y, z = a[1] or 0, a[2] or 0, a[3] or 0
    local len = math.sqrt(x * x + y * y + z * z)
    if len < 1e-4 then
        x, y, z = DEFAULT_INSERT_AXIS[1], DEFAULT_INSERT_AXIS[2], DEFAULT_INSERT_AXIS[3]
        len = 1
    end
    return x / len, y / len, z / len
end

local function getInsertDepth(p)
    local wp = getWeaponTuning()
    return (wp and wp.ptmInsertDepth) or (p and p.insertDepth) or Config.ptmInsertDepth or DEFAULT_INSERT_DEPTH
end

-- The real (hidden) mag mesh the proxy will become: prefer the child whose StaticMesh
-- is the proxy's own mesh asset (the _full variant), else the first live mag child.
local function findInsertTarget(weaponMesh, p)
    local proxyAssetAddr = nil
    if p and p.cachedMeshAsset then proxyAssetAddr = objAddr(p.cachedMeshAsset) end
    local first, match = nil, nil
    for _, entry in ipairs(magMeshes) do
        local child = findLiveChildByAddr(weaponMesh, entry.addr)
        if child ~= nil then
            first = first or child
            if match == nil and proxyAssetAddr ~= nil then
                pcall(function()
                    if child.StaticMesh ~= nil and objAddr(child.StaticMesh) == proxyAssetAddr then
                        match = child
                    end
                end)
            end
        end
    end
    return match or first
end

-- Per-weapon seat offset for bare-socket seats (Rhino speedloader), socket space:
-- weaponProfiles[name].ptmSeatLoc {x,y,z} cm / ptmSeatRot {pitch,yaw,roll} degrees.
local function getSeatOffset()
    local wp = getWeaponTuning()
    local sl = (wp and wp.ptmSeatLoc) or {0, 0, 0}
    local sr = (wp and wp.ptmSeatRot) or {0, 0, 0}
    return {x = sl[1] or 0, y = sl[2] or 0, z = sl[3] or 0},
           quat.fromRotator(sr[1] or 0, sr[2] or 0, sr[3] or 0)
end

-- Called on a near-socket release in STATE_HIP_HOLD. Returns false when the glide
-- doesn't apply (disabled, not a box mag, no live target) so the caller snaps as before.
local function startInsertGlide(pawn, weaponMesh, p)
    local duration = getInsertGlideTime()
    if duration <= 0 or p == nil or weaponMesh == nil then return false end
    -- Tube-fed shells / RPG rocket glide via startShellInsertGlide (STATE_SHELL_HOLD).
    if p.isTubeFed then return false end
    if not isAlive(heldProxy) then return false end

    -- seatOnSocket profiles (Rhino speedloader): its real loader/bullet/drum-lock meshes are
    -- hidden and posed by the paused double-action montage, not sitting in the open cylinder,
    -- so they're no use as a seat target. Seat on the MagBox socket instead (the point the
    -- insert-distance check measures to) plus the per-weapon seat offset tuned by eye.
    if p.seatOnSocket then
        local socketFName = magReload.getMagBoxSocketName()
        if socketFName == nil then
            print("[Reload][" .. tostring(p.id) .. "] Speedloader glide: no MagBox socket - snapping.")
            return false
        end
        insertGlide = {
            kind = "mag",
            pending = true, pendingTicks = 0, elapsed = 0, duration = duration,
            proxy = heldProxy, weaponMesh = weaponMesh, weaponAddr = objAddr(weaponMesh),
            targetChild = nil, socket = socketFName, useSeatOffset = true, profile = p,
        }
        heldProxy    = nil
        currentState = STATE_INSERTING
        print("[Reload][" .. tostring(p.id) .. "] Speedloader glide started (" .. duration .. "s).")
        return true
    end

    local target = findInsertTarget(weaponMesh, p)
    if target == nil then
        print("[Reload][" .. tostring(p.id) .. "] Insert glide: no live mag mesh to seat into - snapping.")
        return false
    end

    insertGlide = {
        kind = "mag",
        pending = true, pendingTicks = 0, elapsed = 0, duration = duration,
        proxy = heldProxy, weaponMesh = weaponMesh, weaponAddr = objAddr(weaponMesh),
        targetChild = target, profile = p,
    }
    heldProxy    = nil
    currentState = STATE_INSERTING
    print("[Reload][" .. tostring(p.id) .. "] Insert glide started (" .. duration .. "s).")
    return true
end

-- Tube-fed counterpart, called on a release overlapping the MagBox in STATE_SHELL_HOLD.
-- Seats the shell(s) at the loading port: the real shell child attached to the MagBox's
-- own socket if there is one (the shell proxy borrows that mesh), else the first live
-- shell child, else the bare socket. Same glide, same axis/depth/time settings (use the
-- per-weapon overrides to point the axis out of the port / the RPG-7 muzzle).
local function startShellInsertGlide(pawn, weaponMesh, p)
    local duration = getInsertGlideTime()
    if duration <= 0 or p == nil or weaponMesh == nil then return false end
    if not isAlive(shellProxy) then return false end

    local socketFName = magReload.getMagBoxSocketName()
    local socketStr = nil
    if socketFName ~= nil then
        pcall(function() socketStr = string.lower(socketFName:to_string()) end)
    end

    -- seatOnSocket profiles (RPG-7 rocket): bare socket + per-weapon seat offset, like the
    -- Rhino speedloader - see the WEAPON_PROFILES comment on sk_rpg7.
    if p.seatOnSocket then
        if socketFName == nil then
            print("[Reload][" .. tostring(p.id) .. "] Shell insert glide: no MagBox socket - snapping.")
            return false
        end
        insertGlide = {
            kind = "shell",
            pending = true, pendingTicks = 0, elapsed = 0, duration = duration,
            proxy = shellProxy, weaponMesh = weaponMesh, weaponAddr = objAddr(weaponMesh),
            targetChild = nil, socket = socketFName, useSeatOffset = true, profile = p,
        }
        shellProxy   = nil
        currentState = STATE_INSERTING
        print("[Reload][" .. tostring(p.id) .. "] Shell insert glide started on socket + seat offset (" .. duration .. "s).")
        return true
    end

    local target, first = nil, nil
    for _, entry in ipairs(collectMagMeshes(weaponMesh, p)) do
        local child = findLiveChildByAddr(weaponMesh, entry.addr)
        if child ~= nil then
            first = first or child
            if target == nil and socketStr ~= nil then
                pcall(function()
                    if string.lower(child.AttachSocketName:to_string()) == socketStr then
                        target = child
                    end
                end)
            end
        end
    end
    target = target or first
    if target == nil and socketFName == nil then
        print("[Reload][" .. tostring(p.id) .. "] Shell insert glide: no shell mesh or port socket - snapping.")
        return false
    end

    insertGlide = {
        kind = "shell",
        pending = true, pendingTicks = 0, elapsed = 0, duration = duration,
        proxy = shellProxy, weaponMesh = weaponMesh, weaponAddr = objAddr(weaponMesh),
        targetChild = target, socket = socketFName, profile = p,
    }
    shellProxy   = nil
    currentState = STATE_INSERTING
    print("[Reload][" .. tostring(p.id) .. "] Shell insert glide started (" .. duration .. "s"
        .. (target and "" or ", bare socket target") .. ").")
    return true
end

-- Re-parents the proxy in place onto the real mag's socket and records the path.
-- Runs from the post-stereo callback: the hand PMC (the proxy's parent) and the
-- UObjectHook-driven weapon mesh only hold their real poses there, and KeepWorld
-- computes the new relative transform from both parents' CURRENT world poses.
local function beginInsertGlide()
    local g = insertGlide
    if g == nil or not g.pending then return end
    g.pending = false
    local ok, err = pcall(function()
        local wm, child, proxy = g.weaponMesh, g.targetChild, g.proxy
        local socket

        if child ~= nil then
            -- Seat target = the real mag/shell's own transform relative to its socket
            socket = child.AttachSocketName
            local rl, rr = child.RelativeLocation, child.RelativeRotation
            g.toLoc  = {x = rl.X, y = rl.Y, z = rl.Z}
            g.toQuat = quat.fromRotator(rr.Pitch, rr.Yaw, rr.Roll)
        else
            -- Bare-socket seat: shells with no live shell mesh, and the Rhino speedloader
            -- (which adds the per-weapon seat offset, socket space, cm / degrees)
            socket   = g.socket
            g.toLoc  = {x = 0, y = 0, z = 0}
            g.toQuat = {w = 1, x = 0, y = 0, z = 0}
            if g.useSeatOffset then
                g.toLoc, g.toQuat = getSeatOffset()
            end
        end

        -- Insertion axis: weapon component space -> world -> socket space
        local ax, ay, az = getInsertAxis(g.profile)
        local wr = wm:K2_GetComponentRotation()
        local sr = wm:GetSocketRotation(socket)
        local axWorld = quat.rotate(quat.fromRotator(wr.Pitch, wr.Yaw, wr.Roll), ax, ay, az)
        local axSock  = quat.rotate(quat.inv(quat.fromRotator(sr.Pitch, sr.Yaw, sr.Roll)), axWorld.x, axWorld.y, axWorld.z)
        local depth = getInsertDepth(g.profile)
        g.preLoc = {
            x = g.toLoc.x + axSock.x * depth,
            y = g.toLoc.y + axSock.y * depth,
            z = g.toLoc.z + axSock.z * depth,
        }

        -- KeepWorld (1,1,1): the mag stays exactly where it left the hand
        proxy:K2_AttachToComponent(wm, socket, 1, 1, 1, false)
        local pl, pr = proxy.RelativeLocation, proxy.RelativeRotation
        g.fromLoc  = {x = pl.X, y = pl.Y, z = pl.Z}
        g.fromQuat = quat.fromRotator(pr.Pitch, pr.Yaw, pr.Roll)
    end)
    if not ok then
        print("[Reload] Insert glide start failed, snapping: " .. tostring(err))
        g.failed = true
    end
end

uevrUtils.registerPostCalculateStereoViewCallback(function(device, view_index)
    if currentState == STATE_INSERTING and insertGlide ~= nil and insertGlide.pending then
        beginInsertGlide()
    end
end)

local function lerp3(a, b, t)
    return {x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t, z = a.z + (b.z - a.z) * t}
end

local function writeProxyRelative(proxy, loc, q)
    local rp, ry, rr = quat.toRotator(q)
    proxy:K2_SetRelativeLocationAndRotation(
        uevrUtils.vector(loc.x, loc.y, loc.z), uevrUtils.rotator(rp, ry, rr), false, {}, false)
end

-- shellsPerGrab (TOZ-34 = 2): the extra shells beside the first, attached to it so they move as one unit.
-- Used by the shell in the hand and by the belt pouch copy. Returns the created components.
local function addExtraShells(pawn, firstShell, p)
    local childProxies = {}
    if not (p.shellsPerGrab and p.shellsPerGrab > 1 and p.cachedMeshAsset) then return childProxies end
    local smClass = getSmClass()
    if not smClass then return childProxies end
    for i = 2, p.shellsPerGrab do
        pcall(function()
            local bp = uevr.api:add_component_by_class(pawn, smClass)
            if isAlive(bp) then
                bp:SetStaticMesh(p.cachedMeshAsset)
                bp:SetCollisionEnabled(0)
                bp:SetHiddenInGame(false)
                applyForegroundFOV(bp)
                -- no weld: the shells have no collision (same as the Rhino bullets, crash 2026-10-18)
                bp:K2_AttachToComponent(firstShell, uevrUtils.fname_from_string("None"), 2, 2, 2, false)
                bp.RelativeLocation.Y = (i - 1) * SHELL_GRAB_SPACING
                table.insert(childProxies, bp)
            end
        end)
    end
    return childProxies
end

-- ---------------------------------------------------------------------------
-- Belt pouch (2026-10-17): while a weapon with manual reload is held, the ammo the next hip grab takes - the full
-- box mag, the shell(s) / round, the Rhino speedloader, the RPG rocket - sits at the left hip (body_items slot
-- "ammo": same anchor, menu hiding and placement sliders as the other body items). It is built by spawnMagProxy,
-- the code that builds the one landing in the hand, so both look the same. Hidden while that one is out of the
-- pouch (hold / insert / await close); a grab glides it from the pouch into the hand (grabGlide).
-- ---------------------------------------------------------------------------
local POUCH_REFRESH_S = 1.0
local pouchRefreshAt = 0

local function pouchType(p)
    if isRhinoProfile(p) then return "speedloader" end
    if p.isTubeFed then return p.ammoMeshPattern and "rocket" or "shell" end
    return "mag"
end

local function buildPouch(pawn, p)
    if p ~= activeProfile then return nil end
    local proxy = spawnMagProxy(pawn, p, true, getPistolWeaponMesh(pawn))
    if not isAlive(proxy) then return nil end
    -- body_items owns these components from here on (destroys the parts with the item)
    local parts = aggregateChildren[proxy] or {}
    aggregateChildren[proxy] = nil
    if p.isTubeFed then
        for _, c in ipairs(addExtraShells(pawn, proxy, p)) do table.insert(parts, c) end
    end
    return proxy, parts
end

local function pouchSource()
    if not enabled then return nil, "manual reload is off" end
    local p = activeProfile
    if p == nil then return nil, "no weapon with manual reload" end
    local pawn = uevr.api:get_local_pawn(0)
    local wm = pawn and getPistolWeaponMesh(pawn) or nil
    if wm == nil then return nil, "no weapon" end
    -- Look the mesh up again now and then while idle: a mag swapped in the inventory (GP3A capacities) keeps the
    -- weapon name, so M.init does not run, and the old mesh asset may be unloaded. Never cleared to nil here (an
    -- empty tube can have no round child to read).
    local now = os.clock()
    if now >= pouchRefreshAt and currentState == STATE_IDLE and not tubeFedReloadParked then
        pouchRefreshAt = now + POUCH_REFRESH_S
        local fresh = pickMagAsset(wm, p, false)
        if fresh == nil and not p.cachedMeshAsset and p.proxyMesh then fresh = findUObjectCached(p.proxyMesh) end
        if fresh ~= nil and objAddr(fresh) ~= objAddr(p.cachedMeshAsset) then
            p.cachedMeshAsset = fresh
            p.cachedEmptyMeshAsset = nil
            p.pouchSignature = nil
        end
    end
    if not p.cachedMeshAsset then return nil, tostring(p.id) .. ": no ammo mesh found (no manual reload for it?)" end
    if p.pouchSignature == nil then
        local meshName = "?"
        pcall(function() meshName = p.cachedMeshAsset:get_fname():to_string() end)
        p.pouchLabel = meshName
        p.pouchSignature = tostring(p.id) .. "|" .. meshName .. "|" .. tostring(objAddr(p.cachedMeshAsset))
    end
    local out = currentState == STATE_HIP_HOLD or currentState == STATE_SHELL_HOLD
        or currentState == STATE_INSERTING or currentState == STATE_AWAIT_CLOSE
    return {
        signature = p.pouchSignature, label = p.pouchLabel, type = pouchType(p), hidden = out,
        build = function(buildPawn) return buildPouch(buildPawn, p) end,
    }
end
bodyItems.setProvider("ammo", pouchSource)

-- ---------------------------------------------------------------------------
-- Hip grab glide: the proxy just attached to the hand is moved to the pouch item's world transform in the
-- post-stereo callback (hand PMC and pouch anchor only hold this frame's poses there - same rule as the insert
-- glide), its relative transform read back, then eased to the normal hand offset over Config.ptmHipGrabGlideTime.
-- ---------------------------------------------------------------------------
local function getGrabGlideTime()
    local v = Config.ptmHipGrabGlideTime
    if v == nil then return DEFAULT_GRAB_GLIDE_TIME end
    return v
end

-- Called right after a grabbed mag / shell was attached to the hand
local function startGrabGlide(proxy)
    grabGlide = nil
    local duration = getGrabGlideTime()
    if duration <= 0 or not isAlive(proxy) then return end
    local pouch = bodyItems.getShownComponent("ammo")
    if pouch == nil then return end
    grabGlide = { proxy = proxy, pouch = pouch, pending = true, pendingTicks = 0, elapsed = 0, duration = duration }
end

local function beginGrabGlide()
    local g = grabGlide
    if g == nil or not g.pending then return end
    g.pending = false
    local ok, err = pcall(function()
        local proxy, pouch = g.proxy, g.pouch
        local l = pouch:K2_GetComponentLocation()
        local r = pouch:K2_GetComponentRotation()
        local s = pouch:K2_GetComponentScale()
        proxy:K2_SetWorldLocationAndRotation(uevrUtils.vector(l.X, l.Y, l.Z), uevrUtils.rotator(r.Pitch, r.Yaw, r.Roll),
            false, reusable_hit_result, false)
        proxy:SetWorldScale3D(uevrUtils.vector(s.X, s.Y, s.Z))
        local pl, pr, ps = proxy.RelativeLocation, proxy.RelativeRotation, proxy.RelativeScale3D
        g.fromLoc   = {x = pl.X, y = pl.Y, z = pl.Z}
        g.fromQuat  = quat.fromRotator(pr.Pitch, pr.Yaw, pr.Roll)
        g.fromScale = {x = ps.X, y = ps.Y, z = ps.Z}
        local tl, tr = getProxyLoc(), getProxyRot()
        g.toLoc  = {x = tl[1], y = tl[2], z = tl[3]}
        g.toQuat = quat.fromRotator(tr[1], tr[2], tr[3])
    end)
    if not ok then
        print("[Reload] Hip grab glide start failed, snapping: " .. tostring(err))
        grabGlide = nil
        attachProxyToHand(g.proxy)
        pcall(function() g.proxy:SetRelativeScale3D(uevrUtils.vector(1, 1, 1)) end)
    end
end

uevrUtils.registerPostCalculateStereoViewCallback(function(device, view_index)
    if grabGlide ~= nil and grabGlide.pending then
        beginGrabGlide()
    end
end)

-- Per tick while the grabbed mag / shell is held. Ends itself once the proxy is no longer the one held
-- (inserted, dropped, aborted).
local function stepGrabGlide(delta)
    local g = grabGlide
    if g == nil then return end
    if (g.proxy ~= heldProxy and g.proxy ~= shellProxy) or not isAlive(g.proxy) then
        grabGlide = nil
        return
    end
    if g.pending then
        g.pendingTicks = g.pendingTicks + 1
        -- no stereo callback picked it up: leave the proxy where it is, at the hand offset
        if g.pendingTicks >= INSERT_PENDING_FALLBACK_TICKS then grabGlide = nil end
        return
    end
    g.elapsed = g.elapsed + (delta or 0)
    local t = math.min(g.elapsed / g.duration, 1)
    local e = 1 - (1 - t) ^ 3
    local sc = lerp3(g.fromScale, {x = 1, y = 1, z = 1}, e)
    local ok = pcall(function()
        writeProxyRelative(g.proxy, lerp3(g.fromLoc, g.toLoc, e), quat.slerp(g.fromQuat, g.toQuat, e))
        g.proxy:SetRelativeScale3D(uevrUtils.vector(sc.x, sc.y, sc.z))
    end)
    if t >= 1 or not ok then grabGlide = nil end
end

-- ---------------------------------------------------------------------------
-- Flick to close (flickToClose profiles, i.e. the Rhino speedloader).
-- The seated loader stays parked in the open cylinder (weapon anims stay paused, real
-- loader meshes stay hidden) until the RIGHT hand flicks to the right, like snapping the
-- cylinder shut; then the normal box INSERT completion runs.
-- Flick = sideways speed (along the HMD's horizontal right vector) of two points on the
-- right controller: one FLICK_TIP_CM ahead of it (catches a yaw swing of the gun) and one
-- FLICK_TOP_CM above it (catches a wrist roll). Either over Config.ptmFlickCloseSpeed
-- (cm/s) for FLICK_HIT_TICKS consecutive ticks closes it.
-- ---------------------------------------------------------------------------
local FLICK_TIP_CM     = 30.0
local FLICK_TOP_CM     = 20.0
local FLICK_ARM_TIME   = 0.15  -- s after seating before a flick counts
local FLICK_HIT_TICKS  = 2
local DEFAULT_FLICK_CLOSE_SPEED = 150.0

local function flickToCloseActive(p)
    return p ~= nil and p.flickToClose == true and Config.ptmFlickToClose ~= false
end

-- {tip = {x,y,z}, top = {x,y,z}, right = {x,y} (flat, normalised)} or nil
local function sampleRightHandFlickPoints()
    local s = nil
    pcall(function()
        local loc = controllers.getControllerLocation(Handed.Right)
        local fwd = controllers.getControllerDirection(Handed.Right)
        local up  = controllers.getControllerUpVector(Handed.Right)
        local hr  = controllers.getControllerRightVector(2)
        if loc == nil or fwd == nil or up == nil or hr == nil then return end
        local len = math.sqrt(hr.X * hr.X + hr.Y * hr.Y)
        if len < 0.01 then return end
        s = {
            tip   = {x = loc.X + fwd.X * FLICK_TIP_CM, y = loc.Y + fwd.Y * FLICK_TIP_CM, z = loc.Z + fwd.Z * FLICK_TIP_CM},
            top   = {x = loc.X + up.X * FLICK_TOP_CM,  y = loc.Y + up.Y * FLICK_TOP_CM,  z = loc.Z + up.Z * FLICK_TOP_CM},
            right = {x = hr.X / len, y = hr.Y / len},
        }
    end)
    return s
end

local function enterAwaitClose(proxy, p, weaponMesh)
    awaitClose = {proxy = proxy, profile = p, weaponAddr = objAddr(weaponMesh), elapsed = 0, last = nil, hits = 0}
    currentState = STATE_AWAIT_CLOSE
    print("[Reload][" .. tostring(p and p.id) .. "] Speedloader seated - flick right hand to the right to close.")
end

local function finishAwaitClose(pawn, weaponMesh, closedByFlick)
    local a = awaitClose
    awaitClose = nil
    if a ~= nil and a.proxy ~= nil then destroyProxy(a.proxy, pawn) end
    if closedByFlick then
        pcall(function() uevrUtils.triggerHapticVibration(Handed.Right, 0, 0.06, 1000, 1.0) end)
    end
    completeBoxMagInsert(pawn, weaponMesh, (a and a.profile) or activeProfile)
end

-- Per tick while STATE_AWAIT_CLOSE
local function stepAwaitClose(delta, pawn, weaponMesh)
    local a = awaitClose
    -- Weapon gone/switched or the parked loader died: finish rather than strand the reload
    -- (same policy as the insert glide's bail-outs).
    if a == nil or objAddr(weaponMesh) ~= a.weaponAddr or (a.proxy ~= nil and not isAlive(a.proxy)) then
        finishAwaitClose(pawn, weaponMesh, false)
        return
    end
    -- Toggled off mid-wait (dev panel): just complete
    if not flickToCloseActive(a.profile) then
        finishAwaitClose(pawn, weaponMesh, false)
        return
    end
    a.elapsed = a.elapsed + (delta or 0)
    local s = sampleRightHandFlickPoints()
    if s == nil or delta == nil or delta <= 0 then
        a.last = s
        return
    end
    local last = a.last
    a.last = s
    if last == nil or a.elapsed < FLICK_ARM_TIME then return end

    local function sideSpeed(now, before)
        return ((now.x - before.x) * s.right.x + (now.y - before.y) * s.right.y) / delta
    end
    local speed = math.max(sideSpeed(s.tip, last.tip), sideSpeed(s.top, last.top))
    if speed >= (Config.ptmFlickCloseSpeed or DEFAULT_FLICK_CLOSE_SPEED) then
        a.hits = a.hits + 1
        if a.hits >= FLICK_HIT_TICKS then
            print(string.format("[Reload][%s] Flick close (%.0f cm/s).", tostring(a.profile and a.profile.id), speed))
            finishAwaitClose(pawn, weaponMesh, true)
        end
    else
        a.hits = 0
    end
end

-- Seat frame (or any bail-out): proxy out, real mags in, normal INSERT completion.
-- flickToClose profiles keep the proxy parked on the seat and wait for the flick instead.
local function finishInsertGlide(pawn, weaponMesh)
    local g = insertGlide
    insertGlide = nil
    local p = (g and g.profile) or activeProfile
    local awaitFlick = (g == nil or g.kind ~= "shell") and flickToCloseActive(p)
        and objAddr(weaponMesh) == (g and g.weaponAddr or objAddr(weaponMesh))
    pcall(function() uevrUtils.triggerHapticVibration(Handed.Left, 0, 0.04, 1000, 0.8) end)
    if awaitFlick then
        local proxy = (g ~= nil and isAlive(g.proxy)) and g.proxy or nil
        if g ~= nil and g.proxy ~= nil and proxy == nil then destroyProxy(g.proxy, pawn) end
        enterAwaitClose(proxy, p, weaponMesh)
        return
    end
    if g ~= nil and g.proxy ~= nil then destroyProxy(g.proxy, pawn) end
    if g ~= nil and g.kind == "shell" then
        completeShellInsert(pawn, weaponMesh, p)
        currentState = STATE_IDLE
    else
        completeOrRack(pawn, weaponMesh, p)
    end
end

-- Per tick while STATE_INSERTING. Align: ease-out to the pre-seat pose (backed out along
-- the insertion axis) while rotating to the final orientation. Seat: straight ease-in
-- slide along the axis into the real mag's transform.
local function stepInsertGlide(delta, pawn, weaponMesh)
    local g = insertGlide
    if g == nil or g.failed or not isAlive(g.proxy) or objAddr(weaponMesh) ~= g.weaponAddr then
        diag("insert glide ended early: glide=%s failed=%s proxyAlive=%s weaponChanged=%s",
            tostring(g ~= nil), tostring(g and g.failed), tostring(g ~= nil and isAlive(g.proxy)),
            tostring(g ~= nil and objAddr(weaponMesh) ~= g.weaponAddr))
        finishInsertGlide(pawn, weaponMesh)
        return
    end
    if g.pending then
        g.pendingTicks = g.pendingTicks + 1
        if g.pendingTicks >= INSERT_PENDING_FALLBACK_TICKS then
            diag("insert glide still pending after %d ticks - starting it from the tick", g.pendingTicks)
            -- No stereo callback picked it up (no HMD / view callbacks not firing)
            beginInsertGlide()
        end
        return
    end

    g.elapsed = g.elapsed + (delta or 0)
    local t = math.min(g.elapsed / g.duration, 1)
    if t >= 1 then
        -- Seat preview (bare-socket seats only, dev panel): park the proxy on the seat for
        -- Config.ptmSeatPreviewHold seconds, re-reading the per-weapon seat offset every tick
        -- so the sliders can be tuned live, before the reload completes.
        local hold = Config.ptmSeatPreviewHold or 0
        if g.useSeatOffset and hold > 0 and g.elapsed < g.duration + hold then
            local loc, q = getSeatOffset()
            if not pcall(writeProxyRelative, g.proxy, loc, q) then
                finishInsertGlide(pawn, weaponMesh)
            end
            return
        end
        finishInsertGlide(pawn, weaponMesh)
        return
    end

    local loc, q
    if t < INSERT_ALIGN_FRACTION then
        local u = t / INSERT_ALIGN_FRACTION
        local e = 1 - (1 - u) ^ 3
        loc = lerp3(g.fromLoc, g.preLoc, e)
        q   = quat.slerp(g.fromQuat, g.toQuat, e)
    else
        local u = (t - INSERT_ALIGN_FRACTION) / (1 - INSERT_ALIGN_FRACTION)
        loc = lerp3(g.preLoc, g.toLoc, u * u)
        q   = g.toQuat
    end
    if not pcall(writeProxyRelative, g.proxy, loc, q) then
        finishInsertGlide(pawn, weaponMesh)
    end
end

-- Left hand's input-driven finger lerps locked while Entry's reload / mag-grip pose owns the hand: the
-- hands input handler reads the raw pad before on_xinput_get_state suppresses the grip, so the press that
-- grabs the slide (AWAIT_RACK) or the pouch mag (DROPPED -> HIP_HOLD) started the free-hand grip curl,
-- which fought the per-frame pose (visible flick); the release at the magwell (INSERTING) did the same.
local leftInputLocked = false
local function syncReloadInputLock()
    local want = currentState == STATE_AWAIT_RACK or currentState == STATE_DROPPED
        or currentState == STATE_HIP_HOLD or currentState == STATE_INSERTING
    if want == leftInputLocked then return end
    leftInputLocked = want
    pcall(function() require("libs/hands").setInputLocked(Handed.Left, want) end)
end

function M.on_pre_engine_tick(engine, delta, isReloading)
    syncReloadInputLock()   -- before every early-out: a disabled / idle tick still releases the lock
    if currentState ~= diagLastState then
        diag("state %s -> %s (weapon %s)", stateName(diagLastState), stateName(currentState),
            tostring(activeProfile and activeProfile.id))
        diagLastState = currentState
    end
    if not enabled then return end

    -- FIX 3: Idle early-exit.
    -- Skip ALL C++ bridge calls when we are in STATE_IDLE with no deferred work pending.
    -- Covers both the uninitialised (activeProfile=nil, no weapon) and the normal
    -- in-game steady state (weapon equipped, not in a reload cycle).
    -- The ONLY reason to stay alive in STATE_IDLE is:
    --   • montagePrewarmDeadline > 0  (still trying to resolve the charMontage asset)
    --   • charAnimFastForwardArmed    (one tick after INSERT: set rate to 100×)
    --   • charAnimResetArmed          (0.15s after INSERT: restore rate to 1.0)
    --   • weaponAnimResetArmed        (0.15s after INSERT: restore weapon rate to 1.0)
    if currentState == STATE_IDLE
       and montagePrewarmDeadline == 0
       and not charAnimFastForwardArmed
       and not charAnimResetArmed
       and not weaponAnimResetArmed
       and not animJumpActive
       and ejectHideUntil == 0 then
        return
    end

    -- the game-ejected mag hide window timed out (it is serviced from the post-stereo callback)
    if ejectHideUntil > 0 and os.clock() >= ejectHideUntil then
        endEjectHideWindow()
    end

    if animJumpActive then
        local pawn = uevr.api:get_local_pawn(0)
        local wm = getPistolWeaponMesh(pawn)
        if pawn and pawn.Mesh then
            -- Accumulate real elapsed time (delta, in seconds) rather than counting
            -- calls - see the animJumpActive/animJumpTargetSeconds declaration comment
            -- for why: this is what makes the freeze point framerate-independent.
            if animJumpElapsed < animJumpTargetSeconds then
                animJumpElapsed = animJumpElapsed + delta
            else
                pawn.Mesh.bPauseAnims = true
                if wm ~= nil then wm.bPauseAnims = true end
                animJumpActive  = false
                animJumpElapsed = 0.0
                print("[Reload] Jump sequence complete. Anims paused.")
            end
        else
            animJumpActive  = false
            animJumpElapsed = 0.0
        end
    end

    -- FIX 2: Lightweight deferred charMontage retry.
    -- ONLY retries find_uobject (fast hash lookup) for weapons that have a known static
    -- charMontage path. The expensive get_objects_by_class GUObjectArray scan is NOT
    -- repeated here - it already ran once at init. The auto-intercept path in
    -- tryInterceptReload() will passively cache the montage from the next native reload.
    if montagePrewarmDeadline > 0 then
        if activeProfile and not activeProfile.cachedCharMontage then
            local now = os.clock()
            if now < montagePrewarmDeadline then
                -- Throttled find_uobject retry every 0.5s (no GUObjectArray scan).
                if activeProfile.charMontage and (now - lastDiscoveryAttempt) >= 0.5 then
                    lastDiscoveryAttempt = now
                    activeProfile.cachedCharMontage = findUObjectCached(activeProfile.charMontage)
                    if activeProfile.cachedCharMontage then
                        print("[Reload] charMontage resolved via static path for " .. (activeProfile.id or "?") .. " (deferred).")
                        montagePrewarmDeadline = 0
                    end
                end
            else
                -- Window expired.
                if not activeProfile.cachedCharMontage then
                    print("[Reload] WARNING: charMontage not in memory for " .. (activeProfile.id or "?") .. " after 10s. Tactical reloads rely on auto-intercept cache.")
                end
                montagePrewarmDeadline = 0
            end
        else
            -- Already cached or no active profile.
            montagePrewarmDeadline = 0
        end
    end

    if weaponAnimJumpPending then
        if isAlive(weaponAnimJumpPending) then
            local weaponAnimInst = weaponAnimJumpPending.AnimScriptInstance
            if isAlive(weaponAnimInst) then
                local wMontage = nil
                pcall(function() wMontage = plugin.executeFunction(weaponAnimInst, "GetCurrentActiveMontage") end)
                if wMontage then
                    plugin.executeFunction(weaponAnimInst, "Montage_SetPosition", wMontage, weaponAnimJumpTime)
                    print("[Reload] Weapon montage deferred jump to " .. weaponAnimJumpTime .. "s applied.")
                end
            end
            weaponAnimJumpPending.bPauseAnims = true
            print("[Reload] Weapon anims PAUSED (deferred jump).")
        end
        weaponAnimJumpPending = nil
    end

    -- Deferred char anim fast-forward.
    -- Allows the montage to initialize natively for one tick before fast-forwarding,
    -- which prevents the AnimNotify from being dropped on the very first play.
    -- The deferred actions below re-resolve their targets from the live pawn each
    -- time (char mesh = pawn.Mesh, weapon mesh = current WeaponData.WeaponMesh; the
    -- game recycles one WeaponInHandsMesh across weapons, so "current" is the same
    -- component the rate was set on even if a switch landed inside the window).
    if charAnimFastForwardArmed then
        charAnimFastForwardArmed = false
        local ffPawn = uevr.api:get_local_pawn(0)
        local cm = ffPawn and ffPawn.Mesh or nil
        if cm then
            cm.GlobalAnimRateScale = finishRate
            charAnimResetArmed = true
            charAnimResetTime  = os.clock() + finishWindow
            print(string.format("[Reload] Char mesh rate set to %.0f (deferred fast-forward, %.3fs).", finishRate, finishWindow))
        end
    end

    -- Deferred char anim rate reset.
    -- We wait 0.15s before restoring to 1.0 to ensure UE5's multithreaded Anim Thread
    -- actually sees and evaluates the 1000x speed change (next-tick reset is often missed).
    if charAnimResetArmed and os.clock() > charAnimResetTime then
        charAnimResetArmed = false
        local rsPawn = uevr.api:get_local_pawn(0)
        local cm = rsPawn and rsPawn.Mesh or nil
        if cm then
            cm.GlobalAnimRateScale = 1.0
            print("[Reload] Char mesh rate restored to 1.0.")
        end
    end
    if weaponAnimResetArmed and os.clock() > weaponAnimResetTime then
        weaponAnimResetArmed = false
        local wmNow = resolveWeaponMesh(nil)
        if wmNow then
            wmNow.GlobalAnimRateScale = 1.0
            print("[Reload] Weapon mesh rate restored to 1.0.")
        end
    end

    -- Pawn + weapon guard
    local pawn = uevr.api:get_local_pawn(0)
    if not pawn then return end

    local weaponMesh = getPistolWeaponMesh(pawn)

    if not weaponMesh then
        if currentState ~= STATE_IDLE then
            doAbort(pawn, nil)
        end
        return
    end

    local p = activeProfile

    -- Force weapon anims paused every tick while any reload state is active.
    if currentState ~= STATE_IDLE and not animJumpActive then
        weaponMesh.bPauseAnims = true
    end

    -- Ensure mag meshes stay hidden during active reload.
    -- Transition-based: only calls SetVisibility/SetHiddenInGame when the state
    -- actually changes, not every tick. Previously this was 3 C++ roundtrips per
    -- mag mesh per frame for the entire EJECT_HOLD → HIP_HOLD duration.
    if currentState ~= STATE_IDLE and not magMeshesCurrentlyHidden and #magMeshes > 0 then
        setMagMeshesHidden(magMeshes, true, weaponMesh)
        magMeshesCurrentlyHidden = true
    end

    -- Grip release detection for HIP_HOLD (reads currentButtons from on_xinput_get_state).
    local gripDown     = (currentButtons & GRIP_BUTTON) ~= 0
    local gripReleased = not gripDown and wasGripHeld
    if gripDown ~= wasGripHeld then
        diag("left grip %s in %s", gripDown and "DOWN" or "UP", stateName(currentState))
    end
    wasGripHeld        = gripDown

    -- STATE_INSERTING: fresh mag gliding into the magwell; input is ignored until it seats.
    -- Weapon anims stay paused and the real mags stay hidden (both enforced above for any
    -- non-IDLE state) until finishInsertGlide swaps the proxy for them.
    if currentState == STATE_INSERTING then
        stepInsertGlide(delta, pawn, weaponMesh)
        return
    end

    -- STATE_AWAIT_CLOSE: loader seated, waiting for the right-hand flick (flickToClose profiles)
    if currentState == STATE_AWAIT_CLOSE then
        stepAwaitClose(delta, pawn, weaponMesh)
        return
    end

    -- STATE_AWAIT_RACK: mag seated after an empty reload, waiting for the slide / handle rack
    if currentState == STATE_AWAIT_RACK then
        stepAwaitRack(pawn, weaponMesh, gripReleased)
        return
    end

    -- STATE_EJECT_HOLD: subsequent ticks - wait for grip release, then drop proxy.
    if currentState == STATE_EJECT_HOLD then
        if gripReleased then
            print("[DBG][EJECT_HOLD] gripReleased - dropping empty proxy -> STATE_DROPPING_EMPTY")
            if isAlive(ejectProxy) then
                pcall(function() ejectProxy:K2_DetachFromComponent(1, 1, 1, true) end)
                droppingProxy = ejectProxy
                dropVelocity = 0
                dropProxyReady = true
            end
            ejectProxy    = nil
            currentState  = STATE_DROPPING_EMPTY
            print("[Reload] Grip released - empty mag dropping to floor. STATE_DROPPING_EMPTY.")
        end
        return
    end

    -- STATE_DROPPING_EMPTY: kinematic mag fall.
    -- Proxy falls under gravity each tick. Terminates when proxy Z drops 120 cm
    -- below pawn feet, then transitions to STATE_DROPPED.
    -- IMPORTANT: proxy is never K2_DetachFromComponent'd so K2_SetWorldLocation works.
    if currentState == STATE_DROPPING_EMPTY then
        if not isAlive(droppingProxy) then
            droppingProxy   = nil
            dropProxyReady  = false
            currentState    = STATE_DROPPED
            print("[Reload] STATE_DROPPING_EMPTY: proxy gone, advancing to STATE_DROPPED.")
            return
        end
        dropVelocity = dropVelocity + (DROP_GRAVITY_CM * delta)
        local done = false
        pcall(function()
            local loc     = droppingProxy:K2_GetComponentLocation()
            if not loc then return end
            loc.Z = loc.Z - (dropVelocity * delta)
            droppingProxy:K2_SetWorldLocation(loc, false, reusable_hit_result, true)
            local pawnLoc = pawn:K2_GetActorLocation()
            if pawnLoc and loc.Z < (pawnLoc.Z - 60) then
                done = true
            end
        end)
        if done then
            droppingProxy  = destroyProxy(droppingProxy, pawn)
            droppingProxy  = nil
            dropProxyReady = false
            currentState   = STATE_DROPPED
            print("[Reload] Ejected mag hit floor - STATE_DROPPED.")
        end
        return
    end

    -- STATE_DROPPED: idle wait; hip-zone grab transition in on_xinput_get_state.
    if currentState == STATE_DROPPED then
        return
    end

    -- STATE_SHELL_HOLD (isTubeFed only): first tick - spawn a single shell proxy in hand.
    if currentState == STATE_SHELL_HOLD and shellProxy == nil then
        -- Borrow a live sm_bullet child's StaticMesh for the proxy. Deliberately
        -- NOT stored in the module-level magMeshes: that list is the "hide these
        -- while reloading" set, and unlike a detachable magazine the tube's
        -- shells should stay visible throughout.
        if not p.cachedMeshAsset then
            local mags = collectMagMeshes(weaponMesh, p)
            local firstLive = (#mags > 0) and findLiveChildByAddr(weaponMesh, mags[1].addr) or nil
            if firstLive then
                pcall(function() p.cachedMeshAsset = firstLive.StaticMesh end)
            end
        end
        shellProxy = spawnMagProxy(pawn, p, true, weaponMesh)
        if not isAlive(shellProxy) then
            print("[Reload][" .. (p and p.id or "?") .. "] ERROR: Failed to spawn shell proxy. Aborting.")
            doAbort(pawn, weaponMesh)
            return
        end
        attachProxyToHand(shellProxy)

        -- shellsPerGrab (TOZ-34 = 2): extra shell proxies side-by-side, attached to
        -- shellProxy (not leftHandComp directly) so they move as one unit. Tracked
        -- in aggregateChildren[shellProxy] - destroyProxy() already cleans these up
        -- generically (same mechanism the Rhino moon-clip proxy uses), so INSERT/discard
        -- need no changes.
        if p.shellsPerGrab and p.shellsPerGrab > 1 and p.cachedMeshAsset then
            aggregateChildren[shellProxy] = addExtraShells(pawn, shellProxy, p)
        end
        startGrabGlide(shellProxy)

        print("[Reload][" .. (p and p.id or "?") .. "] Shell grabbed from hip and attached to left hand.")
        return
    end

    -- STATE_SHELL_HOLD: grip release -> insert (near tube socket) or discard (far).
    if currentState == STATE_SHELL_HOLD then
        if not isAlive(shellProxy) then
            doAbort(pawn, weaponMesh)
            return
        end
        stepGrabGlide(delta)
        if not isAlive(leftHandComp) then return end

        if gripReleased then
            -- Reuse the same BoxCompLH-vs-MagBox physics overlap the EJECT trigger
            -- uses (mag_reload.lua, refreshed once per tick), rather than a separate
            -- flat-radius distance check - it already tracks the correct box shape/
            -- offset for this weapon's socket (jnt_bullet), not just a raw point.
            local overlapping = magReload.isHandOverlappingMag()
            print("[DBG][SHELL_HOLD] gripReleased - overlappingMagBox=" .. tostring(overlapping))

            if overlapping then
                -- INSERT: destroy the shell proxy, then simply UNPAUSE and
                -- fast-forward the native reload that tryInterceptReload parked
                -- when the shell was grabbed - identical in shape to the
                -- box-magazine INSERT below.
                --
                -- The parked pair is the whole point. Both the char montage and
                -- its weapon-mesh counterpart are already playing (frozen), so
                -- resuming them fires AnimNotify_WeaponAction in the coordinated
                -- state the native handler expects, and the game adds the ammo.
                --
                -- Do NOT try to hand-play a montage here instead. Both attempts
                -- fail:
                --  1. Montage_JumpToSection("In") - animation plays, ammo never
                --     increases. UE fires a notify only when the playhead
                --     *advances across* its time (half-open (prev, current]);
                --     a section jump teleports past it without crossing it.
                --  2. Montage_Play of the single-bullet montage on the char mesh
                --     alone - the notify fires and HARD-CRASHES the game (null
                --     deref), because the char-side notify reaches into
                --     weapon-side reload state that only exists while the weapon
                --     montage is running too.
                -- Calling the notify directly is out as well: Received_Notify is
                -- the Blueprint stub (returns false) and the real work is in a
                -- native C++ Notify() not exposed as a UFunction.
                -- INSERT: glide the shell into the loading port, or snap as before
                if not startShellInsertGlide(pawn, weaponMesh, p) then
                    shellProxy = destroyProxy(shellProxy, pawn)
                    completeShellInsert(pawn, weaponMesh, p)
                end
            else
                -- Released far from the tube socket - shell wasn't inserted, just discard it.
                shellProxy = destroyProxy(shellProxy, pawn)
                print("[Reload][" .. p.id .. "] Grip released far from tube socket - shell discarded.")
            end

            -- The glide path leaves STATE_INSERTING in charge until the shell seats
            if currentState ~= STATE_INSERTING then currentState = STATE_IDLE end
        end
        return
    end

    -- STATE_HIP_HOLD: first tick - spawn full proxy in hand.
    if currentState == STATE_HIP_HOLD and heldProxy == nil then
        print("[DBG][HIP_HOLD] First tick - spawning fresh mag proxy for " .. (p and p.id or "?"))
        print("[DBG][HIP_HOLD] cachedMeshAsset=" .. tostring(p.cachedMeshAsset ~= nil) .. " #magMeshes=" .. #magMeshes)

        -- Final montage pre-scan before INSERT.
        -- By HIP_HOLD, the player has completed a full EJECT→DROP cycle (~3-6s).
        -- The weapon's anim package is almost certainly in GUObjectArray by now.
        if not p.cachedCharMontage then
            if p.charMontage then
                p.cachedCharMontage = findUObjectCached(p.charMontage)
                if p.cachedCharMontage then
                    print("[Reload][HipHold] charMontage found via find_uobject at hip-hold time!")
                    montagePrewarmDeadline = 0
                end
            end
            if not p.cachedCharMontage and p.id then
                discoveryCache[p.id] = nil  -- force fresh scan
                p.cachedCharMontage = discoverReloadMontage(p.id)
                if p.cachedCharMontage then
                    print("[Reload][HipHold] charMontage found via discovery at hip-hold time!")
                    montagePrewarmDeadline = 0
                else
                    print("[Reload][HipHold] WARNING: charMontage still nil at hip-hold. INSERT may fall back to AnimBP property read.")
                end
            end
        end

        heldProxy = spawnMagProxy(pawn, p, true, weaponMesh)
        if not isAlive(heldProxy) then
            print("[Reload] ERROR: Failed to spawn hip proxy. Aborting.")
            doAbort(pawn, weaponMesh)
            return
        end
        attachProxyToHand(heldProxy)
        startGrabGlide(heldProxy)
        print("[Reload][" .. p.id .. "] Fresh mag spawned from hip and attached to left hand.")
        return
    end

    -- STATE_HIP_HOLD: grip release -> insert (near socket) or drop (far).
    if currentState == STATE_HIP_HOLD then
        if not isAlive(heldProxy) then
            doAbort(pawn, weaponMesh)
            return
        end
        stepGrabGlide(delta)
        if not isAlive(leftHandComp) then return end

        if gripReleased then
            -- Measured from the mag the player is holding to where it will seat (the hidden real mag the
            -- insert glide lands on), not from the controller origin to the MagBox: the controller sits
            -- 5-10 cm above the held mag, so a mag visibly in the magwell could measure past the threshold
            -- and drop (2026-10-27 [ReloadDiag]: 12.3 cm -> DROP). Weapons without a real mag child (Rhino
            -- speedloader seats on the bare socket) keep the MagBox as the seat point.
            local lHandLoc = nil
            pcall(function() lHandLoc = leftHandComp:K2_GetComponentLocation() end)
            local heldLoc = nil
            pcall(function() heldLoc = heldProxy:K2_GetComponentLocation() end)

            local socketLoc = magReload.getMagBoxLocation()
            local seatLoc = nil
            if not p.seatOnSocket then
                local target = findInsertTarget(weaponMesh, p)
                if target ~= nil then pcall(function() seatLoc = target:K2_GetComponentLocation() end) end
            end
            seatLoc = seatLoc or socketLoc
            local fromLoc = heldLoc or lHandLoc

            local dist = math.huge
            if fromLoc and seatLoc then
                local dx = fromLoc.X - seatLoc.X
                local dy = fromLoc.Y - seatLoc.Y
                local dz = fromLoc.Z - seatLoc.Z
                dist = math.sqrt(dx*dx + dy*dy + dz*dz)
            end
            local handDist = math.huge
            if lHandLoc and socketLoc then
                local dx = lHandLoc.X - socketLoc.X
                local dy = lHandLoc.Y - socketLoc.Y
                local dz = lHandLoc.Z - socketLoc.Z
                handDist = math.sqrt(dx*dx + dy*dy + dz*dz)
            end
            print("[DBG][HIP_HOLD] gripReleased - lHandLoc=" .. tostring(lHandLoc ~= nil) .. " socketLoc=" .. tostring(socketLoc ~= nil) .. " dist=" .. string.format("%.2f", dist) .. "cm (threshold=" .. INSERT_DISTANCE_CM .. "cm)")
            -- dev panel: Debug Dev Config > Mag Reload Box Sizes & Offsets > Insert Distance
            local insertDistance = Config.ptmInsertDistance or INSERT_DISTANCE_CM
            diag("HIP_HOLD release: mag->seat=%.1f cm (insert < %.1f, from %s to %s) old hand->magBox=%.1f cm magBoxSocket=%s -> %s",
                dist, insertDistance, heldLoc and "held mag" or "hand",
                seatLoc ~= socketLoc and "real mag" or "magBox", handDist,
                tostring(magReload.getMagBoxSocketName()), dist < insertDistance and "INSERT" or "DROP")

            if dist < insertDistance then
                -- INSERT: glide the fresh mag into the magwell (box mags), or snap as before
                if not startInsertGlide(pawn, weaponMesh, p) then
                    heldProxy = destroyProxy(heldProxy, pawn)
                    if flickToCloseActive(p) then
                        enterAwaitClose(nil, p, weaponMesh) -- no glide: still wait for the flick
                    else
                        completeOrRack(pawn, weaponMesh, p)
                    end
                end
            else
                -- DROP (released far from socket)
                heldProxy    = destroyProxy(heldProxy, pawn)
                currentState = STATE_DROPPED
                print("[Reload] Grip released far from socket - fresh mag dropped. Return to hip zone.")
            end
        end
        return
    end
end

-- Called from the ImGui panel to live-push offset changes to the held proxy.
function M.setProxyOffset(loc, rot)
    if Config then
        Config.ptmMagProxyLocation = loc
        Config.ptmMagProxyRotation = rot
    end
    local proxy = (isAlive(heldProxy) and heldProxy)
                  or (isAlive(ejectProxy) and ejectProxy)
                  or nil
    if proxy then
        pcall(function()
            proxy.RelativeLocation.X = loc[1]
            proxy.RelativeLocation.Y = loc[2]
            proxy.RelativeLocation.Z = loc[3]
            proxy.RelativeRotation.Pitch = rot[1]
            proxy.RelativeRotation.Yaw   = rot[2]
            proxy.RelativeRotation.Roll  = rot[3]
        end)
    end
end

return M
