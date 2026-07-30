
-- Define these!
TOOL.Tab = "V-NPCs"
TOOL.Category = "Tools" -- Name of the category
TOOL.Name = "#tool.vnpc_possess.name" -- Name to display. # means it will be translated ( see below )

TOOL.LeftClickAutomatic = false 
TOOL.RightClickAutomatic = false 
TOOL.RequiresTraceHit = true

TOOL.Information = {
	{ name = "left"},
}

--this code is ripped straight from drgbase
local function CanPossess(ent)
	return ent.IsDrGNextbot and
	GetConVar("drgbase_possession_enable"):GetBool() and
	ent.PossessionPrompt and ent:IsPossessionEnabled()
end

function TOOL:LeftClick(tr)
	local owner = self:GetOwner()
	if not IsValid(tr.Entity) then return false end
	if not tr.Entity.IsDrGNextbot then return false end
	if not owner:IsPlayer() then return end

	if SERVER and CanPossess(tr.Entity) then
		local possess = tr.Entity:Possess(owner)
		if possess == "ok" then
			net.Start("DrGBaseNextbotCanPossess")
			net.WriteEntity(tr.Entity)
		else
			net.Start("DrGBaseNextbotCantPossess")
			net.WriteEntity(tr.Entity)
			net.WriteString(possess)
		end
		net.Send(owner)
	end
	return true
end

function TOOL.BuildCPanel( CPanel )
	CPanel:Help( "#tool.vnpc_possess.desc" )
end

if ( CLIENT ) then -- We can only use language.Add on client
	language.Add("tool.vnpc_possess.name", "Possess" ) -- Add translation
	language.Add("tool.vnpc_possess.desc", "Click on an V-NPC to possess and play as them. E to exit." ) -- Add translation
	language.Add("tool.vnpc_possess.left", "Possess" ) -- Add translation
end