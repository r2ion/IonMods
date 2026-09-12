untyped
global function GamemodeAITdm_Init

// these are now default settings
const int SQUADS_PER_TEAM = 4

const int REAPERS_PER_TEAM = 2

const int LEVEL_SPECTRES = 125
const int LEVEL_STALKERS = 380
const int LEVEL_REAPERS = 500
const float REAPER_RESPAWN_DEBOUNCE = 0.0

const float AITDM_ASSAULT_STALL_TIME = 10.0
const float AITDM_ASSAULT_IDLE_TIME = 20.0
const float AITDM_ASSAULT_COMBAT_GRACE = 6.0
const float AITDM_ASSAULT_RETRY_TIME = 3.0

// add settings
global function AITdm_SetSquadsPerTeam
global function AITdm_SetReapersPerTeam
global function AITdm_SetLevelSpectres
global function AITdm_SetLevelStalkers
global function AITdm_SetLevelReapers

struct AITdmAssaultOrder
{
	entity npc
	entity bossPlayer
	int team
	string squadName
	vector goal
	vector origin
	vector progressOrigin
	float lastProgressTime
	float lastEngagedTime
	int lastHealth
	int goalRevision = -1
	float retryTime = 0.0
	float arrivalTolerance = 0.0
	bool arrivalOverridden = false
	bool assigned = false
	bool arrived = false
	bool failed = false
	bool paused = false
	bool released = false
}

struct
{
	// Due to team based escalation everything is an array
	array<int> levels = [] // Initilazed in `Spawner_Threaded`
	array<array<string> > podEntities = [ [ "npc_soldier" ], [ "npc_soldier" ] ]
	array<bool> reapers = [ false, false ]
	table<int, float> reaperRespawnTimes = {}
	table<int, int> nextFrontlineSquad = { [TEAM_IMC] = 0, [TEAM_MILITIA] = 0 }
	array<AITdmAssaultOrder> assaultOrders

	// default settings
	int squadsPerTeam = SQUADS_PER_TEAM
	int reapersPerTeam = REAPERS_PER_TEAM
	int levelSpectres = LEVEL_SPECTRES
	int levelStalkers = LEVEL_STALKERS
	int levelReapers = LEVEL_REAPERS
} file

void function GamemodeAITdm_Init()
{
	RegisterSignal( "AITdm_StopAssault" )

	SetSpawnpointGamemodeOverride( TEAM_DEATHMATCH ) // use TDM spawns as vanilla game has no spawns explicitly defined for aitdm

	AddCallback_GameStateEnter( eGameState.Prematch, OnPrematchStart )
	AddCallback_GameStateEnter( eGameState.Playing, OnPlaying )

	AddCallback_OnNPCKilled( HandleScoreEvent )
	AddCallback_OnPlayerKilled( HandleScoreEvent )

	AddCallback_OnClientConnected( OnPlayerConnected )
	AddCallback_EntitiesDidLoad( LoadEntities )

	AddCallback_NPCLeeched( OnSpectreLeeched )
	AddCallback_OnNPCKilled( OnReaperKilled )

	if ( GetCurrentPlaylistVarInt( "aitdm_archer_grunts", 0 ) == 0 )
	{
		AiGameModes_SetNPCWeapons( "npc_soldier", [ "mp_weapon_rspn101", "mp_weapon_dmr", "mp_weapon_r97", "mp_weapon_lmg" ] )
		AiGameModes_SetNPCWeapons( "npc_spectre", [ "mp_weapon_hemlok_smg", "mp_weapon_doubletake", "mp_weapon_mastiff" ] )
		AiGameModes_SetNPCWeapons( "npc_stalker", [ "mp_weapon_hemlok_smg", "mp_weapon_lstar", "mp_weapon_mastiff" ] )
	}
	else
	{
		AiGameModes_SetNPCWeapons( "npc_soldier", [ "mp_weapon_rocket_launcher" ] )
		AiGameModes_SetNPCWeapons( "npc_spectre", [ "mp_weapon_rocket_launcher" ] )
		AiGameModes_SetNPCWeapons( "npc_stalker", [ "mp_weapon_rocket_launcher" ] )
	}

	file.levelSpectres = GetCurrentPlaylistVarInt( "aitdm_level_spectres", LEVEL_SPECTRES )
	file.levelStalkers = GetCurrentPlaylistVarInt( "aitdm_level_stalkers", LEVEL_STALKERS )
	file.levelReapers = GetCurrentPlaylistVarInt( "aitdm_level_reapers", LEVEL_REAPERS )

	ScoreEvent_SetupEarnMeterValuesForMixedModes()
	SetupGenericTDMChallenge()
}

