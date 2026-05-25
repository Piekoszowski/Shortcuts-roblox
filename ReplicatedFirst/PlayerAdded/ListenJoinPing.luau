local S = require(game:GetService("ReplicatedFirst").Services.Internal.Shortcuts)

-- Shortcuts event remotes support reliable and unreliable events.
local rateLimitedJoinEvent = S.RemoteEvent("ShowJoinRateLimitedEvent")
local unreliableJoinEvent = S.UnreliableRemoteEvent("ShowJoinUnreliableEvent")

local didSetup = false
local didShowDisconnect = false

local Module = {}

function Module.GetPriority(): number
	return 25
end

function Module.Init(_player: Player): ()
	if didSetup then
		return
	end
	didSetup = true

	-- Shortcuts.RemoteEvent:CallBack to OnClientEvent / OnServerEvent.
	rateLimitedJoinEvent:CallBack(function(name: string, message: string)
		print("rate-limited join from", name, message)
	end)

	-- Shortcuts.UnreliableRemoteEvent:CallBack to OnClientEvent / OnServerEvent.
	unreliableJoinEvent:CallBack(function(name: string, message: string)
		print("unreliable join from", name, message)
	end)

	-- Shortcuts:GetCallBack returns the callback (arrays).
	local rateLimitedCallbacks = rateLimitedJoinEvent:GetCallBack() or {}
	local unreliableCallbacks = unreliableJoinEvent:GetCallBack() or {}
	print("rate-limited join callbacks:", #rateLimitedCallbacks)
	print("unreliable join callbacks:", #unreliableCallbacks)

	if not didShowDisconnect then
		didShowDisconnect = true
		-- all shortcut events support disconnect cleanup.
		local tempUnreliable = S.UnreliableRemoteEvent("ShowTempUnreliable")
		tempUnreliable:CallBack(function()
			print("temp unreliable callback ran")
		end)
		tempUnreliable:Disconnect()
		print("temp unreliable listener is off")
	end
end

return Module
