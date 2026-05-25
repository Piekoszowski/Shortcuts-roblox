local S = require(game:GetService("ReplicatedFirst").Services.Internal.Shortcuts)

-- Shortcuts function remotes support reliable and unreliable events.
local askReady = S.RemoteFunction("ShowAskReady", { TimeOut = 8, RateLimit = 20, RateLimitTime = 1 })
local askReadyUnreliable = S.UnreliableRemoteFunction("ShowAskReadyUnreliable", { TimeOut = 8, RateLimit = 20, RateLimitTime = 1 })

-- Shortcuts:Set updates timeout and rate options on the remote, this can be either set up in-line above in askReady and askReadyUnreliable constructors, or after with :Set like here.
askReady:Set({ TimeOut = 10 })
askReadyUnreliable:Set({ TimeOut = 10 })

local didSetupUnreliableCallback = false

local Module = {}

function Module.GetPriority(): number
	return 40
end

function Module.Init(player: Player, character: Model): ()
	if not didSetupUnreliableCallback then
		didSetupUnreliableCallback = true
		-- Shortcuts.UnreliableRemoteFunction:CallBack to OnClientEvent / OnServerEvent.
		askReadyUnreliable:CallBack(function(fromPlayer: Player, text: string): string
			return fromPlayer.Name .. " says " .. tostring(text)
		end)
		local unreliableCallbacks = askReadyUnreliable:GetCallBack() or {}
		print("server unreliable ready callbacks:", #unreliableCallbacks)
	end

	task.delay(1, function()
		-- Shortcuts.RemoteFunction:Fire and Shortcuts.RemoteFunction:Invoke both work for functions and events. You can use either.
		local readyReply = askReady:Fire(player, character.Name)

		print(player.Name, "ready reply:", tostring(readyReply))
	end)
end

return Module
