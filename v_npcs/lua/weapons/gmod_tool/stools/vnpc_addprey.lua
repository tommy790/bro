
-- Define these!
TOOL.Tab = "V-NPCs"
TOOL.Category = "Debug" -- Name of the category
TOOL.Name = "#tool.vnpc_addprey.name" -- Name to display. # means it will be translated ( see below )

TOOL.LeftClickAutomatic = false 
TOOL.RightClickAutomatic = false 
TOOL.RequiresTraceHit = true

TOOL.Information = {
	{ name = "left"},
	{ name = "right"},
	{ name = "reload"}
}

TOOL.ClientConVar[ "value" ] = "80"
TOOL.ClientConVar[ "health" ] = "100"

local function makePsuedoPrey(pred, value, health)
	local button = ents.Create( "npc_breen" ) --yeah ripped straight from 
	button:SetModel( "models/breen.mdl" )
	button:SetPos( Vector( 0, 0, 0 ) )
	button:Spawn()
	button:SetHealth(health)
	button:SetModelScale(value/74.310160812637)


	if not pred:EatEntity(button) then
		button:Remove()
	end
end

function TOOL:LeftClick( tr )
	local ent = tr.Entity
	local owner = self:GetOwner()

	if IsValid(ent) and SERVER and ent.Predator then

		local value = self:GetClientNumber("value", 80)
		local health = self:GetClientNumber( "health", 100)
		makePsuedoPrey(ent, value, health)
		return true
	end
end

function TOOL:RightClick( tr )
	local ent = tr.Entity
	local owner = self:GetOwner()

	if IsValid(ent) and SERVER and ent.Predator then
		if ent.Belly then
			local preyTable = ent.Belly.Prey
			for i = 1, #preyTable do

				local preyInfo = preyTable[i]

				if not preyInfo.Absorbing then
					ent.Belly:AbsorbSpecificPrey(i, ent)
					return true 
				end
			end
		end
	end
end

function TOOL:Reload( tr )
	local ent = tr.Entity
	local owner = self:GetOwner()

	if IsValid(ent) and SERVER and ent.Predator then
		ent:EatEntity(owner, ent)
		return true
	end
end

function TOOL.BuildCPanel( CPanel )
	CPanel:Help( "#tool.vnpc_addprey.desc" )
	CPanel:AddControl( "Slider", { Label = "#tool.vnpc_addprey.slider1", Command = "vnpc_addprey_value", Type = "Int", Min = 30, Max = 500, Help = true } )
	CPanel:AddControl( "Slider", { Label = "#tool.vnpc_addprey.slider2", Command = "vnpc_addprey_health", Type = "Int", Min = 25, Max = 300, Help = true } )

end

if ( CLIENT ) then -- We can only use language.Add on client
	language.Add("tool.vnpc_addprey.name", "Add/Digest prey" ) -- Add translation
	language.Add("tool.vnpc_addprey.desc", "Click on an V-NPC to update to force-feed a prey, alt-fire to instantly digest prey that has been inside for the longest. Reload to get instantly eaten by the NPC." ) -- Add translation
	language.Add("tool.vnpc_addprey.left", "Add prey" ) -- Add translation
	language.Add("tool.vnpc_addprey.right", "Digest prey" ) -- Add translation
	language.Add("tool.vnpc_addprey.reload", "Add Self" ) -- Add translation

	language.Add("tool.vnpc_addprey.slider1", "Value/Size" ) -- Add translation
	language.Add( "tool.vnpc_addprey.slider1.help", "How big the npc is, 80 is usually a size of a player." )

	language.Add("tool.vnpc_addprey.slider2", "Health" ) -- Add translation
	language.Add( "tool.vnpc_addprey.slider2.help", "Health of the prey. Length of digestion time." )

end