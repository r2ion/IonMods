untyped
global function AddNorthstarCustomMatchSettingsMenu
global function AddCustomPrivateMatchSettingsCategory

struct SettingsListEntry
{
	int type // 0 = Header, 1 = Setting, 2 = CustomMenuLink
	string label
	CustomMatchSettingContainer& setting
	string customMenuName
}

struct
{
	int count = 0
	array<string> customCategoryMenus
	array<string> customCategoryLocalization

	int scrollOffset = 0
	var menu
	array<SettingsListEntry> settingsList

	table<string, int> enumRealValues

	table<string, table<string, float> > sliderConfigs = {
		scorelimit = { min = 1.0, max = 5000.0, step = 5.0 },
		roundscorelimit = { min = 0.0, max = 200.0, step = 1.0 },
		timelimit = { min = 1.0, max = 500.0, step = 1.0 },
		fd_wave_buy_time = { min = 0.0, max = 300.0, step = 5.0 },
		respawnprotection = { min = 0.0, max = 10.0, step = 0.5 },
		custom_air_accel_pilot = { min = 0.0, max = 10000.0, step = 1.0 },
		player_bleedout_firstAidTimeSelf = { min = -1.0, max = 30.0, step = 0.1 },
		pilot_health_multiplier = { min = 0.1, max = 5.0, step = 0.1 },
		titan_health_multiplier = { min = 0.1, max = 5.0, step = 0.1 },
		respawn_delay = { min = 0.0, max = 60.0, step = 1.0 },
		earn_meter_pilot_multiplier = { min = 0.1, max = 5.0, step = 0.1 },
		earn_meter_titan_multiplier = { min = 0.1, max = 5.0, step = 0.1 },
		boost_meter_multiplier = { min = 0.1, max = 5.0, step = 0.1 },
		player_force_respawn = { min = 0.0, max = 60.0, step = 1.0 }
	}

	table<string, string> dirtySettings
	table<string, string> localOverrides
	bool isMenuOpen = false
	bool isUpdatingUI = false
	float lastUpdateTime = 0.0
} file

const int ITEMS_PER_PAGE = 15

void function AddNorthstarCustomMatchSettingsMenu()
{
	// Use custom_match_settings.menu as it has the slider and list layout
	AddMenu( "CustomMatchSettingsMenu", $"resource/ui/menus/custom_match_settings.menu", InitNorthstarCustomMatchSettingsMenu, "#MENU_MATCH_SETTINGS" )
}

void function InitNorthstarCustomMatchSettingsMenu()
{
	file.menu = GetMenu( "CustomMatchSettingsMenu" )

	AddMenuEventHandler( file.menu, eUIEvent.MENU_OPEN, OnNorthstarCustomMatchSettingsMenuOpened )
	AddMenuEventHandler( file.menu, eUIEvent.MENU_CLOSE, OnNorthstarCustomMatchSettingsMenuClosed )

	AddMenuFooterOption( file.menu, BUTTON_B, "#B_BUTTON_BACK", "#BACK" )
	AddMenuFooterOption( file.menu, BUTTON_Y, "#Y_BUTTON_RESTORE_DEFAULTS", "#RESTORE_DEFAULTS", ResetMatchSettingsToDefault )

	AddButtonEventHandler( Hud_GetChild( file.menu, "PageButtonU" ), UIE_CLICK, OnUpArrowSelected )
	AddButtonEventHandler( Hud_GetChild( file.menu, "PageButtonD" ), UIE_CLICK, OnDownArrowSelected )

	AddButtonEventHandler( Hud_GetChild( file.menu, "DummyTop" ), UIE_GET_FOCUS, OnHitDummyTop )
	AddButtonEventHandler( Hud_GetChild( file.menu, "DummyBottom" ), UIE_GET_FOCUS, OnHitDummyBottom )

	AddCallback_InputEvent( InputEventType.IE_AnalogValueChanged, OnAnalogueScroll )

	array<var> buttons = GetElementsByClassname( file.menu, "MatchSettingPanel" )
	foreach ( var panel in buttons )
	{
		// AddEventHandlerToButton( panel, "BtnSwch", UIE_CLICK, OnSettingButtonPressed )
		AddEventHandlerToButton( panel, "BtnSwch", UIE_CHANGE, OnSettingButtonChanged )
		AddEventHandlerToButton( panel, "BtnSlide", UIE_CHANGE, OnSliderChanged )

		var slider = Hud_GetChild( panel, "BtnSlide" )
		var dropButton = Hud_GetChild( slider, "BtnDropButton" )
		if ( dropButton != null )
		{
			Hud_AddEventHandler(
				dropButton,
				UIE_CHANGE,
				void function( var _ ) : ( slider )
				{
					OnSliderChanged( slider )
				}
			)
		}

		var textEntry = Hud_GetChild( panel, "TextEntrySetting" )
		Hud_AddEventHandler( textEntry, UIE_LOSE_FOCUS, OnTextEntryChanged )
	}

	// Hide unused elements
	Hud_SetVisible( Hud_GetChild( file.menu, "BtnModeLabel" ), false )
	Hud_SetVisible( Hud_GetChild( file.menu, "BtnModeSearch" ), false )
	Hud_SetVisible( Hud_GetChild( file.menu, "SwtModeLabel" ), false )

	Hud_SetVisible( Hud_GetChild( file.menu, "NextModeImageFrame" ), false )
	Hud_SetVisible( Hud_GetChild( file.menu, "NextModeImage" ), false )
	Hud_SetVisible( Hud_GetChild( file.menu, "ModeIconImage" ), false )
	Hud_SetVisible( Hud_GetChild( file.menu, "NextModeName" ), false )
	Hud_SetVisible( Hud_GetChild( file.menu, "NextModeDesc" ), false )
}

