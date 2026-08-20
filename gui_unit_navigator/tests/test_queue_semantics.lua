local root = UNIT_NAVIGATOR_TEST_ROOT or (arg and arg[1]) or "./"
local T = dofile(root .. "tests/support.lua")
local QueueSemantics = dofile(root .. "include/queue_semantics.lua")

local semantic = QueueSemantics.New({
	insertCommandID = 1,
	commandFamilies = {[10] = "move", [20] = "attack"},
	commandLabels = {[10] = "Move", [20] = "Attack"},
	unitDefName = function(id) return "Unit " .. tostring(id) end,
})

local semanticConfig = {buildPositionTolerance = 8, queueEquivalencePolicy = "semantic"}

local buildA = {
	{id = -101, params = {100, 0, 200, 1}},
	{id = -102, params = {304, 0, 400, 2}},
}
local buildB = {
	{id = -102, params = {307, 0, 403, 2}},
	{id = -101, params = {103, 0, 199, 1}},
}
T.truthy(semantic:Equivalent(buildA, buildB, nil, nil, semanticConfig), "unordered build spread did not group")
local buildWithDifferentIssueOptions = {
	{id = -101, params = {100, 0, 200, 1}, options = {shift = true}},
	{id = -102, params = {304, 0, 400, 2}, options = {alt = true}},
}
T.truthy(semantic:Equivalent(buildA, buildWithDifferentIssueOptions, nil, nil, semanticConfig), "issue options split normalized build tuples")

local duplicate = {
	{id = -101, params = {100, 0, 200, 1}},
	{id = -101, params = {100, 0, 200, 1}},
	{id = -102, params = {304, 0, 400, 2}},
}
T.falsy(semantic:Equivalent(buildA, duplicate, nil, nil, semanticConfig), "duplicate build count was discarded")

local differentFacing = {
	{id = -101, params = {100, 0, 200, 3}},
	{id = -102, params = {304, 0, 400, 2}},
}
T.falsy(semantic:Equivalent(buildA, differentFacing, nil, nil, semanticConfig), "build facing did not split queues")

local orderedA = {{id = 10, params = {1, 0, 2}}, {id = 20, params = {44}}}
local orderedB = {{id = 20, params = {44}}, {id = 10, params = {1, 0, 2}}}
T.falsy(semantic:Equivalent(orderedA, orderedB, nil, nil, semanticConfig), "non-build command order was discarded")

T.truthy(semantic:Equivalent(
	{{id = 10, params = {10, 0, 10}}},
	{{id = 10, params = {900, 0, 900}}},
	{formationBatchID = "line-42"},
	{formationBatchID = "line-42"},
	semanticConfig
), "formation batch positions split a dispatch")
T.falsy(semantic:Equivalent(
	{{id = 10, params = {10, 0, 10}}, {id = 20, params = {1}}},
	{{id = 10, params = {900, 0, 900}}, {id = 20, params = {2}}},
	{formationBatchID = "line-42", issuedCommandID = 10},
	{formationBatchID = "line-42", issuedCommandID = 10},
	semanticConfig
), "formation grouping discarded later queue differences")

T.falsy(semantic:Equivalent(buildA, buildB, nil, nil, {
	buildPositionTolerance = 8,
	queueEquivalencePolicy = "strict",
}), "strict policy ignored build order")

local inserted = {{id = 1, params = {0, -101, 0, 100, 0, 200, 1}}}
T.equals(semantic:Describe(inserted, nil, semanticConfig).label, "Build Unit 101")
T.equals(semantic:Describe(orderedA, nil, semanticConfig).label, "Move")

print("test_queue_semantics.lua: ok")
