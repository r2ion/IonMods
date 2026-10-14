#if EXTENDED

global function OnAbilityStart_LaserCannonPredicted
global function OnAbilityEnd_LaserCannonPredicted
global function LaserCannon_PredictionUpdate
global function LaserCannon_PredictionEnd

enum eLaserCannonPredictionState
{
	previousDodgeDisabled
}

enum eLaserCannonPredictionFlag
{
	dodgeDisabled
}

bool function OnAbilityStart_LaserCannonPredicted( entity weapon )
{
	entity owner = weapon.GetWeaponOwner()
	if ( !IsValid( owner ) || !owner.IsPlayer() )
		return OnAbilityStart_LaserCannon( weapon )

	bool previousDodgeDisabled = owner.Prediction_GetMovementFlag( eLaserCannonPredictionFlag.dodgeDisabled )
	bool result = OnAbilityStart_LaserCannon( weapon )
	if ( !result )
		return false

	weapon.Prediction_SetBool( eLaserCannonPredictionState.previousDodgeDisabled, previousDodgeDisabled )
	weapon.Prediction_Start()
	owner.Prediction_SetMovementFlag( eLaserCannonPredictionFlag.dodgeDisabled, true )
	return true
}

void function OnAbilityEnd_LaserCannonPredicted( entity weapon )
{
	OnAbilityEnd_LaserCannon( weapon )
	if ( weapon.Prediction_IsActive() )
		weapon.Prediction_Stop( 0 )
}

void function LaserCannon_PredictionUpdate( entity weapon, entity owner, float commandTime, float commandDuration, bool beforeMovement, bool firstExecution )
{
	if ( !IsValid( owner ) || !owner.IsPlayer() || weapon.GetWeaponOwner() != owner )
	{
		weapon.Prediction_Stop( 1 )
		return
	}

	if ( beforeMovement )
		owner.Prediction_SetMovementFlag( eLaserCannonPredictionFlag.dodgeDisabled, true )
}

void function LaserCannon_PredictionEnd( entity weapon, entity owner, int reason )
{
	if ( !IsValid( weapon ) || !IsValid( owner ) || !owner.IsPlayer() )
		return
	#if SERVER
		owner.Prediction_SetMovementFlag( eLaserCannonPredictionFlag.dodgeDisabled, false )
	#elseif CLIENT
		owner.Prediction_SetMovementFlag( eLaserCannonPredictionFlag.dodgeDisabled, weapon.Prediction_GetBool( eLaserCannonPredictionState.previousDodgeDisabled ) )
	#endif
}

#endif
