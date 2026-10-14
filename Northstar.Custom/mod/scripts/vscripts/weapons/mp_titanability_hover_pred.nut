#if EXTENDED
global function OnWeaponPrimaryAttack_TitanHoverPredicted
global function TitanHover_PredictionUpdate
global function TitanHover_PredictionEnd

enum eTitanHoverState
{
	startTime,
	moveStunMultiplier,
	horizontalSpeed,
	previousGravity,
	previousAirSpeed,
	previousAirAcceleration,
	previousGroundFriction,
	previousWallrunFriction,
	previousDodgeDisabled,
	previousDisembarkEnabled,
	hoverEnded,
	disembarkLocked
}

enum eTitanHoverScale
{
	gravity,
	airSpeed,
	airAcceleration,
	groundFriction,
	wallrunFriction
}

enum eTitanHoverFlag
{
	dodgeDisabled,
	titanDisembarkEnabled
}

const TITAN_HOVER_LERP_IN = 0.5
const TITAN_HOVER_DURATION = 3.0
const TITAN_HOVER_SLOW_FADE = 0.75

#if SERVER
struct TitanHoverPresentation
{
	entity player
	entity soul
	float startTime
	int slowHandle = 0
	array<entity> activeFX
	bool thrustEnded = false
	bool landingPlayed = false
}

struct
{
	table<entity, TitanHoverPresentation> presentation
} hoverFile
#endif
var function OnWeaponPrimaryAttack_TitanHoverPredicted( entity weapon, WeaponPrimaryAttackParams attackParams )
{
	entity player = weapon.GetWeaponOwner()
	if ( !IsValid( player ) || !player.IsPlayer() )
		return OnWeaponPrimaryAttack_TitanHover( weapon, attackParams )
	if ( !TitanHover_CanContinue( player ) )
		return

	if ( weapon.Prediction_IsActive() && !weapon.Prediction_GetBool( eTitanHoverState.hoverEnded ) )
		return weapon.GetWeaponSettingInt( eWeaponVar.ammo_per_shot )

	PlayerUsedOffhand( player, weapon )
	entity soul = player.GetTitanSoul()
	float horizontalSpeed = player.HasPassive( ePassives.PAS_NORTHSTAR_FLIGHTCORE ) ? 350.0 : 250.0
	weapon.Prediction_SetFloat( eTitanHoverState.startTime, Time() )
	weapon.Prediction_SetFloat( eTitanHoverState.moveStunMultiplier, 1.0 - StatusEffect_Get( player, eStatusEffect.dodge_speed_slow ) )
	weapon.Prediction_SetFloat( eTitanHoverState.horizontalSpeed, horizontalSpeed )
	weapon.Prediction_SetFloat( eTitanHoverState.previousGravity, player.Prediction_GetMovementScale( eTitanHoverScale.gravity ) )
	weapon.Prediction_SetFloat( eTitanHoverState.previousAirSpeed, player.Prediction_GetMovementScale( eTitanHoverScale.airSpeed ) )
	weapon.Prediction_SetFloat( eTitanHoverState.previousAirAcceleration, player.Prediction_GetMovementScale( eTitanHoverScale.airAcceleration ) )
	weapon.Prediction_SetFloat( eTitanHoverState.previousGroundFriction, player.Prediction_GetMovementScale( eTitanHoverScale.groundFriction ) )
	weapon.Prediction_SetFloat( eTitanHoverState.previousWallrunFriction, player.Prediction_GetMovementScale( eTitanHoverScale.wallrunFriction ) )
	weapon.Prediction_SetBool( eTitanHoverState.previousDodgeDisabled, player.Prediction_GetMovementFlag( eTitanHoverFlag.dodgeDisabled ) )
	if ( !weapon.Prediction_IsActive() || !weapon.Prediction_GetBool( eTitanHoverState.disembarkLocked ) )
		weapon.Prediction_SetBool( eTitanHoverState.previousDisembarkEnabled, player.Prediction_GetMovementFlag( eTitanHoverFlag.titanDisembarkEnabled ) )
	weapon.Prediction_SetBool( eTitanHoverState.hoverEnded, false )
	weapon.Prediction_SetBool( eTitanHoverState.disembarkLocked, true )
	weapon.Prediction_Start()
	TitanHover_ApplyMovement( weapon, player )
	player.Prediction_SetMovementFlag( eTitanHoverFlag.titanDisembarkEnabled, false )
	vector velocity = player.Prediction_GetVelocity()
	velocity.z = 225.0 * weapon.Prediction_GetFloat( eTitanHoverState.moveStunMultiplier )
	player.Prediction_SetVelocity( TitanHover_LimitVelocityHorizontal( velocity, horizontalSpeed + 50.0 ) )

	#if SERVER
		TitanHover_StartPresentation( weapon, player, soul )
	#endif

	return weapon.GetWeaponSettingInt( eWeaponVar.ammo_per_shot )
}

