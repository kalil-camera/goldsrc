#include <amxmodx>
#include <engine>
#include <fakemeta>
#include <cstrike>

static const PLUGIN[] = "Show Teammate Equips";
static const VERSION[] = "0.1";
static const AUTHOR[] = " ";

#define REAPI_COMPATIBILITY

#if defined REAPI_COMPATIBILITY
#include <reapi>
#else
static const szMessageGameRestart[] = "#Game_will_restart_in";
#endif

#pragma semicolon 1

#if !defined client_disconnected
#define client_disconnected client_disconnect
#endif

#if !defined MAX_PLAYERS
#define MAX_PLAYERS 32
#endif

#if !defined EF_NOINTERP
#define EF_NOINTERP 32
#endif

// Runtime loops use the engine-reported slot count instead of assuming that
// every environment is permanently capped at 32. The compile-time MAX_PLAYERS
// remains the array capacity; engines/AMXX forks that expose 64/128 slots only
// need that capacity definition adjusted, not the adaptive-LOD algorithm.
#define IsPlayer(%0)            (1 <= %0 <= g_iMaxPlayers)

const MONEY_SPRITES = 5;
// A Pawn cell is a signed 32-bit integer, so 10 digit entities cover every
// positive health value get_user_health() can represent without an arbitrary
// 3/5-digit HUD cap. The first five are still reused by freezetime money.
const HEALTH_SPRITES = 10;
const WEAPON_SPRITES = 7;

// set_status.spr logical frame map. IDs 0..34 intentionally preserve the
// mapping used by set_status.spr. Unique HUD
// digits are appended at 35..44 so weapon/status IDs do not move.
enum {
    STATUS_FRAME_BLANK = 0,
    STATUS_FRAME_CASH,
    STATUS_FRAME_HEALTH,
    STATUS_FRAME_ARROW,
    STATUS_FRAME_KEVLAR,
    STATUS_FRAME_VESTHELM,
    STATUS_FRAME_C4,
    STATUS_FRAME_DEFUSE,
    STATUS_FRAME_HEGRENADE,
    STATUS_FRAME_FLASHBANG,
    STATUS_FRAME_SMOKEGRENADE,
    STATUS_FRAME_USP,
    STATUS_FRAME_SCOUT,
    STATUS_FRAME_XM1014,
    STATUS_FRAME_MAC10,
    STATUS_FRAME_AUG,
    STATUS_FRAME_ELITE,
    STATUS_FRAME_FIVESEVEN,
    STATUS_FRAME_UMP45,
    STATUS_FRAME_SG550,
    STATUS_FRAME_GALIL,
    STATUS_FRAME_FAMAS,
    STATUS_FRAME_P228,
    STATUS_FRAME_GLOCK18,
    STATUS_FRAME_AWP,
    STATUS_FRAME_MP5NAVY,
    STATUS_FRAME_M249,
    STATUS_FRAME_M3,
    STATUS_FRAME_M4A1,
    STATUS_FRAME_TMP,
    STATUS_FRAME_G3SG1,
    STATUS_FRAME_DEAGLE,
    STATUS_FRAME_SG552,
    STATUS_FRAME_AK47,
    STATUS_FRAME_P90,
    STATUS_FRAME_DIGIT_0,
    STATUS_FRAME_DIGIT_1,
    STATUS_FRAME_DIGIT_2,
    STATUS_FRAME_DIGIT_3,
    STATUS_FRAME_DIGIT_4,
    STATUS_FRAME_DIGIT_5,
    STATUS_FRAME_DIGIT_6,
    STATUS_FRAME_DIGIT_7,
    STATUS_FRAME_DIGIT_8,
    STATUS_FRAME_DIGIT_9,
    // Skull + crossed bones from the user-provided original 640hud1.spr.
    // It is used as the percentage-health icon; IDs 0..44 stay untouched.
    STATUS_FRAME_PERCENT
};

static const szStatusSprite[] = "sprites/set_status.spr"; // 46 frames, fixed 64x32; frame 45 = percentage skull
static const szDebugBeamSprite[] = "sprites/laserbeam.spr";

static const iPistols[] = {
    CSW_P228, CSW_ELITE, CSW_FIVESEVEN, CSW_USP, CSW_GLOCK18, CSW_DEAGLE
};

static const iPrimaryWeapons[] = {
    CSW_SCOUT, CSW_XM1014, CSW_MAC10, CSW_AUG, CSW_UMP45, CSW_SG550,
    CSW_GALIL, CSW_FAMAS, CSW_AWP, CSW_MP5NAVY, CSW_M249, CSW_M3,
    CSW_M4A1, CSW_TMP, CSW_G3SG1, CSW_SG552, CSW_AK47, CSW_P90
};

// set_status.spr uses one 64x32 frame for every visual. The graphic inside each
// frame is centered; AMXX now provides the layout that the old 160x64/112x64
// canvases used to encode as empty black pixels.
//
// These values were reconstructed from the ACTUAL visible centers in the old
// 10000/1000/100/10/1.spr, cash.spr, arrow.spr, weap.spr and weap2.spr.
// AddToFullPack applies them in each viewer's camera plane.
static const Float:g_fMoneyDigitX[MONEY_SPRITES] = { -35.0, -17.0, 1.0, 19.0, 37.0 };
const Float:MONEY_ICON_X = -57.5;
// Persistent health preserves the existing first-digit position/spacing, then
// continues the same row for 4+ digits instead of clamping the value to 999.
const Float:HEALTH_DIGIT_START_X = -35.0;
const Float:HEALTH_DIGIT_STEP_X = 18.0;

// Old weap.spr logical columns: primary left, secondary right; grenade row has
// HE / Flash / Smoke. Since the small deathnotice art is centered in 64x32,
// these offsets reproduce the old layout without baking placement into pixels.
const Float:FREEZE_PRIMARY_X = -25.5;
const Float:FREEZE_SECONDARY_X = 25.5;
const Float:FREEZE_HE_X = -27.5;
const Float:FREEZE_FLASH_X = 0.5;
const Float:FREEZE_SMOKE_X = 28.5;
const Float:FREEZE_ARMOR_X = -16.5;
const Float:FREEZE_OBJECTIVE_X = 19.0;
// Positive = camera up, negative = camera down. These rows are only for
// the freezetime equipment layout.
const Float:MONEY_ROW_Y = 4.0;
const Float:ARROW_ROW_Y = -21.0;
const Float:WEAPON_ROW_Y = -19.5;
const Float:GRENADE_ROW_Y = 2.5;
const Float:ARMOR_ROW_Y = 22.0;
const Float:OBJECTIVE_ROW_Y = 21.0;

// Persistent CS2-style HUD: ONE rigid 2D block. The arrow is the matrix
// origin and sits directly above the player's head. Every other element is
// expressed only as an X/Y offset from that arrow; no element has a separate
// world-space Z origin anymore. This is what keeps weapon -> health -> arrow
// solid at every distance and through every wall projection.
const Float:PERSISTENT_BLOCK_ANCHOR_OFFSET = 34.0;
const Float:PERSISTENT_ARROW_X = 0.0;
const Float:PERSISTENT_ARROW_Y = 0.0;
const Float:PERSISTENT_HEALTH_Y = 25.0;
const Float:PERSISTENT_WEAPON_Y = 52.0;
const Float:PERSISTENT_OBJECTIVE_Y = 78.0;

// Compact per-observer row centers. The first four preserve the established
// geometry exactly when arrow+health+weapon+objective are all present. Missing
// rows consume no slot; FULL+ extends upward without reserving empty space.
static const Float:g_fCompactRowY[] = {0.0, 25.0, 52.0, 78.0, 104.0, 130.0, 156.0};

static g_iPlayerMoneySprites[MAX_PLAYERS + 1][HEALTH_SPRITES];
static g_iPlayerWeaponsSprites[MAX_PLAYERS + 1][WEAPON_SPRITES];
static g_iPlayerDolarSign[MAX_PLAYERS + 1];
static g_iPlayerArrow[MAX_PLAYERS + 1];
static g_iMaxPlayers;
// Do not use a 32-bit player bitmask here: it aliases slot 33 with slot 1.
// A boolean table keeps connection bookkeeping compatible with wider forks.
static bool:g_bIsConnected[MAX_PLAYERS + 1];
static CsTeams:g_iPlayerTeam[MAX_PLAYERS + 1];

// Percentage mode baseline. A new round/team change resets the reference.
// During normal SET health refreshes the reference may only move UP: if another
// gameplay plugin awards a new record HP value (2500 -> 5000), that new maximum
// becomes 100% without adding a polling timer or hardcoding the other plugin.
static g_iHealthBaseline[MAX_PLAYERS + 1];
static g_iHealthBaselineRetries[MAX_PLAYERS + 1];
static g_iCachedHealthDisplayValue[MAX_PLAYERS + 1];

static const szControllerClass[] = "equipment_sprites_controller";
static g_iController;
static Float:g_fFreezeEndTime;
static bool:g_bFreezeFinished;

#if !defined SET_MAX_TRACKED_EDICTS
#define SET_MAX_TRACKED_EDICTS 8192
#endif
const MAX_TRACKED_EDICTS = SET_MAX_TRACKED_EDICTS;

enum PersistentMarkerType {
    MARKER_NONE = 0,
    MARKER_ARROW,
    MARKER_WEAPON,
    MARKER_OBJECTIVE,
    MARKER_HEALTH
};

static g_iMarkerOwnerByEnt[MAX_TRACKED_EDICTS + 1];
static PersistentMarkerType:g_iMarkerTypeByEnt[MAX_TRACKED_EDICTS + 1];
static bool:g_bPersistentEntActive[MAX_TRACKED_EDICTS + 1];
static bool:g_bMarkerLayoutActive[MAX_TRACKED_EDICTS + 1];
static Float:g_fMarkerScreenX[MAX_TRACKED_EDICTS + 1];
static Float:g_fMarkerScreenY[MAX_TRACKED_EDICTS + 1];
static g_iAddToFullPackPreForward = -1;
static g_iAddToFullPackPostForward = -1;
static g_iCheckVisibilityForward = -1;
static g_iTraceHandle;
static g_iDebugBeamModel;

// Cached first blocking plane for each viewer -> teammate pair. SET treats
// the projected persistent indicator as one rigid camera-facing block: one
// anchor, one depth ratio and one scale. Individual env_sprites are still sent
// separately, but their centers are rebuilt from fixed offsets around the same
// projected anchor instead of following independent camera rays.
static Float:g_fProjectionPlanePoint[MAX_PLAYERS + 1][MAX_PLAYERS + 1][3];
static Float:g_fProjectionPlaneNormal[MAX_PLAYERS + 1][MAX_PLAYERS + 1][3];
static Float:g_fNextHudUpdate;
static Float:g_fNextDebugBeamUpdate;

// FM_CheckVisibility does not tell us which client is currently receiving the
// packet. These values are armed by AddToFullPack PRE for exactly one
// host/entity pair, then consumed while the game DLL performs its PVS test.
static g_iVisibilityContextEnt;
static g_iVisibilityContextHost;
static bool:g_bForceCurrentVisibility;

static bool:g_bPersistentPhase;
static Float:g_fNextVisibilityUpdate;
static bool:g_bProjected[MAX_PLAYERS + 1][MAX_PLAYERS + 1];
// One common perspective ratio per viewer -> teammate pair. This
// ratio moves one block anchor toward the viewer. Every marker is then rebuilt
// around that anchor in the viewer camera plane, which keeps weapon -> health ->
// arrow ordering rigid even on oblique walls.
static Float:g_fProjectionRatio[MAX_PLAYERS + 1][MAX_PLAYERS + 1];
static Float:g_fVisibleScaleFactor[MAX_PLAYERS + 1][MAX_PLAYERS + 1];
static Float:g_fViewerCameraOrigin[MAX_PLAYERS + 1][3];
static Float:g_fViewerCameraForward[MAX_PLAYERS + 1][3];
static Float:g_fViewerCameraUp[MAX_PLAYERS + 1][3];
static Float:g_fViewerCameraRight[MAX_PLAYERS + 1][3];
static Float:g_fViewerBasisTime[MAX_PLAYERS + 1];
static Float:g_fClientChaseDistance[MAX_PLAYERS + 1];
static bool:g_bHasClientViewAngles[MAX_PLAYERS + 1];
static Float:g_fClientViewAngles[MAX_PLAYERS + 1][3];
// Extreme near-wall fallback state. Normal common-depth projection is preserved
// unless the projected sprite would sit too close to the camera or require a
// sub-resolution entity scale. In that case all marker sprites for the pair
// use the same safe perspective ratio, and kRenderGlow is enabled only when
// the safe point must sit on/behind the blocking plane.
static bool:g_bUseSafeProjection[MAX_PLAYERS + 1][MAX_PLAYERS + 1];
static bool:g_bProjectionNeedsNoZ[MAX_PLAYERS + 1][MAX_PLAYERS + 1];
static Float:g_fPersistentAnchor[MAX_PLAYERS + 1][3];

// Adaptive network-quality system -------------------------------------------
// Network detail is PER OBSERVER -> OWNER. "Target" is the best complete block
// allowed by server policy, that observer's preferences and the sprite budget.
// "Current" is what has actually been admitted so far. Reductions are immediate;
// promotions are ramped in complete block steps, nearest observer-camera first.
enum NetPairLod {
    NET_LOD_NONE = 0,
    NET_LOD_MINIMAL,  // arrow only
    NET_LOD_REDUCED,  // + preferred weapon + objective
    NET_LOD_FULL,     // + health
    NET_LOD_FULLPLUS  // + both weapons + grenades (persistent)
};

static NetPairLod:g_iNetPairLod[MAX_PLAYERS + 1][MAX_PLAYERS + 1];
static NetPairLod:g_iNetTargetLod[MAX_PLAYERS + 1][MAX_PLAYERS + 1];
static bool:g_bNetDegraded[MAX_PLAYERS + 1];
static g_iNetRequestedSprites[MAX_PLAYERS + 1];
static g_iNetTargetSprites[MAX_PLAYERS + 1];
static g_iNetAllowedSprites[MAX_PLAYERS + 1];
static g_iNetRampCredit[MAX_PLAYERS + 1];
static g_iNetFullPlusPairs[MAX_PLAYERS + 1];
static g_iNetFullPairs[MAX_PLAYERS + 1];
static g_iNetReducedPairs[MAX_PLAYERS + 1];
static g_iNetMinimalPairs[MAX_PLAYERS + 1];
static g_iNetHiddenPairs[MAX_PLAYERS + 1];
static Float:g_fNextNetLodUpdate;
static Float:g_fNextNetRampUpdate;

// Owner-side CONTENT is deliberately decoupled from spatial motion.
// The anchor/real entity origins keep following players at the normal 20 Hz
// cadence, while inventory/health/frame changes are refreshed in small owner
// batches. This spreads entity-state deltas over time instead of making every
// visible block change in the same server frame.
static Float:g_fNextNetContentUpdate;
static bool:g_bNetContentInitialized[MAX_PLAYERS + 1];
static bool:g_bNetContentUrgent[MAX_PLAYERS + 1];
static Float:g_fNetContentLastUpdate[MAX_PLAYERS + 1];
static g_iNetContentCycleOwners[MAX_PLAYERS];
static Float:g_fNetContentCycleDistance[MAX_PLAYERS];
static g_iNetContentCycleCount;
static g_iNetContentCycleCursor;
static Float:g_fNetContentCycleStart;
static g_iNetContentLastBatch;

// Per-observer marker-sent mask. Each owner has only 19 SET entities, so one
// Pawn cell is enough. This lets a marker that was visible receive ONE explicit
// hidden-state update before PRE starts suppressing it entirely. Without this,
// a disappearing second health digit can remain stale client-side (e.g. 9 -> 90).
static g_iNetSentMarkerMask[MAX_PLAYERS + 1][MAX_PLAYERS + 1];

// Client-side requested detail. These settings can only REMOVE information:
// server CVAR policy and network LOD remain authoritative.
static NetPairLod:g_iClientDetailCap[MAX_PLAYERS + 1];
static g_iClientWeaponsMode[MAX_PLAYERS + 1]; // 0 off | 1 primary only | 2 normal/both when FULL+
static bool:g_bClientShowArrow[MAX_PLAYERS + 1];
static bool:g_bClientShowHealth[MAX_PLAYERS + 1];
static bool:g_bClientShowGrenades[MAX_PLAYERS + 1];
static bool:g_bClientShowObjective[MAX_PLAYERS + 1];

static g_pNetAdaptive;
static g_pNetSpriteBudget;
static g_pNetRecoverMargin;
static g_pNetUpdateInterval;
static g_pNetRampSprites;
static g_pNetRampInterval;
static g_pNetContentScheduler;
static g_pNetContentBatch;
static g_pNetContentInterval;
// Connection-quality feedback is a second, per-observer ceiling below
// se_net_sprite_budget. It never grants more detail than the server budget; it
// only lowers the effective budget when that client's own ping/loss degrades.
static g_pNetQualityAdaptive;
static g_pNetQualityInterval;
static g_pNetPingSoftDelta;
static g_pNetPingHardDelta;
static g_pNetLossSoft;
static g_pNetLossHard;
static g_pNetQualityStepDown;
static g_pNetQualityStepUp;
static g_pNetQualityRecoverSamples;
static g_pNetQualityMinBudget;

static g_iNetAdaptive = 1;
static g_iNetSpriteBudget = 96;
static g_iNetRecoverMargin = 16;
static Float:g_fNetUpdateInterval = 0.50;
static g_iNetRampSprites = 8;
static Float:g_fNetRampInterval = 0.10;
static g_iNetContentScheduler = 1;
static g_iNetContentBatch = 3;
static Float:g_fNetContentInterval = 0.10;
static g_iNetQualityAdaptive = 1;
static Float:g_fNetQualityInterval = 1.00;
static g_iNetPingSoftDelta = 20;
static g_iNetPingHardDelta = 40;
static g_iNetLossSoft = 1;
static g_iNetLossHard = 3;
static g_iNetQualityStepDown = 8;
static g_iNetQualityStepUp = 8;
static g_iNetQualityRecoverSamples = 5;
static g_iNetQualityMinBudget = 32;
static Float:g_fNextNetQualityUpdate;

enum NetQualityState {
    NET_QUALITY_GOOD = 0,
    NET_QUALITY_SOFT,
    NET_QUALITY_HARD
};

static bool:g_bNetQualityInitialized[MAX_PLAYERS + 1];
static NetQualityState:g_iNetQualityState[MAX_PLAYERS + 1];
static g_iNetQualityEffectiveBudget[MAX_PLAYERS + 1];
static g_iNetQualityGoodSamples[MAX_PLAYERS + 1];
static Float:g_fNetQualityPingAverage[MAX_PLAYERS + 1];
static Float:g_fNetQualityPingBaseline[MAX_PLAYERS + 1];
static Float:g_fNetQualityLossAverage[MAX_PLAYERS + 1];

const Float:INITIAL_THINK_DELAY = 0.2;
const Float:NORMAL_UPDATE_INTERVAL = 1.0;
const Float:PERSISTENT_UPDATE_INTERVAL = 0.05;
const Float:MIN_WALL_FACING = 0.333333;
const Float:MIN_PROJECTED_DISTANCE = 2.0;
// env_sprite becomes unstable when its projected origin is virtually inside
// the camera. Beams do not share that renderer limitation. SET keeps normal
// projection, but raises only the pathological near-wall
// case to a safe distance and uses no-Z rendering if that point crosses the
// wall plane.
const Float:SAFE_PROJECTED_SPRITE_DISTANCE = 8.0;
// GoldSrc delta-compresses entity_state scale at roughly 1/256 precision.
// Avoid asking an env_sprite to use a scale that can collapse to zero on the
// client; this is independent from how tiny a normal distant sprite APPEARS.
const Float:MIN_SAFE_ENTITY_SCALE = 0.0040;

// Every frame in set_status.spr is 64x32. These
// half-extents let the wall projection protect the COMPLETE rigid HUD plate,
// not only the center of its arrow anchor.  The extra clearance is enabled
// only once distance scaling is active; close-range markers keep the original
// center-only wall offset because they do not need the additional push.
const Float:STATUS_FRAME_HALF_WIDTH = 32.0;
const Float:STATUS_FRAME_HALF_HEIGHT = 16.0;
const Float:RIGID_CLEARANCE_SCALE_EPSILON = 0.0001;

const Float:DEBUG_BEAM_UPDATE_INTERVAL = 0.30;
const DEBUG_MAX_HUD_LABELS = 4;
const Float:HUD_CHAR_HALF_WIDTH = 0.0060;
const Float:DEBUG_LABEL_COLLISION_X = 0.075;
const Float:DEBUG_LABEL_COLLISION_Y = 0.055;
const DEBUG_BEAM_WIDTH = 150;

const TASK_SYNC_TEAM_BASE = 4200;
const TASK_HEALTH_BASELINE_BASE = 4300;
const Float:HEALTH_BASELINE_CAPTURE_DELAY = 0.35;
const Float:HEALTH_BASELINE_RETRY_DELAY = 0.10;
const HEALTH_BASELINE_MAX_RETRIES = 50;

// GoldSrc observer modes (pev_iuser1). The chase camera itself is calculated
// client-side, so the server reconstructs it from the observer mode/target and
// the client's cl_chasedist value.
enum {
    SET_OBS_NONE = 0,
    SET_OBS_CHASE_LOCKED,
    SET_OBS_CHASE_FREE,
    SET_OBS_ROAMING,
    SET_OBS_IN_EYE,
    SET_OBS_MAP_FREE,
    SET_OBS_MAP_CHASE
};

const Float:DEFAULT_CHASE_DISTANCE = 112.0;
const Float:MIN_CHASE_DISTANCE = 32.0;
const Float:MAX_CHASE_DISTANCE = 256.0;
const Float:CHASE_WALL_PUSH = 4.0;

static const g_iTeamColorT[3] = {255, 160, 0};
static const g_iTeamColorCT[3] = {80, 160, 255};
static const g_iLowHealthColor[3] = {255, 0, 0};
static const g_iEnemyArrowColor[3] = {255, 0, 0};

enum DisplayCvars {
    CVAR_SHOW_WEAPONS,
    CVAR_SHOW_MONEY,
    CVAR_SHOW_GRENADES,
    CVAR_SHOW_ARROW,
    CVAR_SHOW_ARMOR,
    CVAR_SHOW_TEAMMATES_ALWAYS,
    CVAR_SHOW_ARROW_MODE,
    CVAR_SHOW_TEAMMATES_WEAPON,
    CVAR_SHOW_TEAMMATES_OBJECTIVE,
    CVAR_SHOW_TEAMMATES_HEALTH,
    CVAR_SHOW_TEAMMATES_NAME,
    CVAR_TEAMMATE_NAME_MAX_DISTANCE,
    CVAR_TEAMMATE_NAME_UPDATE_INTERVAL,
    CVAR_TEAMMATE_NAME_SCREEN_GAP,
    CVAR_SHOW_TEAMMATES_THROUGH_WALLS,
    CVAR_WALL_MARKER_OFFSET,
    CVAR_WALL_VERTICAL_OFFSET,
    CVAR_WALL_CHECK_INTERVAL,
    CVAR_WALL_SCALE_MULTIPLIER,
    CVAR_WALL_SCALE_MIN_FACTOR,
    CVAR_WALL_SCALE_MAX_FACTOR,
    CVAR_VISIBLE_SCALE_DISTANCE_START,
    CVAR_VISIBLE_SCALE_DISTANCE_END,
    CVAR_VISIBLE_SCALE_MAX_FACTOR,
    CVAR_HEALTH_LOW_THRESHOLD,
    CVAR_HEALTH_DISPLAY_MODE,
    CVAR_DEBUG_PROJECTION,
    CVAR_SPRITE_SCALE
};

static g_pDisplayCvar[DisplayCvars];
static g_iShowWeapons;
static g_iShowMoney;
static g_iShowGrenades;
static g_iShowArrow;
static g_iShowArmor;
static g_iShowTeammatesAlways;
static g_iShowArrowMode;
static g_iShowTeammatesWeapon;
static g_iShowTeammatesObjective;
static g_iShowTeammatesHealth;
static g_iShowTeammatesName;
static Float:g_fTeammateNameMaxDistance;
static Float:g_fTeammateNameUpdateInterval;
static Float:g_fTeammateNameScreenGap;
static g_iShowTeammatesThroughWalls;
static Float:g_fWallMarkerOffset;
static Float:g_fWallVerticalOffset;
static Float:g_fWallCheckInterval;
static Float:g_fWallScaleMultiplier;
static Float:g_fWallScaleMinFactor;
static Float:g_fWallScaleMaxFactor;
static Float:g_fVisibleScaleDistanceStart;
static Float:g_fVisibleScaleDistanceEnd;
static Float:g_fVisibleScaleMaxFactor;
static g_iHealthLowThreshold;
static g_iHealthDisplayMode;
static g_iDebugProjection;
static Float:g_fSpriteScale;

enum SpriteColors {
    CVAR_SPRITE_WEAPON_COLOR,
    CVAR_SPRITE_MONEY_COLOR
};

static g_pColorCvar[SpriteColors];
static g_pTeammateColorCvar;
static bool:g_bTeammateColorByTeam = true;
static g_iCustomTeammateColor[3] = {255, 255, 255};

public plugin_precache()
{
    precache_model(szStatusSprite);
    g_iDebugBeamModel = precache_model(szDebugBeamSprite);
}

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);
    register_dictionary("ShowEquipamentTeammates.txt");

    g_iMaxPlayers = get_maxplayers();
    if (g_iMaxPlayers > MAX_PLAYERS) {
        server_print("%L %L", LANG_SERVER, "SET_TAG", LANG_SERVER,
            "SET_WARNING_MAX_PLAYERS", g_iMaxPlayers, MAX_PLAYERS);
        g_iMaxPlayers = MAX_PLAYERS;
    }

    register_concmd("amx_set_netstatus", "CmdSetNetStatus", ADMIN_CVAR);

    // Per-client detail controls. They only reduce what the server allows.
    register_clcmd("se_detail", "CmdClientDetail");
    register_clcmd("se_view", "CmdClientView");

    register_event("HLTV", "EventRoundStart", "a", "1=0", "2=0");
    register_event("DeathMsg", "EventDeathMsg", "a");
    register_event("TeamInfo", "EventTeamInfo", "a");
    register_think(szControllerClass, "ShowSprites");
    register_forward(FM_CmdStart, "ForwardCmdStart");

#if defined REAPI_COMPATIBILITY
    RegisterHookChain(RG_RoundEnd, "fwdRoundEnd", false);
#else
    register_logevent("fwdRoundEnd", 2, "1=Round_End");
    register_message(get_user_msgid("TextMsg"), "TextMsgMessage");
