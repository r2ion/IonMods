#if EXTENDED

global function OnAbilityCharge_FlameWavePredicted
global function OnAbilityChargeEnd_FlameWavePredicted
global function FlameWaveCharge_PredictionUpdate
global function FlameWaveCharge_PredictionEnd

enum eFlameWaveChargePredictionState
{
	previousDisembarkEnabled
}

enum eFlameWaveChargePredictionFlag
{
	dodgeDisabled,
	titanDisembarkEnabled
}

bool function OnAbilityCharge_FlameWavePredicted( entity weapon )
{
	entity owner = weapon.GetWeaponOwner()
	if ( !IsValid( owner ) || !owner.IsPlayer() )
		return OnAbilityCharge_FlameWave( weapon )

	bool wasActive = weapon.Prediction_IsActive()
	bool previousDisembarkEnabled = owner.Prediction_GetMovementFlag( eFlameWaveChargePredictionFlag.titanDisembarkEnabled )
	bool result = OnAbilityCharge_FlameWave( weapon )
	if ( !result )
		return false

	if ( !wasActive )
	{
		weapon.Prediction_SetBool( eFlameWaveChargePredictionState.previousDisembarkEnabled, previousDisembarkEnabled )
		weapon.Prediction_Start()
	}
	owner.Prediction_SetMovementFlag( eFlameWaveChargePredictionFlag.titanDisembarkEnabled, false )
	return true
}

void function OnAbilityChargeEnd_FlameWavePredicted( entity weapon )
{
	OnAbilityChargeEnd_FlameWave( weapon )
	if ( weapon.Prediction_IsActive() )
		weapon.Prediction_Stop( 0 )
}

void function FlameWaveCharge_PredictionUpdate( entity weapon, entity owner, float commandTime, float commandDuration, bool beforeMovement, bool firstExecution )
{
	if ( !IsValid( owner ) || !owner.IsPlayer() || weapon.GetWeaponOwner() != owner )
	{
		weapon.Prediction_Stop( 1 )
		return
	}

	if ( beforeMovement )
		owner.Prediction_SetMovementFlag( eFlameWaveChargePredictionFlag.titanDisembarkEnabled, false )
}

void function FlameWaveCharge_PredictionEnd( entity weapon, entity owner, int reason )
{
	if ( !IsValid( weapon ) || !IsValid( owner ) || !owner.IsPlayer() )
		return
	#if SERVER
		owner.Prediction_SetMovementFlag( eFlameWaveChargePredictionFlag.titanDisembarkEnabled, true )
	#elseif CLIENT
		owner.Prediction_SetMovementFlag( eFlameWaveChargePredictionFlag.titanDisembarkEnabled, weapon.Prediction_GetBool( eFlameWaveChargePredictionState.previousDisembarkEnabled ) )
	#endif
}

#endif
