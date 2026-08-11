ENT.BaseScale = 0 --AKA BELLY FAT LEFT OVER
ENT.MaxBaseScale = 0.5

function ENT:GetBellySize() --this gets the scale of all the stuff in the stomach
    -- Ensure consuming prop meals causes ZERO belly expansion ONLY for male prey who chew or explicitly flagged non-expanding eaters
    if IsValid(self.NPC) and self.NPC.VNPC_NoBellyExpansionFromMeal and not (self.Prey and #self.Prey > 0) and not ((self.NPC.VNPC_FoodMealWeight or 0) > 0) then
        return self.BaseScale
    end

    local waterVal = (self.VNPC_WaterWeight or 0) + (IsValid(self.NPC) and (self.NPC.VNPC_WaterDrank or 0) or 0)
    local foodMealVal = (self.VNPC_FoodMealWeight or 0) + (IsValid(self.NPC) and (self.NPC.VNPC_FoodMealWeight or 0) or 0)
    local totalVal = self:GetCollectivePreyValue() + waterVal + foodMealVal
    local scale = totalVal * 0.013 --no meaning number

    if scale > 1 then
        scale = math.pow(scale, 0.5) 
    end

    if scale == 0 then
        return self.BaseScale
    end

	local target = math.max(scale, self.BaseScale)
	local delta = target - self.BaseScale
	local blend = 1 - math.exp(-delta * 3) 
	local adjustedScale = self.BaseScale + delta * blend

    return adjustedScale
end

function ENT:SetBellySize()
    local target = self:GetBellySize()
    self.VNPC_LastSetBellySize = target
    self:SetNWFloat("BellySize", target)
end

function ENT:SetBaseScale(num)
    self.BaseScale = num
    self:SetNWFloat("BaseScale", num)
end

function ENT:SetMaxScale(num)
    self.MaxBaseScale = num
end