local ActivationController = {}

function ActivationController.New(options)
	options = options or {}
	local self = {
		activeBinding = nil,
	}

	local function BindingFor(keyCode)
		return options.findBinding and options.findBinding(keyCode) or nil
	end

	local function IsOpen()
		return options.isOpen and options.isOpen() == true
	end

	local function Open(binding)
		self.activeBinding = binding
		local opened = not options.onOpen or options.onOpen(binding) ~= false
		if not opened then self.activeBinding = nil end
		return opened
	end

	local function Commit(binding)
		local committed = not options.onCommit or options.onCommit(binding) ~= false
		if committed then self.activeBinding = nil end
		return committed
	end

	function self:KeyPress(keyCode, isRepeat)
		local binding = BindingFor(keyCode)
		if not binding then return false end
		if isRepeat then return true end
		if binding.mode == "hold" and not IsOpen() then Open(binding) end
		return true
	end

	function self:KeyRelease(keyCode)
		local binding = BindingFor(keyCode)
		if not binding then return false end

		if binding.mode == "hold" then
			if self.activeBinding and self.activeBinding.keyCode == binding.keyCode then
				if IsOpen() then Commit(binding) else self.activeBinding = nil end
			end
			return true
		end

		if not IsOpen() then
			Open(binding)
		elseif self.activeBinding and self.activeBinding.keyCode == binding.keyCode then
			Commit(binding)
		end
		return true
	end

	function self:Reset()
		self.activeBinding = nil
	end

	function self:ActiveBinding()
		return self.activeBinding
	end

	return self
end

return ActivationController
