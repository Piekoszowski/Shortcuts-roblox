local S = require(game:GetService("ReplicatedFirst").Services.Internal.Shortcuts)

local Module = {}

function Module.GetPriority(): number
	return 30
end

function Module.Init(player: Player, character: Model): ()
	print(player.Name, "got a body")
	print("body name:", character.Name)
end

return Module
