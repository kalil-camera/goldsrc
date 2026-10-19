#include <amxmodx>
#include <hamsandwich>

new const PLUGIN[] = "Round Damage Summary"
new const VERSION[] = "0.1"
new const AUTHOR[] = " "

// [Atacante][Vítima] armazena o dano e a quantidade de tiros
new g_iDamage[33][33]; 
new g_iHits[33][33];

// Armazena a vida do jogador antes dele tomar o dano
new g_iHealthBefore[33]; 

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR)
    
    // Registramos o Pre (falso) e o Post (true) para comparar a vida
    RegisterHam(Ham_TakeDamage, "player", "Fwd_TakeDamage_Pre", false);
    RegisterHam(Ham_TakeDamage, "player", "Fwd_TakeDamage_Post", true);
    RegisterHam(Ham_Killed, "player", "Fwd_Killed_Post", true);
    
    // Mudei para HLTV pois é o evento mais confiável e livre de bugs para o início do round no CS 1.6
    register_event("HLTV", "Event_RoundStart", "a", "1=0", "2=0");
}

public Event_RoundStart()
{
    // Reseta o rastreio de dano de todos ao iniciar o round
    for(new i = 1; i <= 32; i++)
    {
        for(new j = 1; j <= 32; j++)
        {
            g_iDamage[i][j] = 0;
            g_iHits[i][j] = 0;
        }
    }
}

public Fwd_TakeDamage_Pre(victim, inflictor, attacker, Float:damage, damagedbits)
{
    // Antes do motor do jogo aplicar o dano, nós salvamos quanto de HP a vítima tem
    if(1 <= victim <= 32)
    {
        g_iHealthBefore[victim] = get_user_health(victim);
    }
}

public Fwd_TakeDamage_Post(victim, inflictor, attacker, Float:damage, damagedbits)
{
    if(!is_user_connected(attacker) || !is_user_connected(victim) || attacker == victim)
        return;

    // Pegamos a vida da vítima APÓS o tiro
    new iHealthAfter = get_user_health(victim);

    // Se o tiro for fatal, a vida pode ficar negativa. Nós travamos em 0 para não somar o "overkill"
    if(iHealthAfter < 0) 
        iHealthAfter = 0;
        
    new iHealthBefore = g_iHealthBefore[victim];
    if(iHealthBefore < 0) 
        iHealthBefore = 0;

    // O dano real é apenas a vida que ele perdeu (já desconsidera o colete)
    new iActualDamage = iHealthBefore - iHealthAfter;

    // Se realmente perdeu HP
    if(iActualDamage > 0)
    {
        g_iDamage[attacker][victim] += iActualDamage;
        g_iHits[attacker][victim]++;
        
        // Regra solicitada: Nunca deixar passar de 100 de dano exibido
        if(g_iDamage[attacker][victim] > 100)
        {
            g_iDamage[attacker][victim] = 100;
        }
    }
}

public Fwd_Killed_Post(victim, killer, shouldgib)
{
    if(!is_user_connected(victim))
        return;

    // Monta a lista de jogadores que a vítima atingiu neste round
    new szBuffer[512], len = 0;
    len += formatex(szBuffer[len], charsmax(szBuffer) - len, "=== DANO CAUSADO ===^n");
    
    new intHitsFound = 0;
    for(new i = 1; i <= 32; i++)
    {
        if(i == victim || !is_user_connected(i)) 
            continue;
            
        if(g_iDamage[victim][i] > 0)
        {
            new szTargetName[32];
            get_user_name(i, szTargetName, charsmax(szTargetName));
            
            len += formatex(szBuffer[len], charsmax(szBuffer) - len, "> %s: %d de dano (com %d tiros)^n", szTargetName, g_iDamage[victim][i], g_iHits[victim][i]);
            intHitsFound++;
        }
    }
    
    if(intHitsFound == 0)
    {
        len += formatex(szBuffer[len], charsmax(szBuffer) - len, "Nenhum.^n");
    }



    // Exibe tudo limpo no centro da tela (HUD) para quem morreu
    set_hudmessage(255, 200, 0, -1.0, 0.32, 0, 6.0, 10.0, 0.5, 0.5, -1);
    show_hudmessage(victim, "%s", szBuffer);
}