local root = UNIT_NAVIGATOR_TEST_ROOT or (arg and arg[1]) or "./"
local T = dofile(root .. "tests/support.lua")
local CommandObserver = dofile(root .. "include/command_observer.lua")

local frame = 100
local selection = {1, 2, 3}
local queues = {[1] = {}, [2] = {}, [3] = {}}
local batches = {}
local observer = CommandObserver.New({
	getFrame = function() return frame end,
	getSelection = function() return selection end,
	getMyTeamID = function() return 7 end,
	getUnitTeam = function(unitID) return unitID == 99 and 8 or 7 end,
	getUnitCommands = function(unitID) return queues[unitID] or {} end,
	queueFingerprint = function(queue)
		local ids = {}
		for index, command in ipairs(queue) do ids[index] = tostring(command.id) end
		return table.concat(ids, ",")
	end,
	onBatch = function(batch) batches[#batches + 1] = batch end,
}, {snapshotDelayFrames = 2, formationBatchWindowFrames = 1})

T.falsy(observer:OnCommandNotify(10, {50, 0, 50}, {}), "observer consumed CommandNotify")
observer:OnUnitCommand(1, 11, 7, 10, {50, 0, 50}, {}, 1, 0, false, false)
observer:OnUnitCommand(2, 11, 7, 10, {50, 0, 50}, {}, 2, 0, false, false)
queues[1] = {{id = 10}}
queues[2] = {{id = 10}}
frame = 102
observer:Flush(frame)
T.equals(#batches, 1)
T.arrayEquals(batches[1].recipientUnitIDs, {1, 2})
T.arrayEquals(batches[1].skippedUnitIDs, {3})

frame = 200
selection = {1, 2}
observer:OnCommandNotify(10, {0, 0, 0}, {})
T.falsy(observer:OnUnitCommandNotify(1, 10, {10, 0, 10}, {}), "observer consumed UnitCommandNotify")
observer:OnUnitCommandNotify(2, 10, {90, 0, 90}, {})
frame = 202
observer:Flush(frame)
T.equals(#batches, 2)
local formation = batches[2]
T.equals(formation.commandContextByUnit[1].formationBatchID, formation.commandContextByUnit[2].formationBatchID)

frame = 250
selection = {1}
observer:OnCommandNotify(20, {40, 0, 40}, {})
observer:OnUnitCommand(2, 11, 7, 20, {40, 0, 40}, {}, 3, 0, false, false)
frame = 252
observer:Flush(frame)
T.equals(#batches, 2, "a unit outside the CommandNotify selection was admitted")

frame = 300
selection = {1, 2, 3}
observer:OnUnitCommand(1, 11, 7, -101, {10, 0, 10}, {}, 1, 0, false, true)
observer:OnUnitCommand(2, 11, 7, -102, {20, 0, 20}, {}, 2, 0, false, true)
observer:OnUnitCommandNotify(3, -103, {30, 0, 30}, {})
frame = 302
observer:Flush(frame)
T.equals(#batches, 2, "standalone widget commands bypassed the CommandNotify admission gate")

local ok, message = observer:RecordBatch({recipientUnitIDs = {}})
T.falsy(ok)
T.contains(message, "humanIssued")

ok, message = observer:RecordBatch({humanIssued = true, recipientUnitIDs = {}})
T.falsy(ok)
T.contains(message, "recipientUnitIDs")

frame = 400
ok = observer:RecordBatch({
	humanIssued = true,
	batchID = "producer-1",
	semanticKind = "formation",
	selectedUnitIDs = {1, 2, 99},
	recipientUnitIDs = {1, 99},
	commandID = 10,
})
T.truthy(ok)
observer:OnUnitCommand(1, 11, 7, 10, {50, 0, 50}, {}, 9, 0, false, true)
queues[2] = {{id = 20}}
frame = 402
observer:Flush(frame)
T.arrayEquals(batches[3].recipientUnitIDs, {1}, "producer seam admitted an enemy or inferred recipient")
T.arrayEquals(batches[3].skippedUnitIDs, {2}, "producer selection metadata did not preserve skipped units")
T.equals(#batches, 3, "producer batch duplicated its authoritative UnitCommand fallback")

ok, message = observer:RecordBatch({humanIssued = true, selectedUnitIDs = {99}, recipientUnitIDs = {99}, commandID = 10})
T.falsy(ok)
T.contains(message, "owned")

frame = 500
selection = {1}
observer:OnCommandNotify(10, {10, 0, 10}, {})
selection = {2, 3}
observer:OnCommandNotify(10, {20, 0, 20}, {})
observer:OnUnitCommand(1, 11, 7, 10, {10, 0, 10}, {}, 10, 0, false, false)
observer:OnUnitCommand(2, 11, 7, 10, {20, 0, 20}, {}, 11, 0, false, false)
frame = 502
observer:Flush(frame)
T.equals(#batches, 5)
T.arrayEquals(batches[4].selectedUnitIDs, {1})
T.arrayEquals(batches[4].recipientUnitIDs, {1}, "commander command moved into the newer squad batch")
T.arrayEquals(batches[5].selectedUnitIDs, {2, 3})
T.arrayEquals(batches[5].recipientUnitIDs, {2}, "squad command absorbed the previous commander selection")

print("test_command_observer.lua: ok")
