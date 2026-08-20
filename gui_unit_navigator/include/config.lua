local Config = {}

local CURRENT_VERSION = 6
local GLASS_DEFAULT_MIGRATION_VERSION = 4
local TERRAIN_DEFAULT_MIGRATION_VERSION = 5
local LEGACY_GLASS_OPACITY = 0.82
local LEGACY_TERRAIN_OPACITY = 0.72
local MAXIMUM_ACTIVATION_BINDINGS = 6
local ACTIVATION_MODE_HOLD = "hold"
local ACTIVATION_MODE_PRESS_RELEASE = "press_release"

local DEFAULTS = {
	activationBindings = {{
		keyName = "CapsLock",
		keyCode = 301,
		mode = ACTIVATION_MODE_HOLD,
	}},
	-- Retained as derived aliases so existing configs and external readers keep
	-- working while activationBindings is the canonical representation.
	activationKeyBound = true,
	activationKeyName = "CapsLock",
	activationKeyCode = 301,
	gridKeyNames = {"Q", "W", "E", "A", "S", "D"},
	gridKeyCodes = {113, 119, 101, 97, 115, 100},
	cancelKeyName = "Escape",
	cancelKeyCode = 27,
	cameraPreview = true,
	cameraTransitionSeconds = 0.12,
	mouseLeaveGuardDp = 24,
	mouseLeaveDelaySeconds = 0.15,
	glassOpacity = 0.45,
	terrainOpacity = 0.85,
	nonGroupUnitOpacity = 0.28,
	formationBatchWindowFrames = 1,
	buildPositionTolerance = 8,
	queueEquivalencePolicy = "semantic",
	commandFamilyFilters = {
		build = true,
		move = true,
		attack = true,
		patrol = true,
		other = true,
	},
}