void function LoadEntities()
{
	ValidateAndFinalizePendingStationaryPositions()
}

// add settings
void function AITdm_SetSquadsPerTeam( int squads )
{
	file.squadsPerTeam = squads
}

void function AITdm_SetReapersPerTeam( int reapers )
{
	file.reapersPerTeam = reapers
}

void function AITdm_SetLevelSpectres( int level )
{
	file.levelSpectres = level
}

void function AITdm_SetLevelStalkers( int level )
{
	file.levelStalkers = level
}

void function AITdm_SetLevelReapers( int level )
{
	file.levelReapers = level
}
//

// Starts skyshow, this also requiers AINs but doesn't crash if they're missing
void function OnPrematchStart()
{
	thread StratonHornetDogfightsIntense()
}

void function OnPlaying()
{
	// don't run spawning code if ains and nms aren't up to date
	if ( GetAINScriptVersion() == AIN_REV && GetNodeCount() != 0 )
	{
		thread SpawnIntroBatch_Threaded( TEAM_MILITIA )
		thread SpawnIntroBatch_Threaded( TEAM_IMC )
	}
}

// Sets up mode specific hud on client
void function OnPlayerConnected( entity player )
{
	Remote_CallFunction_NonReplay( player, "ServerCallback_AITDM_OnPlayerConnected" )
}

// Used to handle both player and ai events
void function HandleScoreEvent( entity victim, entity attacker, var damageInfo )
{
	// Basic checks
	if ( victim == attacker || !( attacker.IsPlayer() || attacker.IsTitan() ) || GetGameState() != eGameState.Playing )
		return
	// Hacked spectre filter
	if ( victim.GetOwner() == attacker )
		return
	// NPC titans without an owner player will not count towards any team's score
	if ( attacker.IsNPC() && attacker.IsTitan() && !IsValid( GetPetTitanOwner( attacker ) ) )
		return

	// Split score so we can check if we are over the score max
	// without showing the wrong value on client
	int teamScore
	int playerScore
	string eventName

	// Handle AI, marvins aren't setup so we check for them to prevent crash
	if ( victim.IsNPC() && victim.GetClassName() != "npc_marvin" )
	{
		switch ( victim.GetClassName() )
		{
			case "npc_soldier":
			case "npc_spectre":
			case "npc_stalker":
				playerScore = 1
				break

			case "npc_super_spectre":
				playerScore = 3
				break

			default:
				playerScore = 0
				break
		}

		// Titan kills get handled bellow this
		if ( eventName != "KillNPCTitan" && eventName != "" )
			playerScore = ScoreEvent_GetPointValue( GetScoreEvent( eventName ) )
	}

	if ( victim.IsPlayer() )
		playerScore = 5

	// Player ejecting triggers this without the extra check
	if ( victim.IsTitan() && victim.GetBossPlayer() != attacker )
		playerScore += 10

	teamScore = playerScore

	// Check score so we dont go over max
	if ( GameRules_GetTeamScore( attacker.GetTeam() ) + teamScore > GetScoreLimit_FromPlaylist() )
		teamScore = GetScoreLimit_FromPlaylist() - GameRules_GetTeamScore( attacker.GetTeam() )

	// Add score + update network int to trigger the "Score +n" popup
	AddTeamScore( attacker.GetTeam(), teamScore )
	attacker.AddToPlayerGameStat( PGS_ASSAULT_SCORE, playerScore )
	int assaultScore = attacker.GetPlayerGameStat( PGS_ASSAULT_SCORE )
	int assaultScore256 = assaultScore / 256

	attacker.SetPlayerNetInt( "AT_bonusPoints", assaultScore - assaultScore256 * 256 )
	attacker.SetPlayerNetInt( "AT_bonusPoints256", assaultScore256 )
}

