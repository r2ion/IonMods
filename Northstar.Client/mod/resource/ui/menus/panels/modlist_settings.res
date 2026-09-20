resource/ui/menus/panels/modlist_settings.res
{


	ModIcon
	{
		ControlName RuiPanel
		xpos 0
		ypos 6
		wide 176
		tall 98
		visible 0
		scaleImage 1
		zpos 2
		rui "ui/basic_image.rpak"
	}

	SourceBadge
	{
		ControlName RuiPanel
		xpos 8
		ypos 79
		wide 16
		tall 16
		visible 0
		scaleImage 1
		rui "ui/basic_image.rpak"
		zpos 8
	}

	MetadataBackground
	{
		ControlName RuiPanel
		xpos 0
		ypos 104
		wide 176
		tall 72
		visible 1
		zpos 3
		rui "ui/knowledgebase_panel.rpak"
	}

	ModName
	{
		ControlName Label
		xpos 7
		ypos 107
		wide 162
		tall 18
		labelText ""
		font Default_16
		wrap 0
		fgcolor_override "255 255 255 255"
		zpos 5
	}

	ModVersion
	{
		ControlName Label
		xpos 7
		ypos 125
		wide 162
		tall 18
		labelText ""
		font Default_16
		fgcolor_override "154 164 174 220"
		zpos 5
	}

	ModStatus
	{
		ControlName Label
		xpos 7
		ypos 143
		wide 162
		tall 18
		labelText ""
		font Default_16
		fgcolor_override "176 185 194 255"
		zpos 5
	}

	StateBar
	{
		ControlName RuiPanel
		xpos 0
		ypos 0
		wide 176
		tall 6
		visible 1
		scaleImage 1
		zpos 30
		rui "ui/basic_image.rpak"
	}

	EnabledImage
	{
		ControlName RuiPanel
		xpos 8
		ypos 12
		wide 22
		tall 22
		visible 0
		scaleImage 1
		zpos 9
		rui "ui/basic_image.rpak"
	}

	WarningImage
	{
		ControlName RuiPanel
		xpos 146
		ypos 12
		wide 22
		tall 22
		visible 0
		scaleImage 1
		zpos 9
		rui "ui/basic_image.rpak"
	}

	UpdateBadge
	{
		ControlName Label
		xpos 48
		ypos 12
		wide 80
		tall 22
		labelText "#MOD_BROWSER_ACTION_UPDATE"
		font Default_16
		allcaps 1
		textAlignment center
		fgcolor_override "255 255 255 255"
		bgcolor_override "137 180 202 230"
		paintbackground 1
		visible 0
		zpos 10
	}

	BtnMod
	{
		ControlName RuiButton
		InheritProperties RuiSmallButton
		classname ModButton
		xpos 0
		ypos 0
		wide 176
		tall 176
		labelText ""
		zpos 40
	}
}
