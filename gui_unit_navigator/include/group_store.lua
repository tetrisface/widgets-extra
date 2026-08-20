local GroupStore = {}

local function UniqueSorted(values)
	local seen = {}
	local result = {}
	for _, value in ipairs(values or {}) do
		local id = tonumber(value)
		if id and not seen[id] then
			seen[id] = true
			result[#result + 1] = id
		end
	end
	table.sort(result)
	return result
end

local function Set(values)
	local result = {}
	for _, value in ipairs(values or {}) do result[value] = true end
	return result
end

local function Key(values)
	local normalized = UniqueSorted(values)
	for index = 1, #normalized do normalized[index] = tostring(normalized[index]) end
	return table.concat(normalized, ",")
end

local function RemoveAt(values, index)
	for cursor = index, #values - 1 do values[cursor] = values[cursor + 1] end
	values[#values] = nil
end

local function CopyDefinition(definition, fallbackUnitIDs)
	definition = definition or {}
	return {
		population = definition.population or "manual",
		manualUnitIDs = UniqueSorted(definition.manualUnitIDs or fallbackUnitIDs),
		unitDefIDs = UniqueSorted(definition.unitDefIDs),
		includeUnitIDs = UniqueSorted(definition.includeUnitIDs),
		excludeUnitIDs = UniqueSorted(definition.excludeUnitIDs),
		splitStrategy = definition.splitStrategy or "semantic_queue",
	}
end

function GroupStore.New(options)
	options = options or {}
	local slotCount = options.slotCount or 6
	local semantic = assert(options.semantic, "semantic queue adapter is required")
	local self = {
		pinned = {},
		mru = {},
		nextID = 1,
	}

	local function EffectiveKey(card)
		local key = card and Key(card.unitIDs) or ""
		if card then card.dedupeKey = key end
		return key
	end

	local function ExistingByDedupeKey(dedupeKey)
		for slot = 1, slotCount do
			local card = self.pinned[slot]
			if card and EffectiveKey(card) == dedupeKey then return card, "pinned", slot end
		end
		for index = 1, #self.mru do
			if EffectiveKey(self.mru[index]) == dedupeKey then return self.mru[index], "mru", index end
		end
		return nil
	end

	local function PrepareCard(card, existing)
		card = card or {}
		card.unitIDs = UniqueSorted(card.unitIDs)
		card.skippedUnitIDs = UniqueSorted(card.skippedUnitIDs)
		card.selectedUnitIDs = UniqueSorted(card.selectedUnitIDs)
		-- A recent card represents actual command recipients. The issued
		-- selection also contains skipped units and cannot identify the card.
		card.dedupeKey = Key(card.unitIDs)
		card.id = existing and existing.id or card.id or self.nextID
		if not existing and not card.id then self.nextID = self.nextID + 1 end
		if not existing and card.id == self.nextID then self.nextID = self.nextID + 1 end
		card.definition = CopyDefinition(existing and existing.definition or card.definition, card.unitIDs)
		card.pinned = existing and existing.pinned or false
		card.slot = existing and existing.slot or nil
		return card
	end

	function self:RecordRecent(card)
		local dedupeKey = card and Key(card.unitIDs)
		if not dedupeKey or dedupeKey == "" then return nil end
		local existing, location, index = ExistingByDedupeKey(dedupeKey)
		local prepared = PrepareCard(card, existing)
		if location == "pinned" then
			self.pinned[index] = prepared
			prepared.pinned = true
			prepared.slot = index
			return prepared
		end
		if location == "mru" then RemoveAt(self.mru, index) end
		table.insert(self.mru, 1, prepared)
		while #self.mru > (options.historyLimit or 24) do self.mru[#self.mru] = nil end
		return prepared
	end

	function self:Reconcile()
		local occupied = {}
		for slot = 1, slotCount do
			local card = self.pinned[slot]
			local key = EffectiveKey(card)
			if key ~= "" then occupied[key] = true end
		end

		local unique = {}
		for _, card in ipairs(self.mru) do
			local key = EffectiveKey(card)
			if key ~= "" and not occupied[key] then
				occupied[key] = true
				unique[#unique + 1] = card
			end
		end
		self.mru = unique
	end

	function self:Slots()
		local slots = {}
		local mruIndex = 1
		for slot = 1, slotCount do
			local card = self.pinned[slot]
			if not card then
				card = self.mru[mruIndex]
				mruIndex = mruIndex + 1
			end
			if card then card.slot = slot end
			slots[slot] = card
		end
		return slots
	end

	function self:Pin(slot)
		slot = tonumber(slot)
		if not slot or slot < 1 or slot > slotCount then return false end
		if self.pinned[slot] then return true end
		local card = self:Slots()[slot]
		if not card then return false end
		for index = 1, #self.mru do
			if self.mru[index] == card then RemoveAt(self.mru, index) break end
		end
		card.pinned = true
		card.slot = slot
		card.definition = CopyDefinition(card.definition, card.unitIDs)
		self.pinned[slot] = card
		return true
	end

	function self:Unpin(slot)
		slot = tonumber(slot)
		local card = slot and self.pinned[slot]
		if not card then return false end
		self.pinned[slot] = nil
		card.pinned = false
		card.slot = nil
		table.insert(self.mru, 1, card)
		return true
	end

	function self:TogglePin(slot)
		if self.pinned[tonumber(slot)] then return self:Unpin(slot) end
		return self:Pin(slot)
	end

	function self:PinnedCards()
		local cards = {}
		for slot = 1, slotCount do
			if self.pinned[slot] then cards[#cards + 1] = self.pinned[slot] end
		end
		return cards
	end

	function self:ResolvePopulation(definition, ownedUnits)
		definition = CopyDefinition(definition)
		local byID = {}
		for _, unit in ipairs(ownedUnits or {}) do byID[unit.id] = unit end
		local resultSet = {}
		if definition.population == "all_army" then
			for _, unit in ipairs(ownedUnits or {}) do
				if unit.isMobile and unit.isCombat then resultSet[unit.id] = true end
			end
		elseif definition.population == "unitdef" then
			local acceptedDefs = Set(definition.unitDefIDs)
			for _, unit in ipairs(ownedUnits or {}) do
				if acceptedDefs[unit.defID] then resultSet[unit.id] = true end
			end
		else
			for _, unitID in ipairs(definition.manualUnitIDs) do
				if byID[unitID] then resultSet[unitID] = true end
			end
		end

		for _, unitID in ipairs(definition.includeUnitIDs) do
			if byID[unitID] then resultSet[unitID] = true end
		end
		for _, unitID in ipairs(definition.excludeUnitIDs) do resultSet[unitID] = nil end

		local result = {}
		for unitID in pairs(resultSet) do result[#result + 1] = unitID end
		table.sort(result)
		return result
	end

	function self:BuildSubgroups(card, config)
		if not card then return {} end
		local definition = card.definition or {}
		local strategy = definition.splitStrategy or "semantic_queue"
		local groupsByKey = {}
		local groups = {}
		for _, unitID in ipairs(card.unitIDs or {}) do
			local defID = card.unitDefIDs and card.unitDefIDs[unitID]
			local queue = card.queuesByUnit and card.queuesByUnit[unitID] or {}
			local context = card.commandContextByUnit and card.commandContextByUnit[unitID] or {}
			local semanticKey = semantic:Fingerprint(queue, context, config)
			local key = semanticKey
			if strategy == "strict_unitdef" then
				key = "def:" .. tostring(defID or 0)
			elseif strategy == "unitdef_semantic" then
				key = "def:" .. tostring(defID or 0) .. "/" .. semanticKey
			end
			local group = groupsByKey[key]
			if not group then
				local description = semantic:Describe(queue, context, config)
				if strategy == "strict_unitdef" then
					description = {
						family = "unitdef",
						label = tostring(options.unitDefName and options.unitDefName(defID) or ("Type " .. tostring(defID or "?"))),
						iconText = "TYPE",
						buildingDefID = defID,
					}
				end
				group = {
					id = key,
					key = key,
					unitIDs = {},
					label = description.label,
					family = description.family,
					iconText = description.iconText,
					buildingDefID = description.buildingDefID,
				}
				groupsByKey[key] = group
				groups[#groups + 1] = group
			end
			group.unitIDs[#group.unitIDs + 1] = unitID
		end

		table.sort(groups, function(left, right)
			if #left.unitIDs ~= #right.unitIDs then return #left.unitIDs > #right.unitIDs end
			return left.key < right.key
		end)

		if #(card.skippedUnitIDs or {}) > 0 then
			groups[#groups + 1] = {
				id = "skipped",
				key = "skipped",
				unitIDs = UniqueSorted(card.skippedUnitIDs),
				label = "Skipped",
				family = "skipped",
				iconText = "SKIP",
				isSkipped = true,
			}
		end
		card.subgroups = groups
		return groups
	end

	function self:AllCards()
		local cards = {}
		local seen = {}
		for _, card in pairs(self.pinned) do
			cards[#cards + 1] = card
			seen[card] = true
		end
		for _, card in ipairs(self.mru) do if not seen[card] then cards[#cards + 1] = card end end
		return cards
	end

	function self:Clear()
		self.pinned = {}
		self.mru = {}
	end

	self.Key = Key
	self.CopyDefinition = CopyDefinition
	return self
end

return GroupStore
