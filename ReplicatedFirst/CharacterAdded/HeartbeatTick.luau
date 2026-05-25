local S = require(game:GetService("ReplicatedFirst").Services.Internal.Shortcuts)

local Module = {}

function Module.GetPriority(): number
	return 15
end

function Module.Init(player: Player, _character: Model): RBXScriptConnection?
	-- Shortcuts.LocalPlayer is a thing.
	if player ~= S.LocalPlayer then
		return nil
	end

	local count = 0
	local connection: RBXScriptConnection
	connection = S.RunService.Heartbeat:Connect(function()
		count += 1
		if count == 60 then
			print("around a second of heartbeats passed")
			connection:Disconnect()
		end
	end)

	return connection
end

return Module
