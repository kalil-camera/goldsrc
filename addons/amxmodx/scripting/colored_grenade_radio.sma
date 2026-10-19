#include <amxmodx>
#include <amxmisc>
#include <reapi>

//#define CUSTOM_FITH_SOUNDS	// Using custom sounds instead "Fire in the hole!"

#if defined CUSTOM_FITH_SOUNDS
	#define MAX_SOUND_PATH_LENGTH	32
	#define MAX_SOUNDS				3
	
	new const g_szHEGrenadeSounds[MAX_SOUNDS][MAX_SOUND_PATH_LENGTH] = {
		"radio/fith/hegrenade1.wav",
		"radio/fith/hegrenade2.wav",
		"radio/fith/hegrenade3.wav"
	}
	
	new const g_szSmokeGrenadeSounds[MAX_SOUNDS][MAX_SOUND_PATH_LENGTH] = {
		"radio/fith/smokegrenade1.wav",
		"radio/fith/smokegrenade2.wav",
		"radio/fith/smokegrenade3.wav"
	}
	
	new const g_szFlashBangSounds[MAX_SOUNDS][MAX_SOUND_PATH_LENGTH] = {
		"radio/fith/flashbang1.wav",
		"radio/fith/flashbang2.wav",
		"radio/fith/flashbang3.wav"
	}
	
	public plugin_precache() {
		for(new i; i < MAX_SOUNDS; i++) {
			precache_sound(g_szHEGrenadeSounds[i])
			precache_sound(g_szSmokeGrenadeSounds[i])
			precache_sound(g_szFlashBangSounds[i])
		}
	}
#endif

public plugin_init() {
	register_plugin("Colored Utilitary Chat", "0.1", " ")
	
	register_dictionary("colored_fith.txt")
	
	RegisterHookChain(RG_CBasePlayer_Radio, "Radio_Pre")
}

public Radio_Pre(pSender, szMsgID[], szMsgVerbose[]) {
	if(szMsgVerbose[0] == EOS || !equal(szMsgVerbose, "#Fire_in_the_hole")) {
		return HC_CONTINUE
	}
	
	new pPlayers[MAX_PLAYERS], iNum, pReceiver, iReceiverTeam
	new iSenderTeam = get_member(pSender, m_iTeam)
	new WeaponIdType:pGrenade = rg_get_user_weapon(pSender)
	#if defined CUSTOM_FITH_SOUNDS
		new szSound[MAX_SOUND_PATH_LENGTH]
	#endif
	
	get_players_ex(pPlayers, iNum, GetPlayers_ExcludeBots)
	
	for(new i; i < iNum; i++) {
		pReceiver = pPlayers[i]
		
		if(get_member(pReceiver, m_bIgnoreRadio)) {
			continue
		}
		
		iReceiverTeam = get_member(pReceiver, m_iTeam)
		
		if(iReceiverTeam != iSenderTeam && any:iReceiverTeam != TEAM_SPECTATOR) {
			continue
		}
		
		switch(pGrenade) {
			case WEAPON_HEGRENADE: {
				client_print_color(pReceiver, print_team_red, "%l", "CFITH_HEGRENADE", pSender)
				
				#if defined CUSTOM_FITH_SOUNDS
					szSound = g_szHEGrenadeSounds[random(sizeof(g_szHEGrenadeSounds))]
				#endif
			}
			case WEAPON_SMOKEGRENADE: {
				client_print_color(pReceiver, print_team_default, "%l", "CFITH_SMOKEGRENADE", pSender)
				
				#if defined CUSTOM_FITH_SOUNDS
					szSound = g_szSmokeGrenadeSounds[random(sizeof(g_szSmokeGrenadeSounds))]
				#endif
			}
			case WEAPON_FLASHBANG: {
				client_print_color(pReceiver, print_team_grey, "%l", "CFITH_FLASHBANG", pSender)
				
				#if defined CUSTOM_FITH_SOUNDS
					szSound = g_szFlashBangSounds[random(sizeof(g_szFlashBangSounds))]
				#endif
			}
			default: {
				return HC_CONTINUE
			}
		}
		
		#if defined CUSTOM_FITH_SOUNDS
			rg_send_audio(pReceiver, szSound)
		#else
			rg_send_audio(pReceiver, "radio/ct_fireinhole.wav")
		#endif
	}
	
	return HC_SUPERCEDE
}

stock WeaponIdType:rg_get_user_weapon(const pPlayer) {
	new pWeapon = get_member(pPlayer, m_pActiveItem)
	
	if(!is_nullent(pWeapon)) {
		return get_member(pWeapon, m_iId)
	}
	
	return WEAPON_NONE
}