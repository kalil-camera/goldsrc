#include <amxmodx>
#include <fakemeta>
#include <hamsandwich>

new const PICKUP_SOUND[] = "items/gunpickup2.wav";
new const AMMO_SOUND[]   = "items/9mmclip1.wav";  

const Float:FALL_NOISE = 250.0;

enum { CAT_NONE = 0, CAT_GUN, CAT_PISTOL, CAT_NADE, CAT_BOMB };

new const WEAPONS[][] =
{
    "weapon_p228", "weapon_scout", "weapon_hegrenade", "weapon_xm1014",
    "weapon_mac10", "weapon_aug", "weapon_smokegrenade", "weapon_elite",
    "weapon_fiveseven", "weapon_ump45", "weapon_sg550", "weapon_galil",
    "weapon_famas", "weapon_usp", "weapon_glock18", "weapon_awp",
    "weapon_mp5navy", "weapon_m249", "weapon_m3", "weapon_m4a1",
    "weapon_tmp", "weapon_g3sg1", "weapon_deagle", "weapon_sg552",
    "weapon_ak47", "weapon_p90", "weapon_flashbang"
};

new g_cv_guns, g_cv_pistols, g_cv_nades, g_cv_bomb, g_cv_speed;

new bool:g_fresh[2048];      
new bool:g_buy_emit[33];     
new bool:g_armoury[33];      
new g_pending_cat[33];       
new Float:g_fall[33];        

public plugin_init()
{
    register_plugin("Silent Pickups", "0.1", " ");

    g_cv_guns    = register_cvar("silent_pickup_primary", "1");
    g_cv_pistols = register_cvar("silent_pickup_secondary", "1");
    g_cv_nades   = register_cvar("silent_pickup_nades", "1");
    g_cv_bomb    = register_cvar("silent_pickup_bomb", "0");
    g_cv_speed   = register_cvar("silent_pickup_speed", "150");

    for (new i = 0; i < sizeof WEAPONS; i++)
        RegisterHam(Ham_Spawn, WEAPONS[i], "HamWeaponSpawn", true);

    RegisterHamPlayer(Ham_AddPlayerItem, "HamAddPlayerItem");
    RegisterHam(Ham_Touch, "weaponbox", "HamBoxTouch");
    RegisterHam(Ham_Touch, "armoury_entity", "HamArmouryTouch");

    register_forward(FM_PlayerPreThink, "fw_PreThink");
    register_forward(FM_EmitSound, "fw_EmitSound");
}

public fw_PreThink(id)
{
    if (pev(id, pev_flags) & FL_ONGROUND)
    {
        g_fall[id] = 0.0;
        return;
    }

    static Float:vel[3];
    pev(id, pev_velocity, vel);
    g_fall[id] = -vel[2];
}

public client_disconnected(id)
{
    g_buy_emit[id] = false;
    g_armoury[id] = false;
    g_pending_cat[id] = CAT_NONE;
    g_fall[id] = 0.0;

    remove_task(id + 40000);
    remove_task(id + 50000);
    remove_task(id + 60000);
}

public HamWeaponSpawn(ent)
{
    g_fresh[ent] = true;
    set_task(0.0, "TaskClearFresh", ent + 20000);
}

public TaskClearFresh(taskid)
    g_fresh[taskid - 20000] = false;

public TaskClearCat(taskid)
    g_pending_cat[taskid - 40000] = CAT_NONE;

public TaskClearBuy(taskid)
    g_buy_emit[taskid - 50000] = false;

public TaskClearArmoury(taskid)
    g_armoury[taskid - 60000] = false;

weapon_category(const cls[])
{
    if (equal(cls, "weapon_hegrenade") || equal(cls, "weapon_flashbang") || equal(cls, "weapon_smokegrenade"))
        return CAT_NADE;

    if (equal(cls, "weapon_usp") || equal(cls, "weapon_glock18") || equal(cls, "weapon_deagle")
     || equal(cls, "weapon_p228") || equal(cls, "weapon_fiveseven") || equal(cls, "weapon_elite"))
        return CAT_PISTOL;

    if (equal(cls, "weapon_c4"))
        return CAT_BOMB;

    if (equal(cls, "weapon_knife"))
        return CAT_NONE;

    return CAT_GUN;
}