bool function TitanHover_CanContinue( entity player )
{
	if ( !IsValid( player ) || !IsAlive( player ) || !player.IsPlayer() || !player.IsTitan() )
		return false
	entity soul = player.GetTitanSoul()
	if ( !IsValid( soul ) || soul.IsEjecting() )
		return false
	#if SERVER
		if ( IsPlayerDisembarking( player ) )
			return false
	#endif
	return true
}

void function TitanHover_ApplyMovement( entity weapon, entity player )
{
	player.Prediction_SetMovementScale( eTitanHoverScale.gravity, 0.0 )
	player.Prediction_SetMovementScale( eTitanHoverScale.airSpeed, weapon.Prediction_GetFloat( eTitanHoverState.horizontalSpeed ) )
	player.Prediction_SetMovementScale( eTitanHoverScale.airAcceleration, 540.0 )
	player.Prediction_SetMovementScale( eTitanHoverScale.groundFriction, 0.0 )
	player.Prediction_SetMovementScale( eTitanHoverScale.wallrunFriction, 0.0 )
	player.Prediction_SetMovementFlag( eTitanHoverFlag.dodgeDisabled, true )
}

void function TitanHover_RestoreMovement( entity weapon, entity player )
{
	player.Prediction_SetMovementScale( eTitanHoverScale.gravity, weapon.Prediction_GetFloat( eTitanHoverState.previousGravity ) )
	player.Prediction_SetMovementScale( eTitanHoverScale.airSpeed, weapon.Prediction_GetFloat( eTitanHoverState.previousAirSpeed ) )
	player.Prediction_SetMovementScale( eTitanHoverScale.airAcceleration, weapon.Prediction_GetFloat( eTitanHoverState.previousAirAcceleration ) )
	player.Prediction_SetMovementScale( eTitanHoverScale.groundFriction, weapon.Prediction_GetFloat( eTitanHoverState.previousGroundFriction ) )
	player.Prediction_SetMovementScale( eTitanHoverScale.wallrunFriction, weapon.Prediction_GetFloat( eTitanHoverState.previousWallrunFriction ) )
	player.Prediction_SetMovementFlag( eTitanHoverFlag.dodgeDisabled, weapon.Prediction_GetBool( eTitanHoverState.previousDodgeDisabled ) )
}

