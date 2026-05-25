--!strict
--!optimize 2

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--[[ Dependencies ]]--
local Helpers = require(script.Parent.Helpers)
local Signal = require(game:GetService("ReplicatedFirst"):FindFirstChild("Signal", true))

--[[ Typing ]]--
type CallbackList = { any }

local function waitForChildStrict(parent: Instance, childName: string): Instance
	local child = parent:WaitForChild(childName, math.huge)
	if child == nil then
		error("cant find '" .. childName .. "' under " .. parent:GetFullName() .. "\n  Traceback:\n" .. debug.traceback(),2)
	end
	return child
end

local function getRemotesFolder(): Instance
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", math.huge)
	if remotesFolder == nil then
		error("ReplicatedStorage.Remotes not found.\n  Traceback:\n" .. debug.traceback(), 2)
	end
	return remotesFolder
end

export type Remote = {
	_Name: string,
	_Rate: number,
	_RateLimitStart: boolean,
	_RateLimitReach: boolean,
	_Remote: Instance?,
	_Sent: RemoteEvent?,
	_Receive: RemoteEvent?,
	_CallBack: any?,
	_CallBackType: { [string]: { any } }?,
	_serverSentConnection: RBXScriptConnection?,
	_clientReceiveConnection: RBXScriptConnection?,
	RateLimit: number,
	RateLimitTime: number,
	TimeOut: number?,
	Receive: any,
	Fire: ((self: Remote, ...any) -> ...any)?,
	FireTo: ((self: Remote, players: { Player }, ...any) -> ())?,
	FireAll: ((self: Remote, ...any) -> ...any)?,
	FireAllExcept: ((self: Remote, exceptions: { Player }, ...any) -> ())?,
	FireDistance: ((self: Remote, plr: Player, distance: number?, ...any) -> ())?,
	Invoke: ((self: Remote, ...any) -> ...any)?,
	CallBack: ((self: Remote, cb: any) -> any)?,
	Once: ((self: Remote, cb: any) -> ())?,
	GetCallBack: ((self: Remote, ...any) -> any)?,
	Set: ((self: Remote, info: { [string]: any }) -> ())?,
	Disconnect: ((self: Remote) -> ())?,
}

export type ShortcutsScript = Instance & {
	RemoteConnection: RemoteEvent,
	UnreliableRemoteConnection: RemoteEvent,
}

type Request = {
	Remote: any,
	Data: { n: number, [number]: any },
}

type CallbackRegistration = {
	Callback: any,
	Connection: any,
}

