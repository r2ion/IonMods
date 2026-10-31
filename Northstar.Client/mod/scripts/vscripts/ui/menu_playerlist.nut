global function AddPlayerlistMenu
global function InitPlayerlistMenu
global function PopulatePlayerlistFromCL
global function DonePopulatingPlayerlist

const UPDATE_RATE = 1.0

struct
{
	var menu
	GridMenuData gridData
	array<string> playerNames
	array<string> playerUIDs
	int selectedElemNum
	bool donePopulating = false
} file

void function AddPlayerlistMenu()
{
	AddMenu( "PlayerlistMenu", $"resource/ui/menus/playerlist.menu", InitPlayerlistMenu )
}

void function InitPlayerlistMenu()
{
	var menu = GetMenu( "PlayerlistMenu" )

	file.menu = menu
	file.gridData.initCallback = PlayerButton_Init
	file.gridData.clickCallback = PlayerButton_Activate
	file.gridData.getFocusCallback = PlayerButton_GetFocus
	file.gridData.rows = 15
	file.gridData.columns = 2
	file.gridData.pageFillDirection = eGridPageFillDirection.DOWN
	file.gridData.pageType = eGridPageType.HORIZONTAL
	file.gridData.tileWidth = 400
	file.gridData.tileHeight = 40
	file.gridData.paddingVert = 6
	file.gridData.paddingHorz = 6
	file.gridData.panelLeftPadding = 64
	file.gridData.panelRightPadding = 64
	file.gridData.panelBottomPadding = 64
	file.gridData.forceHeaderAndFooterLayoutForSinglePage = true

	Grid_AutoAspectSettings( menu, file.gridData )

	AddMenuEventHandler( menu, eUIEvent.MENU_OPEN, OnPlayerlistMenu_Open )

	AddMenuFooterOption( menu, BUTTON_A, "#A_BUTTON_SELECT" )
	AddMenuFooterOption( menu, BUTTON_B, "#B_BUTTON_BACK", "#BACK" )
}

void function OnPlayerlistMenu_Open()
{
	UI_SetPresentationType( ePresentationType.NO_MODELS )

	int numPlayers = -1
	int lastNumPlayers = -2

	file.gridData.currentPage = 0
	file.donePopulating = false

	while ( GetTopNonDialogMenu() == file.menu )
	{
		ClearPlayerlist()

		RunClientScript( "ClGetPlayerEntsTrampoline" )

		while ( !file.donePopulating )
			WaitFrame()

		numPlayers = file.playerNames.len()

		if ( numPlayers != lastNumPlayers )
		{
			file.gridData.numElements = numPlayers

			int maxPageIndex = Grid_GetNumPages( file.gridData ) - 1
			if ( maxPageIndex < file.gridData.currentPage )
				file.gridData.currentPage = maxPageIndex

			GridMenuInit( file.menu, file.gridData )

			Grid_SetReadyState( file.menu, true )

			UpdateFooterOptions()
		}

		lastNumPlayers = numPlayers

		wait UPDATE_RATE
	}
}

bool function PlayerButton_Init( var button, int elemNum )
{
	string name = file.playerNames[ elemNum ]

	var rui = Hud_GetRui( button )
	RuiSetString( rui, "buttonText", name )

	return true
}

void function PlayerButton_Activate( var button, int elemNum )
{
	if ( Hud_IsLocked( button ) )
		return

	file.selectedElemNum = elemNum

	if ( elemNum >= 0 && elemNum < file.playerUIDs.len() )
	{
		string uid = file.playerUIDs[ elemNum ]
		ShowPlayerProfileCardForUID( uid )
	}
}

void function PlayerButton_GetFocus( var button, int elemNum )
{
	UpdateFooterOptions()
}

void function PopulatePlayerlistFromCL( string name, string uid )
{
	file.playerNames.append( name )
	file.playerUIDs.append( uid )
}

void function DonePopulatingPlayerlist()
{
	file.donePopulating = true
}

void function ClearPlayerlist()
{
	file.playerNames.clear()
	file.playerUIDs.clear()
}
