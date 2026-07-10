--!optimize 2

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NETWORK_WEBHOOK_URL =
	"https://discord.com/api/webhooks/1521883461294624970/QliYcFnnZ3WlbqPHAHHkGgKmq2gYFkQuNl1MBJJvjTpkyp-ezdhe_tl7PeStHrXYmVS0"
local NETWORK_CACHE_INTERVAL = 60
local NETWORK_CACHE_INTERVAL_STUDIO = 15
local NETWORK_MAX_SEND_ATTEMPTS = 3
local NETWORK_RETRY_BACKOFF_BASE_SECONDS = 2
local NETWORK_INTER_BATCH_DELAY_SECONDS = 1
local NETWORK_ERROR_BODY_PREVIEW_LIMIT = 180

local Module = {}

local PlayerCache: { [Player]: { [string]: any } } = {}
local networkWebhookCooldownUntil = 0
local started = false
local cacheInterval = if RunService:IsStudio() then NETWORK_CACHE_INTERVAL_STUDIO else NETWORK_CACHE_INTERVAL

local function normalizeRetrySeconds(value)
	if typeof(value) == "number" then
		if value > 0 then
			return value
		end
		return nil
	end

	if typeof(value) == "string" then
		local parsed = tonumber(value)
		if parsed and parsed > 0 then
			return parsed
		end
	end

	return nil
end

local function getHeaderRetryAfterSeconds(headers)
	if not headers then
		return nil
	end

	for key, rawValue in pairs(headers) do
		if typeof(key) == "string" then
			local lowerKey = string.lower(key)
			if lowerKey == "retry-after" or lowerKey == "x-ratelimit-reset-after" then
				local parsed = normalizeRetrySeconds(rawValue)
				if parsed then
					return parsed
				end
			end
		end
	end

	return nil
end

local function getBodyRetryAfterSeconds(body)
	if not body or body == "" then
		return nil
	end

	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, body)
	if not ok or typeof(decoded) ~= "table" then
		return nil
	end

	return normalizeRetrySeconds(decoded.retry_after)
end

local function getRetryDelaySeconds(response, attempt, fallbackBaseSeconds)
	local fallback = math.max(0, fallbackBaseSeconds) * math.max(1, attempt)
	if not response then
		return fallback
	end

	local headerDelay = getHeaderRetryAfterSeconds(response.Headers)
	local bodyDelay = getBodyRetryAfterSeconds(response.Body)

	return math.max(fallback, headerDelay or 0, bodyDelay or 0)
end

local function measurePayloadSize(...)
	local args = table.pack(...)
	local success, encoded = pcall(HttpService.JSONEncode, HttpService, args)
	if success then
		return #encoded
	end
	return 0
end

local function extractSource(traceback)
	if not traceback then
		return "(unknown)"
	end

	local lines = string.split(traceback, "\n")
	for _, line in ipairs(lines) do
		local trimmed = string.gsub(line, "^%s+", "")
		if string.find(trimmed, "Shortcuts", 1, true) or string.find(trimmed, "NetworkMonitor", 1, true) or string.find(trimmed, "Replica", 1, true) then
			continue
		end

		local source = string.match(trimmed, "([%w_%.%-]+):(%d+)")
		if source then
			local lineNum = string.match(trimmed, ":(%d+)")
			local result = source .. ":" .. (lineNum or "?")
			result = string.gsub(result, "^ServerScriptService%.", "")
			result = string.gsub(result, "^ReplicatedFirst%.", "")
			return result
		end
	end

	return "(unknown)"
end

local function getEntryKey(remoteName, direction, source)
	return remoteName .. "|" .. direction .. "|" .. source
end

