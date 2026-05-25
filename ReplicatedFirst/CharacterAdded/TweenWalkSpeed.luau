local S = require(game:GetService("ReplicatedFirst").Services.Internal.Shortcuts)

local Module = {}

function Module.GetPriority(): number
	return 20
end

function Module.Init(player: Player, character: Model): ()
	-- Shortcuts.LocalPlayer is a thing.
	if player ~= S.LocalPlayer then
		return
	end

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	-- Shortcuts.TweenService accesses the service using :GetService (it's cached).
	local tween = S.TweenService:Create(humanoid, TweenInfo.new(1), { WalkSpeed = 24 })
	tween:Play()
	print("my walk speed will go up")
end

return Module
