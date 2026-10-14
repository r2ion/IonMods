#if EXTENDED

global function OnAbilityStart_FlightCorePredicted
global function OnAbilityEnd_FlightCorePredicted
global function FlightCore_PredictionUpdate
global function FlightCore_PredictionEnd

enum eFlightCorePredictionState
{
	startTime,
	duration,
	moveStunMultiplier,
	horizontalSpeed,
	previousGravity,
	previousAirSpeed,
	previousAirAcceleration,
	previousGroundFriction,
	previousDodgeDisabled,
	previousDisembarkEnabled,
	hoverEnded,
	disembarkLocked
}

enum eFlightCorePredictionScale
{
	gravity,
	airSpeed,
	airAcceleration,
	groundFriction
}

enum eFlightCorePredictionFlag
{
	dodgeDisabled,
	titanDisembarkEnabled
}

const float FLIGHT_CORE_LERP_IN = 0.5
const float FLIGHT_CORE_SLOW_FADE = 0.75

bool function OnAbilityStart_FlightCorePredicted( entity weapon )
{
	entity owner = weapon.GetWeaponOwner()
	if ( !IsValid( owner ) || !owner.IsPlayer() || !owner.IsTitan() )
		return OnAbilityStart_FlightCore( weapon )

	float startTime = Time()
	float duration = weapon.GetCoreDuration()
	float moveStunMultiplier = 1.0 - StatusEffect_Get( owner, eStatusEffect.dodge_speed_slow )
	float horizontalSpeed = owner.HasPassive( ePassives.PAS_NORTHSTAR_FLIGHTCORE ) ? 350.0 : 200.0
	float previousGravity = owner.Prediction_GetMovementScale( eFlightCorePredictionScale.gravity )
	float previousAirSpeed = owner.Prediction_GetMovementScale( eFlightCorePredictionScale.airSpeed )
	float previousAirAcceleration = owner.Prediction_GetMovementScale( eFlightCorePredictionScale.airAcceleration )
	float previousGroundFriction = owner.Prediction_GetMovementScale( eFlightCorePredictionScale.groundFriction )
	bool previousDodgeDisabled = owner.Prediction_GetMovementFlag( eFlightCorePredictionFlag.dodgeDisabled )
	bool previousDisembarkEnabled = owner.Prediction_GetMovementFlag( eFlightCorePredictionFlag.titanDisembarkEnabled )

	bool result = OnAbilityStart_FlightCore( weapon )
	if ( !result )
		return false

	weapon.Prediction_SetFloat( eFlightCorePredictionState.startTime, startTime )
	weapon.Prediction_SetFloat( eFlightCorePredictionState.duration, duration )
	weapon.Prediction_SetFloat( eFlightCorePredictionState.moveStunMultiplier, moveStunMultiplier )
	weapon.Prediction_SetFloat( eFlightCorePredictionState.horizontalSpeed, horizontalSpeed )
	weapon.Prediction_SetFloat( eFlightCorePredictionState.previousGravity, previousGravity )
	weapon.Prediction_SetFloat( eFlightCorePredictionState.previousAirSpeed, previousAirSpeed )
	weapon.Prediction_SetFloat( eFlightCorePredictionState.previousAirAcceleration, previousAirAcceleration )
	weapon.Prediction_SetFloat( eFlightCorePredictionState.previousGroundFriction, previousGroundFriction )
	weapon.Prediction_SetBool( eFlightCorePredictionState.previousDodgeDisabled, previousDodgeDisabled )
	weapon.Prediction_SetBool( eFlightCorePredictionState.previousDisembarkEnabled, previousDisembarkEnabled )
	weapon.Prediction_SetBool( eFlightCorePredictionState.hoverEnded, false )
	weapon.Prediction_SetBool( eFlightCorePredictionState.disembarkLocked, true )
	weapon.Prediction_Start()

	FlightCore_ApplyMovement( weapon, owner )
	owner.Prediction_SetMovementFlag( eFlightCorePredictionFlag.titanDisembarkEnabled, false )
	vector velocity = owner.Prediction_GetVelocity()
	velocity.z = 225.0 * moveStunMultiplier
	owner.Prediction_SetVelocity( FlightCore_LimitVelocityHorizontal( velocity, horizontalSpeed + 50.0 ) )
	return true
}

void function OnAbilityEnd_FlightCorePredicted( entity weapon )
{
	OnAbilityEnd_FlightCore( weapon )
}

bool function FlightCore_CanContinue( entity owner )
{
	if ( !IsValid( owner ) || !IsAlive( owner ) || !owner.IsPlayer() || !owner.IsTitan() )
		return false
	entity soul = owner.GetTitanSoul()
	if ( !IsValid( soul ) || soul.IsEjecting() )
		return false
	#if SERVER
		if ( IsPlayerDisembarking( owner ) )
			return false
	#endif
	return true
}

void function FlightCore_ApplyMovement( entity weapon, entity owner )
{
	owner.Prediction_SetMovementScale( eFlightCorePredictionScale.gravity, 0.0 )
	owner.Prediction_SetMovementScale( eFlightCorePredictionScale.airSpeed, weapon.Prediction_GetFloat( eFlightCorePredictionState.horizontalSpeed ) )
	owner.Prediction_SetMovementScale( eFlightCorePredictionScale.airAcceleration, 540.0 )
	owner.Prediction_SetMovementScale( eFlightCorePredictionScale.groundFriction, 0.0 )
	owner.Prediction_SetMovementFlag( eFlightCorePredictionFlag.dodgeDisabled, true )
}

