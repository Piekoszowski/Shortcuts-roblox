--[[
	Require it once and use the same table everywhere. The require is cached so you're not paying for re-requires if you in-line shortcut paths, just keep S = require(path.to.Shortcuts) somewhere at the top of every script and you're done.

	You require this once in each script and module and call S.<anything> from then on. Services, your own modules, networking (remotes, bindables), data handler that handles replica already, debug printing and output visibility management.
	There are no separate getters for anything. ex. S.Players and S.MyRandomGameModule S.DataHandler(Something) S.Tag.ThisThing:GetChildren() all work as in the examples.
	Lookups go services -> custom paths from CustomPaths module -> any other ModuleScript in the game that is a ReplicatedFirst or ServerScriptService descendant. First hit wins and the result is cached forever for that session.
	That said name collisions across the games will be shown in output to correct but still let one of them win, to not break the game.

	Want a new roblox service exposed as S.<Name>? add the string into RobloxServicesList (frozen table). Case insensitive on access so S.players works the same as S.Players.
	Want a custom path to a folder like S.Data so you can access modules in it like S.Data.ModuleName? add it in CustomPaths pointing at the folder.
	Anything else: just name your ModuleScript uniquely under ReplicatedFirst or ServerScriptService and the S.<TheName> will require + cache it on first access. Nothing else needed.

	S.<ServiceName> shortcuts any Roblox service listed in RobloxServicesList. Case-insensitive. No better way to do this sadly.
	S.LocalPlayer is client-only shortcut for Players.LocalPlayer.
	S.Tag.<TagName> shortcuts CollectionService:GetTagged(tagName) into { GetChildren = ... } so you can iterate it like a folder. (does NOT cache, gets called fresh each time!)
	S.<ModuleName> is any ModuleScript in ReplicatedFirst or ServerScriptService. On game init shortcuts requires + caches the module.
	S.<CustomPathName> If you set up the path in Custompaths module, you can now index into it with that specific path. (ex S.Data.Foo)

	S.RemoteEvent / S.UnreliableRemoteEvent / S.RemoteFunction / S.UnreliableRemoteFunction / S.BindableEvent / S.BindableFunction | networking & bindables. See below for the full API.
	S.GetRemoteEvent / S.GetUnreliableRemoteEvent / S.GetRemoteFunction / S.GetUnreliableRemoteFunction / S.GetBindableEvent / S.GetBindableFunction | yields and returns cached endpoints by name. See below for the full API.
	S.DataHandler(key) | per-key DataHandler object for save + replicate state. Callable shortcut for S.DataHandler.Data(key). See below for the full API.
	S.print / S.warn / S.silenterror / S.error / S:Debug() | tagged debug printing tied to the calling module name. This listens to "S.DEBUGGING([UserId] = {1, 2, 3, 4}, so on)" where 1 = print 2 = warn 3 = fake error 4 = error
	S.DEBUGGING | S.DEBUGGING([UserId] = {1, 2, 3, 4}, [UserId] = {1, 2}, so on)  where 1 = print 2 = warn 3 = fake error 4 = error if you remove a number that userid wont be able to see that output type from
	that module/script/localscript. If someone is not in the S.DEBUGGING table they shall not see anything, if you want everyone to see use non S.-output (s.print, so on) or do not declare S.DEBUGGING in that script/module.
	this is useful when a project has more than 4 people working on it and the output get's spammy. I can immediately opt out of my coworkers features that I do not contribute to if my output gets hard to read.

	If S.<SomeName> doesn't exist but its called it'll throw an error with the module name.
	A lot of programmers (me) like to fork this to adress their project needs. Do it, just don't add subsystems by mutating S after this returns from another script, do it here in the right boot order.
	Otherwise you race the cache, good luck debugging that. Shortcut's are best forked by editing the subfolders already provided, but if you want to you can add new features, it's add-on friendly just not with runtime path edits.
]]

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

	S.DataHandler(key) to get a DataHandler object for that key. key is usually player.UserId for normal player data. use any string you want for non-player bound data. (that works always, it's intended to be used aswell)
	S.DataHandler("UnsavedData_" .. UserId) is an unsaved mirror. It has some use cases, you can add keys runtime on server that you want replicated but not saved, this module replicates to the player at the rate of the normal UserId one!
	S.DataHandler("AnyCustomKey") any non-player bound data goes here. Game events, weather, whatever you need. If the root path you write is in ReplicatedKeys, the value auto-replicates to every player through a shared "SharedData" replica (every connected player is auto-subscribed).
	Anything custom key but not in ReplicatedKeys stays local to whichever side wrote it. SavedKeys (& obviously DefaultProfileData neither) dont override this since there's no global datastore to save it to. (TODO: Maybe in the future.)

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

--[[
	Below is the networking + bindable event/function API, it mimics robloxs api and supports everything + more. (RemoteEvent, UnreliableRemoteEvent, RemoteFunction, UnreliableRemoteFunction, BindableEvent, BindableFunction)
	All endpoints are cached by name, callbacks run through error catching wrappers, network fires are batched on RunService.PostSimulation, and request/response calls get built-in rate limits (& timeouts), with a healthy default of 60/s.

	Every constructor accepts an optional table as a second arg to S.DataHandler(name, ratelimits), the ratelimits table is { RateLimit = 60, RateLimitTime = 1, TimeOut = 3 } (defaults shown for RemoteFunction's, RemoteEvent's don't have TimeOut neither bindables). You can also call :Set({...}) later to mutate fields on the returned object.
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

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--[[ Dependencies ]]--
local DataHandlerModule = require(script.DataHandler)
local DebugPrinting = require(script.DebugPrinting)
local EasyRequire = require(script.EasyRequire)
local RemoteBindableEvents = require(script.RemoteBindableEvents)
local RobloxServicesList = require(script.RobloxServicesList)

if RunService:IsServer() and not ReplicatedStorage:FindFirstChild("Remotes") then
	local remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "Remotes"
	remotesFolder.Parent = ReplicatedStorage
end

if RunService:IsServer() then
	if not script:FindFirstChild("RemoteConnection") then
		local remoteConnection = Instance.new("RemoteEvent")
		remoteConnection.Name = "RemoteConnection"
		remoteConnection.Parent = script
	end

	if not script:FindFirstChild("UnreliableRemoteConnection") then
		local unreliableRemoteConnection = Instance.new("RemoteEvent")
		unreliableRemoteConnection.Name = "UnreliableRemoteConnection"
		unreliableRemoteConnection.Parent = script
	end
else
	script:WaitForChild("RemoteConnection", math.huge)
	script:WaitForChild("UnreliableRemoteConnection", math.huge)
end

local shortcuts = EasyRequire(script, RobloxServicesList)

RemoteBindableEvents(shortcuts, script)
DebugPrinting(shortcuts)

shortcuts.DataHandler = DataHandlerModule(shortcuts)

return shortcuts
