local S = require(game:GetService("ReplicatedFirst").Services.Internal.Shortcuts)

-- all shortcut events and functions support rate limit options in the constructor.
local rateLimitedJoinEvent = S.RemoteEvent("ShowJoinRateLimitedEvent", { RateLimit = 2, RateLimitTime = 1 })

local Module = {}

function Module.GetPriority(): number
	return 20
end

function Module.Init(player: Player): ()
	-- Shortcuts:Set updates timeout and rate options on the remote, this can be either set up in-line above in rateLimitedJoinEvent constructor, or after with :Set like here.
	rateLimitedJoinEvent:Set({ RateLimit = 6, RateLimitTime = 1 })

	task.delay(1, function()
		-- Shortcuts.RemoteEvent:FireAll sends to all player clients.
		rateLimitedJoinEvent:FireAll(player.Name, "rate-limited join ping")

		print("server sent rate-limited join ping for", player.Name)
	end)
end

return Module
