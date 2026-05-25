local S = require(game:GetService("ReplicatedFirst").Services.Internal.Shortcuts)

-- Shortcuts event remotes support reliable and unreliable events timeout and rate options on the remote and bindables can be either set up here or later with joinEvent:Set({ RateLimit = number, RateLimitTime = number }).
local joinEvent = S.RemoteEvent("ShowJoinEvent", { RateLimit = 80, RateLimitTime = 1 })

local didSetup = false
local didShowTempDisconnect = false

local Module = {}

function Module.GetPriority(): number
	return 40
end

function Module.Init(_player: Player): ()
	if didSetup then
		return
	end
	didSetup = true

	-- Shortcuts.RemoteEvent:CallBack to OnClientEvent / OnServerEvent.
	joinEvent:CallBack(function(name: string, action: string)
		print(name, action)
	end)

	-- :Once listens once and auto disconnects.
	joinEvent:Once(function(name: string)
		print("first join we heard:", name)
	end)

	-- Shortcuts:GetCallBack returns the callback (arrays).
	local callbacks = joinEvent:GetCallBack() or {}
	print("join event callbacks:", #callbacks)

	if not didShowTempDisconnect then
		didShowTempDisconnect = true
		-- all shortcut events support disconnect cleanup.
		local tempEvent = S.RemoteEvent("ShowTempRemote")
		tempEvent:CallBack(function()
			print("temp remote callback ran")
		end)
		tempEvent:Disconnect()
		print("temp remote listener is off")
	end
end

return Module
