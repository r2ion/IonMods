"resource/ui/menus/panels/modbrowser_card.res"
{
	Thumbnail
	{
		ControlName RuiPanel
		wide 176
		tall 109
		visible 1
		scaleImage 1
		zpos 0
		rui "ui/basic_image.rpak"
	}

	SourceBadge
	{
		ControlName RuiPanel
		xpos 8
		ypos 84
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
		wide 176
		tall 87
		ypos 109
		visible 1
		zpos 1
		rui "ui/knowledgebase_panel.rpak"
	}

	ModName
	{
		ControlName Label
		xpos 7
		ypos 110
		wide 162
		tall 30
		labelText "#MOD_BROWSER_CARD_MOD_NAME"
		font Default_18
		fgcolor_override "255 255 255 255"
		zpos 2
	}


	ModAuthor
	{
		ControlName Label
		xpos 7
		ypos 143
		wide 162
		tall 20
		labelText "#MOD_BROWSER_CARD_BY_AUTHOR"
		font Default_16
		fgcolor_override "154 164 174 220"
		zpos 2
	}

	ModStatus
	{
		ControlName Label
		xpos 7
		ypos 169
		wide 162
		tall 20
		labelText ""
		font Default_16
		fgcolor_override "118 132 144 195"
		zpos 2
	}
}
