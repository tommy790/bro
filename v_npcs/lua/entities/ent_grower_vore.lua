--[[
    BELLY MECHANICS USED IN PUR SLIME
]]

AddCSLuaFile()
ENT.Base = "ent_vore_belly" -- doesn't really change visuals or that many core mechanics, would just be reusing alot of code if it didn't extend from it

ENT.NPCScale = 1

function ENT:OnPreyAbsorbing(power, old_value, new_value)  --this is here so the npc grows and also gets rid of the belly fat, cus it goes to their actual form
    local npc = self.NPC
    if npc then
        npc:GainWeight(self.WeightGainAmount * power * 0.005) --we wanna gain over the course of absorbption
        self.NPCScale = self.NPCScale + power * 0.007
        npc:SetModelScale(self.NPCScale, 2)
    end    
end
 
local function getModelBounds(ent, scale)
    local _, max_bounds = ent:GetModelBounds()
    return max_bounds:Length() * ent:GetModelScale()
end

function ENT:EatCondition(prey) --slime girl cant eat something thats a bigger than her
    local preyValue = getModelBounds(prey)
    local ourValue = getModelBounds(self.NPC)
    print(preyValue, ourValue)
    return (preyValue ) < ourValue
end
