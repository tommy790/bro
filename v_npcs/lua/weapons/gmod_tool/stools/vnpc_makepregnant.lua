
-- V-NPCs Make Pregnant tool
TOOL.Tab = "V-NPCs"
TOOL.Category = "Tools"
TOOL.Name = "#tool.vnpc_makepregnant.name"

TOOL.LeftClickAutomatic = false
TOOL.RightClickAutomatic = false
TOOL.RequiresTraceHit = true

TOOL.Information = {
	{ name = "left" },
	{ name = "right" },
	{ name = "reload" }
}

TOOL.ClientConVar["litter"] = "2"
TOOL.ClientConVar["growth"] = "28"
TOOL.ClientConVar["love"] = "70"

local function canBeMother(ent)
	if not IsValid(ent) then return false end
	if not (ent:IsNPC() or ent:IsNextBot() or ent:IsPlayer() or ent.IsDrGNextbot) then
		return false
	end
	if ent.VNPC_IsUnbornBaby or ent.VNPC_IsGrowingBaby or ent.VNPC_ProtectedChild then
		return false
	end
	if (ent.GetModelScale and ent:GetModelScale() or 1) < 0.95 then
		return false
	end
	if ent.Predator or ent.VNPC_FemaleModelVore or ent.IsDrGNextbot then
		return true
	end
	if VNPC_IsFemalePredator and VNPC_IsFemalePredator(ent) then
		return true
	end
	if VNPC_ModelLooksFemale and VNPC_ModelLooksFemale(ent) then
		return true
	end
	if VNPC_IsFemalePreyCitizen and VNPC_IsFemalePreyCitizen(ent) then
		return true
	end
	return false
end

local function clearPregnancy(ent)
	if not IsValid(ent) then return end
	local kids = {}
	if VNPC_GetUnbornLitter then
		kids = VNPC_GetUnbornLitter(ent) or {}
	elseif istable(ent.VNPC_UnbornChildren) then
		kids = ent.VNPC_UnbornChildren
	elseif IsValid(ent.VNPC_UnbornChild) then
		kids = { ent.VNPC_UnbornChild }
	end
	for _, child in ipairs(kids) do
		if IsValid(child) then
			if VNPC_RemoveWombPrey then
				VNPC_RemoveWombPrey(ent, child)
			else
				child:SetParent(nil)
				child:Remove()
			end
		end
	end
	ent.VNPC_IsPregnant = nil
	ent.VNPC_IsPregnantWithSister = nil
	ent.VNPC_IsPregnantWithCitizen = nil
	ent.VNPC_UnbornChild = nil
	ent.VNPC_UnbornChildren = nil
	ent.VNPC_BabyGrowthValue = nil
	ent.VNPC_LitterSize = nil
	ent.VNPC_PregnancyStartTime = nil
	ent.VNPC_LastGrowthTime = nil
	if VNPC_ResetPregnancyBellyBulge then
		VNPC_ResetPregnancyBellyBulge(ent)
	end
end

local function makePregnant(ent, litter, growth, love)
	if not IsValid(ent) then return false end
	litter = math.Clamp(math.floor(tonumber(litter) or 1), 1, 4)
	growth = math.Clamp(tonumber(growth) or 10, 10, 49.5)
	love = math.Clamp(tonumber(love) or 0, 0, 100)

	if love > 0 then
		ent.VNPC_MateLove = love
		if IsValid(ent.VNPC_LovedPartner) then
			ent.VNPC_LovedPartner.VNPC_MateLove = love
		end
		if IsValid(ent.VNPC_WildMate) then
			ent.VNPC_WildMate.VNPC_MateLove = love
		end
	end

	ent.VNPC_IsPregnant = true
	ent.VNPC_BabyGrowthValue = growth
	ent.VNPC_LastGrowthTime = CurTime()
	ent.VNPC_PregnancyStartTime = CurTime() - ((growth - 10) / 40) * 120
	ent.VNPC_LitterSize = litter

	if VNPC_EnsureUnbornLitter then
		VNPC_EnsureUnbornLitter(ent, litter)
	elseif VNPC_EnsureUnbornChild then
		VNPC_EnsureUnbornChild(ent, litter)
	end
	if VNPC_ApplyPregnancyBellyBulge then
		VNPC_ApplyPregnancyBellyBulge(ent, growth)
	end
	return true
end

