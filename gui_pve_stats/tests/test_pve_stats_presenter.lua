local root = PVE_STATS_TEST_ROOT or (arg and arg[1]) or "./"
local T = dofile(root .. "tests/support.lua")
local Display = dofile(root .. "include/display.lua")
local PlayerStats = dofile(root .. "include/player_stats.lua").New(Display)
local Histogram = dofile(root .. "include/histogram.lua").New(Display, PlayerStats)
local Diagnostics = dofile(root .. "include/diagnostics.lua").New(Display)
local ViewModel = dofile(root .. "include/view_model.lua").New(
	Display,
	PlayerStats,
	Histogram,
	Diagnostics
)

local request = T.request({
	map = "Supreme Isthmus",
	game_settings = {startmetal = 1000},
	encounter_context = {human_team_size = 2},
	player_names = {"Alice", "Bob", "Spectator"},
	player_ids = {101, 202, 303},
	player_filter_requested = true,
	_own_player_id = 101,
	_own_player_name = "Alice",
	_spectator_names = {"Spectator"},
	_spectator_ids = {303},
})

local response = {
	-- Expresses "the server advertises a newer widget" rather than pinning a
	-- number, so bumping CLIENT_VERSION does not silently stop exercising the
	-- update notice.
	client_version = ViewModel.CLIENT_VERSION + 1,
	match_status = "closest",
	setting_hash = "query-hash-that-is-long",
	difficulty_estimate = {
		player_win_probability = 0.625,
		evidence_games = 1234,
		difficulty_target_sha256 = "contract-hash-that-is-long",
	},
	difficulty_histogram = {
		total_games = 10,
		current_difficulty = 21,
		current_percentile = 73,
		bins = {
			{lower_bound = 15, upper_bound = 20, games = 4, wins = 3},
			{lower_bound = 20, upper_bound = 25, games = 6, wins = 2},
		},
	},
	players = {
		{
			player_id = 101,
			player_name = "Alice",
			setup_clears = 3,
			setup_plays = 4,
			setup_experience = {clears = 3, defeated = 195, max_defeated = 65},
			accomplishments = {
				participation = {games_played = 50, victories = 30, distinct_maps_played = 12},
				encounters = {raptor_queens_defeated = 10, scavenger_bosses_defeated = 2, barbarian_ais_defeated = 1},
				personal_bests = {max_queens_one_victory = 7, max_bosses_one_victory = 2, max_barbarian_ais_one_victory = 1},
				challenges = {
					challenge_20_clears = 5,
					challenge_25_clears = 2,
					challenge_30_clears = 1,
					highest_challenge_cleared = 28.5,
					clear_histogram = {1, 3},
				},
			},
			awards = {most_killed = {raptors = 4, scavengers = 2, barbarians = 1}},
		},
		{
			player_id = 202,
			player_name = "Bob",
			setup_clears = 2,
			setup_plays = 5,
			setup_experience = {clears = 2, defeated = 130, max_defeated = 20},
			accomplishments = {
				participation = {games_played = 40, victories = 20, distinct_maps_played = 8},
				-- No `encounters` group on purpose: a player missing one must
				-- still render, and must not be sorted as if they had a zero.
				personal_bests = {max_queens_one_victory = 3},
				challenges = {challenge_20_clears = 2, challenge_25_clears = 0, challenge_30_clears = 0},
			},
			awards = {most_killed = {raptors = 2}},
		},
		{player_id = 303, player_name = "Spectator", accomplishments = {}},
	},
	unresolved_player_names = {"Unresolved"},
	setup_experience_context = {
		source = "similar",
		setting_hash = "matched-hash-that-is-long",
		encounter_count = 65,
	},
	closest_matches = {{
		match_method = "similar",
		similarity = 0.875,
		setting_hash = "matched-hash-that-is-long",
		difference_count = 4,
		display_diffs = {
			{column = "startmetal", incoming = 1001, expected = 994},
		},
		hidden_diff_summary = {total = 2},
	}},
	request_completeness = {
		provided_hash_columns = 7,
		derived_hash_column_names = {},
		defaulted_hash_columns = 1,
		missing_hash_columns = 1,
		missing_hash_column_names = {},
		total_hash_columns = 10,
	},
	source_window = {
		earliest_replay_time = "2026-01-01T00:00:00Z",
		latest_replay_age_seconds = 120,
	},
}

local options = {
	playerTab = "achievements",
	showSpectators = true,
	sortColumn = 1,
	sortDescending = true,
	diagnosticsExpanded = true,
	modOptionSteps = {startmetal = 10},
	currentGameId = "game-opaque-id",
	sentGameId = "sent-game-opaque-id",
	transportEvidence = {
		http_status = 200,
		attempt = 2,
		request_duration_ms = 1250,
		loading_elapsed_ms = 1500,
		loading_expected_seconds = 19,
		request_bytes = 512,
		response_bytes = 2048,
		request_hash = "request-opaque-id",
		trace_id = "trace-opaque-id",
		unapproved_detail = "excluded-support-detail",
	},
}

