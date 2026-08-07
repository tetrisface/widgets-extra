local PlayerStatsFactory = {}

local PLAYER_COLOR_FALLBACKS = {
	"#0066FF", "#FFCC00", "#FF3333", "#FF00CC", "#9966FF", "#33FFCC",
	"#CC6600", "#FFFFFF", "#00CC66", "#00CCCC", "#FF9966", "#66FF00",
}
local DEFAULT_PLAYER_COLOR = "#FFFFFF"

local function StableIndex(value, count)
	local text = tostring(value or "")
	local hash = 0
	for index = 1, #text do
		hash = (hash * 33 + string.byte(text, index)) % 2147483647
	end
	return (hash % count) + 1
end

local function PlayerId(player)
	return player and (player.player_id or player.playerId or player.account_id or player.accountId)
end

local function PlayerColor(player, colorLookup)
	local lookup = colorLookup or {}
	local name = player and player.player_name
	local id = PlayerId(player)
	local color = lookup[name] or lookup[tostring(name or "")] or lookup[id] or lookup[tostring(id or "")]
	if color and string.match(tostring(color), "^#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$") then
		return tostring(color)
	end
	return PLAYER_COLOR_FALLBACKS[StableIndex(name or id or "player", #PLAYER_COLOR_FALLBACKS)] or DEFAULT_PLAYER_COLOR
end

local function ToSet(values)
	local set = {}
	for _, value in ipairs(values or {}) do
		set[value] = true
		set[tostring(value)] = true
	end
	return set
end

local function AccomplishmentGroup(player, group)
	local accomplishments = player and player.accomplishments
	local value = accomplishments and accomplishments[group]
	return type(value) == "table" and value or {}
end

local function AwardGroup(player, group)
	local awards = player and player.awards
	local value = awards and awards[group]
	return type(value) == "table" and value or {}
end

local function CurrentAiColumn(request)
	local aiType = string.lower(tostring(request and request.ai_type or ""))
	if aiType == "scavengers" then
		return 2
	end
	if aiType == "barbarian" then
		return 3
	end
	return 1
end

local DEFINITIONS = {
	setup = {
		labels = {"Setup Clears", "Setup Plays", "PvE Games"},
		help = {
			"Eligible victories with this exact effective setup and encounter context. Similar settings never contribute.",
			"Eligible games with this exact effective setup and encounter context, regardless of outcome.",
			"All curated PvE games played in this mode.",
		},
		values = function(player)
			local participation = AccomplishmentGroup(player, "participation")
			return {player.setup_clears, player.setup_plays, participation.games_played}
		end,
		defaultSortColumn = function() return 1 end,
	},
	adventures = {
		labels = {"Games", "Victories", "Maps"},
		help = {
			"All curated PvE games played in this mode.",
			"All curated PvE victories in this mode.",
			"Distinct maps played in this mode.",
		},
		values = function(player)
			local participation = AccomplishmentGroup(player, "participation")
			return {participation.games_played, participation.victories, participation.distinct_maps_played}
		end,
		defaultSortColumn = function() return 2 end,
	},
	-- "Defeated", not "killed": these count the lobby's configured enemy count
	-- credited on a win, never per-player kill attribution. The totals cannot
	-- tell one enormous victory from many small ones, which is what the max
	-- columns beside them are for.
	encounters = {
		labels = {"Queens Defeated", "Bosses Defeated", "BARbarians Defeated", "Max Queens", "Max Bosses", "Max BARbarians"},
		help = {
			"Total Raptor queens defeated in victories.",
			"Total Scavenger bosses defeated in victories.",
			"Total Barbarian AI opponents defeated in victories.",
			"Most Raptor queens defeated in a single victory.",
			"Most Scavenger bosses defeated in a single victory.",
			"Most Barbarian AI opponents defeated in a single victory.",
		},
		values = function(player)
			local encounters = AccomplishmentGroup(player, "encounters")
			local bests = AccomplishmentGroup(player, "personal_bests")
			return {
				encounters.raptor_queens_defeated,
				encounters.scavenger_bosses_defeated,
				encounters.barbarian_ais_defeated,
				bests.max_queens_one_victory,
				bests.max_bosses_one_victory,
				bests.max_barbarian_ais_one_victory,
			}
		end,
		defaultSortColumn = CurrentAiColumn,
	},
	milestones = {
		labels = {"20+ Clears", "25+ Clears", "30+ Clears"},
		help = {
			"Eligible wins at governed challenge 20 or above: modeled population win chance at most 41.2%.",
			"Eligible wins at governed challenge 25 or above: modeled population win chance at most 26.5%.",
			"Eligible wins at governed challenge 30 or above: modeled population win chance at most 11.8%.",
		},
		values = function(player)
			local challenges = AccomplishmentGroup(player, "challenges")
			return {challenges.challenge_20_clears, challenges.challenge_25_clears, challenges.challenge_30_clears}
		end,
		defaultSortColumn = function() return 1 end,
	},
	awards = {
		labels = {"Raptor Most Killed", "Scav Most Killed", "BARb Most Killed"},
		help = {
			"Times this player earned Most Killed against Raptors by ranking first in fighting-unit value destroyed.",
			"Times this player earned Most Killed against Scavengers by ranking first in fighting-unit value destroyed.",
			"Times this player earned Most Killed against BARbarians by ranking first in fighting-unit value destroyed.",
		},
		values = function(player)
			local mostKilled = AwardGroup(player, "most_killed")
			return {mostKilled.raptors, mostKilled.scavengers, mostKilled.barbarians}
		end,
		defaultSortColumn = CurrentAiColumn,
	},
}

local function Definition(tab)
	return DEFINITIONS[tab] or DEFINITIONS.setup
end

local function PlayerNameForSort(player)
	local name = tostring(player and player.player_name or "")
	return string.lower(name), name
end

local function PlayerComesBefore(left, right)
	local leftLower, leftName = PlayerNameForSort(left)
	local rightLower, rightName = PlayerNameForSort(right)
	if leftLower ~= rightLower then return leftLower < rightLower end
	if leftName ~= rightName then return leftName < rightName end
	return (tonumber(PlayerId(left)) or 0) < (tonumber(PlayerId(right)) or 0)
end

-- `labels` is the authoritative column count, not the values table: a player
-- missing an accomplishment group yields nils, and `#` over a table with holes
-- is undefined in Lua.
local function ColumnCount(definition)
	return #definition.labels
end

local function StatValue(player, definition, column)
	if column < 1 or column > ColumnCount(definition) then return nil end
	return tonumber(definition.values(player)[column])
end

local function SortPlayers(players, definition, sortColumn, descending)
	table.sort(players, function(left, right)
		if sortColumn == 0 then
			if descending then return PlayerComesBefore(right, left) end
			return PlayerComesBefore(left, right)
		end
		local leftValue = StatValue(left, definition, sortColumn)
		local rightValue = StatValue(right, definition, sortColumn)
		if leftValue == nil and rightValue ~= nil then return false end
		if leftValue ~= nil and rightValue == nil then return true end
		if leftValue ~= nil and rightValue ~= nil and leftValue ~= rightValue then
			if descending then return leftValue > rightValue end
			return leftValue < rightValue
		end
		return PlayerComesBefore(left, right)
	end)
	return players
end

local function PlayersWithUnresolvedNames(response)
	local players = {}
	local seenNames = {}
	for _, player in ipairs(response and response.players or {}) do
		players[#players + 1] = player
		local name = string.lower(tostring(player and player.player_name or ""))
		if name ~= "" then seenNames[name] = true end
	end
	for _, unresolvedName in ipairs(response and response.unresolved_player_names or {}) do
		local name = tostring(unresolvedName or "")
		local folded = string.lower(name)
		if name ~= "" and not seenNames[folded] then
			players[#players + 1] = {player_id = 0, player_name = name, exact_wins = 0, harder_wins = 0}
			seenNames[folded] = true
		end
	end
	return players
end

local function IsOwnPlayer(player, request)
	local ownID = request and request._own_player_id
	local playerID = PlayerId(player)
	if ownID ~= nil and playerID ~= nil and tostring(ownID) == tostring(playerID) then
		return true
	end
	local ownName = string.lower(tostring(request and request._own_player_name or ""))
	local playerName = string.lower(tostring(player and player.player_name or ""))
	return ownName ~= "" and ownName == playerName
end

local function SplitPlayers(players, request, definition, sortColumn, descending)
	local active = {}
	local spectators = {}
	local spectatorNames = ToSet(request and request._spectator_names)
	local spectatorIds = ToSet(request and request._spectator_ids)
	for _, player in ipairs(players) do
		local name = player.player_name
		local id = PlayerId(player)
		if spectatorNames[name] or spectatorNames[tostring(name or "")] or spectatorIds[id] or spectatorIds[tostring(id or "")] then
			spectators[#spectators + 1] = player
		else
			active[#active + 1] = player
		end
	end
	return SortPlayers(active, definition, sortColumn, descending), SortPlayers(spectators, definition, sortColumn, descending)
end

function PlayerStatsFactory.New(Display)
	local PlayerStats = {}

	function PlayerStats.DefaultTab(response)
		return string.lower(tostring(response and response.match_status or "")) == "exact" and "setup" or "awards"
	end

	function PlayerStats.HelpText(tab, column)
		local definition = Definition(tab)
		return definition.help[column] or ""
	end

	function PlayerStats.DefaultSortColumn(tab, request)
		local definition = Definition(tab)
		return tonumber(definition.defaultSortColumn(request)) or 1
	end

	local function SortLabel(label, column, activeColumn, descending)
		if column ~= activeColumn then return label end
		return label .. (descending and " v" or " ^")
	end

	local function DisplayRows(players, definition, request, colorLookup, showColors)
		local columns = ColumnCount(definition)
		local rows = {}
		for _, player in ipairs(players) do
			local values = definition.values(player)
			-- Columns beyond this tab's count render empty rather than "-", so an
			-- unused slot reads as absent instead of as a missing value.
			local function Cell(column)
				if column > columns then return "" end
				return Display.Number(values[column], 0)
			end
			rows[#rows + 1] = {
				name = tostring(player.player_name or "Unknown"),
				statOne = Cell(1),
				statTwo = Cell(2),
				statThree = Cell(3),
				statFour = Cell(4),
				statFive = Cell(5),
				statSix = Cell(6),
				color = showColors and PlayerColor(player, colorLookup) or "#00000000",
				hasColor = showColors,
				isOwn = IsOwnPlayer(player, request),
			}
		end
		return rows
	end

	function PlayerStats.Build(response, request, colorLookup, options)
		options = options or {}
		local tab = DEFINITIONS[options.playerTab] and options.playerTab or "setup"
		local definition = Definition(tab)
		local defaultColumn = PlayerStats.DefaultSortColumn(tab, request)
		local columns = ColumnCount(definition)
		local sortColumn = tonumber(options.sortColumn)
		-- A tab with fewer columns cannot inherit a sort from a wider one.
		if sortColumn == nil or sortColumn < 0 or sortColumn > columns then sortColumn = defaultColumn end
		local descending = options.sortDescending ~= false
		local displayedPlayers = PlayersWithUnresolvedNames(response)
		local active, spectators = SplitPlayers(displayedPlayers, request, definition, sortColumn, descending)
		local groups = {}
		if options.showSpectators == true then
			groups = {
				{label = "Players", showLabel = true, emptyText = "No player stats", players = DisplayRows(active, definition, request, colorLookup, true), hasPlayers = #active > 0},
				{label = "Spectators", showLabel = true, emptyText = "No spectator stats", players = DisplayRows(spectators, definition, request, colorLookup, false), hasPlayers = #spectators > 0},
			}
		else
			groups = {
				{label = "", showLabel = false, emptyText = "No player stats", players = DisplayRows(active, definition, request, colorLookup, true), hasPlayers = #active > 0},
			}
		end
		return {
			playerTab = tab,
			playerHeaderLabel = SortLabel("Player", 0, sortColumn, descending),
			playerStatOneLabel = SortLabel(definition.labels[1], 1, sortColumn, descending),
			playerStatTwoLabel = SortLabel(definition.labels[2], 2, sortColumn, descending),
			playerStatThreeLabel = SortLabel(definition.labels[3], 3, sortColumn, descending),
			playerStatFourLabel = SortLabel(definition.labels[4] or "", 4, sortColumn, descending),
			playerStatFiveLabel = SortLabel(definition.labels[5] or "", 5, sortColumn, descending),
			playerStatSixLabel = SortLabel(definition.labels[6] or "", 6, sortColumn, descending),
			playerStatOneHelpText = definition.help[1] or "",
			playerStatTwoHelpText = definition.help[2] or "",
			playerStatThreeHelpText = definition.help[3] or "",
			playerStatFourHelpText = definition.help[4] or "",
			playerStatFiveHelpText = definition.help[5] or "",
			playerStatSixHelpText = definition.help[6] or "",
			-- Drives the conditional columns in the RML, so the five three-column
			-- tabs render exactly as they did before this became variable.
			hasExtraStatColumns = columns > 3,
			statColumnCount = columns,
			showSpectators = options.showSpectators == true,
			sortColumn = sortColumn,
			sortDescending = descending,
			playerGroups = groups,
			hasPlayers = #displayedPlayers > 0,
		}
	end

	function PlayerStats.OwnPlayer(response, request)
		for _, player in ipairs(response and response.players or {}) do
			if IsOwnPlayer(player, request) then return player end
		end
		return nil
	end

	function PlayerStats.AccomplishmentGroup(player, group)
		return AccomplishmentGroup(player, group)
	end

	return PlayerStats
end

return PlayerStatsFactory
