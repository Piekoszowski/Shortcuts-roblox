local S = require(game:GetService("ReplicatedFirst").Services.Internal.Shortcuts)

-- Shortcuts function remotes support reliable and unreliable events.
local rangeEvent = S.RemoteEvent("ShowRangeEvent")
local rangeUnreliableEvent = S.UnreliableRemoteEvent("ShowRangeUnreliableEvent")

local didSetup = false

local Module = {}

function Module.GetPriority(): number
	return 40
end

function Module.Init(player: Player, _character: Model): ()
	-- Shortcuts.LocalPlayer is a thing.
	if player ~= S.LocalPlayer or didSetup then
		return
	end
	didSetup = true

	-- Shortcuts.RemoteEvent:CallBack to OnClientEvent / OnServerEvent.
	rangeEvent:CallBack(function(message: string)
		print("server says:", message)
	end)

	-- Shortcuts.UnreliableRemoteEvent:CallBack to OnClientEvent / OnServerEvent.
	rangeUnreliableEvent:CallBack(function(name: string, message: string)
		print(name, message)
	end)

	-- Shortcuts:GetCallBack returns the callback (arrays).
	local rangeCallbacks = rangeEvent:GetCallBack() or {}
	local unreliableCallbacks = rangeUnreliableEvent:GetCallBack() or {}
	print("range callbacks:", #rangeCallbacks)
	print("unreliable range callbacks:", #unreliableCallbacks)
end

return Module
