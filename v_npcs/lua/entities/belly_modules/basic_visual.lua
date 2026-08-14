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
    simulation involved. Every currently-occupying body (prey still
    struggling, prey being digested, or even swallowed props/objects)
    contributes its own bounding box, shrinking down once it actually starts
    getting absorbed. Those boxes get packed "shoulder to shoulder" into
    rows (like laying boxes down on a shelf), and the resulting packed
    footprint is compared against what a single body of equivalent bulk
    would need, to get a width/depth/height bias around (1,1,1).

    Two prey of similar size packed into one row means the belly reads as
    genuinely wider (their real shoulder-to-shoulder widths add together)
    instead of just a rounder single blob. Once a row gets too wide for more
    bodies to realistically fit, the next body spills into a second row,
    which adds depth instead of making the belly absurdly wide. It's
    deterministic and stable frame to frame - the only smoothing happens
    client-side via the existing Lerp on the networked BellyShape vector.
]]

--Source model bounds are in model space: X = forward/back (depth/thickness),
--Y = left/right (width), Z = up/down (height). Keep that straight here so
--"packing shoulder to shoulder" actually sums real shoulder width and not
--how thick someone's chest is.
local EXT_WIDTH, EXT_DEPTH, EXT_HEIGHT = "y", "x", "z"

local MAX_PACKED = 8 --hard cap so a huge chain-eaten group can't produce an absurd shape
local MIN_REMAINING = 0.03 --below this fraction left, treat a body as fully gone

local function getPackedPreyBoxes(self)
    local boxes = {}

    for _, info in ipairs(self.Prey) do
        local ext = info.HalfExtents
        if not ext then continue end

        -- While still struggling (or an inanimate object waiting its turn),
        -- the body is fully present - digestion damage doesn't shrink its
        -- physical bulk yet. Only once it's actually being absorbed
        -- (info.Absorbing) does its Value count down towards 0, so shrink
        -- proportionally to that instead of popping out of the shape
        -- instantly the moment absorption starts.
        local remaining = 1
        if info.Absorbing and info.TrueValue and info.TrueValue > 0 then
            remaining = math.Clamp(info.Value / info.TrueValue, 0, 1)
        end

        if remaining < MIN_REMAINING then continue end

        local shrink = remaining ^ (1 / 3) --volume-correct shrink, not linear
        table.insert(boxes, Vector(ext.x * shrink, ext.y * shrink, ext.z * shrink))
    end

    -- biggest bodies define the silhouette; a couple of tiny mostly-digested
    -- leftovers shouldn't be allowed to dominate the packing
    table.sort(boxes, function(a, b) return a:Length() > b:Length() end)

    return boxes
end

--[[
    First-fit-decreasing shelf packing: bodies are added to the current row
    until adding one more would overflow that row's width budget, then a new
    row starts. The width budget is adaptive (based on how wide bodies here
    actually are) instead of a fixed headcount, so e.g. three children pack
    into one row much more readily than three adult-sized bodies would, and
    one huge body can still always claim a row to itself.
]]
local function packBoxesIntoRows(boxes)
    if #boxes == 0 then return {} end

    local totalWidth, biggestWidth = 0, 0
    for _, ext in ipairs(boxes) do
        local width = ext[EXT_WIDTH] * 2
        totalWidth = totalWidth + width
        biggestWidth = math.max(biggestWidth, width)
    end

    local avgWidth = totalWidth / #boxes
    local maxRowWidth = math.max(avgWidth * 3.3, biggestWidth * 1.05)

    local rows = {}
    local row = {width = 0, depth = 0, height = 0, count = 0}

    for i = 1, math.min(#boxes, MAX_PACKED) do
        local ext = boxes[i]
        local width, depth, height = ext[EXT_WIDTH] * 2, ext[EXT_DEPTH] * 2, ext[EXT_HEIGHT] * 2

        if row.count > 0 and (row.width + width) > maxRowWidth then
            table.insert(rows, row)
            row = {width = 0, depth = 0, height = 0, count = 0}
        end

        row.width = row.width + width
        row.depth = math.max(row.depth, depth)
        row.height = math.max(row.height, height)
        row.count = row.count + 1
    end
    table.insert(rows, row)

    return rows
end

function ENT:GetBellyShapeVector()
    if not shape_deform_enabled:GetBool() then return Vector(1, 1, 1) end
    if #self.Prey == 0 then return Vector(1, 1, 1) end

    local boxes = getPackedPreyBoxes(self)
    if #boxes == 0 then return Vector(1, 1, 1) end

    local rows = packBoxesIntoRows(boxes)
    if #rows == 0 then return Vector(1, 1, 1) end

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
        math.Clamp(packedWidth / mean, 0.65, 2.6),
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