local function FindPlayer(groups, name)
	for _, group in ipairs(groups) do
		for _, player in ipairs(group.players) do
			if player.name == name then return player, group end
		end
	end
	return nil
end

local function AssertNoRmlFragments(value, seen)
	if type(value) ~= "table" then return end
	seen = seen or {}
	if seen[value] then return end
	seen[value] = true
	for key, child in pairs(value) do
		T.falsy(string.match(tostring(key), "Rml$"), "presenter returned generated RML field " .. tostring(key))
		AssertNoRmlFragments(child, seen)
	end
end

local function AssertSameRootKeys(expected, actual)
	for key in pairs(expected) do
		T.truthy(actual[key] ~= nil, "view model removed root key " .. tostring(key))
	end
	for key in pairs(actual) do
		T.truthy(expected[key] ~= nil, "view model added undeclared root key " .. tostring(key))
	end
end

local function testDataModelRootSchemaIsStable()
	local empty = ViewModel.Empty()
	AssertSameRootKeys(empty, ViewModel.Build(response, nil, request, nil, options))
	AssertSameRootKeys(empty, ViewModel.Build(nil, "invalid_json", request, nil, {}))
	T.equals(empty.apiClientVersion, 0)
end

local function testStructuredViewModel()
	local view = ViewModel.Build(response, nil, request, {Alice = "#112233", Bob = "#445566"}, options)
	T.equals(view.difficultyText, "21.0")
	T.equals(view.exactWinsText, "62.5%")
	T.equals(view.evidenceGamesText, "P73")
	T.equals(view.matchText, "Similar 0.875")
	T.truthy(view.hasHistogram)
	T.equals(#view.histogramBins, 2)
	T.contains(view.histogramHelpText, "Dark bars show 10 eligible games")
	T.falsy(view.histogramBins[1].isCurrent)
	T.truthy(view.histogramBins[1].tooltipAlignStart)
	T.falsy(view.histogramBins[1].tooltipAlignEnd)
	T.truthy(view.histogramBins[2].isCurrent)
	T.falsy(view.histogramBins[2].tooltipAlignStart)
	T.truthy(view.histogramBins[2].tooltipAlignEnd)
	T.contains(view.histogramBins[2].helpText, "Your current setup is here at 21.0")
	T.equals(view.histogramBins[2].populationHeight, "80%")
	T.equals(view.histogramBins[2].ownHeight, "100%")
	T.contains(view.playerStatOneHelpText, "governed challenge 20")
	local alice = assert(FindPlayer(view.playerGroups, "Alice"))
	T.truthy(alice.isOwn)
	T.equals(alice.color, "#112233")
	local spectator, spectatorGroup = FindPlayer(view.playerGroups, "Spectator")
	T.truthy(spectator)
	T.equals(spectatorGroup.label, "Spectators")
	T.equals(view.diffRows[1].field, "startmetal")
	T.equals(view.diffRows[1].current, "1000")
	T.equals(view.diffRows[1].closest, "990")
	T.truthy(view.hasUpdate)
	T.contains(view.sourceWindowText, "2 minutes ago")
	AssertNoRmlFragments(view)
end

local function testDiagnosticsUseOneNarrowEvidenceContract()
	local evidence = Diagnostics.Evidence(response, options)
	T.equals(evidence.http_status, 200)
	T.equals(evidence.query_hash, "query-hash-t")
	T.equals(evidence.unapproved_detail, nil)
	local presentation = Diagnostics.Build(response, options)
	T.contains(presentation.diagnosticsText, "HTTP: 200; attempt 2")
	-- The row label supplies "Match:"; the summary must not repeat it.
	T.contains(presentation.diagnosticsText, "Match: similar setting")
	T.notContains(presentation.diagnosticsText, "Match: Match:")
	-- Release identity leads the IDs row rather than holding a row of its own.
	T.contains(presentation.diagnosticsText, "IDs: contract contract-has")
	T.notContains(presentation.diagnosticsText, "Contract:")
	T.contains(presentation.diagnosticsText, "request 512 B; response 2 KiB")
	T.contains(presentation.diagnosticsText, "sent game sent-game-opaque-id")
	T.contains(presentation.diagnosticsText, "current game game-opaque-id")
	T.notContains(presentation.diagnosticsText, "excluded-support-detail")
	local logText = Diagnostics.FormatEvidenceLog(evidence)
	T.contains(logText, "http_status=200")
	T.notContains(logText, "excluded-support-detail")
end

local function testErrorsAndFreshnessArePresentationState()
	local unavailable = ViewModel.Build(nil, "invalid_json", request, nil, {})
	T.equals(unavailable.statusText, "Unavailable")
	T.truthy(unavailable.hasError)
	T.equals(unavailable.playerGroups[1].players[1], nil)
	T.equals(ViewModel.SourceWindowAgeMinute(response, {}), 2)
	local early = ViewModel.EstimatedLoadingProgress(1, 10)
	local late = ViewModel.EstimatedLoadingProgress(20, 10)
	T.truthy(early > 0 and early < 0.9)
	T.truthy(late >= 0.9 and late <= 0.92)
end

local function testFeatureTabsSortingAndHelpMatchPresentation()
	-- The tab is populated on every match type now, so there is nothing left to
	-- steer away from. It used to fall through to "awards" on a non-exact match
	-- only because the setup columns went blank there.
	T.equals(PlayerStats.DefaultTab({match_status = "exact"}), "achievements")
	T.equals(PlayerStats.DefaultTab(response), "achievements")
	T.equals(PlayerStats.DefaultTab(), "achievements")
	for _, tab in ipairs({"achievements", "adventures", "encounters", "awards"}) do
		local model = PlayerStats.Build(response, request, nil, {
			playerTab = tab,
			sortColumn = PlayerStats.DefaultSortColumn(tab, request),
			sortDescending = true,
		})
		T.equals(model.playerTab, tab)
		T.truthy(model.playerStatOneLabel ~= "")
		T.equals(model.playerStatOneHelpText, PlayerStats.HelpText(tab, 1, response))
		T.equals(model.playerStatTwoHelpText, PlayerStats.HelpText(tab, 2, response))
		T.equals(model.playerStatThreeHelpText, PlayerStats.HelpText(tab, 3, response))
	end
	local withoutSpectators = PlayerStats.Build(response, request, nil, {
		playerTab = "achievements",
		showSpectators = false,
		sortColumn = 0,
		sortDescending = false,
	})
	T.equals(FindPlayer(withoutSpectators.playerGroups, "Spectator"), nil)
	T.contains(Histogram.HelpText(response, request), "eligible games")
	T.contains(Histogram.BinHelpText(response, request, 2), "current setup is here")
end

local function testHistogramTooltipAlignmentCoversBothEdgesAndCenter()
	local histogram = Histogram.Build({
		difficulty_histogram = {
			total_games = 6,
			bins = {
				{lower_bound = 0, upper_bound = 10, games = 1, wins = 1},
				{lower_bound = 10, upper_bound = 20, games = 2, wins = 1},
				{lower_bound = 20, upper_bound = 30, games = 3, wins = 1},
			},
		},
	}, request)
	T.truthy(histogram.histogramBins[1].tooltipAlignStart)
	T.falsy(histogram.histogramBins[2].tooltipAlignStart)
	T.falsy(histogram.histogramBins[2].tooltipAlignEnd)
	T.truthy(histogram.histogramBins[3].tooltipAlignEnd)
	T.contains(histogram.histogramBins[2].helpText, "Challenge 10-20")
end

local function testPlayerSortingIsStrictAndDirectional()
	local players = {}
	for index = 1, 40 do
		players[index] = {
			player_id = index,
			player_name = string.format("Player %02d", index),
			setup_clears = index,
			setup_plays = index,
			setup_experience = {clears = index, defeated = index * 65},
			accomplishments = {
				participation = {games_played = index},
				challenges = {challenge_20_clears = index},
			},
		}
	end
	local sortResponse = {players = players}
	local descending = PlayerStats.Build(sortResponse, request, nil, {
		playerTab = "achievements",
		sortColumn = 1,
		sortDescending = true,
	})
	T.equals(descending.playerGroups[1].players[1].name, "Player 40")
	T.equals(descending.playerGroups[1].players[40].name, "Player 01")

	local ascending = PlayerStats.Build(sortResponse, request, nil, {
		playerTab = "achievements",
		sortColumn = 1,
		sortDescending = false,
	})
	T.equals(ascending.playerGroups[1].players[1].name, "Player 01")
	T.equals(ascending.playerGroups[1].players[40].name, "Player 40")

	local namesDescending = PlayerStats.Build(sortResponse, request, nil, {
		playerTab = "achievements",
		sortColumn = 0,
		sortDescending = true,
	})
	T.equals(namesDescending.playerGroups[1].players[1].name, "Player 40")
	T.equals(namesDescending.playerGroups[1].players[40].name, "Player 01")
end

local function testRmlOwnsDynamicMarkup()
	local rml = T.read(root .. "gui_pve_stats.rml")
	local rcss = T.read(root .. "gui_pve_stats.rcss")
	local entrypoint = T.read(root .. "gui_pve_stats.lua")
	T.contains(rml, "data-for=\"bin : histogramBins\"")
	T.contains(rml, "data-for=\"row : diagnosticRows\"")
	T.contains(rml, "data-for=\"diff : diffRows\"")
	T.contains(rml, "data-for=\"player : group.players\"")
	T.contains(rml, "data-style-height=\"bin.populationHeight\"")
	T.contains(rml, "data-if=\"bin.hasOwn\"")
	T.contains(rml, "{{bin.helpText}}")
	T.contains(rml, "{{playerStatOneHelpText}}")
	T.contains(rml, "{{updateTooltipText}}")
	T.contains(rcss, ".pve-stats-tooltip {")
	T.contains(rcss, "visibility: hidden;")
	T.contains(rcss, "position: absolute;")
	T.contains(rcss, "pointer-events: none;")
	T.contains(rcss, "font-size: 12dp;")
	T.notContains(rml, "id=\"pve-stats-help\"")
	T.notContains(rml, "id=\"pve-stats-table-help\"")
	T.notContains(rml, "onmouseover=")
	T.notContains(entrypoint, "ShowSummaryHelp")
	T.notContains(entrypoint, "ShowHistogramBinHelp")
	T.notContains(entrypoint, "ShowPlayerStatHelp")
	T.notContains(entrypoint, "inner_rml")
	T.notContains(entrypoint, "playersRml")
end

local function testUncataloguedOptionsAreExplainedNotSilent()
	-- A modoption BAR added after the catalog was pinned. The panel must say so
	-- instead of just going quiet, which is what made this hard to diagnose.
	local degraded = {}
	for key, value in pairs(response) do degraded[key] = value end
	degraded.request_completeness = {
		provided_hash_columns = 142,
		defaulted_hash_columns = 0,
		missing_hash_columns = 0,
		unknown_setting_count = 2,
		total_hash_columns = 145,
		derived_hash_column_names = {"Player Handicap"},
		missing_hash_column_names = {},
		unknown_setting_names = {"future_option_a", "future_option_b"},
	}
	degraded.degradation = {
		reason = "unknown_modoptions",
		effects = {"exact_match_suppressed"},
		unknown_setting_names = {"future_option_a", "future_option_b"},
		unknown_setting_count = 2,
	}

	local view = ViewModel.Build(degraded, nil, request, nil, options)
	T.truthy(view.isBestEffort, "degraded response must be marked best-effort")
	T.contains(view.bestEffortText, "2 options")
	T.contains(view.matchHelpText, "best-effort")

	local evidence = Diagnostics.Evidence(degraded, options)
	T.contains(evidence.request_fields, "unknown 2")
	T.contains(evidence.unknown_settings, "future_option_a")
	T.contains(evidence.unknown_settings, "future_option_b")

	-- An older server omits both fields; that must read as "nothing to report"
	-- rather than producing a bogus warning.
	local silent = {}
	for key, value in pairs(response) do silent[key] = value end
	local silentView = ViewModel.Build(silent, nil, request, nil, options)
	T.falsy(silentView.isBestEffort, "responses without degradation must not be marked")
	T.equals(silentView.bestEffortText, "")
	T.equals(Diagnostics.Evidence(silent, options).unknown_settings, nil)
end

local function testUnsupportedEvidenceNamesWhatThePlayerCanRecognise()
	-- The server discloses what the model has no trained evidence for. Two of
	-- the names it can send are not lobby options: a whole tweak payload, and
	-- an exact setup no game used. Rendering either as an option key put a raw
	-- `__sentinel__` in front of the player and counted a tweak payload as one
	-- option, which reads as a broken setting rather than as thin evidence.
	local degraded = {}
	for key, value in pairs(response) do degraded[key] = value end
	degraded.degradation = {
		reason = "unsupported_modoptions",
		effects = {"difficulty_estimate_extrapolated"},
		unsupported_setting_names = {"skyshift", "__unseen_tweak_profile__"},
	}

	local view = ViewModel.Build(degraded, nil, request, nil, options)
	T.truthy(view.isBestEffort, "unsupported evidence must be marked best-effort")
	T.contains(view.bestEffortText, "1 option")
	T.contains(view.bestEffortText, "tweak files")
	T.notContains(view.bestEffortText, "__unseen")
	T.notContains(view.bestEffortText, "2 options")

	local evidence = Diagnostics.Evidence(degraded, options)
	T.contains(evidence.unsupported_settings, "skyshift")
	T.contains(evidence.unsupported_settings, "this lobby's tweak files")
	T.notContains(evidence.unsupported_settings, "__unseen")

	-- Tweaks alone must not be described as an option count at all.
	local tweaksOnly = {}
	for key, value in pairs(response) do tweaksOnly[key] = value end
	tweaksOnly.degradation = {
		reason = "unsupported_modoptions",
		effects = {"difficulty_estimate_extrapolated"},
		unsupported_setting_names = {"__unseen_tweak_profile__"},
	}
	local tweaksView = ViewModel.Build(tweaksOnly, nil, request, nil, options)
	T.contains(tweaksView.bestEffortText, "tweak files")
	T.notContains(tweaksView.bestEffortText, "option")
end

local function testEncountersReportsWhatTheDataMeasuresAcrossSixColumns()
	-- The totals credit the lobby's configured enemy count on a win; they are
	-- never per-player kill attribution, so the label must not say "killed".
	-- The maxima sit beside them because a total cannot tell one enormous
	-- victory from many small ones.
	local view = PlayerStats.Build(response, request, nil, {playerTab = "encounters", sortColumn = 1, sortDescending = true})

	T.truthy(view.hasStatColumnSix, "encounters must render all six columns")
	T.truthy(view.isWideStatTable, "encounters must widen the table")
	T.truthy(view.tooltipAlignEndSix, "column six is last here, so its tooltip opens leftwards")
	T.falsy(view.tooltipAlignEndFive)
	T.equals(view.statColumnCount, 6)
	-- Encounters carries no served-setting column, so it never inherits the
	-- source marking even when the response itself is a closest match.
	T.falsy(view.hasScopedStatColumns)
	T.falsy(view.scopedColumnsAreInexact)
	T.notContains(view.playerStatOneLabel, "*")
	for _, label in ipairs({view.playerStatOneLabel, view.playerStatTwoLabel, view.playerStatThreeLabel}) do
		T.notContains(label, "Killed")
	end
	T.contains(view.playerStatOneLabel, "Queens Defeated")
	T.contains(view.playerStatFourLabel, "Max Queens")
	T.contains(view.playerStatSixHelpText, "single victory")

	local alice = FindPlayer(view.playerGroups, "Alice")
	T.equals(alice.statOne, "10")
	T.equals(alice.statFour, "7")
	T.equals(alice.statFive, "2")
	T.equals(alice.statSix, "1")
end

local function testModeTabsCascadeCurrentModeFirstThenEvidence()
	-- Default sorts and tie cascades follow the lobby: the current mode's
	-- column leads. Cross-mode ties then follow measured evidence -- ceiling
	-- rarity for Encounters maxes, mode popularity for Awards -- rather than
	-- column order.
	local function CascadePlayer(id, name, values)
		return {
			player_id = id,
			player_name = name,
			accomplishments = {
				participation = {
					victories = values.victories or 0,
					games_played = values.games or 0,
					distinct_maps_played = values.maps or 0,
				},
				encounters = {
					raptor_queens_defeated = values.queens or 0,
					scavenger_bosses_defeated = values.bosses or 0,
					barbarian_ais_defeated = values.barbs or 0,
				},
				personal_bests = {
					max_queens_one_victory = values.maxQueens or 0,
					max_bosses_one_victory = values.maxBosses or 0,
					max_barbarian_ais_one_victory = values.maxBarbs or 0,
				},
			},
			awards = {
				most_killed = {
					raptors = values.mkRaptors or 0,
					scavengers = values.mkScav or 0,
					barbarians = values.mkBarb or 0,
				},
			},
		}
	end
	local function Names(view)
		local names = {}
		for _, row in ipairs(view.playerGroups[1].players) do names[#names + 1] = row.name end
		return table.concat(names, ",")
	end
	local raptorsLobby = {ai_type = "Raptors"}

	-- Encounters opens on the current mode's Max, not its total.
	T.equals(PlayerStats.DefaultSortColumn("encounters", raptorsLobby), 4)
	T.equals(PlayerStats.DefaultSortColumn("encounters", {ai_type = "Barbarian"}), 6)
	T.equals(PlayerStats.DefaultSortColumn("encounters", {ai_type = "Scavengers"}), 5)

	-- Elle breaks the Max Queens tie on the current total; Dana and Cara stay
	-- tied through both current columns, so Max Bosses (the rarest ceiling)
	-- decides -- Cara's bigger Max BARbs must not outrank it.
	local encountersResponse = {
		players = {
			CascadePlayer(1, "Cara", {maxQueens = 10, queens = 50, maxBosses = 1, maxBarbs = 9}),
			CascadePlayer(2, "Dana", {maxQueens = 10, queens = 50, maxBosses = 5}),
			CascadePlayer(3, "Elle", {maxQueens = 10, queens = 60}),
		},
	}
	local encountersView = PlayerStats.Build(encountersResponse, raptorsLobby, nil, {playerTab = "encounters"})
	T.equals(encountersView.sortColumn, 4)
	T.equals(Names(encountersView), "Elle,Dana,Cara")

	-- Awards: tied on the current mode, the BARb count decides before the
	-- Scavenger one because it is earned against the larger population.
	local awardsResponse = {
		players = {
			CascadePlayer(1, "Faye", {mkRaptors = 3, mkBarb = 1, mkScav = 9}),
			CascadePlayer(2, "Gwen", {mkRaptors = 3, mkBarb = 2}),
		},
	}
	local awardsView = PlayerStats.Build(awardsResponse, raptorsLobby, nil, {playerTab = "awards"})
	T.equals(awardsView.sortColumn, 1)
	T.equals(Names(awardsView), "Gwen,Faye")

	-- Games & Maps leads with Victories and breaks its ties on Games.
	T.equals(PlayerStats.DefaultSortColumn("adventures", raptorsLobby), 1)
	local adventuresResponse = {
		players = {
			CascadePlayer(1, "Hope", {victories = 20, games = 40}),
			CascadePlayer(2, "Iris", {victories = 20, games = 55}),
		},
	}
	local adventuresView = PlayerStats.Build(adventuresResponse, raptorsLobby, nil, {playerTab = "adventures"})
	T.equals(Names(adventuresView), "Iris,Hope")
end

local function testNarrowTabsKeepExactlyThreeColumns()
	-- Widening the table must not leak stray cells into the tabs that did not
	-- ask for them, and a wide sort column must not survive the switch.
	for _, tab in ipairs({"adventures", "awards"}) do
		local view = PlayerStats.Build(response, request, nil, {playerTab = tab, sortColumn = 6, sortDescending = true})
		T.falsy(view.hasStatColumnFour, tab .. " must not render a fourth column")
		T.falsy(view.isWideStatTable, tab .. " must not widen the table")
		T.truthy(view.tooltipAlignEndThree, tab .. " ends at column three")
		T.equals(view.statColumnCount, 3)
		T.equals(view.playerStatFourLabel, "")
		T.truthy(view.sortColumn <= 3, tab .. " must reject a column it does not have")
		local alice = FindPlayer(view.playerGroups, "Alice")
		T.equals(alice.statFour, "")
		T.equals(alice.statSix, "")
	end

	-- "Most Killed" is BAR's award name, earned by ranking first in
	-- fighting-unit value destroyed. That one really is about kills.
	local awards = PlayerStats.Build(response, request, nil, {playerTab = "awards", sortColumn = 1, sortDescending = true})
	T.contains(awards.playerStatOneLabel, "Most Killed")
end

local function testSettingAchievementsEndOnTheSetupLadder()
	-- Five columns: three lifetime difficulty bands, then the served-setting
	-- pair. Max Here is each player's rung on this setup's enemy-count ladder,
	-- so Bob showing 20 in a 65-enemy lobby is the interesting case. The
	-- cumulative "Defeated Here" was dropped deliberately: it was a linear
	-- rescale of Setup Clears, and the info line above the table already names
	-- the multiplier.
	local view = PlayerStats.Build(response, request, nil, {playerTab = "achievements", sortColumn = 5, sortDescending = true, showSpectators = true})

	T.equals(view.statColumnCount, 5)
	T.truthy(view.hasStatColumnFour)
	T.truthy(view.hasStatColumnFive)
	T.falsy(view.hasStatColumnSix, "the sixth column must not leak into a five-column tab")
	T.truthy(view.isWideStatTable, "five columns must take the narrow styling")
	T.truthy(view.tooltipAlignEndFive, "column five is last, so its tooltip opens leftwards")
	T.falsy(view.tooltipAlignEndThree)
	T.falsy(view.tooltipAlignEndSix)
	T.equals(view.sortColumn, 5, "the ladder column is sortable")
	T.truthy(PlayerStats.Build(response, request, nil, {playerTab = "achievements", sortColumn = 6, sortDescending = true}).sortColumn <= 5,
		"a six-column sort must not survive into this tab")

	T.contains(view.playerStatOneLabel, "20+ Clears")
	T.contains(view.playerStatFourLabel, "Setup Clears")
	T.contains(view.playerStatFiveLabel, "Max Here")
	T.contains(view.playerStatFiveHelpText, "enemy-count versions")
	T.equals(view.playerStatSixLabel, "")

	local alice = FindPlayer(view.playerGroups, "Alice")
	T.equals(alice.statOne, "5")
	T.equals(alice.statFour, "3")
	T.equals(alice.statFive, "65")
	T.equals(alice.statSix, "")
	T.equals(FindPlayer(view.playerGroups, "Bob").statFive, "20")
	-- No clears anywhere on the ladder blanks like every empty cell.
	T.equals(FindPlayer(view.playerGroups, "Spectator").statFive, "")
end

local function testServedSettingColumnsAreMarkedWhenTheyDescribeAnotherSetting()
	-- The whole disclosure rests on this: the numbers are the matched setting's,
	-- so the columns must say so in three independent ways -- colour, an
	-- asterisk, and the hover text -- and the caveat must name the columns it
	-- applies to rather than the whole table.
	local inexact = PlayerStats.Build(response, request, nil, {playerTab = "achievements", sortColumn = 4, sortDescending = true})

	T.truthy(inexact.hasScopedStatColumns)
	T.truthy(inexact.scopedColumnsAreInexact)
	T.contains(inexact.playerStatFourLabel, "*")
	T.contains(inexact.playerStatFiveLabel, "*")
	-- The lifetime columns on the same tab must stay unmarked.
	T.notContains(inexact.playerStatOneLabel, "*")
	T.notContains(inexact.playerStatThreeLabel, "*")
	T.contains(inexact.playerStatFourHelpText, "SIMILAR")
	T.notContains(inexact.playerStatOneHelpText, "SIMILAR")
	T.contains(inexact.setupCaveatText, "Setup Clears")
	T.contains(inexact.setupCaveatText, "Max Here")
	T.contains(inexact.setupCaveatText, "not your exact lobby")

	-- A raw fallback says so in its own words rather than borrowing "similar".
	local rawResponse = {}
	for key, value in pairs(response) do rawResponse[key] = value end
	rawResponse.setup_experience_context = {
		source = "raw_fallback",
		setting_hash = "matched-hash-that-is-long",
		encounter_count = 65,
	}
	local rawView = PlayerStats.Build(rawResponse, request, nil, {playerTab = "achievements", sortColumn = 4, sortDescending = true})
	T.truthy(rawView.scopedColumnsAreInexact)
	T.contains(rawView.playerStatFourHelpText, "CLOSEST RAW")
	T.notContains(rawView.playerStatFourHelpText, "SIMILAR")

	-- An exact match carries no marking at all: no colour, no asterisk, no
	-- caveat. Reading the server's own `source` is what keeps the label from
	-- disagreeing with the numbers it labels.
	local exactResponse = {}
	for key, value in pairs(response) do exactResponse[key] = value end
	exactResponse.setup_experience_context = {
		source = "exact",
		setting_hash = "query-hash-that-is-long",
		encounter_count = 65,
	}
	local exactView = PlayerStats.Build(exactResponse, request, nil, {playerTab = "achievements", sortColumn = 4, sortDescending = true})
	T.falsy(exactView.scopedColumnsAreInexact)
	T.notContains(exactView.playerStatFourLabel, "*")
	T.equals(exactView.setupCaveatText, "")
	T.contains(exactView.playerStatFourHelpText, "this exact lobby setup")

	-- A response that carries no context at all must not be treated as inexact
	-- either, or every pre-upgrade server would light the panel amber.
	local silentResponse = {}
	for key, value in pairs(response) do silentResponse[key] = value end
	silentResponse.setup_experience_context = nil
	local silentView = PlayerStats.Build(silentResponse, request, nil, {playerTab = "achievements", sortColumn = 4, sortDescending = true})
	T.falsy(silentView.scopedColumnsAreInexact)
	T.equals(silentView.setupCaveatText, "")
end

local function testServedSettingEnemyCountRidesTheSetupClearsTooltip()
	-- The per-game enemy count is constant within a setting, so it belongs to
	-- the Setup Clears tooltip rather than a standalone line above the table.
	-- Never in Max Here: that column compares enemy-count versions, so pinning
	-- one count inside it would contradict the number it explains.
	local inexact = PlayerStats.Build(response, request, nil, {playerTab = "achievements", sortColumn = 4, sortDescending = true})
	T.contains(inexact.playerStatFourHelpText, "The matched setting fields 65 queens per game.")
	T.notContains(inexact.playerStatFiveHelpText, "per game.")
	T.falsy(inexact.hasSetupEncounterInfo)

	local exactResponse = {}
	for key, value in pairs(response) do exactResponse[key] = value end
	exactResponse.setup_experience_context = {source = "exact", setting_hash = "query-hash-that-is-long", encounter_count = 65}
	local exactView = PlayerStats.Build(exactResponse, request, nil, {playerTab = "achievements", sortColumn = 4, sortDescending = true})
	T.contains(exactView.playerStatFourHelpText, "This setup fields 65 queens per game.")

	-- Modes name their enemies differently, and one enemy must read singular.
	local scavResponse = {}
	for key, value in pairs(response) do scavResponse[key] = value end
	scavResponse.setup_experience_context = {source = "exact", setting_hash = "h", encounter_count = 1}
	local scavView = PlayerStats.Build(scavResponse, {ai_type = "Scavengers"}, nil, {playerTab = "achievements", sortColumn = 4, sortDescending = true})
	T.contains(scavView.playerStatFourHelpText, "This setup fields 1 boss per game.")

	-- A pre-upgrade server sends no context: the tooltip must not invent a
	-- count, and lifetime tabs never carry it.
	local silentResponse = {}
	for key, value in pairs(response) do silentResponse[key] = value end
	silentResponse.setup_experience_context = nil
	local silentView = PlayerStats.Build(silentResponse, request, nil, {playerTab = "achievements", sortColumn = 4, sortDescending = true})
	T.notContains(silentView.playerStatFourHelpText, "per game.")
	local encountersView = PlayerStats.Build(response, request, nil, {playerTab = "encounters", sortColumn = 1, sortDescending = true})
	T.notContains(encountersView.playerStatFourHelpText, "per game.")
end

local function testMeasuredZerosBlankWhileAbsentStaysDashed()
	-- Three cell states, all distinct: a measured zero blanks so nonzero
	-- results carry the table, "-" still means unknown or absent, and slots
	-- beyond the tab's width stay empty. Collapsing zero into "-" would claim
	-- ignorance about a value the server actually measured.
	local view = PlayerStats.Build(response, request, nil, {playerTab = "achievements", sortColumn = 5, sortDescending = true, showSpectators = true})
	local bob = FindPlayer(view.playerGroups, "Bob")
	T.equals(bob.statTwo, "", "challenge_25_clears of 0 must blank")
	T.equals(bob.statThree, "", "challenge_30_clears of 0 must blank")
	T.equals(bob.statFive, "20", "a nonzero value still shows")
	T.equals(FindPlayer(view.playerGroups, "Spectator").statFive, "", "absent blanks like zero; sorting still ranks them apart")
	-- The discreet stripe alternates within each group, so spectators restart
	-- from an unstriped first row.
	local players = view.playerGroups[1].players
	T.falsy(players[1].isAlt)
	T.truthy(players[2].isAlt)
	T.falsy(view.playerGroups[2].players[1].isAlt, "spectators restart unstriped")
end

local function testAchievementsTiesCascadeThroughLadderClearsThenBands()
	-- Requested order: Max Here, then Setup Clears, then 30+, 25+, 20+, all
	-- descending. Equal rungs split by clears; players with no rung at all
	-- fall through to the difficulty bands instead of an arbitrary name sort.
	local cascadeResponse = {players = {
		{player_id = 1, player_name = "EqualMaxFewClears", setup_experience = {clears = 2, max_defeated = 50},
			accomplishments = {challenges = {challenge_20_clears = 9, challenge_25_clears = 9, challenge_30_clears = 9}}},
		{player_id = 2, player_name = "EqualMaxManyClears", setup_experience = {clears = 5, max_defeated = 50},
			accomplishments = {challenges = {challenge_20_clears = 0, challenge_25_clears = 0, challenge_30_clears = 0}}},
		{player_id = 3, player_name = "NoRungStrongBands", accomplishments = {challenges = {challenge_20_clears = 7, challenge_25_clears = 6, challenge_30_clears = 5}}},
		{player_id = 4, player_name = "NoRungWeakBands", accomplishments = {challenges = {challenge_20_clears = 1, challenge_25_clears = 0, challenge_30_clears = 0}}},
	}}
	local view = PlayerStats.Build(cascadeResponse, request, nil, {playerTab = "achievements", sortColumn = 5, sortDescending = true})
	local names = {}
	for index, player in ipairs(view.playerGroups[1].players) do names[index] = player.name end
	T.equals(names[1], "EqualMaxManyClears")
	T.equals(names[2], "EqualMaxFewClears")
	T.equals(names[3], "NoRungStrongBands")
	T.equals(names[4], "NoRungWeakBands")
	-- The default sort for the tab is the ladder itself.
	T.equals(PlayerStats.DefaultSortColumn("achievements", request), 5)
end

local function testWideColumnsAreSortable()
	-- Column 4 is one of the new maxima, so this fails outright if the widened
	-- columns are not wired into the sort comparator.
	local descending = PlayerStats.Build(response, request, nil, {playerTab = "encounters", sortColumn = 4, sortDescending = true})
	T.equals(descending.sortColumn, 4)
	T.equals(descending.playerGroups[1].players[1].name, "Alice")

	local ascending = PlayerStats.Build(response, request, nil, {playerTab = "encounters", sortColumn = 4, sortDescending = false})
	T.equals(ascending.playerGroups[1].players[1].name, "Bob")

	-- Bob has no `encounters` group at all. A missing group must read as absent
	-- rather than as zero, and must not crash the row.
	local byTotal = PlayerStats.Build(response, request, nil, {playerTab = "encounters", sortColumn = 1, sortDescending = false})
	T.equals(FindPlayer(byTotal.playerGroups, "Bob").statOne, "")
	T.equals(byTotal.playerGroups[1].players[1].name, "Alice")
end

testStructuredViewModel()
testDataModelRootSchemaIsStable()
testUncataloguedOptionsAreExplainedNotSilent()
testUnsupportedEvidenceNamesWhatThePlayerCanRecognise()
testEncountersReportsWhatTheDataMeasuresAcrossSixColumns()
testModeTabsCascadeCurrentModeFirstThenEvidence()
testNarrowTabsKeepExactlyThreeColumns()
testSettingAchievementsEndOnTheSetupLadder()
testServedSettingColumnsAreMarkedWhenTheyDescribeAnotherSetting()
testWideColumnsAreSortable()
testAchievementsTiesCascadeThroughLadderClearsThenBands()
testMeasuredZerosBlankWhileAbsentStaysDashed()
testServedSettingEnemyCountRidesTheSetupClearsTooltip()
testDiagnosticsUseOneNarrowEvidenceContract()
testErrorsAndFreshnessArePresentationState()
testFeatureTabsSortingAndHelpMatchPresentation()
testHistogramTooltipAlignmentCoversBothEdgesAndCenter()
testPlayerSortingIsStrictAndDirectional()
testRmlOwnsDynamicMarkup()

print("test_pve_stats_presenter.lua: ok")
