#include <amxmodx>
#include <fakemeta>
#include <hamsandwich>

#define VERSION "0.1"

#define XTRA_OFS_WEAPON			4
#define m_pPlayer				41
#define m_flNextPrimaryAttack		46
#define m_flNextSecondaryAttack	47
#define m_flTimeWeaponIdle		48
#define m_fWeaponState			74

const USP_SILENCED = (1<<0)
const M4A1_SILENCED = (1<<2)

#define m4a1_add_silencer	6
#define m4a1_detach_silencer	13

#define usp_add_silencer		7
#define usp_detach_silencer	15

public plugin_init()
{
	register_plugin("Anti Fast Silencer", VERSION, " ")

	RegisterHam(Ham_Item_Holster, "weapon_usp", "Usp_Holster")
	RegisterHam(Ham_Item_Holster, "weapon_m4a1", "M4a1_Holster")
}

public Usp_Holster(iEnt)
{
	switch( pev(get_pdata_cbase(iEnt, m_pPlayer, XTRA_OFS_WEAPON), pev_weaponanim) )
	{
		case usp_add_silencer:
		{
			if( get_pdata_float(iEnt, m_flNextSecondaryAttack, XTRA_OFS_WEAPON) == get_pdata_float(iEnt, m_flTimeWeaponIdle, XTRA_OFS_WEAPON) )
			{
				set_pdata_int(iEnt, m_fWeaponState, get_pdata_int(iEnt, m_fWeaponState, XTRA_OFS_WEAPON) & ~USP_SILENCED, XTRA_OFS_WEAPON)
				set_pdata_float(iEnt, m_flNextPrimaryAttack, -1.000, XTRA_OFS_WEAPON)
				set_pdata_float(iEnt, m_flNextSecondaryAttack, -0.001, XTRA_OFS_WEAPON)
			}
		}
		case usp_detach_silencer:
		{
			if( get_pdata_float(iEnt, m_flNextSecondaryAttack, XTRA_OFS_WEAPON) == get_pdata_float(iEnt, m_flTimeWeaponIdle, XTRA_OFS_WEAPON) )
			{
				set_pdata_int(iEnt, m_fWeaponState, get_pdata_int(iEnt, m_fWeaponState, XTRA_OFS_WEAPON) | USP_SILENCED, XTRA_OFS_WEAPON)
				set_pdata_float(iEnt, m_flNextPrimaryAttack, -1.000, XTRA_OFS_WEAPON)
				set_pdata_float(iEnt, m_flNextSecondaryAttack, -0.001, XTRA_OFS_WEAPON)
			}
		}
	}
	
}

public M4a1_Holster(iEnt)
{
	switch( pev(get_pdata_cbase(iEnt, m_pPlayer, XTRA_OFS_WEAPON), pev_weaponanim) )
	{
		case m4a1_add_silencer:
		{
			if( get_pdata_float(iEnt, m_flNextSecondaryAttack, XTRA_OFS_WEAPON) == get_pdata_float(iEnt, m_flTimeWeaponIdle, XTRA_OFS_WEAPON) )
			{
				set_pdata_int(iEnt, m_fWeaponState, get_pdata_int(iEnt, m_fWeaponState, XTRA_OFS_WEAPON) & ~M4A1_SILENCED, XTRA_OFS_WEAPON)
				set_pdata_float(iEnt, m_flNextPrimaryAttack, -1.000, XTRA_OFS_WEAPON)
				set_pdata_float(iEnt, m_flNextSecondaryAttack, -0.001, XTRA_OFS_WEAPON)
			}
		}
		case m4a1_detach_silencer:
		{
			if( get_pdata_float(iEnt, m_flNextSecondaryAttack, XTRA_OFS_WEAPON) == get_pdata_float(iEnt, m_flTimeWeaponIdle, XTRA_OFS_WEAPON) )
			{
				set_pdata_int(iEnt, m_fWeaponState, get_pdata_int(iEnt, m_fWeaponState, XTRA_OFS_WEAPON) | M4A1_SILENCED, XTRA_OFS_WEAPON)
				set_pdata_float(iEnt, m_flNextPrimaryAttack, -1.000, XTRA_OFS_WEAPON)
				set_pdata_float(iEnt, m_flNextSecondaryAttack, -0.001, XTRA_OFS_WEAPON)
			}
		}
	}
}