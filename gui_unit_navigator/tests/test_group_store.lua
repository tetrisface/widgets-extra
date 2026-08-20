local root = UNIT_NAVIGATOR_TEST_ROOT or (arg and arg[1]) or "./"
local T = dofile(root .. "tests/support.lua")
local QueueSemantics = dofile(root .. "include/queue_semantics.lua")
local GroupStore = dofile(root .. "include/group_store.lua")

local semantic = QueueSemantics.New({commandFamilies = {[10] = "move", [20] = "attack"}, commandLabels = {[10] = "Move", [20] = "Attack"}})
local store = GroupStore.New({semantic = semantic, unitDefName = function(id) return "Type " .. id end})

local function Card(id, unitIDs)
	return {taskLabel = id, unitIDs = unitIDs, selectedUnitIDs = unitIDs, unitDefIDs = {}, queuesByUnit = {}}
end

store:RecordRecent(Card("one", {1}))
store:RecordRecent(Card("two", {2}))
store:RecordRecent(Card("three", {3}))
T.equals(store:Slots()[1].taskLabel, "three")
T.equals(store:Slots()[2].taskLabel, "two")

local originalID = store:Slots()[2].id
store:RecordRecent(Card("two updated", {2}))
T.equals(store:Slots()[1].taskLabel, "two updated")
T.equals(store:Slots()[1].id, originalID, "dedupe replaced card identity")

local recipientStore = GroupStore.New({semantic = semantic})
local firstRecipientCard = recipientStore:RecordRecent({
	taskLabel = "commander from mixed selection",
	unitIDs = {1},
	selectedUnitIDs = {1, 2},
})
local updatedRecipientCard = recipientStore:RecordRecent({
	taskLabel = "commander from other selection",
	unitIDs = {1},
	selectedUnitIDs = {1, 3},
})
T.equals(updatedRecipientCard.id, firstRecipientCard.id, "actual recipients did not define card identity")
T.equals(recipientStore:Slots()[1].taskLabel, "commander from other selection")
T.equals(recipientStore:Slots()[2], nil, "different issued selections duplicated one recipient group")

local staleStore = GroupStore.New({semantic = semantic})
staleStore:RecordRecent(Card("commander and first squad", {1, 2}))
staleStore:RecordRecent(Card("commander and second squad", {1, 3}))
local staleSlots = staleStore:Slots()
staleSlots[1].unitIDs = {1}
staleSlots[2].unitIDs = {1}
staleStore:Reconcile()
T.equals(staleStore:Slots()[1].taskLabel, "commander and second squad")
T.equals(staleStore:Slots()[2], nil, "filtered populations left duplicate effective groups")

T.truthy(store:Pin(2))
local pinned = store:Slots()[2]
store:RecordRecent(Card("four", {4}))
store:RecordRecent(Card("five", {5}))
T.equals(store:Slots()[2], pinned, "pinned slot moved under MRU pressure")
T.truthy(pinned.pinned)
T.truthy(store:Unpin(2))
T.falsy(pinned.pinned)
T.equals(store:Slots()[1], pinned, "unpin did not return card to MRU front")

local owned = {
	{id = 1, defID = 11, isMobile = true, isCombat = true},
	{id = 2, defID = 11, isMobile = true, isCombat = false},
	{id = 3, defID = 12, isMobile = false, isCombat = true},
	{id = 4, defID = 12, isMobile = true, isCombat = true},
}
T.arrayEquals(store:ResolvePopulation({population = "all_army", includeUnitIDs = {2}, excludeUnitIDs = {4}}, owned), {1, 2})
T.arrayEquals(store:ResolvePopulation({population = "unitdef", unitDefIDs = {12}}, owned), {3, 4})
T.arrayEquals(store:ResolvePopulation({population = "manual", manualUnitIDs = {1, 99}}, owned), {1})

local groupedCard = {
	unitIDs = {1, 2, 3},
	skippedUnitIDs = {4},
	unitDefIDs = {[1] = 11, [2] = 11, [3] = 12},
	queuesByUnit = {
		[1] = {{id = 10, params = {5, 0, 5}}},
		[2] = {{id = 10, params = {5, 0, 5}}},
		[3] = {{id = 20, params = {50}}},
	},
	definition = {splitStrategy = "semantic_queue"},
}
local groups = store:BuildSubgroups(groupedCard, {queueEquivalencePolicy = "semantic"})
T.equals(#groups, 3)
T.arrayEquals(groups[1].unitIDs, {1, 2})
T.truthy(groups[3].isSkipped)
T.arrayEquals(groups[3].unitIDs, {4})

groupedCard.definition.splitStrategy = "strict_unitdef"
groups = store:BuildSubgroups(groupedCard, {})
T.equals(groups[1].label, "Type 11")

print("test_group_store.lua: ok")
