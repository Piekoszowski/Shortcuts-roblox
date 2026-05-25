local S = require(game:GetService("ReplicatedFirst").Services.Internal.Shortcuts)

local waitedForUserIds: { [number]: boolean } = {}

local function waitForOther(player: Player): ()
	if player == S.LocalPlayer or waitedForUserIds[player.UserId] then
		return
	end
	waitedForUserIds[player.UserId] = true

	task.spawn(function()
		-- Shortcuts.DataHandler:WaitFor waits for a specific non-local key.
		local received = S.DataHandler:WaitFor(player.UserId, 20)
		print("wait for", player.Name, "data:", tostring(received))
	end)
end

for _, player in ipairs(S.Players:GetPlayers()) do
	waitForOther(player)
end

S.Players.PlayerAdded:Connect(function(player)
	waitForOther(player)
end)

return true