// When attrition starts both teams spawn ai on preset nodes, after that
// Spawner_Threaded is used to keep the match populated
void function SpawnIntroBatch_Threaded( int team )
{
	array<entity> dropPodNodes = GetEntArrayByClass_Expensive( "info_spawnpoint_droppod_start" )
	array<entity> dropShipNodes = GetValidIntroDropShipSpawn( dropPodNodes )

	array<entity> podNodes

	array<entity> shipNodes

	// mp_rise has weird droppod_start nodes, this gets around it
	// To be more specific the teams aren't setup and some nodes are scattered in narnia
	if ( GetMapName() == "mp_rise" )
	{
		entity spawnPoint

		// Get a spawnpoint for team
		foreach ( point in GetEntArrayByClass_Expensive( "info_spawnpoint_dropship_start" ) )
		{
			if ( GameModeRemove( point ) )
				continue

			if ( point.GetTeam() == team )
			{
				spawnPoint = point
				break
			}
		}

		// Get nodes close enough to team spawnpoint
		foreach ( node in dropPodNodes )
		{
			if ( node.HasKey( "teamnum" ) && Distance2D( node.GetOrigin(), spawnPoint.GetOrigin() ) < 2000 )
				podNodes.append( node )
		}
	}
	else
	{
		// Sort per team
		foreach ( node in dropPodNodes )
		{
			if ( node.GetTeam() == team )
				podNodes.append( node )
		}
	}

	shipNodes = GetValidIntroDropShipSpawn( podNodes )

	// Spawn logic
	int startIndex = 0
	bool first = true
	entity node

	int pods = RandomInt( podNodes.len() + 1 )

	int ships = shipNodes.len()

	for ( int i = 0; i < file.squadsPerTeam; i++ )
	{
		if ( pods != 0 || ships == 0 )
		{
			int index = i

			if ( index > podNodes.len() - 1 )
				index = RandomInt( podNodes.len() )

			node = podNodes[ index ]
			thread AiGameModes_SpawnDropPod( node.GetOrigin(), node.GetAngles(), team, "npc_soldier", SquadHandler )

			pods--
		}
		else
		{
			if ( startIndex == 0 )
				startIndex = i // save where we started

			node = shipNodes[ i - startIndex ]
			thread AiGameModes_SpawnDropShip( node.GetOrigin(), node.GetAngles(), team, 4, SquadHandler )

			ships--
		}

		// Vanilla has a delay after first spawn
		if ( first )
			wait 2

		first = false
	}

	wait 15

	thread Spawner_Threaded( team )
}

