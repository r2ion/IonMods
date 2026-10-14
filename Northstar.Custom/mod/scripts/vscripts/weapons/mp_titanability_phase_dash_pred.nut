#if EXTENDED
global function OnWeaponPrimaryAttack_titanability_phase_dash_predicted
global function PhaseDash_PredictionUpdate

enum ePhaseDashState
{
	expireTime,
	launchVelocity
}

// is this a kv somewhere?
const PHASE_DASH_SPEED = 1000

var function OnWeaponPrimaryAttack_titanability_phase_dash_predicted( entity weapon, WeaponPrimaryAttackParams attackParams )
{
	entity player = weapon.GetWeaponOwner()
	if ( !IsValid( player ) || !player.IsPlayer() )
		return OnWeaponPrimaryAttack_titanability_phase_dash( weapon, attackParams )

	const float shiftTime = 1.0
	if ( IsAlive( player ) && PhaseShift( player, 0.0, shiftTime ) )
	{
		PlayerUsedOffhand( player, weapon )
		float moveSpeed = PHASE_DASH_SPEED * ( 1.0 - StatusEffect_Get( player, eStatusEffect.dodge_speed_slow ) )
		if ( weapon.HasMod( "fd_phase_distance" ) )
			moveSpeed *= 1.5

		vector velocity = player.Prediction_GetInputDirection() * moveSpeed + <0,0,200>
		weapon.Prediction_SetFloat( ePhaseDashState.expireTime, Time() + shiftTime )
		weapon.Prediction_SetVector( ePhaseDashState.launchVelocity, velocity )
		weapon.Prediction_Start()
		player.Prediction_SetVelocity( velocity )

		#if SERVER
			EmitSoundOnEntityExceptToPlayer( player, player, "Stryder.Dash" )
			entity soul = player.GetTitanSoul()
			if ( soul == null )
				soul = player
			const float fade = 0.5
			StatusEffect_AddTimed( soul, eStatusEffect.move_slow, 0.6, shiftTime + fade, fade )
		#elseif CLIENT
			if ( IsFirstTimePredicted() )
				EmitSoundOnEntity( player, "Stryder.Dash" )
		#endif
	}
	return weapon.GetWeaponSettingInt( eWeaponVar.ammo_per_shot )
}

void function PhaseDash_PredictionUpdate( entity weapon, entity player, float commandTime, float commandDuration, bool beforeMovement, bool firstExecution )
{
	if ( !beforeMovement )
		return
	if ( !IsAlive( player ) || !player.IsTitan() || weapon.GetWeaponOwner() != player )
	{
		weapon.Prediction_Stop( 1 )
		return
	}
	if ( commandTime >= weapon.Prediction_GetFloat( ePhaseDashState.expireTime ) )
		weapon.Prediction_Stop( 0 )
	else if ( !player.IsPhaseShifted() )
		weapon.Prediction_Stop( 1 )
}

#endif
