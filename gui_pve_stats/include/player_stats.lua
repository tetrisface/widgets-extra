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

-- The served setting's enemies, named the way the mode's players say them.
-- Defaults to Raptors for the same reason CurrentAiColumn defaults to column 1.
local function EnemyNoun(request, count)
	local aiType = string.lower(tostring(request and request.ai_type or ""))
	if aiType == "scavengers" then
		return count == 1 and "boss" or "bosses"
	end
	if aiType == "barbarian" then
		return count == 1 and "Barbarian AI" or "Barbarian AIs"
	end
	return count == 1 and "queen" or "queens"
end

local function SetupExperience(player)
	local value = player and player.setup_experience
	return type(value) == "table" and value or {}
end

local DEFINITIONS = {
	-- Every column here is a clear qualified by the setting it was earned on:
	-- the first three by difficulty band, the last two by this exact setting.
	-- Those last two are the only per-player figures in the panel scoped to the
	-- current lobby, which is why they carry their own source marking.
	achievements = {
		labels = {"20+ Clears", "25+ Clears", "30+ Clears", "Setup Clears", "Max Here"},
		help = {
			"Eligible wins at governed challenge 20 or above: modeled population win chance at most 41.2%.",
			"Eligible wins at governed challenge 25 or above: modeled population win chance at most 26.5%.",
			"Eligible wins at governed challenge 30 or above: modeled population win chance at most 11.8%.",
			-- Overwritten per response by SetupSourceHelp; this is the exact-match
			-- wording and the fallback when no response has arrived yet.
			"Eligible victories on this exact lobby setup, at this team size and AI count. Counts only curated eligible games, so it sits below the lifetime totals on Encounters.",
			"The most enemies per game this player has beaten on this setup, comparing its enemy-count versions: clearing both the 20 and 50 queen versions shows 50.",
		},
		values = function(player)
			local challenges = AccomplishmentGroup(player, "challenges")
			local experience = SetupExperience(player)
			return {
				challenges.challenge_20_clears,
				challenges.challenge_25_clears,
				challenges.challenge_30_clears,
				experience.clears,
				experience.max_defeated,
			}
		end,
		defaultSortColumn = function() return 5 end,
		-- Ties on the sorted column resolve through this order: the ladder rung
		-- first, then clears on this setup, then the difficulty bands hardest
		-- first.
		sortCascade = {5, 4, 3, 2, 1},
		-- First column whose scope is the served setting rather than a lifetime
		-- total. Columns from here on get the source colouring, the asterisk and
		-- the per-source help text.
		setupSourceHelpColumns = 4,
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

local DEFAULT_TAB = "achievements"

local function Definition(tab)
	return DEFINITIONS[tab] or DEFINITIONS[DEFAULT_TAB]
end

-- The source values the server publishes for the setting it actually served.
-- Anything other than "exact" means the figures describe a neighbouring
-- setting and must say so.
local SETUP_SOURCE_HELP = {
	exact = {
		"Eligible victories on this exact lobby setup, at this team size and AI count. Counts only curated eligible games, so it sits below the lifetime totals on Encounters.",
		"The most enemies per game this player has beaten on this setup, comparing its enemy-count versions: clearing both the 20 and 50 queen versions shows 50.",
	},
	similar = {
		"Eligible victories on a SIMILAR setting matched by effect vector, not your exact lobby, at this team size and AI count. Counts only curated eligible games.",
		"The most enemies per game this player has beaten on the SIMILAR matched setting's enemy-count versions, not your exact lobby.",
	},
	raw_fallback = {
		"Eligible victories on the CLOSEST RAW setting match, not your exact lobby, at this team size and AI count. Counts only curated eligible games.",
		"The most enemies per game this player has beaten on the CLOSEST RAW matched setting's enemy-count versions, not your exact lobby.",
	},
}

local function SetupExperienceContext(response)
	local value = response and response.setup_experience_context
	return type(value) == "table" and value or nil
end

-- Read the server's own label for what it served rather than re-deriving it
-- from the closest-match metadata: two independent derivations of the same
-- fact can disagree, and this one sits directly above the numbers it describes.
local function SetupExperienceSource(response)
	local context = SetupExperienceContext(response)
	local source = context and tostring(context.source or "")
	if source == nil or source == "" then return nil end
	return source
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

-- One column's verdict, or nil on a tie so the caller can consult the next
-- key. A missing value sorts after every present one regardless of direction.
local function StatOrder(left, right, definition, column, descending)
	local leftValue = StatValue(left, definition, column)
	local rightValue = StatValue(right, definition, column)
	if leftValue == nil and rightValue == nil then return nil end
	if leftValue == nil then return false end
	if rightValue == nil then return true end
	if leftValue == rightValue then return nil end
	if descending then return leftValue > rightValue end
	return leftValue < rightValue
end

local function SortPlayers(players, definition, sortColumn, descending)
	table.sort(players, function(left, right)
		if sortColumn == 0 then
			if descending then return PlayerComesBefore(right, left) end
			return PlayerComesBefore(left, right)
		end
		local order = StatOrder(left, right, definition, sortColumn, descending)
		if order ~= nil then return order end
		-- Ties fall through the tab's declared cascade before names, so equal
		-- ladder rungs are split by clears and then the difficulty bands. The
		-- clicked column stays primary; the cascade only decides what it left
		-- undecided.
		for _, column in ipairs(definition.sortCascade or {}) do
			if column ~= sortColumn then
				order = StatOrder(left, right, definition, column, descending)
				if order ~= nil then return order end
			end
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

	-- Every match type now fills this tab, so there is nothing left to steer
	-- away from. It used to fall through to "awards" on a non-exact match
	-- purely because the setup columns went blank there.
	function PlayerStats.DefaultTab()
		return DEFAULT_TAB
	end

	function PlayerStats.HelpText(tab, column, response)
		local definition = Definition(tab)
		local help = definition.setupSourceHelpColumns and SETUP_SOURCE_HELP[SetupExperienceSource(response) or "exact"]
		local offset = definition.setupSourceHelpColumns and column - definition.setupSourceHelpColumns + 1
		if help and offset and offset >= 1 and offset <= #help then
			return help[offset]
		end
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
		for index, player in ipairs(players) do
			local values = definition.values(player)
			-- Columns beyond this tab's count render empty rather than "-", so an
			-- unused slot reads as absent instead of as a missing value.
			local function Cell(column)
				if column > columns then return "" end
				-- Zeros and absent values both blank so the nonzero results
				-- carry the table. Sorting still ranks a genuine zero above an
				-- absent value, so the order keeps the distinction the display
				-- gives up.
				local value = tonumber(values[column])
				if value == nil or value == 0 then return "" end
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
				-- Alternates within each group so players and spectators both
				-- stripe from their own first row.
				isAlt = index % 2 == 0,
			}
		end
		return rows
	end

	function PlayerStats.Build(response, request, colorLookup, options)
		options = options or {}
		local tab = DEFINITIONS[options.playerTab] and options.playerTab or DEFAULT_TAB
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
		local source = SetupExperienceSource(response)
		-- Only the tab that actually carries served-setting columns can be
		-- inexact, so a lifetime-only tab never inherits the marking.
		local scopedColumn = definition.setupSourceHelpColumns
		local scopedColumnsAreInexact = scopedColumn ~= nil and source ~= nil and source ~= "exact"
		-- Colour must never be the sole carrier of meaning, so the mark rides
		-- on the label too.
		local function ScopedLabel(label, column)
			if not scopedColumnsAreInexact or scopedColumn == nil then return label end
			-- Bounded above by the tab's own width as well: a slot this tab does
			-- not have renders empty, and a lone "*" would be a mark on nothing.
			if column < scopedColumn or column > columns then return label end
			return label .. "*"
		end
		local function StatLabel(column)
			return SortLabel(ScopedLabel(definition.labels[column] or "", column), column, sortColumn, descending)
		end
		local caveatText = ""
		if scopedColumnsAreInexact then
			local matched = {}
			for column = scopedColumn, columns do
				matched[#matched + 1] = definition.labels[column]
			end
			caveatText = table.concat(matched, " and ") .. " are for the matched setting, not your exact lobby."
		end
		-- The per-game enemy count is constant within a setting, so "the most
		-- you can defeat in one game here" is a property of the served setting
		-- rather than a per-player column. One neutral line above the table
		-- carries it for the whole lobby.
		local encounterInfoText = ""
		local experienceContext = SetupExperienceContext(response)
		local encounterCount = experienceContext and tonumber(experienceContext.encounter_count) or nil
		if scopedColumn ~= nil and encounterCount ~= nil and encounterCount > 0 then
			local subject = scopedColumnsAreInexact and "The matched setting fields " or "This setup fields "
			encounterInfoText = subject .. Display.Number(encounterCount, 0) .. " " .. EnemyNoun(request, encounterCount) .. " per game."
		end
		return {
			playerTab = tab,
			playerHeaderLabel = SortLabel("Player", 0, sortColumn, descending),
			playerStatOneLabel = StatLabel(1),
			playerStatTwoLabel = StatLabel(2),
			playerStatThreeLabel = StatLabel(3),
			playerStatFourLabel = StatLabel(4),
			playerStatFiveLabel = StatLabel(5),
			playerStatSixLabel = StatLabel(6),
			playerStatOneHelpText = PlayerStats.HelpText(tab, 1, response),
			playerStatTwoHelpText = PlayerStats.HelpText(tab, 2, response),
			playerStatThreeHelpText = PlayerStats.HelpText(tab, 3, response),
			playerStatFourHelpText = PlayerStats.HelpText(tab, 4, response),
			playerStatFiveHelpText = PlayerStats.HelpText(tab, 5, response),
			playerStatSixHelpText = PlayerStats.HelpText(tab, 6, response),
			-- Per-column rather than one "is this the wide tab" flag: the table
			-- is now 3, 5 or 6 columns wide and only the last of those is the
			-- old widened case.
			hasStatColumnFour = columns >= 4,
			hasStatColumnFive = columns >= 5,
			hasStatColumnSix = columns >= 6,
			-- Drops the stat columns to 50dp so they still fit. Five 90dp
			-- columns plus the flexing name column overflow the panel, so this
			-- has to trip at five, not six.
			isWideStatTable = columns >= 5,
			-- The last column's tooltip opens leftwards or it clips off the
			-- panel edge, and which column is last is now variable.
			tooltipAlignEndThree = columns == 3,
			tooltipAlignEndFive = columns == 5,
			tooltipAlignEndSix = columns == 6,
			hasScopedStatColumns = scopedColumn ~= nil,
			scopedColumnsAreInexact = scopedColumnsAreInexact,
			setupCaveatText = caveatText,
			hasSetupEncounterInfo = encounterInfoText ~= "",
			setupEncounterInfoText = encounterInfoText,
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
