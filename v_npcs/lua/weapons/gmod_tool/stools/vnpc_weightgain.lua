
-- Define these!
TOOL.Tab = "V-NPCs"
TOOL.Category = "Debug" -- Name of the category
TOOL.Name = "#tool.vnpc_weightgain.name" -- Name to display. # means it will be translated ( see below )

TOOL.LeftClickAutomatic = true
TOOL.RightClickAutomatic = true
TOOL.RequiresTraceHit = true

TOOL.Information = {
	{ name = "left"},
	{ name = "right"},
	{ name = "reload"}
}

-- An example clientside convar
--TOOL.ClientConVar[ "CLIENTSIDE" ] = "default"

-- An example serverside convar
--TOOL.ServerConVar[ "SERVERSIDE" ] = "default"

function TOOL:LeftClick( tr )
	local ent = tr.Entity
	local owner = self:GetOwner()

	if IsValid(ent) and SERVER and ent.Predator then
		local effectdata = EffectData()
		effectdata:SetOrigin( tr.HitPos )
		util.Effect( "inflator_magic", effectdata )

		ent:GainWeight(0.01)
		owner:SetNW2Float("VNPC_Bonescale", ent.BoneScale)
	end
end

function TOOL:RightClick( tr )
	local ent = tr.Entity
	local owner = self:GetOwner()

	if IsValid(ent) and SERVER and ent.Predator then
		local effectdata = EffectData()
		effectdata:SetOrigin( tr.HitPos )
		util.Effect( "inflator_magic", effectdata )
		ent:GainWeight(-0.01)
		owner:SetNW2Float("VNPC_Bonescale", ent.BoneScale)
	end
end

function TOOL:Reload( tr )
	local ent = tr.Entity
	local owner = self:GetOwner()

	if IsValid(ent) and SERVER and ent.Predator then
		ent:SetWeight(1)
		owner:SetNW2Float("VNPC_Bonescale", ent.BoneScale)
		return true
	end
end

function TOOL.BuildCPanel( CPanel )
	CPanel:Help( "#tool.vnpc_weightgain.desc" )
end

function TOOL:DrawToolScreen(width, height)
	surface.SetDrawColor(DrGBase.CLR_DARKGRAY)
	surface.DrawRect(0, 0, width, height)
	local owner = self:GetOwner()
	local bonescale = owner:GetNW2Float("VNPC_Bonescale")
	if bonescale then
		draw.SimpleText("Current Bonescale:", "DermaLarge", width/2, height/2-20, DrGBase.CLR_RED, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		draw.SimpleText(tostring(bonescale), "DermaLarge", width/2, height/2+20, DrGBase.CLR_RED, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	else
		draw.SimpleText("No V-NPC", "DermaLarge", width/2, height/2-20, DrGBase.CLR_RED, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		draw.SimpleText("selected", "DermaLarge", width/2, height/2+20, DrGBase.CLR_RED, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
end

if ( CLIENT ) then -- We can only use language.Add on client
	language.Add("tool.vnpc_weightgain.name", "Weight Gain" ) -- Add translation
	language.Add("tool.vnpc_weightgain.desc", "Click on an V-NPC to update to increase their bonescale by 0.1, alt-fire to decrease it by 0.1. Reload to completely reset their bonescaling." ) -- Add translation
	language.Add("tool.vnpc_weightgain.left", "Add Weight" ) -- Add translation
	language.Add("tool.vnpc_weightgain.right", "Remove Weight" ) -- Add translation
	language.Add("tool.vnpc_weightgain.reload", "Reset Weight" ) -- Add translation
end