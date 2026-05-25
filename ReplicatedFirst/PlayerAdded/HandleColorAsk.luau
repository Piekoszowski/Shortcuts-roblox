local S = require(game:GetService("ReplicatedFirst").Services.Internal.Shortcuts)

-- Shortcuts function remotes support reliable and unreliable events.
local askColor = S.RemoteFunction("ShowAskColor")
local askServer = S.RemoteFunction("ShowClientAsk")
local askServerUnreliable = S.UnreliableRemoteFunction("ShowClientAskUnreliable")

local didSetup = false
local didAskServer = false

local Module = {}

function Module.GetPriority(): number
	return 35
end

function Module.Init(player: Player): ()
	-- Shortcuts.LocalPlayer is a thing.
	if player ~= S.LocalPlayer then
		return
	end

	if not didSetup then
		didSetup = true

		-- Shortcuts.RemoteFunction:CallBack to OnClientEvent / OnServerEvent.
		askColor:CallBack(function(_question: string): string
			return "blue"
		end)

		-- Shortcuts:GetCallBack returns the callback (arrays).
		local callbacks = askColor:GetCallBack() or {}
		print("color callbacks:", #callbacks)

		-- Shortcuts:Set updates timeout and rate options on the remote, this can be either set up in-line above in askColor constructor, or later with :Set like here.
		askColor:Set({ TimeOut = 12 })

	end

	if didAskServer then
		return
	end
	didAskServer = true

	task.delay(3, function()
		local serverReplyByFire = askServer:Fire("hello by fire")
		local serverReply = askServer:Invoke("hello")
		local serverUnreliableReplyByFire = askServerUnreliable:Fire("hello unreliable by fire")
		local serverUnreliableReply = askServerUnreliable:Invoke("hello unreliable")
		print("server reply by fire:", tostring(serverReplyByFire))
		print("server reply:", tostring(serverReply))
		print("server unreliable reply by fire:", tostring(serverUnreliableReplyByFire))
		print("server unreliable reply:", tostring(serverUnreliableReply))
	end)
end

return Module
