untyped

global function ModBrowser_LoadSourceImages
global function ModBrowser_SetSourceBadge
global function ModBrowser_GetSourceName
global function AddNorthstarModBrowserMenu
global function NSUICodeCallback_ModBrowserPageChanged
global function NSUICodeCallback_ModBrowserDetailsChanged
global function NSUICodeCallback_ModBrowserUpdatesChanged
global function NSUICodeCallback_ModBrowserOperationChanged

const int MOD_BROWSER_VISIBLE_COUNT = 18
const int MOD_BROWSER_BATCH_SIZE = 24
const int MOD_BROWSER_SCROLL_STEP = 6
const int MOD_BROWSER_DETAILS_LINE_WIDTH = 70
const int MOD_BROWSER_DETAILS_VISIBLE_LINES = 5
const float MOD_BROWSER_TITLE_MAX_WIDTH_MULTIPLIER = 1.6
const float MOD_BROWSER_SEARCH_DELAY = 0.35
const int MOD_BROWSER_INVENTORY_LOCAL_COMPLETE = 0
const int MOD_BROWSER_INVENTORY_LOCAL_REMOTE_PENDING = 1
const int MOD_BROWSER_INVENTORY_REMOTE_COMPLETE = 2
const int MOD_BROWSER_IMAGE_WIDTH = 504
const int MOD_BROWSER_IMAGE_HEIGHT = 252
const int MOD_BROWSER_IMAGE_GUTTER = 4
const int MOD_BROWSER_ATLAS_COLUMNS = 6
const int MOD_BROWSER_SOURCE_SIZE = 128
const int MOD_BROWSER_SOURCE_GUTTER = 2
const vector MOD_BROWSER_IMAGE_PENDING = <0.08, 0.09, 0.11>
const vector MOD_BROWSER_IMAGE_ERROR = <0.16, 0.09, 0.10>

struct
{
	var menu
	array<var> cards
	array<var> cardButtons
	var detailsPreviewFocus
	array<var> previewElements
	array<ModBrowserPageEntry> entries
	string search = ""
	string sort = "bumped_at"
	int filter = 0
	int source = 4
	int page = 1
	int lastPage = 1
	int scrollOffset = 0
	int totalEntries = 0
	bool fromCache = false
	bool scrollToEnd = false
	bool loading = false
	int requestGeneration = 0
	int imageAtlas = 0
	int sourceAtlas = 0
	int imageGeneration = 0
	int detailsGeneration = 0
	int selectedIndex = -1
	string selectedId = ""
	int pendingAction = eModBrowserInstallAction.INSTALL
	int browseOperationGeneration = 0
	int lastTerminalGeneration = 0
	bool isOpen = false
	bool previewVisible = false
	int inventoryGeneration = 0
	bool forcePageRefresh = false
	bool focusCardsOnNextRender = false
	array<string> detailsLines
	int detailsScrollOffset = 0
	bool operationDialogRunning = false
	int lastOperationDialogGeneration = 0
	int lastMigrationPromptGeneration = 0
} file

void function AddNorthstarModBrowserMenu()
{
	RegisterSignal( "MOD_BROWSER_SearchChanged" )
	RegisterSignal( "MOD_BROWSER_OperationChanged" )
	thread ModBrowserOperationDialog_Think()
	AddMenu( "ModBrowserMenu", $"resource/ui/menus/modbrowser.menu", InitModBrowserMenu )
	ModBrowserOperationSnapshot operation = NSModBrowserGetOperationState()
	if ( operation.state != eModBrowserInstallState.IDLE )
		Signal( uiGlobal.signalDummy, "MOD_BROWSER_OperationChanged" )
}

void function InitModBrowserMenu()
{
	file.menu = GetMenu( "ModBrowserMenu" )
	file.cards = GetElementsByClassname( file.menu, "ModBrowserCard" )
	file.cardButtons = GetElementsByClassname( file.menu, "ModBrowserCardButton" )
	file.detailsPreviewFocus = Hud_GetChild( file.menu, "DetailsPreviewFocus" )
	file.previewElements = GetElementsByClassname( file.menu, "ModBrowserPreviewPane" )
	Hud_EnableKeyBindingIcons( Hud_GetChild( file.menu, "PageLabel" ) )
	SetPreviewVisible( false )

	foreach ( var button in file.cardButtons )
	{
		AddButtonEventHandler( button, UIE_GET_FOCUS, OnCardFocused )
		AddButtonEventHandler( button, UIE_CLICK, OnCardActivated )
	}

	AddButtonEventHandler( Hud_GetChild( file.menu, "ModBrowserSearch" ), UIE_CHANGE, OnSearchChanged )
	AddButtonEventHandler( Hud_GetChild( file.menu, "ModBrowserSort" ), UIE_CHANGE, OnSortChanged )
	AddButtonEventHandler( Hud_GetChild( file.menu, "ModBrowserFilter" ), UIE_CHANGE, OnFilterChanged )
	RuiSetString( Hud_GetRui( Hud_GetChild( file.menu, "ModBrowserSort" ) ), "buttonText", "" )
	RuiSetString( Hud_GetRui( Hud_GetChild( file.menu, "ModBrowserFilter" ) ), "buttonText", "" )
	AddButtonEventHandler( Hud_GetChild( file.menu, "ModBrowserSource" ), UIE_CHANGE, OnSourceChanged )
	RuiSetString( Hud_GetRui( Hud_GetChild( file.menu, "ModBrowserSource" ) ), "buttonText", "" )
	AddCallback_InputEvent( InputEventType.IE_AnalogValueChanged, OnAnalogueScroll )

	AddMenuEventHandler( file.menu, eUIEvent.MENU_OPEN, OnModBrowserOpened )
	AddMenuEventHandler( file.menu, eUIEvent.MENU_CLOSE, OnModBrowserClosed )
	AddMenuFooterOption( file.menu, BUTTON_A, "#A_BUTTON_SELECT" )
	AddMenuFooterOption( file.menu, BUTTON_B, "#B_BUTTON_BACK", "#BACK" )
	AddMenuFooterOption( file.menu, BUTTON_X, PrependControllerPrompts( BUTTON_X, "#REFRESH_SERVERS" ), "#REFRESH_SERVERS", OnRefresh )

	Hud_SetDialogListSelectionValue( Hud_GetChild( file.menu, "ModBrowserSort" ), file.sort )
	Hud_SetDialogListSelectionValue( Hud_GetChild( file.menu, "ModBrowserFilter" ), string( file.filter ) )
	Hud_SetDialogListSelectionValue( Hud_GetChild( file.menu, "ModBrowserSource" ), string( file.source ) )
}

