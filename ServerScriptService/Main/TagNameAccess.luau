local S = require(game:GetService("ReplicatedFirst").Services.Internal.Shortcuts)

local marker = Instance.new("Folder")
marker.Name = "ShowTaggedMainMarker"
marker.Parent = workspace
S.CollectionService:AddTag(marker, "ShowTaggedMain")

-- Shortcuts.Tag.<name>:GetChildren() gives you an array of the tagged instances.
local tagTableList = S.Tag.ShowTaggedMain:GetChildren()
print("tag table count:", #tagTableList)

-- Shortcuts.[tagname]:GetChildren() also returns an array of the tagged instances.
local tagDirectList = S["ShowTaggedMain"]:GetChildren()
print("tag direct count:", #tagDirectList)

-- Shortcuts.CollectionService can remove tags too.
S.CollectionService:RemoveTag(marker, "ShowTaggedMain")
marker:Destroy()

return true
