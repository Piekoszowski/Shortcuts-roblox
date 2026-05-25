local S = require(game:GetService("ReplicatedFirst").Services.Internal.Shortcuts)

task.spawn(function()
	-- Shortcuts.DataHandler:WaitForLocal waits until local data is ready.
	if not S.DataHandler:WaitForLocal(20) then
		return
	end

	-- Shortcuts.RemoteFunction(name) accesses the data path endpoint.
	local getByPath = S.RemoteFunction("GetPlayerDataPath")
	local userIdPath = tostring(S.LocalPlayer.UserId)
	local unsavedPath = "UnsavedData_" .. tostring(S.LocalPlayer.UserId)

	-- Shortcuts.RemoteFunction:Invoke can for example request tables by path key.
	local savedTable = getByPath:Invoke(userIdPath)
	local unsavedTable = getByPath:Invoke(unsavedPath)

	print("get path saved table:", tostring(type(savedTable) == "table"))
	print("get path unsaved table:", tostring(type(unsavedTable) == "table"))
end)

return true
