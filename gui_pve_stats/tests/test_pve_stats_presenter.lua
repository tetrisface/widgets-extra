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
	playerTab = "milestones",
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
	T.equals(PlayerStats.DefaultTab({match_status = "exact"}), "setup")
	T.equals(PlayerStats.DefaultTab(response), "awards")
	for _, tab in ipairs({"setup", "adventures", "encounters", "milestones", "awards"}) do
		local model = PlayerStats.Build(response, request, nil, {
			playerTab = tab,
			sortColumn = PlayerStats.DefaultSortColumn(tab, request),
			sortDescending = true,
		})
		T.equals(model.playerTab, tab)
		T.truthy(model.playerStatOneLabel ~= "")
		T.equals(model.playerStatOneHelpText, PlayerStats.HelpText(tab, 1))
		T.equals(model.playerStatTwoHelpText, PlayerStats.HelpText(tab, 2))
		T.equals(model.playerStatThreeHelpText, PlayerStats.HelpText(tab, 3))
	end
	local withoutSpectators = PlayerStats.Build(response, request, nil, {
		playerTab = "setup",
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
			accomplishments = {participation = {games_played = index}},
		}
	end
	local sortResponse = {players = players}
	local descending = PlayerStats.Build(sortResponse, request, nil, {
		playerTab = "setup",
		sortColumn = 1,
		sortDescending = true,
	})
	T.equals(descending.playerGroups[1].players[1].name, "Player 40")
	T.equals(descending.playerGroups[1].players[40].name, "Player 01")

	local ascending = PlayerStats.Build(sortResponse, request, nil, {
		playerTab = "setup",
		sortColumn = 1,
		sortDescending = false,
	})
	T.equals(ascending.playerGroups[1].players[1].name, "Player 01")
	T.equals(ascending.playerGroups[1].players[40].name, "Player 40")

	local namesDescending = PlayerStats.Build(sortResponse, request, nil, {
		playerTab = "setup",
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

	T.truthy(view.hasExtraStatColumns, "encounters must widen the table")
	T.equals(view.statColumnCount, 6)
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

local function testNarrowTabsKeepExactlyThreeColumns()
	-- Widening the table must not leak stray cells into the tabs that did not
	-- ask for them, and a wide sort column must not survive the switch.
	for _, tab in ipairs({"setup", "adventures", "milestones", "awards"}) do
		local view = PlayerStats.Build(response, request, nil, {playerTab = tab, sortColumn = 6, sortDescending = true})
		T.falsy(view.hasExtraStatColumns, tab .. " must not widen the table")
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
	T.equals(FindPlayer(byTotal.playerGroups, "Bob").statOne, "-")
	T.equals(byTotal.playerGroups[1].players[1].name, "Alice")
end

testStructuredViewModel()
testDataModelRootSchemaIsStable()
testUncataloguedOptionsAreExplainedNotSilent()
testUnsupportedEvidenceNamesWhatThePlayerCanRecognise()
testEncountersReportsWhatTheDataMeasuresAcrossSixColumns()
testNarrowTabsKeepExactlyThreeColumns()
testWideColumnsAreSortable()
testDiagnosticsUseOneNarrowEvidenceContract()
testErrorsAndFreshnessArePresentationState()
testFeatureTabsSortingAndHelpMatchPresentation()
testHistogramTooltipAlignmentCoversBothEdgesAndCenter()
testPlayerSortingIsStrictAndDirectional()
testRmlOwnsDynamicMarkup()

print("test_pve_stats_presenter.lua: ok")