#endif

    g_pDisplayCvar[CVAR_SHOW_WEAPONS] = register_cvar("se_show_weapons", "1");
    g_pDisplayCvar[CVAR_SHOW_MONEY] = register_cvar("se_show_money", "1");
    g_pDisplayCvar[CVAR_SHOW_GRENADES] = register_cvar("se_show_grenades", "1");
    g_pDisplayCvar[CVAR_SHOW_ARROW] = register_cvar("se_show_arrow", "1");
    g_pDisplayCvar[CVAR_SHOW_ARMOR] = register_cvar("se_show_armortype", "1");
    g_pDisplayCvar[CVAR_SHOW_TEAMMATES_ALWAYS] = register_cvar("se_show_teammates_always", "0");
    g_pDisplayCvar[CVAR_SHOW_ARROW_MODE] = register_cvar("se_show_arrow_mode", "1"); // 0 = both teams | 1 = teammates only | 2 = enemies only
    g_pDisplayCvar[CVAR_SHOW_TEAMMATES_WEAPON] = register_cvar("se_show_teammates_weapon", "1");
    g_pDisplayCvar[CVAR_SHOW_TEAMMATES_OBJECTIVE] = register_cvar("se_show_teammates_objective", "1");
    g_pDisplayCvar[CVAR_SHOW_TEAMMATES_HEALTH] = register_cvar("se_show_teammates_health", "1");
    g_pDisplayCvar[CVAR_SHOW_TEAMMATES_NAME] = register_cvar("se_show_teammates_name", "0");
    g_pDisplayCvar[CVAR_TEAMMATE_NAME_MAX_DISTANCE] = register_cvar("se_teammate_name_max_distance", "2000.0");
    g_pDisplayCvar[CVAR_TEAMMATE_NAME_UPDATE_INTERVAL] = register_cvar("se_teammate_name_update_interval", "0.20");
    g_pDisplayCvar[CVAR_TEAMMATE_NAME_SCREEN_GAP] = register_cvar("se_teammate_name_screen_gap", "0.035");
    g_pDisplayCvar[CVAR_SHOW_TEAMMATES_THROUGH_WALLS] = register_cvar("se_show_teammates_through_walls", "0");
    g_pDisplayCvar[CVAR_WALL_MARKER_OFFSET] = register_cvar("se_wall_marker_offset", "8.0");
    g_pDisplayCvar[CVAR_WALL_VERTICAL_OFFSET] = register_cvar("se_wall_vertical_offset", "0.0");
    g_pDisplayCvar[CVAR_WALL_CHECK_INTERVAL] = register_cvar("se_wall_check_interval", "0.001");
    g_pDisplayCvar[CVAR_WALL_SCALE_MULTIPLIER] = register_cvar("se_wall_scale_multiplier", "1.00");
    g_pDisplayCvar[CVAR_WALL_SCALE_MIN_FACTOR] = register_cvar("se_wall_scale_min_factor", "0.001");
    g_pDisplayCvar[CVAR_WALL_SCALE_MAX_FACTOR] = register_cvar("se_wall_scale_max_factor", "16.0");
    g_pDisplayCvar[CVAR_VISIBLE_SCALE_DISTANCE_START] = register_cvar("se_visible_scale_distance_start", "500.0");
    g_pDisplayCvar[CVAR_VISIBLE_SCALE_DISTANCE_END] = register_cvar("se_visible_scale_distance_end", "5000.0");
    g_pDisplayCvar[CVAR_VISIBLE_SCALE_MAX_FACTOR] = register_cvar("se_visible_scale_max_factor", "14.0");
    g_pDisplayCvar[CVAR_HEALTH_LOW_THRESHOLD] = register_cvar("se_health_low_threshold", "25");
    // 0 = clamp to 999 | 1 = dynamic 0..100 percentage | 2 = real health
    g_pDisplayCvar[CVAR_HEALTH_DISPLAY_MODE] = register_cvar("se_health_display_mode", "0");
    g_pDisplayCvar[CVAR_DEBUG_PROJECTION] = register_cvar("se_debug_projection", "0");
    g_pDisplayCvar[CVAR_SPRITE_SCALE] = register_cvar("se_sprites_scale", "0.25");

    // Conservative first calibration point. This budget counts only SET
    // persistent sprite entities; other game/plugin traffic still shares the
    // client datagram, so the safe value is intentionally configurable.
    g_pNetAdaptive = register_cvar("se_net_adaptive", "1");
    g_pNetSpriteBudget = register_cvar("se_net_sprite_budget", "96");
    g_pNetRecoverMargin = register_cvar("se_net_recover_margin", "16");
    g_pNetUpdateInterval = register_cvar("se_net_update_interval", "0.50");
    g_pNetRampSprites = register_cvar("se_net_ramp_sprites", "8");
    g_pNetRampInterval = register_cvar("se_net_ramp_interval", "0.10");
    // Semantic-content scheduler. Position/projection still runs at SET's fast
    // cadence; these CVARs only stagger health/inventory/frame refreshes.
    g_pNetContentScheduler = register_cvar("se_net_content_scheduler", "1");
    g_pNetContentBatch = register_cvar("se_net_content_batch", "3");
    g_pNetContentInterval = register_cvar("se_net_content_interval", "0.10");

    // Per-observer connection-quality feedback. Ping thresholds are DELTAS over
    // that client's learned baseline, so a stable 100 ms Internet player is not
    // penalized merely for being geographically distant. Loss remains absolute.
    g_pNetQualityAdaptive = register_cvar("se_net_quality_adaptive", "1");
    g_pNetQualityInterval = register_cvar("se_net_quality_interval", "1.00");
    g_pNetPingSoftDelta = register_cvar("se_net_ping_soft_delta", "20");
    g_pNetPingHardDelta = register_cvar("se_net_ping_hard_delta", "40");
    g_pNetLossSoft = register_cvar("se_net_loss_soft", "1");
    g_pNetLossHard = register_cvar("se_net_loss_hard", "3");
    g_pNetQualityStepDown = register_cvar("se_net_quality_step_down", "8");
    g_pNetQualityStepUp = register_cvar("se_net_quality_step_up", "8");
    g_pNetQualityRecoverSamples = register_cvar("se_net_quality_recover_samples", "5");
    g_pNetQualityMinBudget = register_cvar("se_net_quality_min_budget", "32");

    g_pColorCvar[CVAR_SPRITE_WEAPON_COLOR] = register_cvar("se_sprite_color_weapons", "255255255");
    g_pColorCvar[CVAR_SPRITE_MONEY_COLOR] = register_cvar("se_sprite_color_money", "000255000");

    // One CS2-style persistent status color control. "team" gives T orange
    // and CT blue. A RRRGGGBBB value applies a custom teammate color to active
    // players; observers always retain owner-team colors so T/CT cannot mix.
    g_pTeammateColorCvar = register_cvar("se_sprite_color_teammates", "team");

    g_iTraceHandle = create_tr2();
}

public plugin_end()
{
    if (g_iTraceHandle)
        free_tr2(g_iTraceHandle);
}

public plugin_cfg()
{
    if (is_plugin_loaded("Pause Plugins") != -1)
        server_cmd("amx_pausecfg add ^"%s^"", PLUGIN);
}

#if defined REAPI_COMPATIBILITY
public fwdRoundEnd(WinStatus:status, ScenarioEventEndRound:event, Float:tmDelay)
{
    // Keep persistent markers visible during the round-end delay.
}
#else
public fwdRoundEnd()
{
    // Keep persistent markers visible during the round-end delay.
}

public TextMsgMessage()
{
    static szMsg[22];
    get_msg_arg_string(2, szMsg, charsmax(szMsg));

    if (equal(szMsg, szMessageGameRestart))
        StopRoundDisplay();
}
#endif

public EventRoundStart()
{
    StopRoundDisplay();
    CacheDisplaySettings();
    ApplyScaleToAllSprites();

    new Float:fFreezeTime = get_cvar_float("mp_freezetime");
    if (fFreezeTime < 0.0)
        fFreezeTime = 0.0;

    g_fFreezeEndTime = get_gametime() + fFreezeTime;
    g_bFreezeFinished = (fFreezeTime <= 0.0);
    g_bPersistentPhase = g_bFreezeFinished;
    g_fNextVisibilityUpdate = 0.0;
    g_fNextHudUpdate = 0.0;
    g_fNextDebugBeamUpdate = 0.0;
    g_fNextNetLodUpdate = 0.0;
    g_fNextNetRampUpdate = 0.0;
    g_fNextNetContentUpdate = 0.0;
    g_fNextNetQualityUpdate = 0.0;
    CacheNetSettings();
    ResetAllNetLod();
    ResetNetContentScheduler();

    // A new round always establishes a new 100% reference. This prevents a
    // previous round (for example 1500 HP) from making a new 100 HP spawn look
    // like ~7%. Capture is delayed so spawn/other plugins can finish first.
    for (new id = 1; id <= g_iMaxPlayers; id++) {
        if (g_bIsConnected[id])
            ScheduleHealthBaselineCapture(id);
    }

    if (g_bFreezeFinished && !HasPersistentDisplayEnabled())
        return;

    EnablePersistentVisibilityForwards();
    CreateController();
}

public EventDeathMsg()
{
    new id = read_data(2);
    if (IsPlayer(id)) {
        HidePlayerSprites(id);
        MarkNetContentUrgent(id);
    }
}

public EventTeamInfo()
{
    new id = read_data(1);
    if (!IsPlayer(id))
        return;

    new CsTeams:iOldTeam = g_iPlayerTeam[id];

    static szTeam[2];
    read_data(2, szTeam, charsmax(szTeam));

    switch (szTeam[0]) {
        case 'T': g_iPlayerTeam[id] = CS_TEAM_T;
        case 'C': g_iPlayerTeam[id] = CS_TEAM_CT;
        case 'S': g_iPlayerTeam[id] = CS_TEAM_SPECTATOR;
        default: g_iPlayerTeam[id] = CS_TEAM_UNASSIGNED;
    }

    if (g_iPlayerTeam[id] != iOldTeam) {
        if (g_iPlayerTeam[id] == CS_TEAM_T || g_iPlayerTeam[id] == CS_TEAM_CT)
            ScheduleHealthBaselineCapture(id);
        else
            ClearHealthBaseline(id);

        MarkNetContentUrgent(id);
    }

    g_fNextVisibilityUpdate = 0.0;
    g_fNextNetLodUpdate = 0.0;
    g_fNextNetRampUpdate = 0.0;
}

public client_putinserver(id)
{
    g_bIsConnected[id] = true;

    // client_putinserver can fire before Counter-Strike has allocated the
    // player's private data (especially for bots). Calling cs_get_user_team()
    // here can therefore throw "Invalid player (no private data)".
    g_iPlayerTeam[id] = CS_TEAM_UNASSIGNED;
    g_iHealthBaseline[id] = 0;
    g_iHealthBaselineRetries[id] = 0;
    g_iCachedHealthDisplayValue[id] = 0;
    g_bNetContentInitialized[id] = false;
    g_bNetContentUrgent[id] = false;
    g_fNetContentLastUpdate[id] = 0.0;
    ResetNetQualityForPlayer(id);
    ApplyClientDetailPreset(id, NET_LOD_FULL, false);
    ResetNetLodForPlayer(id);
    g_fNextNetLodUpdate = 0.0;
    g_fNextNetRampUpdate = 0.0;
    g_fClientChaseDistance[id] = DEFAULT_CHASE_DISTANCE;
    g_bHasClientViewAngles[id] = false;
    g_fViewerBasisTime[id] = -9999.0;
    CreateEntitiesOnConnect(id);

    if (!is_user_bot(id))
        query_client_cvar(id, "cl_chasedist", "OnClientChaseDistance");

    // TeamInfo remains the authoritative live update. This delayed AMXX-native
    // sync only covers plugin reloads / joins where TeamInfo has not arrived yet.
    remove_task(TASK_SYNC_TEAM_BASE + id);
    set_task(0.5, "TaskSyncPlayerTeam", TASK_SYNC_TEAM_BASE + id);

    // A late join during the persistent phase must not wait for the next round.
    if (g_bPersistentPhase && HasPersistentDisplayEnabled()) {
        EnablePersistentVisibilityForwards();

        if (!is_valid_ent(g_iController))
            CreateController();

        g_fNextVisibilityUpdate = 0.0;
        g_fNextHudUpdate = 0.0;
        g_fNextDebugBeamUpdate = 0.0;
        g_fNextNetLodUpdate = 0.0;
        g_fNextNetRampUpdate = 0.0;
    }
}

public ForwardCmdStart(id, ucHandle, seed)
{
    if (!IsPlayer(id) || !is_user_connected(id))
        return FMRES_IGNORED;

    // pev_v_angle is not reliable for every spectator chase-camera rotation.
    // UC_ViewAngles comes directly from the client's current user command, so
    // it follows the actual orbiting camera while spectating. The cached basis
    // is invalidated immediately so AddToFullPack uses this command's view.
    get_uc(ucHandle, UC_ViewAngles, g_fClientViewAngles[id]);
    g_bHasClientViewAngles[id] = true;
    g_fViewerBasisTime[id] = -9999.0;

    return FMRES_IGNORED;
}

public OnClientChaseDistance(id, const szCvar[], const szValue[])
{
    if (!IsPlayer(id) || !is_user_connected(id))
        return;

    new Float:fDistance = str_to_float(szValue);
    if (fDistance >= MIN_CHASE_DISTANCE && fDistance <= MAX_CHASE_DISTANCE)
        g_fClientChaseDistance[id] = fDistance;
}

public TaskSyncPlayerTeam(iTask)
{
    new id = iTask - TASK_SYNC_TEAM_BASE;

    if (!IsPlayer(id) || !is_user_connected(id))
        return;

    new CsTeams:iOldTeam = g_iPlayerTeam[id];

    switch (get_user_team(id)) {
        case 1: g_iPlayerTeam[id] = CS_TEAM_T;
        case 2: g_iPlayerTeam[id] = CS_TEAM_CT;
        case 3: g_iPlayerTeam[id] = CS_TEAM_SPECTATOR;
        default: g_iPlayerTeam[id] = CS_TEAM_UNASSIGNED;
    }

    if (g_iPlayerTeam[id] != iOldTeam) {
        if (g_iPlayerTeam[id] == CS_TEAM_T || g_iPlayerTeam[id] == CS_TEAM_CT)
            ScheduleHealthBaselineCapture(id);
        else
            ClearHealthBaseline(id);

        MarkNetContentUrgent(id);
    }

    g_fNextVisibilityUpdate = 0.0;
    g_fNextNetLodUpdate = 0.0;
    g_fNextNetRampUpdate = 0.0;
}

public client_disconnected(id)
{
    remove_task(TASK_SYNC_TEAM_BASE + id);
    remove_task(TASK_HEALTH_BASELINE_BASE + id);

    if (!g_bIsConnected[id])
        return;

    g_bIsConnected[id] = false;
    g_iPlayerTeam[id] = CS_TEAM_UNASSIGNED;
    g_iHealthBaseline[id] = 0;
    g_iHealthBaselineRetries[id] = 0;
    g_iCachedHealthDisplayValue[id] = 0;
    g_bNetContentInitialized[id] = false;
    g_bNetContentUrgent[id] = false;
    g_fNetContentLastUpdate[id] = 0.0;
    ResetNetQualityForPlayer(id);
    ResetClientDetailPreferences(id);
    ResetNetLodForPlayer(id);
    g_fNextNetLodUpdate = 0.0;
    g_fNextNetRampUpdate = 0.0;
    g_fClientChaseDistance[id] = DEFAULT_CHASE_DISTANCE;
    g_bHasClientViewAngles[id] = false;
    g_fViewerBasisTime[id] = -9999.0;
    RemoveEntitiesOnDisconnect(id);
}

ClearHealthBaseline(const id)
{
    if (!IsPlayer(id))
        return;

    remove_task(TASK_HEALTH_BASELINE_BASE + id);
    g_iHealthBaseline[id] = 0;
    g_iHealthBaselineRetries[id] = 0;
}

ScheduleHealthBaselineCapture(const id)
{
    if (!IsPlayer(id) || !is_user_connected(id))
        return;

    remove_task(TASK_HEALTH_BASELINE_BASE + id);
    g_iHealthBaseline[id] = 0;
    g_iHealthBaselineRetries[id] = 0;
    set_task(HEALTH_BASELINE_CAPTURE_DELAY, "TaskCaptureHealthBaseline",
        TASK_HEALTH_BASELINE_BASE + id);
}

public TaskCaptureHealthBaseline(iTask)
{
    new id = iTask - TASK_HEALTH_BASELINE_BASE;

    if (!IsPlayer(id) || !is_user_connected(id))
        return;

    if (g_iPlayerTeam[id] != CS_TEAM_T && g_iPlayerTeam[id] != CS_TEAM_CT)
        return;

    // If the normal persistent HUD already observed a positive HP value before
    // this delayed task fired, keep that reference. In particular, never let a
    // late task lower a 5000-HP max that was already auto-diagnosed.
    if (g_iHealthBaseline[id] > 0)
        return;

    // If HLTV/TeamInfo arrived before spawn, wait for a live positive HP value
    // rather than accidentally storing the previous round's 0 HP.
    if (is_user_alive(id)) {
        new iHealth = get_user_health(id);
        if (iHealth > 0) {
            g_iHealthBaseline[id] = iHealth;
            return;
        }
    }

    if (++g_iHealthBaselineRetries[id] <= HEALTH_BASELINE_MAX_RETRIES)
        set_task(HEALTH_BASELINE_RETRY_DELAY, "TaskCaptureHealthBaseline", iTask);
}


ResetClientDetailPreferences(const id)
{
    if (id < 1 || id > MAX_PLAYERS)
        return;

    g_iClientDetailCap[id] = NET_LOD_FULL;
    g_iClientWeaponsMode[id] = 2;
    g_bClientShowArrow[id] = true;
    g_bClientShowHealth[id] = true;
    g_bClientShowGrenades[id] = true;
    g_bClientShowObjective[id] = true;
}

ApplyClientDetailPreset(const id, const NetPairLod:iLod, const bool:bNotify)
{
    if (id < 1 || id > MAX_PLAYERS)
        return;

    g_iClientDetailCap[id] = iLod;

    switch (iLod) {
        case NET_LOD_NONE: {
            g_iClientWeaponsMode[id] = 0;
            g_bClientShowArrow[id] = false;
            g_bClientShowHealth[id] = false;
            g_bClientShowGrenades[id] = false;
            g_bClientShowObjective[id] = false;
        }
        case NET_LOD_MINIMAL: {
            g_iClientWeaponsMode[id] = 0;
            g_bClientShowArrow[id] = true;
            g_bClientShowHealth[id] = false;
            g_bClientShowGrenades[id] = false;
            g_bClientShowObjective[id] = false;
        }
        case NET_LOD_REDUCED: {
            g_iClientWeaponsMode[id] = 2;
            g_bClientShowArrow[id] = true;
            g_bClientShowHealth[id] = false;
            g_bClientShowGrenades[id] = false;
            g_bClientShowObjective[id] = true;
        }
        case NET_LOD_FULL: {
            g_iClientWeaponsMode[id] = 2;
            g_bClientShowArrow[id] = true;
            g_bClientShowHealth[id] = true;
            // Persistent FULL still hides grenades by LOD; keeping the preference
            // enabled preserves the traditional rich freezetime equipment view.
            g_bClientShowGrenades[id] = true;
            g_bClientShowObjective[id] = true;
        }
        default: {
            g_iClientDetailCap[id] = NET_LOD_FULLPLUS;
            g_iClientWeaponsMode[id] = 2;
            g_bClientShowArrow[id] = true;
            g_bClientShowHealth[id] = true;
            g_bClientShowGrenades[id] = true;
            g_bClientShowObjective[id] = true;
        }
    }

    g_fNextNetLodUpdate = 0.0;
    g_fNextNetRampUpdate = 0.0;
    g_fNextVisibilityUpdate = 0.0;

    if (bNotify)
        PrintClientDetailStatus(id);
}

GetNetLodName(const iLang, const NetPairLod:iLod, szName[], const iLen)
{
    switch (iLod) {
        case NET_LOD_NONE: formatex(szName, iLen, "%L", iLang, "SET_LOD_OFF");
        case NET_LOD_MINIMAL: formatex(szName, iLen, "%L", iLang, "SET_LOD_MINIMAL");
        case NET_LOD_REDUCED: formatex(szName, iLen, "%L", iLang, "SET_LOD_REDUCED");
        case NET_LOD_FULL: formatex(szName, iLen, "%L", iLang, "SET_LOD_FULL");
        default: formatex(szName, iLen, "%L", iLang, "SET_LOD_FULLPLUS");
    }
}

PrintClientDetailStatus(const id)
{
    if (!IsPlayer(id) || !is_user_connected(id))
        return;

    static szLod[12];
    GetNetLodName(id, g_iClientDetailCap[id], szLod, charsmax(szLod));

    client_print(id, print_console, "%L %L",
        id, "SET_TAG", id, "SET_DETAIL_STATUS",
        _:g_iClientDetailCap[id], szLod,
        g_bClientShowArrow[id] ? 1 : 0,
        g_bClientShowHealth[id] ? 1 : 0,
        g_iClientWeaponsMode[id],
        g_bClientShowGrenades[id] ? 1 : 0,
        g_bClientShowObjective[id] ? 1 : 0);
    client_print(id, print_console, "%L %L",
        id, "SET_TAG", id, "SET_DETAIL_HELP");
}

public CmdClientDetail(id)
{
    if (!IsPlayer(id) || !is_user_connected(id))
        return PLUGIN_HANDLED;

    if (read_argc() < 2) {
        PrintClientDetailStatus(id);
        return PLUGIN_HANDLED;
    }

    static szArg[8];
    read_argv(1, szArg, charsmax(szArg));

    new iDetail = str_to_num(szArg);
    if (iDetail < 0 || iDetail > 4) {
        client_print(id, print_console, "%L %L", id, "SET_TAG", id, "SET_DETAIL_RANGE");
        return PLUGIN_HANDLED;
    }

    ApplyClientDetailPreset(id, NetPairLod:iDetail, true);
    return PLUGIN_HANDLED;
}

public CmdClientView(id)
{
    if (!IsPlayer(id) || !is_user_connected(id))
        return PLUGIN_HANDLED;

    if (read_argc() < 3) {
        PrintClientDetailStatus(id);
        return PLUGIN_HANDLED;
    }

    static szFeature[16], szValue[8];
    read_argv(1, szFeature, charsmax(szFeature));
    read_argv(2, szValue, charsmax(szValue));
    new iValue = str_to_num(szValue);

    if (equali(szFeature, "weapons")) {
        if (iValue < 0 || iValue > 2) {
            client_print(id, print_console, "%L %L", id, "SET_TAG", id, "SET_VIEW_WEAPONS_RANGE");
            return PLUGIN_HANDLED;
        }

        g_iClientWeaponsMode[id] = iValue;

        // Individual controls are allowed to turn a preset into a custom view.
        // Raising the client CAP only asks for the feature; server CVARs and the
        // adaptive network target remain authoritative.
        if (iValue == 1 && g_iClientDetailCap[id] < NET_LOD_REDUCED)
            g_iClientDetailCap[id] = NET_LOD_REDUCED;
        else if (iValue == 2 && g_iClientDetailCap[id] < NET_LOD_FULLPLUS)
            g_iClientDetailCap[id] = NET_LOD_FULLPLUS;
    }
    else {
        if (iValue < 0 || iValue > 1) {
            client_print(id, print_console, "%L %L", id, "SET_TAG", id, "SET_VIEW_BINARY_RANGE");
            return PLUGIN_HANDLED;
        }

        if (equali(szFeature, "arrow")) {
            g_bClientShowArrow[id] = bool:iValue;
            if (iValue && g_iClientDetailCap[id] < NET_LOD_MINIMAL)
                g_iClientDetailCap[id] = NET_LOD_MINIMAL;
        }
        else if (equali(szFeature, "health")) {
            g_bClientShowHealth[id] = bool:iValue;
            if (iValue && g_iClientDetailCap[id] < NET_LOD_FULL)
                g_iClientDetailCap[id] = NET_LOD_FULL;
        }
        else if (equali(szFeature, "grenades")) {
            g_bClientShowGrenades[id] = bool:iValue;
            if (iValue && g_iClientDetailCap[id] < NET_LOD_FULLPLUS)
                g_iClientDetailCap[id] = NET_LOD_FULLPLUS;
        }
        else if (equali(szFeature, "objective")) {
            g_bClientShowObjective[id] = bool:iValue;
            if (iValue && g_iClientDetailCap[id] < NET_LOD_REDUCED)
                g_iClientDetailCap[id] = NET_LOD_REDUCED;
        }
        else {
            client_print(id, print_console, "%L %L", id, "SET_TAG", id, "SET_VIEW_UNKNOWN");
            return PLUGIN_HANDLED;
        }
    }

    g_fNextNetLodUpdate = 0.0;
    g_fNextNetRampUpdate = 0.0;
    g_fNextVisibilityUpdate = 0.0;
    PrintClientDetailStatus(id);
    return PLUGIN_HANDLED;
}

CacheDisplaySettings()
{
    g_iShowWeapons = get_pcvar_num(g_pDisplayCvar[CVAR_SHOW_WEAPONS]);
    g_iShowMoney = get_pcvar_num(g_pDisplayCvar[CVAR_SHOW_MONEY]);
    g_iShowGrenades = get_pcvar_num(g_pDisplayCvar[CVAR_SHOW_GRENADES]);
    g_iShowArrow = get_pcvar_num(g_pDisplayCvar[CVAR_SHOW_ARROW]);
    g_iShowArmor = get_pcvar_num(g_pDisplayCvar[CVAR_SHOW_ARMOR]);
    g_iShowTeammatesAlways = get_pcvar_num(g_pDisplayCvar[CVAR_SHOW_TEAMMATES_ALWAYS]);
    g_iShowArrowMode = clamp(get_pcvar_num(g_pDisplayCvar[CVAR_SHOW_ARROW_MODE]), 0, 2);
    g_iShowTeammatesWeapon = get_pcvar_num(g_pDisplayCvar[CVAR_SHOW_TEAMMATES_WEAPON]);
    g_iShowTeammatesObjective = get_pcvar_num(g_pDisplayCvar[CVAR_SHOW_TEAMMATES_OBJECTIVE]);
    g_iShowTeammatesHealth = get_pcvar_num(g_pDisplayCvar[CVAR_SHOW_TEAMMATES_HEALTH]);
    CacheHudSettings();
    g_iShowTeammatesThroughWalls = get_pcvar_num(g_pDisplayCvar[CVAR_SHOW_TEAMMATES_THROUGH_WALLS]);
    CacheLiveScaleSettings();
    g_iHealthLowThreshold = clamp(get_pcvar_num(g_pDisplayCvar[CVAR_HEALTH_LOW_THRESHOLD]), 1, 100);
    g_iHealthDisplayMode = clamp(get_pcvar_num(g_pDisplayCvar[CVAR_HEALTH_DISPLAY_MODE]), 0, 2);
    g_iDebugProjection = get_pcvar_num(g_pDisplayCvar[CVAR_DEBUG_PROJECTION]);
    CacheTeammateColorSettings();
    CacheNetSettings();
}