local function Copy(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for key, child in pairs(value) do copy[key] = Copy(child) end
	return copy
end

local function Clamp(value, minimum, maximum, fallback)
	value = tonumber(value)
	if not value then return fallback end
	return math.max(minimum, math.min(maximum, value))
end

local function KeyCode(value, fallback)
	value = tonumber(value)
	if not value or value < 1 or value > 65535 then return fallback end
	return math.floor(value)
end

local function ActivationMode(value)
	if value == ACTIVATION_MODE_PRESS_RELEASE then return ACTIVATION_MODE_PRESS_RELEASE end
	return ACTIVATION_MODE_HOLD
end

local function ActivationBindings(saved)
	local bindings = {}
	local seenCodes = {}
	for index = 1, math.min(MAXIMUM_ACTIVATION_BINDINGS, #saved) do
		local candidate = saved[index]
		local keyCode = type(candidate) == "table" and KeyCode(candidate.keyCode)
		if keyCode and not seenCodes[keyCode] then
			seenCodes[keyCode] = true
			bindings[#bindings + 1] = {
				keyName = type(candidate.keyName) == "string" and candidate.keyName or tostring(keyCode),
				keyCode = keyCode,
				mode = ActivationMode(candidate.mode),
			}
		end
	end
	return bindings
end

local function SyncLegacyActivation(result)
	local primary = result.activationBindings[1]
	result.activationKeyBound = primary ~= nil
	result.activationKeyName = primary and primary.keyName or nil
	result.activationKeyCode = primary and primary.keyCode or nil
	return result
end

function Config.Defaults()
	return Copy(DEFAULTS)
end

function Config.Normalize(saved)
	local result = Config.Defaults()
	if type(saved) ~= "table" then return result end

	if type(saved.activationBindings) == "table" then
		result.activationBindings = ActivationBindings(saved.activationBindings)
	elseif saved.activationKeyBound == false then
		result.activationBindings = {}
	else
		result.activationBindings = {{
			keyName = type(saved.activationKeyName) == "string" and saved.activationKeyName or DEFAULTS.activationKeyName,
			keyCode = KeyCode(saved.activationKeyCode, DEFAULTS.activationKeyCode),
			mode = ACTIVATION_MODE_HOLD,
		}}
	end
	SyncLegacyActivation(result)
	if type(saved.cancelKeyName) == "string" then result.cancelKeyName = saved.cancelKeyName end
	result.cancelKeyCode = KeyCode(saved.cancelKeyCode, result.cancelKeyCode)

	if type(saved.gridKeyNames) == "table" and type(saved.gridKeyCodes) == "table" then
		for index = 1, 6 do
			if type(saved.gridKeyNames[index]) == "string" then result.gridKeyNames[index] = saved.gridKeyNames[index] end
			result.gridKeyCodes[index] = KeyCode(saved.gridKeyCodes[index], result.gridKeyCodes[index])
		end
	end

	if type(saved.cameraPreview) == "boolean" then result.cameraPreview = saved.cameraPreview end
	result.cameraTransitionSeconds = Clamp(saved.cameraTransitionSeconds, 0, 1.5, result.cameraTransitionSeconds)
	result.mouseLeaveGuardDp = Clamp(saved.mouseLeaveGuardDp, 0, 96, result.mouseLeaveGuardDp)
	result.mouseLeaveDelaySeconds = Clamp(saved.mouseLeaveDelaySeconds, 0, 1, result.mouseLeaveDelaySeconds)
	result.glassOpacity = Clamp(saved.glassOpacity, 0.2, 1, result.glassOpacity)
	result.terrainOpacity = Clamp(saved.terrainOpacity, 0, 1, result.terrainOpacity)
	result.nonGroupUnitOpacity = Clamp(saved.nonGroupUnitOpacity, 0, 1, result.nonGroupUnitOpacity)
	result.formationBatchWindowFrames = math.floor(Clamp(saved.formationBatchWindowFrames, 0, 30, result.formationBatchWindowFrames))
	result.buildPositionTolerance = Clamp(saved.buildPositionTolerance, 0, 128, result.buildPositionTolerance)
	if saved.queueEquivalencePolicy == "semantic" or saved.queueEquivalencePolicy == "strict" then
		result.queueEquivalencePolicy = saved.queueEquivalencePolicy
	end
	if type(saved.commandFamilyFilters) == "table" then
		for family in pairs(result.commandFamilyFilters) do
			if type(saved.commandFamilyFilters[family]) == "boolean" then
				result.commandFamilyFilters[family] = saved.commandFamilyFilters[family]
			end
		end
	end
	return result
end

function Config.FromSaved(saved, version)
	local migrated = type(saved) == "table" and Copy(saved) or {}
	local savedVersion = tonumber(version) or 0
	if savedVersion < GLASS_DEFAULT_MIGRATION_VERSION and tonumber(migrated.glassOpacity) == LEGACY_GLASS_OPACITY then
		migrated.glassOpacity = DEFAULTS.glassOpacity
	end
	if savedVersion < TERRAIN_DEFAULT_MIGRATION_VERSION and tonumber(migrated.terrainOpacity) == LEGACY_TERRAIN_OPACITY then
		migrated.terrainOpacity = DEFAULTS.terrainOpacity
	end
	return Config.Normalize(migrated)
end

function Config.Version()
	return CURRENT_VERSION
end

function Config.WithoutActivation(source)
	local result = Config.Normalize(source)
	result.activationBindings = {}
	return SyncLegacyActivation(result)
end

function Config.HasActivation(source)
	return type(source) == "table"
		and type(source.activationBindings) == "table"
		and #source.activationBindings > 0
end

function Config.FindActivation(source, keyCode)
	keyCode = KeyCode(keyCode)
	if not keyCode then return nil end
	for index, binding in ipairs(source and source.activationBindings or {}) do
		if binding.keyCode == keyCode then return binding, index end
	end
	return nil
end

function Config.SetActivationBinding(source, index, binding)
	local result = Config.Normalize(source)
	index = math.floor(tonumber(index) or (#result.activationBindings + 1))
	if index < 1 or index > MAXIMUM_ACTIVATION_BINDINGS then return result, false end
	local keyCode = type(binding) == "table" and KeyCode(binding.keyCode)
	if not keyCode then return result, false end

	local bindings = Copy(result.activationBindings)
	if index <= #bindings then table.remove(bindings, index) end
	for existingIndex = #bindings, 1, -1 do
		if bindings[existingIndex].keyCode == keyCode then table.remove(bindings, existingIndex) end
	end
	index = math.min(index, #bindings + 1)
	table.insert(bindings, index, {
		keyName = type(binding.keyName) == "string" and binding.keyName or tostring(keyCode),
		keyCode = keyCode,
		mode = ActivationMode(binding.mode),
	})
	result.activationBindings = bindings
	return SyncLegacyActivation(result), true
end

function Config.RemoveActivationBinding(source, index)
	local result = Config.Normalize(source)
	index = math.floor(tonumber(index) or 0)
	if index < 1 or index > #result.activationBindings then return result, false end
	table.remove(result.activationBindings, index)
	return SyncLegacyActivation(result), true
end

function Config.MaximumActivationBindings()
	return MAXIMUM_ACTIVATION_BINDINGS
end

function Config.ActivationModes()
	return ACTIVATION_MODE_HOLD, ACTIVATION_MODE_PRESS_RELEASE
end

function Config.Copy(value)
	return Copy(value)
end

return Config
