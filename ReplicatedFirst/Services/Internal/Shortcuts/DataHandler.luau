--!strict
--!optimize 2

--[[ Whether to save to datastore or load saved datastore values in studio, or apply DefaultProfileData defaults on every studio playtest. ]]--
local DontSaveInStudio = false
local DontLoadInStudio = false

--[[ Modules ]]--
type DefaultProfileDataShape = {
	DataVersion: number,
	LastSave: number?,
	LastPlayTime: string?,
	[string]: any,
}

local DefaultProfileData = require(script.Parent.DefaultProfileData) :: DefaultProfileDataShape
local Helpers = require(script.Parent.Helpers)
local ReplicatedKeys: { string } = require(script.Parent.ReplicatedKeys)
local SavedKeys: { string } = require(script.Parent.SavedKeys)
local PlayerReplicas = require(script.Parent.PlayerReplicas)
local Signal = require(game:GetService("ReplicatedFirst"):FindFirstChild("Signal", true))

--[[ Typing ]]--
export type CallbackFunction = (newValue: any, oldValue: any) -> ()

export type ListenerObject = {
	Connect: (
		self: ListenerObject,
		propertyName: string,
		callback: CallbackFunction
	) -> ListenerObject,
	Disconnect: (self: ListenerObject, propertyName: string, callback: CallbackFunction) -> (),
	Invoke: (
		self: ListenerObject,
		propertyName: string,
		newValue: any,
		oldValue: any,
		dataGetter: ((string) -> any)?
	) -> (),
}

export type DataObject = {
	Key: string | number,
	Changed: ListenerObject,
	Set: (
		self: DataObject,
		path: string,
		newValue: any,
		increment: boolean?,
		forceReplicate: boolean?
	) -> (),
	Get: (self: DataObject, path: string?) -> any,
	Increment: (self: DataObject, path: string, value: number) -> (),
	Decrement: (self: DataObject, path: string, value: number) -> (),
}

export type DataMap = Helpers.DataMap
export type NavigationResult = Helpers.NavigationResult

export type Profile = {
	Data: DataMap,
	AddUserId: (self: Profile, userId: number) -> (),
	EndSession: (self: Profile) -> (),
	OnSessionEnd: RBXScriptSignal,
}

export type Replica = {
	Data: DataMap,
	Tags: { [string]: any },
	Set: (self: Replica, path: { any }, value: any) -> (),
	Subscribe: (self: Replica, player: Player) -> (),
	Unsubscribe: (self: Replica, player: Player) -> (),
	Destroy: (self: Replica) -> (),
	OnChange: (
		self: Replica,
		callback: (action: string, path: { string }, param1: any, param2: any) -> ()
	) -> (),
}

export type ReplicaService = {
	OnNew: (token: string, callback: (replica: Replica) -> ()) -> (),
	RequestData: () -> (),
	Token: (name: string) -> any,
	New: (params: { [string]: any }) -> Replica,
	ReadyPlayers: { [Player]: boolean },
	NewReadyPlayer: RBXScriptSignal,
}

export type ProfileStoreClass = {
	StartSessionAsync: (
		self: ProfileStoreClass,
		key: string,
		options: { Cancel: () -> boolean }
	) -> Profile?,
	Mock: ProfileStoreClass,
}

