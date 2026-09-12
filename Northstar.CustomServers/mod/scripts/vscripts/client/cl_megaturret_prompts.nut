untyped

global function MegaTurretPrompts_Init

struct
{
	string repair
	string capture
} file

void function MegaTurretPrompts_Init()
{
	string prompt = Localize( "#TURRET_HEAVY_REPAIR_CAPTURE" )
	int separator = expect int( prompt.find( "||" ) )
	file.repair = prompt.slice( 0, separator )
	file.capture = prompt.slice( separator + 2 )
	AddCreateCallback( "npc_turret_mega", MegaTurretPrompt_OnCreate )
}

void function MegaTurretPrompt_OnCreate( entity turret )
{
	thread MegaTurretPrompt_LinkPanel( turret )
}

void function MegaTurretPrompt_LinkPanel( entity turret )
{
	turret.EndSignal( "OnDestroy" )
	entity panel = turret.GetControlPanel()
	while ( !IsValid( panel ) )
	{
		WaitFrame()
		panel = turret.GetControlPanel()
	}

	if ( IsValid( panel.e.entTextOverrideCallback ) && panel.e.entTextOverrideCallback != MegaTurretPrompt_GetText )
		return
	panel.s.megaTurretPromptTarget <- turret
	if ( !IsValid( panel.e.entTextOverrideCallback ) )
		AddEntityCallback_GetUseEntOverrideText( panel, MegaTurretPrompt_GetText )
}

string function MegaTurretPrompt_GetText( entity panel )
{
	entity turret = expect entity( panel.s.megaTurretPromptTarget )
	if ( !IsValid( turret ) )
		return ""
	return !IsAlive( turret ) || !IsIMCOrMilitiaTeam( turret.GetTeam() ) ? file.repair : file.capture
}