void function TitanHover_PredictionUpdate( entity weapon, entity player, float commandTime, float commandDuration, bool beforeMovement, bool firstExecution )
{
	if ( !TitanHover_CanContinue( player ) || weapon.GetWeaponOwner() != player )
	{
		weapon.Prediction_Stop( 1 )
		return
	}

	float simulationTime = beforeMovement ? commandTime : commandTime + commandDuration
	float elapsed = simulationTime - weapon.Prediction_GetFloat( eTitanHoverState.startTime )
	bool hoverEnded = weapon.Prediction_GetBool( eTitanHoverState.hoverEnded )
	if ( !hoverEnded && elapsed > TITAN_HOVER_DURATION )
	{
		TitanHover_RestoreMovement( weapon, player )
		weapon.Prediction_SetBool( eTitanHoverState.hoverEnded, true )
		hoverEnded = true
		#if SERVER
			if ( firstExecution )
				TitanHover_EndThrustPresentation( weapon, true )
		#endif
	}

	if ( !hoverEnded )
	{
		if ( beforeMovement )
			TitanHover_ApplyMovement( weapon, player )
		vector velocity = player.Prediction_GetVelocity()
		if ( beforeMovement )
		{
			float riseSpeed = elapsed < TITAN_HOVER_LERP_IN
				? GraphCapped( elapsed, 0.0, TITAN_HOVER_LERP_IN, 225.0, 450.0 )
				: GraphCapped( elapsed, TITAN_HOVER_LERP_IN, TITAN_HOVER_LERP_IN + 0.75, 450.0, 70.0 )
			velocity.z = riseSpeed * weapon.Prediction_GetFloat( eTitanHoverState.moveStunMultiplier )
		}
		velocity = TitanHover_LimitVelocityHorizontal( velocity, weapon.Prediction_GetFloat( eTitanHoverState.horizontalSpeed ) + 50.0 )
		player.Prediction_SetVelocity( velocity )
	}

	if ( weapon.Prediction_GetBool( eTitanHoverState.disembarkLocked ) )
	{
		if ( !beforeMovement && elapsed >= 0.1 && player.IsOnGround() )
		{
			player.Prediction_SetMovementFlag( eTitanHoverFlag.titanDisembarkEnabled, weapon.Prediction_GetBool( eTitanHoverState.previousDisembarkEnabled ) )
			weapon.Prediction_SetBool( eTitanHoverState.disembarkLocked, false )
			#if SERVER
				if ( firstExecution )
					TitanHover_LandingPresentation( weapon )
			#endif
		}
		else
			player.Prediction_SetMovementFlag( eTitanHoverFlag.titanDisembarkEnabled, false )
	}

	if ( hoverEnded && !weapon.Prediction_GetBool( eTitanHoverState.disembarkLocked ) && elapsed >= TITAN_HOVER_DURATION + TITAN_HOVER_SLOW_FADE )
		weapon.Prediction_Stop( 0 )
}

void function TitanHover_PredictionEnd( entity weapon, entity player, int reason )
{
	bool validWeapon = IsValid( weapon )
	if ( validWeapon && IsValid( player ) && player.IsTitan() )
	{
		if ( !weapon.Prediction_GetBool( eTitanHoverState.hoverEnded ) )
			TitanHover_RestoreMovement( weapon, player )
		if ( weapon.Prediction_GetBool( eTitanHoverState.disembarkLocked ) )
			player.Prediction_SetMovementFlag( eTitanHoverFlag.titanDisembarkEnabled, weapon.Prediction_GetBool( eTitanHoverState.previousDisembarkEnabled ) )
	}
	#if SERVER
		if ( validWeapon )
			TitanHover_StopPresentation( weapon )
		else
		{
			array<entity> removedWeapons
			foreach ( hoverWeapon, presentation in hoverFile.presentation )
			{
				if ( !IsValid( hoverWeapon ) && presentation.player == player )
					removedWeapons.append( hoverWeapon )
			}
			foreach ( hoverWeapon in removedWeapons )
				TitanHover_StopPresentation( hoverWeapon )
		}
	#endif
}

