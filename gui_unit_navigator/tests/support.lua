local Support = {}

function Support.equals(actual, expected, message)
	if actual ~= expected then
		error((message or "values differ") .. ": expected " .. tostring(expected) .. ", actual " .. tostring(actual), 2)
	end
end

function Support.truthy(value, message)
	if not value then error(message or "expected truthy value", 2) end
end

function Support.falsy(value, message)
	if value then error(message or "expected falsy value", 2) end
end

function Support.contains(text, expected, message)
	if not string.find(tostring(text or ""), expected, 1, true) then
		error((message or "text does not contain expected value") .. ": " .. tostring(expected), 2)
	end
end

function Support.arrayEquals(actual, expected, message)
	Support.equals(#(actual or {}), #(expected or {}), (message or "arrays differ") .. " length")
	for index = 1, #expected do Support.equals(actual[index], expected[index], (message or "arrays differ") .. " at " .. index) end
end

function Support.read(path)
	local file = assert(io.open(path, "rb"))
	local content = file:read("*a")
	file:close()
	return content
end

return Support
