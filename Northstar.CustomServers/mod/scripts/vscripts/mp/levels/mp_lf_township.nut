global function CodeCallback_MapInit

void function CodeCallback_MapInit()
{
	SetupLiveFireMaps()

	if ( GameRules_GetGameMode() == FD )
		initFrontierDefenseData()
}
