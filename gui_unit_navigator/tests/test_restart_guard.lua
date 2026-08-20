local root = UNIT_NAVIGATOR_TEST_ROOT or (arg and arg[1]) or "./"
local T = dofile(root .. "tests/support.lua")
local RestartGuard = dofile(root .. "include/restart_guard.lua")

local history = nil
local triggered
for nowSeconds = 100, 103 do
	history, triggered = RestartGuard.Record(history, nowSeconds)
	T.falsy(triggered, "restart guard triggered before the fifth startup")
end
T.arrayEquals(history, {100, 101, 102, 103})

history, triggered = RestartGuard.Record(history, 120)
T.truthy(triggered, "the inclusive 20-second boundary did not trigger")
T.arrayEquals(history, {}, "triggered history was not reset")

history, triggered = RestartGuard.Record({100, 101, 102, 103}, 121)
T.falsy(triggered, "an out-of-window startup contributed to the threshold")
T.arrayEquals(history, {101, 102, 103, 121})

history, triggered = RestartGuard.Record({
	[1] = 195,
	[2] = "196",
	[3] = 201,
	[4] = 179,
	[6] = 199,
	metadata = 198,
}, 200)
T.falsy(triggered, "invalid or future timestamps contributed to the threshold")
T.arrayEquals(history, {195, 199, 200})

history, triggered = RestartGuard.Record({1, 2, 3, 4}, nil)
T.falsy(triggered, "a missing current time triggered recovery")
T.arrayEquals(history, {}, "a missing current time retained an unsafe history")

history, triggered = RestartGuard.Record({1, 2, 3, 4}, 0 / 0)
T.falsy(triggered, "a non-finite current time triggered recovery")
T.arrayEquals(history, {}, "a non-finite current time retained an unsafe history")

history = nil
for nowSeconds = 10, 11 do
	history, triggered = RestartGuard.Record(history, nowSeconds, {threshold = 3, windowSeconds = 2})
	T.falsy(triggered)
end
history, triggered = RestartGuard.Record(history, 12, {threshold = 3, windowSeconds = 2})
T.truthy(triggered, "custom guard options were ignored")
T.arrayEquals(history, {})

print("test_restart_guard.lua: ok")
