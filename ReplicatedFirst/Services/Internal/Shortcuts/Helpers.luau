--!strict
--!optimize 2
--!native

--[[ Services ]]--
local Players = game:GetService("Players")

--[[ Constants ]]--
local RNG = Random.new()

--[[ Typing ]]--
export type SeverityMap = { [string]: number }

export type RateLimitedObject = {
	_Name: string,
	_Rate: number,
	_RateLimitStart: boolean,
	_RateLimitReach: boolean,
	RateLimit: number,
	RateLimitTime: number,
	[string]: any,
}

export type ObjectInfo = {
	RateLimit: number?,
	RateLimitTime: number?,
	TimeOut: number?,
	[string]: any,
}

export type DataMap = { [string]: any }

export type NavigationResult = {
	tableRef: { [any]: any },
	lastKey: any,
}

--[[ Helpers ]]--
local Helpers = {}
local RuntimeRequire: (ModuleScript) -> any = require

local function ErrorRequire(originalKey: string, moduleScript: ModuleScript?, requireError: any): string
	local path = if moduleScript then moduleScript:GetFullName() else "unknown"
	local tb = debug.traceback(nil, 3)
	return "Failed to require '" .. originalKey .. "' (path: " .. path .. ")\n  Error: " .. tostring(requireError) .. "\n  Traceback:\n" .. tb
end

function Helpers.copyTable(original: any): any
	if type(original) ~= "table" then
		return original
	end
	local copy: { [any]: any } = {}
	for key, value in pairs(original) do
		if type(value) == "table" then
			copy[key] = Helpers.copyTable(value)
		else
			copy[key] = value
		end
	end
	return copy
end

function Helpers.deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end

	if type(a) ~= type(b) then
		return false
	end

	if type(a) ~= "table" then
		return false
	end

	for key, value in pairs(a) do
		if not Helpers.deepEqual(value, b[key]) then
			return false
		end
	end

	for key in pairs(b) do
		if a[key] == nil then
			return false
		end
	end

	return true
end

function Helpers.hasInvalidUtf8(value: any, visited: { [any]: boolean }?): boolean
	local valueType = type(value)
	if valueType == "string" then
		return utf8.len(value) == nil
	end
	if valueType ~= "table" then
		return false
	end

	local visitedTable: { [any]: boolean } = visited or {}
	if visitedTable[value] then
		return false
	end
	visitedTable[value] = true

	for key, nestedValue in pairs(value) do
		if type(key) == "string" and utf8.len(key) == nil then
			return true
		end
		if Helpers.hasInvalidUtf8(nestedValue, visitedTable) then
			return true
		end
	end

	return false
end