CacheNetSettings()
{
    g_iNetAdaptive = get_pcvar_num(g_pNetAdaptive) ? 1 : 0;
    g_iNetSpriteBudget = clamp(get_pcvar_num(g_pNetSpriteBudget), 1, 1024);
    g_iNetRecoverMargin = clamp(get_pcvar_num(g_pNetRecoverMargin), 0, g_iNetSpriteBudget - 1);
    g_fNetUpdateInterval = get_pcvar_float(g_pNetUpdateInterval);
    g_iNetRampSprites = clamp(get_pcvar_num(g_pNetRampSprites), 1, 128);
    g_fNetRampInterval = get_pcvar_float(g_pNetRampInterval);
    g_iNetContentScheduler = get_pcvar_num(g_pNetContentScheduler) ? 1 : 0;
    g_iNetContentBatch = clamp(get_pcvar_num(g_pNetContentBatch), 1, MAX_PLAYERS);
    g_fNetContentInterval = get_pcvar_float(g_pNetContentInterval);
    g_iNetQualityAdaptive = get_pcvar_num(g_pNetQualityAdaptive) ? 1 : 0;
    g_fNetQualityInterval = get_pcvar_float(g_pNetQualityInterval);
    g_iNetPingSoftDelta = clamp(get_pcvar_num(g_pNetPingSoftDelta), 1, 1000);
    g_iNetPingHardDelta = clamp(get_pcvar_num(g_pNetPingHardDelta), g_iNetPingSoftDelta + 1, 2000);
    g_iNetLossSoft = clamp(get_pcvar_num(g_pNetLossSoft), 1, 99);
    g_iNetLossHard = clamp(get_pcvar_num(g_pNetLossHard), g_iNetLossSoft + 1, 100);
    g_iNetQualityStepDown = clamp(get_pcvar_num(g_pNetQualityStepDown), 1, 128);
    g_iNetQualityStepUp = clamp(get_pcvar_num(g_pNetQualityStepUp), 1, 128);
    g_iNetQualityRecoverSamples = clamp(get_pcvar_num(g_pNetQualityRecoverSamples), 1, 60);
    g_iNetQualityMinBudget = clamp(get_pcvar_num(g_pNetQualityMinBudget), 1, g_iNetSpriteBudget);

    if (g_fNetUpdateInterval < 0.10)
        g_fNetUpdateInterval = 0.10;
    else if (g_fNetUpdateInterval > 2.0)
        g_fNetUpdateInterval = 2.0;

    if (g_fNetRampInterval < 0.05)
        g_fNetRampInterval = 0.05;
    else if (g_fNetRampInterval > 1.0)
        g_fNetRampInterval = 1.0;

    if (g_fNetContentInterval < 0.05)
        g_fNetContentInterval = 0.05;
    else if (g_fNetContentInterval > 1.0)
        g_fNetContentInterval = 1.0;

    if (g_fNetQualityInterval < 0.50)
        g_fNetQualityInterval = 0.50;
    else if (g_fNetQualityInterval > 5.0)
        g_fNetQualityInterval = 5.0;

    // A live server-budget change is always authoritative. Quality adaptation
    // may stay below it, but never above it or below the configured minimum.
    for (new iHost = 1; iHost <= g_iMaxPlayers; iHost++) {
        if (g_iNetQualityEffectiveBudget[iHost] <= 0)
            g_iNetQualityEffectiveBudget[iHost] = g_iNetSpriteBudget;
        else if (g_iNetQualityEffectiveBudget[iHost] > g_iNetSpriteBudget)
            g_iNetQualityEffectiveBudget[iHost] = g_iNetSpriteBudget;

        if (g_iNetQualityEffectiveBudget[iHost] < g_iNetQualityMinBudget)
            g_iNetQualityEffectiveBudget[iHost] = g_iNetQualityMinBudget;
    }
}

// Scale/projection CVARs are calibration controls, so SET reads them live.
// Returns true when a value changed so the viewer->teammate scale cache can be
// rebuilt immediately instead of waiting for a round restart.
bool:CacheLiveScaleSettings()
{
    new Float:fOldWallMarkerOffset = g_fWallMarkerOffset;
    new Float:fOldWallVerticalOffset = g_fWallVerticalOffset;
    new Float:fOldWallCheckInterval = g_fWallCheckInterval;
    new Float:fOldWallScaleMultiplier = g_fWallScaleMultiplier;
    new Float:fOldWallScaleMinFactor = g_fWallScaleMinFactor;
    new Float:fOldWallScaleMaxFactor = g_fWallScaleMaxFactor;
    new Float:fOldVisibleScaleDistanceStart = g_fVisibleScaleDistanceStart;
    new Float:fOldVisibleScaleDistanceEnd = g_fVisibleScaleDistanceEnd;
    new Float:fOldVisibleScaleMaxFactor = g_fVisibleScaleMaxFactor;
    new Float:fOldSpriteScale = g_fSpriteScale;

    g_fWallMarkerOffset = get_pcvar_float(g_pDisplayCvar[CVAR_WALL_MARKER_OFFSET]);
    g_fWallVerticalOffset = get_pcvar_float(g_pDisplayCvar[CVAR_WALL_VERTICAL_OFFSET]);
    g_fWallCheckInterval = get_pcvar_float(g_pDisplayCvar[CVAR_WALL_CHECK_INTERVAL]);
    g_fWallScaleMultiplier = get_pcvar_float(g_pDisplayCvar[CVAR_WALL_SCALE_MULTIPLIER]);
    g_fWallScaleMinFactor = get_pcvar_float(g_pDisplayCvar[CVAR_WALL_SCALE_MIN_FACTOR]);
    g_fWallScaleMaxFactor = get_pcvar_float(g_pDisplayCvar[CVAR_WALL_SCALE_MAX_FACTOR]);
    g_fVisibleScaleDistanceStart = get_pcvar_float(g_pDisplayCvar[CVAR_VISIBLE_SCALE_DISTANCE_START]);
    g_fVisibleScaleDistanceEnd = get_pcvar_float(g_pDisplayCvar[CVAR_VISIBLE_SCALE_DISTANCE_END]);
    g_fVisibleScaleMaxFactor = get_pcvar_float(g_pDisplayCvar[CVAR_VISIBLE_SCALE_MAX_FACTOR]);
    g_fSpriteScale = get_pcvar_float(g_pDisplayCvar[CVAR_SPRITE_SCALE]);

    if (g_fSpriteScale < 0.01)
        g_fSpriteScale = 0.01;
    else if (g_fSpriteScale > 16.0)
        g_fSpriteScale = 16.0;

    if (g_fWallMarkerOffset < 0.0)
        g_fWallMarkerOffset = 0.0;
    else if (g_fWallMarkerOffset > 64.0)
        g_fWallMarkerOffset = 64.0;

    if (g_fWallVerticalOffset < -32.0)
        g_fWallVerticalOffset = -32.0;
    else if (g_fWallVerticalOffset > 64.0)
        g_fWallVerticalOffset = 64.0;

    if (g_fWallCheckInterval < 0.001)
        g_fWallCheckInterval = 0.001;
    else if (g_fWallCheckInterval > 1.0)
        g_fWallCheckInterval = 1.0;

    if (g_fWallScaleMultiplier < 0.01)
        g_fWallScaleMultiplier = 0.01;
    else if (g_fWallScaleMultiplier > 16.0)
        g_fWallScaleMultiplier = 16.0;

    if (g_fWallScaleMinFactor < 0.0001)
        g_fWallScaleMinFactor = 0.0001;
    else if (g_fWallScaleMinFactor > 16.0)
        g_fWallScaleMinFactor = 16.0;

    if (g_fWallScaleMaxFactor < g_fWallScaleMinFactor)
        g_fWallScaleMaxFactor = g_fWallScaleMinFactor;
    else if (g_fWallScaleMaxFactor > 16.0)
        g_fWallScaleMaxFactor = 16.0;

    if (g_fVisibleScaleDistanceStart < 0.0)
        g_fVisibleScaleDistanceStart = 0.0;

    if (g_fVisibleScaleDistanceEnd < g_fVisibleScaleDistanceStart + 1.0)
        g_fVisibleScaleDistanceEnd = g_fVisibleScaleDistanceStart + 1.0;

    if (g_fVisibleScaleMaxFactor < 1.0)
        g_fVisibleScaleMaxFactor = 1.0;
    else if (g_fVisibleScaleMaxFactor > 16.0)
        g_fVisibleScaleMaxFactor = 16.0;

    return bool:(
        fOldWallMarkerOffset != g_fWallMarkerOffset ||
        fOldWallVerticalOffset != g_fWallVerticalOffset ||
        fOldWallCheckInterval != g_fWallCheckInterval ||
        fOldWallScaleMultiplier != g_fWallScaleMultiplier ||
        fOldWallScaleMinFactor != g_fWallScaleMinFactor ||
        fOldWallScaleMaxFactor != g_fWallScaleMaxFactor ||
        fOldVisibleScaleDistanceStart != g_fVisibleScaleDistanceStart ||
        fOldVisibleScaleDistanceEnd != g_fVisibleScaleDistanceEnd ||
        fOldVisibleScaleMaxFactor != g_fVisibleScaleMaxFactor ||
        fOldSpriteScale != g_fSpriteScale
    );
}

CacheHudSettings()
{
    // Name visibility is a live HUD setting. Turning it off stops new
    // HUD messages on the next HUD tick (default 0.10 s), so no round restart is
    // required. Existing labels naturally expire a few hundredths later.
    g_iShowTeammatesName = get_pcvar_num(g_pDisplayCvar[CVAR_SHOW_TEAMMATES_NAME]);
    g_fTeammateNameMaxDistance = get_pcvar_float(g_pDisplayCvar[CVAR_TEAMMATE_NAME_MAX_DISTANCE]);
    g_fTeammateNameUpdateInterval = get_pcvar_float(g_pDisplayCvar[CVAR_TEAMMATE_NAME_UPDATE_INTERVAL]);
    g_fTeammateNameScreenGap = get_pcvar_float(g_pDisplayCvar[CVAR_TEAMMATE_NAME_SCREEN_GAP]);

    // 0 means unlimited. Negative values are normalized to unlimited as well.
    if (g_fTeammateNameMaxDistance < 0.0)
        g_fTeammateNameMaxDistance = 0.0;

    if (g_fTeammateNameUpdateInterval < 0.05)
        g_fTeammateNameUpdateInterval = 0.05;
    else if (g_fTeammateNameUpdateInterval > 1.0)
        g_fTeammateNameUpdateInterval = 1.0;

    if (g_fTeammateNameScreenGap < 0.0)
        g_fTeammateNameScreenGap = 0.0;
    else if (g_fTeammateNameScreenGap > 0.20)
        g_fTeammateNameScreenGap = 0.20;
}

CacheTeammateColorSettings()
{
    static szValue[16];
    get_pcvar_string(g_pTeammateColorCvar, szValue, charsmax(szValue));
    trim(szValue);

    if (!szValue[0] || equali(szValue, "team")) {
        g_bTeammateColorByTeam = true;
        return;
    }

    g_bTeammateColorByTeam = false;
    ConvertCvarToRGB(str_to_num(szValue), g_iCustomTeammateColor);
}

SetColorArray(iDest[3], const iSource[3])
{
    iDest[0] = iSource[0];
    iDest[1] = iSource[1];
    iDest[2] = iSource[2];
}

GetOwnerTeamColor(const id, iColor[3])
{
    switch (g_iPlayerTeam[id]) {
        case CS_TEAM_CT: SetColorArray(iColor, g_iTeamColorCT);
        case CS_TEAM_T: SetColorArray(iColor, g_iTeamColorT);
        default: SetColorArray(iColor, g_iCustomTeammateColor);
    }
}

GetOwnerTeamStatusColor(const id, iColor[3])
{
    if (g_bTeammateColorByTeam) {
        GetOwnerTeamColor(id, iColor);
        return;
    }

    SetColorArray(iColor, g_iCustomTeammateColor);
}

GetStatusColorForViewer(const iHost, const iOwner, iColor[3])
{
    // Spectator/chase/in-eye views always use the observed player's team color
    // so CT/T markers remain distinguishable even if active players selected a
    // custom teammate color.
    if (IsViewerInObserverMode(iHost) || g_bTeammateColorByTeam) {
        GetOwnerTeamColor(iOwner, iColor);
        return;
    }

    SetColorArray(iColor, g_iCustomTeammateColor);
}

bool:IsFreezetimeTeamStatusEntity(const iOwner, const iEnt)
{
    if (!IsPlayer(iOwner))
        return false;

    if (iEnt == g_iPlayerArrow[iOwner])
        return true;

    // 2..4 = HE/Flash/Smoke, 5 = armor, 6 = C4/defuse.
    // 0..1 are weapons and deliberately remain white.
    for (new i = 2; i <= 6; i++) {
        if (iEnt == g_iPlayerWeaponsSprites[iOwner][i])
            return true;
    }

    return false;
}

ApplyPersistentMarkerColorForHost(esHandle, const iEnt, const iHost, const iOwner)
{
    static iColor[3];

    switch (g_iMarkerTypeByEnt[iEnt]) {
        case MARKER_WEAPON: {
            GetColor(CVAR_SPRITE_WEAPON_COLOR, iColor);
        }
        case MARKER_HEALTH: {
            if (g_iCachedHealthDisplayValue[iOwner] <= g_iHealthLowThreshold)
                SetColorArray(iColor, g_iLowHealthColor);
            else
                GetStatusColorForViewer(iHost, iOwner, iColor);
        }
        case MARKER_ARROW, MARKER_OBJECTIVE: {
            GetStatusColorForViewer(iHost, iOwner, iColor);
        }
        default: {
            // Persistent FULL+ reuses slots 2..4 for grenade status icons. They
            // were historically MARKER_NONE because those slots were freeze-only.
            // Treat them as team-status markers without changing the sprite frame map.
            for (new i = 2; i <= 5; i++) {
                if (iEnt == g_iPlayerWeaponsSprites[iOwner][i]) {
                    GetStatusColorForViewer(iHost, iOwner, iColor);
                    set_es(esHandle, ES_RenderColor, iColor);
                    return;
                }
            }
            return;
        }
    }

    set_es(esHandle, ES_RenderColor, iColor);
}

bool:HasPersistentDisplayEnabled()
{
    if (!g_iShowTeammatesAlways)
        return false;

    return bool:(g_iShowArrow || g_iShowTeammatesWeapon || g_iShowTeammatesObjective ||
        g_iShowTeammatesHealth || g_iShowGrenades || g_iShowTeammatesName || g_iDebugProjection);
}

CreateEntitiesOnConnect(const id)
{
    for (new i = 0; i < HEALTH_SPRITES; i++) {
        g_iPlayerMoneySprites[id][i] = create_entity("env_sprite");
        if (is_valid_ent(g_iPlayerMoneySprites[id][i])) {
            SetEntityAttribs(g_iPlayerMoneySprites[id][i], szStatusSprite);
            TrackPersistentMarker(g_iPlayerMoneySprites[id][i], id, MARKER_HEALTH);
        }
    }

    for (new i = 0; i < WEAPON_SPRITES; i++) {
        g_iPlayerWeaponsSprites[id][i] = create_entity("env_sprite");
        if (is_valid_ent(g_iPlayerWeaponsSprites[id][i])) {
            SetEntityAttribs(g_iPlayerWeaponsSprites[id][i], szStatusSprite);

            if (i <= 1)
                TrackPersistentMarker(g_iPlayerWeaponsSprites[id][i], id, MARKER_WEAPON);
            else if (i == 6)
                TrackPersistentMarker(g_iPlayerWeaponsSprites[id][i], id, MARKER_OBJECTIVE);
            else
                TrackPersistentMarker(g_iPlayerWeaponsSprites[id][i], id, MARKER_NONE);
        }
    }

    g_iPlayerDolarSign[id] = create_entity("env_sprite");
    if (is_valid_ent(g_iPlayerDolarSign[id])) {
        SetEntityAttribs(g_iPlayerDolarSign[id], szStatusSprite);
        TrackPersistentMarker(g_iPlayerDolarSign[id], id, MARKER_HEALTH);
    }

    g_iPlayerArrow[id] = create_entity("env_sprite");
    if (is_valid_ent(g_iPlayerArrow[id])) {
        SetEntityAttribs(g_iPlayerArrow[id], szStatusSprite);
        TrackPersistentMarker(g_iPlayerArrow[id], id, MARKER_ARROW);
    }

    ApplyScaleToPlayerSprites(id);
}

RemoveEntitiesOnDisconnect(const id)
{
    for (new i = 0; i < HEALTH_SPRITES; i++) {
        UntrackPersistentMarker(g_iPlayerMoneySprites[id][i]);
        if (is_valid_ent(g_iPlayerMoneySprites[id][i]))
            remove_entity(g_iPlayerMoneySprites[id][i]);
        g_iPlayerMoneySprites[id][i] = 0;
    }

    for (new i = 0; i < WEAPON_SPRITES; i++) {
        UntrackPersistentMarker(g_iPlayerWeaponsSprites[id][i]);
        if (is_valid_ent(g_iPlayerWeaponsSprites[id][i]))
            remove_entity(g_iPlayerWeaponsSprites[id][i]);
        g_iPlayerWeaponsSprites[id][i] = 0;
    }

    UntrackPersistentMarker(g_iPlayerDolarSign[id]);
    if (is_valid_ent(g_iPlayerDolarSign[id]))
        remove_entity(g_iPlayerDolarSign[id]);
    g_iPlayerDolarSign[id] = 0;

    UntrackPersistentMarker(g_iPlayerArrow[id]);
    if (is_valid_ent(g_iPlayerArrow[id]))
        remove_entity(g_iPlayerArrow[id]);
    g_iPlayerArrow[id] = 0;

    ClearVisibilityCacheForPlayer(id);
}

TrackPersistentMarker(const iEnt, const id, const PersistentMarkerType:iType)
{
    if (iEnt <= 0 || iEnt > MAX_TRACKED_EDICTS)
        return;

    g_iMarkerOwnerByEnt[iEnt] = id;
    g_iMarkerTypeByEnt[iEnt] = iType;
    g_bPersistentEntActive[iEnt] = false;
    g_bMarkerLayoutActive[iEnt] = false;
    g_fMarkerScreenX[iEnt] = 0.0;
    g_fMarkerScreenY[iEnt] = 0.0;
}

UntrackPersistentMarker(const iEnt)
{
    if (iEnt <= 0 || iEnt > MAX_TRACKED_EDICTS)
        return;

    g_iMarkerOwnerByEnt[iEnt] = 0;
    g_iMarkerTypeByEnt[iEnt] = MARKER_NONE;
    g_bPersistentEntActive[iEnt] = false;
    g_bMarkerLayoutActive[iEnt] = false;
    g_fMarkerScreenX[iEnt] = 0.0;
    g_fMarkerScreenY[iEnt] = 0.0;
}

SetPersistentEntityActive(const iEnt, const bool:bActive)
{
    if (iEnt <= 0 || iEnt > MAX_TRACKED_EDICTS)
        return;

    g_bPersistentEntActive[iEnt] = bActive;
}

SetMarkerScreenLayout(const iEnt, const Float:fScreenX, const Float:fScreenY)
{
    if (iEnt <= 0 || iEnt > MAX_TRACKED_EDICTS)
        return;

    g_fMarkerScreenX[iEnt] = fScreenX;
    g_fMarkerScreenY[iEnt] = fScreenY;
    g_bMarkerLayoutActive[iEnt] = true;
}

ClearMarkerScreenLayout(const iEnt)
{
    if (iEnt <= 0 || iEnt > MAX_TRACKED_EDICTS)
        return;

    g_fMarkerScreenX[iEnt] = 0.0;
    g_fMarkerScreenY[iEnt] = 0.0;
    g_bMarkerLayoutActive[iEnt] = false;
}

SetEntityAttribs(const iEnt, const szModel[])
{
    entity_set_model(iEnt, szModel);
    entity_set_int(iEnt, EV_INT_movetype, MOVETYPE_NOCLIP);
    entity_set_float(iEnt, EV_FL_framerate, 1.0);
    entity_set_float(iEnt, EV_FL_scale, 0.25);
    entity_set_int(iEnt, EV_INT_solid, SOLID_NOT);
    set_ent_rendering(iEnt, kRenderFxNone, 0, 0, 0, kRenderTransAlpha, 0);
}

ApplyScaleToPlayerSprites(const id)
{
    for (new i = 0; i < HEALTH_SPRITES; i++) {
        if (is_valid_ent(g_iPlayerMoneySprites[id][i]))
            entity_set_float(g_iPlayerMoneySprites[id][i], EV_FL_scale, g_fSpriteScale);
    }

    for (new i = 0; i < WEAPON_SPRITES; i++) {
        if (is_valid_ent(g_iPlayerWeaponsSprites[id][i]))
            entity_set_float(g_iPlayerWeaponsSprites[id][i], EV_FL_scale, g_fSpriteScale);
    }

    if (is_valid_ent(g_iPlayerDolarSign[id]))
        entity_set_float(g_iPlayerDolarSign[id], EV_FL_scale, g_fSpriteScale);

    if (is_valid_ent(g_iPlayerArrow[id]))
        entity_set_float(g_iPlayerArrow[id], EV_FL_scale, g_fSpriteScale);
}

ApplyScaleToAllSprites()
{
    for (new id = 1; id <= g_iMaxPlayers; id++) {
        if (g_bIsConnected[id])
            ApplyScaleToPlayerSprites(id);
    }
}

CreateController()
{
    RemoveController();

    g_iController = create_entity("info_target");
    if (!is_valid_ent(g_iController))
        return;

    entity_set_string(g_iController, EV_SZ_classname, szControllerClass);

    entity_set_float(g_iController, EV_FL_nextthink, get_gametime() + INITIAL_THINK_DELAY);
}

RemoveController()
{
    if (!is_valid_ent(g_iController)) {
        g_iController = 0;
        return;
    }

    remove_entity(g_iController);
    g_iController = 0;
}

StopRoundDisplay()
{
    DisablePersistentVisibilityForwards();
    RemoveController();
    HideAllSprites();
    ClearAllVisibilityCache();
    ResetAllNetLod();
    ResetNetContentScheduler();
    g_fNextNetLodUpdate = 0.0;
    g_fNextNetRampUpdate = 0.0;
    g_fNextNetContentUpdate = 0.0;
    g_fNextNetQualityUpdate = 0.0;
    g_bFreezeFinished = true;
    g_bPersistentPhase = false;
}

public ShowSprites(iEnt)
{
    if (!is_valid_ent(iEnt) || iEnt != g_iController)
        return PLUGIN_HANDLED;

    new Float:fNow = get_gametime();

    if (!g_bFreezeFinished && fNow >= g_fFreezeEndTime) {
        g_bFreezeFinished = true;
        g_bPersistentPhase = true;
        HideAllSprites();
        ResetNetContentScheduler();

        if (!HasPersistentDisplayEnabled()) {
            RemoveController();
            return PLUGIN_HANDLED;
        }

        EnablePersistentVisibilityForwards();
        g_fNextVisibilityUpdate = 0.0;
        g_fNextNetLodUpdate = 0.0;
        g_fNextNetRampUpdate = 0.0;
    }

    if (g_bFreezeFinished) {
        if (CacheLiveScaleSettings())
            g_fNextVisibilityUpdate = 0.0;

        CacheTeammateColorSettings();

        // Health mode stays server-authoritative and live. A client may hide the
        // row, but cannot replace percentage mode with raw HP or vice versa.
        g_iHealthDisplayMode = clamp(get_pcvar_num(g_pDisplayCvar[CVAR_HEALTH_DISPLAY_MODE]), 0, 2);

        // Position is the illusion's core and remains fast. Content (frames, HP,
        // weapons, inventory) is independently staggered below.
        UpdateOwnerSpatialState();

        if (!g_iNetContentScheduler)
            UpdateAllPersistentContent();
        else if (fNow >= g_fNextNetContentUpdate) {
            UpdateScheduledNetContent(fNow);
            g_fNextNetContentUpdate = fNow + g_fNetContentInterval;
        }

        if (fNow >= g_fNextNetQualityUpdate) {
            UpdateNetQuality();
            g_fNextNetQualityUpdate = fNow + g_fNetQualityInterval;
        }

        if (fNow >= g_fNextNetLodUpdate) {
            CacheNetSettings();
            UpdateAdaptiveNetLod();
            g_fNextNetLodUpdate = fNow + g_fNetUpdateInterval;
        }

        if (fNow >= g_fNextNetRampUpdate) {
            ApplyAdaptiveNetRamp();
            g_fNextNetRampUpdate = fNow + g_fNetRampInterval;
        }

        g_iDebugProjection = get_pcvar_num(g_pDisplayCvar[CVAR_DEBUG_PROJECTION]);

        if (fNow >= g_fNextVisibilityUpdate) {
            UpdateMarkerVisibilityCache();
            g_fNextVisibilityUpdate = fNow + g_fWallCheckInterval;
        }

        if (fNow >= g_fNextHudUpdate) {
            CacheHudSettings();

            if (g_iShowTeammatesName || g_iDebugProjection)
                UpdateTeammateHudLabels();

            g_fNextHudUpdate = fNow + g_fTeammateNameUpdateInterval;
        }

        if (g_iDebugProjection && fNow >= g_fNextDebugBeamUpdate) {
            DrawProjectionDebug();
            g_fNextDebugBeamUpdate = fNow + DEBUG_BEAM_UPDATE_INTERVAL;
        }

        entity_set_float(iEnt, EV_FL_nextthink, fNow + PERSISTENT_UPDATE_INTERVAL);
        return PLUGIN_CONTINUE;
    }

    // Freezetime uses the same fast spatial path and staggered semantic-content
    // scheduler: complete owner blocks are refreshed a few at a time, nearest first.
    CacheTeammateColorSettings();
    UpdateOwnerSpatialState();

    if (!g_iNetContentScheduler) {
        if (fNow >= g_fNextNetContentUpdate) {
            UpdateAllFreezetimeContent();
            g_fNextNetContentUpdate = fNow + 0.25;
            g_fNextNetLodUpdate = 0.0;
        }
    }
    else if (fNow >= g_fNextNetContentUpdate) {
        UpdateScheduledNetContent(fNow);
        g_fNextNetContentUpdate = fNow + g_fNetContentInterval;
        g_fNextNetLodUpdate = 0.0;
    }

    if (CacheLiveScaleSettings())
        g_fNextVisibilityUpdate = 0.0;

    if (fNow >= g_fNextNetQualityUpdate) {
        UpdateNetQuality();
        g_fNextNetQualityUpdate = fNow + g_fNetQualityInterval;
    }

    if (fNow >= g_fNextNetLodUpdate) {
        CacheNetSettings();
        UpdateAdaptiveNetLod();
        g_fNextNetLodUpdate = fNow + g_fNetUpdateInterval;
    }

    if (fNow >= g_fNextNetRampUpdate) {
        ApplyAdaptiveNetRamp();
        g_fNextNetRampUpdate = fNow + g_fNetRampInterval;
    }

    if (fNow >= g_fNextVisibilityUpdate) {
        UpdateMarkerVisibilityCache();
        g_fNextVisibilityUpdate = fNow + g_fWallCheckInterval;
    }

    entity_set_float(iEnt, EV_FL_nextthink, fNow + PERSISTENT_UPDATE_INTERVAL);
    return PLUGIN_CONTINUE;
}

