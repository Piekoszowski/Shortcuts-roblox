--!strict
--!optimize 2

--[[ Services ]]--
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ Dependencies ]]--
type CustomPathFolders = { Instance? }
type CustomPathsMap = { [string]: CustomPathFolders }

local CustomPaths: CustomPathsMap = require(script.Parent.CustomPaths) :: CustomPathsMap
local Helpers = require(script.Parent.Helpers)

--[[ Service Mapping ]]--
local function MapServices(serviceList: { [any]: any }): { [string]: Instance }
	local services: { [string]: Instance } = {}

	for key, value in pairs(serviceList) do
		if type(key) == "string" and typeof(value) == "Instance" then
			local keyStr: string = key
			services[keyStr:lower()] = value
		elseif type(value) == "string" then
			local Service: string = value
			local success, service = pcall(function()
				return game:GetService(Service)
			end)
			if success and service then
				services[Service:lower()] = service
			end
		else
			Helpers.silentTypeError("not a string type or not an Instance type")
		end
	end

	return services
end

--[[ EasyRequire ]]--
return function(ShortcutsMain: Instance, ServicesList: { string })
	local Module: { [string]: any } = {}
	local Services = MapServices(ServicesList)

	--[[ Module Caches ]]--
	local Modules: { [string]: ModuleScript } = {}
	local LoadedModulesCache: { [string]: any } = {}
	local ServiceExternalModules: { [string]: ModuleScript } = {}
	local ServiceInternalModules: { [string]: ModuleScript } = {}
	local ServiceModules: { [string]: ModuleScript } = {}
	local CustomPathViews: { [string]: { [string]: any } } = {}
	local CustomPathKeysByLower: { [string]: string } = {}

	--[[ Module Lookup ]]--
	local warnedCollisions: { [string]: boolean } = {}

	local function warnCollision(bucketLabel: string, name: string, keepingFullName: string, droppingFullName: string): ()
		local collisionId = bucketLabel .. "|" .. name:lower() .. "|" .. keepingFullName .. "|" .. droppingFullName
		if warnedCollisions[collisionId] then
			return
		end
		warnedCollisions[collisionId] = true
		warn(
			"[Shortcuts] name collision in "
				.. bucketLabel
				.. ": '"
				.. name
				.. "' exists at "
				.. keepingFullName
				.. " AND "
				.. droppingFullName
				.. " — keeping "
				.. keepingFullName
				.. ", ignoring the other. Rename one to fix."
		)
	end

	local function insertWithCollisionCheck(bucket: { [string]: ModuleScript }, descendant: ModuleScript, bucketLabel: string): ()
		local loweredName = descendant.Name:lower()
		local existing = bucket[loweredName]
		if existing ~= nil and existing ~= descendant then
			warnCollision(bucketLabel, descendant.Name, existing:GetFullName(), descendant:GetFullName())
			return
		end
		bucket[loweredName] = descendant
	end

	local function populateModules(): { [string]: ModuleScript }
		local modules: { [string]: ModuleScript } = {}
		table.clear(ServiceExternalModules)
		table.clear(ServiceInternalModules)
		table.clear(ServiceModules)

		local servicesFolder = ReplicatedFirst:FindFirstChild("Services")
		local externalFolder: Instance? = nil
		local internalFolder: Instance? = nil

		if servicesFolder then
			externalFolder = servicesFolder:FindFirstChild("External")
			internalFolder = servicesFolder:FindFirstChild("Internal")

			if externalFolder then
				for _, descendant in ipairs(externalFolder:GetDescendants()) do
					if descendant:IsA("ModuleScript") then
						insertWithCollisionCheck(ServiceExternalModules, descendant, "Services/External")
					end
				end
			end

			if internalFolder then
				for _, descendant in ipairs(internalFolder:GetDescendants()) do
					if descendant:IsA("ModuleScript") then
						insertWithCollisionCheck(ServiceInternalModules, descendant, "Services/Internal")
					end
				end
			end

			for _, descendant in ipairs(servicesFolder:GetDescendants()) do
				if descendant:IsA("ModuleScript") then
					if externalFolder and descendant:IsDescendantOf(externalFolder) then
						continue
					end
					if internalFolder and descendant:IsDescendantOf(internalFolder) then
						continue
					end
					insertWithCollisionCheck(ServiceModules, descendant, "Services")
				end
			end
		end

		for _, descendant in ipairs(ReplicatedFirst:GetDescendants()) do
			if descendant:IsA("ModuleScript") then
				if servicesFolder and descendant:IsDescendantOf(servicesFolder) then
					continue
				end
				insertWithCollisionCheck(modules, descendant, "ReplicatedFirst/ServerScriptService/Players")
			end
		end

		for _, descendant in ipairs(ServerScriptService:GetDescendants()) do
			if descendant:IsA("ModuleScript") then
				insertWithCollisionCheck(modules, descendant, "ReplicatedFirst/ServerScriptService/Players")
			end
		end

		for _, descendant in ipairs(Players:GetDescendants()) do
			if descendant:IsA("ModuleScript") then
				insertWithCollisionCheck(modules, descendant, "ReplicatedFirst/ServerScriptService/Players")
			end
		end

		--[[ Cross-tier shadowing: same name as a Roblox service, a CustomPath alias, or a higher-priority bucket. ]]--
		local crossTierBuckets: { { name: string, bucket: { [string]: any } } } = {
			{ name = "Services/External", bucket = ServiceExternalModules },
			{ name = "Services/Internal", bucket = ServiceInternalModules },
			{ name = "Services", bucket = ServiceModules },
			{ name = "ReplicatedFirst/ServerScriptService/Players", bucket = modules },
		}

		for _, entry in ipairs(crossTierBuckets) do
			for loweredName, descendant in pairs(entry.bucket) do
				local shadowed = Services[loweredName]
				if shadowed ~= nil then
					warnCollision(
						"S.<name> resolution",
						descendant.Name,
						"Roblox service " .. shadowed:GetFullName(),
						descendant:GetFullName() .. " (from " .. entry.name .. ")"
					)
				end
				if CustomPathKeysByLower[loweredName] ~= nil then
					warnCollision(
						"S.<name> resolution",
						descendant.Name,
						"CustomPaths alias '" .. CustomPathKeysByLower[loweredName] .. "'",
						descendant:GetFullName() .. " (from " .. entry.name .. ")"
					)
				end
				if loweredName == "localplayer" or loweredName == "tag" then
					warnCollision(
						"S.<name> resolution",
						descendant.Name,
						"built-in S." .. (loweredName == "localplayer" and "LocalPlayer" or "Tag"),
						descendant:GetFullName() .. " (from " .. entry.name .. ")"
					)
				end
			end
		end

		--[[ Higher-priority bucket already owns this name → lower-priority shadow gets warned about. ]]--
		local prioritizedBuckets: { { name: string, bucket: { [string]: ModuleScript } } } = {
			{ name = "Services/External", bucket = ServiceExternalModules },
			{ name = "Services/Internal", bucket = ServiceInternalModules },
			{ name = "Services", bucket = ServiceModules },
			{ name = "ReplicatedFirst/ServerScriptService/Players", bucket = modules },
		}
		for higherIndex = 1, #prioritizedBuckets do
			local higher = prioritizedBuckets[higherIndex]
			for loweredName, higherModule in pairs(higher.bucket) do
				for lowerIndex = higherIndex + 1, #prioritizedBuckets do
					local lower = prioritizedBuckets[lowerIndex]
					local lowerModule = lower.bucket[loweredName]
					if lowerModule ~= nil and lowerModule ~= higherModule then
						warnCollision(
							"S.<name> resolution",
							higherModule.Name,
							higherModule:GetFullName() .. " (from " .. higher.name .. ")",
							lowerModule:GetFullName() .. " (from " .. lower.name .. ")"
						)
					end
				end
			end
		end

		return modules
	end

	--[[ Custom Path Lookup ]]--
	for customPathKey, customPathValue in pairs(CustomPaths) do
		if type(customPathKey) == "string" and type(customPathValue) == "table" then
			CustomPathKeysByLower[customPathKey:lower()] = customPathKey
		else
			Helpers.silentTypeError("not a string type or not a table type")
		end
	end

	type TagView = {
		_tagName: string,
		GetChildren: (self: TagView) -> { Instance },
	}
	type IndexerView = { [string]: any }

	local tagViews: { [string]: TagView } = {}
	local tagViewMethods = {}
	function tagViewMethods:GetChildren(): { Instance }
		return CollectionService:GetTagged(self._tagName)
	end

	local function getTagView(tagName: string): TagView
		local existing = tagViews[tagName]
		if existing ~= nil then
			return existing
		end

		local tagView = setmetatable({_tagName = tagName}, {__index = tagViewMethods}) :: TagView

		tagViews[tagName] = tagView
		return tagView
	end

	local tagRoot: IndexerView = (setmetatable({}, {__index = function(_, tagName: string): TagView return getTagView(tagName) end}) :: any) :: IndexerView

	local function findCustomPathModule(folders: { Instance? }, moduleName: string): ModuleScript?
		local moduleKey = moduleName:lower()
		for _, folder in ipairs(folders) do
			if folder ~= nil then
				local folderInstance: Instance = folder
				local exactMatch = folderInstance:FindFirstChild(moduleName)
				if exactMatch ~= nil then
					if exactMatch:IsA("ModuleScript") then
						return exactMatch
					end
					Helpers.silentTypeError("not a ModuleScript type")
					return nil
				end

				for _, child in ipairs(folderInstance:GetChildren()) do
					if child:IsA("ModuleScript") and child.Name:lower() == moduleKey then
						return child
					end
				end
			end
		end

		return nil
	end

	local function getCustomPathView(pathKey: string): { [string]: any }?
		local normalizedPathKey = CustomPathKeysByLower[pathKey:lower()]
		if normalizedPathKey == nil then
			return nil
		end

		local cachedView = CustomPathViews[normalizedPathKey]
		if cachedView ~= nil then
			return cachedView
		end

		local folders: { Instance? } = {}
		for _, folder in ipairs(CustomPaths[normalizedPathKey]) do
			table.insert(folders, folder)
		end
		local loadedModules: { [string]: any } = {}

		local view: IndexerView = (setmetatable({}, {
			__index = function(_, moduleName: string): any
				if type(moduleName) ~= "string" then
					error("Invalid module key for '" .. normalizedPathKey .. "'", 2)
				end

				local moduleCacheKey = moduleName:lower()
				local cachedLoadedModule = loadedModules[moduleCacheKey]
				if cachedLoadedModule ~= nil then
					return cachedLoadedModule
				end

				local moduleScript = findCustomPathModule(folders, moduleName)
				if moduleScript ~= nil then
					local loadedModule = Helpers.requireModule(moduleScript, normalizedPathKey .. "." .. moduleName, 2)
					loadedModules[moduleCacheKey] = loadedModule
					return loadedModule
				end

				error("'" .. normalizedPathKey .. "." .. moduleName .. "' does not exist. Check for typos and confirm the module exists in the game.\n  Traceback:\n" .. debug.traceback(nil, 2), 2)
			end,
		}) :: any) :: IndexerView

		CustomPathViews[normalizedPathKey] = view
		return view
	end

	--[[ Cache Init ]]--
	Modules = populateModules()

	--[[ Shortcuts Paths API ]]--
	setmetatable(Module, {
		__index = function(_, key: string): any
			local originalKey = key
			key = key:lower()

			if Services[key] then
				return Services[key]
			end

			if key == "localplayer" then
				return Players.LocalPlayer
			end

			local customPathView = getCustomPathView(originalKey)
			if customPathView ~= nil then
				return customPathView
			end

			if key == "tag" then
				return tagRoot
			end

			local cachedLoadedModule = LoadedModulesCache[key]
			if cachedLoadedModule ~= nil then
				return cachedLoadedModule
			end

			local prioritizedModuleScript = ServiceExternalModules[key]
				or ServiceInternalModules[key]
				or ServiceModules[key]
			if prioritizedModuleScript then
				local loadedModule = Helpers.requireModule(prioritizedModuleScript, originalKey, 2)
				LoadedModulesCache[key] = loadedModule
				return loadedModule
			end

			local moduleScript = Modules[key]
			if moduleScript then
				local loadedModule = Helpers.requireModule(moduleScript, originalKey, 2)
				LoadedModulesCache[key] = loadedModule
				return loadedModule
			end

			local allTagsOk, allTags = pcall(function()
				return CollectionService:GetAllTags()
			end)
			if allTagsOk and type(allTags) == "table" then
				for _, tagName in ipairs(allTags) do
					if type(tagName) == "string" and tagName:lower() == key then
						return getTagView(tagName)
					end
				end
			end

			error("'" .. originalKey .. "' does not exist. Check for typos and confirm the module exists in the game.\n  Traceback:\n" .. debug.traceback(nil, 2), 2)
		end
	})

	return Module
end
