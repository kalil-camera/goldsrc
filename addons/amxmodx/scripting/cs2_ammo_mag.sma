#include <amxmodx>
#include <fakemeta>
#include <hamsandwich>
#include <cstrike>

#define PLUGIN "CS2 Ammo System"
#define VERSION "0.1_Fix"
#define AUTHOR " "

// Offsets
#define EXTRAOFFSET_WEAPONS 4
#define m_pPlayer           41
#define m_iId               43
#define m_iClip             51
#define m_fInReload         54
#define m_rgpPlayerItems    367 // Array de slots de inventario (0 a 5)

// Globales guardadas en caché
new g_msgAmmoX
new g_iMaxPlayers

// Constantes de Configuración de Armas
new const MAX_CLIP[31] = {
    0, 13, 0, 10, 0, 7, 0, 30, 30, 0, 
    30, 20, 25, 30, 35, 25, 12, 20, 10, 30, 
    100, 8, 30, 30, 20, 0, 7, 30, 30, 0, 50
}

new const WPN_AMMO_ID[31] = {
    0, 9, 0, 2, 12, 5, 14, 6, 4, 13, 
    10, 7, 6, 4, 4, 4, 6, 10, 1, 10, 
    3, 5, 4, 10, 2, 11, 8, 4, 2, 0, 7
}

new const CS2_BPAMMO[31] = {
    0, 52, 0, 90, 0, 35, 0, 90, 90, 0, 
    120, 100, 100, 90, 105, 75, 48, 80, 30, 120, 
    200, 32, 90, 120, 80, 0, 35, 90, 90, 0, 100
}

new const AMMO_DIVISOR[15] = {
    1, 10, 30, 100, 30, 8, 25, 50, 7, 13, 30, 1, 1, 1, 1
}

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR)
    
    // Almacenar IDs globales en caché para evitar consultas repetidas al Engine
    g_msgAmmoX = get_user_msgid("AmmoX")
    g_iMaxPlayers = get_maxplayers()
    
    register_message(g_msgAmmoX, "message_AmmoX")
    RegisterHam(Ham_Spawn, "player", "fw_PlayerSpawn_Post", 1)
    
    new wpn_name[32]
    for(new i = 1; i <= 30; i++) {
        if(MAX_CLIP[i] > 0) {
            get_weaponname(i, wpn_name, charsmax(wpn_name))
            
            RegisterHam(Ham_Item_AddToPlayer, wpn_name, "fw_AddToPlayer_Post", 1)
            RegisterHam(Ham_Item_Deploy, wpn_name, "fw_Deploy_Post", 1)
            RegisterHam(Ham_Weapon_Reload, wpn_name, "fw_Reload_Post", 1)
            
            // NOVO: Intercepta quando a arma é guardada (Cancelamento)
            RegisterHam(Ham_Item_Holster, wpn_name, "fw_Holster_Pre", 0)
        }
    }
}

public fw_Deploy_Post(ent) {
    if(!pev_valid(ent)) return HAM_IGNORED

    new id = get_pdata_cbase(ent, m_pPlayer, EXTRAOFFSET_WEAPONS)
    if(1 <= id <= g_iMaxPlayers && is_user_alive(id)) {
        
        // Obtener ID del arma directamente desde su offset
        new wpn_id = get_pdata_int(ent, m_iId, EXTRAOFFSET_WEAPONS)
        if(1 <= wpn_id <= 30 && MAX_CLIP[wpn_id] > 0) {
            
            new bp = cs_get_user_bpammo(id, wpn_id)
            if(bp > 0) {
                new clip = MAX_CLIP[wpn_id]
                new mags = (bp + clip - 1) / clip
                
                message_begin(MSG_ONE_UNRELIABLE, g_msgAmmoX, _, id)
                write_byte(WPN_AMMO_ID[wpn_id])
                write_byte(mags)
                message_end()
            }
        }
    }
    return HAM_IGNORED
}

