local S = require(game:GetService("ReplicatedFirst").Services.Internal.Shortcuts)

local Module = {}

function Module.GetPriority(): number
	return 10
end

function Module.Init(player: Player, _character: Model): RBXScriptConnection?
	-- Shortcuts.LocalPlayer is a thing.
	if player ~= S.LocalPlayer then
		return nil
	end

	-- Shortcuts.UserInputService accesses the service using :GetService (it's cached).
	local connection = S.UserInputService.InputBegan:Connect(
		function(input: InputObject, processed: boolean)
			if processed then
				return
			end
			if input.KeyCode == Enum.KeyCode.H then
				print("you pressed h")
			end
		end
	)

	print("press h to test a key")
	return connection
end

return Module
