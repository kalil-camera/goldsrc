



// ========================================================================= CONFIG START =========================================================================

// Comment this line if you need more CPU or you don't want to block client-side doubleduck.
#define BLOCK_CLIENT_SIDE_DD_VIEW // default: enabled (uncommented)



// If you are using client-side doubleduck block (this is just a start of upcoming configs):
#if defined BLOCK_CLIENT_SIDE_DD_VIEW // this is only a notification (but a needed one) - do not change/remove it.


// Please write any world-view gun model what is automatically downloaded by the engine.
#define ENTITY_MDL "models/w_awp.mdl" // default: ("models/w_awp.mdl") (for use in cs/cz)

// Class-Name of anti-doubleduck entity.
#define ENTITY_NAME "anti_doubleducker" // default: ("anti_doubleducker")


#endif // this is only a notification (but a needed one) - do not change/remove it.

// ========================================================================== CONFIG END ==========================================================================



#include <amxmodx>
#include <fakemeta>

#define PLUGIN_NAME    "No DoubleDuck Spam"
#define PLUGIN_VERSION "0.1"
#define PLUGIN_AUTHOR  " "

#if defined BLOCK_CLIENT_SIDE_DD_VIEW
#define ENTITY_NAME "anti_doubleducker"

new g_iFakeEnt;
#endif
new bool:g_bIsUserDead[33];

public plugin_init()
{
	register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
	
	register_event("ResetHUD", "Event_ResetHUD", "be");
	register_event("Health",   "Event_Health",   "bd", "1=0");
	
	register_forward(FM_PlayerPreThink, "FM_PlayerPreThink_Pre", 0);
	
#if defined BLOCK_CLIENT_SIDE_DD_VIEW
	if( (g_iFakeEnt=engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_target")))>0 ) // if anti-doubleduck entity created successfully:
	{
		set_pev(g_iFakeEnt, pev_classname,  ENTITY_NAME);       // lets register entity as non-standard
		set_pev(g_iFakeEnt, pev_solid,      SOLID_NOT);         // why it should be solid to the server engine?
		set_pev(g_iFakeEnt, pev_movetype,   MOVETYPE_NONE);     // lets make it unmovable
		set_pev(g_iFakeEnt, pev_rendermode, kRenderTransAlpha); // we are starting to render it in invisible mode
		set_pev(g_iFakeEnt, pev_renderamt,  0.0);               // setting visibility level to zero (invinsible)
		
		engfunc(EngFunc_SetModel, g_iFakeEnt, ENTITY_MDL); // we are setting model so client-side trace scan cold detect the entity
		engfunc(EngFunc_SetSize, g_iFakeEnt, Float:{-16.0, -16.0, 53.0}, Float:{16.0, 16.0, 54.0}); // plugin will use less power if we wont change entity size at each FM_AddToFullPack
		
		register_forward(FM_AddToFullPack, "FM_AddToFullPack_Pre", 0); // now we enable main and most important part of client-side double-duck block
	}
#endif
}

public client_connect(iPlrId)
	g_bIsUserDead[iPlrId] = true;

public Event_ResetHUD(iPlrId)
	g_bIsUserDead[iPlrId] = false;

public Event_Health(iPlrId)
	g_bIsUserDead[iPlrId] = true;

public FM_PlayerPreThink_Pre(iPlrId)
{
	if( g_bIsUserDead[iPlrId] )
		return FMRES_IGNORED;
		
	if( pev(iPlrId, pev_oldbuttons)&IN_DUCK && !(pev(iPlrId, pev_button)&IN_DUCK) ) // if user unpressed duck key
	{
		static s_iFlags;
		s_iFlags = pev(iPlrId, pev_flags);
		if( !(s_iFlags&FL_DUCKING) && pev(iPlrId, pev_bInDuck) ) // if user wasn't fully ducked and is in ducking process
		{
			set_pev(iPlrId, pev_bInDuck, false); // set user not in ducking process
			set_pev(iPlrId, pev_flags, (s_iFlags|FL_DUCKING)); // set user fully fucked
			engfunc(EngFunc_SetSize, iPlrId, Float:{-16.0, -16.0, -25.0}, Float:{16.0, 16.0, 25.0}); // set user size as fully ducked (won't take one frame delay)
		}
	}
	
	return FMRES_IGNORED;
}

#if defined BLOCK_CLIENT_SIDE_DD_VIEW
public FM_AddToFullPack_Pre(iEsHandle, iE, iEnt, iPlrId, iHostFlags, iPlayer, iPSet)
{
	if( iEnt==g_iFakeEnt )
	{
		if( g_bIsUserDead[iPlrId] )     // we are just blocking the function if user is dead cause why on earth we need it in this case (plus saves a bit of inet speed)
			return FMRES_SUPERCEDE; // also I would block it if user is on ladder or in water, but it's unneeded CPU usage cause this two cases are rare
		
		static Float:s_fFallSpeed;
		pev(iPlrId, pev_flFallVelocity, s_fFallSpeed);
		if( s_fFallSpeed>=0.0 ) // vertical speed is always 0.0 if user is on ground, so we aren't checking FL_ONGROUND existence. Plus we need a check is user falling down
		{
			static Float:s_fOrigin[3];
			pev(iPlrId, pev_origin, s_fOrigin); // lets get player origin
			
			if( pev(iPlrId, pev_flags)&FL_DUCKING ) // this part teleports anti-doubleduck entity 17 units above player head
				s_fOrigin[2] += s_fFallSpeed?2.0:18.0; // or right on players head if he is falling down to avoid instant double-duck after landing
			else // and yes - if player is ducked we must teleport it a bit higher comparing to player center
				s_fOrigin[2] -= s_fFallSpeed?16.0:0.0;
			
			//set_es(iEsHandle, ES_Origin, s_fOrigin); // don't care asking me why this doesn't work in certain areas - I really dunno. if it did - CPU would be much better...
			engfunc(EngFunc_SetOrigin, iEnt, s_fOrigin); // cause ES_Origin doesn't work I use this one (the one what takes all of this power)
			
			forward_return(FMV_CELL, dllfunc(DLLFunc_AddToFullPack, iEsHandle, iE, iEnt, iPlrId, iHostFlags, iPlayer, iPSet));
			// cause ES_Origin doesn't work I forward my own function and block original one to
			// save CPU by not hooking it twice like I did in 1.6 and older versions of plugin
			
			set_es(iEsHandle, ES_Solid, SOLID_BBOX); // now we are making anti-doubleduck entity solid to the client engine
			
			return FMRES_SUPERCEDE;
		}
		return FMRES_SUPERCEDE; // now we block original AddToFullPack cause or we already forwarded our own one or to save and server 
					// and client CPU and internet power cause we don't need this entity to be sent to client this frame
	}
	
	return FMRES_IGNORED;
}
#endif
