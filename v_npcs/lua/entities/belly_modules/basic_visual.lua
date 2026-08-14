ENT.BaseScale = 0 --AKA BELLY FAT LEFT OVER
ENT.MaxBaseScale = 0.5

local shape_deform_enabled = CreateConVar("vnpcs_shape_deform", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED})

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

    Purely geometric, bounding-box driven belly shape - no physics
    simulation involved. Every living, non-absorbing prey contributes its
    own bounding box (shrunk down as it digests). Those boxes get packed
    "shoulder to shoulder" into rows (like laying boxes down in a shelf),
    and the resulting packed footprint is compared against what a single
    body of equivalent bulk would need to get a width/depth/height bias
    around (1,1,1).

    Two prey of similar size packed into one row means the belly reads as
    genuinely wider (their widths add together) instead of just a rounder
    single blob. A bigger group spills into a second row, which adds depth
    instead of making the belly absurdly wide. It's deterministic and
    stable frame to frame - the only smoothing happens client-side via the
    existing Lerp on the networked BellyShape vector.
]]
local ROW_CAPACITY = 3 --how many bodies fit "shoulder to shoulder" before starting a new row
local MAX_PACKED = 6 --hard cap so a huge chain-eaten group can't produce an absurd shape

local function getPackedPreyBoxes(self)
    local boxes = {}

    for _, info in ipairs(self.Prey) do
        if info.Absorbing or not info.Alive then continue end

        local ent = info.Entity
        if not IsValid(ent) then continue end

        local ext = info.HalfExtents or Vector(8, 8, 8)

        -- shrink the occupied footprint as it gets digested, so mostly
        -- absorbed prey stop holding the belly's shape open
        local remaining = 1
        if info.TrueValue and info.TrueValue > 0 then
            remaining = math.Clamp(info.Value / info.TrueValue, 0.2, 1)
        end
        local shrink = remaining ^ (1 / 3)

        table.insert(boxes, Vector(ext.x * shrink, ext.y * shrink, ext.z * shrink))
    end

    -- biggest bodies define the silhouette; a couple of tiny mostly-digested
    -- leftovers shouldn't be allowed to dominate the packing
    table.sort(boxes, function(a, b) return a:Length() > b:Length() end)

    return boxes
end

function ENT:GetBellyShapeVector()
    if not shape_deform_enabled:GetBool() then return Vector(1, 1, 1) end
    if #self.Prey == 0 then return Vector(1, 1, 1) end

    local boxes = getPackedPreyBoxes(self)
    if #boxes == 0 then return Vector(1, 1, 1) end

    local rows = {}
    local row = {width = 0, depth = 0, height = 0, count = 0}

    for i = 1, math.min(#boxes, MAX_PACKED) do
        local ext = boxes[i]

        if row.count >= ROW_CAPACITY then
            table.insert(rows, row)
            row = {width = 0, depth = 0, height = 0, count = 0}
        end

        row.width = row.width + ext.x * 2
        row.depth = math.max(row.depth, ext.y * 2)
        row.height = math.max(row.height, ext.z * 2)
        row.count = row.count + 1
    end
    table.insert(rows, row)

    local packedWidth, packedDepth, packedHeight = 0, 0, 0
    for _, r in ipairs(rows) do
        packedWidth = math.max(packedWidth, r.width)
        packedDepth = packedDepth + r.depth
        packedHeight = math.max(packedHeight, r.height)
    end

    if packedWidth <= 0 or packedDepth <= 0 or packedHeight <= 0 then
        return Vector(1, 1, 1)
    end

    -- normalize by the geometric mean so this only biases the *shape*
    -- (aspect ratio); overall size is still handled by GetBellySize()
    local mean = (packedWidth * packedDepth * packedHeight) ^ (1 / 3)
    if mean <= 0 then return Vector(1, 1, 1) end

    return Vector(
        math.Clamp(packedWidth / mean, 0.65, 2.4),
        math.Clamp(packedDepth / mean, 0.65, 1.8),
        math.Clamp(packedHeight / mean, 0.65, 1.6)
    )
end

function ENT:SetBellySize()
    self:SetNWFloat("BellySize", self:GetBellySize())
    self:SetNWVector("BellyShape", self:GetBellyShapeVector())
end

function ENT:SetBaseScale(num)
    self.BaseScale = num
    self:SetNWFloat("BaseScale", num)
end

function ENT:SetMaxScale(num)
    self.MaxBaseScale = num
end