void function OnModBrowserOpened()
{
	file.isOpen = true
	file.focusCardsOnNextRender = true
	SetPreviewVisible( false )
	UI_SetPresentationType( ePresentationType.NO_MODELS )
	ModBrowser_CreateImageAtlas()
	ModBrowser_LoadSourceImages()
	ResetScroll()
	file.loading = true
	ShowGridMessage( "#MOD_BROWSER_LOADING" )
	Hud_SetText( Hud_GetChild( file.menu, "PageLabel" ), "#MOD_BROWSER_LOADING_SHORT" )
	BeginInventoryRefresh( true, false )
}

void function OnModBrowserClosed()
{
	file.isOpen = false
	file.imageGeneration++
	file.focusCardsOnNextRender = false
	Signal( uiGlobal.signalDummy, "MOD_BROWSER_SearchChanged" )
	NSModBrowserCancelPage()
	NSModBrowserCancelDetails()
}

void function ResetScroll()
{
	file.page = 1
	file.scrollOffset = 0
	file.scrollToEnd = false
}

void function BeginInventoryRefresh( bool checkRemote, bool forcePageRefresh )
{
	file.imageGeneration++
	file.forcePageRefresh = forcePageRefresh
	file.inventoryGeneration = NSModBrowserRefreshTrackedMods( checkRemote )
}

void function OnRefresh( var button )
{
	if ( file.loading )
		return
	file.focusCardsOnNextRender = ModBrowser_IsCardFocused()
	file.loading = true
	ShowGridMessage( "#MOD_BROWSER_LOADING" )
	Hud_SetText( Hud_GetChild( file.menu, "PageLabel" ), "#MOD_BROWSER_LOADING_SHORT" )
	BeginInventoryRefresh( true, true )
}



void function OnSearchChanged( var button )
{
	string value = Hud_GetUTF8Text( button )
	file.focusCardsOnNextRender = false
	Signal( uiGlobal.signalDummy, "MOD_BROWSER_SearchChanged" )
	thread ApplySearchAfterDelay( value )
}

void function ApplySearchAfterDelay( string value )
{
	EndSignal( uiGlobal.signalDummy, "MOD_BROWSER_SearchChanged" )
	wait MOD_BROWSER_SEARCH_DELAY
	if ( !file.isOpen )
		return
	file.focusCardsOnNextRender = false
	file.search = value
	ResetScroll()
	RequestCurrentPage( false )
}

void function OnSortChanged( var button )
{
	file.focusCardsOnNextRender = false
	file.sort = Hud_GetDialogListSelectionValue( button )
	ResetScroll()
	RequestCurrentPage( false )
}

void function OnFilterChanged( var button )
{
	file.focusCardsOnNextRender = false
	file.filter = int( Hud_GetDialogListSelectionValue( button ) )
	ResetScroll()
	if ( file.filter == 2 )
	{
		file.loading = true
		ShowGridMessage( "#MOD_BROWSER_LOADING" )
		Hud_SetText( Hud_GetChild( file.menu, "PageLabel" ), "#MOD_BROWSER_LOADING_SHORT" )
		BeginInventoryRefresh( true, false )
		return
	}
	RequestCurrentPage( false )
}

void function OnSourceChanged( var button )
{
	file.focusCardsOnNextRender = false
	file.source = int( Hud_GetDialogListSelectionValue( button ) )
	ResetScroll()
	RequestCurrentPage( false )
}

bool function ModBrowser_IsCardFocused()
{
	var focused = GetFocus()
	foreach ( var button in file.cardButtons )
	{
		if ( focused == button )
			return true
	}
	return false
}

void function OnAnalogueScroll( int eventType, int nTick, int nData, int nData2, int nData3 )
{
	if ( !file.isOpen || uiGlobal.activeMenu != file.menu || nData != AnalogCode.MOUSE_WHEEL )
		return
	if ( GetFocus() == file.detailsPreviewFocus )
	{
		ScrollDetails( nData3 > 0 ? -1 : 1 )
		return
	}
	if ( nData3 > 0 )
		OnScrollUp()
	else if ( nData3 < 0 )
		OnScrollDown()
}

