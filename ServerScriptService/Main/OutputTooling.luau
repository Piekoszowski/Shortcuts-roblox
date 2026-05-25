local S = require(game:GetService("ReplicatedFirst").Services.Internal.Shortcuts)

-- Shortcuts.DEBUGGING configures output visiblity for this module.
S.DEBUGGING(true)

local function showDebug(player: Player): ()
	-- Shortcuts:Debug logs to output with the inputted severity. Defaults to print if no second argument is provided.
	S:Debug(player.Name .. " debug print is on", "print")
	S:Debug(player.Name .. " debug warn is on", "warn")
end

-- Shortcuts.Players accesses (shortcuts haha) the service. (S.<Service> is also cached.)
for _, player in ipairs(S.Players:GetPlayers()) do
	showDebug(player)
end

S.Players.PlayerAdded:Connect(function(player)
	showDebug(player)
end)

return true
