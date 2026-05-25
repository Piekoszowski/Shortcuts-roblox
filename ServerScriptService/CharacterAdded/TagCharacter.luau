local S = require(game:GetService("ReplicatedFirst").Services.Internal.Shortcuts)

local Module = {}

function Module.GetPriority(): number
	return 20
end

function Module.Init(_player: Player, character: Model): ()
	S.CollectionService:AddTag(character, "Hero")

	print("tagged", character.Name, "as hero")
	-- Shortcuts.Tag.<name>:GetChildren() gives you an array of the tagged instances.
	print("heroes now:", #S.Tag.Hero:GetChildren())
end

return Module
