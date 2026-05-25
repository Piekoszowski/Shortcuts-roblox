local S = require(game:GetService("ReplicatedFirst").Services.Internal.Shortcuts)

task.spawn(function()
	-- Shortcuts.DataHandler:WaitForLocal waits until the client has received server data.
	if not S.DataHandler:WaitForLocal(20) then
		return
	end

	-- Shortcuts.DataHandler(userId) accesses local replicated values under that key. The key can be anything, using userid is just one way to set up a general player data table.
	local data = S.DataHandler(S.LocalPlayer.UserId)

	-- Shortcuts.DataHandler.Changed:Connect listens for value updates under that key. (This includes nested changes.)
	data.Changed:Connect("LastPlayTime", function(newValue: any, oldValue: any)
		print("saved value changed from", tostring(oldValue), "to", tostring(newValue))
	end)

	-- Shortcuts.DataHandler.Changed:Connect of course also works for live replicated keys, I use it for this specific purpose here.
	data.Changed:Connect("CurrentMood", function(newValue: any, oldValue: any)
		print("current mood changed from", tostring(oldValue), "to", tostring(newValue))
	end)

	-- Shortcuts.DataHandler.Changed:Connect also works for client-only keys. :) Save on networking, it's still a useful tool for data management in general, not just networking.
	data.Changed:Connect("ClientOnly.Note", function(newValue: any)
		print("client only note is now", tostring(newValue))
	end)
end)

return true
