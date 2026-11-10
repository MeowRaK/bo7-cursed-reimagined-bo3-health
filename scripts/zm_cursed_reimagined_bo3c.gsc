// BO7 Zombies (Kronos) - Cursed Reimagined, BO3 health edition.
// Load together with bo3_health.gsc (that file is not modified).
// Active only in Cursed (zm_rb_r_mod), Cursed Survival (zm_rb_r_mod_survival)
// and Mister Peeks Mayhem (zm_rb_rh_mod); every other mode is left stock.
// Source build: not compiled or runtime tested; verify in an offline game.
//
// bo3_health.gsc owns these systems, so this file steps aside:
//  - Player health, Jugger-Nog and zombie melee damage. bo3_health.gsc sets
//    level.var_9209eecc9aff21ad (stock flag: no round damage scaling) and
//    zombie_melee_damage_override 50. The attack-damage tier hook stays
//    installed but does nothing while that flag is set; it only applies if
//    this file is loaded without bo3_health.gsc.
//  - Armor: disabled. bo3_health.gsc forces level.allowarmor 0 and the
//    no-armor modifier on every 0.05 s, so this file never writes
//    zmmodenoarmor (no tug-of-war). It gives 0 starting armor (saved loads
//    included), clears armor after spawn, hides the armor HUD and blocks
//    armor wall-buys (golden armor included).
//  - Zombie speed: bo3_health.gsc caps every zombie at "run" in all rounds,
//    boss fights included, and turns Rampage Inducer off. This file has no
//    speed code of its own.
//
// What this file changes (each feature has its own section below):
//  - Pack-a-Punch: max level IV; the PaP level sets the weapon's rarity
//    (I blue, II purple, III legendary, IV ultra).
//  - Starting loadout: the 1911 and the knife use each player's saved
//    Zombie Build; no GobbleGums are pre-loaded.
//  - Classic damage: White 1911 uses BO1 hit-location damage; White knife
//    uses BO1-BO3 hits-to-kill; Mocha Maul classic knife for every player.
//  - Arsenal: random Ammo Mod for 250 Salvage (no rarity upgrades).
//  - Wall-buys: locked to Green, shown with classic white chalk.
//  - Mystery Box: regular weapons are Green; the map Wonder Weapon is in the
//    box from round 1 (level.cursed_box_ww_copies copies); in Mister Peeks
//    Mayhem the Ray Gun / Mk 2 chance is reduced (level.cursed_peeks_raygun_keep).
//  - Aether Tools removed everywhere (T.E.D.D. chests give the tier's Aether
//    Crystal instead). Field Upgrades always cost 40 kills.
//  - Wonder Weapons: map Wonder Weapons one-hit normal and armored zombies
//    at PaP III+ and deal x1.7 to other non-boss enemies at PaP IV; LGM-1
//    PaP IV saucer strike; Ray Gun / Mk 2 x2 (PaP I-III) and x2.5 (PaP IV).
//  - Legacy (Ultra) box weapons get Pack Mule ammo; box weapons dropped by
//    a melee keep the Zombie Build; Death Perception has no orange indicator.
//
// Tunables are the level.cursed_* values set in init() and in each section.

// script_aa3bac81ad4fc8e = stock GobbleGum core (#namespace bgb), referenced
// by this exact hashed name in stock scripts\mp\zm\points.gsc.
#using script_aa3bac81ad4fc8e;
#using scripts\common\ai\aitypes\shared\zombie\zombie_damage;
#using scripts\common\ai\aitypes\shared\zombie\zombie_utils;
#using scripts\common\callbacks;
#using scripts\common\shared_func_utility;
#using scripts\common\system;
#using scripts\common\utility;
#using scripts\common\weapon;
#using scripts\mp\ammomods\ammo_mod;
#using scripts\mp\augments\m_mod_augments;
#using scripts\mp\augments\zombie_augments;
#using scripts\mp\common\utility\perk;
#using scripts\mp\armor;
#using scripts\mp\currency;
#using scripts\mp\interaction;
#using scripts\mp\loot\common_cache;
#using scripts\mp\loot\common_item;
#using scripts\mp\loot\common_item_database;
#using scripts\mp\loot\common_item_weapon;
#using scripts\mp\magicbox;
#using scripts\mp\pack_a_punch;
#using scripts\mp\purchasemenu;
#using scripts\mp\common\utility\game_utility;
#using scripts\mp\common\utility\lui_game_event_aggregator;
#using scripts\mp\wallbuy;
#using scripts\mp\weaponmetadata;
#using scripts\mp\zm\systems\zm_armor;
#using scripts\mp\zm\zm_utility;

#namespace bo7_cursed_fresh;

