ENT.BaseScale = 0 --AKA BELLY FAT LEFT OVER
ENT.MaxBaseScale = 0.5

-- Bounding-box belly shape: convert packed prey blob metrics into the scalar
-- belly scale the classic belly model / bone stretch path expects. Wider or
-- multi-body packs (from VNPC_DefaultBlobLayout) produce a larger scale than
-- a single small prey, so 2 similar bodies genuinely look like two people.
local function bellyScaleFromBlobMetrics(metrics)
    if not metrics then return 0 end
    local width = metrics.width or ((metrics.rx or 0) * 2)
    local depth = metrics.depth or ((metrics.ry or 0) * 2)
    local height = metrics.height or ((metrics.rz or 0) * 2)
    local footprint = math.max(width, 1) * math.max(depth, 1)
    local blobCount = (metrics.blobs and #metrics.blobs) or 1
    -- Footprint drives most of the growth; height and count add a bit more so
    -- stacked rows / taller prey also read as fuller.
    local scale = (footprint * 0.00115) + (height * 0.018) + (math.max(0, blobCount - 1) * 0.12)
    if metrics.totalMass and metrics.totalMass > 0 then
        scale = math.max(scale, metrics.totalMass * 0.0045)
    end
    if scale > 1 then
        scale = math.pow(scale, 0.55)
    end
    return math.Clamp(scale, 0, 4.5)
end

function ENT:GetBellySize() --this gets the scale of all the stuff in the stomach
    -- Ensure consuming prop meals causes ZERO belly expansion ONLY for male prey who chew or explicitly flagged non-expanding eaters
    if IsValid(self.NPC) and self.NPC.VNPC_NoBellyExpansionFromMeal and not (self.Prey and #self.Prey > 0) and not ((self.NPC.VNPC_FoodMealWeight or 0) > 0) then
        return self.BaseScale
    end

    local waterVal = (self.VNPC_WaterWeight or 0) + (IsValid(self.NPC) and (self.NPC.VNPC_WaterDrank or 0) or 0)
    local foodMealVal = (self.VNPC_FoodMealWeight or 0) + (IsValid(self.NPC) and (self.NPC.VNPC_FoodMealWeight or 0) or 0)

    -- Prefer bounding-box packed prey shape when weight paint is on.
    local scale = 0
    local paintEnabled = GetConVar("vnpcs_weight_paint_enabled")
    if (not paintEnabled or paintEnabled:GetBool()) and VNPC_GetBellyDeformMetrics and IsValid(self.NPC) then
        local metrics = VNPC_GetBellyDeformMetrics(self.NPC)
        if metrics then
            scale = bellyScaleFromBlobMetrics(metrics)
        end
    end

    -- Fallback / blend with classic collective-value scale (meals, water, props
    -- with no measured body parts still need a size).
    local totalVal = self:GetCollectivePreyValue() + waterVal + foodMealVal
    local valueScale = totalVal * 0.013
    if valueScale > 1 then
        valueScale = math.pow(valueScale, 0.5)
    end
    if scale <= 0 then
        scale = valueScale
    else
        -- Keep water/food contribution on top of the packed shape.
        local extras = (waterVal + foodMealVal) * 0.013
        scale = math.max(scale, valueScale * 0.55) + extras
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

    -- Keep client-side GPU belly / weight paint in sync with the packed layout.
    if SERVER and IsValid(self.NPC) and VNPC_SyncPaintBlobNW then
        local now = CurTime()
        if (self.VNPC_NextBlobSync or 0) <= now then
            self.VNPC_NextBlobSync = now + 0.35
            pcall(VNPC_SyncPaintBlobNW, self.NPC)
        end
    end
end

function ENT:SetBaseScale(num)
    self.BaseScale = num
    self:SetNWFloat("BaseScale", num)
end

function ENT:SetMaxScale(num)
    self.MaxBaseScale = num
end