void function OnNorthstarCustomMatchSettingsMenuOpened()
{
	file.isMenuOpen = true
	file.localOverrides.clear()
	// RegisterButtonPressedCallback( MOUSE_WHEEL_UP , OnScrollUp )
	// RegisterButtonPressedCallback( MOUSE_WHEEL_DOWN , OnScrollDown )

	BuildSettingsList()

	file.scrollOffset = 0
	UpdateVisibleSettings()
	UpdateListSliderPosition()
	array<var> panels = GetElementsByClassname( file.menu, "MatchSettingPanel" )
	var firstControl = GetFirstFocusableSettingControl( panels )
	if ( firstControl != null )
		Hud_SetFocused( firstControl )

	thread SliderUpdateMonitor()
}

void function OnNorthstarCustomMatchSettingsMenuClosed()
{
	file.isMenuOpen = false
	// DeregisterButtonPressedCallback( MOUSE_WHEEL_UP , OnScrollUp )
	// DeregisterButtonPressedCallback( MOUSE_WHEEL_DOWN , OnScrollDown )
}

var function GetFirstFocusableSettingControl( array<var> panels )
{
	for ( int i = 0; i < ITEMS_PER_PAGE; i++ )
	{
		if ( i + file.scrollOffset >= file.settingsList.len() )
			break

		SettingsListEntry entry = file.settingsList[ i + file.scrollOffset ]
		if ( entry.type == 0 )
			continue

		var panel = panels[ i ]
		if ( !Hud_IsVisible( panel ) || !Hud_IsEnabled( panel ) )
			continue

		var switchButton = Hud_GetChild( panel, "BtnSwch" )
		var slider = Hud_GetChild( panel, "BtnSlide" )
		return Hud_IsVisible( slider ) ? slider : switchButton
	}

	return null
}

var function GetLastFocusableSettingControl( array<var> panels )
{
	for ( int i = ITEMS_PER_PAGE - 1; i >= 0; i-- )
	{
		if ( i + file.scrollOffset >= file.settingsList.len() )
			continue

		SettingsListEntry entry = file.settingsList[ i + file.scrollOffset ]
		if ( entry.type == 0 )
			continue

		var panel = panels[ i ]
		if ( !Hud_IsVisible( panel ) || !Hud_IsEnabled( panel ) )
			continue

		var switchButton = Hud_GetChild( panel, "BtnSwch" )
		var slider = Hud_GetChild( panel, "BtnSlide" )
		return Hud_IsVisible( slider ) ? slider : switchButton
	}

	return null
}

void function OnHitDummyTop( var button )
{
	file.scrollOffset -= 1
	if ( file.scrollOffset < 0 )
	{
		file.scrollOffset = 0
	}
	else
	{
		UpdateVisibleSettings()
	}

	array<var> panels = GetElementsByClassname( file.menu, "MatchSettingPanel" )
	var firstControl = GetFirstFocusableSettingControl( panels )
	if ( firstControl != null )
		Hud_SetFocused( firstControl )
}

