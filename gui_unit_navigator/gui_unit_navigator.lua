if not RmlUi then return end

local widget = widget

-- BAR's canonical key constants are more reliable than GetKeyCode for lock keys.
if not KEYSYMS and VFS and VFS.Include then pcall(VFS.Include, "LuaUI/Headers/keysym.h.lua") end

function widget:GetInfo()
	return {
		name = "Unit Navigator",
		desc = "Hold a key to preview and select recent command groups and semantic subgroups",
		author = "tetrisface",
		date = "2026",
		license = "GNU GPL, v2 or later",
		layer = 15,
		enabled = true,
	}
end

local WIDGET_PATH = "LuaUI/Widgets/gui_unit_navigator/"
local INCLUDE_PATH = WIDGET_PATH .. "include/"
local RML_PATH = WIDGET_PATH .. "gui_unit_navigator.rml"
local MODEL_NAME = "unit_navigator_model"
local ROOT_ID = "unit-navigator-root"
local GRID_ID = "unit-navigator-grid-shell"
local HEADER_ID = "unit-navigator-overlay-header"
local SETTINGS_ID = "unit-navigator-settings"
local REFRESH_VISIBLE_SECONDS = 0.15
local REFRESH_BACKGROUND_SECONDS = 1

local Config = VFS.Include(INCLUDE_PATH .. "config.lua")
local RestartGuard = VFS.Include(INCLUDE_PATH .. "restart_guard.lua")
local RmlKeyMapper = VFS.Include(INCLUDE_PATH .. "rml_key_mapper.lua")
local RAPID_RESTART_THRESHOLD = RestartGuard.DEFAULT_THRESHOLD
local RAPID_RESTART_WINDOW_SECONDS = RestartGuard.DEFAULT_WINDOW_SECONDS
local ACTIVATION_RECOVERY_NOTICE = string.format(
	"Activation shortcuts cleared after %d rapid restarts within %d seconds. Add a new key; onboarding will reopen until one is set.",
	RAPID_RESTART_THRESHOLD,
	RAPID_RESTART_WINDOW_SECONDS
)
local QueueSemantics = VFS.Include(INCLUDE_PATH .. "queue_semantics.lua")
local GroupStore = VFS.Include(INCLUDE_PATH .. "group_store.lua")
local CommandObserver = VFS.Include(INCLUDE_PATH .. "command_observer.lua")
local InteractionController = VFS.Include(INCLUDE_PATH .. "interaction_controller.lua")
local CameraAdapter = VFS.Include(INCLUDE_PATH .. "camera_adapter.lua")
local ViewModel = VFS.Include(INCLUDE_PATH .. "view_model.lua")
local ActivationController = VFS.Include(INCLUDE_PATH .. "activation_controller.lua")

local config = Config.Defaults()
local state = {
	context = nil,
	document = nil,
	dm = nil,
	semantic = nil,
	store = nil,
	observer = nil,
	interaction = nil,
	camera = nil,
	activation = nil,
	elapsedSeconds = 0,
	refreshElapsed = 0,
	refreshRequested = true,
	captureTarget = nil,
	captureTargetLabel = nil,
	ignoreCardClickUntil = nil,
	onboardingComplete = false,
	rapidStartTimestamps = {},
	settingsNotice = nil,
	ownsText = false,
	releaseTextOnKeyCode = nil,
}

local function SafeCall(method, ...)
	if not method then return nil end
	local ok, first, second, third = pcall(method, ...)
	if not ok then return nil end
	return first, second, third
end

local function SafeValue(method, ...)
	local value = SafeCall(method, ...)
	return value
end

local function WallClockSeconds()
	if not os or not os.time then return nil end
	return tonumber(SafeValue(os.time))
end

local function OwnShortcutText()
	if state.ownsText then return true end
	if not widgetHandler or not widgetHandler.OwnText then return false end
	-- BAR dispatches the text owner before bound actions, which lets the capture
	-- see keys that would otherwise be consumed before ordinary widget call-ins.
	local ok, owned = pcall(widgetHandler.OwnText, widgetHandler)
	state.ownsText = ok and owned == true
	return state.ownsText
end

local function DisownShortcutText()
	state.releaseTextOnKeyCode = nil
	if not state.ownsText then return false end
	state.ownsText = false
	if not widgetHandler or not widgetHandler.DisownText then return false end
	local ok, disowned = pcall(widgetHandler.DisownText, widgetHandler)
	return ok and disowned == true
end

