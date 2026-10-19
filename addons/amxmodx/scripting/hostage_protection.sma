#include <amxmodx>
#include <hamsandwich>

public plugin_init()
{
    register_plugin("Hostage Protection", "0.1", " ");

    // Bloqueia as marcas de sangue no refém
    RegisterHam(Ham_TraceAttack, "hostage_entity", "BlockHostageDamage");
    
    // Bloqueia a perda de vida do refém
    RegisterHam(Ham_TakeDamage, "hostage_entity", "BlockHostageDamage");
}

public BlockHostageDamage(victim, inflictor, attacker, Float:damage, damage_type)
{
    // Verifica se quem atacou foi um jogador (ID de 1 a 32)
    if (attacker >= 1 && attacker <= 32)
    {
        return HAM_SUPERCEDE;
    }
    
    return HAM_IGNORED;
}