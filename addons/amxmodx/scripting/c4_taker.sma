#include <amxmodx>
#include <fakemeta>
#include <reapi>

#define PLUGIN "Take C4 From Bot"
#define VERSION "0.1"
#define AUTHOR " "

// Distância máxima para conseguir pegar a C4
#define MAX_DIST 120

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    // Intercepta o botão de "Use" (tecla E) e executa verificação contínua de HUD
    register_forward(FM_CmdStart, "OnCmdStart");
}

public OnCmdStart(id, uc_handle, seed)
{
    // Ignora se o jogador estiver morto ou for um bot
    if (!is_user_alive(id) || is_user_bot(id))
        return FMRES_IGNORED;

    // Executa a verificação visual da HUD a cada frame de comando (muito fluido)
    CheckPlayerAim(id);

    static buttons, oldbuttons;
    buttons = get_uc(uc_handle, UC_Buttons);
    oldbuttons = pev(id, pev_oldbuttons);

    // Dispara apenas no momento exato em que a tecla 'E' for afundada
    if ((buttons & IN_USE) && !(oldbuttons & IN_USE))
    {
        TryTakeC4(id);
    }

    return FMRES_IGNORED;
}

// Função que gerencia a exibição da HUD olhando para o bot
CheckPlayerAim(id)
{
    // Apenas Terroristas vivos podem ver o aviso
    if (get_member(id, m_iTeam) != TEAM_TERRORIST)
        return;

    new target, body;
    // Pega o alvo que o jogador está olhando dentro do limite de MAX_DIST
    get_user_aiming(id, target, body, MAX_DIST);

    // Valida se o alvo é um bot válido, vivo, terrorista e que possui a C4
    if (target > 0 && target <= MaxClients && is_user_alive(target) && is_user_bot(target))
    {
        if (get_member(target, m_iTeam) == TEAM_TERRORIST && rg_has_item_by_name(target, "weapon_c4"))
        {
            // Dupla checagem de segurança da distância por coordenadas 3D
            new Float:origin1[3], Float:origin2[3];
            pev(id, pev_origin, origin1);
            pev(target, pev_origin, origin2);

            if (vector_distance(origin1, origin2) <= MAX_DIST)
            {
                set_hudmessage(0, 255, 0, -1.0, 0.55, 0, 0.1, 2.1, 0.1, 0.1, -1);
                show_hudmessage(id, "[E] - pegar  C4");
                return;
            }
        }
    }

    // Se não estiver olhando para o bot com C4, limpa a HUD instantaneamente
    show_hudmessage(id, "");
}

TryTakeC4(id)
{
    // Apenas Terroristas podem roubar a C4
    if (get_member(id, m_iTeam) != TEAM_TERRORIST)
        return;

    // Se o humano já estiver com a C4, ignora
    if (rg_has_item_by_name(id, "weapon_c4"))
        return;

    new target, body;
    get_user_aiming(id, target, body, MAX_DIST);

    // Se houver um alvo válido, vivo, e for um BOT
    if (target > 0 && target <= MaxClients && is_user_alive(target) && is_user_bot(target))
    {
        // Se o bot for Terrorista e possuir a C4
        if (get_member(target, m_iTeam) == TEAM_TERRORIST && rg_has_item_by_name(target, "weapon_c4"))
        {
            // Remove a C4 do Bot
            rg_remove_item(target, "weapon_c4");
            
            // Entrega a C4 na mão do humano 
            rg_give_item(id, "weapon_c4");

            // Aviso na tela do jogador
            client_print(id, print_center, "Voce pegou a C4!");
        }
    }
}