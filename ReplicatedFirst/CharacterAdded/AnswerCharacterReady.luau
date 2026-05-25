local S = require(game:GetService("ReplicatedFirst").Services.Internal.Shortcuts)

-- Shortcuts function remotes support reliable and unreliable events.
local askReady = S.RemoteFunction("ShowAskReady")
local askReadyUnreliable = S.UnreliableRemoteFunction("ShowAskReadyUnreliable")

local didSetup = false
local didInvokeUnreliable = false

local Module = {}

function Module.GetPriority(): number
	return 45
end

function Module.Init(player: Player, _character: Model): ()
	-- Shortcuts.LocalPlayer is a thing
	if player ~= S.LocalPlayer or didSetup then
		return
	end
	didSetup = true

	-- Shortcuts.RemoteFunction:CallBack to OnClientEvent / OnServerEvent.
	askReady:CallBack(function(_characterName: string): string
		return "yes ready"
	end)

	-- Shortcuts:GetCallBack returns the callback (arrays).
	local readyCallbacks = askReady:GetCallBack() or {}
	print("ready callbacks:", #readyCallbacks)

	-- Shortcuts:Set updates timeout and rate options on the remote, this can be either set up in-line above in askReady and askReadyUnreliable lines, or later with :Set like here.
	askReady:Set({ TimeOut = 12, RateLimit = 40, RateLimitTime = 1 })
	askReadyUnreliable:Set({ TimeOut = 12, RateLimit = 40, RateLimitTime = 1 })

	if not didInvokeUnreliable then
		didInvokeUnreliable = true
		task.delay(2, function()
			local unreliableReply = askReadyUnreliable:Invoke("i am ready")
			print("server unreliable ready reply:", tostring(unreliableReply))
		end)
	end

	print("client will answer ready checks")
end

return Module