ShowAllPlayerSprites(const id)
{
    static Float:fOrigin[3];
    GetSpriteOrigin(id, fOrigin);

    // Freezetime uses the same arrow/matrix world anchor as persistent mode.
    g_fPersistentAnchor[id][0] = fOrigin[0];
    g_fPersistentAnchor[id][1] = fOrigin[1];
    g_fPersistentAnchor[id][2] = fOrigin[2] + PERSISTENT_BLOCK_ANCHOR_OFFSET;

    new iWeapons = pev(id, pev_weapons);

    if (g_iShowMoney)
        ShowMoneySprites(id, fOrigin);
    else
        HideMoneySprites(id);

    if (g_iShowArrow)
        ShowArrowSprite(id, fOrigin);
    else
        HideEntity(g_iPlayerArrow[id]);

    if (g_iShowWeapons) {
        ShowPistolsSprite(id, fOrigin, iWeapons);
        ShowRiflesSprite(id, fOrigin, iWeapons);
    }
    else {
        HideEntity(g_iPlayerWeaponsSprites[id][0]);
        HideEntity(g_iPlayerWeaponsSprites[id][1]);
    }

    if (g_iShowGrenades)
        ShowGrenadesSprites(id, fOrigin, iWeapons);
    else {
        HideEntity(g_iPlayerWeaponsSprites[id][2]);
        HideEntity(g_iPlayerWeaponsSprites[id][3]);
        HideEntity(g_iPlayerWeaponsSprites[id][4]);
    }

    if (g_iShowArmor)
        ShowArmorSprite(id, fOrigin);
    else
        HideEntity(g_iPlayerWeaponsSprites[id][5]);

    ShowC4AndDefuseSprite(id, fOrigin, iWeapons);
}

GetSpriteOrigin(const id, Float:fOrigin[3])
{
    entity_get_vector(id, EV_VEC_origin, fOrigin);

    if (pev(id, pev_flags) & FL_DUCKING)
        fOrigin[2] += 9.0;
}

ShowMoneySprites(const id, const Float:fOrigin[3])
{
    static iColor[3];
    GetColor(CVAR_SPRITE_MONEY_COLOR, iColor);

    static szMoney[6];
    num_to_str(cs_get_user_money(id), szMoney, charsmax(szMoney));

    for (new i = 0; i < MONEY_SPRITES; i++) {
        if (!szMoney[i]) {
            HideEntity(g_iPlayerMoneySprites[id][i]);
            continue;
        }

        new iDigit = szMoney[i] - '0';
        DisplaySprite(g_iPlayerMoneySprites[id][i], fOrigin,
            float(GetDigitFrame(iDigit)), 34.0, g_fMoneyDigitX[i], MONEY_ROW_Y, iColor);
    }

    DisplaySprite(g_iPlayerDolarSign[id], fOrigin,
        float(STATUS_FRAME_CASH), 34.0, MONEY_ICON_X, MONEY_ROW_Y, iColor);
}

HideMoneySprites(const id)
{
    for (new i = 0; i < HEALTH_SPRITES; i++)
        HideEntity(g_iPlayerMoneySprites[id][i]);

    HideEntity(g_iPlayerDolarSign[id]);
}

ShowArrowSprite(const id, const Float:fOrigin[3])
{
    static iColor[3];
    GetOwnerTeamStatusColor(id, iColor);
    DisplaySprite(g_iPlayerArrow[id], fOrigin,
        float(STATUS_FRAME_ARROW), 34.0, 0.0, ARROW_ROW_Y, iColor);
}

ShowPistolsSprite(const id, const Float:fOrigin[3], const iWeapons)
{
    static iColor[3];
    GetColor(CVAR_SPRITE_WEAPON_COLOR, iColor);

    for (new i = 0; i < sizeof(iPistols); i++) {
        new iWeapon = iPistols[i];
        if (iWeapons & (1 << iWeapon)) {
            DisplaySprite(g_iPlayerWeaponsSprites[id][0], fOrigin,
                float(GetStatusFrameForWeaponId(iWeapon)), 47.0,
                FREEZE_SECONDARY_X, WEAPON_ROW_Y, iColor);
            return;
        }
    }

    HideEntity(g_iPlayerWeaponsSprites[id][0]);
}

ShowRiflesSprite(const id, const Float:fOrigin[3], const iWeapons)
{
    static iColor[3];
    GetColor(CVAR_SPRITE_WEAPON_COLOR, iColor);

    for (new i = 0; i < sizeof(iPrimaryWeapons); i++) {
        new iWeapon = iPrimaryWeapons[i];
        if (iWeapons & (1 << iWeapon)) {
            DisplaySprite(g_iPlayerWeaponsSprites[id][1], fOrigin,
                float(GetStatusFrameForWeaponId(iWeapon)), 47.0,
                FREEZE_PRIMARY_X, WEAPON_ROW_Y, iColor);
            return;
        }
    }

    HideEntity(g_iPlayerWeaponsSprites[id][1]);
}

ShowGrenadesSprites(const id, const Float:fOrigin[3], const iWeapons)
{
    static iColor[3];
    GetOwnerTeamStatusColor(id, iColor);

    if (iWeapons & (1 << CSW_HEGRENADE))
        DisplaySprite(g_iPlayerWeaponsSprites[id][2], fOrigin,
            float(STATUS_FRAME_HEGRENADE), 47.0, FREEZE_HE_X, GRENADE_ROW_Y, iColor);
    else
        HideEntity(g_iPlayerWeaponsSprites[id][2]);

    if (iWeapons & (1 << CSW_FLASHBANG))
        DisplaySprite(g_iPlayerWeaponsSprites[id][3], fOrigin,
            float(STATUS_FRAME_FLASHBANG), 47.0, FREEZE_FLASH_X, GRENADE_ROW_Y, iColor);
    else
        HideEntity(g_iPlayerWeaponsSprites[id][3]);

    if (iWeapons & (1 << CSW_SMOKEGRENADE))
        DisplaySprite(g_iPlayerWeaponsSprites[id][4], fOrigin,
            float(STATUS_FRAME_SMOKEGRENADE), 47.0, FREEZE_SMOKE_X, GRENADE_ROW_Y, iColor);
    else
        HideEntity(g_iPlayerWeaponsSprites[id][4]);
}

ShowArmorSprite(const id, const Float:fOrigin[3])
{
    static iColor[3];
    static CsArmorType:iArmorType;

    cs_get_user_armor(id, iArmorType);

    switch (iArmorType) {
        case CS_ARMOR_VESTHELM: {
            GetOwnerTeamStatusColor(id, iColor);
            DisplaySprite(g_iPlayerWeaponsSprites[id][5], fOrigin,
                float(STATUS_FRAME_VESTHELM), 48.0, FREEZE_ARMOR_X, ARMOR_ROW_Y, iColor);
        }
        case CS_ARMOR_KEVLAR: {
            GetOwnerTeamStatusColor(id, iColor);
            DisplaySprite(g_iPlayerWeaponsSprites[id][5], fOrigin,
                float(STATUS_FRAME_KEVLAR), 48.0, FREEZE_ARMOR_X, ARMOR_ROW_Y, iColor);
        }
        default: HideEntity(g_iPlayerWeaponsSprites[id][5]);
    }
}

ShowC4AndDefuseSprite(const id, const Float:fOrigin[3], const iWeapons)
{
    static iColor[3];
    GetOwnerTeamStatusColor(id, iColor);

    if (iWeapons & (1 << CSW_C4)) {
        DisplaySprite(g_iPlayerWeaponsSprites[id][6], fOrigin,
            float(STATUS_FRAME_C4), 48.0, FREEZE_OBJECTIVE_X, OBJECTIVE_ROW_Y, iColor);
        return;
    }

    if (cs_get_user_defuse(id)) {
        DisplaySprite(g_iPlayerWeaponsSprites[id][6], fOrigin,
            float(STATUS_FRAME_DEFUSE), 48.0, FREEZE_OBJECTIVE_X, OBJECTIVE_ROW_Y, iColor);
        return;
    }

    HideEntity(g_iPlayerWeaponsSprites[id][6]);
}

DisplaySprite(const iEnt, const Float:fBaseOrigin[3], Float:fFrame, Float:fOffset,
    const Float:fScreenX, const Float:fScreenY, const iColor[3])
{
    if (!is_valid_ent(iEnt))
        return;

    static Float:fOrigin[3];
    fOrigin[0] = fBaseOrigin[0];
    fOrigin[1] = fBaseOrigin[1];
    fOrigin[2] = fBaseOrigin[2] + fOffset;

    entity_set_float(iEnt, EV_FL_frame, fFrame);
    entity_set_float(iEnt, EV_FL_scale, g_fSpriteScale);
    entity_set_origin(iEnt, fOrigin);
    SetMarkerScreenLayout(iEnt, fScreenX, fScreenY);
    SetPersistentEntityActive(iEnt, false);
    set_ent_rendering(iEnt, kRenderFxNone, iColor[0], iColor[1], iColor[2], kRenderTransAdd, 255);
}

HideEntity(const iEnt)
{
    if (!is_valid_ent(iEnt))
        return;

    ClearMarkerScreenLayout(iEnt);
    SetPersistentEntityActive(iEnt, false);
    set_ent_rendering(iEnt, kRenderFxNone, 0, 0, 0, kRenderTransAlpha, 0);
}

HidePlayerSprites(const id)
{
    HideMoneySprites(id);

    for (new i = 0; i < WEAPON_SPRITES; i++)
        HideEntity(g_iPlayerWeaponsSprites[id][i]);

    HideEntity(g_iPlayerArrow[id]);
    DeactivatePersistentMarkers(id);
}

HideAllSprites()
{
    for (new id = 1; id <= g_iMaxPlayers; id++) {
        if (g_bIsConnected[id])
            HidePlayerSprites(id);
    }
}

DeactivatePersistentMarkers(const id)
{
    for (new i = 0; i < HEALTH_SPRITES; i++)
        SetPersistentEntityActive(g_iPlayerMoneySprites[id][i], false);

    SetPersistentEntityActive(g_iPlayerDolarSign[id], false);
    for (new i = 0; i < WEAPON_SPRITES; i++)
        SetPersistentEntityActive(g_iPlayerWeaponsSprites[id][i], false);

    SetPersistentEntityActive(g_iPlayerArrow[id], false);
}

HidePersistentPlayerMarkers(const id)
{
    for (new i = 0; i < HEALTH_SPRITES; i++)
        HidePersistentEntity(g_iPlayerMoneySprites[id][i]);

    HidePersistentEntity(g_iPlayerDolarSign[id]);

    for (new i = 0; i < WEAPON_SPRITES; i++)
        HidePersistentEntity(g_iPlayerWeaponsSprites[id][i]);

    HidePersistentEntity(g_iPlayerArrow[id]);
}

HidePersistentEntity(const iEnt)
{
    HideEntity(iEnt);
    SetPersistentEntityActive(iEnt, false);
}

DisplayPersistentSprite(const iEnt, const Float:fBaseOrigin[3], Float:fFrame,
    const Float:fScreenX, const Float:fScreenY, const iColor[3])
{
    // All persistent entities share the arrow's exact world-space anchor.
    // Their full layout lives only in screen X/Y, so visible and projected
    // states use the same rigid matrix.
    DisplaySprite(iEnt, fBaseOrigin, fFrame, PERSISTENT_BLOCK_ANCHOR_OFFSET,
        fScreenX, fScreenY, iColor);
    SetPersistentEntityActive(iEnt, true);
}

UpdateOwnerSpatialState()
{
    for (new id = 1; id <= g_iMaxPlayers; id++) {
        if (!is_user_alive(id)) {
            // Death/removal is urgent: never leave an old block following a dead
            // owner while waiting for a semantic scheduler turn.
            if (g_bNetContentInitialized[id]) {
                HidePlayerSprites(id);
                g_bNetContentUrgent[id] = true;
            }

            g_bNetContentInitialized[id] = false;
            g_fNetContentLastUpdate[id] = 0.0;
            continue;
        }

        static Float:fOrigin[3];
        GetSpriteOrigin(id, fOrigin);

        g_fPersistentAnchor[id][0] = fOrigin[0];
        g_fPersistentAnchor[id][1] = fOrigin[1];
        g_fPersistentAnchor[id][2] = fOrigin[2] + PERSISTENT_BLOCK_ANCHOR_OFFSET;

        // Keep real env_sprite origins near the owner at the normal SET cadence.
        // AddToFullPack still rebuilds the final compact screen-plane origin per
        // observer. This prevents semantic refresh frequency from becoming
        // movement/PVS frequency, especially for normal-PVS enemy arrows.
        MoveActiveOwnerEntitiesToAnchor(id);
    }
}

MoveActiveEntityToOwnerAnchor(const id, const iEnt)
{
    if (!is_valid_ent(iEnt) || !IsOwnerEntityPhaseActive(iEnt))
        return;

    entity_set_origin(iEnt, g_fPersistentAnchor[id]);
}

MoveActiveOwnerEntitiesToAnchor(const id)
{
    for (new i = 0; i < HEALTH_SPRITES; i++)
        MoveActiveEntityToOwnerAnchor(id, g_iPlayerMoneySprites[id][i]);

    for (new i = 0; i < WEAPON_SPRITES; i++)
        MoveActiveEntityToOwnerAnchor(id, g_iPlayerWeaponsSprites[id][i]);

    MoveActiveEntityToOwnerAnchor(id, g_iPlayerDolarSign[id]);
    MoveActiveEntityToOwnerAnchor(id, g_iPlayerArrow[id]);
}

UpdatePersistentContentForOwner(const id)
{
    if (!is_user_alive(id)) {
        HidePersistentPlayerMarkers(id);
        return;
    }

    static Float:fOrigin[3];
    GetSpriteOrigin(id, fOrigin);
    new iWeapons = pev(id, pev_weapons);

    if (g_iShowArrow)
        ShowPersistentArrow(id, fOrigin);
    else
        HidePersistentEntity(g_iPlayerArrow[id]);

    if (g_iShowTeammatesWeapon)
        ShowPersistentWeaponCandidates(id, fOrigin, iWeapons);
    else {
        HidePersistentEntity(g_iPlayerWeaponsSprites[id][0]);
        HidePersistentEntity(g_iPlayerWeaponsSprites[id][1]);
    }

    if (g_iShowGrenades)
        ShowPersistentGrenades(id, fOrigin, iWeapons);
    else {
        HidePersistentEntity(g_iPlayerWeaponsSprites[id][2]);
        HidePersistentEntity(g_iPlayerWeaponsSprites[id][3]);
        HidePersistentEntity(g_iPlayerWeaponsSprites[id][4]);
    }

    // Armor remains a freezetime-only row in persistent mode.
    HidePersistentEntity(g_iPlayerWeaponsSprites[id][5]);

    if (g_iShowTeammatesObjective)
        ShowPersistentObjective(id, fOrigin, iWeapons);
    else
        HidePersistentEntity(g_iPlayerWeaponsSprites[id][6]);

    if (g_iShowTeammatesHealth)
        ShowPersistentHealth(id, fOrigin);
    else {
        g_iCachedHealthDisplayValue[id] = 0;
        for (new i = 0; i < HEALTH_SPRITES; i++)
            HidePersistentEntity(g_iPlayerMoneySprites[id][i]);
        HidePersistentEntity(g_iPlayerDolarSign[id]);
    }
}

UpdateAllPersistentContent()
{
    if (!HasPersistentDisplayEnabled())
        return;

    new Float:fNow = get_gametime();

    for (new id = 1; id <= g_iMaxPlayers; id++) {
        if (is_user_alive(id)) {
            UpdatePersistentContentForOwner(id);
            g_bNetContentInitialized[id] = true;
            g_bNetContentUrgent[id] = false;
            g_fNetContentLastUpdate[id] = fNow;
        }
        else {
            HidePersistentPlayerMarkers(id);
            g_bNetContentInitialized[id] = false;
        }
    }
}

UpdateFreezetimeContentForOwner(const id)
{
    if (is_user_alive(id))
        ShowAllPlayerSprites(id);
    else
        HidePlayerSprites(id);
}

UpdateAllFreezetimeContent()
{
    new Float:fNow = get_gametime();

    for (new id = 1; id <= g_iMaxPlayers; id++) {
        if (is_user_alive(id)) {
            UpdateFreezetimeContentForOwner(id);
            g_bNetContentInitialized[id] = true;
            g_bNetContentUrgent[id] = false;
            g_fNetContentLastUpdate[id] = fNow;
        }
        else {
            HidePlayerSprites(id);
            g_bNetContentInitialized[id] = false;
        }
    }
}

ResetNetContentCycle()
{
    g_iNetContentCycleCount = 0;
    g_iNetContentCycleCursor = 0;
    g_fNetContentCycleStart = 0.0;
    g_iNetContentLastBatch = 0;
}

ResetNetContentScheduler()
{
    g_fNextNetContentUpdate = 0.0;
    ResetNetContentCycle();

    for (new id = 1; id <= g_iMaxPlayers; id++) {
        g_bNetContentInitialized[id] = false;
        g_bNetContentUrgent[id] = false;
        g_fNetContentLastUpdate[id] = 0.0;
    }
}

MarkNetContentUrgent(const id)
{
    if (!IsPlayer(id))
        return;

    g_bNetContentInitialized[id] = false;
    g_bNetContentUrgent[id] = true;
    g_fNetContentLastUpdate[id] = 0.0;
    g_fNextNetContentUpdate = 0.0;
}

enum PersistentPairDisplay {
    PAIR_DISPLAY_NONE = 0,
    PAIR_DISPLAY_FULL,
    PAIR_DISPLAY_ENEMY_ARROW
};

Float:GetOwnerContentPriorityDistanceSquared(const iOwner)
{
    new bool:bFoundViewer = false;
    new Float:fBest = 999999999.0;

    for (new iHost = 1; iHost <= g_iMaxPlayers; iHost++) {
        if (!is_user_connected(iHost) || is_user_bot(iHost) || iHost == iOwner)
            continue;

        if (GetPersistentPairDisplay(iHost, iOwner) == PAIR_DISPLAY_NONE)
            continue;

        UpdateViewerCameraState(iHost);

        new Float:fX = g_fPersistentAnchor[iOwner][0] - g_fViewerCameraOrigin[iHost][0];
        new Float:fY = g_fPersistentAnchor[iOwner][1] - g_fViewerCameraOrigin[iHost][1];
        new Float:fZ = g_fPersistentAnchor[iOwner][2] - g_fViewerCameraOrigin[iHost][2];
        new Float:fDistance = fX * fX + fY * fY + fZ * fZ;

        if (!bFoundViewer || fDistance < fBest) {
            fBest = fDistance;
            bFoundViewer = true;
        }
    }

    if (!bFoundViewer)
        return 999999999.0;

    return fBest;
}

BuildNetContentCycle(const Float:fNow)
{
    g_iNetContentCycleCount = 0;
    g_iNetContentCycleCursor = 0;
    g_fNetContentCycleStart = fNow;

    for (new iHost = 1; iHost <= g_iMaxPlayers; iHost++) {
        if (is_user_connected(iHost) && !is_user_bot(iHost))
            UpdateViewerCameraState(iHost);
    }

    for (new id = 1; id <= g_iMaxPlayers; id++) {
        if (!is_user_alive(id))
            continue;

        new iPos = g_iNetContentCycleCount++;
        g_iNetContentCycleOwners[iPos] = id;
        g_fNetContentCycleDistance[iPos] = GetOwnerContentPriorityDistanceSquared(id);
    }

    // Sort ONCE per complete cycle. Distance only determines who receives the
    // freshest semantic state first; every live owner remains in the cycle, so
    // far players cannot starve even on wider 64/128-player forks.
    for (new i = 1; i < g_iNetContentCycleCount; i++) {
        new iOwner = g_iNetContentCycleOwners[i];
        new Float:fDistance = g_fNetContentCycleDistance[i];
        new j = i - 1;

        while (j >= 0 && g_fNetContentCycleDistance[j] > fDistance) {
            g_iNetContentCycleOwners[j + 1] = g_iNetContentCycleOwners[j];
            g_fNetContentCycleDistance[j + 1] = g_fNetContentCycleDistance[j];
            j--;
        }

        g_iNetContentCycleOwners[j + 1] = iOwner;
        g_fNetContentCycleDistance[j + 1] = fDistance;
    }
}

FindNearestUrgentContentOwner()
{
    new iBestOwner = 0;
    new Float:fBestDistance = 999999999.0;

    for (new id = 1; id <= g_iMaxPlayers; id++) {
        if (!is_user_alive(id) || !g_bNetContentUrgent[id])
            continue;

        new Float:fDistance = GetOwnerContentPriorityDistanceSquared(id);
        if (!iBestOwner || fDistance < fBestDistance) {
            iBestOwner = id;
            fBestDistance = fDistance;
        }
    }

    return iBestOwner;
}

RefreshScheduledOwnerContent(const id, const Float:fNow)
{
    if (!is_user_alive(id)) {
        HidePlayerSprites(id);
        g_bNetContentInitialized[id] = false;
        g_fNetContentLastUpdate[id] = 0.0;
        return;
    }

    if (g_bPersistentPhase)
        UpdatePersistentContentForOwner(id);
    else
        UpdateFreezetimeContentForOwner(id);

    g_bNetContentInitialized[id] = true;
    g_bNetContentUrgent[id] = false;
    g_fNetContentLastUpdate[id] = fNow;
}

UpdateScheduledNetContent(const Float:fNow)
{
    new iRemaining = g_iNetContentBatch;
    g_iNetContentLastBatch = 0;

    // New round, respawn and team-change blocks are urgent. They still enter as
    // complete owner units and respect the same per-step batch limit.
    while (iRemaining > 0) {
        new iOwner = FindNearestUrgentContentOwner();
        if (!iOwner)
            break;

        RefreshScheduledOwnerContent(iOwner, fNow);
        iRemaining--;
        g_iNetContentLastBatch++;
    }

    if (iRemaining <= 0)
        return;

    if (g_iNetContentCycleCursor >= g_iNetContentCycleCount)
        BuildNetContentCycle(fNow);

    while (iRemaining > 0 && g_iNetContentCycleCursor < g_iNetContentCycleCount) {
        new iOwner = g_iNetContentCycleOwners[g_iNetContentCycleCursor++];

        if (!is_user_alive(iOwner))
            continue;

        // An urgent refresh can service an owner already present in the current
        // cycle. Do not update that same block twice in one cycle.
        if (g_fNetContentLastUpdate[iOwner] >= g_fNetContentCycleStart)
            continue;

        RefreshScheduledOwnerContent(iOwner, fNow);
        iRemaining--;
        g_iNetContentLastBatch++;
    }
}

ShowPersistentArrow(const id, const Float:fOrigin[3])
{
    static iColor[3];
    GetOwnerTeamStatusColor(id, iColor);
    DisplayPersistentSprite(g_iPlayerArrow[id], fOrigin,
        float(STATUS_FRAME_ARROW), PERSISTENT_ARROW_X, PERSISTENT_ARROW_Y, iColor);
}

ShowPersistentWeaponCandidates(const id, const Float:fOrigin[3], const iWeapons)
{
    static iColor[3];
    GetColor(CVAR_SPRITE_WEAPON_COLOR, iColor);

    new bool:bPrimary = false;
    for (new i = 0; i < sizeof(iPrimaryWeapons); i++) {
        new iWeapon = iPrimaryWeapons[i];
        if (iWeapons & (1 << iWeapon)) {
            DisplayPersistentSprite(g_iPlayerWeaponsSprites[id][1], fOrigin,
                float(GetStatusFrameForWeaponId(iWeapon)), FREEZE_PRIMARY_X, PERSISTENT_WEAPON_Y, iColor);
            bPrimary = true;
            break;
        }
    }
    if (!bPrimary)
        HidePersistentEntity(g_iPlayerWeaponsSprites[id][1]);

    new bool:bSecondary = false;
    for (new i = 0; i < sizeof(iPistols); i++) {
        new iWeapon = iPistols[i];
        if (iWeapons & (1 << iWeapon)) {
            DisplayPersistentSprite(g_iPlayerWeaponsSprites[id][0], fOrigin,
                float(GetStatusFrameForWeaponId(iWeapon)), FREEZE_SECONDARY_X, PERSISTENT_WEAPON_Y, iColor);
            bSecondary = true;
            break;
        }
    }
    if (!bSecondary)
        HidePersistentEntity(g_iPlayerWeaponsSprites[id][0]);
}

ShowPersistentGrenades(const id, const Float:fOrigin[3], const iWeapons)
{
    static iColor[3];
    GetOwnerTeamStatusColor(id, iColor);

    if (iWeapons & (1 << CSW_HEGRENADE))
        DisplayPersistentSprite(g_iPlayerWeaponsSprites[id][2], fOrigin,
            float(STATUS_FRAME_HEGRENADE), FREEZE_HE_X, PERSISTENT_OBJECTIVE_Y, iColor);
    else
        HidePersistentEntity(g_iPlayerWeaponsSprites[id][2]);

    if (iWeapons & (1 << CSW_FLASHBANG))
        DisplayPersistentSprite(g_iPlayerWeaponsSprites[id][3], fOrigin,
            float(STATUS_FRAME_FLASHBANG), FREEZE_FLASH_X, PERSISTENT_OBJECTIVE_Y, iColor);
    else
        HidePersistentEntity(g_iPlayerWeaponsSprites[id][3]);

    if (iWeapons & (1 << CSW_SMOKEGRENADE))
        DisplayPersistentSprite(g_iPlayerWeaponsSprites[id][4], fOrigin,
            float(STATUS_FRAME_SMOKEGRENADE), FREEZE_SMOKE_X, PERSISTENT_OBJECTIVE_Y, iColor);
    else
        HidePersistentEntity(g_iPlayerWeaponsSprites[id][4]);
}

