
-- Define these!
TOOL.Tab = "V-NPCs"
TOOL.Category = "Debug" -- Name of the category
TOOL.Name = "#tool.vnpc_displayprey.name" -- Name to display. # means it will be translated ( see below )

TOOL.RequiresTraceHit = true

TOOL.Information = {
	{ name = "left"},
}

-- An example clientside convar
--TOOL.ClientConVar[ "CLIENTSIDE" ] = "default"

-- An example serverside convar
--TOOL.ServerConVar[ "SERVERSIDE" ] = "default"

function TOOL:LeftClick( tr )
	local ent = tr.Entity
	local owner = self:GetOwner()

	if IsValid(ent) and SERVER and ent.Predator then
		if not ent.Belly then return end
		for i,v in ipairs(ent.Belly.Prey) do
			PrintTable(v)
			if v.Entity then
				print(v.Entity:Health())
			end
		end
		return true
	end
end


function TOOL.BuildCPanel( CPanel )
	CPanel:Help( "#tool.vnpc_displayprey.desc" )
end

if ( CLIENT ) then -- We can only use language.Add on client
	language.Add("tool.vnpc_displayprey.name", "Display Prey" ) -- Add translation
	language.Add("tool.vnpc_displayprey.desc", "Prints prey info into console. Will be replaced with UI soon." ) -- Add translation
	language.Add("tool.vnpc_displayprey.left", "Prints prey information" ) -- Add translation
end