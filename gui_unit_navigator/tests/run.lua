local root = (arg and arg[1]) or "./"
if string.sub(root, -1) ~= "/" and string.sub(root, -1) ~= "\\" then root = root .. "/" end

UNIT_NAVIGATOR_TEST_ROOT = root

for _, test in ipairs({
	"test_restart_guard.lua",
	"test_config.lua",
	"test_rml_key_mapper.lua",
	"test_queue_semantics.lua",
	"test_group_store.lua",
	"test_interaction_controller.lua",
	"test_activation_controller.lua",
	"test_command_observer.lua",
	"test_unit_navigator_widget.lua",
}) do
	dofile(root .. "tests/" .. test)
end

print("unit_navigator test suite: ok")