ShowPersistentObjective(const id, const Float:fOrigin[3], const iWeapons)
{
    static iColor[3];

    GetOwnerTeamStatusColor(id, iColor);

    if (iWeapons & (1 << CSW_C4)) {
        DisplayPersistentSprite(g_iPlayerWeaponsSprites[id][6], fOrigin,
            float(STATUS_FRAME_C4), 0.0, PERSISTENT_OBJECTIVE_Y, iColor);
        return;
    }

    if (cs_get_user_defuse(id)) {
        DisplayPersistentSprite(g_iPlayerWeaponsSprites[id][6], fOrigin,
            float(STATUS_FRAME_DEFUSE), 0.0, PERSISTENT_OBJECTIVE_Y, iColor);
        return;
    }

    HidePersistentEntity(g_iPlayerWeaponsSprites[id][6]);
}

Float:GetHealthDigitX(const iIndex)
{
    return HEALTH_DIGIT_START_X + float(iIndex) * HEALTH_DIGIT_STEP_X;
}

GetHealthDisplayValue(const id)
{
    new iHealth = get_user_health(id);
    if (iHealth < 0)
        iHealth = 0;

    switch (g_iHealthDisplayMode) {
        case 0: {
            // Compatibility mode: preserve the old +999 ceiling.
            if (iHealth > 999)
                return 999;
            return iHealth;
        }

        case 1: {
            if (iHealth <= 0)
                return 0;

            new iBaseline = g_iHealthBaseline[id];

            // Auto-diagnosis by maximum observed HP. This is not a new poll:
            // SET already reads current HP to draw the health row. If gameplay
            // raises 2500 -> 5000, 5000 becomes the new 100% immediately.
            if (iHealth > iBaseline) {
                g_iHealthBaseline[id] = iHealth;
                g_iHealthBaselineRetries[id] = 0;
                remove_task(TASK_HEALTH_BASELINE_BASE + id);
                iBaseline = iHealth;
            }

            if (iBaseline <= 0)
                return 100; // baseline task is still settling after spawn/team change

            new iPercent = floatround((float(iHealth) * 100.0) / float(iBaseline));
            return clamp(iPercent, 0, 100);
        }
    }

    // Mode 2: every positive Pawn integer is representable by 10 digit sprites.
    return iHealth;
}

ShowPersistentHealth(const id, const Float:fOrigin[3])
{
    new iHealth = GetHealthDisplayValue(id);
    g_iCachedHealthDisplayValue[id] = iHealth;

    static iColor[3];
    if (iHealth <= g_iHealthLowThreshold)
        SetColorArray(iColor, g_iLowHealthColor);
    else
        GetOwnerTeamStatusColor(id, iColor);

    // Percentage mode substitutes the normal health/+ icon with the skull.
    // Layout remains one rigid row: skull + digits share the same matrix.
    new iIconFrame = (g_iHealthDisplayMode == 1)
        ? STATUS_FRAME_PERCENT
        : STATUS_FRAME_HEALTH;

    DisplayPersistentSprite(g_iPlayerDolarSign[id], fOrigin,
        float(iIconFrame), MONEY_ICON_X, PERSISTENT_HEALTH_Y, iColor);

    static szHealth[HEALTH_SPRITES + 1];
    num_to_str(iHealth, szHealth, charsmax(szHealth));

    for (new i = 0; i < HEALTH_SPRITES; i++) {
        if (!szHealth[i]) {
            HidePersistentEntity(g_iPlayerMoneySprites[id][i]);
            continue;
        }

        new iDigit = szHealth[i] - '0';
        DisplayPersistentSprite(g_iPlayerMoneySprites[id][i], fOrigin,
            float(GetDigitFrame(iDigit)), GetHealthDigitX(i), PERSISTENT_HEALTH_Y, iColor);
    }
}

PersistentPairDisplay:GetPersistentPairDisplay(const iHost, const iOwner)
{
    if (!IsPlayer(iHost) || !IsPlayer(iOwner) || iHost == iOwner)
        return PAIR_DISPLAY_NONE;

    if (!is_user_connected(iHost) || !is_user_alive(iOwner))
        return PAIR_DISPLAY_NONE;

    new CsTeams:iHostTeam = g_iPlayerTeam[iHost];
    new CsTeams:iOwnerTeam = g_iPlayerTeam[iOwner];

    if (iOwnerTeam != CS_TEAM_T && iOwnerTeam != CS_TEAM_CT)
        return PAIR_DISPLAY_NONE;

    // A real spectator has no competitive team, so it can use the complete
    // CS2-style information for both sides.
    if (iHostTeam == CS_TEAM_SPECTATOR)
        return PAIR_DISPLAY_FULL;

    if (iHostTeam != CS_TEAM_T && iHostTeam != CS_TEAM_CT)
        return PAIR_DISPLAY_NONE;

    new bool:bSameTeam = (iHostTeam == iOwnerTeam);

    if (bSameTeam) {
        if (g_iShowArrowMode == 0 || g_iShowArrowMode == 1)
            return PAIR_DISPLAY_FULL;

        return PAIR_DISPLAY_NONE;
    }

    if (g_iShowArrowMode == 0 || g_iShowArrowMode == 2)
        return PAIR_DISPLAY_ENEMY_ARROW;

    return PAIR_DISPLAY_NONE;
}

ResetNetLodForPlayer(const id)
{
    if (id < 1 || id > MAX_PLAYERS)
        return;

    g_bNetDegraded[id] = false;
    g_iNetRequestedSprites[id] = 0;
    g_iNetTargetSprites[id] = 0;
    g_iNetAllowedSprites[id] = 0;
    g_iNetRampCredit[id] = 0;
    g_iNetFullPlusPairs[id] = 0;
    g_iNetFullPairs[id] = 0;
    g_iNetReducedPairs[id] = 0;
    g_iNetMinimalPairs[id] = 0;
    g_iNetHiddenPairs[id] = 0;
    g_bNetContentInitialized[id] = false;
    g_bNetContentUrgent[id] = false;
    g_fNetContentLastUpdate[id] = 0.0;

    for (new i = 1; i <= g_iMaxPlayers; i++) {
        g_iNetPairLod[id][i] = NET_LOD_NONE;
        g_iNetPairLod[i][id] = NET_LOD_NONE;
        g_iNetTargetLod[id][i] = NET_LOD_NONE;
        g_iNetTargetLod[i][id] = NET_LOD_NONE;
        g_iNetSentMarkerMask[id][i] = 0;
        g_iNetSentMarkerMask[i][id] = 0;
    }
}

ResetAllNetLod()
{
    for (new iHost = 1; iHost <= g_iMaxPlayers; iHost++) {
        g_bNetDegraded[iHost] = false;
        g_iNetRequestedSprites[iHost] = 0;
        g_iNetTargetSprites[iHost] = 0;
        g_iNetAllowedSprites[iHost] = 0;
        g_iNetRampCredit[iHost] = 0;
        g_iNetFullPlusPairs[iHost] = 0;
        g_iNetFullPairs[iHost] = 0;
        g_iNetReducedPairs[iHost] = 0;
        g_iNetMinimalPairs[iHost] = 0;
        g_iNetHiddenPairs[iHost] = 0;

        for (new iOwner = 1; iOwner <= g_iMaxPlayers; iOwner++) {
            g_iNetPairLod[iHost][iOwner] = NET_LOD_NONE;
            g_iNetTargetLod[iHost][iOwner] = NET_LOD_NONE;
            g_iNetSentMarkerMask[iHost][iOwner] = 0;
        }
    }
}

GetOwnerMarkerBit(const iOwner, const iEnt)
{
    if (!IsPlayer(iOwner) || iEnt <= 0)
        return 0;

    for (new i = 0; i < HEALTH_SPRITES; i++) {
        if (g_iPlayerMoneySprites[iOwner][i] == iEnt)
            return (1 << i);
    }

    for (new i = 0; i < WEAPON_SPRITES; i++) {
        if (g_iPlayerWeaponsSprites[iOwner][i] == iEnt)
            return (1 << (HEALTH_SPRITES + i));
    }

    if (g_iPlayerDolarSign[iOwner] == iEnt)
        return (1 << (HEALTH_SPRITES + WEAPON_SPRITES));

    if (g_iPlayerArrow[iOwner] == iEnt)
        return (1 << (HEALTH_SPRITES + WEAPON_SPRITES + 1));

    return 0;
}

bool:IsOwnerEntityPhaseActive(const iEnt)
{
    if (iEnt <= 0 || iEnt > MAX_TRACKED_EDICTS)
        return false;

    if (g_bPersistentPhase)
        return g_bPersistentEntActive[iEnt];

    return g_bMarkerLayoutActive[iEnt];
}

bool:IsPrimaryWeaponMarker(const iOwner, const iEnt)
{
    return bool:(g_iPlayerWeaponsSprites[iOwner][1] == iEnt);
}

bool:IsSecondaryWeaponMarker(const iOwner, const iEnt)
{
    return bool:(g_iPlayerWeaponsSprites[iOwner][0] == iEnt);
}

bool:IsHealthRowMarker(const iOwner, const iEnt)
{
    if (g_iPlayerDolarSign[iOwner] == iEnt)
        return true;

    for (new i = 0; i < HEALTH_SPRITES; i++) {
        if (g_iPlayerMoneySprites[iOwner][i] == iEnt)
            return true;
    }

    return false;
}

bool:IsPersistentEntityAllowedAtLod(const iHost, const iOwner, const iEnt, const NetPairLod:iLod)
{
    if (iLod == NET_LOD_NONE || !IsOwnerEntityPhaseActive(iEnt))
        return false;

    if (iEnt == g_iPlayerArrow[iOwner])
        return bool:(iLod >= NET_LOD_MINIMAL && g_iShowArrow && g_bClientShowArrow[iHost]);

    if (IsHealthRowMarker(iOwner, iEnt))
        return bool:(iLod >= NET_LOD_FULL && g_iShowTeammatesHealth && g_bClientShowHealth[iHost]);

    if (iEnt == g_iPlayerWeaponsSprites[iOwner][6])
        return bool:(iLod >= NET_LOD_REDUCED && g_iShowTeammatesObjective && g_bClientShowObjective[iHost]);

    for (new i = 2; i <= 4; i++) {
        if (iEnt == g_iPlayerWeaponsSprites[iOwner][i])
            return bool:(iLod >= NET_LOD_FULLPLUS && g_iShowGrenades && g_bClientShowGrenades[iHost]);
    }

    if (iEnt == g_iPlayerWeaponsSprites[iOwner][5])
        return false;

    if (IsPrimaryWeaponMarker(iOwner, iEnt) || IsSecondaryWeaponMarker(iOwner, iEnt)) {
        if (iLod < NET_LOD_REDUCED || !g_iShowTeammatesWeapon || g_iClientWeaponsMode[iHost] <= 0)
            return false;

        new iPrimary = g_iPlayerWeaponsSprites[iOwner][1];
        new iSecondary = g_iPlayerWeaponsSprites[iOwner][0];
        new bool:bPrimaryActive = IsOwnerEntityPhaseActive(iPrimary);
        new bool:bSecondaryActive = IsOwnerEntityPhaseActive(iSecondary);

        if (g_iClientWeaponsMode[iHost] == 1)
            return bool:(iEnt == iPrimary && bPrimaryActive);

        if (iLod >= NET_LOD_FULLPLUS)
            return bool:((iEnt == iPrimary && bPrimaryActive) || (iEnt == iSecondary && bSecondaryActive));

        // Normal REDUCED/FULL preserves the old preferred-weapon behavior.
        if (bPrimaryActive)
            return bool:(iEnt == iPrimary);

        return bool:(iEnt == iSecondary && bSecondaryActive);
    }

    return false;
}

bool:IsFreezetimeEntityAllowedAtLod(const iHost, const iOwner, const iEnt, const NetPairLod:iLod)
{
    if (iLod == NET_LOD_NONE || !IsOwnerEntityPhaseActive(iEnt))
        return false;

    if (iEnt == g_iPlayerArrow[iOwner])
        return bool:(iLod >= NET_LOD_MINIMAL && g_iShowArrow && g_bClientShowArrow[iHost]);

    // In freezetime these same entities carry money, not health.
    if (IsHealthRowMarker(iOwner, iEnt))
        return bool:(iLod >= NET_LOD_FULL && g_iShowMoney);

    if (iEnt == g_iPlayerWeaponsSprites[iOwner][6])
        return bool:(iLod >= NET_LOD_REDUCED && g_iShowTeammatesObjective && g_bClientShowObjective[iHost]);

    for (new i = 2; i <= 4; i++) {
        if (iEnt == g_iPlayerWeaponsSprites[iOwner][i])
            return bool:(iLod >= NET_LOD_FULL && g_iShowGrenades && g_bClientShowGrenades[iHost]);
    }

    if (iEnt == g_iPlayerWeaponsSprites[iOwner][5])
        return bool:(iLod >= NET_LOD_FULL && g_iShowArmor);

    if (IsPrimaryWeaponMarker(iOwner, iEnt) || IsSecondaryWeaponMarker(iOwner, iEnt)) {
        if (iLod < NET_LOD_REDUCED || !g_iShowWeapons || g_iClientWeaponsMode[iHost] <= 0)
            return false;

        new iPrimary = g_iPlayerWeaponsSprites[iOwner][1];
        new iSecondary = g_iPlayerWeaponsSprites[iOwner][0];
        new bool:bPrimaryActive = IsOwnerEntityPhaseActive(iPrimary);
        new bool:bSecondaryActive = IsOwnerEntityPhaseActive(iSecondary);

        if (g_iClientWeaponsMode[iHost] == 1)
            return bool:(iEnt == iPrimary && bPrimaryActive);

        // Freezetime FULL already means its traditional rich equipment view.
        if (iLod >= NET_LOD_FULL)
            return bool:((iEnt == iPrimary && bPrimaryActive) || (iEnt == iSecondary && bSecondaryActive));

        if (bPrimaryActive)
            return bool:(iEnt == iPrimary);

        return bool:(iEnt == iSecondary && bSecondaryActive);
    }

    return false;
}

bool:IsSetEntityAllowedAtLod(const iHost, const iOwner, const iEnt, const NetPairLod:iLod)
{
    if (!IsPlayer(iHost) || !IsPlayer(iOwner) || iEnt <= 0 || iEnt > MAX_TRACKED_EDICTS)
        return false;

    if (g_bPersistentPhase)
        return IsPersistentEntityAllowedAtLod(iHost, iOwner, iEnt, iLod);

    return IsFreezetimeEntityAllowedAtLod(iHost, iOwner, iEnt, iLod);
}

GetOwnerNetCost(const iHost, const iOwner, const NetPairLod:iLod)
{
    if (!IsPlayer(iHost) || !IsPlayer(iOwner) || iLod == NET_LOD_NONE)
        return 0;

    new iCost = 0;

    for (new i = 0; i < HEALTH_SPRITES; i++) {
        if (IsSetEntityAllowedAtLod(iHost, iOwner, g_iPlayerMoneySprites[iOwner][i], iLod))
            iCost++;
    }

    for (new i = 0; i < WEAPON_SPRITES; i++) {
        if (IsSetEntityAllowedAtLod(iHost, iOwner, g_iPlayerWeaponsSprites[iOwner][i], iLod))
            iCost++;
    }

    if (IsSetEntityAllowedAtLod(iHost, iOwner, g_iPlayerDolarSign[iOwner], iLod))
        iCost++;

    if (IsSetEntityAllowedAtLod(iHost, iOwner, g_iPlayerArrow[iOwner], iLod))
        iCost++;

    return iCost;
}

NetPairLod:GetRequestedLodForPair(const iHost, const PersistentPairDisplay:iDisplay)
{
    if (iDisplay == PAIR_DISPLAY_NONE || !IsPlayer(iHost))
        return NET_LOD_NONE;

    new NetPairLod:iCap = g_iClientDetailCap[iHost];

    if (iDisplay == PAIR_DISPLAY_ENEMY_ARROW) {
        if (iCap >= NET_LOD_MINIMAL)
            return NET_LOD_MINIMAL;
        return NET_LOD_NONE;
    }

    return iCap;
}

GetAllowedNetCostForPair(const iHost, const PersistentPairDisplay:iDisplay, const iOwner)
{
    if (iDisplay == PAIR_DISPLAY_NONE)
        return 0;

    new NetPairLod:iLod = g_iNetPairLod[iHost][iOwner];
    if (iDisplay == PAIR_DISPLAY_ENEMY_ARROW && iLod > NET_LOD_MINIMAL)
        iLod = NET_LOD_MINIMAL;

    return GetOwnerNetCost(iHost, iOwner, iLod);
}

bool:IsNetMarkerAllowedForHost(const iHost, const iOwner, const iEnt)
{
    if (!IsPlayer(iHost) || !IsPlayer(iOwner))
        return false;

    new PersistentPairDisplay:iDisplay = GetPersistentPairDisplay(iHost, iOwner);
    if (iDisplay == PAIR_DISPLAY_NONE)
        return false;

    new NetPairLod:iLod;

    if (!g_iNetAdaptive || is_user_bot(iHost))
        iLod = GetRequestedLodForPair(iHost, iDisplay);
    else
        iLod = g_iNetPairLod[iHost][iOwner];

    if (iDisplay == PAIR_DISPLAY_ENEMY_ARROW && iLod > NET_LOD_MINIMAL)
        iLod = NET_LOD_MINIMAL;

    return IsSetEntityAllowedAtLod(iHost, iOwner, iEnt, iLod);
}

SetUnrestrictedNetLodForHost(const iHost)
{
    new iTarget = 0;
    new iAllowed = 0;

    for (new iOwner = 1; iOwner <= g_iMaxPlayers; iOwner++) {
        new PersistentPairDisplay:iDisplay = GetPersistentPairDisplay(iHost, iOwner);
        new NetPairLod:iLod = GetRequestedLodForPair(iHost, iDisplay);

        if (GetOwnerNetCost(iHost, iOwner, iLod) <= 0)
            iLod = NET_LOD_NONE;

        g_iNetTargetLod[iHost][iOwner] = iLod;
        g_iNetPairLod[iHost][iOwner] = iLod;

        iTarget += GetOwnerNetCost(iHost, iOwner, iLod);
        iAllowed += GetOwnerNetCost(iHost, iOwner, iLod);
    }

    g_iNetTargetSprites[iHost] = iTarget;
    g_iNetAllowedSprites[iHost] = iAllowed;
    CountNetLodPairs(iHost);
}

CountNetLodPairs(const iHost)
{
    g_iNetFullPlusPairs[iHost] = 0;
    g_iNetFullPairs[iHost] = 0;
    g_iNetReducedPairs[iHost] = 0;
    g_iNetMinimalPairs[iHost] = 0;
    g_iNetHiddenPairs[iHost] = 0;

    for (new iOwner = 1; iOwner <= g_iMaxPlayers; iOwner++) {
        if (GetPersistentPairDisplay(iHost, iOwner) == PAIR_DISPLAY_NONE)
            continue;

        switch (g_iNetPairLod[iHost][iOwner]) {
            case NET_LOD_FULLPLUS: g_iNetFullPlusPairs[iHost]++;
            case NET_LOD_FULL: g_iNetFullPairs[iHost]++;
            case NET_LOD_REDUCED: g_iNetReducedPairs[iHost]++;
            case NET_LOD_MINIMAL: g_iNetMinimalPairs[iHost]++;
            default: g_iNetHiddenPairs[iHost]++;
        }
    }
}

Float:GetNetPairDistanceSquared(const iHost, const iOwner)
{
    new Float:fX = g_fPersistentAnchor[iOwner][0] - g_fViewerCameraOrigin[iHost][0];
    new Float:fY = g_fPersistentAnchor[iOwner][1] - g_fViewerCameraOrigin[iHost][1];
    new Float:fZ = g_fPersistentAnchor[iOwner][2] - g_fViewerCameraOrigin[iHost][2];
    return fX * fX + fY * fY + fZ * fZ;
}

SortNetCandidatesByDistance(const iHost, iOwners[MAX_PLAYERS], const iCount)
{
    for (new i = 1; i < iCount; i++) {
        new iOwner = iOwners[i];
        new Float:fDistance = GetNetPairDistanceSquared(iHost, iOwner);
        new j = i - 1;

        while (j >= 0 && GetNetPairDistanceSquared(iHost, iOwners[j]) > fDistance) {
            iOwners[j + 1] = iOwners[j];
            j--;
        }

        iOwners[j + 1] = iOwner;
    }
}

ApplyImmediateNetReductions(const iHost)
{
    for (new iOwner = 1; iOwner <= g_iMaxPlayers; iOwner++) {
        if (g_iNetPairLod[iHost][iOwner] > g_iNetTargetLod[iHost][iOwner])
            g_iNetPairLod[iHost][iOwner] = g_iNetTargetLod[iHost][iOwner];
    }
}

RecountCurrentNetCost(const iHost)
{
    new iAllowed = 0;

    for (new iOwner = 1; iOwner <= g_iMaxPlayers; iOwner++)
        iAllowed += GetAllowedNetCostForPair(iHost, GetPersistentPairDisplay(iHost, iOwner), iOwner);

    g_iNetAllowedSprites[iHost] = iAllowed;
    CountNetLodPairs(iHost);
}

RecountTargetNetCost(const iHost)
{
    new iTarget = 0;

    for (new iOwner = 1; iOwner <= g_iMaxPlayers; iOwner++)
        iTarget += GetOwnerNetCost(iHost, iOwner, g_iNetTargetLod[iHost][iOwner]);

    g_iNetTargetSprites[iHost] = iTarget;
}

ClampTargetToRequested(const iHost)
{
    for (new iOwner = 1; iOwner <= g_iMaxPlayers; iOwner++) {
        new PersistentPairDisplay:iDisplay = GetPersistentPairDisplay(iHost, iOwner);
        new NetPairLod:iRequested = GetRequestedLodForPair(iHost, iDisplay);

        if (g_iNetTargetLod[iHost][iOwner] > iRequested)
            g_iNetTargetLod[iHost][iOwner] = iRequested;

        if (GetOwnerNetCost(iHost, iOwner, g_iNetTargetLod[iHost][iOwner]) <= 0)
            g_iNetTargetLod[iHost][iOwner] = NET_LOD_NONE;
    }
}

ResetNetQualityForPlayer(const id)
{
    if (id < 1 || id > MAX_PLAYERS)
        return;

    g_bNetQualityInitialized[id] = false;
    g_iNetQualityState[id] = NET_QUALITY_GOOD;
    g_iNetQualityEffectiveBudget[id] = g_iNetSpriteBudget;
    g_iNetQualityGoodSamples[id] = 0;
    g_fNetQualityPingAverage[id] = 0.0;
    g_fNetQualityPingBaseline[id] = 0.0;
    g_fNetQualityLossAverage[id] = 0.0;
}

GetEffectiveNetBudgetForHost(const iHost)
{
    if (!g_iNetAdaptive || !g_iNetQualityAdaptive || is_user_bot(iHost))
        return g_iNetSpriteBudget;

    new iBudget = g_iNetQualityEffectiveBudget[iHost];

    if (iBudget <= 0)
        iBudget = g_iNetSpriteBudget;

    if (iBudget > g_iNetSpriteBudget)
        iBudget = g_iNetSpriteBudget;
    if (iBudget < g_iNetQualityMinBudget)
        iBudget = g_iNetQualityMinBudget;

    return iBudget;
}

GetNetQualityStateName(const iLang, const NetQualityState:iState, szName[], const iLen)
{
    switch (iState) {
        case NET_QUALITY_SOFT: formatex(szName, iLen, "%L", iLang, "SET_QUALITY_SOFT");
        case NET_QUALITY_HARD: formatex(szName, iLen, "%L", iLang, "SET_QUALITY_HARD");
        default: formatex(szName, iLen, "%L", iLang, "SET_QUALITY_GOOD");
    }
}

bool:UpdateNetQualityForHost(const iHost)
{
    if (!IsPlayer(iHost) || !is_user_connected(iHost) || is_user_bot(iHost))
        return false;

    new iPing, iLoss;
    get_user_ping(iHost, iPing, iLoss);

    if (iPing < 0)
        iPing = 0;
    if (iLoss < 0)
        iLoss = 0;
    else if (iLoss > 100)
        iLoss = 100;

    new Float:fPing = float(iPing);
    new Float:fLoss = float(iLoss);

    if (!g_bNetQualityInitialized[iHost]) {
        g_bNetQualityInitialized[iHost] = true;
        g_fNetQualityPingAverage[iHost] = fPing;
        g_fNetQualityPingBaseline[iHost] = fPing;
        g_fNetQualityLossAverage[iHost] = fLoss;
        g_iNetQualityEffectiveBudget[iHost] = g_iNetSpriteBudget;
        g_iNetQualityState[iHost] = NET_QUALITY_GOOD;
        g_iNetQualityGoodSamples[iHost] = 0;
        return false;
    }

    // Short EMA: enough to ignore a single transient scoreboard sample while
    // still reacting within a few seconds to sustained SET-induced pressure.
    g_fNetQualityPingAverage[iHost] = g_fNetQualityPingAverage[iHost] * 0.70 + fPing * 0.30;
    g_fNetQualityLossAverage[iHost] = g_fNetQualityLossAverage[iHost] * 0.70 + fLoss * 0.30;

    // Baseline behaves as a low-water mark. It follows improvements immediately,
    // but rises only 0.10 ms per quality sample so sustained SET load cannot be
    // quickly "learned" as the client's new normal ping.
    if (g_fNetQualityPingAverage[iHost] < g_fNetQualityPingBaseline[iHost]) {
        g_fNetQualityPingBaseline[iHost] = g_fNetQualityPingAverage[iHost];
    }
    else if (g_fNetQualityPingBaseline[iHost] < g_fNetQualityPingAverage[iHost]) {
        g_fNetQualityPingBaseline[iHost] += 0.10;
        if (g_fNetQualityPingBaseline[iHost] > g_fNetQualityPingAverage[iHost])
            g_fNetQualityPingBaseline[iHost] = g_fNetQualityPingAverage[iHost];
    }

    new iOldBudget = GetEffectiveNetBudgetForHost(iHost);

    if (!g_iNetAdaptive || !g_iNetQualityAdaptive) {
        g_iNetQualityState[iHost] = NET_QUALITY_GOOD;
        g_iNetQualityGoodSamples[iHost] = 0;
        g_iNetQualityEffectiveBudget[iHost] = g_iNetSpriteBudget;
        return bool:(iOldBudget != g_iNetSpriteBudget);
    }

    new Float:fPingDelta = g_fNetQualityPingAverage[iHost] - g_fNetQualityPingBaseline[iHost];
    if (fPingDelta < 0.0)
        fPingDelta = 0.0;

    new NetQualityState:iState = NET_QUALITY_GOOD;

    if (fPingDelta >= float(g_iNetPingHardDelta) ||
        iLoss >= g_iNetLossHard || g_fNetQualityLossAverage[iHost] >= float(g_iNetLossHard)) {
        iState = NET_QUALITY_HARD;
    }
    else if (fPingDelta >= float(g_iNetPingSoftDelta) ||
             iLoss >= g_iNetLossSoft || g_fNetQualityLossAverage[iHost] >= float(g_iNetLossSoft)) {
        iState = NET_QUALITY_SOFT;
    }

    g_iNetQualityState[iHost] = iState;

    new iBudget = iOldBudget;

    switch (iState) {
        case NET_QUALITY_HARD: {
            g_iNetQualityGoodSamples[iHost] = 0;
            iBudget -= g_iNetQualityStepDown * 2;
        }
        case NET_QUALITY_SOFT: {
            g_iNetQualityGoodSamples[iHost] = 0;
            iBudget -= g_iNetQualityStepDown;
        }
        default: {
            if (iBudget < g_iNetSpriteBudget) {
                g_iNetQualityGoodSamples[iHost]++;

                if (g_iNetQualityGoodSamples[iHost] >= g_iNetQualityRecoverSamples) {
                    iBudget += g_iNetQualityStepUp;
                    g_iNetQualityGoodSamples[iHost] = 0;
                }
            }
            else {
                g_iNetQualityGoodSamples[iHost] = 0;
            }
        }
    }

    if (iBudget < g_iNetQualityMinBudget)
        iBudget = g_iNetQualityMinBudget;
    else if (iBudget > g_iNetSpriteBudget)
        iBudget = g_iNetSpriteBudget;

    g_iNetQualityEffectiveBudget[iHost] = iBudget;
    return bool:(iBudget != iOldBudget);
}

