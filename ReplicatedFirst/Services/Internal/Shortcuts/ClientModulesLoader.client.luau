--!strict
--!optimize 2

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")

if _G.__ShortcutsClientEventDispatcherBooted then
	return
end
_G.__ShortcutsClientEventDispatcherBooted = true

--[[ Maid ]]--
type MaidToken = {
	Destroy: (self: MaidToken) -> (),
	Cleanup: (self: MaidToken, ...any) -> (),
}

type Destroyable = {
	Destroy: (self: Destroyable) -> (),
}

type Disconnectable = {
	Disconnect: (self: Disconnectable) -> (),
}

type CleanupTarget = ((...any) -> ()) | RBXScriptConnection | Instance | Destroyable | Disconnectable

type MaidObject = {
	Add: (self: MaidObject, object: CleanupTarget) -> MaidToken,
	Cleanup: (self: MaidObject, ...any) -> (),
	CharacterMaid: MaidObject?,
}

type MaidModule = {
	New: (key: any?) -> MaidObject,
}

local Maid = require(ReplicatedFirst:FindFirstChild("Maid", true))
local Helpers = require(script.Parent.Helpers)

--[[ Typing ]]--
type ModuleMethod = (...any) -> ...any

type ModuleTable = {
	Init: ModuleMethod?,
	Initialize: ModuleMethod?,
	Cleanup: ModuleMethod?,
	GetPriority: ((self: ModuleTable) -> number)?,
}

type ModuleEntry = ModuleMethod | ModuleTable

type ModuleRecord = {
	Name: string,
	Priority: number,
	Module: ModuleEntry,
}

local function newMaid()
	return Maid.New()
end

--[[ Caching ]]--
local function getPriority(requiredModule: ModuleEntry, moduleScript: ModuleScript): number
	if type(requiredModule) ~= "table" then
		return 1
	end

	local getPriorityMethod = requiredModule.GetPriority
	if type(getPriorityMethod) ~= "function" then
		return 1
	end

	local priorityOk, priorityOrError = pcall(function()
		return getPriorityMethod(requiredModule)
	end)
	if priorityOk then
		local resolvedPriority = priorityOrError
		if type(resolvedPriority) == "number" then
			local priority: number = resolvedPriority
			return priority
		end
	end

	if not priorityOk then
		warn("GetPriority failed for " .. moduleScript:GetFullName() .. ": " .. tostring(priorityOrError))
	end

	return 1
end

local function cacheModules(sourceFolder: Instance?, label: string, warnOnMissing: boolean?, allowSideEffectOnly: boolean?): { ModuleRecord }
	if sourceFolder == nil then
		if warnOnMissing ~= false then
			warn("Missing " .. label .. " folder")
		end
		return {}
	end
	local targetFolder: Instance = sourceFolder

	local cache: { ModuleRecord } = {}
	for _, dependency in ipairs(targetFolder:GetChildren()) do
		if dependency:IsA("ModuleScript") then
			local ok, requiredModuleOrError = pcall(function()
				return (require :: any)(dependency)
			end)
			if ok then
				if type(requiredModuleOrError) == "table" or type(requiredModuleOrError) == "function" then
					local requiredModule = requiredModuleOrError :: ModuleEntry
					local priority = getPriority(requiredModule, dependency)
					if priority >= 0 then
						table.insert(cache, { Module = requiredModule, Priority = priority, Name = dependency.Name })
					end
				elseif allowSideEffectOnly ~= true then
					warn("Module " .. dependency:GetFullName() .. " returned not supported type '" .. typeof(requiredModuleOrError) .. "'")
				end
			else
				warn("Failed to require " .. dependency:GetFullName() .. " while caching modules: " .. tostring(requiredModuleOrError))
			end
		end
	end

	table.sort(cache, function(a: ModuleRecord, b: ModuleRecord): boolean
		return a.Priority > b.Priority
	end)

	return cache
end