local function CommandMap()
	local ids = CMD or {}
	local families = {}
	local labels = {}
	local function Add(id, family, label)
		if not id then return end
		families[id] = family
		labels[id] = label
	end
	Add(ids.MOVE, "move", "Move")
	Add(ids.FIGHT, "attack", "Fight")
	Add(ids.ATTACK, "attack", "Attack")
	Add(ids.AREA_ATTACK, "attack", "Area attack")
	Add(ids.PATROL, "patrol", "Patrol")
	Add(ids.GUARD, "other", "Guard")
	Add(ids.REPAIR, "other", "Repair")
	Add(ids.RECLAIM, "other", "Reclaim")
	Add(ids.RESURRECT, "other", "Resurrect")
	Add(ids.LOAD_UNITS, "other", "Load")
	Add(ids.UNLOAD_UNITS, "other", "Unload")
	Add(ids.STOP, "other", "Stop")
	return families, labels, ids.INSERT
end

local function UnitDefName(unitDefID)
	local definition = UnitDefs and UnitDefs[tonumber(unitDefID)]
	return definition and (definition.translatedHumanName or definition.humanName or definition.name) or tostring(unitDefID or "Unknown")
end

local function ExistingImagePath(path)
	if type(path) ~= "string" or path == "" or not VFS or not VFS.FileExists then return nil end
	local normalized = string.gsub(string.gsub(path, "\\", "/"), "^/+", "")
	if normalized == "" or not SafeValue(VFS.FileExists, normalized) then return nil end
	return "/" .. normalized
end

local function UnitPortraitPath(unitDefID)
	local definition = UnitDefs and UnitDefs[tonumber(unitDefID)]
	if not definition then return nil end
	local buildPic = definition.buildPic or definition.buildpic
	local resolved = ExistingImagePath(buildPic)
	if resolved then return resolved end
	if type(buildPic) == "string" and not string.find(buildPic, "/", 1, true) then
		resolved = ExistingImagePath("unitpics/" .. buildPic)
		if resolved then return resolved end
	end
	local name = definition.name
	if type(name) ~= "string" or name == "" then return nil end
	return ExistingImagePath("unitpics/" .. name .. ".dds")
		or ExistingImagePath("unitpics/" .. name .. ".png")
end

local function CurrentFrame()
	return tonumber(SafeValue(Spring.GetGameFrame)) or 0
end

local function CurrentViewGeometry()
	local width, height = SafeCall(Spring.GetViewGeometry)
	return tonumber(width) or 1920, tonumber(height) or 1080
end

local function ValidKeyCode(value)
	value = tonumber(value)
	if not value or value < 1 or value > 65535 then return nil end
	return math.floor(value)
end

local function ResolveNamedKeyCode(name, fallback)
	local symbolName = string.upper(tostring(name or "")):gsub("[^A-Z0-9_]", "")
	local symbol = KEYSYMS and ValidKeyCode(KEYSYMS[symbolName])
	if symbol then return symbol end
	local engineCode = SafeValue(Spring.GetKeyCode, string.lower(tostring(name or "")))
	return ValidKeyCode(engineCode) or ValidKeyCode(fallback)
end

local function ResolveDefaultKeyCodes()
	for _, binding in ipairs(config.activationBindings or {}) do
		if binding.keyName == "CapsLock" then
			binding.keyCode = ResolveNamedKeyCode(binding.keyName, binding.keyCode)
		end
	end
	config = Config.Normalize(config)
	if config.cancelKeyName == "Escape" then
		config.cancelKeyCode = ResolveNamedKeyCode(config.cancelKeyName, config.cancelKeyCode)
	end
	for index, name in ipairs(config.gridKeyNames) do
		config.gridKeyCodes[index] = ResolveNamedKeyCode(name, config.gridKeyCodes[index])
	end
end

local function ControllableTeamID()
	if Spring.GetSpectatingState then
		local spectating = SafeValue(Spring.GetSpectatingState)
		if spectating then return -1 end
	end
	return SafeValue(Spring.GetMyTeamID)
end

local function OwnedUnitRecords()
	local myTeamID = ControllableTeamID()
	if not myTeamID or myTeamID < 0 then return {} end
	local unitIDs = SafeValue(Spring.GetTeamUnits, myTeamID) or {}
	local records = {}
	for _, unitID in ipairs(unitIDs) do
		local defID = SafeValue(Spring.GetUnitDefID, unitID)
		local definition = UnitDefs and UnitDefs[defID]
		local weapons = definition and definition.weapons or {}
		records[#records + 1] = {
			id = unitID,
			defID = defID,
			isMobile = definition and (definition.canMove == true or (tonumber(definition.speed) or 0) > 0) or false,
			isCombat = definition and #weapons > 0 or false,
		}
	end
	return records