void function OnHitDummyBottom( var button )
{
	file.scrollOffset += 1
	int maxOffset = max( 0, file.settingsList.len() - ITEMS_PER_PAGE ).tointeger()
	if ( file.scrollOffset > maxOffset )
	{
		file.scrollOffset = maxOffset
	}
	else
	{
		UpdateVisibleSettings()
	}

	array<var> panels = GetElementsByClassname( file.menu, "MatchSettingPanel" )
	var lastControl = GetLastFocusableSettingControl( panels )
	if ( lastControl != null )
		Hud_SetFocused( lastControl )
}

int function GetCategoryPriority( string cat )
{
	string selected = "#PL_" + PrivateMatch_GetSelectedMode()

	switch ( cat )
	{
		case selected:
			return 0

		case "#MODE_SETTING_CATEGORY_MATCH":
			return 1

		case "#MODE_SETTING_CATEGORY_PILOT":
			return 2

		case "#MODE_SETTING_CATEGORY_TITAN":
			return 3

		default:
			return 100
	}

	unreachable
}

int function SortPrivateMatchSettingsCategories( string a, string b )
{
	int pa = GetCategoryPriority( a )
	int pb = GetCategoryPriority( b )

	if ( pa < pb )
		return -1
	if ( pa > pb )
		return 1

	string la = Localize( a )
	string lb = Localize( b )
	if ( la < lb )
		return -1
	if ( la > lb )
		return 1
	return 0
}

void function BuildSettingsList()
{
	file.settingsList.clear()
	file.enumRealValues.clear()

	// Custom Categories (Links)
	for ( int i = 0; i < file.count; i++ )
	{
		SettingsListEntry entry
		entry.type = 2
		entry.label = file.customCategoryLocalization[ i ]
		entry.customMenuName = file.customCategoryMenus[ i ]
		file.settingsList.append( entry )
	}

	// Standard Categories
	array<string> categories = GetPrivateMatchSettingCategories()
	categories.sort( SortPrivateMatchSettingsCategories )

	foreach ( string category in categories )
	{
		// Add Header
		SettingsListEntry header
		header.type = 0
		header.label = category
		file.settingsList.append( header )

		// Add Settings
		array<CustomMatchSettingContainer> settings = GetPrivateMatchCustomSettingsForCategory( category )
		foreach ( CustomMatchSettingContainer setting in settings )
		{
			if ( setting.playlistVar in file.sliderConfigs )
			{
				setting.isSlider = true
				setting.min = file.sliderConfigs[ setting.playlistVar ].min
				setting.max = file.sliderConfigs[ setting.playlistVar ].max
				setting.step = file.sliderConfigs[ setting.playlistVar ].step
			}
			else if ( !setting.isEnumSetting )
			{
				setting.isSlider = true
				setting.min = 0.0
				setting.max = 100.0
				setting.step = 1.0

				// Simple heuristic for small float values (likely multipliers)
				if ( setting.defaultValue.find( "." ) != null )
				{
					float val = float( setting.defaultValue )
					if ( val <= 10.0 )
					{
						setting.max = 10.0
						setting.step = 0.1
					}
				}
			}

			SettingsListEntry item
			item.type = 1
			item.setting = setting
			file.settingsList.append( item )

			// Initialize enum state
			if ( setting.isEnumSetting )
			{
				string gamemodeVar = GetGamemodeVarOrUseValue( PrivateMatch_GetSelectedMode(), setting.playlistVar, setting.defaultValue )
				string playlistVar = string( GetCurrentPlaylistVarOrUseValue( setting.playlistVar, setting.defaultValue ) )

				if ( playlistVar != gamemodeVar && playlistVar == setting.defaultValue )
					playlistVar = gamemodeVar

				int enumIndex = int( max( 0, setting.enumValues.find( playlistVar ) ) )
				file.enumRealValues[ setting.playlistVar ] <- enumIndex
			}
		}
	}
}

