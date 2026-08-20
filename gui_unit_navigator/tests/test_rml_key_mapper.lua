local root = UNIT_NAVIGATOR_TEST_ROOT or (arg and arg[1]) or "./"
local T = dofile(root .. "tests/support.lua")
local RmlKeyMapper = dofile(root .. "include/rml_key_mapper.lua")

local rmlIdentifiers = {
	UNKNOWN = 1,
	A = 2,
	["7"] = 3,
	F9 = 4,
	CAPITAL = 5,
	BACK = 6,
	PRIOR = 7,
	NEXT = 8,
	SNAPSHOT = 9,
	LCONTROL = 10,
	RCONTROL = 11,
	LMENU = 12,
	RMENU = 13,
	LWIN = 14,
	RWIN = 15,
	SCROLL = 16,
	NUMPAD4 = 17,
	NUMPADENTER = 18,
	MULTIPLY = 19,
	ADD = 20,
	SUBTRACT = 21,
	DECIMAL = 22,
	DIVIDE = 23,
	OEM_NEC_EQUAL = 24,
	OEM_1 = 25,
	OEM_PLUS = 26,
	OEM_COMMA = 27,
	OEM_MINUS = 28,
	OEM_PERIOD = 29,
	OEM_2 = 30,
	OEM_3 = 31,
	OEM_4 = 32,
	OEM_5 = 33,
	OEM_6 = 34,
	OEM_7 = 35,
	OEM_102 = 36,
	RETURN = 37,
	APPS = 38,
	UNMAPPED = 39,
}

local keySymbols = {
	UNKNOWN = 0,
	A = 97,
	N_7 = 55,
	F9 = 290,
	CAPSLOCK = 301,
	BACKSPACE = 8,
	PAGEUP = 280,
	PAGEDOWN = 281,
	PRINT = 316,
	LCTRL = 306,
	RCTRL = 305,
	LALT = 308,
	RALT = 307,
	LSUPER = 311,
	RSUPER = 312,
	SCROLLOCK = 302,
	KP4 = 260,
	KP_ENTER = 271,
	KP_MULTIPLY = 268,
	KP_PLUS = 270,
	KP_MINUS = 269,
	KP_PERIOD = 266,
	KP_DIVIDE = 267,
	KP_EQUALS = 272,
	SEMICOLON = 59,
	EQUALS = 61,
	COMMA = 44,
	MINUS = 45,
	PERIOD = 46,
	SLASH = 47,
	BACKQUOTE = 96,
	LEFTBRACKET = 91,
	BACKSLASH = 92,
	RIGHTBRACKET = 93,
	QUOTE = 39,
	LESS = 60,
	RETURN = 13,
	MENU = 319,
}

local function Expect(identifier, expectedCode, expectedLabel, message)
	local code, label = RmlKeyMapper.Resolve(identifier, rmlIdentifiers, keySymbols)
	T.equals(code, expectedCode, (message or tostring(identifier)) .. " code")
	T.equals(label, expectedLabel, (message or tostring(identifier)) .. " label")
end

Expect(2, 97, "A", "letter")
Expect(3, 55, "7", "number row")
Expect(4, 290, "F9", "function key")
Expect(5, 301, "CAPSLOCK")
Expect(6, 8, "BACKSPACE")
Expect(7, 280, "PAGEUP")
Expect(8, 281, "PAGEDOWN")
Expect(9, 316, "PRINT")
Expect(10, 306, "LCTRL")
Expect(11, 305, "RCTRL")
Expect(12, 308, "LALT")
Expect(13, 307, "RALT")
Expect(14, 311, "LSUPER")
Expect(15, 312, "RSUPER")
Expect(16, 302, "SCROLLOCK")
Expect(17, 260, "KP4")
Expect(18, 271, "KP_ENTER")
Expect(19, 268, "KP_MULTIPLY")
Expect(20, 270, "KP_PLUS")
Expect(21, 269, "KP_MINUS")
Expect(22, 266, "KP_PERIOD")
Expect(23, 267, "KP_DIVIDE")
Expect(24, 272, "KP_EQUALS")

local punctuation = {
	{25, 59, "SEMICOLON"},
	{26, 61, "EQUALS"},
	{27, 44, "COMMA"},
	{28, 45, "MINUS"},
	{29, 46, "PERIOD"},
	{30, 47, "SLASH"},
	{31, 96, "BACKQUOTE"},
	{32, 91, "LEFTBRACKET"},
	{33, 92, "BACKSLASH"},
	{34, 93, "RIGHTBRACKET"},
	{35, 39, "QUOTE"},
	{36, 60, "LESS"},
}
for _, example in ipairs(punctuation) do Expect(example[1], example[2], example[3], "OEM punctuation") end

Expect(37, 13, "RETURN", "direct match")
Expect(38, 319, "MENU", "application/menu key")
Expect("CAPITAL", 301, "CAPSLOCK", "string identifier")
Expect("RmlUi.key_identifier.KI_CAPITAL", 301, "CAPSLOCK", "qualified string identifier")
Expect("left control", 306, "LCTRL", "friendly string identifier")
Expect("3", nil, nil, "single digit without matching Spring symbol")
keySymbols.N_3 = 51
Expect("3", 51, "3", "single digit string")
Expect("05", 301, "CAPSLOCK", "numeric identifier string")

local reverseRmlIdentifiers = {[77] = "CAPITAL"}
local reverseCode, reverseLabel = RmlKeyMapper.Resolve(77, reverseRmlIdentifiers, keySymbols)
T.equals(reverseCode, 301, "reverse-shaped RmlUi identifier table code")
T.equals(reverseLabel, "CAPSLOCK", "reverse-shaped RmlUi identifier table label")

local code, label = RmlKeyMapper.Resolve(1, rmlIdentifiers, keySymbols)
T.equals(code, nil, "UNKNOWN identifier resolved")
T.equals(label, nil, "UNKNOWN identifier returned a label")
T.equals(RmlKeyMapper.Resolve(39, rmlIdentifiers, keySymbols), nil, "unmapped identifier resolved")
T.equals(RmlKeyMapper.Resolve(0, rmlIdentifiers, keySymbols), nil, "zero identifier resolved")
T.equals(RmlKeyMapper.Resolve(-1, rmlIdentifiers, keySymbols), nil, "negative identifier resolved")
T.equals(RmlKeyMapper.Resolve(0 / 0, rmlIdentifiers, keySymbols), nil, "NaN identifier resolved")
T.equals(RmlKeyMapper.Resolve({}, rmlIdentifiers, keySymbols), nil, "non-scalar identifier resolved")
T.equals(RmlKeyMapper.Resolve(2, nil, keySymbols), nil, "numeric identifier resolved without RmlUi map")
T.equals(RmlKeyMapper.Resolve("A", rmlIdentifiers, {A = 0}), nil, "zero Spring key code resolved")
T.equals(RmlKeyMapper.Resolve("A", rmlIdentifiers, {A = -97}), nil, "negative Spring key code resolved")
T.equals(RmlKeyMapper.Resolve("A", rmlIdentifiers, {A = 97.5}), nil, "fractional Spring key code resolved")

print("test_rml_key_mapper.lua: ok")
