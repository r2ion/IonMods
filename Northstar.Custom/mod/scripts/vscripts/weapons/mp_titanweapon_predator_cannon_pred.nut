#if EXTENDED

global function OnWeaponPrimaryAttack_titanweapon_predator_cannon_predicted

var function OnWeaponPrimaryAttack_titanweapon_predator_cannon_predicted( entity weapon, WeaponPrimaryAttackParams attackParams )
{
	bool hadCloseRangePowerShot = weapon.HasMod( "CloseRangePowerShot" )
	bool hadLongRangePowerShot = weapon.HasMod( "LongRangePowerShot" )
	var result = OnWeaponPrimaryAttack_titanweapon_predator_cannon( weapon, attackParams )

	#if CLIENT
		if ( result && ( hadCloseRangePowerShot || hadLongRangePowerShot ) )
		{
			entity owner = weapon.GetWeaponOwner()
			if ( IsValid( owner ) && owner.IsPlayer() )
			{
				owner.ClearMeleeDisabled()
				owner.Prediction_SetMovementFlag( 1, true )
			}

			array<string> mods = weapon.GetMods()
			if ( hadCloseRangePowerShot )
			{
				mods.fastremovebyvalue( "CloseRangePowerShot" )
				mods.fastremovebyvalue( "fd_CloseRangePowerShot" )
				mods.fastremovebyvalue( "pas_CloseRangePowerShot" )
			}
			else
			{
				mods.fastremovebyvalue( "LongRangePowerShot" )
				mods.fastremovebyvalue( "fd_LongRangePowerShot" )
				mods.fastremovebyvalue( "pas_LongRangePowerShot" )
				if ( !mods.contains( "LongRangeAmmo" ) )
					mods.append( "LongRangeAmmo" )
			}
			weapon.SetMods( mods )
		}
	#endif

	return result
}

#endif
