local root = UNIT_NAVIGATOR_TEST_ROOT or (arg and arg[1]) or "./"
local T = dofile(root .. "tests/support.lua")
local ActivationController = dofile(root .. "include/activation_controller.lua")

local bindings = {
	[301] = {keyName = "CapsLock", keyCode = 301, mode = "hold"},
	[290] = {keyName = "F9", keyCode = 290, mode = "press_release"},
}
local isOpen = false
local events = {}
local allowOpen = true
local controller = ActivationController.New({
	findBinding = function(keyCode) return bindings[keyCode] end,
	isOpen = function() return isOpen end,
	onOpen = function(binding)
		events[#events + 1] = "open:" .. binding.keyName
		if not allowOpen then return false end
		isOpen = true
		return true
	end,
	onCommit = function(binding)
		events[#events + 1] = "commit:" .. binding.keyName
		isOpen = false
		return true
	end,
})

T.truthy(controller:KeyPress(301, false))
T.truthy(isOpen, "hold binding did not open on key-down")
T.equals(controller:ActiveBinding().keyCode, 301)
T.truthy(controller:KeyPress(301, true), "hold repeat was not consumed")
T.equals(#events, 1, "hold repeat reopened the navigator")
T.truthy(controller:KeyRelease(301))
T.falsy(isOpen, "hold binding did not commit on release")
T.equals(events[#events], "commit:CapsLock")

T.truthy(controller:KeyPress(290, false))
T.falsy(isOpen, "press-release binding opened before release")
T.truthy(controller:KeyRelease(290))
T.truthy(isOpen, "press-release binding did not open on first tap")
T.equals(controller:ActiveBinding().keyCode, 290)

T.truthy(controller:KeyPress(301, false), "secondary binding was not consumed while open")
T.truthy(controller:KeyRelease(301), "secondary release was not consumed while open")
T.equals(controller:ActiveBinding().keyCode, 290, "secondary binding stole the active tap gesture")
T.truthy(isOpen)

T.truthy(controller:KeyPress(290, false))
T.truthy(controller:KeyRelease(290))
T.falsy(isOpen, "press-release binding did not commit on second tap")
T.equals(events[#events], "commit:F9")

isOpen = true
controller:KeyPress(290, false)
controller:Reset()
T.equals(controller:ActiveBinding(), nil)
isOpen = false

allowOpen = false
T.truthy(controller:KeyPress(301, false))
T.equals(controller:ActiveBinding(), nil, "failed open retained activation ownership")
T.truthy(controller:KeyRelease(301))
T.falsy(isOpen)

T.falsy(controller:KeyPress(999, false))
T.falsy(controller:KeyRelease(999))

print("test_activation_controller.lua: ok")
