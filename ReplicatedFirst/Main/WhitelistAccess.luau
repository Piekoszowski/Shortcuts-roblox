local S = require(game:GetService("ReplicatedFirst").Services.Internal.Shortcuts)

-- Shortcuts.RemoteFunction(name) accesses whitelist request endpoints.
local requestWhitelist = S.RemoteFunction("RequestDataWhitelist")
local removeWhitelist = S.RemoteFunction("RemoveDataWhitelist")

local handledTargets: { [number]: boolean } = {}

local function runForTarget(player: Player): ()
	if player == S.LocalPlayer or handledTargets[player.UserId] then
		return
	end
	handledTargets[player.UserId] = true

	task.spawn(function()
		task.wait(2)
		-- Shortcuts.RemoteFunction:Invoke RequestDataWhitelist sends a whitelist request.
		local requestOk = requestWhitelist:Invoke(player.UserId)
		print("request whitelist for", player.Name, ":", tostring(requestOk))

		task.wait(2)
		-- Shortcuts.RemoteFunction:Invoke RemoveDataWhitelist sends a whitelist removal request.
		local removeOk = removeWhitelist:Invoke(player.UserId)
		print("remove whitelist for", player.Name, ":", tostring(removeOk))
	end)
end

for _, player in ipairs(S.Players:GetPlayers()) do
	runForTarget(player)
end

S.Players.PlayerAdded:Connect(function(player)
	runForTarget(player)
end)

return true
