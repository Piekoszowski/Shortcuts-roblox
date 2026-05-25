local S = require(game:GetService("ReplicatedFirst").Services.Internal.Shortcuts)

local Module = {}

function Module.GetPriority(): number
	return 25
end

function Module.Init(player: Player, character: Model): ()
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid

	humanoid.MaxHealth = 250
	humanoid.Health = 250
	humanoid.WalkSpeed = 22

	print(player.Name, "is now strong")
end

return Module
