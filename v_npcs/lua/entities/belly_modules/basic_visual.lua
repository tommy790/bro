ENT.BaseScale = 0 --AKA BELLY FAT LEFT OVER
ENT.MaxBaseScale = 0.5

function ENT:GetBellySize() --this gets the scale of all the stuff in the stomach
    local scale = self:GetCollectivePreyValue() * 0.013 --no meaning number

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
    self:SetNWFloat("BellySize", self:GetBellySize())
end

function ENT:SetBaseScale(num)
    self.BaseScale = num
    self:SetNWFloat("BaseScale", num)
end

function ENT:SetMaxScale(num)
    self.MaxBaseScale = num
end