UpdateNetQuality()
{
    new bool:bBudgetChanged = false;

    for (new iHost = 1; iHost <= g_iMaxPlayers; iHost++) {
        if (!is_user_connected(iHost) || is_user_bot(iHost))
            continue;

        if (UpdateNetQualityForHost(iHost))
            bBudgetChanged = true;
    }

    if (bBudgetChanged) {
        // A quality reduction must become a LOD reduction immediately on the
        // next controller pass; recovery still goes through normal LOD+ramp.
        g_fNextNetLodUpdate = 0.0;
    }
}

RebuildAdaptiveNetLodForHost(const iHost)
{
    static iOwners[MAX_PLAYERS];
    new iCount = 0;
    new iRequested = 0;
    new iBudget = GetEffectiveNetBudgetForHost(iHost);
    new iRecoverMargin = g_iNetRecoverMargin;

    if (iRecoverMargin >= iBudget)
        iRecoverMargin = iBudget - 1;
    if (iRecoverMargin < 0)
        iRecoverMargin = 0;

    for (new iOwner = 1; iOwner <= g_iMaxPlayers; iOwner++) {
        new PersistentPairDisplay:iDisplay = GetPersistentPairDisplay(iHost, iOwner);
        new NetPairLod:iRequestedLod = GetRequestedLodForPair(iHost, iDisplay);
        new iCost = GetOwnerNetCost(iHost, iOwner, iRequestedLod);

        if (iDisplay == PAIR_DISPLAY_NONE || iCost <= 0) {
            g_iNetTargetLod[iHost][iOwner] = NET_LOD_NONE;
            continue;
        }

        iRequested += iCost;
        iOwners[iCount++] = iOwner;
    }

    g_iNetRequestedSprites[iHost] = iRequested;

    if (!g_iNetAdaptive || is_user_bot(iHost)) {
        g_bNetDegraded[iHost] = false;
        SetUnrestrictedNetLodForHost(iHost);
        return;
    }

    if (iRequested <= iBudget) {
        if (!g_bNetDegraded[iHost] || iRequested <= (iBudget - iRecoverMargin)) {
            g_bNetDegraded[iHost] = false;

            for (new iOwner = 1; iOwner <= g_iMaxPlayers; iOwner++) {
                new PersistentPairDisplay:iDisplay = GetPersistentPairDisplay(iHost, iOwner);
                new NetPairLod:iRequestedLod = GetRequestedLodForPair(iHost, iDisplay);

                if (GetOwnerNetCost(iHost, iOwner, iRequestedLod) <= 0)
                    iRequestedLod = NET_LOD_NONE;

                g_iNetTargetLod[iHost][iOwner] = iRequestedLod;
            }
        }
        else {
            // Hysteresis band: do not refill every tiny temporary opening, but
            // immediately honor any user/server request that became smaller.
            ClampTargetToRequested(iHost);
        }

        ApplyImmediateNetReductions(iHost);
        RecountTargetNetCost(iHost);
        RecountCurrentNetCost(iHost);
        return;
    }

    g_bNetDegraded[iHost] = true;
    SortNetCandidatesByDistance(iHost, iOwners, iCount);

    for (new iOwner = 1; iOwner <= g_iMaxPlayers; iOwner++)
        g_iNetTargetLod[iHost][iOwner] = NET_LOD_NONE;

    new iUsed = 0;

    // Build TARGET by complete LOD passes. Distance matters only because the
    // requested total exceeded the budget.
    for (new iLevel = _:NET_LOD_MINIMAL; iLevel <= _:NET_LOD_FULLPLUS; iLevel++) {
        new NetPairLod:iThisLod = NetPairLod:iLevel;
        new NetPairLod:iPreviousLod = NetPairLod:(iLevel - 1);

        for (new i = 0; i < iCount; i++) {
            new iOwner = iOwners[i];
            new PersistentPairDisplay:iDisplay = GetPersistentPairDisplay(iHost, iOwner);
            new NetPairLod:iRequestedLod = GetRequestedLodForPair(iHost, iDisplay);

            if (iRequestedLod < iThisLod)
                continue;

            if (g_iNetTargetLod[iHost][iOwner] != iPreviousLod)
                continue;

            new iOldCost = GetOwnerNetCost(iHost, iOwner, iPreviousLod);
            new iNewCost = GetOwnerNetCost(iHost, iOwner, iThisLod);
            new iExtra = iNewCost - iOldCost;

            if (iExtra <= 0 || iUsed + iExtra <= iBudget) {
                g_iNetTargetLod[iHost][iOwner] = iThisLod;
                if (iExtra > 0)
                    iUsed += iExtra;
            }
        }
    }

    g_iNetTargetSprites[iHost] = iUsed;
    ApplyImmediateNetReductions(iHost);
    RecountCurrentNetCost(iHost);
}

UpdateAdaptiveNetLod()
{
    for (new iHost = 1; iHost <= g_iMaxPlayers; iHost++) {
        if (!is_user_connected(iHost) || is_user_bot(iHost))
            continue;

        UpdateViewerCameraState(iHost);
        RebuildAdaptiveNetLodForHost(iHost);
    }
}

ApplyAdaptiveNetRampForHost(const iHost)
{
    if (!g_iNetAdaptive || is_user_bot(iHost)) {
        RecountCurrentNetCost(iHost);
        return;
    }

    // Credit accumulation lets one atomic row larger than a single interval
    // (for example a 10-digit real-health row) wait safely instead of never
    // becoming eligible.
    g_iNetRampCredit[iHost] += g_iNetRampSprites;
    if (g_iNetRampCredit[iHost] > 128)
        g_iNetRampCredit[iHost] = 128;

    static iOwners[MAX_PLAYERS];
    new iCount = 0;

    for (new iOwner = 1; iOwner <= g_iMaxPlayers; iOwner++) {
        if (g_iNetPairLod[iHost][iOwner] < g_iNetTargetLod[iHost][iOwner])
            iOwners[iCount++] = iOwner;
    }

    if (iCount <= 0) {
        // Do not bank a large burst while the view is already settled. Otherwise
        // a new group entering next tick could consume a stale 128-credit reserve
        // and defeat the whole purpose of gradual admission.
        g_iNetRampCredit[iHost] = 0;
        RecountCurrentNetCost(iHost);
        return;
    }

    SortNetCandidatesByDistance(iHost, iOwners, iCount);

    for (new i = 0; i < iCount; i++) {
        new iOwner = iOwners[i];

        while (g_iNetPairLod[iHost][iOwner] < g_iNetTargetLod[iHost][iOwner]) {
            new NetPairLod:iOldLod = g_iNetPairLod[iHost][iOwner];
            new NetPairLod:iNextLod = NetPairLod:(_:iOldLod + 1);
            new iOldCost = GetOwnerNetCost(iHost, iOwner, iOldLod);
            new iNewCost = GetOwnerNetCost(iHost, iOwner, iNextLod);
            new iExtra = iNewCost - iOldCost;

            if (iExtra > g_iNetRampCredit[iHost])
                break;

            g_iNetPairLod[iHost][iOwner] = iNextLod;

            if (iExtra > 0)
                g_iNetRampCredit[iHost] -= iExtra;
        }

        // Strict nearest-first admission: if the nearest unfinished block cannot
        // fit yet, accumulate credit for it instead of filling farther players.
        if (g_iNetPairLod[iHost][iOwner] < g_iNetTargetLod[iHost][iOwner])
            break;
    }

    RecountCurrentNetCost(iHost);
}

ApplyAdaptiveNetRamp()
{
    for (new iHost = 1; iHost <= g_iMaxPlayers; iHost++) {
        if (!is_user_connected(iHost) || is_user_bot(iHost))
            continue;

        UpdateViewerCameraState(iHost);
        ApplyAdaptiveNetRampForHost(iHost);
    }
}

Float:GetCompactRowY(const iRow)
{
    new iIndex = iRow;

    if (iIndex < 0)
        iIndex = 0;
    else if (iIndex >= sizeof(g_fCompactRowY))
        iIndex = sizeof(g_fCompactRowY) - 1;

    return g_fCompactRowY[iIndex];
}

Float:GetCompactGrenadeX(const iHost, const iOwner, const iEnt, const NetPairLod:iLod)
{
    new iAllowed[3], iCount = 0;

    for (new i = 2; i <= 4; i++) {
        new iMarker = g_iPlayerWeaponsSprites[iOwner][i];
        if (IsSetEntityAllowedAtLod(iHost, iOwner, iMarker, iLod))
            iAllowed[iCount++] = iMarker;
    }

    if (iCount <= 1)
        return 0.0;

    new iIndex = 0;
    while (iIndex < iCount && iAllowed[iIndex] != iEnt)
        iIndex++;

    if (iCount == 2)
        return (iIndex == 0) ? -14.0 : 14.0;

    switch (iIndex) {
        case 0: return FREEZE_HE_X;
        case 1: return FREEZE_FLASH_X;
    }

    return FREEZE_SMOKE_X;
}

bool:GetPersistentCompactMarkerLayout(const iHost, const iOwner, const iEnt,
    &Float:fScreenX, &Float:fScreenY)
{
    new NetPairLod:iLod = g_iNetPairLod[iHost][iOwner];

    if (!IsSetEntityAllowedAtLod(iHost, iOwner, iEnt, iLod))
        return false;

    new iArrow = g_iPlayerArrow[iOwner];
    new iIcon = g_iPlayerDolarSign[iOwner];
    new iPrimary = g_iPlayerWeaponsSprites[iOwner][1];
    new iSecondary = g_iPlayerWeaponsSprites[iOwner][0];
    new iObjective = g_iPlayerWeaponsSprites[iOwner][6];

    new bool:bArrow = IsSetEntityAllowedAtLod(iHost, iOwner, iArrow, iLod);
    new bool:bHealth = IsSetEntityAllowedAtLod(iHost, iOwner, iIcon, iLod);
    new bool:bPrimary = IsSetEntityAllowedAtLod(iHost, iOwner, iPrimary, iLod);
    new bool:bSecondary = IsSetEntityAllowedAtLod(iHost, iOwner, iSecondary, iLod);
    new bool:bWeapons = bPrimary || bSecondary;
    new bool:bGrenades = false;

    for (new i = 2; i <= 4; i++) {
        if (IsSetEntityAllowedAtLod(iHost, iOwner, g_iPlayerWeaponsSprites[iOwner][i], iLod)) {
            bGrenades = true;
            break;
        }
    }

    new bool:bObjective = IsSetEntityAllowedAtLod(iHost, iOwner, iObjective, iLod);
    new iRow = 0;

    if (bArrow) {
        if (iEnt == iArrow) {
            fScreenX = 0.0;
            fScreenY = GetCompactRowY(iRow);
            return true;
        }
        iRow++;
    }

    if (bHealth) {
        if (IsHealthRowMarker(iOwner, iEnt)) {
            fScreenX = g_fMarkerScreenX[iEnt];
            fScreenY = GetCompactRowY(iRow);
            return true;
        }
        iRow++;
    }

    if (bWeapons) {
        if (iEnt == iPrimary || iEnt == iSecondary) {
            if (bPrimary && bSecondary)
                fScreenX = (iEnt == iPrimary) ? FREEZE_PRIMARY_X : FREEZE_SECONDARY_X;
            else
                fScreenX = 0.0;

            fScreenY = GetCompactRowY(iRow);
            return true;
        }
        iRow++;
    }

    if (bGrenades) {
        for (new i = 2; i <= 4; i++) {
            if (iEnt == g_iPlayerWeaponsSprites[iOwner][i]) {
                fScreenX = GetCompactGrenadeX(iHost, iOwner, iEnt, iLod);
                fScreenY = GetCompactRowY(iRow);
                return true;
            }
        }
        iRow++;
    }

    if (bObjective && iEnt == iObjective) {
        fScreenX = 0.0;
        fScreenY = GetCompactRowY(iRow);
        return true;
    }

    return false;
}

bool:GetFreezetimeCompactMarkerLayout(const iHost, const iOwner, const iEnt,
    &Float:fScreenX, &Float:fScreenY)
{
    new NetPairLod:iLod = g_iNetPairLod[iHost][iOwner];

    if (!IsSetEntityAllowedAtLod(iHost, iOwner, iEnt, iLod))
        return false;

    new iArrow = g_iPlayerArrow[iOwner];
    new iMoneyIcon = g_iPlayerDolarSign[iOwner];
    new iPrimary = g_iPlayerWeaponsSprites[iOwner][1];
    new iSecondary = g_iPlayerWeaponsSprites[iOwner][0];
    new iArmor = g_iPlayerWeaponsSprites[iOwner][5];
    new iObjective = g_iPlayerWeaponsSprites[iOwner][6];

    new bool:bArrow = IsSetEntityAllowedAtLod(iHost, iOwner, iArrow, iLod);
    new bool:bMoney = IsSetEntityAllowedAtLod(iHost, iOwner, iMoneyIcon, iLod);
    new bool:bPrimary = IsSetEntityAllowedAtLod(iHost, iOwner, iPrimary, iLod);
    new bool:bSecondary = IsSetEntityAllowedAtLod(iHost, iOwner, iSecondary, iLod);
    new bool:bWeapons = bPrimary || bSecondary;
    new bool:bGrenades = false;

    for (new i = 2; i <= 4; i++) {
        if (IsSetEntityAllowedAtLod(iHost, iOwner, g_iPlayerWeaponsSprites[iOwner][i], iLod)) {
            bGrenades = true;
            break;
        }
    }

    new bool:bArmor = IsSetEntityAllowedAtLod(iHost, iOwner, iArmor, iLod);
    new bool:bObjective = IsSetEntityAllowedAtLod(iHost, iOwner, iObjective, iLod);
    new bool:bTop = bArmor || bObjective;
    new iRow = 0;

    if (bArrow) {
        if (iEnt == iArrow) {
            fScreenX = 0.0;
            fScreenY = GetCompactRowY(iRow);
            return true;
        }
        iRow++;
    }

    if (bMoney) {
        if (IsHealthRowMarker(iOwner, iEnt)) {
            fScreenX = g_fMarkerScreenX[iEnt];
            fScreenY = GetCompactRowY(iRow);
            return true;
        }
        iRow++;
    }

    if (bWeapons) {
        if (iEnt == iPrimary || iEnt == iSecondary) {
            if (bPrimary && bSecondary)
                fScreenX = (iEnt == iPrimary) ? FREEZE_PRIMARY_X : FREEZE_SECONDARY_X;
            else
                fScreenX = 0.0;

            fScreenY = GetCompactRowY(iRow);
            return true;
        }
        iRow++;
    }

    if (bGrenades) {
        for (new i = 2; i <= 4; i++) {
            if (iEnt == g_iPlayerWeaponsSprites[iOwner][i]) {
                fScreenX = GetCompactGrenadeX(iHost, iOwner, iEnt, iLod);
                fScreenY = GetCompactRowY(iRow);
                return true;
            }
        }
        iRow++;
    }

    if (bTop) {
        if (iEnt == iArmor || iEnt == iObjective) {
            if (bArmor && bObjective)
                fScreenX = (iEnt == iArmor) ? FREEZE_ARMOR_X : FREEZE_OBJECTIVE_X;
            else
                fScreenX = 0.0;

            fScreenY = GetCompactRowY(iRow);
            return true;
        }
    }

    return false;
}

bool:GetEffectiveMarkerScreenLayout(const iHost, const iOwner, const iEnt,
    &Float:fScreenX, &Float:fScreenY)
{
    if (g_bPersistentPhase)
        return GetPersistentCompactMarkerLayout(iHost, iOwner, iEnt, fScreenX, fScreenY);

    return GetFreezetimeCompactMarkerLayout(iHost, iOwner, iEnt, fScreenX, fScreenY);
}

PrintSetNetStatus(const iRequester, const iHost)
{
    if (!IsPlayer(iHost) || !is_user_connected(iHost))
        return;

    new iPing, iLoss;
    get_user_ping(iHost, iPing, iLoss);

    new iLang = (iRequester > 0) ? iRequester : LANG_SERVER;
    static szName[32], szPhase[16], szState[16], szQuality[16];
    get_user_name(iHost, szName, charsmax(szName));

    if (g_bPersistentPhase)
        formatex(szPhase, charsmax(szPhase), "%L", iLang, "SET_PHASE_PERSISTENT");
    else
        formatex(szPhase, charsmax(szPhase), "%L", iLang, "SET_PHASE_FREEZE");

    if (g_bNetDegraded[iHost])
        formatex(szState, charsmax(szState), "%L", iLang, "SET_LOD_REDUCED");
    else
        formatex(szState, charsmax(szState), "%L", iLang, "SET_LOD_FULL");

    GetNetQualityStateName(iLang, g_iNetQualityState[iHost], szQuality, charsmax(szQuality));

    new iEffectiveBudget = GetEffectiveNetBudgetForHost(iHost);
    new Float:fPingDelta = g_fNetQualityPingAverage[iHost] - g_fNetQualityPingBaseline[iHost];
    if (fPingDelta < 0.0)
        fPingDelta = 0.0;

    if (iRequester > 0) {
        client_print(iRequester, print_console, "%L %L",
            iRequester, "SET_NET_TAG", iRequester, "SET_NET_STATUS_HEADER",
            szName, szPhase, g_iMaxPlayers, g_iNetAdaptive, g_iNetSpriteBudget,
            iEffectiveBudget, g_iNetRequestedSprites[iHost], g_iNetTargetSprites[iHost],
            g_iNetAllowedSprites[iHost], szState);
        client_print(iRequester, print_console, "%L %L",
            iRequester, "SET_NET_TAG", iRequester, "SET_NET_STATUS_PAIRS",
            g_iNetFullPlusPairs[iHost], g_iNetFullPairs[iHost], g_iNetReducedPairs[iHost],
            g_iNetMinimalPairs[iHost], g_iNetHiddenPairs[iHost],
            g_iNetRampSprites, g_fNetRampInterval, g_iNetRampCredit[iHost]);
        client_print(iRequester, print_console, "%L %L",
            iRequester, "SET_NET_TAG", iRequester, "SET_NET_STATUS_SCHEDULER",
            g_iNetContentScheduler, g_iNetContentBatch, g_fNetContentInterval,
            g_iNetContentLastBatch, g_iNetContentCycleCursor, g_iNetContentCycleCount);
        client_print(iRequester, print_console, "%L %L",
            iRequester, "SET_NET_TAG", iRequester, "SET_NET_STATUS_QUALITY",
            g_iNetQualityAdaptive, szQuality, iPing, g_fNetQualityPingAverage[iHost],
            g_fNetQualityPingBaseline[iHost], fPingDelta, iLoss,
            g_fNetQualityLossAverage[iHost], g_iNetQualityGoodSamples[iHost],
            g_iNetQualityRecoverSamples);
    }
    else {
        server_print("%L %L", LANG_SERVER, "SET_NET_TAG", LANG_SERVER,
            "SET_NET_STATUS_HEADER", szName, szPhase, g_iMaxPlayers, g_iNetAdaptive,
            g_iNetSpriteBudget, iEffectiveBudget, g_iNetRequestedSprites[iHost],
            g_iNetTargetSprites[iHost], g_iNetAllowedSprites[iHost], szState);
        server_print("%L %L", LANG_SERVER, "SET_NET_TAG", LANG_SERVER,
            "SET_NET_STATUS_PAIRS", g_iNetFullPlusPairs[iHost], g_iNetFullPairs[iHost],
            g_iNetReducedPairs[iHost], g_iNetMinimalPairs[iHost], g_iNetHiddenPairs[iHost],
            g_iNetRampSprites, g_fNetRampInterval, g_iNetRampCredit[iHost]);
        server_print("%L %L", LANG_SERVER, "SET_NET_TAG", LANG_SERVER,
            "SET_NET_STATUS_SCHEDULER", g_iNetContentScheduler, g_iNetContentBatch,
            g_fNetContentInterval, g_iNetContentLastBatch, g_iNetContentCycleCursor,
            g_iNetContentCycleCount);
        server_print("%L %L", LANG_SERVER, "SET_NET_TAG", LANG_SERVER,
            "SET_NET_STATUS_QUALITY", g_iNetQualityAdaptive, szQuality, iPing,
            g_fNetQualityPingAverage[iHost], g_fNetQualityPingBaseline[iHost],
            fPingDelta, iLoss, g_fNetQualityLossAverage[iHost],
            g_iNetQualityGoodSamples[iHost], g_iNetQualityRecoverSamples);
    }
}

public CmdSetNetStatus(id)
{
    if (id > 0) {
        if (!(get_user_flags(id) & ADMIN_CVAR)) {
            client_print(id, print_console, "%L %L", id, "SET_NET_TAG", id, "SET_NET_NO_ACCESS");
            return PLUGIN_HANDLED;
        }

        PrintSetNetStatus(id, id);
        return PLUGIN_HANDLED;
    }

    for (new iHost = 1; iHost <= g_iMaxPlayers; iHost++) {
        if (is_user_connected(iHost) && !is_user_bot(iHost))
            PrintSetNetStatus(0, iHost);
    }

    return PLUGIN_HANDLED;
}

bool:IsDebugProjectionPair(const iHost, const iOwner)
{
    if (!IsPlayer(iHost) || !IsPlayer(iOwner) || iHost == iOwner)
        return false;

    if (!is_user_connected(iHost) || !is_user_alive(iOwner))
        return false;

    new CsTeams:iHostTeam = g_iPlayerTeam[iHost];
    new CsTeams:iOwnerTeam = g_iPlayerTeam[iOwner];

    if (iOwnerTeam != CS_TEAM_T && iOwnerTeam != CS_TEAM_CT)
        return false;

    if (iHostTeam == CS_TEAM_SPECTATOR)
        return true;

    return bool:((iHostTeam == CS_TEAM_T || iHostTeam == CS_TEAM_CT) && iHostTeam == iOwnerTeam);
}

UpdateMarkerVisibilityCache()
{
    for (new iHost = 1; iHost <= g_iMaxPlayers; iHost++) {
        if (!is_user_connected(iHost))
            continue;

        // Resolve the actual viewer camera once per tick. In chase/in-eye
        // observer modes this is reconstructed from iuser1/iuser2 instead of
        // using the observed player's origin as the camera.
        UpdateViewerCameraState(iHost);

        for (new iOwner = 1; iOwner <= g_iMaxPlayers; iOwner++) {
            g_bProjected[iHost][iOwner] = false;
            g_bUseSafeProjection[iHost][iOwner] = false;
            g_bProjectionNeedsNoZ[iHost][iOwner] = false;
            g_fProjectionRatio[iHost][iOwner] = 1.0;
            g_fVisibleScaleFactor[iHost][iOwner] = 1.0;
            ClearProjectionPlane(iHost, iOwner);

            new bool:bFullDisplay = (GetPersistentPairDisplay(iHost, iOwner) == PAIR_DISPLAY_FULL);
            new bool:bDebugPair = (g_iDebugProjection && IsDebugProjectionPair(iHost, iOwner));

            // Do not spend a wall trace on a pair whose CURRENT per-observer LOD
            // has no admitted SET entities. As ramp promotes it, the normal
            // visibility cadence picks it up automatically.
            if (bFullDisplay && GetOwnerNetCost(iHost, iOwner, g_iNetPairLod[iHost][iOwner]) <= 0)
                bFullDisplay = false;

            if (!bFullDisplay && !bDebugPair)
                continue;

            g_fVisibleScaleFactor[iHost][iOwner] = CalculateVisibleScaleFactor(iHost, iOwner);

            if (!g_iShowTeammatesThroughWalls && !bDebugPair)
                continue;

            CalculateMarkerProjection(iHost, iOwner);
        }
    }
}

Float:CalculateVisibleScaleFactor(const iHost, const iOwner)
{
    static Float:fEye[3];
    GetViewerEyeOrigin(iHost, fEye);

    new Float:fDistance = VectorDistance(fEye, g_fPersistentAnchor[iOwner]);

    if (fDistance <= g_fVisibleScaleDistanceStart)
        return 1.0;

    if (fDistance >= g_fVisibleScaleDistanceEnd)
        return g_fVisibleScaleMaxFactor;

    new Float:fRange = g_fVisibleScaleDistanceEnd - g_fVisibleScaleDistanceStart;
    if (fRange <= 0.01)
        return g_fVisibleScaleMaxFactor;

    new Float:fProgress = (fDistance - g_fVisibleScaleDistanceStart) / fRange;
    return 1.0 + (g_fVisibleScaleMaxFactor - 1.0) * fProgress;
}