void function OnScrollDown()
{
	if ( file.loading || file.entries.len() == 0 )
		return
	int maxOffset = maxint( 0, file.entries.len() - MOD_BROWSER_VISIBLE_COUNT )
	int nextOffset = minint( maxOffset, file.scrollOffset + MOD_BROWSER_SCROLL_STEP )
	if ( nextOffset != file.scrollOffset )
	{
		file.scrollOffset = nextOffset
		RenderVisibleEntries( true )
		return
	}
	if ( file.page >= file.lastPage )
		return
	file.page++
	file.scrollOffset = 0
	file.scrollToEnd = false
	file.focusCardsOnNextRender = true
	RequestCurrentPage( false )
}

void function OnScrollUp()
{
	if ( file.loading || file.entries.len() == 0 )
		return
	int nextOffset = maxint( 0, file.scrollOffset - MOD_BROWSER_SCROLL_STEP )
	if ( nextOffset != file.scrollOffset )
	{
		file.scrollOffset = nextOffset
		RenderVisibleEntries( true )
		return
	}
	if ( file.page <= 1 )
		return
	file.page--
	file.scrollToEnd = true
	file.focusCardsOnNextRender = true
	RequestCurrentPage( false )
}

void function RequestCurrentPage( bool forceRefresh )
{
	if ( !file.isOpen )
		return
	file.loading = true
	file.imageGeneration++
	file.requestGeneration = NSModBrowserRequestPage(
		file.search,
		file.sort,
		file.page,
		file.filter,
		forceRefresh,
		file.source
	)
	ShowGridMessage( "#MOD_BROWSER_LOADING" )
}

void function NSUICodeCallback_ModBrowserPageChanged( int generation )
{
	if ( !file.isOpen )
		return
	ModBrowserPageSnapshot snapshot = NSModBrowserGetPage()
	if ( snapshot.generation != file.requestGeneration )
		return
	RenderPage( snapshot )
}

void function RenderPage( ModBrowserPageSnapshot snapshot )
{
	file.loading = snapshot.state == eModBrowserLoadState.LOADING
	if ( snapshot.state == eModBrowserLoadState.LOADING )
	{
		ShowGridMessage( "#MOD_BROWSER_LOADING" )
		Hud_SetText( Hud_GetChild( file.menu, "PageLabel" ), "#MOD_BROWSER_LOADING_SHORT" )
		return
	}
	if ( snapshot.state == eModBrowserLoadState.FAILED )
	{
		ShowGridMessage( snapshot.error == "" ? "#MOD_BROWSER_UNAVAILABLE" : snapshot.error )
		Hud_SetText( Hud_GetChild( file.menu, "PageLabel" ), "#MOD_BROWSER_SCROLL_UNAVAILABLE" )
		return
	}
	if ( snapshot.state == eModBrowserLoadState.CANCELLED )
		return
	if ( snapshot.state != eModBrowserLoadState.READY )
	{
		ShowGridMessage( "#MOD_BROWSER_NOT_READY" )
		return
	}

	file.entries = snapshot.entries
	ModBrowser_LoadPageImages()
	file.page = snapshot.currentPage
	file.lastPage = maxint( 1, snapshot.lastPage )
	file.totalEntries = maxint( snapshot.total, file.entries.len() )
	file.fromCache = snapshot.fromCache
	int maxOffset = maxint( 0, file.entries.len() - MOD_BROWSER_VISIBLE_COUNT )
	if ( file.scrollToEnd )
	{
		file.scrollOffset = maxOffset
		file.scrollToEnd = false
	}
	else
	{
		file.scrollOffset = minint( file.scrollOffset, maxOffset )
	}

	if ( file.entries.len() == 0 )
	{
		file.focusCardsOnNextRender = false
		ShowGridMessage( "#MOD_BROWSER_NO_MODS_FOUND" )
		Hud_SetText( Hud_GetChild( file.menu, "PageLabel" ), "#NO_RESULTS" )
		ClearDetails()
		return
	}
	HideGridMessage()
	bool focusCards = file.focusCardsOnNextRender
	file.focusCardsOnNextRender = false
	RenderVisibleEntries( focusCards )
}

void function RenderVisibleEntries( bool focusCards )
{
	HideAllCards()
	int visibleCount = minint( MOD_BROWSER_VISIBLE_COUNT, file.entries.len() - file.scrollOffset )
	for ( int visibleIndex = 0; visibleIndex < visibleCount; visibleIndex++ )
	{
		int entryIndex = file.scrollOffset + visibleIndex
		ModBrowserPageEntry entry = file.entries[ entryIndex ]
		var card = file.cards[ visibleIndex ]
		var button = file.cardButtons[ visibleIndex ]
		Hud_Show( card )
		Hud_Show( button )
		Hud_SetEnabled( button, true )
		RuiSetImage(
			Hud_GetRui( Hud_GetChild( card, "Thumbnail" ) ),
			"basicImage",
			ScriptAtlasGetImage( file.imageAtlas, entryIndex )
		)
		ModBrowser_SetSourceBadge( card, "Source", entry.source, true )
		SetScaledTitle( Hud_GetChild( card, "ModName" ), entry.name, 162.0 )
		Hud_SetText( Hud_GetChild( card, "ModAuthor" ), GetAuthorText( entry.author, "" ) )
		Hud_SetText( Hud_GetChild( card, "ModStatus" ), GetCardStatus( entry ) )
	}

	int focusIndex = 0
	if ( file.selectedId != "" )
	{
		for ( int visibleIndex = 0; visibleIndex < visibleCount; visibleIndex++ )
		{
			if ( file.entries[ file.scrollOffset + visibleIndex ].id == file.selectedId )
			{
				focusIndex = visibleIndex
				break
			}
		}
	}
	if ( focusCards )
		Hud_SetFocused( file.cardButtons[ focusIndex ] )
	SelectCard( file.scrollOffset + focusIndex )
	UpdateScrollLabel( visibleCount )
}

