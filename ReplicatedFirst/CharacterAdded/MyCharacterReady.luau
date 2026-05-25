local S = require(game:GetService("ReplicatedFirst").Services.Internal.Shortcuts)

local Module = {}

function Module.GetPriority(): number
	return 30
end

function Module.Init(player: Player, character: Model): ()
	-- Shortcuts.LocalPlayer identifies the local user.
	if player ~= S.LocalPlayer then
		return
	end

	print("my body just spawned")
	print("body name:", character.Name)
end

return Module