UpdateRigidBlockLogicalBoundsFromEntity(const iHost, const iOwner, const iEnt, &bHasBounds,
    &Float:fMinX, &Float:fMaxX, &Float:fMinY, &Float:fMaxY)
{
    if (iEnt <= 0 || iEnt > MAX_TRACKED_EDICTS)
        return;

    new Float:fScreenX, Float:fScreenY;
    if (!GetEffectiveMarkerScreenLayout(iHost, iOwner, iEnt, fScreenX, fScreenY))
        return;

    new Float:fLeft = fScreenX - STATUS_FRAME_HALF_WIDTH;
    new Float:fRight = fScreenX + STATUS_FRAME_HALF_WIDTH;
    new Float:fBottom = fScreenY - STATUS_FRAME_HALF_HEIGHT;
    new Float:fTop = fScreenY + STATUS_FRAME_HALF_HEIGHT;

    if (!bHasBounds) {
        fMinX = fLeft;
        fMaxX = fRight;
        fMinY = fBottom;
        fMaxY = fTop;
        bHasBounds = true;
        return;
    }

    if (fLeft < fMinX)
        fMinX = fLeft;
    if (fRight > fMaxX)
        fMaxX = fRight;
    if (fBottom < fMinY)
        fMinY = fBottom;
    if (fTop > fMaxY)
        fMaxY = fTop;
}

// Returns how many LOGICAL sprite pixels the current rigid block can extend
// from the arrow anchor toward/through the blocking wall plane.  The result is
// based only on marker entities that are actually active for this owner.
Float:GetRigidBlockBackExtentPixels(const iHost, const iOwner,
    const Float:fPlanePoint[3], const Float:fPlaneNormal[3])
{
    // Close range intentionally keeps the old behavior.  The large edge
    // clearance is only necessary once the distance-growth system makes the
    // oriented 64x32 quads large enough for their corners to cross a wall.
    if (g_fVisibleScaleFactor[iHost][iOwner] <= 1.0 + RIGID_CLEARANCE_SCALE_EPSILON)
        return 0.0;

    new bHasBounds = false;
    new Float:fMinX, Float:fMaxX, Float:fMinY, Float:fMaxY;

    UpdateRigidBlockLogicalBoundsFromEntity(iHost, iOwner, g_iPlayerArrow[iOwner], bHasBounds,
        fMinX, fMaxX, fMinY, fMaxY);
    UpdateRigidBlockLogicalBoundsFromEntity(iHost, iOwner, g_iPlayerDolarSign[iOwner], bHasBounds,
        fMinX, fMaxX, fMinY, fMaxY);

    for (new i = 0; i < HEALTH_SPRITES; i++)
        UpdateRigidBlockLogicalBoundsFromEntity(iHost, iOwner, g_iPlayerMoneySprites[iOwner][i], bHasBounds,
            fMinX, fMaxX, fMinY, fMaxY);

    for (new i = 0; i < WEAPON_SPRITES; i++)
        UpdateRigidBlockLogicalBoundsFromEntity(iHost, iOwner, g_iPlayerWeaponsSprites[iOwner][i], bHasBounds,
            fMinX, fMaxX, fMinY, fMaxY);

    if (!bHasBounds)
        return 0.0;

    EnsureViewerCameraBasis(iHost);

    // Orient the plane normal toward the viewer.  We then find the corner of
    // the complete X/Y HUD rectangle that has the smallest signed distance in
    // that direction; that is the corner most likely to disappear into the
    // wall when the rigid plate is viewed obliquely.
    static Float:fEyeDelta[3], Float:fTowardEyeNormal[3];
    fEyeDelta[0] = g_fViewerCameraOrigin[iHost][0] - fPlanePoint[0];
    fEyeDelta[1] = g_fViewerCameraOrigin[iHost][1] - fPlanePoint[1];
    fEyeDelta[2] = g_fViewerCameraOrigin[iHost][2] - fPlanePoint[2];

    new Float:fSide = DotProduct(fPlaneNormal, fEyeDelta);
    new Float:fNormalSign = (fSide >= 0.0) ? 1.0 : -1.0;

    fTowardEyeNormal[0] = fPlaneNormal[0] * fNormalSign;
    fTowardEyeNormal[1] = fPlaneNormal[1] * fNormalSign;
    fTowardEyeNormal[2] = fPlaneNormal[2] * fNormalSign;

    new Float:fRightCoeff = DotProduct(fTowardEyeNormal, g_fViewerCameraRight[iHost]);
    new Float:fUpCoeff = DotProduct(fTowardEyeNormal, g_fViewerCameraUp[iHost]);

    new Float:fWorstX = (fRightCoeff >= 0.0) ? fMinX : fMaxX;
    new Float:fWorstY = (fUpCoeff >= 0.0) ? fMinY : fMaxY;
    new Float:fMinimumOffset = fRightCoeff * fWorstX + fUpCoeff * fWorstY;

    if (fMinimumOffset >= 0.0)
        return 0.0;

    return -fMinimumOffset;
}

CalculateMarkerProjection(const iHost, const iOwner)
{
    static Float:fEye[3], Float:fTarget[3], Float:fHit[3], Float:fNormal[3];
    GetViewerEyeOrigin(iHost, fEye);

    // ONE trace, ONE wall plane and ONE depth ratio are used for the entire HUD.
    // The traced target is the arrow/matrix anchor. Individual marker entities
    // no longer participate in projection-depth selection.
    fTarget[0] = g_fPersistentAnchor[iOwner][0];
    fTarget[1] = g_fPersistentAnchor[iOwner][1];
    fTarget[2] = g_fPersistentAnchor[iOwner][2] + g_fWallVerticalOffset;

    engfunc(EngFunc_TraceLine, fEye, fTarget, IGNORE_MONSTERS, iHost, g_iTraceHandle);

    static Float:fFraction;
    get_tr2(g_iTraceHandle, TR_flFraction, fFraction);

    if (fFraction >= 0.999) {
        g_bProjected[iHost][iOwner] = false;
        g_fProjectionRatio[iHost][iOwner] = 1.0;
        return;
    }

    get_tr2(g_iTraceHandle, TR_vecEndPos, fHit);
    get_tr2(g_iTraceHandle, TR_vecPlaneNormal, fNormal);

    if (VectorLength(fNormal) <= 0.001) {
        g_bProjected[iHost][iOwner] = false;
        g_fProjectionRatio[iHost][iOwner] = 1.0;
        return;
    }

    NormalizeVector(fNormal);

    CopyVector(fHit, g_fProjectionPlanePoint[iHost][iOwner]);
    CopyVector(fNormal, g_fProjectionPlaneNormal[iHost][iOwner]);

    static Float:fTargetRay[3], Float:fTargetDirection[3];
    fTargetRay[0] = fTarget[0] - fEye[0];
    fTargetRay[1] = fTarget[1] - fEye[1];
    fTargetRay[2] = fTarget[2] - fEye[2];

    new Float:fRealDistance = VectorLength(fTargetRay);
    if (fRealDistance <= 0.01) {
        g_bProjected[iHost][iOwner] = false;
        g_fProjectionRatio[iHost][iOwner] = 1.0;
        return;
    }

    fTargetDirection[0] = fTargetRay[0] / fRealDistance;
    fTargetDirection[1] = fTargetRay[1] / fRealDistance;
    fTargetDirection[2] = fTargetRay[2] / fRealDistance;

    new Float:fWallDistance = VectorDistance(fEye, fHit);
    new Float:fFacing = floatabs(DotProduct(fNormal, fTargetDirection));
    if (fFacing < MIN_WALL_FACING)
        fFacing = MIN_WALL_FACING;

    // The old offset protected only the arrow anchor. With SPR_ORIENTED, an
    // oblique wall can still cut a corner of the rigid plate even while that
    // center is 8 units in front of the plane.  At scaled/distant ranges we
    // now include the active block's complete 64x32-frame footprint.
    //
    // The block itself shrinks by the same projection ratio, so solving the
    // clearance analytically avoids an iterative per-sprite projection:
    //   push*facing >= baseMargin + backPixels*scale*(wallDistance-push)/realDistance
    new Float:fPush = g_fWallMarkerOffset / fFacing;
    new Float:fBackPixels = GetRigidBlockBackExtentPixels(iHost, iOwner, fHit, fNormal);

    if (fBackPixels > 0.0 && fRealDistance > 0.01) {
        new Float:fUnprojectedPixelScale = g_fSpriteScale
            * g_fVisibleScaleFactor[iHost][iOwner]
            * g_fWallScaleMultiplier;

        if (fUnprojectedPixelScale > 0.0) {
            new Float:fK = (fBackPixels * fUnprojectedPixelScale) / fRealDistance;
            new Float:fClearancePush = (g_fWallMarkerOffset + fK * fWallDistance)
                / (fFacing + fK);

            if (fClearancePush > fPush)
                fPush = fClearancePush;
        }
    }

    new Float:fMaxPush = fWallDistance - MIN_PROJECTED_DISTANCE;
    if (fMaxPush < 0.0)
        fMaxPush = 0.0;
    if (fPush > fMaxPush)
        fPush = fMaxPush;

    new Float:fProjectedDistance = fWallDistance - fPush;
    if (fProjectedDistance < MIN_PROJECTED_DISTANCE)
        fProjectedDistance = MIN_PROJECTED_DISTANCE;

    new Float:fRatio = fProjectedDistance / fRealDistance;
    if (fRatio < 0.0001)
        fRatio = 0.0001;
    else if (fRatio > 1.0)
        fRatio = 1.0;

    // Near-camera safety is also block-wide. It can move the complete matrix
    // closer/farther as one unit, never one sprite independently.
    new Float:fSafeRatio = fRatio;

    new Float:fMinRatioForDistance = SAFE_PROJECTED_SPRITE_DISTANCE / fRealDistance;
    if (fSafeRatio < fMinRatioForDistance)
        fSafeRatio = fMinRatioForDistance;

    new Float:fScaleBase = g_fSpriteScale * g_fVisibleScaleFactor[iHost][iOwner] * g_fWallScaleMultiplier;
    if (fScaleBase > 0.000001) {
        new Float:fMinRatioForScale = MIN_SAFE_ENTITY_SCALE / fScaleBase;
        if (fSafeRatio < fMinRatioForScale)
            fSafeRatio = fMinRatioForScale;
    }

    if (fSafeRatio > 1.0)
        fSafeRatio = 1.0;

    if (fSafeRatio > fRatio + 0.000001)
        g_bUseSafeProjection[iHost][iOwner] = true;

    // TR_flFraction is the wall ratio along this exact arrow-anchor ray.
    if (fSafeRatio >= fFraction - 0.0001)
        g_bProjectionNeedsNoZ[iHost][iOwner] = true;

    g_fProjectionRatio[iHost][iOwner] = fSafeRatio;
    g_bProjected[iHost][iOwner] = true;
}

// Generic same-ray projection retained for the blue debug hull and HUD helpers.
// Persistent S.E.T. sprites themselves use ProjectMarkerAsRigidBlock() below.
bool:ProjectPointToCachedWall(const iHost, const iOwner, const Float:fRealPoint[3], Float:fProjectedPoint[3], &Float:fScaleFactor)
{
    if (!g_bProjected[iHost][iOwner])
        return false;

    static Float:fEye[3], Float:fRay[3];
    GetViewerEyeOrigin(iHost, fEye);

    fRay[0] = fRealPoint[0] - fEye[0];
    fRay[1] = fRealPoint[1] - fEye[1];
    fRay[2] = fRealPoint[2] - fEye[2];

    if (VectorLength(fRay) <= 0.01)
        return false;

    new Float:fProjectedT = g_fProjectionRatio[iHost][iOwner];

    fProjectedPoint[0] = fEye[0] + fRay[0] * fProjectedT;
    fProjectedPoint[1] = fEye[1] + fRay[1] * fProjectedT;
    fProjectedPoint[2] = fEye[2] + fRay[2] * fProjectedT;

    fScaleFactor = fProjectedT * g_fVisibleScaleFactor[iHost][iOwner] * g_fWallScaleMultiplier;

    if (fScaleFactor < g_fWallScaleMinFactor)
        fScaleFactor = g_fWallScaleMinFactor;
    else if (fScaleFactor > g_fWallScaleMaxFactor)
        fScaleFactor = g_fWallScaleMaxFactor;

    return true;
}

// The projected arrow is the matrix point. Every marker is rebuilt
// from that same point with one camera basis, one visible scale and one wall
// depth ratio. There are no marker-type Z offsets and no per-marker rays.
bool:ProjectMarkerAsRigidBlock(const iHost, const iOwner, const iEnt,
    Float:fProjectedPoint[3], &Float:fScaleFactor)
{
    if (!g_bProjected[iHost][iOwner])
        return false;

    static Float:fEye[3], Float:fAnchor[3], Float:fAnchorRay[3], Float:fProjectedAnchor[3];
    GetViewerEyeOrigin(iHost, fEye);

    fAnchor[0] = g_fPersistentAnchor[iOwner][0];
    fAnchor[1] = g_fPersistentAnchor[iOwner][1];
    fAnchor[2] = g_fPersistentAnchor[iOwner][2] + g_fWallVerticalOffset;

    fAnchorRay[0] = fAnchor[0] - fEye[0];
    fAnchorRay[1] = fAnchor[1] - fEye[1];
    fAnchorRay[2] = fAnchor[2] - fEye[2];

    if (VectorLength(fAnchorRay) <= 0.01)
        return false;

    new Float:fProjectedT = g_fProjectionRatio[iHost][iOwner];

    fProjectedAnchor[0] = fEye[0] + fAnchorRay[0] * fProjectedT;
    fProjectedAnchor[1] = fEye[1] + fAnchorRay[1] * fProjectedT;
    fProjectedAnchor[2] = fEye[2] + fAnchorRay[2] * fProjectedT;

    // Physical scale shrinks by projection ratio so its apparent size remains
    // identical to the unobstructed visible block at the real player distance.
    fScaleFactor = fProjectedT * g_fVisibleScaleFactor[iHost][iOwner] * g_fWallScaleMultiplier;
    if (fScaleFactor < g_fWallScaleMinFactor)
        fScaleFactor = g_fWallScaleMinFactor;
    else if (fScaleFactor > g_fWallScaleMaxFactor)
        fScaleFactor = g_fWallScaleMaxFactor;

    EnsureViewerCameraBasis(iHost);

    new Float:fScreenX, Float:fScreenY;
    if (!GetEffectiveMarkerScreenLayout(iHost, iOwner, iEnt, fScreenX, fScreenY))
        return false;

    new Float:fPixelScale = g_fSpriteScale * fScaleFactor;
    new Float:fRightOffset = fScreenX * fPixelScale;
    new Float:fUpOffset = fScreenY * fPixelScale;

    fProjectedPoint[0] = fProjectedAnchor[0]
        + g_fViewerCameraRight[iHost][0] * fRightOffset
        + g_fViewerCameraUp[iHost][0] * fUpOffset;
    fProjectedPoint[1] = fProjectedAnchor[1]
        + g_fViewerCameraRight[iHost][1] * fRightOffset
        + g_fViewerCameraUp[iHost][1] * fUpOffset;
    fProjectedPoint[2] = fProjectedAnchor[2]
        + g_fViewerCameraRight[iHost][2] * fRightOffset
        + g_fViewerCameraUp[iHost][2] * fUpOffset;

    return true;
}

GetRawEyeOrigin(const id, Float:fEye[3])
{
    static Float:fViewOfs[3];
    pev(id, pev_origin, fEye);
    pev(id, pev_view_ofs, fViewOfs);

    fEye[0] += fViewOfs[0];
    fEye[1] += fViewOfs[1];
    fEye[2] += fViewOfs[2];
}

BuildCameraBasisFromAngles(const Float:fAngles[3], Float:fForward[3], Float:fRight[3], Float:fUp[3])
{
    engfunc(EngFunc_MakeVectors, fAngles);
    global_get(glb_v_forward, fForward);
    global_get(glb_v_right, fRight);
    global_get(glb_v_up, fUp);

    if (VectorLength(fForward) <= 0.001) {
        fForward[0] = 1.0;
        fForward[1] = 0.0;
        fForward[2] = 0.0;
    }
    else
        NormalizeVector(fForward);

    if (VectorLength(fRight) <= 0.001) {
        fRight[0] = 0.0;
        fRight[1] = -1.0;
        fRight[2] = 0.0;
    }
    else
        NormalizeVector(fRight);

    if (VectorLength(fUp) <= 0.001) {
        fUp[0] = 0.0;
        fUp[1] = 0.0;
        fUp[2] = 1.0;
    }
    else
        NormalizeVector(fUp);
}

BuildCameraBasisFromDirection(const Float:fDirection[3], const Float:fFallbackAngles[3],
    Float:fForward[3], Float:fRight[3], Float:fUp[3])
{
    CopyVector(fDirection, fForward);
    if (VectorLength(fForward) <= 0.001) {
        BuildCameraBasisFromAngles(fFallbackAngles, fForward, fRight, fUp);
        return;
    }

    NormalizeVector(fForward);

    // GoldSrc screen-right with zero roll is Forward x world-Up. Building the
    // chase basis from the camera->target ray makes the whole HUD block rotate
    // with the spectator camera instead of inheriting the observed player's
    // orientation (the old +26 -> 62+ mirror).
    fRight[0] = fForward[1];
    fRight[1] = -fForward[0];
    fRight[2] = 0.0;

    if (VectorLength(fRight) <= 0.001) {
        BuildCameraBasisFromAngles(fFallbackAngles, fForward, fRight, fUp);
        return;
    }

    NormalizeVector(fRight);

    // Up = Right x Forward. This keeps a stable world-up screen plane even
    // while the chase camera orbits around the target.
    fUp[0] = fRight[1] * fForward[2] - fRight[2] * fForward[1];
    fUp[1] = fRight[2] * fForward[0] - fRight[0] * fForward[2];
    fUp[2] = fRight[0] * fForward[1] - fRight[1] * fForward[0];
    NormalizeVector(fUp);
}

bool:IsViewerInObserverMode(const id)
{
    if (!IsPlayer(id) || !is_user_connected(id))
        return false;

    return bool:(pev(id, pev_iuser1) != SET_OBS_NONE || g_iPlayerTeam[id] == CS_TEAM_SPECTATOR);
}

UpdateViewerCameraState(const id)
{
    new Float:fNow = get_gametime();
    if (floatabs(g_fViewerBasisTime[id] - fNow) <= 0.0001)
        return;

    static Float:fAngles[3];
    new iObsMode = pev(id, pev_iuser1);
    new iTarget = pev(id, pev_iuser2);

    // Living players continue to use the engine view angle. Spectators prefer
    // the latest UC_ViewAngles captured in CmdStart because pev_v_angle can
    // remain tied to the observed player while the local chase camera orbits.
    pev(id, pev_v_angle, fAngles);
    if (iObsMode != SET_OBS_NONE && g_bHasClientViewAngles[id])
        CopyVector(g_fClientViewAngles[id], fAngles);

    GetRawEyeOrigin(id, g_fViewerCameraOrigin[id]);

    if ((iObsMode == SET_OBS_IN_EYE || iObsMode == SET_OBS_CHASE_LOCKED || iObsMode == SET_OBS_CHASE_FREE)
        && IsPlayer(iTarget) && is_user_connected(iTarget)) {

        static Float:fTargetEye[3];
        GetRawEyeOrigin(iTarget, fTargetEye);

        if (iObsMode == SET_OBS_IN_EYE) {
            // In-eye is exactly the observed player's first-person camera.
            pev(iTarget, pev_v_angle, fAngles);
            CopyVector(fTargetEye, g_fViewerCameraOrigin[id]);
            BuildCameraBasisFromAngles(fAngles,
                g_fViewerCameraForward[id], g_fViewerCameraRight[id], g_fViewerCameraUp[id]);
        }
        else {
            // In chase modes the command view angle is the important value: it
            // follows the camera orbit even when the observer entity's v_angle
            // does not. Fall back to the old behavior only before the first cmd.
            if (!g_bHasClientViewAngles[id]) {
                if (iObsMode == SET_OBS_CHASE_LOCKED)
                    pev(iTarget, pev_v_angle, fAngles);
                else
                    pev(id, pev_v_angle, fAngles);
            }

            static Float:fCommandForward[3], Float:fCommandRight[3], Float:fCommandUp[3];
            BuildCameraBasisFromAngles(fAngles, fCommandForward, fCommandRight, fCommandUp);

            new Float:fChaseDistance = g_fClientChaseDistance[id];
            if (fChaseDistance < MIN_CHASE_DISTANCE || fChaseDistance > MAX_CHASE_DISTANCE)
                fChaseDistance = DEFAULT_CHASE_DISTANCE;

            static Float:fDesiredCamera[3];
            fDesiredCamera[0] = fTargetEye[0] - fCommandForward[0] * fChaseDistance;
            fDesiredCamera[1] = fTargetEye[1] - fCommandForward[1] * fChaseDistance;
            fDesiredCamera[2] = fTargetEye[2] - fCommandForward[2] * fChaseDistance;

            engfunc(EngFunc_TraceLine, fTargetEye, fDesiredCamera, IGNORE_MONSTERS, iTarget, g_iTraceHandle);

            static Float:fFraction, Float:fHit[3];
            get_tr2(g_iTraceHandle, TR_flFraction, fFraction);
            get_tr2(g_iTraceHandle, TR_vecEndPos, fHit);

            if (fFraction < 0.999) {
                g_fViewerCameraOrigin[id][0] = fHit[0] + fCommandForward[0] * CHASE_WALL_PUSH;
                g_fViewerCameraOrigin[id][1] = fHit[1] + fCommandForward[1] * CHASE_WALL_PUSH;
                g_fViewerCameraOrigin[id][2] = fHit[2] + fCommandForward[2] * CHASE_WALL_PUSH;
            }
            else
                CopyVector(fDesiredCamera, g_fViewerCameraOrigin[id]);

            // Rebuild the final screen plane from the ACTUAL reconstructed
            // camera position toward the target. This is the matrix used by
            // every icon in the block, so rotating around the target rotates
            // the complete block as one object without reversing digit order.
            static Float:fCameraToTarget[3];
            fCameraToTarget[0] = fTargetEye[0] - g_fViewerCameraOrigin[id][0];
            fCameraToTarget[1] = fTargetEye[1] - g_fViewerCameraOrigin[id][1];
            fCameraToTarget[2] = fTargetEye[2] - g_fViewerCameraOrigin[id][2];

            BuildCameraBasisFromDirection(fCameraToTarget, fAngles,
                g_fViewerCameraForward[id], g_fViewerCameraRight[id], g_fViewerCameraUp[id]);
        }

        g_fViewerBasisTime[id] = fNow;
        return;
    }

    // Roaming spectators also use the command angles captured above. Living
    // players use their normal pev_v_angle and keep the already-correct path.
    BuildCameraBasisFromAngles(fAngles,
        g_fViewerCameraForward[id], g_fViewerCameraRight[id], g_fViewerCameraUp[id]);

    g_fViewerBasisTime[id] = fNow;
}

EnsureViewerCameraBasis(const id)
{
    UpdateViewerCameraState(id);
}

// set_status.spr is SPR_ORIENTED. Unlike SPR_VP_PARALLEL, the
// client renderer no longer rotates every icon independently. We send the
// same explicit sprite angles to every element of a viewer->owner block.
//
// The centers of those elements are already positioned with the same
// g_fViewerCameraRight / g_fViewerCameraUp basis. Deriving ES_Angles from the
// matching forward vector makes the sprite quad use that very same basis too,
// so +26 cannot turn into 62+ when a chase camera crosses to the other side.
ApplyRigidSpriteOrientation(esHandle, const iHost)
{
    EnsureViewerCameraBasis(iHost);

    static Float:fAngles[3];
    engfunc(EngFunc_VecToAngles, g_fViewerCameraForward[iHost], fAngles);

    // The S.E.T. block is intentionally screen-upright. Roll would rotate the
    // entire HUD plate and is not part of the CS2-style layout.
    fAngles[2] = 0.0;
    set_es(esHandle, ES_Angles, fAngles);
}

GetViewerEyeOrigin(const id, Float:fEye[3])
{
    UpdateViewerCameraState(id);
    CopyVector(g_fViewerCameraOrigin[id], fEye);
}

Float:VectorLength(const Float:fVector[3])
{
    return floatsqroot(fVector[0] * fVector[0] + fVector[1] * fVector[1] + fVector[2] * fVector[2]);
}

Float:VectorDistance(const Float:fA[3], const Float:fB[3])
{
    static Float:fDelta[3];
    fDelta[0] = fA[0] - fB[0];
    fDelta[1] = fA[1] - fB[1];
    fDelta[2] = fA[2] - fB[2];
    return VectorLength(fDelta);
}

NormalizeVector(Float:fVector[3])
{
    new Float:fLength = VectorLength(fVector);
    if (fLength <= 0.0001)
        return;

    fVector[0] /= fLength;
    fVector[1] /= fLength;
    fVector[2] /= fLength;
}

Float:DotProduct(const Float:fA[3], const Float:fB[3])
{
    return fA[0] * fB[0] + fA[1] * fB[1] + fA[2] * fB[2];
}

EnablePersistentVisibilityForwards()
{
    if (g_iAddToFullPackPreForward == -1)
        g_iAddToFullPackPreForward = register_forward(FM_AddToFullPack, "ForwardAddToFullPackPre");

    if (g_iAddToFullPackPostForward == -1)
        g_iAddToFullPackPostForward = register_forward(FM_AddToFullPack, "ForwardAddToFullPackPost", 1);

    if (g_iCheckVisibilityForward == -1)
        g_iCheckVisibilityForward = register_forward(FM_CheckVisibility, "ForwardCheckVisibility");
}

DisablePersistentVisibilityForwards()
{
    if (g_iAddToFullPackPreForward != -1) {
        unregister_forward(FM_AddToFullPack, g_iAddToFullPackPreForward);
        g_iAddToFullPackPreForward = -1;
    }

    if (g_iAddToFullPackPostForward != -1) {
        unregister_forward(FM_AddToFullPack, g_iAddToFullPackPostForward, 1);
        g_iAddToFullPackPostForward = -1;
    }

    if (g_iCheckVisibilityForward != -1) {
        unregister_forward(FM_CheckVisibility, g_iCheckVisibilityForward);
        g_iCheckVisibilityForward = -1;
    }

    ResetVisibilityContext();
}

ResetVisibilityContext()
{
    g_iVisibilityContextEnt = 0;
    g_iVisibilityContextHost = 0;
    g_bForceCurrentVisibility = false;
}

bool:IsSetEntityDesiredForHost(const iHost, const iOwner, const iEnt)
{
    if (!IsPlayer(iHost) || !IsPlayer(iOwner) || iHost == iOwner)
        return false;

    if (!is_user_connected(iHost) || !is_user_alive(iOwner))
        return false;

    if (!IsOwnerEntityPhaseActive(iEnt))
        return false;

    new PersistentPairDisplay:iDisplay = GetPersistentPairDisplay(iHost, iOwner);
    if (iDisplay == PAIR_DISPLAY_NONE)
        return false;

    if (iDisplay == PAIR_DISPLAY_ENEMY_ARROW && iEnt != g_iPlayerArrow[iOwner])
        return false;

    return IsNetMarkerAllowedForHost(iHost, iOwner, iEnt);
}