void function UpdateScrollLabel( int visibleCount )
{
	int first = ( file.page - 1 ) * MOD_BROWSER_BATCH_SIZE + file.scrollOffset + 1
	int last = first + visibleCount - 1
	int total = maxint( file.totalEntries, last )
	Hud_SetText(
		Hud_GetChild( file.menu, "PageLabel" ),
		Localize(
			"#MOD_BROWSER_PAGE_RANGE",
			string( first ),
			string( last ),
			string( total ),
			file.fromCache ? Localize( "#MOD_BROWSER_CACHED_SUFFIX" ) : ""
		)
	)
}

void function HideAllCards()
{
	foreach ( var card in file.cards )
		Hud_Hide( card )
	foreach ( var button in file.cardButtons )
	{
		Hud_Hide( button )
		Hud_SetEnabled( button, false )
	}
}

void function ShowGridMessage( string message )
{
	HideAllCards()
	SetPreviewVisible( false )
	var label = Hud_GetChild( file.menu, "GridMessage" )
	Hud_SetText( label, message )
	Hud_Show( label )
}

void function HideGridMessage()
{
	Hud_Hide( Hud_GetChild( file.menu, "GridMessage" ) )
}

void function OnCardFocused( var button )
{
	SelectCard( file.scrollOffset + int( Hud_GetScriptID( button ) ) )
}

void function OnCardActivated( var button )
{
	int index = file.scrollOffset + int( Hud_GetScriptID( button ) )
	SelectCard( index )
	OpenDownloadDialog()
}

void function SelectCard( int index )
{
	if ( index < 0 || index >= file.entries.len() )
		return
	ModBrowserPageEntry entry = file.entries[ index ]
	file.selectedIndex = index
	file.selectedId = entry.id
	SetPreviewVisible( ScriptAtlasGetImageState( file.imageAtlas, index ) == eScriptAtlasImageState.READY )
	RuiSetImage(
		Hud_GetRui( Hud_GetChild( file.menu, "DetailsImage" ) ),
		"basicImage",
		ScriptAtlasGetImage( file.imageAtlas, index )
	)
	SetScaledTitle( Hud_GetChild( file.menu, "DetailsName" ), entry.name, 460.0 )
	Hud_SetText( Hud_GetChild( file.menu, "DetailsAuthor" ), GetAuthorText( entry.author, entry.version ) + "    " + ModBrowser_GetSourceName( entry.source ) )
	SetDetailsDescription( entry.summary )
	Hud_SetText( Hud_GetChild( file.menu, "DetailsStatus" ), GetDownloadCountText( entry.downloads ) )
	Hud_SetText( Hud_GetChild( file.menu, "ProgressLabel" ), "" )
	file.detailsGeneration = NSModBrowserRequestDetails( entry.id, false )
}

void function ModBrowser_CreateImageAtlas()
{
	// Retain one layout for this UI VM; native VM teardown releases its resources.
	if ( file.imageAtlas != 0 )
		return
	array<ScriptAtlasImage> images
	int strideX = MOD_BROWSER_IMAGE_WIDTH + MOD_BROWSER_IMAGE_GUTTER * 2
	int strideY = MOD_BROWSER_IMAGE_HEIGHT + MOD_BROWSER_IMAGE_GUTTER * 2
	for ( int slot = 0; slot < MOD_BROWSER_BATCH_SIZE; slot++ )
	{
		ScriptAtlasImage image
		image.name = "northstar/modbrowser/thumbnail_" + slot
		image.x = ( slot % MOD_BROWSER_ATLAS_COLUMNS ) * strideX + MOD_BROWSER_IMAGE_GUTTER
		image.y = ( slot / MOD_BROWSER_ATLAS_COLUMNS ) * strideY + MOD_BROWSER_IMAGE_GUTTER
		image.width = MOD_BROWSER_IMAGE_WIDTH
		image.height = MOD_BROWSER_IMAGE_HEIGHT
		image.gutter = MOD_BROWSER_IMAGE_GUTTER
		images.append( image )
	}
	file.imageAtlas = ScriptAtlasCreate( "northstar/modbrowser/thumbnails", MOD_BROWSER_ATLAS_COLUMNS * strideX,
		( ( MOD_BROWSER_BATCH_SIZE + MOD_BROWSER_ATLAS_COLUMNS - 1 ) / MOD_BROWSER_ATLAS_COLUMNS ) * strideY, images )
}

void function ModBrowser_LoadPageImages()
{
	file.imageGeneration++
	for ( int slot = 0; slot < MOD_BROWSER_BATCH_SIZE; slot++ )
	{
		ScriptAtlasClearImage( file.imageAtlas, slot, MOD_BROWSER_IMAGE_PENDING, 1.0 )
		if ( slot < file.entries.len() )
			thread ModBrowser_LoadThumbnail( slot, file.entries[ slot ], file.imageGeneration )
	}
}

