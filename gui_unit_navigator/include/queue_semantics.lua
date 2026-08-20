local QueueSemantics = {}

local function CopyArray(values, startIndex)
	local copy = {}
	for index = startIndex or 1, #(values or {}) do copy[#copy + 1] = values[index] end
	return copy
end

local function Round(value, tolerance)
	value = tonumber(value) or 0
	if not tolerance or tolerance <= 0 then return value end
	return math.floor(value / tolerance + 0.5) * tolerance
end

local function Scalar(value)
	if type(value) == "number" then return string.format("%.4f", value) end
	if type(value) == "boolean" then return value and "1" or "0" end
	return tostring(value or "")
end

local function OptionSignature(options)
	if type(options) ~= "table" then return Scalar(options) end
	local values = {}
	for key, value in pairs(options) do
		if key ~= "coded" and value then values[#values + 1] = tostring(key) .. "=" .. Scalar(value) end
	end
	table.sort(values)
	return table.concat(values, ",")
end

local function Unwrap(command, insertCommandID)
	if not command then return {id = 0, params = {}, options = {}} end
	if insertCommandID and command.id == insertCommandID and command.params and command.params[2] then
		return {
			id = tonumber(command.params[2]) or command.params[2],
			params = CopyArray(command.params, 4),
			options = command.options or command.params[3] or {},
		}
	end
	return {id = command.id, params = command.params or {}, options = command.options or {}}
end

function QueueSemantics.New(options)
	options = options or {}
	local self = {}

	local function Normalize(command, config)
		local unwrapped = Unwrap(command, options.insertCommandID)
		local commandID = tonumber(unwrapped.id) or 0
		local tolerance = tonumber((config or {}).buildPositionTolerance) or 0
		if commandID < 0 then
			return {
				family = "build",
				id = commandID,
				buildingDefID = -commandID,
				x = Round(unwrapped.params[1], tolerance),
				z = Round(unwrapped.params[3], tolerance),
				facing = tonumber(unwrapped.params[4]) or 0,
				options = OptionSignature(unwrapped.options),
			}
		end

		local params = {}
		for index = 1, #unwrapped.params do params[index] = Scalar(unwrapped.params[index]) end
		return {
			family = options.commandFamilies and options.commandFamilies[commandID] or "other",
			id = commandID,
			params = params,
			options = OptionSignature(unwrapped.options),
		}
	end

	local function CommandSignature(normalized)
		if normalized.family == "build" then
			return table.concat({
				"b", normalized.buildingDefID, Scalar(normalized.x), Scalar(normalized.z),
				normalized.facing,
			}, ":")
		end
		return table.concat({"c", normalized.id, table.concat(normalized.params or {}, ","), normalized.options}, ":")
	end

	function self:Fingerprint(commands, context, config)
		context = context or {}
		config = config or {}

		local signatures = {}
		local onlyBuilds = #((commands or {})) > 0
		local formationCommandSkipped = false
		if context.formationBatchID then
			signatures[#signatures + 1] = "formation:" .. tostring(context.formationBatchID)
			onlyBuilds = false
		end
		for index = 1, #(commands or {}) do
			local normalized = Normalize(commands[index], config)
			local isFormationCommand = context.formationBatchID and not formationCommandSkipped
				and (context.issuedCommandID == nil or normalized.id == context.issuedCommandID)
			if isFormationCommand then
				formationCommandSkipped = true
			else
				onlyBuilds = onlyBuilds and normalized.family == "build"
				signatures[#signatures + 1] = CommandSignature(normalized)
			end
		end

		if config.queueEquivalencePolicy ~= "strict" and onlyBuilds then table.sort(signatures) end
		return (onlyBuilds and "build:" or "queue:") .. table.concat(signatures, "|")
	end

	function self:Equivalent(left, right, leftContext, rightContext, config)
		return self:Fingerprint(left, leftContext, config) == self:Fingerprint(right, rightContext, config)
	end

	function self:Describe(commands, context, config)
		context = context or {}
		if context.skipped then return {family = "skipped", label = "Skipped", iconText = "SKIP"} end
		if context.formationBatchID then return {family = "move", label = "Formation", iconText = "FORM"} end
		local first = commands and commands[1]
		if not first then return {family = "idle", label = "Idle", iconText = "IDLE"} end
		local normalized = Normalize(first, config)
		if normalized.family == "build" then
			local buildDefs = {}
			local buildDefCount = 0
			for _, command in ipairs(commands or {}) do
				local candidate = Normalize(command, config)
				if candidate.family == "build" and not buildDefs[candidate.buildingDefID] then
					buildDefs[candidate.buildingDefID] = true
					buildDefCount = buildDefCount + 1
				end
			end
			if buildDefCount > 1 then
				return {family = "build", label = "Build spread (" .. tostring(buildDefCount) .. ")", iconText = "BLD"}
			end
			return {
				family = "build",
				label = "Build " .. tostring(options.unitDefName and options.unitDefName(normalized.buildingDefID) or normalized.buildingDefID),
				iconText = "BLD",
				buildingDefID = normalized.buildingDefID,
			}
		end
		local labels = options.commandLabels or {}
		local label = labels[normalized.id] or (normalized.family == "other" and "Command " .. tostring(normalized.id) or normalized.family)
		return {family = normalized.family, label = label, iconText = string.upper(string.sub(label, 1, 4))}
	end

	function self:Family(command)
		return Normalize(command, {}).family
	end

	return self
end

return QueueSemantics