--[[
	You can add keys runtime to any S.DataHandler(KeyYouWannaAccess) with :Set whenever you want. They don't have to exist beforehand. Keys made on client obviously stay client only.

	A data & replication manager for player keyed data (& non-player bound data is supported too! Just don't input the userid as the key thats it) objects wrap ProfileStore + Replica + a listener signal system behind one API.
	Every bucket of data (S.DataHandler(KeyStringThisIsTheBucket):Get("SomePathToAValue")) lives behind a key (typically a UserId; recommended for player bound data).
	Buckets can be saved + replicated, replicated-only, saved-only, or pure local, the datahandler key you use you write decide which.
	On the server it loads the profile through ProfileStore, mirrors it into a Replica per PlayerReplicas token, and delivers to the subscribed viewers (by default set ups only the player whose userid the datahandler key is)
	On the client it listens to the same replicas and writes them back into local buckets so :Get reads are instant, client set data never makes it to the server of course. Use remote events/functions.

	Flip DontSaveInStudio / DontLoadInStudio to your liking when iterating so you don't pollute real saves.
	DefaultProfileData is the player-bound template for keys they save and replicate. Any key here is auto-saved + auto-replicated. DataVersion triggers migration patch. (bump it + add new keys, old profiles get the new keys deep-copied i)
	ReplicatedKeys is any extra keys (so not the ones in DefaultProfileData) that should sync to the client but shouldn't save to datastore. Good for UI / volatile stuff.
	SavedKeys is any extra keys that should persist even if you forgot to put them in DefaultProfileData. Good for server data values introduced post launch, although DataVersion migration works just fine.
	PlayerReplicas lists replica token names to instantiate per player (ex. {"PlayerData"}). One Replica per token, all force-replicated + force-saved because it carries the live profile data. (often called just player data)

	S.DataHandler(key) to get a DataObject for that key. key is usually player.UserId for normal player data. use any string you want for non-player bound data. (that works always, it's intended to be used aswell)
	S.DataHandler("UnsavedData_" .. UserId) is an unsaved mirror. It has some use cases, you can add keys runtime on server that you want replicated but not saved, this module replicates to the player at the rate of the normal UserId one!
	S.DataHandler("AnyCustomKey") any non-player bound data goes here. Game events, weather, whatever you need. If the root path you write is in ReplicatedKeys, the value auto-replicates to every player through a shared "SharedData" replica (every connected player is auto-subscribed). Anything not in ReplicatedKeys stays local to whichever side wrote it. SavedKeys / DefaultProfileData do nothing here, there's no global datastore. (TODO: Maybe in the future.)

	dataObject:Get(path?) -> any | Get("Key") returns one key. Get("Inventory.Slots.1") supports the dotted paths (numeric segments are coerced to number ). Get() with no path returns the whole data table of that key.
	dataObject:Set(path, newValue, increment?, forceReplicate?) | writes the value. increment=true adds newValue if the current value is a number. forceReplicate=true ignores even if the deepequal is positive and replicates anyway.
	dataObject:Increment(path, value)
	dataObject:Decrement(path, value)

	dataObject.Changed:Connect(path, function(newValue, oldValue) end) | listens for changes at that path. writing "Inventory.Slots.1.ItemId" fires listeners on "Inventory.Slots.1", "Inventory.Slots", "Inventory" too. (because it supports deep table changes)
	dataObject.Changed:Disconnect(path, callback) drops the callback connected with that exact function reference.
	oldValue is NOT guaranteed. Always add a case for oldValue being nil! You will run into this being nil it's designed so!

	S.DataHandler:IsReady(key) -> boolean | true once all configured replica tokens have connected and work for that datahandler key.
	S.DataHandler:WaitFor(key, timeoutSeconds?) -> boolean | yields until isReady or timeout (default 20s). false on timeout.
	S.DataHandler:WaitForLocal(timeoutSeconds?) -> boolean | same as above but puts the userid as the first argument for you, nothing else. You can use this if your keys are UserIds.

	S.DataHandler.AddToWhitelist(viewerUserId, targetUserId) | grants the player thats viewerUserId all of the data that is being replicated to targetUserId from server.
	S.DataHandler.RemoveFromWhitelist(viewerUserId, targetUserId) | revokes the above permission.
	S.DataHandler.IsWhitelisted(viewerUserId, targetUserId) -> boolean | if ou put the same user id in viewerUserId and targetUserId at the same time this will always return true you won't un-whitelist your own player data!
	S.RemoteFunction("RequestDataWhitelist"):InvokeServer(targetUserId) -> boolean | client asks the server to whitelist itself for the target player's data. Server practically always grants. No condiitons.
	S.RemoteFunction("RemoveDataWhitelist"):InvokeServer(targetUserId) -> boolean | client asks server to revoke that whitelist now. Server practically always grants. No condiitons.

	S.RemoteFunction("GetPlayerData") always returns S.DataHandler(UserId):Get(). Always does UserId.
	S.RemoteFunction("GetPlayerDataPath") | client: Invoke(dataHandlerKey) -> table. Server reads S.DataHandler(dataHandlerKey):Get() and returns the full bucket. Whole-bucket only, no nested dot-paths — use GetPlayerData for those.
	S.BindableFunction("GetPlayerData") | always returns S.DataHandler(UserId):Get(). Always does UserId.
	S.BindableEvent("SetPlayerData") | (player, dataPath, newValue). does S.DataHandler(player.UserId):Set(dataPath, newValue). Always does UserId.
	S.BindableFunction("IncrementPlayerData") | (player, dataPath, amount). Increments S.DataHandler(player.UserId) at given dataPath. Always does UserId.

	Multiple callbacks per path are allowed and they all run.
	Errors inside a .Changed callback surface with traceback but don't halt the runtime.
	Unless you pass forceReplicate=true if you set a value to the same one (DeepEqual included, so it checks the whole deep nest) it won't fire listeners.
	Don't try to edit PlayerReplicas DefaultProfileData SavedKeys ReplicatedKeys on runtime, they are frozen tables and should remaintable.freeze as there is no support for editing them runtime right now.
]]

--[[ DataHandler ]]--
return function(S: any): any
	local Module: { [string]: any } = {}
	local Profiles: { [number]: Profile } = {}
	local replicatedKeysSet: { [string]: boolean } = {}
	local savedKeysSet: { [string]: boolean } = {}

	Module.Profiles = {} :: { [Player]: Profile }
	Module.ProfileReplica = {} :: { [number]: Replica }
	Module.ProfileReplicas = {} :: { [number]: { [string]: Replica } }
	Module.DataWhitelist = {} :: { [number]: { [number]: boolean } }
	Module.ReceivedDataSources = {} :: { [number]: boolean }
	Module.DataStore = {} :: { [string | number]: DataMap }
	Module.DataObjects = {} :: { [string | number]: DataObject }

	local replicaTokenNames: { string } = Helpers.normalizeReplicaTokenNames(PlayerReplicas)
	local receivedReplicaTokens: { [number]: { [string]: boolean } } = {}

	--[[ All keys from DefaultProfileData replicate and save by default, ReplicatedKeys is for keys not in DefaultProfileData that we want replicated. ]]--
	for _, key in ipairs(ReplicatedKeys) do
		replicatedKeysSet[key] = true
	end
	
	--[[ All keys from DefaultProfileData replicate and save by default, SavedKeys is for keys not in DefaultProfileData that we want saved to datastore. ]]--
	for _, key in ipairs(SavedKeys) do
		savedKeysSet[key] = true
	end

	--[[ Local Utilities ]]--
	local function markReceivedReplicaSource(userId: number, tokenName: string): ()
		local userTokenMap = receivedReplicaTokens[userId]
		if not userTokenMap then
			userTokenMap = {}
			receivedReplicaTokens[userId] = userTokenMap
		end

		userTokenMap[tokenName] = true
		for _, expectedTokenName in ipairs(replicaTokenNames) do
			if not userTokenMap[expectedTokenName] then
				return
			end
		end

		Module.ReceivedDataSources[userId] = true
	end

	local function setReplicasForUser(userId: number, replicasByToken: { [string]: Replica }?): ()
		Module.ProfileReplicas[userId] = replicasByToken
		if replicasByToken then
			Module.ProfileReplica[userId] = replicasByToken[replicaTokenNames[1] or "PlayerData"]
		else
			Module.ProfileReplica[userId] = nil
		end
	end

	local function destroyReplicasForUser(userId: number): ()
		local replicasByToken = Module.ProfileReplicas[userId]
		if replicasByToken then
			for _, tokenName in ipairs(replicaTokenNames) do
				local replica = replicasByToken[tokenName]
				if replica then
					pcall(function()
						replica:Destroy()
					end)
				end
			end
		end
		Module.ProfileReplicas[userId] = nil
		Module.ProfileReplica[userId] = nil
	end

	local function subscribeReplicasToPlayer(userId: number, player: Player): boolean
		local replicasByToken = Module.ProfileReplicas[userId]
		if not replicasByToken then
			return false
		end

		for _, tokenName in ipairs(replicaTokenNames) do
			local replica = replicasByToken[tokenName]
			if not replica then
				return false
			end

			local ok = pcall(function()
				replica:Subscribe(player)
			end)
			if not ok then
				return false
			end
		end

		return true
	end

	local function unsubscribeReplicasFromPlayer(userId: number, player: Player): ()
		local replicasByToken = Module.ProfileReplicas[userId]
		if not replicasByToken then
			return
		end

		for _, tokenName in ipairs(replicaTokenNames) do
			local replica = replicasByToken[tokenName]
			if replica then
				pcall(function()
					replica:Unsubscribe(player)
				end)
			end
		end
	end

	local sharedReplica: Replica? = nil

	local function replicateSharedChange(dataObject: DataObject, pathStr: string, value: any, splitParts: { string }?): ()
		if not sharedReplica then
			return
		end
		local rootKey: string = (splitParts and splitParts[1]) or pathStr:match("^[^%.]+") or pathStr
		if not replicatedKeysSet[rootKey] then
			return
		end

		local bucketKey: string = tostring(dataObject.Key)
		if sharedReplica.Data[bucketKey] == nil then
			local okSeed, errSeed = pcall(function()
				sharedReplica:Set({ bucketKey }, {})
			end)
			if not okSeed then
				S.warn("SharedData bucket seed failed for '" .. bucketKey .. "': " .. tostring(errSeed))
				return
			end
		end

		local replicaPath: { any } = { bucketKey }
		for _, segment in ipairs(Helpers.pathToReplicaParts(pathStr, splitParts)) do
			table.insert(replicaPath, segment)
		end

		local ok, err = pcall(function()
			sharedReplica:Set(replicaPath, value)
		end)
		if not ok then
			S.warn("SharedData Set failed at '" .. bucketKey .. "." .. pathStr .. "': " .. tostring(err))
		end
	end

	local function replicateChange(dataObject: DataObject, pathStr: string, value: any, splitParts: { string }?): ()
		local resolvedUserId = Helpers.resolveUserId(dataObject.Key)
		if type(resolvedUserId) ~= "number" then
			replicateSharedChange(dataObject, pathStr, value, splitParts)
			return
		end
		local userId: number = resolvedUserId
		local player: Player? = S.Players:GetPlayerByUserId(userId)
		if not player then
			return
		end
		local replicasByToken = Module.ProfileReplicas[userId]
		if not replicasByToken then
			return
		end

		local replicaPath = Helpers.pathToReplicaParts(pathStr, splitParts)
		for _, tokenName in ipairs(replicaTokenNames) do
			local replica = replicasByToken[tokenName]
			if replica then
				local ok, err = pcall(function()
					replica:Set(replicaPath, value)
				end)
				if not ok then
					S.warn("Replica Set has failed at path " .. pathStr .. " for token " .. tokenName .. ": " .. tostring(err))
				end
			end
		end
	end

	local function createListenerObject(): ListenerObject
		local propertySignals: { [string]: any } = {}
		local propertyConnections: { [string]: { [CallbackFunction]: any } } = {}
		local listenerObj = {} :: ListenerObject

		local function hasListeners(propertyName: string): boolean
			local callbackMap = propertyConnections[propertyName]
			return callbackMap ~= nil and next(callbackMap) ~= nil
		end

		local function getPropertySignal(propertyName: string): any
			local signalObject = propertySignals[propertyName]
			if signalObject then
				return signalObject
			end
			local newSignal = Signal.New()
			propertySignals[propertyName] = newSignal
			return newSignal
		end

		local function clearPropertyIfEmpty(propertyName: string): ()
			local callbackMap = propertyConnections[propertyName]
			if callbackMap and next(callbackMap) == nil then
				propertyConnections[propertyName] = nil
				propertySignals[propertyName] = nil
			end
		end

		local function firePropertySignal(propertyName: string, newValue: any, oldValue: any): ()
			local signalObject = propertySignals[propertyName]
			if signalObject then
				signalObject:Fire(newValue, oldValue)
			end
		end

		function listenerObj:Connect(propertyName: string, callback: CallbackFunction): ListenerObject
			if not propertyConnections[propertyName] then
				propertyConnections[propertyName] = {}
			end

			local callbackMap = propertyConnections[propertyName]
			local existingConnection = callbackMap[callback]
			if existingConnection and type(existingConnection.Disconnect) == "function" then
				local disconnectMethod = existingConnection.Disconnect :: any
				disconnectMethod(existingConnection)
			end

			local signalObject = getPropertySignal(propertyName)
			callbackMap[callback] = signalObject:Connect(function(newValue: any, oldValue: any)
				local ok, err = pcall(function()
					return callback(newValue, oldValue)
				end)
				if not ok then
					error(err, 0)
				end
			end)
			return listenerObj
		end

		function listenerObj:Disconnect(propertyName: string, callback: CallbackFunction): ()
			local callbackMap = propertyConnections[propertyName]
			if not callbackMap then
				return
			end

			local connection = callbackMap[callback]
			if connection and type(connection.Disconnect) == "function" then
				local disconnectMethod = connection.Disconnect :: any
				disconnectMethod(connection)
			end
			callbackMap[callback] = nil
			clearPropertyIfEmpty(propertyName)
		end

		function listenerObj:Invoke(propertyName: string, newValue: any, oldValue: any, dataGetter: ((string) -> any)?): ()
			if hasListeners(propertyName) then
				firePropertySignal(propertyName, newValue, oldValue)
			end

			local pathParts: { string } = string.split(propertyName, ".")
			if #pathParts > 1 then
				for i = #pathParts - 1, 1, -1 do
					local parentProperty: string = table.concat(pathParts, ".", 1, i)
					if hasListeners(parentProperty) then
						local parentValue = newValue
						if dataGetter then
							parentValue = dataGetter(parentProperty)
						end
						firePropertySignal(parentProperty, parentValue, nil)
					end
				end
			end
		end

		return listenerObj
	end

	--[[ Server -> Replica -> Client ]]--
	if S.RunService:IsClient() then
		task.spawn(function()
			for _, tokenName in ipairs(replicaTokenNames) do
				local handlerTokenName = tokenName
				S.Replica.OnNew(handlerTokenName, function(replica: Replica)
					local sourceUserIdRaw = tonumber(replica.Tags.UserId)
					if type(sourceUserIdRaw) ~= "number" then
						return
					end
					local sourceUserId: number = sourceUserIdRaw

					if sourceUserId ~= S.LocalPlayer.UserId then
						local otherDataObj = Module.Data(sourceUserId)
						local otherUnsavedObj = Module.Data("UnsavedData_" .. tostring(sourceUserId))
						for key, value in pairs(replica.Data) do
							local keyStr = tostring(key)
							otherDataObj:Set(keyStr, value)
							if replicatedKeysSet[keyStr] then
								otherUnsavedObj:Set(keyStr, value)
							end
						end
						markReceivedReplicaSource(sourceUserId, handlerTokenName)
						replica:OnChange(
							function(action: string, path: { string }, param1: any, _param2: any)
								local pathStr: string = table.concat(path, ".")
								if action == "SetValues" then
									for setValKey, setValValue in pairs(param1) do
										local rootKey = path[1] or tostring(setValKey)
										local fullPath: string = if pathStr ~= ""
											then pathStr .. "." .. tostring(setValKey)
											else tostring(setValKey)
										otherDataObj:Set(fullPath, setValValue)
										if replicatedKeysSet[rootKey] then
											otherUnsavedObj:Set(fullPath, setValValue)
										end
									end
								else
									otherDataObj:Set(pathStr, param1)
									if replicatedKeysSet[path[1]] then
										otherUnsavedObj:Set(pathStr, param1)
									end
								end
							end
						)
						return
					end

					for key, value in pairs(replica.Data) do
						local keyStr = tostring(key)
						Module.Data(S.LocalPlayer.UserId):Set(keyStr, value)
						if replicatedKeysSet[keyStr] then
							Module.Data("UnsavedData_" .. tostring(S.LocalPlayer.UserId)):Set(keyStr, value)
						end
					end

					markReceivedReplicaSource(sourceUserId, handlerTokenName)
					replica:OnChange(
						function(action: string, path: { string }, param1: any, _param2: any)
							local pathStr: string = table.concat(path, ".")
							if action == "SetValues" then
								for setValKey, setValValue in pairs(param1) do
									local fullPath: string = if pathStr ~= ""
										then pathStr .. "." .. tostring(setValKey)
										else tostring(setValKey)
									local rootKey = path[1] or tostring(setValKey)
									Module.Data(S.LocalPlayer.UserId):Set(fullPath, setValValue)
									if replicatedKeysSet[rootKey] then
										Module.Data("UnsavedData_" .. tostring(S.LocalPlayer.UserId)):Set(fullPath, setValValue)
									end
								end
							else
								Module.Data(S.LocalPlayer.UserId):Set(pathStr, param1)
								if replicatedKeysSet[path[1]] then
									Module.Data("UnsavedData_" .. tostring(S.LocalPlayer.UserId)):Set(pathStr, param1)
								end
							end
						end
					)
				end)
			end
			S.Replica.OnNew("SharedData", function(replica: Replica)
				for bucketKey, bucketData in pairs(replica.Data) do
					if type(bucketKey) == "string" and type(bucketData) == "table" then
						local dataObj = Module.Data(bucketKey)
						for path, value in pairs(bucketData) do
							dataObj:Set(tostring(path), value)
						end
					end
				end

				replica:OnChange(function(action: string, path: { string }, param1: any, _param2: any)
					local bucketKey = path[1]
					if type(bucketKey) ~= "string" then
						return
					end
					local dataObj = Module.Data(bucketKey)
					local subPath: string = table.concat(path, ".", 2)

					if action == "SetValues" and type(param1) == "table" then
						for k, v in pairs(param1) do
							local fullPath: string = if subPath ~= ""
								then subPath .. "." .. tostring(k)
								else tostring(k)
							dataObj:Set(fullPath, v)
						end
						return
					end

					if subPath == "" then
						if type(param1) == "table" then
							for k, v in pairs(param1) do
								dataObj:Set(tostring(k), v)
							end
						end
					else
						dataObj:Set(subPath, param1)
					end
				end)
			end)

			S.Replica.RequestData()
		end)
	end

	--[[ If we change DefaultProfileData table, we want to handle existing player's data migration here. ]]--
	local function PatchData(profile: Profile): ()
		local data = profile.Data
		local currentVersion: number = tonumber(data.DataVersion) or 0
		local targetVersion: number = tonumber(DefaultProfileData.DataVersion) or 0

		if currentVersion >= targetVersion then
			return
		end

		local function deepPatch(source: any, target: any): ()
			for key, value in pairs(source) do
				if target[key] == nil then
					if type(value) == "table" then
						target[key] = Helpers.copyTable(value)
					else
						target[key] = value
					end
				elseif type(value) == "table" and type(target[key]) == "table" then
					deepPatch(value, target[key])
				end
			end
		end

		deepPatch(DefaultProfileData, data)
		data.DataVersion = targetVersion
	end

	--[[ Profile Lifecycle ]]--
	if S.RunService:IsServer() then
		local doSaving = not (S.RunService:IsStudio() and DontSaveInStudio)
		local doLoading = not (S.RunService:IsStudio() and DontLoadInStudio)
		if not doLoading then
			doSaving = false
		end

		local playerStore: ProfileStoreClass =
			S.ProfileStore.New("MainSave", Helpers.copyTable(DefaultProfileData))
		if not doSaving then
			playerStore = playerStore.Mock
		end

		local ReplicaTokensByName: { [string]: any } = {}
		for _, tokenName in ipairs(replicaTokenNames) do
			ReplicaTokensByName[tokenName] = S.Replica.Token(tokenName)
		end

		do
			local SharedDataToken = S.Replica.Token("SharedData")
			local okShared, sharedReplicaOrErr = pcall(function()
				return S.Replica.New({
					Token = SharedDataToken,
					Tags = {},
					Data = {},
				})
			end)
			if okShared and sharedReplicaOrErr then
				sharedReplica = sharedReplicaOrErr
			else
				S.warn("SharedData replica creation failed: " .. tostring(sharedReplicaOrErr))
			end
		end

		local function whenReady(player: Player, fn: () -> ()): ()
			local Replica: any = S.Replica
			if Replica.ReadyPlayers[player] then
				fn()
				return
			end
			local readyConn: RBXScriptConnection
			local leaveConn: RBXScriptConnection
			readyConn = Replica.NewReadyPlayer:Connect(function(readyPlayer: Player)
				if readyPlayer ~= player then
					return
				end
				readyConn:Disconnect()
				leaveConn:Disconnect()
				if player.Parent == S.Players then
					fn()
				end
			end)
			leaveConn = player.AncestryChanged:Connect(function()
				if player.Parent == S.Players then
					return
				end
				readyConn:Disconnect()
				leaveConn:Disconnect()
			end)
		end

		local function startProfileSessionRetry(player: Player): Profile?
			local profile: Profile? = nil
			for attempt = 1, 3 do
				local ok, result = pcall(function()
					return playerStore:StartSessionAsync(tostring(player.UserId), {
						Cancel = function(): boolean
							return player.Parent ~= S.Players
						end,
					})
				end)
				if ok then
					profile = result
					if profile then
						break
					end
				end

				if attempt < 3 and player.Parent == S.Players then
					task.wait(1)
				end
			end
			return profile
		end

		local function createReplicaRetry(player: Player, profileData: DataMap): { [string]: Replica }?
			local replicasByToken: { [string]: Replica } = {}

			for _, tokenName in ipairs(replicaTokenNames) do
				local replicaForToken: Replica? = nil
				local token = ReplicaTokensByName[tokenName]

				for attempt = 1, 3 do
					local ok, replica = pcall(function()
						return S.Replica.New({
							Token = token,
							Tags = { UserId = player.UserId },
							Data = Helpers.copyTable(profileData),
						})
					end)
					if ok and replica then
						replicaForToken = replica
						break
					end

					if attempt < 3 and player.Parent == S.Players then
						task.wait(0.5)
					end
				end

				if not replicaForToken then
					for _, createdTokenName in ipairs(replicaTokenNames) do
						local createdReplica = replicasByToken[createdTokenName]
						if createdReplica then
							pcall(function()
								createdReplica:Destroy()
							end)
						end
					end
					return nil
				end

				replicasByToken[tokenName] = replicaForToken
			end

			return replicasByToken
		end

		local function onPlayerAdded(player: Player): ()
			local playerUserId = player.UserId
			local profile: Profile? = startProfileSessionRetry(player)
			if not profile then
				Module.Profiles[player] = nil
				Profiles[playerUserId] = nil
				destroyReplicasForUser(playerUserId)
				if player.Parent == S.Players then
					player:Kick("Data loading has failed for ProfileStore. Please rejoin.")
				end
				return
			end

			profile:AddUserId(player.UserId)

			local currentDataVersionRaw = tonumber(profile.Data.DataVersion)
			local targetDataVersion: number = tonumber(DefaultProfileData.DataVersion) or 0
			if not doLoading then
				profile.Data = Helpers.copyTable(DefaultProfileData)
			elseif currentDataVersionRaw == nil then
				profile.Data = Helpers.copyTable(DefaultProfileData)
			else
				local currentDataVersion: number = currentDataVersionRaw
				if currentDataVersion < targetDataVersion then
					PatchData(profile)
				end
			end

			local lastSaveRaw = profile.Data.LastSave
			if type(lastSaveRaw) == "number" then
				local lastSave: number = lastSaveRaw
				local timeDiff: number = os.time() - lastSave
				if timeDiff >= 0 then
					local minutes: number = math.floor(timeDiff / 60)
					local seconds: number = timeDiff % 60
					profile.Data.LastPlayTime = string.format("%02d:%02d", minutes, seconds)
				end
			end

			profile.OnSessionEnd:Connect(function()
				Module.Profiles[player] = nil
				player:Kick("ProfileService Profile session ended. Please rejoin.")
			end)

			if player.Parent == S.Players then
				Module.Profiles[player] = profile
				Profiles[player.UserId] = profile
			else
				profile:EndSession()
				return
			end

			if not Module.ProfileReplicas[player.UserId] then
				local replicaData = Helpers.copyTable(profile.Data)
				setReplicasForUser(player.UserId, createReplicaRetry(player, replicaData))
			end

			if not Module.ProfileReplicas[playerUserId] then
				local existingProfile: Profile? = Module.Profiles[player]
				if existingProfile then
					pcall(function()
						existingProfile:EndSession()
					end)
				end
				Module.Profiles[player] = nil
				Profiles[playerUserId] = nil
				destroyReplicasForUser(playerUserId)
				if player.Parent == S.Players then
					player:Kick("ReplicaService startup has failed for your data. Please rejoin.")
				end
				return
			end

			Module.DataWhitelist[playerUserId] = Module.DataWhitelist[playerUserId] or {}
			for _, otherPlayer in ipairs(S.Players:GetPlayers()) do
				local otherUserId = otherPlayer.UserId
				if otherUserId ~= playerUserId then
					Module.DataWhitelist[playerUserId][otherUserId] = true
					Module.DataWhitelist[otherUserId] = Module.DataWhitelist[otherUserId] or {}
					Module.DataWhitelist[otherUserId][playerUserId] = true
				end
			end

			whenReady(player, function()
				if sharedReplica and player.Parent == S.Players then
					pcall(function()
						sharedReplica:Subscribe(player)
					end)
				end
			end)

			whenReady(player, function()
				if not Module.ProfileReplicas[playerUserId] or player.Parent ~= S.Players then
					return
				end
				local ok = subscribeReplicasToPlayer(playerUserId, player)
				if ok then
					return
				end
				local existingProfile: Profile? = Module.Profiles[player]
				if existingProfile then
					pcall(function()
						existingProfile:EndSession()
					end)
				end
				Module.Profiles[player] = nil
				Profiles[playerUserId] = nil
				destroyReplicasForUser(playerUserId)
				if player.Parent == S.Players then
					player:Kick("ReplicaService subscribe has failed for your data. Please rejoin.")
				end
			end)

			local Replica: any = S.Replica
			for viewerUserIdKey, targets in pairs(Module.DataWhitelist) do
				local viewerUserId = tonumber(viewerUserIdKey)
				if viewerUserId ~= nil and targets[playerUserId] then
					local viewerPlayer = S.Players:GetPlayerByUserId(viewerUserId)
					if viewerPlayer and Replica.ReadyPlayers[viewerPlayer] then
						subscribeReplicasToPlayer(playerUserId, viewerPlayer)
					end
				end
			end

			whenReady(player, function()
				local myTargets = Module.DataWhitelist[playerUserId]
				if not myTargets then
					return
				end
				for targetUserIdKey in pairs(myTargets) do
					local targetUserId = tonumber(targetUserIdKey)
					if targetUserId ~= nil then
						local targetReplicas = Module.ProfileReplicas[targetUserId]
						if targetReplicas then
							subscribeReplicasToPlayer(targetUserId, player)
						end
					end
				end
			end)
		end

		for _, player in ipairs(S.Players:GetPlayers()) do
			task.spawn(function()
				onPlayerAdded(player)
			end)
		end

		S.Players.PlayerAdded:Connect(function(player)
			onPlayerAdded(player)
		end)
		S.Players.PlayerRemoving:Connect(function(player: Player)
			local userId = player.UserId

			Module.DataWhitelist[userId] = nil
			for _, targets in pairs(Module.DataWhitelist) do
				targets[userId] = nil
			end

			local profile: Profile? = Module.Profiles[player]
			if profile ~= nil then
				profile:EndSession()
			end
			destroyReplicasForUser(userId)
			receivedReplicaTokens[userId] = nil
			Module.ReceivedDataSources[userId] = nil
			Module.Profiles[player] = nil
			Profiles[userId] = nil
		end)

		function Module.AddToWhitelist(viewerUserId: number, targetUserId: number): ()
			if viewerUserId == targetUserId then
				return
			end
			if not Module.DataWhitelist[viewerUserId] then
				Module.DataWhitelist[viewerUserId] = {}
			end
			if Module.DataWhitelist[viewerUserId][targetUserId] then
				return
			end
			Module.DataWhitelist[viewerUserId][targetUserId] = true
			local targetReplicas = Module.ProfileReplicas[targetUserId]
			local viewerPlayer = S.Players:GetPlayerByUserId(viewerUserId)
			local Replica: any = S.Replica
			if targetReplicas and viewerPlayer and viewerPlayer.Parent and Replica.ReadyPlayers[viewerPlayer] then
				subscribeReplicasToPlayer(targetUserId, viewerPlayer)
			end
		end

		function Module.RemoveFromWhitelist(viewerUserId: number, targetUserId: number): ()
			if not Module.DataWhitelist[viewerUserId] then
				return
			end
			if not Module.DataWhitelist[viewerUserId][targetUserId] then
				return
			end
			Module.DataWhitelist[viewerUserId][targetUserId] = nil
			local targetReplicas = Module.ProfileReplicas[targetUserId]
			local viewerPlayer = S.Players:GetPlayerByUserId(viewerUserId)
			if targetReplicas and viewerPlayer then
				unsubscribeReplicasFromPlayer(targetUserId, viewerPlayer)
			end
			if next(Module.DataWhitelist[viewerUserId]) == nil then
				Module.DataWhitelist[viewerUserId] = nil
			end
		end

		function Module.IsWhitelisted(viewerUserId: number, targetUserId: number): boolean
			if viewerUserId == targetUserId then
				return true
			end
			return Module.DataWhitelist[viewerUserId] ~= nil and Module.DataWhitelist[viewerUserId][targetUserId] == true
		end
	end

	--[[ Data :Get'ers and Set'ers through Remote and Bindable events. ]]--
	S.RemoteFunction("GetPlayerData"):CallBack(function(player: Player, path: string)
		return Module.Data(player.UserId):Get(path)
	end)

	S.RemoteFunction("GetPlayerDataPath"):CallBack(function(_player: Player, path: string)
		return Module.Data(path):Get()
	end)

	S.BindableFunction("GetPlayerData"):CallBack(function(player: Player, path: string)
		return Module.Data(player.UserId):Get(path)
	end)

	S.BindableEvent("SetPlayerData"):CallBack(function(player: Player, path: string, newValue: any)
		Module.Data(player.UserId):Set(path, newValue)
	end)

	S.BindableFunction("IncrementPlayerData"):CallBack(function(player: Player, path: string, valueChange: any)
		Module.Data(player.UserId):Set(path, valueChange, true)
	end)

	S.RemoteFunction("RequestDataWhitelist"):CallBack(function(player: Player, targetUserId: number): boolean
		if type(targetUserId) ~= "number" or targetUserId == player.UserId then
			return false
		end
		local targetPlayer = S.Players:GetPlayerByUserId(targetUserId)
		if not targetPlayer then
			return false
		end
		Module.AddToWhitelist(player.UserId, targetUserId)
		return true
	end)

	S.RemoteFunction("RemoveDataWhitelist"):CallBack(function(player: Player, targetUserId: number): boolean
		if type(targetUserId) ~= "number" or targetUserId == player.UserId then
			return false
		end
		Module.RemoveFromWhitelist(player.UserId, targetUserId)
		return true
	end)

	--[[ The Data Object with Methods ]]--
	function Module.Data(key: string | number): DataObject
		if Module.DataObjects[key] then
			return Module.DataObjects[key]
		end

		local playerData: DataMap = Module.DataStore[key]
		if not playerData then
			playerData = {}
			Module.DataStore[key] = playerData

			if S.RunService:IsServer() then
				local player: Player? = S.Players:GetPlayerByUserId(tonumber(key) or 0)
				if player and Module.Profiles[player] then
					local profile: Profile? = Module.Profiles[player]
					if profile and profile.Data then
						for k, v in pairs(profile.Data) do
							playerData[k] = v
						end
					end
				end
			end
		end

		local dataObject = {Key = key,Changed = createListenerObject(),} :: DataObject

		function dataObject:Set(path: string, newValue: any, increment: boolean?, forceReplicate: boolean?)
			if not path then
				return
			end

			if increment then
				self:Get(path)
			end

			local player: Player? = S.Players:GetPlayerByUserId(tonumber(self.Key) or 0)
			if path:find("%.") then
				local keyParts: { string } = string.split(path, ".")
				local navResult = Helpers.navigateForSet(playerData, keyParts)
				local targetTable = navResult.tableRef
				local lastKey = navResult.lastKey
				local currentValue: any = targetTable[lastKey]
				local oldValue: any = Helpers.copyTable(currentValue)
				local finalValue: any
				if increment and type(targetTable[lastKey]) == "number" then
					finalValue = targetTable[lastKey] + newValue
				else
					finalValue = newValue
				end

				local isSameTableReference = type(currentValue) == "table" and type(finalValue) == "table" and rawequal(currentValue, finalValue)
				if not forceReplicate and not isSameTableReference and Helpers.deepEqual(oldValue, finalValue) then
					return
				end

				targetTable[lastKey] = finalValue

				if S.RunService:IsServer() and player and Module.Profiles[player] then
					if Helpers.hasInvalidUtf8(finalValue) then
						S.silenterror("Skipping profile save for path '" .. path .. "' due to invalid UTF-8 value")
					else
						local profile = Module.Profiles[player]
						local profileNavResult = Helpers.navigateForSet(profile.Data, keyParts)
						profileNavResult.tableRef[profileNavResult.lastKey] = finalValue
					end
				end

				if S.RunService:IsServer() then
					replicateChange(self, path, finalValue, keyParts)
				end
				self.Changed:Invoke(path, finalValue, oldValue, function(p: string): any
					return self:Get(p)
				end)
			else
				local currentValue: any = playerData[path]
				local oldValue: any = Helpers.copyTable(currentValue)
				local finalValue: any
				if increment and type(playerData[path]) == "number" then
					finalValue = playerData[path] + newValue
				else
					finalValue = newValue
				end

				local isSameTableReference = type(currentValue) == "table" and type(finalValue) == "table" and rawequal(currentValue, finalValue)
				if not forceReplicate and not isSameTableReference and Helpers.deepEqual(oldValue, finalValue) then
					return
				end

				playerData[path] = finalValue
				self.Changed:Invoke(path, finalValue, oldValue, function(p: string): any
					return self:Get(p)
				end)
				if S.RunService:IsServer() then
					if player and Module.Profiles[player] then
						local isReplicatedOnly = replicatedKeysSet[path] and not savedKeysSet[path]
						if not isReplicatedOnly then
							local profile = Module.Profiles[player]
							if profile.Data[path] ~= nil or DefaultProfileData[path] ~= nil or savedKeysSet[path] then
								if Helpers.hasInvalidUtf8(playerData[path]) then
									S.silenterror("Skipping profile save for path '" .. path .. "' due to invalid UTF-8 value")
								else
									profile.Data[path] = playerData[path]
								end
							end
						end
					end
					replicateChange(self, path, playerData[path])
				end
			end
		end

		function dataObject:Get(path: string?): any
			if not path then
				if S.RunService:IsServer() then
					local player: Player? = S.Players:GetPlayerByUserId(tonumber(self.Key) or 0)
					if player and Module.Profiles[player] then
						local profile: Profile? = Module.Profiles[player]
						if profile and profile.Data then
							for k, v in pairs(profile.Data) do
								if playerData[k] == nil then
									playerData[k] = v
								end
							end
						end
					end
				end
				return playerData
			end
			if path:find("%.") then
				local keyParts: { string } = string.split(path, ".")
				local navResult = Helpers.navigateForGet(playerData, keyParts)
				if
					navResult
					and navResult.tableRef
					and navResult.tableRef[navResult.lastKey] ~= nil
				then
					return navResult.tableRef[navResult.lastKey]
				end
				if S.RunService:IsServer() then
					local player: Player? = S.Players:GetPlayerByUserId(tonumber(self.Key) or 0)
					if player and Module.Profiles[player] then
						local profile: Profile? = Module.Profiles[player]
						if profile and profile.Data then
							local profileNavResult = Helpers.navigateForGet(profile.Data, keyParts)
							if
								profileNavResult
								and profileNavResult.tableRef
								and profileNavResult.tableRef[profileNavResult.lastKey] ~= nil
							then
								local value: any =
									profileNavResult.tableRef[profileNavResult.lastKey]
								local navSetResult = Helpers.navigateForSet(playerData, keyParts)
								navSetResult.tableRef[navSetResult.lastKey] = value
								return value
							end
						end
					end
				end
				return nil
			else
				local value: any = playerData[path]
				if value ~= nil then
					return value
				end
				if S.RunService:IsServer() then
					local player: Player? = S.Players:GetPlayerByUserId(tonumber(self.Key) or 0)
					if player and Module.Profiles[player] then
						local profile: Profile? = Module.Profiles[player]
						if profile and profile.Data and profile.Data[path] ~= nil then
							value = profile.Data[path]
							playerData[path] = value
							return value
						end
					end
				end
				return nil
			end
		end

		function dataObject:Increment(path: string, value: number): ()
			self:Set(path, (type(value) == "number" and value) or 1, true)
		end

		function dataObject:Decrement(path: string, value: number): ()
			self:Set(path, -((type(value) == "number" and value) or 1), true)
		end

		Module.DataObjects[key] = dataObject
		return dataObject
	end

	function Module:IsReady(key: string | number): boolean
		if S.RunService:IsServer() then
			return true
		end

		local resolvedUserId = Helpers.resolveUserId(key)
		if type(resolvedUserId) ~= "number" then
			return false
		end
		local userId: number = resolvedUserId

		return Module.ReceivedDataSources[userId] == true
	end

	function Module:WaitFor(key: string | number, timeoutSeconds: number?): boolean
		if S.RunService:IsServer() then
			return true
		end

		local resolvedUserId = Helpers.resolveUserId(key)
		if type(resolvedUserId) ~= "number" then
			return false
		end
		local userId: number = resolvedUserId

		if Module.ReceivedDataSources[userId] then
			return true
		end

		local timeout = timeoutSeconds or 20
		local startedAt = os.clock()
		while not Module.ReceivedDataSources[userId] and os.clock() - startedAt < timeout do
			task.wait()
		end

		return Module.ReceivedDataSources[userId] == true
	end

	function Module:WaitForLocal(timeoutSeconds: number?): boolean
		if S.RunService:IsServer() then
			return false
		end

		return self:WaitFor(S.LocalPlayer.UserId, timeoutSeconds)
	end

	--[[ Shortcuts.DataHandler() Shortcut ]]--
	setmetatable(Module, {
		__call = function(_, key: string | number): DataObject
			return Module.Data(key)
		end,
	})

	return Module
end