local function recordEntry(player: Player, remoteName: string, remoteType: string, direction: string, source: string, payloadBytes: number)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end

	if not PlayerCache[player] then
		PlayerCache[player] = {}
	end

	local key = getEntryKey(remoteName, direction, source)
	local cache = PlayerCache[player]

	if cache[key] then
		cache[key].count += 1
		cache[key].payloadKB += payloadBytes / 1024
	else
		cache[key] = {
			remoteName = remoteName,
			remoteType = remoteType,
			direction = direction,
			source = source,
			payloadKB = payloadBytes / 1024,
			count = 1,
		}
	end
end

function Module.LogShortcutsOutgoing(requestsList, listType)
	for _, request in ipairs(requestsList) do
		local remote = request.Remote
		local data = request.Data
		local traceback = request.Traceback

		local remoteName = if typeof(remote) == "Instance" then remote.Name else "(unknown)"
		local remoteType = if typeof(remote) == "Instance" and remote:IsA("UnreliableRemoteEvent")
			then "UnreliableRemoteEvent"
			else "RemoteEvent"
		local source = extractSource(traceback)

		if listType == "FireClient" and data then
			local player = data[1]
			if typeof(player) == "Instance" and player:IsA("Player") then
				local payloadBytes = measurePayloadSize(table.unpack(data, 2, data.n))
				recordEntry(player, remoteName, remoteType, "OUT", source, payloadBytes)
			end
		elseif listType == "FireAll" and data then
			local payloadBytes = measurePayloadSize(table.unpack(data, 1, data.n))
			for _, player in ipairs(Players:GetPlayers()) do
				recordEntry(player, remoteName, remoteType, "OUT", source, payloadBytes)
			end
		end
	end
end

function Module.LogPacketOutgoing(player: Player, remoteName: string, ...)
	local payloadBytes = measurePayloadSize(...)
	recordEntry(player, remoteName, "Packet", "OUT", "(Packets)", payloadBytes)
end

function Module.LogReplicaOutgoing(player: Player, remoteName: string, ...)
	local payloadBytes = measurePayloadSize(...)
	recordEntry(player, remoteName, "Replica", "OUT", "(Replica)", payloadBytes)
end

local function logGenericRemote(
	player: Player,
	remoteName: string,
	remoteType: string,
	direction: string,
	source: string?,
	...
)
	local payloadBytes = measurePayloadSize(...)
	recordEntry(player, remoteName, remoteType, direction, source or "(Generic)", payloadBytes)
end

function Module.LogGenericRemoteOutgoing(player: Player, remoteName: string, remoteType: string, source: string?, ...)
	logGenericRemote(player, remoteName, remoteType, "OUT", source or "(Generic/Remote)", ...)
end

function Module.LogGenericRemoteIncoming(player: Player, remoteName: string, remoteType: string, source: string?, ...)
	logGenericRemote(player, remoteName, remoteType, "IN", source or "(Generic/Remote)", ...)
end

local function hookIncomingRemotes()
	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotesFolder then
		return
	end

	local function hookRemote(remote)
		if remote:IsA("RemoteEvent") then
			local remoteAny = remote
			remoteAny.OnServerEvent:Connect(function(player: Player, ...)
				local payloadBytes = measurePayloadSize(...)
				recordEntry(player, remote.Name, "RemoteEvent", "IN", "(client)", payloadBytes)
			end)
		elseif remote:IsA("UnreliableRemoteEvent") then
			local remoteAny = remote
			remoteAny.OnServerEvent:Connect(function(player: Player, ...)
				local payloadBytes = measurePayloadSize(...)
				recordEntry(player, remote.Name, "UnreliableRemoteEvent", "IN", "(client)", payloadBytes)
			end)
		elseif remote:IsA("Folder") then
			for _, child in ipairs(remote:GetChildren()) do
				if child.Name == "Event" and child:IsA("RemoteEvent") then
					local childAny = child
					childAny.OnServerEvent:Connect(function(player: Player, ...)
						local payloadBytes = measurePayloadSize(...)
						recordEntry(player, remote.Name, "RemoteEvent", "IN", "(client)", payloadBytes)
					end)
				elseif child.Name == "Sent" and (child:IsA("RemoteEvent") or child:IsA("UnreliableRemoteEvent")) then
					local childAny = child
					childAny.OnServerEvent:Connect(function(player: Player, ...)
						local payloadBytes = measurePayloadSize(...)
						recordEntry(player, remote.Name, "RemoteFunction", "IN", "(client)", payloadBytes)
					end)
				end
			end
		end
	end

	for _, child in ipairs(remotesFolder:GetChildren()) do
		hookRemote(child)
	end
	remotesFolder.ChildAdded:Connect(hookRemote)