void function UpdateVisibleSettings()
{
	file.isUpdatingUI = true
	file.lastUpdateTime = Time()
	array<var> buttons = GetElementsByClassname( file.menu, "MatchSettingPanel" )
	foreach ( var panel in buttons )
	{
		Hud_SetEnabled( panel, false )
		Hud_SetVisible( panel, false )
	}

	var pageButtonUp = Hud_GetChild( file.menu, "PageButtonU" )
	var pageButtonD = Hud_GetChild( file.menu, "PageButtonD" )
	var dummyTop = Hud_GetChild( file.menu, "DummyTop" )
	var dummyBottom = Hud_GetChild( file.menu, "DummyBottom" )

	bool canScrollUp = file.scrollOffset > 0
	bool canScrollDown = ( file.scrollOffset + ITEMS_PER_PAGE ) < file.settingsList.len()
	Hud_SetEnabled( dummyTop, canScrollUp )
	Hud_SetEnabled( dummyBottom, canScrollDown )

	if ( file.scrollOffset <= 0 )
		Hud_SetVisible( pageButtonUp, false )
	else
		Hud_SetVisible( pageButtonUp, true )

	if ( ( file.scrollOffset + ITEMS_PER_PAGE ) >= file.settingsList.len() )
		Hud_SetVisible( pageButtonD, false )
	else
		Hud_SetVisible( pageButtonD, true )

	for ( int i = 0; i < ITEMS_PER_PAGE; i++ )
	{
		if ( i + file.scrollOffset >= file.settingsList.len() )
			break

		var panel = buttons[ i ]
		var button = Hud_GetChild( panel, "BtnSwch" )
		var header = Hud_GetChild( panel, "Header" )
		var menuline = Hud_GetChild( panel, "BottomLine" )

		var slider = Hud_GetChild( panel, "BtnSlide" )
		var textEntry = Hud_GetChild( panel, "TextEntrySetting" )

		SettingsListEntry entry = file.settingsList[ i + file.scrollOffset ]

		Hud_SetEnabled( panel, true )
		Hud_SetVisible( panel, true )
		Hud_SetVisible( slider, false ) // Hide slider by default
		Hud_SetVisible( textEntry, false )

		if ( entry.type == 0 ) // Header
		{
			Hud_SetVisible( menuline, true )
			Hud_SetVisible( button, false )
			Hud_SetVisible( slider, false )
			Hud_SetVisible( header, true )
			Hud_SetText( header, Localize( entry.label ) )
		}
		else if ( entry.type == 2 ) // Link
		{
			Hud_SetVisible( menuline, false )
			Hud_SetVisible( button, true )
			Hud_SetEnabled( button, true )
			Hud_SetVisible( slider, false )
			Hud_SetVisible( header, false )
			SetButtonRuiText( button, Localize( entry.label ) + " ->" )
		}
		else if ( entry.type == 1 ) // Setting
		{
			Hud_SetVisible( menuline, false )
			Hud_SetVisible( header, false )

			CustomMatchSettingContainer setting = entry.setting

			if ( setting.isSlider )
			{
				Hud_SetVisible( button, false )
				Hud_SetVisible( slider, true )
				Hud_SetVisible( textEntry, true )
				Hud_SetEnabled( slider, true )
				Hud_SetEnabled( textEntry, true )

				string playlistVar
				if ( setting.playlistVar in file.localOverrides )
					playlistVar = file.localOverrides[ setting.playlistVar ]
				else
					playlistVar = string( GetCurrentPlaylistVarOrUseValue( setting.playlistVar, setting.defaultValue ) )

				float val = float( playlistVar )

				Hud_SliderControl_SetMin( slider, val )
				Hud_SliderControl_SetMax( slider, val )
				Hud_SliderControl_SetMin( slider, setting.min )
				Hud_SliderControl_SetMax( slider, setting.max )
				Hud_SliderControl_SetStepSize( slider, setting.step )

				var dropButton = Hud_GetChild( slider, "BtnDropButton" )
				if ( dropButton != null )
				{
					string displayValue = string( val )
					if ( val == int( val ) )
						displayValue = string( int( val ) )
					else
						displayValue = format( "%.2f", val )

					SetButtonRuiText( dropButton, Localize( setting.localizedName ) )
					Hud_SetText( textEntry, displayValue )
				}

				Hud_HandleEvent( slider, UIE_CHANGE )
			}
			else
			{
				Hud_SetVisible( button, true )
				Hud_SetEnabled( button, true )
				Hud_SetVisible( slider, false )

				string displayValue = ""

				if ( setting.isEnumSetting )
				{
					Hud_DialogList_RemoveListItems( button )
					foreach ( int i, name in setting.enumNames )
					{
						Hud_DialogList_AddListItem( button, Localize( name ), setting.enumValues[ i ] )
					}

					string gamemodeVar = GetGamemodeVarOrUseValue( PrivateMatch_GetSelectedMode(), setting.playlistVar, setting.defaultValue )
					string playlistVar
					if ( setting.playlistVar in file.localOverrides )
						playlistVar = file.localOverrides[ setting.playlistVar ]
					else
						playlistVar = string( GetCurrentPlaylistVarOrUseValue( setting.playlistVar, setting.defaultValue ) )

					if ( setting.playlistVar.len() != 0 )
					{
						int gamemodeIdx = expect int( level.ui.privatematch_mode )
						Hud_SetGamemodeIdx( button, gamemodeIdx )
						Hud_SetPlaylistVarName( button, setting.playlistVar )
					}

					if ( gamemodeVar.find( "." ) != null )
						gamemodeVar = string( int( float( gamemodeVar ) ) )
					if ( playlistVar.find( "." ) != null )
						playlistVar = string( int( float( playlistVar ) ) )

					if ( !( setting.playlistVar in file.localOverrides ) && playlistVar != gamemodeVar && playlistVar == setting.defaultValue )
						playlistVar = gamemodeVar

					Hud_SetDialogListSelectionValue( button, playlistVar )

					int valIndex = setting.enumValues.find( playlistVar )
					string valName = ( valIndex != -1 ) ? setting.enumNames[ valIndex ] : playlistVar
					SetButtonRuiText( button, Localize( setting.localizedName ) )
				}
			}
		}
	}

	array<var> focusableControls
	for ( int i = 0; i < ITEMS_PER_PAGE; i++ )
	{
		if ( i + file.scrollOffset >= file.settingsList.len() )
			break

		SettingsListEntry entry = file.settingsList[ i + file.scrollOffset ]
		if ( entry.type == 0 ) // headers are not focusable
			continue

		var panel = buttons[ i ]
		var switchButton = Hud_GetChild( panel, "BtnSwch" )
		var slider = Hud_GetChild( panel, "BtnSlide" )
		var control = Hud_IsVisible( slider ) ? slider : switchButton
		focusableControls.append( control )
	}

	for ( int i = 0; i < focusableControls.len(); i++ )
	{
		var current = focusableControls[ i ]
		var prev = ( i > 0 ) ? focusableControls[ i - 1 ] : null
		var next = ( i < focusableControls.len() - 1 ) ? focusableControls[ i + 1 ] : null

		if ( prev != null )
			current.SetNavUp( prev )
		else
			current.SetNavUp( dummyTop )

		if ( next != null )
			current.SetNavDown( next )
		else
			current.SetNavDown( dummyBottom )
	}
	UpdateListSliderPosition()
	file.isUpdatingUI = false
}

