
-- Define these!
TOOL.Tab = "V-NPCs"
TOOL.Category = "Tools" -- Name of the category
TOOL.Name = "#tool.vnpc_eatent.name" -- Name to display. # means it will be translated ( see below )

TOOL.LeftClickAutomatic = false 
TOOL.RightClickAutomatic = false 
TOOL.RequiresTraceHit = true

TOOL.Information = {
	{ name = "left"},
	{ name = "right"},
	{ name = "reload"}
}

local function chaseGuy(pred, prey, owner)
	pred:ClearPatrols()
	
	pred:SetEntityRelationship(prey, D_HT, 99999)
	pred:SetEnemy(prey)
	pred:SpotEntity(prey)
end

function TOOL:LeftClick( tr )
	local ent = tr.Entity
	local owner = self:GetOwner()

	if owner.SelectedPred then
		if IsValid(owner.SelectedPred) then
			local pred = owner.SelectedPred
			if ent == pred then return end
			if not IsValid(ent) then return end

			chaseGuy(pred, ent, owner)
			return true 
		else
			owner.SelectedPred = nil 
		end
	end

	if not IsValid(ent) or not ent.Predator then return end

	owner.SelectedPred = ent
	return true
end

function TOOL:RightClick( tr )
	local ent = tr.Entity
	local owner = self:GetOwner()
	owner.SelectedPred = nil 
	return true 
end

function TOOL:Reload( tr )
	local ent = tr.Entity
	local owner = self:GetOwner()

	if owner.SelectedPred then
		if IsValid(owner.SelectedPred) then
			local pred = owner.SelectedPred
			if not IsValid(owner) then return end
			chaseGuy(pred, owner, owner)

			return true 
		else
			owner.SelectedPred = nil 
		end
	end

	if not IsValid(ent) or not ent.Predator then return end

	owner.SelectedPred = ent
	chaseGuy(owner.SelectedPred, owner, owner)

	return true
end

function TOOL.BuildCPanel( CPanel )
	CPanel:Help( "#tool.vnpc_eatent.desc" )
end

if ( CLIENT ) then -- We can only use language.Add on client
	language.Add("tool.vnpc_eatent.name", "Eat Entity" ) -- Add translation
	language.Add("tool.vnpc_eatent.desc", "Click on an V-NPC, and click on an another entity. This will make the V-NPC follow and try and eat the entity." ) -- Add translation
	language.Add("tool.vnpc_eatent.left", "Select Predator/Select Prey" ) -- Add translation
	language.Add("tool.vnpc_eatent.right", "Unselect Predator" ) -- Add translation
	language.Add("tool.vnpc_eatent.reload", "Select Self as Prey" ) -- Add translation
end