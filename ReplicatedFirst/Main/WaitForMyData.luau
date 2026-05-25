local S = require(game:GetService("ReplicatedFirst").Services.Internal.Shortcuts)

task.spawn(function()
	-- Shortcuts.DataHandler:WaitForLocal waits until the client has received server data.
	local ready = S.DataHandler:WaitForLocal(20)
	if not ready then
		print("my data took too long")
		return
	end

	-- Shortcuts.DataHandler(userId) reads the local values that are replicated from the server.
	local data = S.DataHandler(S.LocalPlayer.UserId)
	print("my data is ready")
	print("saved value:", tostring(data:Get(S.Data.ProfileKeys.JourneyTime)))
	print("current mood value:", tostring(data:Get(S.Data.ProfileKeys.CurrentMood)))
	print("live ping value:", tostring(data:Get(S.Data.ProfileKeys.EchoPing)))
end)

return true