function private autoexec __init__system__()
{
    system::register( #"bo7_cursed_fresh_rules", undefined, &init, undefined );
}

function private supported_mode()
{
    mode = game_utility::getgametype();
    return mode == "zm_rb_r_mod" || mode == "zm_rb_r_mod_survival" || mode == "zm_rb_rh_mod";
}

function init()
{
    // Arsenal prompt text read by zm_cursed_arsenal_prompt_post.lua ("" = hidden).
    // Reset first so no mode inherits a value from a previous match.
    setdvar( "cursed_arsenal_prompt", "" );
    if ( !supported_mode() )
    {
        return;
    }

    level callback::add( #"player_spawned", &on_player_spawned );
    level callback::add( "on_variant_wallbuy_spawn", &on_armor_wall_spawned );

    // PaP IV in some configurations has a menu item with mismatched tier=3.
    // The fallback applies only when the menu identifies the level4 item.
    lui_game_event_aggregator::registeronluieventcallback( &pap_four_fallback, "pap_weaponupgrade_purchase" );

    // Clear the 3 GobbleGums stock pre-loads at connect (see GOBBLEGUMS section).
    level callback::add( #"player_connect", &on_player_connect_gobblegums );
    level callback::add( #"player_spawned", &on_player_connect_gobblegums );
    if ( isdefined( level.players ) )
    {
        foreach ( player in level.players )
        {
            player thread clear_starting_gobblegums(); // already connected before init
        }
    }

    level thread maintain_pap_and_starting_armor();
    level thread bind_armor_walls();
    // Extra % chance per box use to force the map's own Wonder Weapon.
    // 0 = off: the map Wonder Weapon is already in the box's Wonder Weapon
    // list with the same chance as the Ray Gun.
    level.cursed_box_ww_chance = 0;
    // Max copies of the map's Wonder Weapon (on the ground + held).
    level.cursed_box_ww_copies = 4;
    level thread unlock_map_wonder_weapons();

    // Zombie attack damage tier hook (see ZOMBIE ATTACK DAMAGE section).
    level thread install_early_round_damage_tier();

    // Map Wonder Weapons one-hit normal zombies at PaP III+ (see section).
    install_ww_instakill();

    // Ray Gun / Mark II: x2 damage at PaP I-III, x2.5 at PaP IV (see section).
    install_raygun_pap_double();
    // LGM-1 PaP IV saucer strike (see section).
    install_lgm_strike();

    // Death Perception "Sixth Sense" - no orange edge glow (see section).
    callback::add( "zm_perk_obtained", &sixth_sense_no_glow );

    // Starting 1911 uses the player's own Zombie Build (see section below).
    level thread install_starting_1911_build_hook();

    // Classic BO1 white-1911 damage by hit location (see section at the end).
    level zombie_utils::register_zombie_weapon_damage_callback( "sat_pi_alcor_mp", &classic_1911_leg_damage );

    // Classic BO1-BO3 starting knife hits-to-kill (see section after the classic 1911).
    level zombie_utils::register_zombie_agent_damage_callback( &classic_knife_damage );

    // Weapon progression: PaP rarity, Arsenal, wall-buys, Mystery Box (see section).
    level callback::add( "zm_packed_weapon", &on_packed_weapon_rarity );
    level callback::add( "zm_packed_weapon_non_augment", &on_packed_weapon_rarity );
    level callback::add( #"player_weapon_change", &on_weapon_change_rarity );
    level callback::add( #"player_weapon_change", &classic_knife_on_weapon_change );
    level callback::add( "zm_perk_lost", &classic_knife_on_perk_lost );
    level thread classic_knife_install_augment_check();
    level callback::add( #"on_arsenal_spawned", &on_arsenal_spawned_bind );
    level callback::add( "on_round_end", &on_round_end_lock_wallbuys );
    level thread lock_wallbuys_green_init();
    level thread lock_magicbox_green();
    level thread legacy_pack_mule_init();
    level callback::add( "magicbox_purchase", &legacy_pack_mule_on_box_purchase );
    level callback::add( #"item_spawn_allowed", &veto_aether_tool_spawn );
    // T.E.D.D. task chests: Aether Tool slots -> tier Aether Crystal.
    level callback::add( "teddtask_complete", &tedd_rewards_no_tools );
    level callback::add( #"item_spawn_begin", &keep_build_on_box_drop );

    logstring( "[BO7 Cursed Fresh] Initialized Cursed-only rules" );
}

// -------------------- PACK-A-PUNCH --------------------
function private pap_price( item )
{
    if ( !isdefined( item ) )
    {
        return 0;
    }
    if ( !isdefined( item.itemref ) )
    {
        return item.cost ?? 0;
    }

    switch ( item.itemref )
    {
        case "level1": return 5000;
        case "level2": return 20000;
        case "level3": return 35000;
        case "level4": return 50000;
    }
    return item.cost ?? 0;
}

function private pap_four_fallback( channel, menuitemindex )
{
    if ( !supported_mode() || channel != "pap_weaponupgrade_purchase" || !isdefined( menuitemindex ) )
    {
        return;
    }
    s_menu = pack_a_punch::get_pap_purchase_menu( self.origin );
    if ( !isdefined( s_menu ) )
    {
        return;
    }
    item = purchasemenu::create_item_struct( s_menu.ref, menuitemindex );
    if ( !isdefined( item ) || !isdefined( item.itemref ) || item.itemref != "level4" )
    {
        return;
    }
    if ( item.tier == 4 )
    {
        return; // A corrected menu entry is handled by the game itself.
    }
    gun = self getcurrentweapon();
    if ( !isweapon( gun ) || self pack_a_punch::get_pap_level( gun ) != 3 )
    {
        return;
    }
    if ( !self currency::attempt_purchase( #"essence", 50000, 1, undefined, #"packapunch" ) )
    {
        purchasemenu::function_93f934ea2f1c06f8( 3 );
        return;
    }
    self pack_a_punch::pap_weapon( gun, 3, 50000, undefined, #"essence" );
    purchasemenu::function_93f934ea2f1c06f8( 1 );
}

function private maintain_pap_and_starting_armor()
{
    level endon( #"game_ended" );
    while ( supported_mode() )
    {
        // Stock scripts can reset max PaP from 4 to 3 for lower relic tiers.
        level.get_pap_cost_override = &pap_price;
        level.max_pack_a_punch_level = 4;
        // BO3: no starting armor at all, including saved-round loads.
        level.startingarmoroverridefunc = &bo3_no_starting_armor;
        // Stock Arsenal rarity upgrades refuse (no charge) at max 0;
        // stock relic setup otherwise sets 4 or 5.
        level.arsenal_max_weapon_rarity = 0;
        // Zm_store_chompy offers an Aether Tool only when this table
        // has an entry for the next rarity (can_player_use_type); empty =
        // the store picks another item instead (no wasted purchase).
        level.var_a90df52f7134ce0 = [];
        // Field Upgrades always need 40 kills.
        // field_upgrades::function_547d8d27c323ad0() (the points-needed func
        // ZM puts on every Field Upgrade) returns level.var_750a1cea39c9abc8
        // when it is a number, else bundle pointsNeeded + player.superincreasecost.
        // on_field_upgrade_used() adds level.var_d8c17916fed09937 (gametype
        // bundle: 10 in Cursed) to superincreasecost after every use.
        // TEDD tasks temporarily set level.var_750a1cea39c9abc8 to 4 / 20 and
        // back to undefined, so it is only filled in while it is not a number.
        level.var_d8c17916fed09937 = 0;
        if ( !isnumber( level.var_750a1cea39c9abc8 ) )
        {
            level.var_750a1cea39c9abc8 = 40;
        }

        // BO3: zmmodenoarmor is NOT written here - bo3_health.gsc keeps it ON.
        wait 0.10;
    }
}

// -------------------- NO ARMOR AT SPAWN --------------------
function private on_player_spawned( params )
{
    if ( !supported_mode() || !isplayer( self ) )
    {
        return;
    }
    // BO3: remove any armor the HUD would still show and hide the armor bar
    // (armor is disabled by bo3_health.gsc; saved armor is not restored).
    self thread bo3_remove_armor_on_spawn();

    // The stock starting 1911 is built from this player's own Zombie Build.
    self arm_starting_1911_build();

    // Classic knife (Mocha Maul) - see section at the end.
    self thread classic_knife_on_spawn();

    // Pack Mule ammo on legacy (Ultra) box weapons - see section at the end.
    self thread legacy_pack_mule_watch();
}

function private force_armor_zero()
{
    self.platecarrierlevel = 0;
    self.maxarmorhealth = 0;
    self.hasgoldenarmorplate = 0;
    self setclientomnvar( "ui_armor_current_level", 0 );
    self armor::setarmorhealth( 0, 1, 1 );
    self armor::external_setarmorplates( 0 );
}

// -------------------- ARMOR WALL-BUY (BLOCKED, SEE BO3-COMPATIBLE SECTION) --------------------
function private is_armor_wall( wall )
{
    if ( !isdefined( wall ) )
    {
        return false;
    }
    if ( isdefined( wall.variant_type ) && ( wall.variant_type == "armor" || wall.variant_type == #"armor" ) )
    {
        return true;
    }
    return isdefined( wall.scriptablenamehash ) && wall.scriptablenamehash == #"wallbuy_zm_t10_armor_legendary";
}

function private on_armor_wall_spawned( params )
{
    if ( supported_mode() && is_armor_wall( self ) )
    {
        self bind_one_armor_wall();
    }
}

function private bind_armor_walls()
{
    level endon( #"game_ended" );
    while ( supported_mode() )
    {
        // Bind the game's existing armor-variant registration; do not create
        // replacement wallbuy entities or change scriptable part states.
        Wallbuy::register_wallbuy_variant_spawn( "armor", &bo3_armor_wall_use, &bo3_armor_wall_hint );
        if ( isdefined( level.interacts ) )
        {
            foreach ( wall in level.interacts )
            {
                if ( is_armor_wall( wall ) )
                {
                    wall bind_one_armor_wall();
                }
            }
        }
        wait 0.25;
    }
}

function private bind_one_armor_wall()
{
    self interaction::set_interact_use_callback( &bo3_armor_wall_use );
    self interaction::set_interact_hint_callback( &bo3_armor_wall_hint );
}

// -------------------- MAP WONDER WEAPONS: AVAILABLE AT MATCH START --------------------
function private unlock_map_wonder_weapons()
{
    level endon( #"game_ended" );
    utility::flag_wait( "setup_magicbox_weapons" );
    utility::flag_wait( "magicbox_ready" );

    // Five map quests in this dump explicitly call function_2e49...(1)
    // to remove their map Wonder Weapon from the box until the quest ends.
    // The box bundle does not always select the map's own Wonder Weapon list;
    // ensure_map_wonder_list() puts it in place before the loop starts.
    ensure_map_wonder_list();
    level thread unlock_map_wonder_loop();

    // Optional forced map Wonder Weapon roll (see box_force_map_wonder).
    level callback::add( "magicbox_used", &box_force_map_wonder );
    level callback::add( "magicbox_used", &box_half_rayguns_peeks ); // Mister Peeks Mayhem Ray Gun reduction
}

// Forces the map's own Wonder Weapon into a box roll (level.cursed_box_ww_chance).
// Stock hook (magicbox.gsc on_use_magicbox): player callback "magicbox_used"
// with params.s_magicbox runs right before the roll. setup_magicbox_weapon_array()
// takes s_magicbox.var_aef038a20b4915b3 as a forced item ("itemspawnentry:" +
// name), marks it rolled_wonder / ultra, and still re-rolls from the normal
// list when the item limit is reached or the player already has it.
// Kowakujo's Maneki-neko easter egg uses the same field.
function private box_map_wonder_item()
{
    switch ( level.mapname )
    {
        case "zm_sat_firefly":
            return "zm_sat_item_weapon_ww_firefly";
        case "zm_sat_hornet":
            return "zm_sat_item_weapon_ww_hornet";
        case "zm_sat_locust":
            return "zm_sat_item_weapon_ww_locust";
        case "zm_sat_mantis":
            return "zm_sat_item_weapon_ww_mantis";
        case "zm_sat_ruby":
            return "zm_sat_item_weapon_ww_ruby";
        case "zm_sat_scarab":
            return "zm_sat_item_weapon_ww_scarab";
    }
    return undefined;
}

function private box_force_map_wonder( params )
{
    if ( !supported_mode() || !isdefined( params ) || !isdefined( params.s_magicbox ) )
    {
        return;
    }
    item = box_map_wonder_item();
    if ( !isdefined( item ) || randomfloat( 100 ) >= level.cursed_box_ww_chance )
    {
        return;
    }
    params.s_magicbox.var_aef038a20b4915b3 = item;
    params.s_magicbox thread box_clear_forced_wonder();
}

function private box_clear_forced_wonder()
{
    waitframe();
    if ( isdefined( self ) )
    {
        self.var_aef038a20b4915b3 = undefined;
    }
}

// Box Wonder Weapon list. The Cursed box bundle (magicbox_sat_zm_r_mod) has
// no per-map Wonder Weapon table for most maps, which leaves
// level.var_8b6bf63f61fe01f9 on the generic list (Ray Gun + Mk 2 only), so
// the map's Wonder Weapon would never enter the box.
function private ensure_map_wonder_list()
{
    // Use the map's own box Wonder Weapon list. The dump has one per map
    // (itemspawnlist zm_sat_<map>_items_magicbox_weapon_wonder_list: Ray Gun 1,
    // Ray Gun Mk 2 1, map Wonder Weapon 1). Its entries go into
    // level.var_c5111f0d24e5789a, the same item table the stock
    // setup_magicbox_weapons() fills, so the map Wonder Weapon has exactly the
    // Ray Gun's chance on every map and mode.
    if ( !isdefined( box_map_wonder_item() ) )
    {
        return;
    }
    map_list = level.mapname + "_items_magicbox_weapon_wonder_list";
    list_bundle = getscriptbundle( hashcat( %"itemspawnlist:", map_list ) );
    if ( !isdefined( list_bundle ) || !isarray( list_bundle.itementries ) )
    {
        logstring( "[BO7 Cursed Fresh] Map Wonder Weapon list not found: " + map_list );
        return;
    }
    level.var_8b6bf63f61fe01f9 = map_list;
    if ( !isdefined( level.var_c5111f0d24e5789a ) )
    {
        level.var_c5111f0d24e5789a = [];
    }
    foreach ( s_itementry in list_bundle.itementries )
    {
        if ( isdefined( s_itementry.itemspawnentry ) )
        {
            level.var_c5111f0d24e5789a = arraycombineunique( level.var_c5111f0d24e5789a, [ s_itementry.itemspawnentry ] );
        }
    }
    logstring( "[BO7 Cursed Fresh] Map Wonder Weapon list in the Mystery Box: " + map_list );
}

function private set_map_wonder_limit( item_name, limit )
{
    if ( !isdefined( level.a_magicbox_item_limits ) )
    {
        return;
    }
    // Create the limit when the box bundle has none (stock
    // on_scriptable_item_spawned() then tracks the spawned copies), and set
    // it to exactly this value.
    if ( !isdefined( level.a_magicbox_item_limits[ item_name ] ) )
    {
        level.a_magicbox_item_limits[ item_name ] = { #itemmax:limit, #spawneditems:[] };
        return;
    }
    if ( level.a_magicbox_item_limits[ item_name ].itemmax != limit )
    {
        level.a_magicbox_item_limits[ item_name ].itemmax = limit;
    }
}

function private unlock_map_wonder_loop()
{
    level endon( #"game_ended" );
    b_rebuilt = 0;
    while ( supported_mode() )
    {
        // Restore the map's own Wonder Weapon list when quest scripts lock it.
        b_changed = 0;
        if ( isdefined( level.var_20cf5eda0c956d52 ) && level.var_20cf5eda0c956d52 )
        {
            magicbox::function_2e49cd8681e36211( 0 );
            b_changed = 1;
        }
        if ( isdefined( level.var_641b7c91f663ea4f ) && level.var_641b7c91f663ea4f )
        {
            magicbox::function_6f00dd035f2d8f9a( 0, 0 );
            b_changed = 1;
        }

        // These quest rewards have item limits raised only at quest completion.
        // Set the limit to the same completed-quest level from round 1.
        // Every map Wonder Weapon: level.cursed_box_ww_copies copies (the box limit
        // counts the ones on the ground + the ones players hold).
        item = box_map_wonder_item();
        if ( isdefined( item ) )
        {
            set_map_wonder_limit( hashcat( %"itemspawnentry:", item ), level.cursed_box_ww_copies );
        }

        // Regenerate the roulette's cached map-weapon models after clearing
        // an initial quest lock. Not needed on subsequent unchanged frames.
        if ( ( !b_rebuilt || b_changed ) && isdefined( level.var_8b6bf63f61fe01f9 ) )
        {
            magicbox::function_b787d845dbbfa18e();
            b_rebuilt = 1;
        }
        wait 0.25;
    }
}

// =====================================================================
// STARTING WEAPON - PLAYER'S OWN SAVED 1911 ZOMBIE BUILD
// =====================================================================
// Verified in the BO7 dump:
//  - zm_rb_r_mod::post_main() (all three supported gametypes) calls
//    zm_mode_modifiers "set_no_starting_equipment" with weapon_override
//    "sat_pi_alcor_mp", which sets level.zm_mode_modifiers.var_a551bdc7e905a4fd.
//  - zombie_mode_modifiers::on_player_spawned() threads (on the player)
//    function_2bcdcde1ea4b896b() unless a saved round is loading. After
//    wait 1 it calls weapon_utility::makeweaponwithdefaults( override ),
//    which reaches weapon::makeweaponwithdefaults():
//        weaponobj = self [[ level.addbaseattachments ]]( weaponobj );
//    with self == the spawning player. It then does ONE giveweapon() and
//    ONE switchtoweapon() with whatever weapon that returned.
//  - level.addbaseattachments = zm::zm_add_base_attachments (zm.gsc).
//  - The Zombie Build is stock per-player data: weaponmetadata::
//    function_f5a4ca68b5d36e7e() runs on player_connect and fills
//    self.favoriteweapons[ "sat_pi_alcor_mp" ] from the player's
//    "zmFavoriteWeapons" stats (attachments, blueprint variant, camo,
//    reticle, charm, stickers). The 1911 entry is eligible (pistol,
//    canpap, not a wonder weapon) in zm_sat_weapons_list, which is the
//    gamemode bundle's list for these modes.
//  - weaponmetadata::function_c68204eff69ed046( name ) is the stock
//    "apply my Zombie Build" call: it returns the built weapon, or
//    undefined when the player has no build. Wall-buys (wallbuy.gsc),
//    the Mystery Box (magicbox.gsc), the weapon carousel modifier and
//    several quests all use it exactly this way.
// Approach: wrap level.addbaseattachments once. On spawn the player is
// armed for ONE swap; the first time the stock starting hand-out builds
// "sat_pi_alcor_mp" for that player, the wrapper returns the player's own
// Zombie Build instead. Stock code then gives it and switches to it
// itself: no second giveweapon, no takeweapon, no visible replacement.
// No build -> stock default 1911. Every other weapon, player, entity and
// call passes straight through to the original zm_add_base_attachments.

function private install_starting_1911_build_hook()
{
    level endon( #"game_ended" );

    // zm init assigns level.addbaseattachments; wait for it (bounded).
    for ( i = 0; i < 600 && !isdefined( level.addbaseattachments ); i++ )
    {
        waitframe();
    }
    if ( !try_hook_add_base_attachments() )
    {
        logstring( "[BO7 Cursed Fresh] level.addbaseattachments not found; 1911 Zombie Build not applied" );
    }
}

function private try_hook_add_base_attachments()
{
    if ( istrue( level.cursed_1911_build_hooked ) )
    {
        return 1;
    }
    if ( !isdefined( level.addbaseattachments ) )
    {
        return 0;
    }
    level.cursed_orig_addbaseattachments = level.addbaseattachments;
    level.addbaseattachments = &starting_1911_add_base_attachments;
    level.cursed_1911_build_hooked = 1;
    return 1;
}

// self = the player, from on_player_spawned().
function private arm_starting_1911_build()
{
    // Only when the stock starting hand-out will actually run.
    if ( !isdefined( level.zm_mode_modifiers ) || !istrue( level.zm_mode_modifiers.var_a551bdc7e905a4fd ) )
    {
        return;
    }
    if ( utility::issharedfuncdefined( #"zombie", #"is_loading_saved_round" ) && utility::callsharedfunc( #"zombie", #"is_loading_saved_round" ) )
    {
        return;
    }
    if ( !try_hook_add_base_attachments() )
    {
        return;
    }
    self.cursed_1911_build_pending = 1;
    self.cursed_knife_build_pending = 1; // starting knife (melee_override)
    self thread expire_starting_1911_build();
}

// One-shot safety: if the stock hand-out is skipped (e.g. the healing-aura
// augment flag), disarm so no later 1911 is ever affected. Single wait, no loop.
function private expire_starting_1911_build()
{
    self notify( #"cursed_1911_build_expire" );
    self endon( #"cursed_1911_build_expire" );
    self endon( #"disconnect" );
    wait 5;
    self.cursed_1911_build_pending = undefined;
    self.cursed_knife_build_pending = undefined;
}

// Same calling convention as zm_add_base_attachments: self = caller's self.
function private starting_1911_add_base_attachments( weaponobj )
{
    if ( isdefined( self ) && isplayer( self ) && istrue( self.cursed_1911_build_pending ) && isweapon( weaponobj ) && weaponobj.basename == "sat_pi_alcor_mp" )
    {
        // Disarm FIRST: the stock build call below runs weapon::buildweapon(),
        // which re-enters this hook; that nested call must take the stock path
        // (it adds zm_add_base_attachments, keeping Pack-a-Punch compatibility).
        self.cursed_1911_build_pending = undefined;
        build = self weaponmetadata::function_c68204eff69ed046( "sat_pi_alcor_mp" );
        if ( isdefined( build ) && isweapon( build ) && !isnullweapon( build ) )
        {
            return build;
        }
        // No saved Zombie Build: fall through to the stock default 1911.
    }

    // Zm_rb_r_mod::post_main() sets melee_override "sat_me_knife_mp"; the
    // stock hand-out builds it with makeweaponwithdefaults() (this hook), then
    // giveweapon() + weapon::updatetertiaryweapon(). sat_me_knife_mp is an
    // eligible melee entry in zm_sat_weapons_list, so the player's saved build
    // is in self.favoriteweapons. Separate flag: independent from the 1911.
    if ( isdefined( self ) && isplayer( self ) && istrue( self.cursed_knife_build_pending ) && isweapon( weaponobj ) && weaponobj.basename == "sat_me_knife_mp" )
    {
        self.cursed_knife_build_pending = undefined;
        build = self weaponmetadata::function_c68204eff69ed046( "sat_me_knife_mp" );
        if ( isdefined( build ) && isweapon( build ) && !isnullweapon( build ) )
        {
            return build;
        }
        // No saved Knife Zombie Build: stock default knife.
    }

    orig = level.cursed_orig_addbaseattachments;
    if ( isfunction( orig ) )
    {
        return self [[ orig ]]( weaponobj );
    }
    return weaponobj;
}

// =====================================================================
// ZOMBIE ATTACK DAMAGE - CONSTANT ROUND-11 TIER
// =====================================================================
// Verified in the BO7 dump:
//  - damage_scaling_round::init_scaling_damage() registers
//    sharedfunc( #"zombie", #"hash_e27e55920dabe660" ) =
//    function_c0f17eb03e09d5ef( fixed_round_number ).
//  - It is called per AI at spawn (zombie_init.gsc, zm_round_spawning.gsc)
//    with the AI's difficulty round, and reads the AI's own
//    "damagescalinground:" bundle: melee / ranged / leap / armor-health /
//    custom damage multipliers, all "startround -> damagemultiplier".
//  - The common zombie tables are 1:x1.0, 11:x1.6666, 31:x2.5, ... (cap 250).
//    (damagescalinground ingame_zm: melee 1/11/31/41/51/61/71/100/200/400,
//    ranged 1/11/31/46). Rounds 11-30 share the x1.6666 tier.
//  Normal zombies (aicategory "normal") get the round-11 tier at every
//    round, so their attack damage never rises after round 30. Other AI
//    categories get the round-11 tier in rounds 1-10 and stock afterwards,
//    so special / boss damage is not changed.
//    Health uses a different sharedfunc, so this hook cannot touch health.
// Approach: wrap the stock function and, for rounds 1-10 only, run it with
// round 11. Every AI keeps ITS OWN table (so a type whose tier only changes
// at 21 is correctly unchanged) and caps stay intact. Rounds 11+ call the
// original with the original round number. Player-side reductions (armor,
// Juggernog, augments) are applied later in the damage pipeline and are not
// affected. Exfil passes round 1 on purpose; the live-round check keeps that.

function private install_early_round_damage_tier()
{
    level endon( #"game_ended" );

    // zm init registers the stock function; wait for it (bounded).
    for ( i = 0; i < 600 && !utility::issharedfuncdefined( #"zombie", #"hash_e27e55920dabe660" ); i++ )
    {
        waitframe();
    }
    if ( !utility::issharedfuncdefined( #"zombie", #"hash_e27e55920dabe660" ) )
    {
        logstring( "[BO7 Cursed Fresh] Zombie damage scaling func not found; early-round tier not applied" );
        return;
    }
    if ( istrue( level.cursed_damage_tier_hooked ) )
    {
        return;
    }
    level.cursed_orig_damage_scaling = utility::getsharedfunc( #"zombie", #"hash_e27e55920dabe660" );
    utility::registersharedfunc( #"zombie", #"hash_e27e55920dabe660", &early_round_damage_tier );
    level.cursed_damage_tier_hooked = 1;
}

// self = the AI being scaled (same calling convention as the stock function).
// zombie_init_ai() assigns self.aicategory only AFTER the spawn-time damage
// scaling call, so the AI's own settings bundle (self.zombieaisettings, set
// first) is read when the field is not there yet.
function private damage_tier_is_normal()
{
    category = self.aicategory;
    if ( !isdefined( category ) && isdefined( self.zombieaisettings ) )
    {
        category = self.zombieaisettings.aicategory;
    }
    return category === "normal";
}

function private early_round_damage_tier( fixed_round_number )
{
    orig = level.cursed_orig_damage_scaling;
    if ( !isfunction( orig ) )
    {
        return;
    }

    if ( !supported_mode() || !isdefined( fixed_round_number ) || fixed_round_number < 1 )
    {
        return self [[ orig ]]( fixed_round_number );
    }

    // BO3: bo3_health.gsc disables round damage scaling (stock flag below;
    // the stock function returns without changing anything) and fixes zombie
    // melee at 50 via dvar. Damage is already constant: never re-scale it.
    if ( istrue( level.var_9209eecc9aff21ad ) )
    {
        return self [[ orig ]]( fixed_round_number );
    }

    // Exfil and other scripted callers pass a low round on purpose while the
    // live round is already 11+: keep their stock result.
    if ( fixed_round_number < 11 && zm_utility::get_round_number() >= 11 )
    {
        return self [[ orig ]]( fixed_round_number );
    }

    // From round 11 on only normal zombies are pinned; specials,
    // elites, HVTs and bosses keep their own stock round scaling.
    if ( fixed_round_number >= 11 && !damage_tier_is_normal() )
    {
        return self [[ orig ]]( fixed_round_number );
    }

    if ( fixed_round_number == 11 )
    {
        return self [[ orig ]]( 11 );
    }

    // First pass at the real round, only to keep the max-simultaneous-target
    // count (var_577dec43cf1caedf, a targeting value, not damage) and the
    // stock late-round flag (var_f1cb4f6133640cfe) unchanged. The stock
    // function is idempotent (recomputes from *_base values).
    self [[ orig ]]( fixed_round_number );
    max_targets = self.var_577dec43cf1caedf;

    // Second pass with round 11 sets all damage values to the round-11 tier.
    self [[ orig ]]( 11 );
    self.var_577dec43cf1caedf = max_targets;
}

// =====================================================================
// START WITH 0 GOBBLEGUMS LOADED (STOCK PRE-LOADS 3)
// =====================================================================
// Verified in the BO7 dump (script_aa3bac81ad4fc8e, #namespace bgb):
//  - bgb::on_player_connect() -> bgb_player_init() builds the player's
//    5-gum pack (self.bgb_pack) and, when dvar hash_a7dd6191064a0709 (default
//    1) is set and there is no saved loadout, pre-loads the first 3 into the
//    3 action slots (self.bgb_action_pack[1..3]) via function_c068e36660508e7c.
//    THOSE are the "3 starting GobbleGums": loaded slots, not charges and not
//    inventory. Pre-loading consumes nothing; use is counted on activation.
//  - The GobbleGum machine (bgb_machine) only works when an action slot is
//    open (bgb::get_open_action_slot()) and draws from self.bgb_pack.
//  - During the first 180s, changing pack in-game re-fills the 3 slots via
//    function_9e1a713b9554d08a only while self.allow_instant_bgb_pack_switching
//    is 1 (stock sets it to 0 after the first gum use or 180s).
// Approach: once, right after stock connect-init, empty the pre-loaded slots
// with the stock bgb::clear_action_slot() and close the instant re-fill.
// The pack, inventory counts and the machine are untouched, so gums can be
// earned normally. Nothing runs on respawn. Saved-round loads are skipped.

function private on_player_connect_gobblegums( params )
{
    if ( !supported_mode() || !isplayer( self ) )
    {
        return;
    }
    self thread clear_starting_gobblegums();
}

function private clear_starting_gobblegums()
{
    self endon( #"disconnect" );
    level endon( #"game_ended" );

    // bgb_player_init() runs synchronously in bgb's own player_connect
    // callback; let every connect callback finish first.
    waittillframeend();
    for ( i = 0; i < 20 && !isdefined( self.bgb_action_pack ); i++ )
    {
        waitframe();
    }
    if ( !isdefined( self.bgb_action_pack ) )
    {
        return; // GobbleGums disabled for this match.
    }
    if ( istrue( self.cursed_starting_gums_cleared ) || istrue( self.cursed_starting_gums_pending ) )
    {
        return;
    }
    self.cursed_starting_gums_pending = 1;

    // Clear only once the round logic starts: every pre-load / pack refill
    // has happened by then, and no gum can be earned yet.
    level utility::flag_wait( "begin_round_logic" );
    waitframe();
    self.cursed_starting_gums_cleared = 1;

    // Same saved-loadout checks stock uses; restored gums are legitimate.
    if ( utility::issharedfuncdefined( #"zombie", #"is_loading_saved_round" ) && utility::callsharedfunc( #"zombie", #"is_loading_saved_round" ) )
    {
        return;
    }
    if ( utility::issharedfuncdefined( #"zombie", #"has_saved_loadout" ) && utility::callsharedfunc( #"zombie", #"has_saved_loadout" ) )
    {
        return;
    }

    // Stop the pre-match pack switch from re-filling all 3 slots.
    self.allow_instant_bgb_pack_switching = 0;

    for ( slot = 1; slot <= 3; slot++ )
    {
        if ( self bgb::is_slot_loaded( slot ) && !istrue( self.is_using_bgb_slot[ slot ] ) )
        {
            self bgb::clear_action_slot( slot );
        }
    }
}

// =====================================================================
// CLASSIC BO1 M1911 - WHITE 1911 DAMAGE BY HIT LOCATION
// =====================================================================
// Verified in the BO7 dump:
//  - zm_damage::zombie_agent_damage_callback() (and br_damage's copy) run the
//    stock zombie damage pipeline: rarity / PaP / critical multipliers first
//    (zombie_damage::function_881dfa87252ee0ea), then augments and relics,
//    then zombie_damage::function_23f0f83c55de1ad(), which calls the
//    per-weapon callback stored by zombie_utils::
//    register_zombie_weapon_damage_callback( weapon_name, func ), keyed by
//    sweapon.basename. A callback returning >= 0 sets the damage; -1 leaves
//    it untouched. No stock script registers one for "sat_pi_alcor_mp".
//  - After that callback, zombie_damage::function_960f65c8626d199b() divides
//    head / neck / helmet damage by the weapon asset's head modifier unless
//    dmg_struct.bskipexposedhead is set (stock flag, set the same way in
//    zombie_weyward.gsc and several map scripts). It is set here for head
//    hits so the value below is the final headshot damage.
//  - The 1911's raw damage, location multipliers and the knife's damage live
//    in the weapon assets, not in the script dump. Attachments in a player's
//    Zombie Build (barrels, .45 FMJ ammo, ...) can change that raw damage.
//    So the damage is SET here to an absolute value instead of scaled,
//    which makes it identical for every Zombie Build and every range.
//  - Normal zombie = subclass "zombie_base", aicategory "normal".
//    Spawn health = health_scaling_get_starting_health( own healthscriptbundle,
//    round ) called on the zombie (zombie_init.gsc); round 1 = base health.
//    The ZM normal-zombie bundles have numplayerhealthscale 0 (no co-op HP).
//  - Cursed classic points (zombie_mode_modifiers::set_classic_points):
//    10 per hit that does not kill (and while total damage <= maxhealth),
//    130 for a MOD_MELEE kill. 8 x 10 + 130 = 210 is the stock scoring.
// Base value (legs / feet / arms / hands) = floor( ( round-1 health - 1 ) / 8 ):
//    8 leg hits <= health - 1 -> the zombie always survives all 8 shots;
//    remaining health after 8 hits is 1..8 HP -> one knife hit kills.
// Other locations use BO1 Zombies M1911 multipliers on that base value
// (BO1: 20 damage; head x3.5, chest x1.25, abdomen x1.1, limbs x1.0):
//    torso_upper (chest) x1.25, torso_lower (abdomen) x1.1,
//    head / neck / helmet x3.5 (BO7 treats these three as one head zone).
// The values are flat for the whole match (BO1-style: fixed pistol damage,
// zombie health keeps growing). Other rarities, Pack-a-Punched 1911s, other
// weapons, other enemies, melee and unknown hit locations stay stock.

function private classic_1911_location_mult( loc )
{
    if ( !isdefined( loc ) )
    {
        return undefined;
    }
    if ( loc == "head" || loc == "neck" || loc == "helmet" )
    {
        return 3.5;
    }
    if ( issubstr( loc, "torso_upper" ) )
    {
        return 1.25;
    }
    if ( issubstr( loc, "torso_lower" ) )
    {
        return 1.1;
    }
    if ( issubstr( loc, "leg" ) || issubstr( loc, "foot" ) || issubstr( loc, "arm" ) || issubstr( loc, "hand" ) )
    {
        return 1.0;
    }
    return undefined; // "none", "gun", "shield", "armor", ... -> stock damage
}

function private classic_1911_leg_damage( dmg_struct )
{
    // self = the zombie being damaged.
    if ( !supported_mode() )
    {
        return -1;
    }
    attacker = dmg_struct.eattacker;
    if ( !isdefined( attacker ) || !isplayer( attacker ) )
    {
        return -1;
    }
    if ( !isdefined( self.subclass ) || self.subclass != "zombie_base" || !isdefined( self.aicategory ) || self.aicategory != "normal" )
    {
        return -1;
    }
    if ( !isdefined( dmg_struct.smeansofdeath ) || !utility::isbulletdamage( dmg_struct.smeansofdeath ) )
    {
        return -1; // pistol-whip / melee / explosive / ammo-mod damage stays stock
    }
    loc = dmg_struct.shitloc;
    mult = classic_1911_location_mult( loc );
    if ( !isdefined( mult ) )
    {
        return -1;
    }
    w = dmg_struct.objweapon;
    if ( !isdefined( w ) || !isweapon( w ) || w.basename != "sat_pi_alcor_mp" )
    {
        return -1;
    }

    // White / Common only (stock get_rarity(): undefined or 0 == "white").
    if ( utility::issharedfuncdefined( #"zombie", #"getplayerweaponrarity" ) )
    {
        rarity = attacker utility::callsharedfunc( #"zombie", #"getplayerweaponrarity", w );
        if ( isdefined( rarity ) && rarity != 0 )
        {
            return -1;
        }
    }
    // Not Pack-a-Punched.
    if ( attacker pack_a_punch::get_pap_level( w ) > 0 )
    {
        return -1;
    }

    // Round-1 health of THIS zombie type, from the stock health system.
    if ( !isdefined( self.zombieaisettings ) || !isdefined( self.zombieaisettings.healthscriptbundle ) )
    {
        return -1;
    }
    round1_health = self shared_func_utility::function_bb9b98eb7368a15a( self.zombieaisettings.healthscriptbundle, 1 );
    if ( !isdefined( round1_health ) || int( round1_health ) < 9 )
    {
        return -1;
    }
    base = int( ( int( round1_health ) - 1 ) / 8 );

    if ( loc == "head" || loc == "neck" || loc == "helmet" )
    {
        // Our value is final: stop the stock exposed-head step from dividing it.
        dmg_struct.bskipexposedhead = 1;
    }
    return int( base * mult );
}

// =====================================================================
// CLASSIC BO1-BO3 STARTING KNIFE - WHITE KNIFE HITS-TO-KILL
// =====================================================================
// Verified in the BO7 dump:
//  - Starting knife: "sat_me_knife_mp" (zm_rb_r_mod.gsc melee_override,
//    pack_a_punch.gsc). Alternate-mode weapon objects are mapped back with
//    the stock getnoaltweapon() (zombie_damage.gsc does the same), so the
//    alternate attack is recognised whatever its weapon object is.
//  - zombie_damage::function_23f0f83c55de1ad() runs, in order: level
//    agent-damage callbacks (zombie_utils::register_zombie_agent_damage_
//    callback on level), the zombie's own, the attacker's, then per-weapon
//    callbacks. It runs AFTER every multiplier step (criticals, rarity / PaP,
//    augments, and function_eb7d5e5b35444c8b = Melee Macchiato / Mocha Maul
//    knife damage: a base zombie's full health up to round 20). No stock
//    script registers a later callback for the knife or for zombie_base.
//  - After the callbacks, function_960f65c8626d199b (exposed-head divide)
//    skips MOD_MELEE / melee weapons; the armor steps only run when armor was
//    damaged (armored zombies are left stock here). So the value returned
//    here is the final damage for every hit location.
//  - Insta-Kill (insta_kill.gsc) sets the zombie's kill_on_damage flag,
//    which the pipeline applies after this callback: Insta-Kill still kills.
//  - Spawn health: zombie_init.gsc sets maxhealth from the zombie's own
//    health bundle at self._blackboard.difficultyround; in ZM that is
//    zm_utility::get_round_number() at spawn (zm.gsc get_shared_round_number).
//  - Points / kill credit: unchanged; only the damage number is returned.
// Classic table (BO1-BO3 zombie health / 150 knife damage):
//    hits = ceil( classic_health( round ) / 150 )
//    rounds 1-15 exactly as listed: 1,2,3,3,4,5,5,6,7,7,8,9,10,11,12;
//    round 16+ continues the classic health formula (x1.1 per round).
// BO7 damage per hit = ceil( this zombie's maxhealth / hits ), using the
// round the zombie spawned in (as in the classic games). N hits kill, N-1
// do not, for every hit location and both attack inputs. Only White /
// Common, non-Pack-a-Punched knife, MOD_MELEE, on unarmored normal zombies
// (subclass "zombie_base", aicategory "normal"); everything else -> -1
// (stock). Rarity / PaP are read on every hit, so an upgraded knife is
// stock immediately.

function private classic_knife_hits( n_round )
{
    if ( !isdefined( level.cursed_knife_hits ) )
    {
        level.cursed_knife_hits = [];
    }
    if ( isdefined( level.cursed_knife_hits[ n_round ] ) )
    {
        return level.cursed_knife_hits[ n_round ];
    }

    table = [ 150, 250, 350, 450, 550, 650, 750, 850, 950, 1045, 1150, 1265, 1391, 1530, 1683 ];
    if ( n_round <= table.size )
    {
        hp = table[ n_round - 1 ];
    }
    else
    {
        hp = table[ table.size - 1 ];
        last = min( n_round, 150 ); // classic growth; capped to stay in range
        for ( r = table.size + 1; r <= last; r++ )
        {
            hp = int( hp * 1.1 );
        }
    }
    hits = int( ceil( hp / 150 ) );
    if ( hits < 1 )
    {
        hits = 1;
    }
    level.cursed_knife_hits[ n_round ] = hits;
    return hits;
}

function private classic_knife_damage( dmg_struct )
{
    // self = the zombie being damaged.
    if ( !supported_mode() )
    {
        return -1;
    }
    if ( !isdefined( dmg_struct.smeansofdeath ) || dmg_struct.smeansofdeath != "MOD_MELEE" )
    {
        return -1;
    }
    attacker = dmg_struct.eattacker;
    if ( !isdefined( attacker ) || !isplayer( attacker ) )
    {
        return -1;
    }
    // Melee Macchiato owners keep stock perk/augment knife damage.
    // Zombie perks live in self.a_perks: engine hasperk() is always false.
    if ( utility::issharedfuncdefined( #"zombie_perks", #"has_zombie_perk" ) && attacker utility::callsharedfunc( #"zombie_perks", #"has_zombie_perk", "specialty_m_mod" ) )
    {
        return -1;
    }
    if ( !isdefined( self.subclass ) || self.subclass != "zombie_base" || !isdefined( self.aicategory ) || self.aicategory != "normal" )
    {
        return -1;
    }
    if ( isdefined( self.armorhealth ) && self.armorhealth > 0 )
    {
        return -1; // armored zombies keep stock damage / armor behaviour
    }

    w = dmg_struct.objweapon;
    if ( !isdefined( w ) || !isweapon( w ) )
    {
        w = dmg_struct.sweapon;
    }
    if ( !isdefined( w ) || !isweapon( w ) )
    {
        return -1;
    }
    if ( w.isalternate )
    {
        w = w getnoaltweapon();
    }
    if ( w.basename != "sat_me_knife_mp" )
    {
        return -1;
    }

    // White / Common only (stock get_rarity(): undefined or 0 == "white").
    if ( utility::issharedfuncdefined( #"zombie", #"getplayerweaponrarity" ) )
    {
        rarity = attacker utility::callsharedfunc( #"zombie", #"getplayerweaponrarity", w );
        if ( isdefined( rarity ) && rarity != 0 )
        {
            return -1;
        }
    }
    // Not Pack-a-Punched.
    if ( attacker pack_a_punch::get_pap_level( w ) > 0 )
    {
        return -1;
    }

    if ( !isdefined( self.maxhealth ) || self.maxhealth < 1 )
    {
        return -1;
    }
    n_round = undefined;
    if ( isdefined( self._blackboard ) && isdefined( self._blackboard.difficultyround ) )
    {
        n_round = self._blackboard.difficultyround;
    }
    if ( !isdefined( n_round ) || n_round < 1 )
    {
        n_round = zm_utility::get_round_number();
    }
    if ( !isdefined( n_round ) || n_round < 1 )
    {
        n_round = 1;
    }

    hits = classic_knife_hits( int( n_round ) );
    damage = int( ceil( self.maxhealth / hits ) );
    if ( damage < 1 )
    {
        damage = 1;
    }
    return damage;
}

// =====================================================================
// WEAPON PROGRESSION OVERHAUL
// =====================================================================

// ---------- 1. PACK-A-PUNCH LEVEL -> RARITY ----------
// Verified in the BO7 dump:
//  - Cursed's gametype bundle has the item-based PaP flag off, so every PaP
//    (stock menu purchase and this mod's Tier IV fallback) goes through
//    pack_a_punch::pap_weapon(), which fires
//    callback::callback( "zm_packed_weapon", params ) with params.player /
//    params.w_new, then gives w_new and calls set_pap_level() in the same frame.
//  - Rarity is stored per primary-inventory slot (item_weapon weapon data,
//    matched by basename), so it survives the PaP weapon swap.
//  - The native rarity setter is item_weapon::function_40e1cbd0e1f47d1a(
//    weapon, rarity ) - the exact call arsenal::upgrade_rarity() makes. It
//    updates the rarity read by zombie_damage::get_rarity() (damage), the
//    rarity HUD, and fires "on_weapon_rarity_set_complete".
//  - Rarity indices: 0 white, 1 green, 2 blue, 3 purple, 4 legendary,
//    5 "ultra_red" (magicbox::function_c19ee905418ebc92).
//  - arsenal::can_increase_weapon_tier() rejects fists, killstreaks and
//    Wonder Weapons; it is reused here unchanged.
// PaP I -> blue (2), II -> purple (3), III -> legendary (4), IV -> ultra (5).
// Never lowers rarity, never re-applies, costs nothing extra.

// Fired by pack_a_punch::pap_weapon() (direct PaP) and, for the PaP where
// the weapon floats out of the machine (function_893799cfb3f4d2d7), again by
// function_fc8ec85501be6cb8() when the player picks the packed weapon up -
// that pickup restores the OLD rarity from the stored item info, which is why
// rarity must be re-applied after it. self = the player in both cases.
function private on_packed_weapon_rarity( params )
{
    player = self;
    if ( isdefined( params ) && isdefined( params.player ) )
    {
        player = params.player;
    }
    if ( !supported_mode() || !isdefined( player ) || !isplayer( player ) )
    {
        return;
    }
    player thread reconcile_pap_rarity_deferred();
}

// weapons.gsc watchchangeweapon(): self = player. Also covers any other
// path that hands back a packed weapon. Event-driven, no polling.
function private on_weapon_change_rarity( params )
{
    if ( supported_mode() && isplayer( self ) )
    {
        self thread reconcile_pap_rarity_deferred();
    }
}

function private reconcile_pap_rarity_deferred()
{
    self endon( #"disconnect" );
    // Let the stock PaP / pickup code finish its give + set_pap_level() first.
    waittillframeend();
    self reconcile_pap_rarity();
}

// Rarity follows the PaP level of every primary weapon (upward only).
function private reconcile_pap_rarity()
{
    foreach ( w in self getweaponslistprimaries() )
    {
        if ( !isweapon( w ) || isnullweapon( w ) || !can_change_weapon_tier( w ) )
        {
            continue;
        }
        pap_level = self pack_a_punch::get_pap_level( w );
        if ( !isdefined( pap_level ) || pap_level <= 0 )
        {
            continue;
        }
        target = pap_level_rarity( w, pap_level );
        if ( target <= 0 )
        {
            continue;
        }
        current = self get_weapon_rarity( w );
        if ( isdefined( current ) && current >= target )
        {
            continue;
        }
        self set_weapon_rarity( w, target );
    }
}

// Same rule as arsenal::can_increase_weapon_tier() (fists, killstreaks and
// Wonder Weapons cannot change tier), written out here so this script does
// not call into the arsenal namespace.
function private can_change_weapon_tier( w )
{
    return !( weapon::isfistweapon( w ) || weapon::iskillstreakweapon( w ) || weapon::iswonderweapon( w ) );
}

// Stock rarity getter: shared func registered by item_weapon
// (#"zombie", #"getplayerweaponrarity" -> function_fb81bd2fe070faa6).
function private get_weapon_rarity( w )
{
    if ( utility::issharedfuncdefined( #"zombie", #"getplayerweaponrarity" ) )
    {
        return utility::callsharedfunc( #"zombie", #"getplayerweaponrarity", w ) ?? 0;
    }
    return item_weapon::function_fb81bd2fe070faa6( w );
}

// Stock rarity setter: shared func registered by item_weapon
// (#"zombie", #"hash_e546039029657cd5" -> function_40e1cbd0e1f47d1a).
function private set_weapon_rarity( w, rarity )
{
    if ( utility::issharedfuncdefined( #"zombie", #"hash_e546039029657cd5" ) )
    {
        utility::callsharedfunc( #"zombie", #"hash_e546039029657cd5", w, rarity );
        return;
    }
    item_weapon::function_40e1cbd0e1f47d1a( w, rarity );
}

function private pap_level_rarity( w, pap_level )
{
    switch ( pap_level )
    {
        case 1: return 2;
        case 2: return 3;
        case 3: return 4;
        case 4:
            // The zm_sat weapon list defines no base Ultra damage multiplier;
            // Ultra damage then depends on the weapon asset's own value. Use
            // the game's own multiplier lookup and never trade Legendary for a
            // weaker Ultra. (get_rarity() names index 4 "orange", 5 "yellow".)
            legendary = zombie_damage::function_6786d0923b8261db( w, "MOD_RIFLE_BULLET", "orange" );
            ultra = zombie_damage::function_6786d0923b8261db( w, "MOD_RIFLE_BULLET", "yellow" );
            if ( isdefined( legendary ) && isdefined( ultra ) && ultra < legendary )
            {
                logstring( "[BO7 Cursed Fresh] Ultra multiplier below Legendary for this weapon; keeping Legendary at PaP IV" );
                return 4;
            }
            return 5;
    }
    return 0;
}

// ---------- 2. ARSENAL: RANDOM AMMO MOD FOR 250 SALVAGE ----------
// Verified in the BO7 dump (mp/arsenal.gsc, mp/ammomods/ammo_mod.gsc):
//  - init_arsenal_machine() registers each machine's interact with
//    on_use_arsenal / arsenal_per_player_hint, stores interact.s_arsenal and
//    then fires callback::callback( #"on_arsenal_spawned" ) on the machine.
//  - The stock ammo-mod purchase (craft_weapon_ammomod) checks can_afford,
//    rejects the mod already on the weapon, requires
//    ammo_mod::can_get_ammo_mod(), applies ammo_mod::add_ammo_mod_to_weapon(),
//    fires "arsenal_craft_ammo_mod", then sub_currency_amount(). Applying a
//    new mod natively REPLACES the current one (add_ammo_mod_to_weapon).
//  - The Arsenal menu content comes from purchase-menu bundles that script
//    cannot edit, so the machine's interaction is rebound instead (same
//    interaction API this mod already uses for armor walls). The menu - and
//    with it manual rarity upgrades - is never opened.
//  - level.arsenal_max_weapon_rarity = 0 additionally makes the stock
//    craft_weapon_tier() refuse (response 4, no charge) if the menu is
//    ever opened by any other path.

function private on_arsenal_spawned_bind( params )
{
    if ( supported_mode() )
    {
        self arsenal_bind_one();
    }
}

// self = arsenal struct (level.a_s_arsenal_locations entry)
function private arsenal_bind_one()
{
    if ( !isdefined( self.mdl_arsenal ) || !isdefined( self.mdl_arsenal.interact ) )
    {
        return;
    }
    self.mdl_arsenal.interact interaction::set_interact_use_callback( &arsenal_random_ammo_mod_use );
    self.mdl_arsenal.interact interaction::set_interact_hint_callback( &arsenal_random_ammo_mod_hint );
}

// self = player. The weapon the Arsenal should modify. At the moment Use is
// pressed getcurrentweapon() can be the interact gesture / hands rather than
// the gun, so the held primary is preferred (engine builtins used by stock:
// getcurrentweapon, getcurrentprimaryweapon).
// A real weapon in hand (not "none" / fists).
function private arsenal_is_real_weapon( w )
{
    return isdefined( w ) && isweapon( w ) && !isnullweapon( w ) && !weapon::isfistweapon( w );
}

// Wonder Weapons never take Arsenal mods. ammo_mod::can_get_ammo_mod()
// only checks weapon::iswonderweapon() (metadata iswonderweapon flag); map
// Wonder Weapons are also flagged ismapwonderweapon, and their weapons are
// named sat_ww_*, so all three are rejected here.
function private arsenal_is_wonder_weapon( w )
{
    if ( weapon::iswonderweapon( w ) || weapon::ismapwonderweapon( w ) )
    {
        return true;
    }
    return isdefined( w.basename ) && issubstr( w.basename, "_ww_" );
}

function private arsenal_weapon_ok( w )
{
    return self arsenal_is_real_weapon( w ) && self hasweapon( w ) && !arsenal_is_wonder_weapon( w ) && ammo_mod::can_get_ammo_mod( w );
}

// The weapon the Arsenal acts on is ALWAYS the one in hand. Only when the gun
// is lowered by the machine itself (getcurrentweapon / getcurrentprimaryweapon
// = "none" at the moment of the press) is the weapon the hint last saw in
// hand used instead - even when that weapon cannot take a mod, so a held
// Wonder Weapon is refused rather than another gun being modified.
function private arsenal_held_weapon()
{
    w = self getcurrentweapon();
    if ( self arsenal_is_real_weapon( w ) )
    {
        return w;
    }
    w = self getcurrentprimaryweapon();
    if ( self arsenal_is_real_weapon( w ) )
    {
        return w;
    }
    return undefined;
}

function private arsenal_is_primary( w )
{
    if ( !isdefined( w ) )
    {
        return false;
    }
    foreach ( pw in self getweaponslistprimaries() )
    {
        if ( pw == w )
        {
            return true;
        }
    }
    return false;
}

// Order: the gun in hand -> the primary the hint last saw in hand -> the
// last primary weapons.gsc recorded (self.lastweaponobj). The fallbacks are
// used AS-IS (not skipped when unsuitable), so a held Wonder Weapon is
// refused instead of another gun being picked. Non-primary entries (use
// gesture / hands) are skipped.
function private arsenal_target_weapon()
{
    held = self arsenal_held_weapon();
    if ( isdefined( held ) )
    {
        return held;
    }
    if ( isdefined( self.cursed_arsenal_weapon ) && self arsenal_is_primary( self.cursed_arsenal_weapon ) )
    {
        return self.cursed_arsenal_weapon;
    }
    if ( isdefined( self.lastweaponobj ) && self arsenal_is_primary( self.lastweaponobj ) )
    {
        return self.lastweaponobj;
    }
    return self getcurrentweapon();
}

// self = player. Returns a random valid mod different from the current one.
function private arsenal_pick_ammo_mod( weapon )
{
    // self.cursed_arsenal_fail names the exact check that failed (shown on
    // screen by the purchase), so a refusal can be traced to one cause.
    self.cursed_arsenal_fail = undefined;
    if ( !istrue( level.ammo_mods_in_use ) || !isdefined( level.ammo_mods ) )
    {
        self.cursed_arsenal_fail = "Arsenal: Ammo Mods are not enabled in this mode";
        return undefined;
    }
    if ( !isdefined( weapon ) || !isweapon( weapon ) || isnullweapon( weapon ) )
    {
        self.cursed_arsenal_fail = "Arsenal: no weapon in hand";
        return undefined;
    }
    if ( weapon::isfistweapon( weapon ) )
    {
        self.cursed_arsenal_fail = "Arsenal: hands/fists cannot take Ammo Mods";
        return undefined;
    }
    if ( arsenal_is_wonder_weapon( weapon ) || !ammo_mod::can_get_ammo_mod( weapon ) )
    {
        self.cursed_arsenal_fail = "Arsenal: this weapon cannot take Ammo Mods";
        return undefined;
    }

    current = ammo_mod::get_ammo_mod_name( weapon );
    pool = [];
    // 1) The stock random pool (what ammo_mod::get_random_ammo_mod() uses).
    if ( isdefined( level.ammomodsbundlelist ) && isdefined( level.ammomodsbundlelist.ammomodbundles ) )
    {
        foreach ( bundle in level.ammomodsbundlelist.ammomodbundles )
        {
            name = bundle.ammomodname;
            if ( isdefined( name ) && isdefined( level.ammo_mods[ name ] ) && !( name === current ) && !( name === "none" ) )
            {
                pool[ pool.size ] = name;
            }
        }
    }
    // 2) Fallback: every Ammo Mod registered with ammo_mod::register_ammo_mod()
    //    (the table add_ammo_mod_to_weapon() itself reads), minus "none".
    if ( !pool.size )
    {
        foreach ( name in getarraykeys( level.ammo_mods ) )
        {
            if ( isdefined( name ) && !( name === "none" ) && !( name === current ) )
            {
                pool[ pool.size ] = name;
            }
        }
    }
    if ( !pool.size )
    {
        self.cursed_arsenal_fail = "Arsenal: no other Ammo Mod available";
        return undefined;
    }
    return utility::array_random( pool );
}

// self = arsenal interact
// Finds the arsenal struct for this interact; falls back to the machine
// nearest the player if the use arrives on another handle.
function private arsenal_struct_for_use( player )
{
    if ( isdefined( self ) && isdefined( self.s_arsenal ) )
    {
        return self.s_arsenal;
    }
    best = undefined;
    if ( isdefined( level.a_s_arsenal_locations ) )
    {
        foreach ( s in level.a_s_arsenal_locations )
        {
            if ( !isdefined( s.mdl_arsenal ) )
            {
                continue;
            }
            if ( !isdefined( best ) || distancesquared( s.mdl_arsenal.origin, player.origin ) < distancesquared( best.mdl_arsenal.origin, player.origin ) )
            {
                best = s;
            }
        }
    }
    return best;
}

// self = arsenal interact. Every refusal plays the deny sound AND prints the
// reason, so a failing purchase is never silent.
function private arsenal_random_ammo_mod_use( player )
{
    if ( !supported_mode() || !isplayer( player ) )
    {
        return;
    }
    if ( !self arsenal_in_reduced_range( player ) )
    {
        return; // outside the reduced prompt range: no prompt, no purchase
    }
    s_arsenal = self arsenal_struct_for_use( player );
    if ( !isdefined( s_arsenal ) )
    {
        arsenal_refuse( player, "Arsenal: machine not found" );
        return;
    }
    // Same checks as arsenal::can_use_arsenal().
    if ( !istrue( s_arsenal.b_arsenal_enabled ) )
    {
        arsenal_refuse( player, "Arsenal: no power" );
        return;
    }
    if ( istrue( player.interactions_disabled ) || istrue( player.arsenal_disabled ) )
    {
        return;
    }
    cost = 250;
    weapon = player arsenal_target_weapon();
    // One-time bounded wait (max 1 s) for the gun to come back up.
    for ( i = 0; i < 20 && !player arsenal_weapon_ok( weapon ); i++ )
    {
        waitframe();
        if ( !isdefined( player ) )
        {
            return;
        }
        weapon = player arsenal_target_weapon();
    }
    mod = player arsenal_pick_ammo_mod( weapon );
    if ( !isdefined( mod ) )
    {
        arsenal_refuse( player, player.cursed_arsenal_fail ?? "Arsenal: this weapon cannot take Ammo Mods" );
        return;
    }
    if ( !player currency::can_afford( #"salvage", cost ) )
    {
        arsenal_refuse( player, "Arsenal: not enough Salvage" );
        return;
    }

    // Native apply (replaces an existing mod, same as the stock Arsenal).
    new_weapon = player ammo_mod::add_ammo_mod_to_weapon( weapon, mod );
    applied = 0;
    if ( isdefined( new_weapon ) && isweapon( new_weapon ) && player ammo_mod::has_ammo_mod_by_name( new_weapon, mod ) )
    {
        applied = 1;
    }
    else if ( player ammo_mod::get_ammo_mod_name( weapon ) == mod )
    {
        applied = 1;
    }
    if ( !applied )
    {
        arsenal_refuse( player, "Arsenal: Ammo Mod could not be applied (no charge)" );
        return;
    }

    params = spawnstruct();
    params.item = mod;
    params.currency = #"salvage";
    params.cost = cost;
    player callback::callback( "arsenal_craft_ammo_mod", params );
    player currency::sub_currency_amount( #"salvage", cost );

    player playsoundtoplayer( #"ui_zm_core_purchase_success", player );
    if ( isdefined( s_arsenal.mdl_arsenal ) )
    {
        s_arsenal.mdl_arsenal setscriptablepartstate( "anim", "weapon_upgrade" );
        s_arsenal.mdl_arsenal setscriptablepartstate( "audio_purchase", "ammomod" );
    }
}

function private arsenal_refuse( player, msg )
{
    player playsoundtoplayer( #"ui_zm_core_purchase_deny", player );
    player iprintlnbold( msg );
}

function private arsenal_random_ammo_mod_hint( usable, player )
{
    if ( !supported_mode() || !isplayer( player ) || !isdefined( usable ) || !isdefined( usable.s_arsenal ) )
    {
        return { #string:&"", #type:"HINT_BUTTON" };
    }
    if ( !usable arsenal_in_reduced_range( player ) )
    {
        return { #string:&"", #type:"HINT_NOICON" }; // prompt hidden (as stock does)
    }
    cost = 250;
    hint = { #icon:"ui_icon_zm_ping_arsenal", #icon_text_value:cost, #icon_text:&"shared_hintstrings/cost_salvage", #title:&"shared_hintstrings/arsenal_title", #buttoncallout:&"shared_hintstrings/hint_buy", #params:[ cost, &"" ], #type:"HINT_BUTTON" };
    hint.string = hint.title;
    if ( !istrue( usable.s_arsenal.b_arsenal_enabled ) )
    {
        hint.aux_text = usable.arsenalpowerstringoverride ?? &"shared_hintstrings/need_power_red";
        hint.interactable = 0;
        return hint;
    }
    if ( player.interactions_disabled || player.arsenal_disabled )
    {
        return { #string:&"", #type:"HINT_NOICON" };
    }
    player arsenal_prompt_label_touch( usable );
    hint_weapon = player arsenal_target_weapon();
    held = player arsenal_held_weapon();
    if ( isdefined( held ) && player arsenal_is_primary( held ) )
    {
        player.cursed_arsenal_weapon = held; // whatever is in hand, valid or not
    }
    if ( !isdefined( player arsenal_pick_ammo_mod( hint_weapon ) ) )
    {
        hint.aux_text = &"ZM_RB_ECHO/PORTAL_AMMO_MOD_WONDER_WEAPON";
        hint.interactable = 0;
    }
    else if ( !player currency::can_afford( #"salvage", cost ) )
    {
        hint.aux_text = &"shared_hintstrings/not_enough_salvage";
        hint.interactable = 0;
    }
    return hint;
}

// ---------- 3. WALL-BUYS: PERMANENTLY GREEN + CLASSIC WHITE CHALK ----------
// Verified in mp/wallbuy.gsc:
//  - Weapon walls are level.contentmanager.spawnedinstances[ "wallbuy" ]
//    [ i ].contentgroups[ "wallbuy_spawn" ][ j ].wallbuy_scriptable with
//    .weapon_root_name (variant walls such as armor have none).
//  - Every wall, content-manager or not, goes through
//    Wallbuy::spawn_wallbuy_internal(), which appends its spawn struct to
//    level.a_s_wallbuy_locations (Survival zones, Mantis boss arena and the
//    wall randomizer modifier all spawn walls this way, outside the content
//    manager instances).
//  - Wallbuy::on_round_end() raises rarity every 5 rounds through
//    update_wallbuy_rarity(), which returns early when
//    wallbuy_scriptable.disable_upgrade is set.
//  - Purchases build the item from wallbuy_scriptable.rarity (item entry
//    "_green", and favourite-build rarity via rarity_to_number), so the
//    bought weapon's real rarity matches the wall.
// Set exactly what update_wallbuy_rarity() sets (rarity, cost from the
// stock get_wallbuy_cost()), without its upgrade fx, and set disable_upgrade
// so rounds and stock scripts cannot raise it.
//
// Classic white chalk (visual only):
//  - The chalk colour is NOT a GSC colour value. It is the "wallbuy" part
//    state of the wall's scriptable asset; each state swaps the chalk
//    material (assets: sat_zm_chalk_buy_<weapon> / mtl_t10_zm_chalk_buy_<weapon>
//    for base, plus _uncommon / _rare / _epic / _legendary variants).
//  - Wallbuy::set_wallbuy_rarity_state() maps white -> "base", green ->
//    "green", blue, purple, orange; update_wallbuy_rarity() also maps
//    "white" -> "base". So "base" exists on every weapon wall scriptable and
//    is the white / Common chalk.
//  - Stock precedent: zm_sat_hornet_assault_rounds on_feature_disabled() calls
//    set_wallbuy_rarity_state( wall, "white" ) without touching .rarity -
//    the part state is independent of the wall's real rarity.
//  - Only the "wallbuy" part is set here; .rarity stays "green", so cost,
//    hint and the purchased weapon are exactly the Green lock.
//  - Hornet's on_feature_enabled() restores set_wallbuy_rarity_state( wall,
//    wall.rarity ) and clears disable_upgrade; the sweep below sees the
//    cleared flag and re-applies the lock + white chalk.
//  - .cursed_white_chalk marks a scriptable that already got "base", so the
//    part state is set once per scriptable (no repeated state changes).

function private lock_wallbuys_green_init()
{
    level endon( #"game_ended" );
    utility::flag_wait( "wallbuy_ready" );
    lock_wallbuys_green();
    level thread white_chalk_sweep();
}

function private on_round_end_lock_wallbuys( params )
{
    if ( supported_mode() )
    {
        lock_wallbuys_green(); // catches any wall spawned after the first pass
    }
}

// Light sweep (1 s, ~20-40 structs, no per-frame work): picks up walls that
// spawn mid-round (Survival zones, boss arena, randomizer respawns) and
// walls whose chalk a map script re-coloured (Hornet feature re-enable).
function private white_chalk_sweep()
{
    level endon( #"game_ended" );
    while ( true )
    {
        wait 1;
        lock_wallbuys_green();
    }
}

function private lock_wallbuys_green()
{
    if ( isdefined( level.contentmanager ) && isdefined( level.contentmanager.spawnedinstances[ "wallbuy" ] ) )
    {
        foreach ( instance in level.contentmanager.spawnedinstances[ "wallbuy" ] )
        {
            if ( !isdefined( instance.contentgroups ) || !isdefined( instance.contentgroups[ "wallbuy_spawn" ] ) )
            {
                continue;
            }
            foreach ( wallbuy_spawn in instance.contentgroups[ "wallbuy_spawn" ] )
            {
                lock_one_wallbuy( wallbuy_spawn.wallbuy_scriptable );
            }
        }
    }

    // Walls spawned through spawn_wallbuy_internal() outside the
    // content manager instances.
    if ( isdefined( level.a_s_wallbuy_locations ) )
    {
        foreach ( s_wallbuy in level.a_s_wallbuy_locations )
        {
            if ( isdefined( s_wallbuy ) )
            {
                lock_one_wallbuy( s_wallbuy.wallbuy_scriptable );
            }
        }
    }
}

function private lock_one_wallbuy( ws )
{
    // Weapon walls only: armor (variant) walls have no weapon_root_name and
    // keep their own chalk / states.
    if ( !isdefined( ws ) || !isdefined( ws.weapon_root_name ) || is_armor_wall( ws ) )
    {
        return;
    }

    // Real rarity + cost: unchanged Green lock.
    if ( !isdefined( ws.rarity ) || ws.rarity != "green" )
    {
        ws.rarity = "green";
        ws.cost = Wallbuy::get_wallbuy_cost( ws.weapon_root_name, "green" );
    }

    // disable_upgrade cleared by someone else (Hornet re-enable restores the
    // rarity colour at the same time) -> chalk must be re-applied.
    if ( !istrue( ws.disable_upgrade ) )
    {
        ws.cursed_white_chalk = undefined;
    }
    ws.disable_upgrade = 1;

    // Visual only: white / Common chalk ("base" part state).
    if ( !istrue( ws.cursed_white_chalk ) )
    {
        ws setscriptablepartstate( "wallbuy", "base" );
        ws.cursed_white_chalk = 1;
    }
}

// ---------- 4. MYSTERY BOX: GREEN REGULAR WEAPONS, NO AETHER TOOLS ----------
// Verified in mp/magicbox.gsc setup_magicbox_weapon_array() and the box
// bundles:
//  - Each roll reads the round entry of level.s_magicbox_scaling.
//    magicboxroundscale. Regular-weapon rarity is decided by n_roll against
//    checks built from legendarychance / epicchance / rarechance; a weapon
//    re-rolled from a high roll (e.g. a Wonder Weapon you already own) lands
//    above every check and becomes Legendary.
//  - The misc list (miscitemspawnlist hash_1d887968b1d9d406) contains ONLY
//    itemspawnentry:zm_t10_item_aether_tool.
//  - Legacy weapons (legacyweaponchance of the active scaling bundle; the
//    map can override the bundle, so this applies in all three modes) are in
//    level.var_d46bd3e7f2f3e08e and take the item's own Ultra rarity branch,
//    not the regular-weapon rarity checks - left exactly as stock.
//  - The roulette preview rolls percent_chance() on the same three values.
// Applied once to every round entry: rare/epic 0, legendary -100 (all three
// checks end above 100, so every regular weapon - rolled, re-rolled and
// previewed - is Green), misc 0 (no Aether Tools; its share goes back to the
// regular weapon list). legacyweaponchance is left as stock.
// ultrachance (Wonder Weapons), support and equipment are untouched.

function private lock_magicbox_green()
{
    level endon( #"game_ended" );
    utility::flag_wait( "setup_magicbox_weapons" );
    utility::flag_wait( "magicbox_ready" );
    if ( !isdefined( level.s_magicbox_scaling ) || !isdefined( level.s_magicbox_scaling.magicboxroundscale ) )
    {
        return;
    }
    foreach ( s_scale in level.s_magicbox_scaling.magicboxroundscale )
    {
        s_scale.rarechance = 0;
        s_scale.epicchance = 0;
        s_scale.legendarychance = -100;
        s_scale.miscchance = 0;
    }
}

// ---------- ARSENAL PROMPT TEXT FOR LUA ----------
// zm_cursed_arsenal_prompt_post.lua shows dvar cursed_arsenal_prompt inside
// the Arsenal prompt (same pattern as zm_perk_remove_post.lua: GSC setdvar()
// -> Lua Dvar.GetDvarString()). The dvar is global, so the local (first)
// player drives it. Bounded watcher: runs only while that player stays at
// the machine, then clears the text and ends.
// Same pattern as the working perk-remove script (set_prompt_text /
// prompt_text_watch): every hint call refreshes a timestamp; the dvar is only
// written when the text changes; one level watcher clears it 250 ms after the
// hint calls stop (prompt gone).
function private arsenal_prompt_label_touch( usable )
{
    if ( !isdefined( level.players ) || !level.players.size || self != level.players[ 0 ] || !isdefined( usable ) )
    {
        return;
    }
    msg = "Equip random Ammo Mod";
    self.cursed_arsenal_prompt_seen = gettime();
    if ( !isdefined( level.cursed_arsenal_prompt_text ) || level.cursed_arsenal_prompt_text != msg )
    {
        level.cursed_arsenal_prompt_text = msg;
        setdvar( "cursed_arsenal_prompt", msg );
    }
    if ( !istrue( level.cursed_arsenal_prompt_watch ) )
    {
        level thread arsenal_prompt_label_watch( self );
    }
}

function private arsenal_prompt_label_watch( player )
{
    level.cursed_arsenal_prompt_watch = 1;
    while ( isdefined( player ) && isdefined( player.cursed_arsenal_prompt_seen ) && gettime() - player.cursed_arsenal_prompt_seen < 250 )
    {
        wait 0.1;
    }
    level.cursed_arsenal_prompt_text = "";
    setdvar( "cursed_arsenal_prompt", "" );
    level.cursed_arsenal_prompt_watch = 0;
}

// ---------- ARSENAL PROMPT RANGE (FIXED DISTANCE) ----------
// The engine calls the hint callback from well outside the distance at
// which the prompt can be used, so one fixed distance decides everything:
// inside it the prompt, the Lua text and the purchase are active; outside
// it the prompt is hidden (stock "HINT_NOICON" return) and Use does
// nothing. Measured flat (distance2d) from the player to the Arsenal
// interact point (25 units in front of the machine, init_arsenal_machine).
// 1 unit = 1 inch; 56 units = 1.4 m. Change ARSENAL_RANGE below to tune it.
function private arsenal_in_reduced_range( player )
{
    arsenal_range = 56; // ARSENAL_RANGE
    return distance2d( player.origin, self.origin ) <= arsenal_range;
}

// ---------- REMOVE AETHER TOOLS (RARITY UPGRADE TOOLS) ----------
// Verified in mp/loot/common_item.gsc: every world item spawn (Mystery Box
// weapons, reward bundles of trials, Mister Peeks eggs, side Easter eggs,
// vault, drops, ...) passes through
//   callback::response( 1, #"item_spawn_allowed", { #itembundle } )
// common/callbacks.gsc _evaluate_response(): with type 1 the spawn is
// cancelled as soon as ANY handler returns false (0). So this handler must
// return true for every item and false only for Aether Tools.
// The four tool tiers are
// itemspawnentry zm_t10_item_aether_tool(_2/_3/_4) with refs t10_aethertool,
// t10_aethertool2/3/4. Aether Crystals (PaP items) are NOT affected.
function private veto_aether_tool_spawn( params )
{
    if ( !supported_mode() || !isdefined( params ) || !isdefined( params.itembundle ) )
    {
        return true; // allowed
    }
    ref = params.itembundle.ref;
    if ( isdefined( ref ) && isstring( ref ) && issubstr( ref, "aethertool" ) )
    {
        return false; // Aether Tool: spawn cancelled
    }
    return true; // everything else: allowed
}

// ---------- CLASSIC KNIFE (MELEE MACCHIATO - MOCHA MAUL) ----------
// Verified in the BO7 dump:
//  - Mocha Maul is augment #"m_mod_panic_knife" ("The punch is replaced with
//    your Dedicated Melee Weapon"). perk_m_mod.gsc / m_mod_augments.gsc give
//    the engine perk "specialty_melee_without_swap" while the player has
//    Melee Macchiato (specialty_m_mod) AND that augment, and remove it for
//    the weapons in level.var_37cff8154b47b497 (Firefly / Hornet Wonder
//    Weapons) and m_mod_augments::function_dc2626f05ee229f9() (spear / spike
//    attachments). vintage.gsc gives the same perk on its own.
//  - zombie_augments::give_player_bonus_augment() adds an augment to the
//    BONUS list (bonusmajoraugments / bonusminoraugments), which
//    player_has_augment() accepts, without using a selection slot - the
//    stock way perks, field upgrades and ammo mods grant extra augments.
// So: (1) Mocha Maul is given as a bonus augment, so with Melee Macchiato
// the stock code runs it next to the player's own augments; (2) without
// Melee Macchiato the same perk is given directly, with the same weapon
// exclusions, so the melee button uses the knife (classic knife) from spawn.

function private classic_knife_on_spawn()
{
    // One watcher per player; a respawn replaces the previous one.
    self notify( #"cursed_classic_knife" );
    self endon( #"cursed_classic_knife" );
    self endon( #"disconnect" );
    level endon( #"game_ended" );
    // Stock loadout hand-out runs ~1 s after spawn (zombie_mode_modifiers).
    wait 1.5;
    self classic_knife_give_bonus_augment();
    self classic_knife_update( self getcurrentweapon() );

    // The perk is given back whenever it is missing (also after a down); it
    // is never force-removed and re-given, which would break the knife. The
    // stock Mocha Maul weapon-change handler also runs for every player
    // (see classic_knife_augment_check below).
    while ( supported_mode() )
    {
        wait 0.5;
        if ( isalive( self ) && !self hasperk( "specialty_melee_without_swap" ) )
        {
            self classic_knife_update( self getcurrentweapon() );
        }
    }
}

function private classic_knife_give_bonus_augment()
{
    if ( !istrue( level.zombie_augments_in_use ) || !isdefined( level.zombie_augments ) )
    {
        return;
    }
    bundle = level.zombie_augments[ #"m_mod_panic_knife" ];
    if ( !isdefined( bundle ) || !isdefined( self.zombie_augments ) || !isdefined( self.zombie_augments[ bundle.augmenttype ] ) )
    {
        return;
    }
    self zombie_augments::give_player_bonus_augment( #"m_mod_panic_knife", #"unknown" );
}

function private classic_knife_banned( weapon )
{
    if ( !isdefined( weapon ) || !isweapon( weapon ) )
    {
        return false;
    }
    if ( isdefined( level.var_37cff8154b47b497 ) )
    {
        foreach ( weapon_name in level.var_37cff8154b47b497 )
        {
            if ( weapon.basename == weapon_name )
            {
                return true;
            }
        }
    }
    return m_mod_augments::function_dc2626f05ee229f9( weapon );
}

// self = player
function private classic_knife_update( weapon )
{
    if ( !supported_mode() || !isalive( self ) )
    {
        return;
    }
    if ( self classic_knife_banned( weapon ) )
    {
        if ( self hasperk( "specialty_melee_without_swap" ) )
        {
            perk::removeperk( "specialty_melee_without_swap" );
        }
        return;
    }
    if ( !self hasperk( "specialty_melee_without_swap" ) )
    {
        perk::giveperk( "specialty_melee_without_swap" );
    }
}

// weapons.gsc watchchangeweapon(): self = player, params.weapon = new weapon.
function private classic_knife_on_weapon_change( params )
{
    if ( supported_mode() && isplayer( self ) )
    {
        weapon = undefined;
        if ( isdefined( params ) )
        {
            weapon = params.weapon;
        }
        self classic_knife_update( weapon );
    }
}

// Losing Melee Macchiato runs perk_m_mod::take_m_mod_perk(), which removes
// specialty_melee_without_swap; give it back on the next frame.
function private classic_knife_on_perk_lost( params )
{
    if ( supported_mode() && isplayer( self ) )
    {
        self thread classic_knife_restore();
    }
}

function private classic_knife_restore()
{
    self endon( #"disconnect" );
    waitframe();
    self classic_knife_update( self getcurrentweapon() );
}

// ---------- MOCHA MAUL WITHOUT MELEE MACCHIATO ----------
// Same technique as zm_armor_health_rework.gsc (Vulture Aid "replate"
// without the perk): wrap the stock shared function
//   #"zombie" / #"hash_3930894d8d2f0ee6" ( perkname, augmentname )
// which every script uses for "has this perk AND this augment"
// (m_mod_augments::m_mod_on_player_weapon_change, perk_m_mod give/think,
// zombie_damage::function_b1972eb8e4bd7e8f, ...). For
// ( "specialty_m_mod", #"m_mod_panic_knife" ) it answers yes, so the stock
// Mocha Maul code runs for every player without the perk:
//  - the weapon-change handler gives/removes specialty_melee_without_swap
//    with the stock weapon exclusions (classic knife on the melee button);
//  - Mocha Maul's stock knife damage applies (zombie_damage: a melee hit
//    deals a base zombie's full health up to the perk bundle's
//    maxdamageround, 20 by default).
//    For the White, non-PaP knife on unarmored normal zombies that
//    value is replaced by the classic hits-to-kill damage (later stage).
// Every other perk / augment question goes to the original function.
function private classic_knife_install_augment_check()
{
    level endon( #"game_ended" );
    while ( !utility::issharedfuncdefined( #"zombie", #"hash_3930894d8d2f0ee6" ) )
    {
        waitframe();
    }
    if ( istrue( level.cursed_classic_knife_check_wrapped ) )
    {
        return;
    }
    level.cursed_classic_knife_check_wrapped = 1;
    level.cursed_classic_knife_orig_check = level.sharedfuncs[ #"zombie" ][ #"hash_3930894d8d2f0ee6" ];
    level.sharedfuncs[ #"zombie" ][ #"hash_3930894d8d2f0ee6" ] = &classic_knife_augment_check;
}

function private classic_knife_augment_check( perkname, augmentname )
{
    if ( perkname === "specialty_m_mod" && augmentname === #"m_mod_panic_knife" && supported_mode() )
    {
        return 1;
    }
    return self [[ level.cursed_classic_knife_orig_check ]]( perkname, augmentname );
}

// ---------- ZOMBIE BUILD KEPT ON MELEE-SHARED BOX WEAPONS ----------
// Verified in mp/magicbox.gsc: meleeing the weapon in an open box runs
// drop_item_from_magicbox(), which spawns the dropped weapon with
// spawnoptions from function_535a73eae8edf8b7() (spawningentity = the
// player, var_90cdc5dbcd319e5d = 1 set just before the spawn) and NO
// spawnoptions.weapon - so the item falls back to the bundle's default
// weapon and the Zombie Build is lost. The normal box spawn sets
// spawnoptions.weapon = weaponmetadata::function_c68204eff69ed046( base ).
// common_item fires callback #"item_spawn_begin" { spawnoptions, itembundle }
// right before spawning (weap_hornetww edits it the same way), so the same
// Zombie Build is put on the dropped weapon there. Weapon item bundles carry
// .baseweapon (e.g. "sat_pi_alcor_mp"), the key of self.favoriteweapons.
function private keep_build_on_box_drop( params )
{
    if ( !supported_mode() || !isdefined( params ) || !isdefined( params.spawnoptions ) )
    {
        return;
    }
    spawnoptions = params.spawnoptions;
    if ( !istrue( spawnoptions.var_90cdc5dbcd319e5d ) || isdefined( spawnoptions.weapon ) )
    {
        return; // not a melee-shared box drop, or a weapon is already set
    }
    player = spawnoptions.spawningentity;
    if ( !isdefined( player ) || !isplayer( player ) )
    {
        return;
    }
    bundle = params.itembundle;
    if ( isdefined( bundle ) && isxhashasset( bundle ) )
    {
        bundle = getscriptbundle( bundle );
    }
    if ( !isdefined( bundle ) || !isdefined( bundle.baseweapon ) )
    {
        return; // not a weapon item (scorestreak, equipment, ...)
    }
    favoriteweapon = player weaponmetadata::function_c68204eff69ed046( bundle.baseweapon );
    if ( isdefined( favoriteweapon ) )
    {
        spawnoptions.weapon = favoriteweapon;
    }
}

// ---------- PACK MULE FOR LEGACY (ULTRA) WEAPONS ----------
// Verified in the BO7 dump:
//  - Pack Mule (#"z_mod_pack_mule") changes ONE value: every refill /
//    pickup / ammo purchase asks utility::get_max_stock_ammo( weapon,
//    has_pack_mule ), which returns weaponmaxammo() with Pack Mule and
//    weaponstartammo() without it (gamemode flag var_1976506fada1193b).
//    Call sites: full_ammo.gsc (Max Ammo), wallbuy.gsc, common_item_weapon /
//    common_item_ammo (pickups, ammo), pack_a_punch.gsc, zm_laststand.gsc.
//  - Those calls pass no weapon to the perk/augment check, so the check
//    itself cannot be answered per weapon. Instead the result is applied
//    per weapon: when a legacy weapon's reserve has just been refilled to
//    the normal maximum, it is raised to the Pack Mule maximum.
//  - Legacy weapons = the box's legacy list, level.var_d46bd3e7f2f3e08e
//    (item entries, magicbox.gsc); their item bundles give .baseweapon.
// Nothing else changes: Mule Kick and all its augments (including the real
// Pack Mule, which then covers every weapon) work exactly as stock.

function private legacy_pack_mule_init()
{
    level endon( #"game_ended" );
    utility::flag_wait( "setup_magicbox_weapons" );
    utility::flag_wait( "magicbox_ready" );
    level.cursed_legacy_weapons = [];
    if ( !isdefined( level.var_d46bd3e7f2f3e08e ) )
    {
        return;
    }
    foreach ( item_entry in level.var_d46bd3e7f2f3e08e )
    {
        bundle = getscriptbundle( item_entry );
        if ( isdefined( bundle ) && isdefined( bundle.baseweapon ) )
        {
            level.cursed_legacy_weapons[ bundle.baseweapon ] = 1;
        }
    }
}

// self = player. Light check (0.25 s) that only acts on a refill: the
// reserve went UP and landed exactly on the normal maximum - the value every
// stock refill sets without Pack Mule. Shooting / reloading only lower the
// reserve, so this can never refill ammo by itself.
// Mystery Box pickups fire callback "magicbox_purchase" (self =
// player) with params.islegacyweapon (the box's var_c472ba9c1811f8cf flag)
// and params.objweapon. That flag is the authoritative "legacy weapon" mark,
// so the weapon is remembered for this player.
function private legacy_pack_mule_on_box_purchase( params )
{
    if ( !supported_mode() || !isplayer( self ) || !isdefined( params ) || !istrue( params.islegacyweapon ) )
    {
        return;
    }
    if ( isdefined( params.objweapon ) && isweapon( params.objweapon ) && isdefined( params.objweapon.basename ) )
    {
        if ( !isdefined( self.cursed_legacy_owned ) )
        {
            self.cursed_legacy_owned = [];
        }
        self.cursed_legacy_owned[ params.objweapon.basename ] = 1;
    }
}

function private legacy_pack_mule_is_legacy( w )
{
    if ( isdefined( self.cursed_legacy_owned ) && istrue( self.cursed_legacy_owned[ w.basename ] ) )
    {
        return true;
    }
    return isdefined( level.cursed_legacy_weapons ) && istrue( level.cursed_legacy_weapons[ w.basename ] );
}

// self = player. Light check (0.25 s) that only acts on a refill: the
// reserve went UP and is at or above the normal maximum
// (weaponstartammo - what every stock refill gives without Pack Mule) but
// below the Pack Mule maximum (weaponmaxammo). Shooting / reloading only
// lower the reserve, so this never adds ammo by itself.
function private legacy_pack_mule_watch()
{
    self notify( #"cursed_legacy_pack_mule" );
    self endon( #"cursed_legacy_pack_mule" );
    self endon( #"disconnect" );
    level endon( #"game_ended" );
    self.cursed_pm_last = [];
    while ( supported_mode() )
    {
        wait 0.25;
        if ( !isalive( self ) )
        {
            continue;
        }
        foreach ( w in self getweaponslistprimaries() )
        {
            if ( !isweapon( w ) || isnullweapon( w ) || !isdefined( w.basename ) || !self legacy_pack_mule_is_legacy( w ) )
            {
                continue;
            }
            stock = self getweaponammostock( w );
            last = self.cursed_pm_last[ w.basename ];
            self.cursed_pm_last[ w.basename ] = stock;
            if ( isdefined( last ) && stock <= last )
            {
                continue; // no refill
            }
            normal_max = weaponstartammo( w );
            pack_mule_max = weaponmaxammo( w );
            if ( pack_mule_max > normal_max && stock >= normal_max && stock < pack_mule_max )
            {
                self setweaponammostock( w, pack_mule_max );
                self.cursed_pm_last[ w.basename ] = pack_mule_max;
            }
        }
    }
}

// =====================================================================
// MAP WONDER WEAPONS - ONE HIT ON NORMAL ZOMBIES (PaP III+)
// =====================================================================
// Verified in the BO7 dump:
//  - Weapon names (scriptbundle scriptedweaponlist global_shared_mp and the
//    weapon scripts):
//      Ashes of the Damned  Necrofluid Gauntlet  sat_ww_firefly_zm
//                           (EE "long" version sat_ww_firefly_ee_zm,
//                           liquid grenade sat_ww_firefly_liquid_zm)
//      Kowakujo             Nekomancer           sat_ww_hornet_zm
//      Totenreich           Jotunn Star          sat_ww_locust_zm
//                           (fireball sub-weapon sat_ww_locust_fireball)
//      Paradox Junction     Blundergat           sat_ww_mantis_zm
//      Astra Malorum        LGM-1                sat_ww_ruby_zm
//      Rex Infernus         Warden's Blight      sat_ww_scarab_zm
//    Not listed (unchanged): sat_ww_raygun_mp, sat_ww_raygunmark2_mp,
//    sat_pi_ztronraygun.
//  - Every damage path of these weapons (projectile hits, scripted
//    dodamage() for AoE / DoT / recall / tornado / tendrils) carries the
//    weapon object and runs through br_damage::zombie_agent_damage_callback.
//    zombie_damage::function_23f0f83c55de1ad() calls the per-weapon map
//    (register_zombie_weapon_damage_callback on level) LAST, after the
//    weapons' own agent callbacks (VO, fx, penetration). No stock script
//    registers a level per-weapon callback for these names.
//  - Only the damage number is returned: effects, animations, ammo, PaP,
//    kill credit and points stay stock; no extra damage event is created.
//  - idamage <= 0 is left alone (Necrofluid returns 0 past its max enemy
//    penetration on purpose). MOD_MELEE (weapon bash / gauntlet punch) stays
//    stock. bskipexposedhead keeps the head-modifier divide from lowering
//    the value. Normal zombies have no max-health damage cap (< 1).
//  - Only normal, unarmored zombies: aicategory "normal", subclass without
//    "armored", no armor health, no damage shield. Specials, elites, HVTs and
//    bosses keep stock damage.
//  - PaP level: pack_a_punch get_pap_level() matches the full weapon object,
//    which sub-weapons (fireball, liquid grenade) never match, so the
//    attacker's a_n_current_pap_level list is read by weapon family.
// Threshold: level.cursed_ww_min_pap (3 = PaP III and IV; 0 = every tier).

function private install_ww_instakill()
{
    level.cursed_ww_min_pap = 3;
    // PaP tier at which non-boss enemies that are not one-hit take x1.7 damage.
    level.cursed_ww_double_pap = 4;
    level.cursed_ww_family = [];
    level.cursed_ww_family[ "sat_ww_firefly_zm" ] = "sat_ww_firefly";
    level.cursed_ww_family[ "sat_ww_firefly_ee_zm" ] = "sat_ww_firefly";
    level.cursed_ww_family[ "sat_ww_firefly_liquid_zm" ] = "sat_ww_firefly";
    level.cursed_ww_family[ "sat_ww_hornet_zm" ] = "sat_ww_hornet";
    level.cursed_ww_family[ "sat_ww_locust_zm" ] = "sat_ww_locust";
    level.cursed_ww_family[ "sat_ww_locust_fireball" ] = "sat_ww_locust";
    level.cursed_ww_family[ "sat_ww_mantis_zm" ] = "sat_ww_mantis";
    level.cursed_ww_family[ "sat_ww_ruby_zm" ] = "sat_ww_ruby";
    level.cursed_ww_family[ "sat_ww_scarab_zm" ] = "sat_ww_scarab";

    foreach ( weapon_name, family in level.cursed_ww_family )
    {
        level zombie_utils::register_zombie_weapon_damage_callback( weapon_name, &ww_instakill_damage );
    }

    // Armored zombies (scriptbundle/ai_subclass), killed through the
    // stock killondamage flag.
    level.cursed_ww_armored_subclass = [];
    level.cursed_ww_armored_subclass[ "zombie_base_armored_light" ] = 1;
    level.cursed_ww_armored_subclass[ "zombie_base_armored_heavy" ] = 1;
    level.cursed_ww_armored_subclass[ "zombie_base_armored_heavy_no_armor" ] = 1;
}

function private ww_family_pap_level( player, family )
{
    best = 0;
    if ( !isdefined( player.a_n_current_pap_level ) )
    {
        return best;
    }
    foreach ( papstruct in player.a_n_current_pap_level )
    {
        if ( !isdefined( papstruct ) || !isweapon( papstruct.weapon ) )
        {
            continue;
        }
        if ( issubstr( papstruct.weapon.basename, family ) && ( papstruct.n_level ?? 0 ) > best )
        {
            best = papstruct.n_level;
        }
    }
    return best;
}

function private ww_instakill_damage( dmg_struct )
{
    // self = the zombie being damaged.
    if ( !supported_mode() )
    {
        return -1;
    }
    if ( !isdefined( dmg_struct.idamage ) || dmg_struct.idamage <= 0 )
    {
        return -1;
    }
    if ( dmg_struct.smeansofdeath === "MOD_MELEE" )
    {
        return -1;
    }
    attacker = dmg_struct.eattacker;
    if ( isdefined( attacker ) && !isplayer( attacker ) && isdefined( attacker.owner ) && isplayer( attacker.owner ) )
    {
        attacker = attacker.owner;
    }
    if ( !isdefined( attacker ) || !isplayer( attacker ) )
    {
        return -1;
    }
    // Scripted invulnerability (damage shield) is always respected.
    if ( istrue( self.damageshield ) )
    {
        return -1;
    }
    if ( !isdefined( dmg_struct.sweapon ) || !isdefined( self.health ) )
    {
        return -1;
    }
    family = level.cursed_ww_family[ dmg_struct.sweapon.basename ];
    if ( !isdefined( family ) )
    {
        return -1;
    }
    n_pap = ww_family_pap_level( attacker, family );
    // LGM-1 PaP IV - first saucer hit of a shot starts the strike.
    if ( family == "sat_ww_ruby" && n_pap >= 4 )
    {
        self lgm_strike_check( attacker, dmg_struct.sweapon );
    }
    // Armored zombies (never HVT / boss variants).
    is_armored = isdefined( self.subclass ) && isdefined( level.cursed_ww_armored_subclass[ self.subclass ] ) && !( self.aicategory === "boss" ) && !( self.aicategory === "hvt" );
    // Normal, unarmored zombies.
    is_plain_normal = self.aicategory === "normal" && !issubstr( self.subclass ?? "", "armored" ) && !( isdefined( self.armorhealth ) && self.armorhealth > 0 );
    if ( ( is_armored || is_plain_normal ) && n_pap >= level.cursed_ww_min_pap )
    {
        dmg_struct.bskipexposedhead = 1;
        if ( is_armored )
        {
            // Armor-plate mitigation, shields and the max-health damage cap run
            // after this callback in zm_damage; the stock killondamage check runs
            // after them and sets the damage to the full remaining health, so the
            // zombie dies instead of only losing armor. Cleared at end of frame
            // if it somehow survived.
            if ( !istrue( self.killondamage ) )
            {
                self.killondamage = 1;
                self thread ww_killondamage_restore();
            }
        }
        return int( self.health ) + 1;
    }
    // PaP IV multiplies the damage by 1.7 on every other enemy
    // (specials, elites, HVTs, normal zombies the rule above skips).
    // Bosses keep stock damage.
    if ( n_pap >= level.cursed_ww_double_pap && !( self.aicategory === "boss" ) )
    {
        return int( dmg_struct.idamage * 1.7 );
    }
    return -1;
}

function private ww_killondamage_restore()
{
    self endon( #"death" );
    waittillframeend();
    if ( isdefined( self ) && isalive( self ) )
    {
        self.killondamage = 0;
    }
}

// =====================================================================
// RAY GUN / RAY GUN MARK II - x2 AT PaP I-III, x2.5 AT PaP IV
// =====================================================================
// Verified in the BO7 dump:
//  - br_damage zombie_agent_damage_callback order: adjustdamagerarity
//    (rarity x PaP multiplier, zombie_damage::function_968dcf03f8aacaae)
//    -> adjustdamagespecific (level.weapon_specific_damage_modifiers: the
//    Ray Gun remaps impact / splash to weap_raygun level.raygun_damage_structs
//    and does x0.1 on bosses) -> shields -> adjustdamagekillcallbacks, which
//    ends with the per-weapon map (register_zombie_weapon_damage_callback).
//    No stock script registers that map for these two weapons.
//  - PaP multipliers (weaponmetadataentry ingame_zm, used when the weapon
//    asset has no own papNdamagescale): Ray Gun sat_ww_raygun_mp 1 / 3.5 /
//    7.5 / 11, Mark II sat_ww_raygunmark2_mp 2 / 4 / 8 / 10 (PaP I-IV).
// So returning damage x2 here, after every stock step, doubles the final
// damage of each PaP tier (I-IV); unpacked weapons stay stock. MOD_MELEE
// (pistol bash) stays stock. The max-health damage cap and armor still run
// after this callback.
function private install_raygun_pap_double()
{
    level zombie_utils::register_zombie_weapon_damage_callback( "sat_ww_raygun_mp", &raygun_pap_double_damage );
    level zombie_utils::register_zombie_weapon_damage_callback( "sat_ww_raygunmark2_mp", &raygun_pap_double_damage );
}

function private raygun_pap_double_damage( dmg_struct )
{
    if ( !supported_mode() )
    {
        return -1;
    }
    if ( !isdefined( dmg_struct.idamage ) || dmg_struct.idamage <= 0 || dmg_struct.smeansofdeath === "MOD_MELEE" || !isdefined( dmg_struct.sweapon ) )
    {
        return -1;
    }
    attacker = dmg_struct.eattacker;
    if ( isdefined( attacker ) && !isplayer( attacker ) && isdefined( attacker.owner ) && isplayer( attacker.owner ) )
    {
        attacker = attacker.owner;
    }
    if ( !isdefined( attacker ) || !isplayer( attacker ) || !isdefined( attacker.a_n_current_pap_level ) )
    {
        return -1;
    }
    n_pap = 0;
    foreach ( papstruct in attacker.a_n_current_pap_level )
    {
        if ( isdefined( papstruct ) && isweapon( papstruct.weapon ) && papstruct.weapon.basename == dmg_struct.sweapon.basename )
        {
            n_pap = papstruct.n_level ?? 0;
            break;
        }
    }
    if ( n_pap < 1 )
    {
        return -1;
    }
    mult = 2.0;
    // PaP IV only: impact + splash x2.5, Mark II headshot +35%.
    if ( n_pap >= 4 )
    {
        mult = 2.5;
        mod = dmg_struct.smeansofdeath;
        if ( dmg_struct.sweapon.basename == "sat_ww_raygunmark2_mp" )
        {
            loc = dmg_struct.shitloc;
            if ( mod === "MOD_HEAD_SHOT" || loc === "head" || loc === "neck" || loc === "helmet" )
            {
                mult = 2.5 * 1.35;
            }
        }
    }
    return int( dmg_struct.idamage * mult );
}

// ---------- T.E.D.D. TASK REWARDS WITHOUT AETHER TOOLS ----------
// Verified in the BO7 dump (mp/zm/tedd_tasks.gsc, mp/zm/sat_interactable_chest.gsc,
// mp/loot/common_cache.gsc, itemspawnlist bundles):
//  - teddtasks::end_task() grades the task (loot_level 1 / 2 / 3), takes the
//    reward list from get_loot_reward_list( loot_level, level.roundscale ) and
//    fires level callback "teddtask_complete" (params.chest = task_chest
//    struct). hide_teddtask( 0 ) then runs
//    sat_interactable_chest::spawn_initial_chest_setup(): one cache per alive
//    player in chest.caches, each filled in the same frame by
//    common_cache::function_a136b84fc5c0dfab( cache, list, 9, 1 ) = engine
//    CommonItem_SelectFromList( list, 9 ) + cache_additem() per pick.
//  - Reward lists: zm_sat_items_trials_chest_{small,large,gold}_lvl1-4
//    (lvl = level.roundscale). Aether Tools exist only in the gold lists, in
//    zm_sat_items_trials_weapon_upgrade_lvlN_droplist (one weighted option of
//    the resources_gold_set slot). No #mincount in any of the 12 lists: no
//    guaranteed tool slot. Without the tools each weapon_upgrade list keeps
//    one eligible item (its existing weight), the tier's Aether Crystal:
//      lvl1: tool_2 (2), crystal (1)                -> t10_aethercrystal
//      lvl2: tool_3 (2), crystal_2 (1)              -> t10_aethercrystal2
//      lvl3: tool_3 (10), tool_4 (3), crystal_3 (1) -> t10_aethercrystal3
//      lvl4: tool_4 (1), crystal_3 (1)              -> t10_aethercrystal3
// The engine pick cannot be filtered from GSC, so right after the chest is
// filled each Aether Tool slot is swapped for that tier's crystal - the same
// result as picking from the tool-free weapon_upgrade list. Slot count stays
// the same. Only T.E.D.D. chests (this callback) are touched; other users of
// get_loot_reward_list (Hornet side Easter egg) are not.
function private tedd_rewards_no_tools( params )
{
    if ( !supported_mode() || !isdefined( params ) || !isdefined( params.chest ) )
    {
        return;
    }
    level thread tedd_chest_replace_tools( params.chest, level.roundscale );
}

function private tedd_chest_replace_tools( chest, n_tier )
{
    level endon( #"game_ended" );
    // Caches still on this chest belong to an earlier task: never touch them.
    if ( isdefined( chest.caches ) )
    {
        foreach ( cache in chest.caches )
        {
            if ( isdefined( cache ) )
            {
                cache.cursed_tedd_checked = 1;
            }
        }
    }
    // hide_teddtask() spawns the chest ~2 s after the callback. All caches
    // are created and filled in one frame, so the first new one = all of them.
    for ( i = 0; i < 1200; i++ )
    {
        wait 0.05;
        if ( !isdefined( chest.caches ) )
        {
            continue;
        }
        found = 0;
        foreach ( cache in chest.caches )
        {
            if ( isdefined( cache ) && !istrue( cache.cursed_tedd_checked ) )
            {
                cache.cursed_tedd_checked = 1;
                tedd_cache_replace_tools( cache, n_tier );
                found = 1;
            }
        }
        if ( found )
        {
            return;
        }
    }
}

function private tedd_is_aether_tool( lootid )
{
    if ( !isdefined( lootid ) || lootid == 0 )
    {
        return false;
    }
    foreach ( ref in [ "t10_aethertool", "t10_aethertool2", "t10_aethertool3", "t10_aethertool4" ] )
    {
        if ( common_item::items_getlootidfromref( ref ) === lootid )
        {
            return true;
        }
    }
    return false;
}

function private tedd_tier_crystal_ref( n_tier )
{
    if ( n_tier === 1 )
    {
        return "t10_aethercrystal";
    }
    if ( n_tier === 2 )
    {
        return "t10_aethercrystal2";
    }
    return "t10_aethercrystal3";
}

function private tedd_cache_replace_tools( cache, n_tier )
{
    if ( !isdefined( cache.contents ) )
    {
        return;
    }
    tool_slots = [];
    foreach ( index, entry in cache.contents )
    {
        if ( isdefined( entry ) && tedd_is_aether_tool( entry.lootid ) )
        {
            tool_slots[ tool_slots.size ] = index;
        }
    }
    if ( !tool_slots.size )
    {
        return;
    }
    crystal = undefined;
    crystal_id = common_item::items_getlootidfromref( tedd_tier_crystal_ref( n_tier ) );
    if ( isdefined( crystal_id ) )
    {
        crystal = common_item_database::function_db2360bc1c33f6f9( crystal_id );
    }
    foreach ( index in tool_slots )
    {
        // Same empty-slot shape the stock cache code uses.
        cache.contents[ index ] = { #quantity:0, #lootid:0 };
        if ( isdefined( crystal ) )
        {
            common_cache::cache_additem( cache, crystal );
        }
        else
        {
            logstring( "[BO7 Cursed Fresh] TEDD reward: no Aether Crystal for tier " + n_tier + "; Aether Tool slot left empty" );
        }
    }
}

// =====================================================================
// BO3-COMPATIBLE: NO VISIBLE ARMOR
// =====================================================================
// With armor disabled by bo3_health.gsc the stock starting armor (zm_armor::
// zm_give_starting_armor via level.startingarmoroverridefunc) would still be
// given and drawn while giving no protection. Starting armor is 0 (saved
// loads included), any armor is cleared after spawn with force_armor_zero()
// and the armor HUD is hidden with the omnvar zm_save uses for no-armor games
// ("ui_show_armor_global" = 0).
function private bo3_no_starting_armor( player )
{
    return [ 0, 0 ];
}

function private bo3_remove_armor_on_spawn()
{
    self endon( #"disconnect" );
    // Stock armor setup can run a frame or two after spawn: clear twice.
    wait 0.20;
    self force_armor_zero();
    self setclientomnvar( "ui_show_armor_global", 0 );
    wait 0.50;
    self force_armor_zero();
    self setclientomnvar( "ui_show_armor_global", 0 );
}

// =====================================================================
// BO3-COMPATIBLE: ARMOR WALL-BUYS BLOCKED
// =====================================================================
// The stock armor wall-buy (variant "armor", incl. wallbuy_zm_t10_armor_
// legendary = golden armor) keeps its own purchase even with armor off.
// The walls are bound the same way as armor walls normally are
// (Wallbuy::register_wallbuy_variant_spawn + set_interact_use/hint_callback),
// to a purchase that does nothing (no charge) and a hidden prompt.
function private bo3_armor_wall_use( player )
{
    return;
}

function private bo3_armor_wall_hint( wall, player )
{
    return { #string:&"", #type:"HINT_NOICON" };
}

// =====================================================================
// DEATH PERCEPTION "SIXTH SENSE" - NO ORANGE INDICATOR
// =====================================================================
// Verified in the BO7 dump (deathperception_augments.gsc, zm_player_damage.gsc):
//  - The indicator is watch_behind_thread(): a per-frame zombie scan started
//    from on_perk_get() ("zm_perk_obtained") that only drives
//    update_sixth_sense(): omnvar "ui_edge_glow" = 16 (orange screen-edge
//    glow) + scriptable part "sixthsense_audio" (warning sound).
//  - The augment's real effect (less damage from zombies behind you) is a
//    separate check in zm_player_damage.gsc that tests the augment and the
//    attacker direction on every hit. It does not use that thread.
//  - The thread ends on notify hash_39e453d8a791005f (only used for this,
//    stock on_perk_lost() sends it).
// So after every Death Perception grant the thread is ended at end of frame
// (after the stock callback started it, whatever the callback order), and
// the glow / sound are switched off once. No loop is added; the stock
// per-frame scan is removed. The damage reduction is untouched.
function private sixth_sense_no_glow( params )
{
    if ( !supported_mode() || !isplayer( self ) || !isdefined( params ) )
    {
        return;
    }
    if ( !( params.specialtyperk === "specialty_death_perception" ) )
    {
        return;
    }
    self endon( #"death_or_disconnect" );
    waittillframeend();
    self notify( #"hash_39e453d8a791005f" );
    self.var_12c1ab119730f01b = 0;
    self setclientomnvar( "ui_edge_glow", 0 );
    self setscriptablepartstate( "sixthsense_audio", "off", 0 );
}

// =====================================================================
// LGM-1 PaP IV - SAUCER STRIKE (level.cursed_lgm_strike_count ZOMBIES PER SHOT)
// =====================================================================
// Shots are counted from the player's weapon_fired notify (the same notify
// the stock LGM-1 script launches a squadron on). The first LGM-1 damage
// event after a shot (a saucer tick) starts one strike around the zombie it
// hit: the strike_count nearest normal / armored zombies within
// strike_radius (the hit zombie included) take a lethal LGM-1 hit, which
// goes through ww_instakill_damage (one-hit at PaP III+, killondamage for
// armored). Strike hits belong to the same shot, so they never start
// another strike.
function private install_lgm_strike()
{
    level.cursed_lgm_strike_count = 10;
    level.cursed_lgm_strike_radius = 400;
    level callback::add( #"player_spawned", &lgm_on_player_spawned );
}

function private lgm_on_player_spawned( params )
{
    if ( !supported_mode() || !isplayer( self ) )
    {
        return;
    }
    self thread lgm_shot_counter();
}

function private lgm_shot_counter()
{
    self notify( #"cursed_lgm_shot_counter" );
    self endon( #"cursed_lgm_shot_counter" );
    self endon( #"death_or_disconnect" );
    level endon( #"game_ended" );
    if ( !isdefined( self.cursed_lgm_shot ) )
    {
        self.cursed_lgm_shot = 0;
    }
    while ( true )
    {
        self waittill( #"weapon_fired", weapon );
        if ( isdefined( weapon ) && weapon.basename == "sat_ww_ruby_zm" )
        {
            self.cursed_lgm_shot = self.cursed_lgm_shot + 1;
        }
    }
}

// self = the zombie the saucer tick hit.
function private lgm_strike_check( attacker, weapon )
{
    shot = attacker.cursed_lgm_shot ?? 0;
    if ( attacker.cursed_lgm_strike_shot === shot )
    {
        return;
    }
    attacker.cursed_lgm_strike_shot = shot;
    level thread lgm_strike( self.origin, attacker, weapon );
}

// Runs a frame after the tick, outside the damage callback.
function private lgm_strike( origin, attacker, weapon )
{
    level endon( #"game_ended" );
    waitframe();
    if ( !isdefined( attacker ) || !isplayer( attacker ) || !isdefined( weapon ) )
    {
        return;
    }
    picked = [];
    for ( n = 0; n < level.cursed_lgm_strike_count; n++ )
    {
        best = undefined;
        best_dist = undefined;
        foreach ( ent in getaiarrayinradius( origin, level.cursed_lgm_strike_radius ) )
        {
            if ( !isdefined( ent ) || !isalive( ent ) || ent.team == attacker.team || arraycontains( picked, ent ) )
            {
                continue;
            }
            if ( !( ent.aicategory === "normal" ) || istrue( ent.damageshield ) || istrue( ent.ignore_ufogun ) )
            {
                continue;
            }
            dist = distancesquared( origin, ent.origin );
            if ( !isdefined( best_dist ) || dist < best_dist )
            {
                best = ent;
                best_dist = dist;
            }
        }
        if ( !isdefined( best ) )
        {
            break;
        }
        picked[ picked.size ] = best;
    }
    foreach ( ent in picked )
    {
        if ( isdefined( ent ) && isalive( ent ) )
        {
            ent dodamage( ent.health + 1, ent.origin, attacker, attacker, "MOD_RIFLE_BULLET", weapon, "torso_upper" );
        }
    }
}

// ---------------------------------------------------------------------------
// Mister Peeks Mayhem - Ray Gun / Ray Gun Mk 2 box chance reduced: a roll
// keeps them level.cursed_peeks_raygun_keep % of the time.
// "magicbox_used" runs in the same frame as setup_magicbox_weapon_array().
// On a failed keep roll, both Ray Guns get item limit 0 for this one frame,
// so the stock limit check (function_239d5db0d6aabc4c) re-rolls them from
// the normal weapon list. Limits are restored the next frame.
// ---------------------------------------------------------------------------
function private box_half_rayguns_peeks( params )
{
    if ( game_utility::getgametype() != "zm_rb_rh_mod" || !isdefined( level.a_magicbox_item_limits ) )
    {
        return;
    }
    if ( !isdefined( level.cursed_peeks_raygun_keep ) )
    {
        level.cursed_peeks_raygun_keep = 80;
    }
    if ( randomfloat( 100 ) < level.cursed_peeks_raygun_keep )
    {
        return;
    }
    // Ray Gun, Ray Gun Mk 2 (Mk 2 entry name is hashed in the dump).
    keys = [ %"itemspawnentry:zm_sat_item_weapon_pi_raygun", %"hash_613157257e008eff" ];
    saved = [];
    foreach ( i, key in keys )
    {
        if ( isdefined( level.a_magicbox_item_limits[ key ] ) )
        {
            saved[ i ] = level.a_magicbox_item_limits[ key ].itemmax;
            level.a_magicbox_item_limits[ key ].itemmax = 0;
        }
        else
        {
            level.a_magicbox_item_limits[ key ] = { #itemmax:0, #spawneditems:[] };
        }
    }
    level thread box_restore_raygun_limits( keys, saved );
}

function private box_restore_raygun_limits( keys, saved )
{
    waitframe();
    foreach ( i, key in keys )
    {
        if ( isdefined( saved[ i ] ) )
        {
            level.a_magicbox_item_limits[ key ].itemmax = saved[ i ];
        }
        else
        {
            level.a_magicbox_item_limits[ key ] = undefined;
        }
    }
}
