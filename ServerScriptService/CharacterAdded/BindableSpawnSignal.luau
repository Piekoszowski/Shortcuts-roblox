local S = require(game:GetService("ReplicatedFirst").Services.Internal.Shortcuts)

-- Shortcuts binadble events do not use the bindableevent object they are handled with tables internally instead.
local spawnedEvent = S.BindableEvent("ShowCharacterSpawnEvent", { RateLimit = 80, RateLimitTime = 1 })

local didSetup = false

local Module = {}

function Module.GetPriority(): number
	return 10
end

local function setupOnce(): ()
	if didSetup then
		return
	end
	didSetup = true

	-- Shortcuts.BindableEvent:CallBack to do the same listener as you would with :Event on the roblox bindableevent instances.
	spawnedEvent:CallBack(function(name: string)
		print(name, "spawned in")
	end)
end

function Module.Init(player: Player, _character: Model): ()
	setupOnce()

	-- Shortcuts:Set updates timeout and rate options on the remote, this can be either set up in-line above in spawnedEvent constructor, or after with :Set like here.
	spawnedEvent:Set({ RateLimit = 120, RateLimitTime = 1 })

	-- Shortcuts.BindableEvent:Fire and Shortcuts.BindableEvent:Invoke both work for functions and events. You can use either.
	spawnedEvent:Fire(player.Name)

	-- Shortcuts:GetCallBack returns the callback (arrays).
	local callbacks = spawnedEvent:GetCallBack() or {}
	print("spawn bindable callbacks:", #callbacks)
end

return Module
