local root = UNIT_NAVIGATOR_TEST_ROOT or (arg and arg[1]) or "./"
local T = dofile(root .. "tests/support.lua")
local InteractionController = dofile(root .. "include/interaction_controller.lua")

local events = {}
local slots = {
	[1] = {unitIDs = {1, 2}, subgroups = {{unitIDs = {1}, label = "one"}, {unitIDs = {2}, label = "two"}}},
	[2] = {unitIDs = {3, 4}, subgroups = {{unitIDs = {3}, label = "three"}}},
	[3] = {unitIDs = {5}, subgroups = {
		{unitIDs = {11}}, {unitIDs = {12}}, {unitIDs = {13}}, {unitIDs = {14}}, {unitIDs = {15}}, {unitIDs = {16}}, {unitIDs = {17}},
	}},
}
local controller = InteractionController.New({
	getSlots = function() return slots end,
	onPreview = function(unitIDs) events[#events + 1] = {kind = "preview", units = unitIDs} end,
	onCommit = function(unitIDs) events[#events + 1] = {kind = "commit", units = unitIDs} end,
	onCancel = function(reason) events[#events + 1] = {kind = "cancel", reason = reason} end,
})

T.truthy(controller:Open())
T.equals(controller.focusedSlot, 1, "newest root was not the release default")
T.truthy(controller:PressGrid(2))
T.truthy(controller.active, "first grid key committed instead of focusing")
T.equals(controller.focusedSlot, 2)
T.truthy(controller:PressGrid(1))
T.truthy(controller.active, "Q committed instead of traversing to the Q card")
T.equals(controller.focusedSlot, 1)
T.truthy(controller:PressGrid(2))
T.truthy(controller.active, "W committed instead of traversing back to the W card")
T.equals(controller.focusedSlot, 2)
T.truthy(controller:ReleaseActivation())
T.arrayEquals(events[#events].units, {3, 4})

controller:Open()
controller:PressGrid(1)
controller:PressGrid(1)
T.equals(controller.keyboardDepth, 2, "repeating the focused root key did not enter subgroup mode")
controller:PressGrid(2)
T.falsy(controller.active, "second grid key did not commit subgroup")
T.arrayEquals(events[#events].units, {2})

controller:Open()
controller:PressGrid(3)
controller:PressGrid(3)
T.truthy(controller:PressGrid(6))
T.truthy(controller.active, "More tile committed")
T.equals(controller.subgroupPage, 2)
controller:PressGrid(1)
T.arrayEquals(events[#events].units, {16}, "overflow page selected the wrong subgroup")

controller:Open()
controller:Leave(1, 0.15)
T.falsy(controller:Update(1.14))
T.truthy(controller:Update(1.15))
T.equals(events[#events].kind, "cancel")
T.falsy(controller:ReleaseActivation(), "release committed after cancellation")

controller:Open()
controller:OpenSettings()
T.truthy(controller.settingsOpen)
T.falsy(controller:ReleaseActivation(), "activation release closed persistent settings")
T.truthy(controller:CloseSettings())

print("test_interaction_controller.lua: ok")