--[[
	A networking + bindable event/function module made with tables and two networking instances (no bindableevent instances; they're technically higher compute to spam) that mimics robloxs api.
	(RemoteEvent, UnreliableRemoteEvent, RemoteFunction, UnreliableRemoteFunction, BindableEvent, BindableFunction)
	All endpoints are cached by name, callbacks run through error catching wrappers, network fires are batched on RunService.PostSimulation, and request/response calls get built-in rate limits (& timeouts), with a healthy default of 60/s.

	Every constructor accepts an optional table as a second arg to S.DataHandler(): { RateLimit = 60, RateLimitTime = 1, TimeOut = 3 } (defaults shown). You can also call :Set({...}) later to mutate fields on the returned object.
	(TimeOut only on RemoteFunction/UnreliableRemoteFunction)

	S.RemoteEvent(name, ratelimits?)
	S.UnreliableRemoteEvent(name, ratelimits?)
	S.RemoteFunction(name, ratelimits?) | Made with a remote event firing twice instead of a remote function, once again, they're technically higher compute to spam.
	S.UnreliableRemoteFunction(name, ratelimits?) | Also made by firing UnreliableRemoteEvent twice. Double the networking packet loss chance, but it's got unreliable in the name! (TODO: FORK IF END UP IN TROUBLE)
	S.BindableEvent(name, ratelimits?) | made using tables
	S.BindableFunction(name, ratelimits?) | you won't belive what this is doing ദ്ദി(˵ •̀ ᴗ - ˵ ) ✧

	example how to use: S.RemoteEvent("helloThisIsMyEvent", { { RateLimit = 60, RateLimitTime = 1 } }):CallBack(function() (those rate limits are also the defaults for RemoteEvent's)

	S.RemoteEvent("helloThisIsMyEvent", { RateLimit = 60, RateLimitTime = 1 }):Fire()

	event/function:Fire(...) | Client -> server, or server -> a single client. (when on server player instance is your first argument always)
	event/function:Invoke(...) | Client -> server, or server -> a single client. (when on server player instance is your first argument always)
	event/function:FireTo({ playerA, playerB }, ...) | Server-only sends a :Fire to all player instances in the table you pass as the first argument.
	event/function:FireAll(...) | Server-only sends a :Fire to all player instances in the server.
	event/function:FireAllExcept({ playerA }, ...) | Server-only sends a :Fire to all player instances except the ones in the table you pass as the first argument. Players that are no longer in the server are silently ignored.
	event/function:FireDistance(sourcePlayer, distance?, ...) | Server-only at the time of firing on the server it sends a :Fire to all player instances that have their sourcePlayer.Character within the given distance of the 1st argument player.Character. (distance defaults to 20).
	event/function:CallBack(function(...) end) | Connects a listener. On reliable server events the first argument is the firing Player. :Disconnect to disconnect.
	event/function:Once(function(...) end) | Connects a listener that removes itself after the first fire.
	event/function:GetCallBack() | Returns the callback list table for this remote/bindable/reliable/unreliable name.
	event/function:Set({ RateLimit = 120, RateLimitTime = 1 }) | Updates RateLimit, RateLimitTime fields on the object after construction.
	event/function:Disconnect() | Clears callbacks, signal connections, and every entry for this endpoint with the same name! It's name (string) bound not object bound unfortunately. (TODO: might want to)
	unreliables work with the same api, however bindables run local listeners immediately (still rate limited as a good practice)

	Multiple callbacks per name are allowed.
	Errors raised inside any callback are surfaced with a traceback are task.spawn()'ed don't halt runtime.
	For function-style endpoints the first successful callback's return value is what the caller gets back; remaining callbacks still run for side effects.
	Function calls use generated request IDs plus coroutine.yield until a response arrives or the timeout (default 3 seconds) fires, and on timeout the call resumes with nil. (FireAll returns whatever responses arrived before the timeout.)
	InvokeAll doesn't exist. (TODO: should it?)
]]

--[[ RemoteBindableEvents ]]--
return function(Module: { [string]: any }, ShortcutsMain: ShortcutsScript)
	local IsServer: boolean = RunService:IsServer()

	--[[ Callback Stores ]]--
	local RemoteFunctionCallbacks: { [string]: CallbackList } = {}
	local ClientRemoteFunctionCallbacks: { [string]: CallbackList } = {}
	local RemoteFunctionRequests: { [number]: (...any) -> () } = {}
	local ServerInvokedRequests: { [number]: boolean } = {}
	local UnreliableRemoteFunctionCallbacks: { [string]: CallbackList } = {}
	local UnreliableRemoteFunctionRequests: { [number]: (...any) -> () } = {}

	--[[ Public Class Tables ]]--
	Module.UnreliableRemoteFunction = {}
	Module.BindableFunction = {}
	Module.RemoteFunction = {}

	--[[ Registries and Queues ]]--
	local RemotesRegistry: { [string]: Remote } = {}
	local UnreliableRemotesRegistry: { [string]: Remote } = {}
	local RemoteFunctionsRegistry: { [string]: Remote } = {}
	local UnreliableRemoteFunctionsRegistry: { [string]: Remote } = {}
	local BindableEventsRegistry: { [string]: Remote } = {}
	local BindableFunctionsRegistry: { [string]: Remote } = {}

	local RequestsList: { Request } = {}
	local FireAllRequestsList: { Request } = {}
	local FireAllFunctionRequestsList: { Request } = {}

	Module.BindableFunction.__index = Module.BindableFunction
	Module.RemoteFunction.__index = Module.RemoteFunction
	Module.UnreliableRemoteFunction.__index = Module.UnreliableRemoteFunction

	--[[ Event Callback Stores ]]--
	local RemoteEventsany: { [string]: CallbackList } = {}
	local UnreliableRemoteEventsany: { [string]: CallbackList } = {}
	local BindableEventsany: { [string]: CallbackList } = {}
	local BindableFunctionsany: { [string]: CallbackList } = {}
	local RemoteEventsSignals: { [string]: any } = {}
	local UnreliableRemoteEventsSignals: { [string]: any } = {}
	local BindableEventsSignals: { [string]: any } = {}
	local RemoteEventCallbackRegistrations: { [string]: { CallbackRegistration } } = {}
	local UnreliableRemoteEventCallbackRegistrations: { [string]: { CallbackRegistration } } = {}
	local BindableEventCallbackRegistrations: { [string]: { CallbackRegistration } } = {}
	local RemoteEventsConnections: { [string]: RBXScriptConnection } = {}
	local UnreliableRemoteEventsConnections: { [string]: RBXScriptConnection } = {}

	--[[ Registries ]]--
	Module.RemotesRegistry = RemotesRegistry
	Module.UnreliableRemotesRegistry = UnreliableRemotesRegistry
	Module.RemoteFunctionsRegistry = RemoteFunctionsRegistry
	Module.UnreliableRemoteFunctionsRegistry = UnreliableRemoteFunctionsRegistry
	Module.BindableEventsRegistry = BindableEventsRegistry
	Module.BindableFunctionsRegistry = BindableFunctionsRegistry
	Module.RemoteEventsany = RemoteEventsany
	Module.RemoteFunctionCallbacks = RemoteFunctionCallbacks
	Module.ClientRemoteFunctionCallbacks = ClientRemoteFunctionCallbacks
	Module.BindableEventsany = BindableEventsany
	Module.BindableFunctionsany = BindableFunctionsany

	--[[ Main ]]--
	local function ServerPostSimulationListener()
		for _, Request in ipairs(RequestsList) do
			local Remote: any = Request.Remote
			local Data = Request.Data
			Remote:FireClient(Data[1], table.unpack(Data, 2, Data.n))
		end
		table.clear(RequestsList)

		for _, Request in ipairs(FireAllRequestsList) do
			local Remote: any = Request.Remote
			local Data = Request.Data
			Remote:FireAllClients(table.unpack(Data, 1, Data.n))
		end
		table.clear(FireAllRequestsList)

		for _, Request in ipairs(FireAllFunctionRequestsList) do
			local Remote: any = Request.Remote
			local Data = Request.Data
			Remote:FireAllClients(table.unpack(Data, 1, Data.n))
		end
		table.clear(FireAllFunctionRequestsList)
	end

	local function ClientPostSimulationListener()
		for _, Request in ipairs(RequestsList) do
			local remote: any = Request.Remote
			if remote then
				remote:FireServer(table.unpack(Request.Data, 1, Request.Data.n))
			else
				warn("Skipped client request, missing remote in queue\n  Traceback:\n" .. debug.traceback())
			end
		end
		table.clear(RequestsList)
	end

	if IsServer then
		ShortcutsMain.RemoteConnection.OnServerEvent:Connect(
			function(_player: Player, OneWay: boolean, Name: string)
				local folder = getRemotesFolder()
				if OneWay then
					Helpers.createRemoteEvent(Name, folder)
				else
					Helpers.createRemoteFunction(Name, folder)
				end
			end
		)

		ShortcutsMain.UnreliableRemoteConnection.OnServerEvent:Connect(
			function(_player: Player, OneWay: boolean, Name: string)
				local folder = getRemotesFolder()
				if OneWay then
					Helpers.createUnreliableRemoteEvent(Name, folder)
				else
					Helpers.createUnreliableRemoteFunction(Name, folder)
				end
			end
		)

		RunService.PostSimulation:Connect(function()
			ServerPostSimulationListener()
		end)
	else
		RunService.PostSimulation:Connect(function()
			ClientPostSimulationListener()
		end)
	end

	--[[ Queue Helpers ]]--
	local function queueFire(Remote: any, ...: any)
		table.insert(RequestsList, {
			Remote = Remote,
			Data = table.pack(...),
		})
	end

	local function queueFireAll(Remote: any, ...: any)
		table.insert(FireAllRequestsList, {
			Remote = Remote,
			Data = table.pack(...),
		})
	end

	local function queueFireAllFunctions(Remote: any, ...: any)
		table.insert(FireAllFunctionRequestsList, {
			Remote = Remote,
			Data = table.pack(...),
		})
	end

	--[[ Shared Utilities ]]--
	local function rateLimit(self: Remote): boolean
		if self._RateLimitReach then
			return false
		end

		if not self._RateLimitStart then
			self._RateLimitStart = true
			task.delay(self.RateLimitTime, function()
				self._Rate = 0
				self._RateLimitReach = false
				self._RateLimitStart = false
			end)
		end

		if self._Rate == self.RateLimit then
			self._RateLimitReach = true
			return false
		else
			self._Rate = self._Rate + 1
		end

		return true
	end

	local function setFields(self: Remote, SetInfo: { [string]: any })
		Helpers.setFields(self :: any, SetInfo)
	end

	local function getFromRegistry(Name: string, TableName: string): Remote?
		Helpers.yieldTilObject(Name, Module[TableName])
		return Module[TableName][Name]
	end

	local function getCallBack(NameOrSelf: any, CallBackType: { [string]: any }?): any?
		if type(NameOrSelf) == "table" then
			local selfRemote: Remote = NameOrSelf
			local any = selfRemote._CallBackType or CallBackType
			if any then
				return any[selfRemote._Name]
			end
			return nil
		end

		if CallBackType then
			return CallBackType[NameOrSelf]
		end

		return nil
	end
	
	--[[ Bindable and Remote, Reliable and Unreliable Event callback handling. ]]--
	local function getOrCreateSignal(signalStore: { [string]: any }, eventName: string): any
		local signalObject = signalStore[eventName]
		if signalObject then
			return signalObject
		end
		local newSignal = Signal.New()
		signalStore[eventName] = newSignal
		return newSignal
	end

	local function fireEventSignal(eventName: string, signalStore: { [string]: any }, ...: any): ()
		local signalObject = signalStore[eventName]
		if signalObject then
			signalObject:Fire(...)
		end
	end

	local function addEventCallback(callbackStore: { [string]: any }, signalStore: { [string]: any }, registrationStore: { [string]: { CallbackRegistration } }, eventName: string, callback: any): ()
		callbackStore[eventName] = callbackStore[eventName] or {}
		table.insert(callbackStore[eventName], callback)

		local signalObject = getOrCreateSignal(signalStore, eventName)
		registrationStore[eventName] = registrationStore[eventName] or {}
		table.insert(registrationStore[eventName], {
			Callback = callback,
			Connection = signalObject:Connect(function(...: any)
				Helpers.protectedCallback(eventName, callback, ...)
			end),
		})
	end

	local function removeEventCallback(
		callbackStore: { [string]: any },
		signalStore: { [string]: any },
		registrationStore: { [string]: { CallbackRegistration } },
		eventName: string,
		callback: any
	): ()
		local any = callbackStore[eventName]
		if any then
			for i = #any, 1, -1 do
				if any[i] == callback then
					table.remove(any, i)
					break
				end
			end
			if #any == 0 then
				callbackStore[eventName] = nil
			end
		end

		local registrations = registrationStore[eventName]
		if registrations then
			for i = #registrations, 1, -1 do
				if registrations[i].Callback == callback then
					local connection = registrations[i].Connection
					if connection and type(connection.Disconnect) == "function" then
						local disconnectMethod = connection.Disconnect :: any
						disconnectMethod(connection)
					end
					table.remove(registrations, i)
					break
				end
			end
			if #registrations == 0 then
				registrationStore[eventName] = nil
			end
		end

		if callbackStore[eventName] == nil and registrationStore[eventName] == nil then
			signalStore[eventName] = nil
		end
	end

	local function disconnectEventConnections(connectionEntries: { CallbackRegistration }?): ()
		if not connectionEntries then
			return
		end
		for _, registration in ipairs(connectionEntries) do
			local connection = registration.Connection
			if connection and type(connection.Disconnect) == "function" then
				local disconnectMethod = connection.Disconnect :: any
				disconnectMethod(connection)
			end
		end
	end

	local function AddRemoteEventCallback(NameOrSelf: any, CallBack: any)
		local Name: string
		if type(NameOrSelf) == "table" then
			Name = NameOrSelf._Name
		else
			Name = NameOrSelf
		end

		addEventCallback(
			RemoteEventsany,
			RemoteEventsSignals,
			RemoteEventCallbackRegistrations,
			Name,
			CallBack
		)
	end

	local function AddUnreliableRemoteEventCallback(NameOrSelf: any, CallBack: any)
		local Name: string
		if type(NameOrSelf) == "table" then
			Name = NameOrSelf._Name
		else
			Name = NameOrSelf
		end

		addEventCallback(
			UnreliableRemoteEventsany,
			UnreliableRemoteEventsSignals,
			UnreliableRemoteEventCallbackRegistrations,
			Name,
			CallBack
		)
	end

	local function BindableCallBackDisconnect(self: Remote)
		if not self._Name then
			return
		end

		local targetCallback = self._CallBack
		if targetCallback == nil then
			return
		end

		removeEventCallback(
			BindableEventsany,
			BindableEventsSignals,
			BindableEventCallbackRegistrations,
			self._Name,
			targetCallback
		)

		self._CallBack = nil
	end

	local function BindableCallBack(self: Remote, CallBack: any): Remote
		addEventCallback(
			BindableEventsany,
			BindableEventsSignals,
			BindableEventCallbackRegistrations,
			self._Name,
			CallBack
		)

		local handle: Remote = {
			_Name = self._Name,
			_Rate = 0,
			_RateLimitStart = false,
			_RateLimitReach = false,
			RateLimit = self.RateLimit,
			RateLimitTime = self.RateLimitTime,
			Receive = nil,
			_CallBack = CallBack,
			Disconnect = BindableCallBackDisconnect,
		}
		return handle
	end

	function Module.RemoteFunction:CallBack(CallBack: any): any
		local selfRemote: Remote = self
		if IsServer then
			RemoteFunctionCallbacks[selfRemote._Name] = RemoteFunctionCallbacks[selfRemote._Name] or {}
			table.insert(RemoteFunctionCallbacks[selfRemote._Name], CallBack)
			return RemoteFunctionCallbacks[selfRemote._Name]
		else
			ClientRemoteFunctionCallbacks[selfRemote._Name] = ClientRemoteFunctionCallbacks[selfRemote._Name] or {}
			table.insert(ClientRemoteFunctionCallbacks[selfRemote._Name], CallBack)
			return ClientRemoteFunctionCallbacks[selfRemote._Name]
		end
	end

	function Module.UnreliableRemoteFunction:CallBack(CallBack: any): any
		local selfRemote: Remote = self
		UnreliableRemoteFunctionCallbacks[selfRemote._Name] = UnreliableRemoteFunctionCallbacks[selfRemote._Name] or {}
		table.insert(UnreliableRemoteFunctionCallbacks[selfRemote._Name], CallBack)
		return UnreliableRemoteFunctionCallbacks[selfRemote._Name]
	end

	--[[ Disconnect Utilities ]]--
	local function disconnectFromMaps(
		self: Remote,
		callbacks: { [string]: any }?,
		connections: { [string]: RBXScriptConnection }?,
		registry: { [string]: Remote }?,
		signals: { [string]: any }?,
		registrationStore: { [string]: { CallbackRegistration } }?
	)
		if not self._Name then
			return
		end

		if callbacks and callbacks[self._Name] then
			callbacks[self._Name] = nil
		end

		if registrationStore and registrationStore[self._Name] then
			disconnectEventConnections(registrationStore[self._Name])
			registrationStore[self._Name] = nil
		end

		if signals and signals[self._Name] then
			signals[self._Name] = nil
		end

		if connections and connections[self._Name] then
			connections[self._Name]:Disconnect()
			connections[self._Name] = nil
		end

		if registry and registry[self._Name] == self then
			registry[self._Name] = nil
		end
	end

	local function RemoteEventDisconnect(self: Remote)
		disconnectFromMaps(
			self,
			RemoteEventsany,
			RemoteEventsConnections,
			RemotesRegistry,
			RemoteEventsSignals,
			RemoteEventCallbackRegistrations
		)
	end

	local function UnreliableRemoteEventDisconnect(self: Remote)
		disconnectFromMaps(
			self,
			UnreliableRemoteEventsany,
			UnreliableRemoteEventsConnections,
			UnreliableRemotesRegistry,
			UnreliableRemoteEventsSignals,
			UnreliableRemoteEventCallbackRegistrations
		)
	end

	local function BindableEventDisconnect(self: Remote)
		disconnectFromMaps(
			self,
			BindableEventsany,
			nil,
			BindableEventsRegistry,
			BindableEventsSignals,
			BindableEventCallbackRegistrations
		)
	end

	local function disconnectFunction(self: Remote, callbacks: { [string]: any }, registry: { [string]: Remote })
		if not self._Name then
			return
		end

		if callbacks[self._Name] then
			callbacks[self._Name] = nil
		end

		if self._serverSentConnection then
			self._serverSentConnection:Disconnect()
			self._serverSentConnection = nil
		end

		if self._clientReceiveConnection then
			self._clientReceiveConnection:Disconnect()
			self._clientReceiveConnection = nil
		end

		if registry[self._Name] == self then
			registry[self._Name] = nil
		end
	end

	local function RemoteFunctionDisconnect(self: Remote)
		disconnectFunction(self, RemoteFunctionCallbacks, RemoteFunctionsRegistry)
	end

	local function UnreliableRemoteFunctionDisconnect(self: Remote)
		disconnectFunction(self, UnreliableRemoteFunctionCallbacks, UnreliableRemoteFunctionsRegistry)
	end

	local function BindableFunctionDisconnect(self: Remote)
		if not self._Name then
			return
		end

		if BindableFunctionsany[self._Name] then
			BindableFunctionsany[self._Name] = nil
		end

		if BindableFunctionsRegistry[self._Name] == self then
			BindableFunctionsRegistry[self._Name] = nil
		end
	end

	--[[ Event Listeners ]]--
	local function ReceiveListener(ID: number, ...: any)
		if not IsServer then
			if ServerInvokedRequests[ID] then
				ServerInvokedRequests[ID] = nil
				return
			end
		end

		local EventListener: any = RemoteFunctionRequests[ID] or UnreliableRemoteFunctionRequests[ID]
		local args = table.pack(...)
		if type(EventListener) ~= "function" then
			return
		else
			if RemoteFunctionRequests[ID] then
				RemoteFunctionRequests[ID] = nil
			elseif UnreliableRemoteFunctionRequests[ID] then
				UnreliableRemoteFunctionRequests[ID] = nil
			end
		end
		(EventListener :: any)(table.unpack(args, 1, args.n))
	end
	
	local function SentListener(self: Remote, plr: Player, ID: number, ...: any)
		local cbs = RemoteFunctionCallbacks[self._Name] or UnreliableRemoteFunctionCallbacks[self._Name]
		if not cbs or #cbs == 0 then
			local eventListener = RemoteFunctionRequests[ID]
			if eventListener and type(eventListener) == "function" then
				(eventListener :: any)(plr, ...)
				return
			end
			warn("Missing callback for RemoteFunction '" .. self._Name .. "'\n  Traceback:\n" .. debug.traceback())
			queueFire(self._Receive, plr, ID)
			return
		end

		local firstResult: { n: number, [number]: any }? = nil
		local args = table.pack(...)
		for i, cb in ipairs(cbs) do
			local results: { n: number, [number]: any } = table.pack()
			local callbackFn = cb :: any
			local ok = xpcall(function()
				results = table.pack(callbackFn(plr, table.unpack(args, 1, args.n)))
			end, function(err: any)
				local errStr = tostring(err)
				task.spawn(function()
					error("Error in RemoteFunction '" .. self._Name .. "' callback " .. tostring(i) .. ":\n" .. debug.traceback(errStr, 2))
				end)
			end)
			if ok and i == 1 then
				firstResult = results
			end
		end

		if firstResult then
			queueFire(self._Receive, plr, ID, table.unpack(firstResult, 1, firstResult.n))
		end
	end

	local function ClientSentListener(self: Remote, ID: number, ...: any)
		if ServerInvokedRequests[ID] then
			return
		end
		ServerInvokedRequests[ID] = true

		local cbs = ClientRemoteFunctionCallbacks[self._Name]
		if not cbs or #cbs == 0 then
			task.spawn(function()
				error("Missing client callback for RemoteFunction '" .. self._Name .. "'\n  Traceback:\n" .. debug.traceback())
			end)
			queueFire(self._Receive, ID)
			return
		end

		local firstResult: { n: number, [number]: any }? = nil
		local args = table.pack(...)
		for i, cb in ipairs(cbs) do
			local results: { n: number, [number]: any } = table.pack()
			local callbackFn = cb :: any
			local ok = xpcall(function()
				results = table.pack(callbackFn(table.unpack(args, 1, args.n)))
			end, function(err: any)
				local errStr = tostring(err)
				task.spawn(function()
					error("Error in client RemoteFunction '" .. self._Name .. "' callback " .. tostring(i) .. ":\n" .. debug.traceback(errStr, 2))
				end)
			end)
			if ok and i == 1 then
				firstResult = results
			end
		end

		if firstResult then
			queueFire(self._Receive, ID, table.unpack(firstResult, 1, firstResult.n))
		else
			queueFire(self._Receive, ID)
		end
	end

	local function RemoteEventListener(Name: string, Remote: RemoteEvent)
		if IsServer then
			RemoteEventsConnections[Name] = Remote.OnServerEvent:Connect(function(plr: Player, ...: any) fireEventSignal(Name, RemoteEventsSignals, plr, ...) end)
		else
			RemoteEventsConnections[Name] = Remote.OnClientEvent:Connect(function(...: any) fireEventSignal(Name, RemoteEventsSignals, ...) end)
		end
	end

	local function UnreliableRemoteEventListener(Name: string, Remote: UnreliableRemoteEvent)
		if IsServer then
			UnreliableRemoteEventsConnections[Name] = Remote.OnServerEvent:Connect(function(plr: Player, ...: any) fireEventSignal(Name, UnreliableRemoteEventsSignals, plr, ...) end)
		else
			UnreliableRemoteEventsConnections[Name] = Remote.OnClientEvent:Connect(function(...: any) fireEventSignal(Name, UnreliableRemoteEventsSignals, ...) end)
		end
	end

	local function RemoteOnce(self: Remote, CallBack: any)
		local function onceCallback(...: any)
			removeEventCallback(
				RemoteEventsany,
				RemoteEventsSignals,
				RemoteEventCallbackRegistrations,
				self._Name,
				onceCallback
			)
			local packedArgs = table.pack(...)
			task.spawn(function()
				(CallBack :: any)(table.unpack(packedArgs, 1, packedArgs.n))
			end)
		end
		AddRemoteEventCallback(self._Name, onceCallback)
	end

	local function UnreliableRemoteOnce(self: Remote, CallBack: any)
		local function onceCallback(...: any)
			removeEventCallback(
				UnreliableRemoteEventsany,
				UnreliableRemoteEventsSignals,
				UnreliableRemoteEventCallbackRegistrations,
				self._Name,
				onceCallback
			)
			local packedArgs = table.pack(...)
			task.spawn(function()
				(CallBack :: any)(table.unpack(packedArgs, 1, packedArgs.n))
			end)
		end
		AddUnreliableRemoteEventCallback(self._Name, onceCallback)
	end

	--[[ Fire APIs ]]--
	local function RemoteFire(self: Remote, ...: any)
		if not rateLimit(self) then
			return
		end

		if not IsServer and not self._Remote then
			local packedArgs = table.pack(...)
			task.spawn(function()
				local start = os.clock()
				while not self._Remote and os.clock() - start < 10 do
					task.wait()
				end

				if self._Remote then
					queueFire(self._Remote, table.unpack(packedArgs, 1, packedArgs.n))
				else
					warn("RemoteEvent '" .. self._Name .. "' is still not ready after 10 seconds so im dropping the client fire\n  Traceback:\n" .. debug.traceback())
				end
			end)
			return
		end

		queueFire(self._Remote, ...)
	end

	local function RemoteFireTo(self: Remote, PlayerArray: { Player }, ...: any)
		if not IsServer or not rateLimit(self) then
			return
		end
		for _, plr in ipairs(PlayerArray) do
			queueFire(self._Remote, plr, ...)
		end
	end

	local function RemoteFireAll(self: Remote, ...: any)
		if not IsServer or not rateLimit(self) then
			return
		end
		queueFireAll(self._Remote, ...)
	end

	local function RemoteFireAllExcept(self: Remote, ExceptionArray: { Player }, ...: any)
		if not IsServer or not rateLimit(self) then
			return
		end
		local exceptionSet: { [Player]: true } = {}
		for _, exceptionPlr in ipairs(ExceptionArray) do
			exceptionSet[exceptionPlr] = true
		end
		for _, plr in ipairs(Players:GetPlayers()) do
			if not exceptionSet[plr] then
				queueFire(self._Remote, plr, ...)
			end
		end
	end

	local function RemoteFireDistance(self: Remote, plr: Player, RenderDistance: number?, ...: any)
		if not IsServer or not rateLimit(self) then
			return
		end

		local chr: Model = (plr.Character and plr.Character.Parent and plr.Character) or plr.CharacterAdded:Wait()
		local distance: number = RenderDistance or 20
		local RenderPlayers = Helpers.getNearPlayer(chr, distance)
		for _, RenderPlayer in ipairs(RenderPlayers) do
			queueFire(self._Remote, RenderPlayer, ...)
		end
	end

	local function BindableFire(self: Remote, ...: any)
		if not rateLimit(self) then
			return
		end

		fireEventSignal(self._Name, BindableEventsSignals, ...)
	end

	local function BindableInvoke(self: Remote, ...: any): any
		BindableFire(self, ...)
		return nil
	end

	--[[ Bindable and Remote, Reliable and Unreliable construction APIs. ]]--
	function Module.BindableFunction.new(Name: string, Info: Helpers.ObjectInfo?): Remote
		if BindableFunctionsRegistry[Name] then
			return BindableFunctionsRegistry[Name]
		end
		local info: Helpers.ObjectInfo = Info or {}

		local base = Helpers.createObject(Name, info)
		local self: Remote = base :: any
		setmetatable(self :: any, Module.BindableFunction)
		self.TimeOut = info.TimeOut or 3
		self.Receive = nil
		self.Disconnect = BindableFunctionDisconnect

		BindableFunctionsRegistry[Name] = self
		return self
	end

	function Module.RemoteFunction.new(Name: string, Info: Helpers.ObjectInfo?): Remote
		if RemoteFunctionsRegistry[Name] then
			return RemoteFunctionsRegistry[Name]
		end
		local info: Helpers.ObjectInfo = Info or {}

		local base = Helpers.createObject(Name, info)
		local self: Remote = base :: any
		setmetatable(self :: any, Module.RemoteFunction)
		self.TimeOut = info.TimeOut or 3

		local remotesFolder = getRemotesFolder()
		local existing = remotesFolder:FindFirstChild(Name)
		local Folder: Instance
		if existing then
			Folder = existing
		else
			if IsServer then
				Helpers.createRemoteFunction(Name, remotesFolder)
			else
				queueFire(ShortcutsMain.RemoteConnection, false, Name)
			end
			Folder = waitForChildStrict(remotesFolder, Name)
		end

		local sentChild = waitForChildStrict(Folder, "Sent")
		local receiveChild = waitForChildStrict(Folder, "Receive")
		assert(sentChild:IsA("RemoteEvent"), "RemoteFunction Sent has to be a RemoteEvent")
		assert(receiveChild:IsA("RemoteEvent"), "RemoteFunction Receive has to be a RemoteEvent")
		local sent: RemoteEvent = sentChild
		local receive: RemoteEvent = receiveChild
		self._Sent = sent
		self._Receive = receive

		self._serverSentConnection = nil
		self._clientReceiveConnection = nil

		if IsServer then
			self._serverSentConnection = sent.OnServerEvent:Connect(
				function(plr: Player, ID: number, ...: any)
					SentListener(self, plr, ID, ...)
				end
			)
			self._clientReceiveConnection = receive.OnServerEvent:Connect(
				function(plr: Player, ID: number, ...: any)
					ReceiveListener(ID, plr, ...)
				end
			)
		else
			self._serverSentConnection = sent.OnClientEvent:Connect(function(ID: number, ...: any)
				ClientSentListener(self, ID, ...)
			end)
			self._clientReceiveConnection = receive.OnClientEvent:Connect(
				function(ID: number, ...: any)
					ReceiveListener(ID, ...)
				end
			)
		end

		self.Disconnect = RemoteFunctionDisconnect

		RemoteFunctionsRegistry[Name] = self
		return self
	end

	function Module.UnreliableRemoteFunction.new(Name: string, Info: Helpers.ObjectInfo?): Remote
		if UnreliableRemoteFunctionsRegistry[Name] then
			return UnreliableRemoteFunctionsRegistry[Name]
		end
		local info: Helpers.ObjectInfo = Info or {}

		local base = Helpers.createObject(Name, info)
		local self: Remote = base :: any
		setmetatable(self :: any, Module.UnreliableRemoteFunction)
		self.TimeOut = info.TimeOut or 3

		local remotesFolder = getRemotesFolder()
		local existing = remotesFolder:FindFirstChild(Name)
		local Folder: Instance
		if existing then
			Folder = existing
		else
			if IsServer then
				Helpers.createUnreliableRemoteFunction(Name, remotesFolder)
			else
				queueFire(ShortcutsMain.UnreliableRemoteConnection, false, Name)
			end
			Folder = waitForChildStrict(remotesFolder, Name)
		end

		local sentChild = waitForChildStrict(Folder, "Sent")
		local receiveChild = waitForChildStrict(Folder, "Receive")
		assert(sentChild:IsA("UnreliableRemoteEvent") or sentChild:IsA("RemoteEvent"), "Sent has to be a remote event")
		assert(receiveChild:IsA("UnreliableRemoteEvent") or receiveChild:IsA("RemoteEvent"), "Receive has to be a remote event")
		local sent: any = sentChild
		local receive: any = receiveChild
		self._Sent = sent
		self._Receive = receive

		self._serverSentConnection = nil
		self._clientReceiveConnection = nil

		if IsServer then
			self._serverSentConnection = sent.OnServerEvent:Connect(
				function(plr: Player, ID: number, ...: any)
					SentListener(self, plr, ID, ...)
				end
			)
		else
			self._clientReceiveConnection = receive.OnClientEvent:Connect(
				function(ID: number, ...: any)
					ReceiveListener(ID, ...)
				end
			)
		end

		self.Disconnect = UnreliableRemoteFunctionDisconnect

		UnreliableRemoteFunctionsRegistry[Name] = self
		return self
	end

	function Module.RemoteFunction:GetCallBack(): any?
		local selfRemote: Remote = self
		return RemoteFunctionCallbacks[selfRemote._Name]
	end

	function Module.UnreliableRemoteFunction:GetCallBack(): any?
		local selfRemote: Remote = self
		return UnreliableRemoteFunctionCallbacks[selfRemote._Name]
	end

	function Module.RemoteFunction:Set(SetInfo: { [string]: any })
		setFields(self, SetInfo)
	end

	function Module.UnreliableRemoteFunction:Set(SetInfo: { [string]: any })
		setFields(self, SetInfo)
	end

	setmetatable(Module.RemoteFunction, {
		__call = function(_, Name: string, Info: Helpers.ObjectInfo?): Remote
			return Module.RemoteFunction.new(Name, Info)
		end,
	})

	setmetatable(Module.UnreliableRemoteFunction, {
		__call = function(_, Name: string, Info: Helpers.ObjectInfo?): Remote
			return Module.UnreliableRemoteFunction.new(Name, Info)
		end,
	})

	--[[ Event Constructors ]]--
	function Module.UnreliableRemoteEvent(Name: string, Info: Helpers.ObjectInfo?): Remote
		if UnreliableRemotesRegistry[Name] then
			return UnreliableRemotesRegistry[Name]
		end
		local info: Helpers.ObjectInfo = Info or {}

		local base = Helpers.createObject(Name, info)
		local self: Remote = base :: any

		local remotesFolder = getRemotesFolder()
		local existingRemote = remotesFolder:FindFirstChild(Name)

		if existingRemote then
			self._Remote = existingRemote
			if not UnreliableRemoteEventsConnections[Name] then
				UnreliableRemoteEventListener(Name, existingRemote :: UnreliableRemoteEvent)
			end
		else
			if IsServer then
				local created = Helpers.createUnreliableRemoteEvent(Name, remotesFolder)
				self._Remote = created
				if not UnreliableRemoteEventsConnections[Name] then
					UnreliableRemoteEventListener(Name, created :: UnreliableRemoteEvent)
				end
			else
				task.spawn(function()
					ShortcutsMain.UnreliableRemoteConnection:FireServer(true, Name)
					local remote = waitForChildStrict(remotesFolder, Name)
					self._Remote = remote
					if not UnreliableRemoteEventsConnections[Name] then
						UnreliableRemoteEventListener(Name, remote :: UnreliableRemoteEvent)
					end
				end)
			end
		end

		self.Fire = RemoteFire
		self.FireTo = RemoteFireTo
		self.FireAll = RemoteFireAll
		self.FireAllExcept = RemoteFireAllExcept
		self.FireDistance = RemoteFireDistance
		self.CallBack = AddUnreliableRemoteEventCallback :: any
		self.Once = UnreliableRemoteOnce
		self._CallBackType = UnreliableRemoteEventsany
		self.GetCallBack = getCallBack :: any
		self.Set = setFields
		self.Disconnect = UnreliableRemoteEventDisconnect

		UnreliableRemotesRegistry[Name] = self
		return self
	end

	function Module.RemoteEvent(Name: string, Info: Helpers.ObjectInfo?): Remote
		if RemotesRegistry[Name] then
			return RemotesRegistry[Name]
		end
		local info: Helpers.ObjectInfo = Info or {}

		local base = Helpers.createObject(Name, info)
		local self: Remote = base :: any

		local remotesFolder = getRemotesFolder()
		local existingRemote = remotesFolder:FindFirstChild(Name)

		if existingRemote then
			self._Remote = existingRemote
			if not RemoteEventsConnections[Name] then
				RemoteEventListener(Name, existingRemote :: RemoteEvent)
			end
		else
			if IsServer then
				local created = Helpers.createRemoteEvent(Name, remotesFolder)
				self._Remote = created
				if not RemoteEventsConnections[Name] then
					RemoteEventListener(Name, created :: RemoteEvent)
				end
			else
				task.spawn(function()
					ShortcutsMain.RemoteConnection:FireServer(true, Name)
					local remote = waitForChildStrict(remotesFolder, Name)
					self._Remote = remote
					if not RemoteEventsConnections[Name] then
						RemoteEventListener(Name, remote :: RemoteEvent)
					end
				end)
			end
		end

		self.Fire = RemoteFire
		self.FireTo = RemoteFireTo
		self.FireAll = RemoteFireAll
		self.FireAllExcept = RemoteFireAllExcept
		self.FireDistance = RemoteFireDistance
		self.CallBack = AddRemoteEventCallback :: any
		self.Once = RemoteOnce
		self._CallBackType = RemoteEventsany
		self.GetCallBack = getCallBack :: any
		self.Set = setFields
		self.Disconnect = RemoteEventDisconnect

		RemotesRegistry[Name] = self
		return self
	end

	function Module.BindableEvent(Name: string, Info: Helpers.ObjectInfo?): Remote
		if BindableEventsRegistry[Name] then
			return BindableEventsRegistry[Name]
		end
		local info: Helpers.ObjectInfo = Info or {}

		local base = Helpers.createObject(Name, info)
		local self: Remote = base :: any

		self.Fire = BindableFire
		self.Invoke = BindableInvoke
		self.CallBack = BindableCallBack :: any
		self._CallBackType = BindableEventsany
		self.GetCallBack = getCallBack :: any
		self.Set = setFields
		self.Disconnect = BindableEventDisconnect

		BindableEventsRegistry[Name] = self
		return self
	end

	--[[ Exposed API ]]--
	function Module.GetRemoteEvent(Name: string): Remote?
		return getFromRegistry(Name, "RemotesRegistry")
	end

	function Module.GetUnreliableRemoteEvent(Name: string): Remote?
		return getFromRegistry(Name, "UnreliableRemotesRegistry")
	end

	function Module.GetRemoteFunction(Name: string): Remote?
		return getFromRegistry(Name, "RemoteFunctionsRegistry")
	end

	function Module.GetUnreliableRemoteFunction(Name: string): Remote?
		return getFromRegistry(Name, "UnreliableRemoteFunctionsRegistry")
	end

	function Module.GetBindableEvent(Name: string): Remote?
		return getFromRegistry(Name, "BindableEventsRegistry")
	end

	function Module.GetBindableFunction(Name: string): Remote?
		return getFromRegistry(Name, "BindableFunctionsRegistry")
	end

	--[[ Bindable Invoke ]]--
	local function invokeBindableCallbacks(self: Remote, label: string, ...: any): ...any
		if not rateLimit(self) then
			warn("Rate limit got reached for BindableFunction '" .. self._Name .. "' (" .. label .. ")\n  Traceback:\n" .. debug.traceback())
			return nil
		end

		local callbacks = BindableFunctionsany[self._Name]
		if not callbacks or #callbacks == 0 then
			warn("Callback not set for BindableFunction '" .. self._Name .. "'  anywhere (" .. label .. ")\n  Traceback:\n" .. debug.traceback())
			return nil
		end

		local packedArgs = table.pack(...)
		local firstResults: { n: number, [number]: any }? = nil

		for i, cb in ipairs(callbacks) do
			local results: { n: number, [number]: any } = table.pack()
			local callbackFn = cb :: any
			local ok = xpcall(function()
				results = table.pack(callbackFn(table.unpack(packedArgs, 1, packedArgs.n)))
			end, function(err: any)
				local errStr = tostring(err)
				task.spawn(function()
					error("Error in BindableFunction '" .. self._Name .. "' (" .. label .. ") callback #" .. tostring(i) .. ":\n" .. debug.traceback(errStr, 2))
				end)
			end)
			if ok and i == 1 then
				firstResults = results
			end
		end

		if firstResults then
			return table.unpack(firstResults, 1, firstResults.n)
		end
		return nil
	end

	function Module.BindableFunction:Fire(...: any): ...any
		return invokeBindableCallbacks(self, "Fire", ...)
	end

	function Module.BindableFunction:Invoke(...: any): ...any
		return invokeBindableCallbacks(self, "Invoke", ...)
	end

	function Module.BindableFunction:CallBack(CallBack: any): any
		local selfRemote: Remote = self
		BindableFunctionsany[selfRemote._Name] = BindableFunctionsany[selfRemote._Name]
			or {}
		table.insert(BindableFunctionsany[selfRemote._Name], CallBack)
		return BindableFunctionsany[selfRemote._Name]
	end

	function Module.BindableFunction:GetCallBack(): any?
		local selfRemote: Remote = self
		return BindableFunctionsany[selfRemote._Name]
	end

	function Module.BindableFunction:Set(SetInfo: { [string]: any })
		setFields(self, SetInfo)
	end

	setmetatable(Module.BindableFunction, {
		__call = function(_, Name: string, Info: Helpers.ObjectInfo?): Remote
			return Module.BindableFunction.new(Name, Info)
		end,
	})

	--[[ Remote Invoke ]]--
	local function invokeRemoteFunctionAsClient(self: Remote, label: string, ...: any): any
		if not rateLimit(self) then
			warn("Rate limit got reached for RemoteFunction '" .. self._Name .. "' (" .. label .. ")\n  Traceback:\n" .. debug.traceback())
			return nil
		end

		local callTraceback = debug.traceback(nil, 2)
		local Thread = coroutine.running()
		local ID = Helpers.generateNumbers()
		local Resume = false
		local timeoutSeconds: number = self.TimeOut or 3

		if IsServer then
			RemoteFunctionRequests[ID] = function(_player: Player, ...: any)
				Resume = true
				RemoteFunctionRequests[ID] = nil
				local args = table.pack(...)
				coroutine.resume(Thread, table.unpack(args, 1, args.n))
			end
		else
			RemoteFunctionRequests[ID] = function(...: any)
				Resume = true
				RemoteFunctionRequests[ID] = nil
				local args = table.pack(...)
				coroutine.resume(Thread, table.unpack(args, 1, args.n))
			end
		end

		task.delay(timeoutSeconds, function()
			if Resume then
				return
			end
			warn("RemoteFunction '" .. self._Name .. "' " .. label .. " has timed out after " .. tostring(timeoutSeconds) .. "s (ID: " .. tostring(ID) .. ")\n  Called from:\n" .. callTraceback)
			RemoteFunctionRequests[ID] = nil
			coroutine.resume(Thread, nil)
		end)

		task.spawn(function(...: any)
			queueFire(self._Sent, ID, ...)
		end, ...)

		return coroutine.yield()
	end

	function Module.RemoteFunction:Fire(...: any): any
		local selfRemote: Remote = self
		if not rateLimit(selfRemote) then
			warn("Rate limit got reached for RemoteFunction '" .. selfRemote._Name .. "'\n  Traceback:\n" .. debug.traceback())
			return nil
		end

		local callTraceback = debug.traceback(nil, 2)
		local Thread = coroutine.running()
		local ID = Helpers.generateNumbers()
		local Resume = false
		local timeoutSeconds: number = selfRemote.TimeOut or 3

		RemoteFunctionRequests[ID] = function(...: any)
			Resume = true
			RemoteFunctionRequests[ID] = nil
			local args = table.pack(...)
			coroutine.resume(Thread, table.unpack(args, 1, args.n))
		end

		task.delay(timeoutSeconds, function()
			if Resume then
				return
			end
			warn("RemoteFunction '" .. selfRemote._Name .. "' has timed out after " .. tostring(timeoutSeconds) .. "s (ID: " .. tostring(ID) .. ")\n  Called from:\n" .. callTraceback)
			RemoteFunctionRequests[ID] = nil
			coroutine.resume(Thread, nil)
		end)

		if IsServer then
			local args = { ... }
			local player = args[1]
			if typeof(player) == "Instance" and player:IsA("Player") then
				queueFire(selfRemote._Sent, player, ID, table.unpack(args, 2, #args))
			else
				task.spawn(function()
					if typeof(player) ~= "Instance" then
						error("not an Instance type")
					else
						error("not a Player type")
					end
				end)
				coroutine.resume(Thread, nil)
			end
		else
			queueFire(selfRemote._Sent, ID, ...)
		end

		return coroutine.yield()
	end

	function Module.RemoteFunction:FireAll(...: any): any
		local selfRemote: Remote = self
		if not IsServer then
			error("RemoteFunction:FireAll can only be called from the server ('" .. selfRemote._Name .. "')\n  Traceback:\n" .. debug.traceback())
		end

		if not rateLimit(selfRemote) then
			warn("Rate limit got reached for RemoteFunction '" .. selfRemote._Name .. "' (FireAll)\n  Traceback:\n" .. debug.traceback())
			return nil
		end

		local callTraceback = debug.traceback(nil, 2)
		local Thread = coroutine.running()
		local ID = Helpers.generateNumbers()
		local results: { [Player]: { n: number, [number]: any } } = {}
		local players = Players:GetPlayers()
		local expectedResponses = #players
		local responsesReceived = 0
		local finished = false
		local timeoutSeconds: number = selfRemote.TimeOut or 3

		local function onResponse(player: Player, ...: any)
			if finished then
				return
			end
			if not table.find(players, player) then
				return
			end
			if results[player] then
				return
			end

			results[player] = table.pack(...)
			responsesReceived = responsesReceived + 1
			if responsesReceived >= expectedResponses then
				finished = true
				RemoteFunctionRequests[ID] = nil
				if coroutine.status(Thread) == "suspended" then
					coroutine.resume(Thread, results)
				end
			end
		end

		RemoteFunctionRequests[ID] = onResponse

		task.delay(timeoutSeconds, function()
			if not finished then
				warn(
					"RemoteFunction '"
						.. selfRemote._Name
						.. "' FireAll timed out after "
						.. tostring(timeoutSeconds)
						.. "s, got "
						.. tostring(responsesReceived)
						.. "/"
						.. tostring(expectedResponses)
						.. " responses (ID: "
						.. tostring(ID)
						.. ")\n  Called from:\n"
						.. callTraceback
				)
				finished = true
				RemoteFunctionRequests[ID] = nil
				if coroutine.status(Thread) == "suspended" then
					coroutine.resume(Thread, results)
				end
			end
		end)

		queueFireAllFunctions(selfRemote._Sent, ID, ...)

		return coroutine.yield()
	end

	function Module.UnreliableRemoteFunction:Fire(...: any): any
		local selfRemote: Remote = self
		if not rateLimit(selfRemote) then
			warn("Rate limit got reached for UnreliableRemoteFunction '" .. selfRemote._Name .. "'\n  Traceback:\n" .. debug.traceback())
			return nil
		end

		local callTraceback = debug.traceback(nil, 2)
		local Thread = coroutine.running()
		local ID = Helpers.generateNumbers()
		local Resume = false
		local timeoutSeconds: number = selfRemote.TimeOut or 3

		UnreliableRemoteFunctionRequests[ID] = function(...: any)
			Resume = true
			UnreliableRemoteFunctionRequests[ID] = nil
			local args = table.pack(...)
			coroutine.resume(Thread, table.unpack(args, 1, args.n))
		end

		task.delay(timeoutSeconds, function()
			if Resume then
				return
			end
			warn("UnreliableRemoteFunction '" .. selfRemote._Name .. "' has timed out after " .. tostring(timeoutSeconds) .. "s (ID: " .. tostring(ID) .. ")\n  Called from:\n" .. callTraceback)
			UnreliableRemoteFunctionRequests[ID] = nil
			coroutine.resume(Thread, nil)
		end)

		task.spawn(function(...: any)
			queueFire(selfRemote._Sent, ID, ...)
		end, ...)

		return coroutine.yield()
	end

	function Module.RemoteFunction:Invoke(...: any): any
		return invokeRemoteFunctionAsClient(self, "Invoke", ...)
	end

	function Module.UnreliableRemoteFunction:Invoke(...: any): any
		local selfRemote: Remote = self
		if not rateLimit(selfRemote) then
			warn("Rate limit got reached for UnreliableRemoteFunction '" .. selfRemote._Name .. "' (Invoke)\n  Traceback:\n" .. debug.traceback())
			return nil
		end

		local callTraceback = debug.traceback(nil, 2)
		local Thread = coroutine.running()
		local ID = Helpers.generateNumbers()
		local Resume = false
		local timeoutSeconds: number = selfRemote.TimeOut or 3

		UnreliableRemoteFunctionRequests[ID] = function(...: any)
			Resume = true
			UnreliableRemoteFunctionRequests[ID] = nil
			local args = table.pack(...)
			coroutine.resume(Thread, table.unpack(args, 1, args.n))
		end

		task.delay(timeoutSeconds, function()
			if Resume then
				return
			end
			warn("UnreliableRemoteFunction '" .. selfRemote._Name .. "' Invoke has timed out after " .. tostring(timeoutSeconds) .. "s (ID: " .. tostring(ID) .. ")\n  Called from:\n" .. callTraceback)
			UnreliableRemoteFunctionRequests[ID] = nil
			coroutine.resume(Thread, nil)
		end)

		task.spawn(function(...: any)
			queueFire(selfRemote._Sent, ID, ...)
		end, ...)

		return coroutine.yield()
	end
end
