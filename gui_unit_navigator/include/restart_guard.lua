local RestartGuard = {}

RestartGuard.DEFAULT_THRESHOLD = 5
RestartGuard.DEFAULT_WINDOW_SECONDS = 20

local function IsFiniteNumber(value)
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function ResolveThreshold(value)
	if not IsFiniteNumber(value) or value < 1 then return RestartGuard.DEFAULT_THRESHOLD end
	return math.floor(value)
end

local function ResolveWindowSeconds(value)
	if not IsFiniteNumber(value) or value < 0 then return RestartGuard.DEFAULT_WINDOW_SECONDS end
	return value
end

local function RecentTimestamps(previousTimestamps, nowSeconds, windowSeconds)
	local timestamps = {}
	if type(previousTimestamps) ~= "table" then return timestamps end

	for index, timestamp in pairs(previousTimestamps) do
		local isArrayIndex = type(index) == "number" and index >= 1 and index % 1 == 0
		local isTimestamp = IsFiniteNumber(timestamp) and timestamp >= 0
		local age = isTimestamp and nowSeconds - timestamp or nil
		if isArrayIndex and isTimestamp and age >= 0 and age <= windowSeconds then
			timestamps[#timestamps + 1] = timestamp
		end
	end
	table.sort(timestamps)
	return timestamps
end

local function KeepNewest(timestamps, limit)
	local bounded = {}
	local first = math.max(1, #timestamps - limit + 1)
	for index = first, #timestamps do bounded[#bounded + 1] = timestamps[index] end
	return bounded
end

-- Records one startup. A trigger consumes its history so the recovery gesture
-- must be performed as a fresh sequence before it can fire again.
function RestartGuard.Record(previousTimestamps, nowSeconds, options)
	if not IsFiniteNumber(nowSeconds) or nowSeconds < 0 then return {}, false end

	options = type(options) == "table" and options or {}
	local threshold = ResolveThreshold(options.threshold)
	local windowSeconds = ResolveWindowSeconds(options.windowSeconds)
	local history = RecentTimestamps(previousTimestamps, nowSeconds, windowSeconds)

	history = KeepNewest(history, math.max(0, threshold - 1))
	history[#history + 1] = nowSeconds
	if #history >= threshold and history[#history] - history[1] <= windowSeconds then return {}, true end

	return history, false
end

return RestartGuard