// A dropped weaponbox wears its weapon's w_ model ("models/w_ak47.mdl")
model_category(const model[])
{
    if (!equal(model, "models/w_", 9))
        return CAT_NONE;

    static wname[32];
    formatex(wname, charsmax(wname), "weapon_%s", model[9]); // "weapon_ak47.mdl"
    new dot = contain(wname, ".");
    if (dot > 0)
        wname[dot] = EOS;

    if (equal(wname, "weapon_mp5"))      return CAT_GUN;  // weapon_mp5navy
    if (equal(wname, "weapon_backpack")) return CAT_BOMB; // dropped C4

    return weapon_category(wname);
}

public HamBoxTouch(box, id)
{
    if (!is_user_alive(id))
        return;

    static model[32];
    pev(box, pev_model, model, charsmax(model));

    new cat = model_category(model);
    if (cat == CAT_NONE)
        return;

    g_pending_cat[id] = cat;
    set_task(0.0, "TaskClearCat", id + 40000);
}

public HamArmouryTouch(ent, id)
{
    if (!is_user_alive(id))
        return;

    static cls[32];
    pev(ent, pev_classname, cls, charsmax(cls));
    if (equal(cls, "armoury_entity"))
        return;

    g_armoury[id] = true;
    set_task(0.0, "TaskClearArmoury", id + 60000);
}

public HamAddPlayerItem(id, ent)
{
    static cls[24]; 
    pev(ent, pev_classname, cls, charsmax(cls));

    new cat = weapon_category(cls);
    if (cat == CAT_NONE)
        return;

    new bool:is_buy = g_fresh[ent] && !g_armoury[id];
    g_fresh[ent] = false;

    if (is_buy)
    {
        g_buy_emit[id] = true;

        set_task(0.0, "TaskClearBuy", id + 50000);
        return;
    }

    g_pending_cat[id] = cat;
    set_task(0.0, "TaskClearCat", id + 40000);
}

category_enabled(cat)
{
    switch (cat)
    {
        case CAT_GUN:    return get_pcvar_num(g_cv_guns)    != 0;
        case CAT_PISTOL: return get_pcvar_num(g_cv_pistols) != 0;
        case CAT_NADE:   return get_pcvar_num(g_cv_nades)   != 0;
        case CAT_BOMB:   return get_pcvar_num(g_cv_bomb)    != 0;
    }
    return false;
}

public fw_EmitSound(entity, channel, const sample[], Float:volume, Float:attenuation, flags, pitch)
{
    if (sample[0] != 'i')
        return FMRES_IGNORED;
    if (!equal(sample, PICKUP_SOUND) && !equal(sample, AMMO_SOUND))
        return FMRES_IGNORED;

    new id;
    if (is_user_alive(entity))
        id = entity;
    else if (pev_valid(entity))
    {
        id = pev(entity, pev_owner);
        if (!is_user_alive(id))
            id = pev(entity, pev_aiment);
    }
    else
        return FMRES_IGNORED;
    if (!is_user_alive(id))
        return FMRES_IGNORED;

    // Buy/give: always audible
    if (g_buy_emit[id])
    {
        g_buy_emit[id] = false;
        return FMRES_IGNORED;
    }

    new cat = g_pending_cat[id];

    if (!category_enabled(cat))
        return FMRES_IGNORED;

    new Float:maxspeed = get_pcvar_float(g_cv_speed);
    if (maxspeed < 1.0)        maxspeed = 1.0;
    else if (maxspeed > 300.0) maxspeed = 300.0;

    static Float:velocity[3];
    pev(id, pev_velocity, velocity);

    new Float:hspeed = floatsqroot(velocity[0] * velocity[0] + velocity[1] * velocity[1]);

    // Silent only when both quiet on foot and not landing hard enough to be heard.
    if (hspeed <= maxspeed && g_fall[id] < FALL_NOISE)
        return FMRES_SUPERCEDE;

    return FMRES_IGNORED;
}
