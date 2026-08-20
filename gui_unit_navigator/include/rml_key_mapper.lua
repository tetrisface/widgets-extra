local RmlKeyMapper = {}

-- RML exposes Windows-style key identifiers while Spring's widget call-ins
-- use SDL 1.2 key symbols. Keep this translation independent of both globals so
-- it can be exercised without loading the engine or an RML document.
local SPRING_SYMBOL_BY_RML_NAME = {
	BACK = "BACKSPACE",
	CAPITAL = "CAPSLOCK",
	PRIOR = "PAGEUP",
	NEXT = "PAGEDOWN",
	SNAPSHOT = "PRINT",
	LCONTROL = "LCTRL",
	RCONTROL = "RCTRL",
	LMENU = "LALT",
	RMENU = "RALT",
	LWIN = "LSUPER",
	RWIN = "RSUPER",
	SCROLL = "SCROLLOCK",
	APPS = "MENU",

	NUMPADENTER = "KP_ENTER",
	MULTIPLY = "KP_MULTIPLY",
	ADD = "KP_PLUS",
	SUBTRACT = "KP_MINUS",
	DECIMAL = "KP_PERIOD",
	DIVIDE = "KP_DIVIDE",
	OEM_NEC_EQUAL = "KP_EQUALS",

	OEM_1 = "SEMICOLON",
	OEM_PLUS = "EQUALS",
	OEM_COMMA = "COMMA",
	OEM_MINUS = "MINUS",
	OEM_PERIOD = "PERIOD",
	OEM_2 = "SLASH",
	OEM_3 = "BACKQUOTE",
	OEM_4 = "LEFTBRACKET",
	OEM_5 = "BACKSLASH",
	OEM_6 = "RIGHTBRACKET",
	OEM_7 = "QUOTE",
	OEM_102 = "LESS",

	-- Useful spellings when Resolve receives a name rather than an enum value.
	CAPS_LOCK = "CAPSLOCK",
	PAGE_UP = "PAGEUP",
	PAGE_DOWN = "PAGEDOWN",
	PRINT_SCREEN = "PRINT",
	LEFT_CONTROL = "LCTRL",
	RIGHT_CONTROL = "RCTRL",
	LEFT_CTRL = "LCTRL",
	RIGHT_CTRL = "RCTRL",
	LEFT_ALT = "LALT",
	RIGHT_ALT = "RALT",
	LEFT_WIN = "LSUPER",
	RIGHT_WIN = "RSUPER",
	LEFT_SUPER = "LSUPER",
	RIGHT_SUPER = "RSUPER",
	SCROLL_LOCK = "SCROLLOCK",
	NUMPAD_ENTER = "KP_ENTER",
}

local function NormalizeName(value)
	if type(value) ~= "string" then return nil end
	local name = string.upper(value):match("^%s*(.-)%s*$")
	if not name or name == "" then return nil end
	name = name:match("([^%.:]+)$") or name
	name = name:gsub("[%s%-]+", "_")
	name = name:gsub("^KI_", "")
	return name ~= "" and name or nil
end

local function IsPositiveKeyCode(value)
	value = tonumber(value)
	if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
	if value <= 0 or value > 65535 or value % 1 ~= 0 then return nil end
	return value
end

local function SpringSymbolName(rmlName)
	if not rmlName or rmlName == "UNKNOWN" then return nil end
	if string.match(rmlName, "^[0-9]$") then return "N_" .. rmlName end
	local numpadDigit = string.match(rmlName, "^NUMPAD([0-9])$")
	if numpadDigit then return "KP" .. numpadDigit end
	return SPRING_SYMBOL_BY_RML_NAME[rmlName] or rmlName
end

local function ResolveName(rmlName, keySymbols)
	if type(keySymbols) ~= "table" then return nil end
	rmlName = NormalizeName(rmlName)
	local springName = SpringSymbolName(rmlName)
	if not springName or springName == "UNKNOWN" then return nil end
	local keyCode = IsPositiveKeyCode(keySymbols[springName])
	if not keyCode then return nil end
	local label = string.match(springName, "^N_([0-9])$") or springName
	return keyCode, label
end

local function NamesForIdentifier(identifier, rmlIdentifiers)
	if type(rmlIdentifiers) ~= "table" then return {} end
	local names = {}
	for name, value in pairs(rmlIdentifiers) do
		if type(name) == "string" and value == identifier then
			names[#names + 1] = name
		elseif type(name) == "number" and name == identifier and type(value) == "string" then
			names[#names + 1] = value
		end
	end
	table.sort(names)
	return names
end

-- Resolves either an RML key_identifier value or its string name to the key
-- code expected by Spring's KeyPress/KeyRelease call-ins and a stable UI label.
function RmlKeyMapper.Resolve(identifier, rmlIdentifiers, keySymbols)
	if type(identifier) == "string" then
		local trimmed = identifier:match("^%s*(.-)%s*$")
		if string.match(trimmed or "", "^[0-9]$") then return ResolveName(trimmed, keySymbols) end
		local numericIdentifier = tonumber(trimmed)
		if not numericIdentifier then return ResolveName(trimmed, keySymbols) end
		identifier = numericIdentifier
	end
	if type(identifier) ~= "number" or identifier ~= identifier or identifier <= 0 then return nil end

	for _, name in ipairs(NamesForIdentifier(identifier, rmlIdentifiers)) do
		local keyCode, label = ResolveName(name, keySymbols)
		if keyCode then return keyCode, label end
	end
	return nil
end

return RmlKeyMapper
