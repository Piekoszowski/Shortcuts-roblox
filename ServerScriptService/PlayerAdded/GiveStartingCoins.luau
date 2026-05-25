local S = require(game:GetService("ReplicatedFirst").Services.Internal.Shortcuts)

local Module = {}

function Module.GetPriority(): number
	return 35
end

function Module.Init(player: Player): ()
	-- Shortcuts.DataHandler(userId) reads the values assigned to that datahandler key. You can make infinite datahandlers and they can hold infinte keys. (Not in literal sense.)
	local userData = S.DataHandler(player.UserId)

	-- Shortcuts.DataHandler("UnsavedData_userId") stores replicated unsaved data.
	local unsavedData = S.DataHandler("UnsavedData_" .. tostring(player.UserId))

	-- Shortcuts.DataHandler(customKey) can store server only data unless the key is put in PlayerReplicas.
	local serverOnlyData = S.DataHandler("ServerOnly_" .. tostring(player.UserId))

	-- Shortcuts.DataHandler:Set can save and replicate inputted keys.
	userData:Set("LastPlayTime", "00:01")

	-- Shortcuts.DataHandler:Set also updates replicated-only keys.
	userData:Set("CurrentMood", "happy")

	-- Shortcuts.DataHandler:Set updates all datahandlers. You can control whether those datahandlers replicate and save, but not on the individual key level. Functionality is TBD if usage requests arrive for it.
	unsavedData:Set("LivePing", math.random(20, 80))

	-- Shortcuts.DataHandler:Set on custom keys makes them server only (or client only on the client) by default.
	serverOnlyData:Set("RoundScore", 1)

	print("saved value:", tostring(userData:Get("LastPlayTime")))
	print("current mood value:", tostring(userData:Get("CurrentMood")))
	print("server only value:", tostring(serverOnlyData:Get("RoundScore")))
end

return Module