function TOOL:LeftClick(tr)
	local ent = tr.Entity
	if not IsValid(ent) then return false end
	if CLIENT then return canBeMother(ent) end
	if not canBeMother(ent) then
		local ply = self:GetOwner()
		if IsValid(ply) then
			ply:ChatPrint("[V-NPCs] Aim at a female pred or female citizen to make them pregnant.")
		end
		return false
	end

	local litter = self:GetClientNumber("litter", 2)
	local growth = self:GetClientNumber("growth", 28)
	local love = self:GetClientNumber("love", 70)
	if not makePregnant(ent, litter, growth, love) then return false end

	local effectdata = EffectData()
	effectdata:SetOrigin(tr.HitPos)
	util.Effect("inflator_magic", effectdata)

	local ply = self:GetOwner()
	if IsValid(ply) then
		ply:ChatPrint(string.format("[V-NPCs] Made %s pregnant (litter %d, growth %.0f/50).", tostring(ent), math.floor(litter), growth))
	end
	return true
end

function TOOL:RightClick(tr)
	local ent = tr.Entity
	if not IsValid(ent) then return false end
	if CLIENT then return ent:IsNPC() or ent:IsNextBot() or ent:IsPlayer() or ent.IsDrGNextbot end
	if not (ent:IsNPC() or ent:IsNextBot() or ent:IsPlayer() or ent.IsDrGNextbot) then
		return false
	end
	if not (ent.VNPC_IsPregnant or ent.VNPC_IsPregnantWithSister or ent.VNPC_IsPregnantWithCitizen or IsValid(ent.VNPC_UnbornChild)) then
		local ply = self:GetOwner()
		if IsValid(ply) then
			ply:ChatPrint("[V-NPCs] That NPC is not pregnant.")
		end
		return false
	end

	clearPregnancy(ent)
	local ply = self:GetOwner()
	if IsValid(ply) then
		ply:ChatPrint("[V-NPCs] Cleared pregnancy on " .. tostring(ent) .. ".")
	end
	return true
end

function TOOL:Reload(tr)
	local ent = tr.Entity
	if not IsValid(ent) then return false end
	if CLIENT then return canBeMother(ent) end
	if not canBeMother(ent) then return false end

	if not ent.VNPC_IsPregnant then
		local litter = self:GetClientNumber("litter", 2)
		local love = self:GetClientNumber("love", 70)
		makePregnant(ent, litter, 48, love)
	end

	local camp = nil
	if VNPC_GetPreyCamp then
		camp = VNPC_GetPreyCamp(ent)
	end
	if VNPC_StartChildbirthAnimation then
		VNPC_StartChildbirthAnimation(ent, ent.VNPC_UnbornChild, camp)
	elseif VNPC_WildGiveBirth then
		VNPC_WildGiveBirth(ent)
	end

	local ply = self:GetOwner()
	if IsValid(ply) then
		ply:ChatPrint("[V-NPCs] Started childbirth on " .. tostring(ent) .. ".")
	end
	return true
end

function TOOL.BuildCPanel(CPanel)
	CPanel:Help("#tool.vnpc_makepregnant.desc")
	CPanel:NumSlider("#tool.vnpc_makepregnant.litter", "vnpc_makepregnant_litter", 1, 4, 0)
	CPanel:ControlHelp("How many unborn babies to create. Birth sits longer for larger litters.")
	CPanel:NumSlider("#tool.vnpc_makepregnant.growth", "vnpc_makepregnant_growth", 10, 49, 0)
	CPanel:ControlHelp("Womb growth 10-50. Birth starts at 50. Higher values show a bigger pregnancy bulge.")
	CPanel:NumSlider("#tool.vnpc_makepregnant.love", "vnpc_makepregnant_love", 0, 100, 0)
	CPanel:ControlHelp("Sets mate love on the mother. Used by the existing litter/mating system.")
end

if CLIENT then
	language.Add("tool.vnpc_makepregnant.name", "Make Pregnant")
	language.Add("tool.vnpc_makepregnant.desc", "Left click a female pred or female citizen to make her pregnant. Right click clears it. Reload starts childbirth.")
	language.Add("tool.vnpc_makepregnant.left", "Make pregnant")
	language.Add("tool.vnpc_makepregnant.right", "Clear pregnancy")
	language.Add("tool.vnpc_makepregnant.reload", "Start childbirth")
	language.Add("tool.vnpc_makepregnant.litter", "Litter size")
	language.Add("tool.vnpc_makepregnant.growth", "Womb growth")
	language.Add("tool.vnpc_makepregnant.love", "Mate love")
end
