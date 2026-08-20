local root = UNIT_NAVIGATOR_TEST_ROOT or (arg and arg[1]) or "./"
local T = dofile(root .. "tests/support.lua")
local Config = dofile(root .. "include/config.lua")

local defaults = Config.Defaults()
T.equals(Config.Version(), 6)
T.truthy(Config.HasActivation(defaults))
T.equals(#defaults.activationBindings, 1)
T.equals(defaults.activationBindings[1].keyName, "CapsLock")
T.equals(defaults.activationBindings[1].mode, "hold")
T.equals(defaults.activationKeyCode, 301)

local migrated = Config.FromSaved({
	activationKeyBound = true,
	activationKeyName = "F8",
	activationKeyCode = 289,
}, 5)
T.equals(#migrated.activationBindings, 1)
T.equals(migrated.activationBindings[1].keyCode, 289)
T.equals(migrated.activationBindings[1].mode, "hold")

local multiple = Config.Normalize({
	activationBindings = {
		{keyName = "F8", keyCode = 289, mode = "hold"},
		{keyName = "F9", keyCode = 290, mode = "press_release"},
	},
})
T.equals(#multiple.activationBindings, 2)
T.equals(Config.FindActivation(multiple, 290).mode, "press_release")
T.equals(multiple.activationKeyCode, 289, "legacy alias did not follow primary binding")

local updated, didUpdate = Config.SetActivationBinding(multiple, 2, {
	keyName = "F10",
	keyCode = 291,
	mode = "press_release",
})
T.truthy(didUpdate)
T.equals(#updated.activationBindings, 2)
T.equals(updated.activationBindings[2].keyCode, 291)

updated, didUpdate = Config.SetActivationBinding(updated, 2, {
	keyName = "F8 duplicate",
	keyCode = 289,
	mode = "press_release",
})
T.truthy(didUpdate)
T.equals(#updated.activationBindings, 1, "duplicate activation code was retained")
T.equals(updated.activationBindings[1].mode, "press_release")

updated, didUpdate = Config.RemoveActivationBinding(updated, 1)
T.truthy(didUpdate)
T.falsy(Config.HasActivation(updated))
T.falsy(updated.activationKeyBound)
T.equals(updated.activationKeyName, nil)
T.equals(updated.activationKeyCode, nil)

local cleared = Config.WithoutActivation(multiple)
T.equals(#cleared.activationBindings, 0)
T.falsy(Config.HasActivation(cleared))
T.equals(Config.MaximumActivationBindings(), 6)

print("test_config.lua: ok")