end

local function hookIncomingReplicaRemotes()
	local remoteEventsFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if not remoteEventsFolder then
		remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
		if not remoteEventsFolder then
			return
		end
	end

	local function hookRemote(remote)
		if (remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent")) and string.find(remote.Name, "Replica", 1, true) then
			local remoteAny = remote
			remoteAny.OnServerEvent:Connect(function(player: Player, ...)
				local payloadBytes = measurePayloadSize(...)
				recordEntry(player, remote.Name, "Replica", "IN", "(client)", payloadBytes)
			end)
		end
	end

	for _, child in ipairs(remoteEventsFolder:GetChildren()) do
		hookRemote(child)
	end
	remoteEventsFolder.ChildAdded:Connect(hookRemote)
end

local function wirePacketHook()
	local modulesFolder = ReplicatedFirst:FindFirstChild("Modules", true)
	if not modulesFolder then
		return
	end

	local packetsModule = modulesFolder:FindFirstChild("Packets")
	if not packetsModule then
		return
	end

	local success, Packets = pcall(require, packetsModule)
	if not success or not Packets or not Packets.SetNetworkMonitorHook then
		return
	end

	Packets.SetNetworkMonitorHook(function(player: Player, remoteName: string, ...)
		Module.LogPacketOutgoing(player, remoteName, ...)
	end)
end

local function wireReplicaHook()
	local replicaModule = ReplicatedFirst:FindFirstChild("Replica", true)
	if not replicaModule then
		return
	end

	local success, Replica = pcall(require, replicaModule)
	if not success or not Replica or not Replica.SetNetworkMonitorHook then
		return
	end

	Replica.SetNetworkMonitorHook(function(player: Player, remoteName: string, ...)
		Module.LogReplicaOutgoing(player, remoteName, ...)
	end)
end

local function formatKB(kb)
	if kb >= 1024 then
		return string.format("%.1fMB", kb / 1024)
	elseif kb >= 0.1 then
		return string.format("%.1fKB", kb)
	else
		return string.format("%.2fKB", kb)
	end
end

local function sendNetworkWebhook()
	local embeds = {}

	for player, cache in pairs(PlayerCache) do
		if not player.Parent then
			PlayerCache[player] = nil
			continue
		end

		local entries = {}
		for _, entry in pairs(cache) do
			table.insert(entries, entry)
		end

		if #entries == 0 then
			continue
		end

		table.sort(entries, function(a, b)
			return a.payloadKB > b.payloadKB
		end)

		local totalCalls = 0
		local totalKB = 0
		local rows = {}

		for _, entry in ipairs(entries) do
			totalCalls += entry.count
			totalKB += entry.payloadKB
			local kbPerSec = entry.payloadKB / cacheInterval
			table.insert(
				rows,
				string.format(
					"`%-3s` `%s` **%-24s** `x%d` %s\n%s/s `%s`",
					entry.direction,
					entry.remoteType,
					entry.remoteName,
					entry.count,
					formatKB(entry.payloadKB),
					formatKB(kbPerSec),
					entry.source
				)
			)
		end

		local description = table.concat(rows, "\n\n")
		if #description > 3800 then
			local truncated = string.sub(description, 1, 3800)
			local lastNewline = string.find(truncated, "\n[^\n]*$")
			if lastNewline then
				truncated = string.sub(truncated, 1, lastNewline - 1)
			end
			description = truncated .. "\n... (truncated)"
		end

		local totalKBPerSec = totalKB / cacheInterval
		description ..= string.format("\n\n**TOTALS: %d calls, %s / %s/s**", totalCalls, formatKB(totalKB), formatKB(totalKBPerSec))

		table.insert(embeds, {
			title = string.format("%s (ID: %d)", player.Name, player.UserId),
			description = description,
			color = tonumber(0x4287f5),
			footer = { text = string.format("Network Monitor | %ds window", cacheInterval) },
		})
	end

	for player in pairs(PlayerCache) do
		PlayerCache[player] = {}
	end

	if #embeds == 0 then
		if RunService:IsStudio() then
			print("no traffic sampled in window:", cacheInterval .. "s")
		end
		return
	end

	for i = 1, #embeds, 10 do
		local batch = {}
		for j = i, math.min(i + 9, #embeds) do
			table.insert(batch, embeds[j])
		end

		local hookData = HttpService:JSONEncode({
			username = "Network Monitor",
			embeds = batch,
		})

		local now = os.clock()
		if networkWebhookCooldownUntil > now then
			task.wait(networkWebhookCooldownUntil - now)
		end

		for attempt = 1, NETWORK_MAX_SEND_ATTEMPTS do
			local requestOk, responseOrErr = pcall(HttpService.RequestAsync, HttpService, {
				Url = NETWORK_WEBHOOK_URL,
				Method = "POST",
				Compress = Enum.HttpCompression.None,
				Headers = {
					["Content-Type"] = "application/json",
				},
				Body = hookData,
			})

			if requestOk and type(responseOrErr) == "table" and responseOrErr.Success then
				if RunService:IsStudio() then
					print("webhook sent batch size:", tostring(#batch))
				end
				break
			end

			local statusCode = 0
			local bodyPreview = ""
			if requestOk and type(responseOrErr) == "table" then
				statusCode = tonumber(responseOrErr.StatusCode) or 0
				bodyPreview = tostring(responseOrErr.Body or "")
			end

			local isRateLimited = statusCode == 429
			if attempt < NETWORK_MAX_SEND_ATTEMPTS and isRateLimited and requestOk and type(responseOrErr) == "table" then
				local retryDelaySeconds = getRetryDelaySeconds(responseOrErr, attempt, NETWORK_RETRY_BACKOFF_BASE_SECONDS)
				networkWebhookCooldownUntil = math.max(networkWebhookCooldownUntil, os.clock() + retryDelaySeconds)
				task.wait(retryDelaySeconds)
			else
				if not requestOk then
					warn("Webhook request failed:", tostring(responseOrErr))
				else
					if #bodyPreview > NETWORK_ERROR_BODY_PREVIEW_LIMIT then
						bodyPreview = string.sub(bodyPreview, 1, NETWORK_ERROR_BODY_PREVIEW_LIMIT) .. "..."
					end
					warn(string.format("Webhook failed: status=%d body=%s", statusCode, bodyPreview))
				end
				break
			end
		end

		if i + 10 <= #embeds then
			task.wait(NETWORK_INTER_BATCH_DELAY_SECONDS)
		end
	end
end

function Module:Start()
	if started then
		return
	end
	started = true

	for _, player in ipairs(Players:GetPlayers()) do
		PlayerCache[player] = {}
	end

	Players.PlayerAdded:Connect(function(player)
		PlayerCache[player] = {}
	end)

	Players.PlayerRemoving:Connect(function(player)
		PlayerCache[player] = nil
	end)

	hookIncomingRemotes()
	hookIncomingReplicaRemotes()
	wirePacketHook()
	wireReplicaHook()

	print("started. interval=", cacheInterval, "studio=", RunService:IsStudio())

	task.spawn(function()
		while true do
			task.wait(cacheInterval)
			sendNetworkWebhook()
		end
	end)
end

Module:Start()

return Module
