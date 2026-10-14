#if EXTENDED

global function ArcWavePrediction_Init
global function OnWeaponPrimaryAttack_titanweapon_arc_wave_predicted
#if CLIENT
global function ArcWave_PredictionReconcile
global function ServerCallback_ArcWaveStart
global function ServerCallback_ArcWaveStep
#endif

const int ARC_WAVE_STEP_EFFECT = 1
const int ARC_WAVE_STEP_FINISHED = 2
const int ARC_WAVE_STEP_CHARGED = 4
const float ARC_WAVE_FUSE_TIME = 99.0

struct ArcWavePath
{
	vector pos
	vector lastDownPos
	vector dir
	bool firstTrace = true
	bool running = true
	bool emitted = false
}

#if CLIENT
struct ArcWaveSegment
{
	vector pos
	vector downPos
	bool emitted = false
	int effect = -1
}

struct ArcWaveShot
{
	entity weapon
	entity owner
	entity carrier
	int command
	int maxCount
	float step
	float interval
	float nextTime
	float deadline
	vector angles
	bool charged
	bool predicted = false
	bool revoked = false
	bool finished = false
	int nextIndex = 0
	int confirmedIndex = -1
	ArcWavePath path
	array<ArcWaveSegment> segments
}

struct
{
	table<int, ArcWaveShot> shots
} file
#endif

void function ArcWavePrediction_Init()
{
	AddCallback_OnRegisteringCustomNetworkVars( ArcWave_RegisterRemoteFunctions )
}

void function ArcWave_RegisterRemoteFunctions()
{
	Remote_RegisterFunction( "ServerCallback_ArcWaveStart", true )
	Remote_RegisterFunction( "ServerCallback_ArcWaveStep", true )
}

// love to see it
float function ArcWave_GetStepInterval()
{
	float fps = GetConVarFloat( "script_server_fps" )
	return max( fps > 0.0 ? 1.0 / fps : 0.01023, IntervalPerTick() )
}

var function OnWeaponPrimaryAttack_titanweapon_arc_wave_predicted( entity weapon, WeaponPrimaryAttackParams attackParams )
{
	entity owner = weapon.GetWeaponOwner()
	if ( owner.IsPhaseShifted() )
		return 0

	bool shouldPredict = weapon.ShouldPredictProjectiles()
	#if CLIENT
		if ( !shouldPredict )
			return 1
	#endif

	int command = Prediction_GetCommandNumber()
	weapon.Prediction_SetInt( 0, command )
	entity projectile = weapon.FireWeaponGrenade( attackParams.pos, attackParams.dir, <0,0,0>, ARC_WAVE_FUSE_TIME, damageTypes.projectileImpact, damageTypes.explosive, shouldPredict, true, true )
	if ( IsValid( projectile ) )
	{
		bool charged = PlayerHasPassive( owner, ePassives.PAS_SHIFT_CORE )
		PlayerUsedOffhand( owner, weapon )
		#if SERVER
			projectile.proj.isChargedShot = charged
			thread ArcWave_ServerWave( projectile, attackParams, command )
		#elseif CLIENT
			if ( IsFirstTimePredicted() && !( command in file.shots ) )
			{
				projectile.SetVelocity( <0,0,0> )
				projectile.StopPhysics()
				ArcWaveShot shot
				shot.weapon = weapon
				shot.owner = owner
				shot.carrier = projectile
				shot.command = command
				shot.charged = charged
				shot.predicted = true
				shot.interval = ArcWave_GetStepInterval()
				string prefix = charged ? "charge_" : ""
				shot.maxCount = expect int( weapon.GetWeaponInfoFileKeyField( prefix + "wave_max_count" ) )
				shot.step = expect float( weapon.GetWeaponInfoFileKeyField( prefix + "wave_step_dist" ) )
				shot.path.pos = attackParams.pos
				shot.path.dir = Normalize( <attackParams.dir.x, attackParams.dir.y, 0.0> )
				shot.angles = VectorToAngles( shot.path.dir )
				shot.nextTime = Time()
				shot.deadline = Time() + ARC_WAVE_FUSE_TIME
				file.shots[command] <- shot
				thread ArcWave_ClientWave( shot )
			}
		#endif
	}
	return weapon.GetWeaponSettingInt( eWeaponVar.ammo_min_to_fire )
}

