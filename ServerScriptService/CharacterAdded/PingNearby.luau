local S = require(game:GetService("ReplicatedFirst").Services.Internal.Shortcuts)

-- Shortcuts remote events support distance based targeting :D
local rangeEvent = S.RemoteEvent("ShowRangeEvent", { RateLimit = 20, RateLimitTime = 1 })
local rangeUnreliableEvent =
	S.UnreliableRemoteEvent("ShowRangeUnreliableEvent", { RateLimit = 20, RateLimitTime = 1 })

local Module = {}

function Module.GetPriority(): number
	return 35
end

function Module.Init(player: Player, _character: Model): ()
	-- Shortcuts:FireTo targets selected table of players! (must be player objects)
	rangeEvent:FireTo({ player }, "you spawned")

	-- Shortcuts:FireDistance uses default render distance if not specified.
	rangeEvent:FireDistance(player)

	-- You specify it as a second argument.
	rangeEvent:FireDistance(player, 80)

	-- Shortcuts.UnreliableRemoteEvent also supports FireDistance!
	rangeUnreliableEvent:FireDistance(player, 80, player.Name, "spawned near")

	print("server sent range pings for", player.Name)
end

return Module
