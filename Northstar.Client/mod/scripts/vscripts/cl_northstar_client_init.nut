global enum eDiscordGameState
{
	LOADING = 0
	MAINMENU
	LOBBY
	INGAME
}

global struct GameStateStruct
{
	string map
	string mapDisplayname

	string playlist
	string playlistDisplayname

	int currentPlayers
	int maxPlayers
	int ownScore
	int otherHighestScore
	int maxScore
	float timeEnd
	int serverGameState
	int fd_waveNumber
	int fd_totalWaves
	bool is_vanilla
}

global struct UIPresenceStruct
{
	int gameState
	bool is_vanilla
	bool in_party
	int party_size
	int party_max_players
}

global struct ScriptAtlasImage
{
	string name
	int x
	int y
	int width
	int height
	int gutter
}

global enum eScriptAtlasFit
{
	COVER = 0
	CONTAIN
	STRETCH
}

global enum eScriptAtlasImageState
{
	EMPTY = 0
	LOADING
	READY
	FAILED
}

global struct ModInfo
{
	string name = ""
	string description = ""
	string version = ""
	string downloadLink = ""
	int loadPriority = 0
	bool enabled = false
	bool requiredOnClient = false
	bool isRemote
	array<string> conVars = []
	string managedId = ""
	int source = 0
	int updateState = 0
	bool canDelete = false
	int deleteModCount = 0
	int index = -1
	bool hasIcon = false
	array<string> assets = []
	string iconPath = ""
	string iconUrl = ""
	string iconVersion = ""
	string iconFallbackUrl = ""
}

global struct RequiredModInfo
{
	string name
	string version
}

global struct ServerInfo
{
	int index
	string id
	string name
	string description
	string map
	string playlist
	int playerCount
	int maxPlayerCount
	bool requiresPassword
	string region
	array<RequiredModInfo> requiredMods
}

global struct MasterServerAuthResult
{
	bool success
	string errorCode
	string errorMessage
}

global struct ModInstallState
{
	string name
	string version
	int status
	int progress
	int total
	float ratio
}

global enum eModBrowserLoadState
{
	IDLE = 0
	LOADING
	READY
	FAILED
	CANCELLED
}

global enum eModBrowserUpdateState
{
	LEGACY_UNKNOWN = 0
	CHECKING
	CURRENT
	UPDATE_AVAILABLE
	MISSING_REMOTE
	UNSUPPORTED
	ERROR
}

global enum eModBrowserInstallAction
{
	INSTALL = 0
	UPDATE
	REPLACE
	REMOVE
}

global enum eModBrowserInstallState
{
	IDLE = 0
	QUEUED
	FETCHING_DETAILS
	RESOLVING_DEPENDENCIES
	DOWNLOADING
	VALIDATING
	STAGING
	COMMITTING
	RELOADING
	DONE
	FAILED
	CANCELLED
	AWAITING_MIGRATION
}

global struct ModBrowserPageEntry
{
	string id
	string name
	string author
	string summary
	string version
	int downloads
	int likes
	int views
	string thumbnailUrl
	bool installed
	int updateState
	int operationState
	bool approved
	bool suspended
	string pageUrl
	bool canInstall
	string selectedFileId
	int source
	string thumbnailFallbackUrl
	string thumbnailVersion
}

global struct ModBrowserPageSnapshot
{
	int state
	int generation
	string search
	string sort
	int requestedPage
	int currentPage
	int lastPage
	int total
	bool fromCache
	string error
	array<ModBrowserPageEntry> entries
}

global struct ModBrowserDetailsSnapshot
{
	int state
	int generation
	string id
	string name
	string author
	string description
	string version
	string selectedFileId
	string selectedFileSize
	string selectedFileUpdatedAt
	int downloads
	int likes
	int views
	bool installed
	int updateState
	bool canInstall
	string pageUrl
	array<string> dependencies
	bool fromCache
	string error
	int source
}

global struct ModBrowserOperationSnapshot
{
	int generation
	string id
	int action
	int state
	string name
	string version
	string message
	int progress
	int total
	float ratio
	bool cancellationDeferred
}

global struct ModBrowserInventorySnapshot
{
	int generation
	int updateCount
	bool checking
	string checkedAt
	string error
	int packageCount
}
