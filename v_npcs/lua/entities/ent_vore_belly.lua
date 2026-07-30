--[[
    This is the default entity for most vore npcs
]]

AddCSLuaFile()
AddCSLuaFile("belly_modules/mechanics.lua")
AddCSLuaFile("belly_modules/sounds.lua")
AddCSLuaFile("belly_modules/basic_visual.lua")
AddCSLuaFile("belly_modules/animations.lua")
AddCSLuaFile("belly_modules/npc.lua")

include("belly_modules/mechanics.lua")
include("belly_modules/sounds.lua")
include("belly_modules/basic_visual.lua")
include("belly_modules/npc.lua")

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.Spawnable = false

local force_fatcap = CreateConVar("vnpcs_global_fatcap", "0", {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED})

local belly_fat_multi = CreateConVar("vnpcs_fat_multi", 1, {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED})
local belly_fatcap_multi = CreateConVar("vnpcs_fatcap_multi", 1, {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED})

ENT.PreyStruggleMultiplier = 1.2

function ENT:Initialize()
	if SERVER then
        self:SetModel("models/wormonlooker/belly.mdl")
        self:SetSolid(SOLID_NONE)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetModelScale(1)
        self.NextVoreThink = CurTime()
    end
    self:CreateSounds()
end

function ENT:GainBellyFat(power)
    local newBase = self.BaseScale + (power * 0.007 * belly_fat_multi:GetFloat()) --magic number

    local max_scale = self.MaxBaseScale 
    if force_fatcap:GetBool() then
        max_scale = belly_fatcap_multi:GetFloat()
    else
        max_scale = max_scale * belly_fatcap_multi:GetFloat()
    end

    if newBase > max_scale then
        self:SetBaseScale(max_scale)
    else
        self:SetBaseScale(newBase)
    end
end

function ENT:OnPreyAdded() 
    self:PlaySwallowedSound()
end

function ENT:OnPreyKilled() 
    self:PlayFinalDigestSound()
end

function ENT:OnPreyAbsorbed() 
    self:PlayFinalAbsorbSound()
end

function ENT:OnPreyDigesting(prey_index, dmg) 
    if math.random() < 0.4 then
		self:PlayRandomGurgle()
    end
end 

--SET FUNCTIONS
function ENT:SetStruggleMultipler(num)
    self.PreyStruggleMultiplier = num
end

function ENT:SetFatFoldsMulti(num, num2)
    self:SetNWFloat("Fatfolds", math.max(num, 0.01))
    self:SetNWFloat("FatfoldsMulti", num2)
end

function ENT:SetStopClipFix(bool)
    self:SetNWBool("NoClipFix", bool)
end
--
function ENT:OnRemove()
    self:WipeAllPrey()
    self:StopAllSounds()
end

function ENT:SetProperties(props, npc) --alot of support for legacy, not very readable or automatic
    self:SetBaseScale(npc.BaseBellySize or props.BaseSize or 0)
	self:SetColor(npc._BellyColor or npc.BellyColor or props.BellyColor or Color(255,0,255))

	self:SetDigestionPower(npc.VoreSettings.DigestionStrength or props.DigestionStrength or 3)
	self:SetAbsorbPower(npc.VoreSettings.AbsorptionSpeed or props.AbsorptionPower or 2)
	--self:SetStruggleMultipler(npc.VoreSettings.StruggleMultiplier or props.StruggleMultiplier or 1.5) --THIS DOESNT DO ANYTHING SORRY .-.
	self:SetMaxScale(npc.VoreSettings.MaxBaseSize or props.MaxBaseSize or 0.5)
	self:SetFatFoldsMulti(npc.VoreSettings.FatFoldsMaxSize or props.FatFoldsMaxSize or 1, props.FatFoldsMulti or 1)
    self:SetStopClipFix(props.StopClipFix or false)

    if npc.BellyMaterial or props.BellyMaterial then
		self:SetMaterial(npc.BellyMaterial or props.BellyMaterial)
	elseif npc._BellyColor then --THIS IS FOR OLD NPCS
		self:SetMaterial("models/wormonlooker/belly/oldbelly")
	end

    self.WeightGainAmount = props.WeightGainAmount or 0.5
end

if not CLIENT then return end

function ENT:Draw()
    self:DrawModel() 
end
include("belly_modules/animations.lua")