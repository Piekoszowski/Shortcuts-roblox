local S = require(game:GetService("ReplicatedFirst").Services.Internal.Shortcuts)

-- Shortcuts function remotes support reliable and unreliable events.
local unreliableJoinEvent = S.UnreliableRemoteEvent("ShowJoinUnreliableEvent", { RateLimit = 3, RateLimitTime = 1 })

local Module = {}

function Module.GetPriority(): number
	return 25
end

function Module.Init(player: Player): ()
	-- Shortcuts:Set updates timeout and rate options on the remote, this can be either set up in-line above in unreliableJoinEvent constructor, or after with :Set like here.
	unreliableJoinEvent:Set({ RateLimit = 8, RateLimitTime = 1 })

	task.delay(1, function()
		-- Shortcuts.UnreliableRemoteEvent:FireAll sends to every player client in the server.
		unreliableJoinEvent:FireAll(player.Name, "unreliable ping")

		-- Shortcuts.UnreliableRemoteEvent:FireTo targets selected table of players! (must be player objects)
		unreliableJoinEvent:FireTo({ player }, "unreliable ping to you")

		-- Shortcuts.UnreliableRemoteEvent:FireAllExcept skips selected player clients.
		unreliableJoinEvent:FireAllExcept({ player }, player.Name, "unreliable ping to others")

		print("server sent unreliable pings for", player.Name)
	end)
end

return Module