// Populates the match
void function Spawner_Threaded( int team )
{
	svGlobal.levelEnt.EndSignal( "GameStateChanged" )

	// used to index into escalation arrays
	int index = team == TEAM_MILITIA ? 0 : 1
	float frontlineTickNext = Time()

	file.levels = [ file.levelSpectres, file.levelSpectres ] // due we added settings, should init levels here!

	while ( true )
	{
		// keep frontline refreshed off the main spawn loop
		#if SERVER
			if ( Flag( "FrontlineInitiated" ) && Time() >= frontlineTickNext )
			{
				GetFrontline( TEAM_IMC )
				frontlineTickNext = Time() + 1.0 // GetFrontline itself clamps to 1Hz; keep this aligned
			}
		#endif

		Escalate( team )

		// TODO: this should possibly not count scripted npc spawns, probably only the ones spawned by this script
		array<entity> npcs = GetNPCArrayOfTeam( team )
		int count = npcs.len()
		int reaperCount = GetNPCArrayEx( "npc_super_spectre", team, -1, < 0, 0, 0 >, -1 ).len()

		// REAPERS
		if ( file.reapers[ index ] )
		{
			array<entity> points = SpawnPoints_GetDropPod()
			array<entity> validPoints

			foreach ( entity point in points )
			{
				if ( IsSpawnpointValid( point, team ) == false )
					continue

				validPoints.append( point )
			}

			if ( validPoints.len() == 0 )
			{
				printt( "WARNING: No valid reaper spawn points found, defaulting to all drop pod points" )
				validPoints = points
			}

			// ensure debounce entry exists for this team
			if ( !( team in file.reaperRespawnTimes ) )
				file.reaperRespawnTimes[ team ] <- 0.0

			if ( reaperCount < file.reapersPerTeam && Time() > file.reaperRespawnTimes[ team ] )
			{
				entity node = validPoints[ GetSpawnPointIndex( validPoints, team ) ]
				waitthread AiGameModes_SpawnReaper( node.GetOrigin(), node.GetAngles(), team, "npc_super_spectre_aitdm", ReaperHandler )
			}
		}

		// NORMAL SPAWNS
		if ( count < file.squadsPerTeam * 4 - 2 )
		{
			string ent = file.podEntities[ index ][ RandomInt( file.podEntities[ index ].len() ) ]

			array<entity> points = GetZiplineDropshipSpawns()
			array<entity> validPoints

			foreach ( entity point in points )
			{
				if ( IsSpawnpointValid( point, team ) == false )
					continue

				validPoints.append( point )
			}

			if ( validPoints.len() == 0 )
			{
				printt( "WARNING: No valid dropship spawn points found, defaulting to all zipline dropship points" )
				validPoints = points
			}

			if ( AllowingAIDropships() == false )
				validPoints = []

			// Prefer dropship when spawning grunts
			if ( ent == "npc_soldier" && validPoints.len() != 0 )
			{
				if ( RandomInt( validPoints.len() ) )
				{
					entity node = validPoints[ GetSpawnPointIndex( validPoints, team ) ]
					waitthread Aitdm_SpawnDropShip( node, team )
					continue
				}
			}

			points = SpawnPoints_GetDropPod()
			validPoints = []

			foreach ( entity point in points )
			{
				if ( IsSpawnpointValid( point, team ) == false )
					continue

				validPoints.append( point )
			}

			if ( validPoints.len() == 0 )
				validPoints = points

			entity node = validPoints[ GetSpawnPointIndex( validPoints, team ) ]
			waitthread AiGameModes_SpawnDropPod( node.GetOrigin(), node.GetAngles(), team, ent, SquadHandler )
		}

		WaitFrame()
	}
}
void function Aitdm_SpawnDropShip( entity node, int team )
{
	thread AiGameModes_SpawnDropShip( node.GetOrigin(), node.GetAngles(), team, 4, SquadHandler )
	wait 20
}

// Based on points tries to balance match
void function Escalate( int team )
{
	int score = GameRules_GetTeamScore( team )
	int index = team == TEAM_MILITIA ? 1 : 0
	// This does the "Enemy x incoming" text
	string defcon = team == TEAM_MILITIA ? "IMCdefcon" : "MILdefcon"

	// Return if the team is under score threshold to escalate
	if ( score < file.levels[ index ] || file.reapers[ index ] )
		return

	// Based on score escalate a team
	switch ( file.levels[ index ] )
	{
		case file.levelSpectres:
			file.levels[ index ] = file.levelStalkers
			file.podEntities[ index ].append( "npc_spectre" )
			SetGlobalNetInt( defcon, 2 )
			return

		case file.levelStalkers:
			file.levels[ index ] = file.levelReapers
			file.podEntities[ index ].append( "npc_stalker" )
			SetGlobalNetInt( defcon, 3 )
			return

		case file.levelReapers:
			file.reapers[ index ] = true
			SetGlobalNetInt( defcon, 4 )
			return
	}

	unreachable // hopefully
}