void function FlightCore_RestoreMovement( entity weapon, entity owner )
{
	#if SERVER
		owner.Prediction_SetMovementScale( eFlightCorePredictionScale.gravity, expect float( owner.GetPlayerSettingsField( "gravityScale" ) ) )
		owner.Prediction_SetMovementScale( eFlightCorePredictionScale.airSpeed, expect float( owner.GetPlayerSettingsField( "airSpeed" ) ) )
		owner.Prediction_SetMovementScale( eFlightCorePredictionScale.airAcceleration, expect float( owner.GetPlayerSettingsField( "airAcceleration" ) ) )
		owner.Prediction_SetMovementScale( eFlightCorePredictionScale.groundFriction, 1.0 )
		owner.Prediction_SetMovementFlag( eFlightCorePredictionFlag.dodgeDisabled, false )
	#elseif CLIENT
		owner.Prediction_SetMovementScale( eFlightCorePredictionScale.gravity, weapon.Prediction_GetFloat( eFlightCorePredictionState.previousGravity ) )
		owner.Prediction_SetMovementScale( eFlightCorePredictionScale.airSpeed, weapon.Prediction_GetFloat( eFlightCorePredictionState.previousAirSpeed ) )
		owner.Prediction_SetMovementScale( eFlightCorePredictionScale.airAcceleration, weapon.Prediction_GetFloat( eFlightCorePredictionState.previousAirAcceleration ) )
		owner.Prediction_SetMovementScale( eFlightCorePredictionScale.groundFriction, weapon.Prediction_GetFloat( eFlightCorePredictionState.previousGroundFriction ) )
		owner.Prediction_SetMovementFlag( eFlightCorePredictionFlag.dodgeDisabled, weapon.Prediction_GetBool( eFlightCorePredictionState.previousDodgeDisabled ) )
	#endif
}

void function FlightCore_RestoreDisembark( entity weapon, entity owner )
{
	#if SERVER
		owner.Prediction_SetMovementFlag( eFlightCorePredictionFlag.titanDisembarkEnabled, true )
	#elseif CLIENT
		owner.Prediction_SetMovementFlag( eFlightCorePredictionFlag.titanDisembarkEnabled, weapon.Prediction_GetBool( eFlightCorePredictionState.previousDisembarkEnabled ) )
	#endif
}

void function FlightCore_PredictionUpdate( entity weapon, entity owner, float commandTime, float commandDuration, bool beforeMovement, bool firstExecution )
{
	if ( !FlightCore_CanContinue( owner ) || weapon.GetWeaponOwner() != owner )
	{
		weapon.Prediction_Stop( 1 )
		return
	}

	float simulationTime = beforeMovement ? commandTime : commandTime + commandDuration
	float elapsed = simulationTime - weapon.Prediction_GetFloat( eFlightCorePredictionState.startTime )
	float duration = weapon.Prediction_GetFloat( eFlightCorePredictionState.duration )
	bool hoverEnded = weapon.Prediction_GetBool( eFlightCorePredictionState.hoverEnded )
	if ( !hoverEnded && elapsed > duration )
	{
		FlightCore_RestoreMovement( weapon, owner )
		weapon.Prediction_SetBool( eFlightCorePredictionState.hoverEnded, true )
		hoverEnded = true
	}

	if ( !hoverEnded )
	{
		if ( beforeMovement )
			FlightCore_ApplyMovement( weapon, owner )
		vector velocity = owner.Prediction_GetVelocity()
		if ( beforeMovement )
		{
			float riseSpeed = elapsed < FLIGHT_CORE_LERP_IN
				? GraphCapped( elapsed, 0.0, FLIGHT_CORE_LERP_IN, 225.0, 450.0 )
				: GraphCapped( elapsed, FLIGHT_CORE_LERP_IN, FLIGHT_CORE_LERP_IN + 0.75, 450.0, 70.0 )
			velocity.z = riseSpeed * weapon.Prediction_GetFloat( eFlightCorePredictionState.moveStunMultiplier )
		}
		velocity = FlightCore_LimitVelocityHorizontal( velocity, weapon.Prediction_GetFloat( eFlightCorePredictionState.horizontalSpeed ) + 50.0 )
		owner.Prediction_SetVelocity( velocity )
	}

	if ( weapon.Prediction_GetBool( eFlightCorePredictionState.disembarkLocked ) )
	{
		if ( !beforeMovement && elapsed >= 0.1 && owner.IsOnGround() )
		{
			FlightCore_RestoreDisembark( weapon, owner )
			weapon.Prediction_SetBool( eFlightCorePredictionState.disembarkLocked, false )
		}
		else
			owner.Prediction_SetMovementFlag( eFlightCorePredictionFlag.titanDisembarkEnabled, false )
	}

	if ( hoverEnded && !weapon.Prediction_GetBool( eFlightCorePredictionState.disembarkLocked ) && elapsed >= duration + FLIGHT_CORE_SLOW_FADE )
		weapon.Prediction_Stop( 0 )
}

void function FlightCore_PredictionEnd( entity weapon, entity owner, int reason )
{
	if ( !IsValid( weapon ) || !IsValid( owner ) || !owner.IsPlayer() )
		return
	if ( !weapon.Prediction_GetBool( eFlightCorePredictionState.hoverEnded ) )
		FlightCore_RestoreMovement( weapon, owner )
	if ( weapon.Prediction_GetBool( eFlightCorePredictionState.disembarkLocked ) )
		FlightCore_RestoreDisembark( weapon, owner )
}

vector function FlightCore_LimitVelocityHorizontal( vector velocity, float speed )
{
	vector horizontal = <velocity.x, velocity.y, 0>
	if ( Length( horizontal ) <= speed )
		return velocity
	horizontal = Normalize( horizontal ) * speed
	velocity.x = horizontal.x
	velocity.y = horizontal.y
	return velocity
}

#endif