void function ArcWave_Advance( ArcWavePath path, float step, entity owner, entity projectile )
{
	path.emitted = false
	vector newPos = path.pos + path.dir * step
	vector traceStart = path.pos
	vector traceEndUnder = newPos
	vector traceEndOver = newPos
	if ( !path.firstTrace )
	{
		traceStart = path.lastDownPos + <0,0,80>
		traceEndUnder = <newPos.x, newPos.y, traceStart.z - 40.0>
		traceEndOver = <newPos.x, newPos.y, traceStart.z + step * 0.57735056839>
	}
	path.firstTrace = false

	#if SERVER
		VortexBulletHit ornull vortexHit = VortexBulletHitCheck( owner, traceStart, traceEndOver )
		if ( vortexHit )
		{
			expect VortexBulletHit( vortexHit )
			entity vortexWeapon = vortexHit.vortex.GetOwnerWeapon()
			if ( vortexWeapon && vortexWeapon.GetWeaponClassName() == "mp_titanweapon_vortex_shield" )
				VortexDrainedByImpact( vortexWeapon, null, projectile, null )
			else if ( IsVortexSphere( vortexHit.vortex ) )
				VortexSphereDrainHealthForDamage( vortexHit.vortex, projectile.GetProjectileWeaponSettingInt( eWeaponVar.damage_near_value_titanarmor ) )
			return
		}
	#endif

	array<entity> ignoreArray = [owner]
	TraceResults forwardTrace = TraceLine( traceStart, traceEndUnder, ignoreArray, TRACE_MASK_SHOT, TRACE_COLLISION_GROUP_BLOCK_WEAPONS )
	if ( forwardTrace.fraction == 1.0 )
	{
		TraceResults downTrace = TraceLine( forwardTrace.endPos, forwardTrace.endPos + <0,0,-1000>, ignoreArray, TRACE_MASK_SHOT, TRACE_COLLISION_GROUP_BLOCK_WEAPONS )
		if ( downTrace.fraction == 1.0 )
		{
			path.running = false
			return
		}
		path.lastDownPos = downTrace.endPos
		path.pos = forwardTrace.endPos
		path.emitted = true
		return
	}

	if ( IsValid( forwardTrace.hitEnt ) && StatusEffect_Get( forwardTrace.hitEnt, eStatusEffect.pass_through_amps_weapon ) > 0 && !CheckPassThroughDir( forwardTrace.hitEnt, forwardTrace.surfaceNormal, forwardTrace.endPos ) )
	{
		path.running = false
		return
	}

	TraceResults upwardTrace = TraceLine( traceStart, traceEndOver, ignoreArray, TRACE_MASK_SHOT, TRACE_COLLISION_GROUP_BLOCK_WEAPONS )
	if ( upwardTrace.fraction < 1.0 )
	{
		if ( IsValid( upwardTrace.hitEnt ) && ( upwardTrace.hitEnt.IsWorld() || upwardTrace.hitEnt.IsPlayer() || upwardTrace.hitEnt.IsNPC() ) )
			path.running = false
		return
	}

	TraceResults downTrace = TraceLine( upwardTrace.endPos, upwardTrace.endPos + <0,0,-1000>, ignoreArray, TRACE_MASK_SHOT, TRACE_COLLISION_GROUP_BLOCK_WEAPONS )
	if ( downTrace.fraction == 1.0 )
	{
		path.running = false
		return
	}
	path.lastDownPos = downTrace.endPos
	path.pos = forwardTrace.endPos
	path.emitted = true
}

