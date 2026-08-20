local CommandObserver = {}

local function UniqueSorted(values)
	local seen = {}
	local result = {}
	for _, value in ipairs(values or {}) do
		local id = tonumber(value)
		if id and id > 0 and not seen[id] then
			seen[id] = true
			result[#result + 1] = id
		end
	end
	table.sort(result)
	return result
end

local function Copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, child in pairs(value) do result[key] = Copy(child) end
	return result
end

function CommandObserver.New(deps, options)
	deps = deps or {}
	options = options or {}
	local self = {
		pending = {},
		nextBatchID = 1,
	}

	local function CurrentFrame()
		return tonumber(deps.getFrame and deps.getFrame()) or 0
	end

	local function Selection()
		return UniqueSorted(deps.getSelection and deps.getSelection() or {})
	end

	local function IsOwned(unitID, suppliedTeamID)
		local myTeamID = deps.getMyTeamID and deps.getMyTeamID()
		if deps.getMyTeamID and myTeamID == nil then return false end
		local teamID = suppliedTeamID
		if teamID == nil and deps.getUnitTeam then teamID = deps.getUnitTeam(unitID) end
		return myTeamID == nil or teamID == myTeamID
	end

	local function Queue(unitID)
		if not deps.getUnitCommands then return {} end
		local ok, queue = pcall(deps.getUnitCommands, unitID, options.queueLimit or -1)
		return ok and type(queue) == "table" and Copy(queue) or {}
	end

	local function Snapshot(unitIDs)
		local queues = {}
		for _, unitID in ipairs(unitIDs or {}) do queues[unitID] = Queue(unitID) end
		return queues
	end

	local function NewBatch(source, selectedUnitIDs, commandID, params, commandOptions, suppliedID)
		local frame = CurrentFrame()
		local selected = UniqueSorted(selectedUnitIDs)
		local selectedSet = {}
		for _, unitID in ipairs(selected) do selectedSet[unitID] = true end
		local batch = {
			id = suppliedID or ("batch-" .. tostring(self.nextBatchID)),
			frame = frame,
			deadlineFrame = frame + (options.snapshotDelayFrames or 2),
			source = source,
			selectedUnitIDs = selected,
			selectedSet = selectedSet,
			commandID = tonumber(commandID) or commandID,
			params = Copy(params or {}),
			options = Copy(commandOptions or {}),
			recipientSet = {},
			commandContextByUnit = {},
		}
		self.nextBatchID = self.nextBatchID + 1
		batch.beforeQueues = Snapshot(batch.selectedUnitIDs)
		self.pending[#self.pending + 1] = batch
		return batch
	end

	local function FindHighLevel(commandID, frame, unitID)
		local window = tonumber(options.formationBatchWindowFrames) or 1
		for index = #self.pending, 1, -1 do
			local batch = self.pending[index]
			local matchesBatch = batch.source == "producer" and batch.recipientSet[unitID]
				or batch.source == "command_notify" and batch.selectedSet[unitID]
			if matchesBatch and frame - batch.frame <= window and batch.commandID == commandID then
				return batch
			end
		end
		return nil
	end

	local function AddRecipient(batch, unitID, context)
		if not batch or not unitID then return end
		batch.recipientSet[unitID] = true
		batch.commandContextByUnit[unitID] = batch.commandContextByUnit[unitID] or {}
		for key, value in pairs(context or {}) do batch.commandContextByUnit[unitID][key] = value end
	end

	function self:OnCommandNotify(commandID, params, commandOptions)
		local selected = Selection()
		if #selected == 0 then return false end
		NewBatch("command_notify", selected, commandID, params, commandOptions)
		return false
	end

	function self:OnUnitCommandNotify(unitID, commandID, params, commandOptions)
		if not IsOwned(unitID) then return false end
		local frame = CurrentFrame()
		local batch = FindHighLevel(commandID, frame, unitID)
		if not batch then return false end
		batch.commandID = batch.commandID or commandID
		batch.semanticKind = "formation"
		batch.deadlineFrame = math.max(batch.deadlineFrame, frame + (options.snapshotDelayFrames or 2))
		AddRecipient(batch, unitID, {
			formationBatchID = batch.id,
			issuedCommandID = commandID,
			issuedParams = Copy(params),
			issuedOptions = Copy(commandOptions),
		})
		return false
	end

	function self:OnUnitCommand(unitID, unitDefID, unitTeam, commandID, params, commandOptions, commandTag, playerID, fromSynced, fromLua)
		if not IsOwned(unitID, unitTeam) then return end
		local frame = CurrentFrame()
		local batch = FindHighLevel(commandID, frame, unitID)
		if not batch then return end
		batch.commandID = batch.commandID or commandID
		batch.deadlineFrame = math.max(batch.deadlineFrame, frame + (options.snapshotDelayFrames or 2))
		AddRecipient(batch, unitID, {
			issuedCommandID = commandID,
			issuedParams = Copy(params),
			issuedOptions = Copy(commandOptions),
			fromLua = fromLua == true,
		})
	end

	function self:RecordBatch(event)
		if type(event) ~= "table" then return false, "event must be a table" end
		if event.humanIssued ~= true then return false, "humanIssued=true is required" end
		if type(event.recipientUnitIDs) ~= "table" then return false, "recipientUnitIDs is required" end
		if event.commandID ~= nil and type(event.commandID) ~= "number" then return false, "commandID must be numeric" end
		if event.semanticKind ~= nil and event.semanticKind ~= "formation" then return false, "unsupported semanticKind" end
		if event.batchID ~= nil and #tostring(event.batchID) > 128 then return false, "batchID is too long" end
		local selected = UniqueSorted(event.selectedUnitIDs or Selection())
		local recipients = UniqueSorted(event.recipientUnitIDs)
		if #recipients == 0 then return false, "recipientUnitIDs is required" end
		local maximumUnits = tonumber(options.maximumBatchUnits) or 4096
		if #recipients > maximumUnits or #selected > maximumUnits then return false, "batch is too large" end
		local batch = NewBatch("producer", selected, event.commandID, event.params, event.options, event.batchID)
		batch.semanticKind = event.semanticKind
		local acceptedRecipients = 0
		for _, unitID in ipairs(recipients) do
			if IsOwned(unitID) then
				acceptedRecipients = acceptedRecipients + 1
				AddRecipient(batch, unitID, {
					formationBatchID = event.semanticKind == "formation" and batch.id or nil,
					issuedCommandID = event.commandID,
					issuedParams = event.paramsByUnit and Copy(event.paramsByUnit[unitID]) or nil,
				})
			end
		end
		if acceptedRecipients == 0 then
			self.pending[#self.pending] = nil
			return false, "no owned recipients"
		end
		return true, batch.id
	end

	local function QueueChanged(before, after)
		if deps.queueFingerprint then return deps.queueFingerprint(before or {}) ~= deps.queueFingerprint(after or {}) end
		if #(before or {}) ~= #(after or {}) then return true end
		for index = 1, #(before or {}) do
			if before[index].id ~= after[index].id then return true end
		end
		return false
	end

	local function Complete(batch)
		local queuesByUnit = Snapshot(batch.selectedUnitIDs)
		if batch.source == "command_notify" then
			for _, unitID in ipairs(batch.selectedUnitIDs) do
				if not batch.recipientSet[unitID] and QueueChanged(batch.beforeQueues[unitID], queuesByUnit[unitID]) then
					AddRecipient(batch, unitID)
				end
			end
		end

		local recipients = {}
		for unitID in pairs(batch.recipientSet) do
			if IsOwned(unitID) then
				recipients[#recipients + 1] = unitID
				if not queuesByUnit[unitID] then queuesByUnit[unitID] = Queue(unitID) end
			end
		end
		table.sort(recipients)
		if #recipients == 0 then return end

		local skipped = {}
		for _, unitID in ipairs(batch.selectedUnitIDs) do
			if not batch.recipientSet[unitID] and IsOwned(unitID) then skipped[#skipped + 1] = unitID end
		end
		if batch.semanticKind == "formation" then
			for _, unitID in ipairs(recipients) do
				batch.commandContextByUnit[unitID] = batch.commandContextByUnit[unitID] or {}
				batch.commandContextByUnit[unitID].formationBatchID = batch.id
			end
		end

		if deps.onBatch then
			deps.onBatch({
				id = batch.id,
				frame = batch.frame,
				source = batch.source,
				selectedUnitIDs = batch.selectedUnitIDs,
				recipientUnitIDs = recipients,
				skippedUnitIDs = skipped,
				commandID = batch.commandID,
				params = batch.params,
				options = batch.options,
				queuesByUnit = queuesByUnit,
				commandContextByUnit = batch.commandContextByUnit,
			})
		end
	end

	function self:Flush(frame)
		frame = tonumber(frame) or CurrentFrame()
		local remaining = {}
		for _, batch in ipairs(self.pending) do
			if frame >= batch.deadlineFrame then Complete(batch) else remaining[#remaining + 1] = batch end
		end
		self.pending = remaining
	end

	function self:Reset()
		self.pending = {}
	end

	return self
end

return CommandObserver
