#if EXTENDED

global function OnWeaponPrimaryAttack_titanweapon_leadwall_predicted

const int LEADWALL_PREDICTED_MAX_BOLTS = 8

struct
{
	float[2][LEADWALL_PREDICTED_MAX_BOLTS] boltOffsets = [
		[0.2, 0.8],
		[0.2, -0.8],
		[-0.2, 0.65],
		[-0.2, -0.65],
		[0.2, 0.2],
		[0.2, -0.2],
		[-0.2, 0.2],
		[-0.2, -0.2],
	]
} file

var function OnWeaponPrimaryAttack_titanweapon_leadwall_predicted( entity weapon, WeaponPrimaryAttackParams attackParams )
{
	#if CLIENT
		if ( !weapon.ShouldPredictProjectiles() )
			return 1
	#endif

	entity owner = weapon.GetWeaponOwner()
	vector attackAngles = VectorToAngles( attackParams.dir )
	vector baseUpVec = AnglesToUp( attackAngles )
	vector baseRightVec = AnglesToRight( attackAngles )
	float adsMultiplier = GraphCapped( owner.GetZoomFrac(), 0, 1, 1.0, 0.5 )
	int numProjectiles = weapon.GetProjectilesPerShot()
	weapon.EmitWeaponNpcSound( LOUD_WEAPON_AI_SOUND_RADIUS_MP, 0.2 )

	for ( int index = 0; index < numProjectiles; index++ )
	{
		float upSpread = Prediction_RandomFloat( index * 3, 1.2, 1.7 )
		float rightSpread = Prediction_RandomFloat( index * 3 + 1, 1.2, 1.7 )
		vector upVec = baseUpVec * file.boltOffsets[index][0] * 0.05 * upSpread * adsMultiplier
		vector rightVec = baseRightVec * file.boltOffsets[index][1] * 0.05 * rightSpread * adsMultiplier
		entity bolt = weapon.FireWeaponBolt( attackParams.pos, attackParams.dir + upVec + rightVec, 4400.0, damageTypes.largeCaliber | DF_SHOTGUN, damageTypes.largeCaliber | DF_SHOTGUN, true, index )
		if ( bolt )
		{
			bolt.kv.gravity = 0.4
			float lifetime = Prediction_RandomFloat( index * 3 + 2, 0.30, 0.35 )
			bolt.SetProjectileLifetime( lifetime )
			EmitSoundOnEntity( bolt, "wpn_leadwall_projectile_crackle" )
		}
	}

	return 1
}

#endif