#if SERVER
void function ArcWave_ServerWave( entity projectile, WeaponPrimaryAttackParams attackParams, int command )
{
	projectile.EndSignal( "OnDestroy" )
	entity owner = projectile.GetOwner()
	owner.EndSignal( "OnDestroy" )
	projectile.SetAbsOrigin( projectile.GetOrigin() )
	projectile.SetAbsAngles( projectile.GetAngles() )
	projectile.SetVelocity( <0,0,0> )
	projectile.StopPhysics()
	projectile.SetTakeDamageType( DAMAGE_NO )
	projectile.Hide()
	projectile.NotSolid()
	projectile.e.onlyDamageEntitiesOnce = true
	EmitSoundOnEntity( projectile, "arcwave_tail_3p" )

	bool charged = projectile.proj.isChargedShot
	string prefix = charged ? "charge_" : ""
	int maxCount = expect int( projectile.ProjectileGetWeaponInfoFileKeyField( prefix + "wave_max_count" ) )
	float step = expect float( projectile.ProjectileGetWeaponInfoFileKeyField( prefix + "wave_step_dist" ) )
	ArcWavePath path
	path.pos = attackParams.pos
	path.dir = Normalize( <attackParams.dir.x, attackParams.dir.y, 0.0> )
	vector angles = VectorToAngles( path.dir )
	Remote_CallFunction_Replay( owner, "ServerCallback_ArcWaveStart", command, angles.y, ArcWave_GetStepInterval() )
	int index = 0
	for ( ; index < maxCount; index++ )
	{
		ArcWave_Advance( path, step, owner, projectile )
		if ( !path.running )
			break
		if ( path.emitted )
		{
			projectile.SetOrigin( path.lastDownPos )
			asset effect = charged ? $"P_arcwave_exp_charged" : $"P_arcwave_exp"
			PlayFXForEveryoneExceptPlayer( effect, owner, path.lastDownPos, angles )
			float damageScalar = charged ? 1.5 : 1.0
			int pilotDamage = int( float( projectile.GetProjectileWeaponSettingInt( eWeaponVar.damage_near_value ) ) * damageScalar )
			int titanDamage = int( float( projectile.GetProjectileWeaponSettingInt( eWeaponVar.damage_near_value_titanarmor ) ) * damageScalar )
			RadiusDamage( path.lastDownPos, owner, projectile, pilotDamage, titanDamage, 112, 112,
				SF_ENVEXPLOSION_NO_DAMAGEOWNER | SF_ENVEXPLOSION_MASK_BRUSHONLY | SF_ENVEXPLOSION_NO_NPC_SOUND_EVENT,
				0, 0, DF_ELECTRICAL | DF_STOPS_TITAN_REGEN, eDamageSourceId.mp_titanweapon_arc_wave )
		}
		ArcWave_SendStep( owner, projectile, command, index, path, charged, false )
		WaitFrame()
	}
	ArcWave_SendStep( owner, projectile, command, index, path, charged, true )
	StopSoundOnEntity( projectile, "arcwave_tail_3p" )
	projectile.Destroy()
}

void function ArcWave_SendStep( entity owner, entity projectile, int command, int index, ArcWavePath path, bool charged, bool finished )
{
	int flags = charged ? ARC_WAVE_STEP_CHARGED : 0
	if ( !finished && path.emitted )
		flags = flags | ARC_WAVE_STEP_EFFECT
	if ( finished )
		flags = flags | ARC_WAVE_STEP_FINISHED
	Remote_CallFunction_Replay( owner, "ServerCallback_ArcWaveStep", command, ( index << 3 ) | flags, projectile.GetEncodedEHandle(),
		path.pos.x, path.pos.y, path.pos.z, path.lastDownPos.x, path.lastDownPos.y, path.lastDownPos.z, Time() )
}
#endif

#if CLIENT
void function ArcWave_PredictionReconcile( entity weapon, entity owner, bool active )
{
	int command = weapon.Prediction_GetInt( 0 )
	foreach ( ArcWaveShot shot in file.shots )
	{
		if ( shot.weapon == weapon && shot.command > command && shot.confirmedIndex < 0 )
		{
			shot.revoked = true
			ArcWave_RetireSegments( shot, 0 )
		}
	}
}

void function ArcWave_ClientWave( ArcWaveShot shot )
{
	shot.owner.EndSignal( "OnDestroy" )
	OnThreadEnd( function() : ( shot )
	{
		if ( shot.command in file.shots && file.shots[shot.command] == shot )
			delete file.shots[shot.command]
	} )
	while ( !shot.revoked && !shot.finished && Time() < shot.deadline )
	{
		while ( shot.path.running && shot.nextIndex < shot.maxCount && Time() >= shot.nextTime )
		{
			ArcWave_Advance( shot.path, shot.step, shot.owner, shot.carrier )
			ArcWave_PresentSegment( shot, shot.nextIndex, shot.path.pos, shot.path.lastDownPos, shot.path.running && shot.path.emitted )
			shot.nextIndex++
			shot.nextTime += shot.interval
		}
		if ( shot.predicted && IsValid( shot.carrier ) && shot.carrier.GetEntIndex() < 0 && shot.segments.len() > 0 && shot.segments[shot.segments.len() - 1].emitted )
		{
			shot.carrier.SetVelocity( <0,0,0> )
			shot.carrier.StopPhysics()
			shot.carrier.SetOrigin( shot.path.lastDownPos )
		}
		WaitFrame()
	}
}

