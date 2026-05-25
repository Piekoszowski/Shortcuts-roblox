local S = require(game:GetService("ReplicatedFirst").Services.Internal.Shortcuts)

local Module = {}

function Module.GetPriority(): number
	return 25
end

function Module.Init(player: Player, _character: Model): ()
	-- Shortcuts.LocalPlayer is a thing.
	if player ~= S.LocalPlayer then
		return
	end

	-- Shortcuts.Workspace and Shortcuts.Lighting accesses the service using :GetService (it's cached).
	print("world gravity is", S.Workspace.Gravity)
	print("time of day is", S.Lighting.ClockTime)
end

return Module