void function UpdateListSliderPosition()
{
	var sliderButton = Hud_GetChild( file.menu, "BtnModeListSlider" )
	var sliderPanel = Hud_GetChild( file.menu, "BtnModeListSliderPanel" )

	int items = file.settingsList.len()
	if ( items <= ITEMS_PER_PAGE )
		return

	float minYPos = -42.0 * ( GetScreenSize()[ 1 ] / 1080.0 )
	float useableSpace = ( 599.0 * ( GetScreenSize()[ 1 ] / 1080.0 ) - Hud_GetHeight( sliderPanel ) )

	float jump = minYPos - ( useableSpace / ( float( items ) - float( ITEMS_PER_PAGE ) ) * file.scrollOffset )

	if ( jump > minYPos )
		jump = minYPos

	Hud_SetPos( sliderButton, 342, jump )
	Hud_SetPos( sliderPanel, 342, jump )
}

void function OnSettingButtonChanged( var button )
{
	// if ( file.isUpdatingUI )
	// 	return

	// if ( Time() - file.lastUpdateTime < 0.5 )
	// 	return

	int index = int( Hud_GetScriptID( Hud_GetParent( button ) ) ) + file.scrollOffset - 1

	if ( index >= file.settingsList.len() )
		return

	SettingsListEntry entry = file.settingsList[ index ]
	if ( entry.type != 1 )
		return

	CustomMatchSettingContainer setting = entry.setting

	if ( setting.isEnumSetting )
	{
		string val = Hud_GetDialogListSelectionValue( button )

		string currentVal
		if ( setting.playlistVar in file.localOverrides )
			currentVal = file.localOverrides[ setting.playlistVar ]
		else
			currentVal = string( GetCurrentPlaylistVarOrUseValue( setting.playlistVar, setting.defaultValue ) )

		string gamemodeVar = GetGamemodeVarOrUseValue( PrivateMatch_GetSelectedMode(), setting.playlistVar, setting.defaultValue )

		if ( !( setting.playlistVar in file.localOverrides ) )
		{
			if ( gamemodeVar.find( "." ) != null )
				gamemodeVar = string( int( float( gamemodeVar ) ) )
			if ( currentVal.find( "." ) != null )
				currentVal = string( int( float( currentVal ) ) )

			if ( currentVal != gamemodeVar && currentVal == setting.defaultValue )
				currentVal = gamemodeVar
		}

		string normVal = val
		string normCurrentVal = currentVal

		if ( normVal.find( "." ) != null )
			normVal = string( int( float( normVal ) ) )
		if ( normCurrentVal.find( "." ) != null )
			normCurrentVal = string( int( float( normCurrentVal ) ) )

		if ( normVal == normCurrentVal )
			return

		ClientCommand( "PrivateMatchSetPlaylistVarOverride " + setting.playlistVar + " " + val )
		file.localOverrides[ setting.playlistVar ] <- val

		int valIndex = setting.enumValues.find( val )
		string valName = ( valIndex != -1 ) ? setting.enumNames[ valIndex ] : val
		SetButtonRuiText( button, Localize( setting.localizedName ) )
	}
}

