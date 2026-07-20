local root = PVE_STATS_TEST_ROOT or (arg and arg[1]) or "./"
local T = dofile(root .. "tests/support.lua")
local GameOver = dofile(root .. "include/game_over.lua")

local function testDecidedAndUndecidedEvents()
	local decided = assert(GameOver.Build(
		"abcdef0123456789abcdef0123456789",
		{2, 0},
		123.9
	))
	T.equals(decided.outcome, "decided")
	T.equals(decided.winning_ally_teams[1], 0)
	T.equals(decided.winning_ally_teams[2], 2)
	T.equals(decided.game_frame, 123)
	local undecided = assert(GameOver.Build(
		"abcdef0123456789abcdef0123456789",
		{},
		0
	))
	T.equals(undecided.outcome, "undecided")
end

local function testInvalidIdentityAndWinnersAreDiscarded()
	local event, err = GameOver.Build("not-valid", {}, 0)
	T.equals(event, nil)
	T.equals(err, "missing_game_id")
	event, err = GameOver.Build(
		"abcdef0123456789abcdef0123456789",
		{-1},
		0
	)
	T.equals(event, nil)
	T.equals(err, "invalid_winners")
end

local function testRetryJitterIsDeterministicAndBounded()
	local low = GameOver.RetryJitter("00cdef0123456789abcdef0123456789", 1, 10)
	local high = GameOver.RetryJitter("ffcdef0123456789abcdef0123456789", 1, 10)
	T.equals(low, 8)
	T.truthy(math.abs(high - 12) < 0.000001)
	T.equals(GameOver.RetryJitter("ffcdef0123456789abcdef0123456789", 1, 10), high)
end

testDecidedAndUndecidedEvents()
testInvalidIdentityAndWinnersAreDiscarded()
testRetryJitterIsDeterministicAndBounded()

print("test_pve_stats_game_over.lua: ok")