// Decides where to spawn ai
// Each team has their "zone" where they and their ai spawns
// These zones should swap based on which team is dominating where
int function GetSpawnPointIndex( array<entity> points, int team )
{
	#if SERVER
		if ( Flag( "FrontlineInitiated" ) )
		{
			var frontline = GetCurrentFrontline()
			if ( frontline != null )
			{
				vector combatDir = Vector( GetTeamCombatDir( frontline, team ).x, GetTeamCombatDir( frontline, team ).y, GetTeamCombatDir( frontline, team ).z )
				vector edgeOrigin = Vector( frontline.frontlineCenter.x, frontline.frontlineCenter.y, frontline.frontlineCenter.z )

				int bestIndex = -1
				float bestRating = -99999.0
				for ( int i = 0; i < points.len(); i++ )
				{
					entity point = points[ i ]
					vector org = point.GetOrigin()
					bool infront = IsPointInFrontofLine( org, edgeOrigin, combatDir )
					float rating
					if ( !infront )
					{
						float distSqr = Distance2DSqr( org, edgeOrigin )
						rating = GraphCapped( distSqr, FRONTLINE_MIN_DIST_SQR, FRONTLINE_MAX_DIST_SQR, 1.0, 0.0 ) * 2.0
					}
					else
					{
						rating = -100.0
					}

					if ( rating > bestRating )
					{
						bestRating = rating
						bestIndex = i
					}
				}

				if ( bestIndex != -1 )
					return bestIndex
			}
		}
	#endif

	entity zone = DecideSpawnZone_Generic( points, team )

	if ( IsValid( zone ) )
	{
		// 20 Tries to get a random point close to the zone
		for ( int i = 0; i < 20; i++ )
		{
			int index = RandomInt( points.len() )

			if ( Distance2D( points[ index ].GetOrigin(), zone.GetOrigin() ) < 6000 )
				return index
		}
	}

	return RandomInt( points.len() )
}

