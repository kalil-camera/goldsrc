#include <amxmodx>
#include <hamsandwich>

public plugin_init() {
    register_plugin("Block Shield & NVG", "0.1", " ");

    // Bloqueia as tentativas de compra via menu, binds ou console (Jogadores reais)
    register_clcmd("shield", "Block_Command");
    register_clcmd("nvgs", "Block_Command");

    // Bloqueia a entrega fisica do escudo para o jogador (Garante o bloqueio para Bots e autobuy)
    RegisterHam(Ham_Item_AttachToPlayer, "weapon_shield", "Block_Shield_Pickup", 0);
}

public Block_Command(id) {
    client_print(id, print_center, "Item desativado.");
    
    // PLUGIN_HANDLED interrompe o comando antes do servidor cobrar o dinheiro
    return PLUGIN_HANDLED;
}

public Block_Shield_Pickup(ent, id) {
    // Se por acaso um bot ou menu antigo tentar entregar um escudo, isso cancela a acao
    client_print(id, print_center, "Item desativado.");
    return HAM_SUPERCEDE;
}