
-- Define these!
TOOL.Tab = "V-NPCs"
TOOL.Category = "Tools" -- Name of the category
TOOL.Name = "#tool.vnpc_changescale.name" -- Name to display. # means it will be translated ( see below )

TOOL.LeftClickAutomatic = false 
TOOL.RightClickAutomatic = false 
TOOL.RequiresTraceHit = true

TOOL.Information = {
	{ name = "left"},
	{ name = "right"},
	{ name = "reload"}
}

--this code is ripped straight from drgbase
function TOOL:LeftClick(tr)
	if not IsValid(tr.Entity) then return false end
	if not tr.Entity.IsDrGNextbot then return false end
	if SERVER then tr.Entity:Scale(1.1, 0.1) end
	return true
end
function TOOL:RightClick(tr)
	if not IsValid(tr.Entity) then return false end
	if not tr.Entity.IsDrGNextbot then return false end
	if SERVER then tr.Entity:Scale(0.9, 0.1) end
	return true
end
function TOOL:Reload(tr)
	if not IsValid(tr.Entity) then return false end
	if not tr.Entity.IsDrGNextbot then return false end
	if SERVER then tr.Entity:SetScale(1, 0.1) end
	return true
end

function TOOL.BuildCPanel( CPanel )
	CPanel:Help( "#tool.vnpc_changescale.desc" )
end

if ( CLIENT ) then -- We can only use language.Add on client
	language.Add("tool.vnpc_changescale.name", "Change Scale" ) -- Add translation
	language.Add("tool.vnpc_changescale.desc", "Click on an V-NPC to make them bigger or smaller." ) -- Add translation
	language.Add("tool.vnpc_changescale.left", "Make bigger" ) -- Add translation
	language.Add("tool.vnpc_changescale.right", "Make Smaller" ) -- Add translation
	language.Add("tool.vnpc_changescale.reload", "Reset scale" ) -- Add translation
end