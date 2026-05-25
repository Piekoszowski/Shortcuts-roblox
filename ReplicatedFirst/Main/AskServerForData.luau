local S = require(game:GetService("ReplicatedFirst").Services.Internal.Shortcuts)

task.delay(4, function()
	-- Shortcuts.RemoteFunction(name) sets up the remote. Set up both endpoints (client and server) one :CallBack one :Fire and that's it.
	local getter = S.RemoteFunction("GetPlayerData")
	-- Shortcuts.RemoteFunction:Invoke and Shortcuts.RemoteFunction:Fire both work for functions and events. You can use either.
	local savedValue = getter:Invoke(S.Data.ProfileKeys.JourneyTime)
	local liveValue = getter:Invoke(S.Data.ProfileKeys.CurrentMood)
	print("server says saved value is", tostring(savedValue))
	print("server says current mood is", tostring(liveValue))

	-- Shortcuts.RemoteFunction:Invoke example usage. Retreiving a table.
	local allData = getter:Invoke()
	if type(allData) == "table" then
		print("server gave full data table")
	end
end)

return true
