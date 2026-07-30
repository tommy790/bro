local belly_fat_loss = CreateConVar("vnpcs_belly_fat_lose", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED})
local weight_loss = CreateConVar("vnpcs_weight_loss", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED})

local global_heal_multi = CreateConVar("vnpcs_absorptionheal_multi", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED})

ENT.WeightGainAmount = 0.5 --for each absorbption
ENT.NextVoreThink = 0

function ENT:NPCThink() --this has to be called by an npc
    --calls every 0.5 seconds
    local c_time = CurTime()
	if c_time < self.NextVoreThink then return end
    local dt = 0.5 --tried to make this actually based on dt but im dumb

	self.NextVoreThink = c_time + 0.5
    --
    local npc = self.NPC

    local living_prey, prey_in_total, total_heal = self:DigestPrey(dt)
    local is_absorbing = self:AbsorbPrey(dt)
    if npc then --burpin' while absorbin'
        if total_heal and total_heal > 0 then
            total_heal = total_heal * global_heal_multi:GetFloat() * 0.1
            npc:SetHealth(npc:Health() + total_heal) --absorption will exceed max health because game design or something
        end

        if is_absorbing and self.NextSoundTime and self.NextSoundTime < c_time then
            npc:Burp(false)
            self.NextSoundTime = c_time + math.Rand(5, 10)
        end
    end

    if is_absorbing == false and prey_in_total == 0 then
        self:LoseWeight(dt)
    end

    self:SetBellySize() 
end

function ENT:OnPreyAbsorbing(power, old_value, new_value) 
    if self.NPC then
        self.NPC:GainWeight(self.WeightGainAmount * power * 0.006) --we wanna gain over the course of absorbption
    end
    self:GainBellyFat(power)
end

function ENT:OnDigestionPhaseChanged(new, old)
    if new == 0 and old == 2 then --from absorbing to empty/hungry
        self:StopDigestionSound()
        self:StopAbsorbSound()

        self.NextSoundTime = nil 

        if self.NPC then
            self.NPC:Burp(true) --no checks, just rawdogging this
        end
    end

    if new == 2 and old == 1 then --from digesting to abosrbing
        self.NextSoundTime = CurTime() + math.Rand(5, 10)
        self:StartAbsorbSound()

        if self.NPC then       
            self.NPC:SetFacialExpression(2)
        end
    end

    if new == 1 and old == 0 then
        self:StartDigestionSound()
    end
end

function ENT:LoseWeight(dt)
    if self.BaseScale > 0 then
        local belly_fat_loss = self.AbsorptionPower * belly_fat_loss:GetFloat() * 0.0035 * dt * 2
        if belly_fat_loss > 0 then
            self:SetBaseScale(self.BaseScale - belly_fat_loss, self.BaseScale)

            if self.BaseScale <= 0 then
                self:SetBaseScale(0)
            end
        end
    end

    local npc = self.NPC
    if not npc then return end

    if npc.BoneScale > 1 then
        local loss = self.AbsorptionPower * weight_loss:GetFloat() * 0.008 * dt * 2
        if loss > 0 then
            npc:GainWeight(-loss) --high metabolism
        end

        if npc.BoneScale <= 1 then --stupid
            npc.BoneScale = 1
        end
    end
end