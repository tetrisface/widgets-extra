local ViewModel = {}

local POPULATION_LABELS = {
	manual = "Manual set",
	unitdef = "Exact unit types",
	all_army = "All army",
}

local SPLIT_LABELS = {
	semantic_queue = "Semantic queue",
	strict_unitdef = "Strict unit type",
	unitdef_semantic = "Unit type -> queue",
}

local SETTINGS_GLASS_OPACITY = 0.82
local UNIT_CHIP_ROWS = 6
local UNIT_MARKER_ROWS = 36
local TARGET_MARKER_ROWS = 18

local function Percent(value, maximum)
	if not value or not maximum or maximum <= 0 then return "50%" end
	return string.format("%.2f%%", math.max(2, math.min(98, value / maximum * 100)))
end

local function OpacityColor(alpha)
	return string.format("rgba(8, 20, 32, %d)", math.floor((tonumber(alpha) or 0.82) * 255 + 0.5))
end

local function UnitChips(card, unitDefName, unitPortraitPath)
	local counts = {}
	for _, unitID in ipairs(card.unitIDs or {}) do
		local defID = card.unitDefIDs and card.unitDefIDs[unitID]
		if defID then counts[defID] = (counts[defID] or 0) + 1 end
	end
	local defs = {}
	for defID, count in pairs(counts) do defs[#defs + 1] = {defID = defID, count = count} end
	table.sort(defs, function(left, right)
		if left.count ~= right.count then return left.count > right.count end
		return left.defID < right.defID
	end)
	local chips = {}
	for index = 1, math.min(5, #defs) do
		local entry = defs[index]
		local image = unitPortraitPath and unitPortraitPath(entry.defID)
		chips[#chips + 1] = {
			image = image or "",
			label = tostring(unitDefName and unitDefName(entry.defID) or entry.defID),
			countText = entry.count > 1 and ("x" .. tostring(entry.count)) or "",
			hasImage = image ~= nil,
			isVisible = true,
			isMore = false,
		}
	end
	if #defs > 5 then
		chips[#chips + 1] = {
			image = "",
			label = "More types",
			countText = "+" .. tostring(#defs - 5),
			hasImage = false,
			isVisible = true,
			isMore = true,
		}
	end
	for index = #chips + 1, UNIT_CHIP_ROWS do
		chips[index] = {
			image = "",
			label = "",
			countText = "",
			hasImage = false,
			isVisible = false,
			isMore = false,
		}
	end
	return chips
end

local function Markers(card, mapSizeX, mapSizeZ, groupAlpha, otherAlpha)
	local markers = {}
	local groupSet = {}
	for _, unitID in ipairs(card.unitIDs or {}) do groupSet[unitID] = true end
	for _, position in ipairs(card.knownPositions or {}) do
		if #markers >= UNIT_MARKER_ROWS then break end
		markers[#markers + 1] = {
			left = Percent(position.x, mapSizeX),
			top = Percent(position.z, mapSizeZ),
			opacity = tostring(groupSet[position.unitID] and groupAlpha or otherAlpha),
			isGroup = groupSet[position.unitID] == true,
			isVisible = true,
		}
	end
	for index = #markers + 1, UNIT_MARKER_ROWS do
		markers[index] = {
			left = "50%",
			top = "50%",
			opacity = "0",
			isGroup = false,
			isVisible = false,
		}
	end
	return markers
end

local function TargetMarkers(card, mapSizeX, mapSizeZ)
	local targets = {}
	local seen = {}
	local function CompleteRows()
		for index = #targets + 1, TARGET_MARKER_ROWS do
			targets[index] = {
				left = "50%",
				top = "50%",
				isBuild = false,
				isVisible = false,
			}
		end
		return targets
	end
	for _, unitID in ipairs(card.unitIDs or {}) do
		for _, command in ipairs(card.queuesByUnit and card.queuesByUnit[unitID] or {}) do
			local params = command.params or {}
			local x = tonumber(params[1])
			local z = tonumber(params[3])
			if x and z then
				local key = tostring(command.id) .. ":" .. tostring(math.floor(x / 8)) .. ":" .. tostring(math.floor(z / 8))
				if not seen[key] then
					seen[key] = true
					targets[#targets + 1] = {
						left = Percent(x, mapSizeX),
						top = Percent(z, mapSizeZ),
						isBuild = tonumber(command.id) and command.id < 0 or false,
						isVisible = true,
					}
					if #targets >= TARGET_MARKER_ROWS then return CompleteRows() end
				end
			end
		end
	end
	return CompleteRows()
end

local function SubgroupRows(card, slot, interaction, gridKeyNames)
	local rows = {}
	local visible = interaction:VisibleSubgroups(slot)
	for index = 1, 6 do
		local subgroup = visible[index]
		rows[index] = {
			index = index,
			keyLabel = gridKeyNames[index],
			label = subgroup and subgroup.label or "",
			countText = subgroup and not subgroup.isMore and tostring(#(subgroup.unitIDs or {})) or "",
			iconText = subgroup and (subgroup.iconText or (subgroup.isMore and ">>" or "")) or "",
			image = subgroup and subgroup.buildingDefID and ("#" .. tostring(subgroup.buildingDefID)) or "",
			hasImage = subgroup and subgroup.buildingDefID ~= nil or false,
			isVisible = subgroup ~= nil,
			isMore = subgroup and subgroup.isMore == true or false,
			isSkipped = subgroup and subgroup.isSkipped == true or false,
			isFocused = interaction.focusedSlot == slot and interaction.focusedSubgroupIndex == index,
		}
	end
	return rows
end

local function ActivationBindingRows(config, limit)
	local rows = {}
	local bindings = config.activationBindings or {}
	for index = 1, limit do
		local binding = bindings[index]
		rows[index] = {
			index = index,
			isVisible = binding ~= nil,
			keyLabel = binding and binding.keyName or "",
			modeLabel = binding and (binding.mode == "press_release" and "PRESS + RELEASE" or "HOLD") or "",
			captureTarget = "activation" .. tostring(index),
			captureLabel = "activation key " .. tostring(index),
		}
	end
	return rows
end

function ViewModel.Build(input)
	input = input or {}
	local config = input.config or {}
	local slots = input.slots or {}
	local interaction = assert(input.interaction, "interaction is required")
	local cards = {}
	for slot = 1, 6 do
		local card = slots[slot]
		if card then
			cards[slot] = {
				slot = slot,
				keyLabel = (config.gridKeyNames or {})[slot] or "?",
				taskLabel = card.taskLabel or "Recent command",
				countText = tostring(#(card.unitIDs or {})) .. " units",
				isEmpty = false,
				isDisabled = card.disabled == true or #(card.unitIDs or {}) == 0,
				isPinned = card.pinned == true,
				isFocused = interaction.focusedSlot == slot,
				unitChips = UnitChips(card, input.unitDefName, input.unitPortraitPath),
				subgroups = SubgroupRows(card, slot, interaction, config.gridKeyNames or {}),
				markers = Markers(card, input.mapSizeX, input.mapSizeZ, 1, config.nonGroupUnitOpacity or 0.28),
				targets = TargetMarkers(card, input.mapSizeX, input.mapSizeZ),
			}
		else
			cards[slot] = {
				slot = slot,
				keyLabel = "",
				taskLabel = "",
				countText = "",
				isEmpty = true,
				isDisabled = true,
				isPinned = false,
				isFocused = false,
				unitChips = UnitChips({}, input.unitDefName, input.unitPortraitPath),
				subgroups = SubgroupRows({}, slot, interaction, config.gridKeyNames or {}),
				markers = Markers({}, input.mapSizeX, input.mapSizeZ, 1, config.nonGroupUnitOpacity or 0.28),
				targets = TargetMarkers({}, input.mapSizeX, input.mapSizeZ),
			}
		end
	end

	local pinnedRows = {}
	for _, card in ipairs(input.pinnedCards or {}) do
		local definition = card.definition or {}
		pinnedRows[#pinnedRows + 1] = {
			slot = card.slot,
			keyLabel = (config.gridKeyNames or {})[card.slot] or "?",
			taskLabel = card.taskLabel or "Pinned group",
			populationLabel = POPULATION_LABELS[definition.population] or definition.population or "Manual set",
			splitLabel = SPLIT_LABELS[definition.splitStrategy] or definition.splitStrategy or "Semantic queue",
			includeCount = tostring(#(definition.includeUnitIDs or {})),
			excludeCount = tostring(#(definition.excludeUnitIDs or {})),
		}
	end

	local captureText = input.captureTarget and ("Press a key for " .. tostring(input.captureTargetLabel or input.captureTarget)) or ""
	local settingsNoticeText = tostring(input.settingsNotice or "")
	local activationBindings = config.activationBindings or {}
	local primaryActivation = activationBindings[1]
	local activeActivationLabel = input.activeActivationKeyLabel or (primaryActivation and primaryActivation.keyName) or "SET KEY"
	local activeActivationMode = input.activeActivationMode or (primaryActivation and primaryActivation.mode) or "hold"
	local activationBindingLimit = tonumber(input.activationBindingLimit) or 6
	return {
		overlayVisible = interaction.active,
		settingsVisible = interaction.settingsOpen,
		subgroupMode = interaction.keyboardDepth >= 2,
		cards = cards,
		pinnedRows = pinnedRows,
		activationBindingRows = ActivationBindingRows(config, activationBindingLimit),
		canAddActivationBinding = #activationBindings < activationBindingLimit,
		activationKeyLabel = activeActivationLabel,
		activationCommitPrefix = activeActivationMode == "press_release" and "Tap " or "Release ",
		activationCommitSuffix = activeActivationMode == "press_release" and " again to commit" or " to commit",
		cancelKeyLabel = config.cancelKeyName or "Escape",
		gridKeyOne = (config.gridKeyNames or {})[1] or "Q",
		gridKeyTwo = (config.gridKeyNames or {})[2] or "W",
		gridKeyThree = (config.gridKeyNames or {})[3] or "E",
		gridKeyFour = (config.gridKeyNames or {})[4] or "A",
		gridKeyFive = (config.gridKeyNames or {})[5] or "S",
		gridKeySix = (config.gridKeyNames or {})[6] or "D",
		cameraPreviewLabel = config.cameraPreview and "On" or "Off",
		cameraTransitionLabel = string.format("%.2fs", config.cameraTransitionSeconds or 0),
		leaveGuardLabel = string.format("%ddp / %.2fs", config.mouseLeaveGuardDp or 0, config.mouseLeaveDelaySeconds or 0),
		mouseLeaveGuardLabel = string.format("%ddp", config.mouseLeaveGuardDp or 0),
		mouseLeaveDelayLabel = string.format("%.2fs", config.mouseLeaveDelaySeconds or 0),
		glassOpacityLabel = string.format("%d%%", math.floor((config.glassOpacity or 0) * 100 + 0.5)),
		terrainOpacityLabel = string.format("%d%%", math.floor((config.terrainOpacity or 0) * 100 + 0.5)),
		nonGroupOpacityLabel = string.format("%d%%", math.floor((config.nonGroupUnitOpacity or 0) * 100 + 0.5)),
		formationWindowLabel = tostring(config.formationBatchWindowFrames or 0) .. " frames",
		buildToleranceLabel = tostring(config.buildPositionTolerance or 0) .. " elmos",
		queuePolicyLabel = config.queueEquivalencePolicy == "strict" and "Strict ordered" or "Task-aware semantic",
		buildFamilyLabel = config.commandFamilyFilters.build and "Build: on" or "Build: off",
		moveFamilyLabel = config.commandFamilyFilters.move and "Move: on" or "Move: off",
		attackFamilyLabel = config.commandFamilyFilters.attack and "Attack: on" or "Attack: off",
		patrolFamilyLabel = config.commandFamilyFilters.patrol and "Patrol: on" or "Patrol: off",
		otherFamilyLabel = config.commandFamilyFilters.other and "Other: on" or "Other: off",
		captureVisible = input.captureTarget ~= nil,
		captureText = captureText,
		settingsNoticeVisible = settingsNoticeText ~= "",
		settingsNoticeText = settingsNoticeText,
		glassColor = OpacityColor(config.glassOpacity),
		settingsGlassColor = OpacityColor(SETTINGS_GLASS_OPACITY),
		terrainOpacity = tostring(config.terrainOpacity or 0.85),
		hasPinnedRows = #pinnedRows > 0,
	}
end

return ViewModel
