#if EXTENDED
global function OnWeaponActivate_titanability_basic_block_predicted
global function OnWeaponDeactivate_titanability_basic_block_predicted
global function BasicBlock_PredictionUpdate
global function BasicBlock_PredictionEnd
global function BasicBlock_PredictionReconcile

enum eBasicBlockPredictionState
{
	active
}

struct
{
	table<entity, int> glowMode
} blockPrediction

#if SERVER
struct
{
	table<entity, entity> blockingWeapon
} blockAuthority
#endif


void function OnWeaponActivate_titanability_basic_block_predicted( entity weapon )
{
	entity player = weapon.GetWeaponOwner()
	if ( !BasicBlock_PredictionOwnerValid( weapon, player ) )
		return

	bool wasActive = weapon.Prediction_IsActive() && weapon.Prediction_GetBool( eBasicBlockPredictionState.active )
	weapon.Prediction_SetBool( eBasicBlockPredictionState.active, true )
	weapon.Prediction_Start()
	#if SERVER
		blockAuthority.blockingWeapon[player] <- weapon
		player.e.blockActive = true
		if ( !wasActive )
			PlayerUsedOffhand( player, weapon )
		BasicBlock_UpdatePredictedGlow( weapon, player, true )
	#else
		if ( IsFirstTimePredicted() )
		{
			if ( !wasActive )
				PlayerUsedOffhand( player, weapon )
			BasicBlock_UpdatePredictedGlow( weapon, player, true )
		}
	#endif
}

void function OnWeaponDeactivate_titanability_basic_block_predicted( entity weapon )
{
	weapon.Prediction_Stop( 0 )
}

bool function BasicBlock_PredictionOwnerValid( entity weapon, entity player )
{
	if ( !IsValid( weapon ) || !IsValid( player ) || !IsAlive( player ) || !player.IsPlayer() || !player.IsTitan() )
		return false
	if ( weapon.GetWeaponOwner() != player )
		return false
	entity soul = player.GetTitanSoul()
	return IsValid( soul ) && !soul.IsEjecting()
}

void function BasicBlock_PredictionUpdate( entity weapon, entity player, float commandTime, float commandDuration, bool beforeMovement, bool firstExecution )
{
	if ( !IsValid( weapon ) || weapon.GetWeaponOwner() != player )
		return
	if ( !BasicBlock_PredictionOwnerValid( weapon, player ) || !weapon.Prediction_GetBool( eBasicBlockPredictionState.active ) )
	{
		weapon.Prediction_Stop( 1 )
		return
	}

	#if SERVER
		if ( !( player in blockAuthority.blockingWeapon ) )
			blockAuthority.blockingWeapon[player] <- weapon
		if ( blockAuthority.blockingWeapon[player] != weapon )
		{
			weapon.Prediction_Stop( 1 )
			return
		}
		player.e.blockActive = weapon.Prediction_GetBool( eBasicBlockPredictionState.active )
	#endif

	if ( !beforeMovement && firstExecution )
		BasicBlock_UpdatePredictedGlow( weapon, player, true )
}

void function BasicBlock_PredictionEnd( entity weapon, entity player, int reason )
{
	if ( !IsValid( weapon ) )
	{
		array<entity> removedWeapons
		foreach ( blockWeapon, mode in blockPrediction.glowMode )
		{
			if ( !IsValid( blockWeapon ) )
				removedWeapons.append( blockWeapon )
		}
		foreach ( blockWeapon in removedWeapons )
			delete blockPrediction.glowMode[blockWeapon]
	}
	if ( IsValid( weapon ) )
		weapon.Prediction_SetBool( eBasicBlockPredictionState.active, false )
	#if SERVER
		if ( player in blockAuthority.blockingWeapon && ( blockAuthority.blockingWeapon[player] == weapon || !IsValid( blockAuthority.blockingWeapon[player] ) ) )
		{
			if ( IsValid( player ) )
				player.e.blockActive = false
			delete blockAuthority.blockingWeapon[player]
		}
		BasicBlock_SetPredictedGlow( weapon, 0 )
	#else
		if ( reason >= 2 || IsFirstTimePredicted() )
			BasicBlock_SetPredictedGlow( weapon, 0 )
	#endif
}

void function BasicBlock_PredictionReconcile( entity weapon, entity player, bool active )
{
	bool blocking = active && BasicBlock_PredictionOwnerValid( weapon, player ) && weapon.Prediction_GetBool( eBasicBlockPredictionState.active )
	BasicBlock_UpdatePredictedGlow( weapon, player, blocking )
}

void function BasicBlock_UpdatePredictedGlow( entity weapon, entity player, bool active )
{
	bool coreGlow = false
	if ( active && BasicBlock_PredictionOwnerValid( weapon, player ) )
	{
		#if SERVER
			entity meleeWeapon = player.GetOffhandWeapon( OFFHAND_MELEE )
			coreGlow = IsValid( meleeWeapon ) && meleeWeapon.HasMod( "super_charged" )
		#else
			coreGlow = ShiftCore_IsPredictedActive( player )
		#endif
	}
	int mode = 0
	if ( coreGlow )
		mode = weapon.HasMod( "modelset_prime" ) ? 2 : 1
	BasicBlock_SetPredictedGlow( weapon, mode )
}

void function BasicBlock_SetPredictedGlow( entity weapon, int mode )
{
	int previousMode = weapon in blockPrediction.glowMode ? blockPrediction.glowMode[weapon] : 0
	if ( previousMode == mode )
		return
	if ( weapon in blockPrediction.glowMode )
		delete blockPrediction.glowMode[weapon]
	if ( !IsValid( weapon ) )
		return

	weapon.StopWeaponEffect( SWORD_GLOW_FP, SWORD_GLOW )
	weapon.StopWeaponEffect( SWORD_GLOW_PRIME_FP, SWORD_GLOW_PRIME )
	if ( mode == 0 )
		return
	asset firstFX = mode == 2 ? SWORD_GLOW_PRIME_FP : SWORD_GLOW_FP
	asset thirdFX = mode == 2 ? SWORD_GLOW_PRIME : SWORD_GLOW
	weapon.PlayWeaponEffectNoCull( firstFX, thirdFX, "sword_edge" )
	blockPrediction.glowMode[weapon] <- mode
}

#endif