public message_AmmoX(msg_id, msg_dest, msg_entity) {
    if(!is_user_alive(msg_entity)) return PLUGIN_CONTINUE
    
    new ammo_id = get_msg_arg_int(1)
    new amount = get_msg_arg_int(2)
    
    if(0 < ammo_id < 15 && amount > 0) {
        new wpn_id = get_user_weapon(msg_entity)
        new clip_size = 0
        
        if(1 <= wpn_id <= 30 && MAX_CLIP[wpn_id] > 0 && WPN_AMMO_ID[wpn_id] == ammo_id) {
            clip_size = MAX_CLIP[wpn_id]
        }
        
        if(clip_size == 0) {
            clip_size = AMMO_DIVISOR[ammo_id]
        }
        
        new mags = (amount + clip_size - 1) / clip_size
        set_msg_arg_int(2, ARG_BYTE, mags)
    }
    return PLUGIN_CONTINUE
}

public fw_PlayerSpawn_Post(id) {
    if(is_user_alive(id)) {
        set_task(0.1, "task_refill", id)
    }
}

public task_refill(id) {
    if(!is_user_alive(id)) return
    
    // Recorremos los slots del inventario directamente por Offsets de CBasePlayer
    for(new slot = 1; slot <= 2; slot++) { // Slot 1 = Primarias, Slot 2 = Secundarias
        new ent = get_pdata_cbase(id, m_rgpPlayerItems + slot)
        
        while(pev_valid(ent)) {
            new wpn_id = get_pdata_int(ent, m_iId, EXTRAOFFSET_WEAPONS)
            
            if(1 <= wpn_id <= 30 && MAX_CLIP[wpn_id] > 0) {
                // Rellenar reserva
                cs_set_user_bpammo(id, wpn_id, CS2_BPAMMO[wpn_id])
                // Rellenar cargador
                set_pdata_int(ent, m_iClip, MAX_CLIP[wpn_id], EXTRAOFFSET_WEAPONS)
            }
            // Siguiente arma en la lista enlazada del mismo slot
            ent = get_pdata_cbase(ent, 42, EXTRAOFFSET_WEAPONS) // m_pNext
        }
    }
}

public fw_AddToPlayer_Post(ent, id) {
    if(pev_valid(ent) && is_user_alive(id)) {
        if(pev(ent, pev_iuser4) == 0) {
            set_pev(ent, pev_iuser4, 1)
            
            new wpn_id = get_pdata_int(ent, m_iId, EXTRAOFFSET_WEAPONS)
            if(1 <= wpn_id <= 30 && MAX_CLIP[wpn_id] > 0) {
                cs_set_user_bpammo(id, wpn_id, CS2_BPAMMO[wpn_id])
            }
        }
    }
    return HAM_IGNORED
}

public fw_Reload_Post(ent) {
    if(pev_valid(ent) && get_pdata_int(ent, m_fInReload, EXTRAOFFSET_WEAPONS) == 1) {
        new id = get_pdata_cbase(ent, m_pPlayer, EXTRAOFFSET_WEAPONS)
        
        if(1 <= id <= g_iMaxPlayers && is_user_alive(id)) {
            new wpn_id = get_pdata_int(ent, m_iId, EXTRAOFFSET_WEAPONS)
            
            if(1 <= wpn_id <= 30 && MAX_CLIP[wpn_id] > 0) {
                new clip = get_pdata_int(ent, m_iClip, EXTRAOFFSET_WEAPONS)
                new bp = cs_get_user_bpammo(id, wpn_id)
                
                if(0 < clip < MAX_CLIP[wpn_id] && bp > 0) {
                    // NOVO: Salva a munição atual no pev_iuser3 ANTES de zerar o pente
                    set_pev(ent, pev_iuser3, clip)
                    set_pdata_int(ent, m_iClip, 0, EXTRAOFFSET_WEAPONS)
                }
            }
        }
    }
    return HAM_IGNORED
}

// NOVO: Função que restaura a munição caso o reload seja cancelado
public fw_Holster_Pre(ent) {
    if(!pev_valid(ent)) return HAM_IGNORED

    // Verifica se a arma foi guardada enquanto recarregava (Cancelamento)
    if(get_pdata_int(ent, m_fInReload, EXTRAOFFSET_WEAPONS) == 1) {
        new old_clip = pev(ent, pev_iuser3)
        
        // Se havia munição salva, devolve para o pente
        if(old_clip > 0) {
            set_pdata_int(ent, m_iClip, old_clip, EXTRAOFFSET_WEAPONS)
            set_pev(ent, pev_iuser3, 0) // Limpa o valor salvo após usar
        }
    }
    
    return HAM_IGNORED
}