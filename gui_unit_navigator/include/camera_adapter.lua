local CameraAdapter = {}

local function Copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, child in pairs(value) do result[key] = Copy(child) end
	return result
end

function CameraAdapter.New(engine)
	engine = engine or {}
	local self = {originalState = nil, previewed = false}

	function self:Capture()
		if not engine.GetCameraState then return nil end
		local ok, state = pcall(engine.GetCameraState)
		self.originalState = ok and type(state) == "table" and Copy(state) or nil
		self.previewed = false
		return self.originalState
	end

	function self:Preview(unitIDs, transitionSeconds)
		if not engine.GetUnitPosition or not engine.SetCameraTarget then return false end
		local xTotal, yTotal, zTotal, count = 0, 0, 0, 0
		for _, unitID in ipairs(unitIDs or {}) do
			local x, y, z = engine.GetUnitPosition(unitID)
			if x and z then
				xTotal = xTotal + x
				yTotal = yTotal + (y or 0)
				zTotal = zTotal + z
				count = count + 1
			end
		end
		if count == 0 then return false end
		engine.SetCameraTarget(xTotal / count, yTotal / count, zTotal / count, tonumber(transitionSeconds) or 0)
		self.previewed = true
		return true
	end

	function self:Restore(transitionSeconds)
		if not self.previewed or not self.originalState or not engine.SetCameraState then return false end
		engine.SetCameraState(Copy(self.originalState), tonumber(transitionSeconds) or 0)
		self.previewed = false
		return true
	end

	function self:Commit()
		self.originalState = nil
		self.previewed = false
	end

	return self
end

return CameraAdapter