void function ModBrowser_LoadThumbnail( int slot, ModBrowserPageEntry entry, int generation )
{
	array<string> sources
	if ( entry.thumbnailUrl != "" )
		sources.append( entry.thumbnailUrl )
	if ( entry.thumbnailFallbackUrl != "" && entry.thumbnailFallbackUrl != entry.thumbnailUrl )
		sources.append( entry.thumbnailFallbackUrl )
	int nextSource = 0
	bool requested = false
	bool failed = false
	int previousState = -1
	while ( file.isOpen && generation == file.imageGeneration )
	{
		int state = ScriptAtlasGetImageState( file.imageAtlas, slot )
		if ( !failed && ( !requested || state == eScriptAtlasImageState.FAILED ) )
		{
			requested = false
			while ( nextSource < sources.len() && !requested )
			{
				string source = sources[ nextSource++ ]
				requested = ScriptAtlasLoadImage( file.imageAtlas, slot, source, entry.thumbnailVersion, eScriptAtlasFit.COVER )
			}
			if ( !requested )
			{
				ScriptAtlasClearImage( file.imageAtlas, slot, MOD_BROWSER_IMAGE_ERROR, 1.0 )
				failed = true
			}
			state = ScriptAtlasGetImageState( file.imageAtlas, slot )
		}
		if ( state != previousState && file.selectedIndex == slot && file.selectedId == entry.id )
			SetPreviewVisible( state == eScriptAtlasImageState.READY )
		previousState = state
		wait 0.05
	}
}

void function NSUICodeCallback_ModBrowserDetailsChanged( string modId )
{
	if ( !file.isOpen || modId != file.selectedId )
		return
	ModBrowserDetailsSnapshot details = NSModBrowserGetDetails()
	if ( details.generation != file.detailsGeneration || details.id != file.selectedId )
		return
	if ( details.state == eModBrowserLoadState.LOADING )
	{
		Hud_SetText( Hud_GetChild( file.menu, "ProgressLabel" ), "#MOD_BROWSER_LOADING_DETAILS" )
		return
	}
	if ( details.state == eModBrowserLoadState.FAILED )
	{
		Hud_SetText( Hud_GetChild( file.menu, "ProgressLabel" ), details.error == "" ? "#MOD_BROWSER_DETAILS_UNAVAILABLE" : details.error )
		return
	}
	if ( details.state != eModBrowserLoadState.READY )
		return

	string description = details.description
	if ( details.dependencies.len() > 0 )
	{
		string dependencies = ""
		foreach ( int index, string dependency in details.dependencies )
			dependencies += ( index == 0 ? "" : ", " ) + dependency
		description += Localize( "#MOD_BROWSER_REQUIRES", dependencies )
	}
	SetScaledTitle( Hud_GetChild( file.menu, "DetailsName" ), details.name, 460.0 )
	Hud_SetText( Hud_GetChild( file.menu, "DetailsAuthor" ), GetAuthorText( details.author, details.version ) + "    " + ModBrowser_GetSourceName( details.source ) )
	SetDetailsDescription( description )
	Hud_SetText(
		Hud_GetChild( file.menu, "DetailsStatus" ),
		Localize( "#MOD_BROWSER_DETAILS_STATS", string( details.downloads ), string( details.likes ), string( details.views ) )
	)
	Hud_SetText( Hud_GetChild( file.menu, "ProgressLabel" ), "" )
}


void function OpenDownloadDialog()
{
	if ( file.selectedIndex < 0 || file.selectedIndex >= file.entries.len() )
		return
	ModBrowserPageEntry entry = file.entries[ file.selectedIndex ]
	ModBrowserOperationSnapshot operation = NSModBrowserGetOperationState()
	if ( IsOperationBusy( operation.state ) && operation.id == entry.id )
	{
		NSModBrowserCancelOperation()
		return
	}
	if ( IsOperationBusy( operation.state ) )
	{
		ShowOperationError( Localize( "#MOD_BROWSER_ANOTHER_OPERATION_ACTIVE" ), entry.installed ? eModBrowserInstallAction.UPDATE : eModBrowserInstallAction.INSTALL )
		return
	}
	if ( !entry.canInstall )
	{
		DialogData unavailableDialog
		unavailableDialog.header = Localize( "#MOD_BROWSER_DOWNLOAD_UNAVAILABLE" )
		unavailableDialog.message = Localize( "#MOD_BROWSER_CANNOT_INSTALL", entry.name )
		AddDialogButton( unavailableDialog, "#OK" )
		OpenDialog( unavailableDialog )
		return
	}

	if ( entry.installed && entry.updateState != eModBrowserUpdateState.UPDATE_AVAILABLE )
		return

	file.pendingAction = entry.installed ? eModBrowserInstallAction.UPDATE : eModBrowserInstallAction.INSTALL
	string actionLabel = entry.installed ? "#MOD_BROWSER_ACTION_UPDATE" : "#MOD_BROWSER_ACTION_DOWNLOAD"
	string actionVerb = Localize( entry.installed ? "#MOD_BROWSER_ACTION_UPDATE" : "#MOD_BROWSER_VERB_DOWNLOAD_AND_INSTALL" )
	DialogData dialogData
	dialogData.header = Localize( entry.installed ? "#MOD_BROWSER_UPDATE_MOD" : "#MOD_BROWSER_DOWNLOAD_MOD" )
	dialogData.message = Localize( "#MOD_BROWSER_CONFIRM_ACTION", actionVerb, entry.name, entry.author )
	AddDialogButton( dialogData, actionLabel, ConfirmPendingAction )
	AddDialogButton( dialogData, "#CANCEL" )
	OpenDialog( dialogData )
}

void function ConfirmPendingAction()
{
	bool accepted = false
	switch ( file.pendingAction )
	{
		case eModBrowserInstallAction.INSTALL:
			accepted = NSModBrowserInstall( file.selectedId )
			break
		case eModBrowserInstallAction.UPDATE:
			accepted = NSModBrowserUpdate( file.selectedId )
			break
	}
	if ( !accepted )
	{
		ShowOperationError( Localize( "#MOD_BROWSER_ANOTHER_OPERATION_ACTIVE" ), file.pendingAction )
		return
	}
	file.browseOperationGeneration = NSModBrowserGetOperationState().generation
}




