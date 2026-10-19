#include <amxmodx>
#include <fakemeta>

#define PLUGIN "Dense Smoke"
#define VERSION "0.1"
#define AUTHOR " "

// =================================================================
// CONFIGURATION: YOUR CHOSEN OPTIMAL SETTINGS
// =================================================================
#define CLOUD_COUNT 20          
#define SMOKE_SCALE 5.0        
#define SMOKE_LIFESPAN 25.0    
#define SPREAD_RADIUS 50.0     

#define MAX_SPRITES_TRACKED 256 // Maximum number of active smoke clouds allowed on map
// =================================================================

new g_SmokeSprite;
new g_TrackedSprites[MAX_SPRITES_TRACKED];
new g_SpriteCount = 0;

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR);
    register_forward(FM_Think, "OnEntityThink");
    
    // Low-level engine hook: HLTV event fires at the absolute beginning of a map cleaning/round reset sequence
    register_event("HLTV", "Event_MapCleanupDetected", "a", "1=0", "2=0");
    register_event("TextMsg", "Event_MapCleanupDetected", "a", "2=#Game_Commencing", "2=#Game_will_restart_in");
}

public plugin_precache() {
    g_SmokeSprite = precache_model("sprites/gas_puff_01.spr");
}

public Event_MapCleanupDetected() {
    
    new Float:current_time = get_gametime();
    
    for (new i = 0; i < g_SpriteCount; i++) {
        new ent = g_TrackedSprites[i];
        if (pev_valid(ent)) {
            set_pev(ent, pev_nextthink, current_time + 0.1);
        }
    }
    
    // Clear our tracking array for the upcoming round
    g_SpriteCount = 0;
}

public OnEntityThink(entity) {
    if (!pev_valid(entity))
        return FMRES_IGNORED;

    if (pev(entity, pev_iuser1) == 1)
        return FMRES_IGNORED;

    new model[32];
    pev(entity, pev_model, model, charsmax(model));
    
    if (equal(model, "models/w_smokegrenade.mdl")) {
        new Float:dmgtime;
        pev(entity, pev_dmgtime, dmgtime);
        
        new Float:current_time = get_gametime();
        
        if (dmgtime > 0.0 && dmgtime <= current_time) {
            new Float:velocity[3];
            pev(entity, pev_velocity, velocity);
            
            new Float:total_momentum = floatabs(velocity[0]) + floatabs(velocity[1]) + floatabs(velocity[2]);
            
            if (total_momentum > 5.0) {
                set_pev(entity, pev_dmgtime, current_time + 0.1);
                set_pev(entity, pev_nextthink, current_time + 0.1);
                return FMRES_HANDLED; 
            }
            
            set_pev(entity, pev_iuser1, 1);
            
            new Float:origin[3];
            pev(entity, pev_origin, origin);
            
            SpawnAbsoluteBlackMask(origin);
            
            new Float:spawn_pos[3];
            new Float:angle_step = (2.0 * M_PI) / float(CLOUD_COUNT - 1); 
            
            for (new i = 0; i < (CLOUD_COUNT - 1); i++) {
                new Float:current_angle = float(i) * angle_step;
                
                spawn_pos[0] = origin[0] + (SPREAD_RADIUS * floatcos(current_angle));
                spawn_pos[1] = origin[1] + (SPREAD_RADIUS * floatsin(current_angle));
                spawn_pos[2] = origin[2] + 10.0; 
                
                SpawnAbsoluteBlackMask(spawn_pos);
            }
            
            set_pev(entity, pev_dmgtime, 0.0);
        }
    }
    
    return FMRES_IGNORED;
}

public SpawnAbsoluteBlackMask(Float:origin[3]) {
    new ent = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "env_sprite"));
    
    if (!pev_valid(ent))
        return;
        
    set_pev(ent, pev_origin, origin);
    set_pev(ent, pev_modelindex, g_SmokeSprite);
    
    set_pev(ent, pev_movetype, MOVETYPE_NONE);
    set_pev(ent, pev_solid, SOLID_NOT);
    
    set_pev(ent, pev_rendermode, kRenderTransAlpha);
    set_pev(ent, pev_renderamt, 255.0); 
    
    new Float:pure_black[3] = { 1.0, 1.0, 1.0 };
    set_pev(ent, pev_rendercolor, pure_black);
    
    set_pev(ent, pev_scale, SMOKE_SCALE);
    
    set_pev(ent, pev_nextthink, get_gametime() + SMOKE_LIFESPAN);
    register_forward(FM_Think, "RemoveBlackMask");
    
    // Store this sprite index inside our global array so we can safely manipulate its lifecycle on reset
    if (g_SpriteCount < MAX_SPRITES_TRACKED) {
        g_TrackedSprites[g_SpriteCount] = ent;
        g_SpriteCount++;
    }
}

public RemoveBlackMask(ent) {
    if (pev_valid(ent)) {
        if (pev(ent, pev_modelindex) == g_SmokeSprite) {
            engfunc(EngFunc_RemoveEntity, ent);
        }
    }
}