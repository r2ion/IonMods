#if EXTENDED
global function OnAbilityStart_Shift_CorePredicted
global function ShiftCore_PredictionUpdate
global function ShiftCore_PredictionEnd
global function ShiftCore_IsPredictedActive

enum eShiftCorePredictionState
{
	expiryTime,
	previousPowerRegenRateScale,
	soulHandle
}

const SHIFT_CORE_POWER_REGEN_SCALE = 5


var function OnAbilityStart_Shift_CorePredicted( entity weapon, WeaponPrimaryAttackParams attackParams )
{
	entity player = weapon.GetWeaponOwner()
	if ( !IsValid( player ) || !player.IsPlayer() )
		return OnAbilityStart_Shift_Core( weapon, attackParams )
	if ( weapon.Prediction_IsActive() )
		return 1

	#if CLIENT
		OnAbilityStart_TitanCore( weapon )
	#endif
	if ( !ShiftCore_CanContinue( player ) )
		return 0
	entity meleeWeapon = player.GetOffhandWeapon( OFFHAND_MELEE )
	if ( !IsValid( meleeWeapon ) || meleeWeapon.GetWeaponClassName() != "melee_titan_sword" )
		return 0

	entity soul = player.GetTitanSoul()
	weapon.Prediction_SetFloat( eShiftCorePredictionState.expiryTime, Time() + GetTitanCoreDurationFromWeapon( weapon ) )
	weapon.Prediction_SetFloat( eShiftCorePredictionState.previousPowerRegenRateScale, player.Prediction_GetMovementScale( SHIFT_CORE_POWER_REGEN_SCALE ) )
	weapon.Prediction_SetInt( eShiftCorePredictionState.soulHandle, Prediction_GetEntityHandle( soul ) )
	weapon.Prediction_Start()
	player.Prediction_SetMovementScale( SHIFT_CORE_POWER_REGEN_SCALE, 6.5 )
	#if CLIENT
		player.Prediction_SetDodgePower( 100.0 )
	#elseif SERVER
		OnAbilityStart_Shift_Core( weapon, attackParams )
		weapon.Prediction_SetFloat( eShiftCorePredictionState.expiryTime, soul.GetCoreChargeExpireTime() )
	#endif
	return 1
}

bool function ShiftCore_CanContinue( entity player )
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

void function ShiftCore_PredictionUpdate( entity weapon, entity player, float commandTime, float commandDuration, bool beforeMovement, bool firstExecution )
{
	if ( !ShiftCore_CanContinue( player ) || weapon.GetWeaponOwner() != player )
	{
		weapon.Prediction_Stop( 1 )
		return
	}
	entity soul = player.GetTitanSoul()
	if ( Prediction_GetEntityHandle( soul ) != weapon.Prediction_GetInt( eShiftCorePredictionState.soulHandle ) )
	{
		weapon.Prediction_Stop( 1 )
		return
	}

	#if SERVER
		weapon.Prediction_SetFloat( eShiftCorePredictionState.expiryTime, soul.GetCoreChargeExpireTime() )
		if ( !PlayerHasPassive( player, ePassives.PAS_SHIFT_CORE ) )
		{
			weapon.Prediction_Stop( 1 )
			return
		}
	#endif

	float simulationTime = beforeMovement ? commandTime : commandTime + commandDuration
	if ( simulationTime >= weapon.Prediction_GetFloat( eShiftCorePredictionState.expiryTime ) )
	{
		weapon.Prediction_Stop( 0 )
		return
	}
	player.Prediction_SetMovementScale( SHIFT_CORE_POWER_REGEN_SCALE, 6.5 )
}

void function ShiftCore_PredictionEnd( entity weapon, entity player, int reason )
{
	if ( !IsValid( player ) || !player.IsTitan() || !IsValid( weapon ) )
		return
	entity soul = player.GetTitanSoul()
	if ( !IsValid( soul ) || Prediction_GetEntityHandle( soul ) != weapon.Prediction_GetInt( eShiftCorePredictionState.soulHandle ) )
		return
	#if SERVER
		player.Prediction_SetMovementScale( SHIFT_CORE_POWER_REGEN_SCALE, 1.0 )
	#elseif CLIENT
		player.Prediction_SetMovementScale( SHIFT_CORE_POWER_REGEN_SCALE, weapon.Prediction_GetFloat( eShiftCorePredictionState.previousPowerRegenRateScale ) )
	#endif
}

bool function ShiftCore_IsPredictedActive( entity player )
{
	if ( !IsValid( player ) || !player.IsTitan() )
		return false
	entity coreWeapon = player.GetOffhandWeapon( OFFHAND_EQUIPMENT )
	if ( !IsValid( coreWeapon ) || coreWeapon.GetWeaponOwner() != player || coreWeapon.GetWeaponClassName() != "mp_titancore_shift_core" )
		return false
	if ( !coreWeapon.Prediction_IsActive() )
		return false
	entity soul = player.GetTitanSoul()
	return IsValid( soul ) && !soul.IsEjecting()
		&& Prediction_GetEntityHandle( soul ) == coreWeapon.Prediction_GetInt( eShiftCorePredictionState.soulHandle )
}

#endif