function Helpers.navigateForSet(rootTable: DataMap, keyPath: { string }): NavigationResult
	local currentTable: { [any]: any } = rootTable
	for i = 1, #keyPath - 1 do
		local rawKey: string = keyPath[i]
		local key: any = tonumber(rawKey) or rawKey

		if currentTable[key] == nil or type(currentTable[key]) ~= "table" then
			currentTable[key] = {}
		end
		currentTable = currentTable[key]
	end
	local rawLastKey: string = keyPath[#keyPath]
	local lastKey: any = tonumber(rawLastKey) or rawLastKey
	return { tableRef = currentTable, lastKey = lastKey }
end

function Helpers.navigateForGet(rootTable: DataMap, keyPath: { string }): NavigationResult?
	local currentTable: any = rootTable
	for i = 1, #keyPath - 1 do
		local rawKey: string = keyPath[i]
		local key: any = tonumber(rawKey) or rawKey

		if type(currentTable) ~= "table" then
			return nil
		end
		currentTable = currentTable[key]
		if currentTable == nil then
			return nil
		end
	end
	if type(currentTable) ~= "table" then
		return nil
	end
	local rawLastKey: string = keyPath[#keyPath]
	local lastKey: any = tonumber(rawLastKey) or rawLastKey
	return { tableRef = currentTable, lastKey = lastKey }
end

function Helpers.pathToReplicaParts(pathStr: string, splitParts: { string }?): { any }
	local raw: { string } = splitParts or string.split(pathStr, ".")
	local parts: { any } = {}
	for i, part in ipairs(raw) do
		parts[i] = tonumber(part) or part
	end
	return parts
end

function Helpers.resolveUserId(key: string | number): number?
	return tonumber(key) or tonumber(string.split(tostring(key), "_")[2])
end

function Helpers.normalizeReplicaTokenNames(config: any): { string }
	local tokenNames: { string } = {}
	local tokenLookup: { [string]: boolean } = {}

	local function addTokenName(value: any): ()
		if type(value) ~= "string" or value == "" or tokenLookup[value] then
			return
		end
		tokenLookup[value] = true
		table.insert(tokenNames, value)
	end

	if type(config) == "table" then
		for _, tokenName in ipairs(config) do
			addTokenName(tokenName)
		end

		if #tokenNames == 0 then
			for _, tokenName in pairs(config) do
				addTokenName(tokenName)
			end
		end
	end

	if #tokenNames == 0 then
		table.insert(tokenNames, "PlayerData")
	end

	return tokenNames
end

function Helpers.silentTypeError(message: string): ()
	task.spawn(function()
		error(message)
	end)
end

function Helpers.generateNumbers(): number
	return RNG:NextInteger(0, 65535)
end

function Helpers.normalizeSeverity(severity: any, severityMap: SeverityMap): number?
	if typeof(severity) == "string" then
		return severityMap[string.lower(severity)]
	elseif typeof(severity) == "number" then
		return severity
	elseif severity ~= nil then
		Helpers.silentTypeError("not a string type or not a number type")
	end
	return nil
end

function Helpers.contains(list: { any }, target: any): boolean
	for _, val in ipairs(list) do
		if val == target then
			return true
		end
	end
	return false
end

function Helpers.findFirstExistingChild(childName: string, ...: Instance?): Instance?
	local parents = table.pack(...)
	for i = 1, parents.n do
		local parent: Instance? = parents[i]
		if parent ~= nil then
			local parentInstance: Instance = parent
			local child = parentInstance:FindFirstChild(childName)
			if child ~= nil then
				return child
			end
		end
	end
	return nil
end

function Helpers.requireModule(moduleScript: ModuleScript?, originalKey: string, errorLevel: number?): any
	if moduleScript == nil then
		Helpers.silentTypeError("no module script")
		return nil
	end

	local success, loadedModule = pcall(function()
		return RuntimeRequire(moduleScript)
	end)
	if success then
		return loadedModule
	end

	error(ErrorRequire(originalKey, moduleScript, loadedModule), errorLevel or 2)
end

function Helpers.createObject(Name: string, Info: ObjectInfo): RateLimitedObject
	return {
		_Name = Name,
		_Rate = 0,
		_RateLimitStart = false,
		_RateLimitReach = false,
		RateLimit = Info.RateLimit or 60,
		RateLimitTime = Info.RateLimitTime or 1,
	}
end

function Helpers.setFields(self: { [string]: any }, SetInfo: { [string]: any }): ()
	for k, v in pairs(SetInfo) do
		self[k] = v
	end
end

local function normalizeCleanupTask(cleanupTask: any): any
	if type(cleanupTask) ~= "table" then
		return cleanupTask
	end

	local hasDestroy = type(cleanupTask.Destroy) == "function"
	local hasDisconnect = type(cleanupTask.Disconnect) == "function"
	if hasDestroy or hasDisconnect then
		return cleanupTask
	end

	if type(cleanupTask.Cleanup) ~= "function" then
		return cleanupTask
	end

	local cleanupMethod = cleanupTask.Cleanup :: any
	return function(...: any)
		cleanupMethod(cleanupTask, ...)
	end
end

function Helpers.registerCleanupTask(maid: { Add: (self: any, object: any) -> any }, moduleName: string, cleanupTask: any, warningPrefix: string): ()
	if cleanupTask == nil then
		return
	end

	local normalizedCleanupTask = normalizeCleanupTask(cleanupTask)
	local success, addError = pcall(function()
		maid:Add(normalizedCleanupTask)
	end)
	if success then
		return
	end

	warn("[" .. warningPrefix .. "] Unsupported cleanup task type from " .. moduleName .. ": " .. typeof(cleanupTask) .. " (" .. tostring(addError) .. ")")
end

function Helpers.yieldTilObject(Name: string, List: { [string]: any }): boolean
	if List[Name] then
		return true
	end

	local Timeout = false
	local tb = debug.traceback(nil, 2)
	task.delay(5, function()
		if List[Name] then
			return
		end
		Timeout = true
		warn("YieldTilObject timed out after 5s waiting for '" .. Name .. "'\n  Called from:\n" .. tb)
	end)

	while not Timeout do
		if not List[Name] then
			task.wait()
		else
			return true
		end
	end

	return false
end

function Helpers.getNearPlayer(chr: Model, Radius: number): { Player }
	local ListOfPlayersInRange: { Player } = {}
	local PlayerList = Players:GetPlayers()
	local hrp = chr.PrimaryPart

	for _, plr in ipairs(PlayerList) do
		local Chr = plr.Character or plr.CharacterAdded:Wait()
		local Hrp = Chr.PrimaryPart

		if chr and Chr and hrp and Hrp then
			if (Hrp.Position - hrp.Position).Magnitude <= Radius and Chr then
				table.insert(ListOfPlayersInRange, plr)
			end
		end
	end

	return ListOfPlayersInRange
end

function Helpers.createInstance(InstanceName: string, Parent: Instance?, Information: { [string]: any }?): Instance
	local NewInstance = Instance.new(InstanceName)
	local instanceFields: any = NewInstance
	if Information then
		for Property, Value in next, Information do
			instanceFields[Property] = Value
		end
	end
	NewInstance.Parent = Parent
	return NewInstance
end

function Helpers.createRemoteEvent(Name: string, Parent: Instance?): Instance
	return Helpers.createInstance("RemoteEvent", Parent, { Name = Name })
end

function Helpers.createUnreliableRemoteEvent(Name: string, Parent: Instance?): Instance
	return Helpers.createInstance("UnreliableRemoteEvent", Parent, { Name = Name })
end

function Helpers.createRemoteFunction(Name: string, RemotesFolder: Instance?): Instance
	local Folder = Helpers.createInstance("Folder", RemotesFolder, { Name = Name })
	Helpers.createRemoteEvent("Sent", Folder)
	Helpers.createRemoteEvent("Receive", Folder)
	return Folder
end

function Helpers.createUnreliableRemoteFunction(Name: string, RemotesFolder: Instance?): Instance
	local Folder = Helpers.createInstance("Folder", RemotesFolder, { Name = Name })
	Helpers.createUnreliableRemoteEvent("Sent", Folder)
	Helpers.createUnreliableRemoteEvent("Receive", Folder)
	return Folder
end

function Helpers.protectedCallback(name: string, cb: any, ...: any): (boolean, ...any)
	if type(cb) ~= "function" then
		return false
	end
	local args = table.pack(...)
	local results = table.pack(xpcall(function()
		return (cb :: any)(table.unpack(args, 1, args.n))
	end, function(err: any): any
		local tb = debug.traceback(tostring(err), 2)
		task.spawn(function()
			error("Error in callback for '" .. name .. "':\n" .. tb)
		end)
		return err
	end))
	local ok = results[1]
	if ok then
		return true, table.unpack(results, 2, results.n)
	end
	return false
end

function Helpers.removeFromList(list: { any }, target: any): ()
	for i = #list, 1, -1 do
		if list[i] == target then
			table.remove(list, i)
		end
	end
end

return Helpers
