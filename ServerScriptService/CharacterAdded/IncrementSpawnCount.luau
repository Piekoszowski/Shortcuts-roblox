local S = require(game:GetService("ReplicatedFirst").Services.Internal.Shortcuts)

local Module = {}

function Module.GetPriority(): number
	return 15
end

function Module.Init(player: Player, _character: Model): ()
	-- Doing something like Shortcuts.DataHandler(userId) is a cool to make per-player storages for their data.
	local data = S.DataHandler(player.UserId)

	-- Shortcuts.DataHandler supports Increment and Decrement methods.
	data:Increment("Spawns", 1)
	data:Increment("BonusSpawns", 5)
	data:Decrement("BadLuck", 1)

	print(player.Name, "spawn count:", tostring(data:Get("Spawns")))
	print(player.Name, "bonus spawns:", tostring(data:Get("BonusSpawns")))
end

return Module