void function SquadHandler( array<entity> guys )
{
	svGlobal.levelEnt.EndSignal( "GameStateChanged" )
	ArrayRemoveDead( guys )
	if ( guys.len() == 0 )
		return

	int team = guys[ 0 ].GetTeam()
	string squadName = expect string( guys[ 0 ].kv.squadname )
	bool isSpectreSquad = guys[ 0 ].GetClassName() == "npc_spectre"
	int squadIndex = file.nextFrontlineSquad[ team ]
	file.nextFrontlineSquad[ team ] = ( squadIndex + 1 ) % 3

	array<AITdmAssaultOrder> orders
	array<entity> players = GetPlayerArrayOfEnemies( team )
	foreach ( entity guy in guys )
	{
		foreach ( player in players )
			guy.Minimap_AlwaysShow( 0, player )

		if ( IsValid( guy.GetBossPlayer() ) || IsValid( guy.GetFollowTarget() ) )
			continue

		AITdmAssaultOrder order
		order.npc = guy
		order.bossPlayer = guy.GetBossPlayer()
		order.team = team
		order.squadName = squadName
		order.origin = guy.GetOrigin()
		order.progressOrigin = order.origin
		order.lastProgressTime = Time()
		order.lastEngagedTime = Time() - AITDM_ASSAULT_COMBAT_GRACE
		order.lastHealth = guy.GetHealth()
		orders.append( order )
		file.assaultOrders.append( order )
		thread AITdm_WatchAssault( order )
	}

	OnThreadEnd(
		function() : ( orders )
		{
			foreach ( order in orders )
				AITdm_ReleaseAssaultOrder( order )
		}
	)

	var lastFrontline = null
	entity lastGoalEnt = null
	vector lastAnchor = < 0, 0, 0 >
	float nextEnemyGoalTime = 0.0
	float nextRepositionTime = 0.0
	int goalRevision = 0
	array<vector> positions

	while ( true )
	{
		for ( int i = orders.len() - 1; i >= 0; i-- )
		{
			if ( AITdm_OwnsAssaultOrder( orders[ i ] ) )
				continue

			AITdm_ReleaseAssaultOrder( orders[ i ] )
			orders.remove( i )
		}
		if ( orders.len() == 0 )
			return

		float now = Time()
		bool squadIdle = true
		foreach ( order in orders )
		{
			AITdm_UpdateAssaultActivity( order, now )
			if ( order.paused || !order.arrived || now - order.lastEngagedTime < AITDM_ASSAULT_IDLE_TIME ||
				now - order.lastProgressTime < AITDM_ASSAULT_IDLE_TIME )
				squadIdle = false
		}

		var frontline = GetCurrentFrontline()
		entity goalEnt = null
		vector anchor = lastAnchor
		bool changed = false
		if ( frontline != null )
		{
			goalEnt = expect entity( GetFrontlineGoal( squadIndex, team, isSpectreSquad ) )
			anchor = goalEnt.GetOrigin()
			changed = frontline != lastFrontline || goalEnt != lastGoalEnt || anchor != lastAnchor
		}
		else if ( now >= nextEnemyGoalTime )
		{
			array<entity> enemies = GetNPCArrayOfEnemies( team )
			ArrayRemoveDead( enemies )
			if ( enemies.len() == 0 )
			{
				wait 1.0
				continue
			}
			anchor = enemies[ RandomInt( enemies.len() ) ].GetOrigin()
			nextEnemyGoalTime = now + RandomFloatRange( 5.0, 15.0 )
			changed = true
		}

		if ( changed )
		{
			lastFrontline = frontline
			lastGoalEnt = goalEnt
			lastAnchor = anchor
			positions.clear()
			goalRevision++
		}
		if ( positions.len() == 0 )
			positions = AITdm_GetAssaultPositions( anchor, orders[ 0 ].npc )

		float radius = STANDARDGOALRADIUS
		if ( IsValid( goalEnt ) && goalEnt.HasKey( "script_goal_radius" ) )
			radius = float( goalEnt.kv.script_goal_radius )

		bool reposition = squadIdle && frontline != null && !changed && now >= nextRepositionTime
		vector preferred = anchor
		if ( reposition )
		{
			preferred += expect vector( GetTeamCombatDir( frontline, team ) ) * 384.0
			nextRepositionTime = now + AITDM_ASSAULT_IDLE_TIME
		}

		foreach ( order in orders )
		{
			if ( order.paused || now - order.lastEngagedTime < AITDM_ASSAULT_COMBAT_GRACE || now < order.retryTime )
				continue

			bool refresh = !order.assigned || order.goalRevision != goalRevision
			bool stalled = order.assigned && !order.arrived && now - order.lastProgressTime >= AITDM_ASSAULT_STALL_TIME
			if ( !refresh && !order.failed && !stalled && !reposition )
				continue

			bool improve = reposition && !refresh && !order.failed && !stalled
			bool avoidPrevious = !refresh && ( order.failed || stalled || improve )
			vector ornull goal = AITdm_SelectAssaultPosition( order, positions, preferred, avoidPrevious, improve )
			order.retryTime = now + ( improve ? AITDM_ASSAULT_IDLE_TIME : stalled ? AITDM_ASSAULT_STALL_TIME : AITDM_ASSAULT_RETRY_TIME )
			if ( goal == null )
				continue

			AITdm_RestoreAssaultArrival( order )
			float tolerance = order.npc.AssaultGetArrivalTolerance()
			if ( tolerance <= 0.0 || tolerance > 64.0 )
			{
				order.arrivalTolerance = tolerance
				order.arrivalOverridden = true
				order.npc.AssaultSetArrivalTolerance( 64.0 )
			}

			order.goal = expect vector( goal )
			order.goalRevision = goalRevision
			order.assigned = true
			order.arrived = false
			order.failed = false
			order.progressOrigin = order.origin
			order.lastProgressTime = now
			order.npc.AssaultPoint( order.goal )
			order.npc.AssaultSetGoalRadius( max( radius, order.npc.GetMinGoalRadius() ) )
		}

		wait 1.0
	}
}

bool function AITdm_OwnsAssaultOrder( AITdmAssaultOrder order )
{
	entity guy = order.npc
	return !order.released && IsAlive( guy ) && guy.GetTeam() == order.team &&
		guy.GetBossPlayer() == order.bossPlayer && !IsValid( guy.GetFollowTarget() ) &&
		expect string( guy.kv.squadname ) == order.squadName
}