void function ArcWave_RetireSegments( ArcWaveShot shot, int first )
{
	for ( int i = first; i < shot.segments.len(); i++ )
	{
		if ( EffectDoesExist( shot.segments[i].effect ) )
			EffectStop( shot.segments[i].effect, true, true )
		shot.segments[i].effect = -1
	}
}

void function ArcWave_PresentSegment( ArcWaveShot shot, int index, vector pos, vector downPos, bool emitted )
{
	while ( shot.segments.len() <= index )
	{
		ArcWaveSegment segment
		shot.segments.append( segment )
	}
	ArcWaveSegment segment = shot.segments[index]
	bool changed = segment.emitted != emitted || DistanceSqr( segment.downPos, downPos ) > 1.0
	if ( changed && EffectDoesExist( segment.effect ) )
	{
		EffectStop( segment.effect, true, true )
		segment.effect = -1
	}
	if ( emitted && ( changed || !segment.emitted ) )
	{
		asset effect = shot.charged ? $"P_arcwave_exp_charged" : $"P_arcwave_exp"
		segment.effect = StartParticleEffectInWorldWithHandle( GetParticleSystemIndex( effect ), downPos, shot.angles )
	}
	segment.pos = pos
	segment.downPos = downPos
	segment.emitted = emitted
}

void function ServerCallback_ArcWaveStart( int command, float yaw, float interval )
{
	if ( !( command in file.shots ) )
	{
		ArcWaveShot shot
		shot.command = command
		shot.owner = GetLocalClientPlayer()
		shot.deadline = Time() + ARC_WAVE_FUSE_TIME
		file.shots[command] <- shot
		thread ArcWave_ClientWave( shot )
	}
	ArcWaveShot shot = file.shots[command]
	shot.angles = <0,yaw,0>
	shot.interval = interval
}

void function ServerCallback_ArcWaveStep( int command, int packedIndexFlags, int carrierHandle,
	float px, float py, float pz, float dx, float dy, float dz, float serverTime )
{
	int index = packedIndexFlags >> 3
	int flags = packedIndexFlags & 7
	vector pos = <px,py,pz>
	vector downPos = <dx,dy,dz>
	bool finished = ( flags & ARC_WAVE_STEP_FINISHED ) != 0
	bool emitted = ( flags & ARC_WAVE_STEP_EFFECT ) != 0
	bool charged = ( flags & ARC_WAVE_STEP_CHARGED ) != 0
	if ( !( command in file.shots ) )
		return
	ArcWaveShot shot = file.shots[command]
	if ( index <= shot.confirmedIndex || shot.revoked )
		return
	shot.confirmedIndex = index
	entity carrier = GetEntityFromEncodedEHandle( carrierHandle )
	if ( IsValid( carrier ) )
		shot.carrier = carrier
	bool changed = index >= shot.segments.len()
	if ( !changed )
		changed = shot.segments[index].emitted != emitted
			|| DistanceSqr( shot.segments[index].pos, pos ) > 1.0
			|| DistanceSqr( shot.segments[index].downPos, downPos ) > 1.0
	if ( shot.charged != charged )
	{
		ArcWave_RetireSegments( shot, 0 )
		foreach ( ArcWaveSegment segment in shot.segments )
			segment.emitted = false
		shot.charged = charged
		changed = true
	}
	if ( finished )
	{
		ArcWave_RetireSegments( shot, index )
		shot.finished = true
		return
	}
	ArcWave_PresentSegment( shot, index, pos, downPos, emitted )
	if ( changed )
	{
		ArcWave_RetireSegments( shot, index + 1 )
		shot.segments.resize( index + 1 )
		shot.path.pos = pos
		shot.path.lastDownPos = downPos
		shot.path.firstTrace = false
		shot.path.running = true
		shot.nextIndex = index + 1
	}
	shot.nextTime = serverTime + ( shot.nextIndex - index ) * shot.interval
}
#endif
#endif