void function OnSliderChanged( var slider )
{
	// if ( file.isUpdatingUI )
	// 	return

	// if ( Time() - file.lastUpdateTime < 0.5 )
	// 	return

	int index = int( Hud_GetScriptID( Hud_GetParent( slider ) ) ) + file.scrollOffset - 1

	if ( index >= file.settingsList.len() )
		return

	SettingsListEntry entry = file.settingsList[ index ]
	if ( entry.type != 1 )
		return

	CustomMatchSettingContainer setting = entry.setting
	float val = Hud_SliderControl_GetCurrentValue( slider )

	string currentValStr = string( GetCurrentPlaylistVarOrUseValue( setting.playlistVar, setting.defaultValue ) )
	float currentVal = float( currentValStr )
	if ( fabs( val - currentVal ) < 0.001 )
		return

	string displayValue = string( val )
	if ( val == int( val ) )
		displayValue = string( int( val ) )
	else
		displayValue = format( "%.2f", val )

	var dropButton = Hud_GetChild( slider, "BtnDropButton" )
	if ( dropButton != null )
	{
		SetButtonRuiText( dropButton, Localize( setting.localizedName ) )
	}

	var panel = Hud_GetParent( slider )
	var textEntry = Hud_GetChild( panel, "TextEntrySetting" )
	Hud_SetText( textEntry, displayValue )

	file.dirtySettings[ setting.playlistVar ] <- displayValue
	file.localOverrides[ setting.playlistVar ] <- displayValue
}

void function SliderUpdateMonitor()
{
	while ( file.isMenuOpen )
	{
		foreach ( string varName, string val in file.dirtySettings )
		{
			ClientCommand( "PrivateMatchSetPlaylistVarOverride " + varName + " " + val )
		}
		file.dirtySettings.clear()
		Wait( 0.1 )
	}
}

void function OnSettingButtonPressed( var button )
{
	int index = int( Hud_GetScriptID( Hud_GetParent( button ) ) ) + file.scrollOffset - 1

	if ( index >= file.settingsList.len() )
		return

	SettingsListEntry entry = file.settingsList[ index ]

	if ( entry.type == 2 )
	{
		AdvanceMenu( GetMenu( entry.customMenuName ) )
	}
}

void function ResetMatchSettingsToDefault( var button )
{
	ClientCommand( "ResetMatchSettingsToDefault" )
	file.localOverrides.clear()
	thread ResetMatchSettingsToDefault_RefreshUI()
}

// i don't like this
void function ResetMatchSettingsToDefault_RefreshUI()
{
	Wait( 0.15 )
	UpdateVisibleSettings()
	Wait( 0.15 )
	UpdateVisibleSettings()
}