local function runCachedModules(cache: { ModuleRecord }, maid, ...: any): ()
	local packedArgs = table.pack(...)
	for _, moduleData in ipairs(cache) do
		local moduleValue = moduleData.Module
		local methodLabel: string? = nil
		local method: ModuleMethod? = nil

		if type(moduleValue) == "function" then
			methodLabel = "Call"
			method = moduleValue
		elseif type(moduleValue) == "table" then
			if type(moduleValue.Init) == "function" then
				methodLabel = "Init"
				method = moduleValue.Init
			elseif type(moduleValue.Initialize) == "function" then
				methodLabel = "Initialize"
				method = moduleValue.Initialize
			end
		end

		if method ~= nil and methodLabel ~= nil then
			local resolvedMethod: ModuleMethod = method
			local resolvedMethodLabel: string = methodLabel
			task.spawn(function()
				local ok, resultOrErr = xpcall(function()
					return (resolvedMethod :: any)(table.unpack(packedArgs, 1, packedArgs.n))
				end, function(err: any): string
					return debug.traceback(tostring(err), 2)
				end)

				if not ok then
					task.spawn(function()
						error("Error in " .. moduleData.Name .. "." .. resolvedMethodLabel .. ":\n" .. tostring(resultOrErr))
					end)
					return
				end

				Helpers.registerCleanupTask(maid, moduleData.Name, resultOrErr, "ClientLoader")
			end)
		end

		if type(moduleValue) == "table" and type(moduleValue.Cleanup) == "function" then
			local cleanupMethod = moduleValue.Cleanup
			maid:Add(function()
				local ok = xpcall(function()
					(cleanupMethod :: any)(table.unpack(packedArgs, 1, packedArgs.n))
				end, function(innerErr: any): string
					return debug.traceback(tostring(innerErr), 2)
				end)

				if not ok then
					warn("Error in " .. moduleData.Name)
				end
			end)
		end
	end
end

--[[ Main, Player and Character folders. ]]--
local mainFolder = ReplicatedFirst:FindFirstChild("Main")
local playerAddedFolder = ReplicatedFirst:FindFirstChild("PlayerAdded")
local characterAddedFolder = ReplicatedFirst:FindFirstChild("CharacterAdded")

local mainModulesCache = cacheModules(mainFolder, "ReplicatedFirst/Main", false, true)
local playerModulesCache = cacheModules(playerAddedFolder, "ReplicatedFirst/PlayerAdded", true, false)
local characterModulesCache = cacheModules(characterAddedFolder, "ReplicatedFirst/CharacterAdded", true, false)
local mainMaid = newMaid()
runCachedModules(mainModulesCache, mainMaid)

--[[ Events ]]--
local playerMaids: { [Player]: MaidObject } = {}

local function attachCharacterHandler(player: Player, playerMaid: MaidObject): ()
	local function handleCharacter(character: Model): ()
		if playerMaid.CharacterMaid then
			playerMaid.CharacterMaid:Cleanup()
			playerMaid.CharacterMaid = nil
		end

		local characterMaid: any = newMaid()
		runCachedModules(characterModulesCache, characterMaid, player, character)

		characterMaid:Add(
			character.AncestryChanged:Connect(function(_child: Instance, parent: Instance?)
				if not parent then
					characterMaid:Cleanup()
				end
			end)
		)

		playerMaid.CharacterMaid = characterMaid
	end

	playerMaid:Add(player.CharacterAdded:Connect(function(character)
		handleCharacter(character)
	end))
	if player.Character then
		handleCharacter(player.Character)
	end
end

local function setupPlayer(player: Player): ()
	if playerMaids[player] then
		playerMaids[player]:Cleanup()
	end

	local playerMaid: any = newMaid()
	playerMaids[player] = playerMaid

	runCachedModules(playerModulesCache, playerMaid, player)

	attachCharacterHandler(player, playerMaid)

	playerMaid:Add(player.AncestryChanged:Connect(function(_child: Instance, parent: Instance?)
		if parent then
			return
		end

		if playerMaid.CharacterMaid then
			playerMaid.CharacterMaid:Cleanup()
			playerMaid.CharacterMaid = nil
		end

		playerMaid:Cleanup()
		playerMaids[player] = nil
	end))
end

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		setupPlayer(player)
	end)
end

Players.PlayerAdded:Connect(function(player)
	setupPlayer(player)
end)
Players.PlayerRemoving:Connect(function(player: Player)
	local playerMaid = playerMaids[player]
	if not playerMaid then
		return
	end

	if playerMaid.CharacterMaid then
		playerMaid.CharacterMaid:Cleanup()
		playerMaid.CharacterMaid = nil
	end

	playerMaid:Cleanup()
	playerMaids[player] = nil
end)
