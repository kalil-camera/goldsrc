#include <amxmodx>
#include <cstrike>
#include <fun>

public plugin_init() {
    register_plugin("YaPB Strict Economy V2", "2.1", "Custom");
    
    // Dispara no momento exato em que o tempo de congelamento (freezetime) acaba
    register_logevent("On_Round_Start", 2, "1=Round_Start");
}

public On_Round_Start() {
    new players[32], pnum, id;
    
    get_players(players, pnum, "a");
    
    for (new i = 0; i < pnum; i++) {
        id = players[i];
        
        // Ignora jogadores reais, so audita os bots
        if (!is_user_bot(id)) continue;
        
        Audit_Bot_Weapons(id);
    }
}

public Audit_Bot_Weapons(id) {
    new money = cs_get_user_money(id);
    new team = get_user_team(id);
    new bool:needs_upgrade = false;
    new weapon_to_give[32];

    if (team == 1 && (user_has_weapon(id, CSW_GALIL) || user_has_weapon(id, CSW_MP5NAVY))) {
        if (money >= 1000) {
            needs_upgrade = true;
            copy(weapon_to_give, charsmax(weapon_to_give), "weapon_ak47");
        }
    }
    else if (team == 2 && (user_has_weapon(id, CSW_FAMAS) || user_has_weapon(id, CSW_MP5NAVY))) {
        if (money >= 1000) {
            needs_upgrade = true;
            copy(weapon_to_give, charsmax(weapon_to_give), "weapon_m4a1");
        }
    }

    if (needs_upgrade) {
        new pistol[32] = "";
        if (user_has_weapon(id, CSW_DEAGLE)) copy(pistol, charsmax(pistol), "weapon_deagle");
        else if (user_has_weapon(id, CSW_FIVESEVEN)) copy(pistol, charsmax(pistol), "weapon_fiveseven");
        else if (user_has_weapon(id, CSW_USP)) copy(pistol, charsmax(pistol), "weapon_usp");
        else if (user_has_weapon(id, CSW_GLOCK18)) copy(pistol, charsmax(pistol), "weapon_glock18");
        
        // CORREÇÃO: Usando a tag CsArmorType exigida pela cstrike
        new CsArmorType:armor_type;
        new armor = cs_get_user_armor(id, armor_type);

        strip_user_weapons(id);
        
        give_item(id, "weapon_knife");
        
        if (pistol[0] != '^0') {
            give_item(id, pistol);
            cs_set_user_bpammo(id, get_weaponid(pistol), 100);
        }
        
        give_item(id, weapon_to_give);
        cs_set_user_bpammo(id, get_weaponid(weapon_to_give), 90);
        
        // CORREÇÃO: Devolvendo o colete usando diretamente a variavel tipada
        if (armor > 0) {
            cs_set_user_armor(id, armor, armor_type);
        }

        cs_set_user_money(id, money - 1000);
    }
}