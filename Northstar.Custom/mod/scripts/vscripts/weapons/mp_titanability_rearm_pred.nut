#if EXTENDED

global function OnWeaponPrimaryAttack_titanability_rearm_predicted

var function OnWeaponPrimaryAttack_titanability_rearm_predicted( entity weapon, WeaponPrimaryAttackParams attackParams )
{
	var result = OnWeaponPrimaryAttack_titanability_rearm( weapon, attackParams )

	#if CLIENT
		entity owner = weapon.GetWeaponOwner()
		if ( IsValid( owner ) && owner.IsPlayer() )
			owner.Prediction_SetDodgePower( 100.0 )
	#endif

	return result
}

#endif