void function ShowMigrationPrompt( ModBrowserOperationSnapshot operation )
{
	file.lastMigrationPromptGeneration = operation.generation
	NSUISetConnectionModalChoiceActive( true )
	CloseAllDialogs()

	int generation = operation.generation
	DialogData dialogData
	dialogData.header = "#MOD_BROWSER_MIGRATION_TITLE"
	dialogData.message = Localize( "#MOD_BROWSER_MIGRATION_MESSAGE", operation.name )
	dialogData.forceChoice = true
	AddDialogButton(
		dialogData,
		"#MOD_BROWSER_MIGRATION_ACCEPT",
		void function() : ( generation )
		{
			NSUISetConnectionModalChoiceActive( false )
			NSModBrowserDecideMigration( generation, true )
		}
	)
	AddDialogButton(
		dialogData,
		"#MOD_BROWSER_MIGRATION_KEEP",
		void function() : ( generation )
		{
			NSUISetConnectionModalChoiceActive( false )
			NSModBrowserDecideMigration( generation, false )
		}
	)
	OpenDialog( dialogData )
}

void function NSUICodeCallback_ModBrowserOperationChanged()
{
	ModBrowserOperationSnapshot operation = NSModBrowserGetOperationState()
	Signal( uiGlobal.signalDummy, "MOD_BROWSER_OperationChanged" )
	if ( operation.state == eModBrowserInstallState.AWAITING_MIGRATION &&
		operation.generation != file.lastMigrationPromptGeneration )
	{
		ShowMigrationPrompt( operation )
		return
	}
	if ( operation.generation == file.lastMigrationPromptGeneration && IsOperationTerminal( operation.state ) )
		NSUISetConnectionModalChoiceActive( false )

	if ( operation.generation == file.browseOperationGeneration && IsOperationTerminal( operation.state ) )
	{
		file.browseOperationGeneration = 0
		if ( operation.state == eModBrowserInstallState.DONE )
		{
			ReloadMods()
			return
		}
	}

	if ( !file.isOpen )
		return
	if ( operation.id == file.selectedId )
		Hud_SetText( Hud_GetChild( file.menu, "ProgressLabel" ), GetOperationProgressText( operation ) )

	if ( IsOperationTerminal( operation.state ) && operation.generation != file.lastTerminalGeneration )
	{
		file.lastTerminalGeneration = operation.generation
		BeginInventoryRefresh( false, false )
	}
}

void function NSUICodeCallback_ModBrowserUpdatesChanged( int generation, int updateCount, int stage )
{
	if ( !file.isOpen || generation != file.inventoryGeneration )
		return
	if ( stage == MOD_BROWSER_INVENTORY_REMOTE_COMPLETE && file.filter != 2 )
	{
		file.focusCardsOnNextRender = file.focusCardsOnNextRender || ModBrowser_IsCardFocused()
		RequestCurrentPage( false )
		return
	}
	if ( stage == MOD_BROWSER_INVENTORY_LOCAL_REMOTE_PENDING && file.filter == 2 )
		return
	bool forceRefresh = file.forcePageRefresh
	file.forcePageRefresh = false
	file.focusCardsOnNextRender = file.focusCardsOnNextRender || ModBrowser_IsCardFocused()
	ResetScroll()
	RequestCurrentPage( forceRefresh )
}

void function ModBrowserOperationDialog_Think()
{
	for ( ; ; )
	{
		WaitSignal( uiGlobal.signalDummy, "MOD_BROWSER_OperationChanged" )
		ModBrowserOperationSnapshot operation = NSModBrowserGetOperationState()
		if ( NSUIConnectionOwnsModDownloadDialog() ||
			operation.generation == 0 ||
			operation.generation == file.lastOperationDialogGeneration ||
			file.operationDialogRunning )
		{
			continue
		}

		file.operationDialogRunning = true
		thread ModBrowserOperationDialog_Run( operation.generation )
	}
}

void function ModBrowserOperationDialog_Run( int generation )
{
	WaitFrame()
	ModBrowserOperationSnapshot operation = NSModBrowserGetOperationState()
	if ( operation.generation != generation )
	{
		file.operationDialogRunning = false
		Signal( uiGlobal.signalDummy, "MOD_BROWSER_OperationChanged" )
		return
	}
	if ( IsOperationTerminal( operation.state ) )
	{
		file.lastOperationDialogGeneration = generation
		file.operationDialogRunning = false
		if ( operation.state == eModBrowserInstallState.FAILED )
			ShowOperationError( operation.message, operation.action )
		return
	}
	if ( operation.state == eModBrowserInstallState.AWAITING_MIGRATION )
	{
		file.operationDialogRunning = false
		return
	}
	if ( !IsOperationBusy( operation.state ) )
	{
		file.operationDialogRunning = false
		return
	}

	DialogData dialogData
	dialogData.header = GetOperationDialogHeader( operation.action )
	dialogData.message = GetOperationProgressText( operation )
	dialogData.showSpinner = true
	dialogData.forceChoice = false
	AddDialogButton( dialogData, "#DISMISS" )
	OpenDialog( dialogData )

	var dialogMenu = GetMenu( "Dialog" )
	var header = Hud_GetChild( dialogMenu, "DialogHeader" )
	var body = GetSingleElementByClassname( dialogMenu, "DialogMessageClass" )
	for ( ; ; )
	{
		operation = NSModBrowserGetOperationState()
		if ( operation.generation != generation || IsOperationTerminal( operation.state ) )
			break
		if ( operation.state == eModBrowserInstallState.AWAITING_MIGRATION )
		{
			WaitFrame()
			continue
		}
		if ( uiGlobal.activeMenu == dialogMenu )
		{
			Hud_SetText( header, GetOperationDialogHeader( operation.action ) )
			Hud_SetText( body, GetOperationProgressText( operation ) )
		}
		WaitFrame()
	}

	if ( uiGlobal.activeMenu == dialogMenu )
		CloseAllDialogs()
	file.lastOperationDialogGeneration = generation
	file.operationDialogRunning = false
	if ( operation.generation == generation && operation.state == eModBrowserInstallState.FAILED )
		ShowOperationError( operation.message, operation.action )
	if ( operation.generation != generation )
		Signal( uiGlobal.signalDummy, "MOD_BROWSER_OperationChanged" )
}