void function AddCustomPrivateMatchSettingsCategory( string menuLocalization, string menuName )
{
	file.count++
	file.customCategoryMenus.append( menuName )
	file.customCategoryLocalization.append( menuLocalization )
}

void function OnAnalogueScroll( int eventType, int nTick, int nData, int nData2, int nData3 )
{
	if ( uiGlobal.activeMenu != file.menu )
		return

	if ( nData == AnalogCode.MOUSE_WHEEL )
	{
		int scrollDirection = nData3

		if ( scrollDirection > 0 )
		{
			OnScrollUp( null )
		}
		else if ( scrollDirection < 0 )
		{
			OnScrollDown( null )
		}
	}
}

void function OnScrollDown( var button )
{
	if ( file.settingsList.len() <= ITEMS_PER_PAGE )
		return
	file.scrollOffset += 1
	if ( file.scrollOffset + ITEMS_PER_PAGE > file.settingsList.len() )
	{
		file.scrollOffset = file.settingsList.len() - ITEMS_PER_PAGE
	}
	UpdateVisibleSettings()
	UpdateListSliderPosition()
}

void function OnScrollUp( var button )
{
	file.scrollOffset -= 1
	if ( file.scrollOffset < 0 )
	{
		file.scrollOffset = 0
	}
	UpdateVisibleSettings()
	UpdateListSliderPosition()
}

void function OnDownArrowSelected( var button )
{
	if ( file.settingsList.len() <= ITEMS_PER_PAGE )
		return
	file.scrollOffset += 1
	if ( file.scrollOffset + ITEMS_PER_PAGE > file.settingsList.len() )
	{
		file.scrollOffset = file.settingsList.len() - ITEMS_PER_PAGE
	}

	UpdateVisibleSettings()
	UpdateListSliderPosition()
}

void function OnUpArrowSelected( var button )
{
	file.scrollOffset -= 1
	if ( file.scrollOffset < 0 )
	{
		file.scrollOffset = 0
	}

	UpdateVisibleSettings()
	UpdateListSliderPosition()
}

void function OnTextEntryChanged( var textEntry )
{
	if ( file.isUpdatingUI )
		return

	var panel = Hud_GetParent( textEntry )
	int index = int( Hud_GetScriptID( panel ) ) + file.scrollOffset - 1

	if ( index >= file.settingsList.len() )
		return

	SettingsListEntry entry = file.settingsList[ index ]
	if ( entry.type != 1 )
		return

	CustomMatchSettingContainer setting = entry.setting
	if ( !setting.isSlider )
		return

	string newSetting = Hud_GetUTF8Text( textEntry )

	try
	{
		float val = newSetting.tofloat()

		if ( val < setting.min )
			val = setting.min
		if ( val > setting.max )
			val = setting.max

		var slider = Hud_GetChild( panel, "BtnSlide" )

		string currentValStr = string( GetCurrentPlaylistVarOrUseValue( setting.playlistVar, setting.defaultValue ) )
		float currentVal = float( currentValStr )

		if ( fabs( val - currentVal ) < 0.001 )
			return

		string displayValue = string( val )
		if ( val == int( val ) )
			displayValue = string( int( val ) )
		else
			displayValue = format( "%.2f", val )

		Hud_SetText( textEntry, displayValue )

		Hud_SliderControl_SetMin( slider, val )
		Hud_SliderControl_SetMax( slider, val )
		Hud_SliderControl_SetMin( slider, setting.min )
		Hud_SliderControl_SetMax( slider, setting.max )

		var dropButton = Hud_GetChild( slider, "BtnDropButton" )
		if ( dropButton != null )
		{
			SetButtonRuiText( dropButton, Localize( setting.localizedName ) + ": " + displayValue )
		}

		file.dirtySettings[ setting.playlistVar ] <- displayValue
		file.localOverrides[ setting.playlistVar ] <- displayValue
	}
	catch ( ex )
	{
		string playlistVar
		if ( setting.playlistVar in file.localOverrides )
			playlistVar = file.localOverrides[ setting.playlistVar ]
		else
			playlistVar = string( GetCurrentPlaylistVarOrUseValue( setting.playlistVar, setting.defaultValue ) )

		Hud_SetText( textEntry, playlistVar )
	}
}
