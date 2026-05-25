local S = require(game:GetService("ReplicatedFirst").Services.Internal.Shortcuts)

-- Shortcuts supports both BindableEvents and BindableFunctions.
local helloEvent = S.BindableEvent("ShowServerHelloEvent", { RateLimit = 50, RateLimitTime = 1 })
local helloFunction = S.BindableFunction("ShowServerHelloFunction", { RateLimit = 50, RateLimitTime = 1 })

local didSetup = false
local didShowDisconnect = false
local helloHandle: any = nil

local Module = {}

function Module.GetPriority(): number
	return 40
end

local function setupOnce(): ()
	if didSetup then
		return
	end
	didSetup = true

	-- Shortcuts.BindableEvent:CallBack to do the same listener as you would with :Event on the roblox bindableevent instances.
	helloHandle = helloEvent:CallBack(function(name: string)
		print("bindable event got", name)
	end)

	-- Shortcuts.BindableFunction:CallBack to do the same listener as you would with :Event on the roblox bindableevent instances.
	helloFunction:CallBack(function(name: string): string
		return "hi " .. name
	end)

	-- Shortcuts:GetCallBack returns the callback (arrays).
	local eventCallbacks = helloEvent:GetCallBack() or {}
	local functionCallbacks = helloFunction:GetCallBack() or {}
	print("bindable event callbacks:", #eventCallbacks)
	print("bindable function callbacks:", #functionCallbacks)

	-- Shortcuts:Set updates rate limits at runtime.
	helloEvent:Set({ RateLimit = 80, RateLimitTime = 1 })
	helloFunction:Set({ RateLimit = 80, RateLimitTime = 1 })
end

function Module.Init(player: Player): ()
	setupOnce()

	-- Shortcuts.BindableEvent:Invoke and Shortcuts.BindableEvent:Fire both work for functions and events. You can use either.
	helloEvent:Fire(player.Name)

	-- Shortcuts.BindableFunction:Fire and Shortcuts.BindableFunction:Invoke both work for functions and events. You can use either.
	print(helloFunction:Fire(player.Name))

	-- As stated above, Shortcuts.BindableFunction:Invoke and Shortcuts.BindableFunction:Fire both work for functions and events. You can use either.
	print(helloFunction:Invoke(player.Name))

	if helloHandle then
		helloHandle:Disconnect()
		helloHandle = helloEvent:CallBack(function(name: string)
			print("bindable event got", name)
		end)
	end

	if not didShowDisconnect then
		didShowDisconnect = true
		-- all shortcut events support disconnect cleanup.
		local tempEvent = S.BindableEvent("ShowTempBindableEvent")
		tempEvent:CallBack(function()
			print("temp bindable event ran")
		end)
		tempEvent:Disconnect()

		-- all shortcut events support disconnect cleanup.
		local tempFunction = S.BindableFunction("ShowTempBindableFunction")
		tempFunction:CallBack(function(): string
			return "temp ok"
		end)
		tempFunction:Disconnect()
		print("temp bindable objects are off")
	end
end

return Module
