--!strict
--!optimize 2

--[[ Services ]]
--
local Players = game:GetService("Players")

--[[ Modules ]]--
local Helpers = require(script.Parent.Helpers)

--[[ Typing ]]--
export type SeverityConfig = boolean | { [number]: number }
export type ModuleDebugConfig = boolean | { [number]: SeverityConfig }

--[[ Output Tiers ]]--
local SeverityMap: { [string]: number } = {
	print = 1,
	warn = 2,
	fakeerror = 3,
	error = 4,
}

--[[ DebugPrinting ]]--
return function(Module: { [string]: any })
	local ModuleDebugConfigs: { [string]: ModuleDebugConfig } = {}

	--[[ You can isolate a whole module/script/localscript outputs to only be visible to the per-module/script defined set of developers. Great for reducing output clutter on large teams with a lot of people collaborating. ]]--
	function Module.DEBUGGING(config: ModuleDebugConfig): ()
		local info = debug.info(2, "s")
		local fileName = info:match("([^/\\]+)$") or info
		local moduleName = (fileName :: string):gsub("%.lua$", "")
		ModuleDebugConfigs[moduleName] = config
	end

	--[[ Core Logging ]]--
	function Module:InternalDebug(severity: any, inHouse: boolean?, ...: any): ()
		local number = 2
		if inHouse then
			number = 3
		end

		local info = debug.info(number, "s")
		local fileName = info:match("([^/\\]+)$") or info
		local moduleName = (fileName :: string):gsub("%.lua$", "")

		local currentModuleDebugConfig = ModuleDebugConfigs[moduleName]
		local allowAllSeverities = currentModuleDebugConfig == nil
			or currentModuleDebugConfig == true

		local normalizedLevel = Helpers.normalizeSeverity(severity, SeverityMap)
		local level: number = normalizedLevel or 1

		local creator = ""

		local tokens: { string } = {}
		for token in moduleName:gmatch("([^%.]+)") do
			table.insert(tokens, token)
		end
		if #tokens > 0 then
			moduleName = tokens[#tokens]
		end

		local tag = ('["' .. creator .. moduleName .. '"]'):upper()

		local function internalLogic(allowedSeverities: any, ...: any): ()
			if
				allowedSeverities and allowedSeverities == true
				or Helpers.contains(allowedSeverities, level)
			then
				local function log_message(isTable: boolean, current_tag: any, ...: any): ()
					local args = table.pack(...)
					local user_message_content = ""
					if args.n > 0 then
						local message_parts: { string } = {}
						for i = 1, args.n do
							table.insert(message_parts, tostring(args[i]))
						end
						user_message_content = table.concat(message_parts, " ")
					end

					if level == 1 then
						if isTable then
							print(current_tag, ...)
						elseif args.n > 0 then
							print(current_tag, table.unpack(args, 1, args.n))
						else
							print(current_tag, ...)
						end
					elseif level == 2 then
						if isTable then
							warn(current_tag, ...)
						elseif args.n > 0 then
							warn(current_tag, table.unpack(args, 1, args.n))
						else
							warn(current_tag, ...)
						end
					elseif level == 3 then
						local final_message: any
						if isTable then
							final_message = ...
						elseif args.n > 0 then
							final_message = current_tag .. " " .. user_message_content
						else
							final_message = current_tag
						end
						task.spawn(function()
							error(final_message, 0)
						end)
					elseif level == 4 then
						local final_message: any
						if isTable then
							final_message = ...
						elseif args.n > 0 then
							final_message = current_tag .. " " .. user_message_content
						else
							final_message = current_tag
						end
						error(final_message)
					end
				end

				if typeof(...) == "table" then
					if level > 2 then
						task.spawn(function()
							log_message(false, " == ERROR IN " .. moduleName:upper() .. ": ==", tag)
						end)
						log_message(true, tag, ...)
					else
						log_message(true, tag, ...)
					end
				else
					log_message(false, tag, ...)
				end
			end
		end

		local configMap: { [number]: any }? = nil
		if type(currentModuleDebugConfig) == "table" then
			configMap = currentModuleDebugConfig :: any
		end

		local players = Players:GetPlayers()
		for _, player in ipairs(players) do
			if player then
				if allowAllSeverities then
					internalLogic(true, ...)
				elseif configMap and configMap[player.UserId] then
					local allowedSeverities = configMap[player.UserId]
					internalLogic(allowedSeverities, ...)
				end
			end
		end

		if #players == 0 then
			internalLogic(true, ...)
		end
	end

	function Module:Debug(message: any, severity: any): ()
		local info = debug.info(2, "s")
		local fileName = info:match("([^/\\]+)$") or info
		local moduleName = (fileName :: string):gsub("%.lua$", "")

		local currentModuleDebugConfig = ModuleDebugConfigs[moduleName]
		local allowAllSeverities = currentModuleDebugConfig == nil
			or currentModuleDebugConfig == true

		local normalizedLevel = Helpers.normalizeSeverity(severity, SeverityMap)
		local level: number = normalizedLevel or 1

		local creator = ""

		local tokens: { string } = {}
		for token in moduleName:gmatch("([^%.]+)") do
			table.insert(tokens, token)
		end
		if #tokens > 0 then
			moduleName = tokens[#tokens]
		end

		local tag = ('["' .. creator .. moduleName .. '"] '):upper()

		local players = Players:GetPlayers()

		local configMap: { [number]: any }? = nil
		if type(currentModuleDebugConfig) == "table" then
			configMap = currentModuleDebugConfig :: any
		end

		for _, player in ipairs(players) do
			if player then
				local allowedSeverities: any = nil
				if allowAllSeverities then
					allowedSeverities = true
				elseif configMap then
					allowedSeverities = configMap[player.UserId]
				end

				if
					allowedSeverities
					and (allowedSeverities == true or Helpers.contains(allowedSeverities, level))
				then
					local function log_message(log_content: any, current_tag: any): ()
						if level == 1 then
							print(current_tag, log_content)
						elseif level == 2 then
							warn(current_tag, log_content)
						elseif level == 3 then
							error(log_content, 0)
						elseif level == 4 then
							error(log_content)
						end
					end

					if typeof(message) == "table" then
						if level > 2 then
							log_message(tag, tag)
							log_message(message, tag)
						else
							log_message(message, tag)
						end
					else
						log_message(tostring(message), tag)
					end
				end
			end
		end
	end

	--[[ API ]]--
	function Module.Print(...: any): ()
		Module:InternalDebug(1, true, ...)
	end

	function Module.print(...: any): ()
		Module:InternalDebug(1, true, ...)
	end

	function Module.Warn(...: any): ()
		Module:InternalDebug(2, true, ...)
	end

	function Module.warn(...: any): ()
		Module:InternalDebug(2, true, ...)
	end

	function Module.SilentError(...: any): ()
		Module:InternalDebug(3, true, ...)
	end

	function Module.silenterror(...: any): ()
		Module:InternalDebug(3, true, ...)
	end

	function Module.Error(...: any): ()
		Module:InternalDebug(4, true, ...)
	end

	function Module.error(...: any): ()
		Module:InternalDebug(4, true, ...)
	end
end
