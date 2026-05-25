local S = require(game:GetService("ReplicatedFirst").Services.Internal.Shortcuts)

-- Shortcuts event remotes support reliable and unreliable events.
local clientPing = S.RemoteEvent("ShowClientPing")
local clientPingUnreliable = S.UnreliableRemoteEvent("ShowClientPingUnreliable")

local didSendLocalPing = false

local Module = {}

function Module.GetPriority(): number
	return 30
end

function Module.Init(player: Player): ()
	print("client sees player:", player.Name)

	-- Shortcuts.LocalPlayer is a thing.
	if player ~= S.LocalPlayer or didSendLocalPing then
		return
	end
	didSendLocalPing = true

	-- Shortcuts:Set updates timeout and rate options on the remote, this can be either set up in-line above in clientPing and clientPingUnreliable constructors, or later with :Set like here.
	clientPing:Set({ RateLimit = 40, RateLimitTime = 1 })
	clientPingUnreliable:Set({ RateLimit = 40, RateLimitTime = 1 })

	-- Shortcuts.RemoteEvent:Invoke and Shortcuts.RemoteEvent:Fire both work for functions and events. You can use either.
	clientPing:Fire("hi from client")

	-- Shortcuts.UnreliableRemoteEvent:Invoke and Shortcuts.UnreliableRemoteEvent:Fire also both work for functions and events. You can use either.
	clientPingUnreliable:Fire("hi from client unreliable")

	print("client sent hello to server")
end

return Module
