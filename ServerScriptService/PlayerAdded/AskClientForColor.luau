local S = require(game:GetService("ReplicatedFirst").Services.Internal.Shortcuts)

-- Shortcuts function remotes support reliable and unreliable events.
local askColor = S.RemoteFunction("ShowAskColor", {
	TimeOut = 8,
	RateLimit = 30,
	RateLimitTime = 1,
})

-- Shortcuts:Set updates timeout and rate options on the remote, this can be either set up in-line above in askColor constructor, or after with :Set like here.
askColor:Set({ TimeOut = 10 })

local Module = {}

function Module.GetPriority(): number
	return 15
end

function Module.Init(player: Player): ()
	task.delay(3, function()
		-- Shortcuts.RemoteFunction:Fire and Shortcuts.RemoteFunction:Invoke both work for functions and events. You can use either.
		local oneAnswer = askColor:Fire(player, "pick a color")
		print(player.Name, "color:", tostring(oneAnswer))

		-- Shortcuts.RemoteFunction:FireAll invokes all players. InvokeAll doesn't exist.
		local allAnswers = askColor:FireAll("say your color")
		if type(allAnswers) == "table" then
			for answerPlayer, packed in pairs(allAnswers) do
				local answer = if type(packed) == "table" then packed[1] else packed
				print("all color from", answerPlayer.Name, tostring(answer))
			end
		end
	end)
end

return Module
