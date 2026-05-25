local S = require(game:GetService("ReplicatedFirst").Services.Internal.Shortcuts)

-- Shortcuts event remotes support reliable and unreliable events.
local clientPing = S.RemoteEvent("ShowClientPing", { RateLimit = 20, RateLimitTime = 1 })
local clientPingUnreliable = S.UnreliableRemoteEvent("ShowClientPingUnreliable", { RateLimit = 20, RateLimitTime = 1 })
local clientAsk = S.RemoteFunction("ShowClientAsk", { TimeOut = 8, RateLimit = 20, RateLimitTime = 1 })
local clientAskUnreliable = S.UnreliableRemoteFunction("ShowClientAskUnreliable", { TimeOut = 8, RateLimit = 20, RateLimitTime = 1 })

local didSetup = false

-- Shortcuts.DEBUGGING toggles the debug prints (warns, errors, silenterrors) visibility for the specified developers.
-- (1 = print, 2 = warn, 3 = error, 4 = silenterror. If number isn't in the table the developer won't have that debug print in their output visible.))
S.DEBUGGING({
	[409141] = { 1, 2, 3, 4 },
	[281575310] = { 1, 2 },
})

local Module = {}

function Module.GetPriority(): number
	return 50
end

local function setupOnce(): ()
	if didSetup then
		return
	end
	didSetup = true

	-- Shortcuts.RemoteEvent:CallBack to OnClientEvent / OnServerEvent.
	clientPing:CallBack(function(fromPlayer: Player, text: string)
		print(fromPlayer.Name, "says", text)
	end)

	-- Shortcuts.UnreliableRemoteEvent:CallBack to OnClientEvent / OnServerEvent.
	clientPingUnreliable:CallBack(function(fromPlayer: Player, text: string)
		print(fromPlayer.Name, "says unreliable", text)
	end)

	-- Shortcuts.RemoteFunction:CallBack to OnClientEvent / OnServerEvent.
	clientAsk:CallBack(function(_fromPlayer: Player, text: string): string
		return "server got " .. tostring(text)
	end)

	-- Shortcuts.UnreliableRemoteFunction:CallBack to OnClientEvent / OnServerEvent.
	clientAskUnreliable:CallBack(function(_fromPlayer: Player, text: string): string
		return "server got unreliable " .. tostring(text)
	end)

	-- Shortcuts:GetCallBack returns the callback (arrays).
	local pingCallbacks = clientPing:GetCallBack() or {}
	local unreliablePingCallbacks = clientPingUnreliable:GetCallBack() or {}
	local askCallbacks = clientAsk:GetCallBack() or {}
	local unreliableAskCallbacks = clientAskUnreliable:GetCallBack() or {}
	print("server ping callbacks:", #pingCallbacks)
	print("server unreliable ping callbacks:", #unreliablePingCallbacks)
	print("server ask callbacks:", #askCallbacks)
	print("server unreliable ask callbacks:", #unreliableAskCallbacks)

	-- Shortcuts:Set updates timeout and rate options on the remote, this can be either set up in-line above in clientPing, clientAsk, clientAskUnreliable and clientPingUnreliable constructors, or after with :Set like here.
	clientPing:Set({ RateLimit = 40, RateLimitTime = 1 })
	clientPingUnreliable:Set({ RateLimit = 40, RateLimitTime = 1 })
	clientAsk:Set({ TimeOut = 10, RateLimit = 40, RateLimitTime = 1 })
	clientAskUnreliable:Set({ TimeOut = 10, RateLimit = 40, RateLimitTime = 1 })
end

function Module.Init(player: Player): ()
	setupOnce()

	-- Shortcuts.Print and Shortcuts.Warn, Shortcuts.Error Shortcuts.SilentError are recommended to use, they work the same but provide strong per-module/script output visibilty tooling and silenterror is a way to error red without halting.
	S.print(player.Name, "joined")
	S.warn(player.Name, "is ready")
end

return Module