void function AITdm_RestoreAssaultArrival( AITdmAssaultOrder order )
{
	if ( !order.arrivalOverridden )
		return
	order.arrivalOverridden = false
	if ( IsAlive( order.npc ) && order.npc.AssaultGetArrivalTolerance() == 64.0 )
		order.npc.AssaultSetArrivalTolerance( order.arrivalTolerance )
}

void function AITdm_ReleaseAssaultOrder( AITdmAssaultOrder order )
{
	AITdm_RestoreAssaultArrival( order )
	order.assigned = false
	order.released = true
	if ( IsValid( order.npc ) )
		order.npc.Signal( "AITdm_StopAssault" )
	for ( int i = file.assaultOrders.len() - 1; i >= 0; i-- )
	{
		if ( file.assaultOrders[ i ] == order )
		{
			file.assaultOrders.remove( i )
			break
		}
	}
}

void function AITdm_UpdateAssaultActivity( AITdmAssaultOrder order, float now )
{
	entity guy = order.npc
	order.origin = guy.GetOrigin()
	if ( DistanceSqr( order.origin, order.progressOrigin ) >= 32 * 32 )
	{
		order.progressOrigin = order.origin
		order.lastProgressTime = now
		order.failed = false
	}

	int health = guy.GetHealth()
	entity enemy = guy.GetEnemy()
	float lastSeen = guy.GetEnemyLastTimeSeen()
	if ( lastSeen > 0.0 )
		order.lastEngagedTime = max( order.lastEngagedTime, lastSeen )
	if ( health < order.lastHealth || ( IsAlive( enemy ) && guy.CanSee( enemy ) ) )
		order.lastEngagedTime = now
	order.lastHealth = health
	if ( now - order.lastEngagedTime < AITDM_ASSAULT_COMBAT_GRACE )
		AITdm_RestoreAssaultArrival( order )

	order.paused = guy.GetParent() != null || !guy.IsInterruptable() || guy.Anim_IsActive()
	if ( order.paused )
	{
		AITdm_RestoreAssaultArrival( order )
		order.assigned = false
		order.arrived = false
		order.failed = false
		order.lastProgressTime = now
		order.retryTime = now + AITDM_ASSAULT_RETRY_TIME
	}
}

array<vector> function AITdm_GetAssaultPositions( vector anchor, entity guy )
{
	array<vector> positions
	vector ornull clamped = NavMesh_ClampPointForAIWithExtents( anchor, guy, < 128, 128, 128 > )
	if ( clamped == null )
		return positions

	vector center = expect vector( clamped )
	array<vector> neighbors = NavMesh_GetNeighborPositions( center, HULL_HUMAN, 32 )
	neighbors.insert( 0, center )
	foreach ( point in neighbors )
	{
		if ( Distance2DSqr( point, anchor ) > 512 * 512 || fabs( point.z - anchor.z ) > 128 )
			continue
		positions.append( point )
	}
	return positions
}

vector ornull function AITdm_SelectAssaultPosition( AITdmAssaultOrder order, array<vector> positions, vector preferred, bool avoidPrevious, bool improve )
{
	vector ornull bestPosition = null
	vector ornull retryPosition = null
	float bestScore = improve ? AITdm_AssaultPositionScore( order, order.origin, preferred ) - 64 * 64 : 1.0e30
	foreach ( point in positions )
	{
		if ( avoidPrevious && Distance2DSqr( order.goal, point ) < 64 * 64 )
		{
			if ( !improve && retryPosition == null && NavMesh_IsPosReachableForAI( order.npc, point ) )
				retryPosition = point
			continue
		}
		if ( improve && Distance2DSqr( order.origin, point ) < 128 * 128 )
			continue

		float score = AITdm_AssaultPositionScore( order, point, preferred )
		if ( score >= bestScore || !NavMesh_IsPosReachableForAI( order.npc, point ) )
			continue
		bestScore = score
		bestPosition = point
	}
	return bestPosition != null ? bestPosition : retryPosition
}