void function ShowOperationError( string message, int action )
{
	DialogData dialogData
	dialogData.header = Localize( action == eModBrowserInstallAction.REMOVE ? "#MODS_UNINSTALL_ERROR_TITLE" : "#MOD_BROWSER_ERROR_TITLE" )
	dialogData.message = message == "" ? Localize( "#MOD_BROWSER_OPERATION_FAILED" ) : Localize( message )
	dialogData.image = $"ui/menu/common/dialog_error"
	AddDialogButton( dialogData, "#OK" )
	OpenDialog( dialogData )
}

void function SetPreviewVisible( bool visible )
{
	file.previewVisible = visible
	foreach ( var element in file.previewElements )
		Hud_SetVisible( element, visible )
	Hud_SetEnabled( file.detailsPreviewFocus, visible )
	int source = file.selectedIndex >= 0 && file.selectedIndex < file.entries.len() ? file.entries[ file.selectedIndex ].source : 0
	ModBrowser_SetSourceBadge( file.menu, "DetailsSource", source, visible )
}

void function ClearDetails()
{
	SetPreviewVisible( false )
	file.selectedIndex = -1
	file.selectedId = ""
	SetScaledTitle( Hud_GetChild( file.menu, "DetailsName" ), Localize( "#MOD_BROWSER_SELECT_MOD" ), 460.0 )
	Hud_SetText( Hud_GetChild( file.menu, "DetailsAuthor" ), "" )
	SetDetailsDescription( "" )
	Hud_SetText( Hud_GetChild( file.menu, "DetailsStatus" ), "" )
	Hud_SetText( Hud_GetChild( file.menu, "ProgressLabel" ), "" )
}

string function GetDownloadCountText( int downloads )
{
	return Localize(
		downloads == 1 ? "#MOD_BROWSER_DOWNLOAD_COUNT_ONE" : "#MOD_BROWSER_DOWNLOAD_COUNT_MANY",
		string( downloads )
	)
}

string function GetCardStatus( ModBrowserPageEntry entry )
{
	return GetDownloadCountText( entry.downloads )
}

string function GetAuthorText( string author, string version )
{
	if ( version == "" )
		return Localize( "#MOD_BROWSER_BY_AUTHOR", author )
	return Localize( "#MOD_BROWSER_BY_AUTHOR_VERSION", author, version )
}

string function GetOperationMessage( ModBrowserOperationSnapshot operation )
{
	if ( operation.message == "" )
		return ""
	if ( operation.state == eModBrowserInstallState.DOWNLOADING ||
		operation.state == eModBrowserInstallState.VALIDATING ||
		operation.state == eModBrowserInstallState.STAGING ||
		operation.state == eModBrowserInstallState.AWAITING_MIGRATION )
	{
		return Localize( operation.message, operation.name )
	}
	return Localize( operation.message )
}

string function GetOperationProgressText( ModBrowserOperationSnapshot operation )
{
	string progress = GetOperationMessage( operation )
	if ( operation.total > 0 )
		progress += Localize( "#MOD_BROWSER_PROGRESS_PERCENT", string( int( operation.ratio * 100.0 ) ) )
	if ( operation.cancellationDeferred )
		progress += Localize( "#MOD_BROWSER_CANCELLATION_DEFERRED_SUFFIX" )
	return progress
}

string function GetOperationDialogHeader( int action )
{
	switch ( action )
	{
		case eModBrowserInstallAction.UPDATE:
			return Localize( "#MOD_BROWSER_UPDATE_MOD" )
		case eModBrowserInstallAction.REPLACE:
			return Localize( "#MOD_BROWSER_DOWNLOAD_MOD" )
		case eModBrowserInstallAction.REMOVE:
			return Localize( "#MOD_BROWSER_REMOVE_MOD" )
	}
	return Localize( "#MOD_BROWSER_DOWNLOAD_MOD" )
}

bool function IsOperationBusy( int state )
{
	return ( state >= eModBrowserInstallState.QUEUED && state <= eModBrowserInstallState.RELOADING ) ||
		state == eModBrowserInstallState.AWAITING_MIGRATION
}

bool function IsOperationTerminal( int state )
{
	return state == eModBrowserInstallState.DONE || state == eModBrowserInstallState.FAILED || state == eModBrowserInstallState.CANCELLED
}


