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

--[[
    DYNAMIC WEIGHT PAINTING & MESH DEFORM

    Instead of just inflating the belly uniformly, this looks at the actual
    shape (width/depth/height) of whatever is currently inside and returns a
    bias vector around (1,1,1). A short, wide prey pushes the belly out
    sideways more than up; a tall prey does the opposite. This is what lets
    one generic belly model adapt to almost any swallowed entity without a
    bespoke pre-made shape for it.
]]
function ENT:GetBellyShapeVector()
    if #self.Prey == 0 then return Vector(1, 1, 1) end

    local widthSum, depthSum, heightSum, weightSum = 0, 0, 0, 0
    for _, info in ipairs(self.Prey) do
        if info.Absorbing then continue end

        local ext = info.HalfExtents or Vector(8, 8, 8)
        local weight = math.max(info.Value, 1)

        widthSum = widthSum + ext.x * weight
        depthSum = depthSum + ext.y * weight
        heightSum = heightSum + ext.z * weight
        weightSum = weightSum + weight
    end

    if weightSum <= 0 then return Vector(1, 1, 1) end

    local avgWidth, avgDepth, avgHeight = widthSum / weightSum, depthSum / weightSum, heightSum / weightSum
    local avg = (avgWidth + avgDepth + avgHeight) / 3
    if avg <= 0 then return Vector(1, 1, 1) end

    local shape = Vector(
        math.Clamp(avgWidth / avg, 0.7, 1.6),
        math.Clamp(avgDepth / avg, 0.7, 1.6),
        math.Clamp(avgHeight / avg, 0.7, 1.6)
    )

    --[[ MULTI-OCCUPANT SHAPE ]]
    --2+ prey of the same species widen/elongate the belly instead of just
    --getting rounder, so it reads like there's more than one body in there.
    local groupCount = self:GetLargestPreyGroup()
    if groupCount >= 2 then
        local widen = 1 + math.min(groupCount - 1, 3) * 0.14
        shape.x = math.Clamp(shape.x * widen, 0.7, 2.2)
        shape.y = math.Clamp(shape.y * widen, 0.7, 2.2)
    end

    return shape
end

function ENT:SetBellySize()
    self:SetNWFloat("BellySize", self:GetBellySize())
    self:SetNWVector("BellyShape", self:GetBellyShapeVector())

    local occupantCount = self:GetLargestPreyGroup()
    self:SetNWInt("BellyOccupants", occupantCount)
end


function ENT:SetBaseScale(num)
    self.BaseScale = num
    self:SetNWFloat("BaseScale", num)
end

function ENT:SetMaxScale(num)
    self.MaxBaseScale = num
end