float function AITdm_AssaultPositionScore( AITdmAssaultOrder order, vector point, vector preferred )
{
	float score = Distance2DSqr( point, preferred )
	foreach ( other in file.assaultOrders )
	{
		if ( other == order || other.team != order.team || other.released || !IsAlive( other.npc ) )
			continue

		float separation = 1.0e30
		if ( fabs( point.z - other.origin.z ) <= 128 )
			separation = Distance2DSqr( point, other.origin )
		if ( other.assigned && fabs( point.z - other.goal.z ) <= 128 )
			separation = min( separation, Distance2DSqr( point, other.goal ) )
		float spacing = other.squadName == order.squadName ? 64.0 : 192.0
		if ( separation < spacing * spacing )
			score += ( spacing * spacing - separation ) * 16.0
	}
	return score
}

void function AITdm_WatchAssault( AITdmAssaultOrder order )
{
	order.npc.EndSignal( "OnDeath" )
	order.npc.EndSignal( "OnDestroy" )
	order.npc.EndSignal( "AITdm_StopAssault" )
	svGlobal.levelEnt.EndSignal( "GameStateChanged" )

	while ( true )
	{
		var result = order.npc.WaitSignal( "OnFailedToPath", "OnFinishedAssault", "OnLeeched" )
		if ( result.signal == "OnLeeched" )
		{
			AITdm_RestoreAssaultArrival( order )
			order.released = true
			order.assigned = false
			return
		}
		if ( !AITdm_OwnsAssaultOrder( order ) )
			return
		if ( !order.assigned )
			continue
		if ( result.signal == "OnFailedToPath" )
		{
			if ( order.arrived )
				continue
			if ( !order.failed )
				order.retryTime = Time() + AITDM_ASSAULT_RETRY_TIME
			order.failed = true
			order.arrived = false
			order.progressOrigin = order.npc.GetOrigin()
			AITdm_RestoreAssaultArrival( order )
		}
		else
		{
			vector origin = order.npc.GetOrigin()
			if ( Distance2DSqr( origin, order.goal ) > 64 * 64 || fabs( origin.z - order.goal.z ) > 128 )
				continue
			order.arrived = true
			order.failed = false
			AITdm_RestoreAssaultArrival( order )
		}
	}
}

// Award for hacking
void function OnSpectreLeeched( entity spectre, entity player )
{
	// Set Owner so we can filter in HandleScore
	spectre.SetOwner( player )
	// Add score + update network int to trigger the "Score +n" popup
	AddTeamScore( player.GetTeam(), 1 )
	player.AddToPlayerGameStat( PGS_ASSAULT_SCORE, 1 )
	int assaultScore = player.GetPlayerGameStat( PGS_ASSAULT_SCORE )
	int assaultScore256 = assaultScore / 256
	player.SetPlayerNetInt( "AT_bonusPoints256", assaultScore256 )
	player.SetPlayerNetInt( "AT_bonusPoints", assaultScore - assaultScore256 * 256 )
}

void function OnReaperKilled( entity victim, entity attacker, var damageInfo )
{
	// Basic checks
	if ( victim.GetClassName() != "npc_super_spectre" )
		return

	int team = victim.GetTeam()
	file.reaperRespawnTimes[ team ] <- Time() + GetCurrentPlaylistVarFloat( "aitdm_reaper_debounce", REAPER_RESPAWN_DEBOUNCE )
}

// Same as SquadHandler, just for reapers
void function ReaperHandler( entity reaper )
{
	array<entity> players = GetPlayerArrayOfEnemies( reaper.GetTeam() )
	foreach ( player in players )
		reaper.Minimap_AlwaysShow( 0, player )

	reaper.AssaultSetGoalRadius( 500 )

	// Every 10 - 20 secs get a player and go to him
	// Definetly not annoying or anything :)
	while ( IsAlive( reaper ) )
	{
		players = GetPlayerArrayOfEnemies( reaper.GetTeam() )
		if ( players.len() != 0 )
		{
			entity player = GetClosest2D( players, reaper.GetOrigin() )
			reaper.AssaultPoint( player.GetOrigin() )
		}
		wait RandomFloatRange( 10.0, 20.0 )
	}
}

