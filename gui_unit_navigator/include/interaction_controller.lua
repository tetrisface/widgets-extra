local InteractionController = {}

function InteractionController.New(options)
	options = options or {}
	local self = {
		active = false,
		settingsOpen = false,
		focusedSlot = nil,
		focusedSubgroupIndex = nil,
		subgroupPage = 1,
		keyboardDepth = 0,
		cancelledActivation = false,
		leaveDeadline = nil,
	}

	local function Slots()
		return options.getSlots and options.getSlots() or {}
	end

	local function Card(slot)
		return Slots()[slot]
	end

	local function PagedSubgroups(card, page)
		local all = card and card.subgroups or {}
		local pageSize = 5
		page = page or self.subgroupPage
		local startIndex = (page - 1) * pageSize + 1
		local visible = {}
		for index = startIndex, math.min(#all, startIndex + pageSize - 1) do visible[#visible + 1] = all[index] end
		if startIndex + pageSize <= #all then
			visible[6] = {isMore = true, label = "More", unitIDs = {}}
		elseif page > 1 then
			visible[6] = {isMore = true, label = "First", unitIDs = {}, targetPage = 1}
		end
		return visible
	end

	local function Preview(unitIDs, target)
		if options.onPreview and unitIDs and #unitIDs > 0 then options.onPreview(unitIDs, target) end
	end

	local function FinishCommit(unitIDs, target)
		if not unitIDs or #unitIDs == 0 then return false end
		self.active = false
		self.leaveDeadline = nil
		if options.onCommit then options.onCommit(unitIDs, target) end
		return true
	end

	function self:Open()
		if self.settingsOpen then return false end
		self.active = true
		self.cancelledActivation = false
		self.focusedSlot = Card(1) and 1 or nil
		self.focusedSubgroupIndex = nil
		self.subgroupPage = 1
		self.keyboardDepth = 0
		self.leaveDeadline = nil
		if options.onOpen then options.onOpen() end
		return true
	end

	function self:FocusCard(slot, shouldPreview)
		slot = tonumber(slot)
		local card = slot and Card(slot)
		if not self.active or not card or card.disabled then return false end
		self.focusedSlot = slot
		self.focusedSubgroupIndex = nil
		self.subgroupPage = 1
		self.keyboardDepth = 1
		if shouldPreview ~= false then Preview(card.unitIDs, {card = card}) end
		return true
	end

	function self:FocusSubgroup(slot, visibleIndex)
		slot = tonumber(slot)
		visibleIndex = tonumber(visibleIndex)
		if not self.active or not slot or not visibleIndex then return false end
		if self.focusedSlot ~= slot then self:FocusCard(slot, false) end
		local card = Card(slot)
		local subgroup = PagedSubgroups(card)[visibleIndex]
		if not subgroup or subgroup.isMore then return false end
		self.focusedSubgroupIndex = visibleIndex
		Preview(subgroup.unitIDs, {card = card, subgroup = subgroup})
		return true
	end

	function self:PressGrid(index)
		index = tonumber(index)
		if not self.active or not index or index < 1 or index > 6 then return false end
		if self.keyboardDepth == 0 or not self.focusedSlot then
			return self:FocusCard(index, true)
		end
		if self.keyboardDepth == 1 then
			if index ~= self.focusedSlot then return self:FocusCard(index, true) end
			self.keyboardDepth = 2
			self.focusedSubgroupIndex = nil
			if options.onChange then options.onChange() end
			return true
		end
		local card = Card(self.focusedSlot)
		local subgroup = PagedSubgroups(card)[index]
		if not subgroup then return false end
		if subgroup.isMore then
			self.subgroupPage = subgroup.targetPage or (self.subgroupPage + 1)
			self.focusedSubgroupIndex = nil
			if options.onChange then options.onChange() end
			return true
		end
		self.focusedSubgroupIndex = index
		Preview(subgroup.unitIDs, {card = card, subgroup = subgroup})
		return FinishCommit(subgroup.unitIDs, {card = card, subgroup = subgroup})
	end

	function self:ReleaseActivation()
		if self.settingsOpen then return false end
		if not self.active or self.cancelledActivation then return false end
		local card = Card(self.focusedSlot)
		if not card then return self:Cancel("empty") end
		local subgroup = self.focusedSubgroupIndex and PagedSubgroups(card)[self.focusedSubgroupIndex]
		return FinishCommit(subgroup and subgroup.unitIDs or card.unitIDs, {card = card, subgroup = subgroup})
	end

	function self:ClickCard(slot)
		local card = Card(tonumber(slot))
		if not self.active or not card or card.disabled then return false end
		return FinishCommit(card.unitIDs, {card = card})
	end

	function self:ClickSubgroup(slot, visibleIndex)
		if not self:FocusSubgroup(slot, visibleIndex) then return false end
		local card = Card(self.focusedSlot)
		local subgroup = PagedSubgroups(card)[self.focusedSubgroupIndex]
		return FinishCommit(subgroup.unitIDs, {card = card, subgroup = subgroup})
	end

	function self:Cancel(reason)
		if not self.active then return false end
		self.active = false
		self.cancelledActivation = true
		self.leaveDeadline = nil
		if options.onCancel then options.onCancel(reason) end
		return true
	end

	function self:OpenSettings()
		local wasActive = self.active
		self.active = false
		self.settingsOpen = true
		self.cancelledActivation = wasActive
		self.leaveDeadline = nil
		if options.onSettings then options.onSettings(true) end
		return true
	end

	function self:CloseSettings()
		if not self.settingsOpen then return false end
		self.settingsOpen = false
		if options.onSettings then options.onSettings(false) end
		return true
	end

	function self:Leave(now, delay)
		if self.active then self.leaveDeadline = (tonumber(now) or 0) + (tonumber(delay) or 0) end
	end

	function self:Enter()
		self.leaveDeadline = nil
	end

	function self:Update(now)
		if self.leaveDeadline and (tonumber(now) or 0) >= self.leaveDeadline then return self:Cancel("mouse_leave") end
		return false
	end

	function self:VisibleSubgroups(slot)
		slot = slot or self.focusedSlot
		return PagedSubgroups(Card(slot), slot == self.focusedSlot and self.subgroupPage or 1)
	end

	return self
end

return InteractionController
