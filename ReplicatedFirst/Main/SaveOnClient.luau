local S = require(game:GetService("ReplicatedFirst").Services.Internal.Shortcuts)

task.spawn(function()
	-- Shortcuts.DataHandler:WaitForLocal waits until local data is ready.
	if not S.DataHandler:WaitForLocal(20) then
		return
	end

	-- Shortcuts.DataHandler(userId) accesses local replicated values under that key. The key can be anything, using userid is just one way to set up a general player data table.
	local data = S.DataHandler(S.LocalPlayer.UserId)

	data:Set("ClientOnly.Note", S.Data.ClientDefaults.DiaryNote)
	data:Set("ClientOnly.Volume", S.Data.ClientDefaults.StartVolume)
	-- Shortcuts.DataHandler:Set accepts an optional forceReplicate argument.
	data:Set("ClientOnly.Volume", S.Data.ClientDefaults.QuietVolume, true)

	print("client only note:", tostring(data:Get("ClientOnly.Note")))
	print("client only volume:", tostring(data:Get("ClientOnly.Volume")))
end)

return true