end

local function OwnedUnitSet(records)
	local result = {}
	for _, record in ipairs(records or {}) do result[record.id] = record end
	return result
end

local function FilterOwned(unitIDs, ownedByID)
	local result = {}
	for _, unitID in ipairs(unitIDs or {}) do
		if ownedByID[unitID] then result[#result + 1] = unitID end
	end
	table.sort(result)
	return result
end

local function CommandAllowed(commandID)
	local family = state.semantic:Family({id = commandID, params = {}})
	return config.commandFamilyFilters[family] ~= false
end

local function DescribeCommand(event)
	local firstRecipient = event.recipientUnitIDs and event.recipientUnitIDs[1]
	local queue = firstRecipient and event.queuesByUnit and event.queuesByUnit[firstRecipient]
	if queue and #queue > 0 then
		return state.semantic:Describe(queue, event.commandContextByUnit and event.commandContextByUnit[firstRecipient], config).label
	end
	local description = state.semantic:Describe({{
		id = event.commandID,
		params = event.params,
		options = event.options,
	}}, nil, config)
	return description.label
end

local ApplyModel
local RefreshCards

local function ModelInput()
	local slots = state.store and state.store:Slots() or {}
	local activeBinding = state.activation and state.activation:ActiveBinding()
	return {
		config = config,
		slots = slots,
		pinnedCards = state.store and state.store:PinnedCards() or {},
		interaction = state.interaction,
		activeActivationKeyLabel = activeBinding and activeBinding.keyName,
		activeActivationMode = activeBinding and activeBinding.mode,
		activationBindingLimit = Config.MaximumActivationBindings(),
		unitDefName = UnitDefName,
		unitPortraitPath = UnitPortraitPath,
		mapSizeX = Game and Game.mapSizeX or 1,
		mapSizeZ = Game and Game.mapSizeZ or 1,
		captureTarget = state.captureTarget,
		captureTargetLabel = state.captureTargetLabel,
		settingsNotice = state.settingsNotice,
	}
end

local function SetDocumentVisibility(visible)
	if not state.document then return end
	if visible then state.document:Show() else state.document:Hide() end
end

ApplyModel = function()
	if not state.interaction then return end
	local model = ViewModel.Build(ModelInput())
	if state.dm then
		for key, value in pairs(model) do state.dm[key] = value end
	end
	SetDocumentVisibility(model.overlayVisible or model.settingsVisible)
end

local function QueueFor(unitID, cache)
	if cache[unitID] ~= nil then return cache[unitID] end
	cache[unitID] = SafeValue(Spring.GetUnitCommands, unitID, -1) or {}
	return cache[unitID]
end

local function PositionFor(unitID, cache)
	if cache[unitID] ~= nil then return cache[unitID] end
	local x, y, z = SafeCall(Spring.GetUnitPosition, unitID)
	cache[unitID] = x and {unitID = unitID, x = x, y = y or 0, z = z} or false
	return cache[unitID]
end

local function RefreshCommandContext(card, unitID, queue)
	local context = card.commandContextByUnit and card.commandContextByUnit[unitID]
	if not context or not context.formationBatchID or not context.issuedCommandID then return end
	for _, command in ipairs(queue or {}) do
		if command.id == context.issuedCommandID then return end
	end
	if CurrentFrame() - (card.lastCommandFrame or 0) <= 30 then return end
	context.formationBatchID = nil
	context.issuedCommandID = nil
	context.issuedParams = nil
	context.issuedOptions = nil
end

RefreshCards = function()
	if not state.store then return end
	local cards = state.store:AllCards()
	if #cards == 0 then
		state.refreshRequested = false
		ApplyModel()
		return
	end
	local owned = OwnedUnitRecords()
	local ownedByID = OwnedUnitSet(owned)
	local queueCache = {}
	local positionCache = {}
	local knownPositions = {}
	for _, unit in ipairs(owned) do
		local position = PositionFor(unit.id, positionCache)
		if position then knownPositions[#knownPositions + 1] = position end
	end

	for _, card in ipairs(cards) do
		if card.pinned then
			card.unitIDs = state.store:ResolvePopulation(card.definition, owned)
			if card.definition.population == "manual" then
				card.definition.manualUnitIDs = FilterOwned(card.definition.manualUnitIDs, ownedByID)
			end
		else
			card.unitIDs = FilterOwned(card.unitIDs, ownedByID)
			card.skippedUnitIDs = FilterOwned(card.skippedUnitIDs, ownedByID)
		end
		card.disabled = #card.unitIDs == 0
		card.unitDefIDs = card.unitDefIDs or {}
		card.queuesByUnit = card.queuesByUnit or {}
		for _, unitID in ipairs(card.unitIDs) do
			card.unitDefIDs[unitID] = ownedByID[unitID] and ownedByID[unitID].defID or SafeValue(Spring.GetUnitDefID, unitID)
			card.queuesByUnit[unitID] = QueueFor(unitID, queueCache)
			RefreshCommandContext(card, unitID, card.queuesByUnit[unitID])
		end
		card.knownPositions = knownPositions
		state.store:BuildSubgroups(card, config)
	end
	state.store:Reconcile()
	state.refreshRequested = false
	ApplyModel()
end

local function SelectOwnedUnits(unitIDs)
	local ownedByID = OwnedUnitSet(OwnedUnitRecords())
	local selection = FilterOwned(unitIDs, ownedByID)
	if #selection == 0 or not Spring.SelectUnitArray then return false end
	Spring.SelectUnitArray(selection, false)
	return true
end

local function StopEvent(event)
	if event and event.StopPropagation then pcall(event.StopPropagation, event) end
end

local function InstallController()
	state.camera = CameraAdapter.New({
		GetCameraState = Spring.GetCameraState,
		SetCameraState = Spring.SetCameraState,
		SetCameraTarget = Spring.SetCameraTarget,
		GetUnitPosition = Spring.GetUnitPosition,
	})
	state.interaction = InteractionController.New({
		getSlots = function() return state.store:Slots() end,
		onOpen = function()
			state.camera:Capture()
			state.refreshRequested = true
			RefreshCards()
		end,
		onPreview = function(unitIDs)
			if config.cameraPreview then state.camera:Preview(unitIDs, config.cameraTransitionSeconds) end
			ApplyModel()
		end,
		onCommit = function(unitIDs)
			if state.activation then state.activation:Reset() end
			SelectOwnedUnits(unitIDs)
			state.camera:Commit()
			ApplyModel()
		end,
		onCancel = function()
			if state.activation then state.activation:Reset() end
			state.camera:Restore(config.cameraTransitionSeconds)
			ApplyModel()
		end,
		onSettings = function(open)
			if state.activation then state.activation:Reset() end
			if open then state.camera:Restore(config.cameraTransitionSeconds) end
			ApplyModel()
		end,
		onChange = function() ApplyModel() end,
	})
end

local function InstallActivationController()
	state.activation = ActivationController.New({
		findBinding = function(keyCode) return Config.FindActivation(config, keyCode) end,
		isOpen = function() return state.interaction and state.interaction.active == true end,
		onOpen = function() return state.interaction and state.interaction:Open() or false end,
		onCommit = function() return state.interaction and state.interaction:ReleaseActivation() or false end,
	})
end

local function OnObservedBatch(event)
	if not event or not CommandAllowed(event.commandID) then return end
	local selectedUnitIDs = event.selectedUnitIDs
	if not selectedUnitIDs or #selectedUnitIDs == 0 then selectedUnitIDs = event.recipientUnitIDs end
	local card = state.store:RecordRecent({
		unitIDs = event.recipientUnitIDs,
		skippedUnitIDs = event.skippedUnitIDs,
		selectedUnitIDs = selectedUnitIDs,
		taskLabel = DescribeCommand(event),
		queuesByUnit = event.queuesByUnit,
		commandContextByUnit = event.commandContextByUnit,
		lastCommandFrame = event.frame,
	})
	if not card then return end
	state.refreshRequested = true
	RefreshCards()
end

local function InstallObserver()
	state.observer = CommandObserver.New({
		getFrame = CurrentFrame,
		getSelection = Spring.GetSelectedUnits,
		getMyTeamID = ControllableTeamID,
		getUnitTeam = Spring.GetUnitTeam,
		getUnitCommands = Spring.GetUnitCommands,
		queueFingerprint = function(queue) return state.semantic:Fingerprint(queue, nil, config) end,
		onBatch = OnObservedBatch,
	}, {
		snapshotDelayFrames = 2,
		formationBatchWindowFrames = config.formationBatchWindowFrames,
		queueLimit = -1,
		maximumBatchUnits = 4096,
	})
end

local function ReleaseResources()
	DisownShortcutText()
	if state.observer then state.observer:Reset() end
	if state.context and state.dm then
		pcall(state.context.RemoveDataModel, state.context, MODEL_NAME)
		state.dm = nil
	end
	if state.document then
		pcall(state.document.Close, state.document)
		state.document = nil
	end
	if WG.UnitNavigator then WG.UnitNavigator = nil end
	state.context = nil
	state.interaction = nil
	state.activation = nil
	state.observer = nil
	state.camera = nil
end

local function InstallPublicApi()
	WG.UnitNavigator = {
		RecordBatch = function(event) return state.observer:RecordBatch(event) end,
		Open = function() return state.interaction:Open() end,
		Cancel = function(reason) return state.interaction:Cancel(reason or "api") end,
		OpenSettings = function() return state.interaction:OpenSettings() end,
		Refresh = function()
			state.refreshRequested = true
			RefreshCards()
		end,
		GetSlots = function() return Config.Copy(state.store:Slots()) end,
	}
end

local function RecordStartup()
	local shouldRecover
	state.rapidStartTimestamps, shouldRecover = RestartGuard.Record(
		state.rapidStartTimestamps,
		WallClockSeconds(),
		{threshold = RAPID_RESTART_THRESHOLD, windowSeconds = RAPID_RESTART_WINDOW_SECONDS}
	)
	if not shouldRecover then return end
	config = Config.WithoutActivation(config)
	state.onboardingComplete = false
	state.settingsNotice = ACTIVATION_RECOVERY_NOTICE
end

function widget:Initialize()
	RecordStartup()
	ResolveDefaultKeyCodes()
	local families, labels, insertCommandID = CommandMap()
	state.semantic = QueueSemantics.New({
		insertCommandID = insertCommandID,
		commandFamilies = families,
		commandLabels = labels,
		unitDefName = UnitDefName,
	})
	state.store = GroupStore.New({semantic = state.semantic, unitDefName = UnitDefName, slotCount = 6})
	InstallController()
	InstallActivationController()
	InstallObserver()

	state.context = SafeValue(RmlUi.GetContext, "shared")
	if not state.context then ReleaseResources() return false end
	local initialized, complete = pcall(function()
		state.dm = state.context:OpenDataModel(MODEL_NAME, ViewModel.Build(ModelInput()), self)
		if not state.dm then return false end
		state.document = state.context:LoadDocument(RML_PATH, self)
		if not state.document then return false end
		state.document:ReloadStyleSheet()
		state.document:Hide()
		return true
	end)
	if not initialized or not complete then ReleaseResources() return false end
	InstallPublicApi()
	if not state.onboardingComplete then state.interaction:OpenSettings() end
	return true
end

function widget:Shutdown()
	ReleaseResources()
end

function widget:GetConfigData()
	return {
		version = Config.Version(),
		onboardingComplete = state.onboardingComplete,
		rapidStartTimestamps = Config.Copy(state.rapidStartTimestamps),
		config = Config.Copy(config),
	}
end

function widget:SetConfigData(data)
	local saved = type(data) == "table" and (data.config or data) or nil
	local version = type(data) == "table" and data.version or nil
	config = Config.FromSaved(saved, version)
	state.onboardingComplete = type(data) == "table" and data.onboardingComplete == true
	state.rapidStartTimestamps = type(data) == "table" and Config.Copy(data.rapidStartTimestamps or {}) or {}
	state.settingsNotice = nil
	if not Config.HasActivation(config) then
		state.onboardingComplete = false
		state.settingsNotice = ACTIVATION_RECOVERY_NOTICE
	end
end

function widget:CommandNotify(commandID, params, options)
	return state.observer and state.observer:OnCommandNotify(commandID, params, options) or false
end

-- BAR's formation widgets may call this before issuing one engine order array.
-- It is intentionally only an input seam; Unit Navigator never calls those widgets.
function widget:UnitCommandNotify(unitID, commandID, params, options)
	return state.observer and state.observer:OnUnitCommandNotify(unitID, commandID, params, options) or false
end

function widget:UnitCommand(unitID, unitDefID, unitTeam, commandID, params, options, commandTag, playerID, fromSynced, fromLua)
	if state.observer then
		state.observer:OnUnitCommand(unitID, unitDefID, unitTeam, commandID, params, options, commandTag, playerID, fromSynced, fromLua)
	end
end

local function KeyName(keyCode, label)
	if type(label) == "string" and label ~= "" then return string.upper(label) end
	local symbol = SafeValue(Spring.GetKeySymbol, keyCode)
	if type(symbol) == "string" and symbol ~= "" then return string.upper(symbol) end
	return tostring(keyCode)
end

local function CaptureKey(keyCode, label)
	local target = state.captureTarget
	if not target then return false end
	keyCode = ValidKeyCode(keyCode)
	if not keyCode then return false end
	local name = KeyName(keyCode, label)
	if target == "activation" or target == "activation_add" or string.match(target, "^activation%d+$") then
		local index
		if target == "activation_add" then
			index = #(config.activationBindings or {}) + 1
		elseif target == "activation" then
			index = 1
		else
			index = tonumber(string.match(target, "^activation(%d+)$"))
		end
		local existing = config.activationBindings and config.activationBindings[index]
		local updated
		config, updated = Config.SetActivationBinding(config, index, {
			keyCode = keyCode,
			keyName = name,
			mode = existing and existing.mode or "hold",
		})
		if not updated then return false end
		state.settingsNotice = nil
	elseif target == "cancel" then
		config.cancelKeyCode = keyCode
		config.cancelKeyName = name
	else
		local index = tonumber(string.match(target, "^grid(%d)$"))
		if not index then return false end
		config.gridKeyCodes[index] = keyCode
		config.gridKeyNames[index] = name
	end
	state.captureTarget = nil
	state.captureTargetLabel = nil
	if state.ownsText then state.releaseTextOnKeyCode = keyCode end
	ApplyModel()
	return true
end

local function RmlEventKeyIdentifier(event)
	local parameters = event and event.parameters
	if not parameters then return nil end
	local ok, identifier = pcall(function() return parameters.key_identifier end)
	return ok and identifier or nil
end

function widget:CaptureRmlKey(event)
	if not state.captureTarget then return false end
	StopEvent(event)
	local keyCode, label = RmlKeyMapper.Resolve(RmlEventKeyIdentifier(event), RmlUi.key_identifier, KEYSYMS)
	if not keyCode then return true end
	return CaptureKey(keyCode, label)
end

function widget:ReleaseRmlKey(event)
	local pendingKeyCode = state.releaseTextOnKeyCode
	if not pendingKeyCode then return false end
	local keyCode = RmlKeyMapper.Resolve(RmlEventKeyIdentifier(event), RmlUi.key_identifier, KEYSYMS)
	if keyCode ~= pendingKeyCode then return false end
	StopEvent(event)
	DisownShortcutText()
	return true
end

local function GridKeyIndex(keyCode)
	for index = 1, 6 do if config.gridKeyCodes[index] == keyCode then return index end end
	return nil
end

local function CloseSettings()
	local closed = state.interaction:CloseSettings()
	if not closed then return false end
	state.captureTarget = nil
	state.captureTargetLabel = nil
	DisownShortcutText()
	state.onboardingComplete = Config.HasActivation(config)
	return true
end

function widget:KeyPress(keyCode, mods, isRepeat, label)
	if state.captureTarget then return CaptureKey(keyCode, label) end
	if state.interaction.settingsOpen and keyCode == config.cancelKeyCode then return CloseSettings() end
	if state.activation and state.activation:KeyPress(keyCode, isRepeat) then return true end
	if not state.interaction.active then return false end
	if keyCode == config.cancelKeyCode then return state.interaction:Cancel("escape") end
	local index = GridKeyIndex(keyCode)
	if index then
		if not isRepeat then state.interaction:PressGrid(index) end
		return true
	end
	return false
end

function widget:KeyRelease(keyCode)
	if state.releaseTextOnKeyCode == keyCode then
		DisownShortcutText()
		return true
	end
	if state.activation and state.activation:KeyRelease(keyCode) then return true end
	return false
end

local function ElementBounds(element)
	if not element then return nil end
	return element.absolute_left or 0, element.absolute_top or 0, element.offset_width or 0, element.offset_height or 0
end

local function MouseInsideCombinedBounds(elements, guard)
	local minimumLeft, minimumTop, maximumRight, maximumBottom
	for _, element in ipairs(elements or {}) do
		local left, top, width, height = ElementBounds(element)
		if left and width > 0 and height > 0 then
			minimumLeft = minimumLeft and math.min(minimumLeft, left) or left
			minimumTop = minimumTop and math.min(minimumTop, top) or top
			maximumRight = maximumRight and math.max(maximumRight, left + width) or (left + width)
			maximumBottom = maximumBottom and math.max(maximumBottom, top + height) or (top + height)
		end
	end
	if not minimumLeft then return true end
	local mouseX, mouseY = SafeCall(Spring.GetMouseState)
	local _, viewHeight = CurrentViewGeometry()
	local topDownY = viewHeight - (mouseY or 0)
	guard = tonumber(guard) or 0
	return mouseX >= minimumLeft - guard and mouseX <= maximumRight + guard
		and topDownY >= minimumTop - guard and topDownY <= maximumBottom + guard
end

local function UpdateMouseLeave()
	if not state.interaction.active or not state.document then return end
	local grid = state.document:GetElementById(GRID_ID)
	local header = state.document:GetElementById(HEADER_ID)
	if MouseInsideCombinedBounds({header, grid}, config.mouseLeaveGuardDp) then
		state.interaction:Enter()
	elseif not state.interaction.leaveDeadline then
		state.interaction:Leave(state.elapsedSeconds, config.mouseLeaveDelaySeconds)
	end
end

function widget:Update(deltaSeconds)
	deltaSeconds = tonumber(deltaSeconds) or 0
	state.elapsedSeconds = state.elapsedSeconds + deltaSeconds
	state.refreshElapsed = state.refreshElapsed + deltaSeconds
	if state.observer then state.observer:Flush(CurrentFrame()) end
	UpdateMouseLeave()
	if state.interaction then state.interaction:Update(state.elapsedSeconds) end
	local interval = state.interaction and (state.interaction.active or state.interaction.settingsOpen) and REFRESH_VISIBLE_SECONDS or REFRESH_BACKGROUND_SECONDS
	if state.refreshRequested or state.refreshElapsed >= interval then
		state.refreshElapsed = 0
		RefreshCards()
	end
end

function widget:UnitDestroyed() state.refreshRequested = true end
function widget:UnitTaken() state.refreshRequested = true end
function widget:UnitGiven() state.refreshRequested = true end
function widget:ViewResize() if state.interaction and (state.interaction.active or state.interaction.settingsOpen) then ApplyModel() end end

function widget:IsAbove(x, y)
	if not state.document or not state.interaction then return false end
	if not state.interaction.active and not state.interaction.settingsOpen then return false end
	local id = state.interaction.settingsOpen and SETTINGS_ID or GRID_ID
	local element = state.document:GetElementById(id)
	local left, top, width, height = ElementBounds(element)
	if not left then return false end
	local _, viewHeight = CurrentViewGeometry()
	local topDownY = viewHeight - y
	return x >= left and x <= left + width and topDownY >= top and topDownY <= top + height
end

function widget:MousePress(x, y, button)
	if state.interaction and state.interaction.active and button == 3 then return state.interaction:Cancel("right_click") end
	if state.interaction and (state.interaction.active or state.interaction.settingsOpen) and self:IsAbove(x, y) then return true end
	return false
end

local function EventAttribute(event, name)
	local element = event and event.current_element
	if not element or not element.GetAttribute then return nil end
	return element:GetAttribute(name)
end

function widget:HoverCard(event)
	if event and event.target_element and event.current_element and event.target_element ~= event.current_element then return end
	state.interaction:FocusCard(EventAttribute(event, "data-slot"), true)
	ApplyModel()
end

function widget:HoverSubgroup(event)
	state.interaction:FocusSubgroup(EventAttribute(event, "data-slot"), EventAttribute(event, "data-index"))
	ApplyModel()
end

function widget:ClickCard(event)
	if state.ignoreCardClickUntil and state.elapsedSeconds <= state.ignoreCardClickUntil then return end
	state.interaction:ClickCard(EventAttribute(event, "data-slot"))
end

function widget:ClickSubgroup(event)
	StopEvent(event)
	state.interaction:ClickSubgroup(EventAttribute(event, "data-slot"), EventAttribute(event, "data-index"))
end

function widget:TogglePin(event)
	StopEvent(event)
	state.ignoreCardClickUntil = state.elapsedSeconds + 0.05
	state.store:TogglePin(EventAttribute(event, "data-slot"))
	state.refreshRequested = true
	RefreshCards()
end

function widget:OpenSettings(event)
	StopEvent(event)
	state.interaction:OpenSettings()
end

function widget:CloseSettings()
	return CloseSettings()
end

function widget:BeginShortcutCapture(event)
	state.captureTarget = tostring(EventAttribute(event, "data-target") or "")
	state.captureTargetLabel = tostring(EventAttribute(event, "data-label") or state.captureTarget)
	OwnShortcutText()
	ApplyModel()
end

function widget:CycleActivationMode(event)
	local index = tonumber(EventAttribute(event, "data-index"))
	local binding = index and config.activationBindings[index]
	if not binding then return false end
	local candidate = Config.Copy(binding)
	candidate.mode = candidate.mode == "hold" and "press_release" or "hold"
	local updated
	config, updated = Config.SetActivationBinding(config, index, candidate)
	if updated then ApplyModel() end
	return updated
end

function widget:RemoveActivationBinding(event)
	local updated
	config, updated = Config.RemoveActivationBinding(config, EventAttribute(event, "data-index"))
	if not updated then return false end
	if not Config.HasActivation(config) then
		state.onboardingComplete = false
		state.settingsNotice = "Add at least one activation key before closing onboarding."
	end
	ApplyModel()
	return true
end

local SETTING_STEPS = {
	cameraTransitionSeconds = 0.05,
	mouseLeaveGuardDp = 4,
	mouseLeaveDelaySeconds = 0.05,
	glassOpacity = 0.05,
	terrainOpacity = 0.05,
	nonGroupUnitOpacity = 0.05,
	formationBatchWindowFrames = 1,
	buildPositionTolerance = 2,
}

function widget:AdjustSetting(event)
	local key = tostring(EventAttribute(event, "data-setting") or "")
	local direction = tonumber(EventAttribute(event, "data-direction")) or 0
	local step = SETTING_STEPS[key]
	if not step or direction == 0 then return end
	local candidate = Config.Copy(config)
	candidate[key] = (tonumber(candidate[key]) or 0) + step * direction
	config = Config.Normalize(candidate)
	if key == "formationBatchWindowFrames" then InstallObserver() end
	state.refreshRequested = true
	RefreshCards()
end

function widget:ToggleCameraPreview()
	config.cameraPreview = not config.cameraPreview
	ApplyModel()
end

function widget:CycleQueuePolicy()
	config.queueEquivalencePolicy = config.queueEquivalencePolicy == "semantic" and "strict" or "semantic"
	state.refreshRequested = true
	RefreshCards()
end

function widget:ToggleCommandFamily(event)
	local family = tostring(EventAttribute(event, "data-family") or "")
	if config.commandFamilyFilters[family] == nil then return end
	config.commandFamilyFilters[family] = not config.commandFamilyFilters[family]
	ApplyModel()
end

local POPULATIONS = {manual = "unitdef", unitdef = "all_army", all_army = "manual"}
local SPLITS = {semantic_queue = "strict_unitdef", strict_unitdef = "unitdef_semantic", unitdef_semantic = "semantic_queue"}

local function PinnedCard(slot)
	return state.store.pinned[tonumber(slot)]
end

function widget:CyclePinnedPopulation(event)
	local card = PinnedCard(EventAttribute(event, "data-slot"))
	if not card then return end
	local definition = card.definition
	definition.population = POPULATIONS[definition.population] or "manual"
	if definition.population == "unitdef" and #definition.unitDefIDs == 0 then
		local seen = {}
		for _, unitID in ipairs(card.unitIDs) do
			local defID = SafeValue(Spring.GetUnitDefID, unitID)
			if defID and not seen[defID] then
				seen[defID] = true
				definition.unitDefIDs[#definition.unitDefIDs + 1] = defID
			end
		end
		table.sort(definition.unitDefIDs)
	end
	state.refreshRequested = true
	RefreshCards()
end

function widget:CyclePinnedSplit(event)
	local card = PinnedCard(EventAttribute(event, "data-slot"))
	if not card then return end
	card.definition.splitStrategy = SPLITS[card.definition.splitStrategy] or "semantic_queue"
	state.refreshRequested = true
	RefreshCards()
end

local function SetSelectionException(event, key)
	local card = PinnedCard(EventAttribute(event, "data-slot"))
	if not card then return end
	card.definition[key] = Spring.GetSelectedUnits and Spring.GetSelectedUnits() or {}
	state.refreshRequested = true
	RefreshCards()
end

function widget:SetPinnedIncludes(event) SetSelectionException(event, "includeUnitIDs") end
function widget:SetPinnedExcludes(event) SetSelectionException(event, "excludeUnitIDs") end

function widget:ClearPinnedExceptions(event)
	local card = PinnedCard(EventAttribute(event, "data-slot"))
	if not card then return end
	card.definition.includeUnitIDs = {}
	card.definition.excludeUnitIDs = {}
	state.refreshRequested = true
	RefreshCards()
end

function widget:RestoreDefaults()
	config = Config.Defaults()
	state.captureTarget = nil
	state.captureTargetLabel = nil
	state.settingsNotice = nil
	if state.activation then state.activation:Reset() end
	DisownShortcutText()
	InstallObserver()
	state.refreshRequested = true
	RefreshCards()
end