#if SERVER
void function TitanHover_StartPresentation( entity weapon, entity player, entity soul )
{
	float startTime = weapon.Prediction_GetFloat( eTitanHoverState.startTime )
	if ( weapon in hoverFile.presentation )
	{
		if ( hoverFile.presentation[weapon].startTime == startTime )
			return
		TitanHover_StopPresentation( weapon )
	}
	TitanHoverPresentation presentation
	presentation.player = player
	presentation.soul = soul
	presentation.startTime = startTime
	hoverFile.presentation[weapon] <- presentation

	CreateShake( player.GetOrigin(), 16, 150, 1.00, 400 )
	PlayFX( FLIGHT_CORE_IMPACT_FX, player.GetOrigin() )
	if ( player.LookupAttachment( "FX_L_BOT_THRUST" ) != 0 )
	{
		presentation.activeFX.append( StartParticleEffectOnEntity_ReturnEntity( player, GetParticleSystemIndex( $"P_xo_jet_fly_large" ), FX_PATTACH_POINT_FOLLOW, player.LookupAttachment( "FX_L_BOT_THRUST" ) ) )
		presentation.activeFX.append( StartParticleEffectOnEntity_ReturnEntity( player, GetParticleSystemIndex( $"P_xo_jet_fly_large" ), FX_PATTACH_POINT_FOLLOW, player.LookupAttachment( "FX_R_BOT_THRUST" ) ) )
		presentation.activeFX.append( StartParticleEffectOnEntity_ReturnEntity( player, GetParticleSystemIndex( $"P_xo_jet_fly_small" ), FX_PATTACH_POINT_FOLLOW, player.LookupAttachment( "FX_L_TOP_THRUST" ) ) )
		presentation.activeFX.append( StartParticleEffectOnEntity_ReturnEntity( player, GetParticleSystemIndex( $"P_xo_jet_fly_small" ), FX_PATTACH_POINT_FOLLOW, player.LookupAttachment( "FX_R_TOP_THRUST" ) ) )
	}
	EmitSoundOnEntityOnlyToPlayer( player, player, "titan_flight_liftoff_1p" )
	EmitSoundOnEntityExceptToPlayer( player, player, "titan_flight_liftoff_3p" )
	EmitSoundOnEntityOnlyToPlayer( player, player, "titan_flight_hover_1p" )
	EmitSoundOnEntityExceptToPlayer( player, player, "titan_flight_hover_3p" )
	presentation.slowHandle = StatusEffect_AddTimed( soul, eStatusEffect.dodge_speed_slow, 0.65, TITAN_HOVER_DURATION + TITAN_HOVER_SLOW_FADE, TITAN_HOVER_SLOW_FADE )
}

void function TitanHover_EndThrustPresentation( entity weapon, bool descent )
{
	if ( !( weapon in hoverFile.presentation ) )
		return
	TitanHoverPresentation presentation = hoverFile.presentation[weapon]
	if ( presentation.thrustEnded )
		return
	presentation.thrustEnded = true
	if ( IsValid( presentation.player ) )
	{
		StopSoundOnEntity( presentation.player, "titan_flight_hover_1p" )
		StopSoundOnEntity( presentation.player, "titan_flight_hover_3p" )
		if ( descent )
		{
			EmitSoundOnEntityOnlyToPlayer( presentation.player, presentation.player, "titan_flight_descent_1p" )
			EmitSoundOnEntityExceptToPlayer( presentation.player, presentation.player, "titan_flight_descent_3p" )
		}
	}
	foreach ( fx in presentation.activeFX )
	{
		if ( IsValid( fx ) )
			fx.Destroy()
	}
	presentation.activeFX.clear()
}

void function TitanHover_LandingPresentation( entity weapon )
{
	if ( !( weapon in hoverFile.presentation ) )
		return
	TitanHoverPresentation presentation = hoverFile.presentation[weapon]
	if ( presentation.landingPlayed || !IsValid( presentation.player ) )
		return
	presentation.landingPlayed = true
	EmitSoundOnEntityOnlyToPlayer( presentation.player, presentation.player, "core_ability_land_1p" )
	EmitSoundOnEntityExceptToPlayer( presentation.player, presentation.player, "core_ability_land_3p" )
}

void function TitanHover_StopPresentation( entity weapon )
{
	if ( !( weapon in hoverFile.presentation ) )
		return
	TitanHover_EndThrustPresentation( weapon, false )
	TitanHoverPresentation presentation = hoverFile.presentation[weapon]
	if ( IsValid( presentation.soul ) && presentation.slowHandle != 0 )
		StatusEffect_Stop( presentation.soul, presentation.slowHandle )
	delete hoverFile.presentation[weapon]
}
#endif // SERVER
vector function TitanHover_LimitVelocityHorizontal( vector vel, float speed )
{
	vector horzVel = <vel.x, vel.y, 0>
	if ( Length( horzVel ) <= speed )
		return vel
	horzVel = Normalize( horzVel )
	horzVel *= speed
	vel.x = horzVel.x
	vel.y = horzVel.y
	return vel
}
#endif
