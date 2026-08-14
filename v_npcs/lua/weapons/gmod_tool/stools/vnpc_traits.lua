-- V-NPCs Trait Editor tool
-- Aim at any V-NPC (predator or prey) and left-click to open the modular
-- Status & Trait editor for that NPC. Right-click opens it for the nearest
-- eligible NPC.

TOOL.Tab = "V-NPCs"
TOOL.Category = "Tools"
TOOL.Name = "#tool.vnpc_traits.name"
TOOL.Command = nil
TOOL.ConfigName = nil

TOOL.LeftClickAutomatic = false
TOOL.RightClickAutomatic = false
TOOL.RequiresTraceHit = true

TOOL.Information = {
	{ name = "left" },
	{ name = "right" }
}

local function isTraitEligible(ent)
	if not IsValid(ent) then return false end
	if ent:IsPlayer() then return false end
	return ent:IsNPC() or ent:IsNextBot() or ent.IsDrGNextbot
end

function TOOL:LeftClick(tr)
	local ent = tr.Entity
	if not isTraitEligible(ent) then return false end
	if CLIENT then
		RunConsoleCommand("vnpcs_trait_menu_open", tostring(ent:EntIndex()))
		return true
	end
	local ply = self:GetOwner()
	if IsValid(ply) then
		ply:ChatPrint("[V-NPCs] Trait editor opened for " .. tostring(ent) .. " (client-side window).")
	end
	return true
end

function TOOL:RightClick(tr)
	if CLIENT then return true end
	-- server side: nothing to do; the menu is client-side
	return true
end

function TOOL.BuildCPanel(CPanel)
	CPanel:Help("Left-click an NPC to open its Status & Trait editor.")
	CPanel:Help("Assign traits like Fast Metabolism, Acid Resistant, Big Stomach, Tireless and more. Conflicts resolve automatically.")
	CPanel:Button("Open Editor (Aimed NPC)", "vnpcs_trait_menu_open")
	CPanel:Help("You can also open the full editor from the spawn menu under V-NPCs -> Status & Traits.")
end

if CLIENT then
	language.Add("tool.vnpc_traits.name", "Trait Editor")
	language.Add("Tool.vnpc_traits.left", "Open the trait/status editor for the aimed NPC")
	language.Add("Tool.vnpc_traits.right", "No action (editor is client-side)")
	language.Add("Tool.vnpc_traits.desc", "Assign and remove RPG-style traits on V-NPCs")
	language.Add("Tool.vnpc_traits.0", "Aim at a V-NPC and left-click to edit its traits.")
end
