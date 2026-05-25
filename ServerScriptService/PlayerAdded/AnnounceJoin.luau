local S = require(game:GetService("ReplicatedFirst").Services.Internal.Shortcuts)

-- Shortcuts event remotes support reliable and unreliable events.
local joinEvent = S.RemoteEvent("ShowJoinEvent")

local Module = {}

function Module.GetPriority(): number
	return 30
end

function Module.Init(player: Player): ()
	task.delay(1, function()
		-- Shortcuts.RemoteEvent:FireAll sends to every client in the game.
		joinEvent:FireAll(player.Name, "joined")

		-- Shortcuts.RemoteEvent:FireAllExcept skips selected player clients.
		joinEvent:FireAllExcept({ player }, player.Name, "joined too")

		-- Shortcuts.RemoteEvent:FireTo targets selected player clients.
		joinEvent:FireTo({ player }, "you joined")

		print("server told clients about", player.Name)
	end)
end

return Module
