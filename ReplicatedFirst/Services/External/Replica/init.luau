if game:GetService("RunService"):IsServer() then
	--[[
MAD STUDIO

-[Replica]---------------------------------------

	State replication with life cycle handling and individual client subscription control.

	WARNING: Avoid numeric tables with gaps & non string/numeric keys - They can't be replicated!

	Members:

		Replica.ReadyPlayers          [table] -- (read-only) {[player] = true, ...}
		Replica.NewReadyPlayer        [Signal] (player)
		Replica.RemovingReadyPlayer   [Signal] (player)

	Functions:

		Replica.Token(token_string) --> [ReplicaToken] -- Only one token object can be created for each unique "token_string"

		Replica.New(params) --> [Replica]
			params   [table]:
				{
					Token = [ReplicaToken],
					-- Optional:
					Tags = {}, -- Immutable dictionary meant for identifying the Replica (e.g. UserId = 2312310)
					Data = {}, -- Initial replica state
					WriteLib = ModuleScript,
				}

		Replica.FromId(id) --> [Replica] or nil

	Members [Replica]:

		Replica.Tags             [table] Secondary Replica identifiers
		Replica.Data             [table] (Read only) Table which is replicated

		Replica.Id               [number] Unique identifier
		Replica.Token            [string] Primary Replica identifier

		Replica.Parent           [Replica] or nil
		Replica.Children         [table]: {[replica] = true, ...}

		Replica.BoundInstance    [Instance] or nil

		Replica.OnServerEvent    [Signal] (player, ...)

		Replica.Maid             [Maid]

	Methods [Component]:

		-- [path]: {"Players", 2312310, "Health"} -- A path defines a key branch within Replica.Data

		Replica:Set(path, value)
		Replica:SetValues(path, values)
			values   [table]: {key = value, ...}

		Replica:TableInsert(path, value, index?) --> new_index -- Performs table.insert(path, value)
		Replica:TableRemove(path, index) --> removed_value -- Performs table.remove(path, index)

		Replica:Write(function_name, ...) --> ... -- Run WriteLib function with given parameters

		Replica:FireClient(player, ...) -- Will not replicate to unsubscribed players
		Replica:FireAllClients(...) -- Will not replicate to unsubscribed players
		Replica:UFireClient(player, ...) -- Same as "Replica:FireClient()", but using UnreliableRemoteEvent
		Replica:UFireAllClients(...) -- Same as "Replica:FireAllClients()", but using UnreliableRemoteEvent

		Replica:SetParent(replica) -- Replication will be inherited from parent replica; Replication and bind methods will be locked.

		Replica:BindToInstance(instance) -- Players who observe the instance stream in
			-- will be subscribed to this component; Observing the instance stream out
			-- will destroy the component for the observing player; Replicas should be bound
			-- to instances first and then ":Replicate()" or ":Subscribe()" should be called
			-- after. A replica can only be bound once.

		Replica:Replicate() -- Subscribes all existing and future players; ":Subscribe()" and ":Unsubscribe()" will become locked
		Replica:DontReplicate() -- Resets all previous subscription settings;
		Replica:Subscribe(player) -- Replicates to player; WILL NOT subscribe to players that are not ready & will throw a warning for trying to do so.
		Replica:Unsubscribe(player) -- Destroys Replica for player

		Replica:Identify() --> [string] -- Debug

		Replica:IsActive() --> [bool]

		Replica:Destroy() -- Destroys replica and all of its descendants (Depth-first)

--]]

	----- Dependencies -----

	local RateLimit = require(script.Parent.RateLimit)
	local Remote = require(script.ReplicaShared.Remote)
	local Signal = require(script.Parent.Signal)
	local Maid = require(script.Parent.Maid)

	----- Private -----

	local BIND_TAG = "Bind"
	local CS_TAG = "REPLICA" -- CollectionService tag
	local REPLICATION_ALL = "ALL"
	local MAID_LOCK = {}
	local EMPTY_TABLE = {}

	local CollectionService = game:GetService("CollectionService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Players = game:GetService("Players")

	local GlobalRateLimit = RateLimit.New(120)

	local ReadyPlayers: {[Player]: boolean} = {}


	local Replicas = {} -- {[id]: Replica}


	local TopReplicas = {} -- {[Replica]: true} -- Replicas with active subscription settings


	local ReplicationAllReplicas = {} -- {[Replica]: true} -- Replicas that had the method :Replicate() called on them


	local SelectiveSubscriptions = {} -- {[Player]: {[replica]: true}}

	local RemoteRequestData = Remote.New("ReplicaRequestData") -- Fired client-side when the client loads for the first time

	local RemoteSet = Remote.New("ReplicaSet")                 -- (replica_id, path, value)
	local RemoteSetValues = Remote.New("ReplicaSetValues")     -- (replica_id, path, values)
	local RemoteTableInsert = Remote.New("ReplicaTableInsert") -- (replica_id, path, value, index)
	local RemoteTableRemove = Remote.New("ReplicaTableRemove") -- (replica_id, path, index)
	local RemoteWrite = Remote.New("ReplicaWrite")             -- (replica_id, fn_id, ...)
	local RemoteSignal = Remote.New("ReplicaSignal")           -- (replica_id, ...)
	local RemoteParent = Remote.New("ReplicaParent")           -- (replica_id, parent_id)
	local RemoteCreate = Remote.New("ReplicaCreate")           -- (creation, root_id?) or ({creation, ...})
	local RemoteBind = Remote.New("ReplicaBind")               -- (replica_id)
	local RemoteDestroy = Remote.New("ReplicaDestroy")         -- (replica_id)
	local RemoteSignalUnreliable = Remote.New("ReplicaSignalUnreliable", true)   -- (replica_id, ...)

	local _NetworkMonitorHook: ((Player, string, ...any) -> ())? = nil

	local Index = 0

	local WriteLibCache: {[ModuleScript]: {[string | number]: {Id: number, fn: (...any) -> (...any)}}} = {}
	local WriteFlag = false
	local Tokens: {[string]: boolean} = {}
	local TokenValidate = {}

	local BindValuePrefab = Instance.new("NumberValue")
	BindValuePrefab.Name = "ReplicaBind"
	CollectionService:AddTag(BindValuePrefab, CS_TAG)

	local function IterateGroup(replica, fn) -- fn(replica)
		fn(replica)
		for child in pairs(replica.Children) do
			IterateGroup(child, fn)
		end
	end

	local function LoadWriteLib(module: ModuleScript)

		local write_lib = WriteLibCache[module]

		if write_lib ~= nil then
			return write_lib -- WriteLib module was previously loaded
		end

		if typeof(module) ~= "Instance" or module:IsA("ModuleScript") ~= true then
			error(`[{script.Name}]: "WriteLib" is not a ModuleScript`)
		elseif module:IsDescendantOf(ReplicatedStorage) == false then
			error(`[{script.Name}]: "WriteLib" module must be a descendant of ReplicatedStorage`)
		end

		local loaded_module = require(module)

		if type(loaded_module) ~= "table" then
			error(`[{script.Name}]: A "WriteLib" ModuleScript must return a table`)
		end

		local function_list = {} -- fn_id = {fn_name, fn}

		for key, value in pairs(loaded_module) do
			if type(key) ~= "string" then
				error(`[{script.Name}]: "WriteLib" table keys must be strings`)
			elseif type(value) ~= "function" then
				error(`[{script.Name}]: "WriteLib" table values must be functions`)
			end
			table.insert(function_list, {key, value})
		end

		table.sort(function_list, function(item1, item2)
			return item1[1] < item2[1] -- Sort functions by their names - this creates a consistent indexing on server and client-side
		end)

		write_lib = {} -- {["fn_name" | fn_id] = {Id = fn_id, fn = fn}, ...}

		for fn_id, fn_entry in ipairs(function_list) do
			local entry_table = {Id = fn_id, fn = fn_entry[2]}
			write_lib[fn_entry[1]] = entry_table
			write_lib[fn_id] = entry_table
		end

		WriteLibCache[module] = write_lib

		return write_lib

	end

	function GenerateCreation(replica)
		local replication = {}
		local creation = {}
		IterateGroup(replica, function(group_replica)
			local self_creation = group_replica.self_creation
			self_creation[4] = if group_replica.Parent == nil then 0 else group_replica.Parent.Id
			creation[tostring(group_replica.Id)] = self_creation
			group_replica.creation = creation
			group_replica.replication = replication
		end)
	end

	----- Public -----

	export type Replica = {
		Tags: {[any]: any},
		Data: {[any]: any},
		Id: number,
		Token: string,
		Parent: Replica?,
		Children: {[Replica]: boolean?},
		BoundInstance: Instance?,
		OnServerEvent: {Connect: (self: any, listener: (Player, ...any) -> ()) -> ({Disconnect: (self: any) -> ()})},
		Maid: typeof(Maid),

		Set: (self: any, path: {string}, value: any) -> (),
		SetValues: (self: any, path: {string}, values: {[string]: any}) -> (),
		TableInsert: (self: any, path: {string}, value: any, index: number?) -> (number),
		TableRemove: (self: any, path: {string}, index: number) -> (any),
		Write: (self: any, function_name: string, ...any) -> (...any),
		FireClient: (self: any, player: Player, ...any) -> (),
		FireAllClients: (self: any, ...any) -> (),
		UFireClient: (self: any, player: Player, ...any) -> (),
		UFireAllClients: (self: any, ...any) -> (),
		SetParent: (self: any, new_parent: Replica) -> (),
		BindToInstance: (self: any, instance: Instance) -> (),
		Replicate: (self: any) -> (),
		DontReplicate: (self: any) -> (),
		Subscribe: (self: any, player: Player) -> (),
		Unsubscribe: (self: any, player: Player) -> (),
		Identify: (self: any) -> (string),
		IsActive: (self: any) -> (boolean),
		Destroy: (self: any) -> (),
	}

	local Replica = {
		ReadyPlayers = ReadyPlayers,
		NewReadyPlayer = Signal.New(),
		RemovingReadyPlayer = Signal.New(),
	}
	Replica.__index = Replica

	local ReplicaToken = {}
	ReplicaToken.__index = ReplicaToken

	local LockedReplica = {}
	LockedReplica.__index = LockedReplica

	function Replica.Token(name: string)

		if type(name) ~= "string" then
			error(`[{script.Name}]: name must be a string`)
		end

		if Tokens[name] == true then
			error(`[{script.Name}]: Token "{name}" duplicate`)
		end

		Tokens[name] = true

		local self = setmetatable({
			Name = name,
		}, ReplicaToken)

		TokenValidate[self] = true

		return self

	end

	function Replica.New(params: {Token: typeof(ReplicaToken), Tags: {}?, Data: {}?, WriteLib: ModuleScript?}): Replica

		local token = params.Token
		local tags = params.Tags or {}
		local data = params.Data or {}
		local write_lib = nil

		if TokenValidate[token] == nil then
			error(`[{script.Name}]: "Token" is not valid ({tostring(token)})`)
		elseif type(tags) ~= "table" then
			error(`[{script.Name}]: "Tags" is not a table`)
		elseif type(data) ~= "table" then
			error(`[{script.Name}]: "Data" is not a table`)
		elseif tags[BIND_TAG] ~= nil then
			error(`[{script.Name}]: "Tags.{BIND_TAG}" key is reserved`)
		end

		if params.WriteLib ~= nil then
			write_lib = LoadWriteLib(params.WriteLib)
		end

		Index += 1

		local self = setmetatable({
			Tags = tags,
			Data = data,
			Id = Index,
			Token = token.Name,
			Parent = nil,
			Children = {},
			BoundInstance = nil,
			OnServerEvent = Signal.New(),
			Maid = Maid.New(MAID_LOCK),

			self_creation = {token.Name, tags, data, 0, params.WriteLib},
			creation = nil, -- ["replica_id"] = {token, tags, data, parent_id, write_lib}, ...
			replication = nil, -- {REPLICATION_ALL = true} or {[Player] = true, ...}

			write_lib = write_lib,
			write_lib_module = params.WriteLib,
			bind_value = nil,

		}, Replica)

		Replicas[Index] = self

		return self

	end

	function Replica.FromId(id: number): Replica
		return Replicas[id]
	end

	function Replica.Test()
		return {
			Replicas = Replicas, -- [id] = Replica, ...
			TopReplicas = TopReplicas, -- [Replica] = true, ... -- Replicas with active subsciption settings
			ReplicationAllReplicas = ReplicationAllReplicas, -- [Replica] = true, ... -- Replicas that had the method :Replicate() called on them
			SelectiveSubscriptions = SelectiveSubscriptions, -- [Player] = {[replica] = true, ...}
		}
	end

	function Replica:Set(path: {string}, value: any)

		-- Apply local change:

		local pointer = self.Data
		for i = 1, #path - 1 do
			pointer = pointer[path[i]]
		end
		pointer[path[#path]] = value

		-- Replicate change:

		if WriteFlag == false then
			local self_id = self.Id
			if self.replication ~= nil then
				if self.replication[REPLICATION_ALL] == true then
					for player in pairs(ReadyPlayers) do
						RemoteSet:FireClient(player, self_id, path, value)
						if _NetworkMonitorHook then _NetworkMonitorHook(player, "ReplicaSet:" .. tostring(path[#path]), value) end
					end
				else
					for player in pairs(self.replication) do
						RemoteSet:FireClient(player, self_id, path, value)
						if _NetworkMonitorHook then _NetworkMonitorHook(player, "ReplicaSet:" .. tostring(path[#path]), value) end
					end
				end
			end
		end

	end

	function Replica:SetValues(path: {string}, values: {[string]: any})

		-- Apply local change:

		local pointer = self.Data
		for _, key in ipairs(path) do
			pointer = pointer[key]
		end
		for key, value in pairs(values) do
			pointer[key] = value
		end

		-- Replicate change:

		if WriteFlag == false then
			local self_id = self.Id
			if self.replication ~= nil then
				if self.replication[REPLICATION_ALL] == true then
					for player in pairs(ReadyPlayers) do
						RemoteSetValues:FireClient(player, self_id, path, values)
						if _NetworkMonitorHook then for k, v in pairs(values) do _NetworkMonitorHook(player, "ReplicaSet:" .. tostring(k), v) end end
					end
				else
					for player in pairs(self.replication) do
						RemoteSetValues:FireClient(player, self_id, path, values)
						if _NetworkMonitorHook then for k, v in pairs(values) do _NetworkMonitorHook(player, "ReplicaSet:" .. tostring(k), v) end end
					end
				end
			end
		end

	end

	function Replica:TableInsert(path: {string}, value: any, index: number?): number

		-- Apply local change:

		local pointer = self.Data
		for _, key in ipairs(path) do
			pointer = pointer[key]
		end
		if index ~= nil then
			table.insert(pointer, index, value)
		else
			table.insert(pointer, value)
		end

		-- Replicate change:

		if WriteFlag == false then
			local self_id = self.Id
			if self.replication ~= nil then
				if self.replication[REPLICATION_ALL] == true then
					for player in pairs(ReadyPlayers) do
						RemoteTableInsert:FireClient(player, self_id, path, value, index)
						if _NetworkMonitorHook then _NetworkMonitorHook(player, "ReplicaTableInsert", path, value, index) end
					end
				else
					for player in pairs(self.replication) do
						RemoteTableInsert:FireClient(player, self_id, path, value, index)
						if _NetworkMonitorHook then _NetworkMonitorHook(player, "ReplicaTableInsert", path, value, index) end
					end
				end
			end
		end

		return index or #pointer

	end

	function Replica:TableRemove(path: {string}, index: number): any

		-- Apply local change:

		local pointer = self.Data
		for _, key in ipairs(path) do
			pointer = pointer[key]
		end
		local removed_value = table.remove(pointer, index)

		-- Replicate change:

		if WriteFlag == false then
			local self_id = self.Id
			if self.replication ~= nil then
				if self.replication[REPLICATION_ALL] == true then
					for player in pairs(ReadyPlayers) do
						RemoteTableRemove:FireClient(player, self_id, path, index)
						if _NetworkMonitorHook then _NetworkMonitorHook(player, "ReplicaTableRemove", path, index) end
					end
				else
					for player in pairs(self.replication) do
						RemoteTableRemove:FireClient(player, self_id, path, index)
						if _NetworkMonitorHook then _NetworkMonitorHook(player, "ReplicaTableRemove", path, index) end
					end
				end
			end
		end

		return removed_value

	end

	function Replica:Write(function_name: string, ...): ...any

		local write_lib_entry = self.write_lib[function_name]

		if WriteFlag == true then -- Chained :Write()
			return write_lib_entry.fn(self, ...)
		end

		-- Apply local change:

		WriteFlag = true
		local return_params = table.pack(pcall(write_lib_entry.fn, self, ...))
		WriteFlag = false

		if return_params[1] ~= true then
			error(`[{script.Name}]: (WriteLib) ` .. tostring(return_params[2]))
		end

		table.remove(return_params, 1)

		-- Replicate change:

		local self_id = self.Id
		local fn_id = write_lib_entry.Id

		if self.replication ~= nil then
			if self.replication[REPLICATION_ALL] == true then
				for player in pairs(ReadyPlayers) do
					RemoteWrite:FireClient(player, self_id, fn_id, ...)
					if _NetworkMonitorHook then _NetworkMonitorHook(player, "ReplicaWrite", fn_id, ...) end
				end
			else
				for player in pairs(self.replication) do
					RemoteWrite:FireClient(player, self_id, fn_id, ...)
					if _NetworkMonitorHook then _NetworkMonitorHook(player, "ReplicaWrite", fn_id, ...) end
				end
			end
		end

		return table.unpack(return_params)

	end

	function Replica:FireClient(player, ...)
		if self.replication ~= nil then
			if (self.replication[REPLICATION_ALL] == true and ReadyPlayers[player] == true) or self.replication[player] ~= nil then
				RemoteSignal:FireClient(player, self.Id, ...)
				if _NetworkMonitorHook then _NetworkMonitorHook(player, "ReplicaSignal", ...) end
			end
		end
	end

	function Replica:FireAllClients(...)
		local self_id = self.Id
		if self.replication ~= nil then
			if self.replication[REPLICATION_ALL] == true then
				for player in pairs(ReadyPlayers) do
					RemoteSignal:FireClient(player, self_id, ...)
					if _NetworkMonitorHook then _NetworkMonitorHook(player, "ReplicaSignal", ...) end
				end
			else
				for player in pairs(self.replication) do
					RemoteSignal:FireClient(player, self_id, ...)
					if _NetworkMonitorHook then _NetworkMonitorHook(player, "ReplicaSignal", ...) end
				end
			end
		end
	end

	function Replica:UFireClient(player, ...)
		if self.replication ~= nil then
			if (self.replication[REPLICATION_ALL] == true and ReadyPlayers[player] == true) or self.replication[player] ~= nil then
				RemoteSignalUnreliable:FireClient(player, self.Id, ...)
				if _NetworkMonitorHook then _NetworkMonitorHook(player, "ReplicaSignalUnreliable", ...) end
			end
		end
	end

	function Replica:UFireAllClients(...)
		local self_id = self.Id
		if self.replication ~= nil then
			if self.replication[REPLICATION_ALL] == true then
				for player in pairs(ReadyPlayers) do
					RemoteSignalUnreliable:FireClient(player, self_id, ...)
					if _NetworkMonitorHook then _NetworkMonitorHook(player, "ReplicaSignalUnreliable", ...) end
				end
			else
				for player in pairs(self.replication) do
					RemoteSignalUnreliable:FireClient(player, self_id, ...)
					if _NetworkMonitorHook then _NetworkMonitorHook(player, "ReplicaSignalUnreliable", ...) end
				end
			end
		end
	end

	function Replica:SetParent(new_parent)

		if type(new_parent) ~= "table" or getmetatable(new_parent) ~= Replica then
			error(`[{script.Name}]: new_parent is not a Replica ({tostring(new_parent)})`)
		elseif Replicas[new_parent.Id] == nil then
			error(`[{script.Name}]: Can't set destroyed Replica as parent`)
		end

		-- Top Replica / Bind check:

		if TopReplicas[self] ~= nil then
			error(`[{script.Name}]: Can't change parent for top level Replica`)
		end

		if self.BoundInstance ~= nil then
			error(`[{script.Name}]: Can't change parent for bound Replica`)
		end

		-- Recursion check:

		local recursion_check = new_parent

		while recursion_check ~= nil do
			recursion_check = recursion_check.Parent
			if recursion_check == self then
				error(`[{script.Name}]: Can't set descendant Replica as parent`)
			end
		end

		-- Hierarchy:

		local old_parent = self.Parent

		if old_parent == new_parent then
			return
		end

		self.Parent = new_parent

		if old_parent ~= nil then
			old_parent.Children[self] = nil
		end

		new_parent.Children[self] = true

		-- Altering creation and replication tables:

		IterateGroup(self, function(group_replica)
			local string_id = tostring(group_replica.Id)
			if old_parent ~= nil and old_parent.creation ~= nil then
				old_parent.creation[string_id] = nil
			end
			if new_parent.creation ~= nil then
				local self_creation = group_replica.self_creation
				self_creation[4] = group_replica.Parent.Id
				new_parent.creation[string_id] = self_creation
			end
			group_replica.creation = new_parent.creation
			group_replica.replication = new_parent.replication
		end)

		-- Subscriptions:

		local self_id = self.Id
		local parent_id = new_parent.Id
		local parent_creation = new_parent.creation

		local old_subscriptions = EMPTY_TABLE

		if old_parent ~= nil and old_parent.replication ~= nil then
			if old_parent.replication[REPLICATION_ALL] == true then
				old_subscriptions = ReadyPlayers
			else
				old_subscriptions = old_parent.replication
			end
		end

		local new_subscriptions = EMPTY_TABLE

		if new_parent ~= nil and new_parent.replication ~= nil then
			if new_parent.replication[REPLICATION_ALL] == true then
				new_subscriptions = ReadyPlayers
			else
				new_subscriptions = new_parent.replication
			end
		end

		-- Informing clients who lost subscription to replica group:

		if old_parent ~= nil and old_parent.replication ~= nil then
			if new_parent.replication ~= old_parent.replication and new_subscriptions ~= ReadyPlayers then

				for player in pairs(old_subscriptions) do
					if new_subscriptions[player] == nil then
						RemoteDestroy:FireClient(player, self_id)
					end
				end

			end
		end

		-- Informing clients who gained subscription to replica group / who retained the subscription:

		if new_parent.replication ~= nil then

			local custom_creation

			for player in pairs(new_subscriptions) do

				if old_subscriptions[player] == true then
					RemoteParent:FireClient(player, self_id, parent_id) -- Subscription was retained
				else
					if custom_creation == nil then -- Generating custom_creation if at least one new subscription was made
						custom_creation = {}
						IterateGroup(self, function(group_replica)
							local string_id = tostring(group_replica.Id)
							custom_creation[string_id] = parent_creation[string_id]
						end)
					end
					RemoteCreate:FireClient(player, custom_creation, self_id)
				end

			end

		end

	end

	function Replica:BindToInstance(instance: Instance)

		if typeof(instance) ~= "Instance" then
			error(`[{script.Name}]: "instance" argument is not an Instance ({tostring(instance)})`)
		end

		if self.Parent ~= nil then
			error(`[{script.Name}]: Can't bind Replica parented to another Replica`)
		end

		if self.BoundInstance ~= nil then
			error(`[{script.Name}]: Can't change Replica bind to another Instance`)
		end

		if instance:IsA("Model") == true and (instance.ModelStreamingMode == Enum.ModelStreamingMode.Default or instance.ModelStreamingMode == Enum.ModelStreamingMode.Nonatomic) then
			warn(`[{script.Name}]: Bound Replica to a model that has improper "ModelStreamingMode" setup; Traceback:\n` .. debug.traceback())
		end

		local bind_value = BindValuePrefab:Clone()
		bind_value.Value = self.Id

		self.Tags[BIND_TAG] = true
		self.BoundInstance = instance
		self.bind_value = bind_value

		bind_value.Parent = instance

		local self_id = self.Id
		if self.replication ~= nil then
			if self.replication[REPLICATION_ALL] == true then
				for player in pairs(ReadyPlayers) do
					RemoteBind:FireClient(player, self_id)
				end
			else
				for player in pairs(self.replication) do
					RemoteBind:FireClient(player, self_id)
				end
			end
		end

	end

	function Replica:Replicate()

		if self.Parent ~= nil then
			error(`[{script.Name}]: Can't selectively replicate Replica parented to another Replica`)
		end

		if self.creation == nil then
			GenerateCreation(self)
			TopReplicas[self] = true
		elseif self.replication[REPLICATION_ALL] == true then
			return
		end

		local creation = self.creation
		local replication = self.replication

		for player in pairs(ReadyPlayers) do
			if replication[player] == nil then
				RemoteCreate:FireClient(player, creation)
				if _NetworkMonitorHook then _NetworkMonitorHook(player, "ReplicaCreate:Replicate", creation) end
			else
				local selective_lookup = SelectiveSubscriptions[player]
				selective_lookup[self] = nil
			end
		end

		table.clear(replication)
		replication[REPLICATION_ALL] = true
		ReplicationAllReplicas[self] = true

	end

	function Replica:DontReplicate()

		if self.Parent ~= nil then
			error(`[{script.Name}]: Can't selectively replicate Replica parented to another Replica`)
		end

		local replication = self.replication

		if replication == nil or next(replication) == nil then
			return
		end

		ReplicationAllReplicas[self] = nil

		local self_id = self.Id

		if replication[REPLICATION_ALL] == true then
			for player in pairs(ReadyPlayers) do
				RemoteDestroy:FireClient(player, self_id)
			end
		else
			for player in pairs(replication) do
				RemoteDestroy:FireClient(player, self_id)
				SelectiveSubscriptions[player][self] = nil
			end
		end

		table.clear(replication)

	end

	function Replica:Subscribe(player: Player)

		if self.Parent ~= nil then
			error(`[{script.Name}]: Can't selectively replicate Replica parented to another Replica`)
		end

		if self.creation == nil then
			GenerateCreation(self)
			TopReplicas[self] = true
		elseif self.replication[REPLICATION_ALL] == true then
			error(`[{script.Name}]: "Subscribe()" is locked after calling "Replicate()"`)
		end

		if ReadyPlayers[player] == nil then
			warn(`[{script.Name}]: Called "Subscribe()" on a non-ready player; Traceback:\n` .. debug.traceback())
			return
		end

		local creation = self.creation
		local replication = self.replication

		if replication[player] ~= nil then
			return -- Already subscribed
		end

		replication[player] = true
		SelectiveSubscriptions[player][self] = true
		RemoteCreate:FireClient(player, creation)
		if _NetworkMonitorHook then _NetworkMonitorHook(player, "ReplicaCreate:Subscribe", creation) end

	end

	function Replica:Unsubscribe(player: Player)

		if self.Parent ~= nil then
			error(`[{script.Name}]: Can't selectively replicate Replica parented to another Replica`)
		end

		local replication = self.replication

		if replication == nil then
			return
		end

		if replication[REPLICATION_ALL] == true then
			error(`[{script.Name}]: "Unsubscribe()" is locked after calling "Replicate()"`)
		end

		if replication[player] ~= nil then
			replication[player] = nil
			SelectiveSubscriptions[player][self] = nil
			RemoteDestroy:FireClient(player, self.Id)
		end

	end

	function Replica:Identify(): string
		local tag_string = ""
		local first_tag = true
		for key, value in pairs(self.Tags) do
			tag_string ..= `{if first_tag == true then "" else ";"}{tostring(key)}={tostring(value)}`
			first_tag = false
		end
		return `[Id:{self.Id};Token:{self.Token};Tags:[{tag_string}]]`
	end

	function Replica:IsActive(): boolean
		return self.Maid:IsActive()
	end

	local function DestroyReplica(replica)
		-- Scan children replicas:
		for child in pairs(replica.Children) do
			DestroyReplica(child)
		end

		local id = replica.Id
		-- Clear replica entry:
		Replicas[id] = nil
		-- Cleanup:
		replica.Maid:Unlock(MAID_LOCK)
		replica.Maid:Cleanup()
		-- Bind cleanup:
		if replica.BoundInstance ~= nil then
			replica.BoundInstance = nil
			replica.bind_value:Destroy()
			replica.bind_value = nil
		end
		-- Remove creation data:
		if replica.creation ~= nil then
			replica.creation[tostring(id)] = nil
		end
		-- Swap metatables:
		setmetatable(replica, LockedReplica)
	end

	function Replica:Destroy()

		local self_id = self.Id

		if Replicas[self_id] == nil then
			return
		end

		local is_top = TopReplicas[self] == true

		-- Destroy replica for all clients who were replicated to:

		if self.replication ~= nil then
			if self.replication[REPLICATION_ALL] == true then
				for player in pairs(ReadyPlayers) do
					RemoteDestroy:FireClient(player, self_id)
				end
			else
				for player in pairs(self.replication) do
					RemoteDestroy:FireClient(player, self_id)
					if is_top == true then
						SelectiveSubscriptions[player][self] = nil
					end
				end
			end
		end

		-- Clearing hierarchy:

		TopReplicas[self] = nil
		ReplicationAllReplicas[self] = nil

		if self.Parent ~= nil then
			self.Parent.Children[self] = nil
		end

		-- Recursive destruction:

		DestroyReplica(self)

	end

	----- Init -----

	do -- Destroyed replica metatable:

		local keep_methods = {
			Identify = true,
			Destroy = true,
		}

		for name, fn in pairs(Replica) do
			if name ~= "__index" then
				if keep_methods[name] == true then
					LockedReplica[name] = fn
				else
					LockedReplica[name] = function(self)
						error(`[{script.Name}]: Tried to call method "{name}" for a destroyed replica; {self:Identify()}`)
					end
				end
			end
		end

	end

	-- New player data replication:

	RemoteRequestData.OnServerEvent:Connect(function(player: Player)

		if ReadyPlayers[player] ~= nil and player:IsDescendantOf(Players) == true then
			return
		end

		-- Make the client create all replicas that are initially replicated to the client;
		-- Pack up and send intially replicated replicas:

		local creation = {}

		for replica in pairs(ReplicationAllReplicas) do
			table.insert(creation, replica.creation)
		end
		RemoteCreate:FireClient(player, creation)
		if _NetworkMonitorHook then _NetworkMonitorHook(player, "ReplicaCreate:Init", creation) end

		-- Let the client know that all replica data has been sent:
		RemoteRequestData:FireClient(player)

		-- Set player to active:
		ReadyPlayers[player] = true
		SelectiveSubscriptions[player] = {}
		Replica.NewReadyPlayer:Fire(player)

	end)

	-- Client-invoked replica signals:

	local function RemoteSignalHandle(player: Player, id: number, ...)

		-- Missing player prevention, spam prevention and exploit prevention:
		if ReadyPlayers[player] == nil or GlobalRateLimit:CheckRate(player) == false
			or type(id) ~= "number" then
			return
		end

		local replica = Replicas[id]

		if replica ~= nil then
			if replica.replication ~= nil and (replica.replication[REPLICATION_ALL] == true or replica.replication[player] ~= nil) then
				replica.OnServerEvent:Fire(player, ...)
			end
		end

	end

	RemoteSignal.OnServerEvent:Connect(function(player: Player, id: number, ...)
		RemoteSignalHandle(player, id, ...)
	end)
	RemoteSignalUnreliable.OnServerEvent:Connect(function(player: Player, id: number, ...)
		RemoteSignalHandle(player, id, ...)
	end)

	-- Player leave handling:

	Players.PlayerRemoving:Connect(function(player)

		if ReadyPlayers[player] == nil then
			return
		end

		-- Remove player from subscription settings:

		for replica in pairs(SelectiveSubscriptions[player]) do
			replica.replication[player] = nil
		end

		-- Remove player from ready players list:

		ReadyPlayers[player] = nil
		SelectiveSubscriptions[player] = nil
		Replica.RemovingReadyPlayer:Fire(player)

	end)

	function Replica.SetNetworkMonitorHook(hook: ((Player, string, ...any) -> ())?)
		_NetworkMonitorHook = hook
	end

	return Replica
else
--[[
MAD STUDIO

-[Replica]---------------------------------------

	State replication with life cycle handling and individual client subscription control.

	WARNING: Avoid numeric tables with gaps & non string/numeric keys - They can't be replicated!

	Members:

		Replica.IsReady        [bool]
		Replica.OnLocalReady   [Signal] ()

	Functions:

		Replica.RequestData() -- Requests the server to start sending replica data

		Replica.OnNew(token, listener) --> [Connection]
			token      [string]
			listener   [function] (replica)

		Replica.FromId(id) --> [Replica] or nil

	Members [Replica]:

		Replica.Tags             [table] Secondary Replica identifiers
		Replica.Data             [table] (Read only) Table which is replicated

		Replica.Id               [number] Unique identifier
		Replica.Token            [string] Primary Replica identifier

		Replica.Parent           [Replica] or nil
		Replica.Children         [table]: {[replica] = true, ...}

		Replica.BoundInstance    [Instance] or nil -- WARNING: Will be set to nil after destruction

		Replica.OnClientEvent    [Signal] (...)

		Replica.Maid             [Maid]

	Methods [Replica]:

		-- [path]: {"Players", 2312310, "Health"} -- A path defines a key branch within Replica.Data
		-- Listeners are called after Replica.Data mutation.

		Replica:OnSet(path, listener) --> [Connection] -- (Only for :Set(); For :SetValues() you can use :OnChange())
			listener   [function] (new_value, old_value)

		Replica:OnWrite(function_name, listener) --> [Connection]
			listener   [function] (...)

		Replica:OnChange(listener) --> [Connection]
			listener   [function] (action, path, param1, param2?)
				-- ("Set",         path, value, old_value)
				-- ("SetValues",   path, values)
				-- ("TableInsert", path, value, index)
				-- ("TableRemove", path, value, index)

		Replica:GetChild(token [string]) --> [Replica] or nil -- Searches for a child replica with given token name

		Replica:FireServer(...) -- Fire a signal to server-side listeners for this specific Replica; Must be subscribed
		Replica:UFireServer(...) -- Same as "Replica:FireServer()", but using UnreliableRemoteEvent

		Replica:Identify() --> [string] -- Debug

		Replica:IsActive() --> [bool]

--]]

	----- Dependencies -----

	local ReplicaShared = script:WaitForChild("ReplicaShared")
	local Remote = require(ReplicaShared.Remote)

	local Signal = require(script.Parent.Signal)
	local Maid = require(script.Parent.Maid)

	----- Private -----

	local BIND_TAG = "Bind"
	local CS_TAG = "REPLICA" -- CollectionService tag
	local MAID_LOCK = {}
	local REQUEST_DATA_REPEAT = 2

	local CollectionService = game:GetService("CollectionService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Players = game:GetService("Players")

	local DataRequestStarted = false


	local TokenReplicas = {} -- [token] = {[replica] = true, ...}


	local Replicas = {} -- [id] = Replica, ...


	local BindReplicas = {} -- [id] = Replica, ... -- Unannounced Replicas waiting for their binds to stream in


	local BindInstances = {} -- [id] = Instance, ...




	local NewReplicaListeners = {} -- [token] = {[connection] = true, ...}
	local RemoteRequestData = Remote.New("ReplicaRequestData") -- Fired client-side when the client loads for the first time

	local RemoteSet = Remote.New("ReplicaSet")                 -- (replica_id, path, value)
	local RemoteSetValues = Remote.New("ReplicaSetValues")     -- (replica_id, path, values)
	local RemoteTableInsert = Remote.New("ReplicaTableInsert") -- (replica_id, path, value, index)
	local RemoteTableRemove = Remote.New("ReplicaTableRemove") -- (replica_id, path, index)
	local RemoteWrite = Remote.New("ReplicaWrite")             -- (replica_id, fn_id, ...)
	local RemoteSignal = Remote.New("ReplicaSignal")           -- (replica_id, ...)
	local RemoteParent = Remote.New("ReplicaParent")           -- (replica_id, parent_id)
	local RemoteCreate = Remote.New("ReplicaCreate")           -- (creation, root_id?) or ({creation, ...})
	local RemoteBind = Remote.New("ReplicaBind")               -- (replica_id)
	local RemoteDestroy = Remote.New("ReplicaDestroy")         -- (replica_id)
	local RemoteSignalUnreliable = Remote.New("ReplicaSignalUnreliable", true)		   -- (replica_id, ...)

	local WriteLibCache: {[ModuleScript]: {[string | number]: {Name: string, Id: number, fn: (...any) -> (...any)}}} = {}
	local ReplicationFlag = false

	local function LoadWriteLib(module: ModuleScript)

		local write_lib = WriteLibCache[module]

		if write_lib ~= nil then
			return write_lib -- WriteLib module was previously loaded
		end

		local loaded_module = require(module)

		local function_list = {} -- fn_id = {fn_name, fn}

		for key, value in pairs(loaded_module) do
			table.insert(function_list, {key, value})
		end

		table.sort(function_list, function(item1, item2)
			return item1[1] < item2[1] -- Sort functions by their names - this creates a consistent indexing on server and client-side
		end)

		write_lib = {} -- {["fn_name" | fn_id] = {Id = fn_id, fn = fn}, ...}

		for fn_id, fn_entry in ipairs(function_list) do
			local entry_table = {Name = fn_entry[1], Id = fn_id, fn = fn_entry[2]}
			write_lib[fn_entry[1]] = entry_table
			write_lib[fn_id] = entry_table
		end

		WriteLibCache[module] = write_lib

		return write_lib

	end

	----- Public -----

	export type Replica = {
		Tags: {[any]: any},
		Data: {[any]: any},
		Id: number,
		Token: string,
		Parent: Replica?,
		Children: {[Replica]: boolean?},
		BoundInstance: Instance?,
		OnClientEvent: {Connect: (self: any, listener: (...any) -> ()) -> ({Disconnect: (self: any) -> ()})},
		Maid: typeof(Maid),




		OnSet: (self: any, path: {}, listener: () -> ()) -> (Signal.Connection),


		OnWrite: (self: any, function_name: string, listener: (...any) -> ()) -> (Signal.Connection),


		OnChange: (self: any, listener: (action: "Set" | "SetValues" | "TableInsert" | "TableRemove", path: {any}, param1: any, param2: any?) -> ()) -> (Signal.Connection),
		GetChild: (self: any, token: string) -> (Replica?),
		FireServer: (self: any, ...any) -> (),
		UFireServer: (self: any, ...any) -> (),
		Identify: (self: any) -> (string),
		IsActive: (self: any) -> (boolean),
	}

	local FreeRunnerThread: thread?
--[[
	Yield-safe coroutine reusing by stravant;
	Sources:
	https://devforum.roblox.com/t/lua-signal-class-comparison-optimal-goodsignal-class/1387063
	https://gist.github.com/stravant/b75a322e0919d60dde8a0316d1f09d2f
--]]

	local function AcquireRunnerThreadAndCallEventHandler(fn, ...)
		local acquired_runner_thread = FreeRunnerThread
		FreeRunnerThread = nil
		fn(...)
		-- The handler finished running, this runner thread is free again.
		FreeRunnerThread = acquired_runner_thread
	end

	local function RunEventHandlerInFreeThread(...)
		AcquireRunnerThreadAndCallEventHandler(...)
		while true do
			AcquireRunnerThreadAndCallEventHandler(coroutine.yield())
		end
	end

	function ConnectionFire(self, ...)
		if not FreeRunnerThread then
			FreeRunnerThread = coroutine.create(RunEventHandlerInFreeThread)
		end
		task.spawn(FreeRunnerThread, self.fn, ...)
	end

	local Replica = {
		IsReady = false,
		OnLocalReady = Signal.New(),
	}
	Replica.__index = Replica

	local function ReplicaNew(id: number, self_creation: {}) -- self_creation = {token, tags, data, parent_id, write_module}

		local write_lib = nil
		if self_creation[5] ~= nil then
			write_lib = LoadWriteLib(self_creation[5])
		end

		local token = self_creation[1]
		local parent = BindReplicas[self_creation[4]] or Replicas[self_creation[4]]

		local self = setmetatable({
			Tags = self_creation[2],
			Data = self_creation[3],
			Id = id,
			Token = token,
			Parent = parent,
			Children = {},
			BoundInstance = nil,
			OnClientEvent = Signal.New(),
			Maid = Maid.New(MAID_LOCK),

			self_creation = self_creation,

			write_lib = write_lib,


			set_listeners = {}, -- {[key]: Signal}


			write_listeners = {}, -- {[key]: Signal}


			changed_listeners = Signal.New(),

		}, Replica)

		if parent ~= nil then
			parent.Children[self] = true
		end

		return self

	end

	function Replica.RequestData()

		if DataRequestStarted == true then
			return
		end

		DataRequestStarted = true

		task.spawn(function()

			RemoteRequestData:FireServer()

			while task.wait(REQUEST_DATA_REPEAT) do
				if Replica.IsReady == true then
					break
				end
				RemoteRequestData:FireServer()
			end

		end)

	end

	function Replica.OnNew(token: string, listener: (replica: Replica) -> ()): Signal.Connection

		if type(token) ~= "string" then
			error(`[{script.Name}]: "token" must be a string`)
		end

		local listeners = NewReplicaListeners[token]

		if listeners == nil then
			listeners = Signal.New()
			NewReplicaListeners[token] = listeners
		end

		local existing_replicas = TokenReplicas[token]

		local connection = listeners:Connect(listener)

		if existing_replicas ~= nil then
			local announce = {}
			for replica in pairs(existing_replicas) do
				announce[replica] = true
			end

			task.defer(function()


				for replica in pairs(announce) do


					if connection.IsConnected ~= true then


						break


					end


					if not FreeRunnerThread then


						FreeRunnerThread = coroutine.create(RunEventHandlerInFreeThread)


					end


					task.spawn(FreeRunnerThread, listener, replica)


				end


			end)
		end

		return connection

	end

	function Replica.FromId(id: number): typeof(Replica)?
		return Replicas[id]
	end

	function Replica.Test()
		return {
			TokenReplicas = TokenReplicas, -- [token] = {[replica] = true, ...}
			Replicas = Replicas, -- [id] = Replica, ...
			BindReplicas = BindReplicas, -- [id] = Replica, ... -- Unannounced Replicas waiting for their binds to stream in
			BindInstances = BindInstances, -- [id] = Instance, ...
		}
	end

	function Replica:OnSet(path: {}, listener: () -> ()): Signal.Connection
		local path_key = table.concat(path, ".")
		local listeners = self.set_listeners[path_key]
		if listeners == nil then
			listeners = Signal.New()
			self.set_listeners[path_key] = listeners
		end

		return listeners:Connect(listener)
	end

	function Replica:OnWrite(function_name: string, listener: (...any) -> ()): Signal.Connection
		local listeners = self.write_listeners[function_name]
		if listeners == nil then
			listeners = Signal.New()
			self.write_listeners[function_name] = listeners
		end

		return listeners:Connect(listener)
	end


	function Replica:OnChange(listener: (action: "Set" | "SetValues" | "TableInsert" | "TableRemove", path: {any}, param1: any, param2: any?) -> ()): Signal.Connection
		return self.changed_listeners:Connect(listener)
	end

	function Replica:GetChild(token: string): Replica?
		if type(token) ~= "string" then
			error(`[{script.Name}]: "token" must be a string`)
		end
		for replica in pairs(self.Children) do
			if replica.Token == token then
				return replica
			end
		end
		return nil
	end

	function Replica:FireServer(...)
		RemoteSignal:FireServer(self.Id, ...)
	end

	function Replica:UFireServer(...)
		RemoteSignalUnreliable:FireServer(self.Id, ...)
	end

	function Replica:Identify(): string
		local tag_string = ""
		local first_tag = true
		for key, value in pairs(self.Tags) do
			tag_string ..= `{if first_tag == true then "" else ";"}{tostring(key)}={tostring(value)}`
			first_tag = false
		end
		return `[Id:{self.Id};Token:{self.Token};Tags:[{tag_string}]]`
	end

	function Replica:IsActive(): boolean
		return self.Maid:IsActive()
	end

	function Replica:Set(path: {string}, value: any)

		if ReplicationFlag ~= true then
			error(`[{script.Name}]: "Set()" can't be called outside of WriteLibs client-side`)
		end

		-- Apply local change:

		local pointer = self.Data
		for i = 1, #path - 1 do
			pointer = pointer[path[i]]
		end
		local last_key = path[#path]
		local old_value = pointer[last_key]
		pointer[last_key] = value

		-- Firing signals:

		if next(self.set_listeners) ~= nil then
			local listeners = self.set_listeners[table.concat(path, ".")]
			if listeners ~= nil then
				listeners:Fire(value, old_value)
			end
		end
		self.changed_listeners:Fire("Set", path, value, old_value)

	end

	function Replica:SetValues(path: {string}, values: {[string]: any})

		if ReplicationFlag ~= true then
			error(`[{script.Name}]: "SetValues()" can't be called outside of WriteLibs client-side`)
		end

		-- Apply local change:

		local pointer = self.Data
		for _, key in ipairs(path) do
			pointer = pointer[key]
		end
		for key, value in pairs(values) do
			pointer[key] = value
		end

		-- Firing signals:

		self.changed_listeners:Fire("SetValues", path, values)

	end

	function Replica:TableInsert(path: {string}, value: any, index: number?): number

		if ReplicationFlag ~= true then
			error(`[{script.Name}]: "TableInsert()" can't be called outside of WriteLibs client-side`)
		end

		-- Apply local change:

		local pointer = self.Data
		for _, key in ipairs(path) do
			pointer = pointer[key]
		end
		if index ~= nil then
			table.insert(pointer, index, value)
		else
			table.insert(pointer, value)
			index = #pointer
		end

		-- Firing signals:

		self.changed_listeners:Fire("TableInsert", path, value, index)

		return index

	end

	function Replica:TableRemove(path: {string}, index: number): any

		if ReplicationFlag ~= true then
			error(`[{script.Name}]: "TableRemove()" can't be called outside of WriteLibs client-side`)
		end

		-- Apply local change:

		local pointer = self.Data
		for _, key in ipairs(path) do
			pointer = pointer[key]
		end
		local removed_value = table.remove(pointer, index)

		-- Firing signals:

		self.changed_listeners:Fire("TableRemove", path, removed_value, index)

		return removed_value

	end

	function Replica:Write(function_name: string, ...): ...any

		if ReplicationFlag ~= true then
			error(`[{script.Name}]: "Write()" can't be called outside of WriteLibs client-side`)
		end

		-- Apply local change:

		local write_lib_entry = self.write_lib[function_name]
		local return_params = table.pack(write_lib_entry.fn(self, ...))

		-- Firing signals:

		local listeners = self.write_listeners[function_name]
		if listeners ~= nil then
			listeners:Fire(...)
		end

		return table.unpack(return_params)

	end

	local function DestroyReplica(replica, is_depth_call)
		-- Scan children replicas:
		for child in pairs(replica.Children) do
			DestroyReplica(child, true)
		end

		if is_depth_call ~= true then
			if replica.Parent ~= nil then
				replica.Parent.Children[replica] = nil
			end
		end

		local id = replica.Id

		-- Clear replica references:
		local token_replicas = TokenReplicas[replica.Token]
		if token_replicas ~= nil then
			token_replicas[replica] = nil
		end
		if Replicas[id] == replica then
			Replicas[id] = nil
		end
		if BindReplicas[id] == replica then
			BindReplicas[id] = nil
		end
		-- Cleanup:
		replica.Maid:Unlock(MAID_LOCK)
		replica.Maid:Cleanup()
		-- Bind cleanup:
		replica.BoundInstance = nil
	end

	local function ReplicaToBindBuffer(replica, is_depth_call)

		-- Copy replica group:

		local copy_replica = ReplicaNew(replica.Id, replica.self_creation)
		BindReplicas[replica.Id] = copy_replica

		for group_replica in pairs(replica.Children) do
			ReplicaToBindBuffer(group_replica, true)
		end

		-- Destroy original:

		if is_depth_call ~= true then
			DestroyReplica(replica)
		end

		return copy_replica

	end

	local function ReplicaFromBindBuffer(replica, announce_buffer)

		local top_call = false

		if announce_buffer == nil then
			top_call = true
			announce_buffer = {}
		end

		BindReplicas[replica.Id] = nil

		local token = replica.Token
		local token_replicas = TokenReplicas[token]

		if token_replicas == nil then
			token_replicas = {}
			TokenReplicas[token] = token_replicas
		end

		token_replicas[replica] = true
		Replicas[replica.Id] = replica

		table.insert(announce_buffer, replica)

		for group_replica in pairs(replica.Children) do
			ReplicaFromBindBuffer(group_replica, announce_buffer)
		end

		if top_call == true then
			for _, replica in ipairs(announce_buffer) do
				local listeners = NewReplicaListeners[replica.Token]
				if listeners ~= nil then
					listeners:Fire(replica)
				end
			end
		end

	end

	local function CreationScan(nested_creation, iterator, parent_id)
		local entries = nested_creation[parent_id]
		if entries ~= nil then

			table.sort(entries, function(a, b)
				return a.Id < b.Id
			end)

			for _, entry in ipairs(entries) do
				iterator(entry.Id, entry.SelfCreation)
				CreationScan(nested_creation, iterator, entry.Id)
			end

		end
	end

	local function BreadthCreationSort(creation: {}, root_id: number?, iterator: (Id: number, SelfCreation: table) -> ())

		-- self_creation = {token, tags, data, parent_id, write_module}
		local top_creation = {} -- {Id = id, SelfCreation = self_creation}, ...
		local nested_creation = {} -- [parent_id] = {{Id = id, SelfCreation = self_creation}, ...}, ...
		local error_creation = {} -- {Id = id, SelfCreation = self_creation}, ... -- Missing parents

		if type(creation[1]) == "table" then -- creation pack {creation, ...}

			for _, packed_creation in ipairs(creation) do

				for string_id, self_creation in pairs(packed_creation) do
					local entry = {Id = tonumber(string_id), SelfCreation = self_creation}
					local parent_id = self_creation[4]
					if parent_id == 0 or entry.Id == root_id then
						table.insert(top_creation, entry)
					elseif packed_creation[tostring(parent_id)] ~= nil then
						local entries = nested_creation[parent_id]
						if entries == nil then
							entries = {}
							nested_creation[parent_id] = entries
						end
						table.insert(entries, entry)
					else
						table.insert(error_creation, entry)
					end
				end

			end

		else

			for string_id, self_creation in pairs(creation) do
				local entry = {Id = tonumber(string_id), SelfCreation = self_creation}
				local parent_id = self_creation[4]
				if parent_id == 0 or entry.Id == root_id then
					table.insert(top_creation, entry)
				elseif creation[tostring(parent_id)] ~= nil then
					local entries = nested_creation[parent_id]
					if entries == nil then
						entries = {}
						nested_creation[parent_id] = entries
					end
					table.insert(entries, entry)
				else
					table.insert(error_creation, entry)
				end
			end

		end

		table.sort(top_creation, function(a, b)
			return a.Id < b.Id
		end)

		local result = {}

		for _, entry in ipairs(top_creation) do
			iterator(entry.Id, entry.SelfCreation)
			CreationScan(nested_creation, iterator, entry.Id)
		end

		if #error_creation ~= 0 then -- An error occurred while replicating a replica group.

			local msg = `[{script.Name}]: GROUP REPLICATION ERROR - Missing parents for:\n`

			for i = 1, math.min(#error_creation, 50) do
				local entry = error_creation[i]
				local self_creation = entry.SelfCreation
				local tag_string = ""
				local first_tag = true
				for key, value in pairs(self_creation[2]) do
					tag_string ..= `{if first_tag == true then "" else ";"}{tostring(key)}={tostring(value)}`
					first_tag = false
				end
				msg ..= `[Id:{entry.Id};ParentId:{self_creation[4]};Token:{self_creation[1]};Tags:[{tag_string}]]\n`
			end

			if #error_creation > 50 then
				msg ..= `(hiding {50 - #error_creation} more)\n`
			end

			msg ..= "Traceback:\n" .. debug.traceback()

			warn(msg)

		end

		return result

	end

	local function GetInternalReplica(id)
		local replica = Replicas[id] or BindReplicas[id]
		if replica == nil then
			return nil
		end
		return replica
	end

	----- Init -----

	RemoteRequestData.OnClientEvent:Connect(function()

		if Replica.IsReady == true then
			return
		end

		Replica.IsReady = true
		print(`[{script.Name}]: Initial data received`)
		Replica.OnLocalReady:Fire()

	end)

	RemoteSet.OnClientEvent:Connect(function(id: number, path: {}, value: any)
		local replica = GetInternalReplica(id)
		if replica == nil then return end
		ReplicationFlag = true
		local success, msg = pcall(replica.Set, replica, path, value)
		ReplicationFlag = false
		if success ~= true then
			--error(`[{script.Name}]: Error while updating replica:\n{replica:Identify()}\n` .. msg)
		end
	end)

	RemoteSetValues.OnClientEvent:Connect(function(id: number, path: {}, values: {})
		local replica = GetInternalReplica(id)
		if replica == nil then return end
		ReplicationFlag = true
		local success, msg = pcall(replica.SetValues, replica, path, values)
		ReplicationFlag = false
		if success ~= true then
			--error(`[{script.Name}]: Error while updating replica:\n{replica:Identify()}\n` .. msg)
		end
	end)

	RemoteTableInsert.OnClientEvent:Connect(function(id: number, path: {}, value: any, index: number?)
		local replica = GetInternalReplica(id)
		if replica == nil then return end
		ReplicationFlag = true
		local success, msg = pcall(replica.TableInsert, replica, path, value, index)
		ReplicationFlag = false
		if success ~= true then
			--error(`[{script.Name}]: Error while updating replica:\n{replica:Identify()}\n` .. msg)
		end
	end)

	RemoteTableRemove.OnClientEvent:Connect(function(id: number, path: {}, index: number)
		local replica = GetInternalReplica(id)
		if replica == nil then return end
		ReplicationFlag = true
		local success, msg = pcall(replica.TableRemove, replica, path, index)
		ReplicationFlag = false
		if success ~= true then
			--error(`[{script.Name}]: Error while updating replica:\n{replica:Identify()}\n` .. msg)
		end
	end)

	RemoteWrite.OnClientEvent:Connect(function(id: number, fn_id: number, ...)
		local replica = GetInternalReplica(id)
		if replica == nil then return end
		local fn_name = replica.write_lib[fn_id].Name
		ReplicationFlag = true
		local success, msg = pcall(replica.Write, replica, fn_name, ...)
		ReplicationFlag = false
		if success ~= true then
			--error(`[{script.Name}]: Error while updating replica:\n{replica:Identify()}\n` .. msg)
		end
	end)

	local function RemoteSignalHandle(id: number, ...)
		local replica = GetInternalReplica(id)
		if replica == nil then return end
		replica.OnClientEvent:Fire(...)
	end

	RemoteSignal.OnClientEvent:Connect(function(id: number, ...)
		RemoteSignalHandle(id, ...)
	end)
	RemoteSignalUnreliable.OnClientEvent:Connect(function(id: number, ...)
		RemoteSignalHandle(id, ...)
	end)

	RemoteParent.OnClientEvent:Connect(function(id: number, parent_id: number)

		local replica = GetInternalReplica(id)
		if replica == nil then return end
		local old_parent = replica.Parent
		local new_parent = GetInternalReplica(parent_id)
		if new_parent == nil then return end

		old_parent.Children[replica] = nil
		new_parent.Children[replica] = true
		replica.Parent = new_parent
		replica.self_creation[4] = parent_id

		if BindReplicas[old_parent.Id] ~= nil and Replicas[parent_id] ~= nil then
			-- Replica streaming in:
			ReplicaFromBindBuffer(replica)
		elseif Replicas[old_parent.Id] ~= nil and BindReplicas[parent_id] ~= nil then
			-- Replica streaming out:
			ReplicaToBindBuffer(replica)
		end

	end)

	RemoteCreate.OnClientEvent:Connect(function(creation: {}, root_id: number?) -- (creation) or ({creation, ...})

		local announce_buffer = {} -- {replica, ...} -- Announce these

		BreadthCreationSort(creation, root_id, function(id: number, self_creation: {}) -- self_creation = {token, tags, data, parent_id, write_module}

			local parent_id = self_creation[4]
			local replica = ReplicaNew(id, self_creation)
			local is_bind_buffered = false

			if parent_id == 0 then -- Top replica

				if replica.Tags[BIND_TAG] == true then
					local bound_instance = BindInstances[id]
					replica.BoundInstance = bound_instance

					if bound_instance == nil then
						is_bind_buffered = true
					end
				end

			elseif BindReplicas[parent_id] ~= nil then

				is_bind_buffered = true

			end

			if is_bind_buffered == true then

				BindReplicas[id] = replica

			else

				local token = replica.Token
				local token_replicas = TokenReplicas[token]

				if token_replicas == nil then
					token_replicas = {}
					TokenReplicas[token] = token_replicas
				end

				token_replicas[replica] = true
				Replicas[id] = replica

				table.insert(announce_buffer, replica)

			end

		end)

		for _, replica in ipairs(announce_buffer) do
			local listeners = NewReplicaListeners[replica.Token]
			if listeners ~= nil then
				listeners:Fire(replica)
			end
		end

	end)

	RemoteBind.OnClientEvent:Connect(function(id: number)

		local replica = GetInternalReplica(id)
		if replica == nil then return end
		replica.Tags[BIND_TAG] = true

		local bound_instance = BindInstances[id]
		replica.BoundInstance = bound_instance

		if bound_instance == nil then
			ReplicaToBindBuffer(replica)
		end

	end)

	RemoteDestroy.OnClientEvent:Connect(function(id: number)
		local replica = GetInternalReplica(id)
		if replica == nil then return end
		DestroyReplica(replica)
	end)

	-- Replica bind system using CollectionService:

	local function OnBindInstanceAdded(instance: NumberValue)

		local id = instance.Value
		local bound_instance = instance.Parent
		BindInstances[id] = bound_instance

		local replica = BindReplicas[id]

		if replica ~= nil then
			replica.BoundInstance = bound_instance
			ReplicaFromBindBuffer(replica)
		end

	end

	local function OnBindInstanceRemoved(instance: NumberValue)

		local id = instance.Value
		BindInstances[id] = nil

		local replica = Replicas[id]

		if replica ~= nil then
			ReplicaToBindBuffer(replica)
		end

	end

	CollectionService:GetInstanceAddedSignal(CS_TAG):Connect(function(instance: NumberValue)
		if instance:IsA("NumberValue") == true then
			OnBindInstanceAdded(instance)
		end
	end)

	CollectionService:GetInstanceRemovedSignal(CS_TAG):Connect(function(instance: NumberValue)
		if instance:IsA("NumberValue") == true then
			OnBindInstanceRemoved(instance)
		end
	end)

	for _, instance: NumberValue in pairs(CollectionService:GetTagged(CS_TAG)) do
		if instance:IsA("NumberValue") == true then
			OnBindInstanceAdded(instance)
		end
	end

	return Replica
end