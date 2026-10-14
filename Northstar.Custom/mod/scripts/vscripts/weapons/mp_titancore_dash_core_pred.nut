#if EXTENDED

global function OnAbilityStart_Dash_CorePredicted
global function DashCore_PredictionUpdate
global function DashCore_PredictionEnd

enum eDashCorePredictionState
{
	endTime,
	previousPowerRegen,
	previousDodgeDelay
}

enum eDashCorePredictionScale
{
	gravity,
	airSpeed,
	airAcceleration,
	groundFriction,
	wallrunFriction,
	powerRegen,
	dodgePowerDelay
}

var function OnAbilityStart_Dash_CorePredicted( entity weapon, WeaponPrimaryAttackParams attackParams )
{
	entity owner = weapon.GetWeaponOwner()
	if ( !IsValid( owner ) || !owner.IsPlayer() || !owner.IsTitan() )
		return OnAbilityStart_Dash_Core( weapon, attackParams )

	float previousPowerRegen = owner.Prediction_GetMovementScale( eDashCorePredictionScale.powerRegen )
	float previousDodgeDelay = owner.Prediction_GetMovementScale( eDashCorePredictionScale.dodgePowerDelay )
	float endTime = Time() + weapon.GetWeaponSettingFloat( eWeaponVar.charge_cooldown_delay )

	var result = OnAbilityStart_Dash_Core( weapon, attackParams )
	if ( !result )
		return result

	weapon.Prediction_SetFloat( eDashCorePredictionState.endTime, endTime )
	weapon.Prediction_SetFloat( eDashCorePredictionState.previousPowerRegen, previousPowerRegen )
	weapon.Prediction_SetFloat( eDashCorePredictionState.previousDodgeDelay, previousDodgeDelay )
	weapon.Prediction_Start()
	DashCore_ApplyMovement( owner )

	#if CLIENT
		owner.Prediction_SetDodgePower( 100.0 )
	#endif

	return result
}

void function DashCore_ApplyMovement( entity owner )
{
	owner.Prediction_SetMovementScale( eDashCorePredictionScale.powerRegen, 16.0 )
	owner.Prediction_SetMovementScale( eDashCorePredictionScale.dodgePowerDelay, 0.1 )
}

void function DashCore_RestoreMovement( entity weapon, entity owner )
{
	owner.Prediction_SetMovementScale( eDashCorePredictionScale.powerRegen, weapon.Prediction_GetFloat( eDashCorePredictionState.previousPowerRegen ) )
	owner.Prediction_SetMovementScale( eDashCorePredictionScale.dodgePowerDelay, weapon.Prediction_GetFloat( eDashCorePredictionState.previousDodgeDelay ) )
}

void function DashCore_PredictionUpdate( entity weapon, entity owner, float commandTime, float commandDuration, bool beforeMovement, bool firstExecution )
{
	if ( !IsValid( owner ) || !owner.IsPlayer() || !owner.IsTitan() || weapon.GetWeaponOwner() != owner )
	{
		weapon.Prediction_Stop( 1 )
		return
	}

	float simulationTime = beforeMovement ? commandTime : commandTime + commandDuration
	if ( simulationTime >= weapon.Prediction_GetFloat( eDashCorePredictionState.endTime ) )
	{
		weapon.Prediction_Stop( 0 )
		return
	}

	if ( beforeMovement )
		DashCore_ApplyMovement( owner )
}

void function DashCore_PredictionEnd( entity weapon, entity owner, int reason )
{
	if ( !IsValid( weapon ) || !IsValid( owner ) || !owner.IsPlayer() )
		return
	#if SERVER
		owner.Prediction_SetMovementScale( eDashCorePredictionScale.powerRegen, 1.0 )
		owner.Prediction_SetMovementScale( eDashCorePredictionScale.dodgePowerDelay, 1.0 )
	#elseif CLIENT
		DashCore_RestoreMovement( weapon, owner )
	#endif
}

#endif