public ForwardAddToFullPackPre(esHandle, e, iEnt, iHost, hostflags, player, pSet)
{
    ResetVisibilityContext();

    if (!IsPlayer(iHost) || !is_user_connected(iHost))
        return FMRES_IGNORED;

    if (iEnt <= 0 || iEnt > MAX_TRACKED_EDICTS)
        return FMRES_IGNORED;

    new iOwner = g_iMarkerOwnerByEnt[iEnt];
    if (!IsPlayer(iOwner))
        return FMRES_IGNORED;

    new iBit = GetOwnerMarkerBit(iOwner, iEnt);
    new bool:bDesired = IsSetEntityDesiredForHost(iHost, iOwner, iEnt);
    new bool:bWasSent = bool:(iBit && (g_iNetSentMarkerMask[iHost][iOwner] & iBit));

    if (!bDesired) {
        if (!bWasSent) {
            forward_return(FMV_CELL, 0);
            return FMRES_SUPERCEDE;
        }

        // One explicit hidden-state packet is required before suppression. This
        // fixes stale disappearing digits/rows while still removing the entity
        // from subsequent datagrams.
        g_iNetSentMarkerMask[iHost][iOwner] &= ~iBit;

        // Force this last hidden update through PVS even if the old marker was
        // projected through a wall. POST will make it NODRAW/alpha 0.
        g_iVisibilityContextEnt = iEnt;
        g_iVisibilityContextHost = iHost;
        g_bForceCurrentVisibility = true;
        return FMRES_IGNORED;
    }

    if (iBit)
        g_iNetSentMarkerMask[iHost][iOwner] |= iBit;

    new PersistentPairDisplay:iDisplay = GetPersistentPairDisplay(iHost, iOwner);

    // Enemies never receive a PVS bypass. Only full teammate/spectator pairs
    // may use the one-wall rigid projection in either persistent or freezetime.
    if (iDisplay == PAIR_DISPLAY_FULL && g_iShowTeammatesThroughWalls) {
        g_iVisibilityContextEnt = iEnt;
        g_iVisibilityContextHost = iHost;
        g_bForceCurrentVisibility = true;
    }

    return FMRES_IGNORED;
}

public ForwardCheckVisibility(iEnt, pSet)
{
    if (!g_bForceCurrentVisibility)
        return FMRES_IGNORED;

    if (iEnt != g_iVisibilityContextEnt || !IsPlayer(g_iVisibilityContextHost))
        return FMRES_IGNORED;

    forward_return(FMV_CELL, 1);
    return FMRES_SUPERCEDE;
}

public ForwardAddToFullPackPost(esHandle, e, iEnt, iHost, hostflags, player, pSet)
{
    if (!IsPlayer(iHost) || !is_user_connected(iHost)) {
        ResetVisibilityContext();
        return FMRES_IGNORED;
    }

    if (iEnt <= 0 || iEnt > MAX_TRACKED_EDICTS) {
        ResetVisibilityContext();
        return FMRES_IGNORED;
    }

    new iOwner = g_iMarkerOwnerByEnt[iEnt];
    if (!IsPlayer(iOwner)) {
        ResetVisibilityContext();
        return FMRES_IGNORED;
    }

    if (!IsSetEntityDesiredForHost(iHost, iOwner, iEnt)) {
        HideEntityForHost(esHandle);
        ResetVisibilityContext();
        return FMRES_IGNORED;
    }

    new PersistentPairDisplay:iDisplay = GetPersistentPairDisplay(iHost, iOwner);

    switch (iDisplay) {
        case PAIR_DISPLAY_FULL: {
            if (g_bProjected[iHost][iOwner])
                ApplyProjectedMarkerState(esHandle, iEnt, iHost, iOwner);
            else
                ApplyVisibleMarkerState(esHandle, iEnt, iHost, iOwner);

            if (g_bPersistentPhase) {
                ApplyPersistentMarkerColorForHost(esHandle, iEnt, iHost, iOwner);
            }
            else if (IsViewerInObserverMode(iHost) && IsFreezetimeTeamStatusEntity(iOwner, iEnt)) {
                static iTeamColor[3];
                GetOwnerTeamColor(iOwner, iTeamColor);
                set_es(esHandle, ES_RenderColor, iTeamColor);
            }
        }

        case PAIR_DISPLAY_ENEMY_ARROW: {
            // Normal engine PVS remains authoritative for enemies. The block is
            // still rebuilt from the real receiving camera so orientation stays
            // consistent with every other SET marker.
            ApplyVisibleMarkerState(esHandle, iEnt, iHost, iOwner);
            set_es(esHandle, ES_RenderColor, g_iEnemyArrowColor);
        }

        default: HideEntityForHost(esHandle);
    }

    ResetVisibilityContext();
    return FMRES_IGNORED;
}


ApplyVisibleMarkerState(esHandle, const iEnt, const iHost, const iOwner)
{
    new Float:fScaleFactor = g_fVisibleScaleFactor[iHost][iOwner];
    if (fScaleFactor < 1.0)
        fScaleFactor = 1.0;

    new Float:fScale = g_fSpriteScale * fScaleFactor;
    set_es(esHandle, ES_Scale, fScale);

    new Float:fScreenX, Float:fScreenY;
    if (!GetEffectiveMarkerScreenLayout(iHost, iOwner, iEnt, fScreenX, fScreenY))
        return;

    EnsureViewerCameraBasis(iHost);

    static Float:fOrigin[3];
    fOrigin[0] = g_fPersistentAnchor[iOwner][0];
    fOrigin[1] = g_fPersistentAnchor[iOwner][1];
    fOrigin[2] = g_fPersistentAnchor[iOwner][2];

    new Float:fRightOffset = fScreenX * fScale;
    new Float:fUpOffset = fScreenY * fScale;

    fOrigin[0] += g_fViewerCameraRight[iHost][0] * fRightOffset + g_fViewerCameraUp[iHost][0] * fUpOffset;
    fOrigin[1] += g_fViewerCameraRight[iHost][1] * fRightOffset + g_fViewerCameraUp[iHost][1] * fUpOffset;
    fOrigin[2] += g_fViewerCameraRight[iHost][2] * fRightOffset + g_fViewerCameraUp[iHost][2] * fUpOffset;

    set_es(esHandle, ES_Origin, fOrigin);
    ApplyRigidSpriteOrientation(esHandle, iHost);
}

ApplyProjectedMarkerState(esHandle, const iEnt, const iHost, const iOwner)
{
    static Float:fFakeOrigin[3];

    new Float:fScaleFactor;
    if (!ProjectMarkerAsRigidBlock(iHost, iOwner, iEnt, fFakeOrigin, fScaleFactor)) {
        // Fallback should be rare. Keeping the real state is safer than
        // inventing a partially projected block.
        ApplyVisibleMarkerState(esHandle, iEnt, iHost, iOwner);
        return;
    }

    set_es(esHandle, ES_Origin, fFakeOrigin);
    set_es(esHandle, ES_Scale, g_fSpriteScale * fScaleFactor);
    ApplyRigidSpriteOrientation(esHandle, iHost);

    // Do not interpolate between the real world origin and the projected one.
    set_es(esHandle, ES_Effects, get_es(esHandle, ES_Effects) | EF_NOINTERP);

    // Normal projection is preserved. Only when the safe projected
    // depth has to reach/cross the wall do we use the no-Z glow renderer. This
    // is intentionally a narrow fallback and can be reverted
    // without affecting the now-stable normal projection path.
    if (g_bProjectionNeedsNoZ[iHost][iOwner])
        set_es(esHandle, ES_RenderMode, kRenderGlow);
    else
        set_es(esHandle, ES_RenderMode, kRenderTransAdd);

    set_es(esHandle, ES_RenderAmt, 255);
}

HideEntityForHost(esHandle)
{
    set_es(esHandle, ES_Effects, get_es(esHandle, ES_Effects) | EF_NODRAW);
    set_es(esHandle, ES_RenderMode, kRenderTransAlpha);
    set_es(esHandle, ES_RenderAmt, 0);
}

ClearVisibilityCacheForPlayer(const id)
{
    for (new i = 1; i <= g_iMaxPlayers; i++) {
        g_bProjected[id][i] = false;
        g_bUseSafeProjection[id][i] = false;
        g_bProjectionNeedsNoZ[id][i] = false;
        g_fProjectionRatio[id][i] = 1.0;
        g_fVisibleScaleFactor[id][i] = 1.0;
        ClearProjectionPlane(id, i);

        g_bProjected[i][id] = false;
        g_bUseSafeProjection[i][id] = false;
        g_bProjectionNeedsNoZ[i][id] = false;
        g_fProjectionRatio[i][id] = 1.0;
        g_fVisibleScaleFactor[i][id] = 1.0;
        ClearProjectionPlane(i, id);
    }
}

ClearAllVisibilityCache()
{
    for (new iHost = 1; iHost <= g_iMaxPlayers; iHost++) {
        for (new iOwner = 1; iOwner <= g_iMaxPlayers; iOwner++) {
            g_bProjected[iHost][iOwner] = false;
            g_bUseSafeProjection[iHost][iOwner] = false;
            g_bProjectionNeedsNoZ[iHost][iOwner] = false;
            g_fProjectionRatio[iHost][iOwner] = 1.0;
            g_fVisibleScaleFactor[iHost][iOwner] = 1.0;
            ClearProjectionPlane(iHost, iOwner);
        }
    }
}


ClearProjectionPlane(const iHost, const iOwner)
{
    g_fProjectionPlanePoint[iHost][iOwner][0] = 0.0;
    g_fProjectionPlanePoint[iHost][iOwner][1] = 0.0;
    g_fProjectionPlanePoint[iHost][iOwner][2] = 0.0;
    g_fProjectionPlaneNormal[iHost][iOwner][0] = 0.0;
    g_fProjectionPlaneNormal[iHost][iOwner][1] = 0.0;
    g_fProjectionPlaneNormal[iHost][iOwner][2] = 0.0;
}

// Returns the player's current collision-hull bottom/top. Unlike a fixed
// standing-height constant this follows crouching automatically and gives the
// debug overlay a stable feet -> head reference for the current posture.
GetPlayerHullVerticalPoints(const id, Float:fFeet[3], Float:fHead[3])
{
    static Float:fOrigin[3], Float:fMins[3], Float:fMaxs[3];
    pev(id, pev_origin, fOrigin);
    pev(id, pev_mins, fMins);
    pev(id, pev_maxs, fMaxs);

    fFeet[0] = fOrigin[0];
    fFeet[1] = fOrigin[1];
    fFeet[2] = fOrigin[2] + fMins[2];

    fHead[0] = fOrigin[0];
    fHead[1] = fOrigin[1];
    fHead[2] = fOrigin[2] + fMaxs[2];
}

DrawProjectionDebug()
{
    if (!g_iDebugBeamModel)
        return;

    for (new iHost = 1; iHost <= g_iMaxPlayers; iHost++) {
        if (!is_user_connected(iHost))
            continue;

        for (new iOwner = 1; iOwner <= g_iMaxPlayers; iOwner++) {
            if (!IsDebugProjectionPair(iHost, iOwner))
                continue;

            static Float:fFeet[3], Float:fHead[3], Float:fDrawFeet[3], Float:fDrawHead[3];
            GetPlayerHullVerticalPoints(iOwner, fFeet, fHead);

            new Float:fUnusedScale;
            if (g_bProjected[iHost][iOwner]) {
                if (!ProjectPointToCachedWall(iHost, iOwner, fFeet, fDrawFeet, fUnusedScale))
                    CopyVector(fFeet, fDrawFeet);
                if (!ProjectPointToCachedWall(iHost, iOwner, fHead, fDrawHead, fUnusedScale))
                    CopyVector(fHead, fDrawHead);
            }
            else {
                CopyVector(fFeet, fDrawFeet);
                CopyVector(fHead, fDrawHead);
            }

            // Debug width follows the SAME one-ratio-per-pair perspective rule
            // used by the projected S.E.T. block.
            new Float:fWidthFactor = 1.0;
            if (g_bProjected[iHost][iOwner])
                fWidthFactor = g_fProjectionRatio[iHost][iOwner];

            new iWidth = floatround(float(DEBUG_BEAM_WIDTH) * fWidthFactor);
            if (iWidth < 1)
                iWidth = 1;
            else if (iWidth > 255)
                iWidth = 255;

            SendDebugBeam(iHost, fDrawHead, fDrawFeet, iWidth, 0, 128, 255, 210);
        }
    }
}

SendDebugBeam(const id, const Float:fStart[3], const Float:fEnd[3], const iWidth,
    const iRed, const iGreen, const iBlue, const iBrightness)
{
    message_begin(MSG_ONE_UNRELIABLE, SVC_TEMPENTITY, {0, 0, 0}, id);
    write_byte(0); // TE_BEAMPOINTS
    write_coord(floatround(fStart[0]));
    write_coord(floatround(fStart[1]));
    write_coord(floatround(fStart[2]));
    write_coord(floatround(fEnd[0]));
    write_coord(floatround(fEnd[1]));
    write_coord(floatround(fEnd[2]));
    write_short(g_iDebugBeamModel);
    write_byte(3);
    write_byte(0);
    write_byte(4); // 0.4 seconds, slightly longer than the debug-beam refresh.
    write_byte(iWidth);
    write_byte(0);
    write_byte(iRed);
    write_byte(iGreen);
    write_byte(iBlue);
    write_byte(iBrightness);
    write_byte(0);
    message_end();
}

UpdateTeammateHudLabels()
{
    // Classic HUD gives us four useful simultaneous channels. Candidates are
    // sorted nearest-first so overlapping labels always keep the closest mate.
    for (new iHost = 1; iHost <= g_iMaxPlayers; iHost++) {
        if (!is_user_connected(iHost))
            continue;

        if (!g_iDebugProjection && g_iClientDetailCap[iHost] == NET_LOD_NONE)
            continue;

        static iOwner[MAX_PLAYERS], Float:fX[MAX_PLAYERS], Float:fY[MAX_PLAYERS], Float:fDistance[MAX_PLAYERS];
        new iCount = 0;

        static Float:fEye[3];
        GetViewerEyeOrigin(iHost, fEye);

        for (new iTarget = 1; iTarget <= g_iMaxPlayers; iTarget++) {
            if (g_iDebugProjection) {
                if (!IsDebugProjectionPair(iHost, iTarget))
                    continue;
            }
            else if (GetPersistentPairDisplay(iHost, iTarget) != PAIR_DISPLAY_FULL) {
                continue;
            }

            // Distance is always the REAL viewer -> teammate distance. A wall
            // never changes label eligibility or the visible-scale reference.
            new Float:fRealDistance = VectorDistance(fEye, g_fPersistentAnchor[iTarget]);
            if (g_fTeammateNameMaxDistance > 0.0 && fRealDistance > g_fTeammateNameMaxDistance)
                continue;

            // Anchor the label to the highest currently visible S.E.T. sprite,
            // not to an arbitrary head+world offset. Because wall projection
            // preserves that sprite's camera ray, the same 2D point works with
            // and without a wall.
            static Float:fLabelPoint[3];
            GetPersistentTopMarkerPoint(iHost, iTarget, fLabelPoint);

            new Float:x, Float:y;
            if (!WorldPointToHud(iHost, fLabelPoint, x, y))
                continue;

            y -= g_fTeammateNameScreenGap;
            if (y <= 0.01 || y >= 0.99)
                continue;

            iOwner[iCount] = iTarget;
            fX[iCount] = x;
            fY[iCount] = y;
            fDistance[iCount] = fRealDistance;
            iCount++;
        }

        // Nearest first, so a close teammate keeps the label if two screen
        // positions overlap.
        for (new i = 0; i < iCount - 1; i++) {
            new iBest = i;
            for (new j = i + 1; j < iCount; j++) {
                if (fDistance[j] < fDistance[iBest])
                    iBest = j;
            }

            if (iBest != i) {
                SwapInt(iOwner[i], iOwner[iBest]);
                SwapFloat(fX[i], fX[iBest]);
                SwapFloat(fY[i], fY[iBest]);
                SwapFloat(fDistance[i], fDistance[iBest]);
            }
        }

        static Float:fUsedX[DEBUG_MAX_HUD_LABELS], Float:fUsedY[DEBUG_MAX_HUD_LABELS];
        new iShown = 0;

        for (new i = 0; i < iCount && iShown < DEBUG_MAX_HUD_LABELS; i++) {
            new bool:bCollision = false;
            for (new j = 0; j < iShown; j++) {
                if (floatabs(fX[i] - fUsedX[j]) < DEBUG_LABEL_COLLISION_X &&
                    floatabs(fY[i] - fUsedY[j]) < DEBUG_LABEL_COLLISION_Y) {
                    bCollision = true;
                    break;
                }
            }

            if (bCollision)
                continue;

            static szName[32], szDistance[16];
            get_user_name(iOwner[i], szName, charsmax(szName));
            formatex(szDistance, charsmax(szDistance), "%L", iHost, "SET_HUD_DISTANCE_UNITS", floatround(fDistance[i]));

            // set_hudmessage uses the supplied X as the text's left edge. Shift
            // it by an approximate half-line width so the label is visually
            // centered over the sprite stack rather than extending to its right.
            new iLongestLine = strlen(szName);
            if (g_iDebugProjection && strlen(szDistance) > iLongestLine)
                iLongestLine = strlen(szDistance);

            new Float:fDrawX = fX[i] - float(iLongestLine) * HUD_CHAR_HALF_WIDTH;
            if (fDrawX < 0.01)
                fDrawX = 0.01;
            else if (fDrawX > 0.98)
                fDrawX = 0.98;

            set_hudmessage(255, 255, 0, fDrawX, fY[i], 0, 0.0,
                g_fTeammateNameUpdateInterval + 0.05, 0.0, 0.0, iShown + 1);

            if (g_iDebugProjection)
                show_hudmessage(iHost, "%s^n%s", szName, szDistance);
            else if (g_iShowTeammatesName)
                show_hudmessage(iHost, "%s", szName);

            // Collision uses the true sprite-stack center, not the shifted text
            // left edge, so long names do not distort the proximity test.
            fUsedX[iShown] = fX[i];
            fUsedY[iShown] = fY[i];
            iShown++;
        }
    }
}

// Returns the real-world origin of the highest active persistent sprite. The
// name HUD is then placed a fixed SCREEN-space gap above this point.
GetPersistentTopMarkerPoint(const iHost, const iOwner, Float:fPoint[3])
{
    new Float:fHighestY = 0.0;
    new bool:bFound = false;
    new Float:fX, Float:fY;

    if (GetEffectiveMarkerScreenLayout(iHost, iOwner, g_iPlayerArrow[iOwner], fX, fY)) {
        fHighestY = fY;
        bFound = true;
    }

    if (GetEffectiveMarkerScreenLayout(iHost, iOwner, g_iPlayerDolarSign[iOwner], fX, fY)) {
        if (!bFound || fY > fHighestY)
            fHighestY = fY;
        bFound = true;
    }

    for (new i = 0; i < HEALTH_SPRITES; i++) {
        if (GetEffectiveMarkerScreenLayout(iHost, iOwner, g_iPlayerMoneySprites[iOwner][i], fX, fY)) {
            if (!bFound || fY > fHighestY)
                fHighestY = fY;
            bFound = true;
        }
    }

    for (new i = 0; i < WEAPON_SPRITES; i++) {
        if (GetEffectiveMarkerScreenLayout(iHost, iOwner, g_iPlayerWeaponsSprites[iOwner][i], fX, fY)) {
            if (!bFound || fY > fHighestY)
                fHighestY = fY;
            bFound = true;
        }
    }

    CopyVector(g_fPersistentAnchor[iOwner], fPoint);

    if (!bFound)
        return;

    EnsureViewerCameraBasis(iHost);

    new Float:fScaleFactor = g_fVisibleScaleFactor[iHost][iOwner];
    if (fScaleFactor < 1.0)
        fScaleFactor = 1.0;

    new Float:fOffset = fHighestY * g_fSpriteScale * fScaleFactor;
    fPoint[0] += g_fViewerCameraUp[iHost][0] * fOffset;
    fPoint[1] += g_fViewerCameraUp[iHost][1] * fOffset;
    fPoint[2] += g_fViewerCameraUp[iHost][2] * fOffset;
}

bool:WorldPointToHud(const id, const Float:fPoint[3], &Float:fX, &Float:fY)
{
    static Float:fEye[3], Float:fTarget[3], Float:fAim[3];
    GetViewerEyeOrigin(id, fEye);

    fTarget[0] = fPoint[0] - fEye[0];
    fTarget[1] = fPoint[1] - fEye[1];
    fTarget[2] = fPoint[2] - fEye[2];

    VelocityByAim(id, 1, fAim);
    if (VectorLength(fAim) <= 0.001 || VectorLength(fTarget) <= 0.001)
        return false;

    static Float:fAimFlat[3], Float:fTargetFlat[3];
    CopyVector(fAim, fAimFlat);
    CopyVector(fTarget, fTargetFlat);
    fAimFlat[2] = 0.0;
    fTargetFlat[2] = 0.0;

    new Float:fAimFlatLen = VectorLength(fAimFlat);
    new Float:fTargetFlatLen = VectorLength(fTargetFlat);
    if (fAimFlatLen <= 0.001 || fTargetFlatLen <= 0.001)
        return false;

    new Float:fCosX = DotProduct(fAimFlat, fTargetFlat) / (fAimFlatLen * fTargetFlatLen);
    if (fCosX > 1.0) fCosX = 1.0;
    else if (fCosX < -1.0) fCosX = -1.0;

    new Float:fXAngle = floatacos(fCosX, degrees);
    if (ScalarTripleUp(fAimFlat, fTargetFlat) < 0.0)
        fXAngle *= -1.0;

    if (fXAngle < -45.0 || fXAngle > 45.0)
        return false;

    fX = 1.0 - (floattan(fXAngle, degrees) + 1.0) / 2.0;

    new Float:fAimLen = VectorLength(fAim);

    // Recreate Admin Spectator ESP's vertical-angle trick: rotate the target's
    // horizontal component onto the aim direction, preserving target Z.
    static Float:fRotated[3], Float:fAimHorizontal[3];
    CopyVector(fAim, fAimHorizontal);
    fAimHorizontal[2] = 0.0;
    NormalizeVector(fAimHorizontal);

    new Float:fHorizontalLen = floatsqroot(fTarget[0] * fTarget[0] + fTarget[1] * fTarget[1]);
    fRotated[0] = fAimHorizontal[0] * fHorizontalLen;
    fRotated[1] = fAimHorizontal[1] * fHorizontalLen;
    fRotated[2] = fTarget[2];

    new Float:fRotatedLen = VectorLength(fRotated);
    if (fRotatedLen <= 0.001)
        return false;

    new Float:fCosY = DotProduct(fAim, fRotated) / (fAimLen * fRotatedLen);
    if (fCosY > 1.0) fCosY = 1.0;
    else if (fCosY < -1.0) fCosY = -1.0;

    new Float:fYAngle = floatacos(fCosY, degrees);

    static Float:fNormTarget[3], Float:fNormAim[3];
    CopyVector(fTarget, fNormTarget);
    CopyVector(fAim, fNormAim);
    NormalizeVector(fNormTarget);
    NormalizeVector(fNormAim);
    if (fNormTarget[2] < fNormAim[2])
        fYAngle *= -1.0;

    if (fYAngle < -45.0 || fYAngle > 45.0)
        return false;

    fY = 1.0 - (floattan(fYAngle, degrees) + 1.0) / 2.0;

    return bool:(fX > 0.0 && fX < 1.0 && fY > 0.0 && fY < 1.0);
}

Float:ScalarTripleUp(const Float:fA[3], const Float:fB[3])
{
    // dot(cross(A,B), [0,0,1]) == cross Z component.
    return fA[0] * fB[1] - fA[1] * fB[0];
}

CopyVector(const Float:fSource[3], Float:fDest[3])
{
    fDest[0] = fSource[0];
    fDest[1] = fSource[1];
    fDest[2] = fSource[2];
}

SwapInt(&a, &b)
{
    new t = a;
    a = b;
    b = t;
}

SwapFloat(&Float:a, &Float:b)
{
    new Float:t = a;
    a = b;
    b = t;
}

GetDigitFrame(const iDigit)
{
    return STATUS_FRAME_DIGIT_0 + clamp(iDigit, 0, 9);
}

GetStatusFrameForWeaponId(const iWeapon)
{
    switch (iWeapon) {
        case CSW_USP: return STATUS_FRAME_USP;
        case CSW_SCOUT: return STATUS_FRAME_SCOUT;
        case CSW_XM1014: return STATUS_FRAME_XM1014;
        case CSW_MAC10: return STATUS_FRAME_MAC10;
        case CSW_AUG: return STATUS_FRAME_AUG;
        case CSW_ELITE: return STATUS_FRAME_ELITE;
        case CSW_FIVESEVEN: return STATUS_FRAME_FIVESEVEN;
        case CSW_UMP45: return STATUS_FRAME_UMP45;
        case CSW_SG550: return STATUS_FRAME_SG550;
        case CSW_GALIL: return STATUS_FRAME_GALIL;
        case CSW_FAMAS: return STATUS_FRAME_FAMAS;
        case CSW_P228: return STATUS_FRAME_P228;
        case CSW_GLOCK18: return STATUS_FRAME_GLOCK18;
        case CSW_AWP: return STATUS_FRAME_AWP;
        case CSW_MP5NAVY: return STATUS_FRAME_MP5NAVY;
        case CSW_M249: return STATUS_FRAME_M249;
        case CSW_M3: return STATUS_FRAME_M3;
        case CSW_M4A1: return STATUS_FRAME_M4A1;
        case CSW_TMP: return STATUS_FRAME_TMP;
        case CSW_G3SG1: return STATUS_FRAME_G3SG1;
        case CSW_DEAGLE: return STATUS_FRAME_DEAGLE;
        case CSW_SG552: return STATUS_FRAME_SG552;
        case CSW_AK47: return STATUS_FRAME_AK47;
        case CSW_P90: return STATUS_FRAME_P90;
    }

    return STATUS_FRAME_BLANK;
}

GetColor(const SpriteColors:iColorCvar, iColor[3])
{
    ConvertCvarToRGB(get_pcvar_num(g_pColorCvar[iColorCvar]), iColor);
}

ConvertCvarToRGB(pCvar, iColor[3])
{
    iColor[0] = clamp((pCvar / 1000000), 0, 255);
    pCvar %= 1000000;
    iColor[1] = clamp((pCvar / 1000), 0, 255);
    iColor[2] = clamp((pCvar % 1000), 0, 255);
}
