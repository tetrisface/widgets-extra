local GameOver = {}

local function IsArray(value)
	if type(value) ~= "table" then return false end
	local count = 0
	for key in pairs(value) do
		if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then return false end
		count = count + 1
	end
	return count == #value
end

function GameOver.Build(gameId, winningAllyTeams, gameFrame)
	if type(gameId) ~= "string" or #gameId ~= 32 or string.find(gameId, "[^0-9a-f]") then
		return nil, "missing_game_id"
	end
	if not IsArray(winningAllyTeams) then return nil, "invalid_winners" end
	local winners = {}
	for _, allyTeam in ipairs(winningAllyTeams) do
		local numeric = tonumber(allyTeam)
		if not numeric or numeric < 0 or numeric ~= math.floor(numeric) then return nil, "invalid_winners" end
		winners[#winners + 1] = numeric
	end
	table.sort(winners)
	return {
		schema_version = 1,
		game_id = gameId,
		event = "game_over",
		outcome = #winners > 0 and "decided" or "undecided",
		winning_ally_teams = winners,
		game_frame = math.max(0, math.floor(tonumber(gameFrame) or 0)),
	}
end

function GameOver.Wire(event)
	if type(event) ~= "table" or event.schema_version ~= 1 or event.event ~= "game_over" then
		return nil, "invalid_game_over_event"
	end
	local validated = GameOver.Build(event.game_id, event.winning_ally_teams, event.game_frame)
	if not validated or validated.outcome ~= event.outcome then return nil, "invalid_game_over_event" end
	return validated
end

function GameOver.RetryJitter(gameId, attempt, delay)
	local normalizedId = type(gameId) == "string" and gameId or "00"
	local offset = ((math.max(1, tonumber(attempt) or 1) - 1) % 16) * 2 + 1
	local byte = tonumber(string.sub(normalizedId, offset, offset + 1), 16) or 128
	return math.max(0, tonumber(delay) or 0) * (0.8 + (byte / 255) * 0.4)
end

return GameOver
