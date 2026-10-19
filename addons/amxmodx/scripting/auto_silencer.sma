#include <amxmodx>
#include <fakemeta>
#include <hamsandwich>
#include <cstrike>

public plugin_init() {
    register_plugin("Auto Silencer USP/M4A1", "1.0", " ");

    // O '1' no final significa hook Post (executa um milissegundo DEPOIS da arma ir para o jogador)
    RegisterHam(Ham_Item_AttachToPlayer, "weapon_m4a1", "On_Weapon_Attach_Post", 1);
    RegisterHam(Ham_Item_AttachToPlayer, "weapon_usp", "On_Weapon_Attach_Post", 1);
}

public On_Weapon_Attach_Post(ent, id) {
    // Checa se a entidade da arma realmente existe para evitar logs de erro
    if (!pev_valid(ent)) {
        return HAM_IGNORED;
    }

    // Verifica se a arma ja nao esta silenciada
    if (!cs_get_weapon_silen(ent)) {
        // (entidade, 1 = silenciador ativado, 1 = forca a atualizacao do modelo na mao)
        cs_set_weapon_silen(ent, 1, 1);
    }

    return HAM_IGNORED;
}