void function SetScaledTitle( var label, string text, float availableLogicalWidth )
{
	float screenScale = float( GetScreenSize()[ 0 ] ) / 1920.0
	int availableWidth = int( availableLogicalWidth * screenScale )
	label.SetScale( 1.0, 1.0 )
	Hud_SetWidth( label, int( float( availableWidth ) * MOD_BROWSER_TITLE_MAX_WIDTH_MULTIPLIER ) )
	Hud_SetText( label, text )
	int naturalWidth = Hud_GetTextWidth( label )
	if ( naturalWidth <= 0 )
	{
		Hud_SetWidth( label, availableWidth )
		return
	}
	Hud_SetWidth( label, naturalWidth )
	float scale = min( 1.0, float( availableWidth ) / float( naturalWidth ) )
	label.SetScale( scale, scale )
}

void function ScrollDetails( int direction )
{
	int maxOffset = maxint( 0, file.detailsLines.len() - MOD_BROWSER_DETAILS_VISIBLE_LINES )
	int nextOffset = minint( maxOffset, maxint( 0, file.detailsScrollOffset + direction ) )
	if ( nextOffset == file.detailsScrollOffset )
		return
	file.detailsScrollOffset = nextOffset
	RenderDetailsDescription()
}

void function SetDetailsDescription( string description )
{
	file.detailsLines = WrapDetailsText( description )
	file.detailsScrollOffset = 0
	RenderDetailsDescription()
}

array<string> function WrapDetailsText( string text )
{
	array<string> lines
	if ( text == "" )
		return lines

	array<string> paragraphs = split( text, "\n" )
	foreach ( string paragraph in paragraphs )
	{
		if ( paragraph == "" )
		{
			lines.append( "" )
			continue
		}

		array<string> words = split( paragraph, " " )
		string currentLine = ""
		foreach ( string paragraphWord in words )
		{
			if ( paragraphWord == "" )
				continue
			string word = paragraphWord
			while ( word.len() > MOD_BROWSER_DETAILS_LINE_WIDTH )
			{
				if ( currentLine != "" )
				{
					lines.append( currentLine )
					currentLine = ""
				}
				lines.append( word.slice( 0, MOD_BROWSER_DETAILS_LINE_WIDTH ) )
				word = word.slice( MOD_BROWSER_DETAILS_LINE_WIDTH, word.len() )
			}

			if ( currentLine == "" )
				currentLine = word
			else if ( currentLine.len() + 1 + word.len() <= MOD_BROWSER_DETAILS_LINE_WIDTH )
				currentLine += " " + word
			else
			{
				lines.append( currentLine )
				currentLine = word
			}
		}
		if ( currentLine != "" )
			lines.append( currentLine )
	}
	return lines
}

void function RenderDetailsDescription()
{
	string visibleText = ""
	int endLine = minint( file.detailsLines.len(), file.detailsScrollOffset + MOD_BROWSER_DETAILS_VISIBLE_LINES )
	for ( int lineIndex = file.detailsScrollOffset; lineIndex < endLine; lineIndex++ )
		visibleText += ( lineIndex == file.detailsScrollOffset ? "" : "\n" ) + file.detailsLines[ lineIndex ]
	Hud_SetText( Hud_GetChild( file.menu, "DetailsDescription" ), visibleText )
}

void function ModBrowser_LoadSourceImages()
{
	// Official provider artwork; rendering and placement belong to this mod.
	// ModWorkshop: https://modworkshop.net/assets/mws_logo_white.svg (rasterized).
	// Thunderstore: https://thunderstore.io/apple-touch-icon.png (background removed).
	// Provider marks identify the source; square image slots preserve their proportions.
	if ( file.sourceAtlas != 0 )
		return
	array<ScriptAtlasImage> images
	int stride = MOD_BROWSER_SOURCE_SIZE + MOD_BROWSER_SOURCE_GUTTER * 2
	array<string> names = [ "modworkshop", "thunderstore" ]
	foreach ( int slot, string name in names )
	{
		ScriptAtlasImage image
		image.name = "northstar/modbrowser/provider_" + name
		image.x = slot * stride + MOD_BROWSER_SOURCE_GUTTER
		image.y = MOD_BROWSER_SOURCE_GUTTER
		image.width = MOD_BROWSER_SOURCE_SIZE
		image.height = MOD_BROWSER_SOURCE_SIZE
		image.gutter = MOD_BROWSER_SOURCE_GUTTER
		images.append( image )
	}
	file.sourceAtlas = ScriptAtlasCreate( "northstar/modbrowser/providers", stride * names.len(), stride, images )
	foreach ( int slot, string name in names )
	{
		ScriptAtlasClearImage( file.sourceAtlas, slot, <0, 0, 0>, 0.0 )
		ScriptAtlasLoadImage( file.sourceAtlas, slot, "resource/modbrowser/" + name + ".png", "", eScriptAtlasFit.CONTAIN )
	}
}

string function ModBrowser_GetSourceName( int source )
{
	if ( source == 2 )
		return Localize( "#MODS_SOURCE_MODWORKSHOP" )
	if ( source == 3 )
		return Localize( "#MODS_SOURCE_THUNDERSTORE" )
	return ""
}

void function ModBrowser_SetSourceBadge( var panel, string prefix, int source, bool visible )
{
	visible = visible && ( source == 2 || source == 3 )
	var image = Hud_GetChild( panel, prefix + "Badge" )
	Hud_SetVisible( image, visible )
	if ( visible )
		RuiSetImage( Hud_GetRui( image ), "basicImage", ScriptAtlasGetImage( file.sourceAtlas, source == 2 ? 0 : 1 ) )
}
