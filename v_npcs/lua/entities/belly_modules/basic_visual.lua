ENT.BaseScale = 0 --AKA BELLY FAT LEFT OVER
ENT.MaxBaseScale = 0.5

local shape_deform_enabled = CreateConVar("vnpcs_shape_deform", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "Shape-aware belly deform from packed prey bounding boxes")
-- Classic belly model treats size 1.0 ≈ 36 hammer-units across (radius ~18).
local BELLY_SIZE_REF_RADIUS = 18
CreateConVar("vnpcs_belly_size_from_prey", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Size the belly procedurally from measured/packed prey volume instead of the old value*0.013 sqrt curve")
CreateConVar("vnpcs_belly_size_scale", "1.0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Global multiplier on procedural / value-based belly size")
CreateConVar("vnpcs_belly_value_to_size", "0.022", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Fallback: prey-value units → belly size when measured extents are unavailable")

-- Procedural belly scale from packed prey half-extents / metaball metrics.
-- Returns nil when there is nothing to measure yet.
function ENT:GetProceduralBellySizeFromPrey()
    local fromPrey = GetConVar("vnpcs_belly_size_from_prey")
    if fromPrey and not fromPrey:GetBool() then return nil end

    local best = 0

    -- 1) Live weight-paint / metaball metrics on the predator (preferred).
    local pred = self.NPC
    if IsValid(pred) and VNPC_GetBellyDeformMetrics then
        local m = VNPC_GetBellyDeformMetrics(pred)
        if m then
            local meanHalf = ((m.rx or 0) + (m.ry or 0) + (m.rz or 0)) / 3
            if meanHalf > 0 then
                best = math.max(best, meanHalf / BELLY_SIZE_REF_RADIUS)
            end
            if m.volRadius and m.volRadius > 0 then
                best = math.max(best, m.volRadius / BELLY_SIZE_REF_RADIUS)
            end
            -- Diagonal of the packed AABB → diameter → size
            if m.width and m.depth and m.height then
                local diag = math.sqrt(m.width * m.width + m.depth * m.depth + m.height * m.height)
                best = math.max(best, (diag * 0.42) / BELLY_SIZE_REF_RADIUS)
            end
        end
    end

    -- 2) Direct sum of stored HalfExtents on each prey entry (works even before paint sync).
    if istable(self.Prey) and #self.Prey > 0 then
        local maxHalf = 0
        local volSum = 0
        local n = 0
        for _, info in ipairs(self.Prey) do
            if not istable(info) then continue end
            local remaining = 1
            if info.Absorbing and info.TrueValue and info.TrueValue > 0 then
                remaining = math.Clamp((info.Value or 0) / info.TrueValue, 0, 1)
            end
            if remaining < 0.04 then continue end
            local shrink = remaining ^ (1 / 3)
            local ext = info.HalfExtents
            -- While still sliding in, keep most of the measured bulk so the
            -- belly swells with the meal instead of staying tiny until finish.
            local depthMul = 1
            local ent = info.Entity
            if IsValid(ent) and ent.VNPC_IsBeingSwallowed and ent.VNPC_IngestionDepth then
                depthMul = math.Clamp(0.55 + 0.45 * math.Clamp(ent.VNPC_IngestionDepth, 0, 1), 0.55, 1)
            end
            shrink = shrink * depthMul

            if isvector(ext) then
                local hx = math.abs(ext.x) * shrink
                local hy = math.abs(ext.y) * shrink
                local hz = math.abs(ext.z) * shrink
                local mean = (hx + hy + hz) / 3
                maxHalf = math.max(maxHalf, mean)
                volSum = volSum + math.max(hx * hy * hz, 1)
                n = n + 1
            elseif IsValid(info.Entity) and VNPC_MeasureBodyParts then
                local parts = VNPC_MeasureBodyParts(info.Entity)
                if parts and parts.torso then
                    local tw = (parts.torso.width or 14) * 0.5 * shrink
                    local th = (parts.torso.height or 16) * 0.5 * shrink
                    local tl = (parts.torso.length or 20) * 0.35 * shrink
                    local mean = (tw + th + tl) / 3
                    maxHalf = math.max(maxHalf, mean)
                    volSum = volSum + math.max(tw * th * tl, 1)
                    n = n + 1
                end
            end
        end
        if n > 0 then
            best = math.max(best, maxHalf / BELLY_SIZE_REF_RADIUS)
            -- Multi-prey volume add: cube-root so 2 humans ≈ +26% radius not 2×
            local packR = (volSum) ^ (1 / 3) * 1.15
            best = math.max(best, packR / BELLY_SIZE_REF_RADIUS)
        end
    end

    if best <= 0 then return nil end
    -- One adult human curled in the gut should read around size 1.1–1.6, not 0.3.
    return math.Clamp(best * 1.35, 0.08, 6.5)
end

function ENT:GetBellySize() --this gets the scale of all the stuff in the stomach
    -- Ensure consuming prop meals causes ZERO belly expansion ONLY for male prey who chew or explicitly flagged non-expanding eaters
    if IsValid(self.NPC) and self.NPC.VNPC_NoBellyExpansionFromMeal and not (self.Prey and #self.Prey > 0) and not ((self.NPC.VNPC_FoodMealWeight or 0) > 0) then
        return self.BaseScale
    end

    local waterVal = (self.VNPC_WaterWeight or 0) + (IsValid(self.NPC) and (self.NPC.VNPC_WaterDrank or 0) or 0)
    local foodMealVal = (self.VNPC_FoodMealWeight or 0) + (IsValid(self.NPC) and (self.NPC.VNPC_FoodMealWeight or 0) or 0)
    local totalVal = self:GetCollectivePreyValue() + waterVal + foodMealVal

    -- Fallback value curve (milder than the old value*0.013 + hard sqrt).
    local valueCoef = 0.022
    local coefCv = GetConVar("vnpcs_belly_value_to_size")
    if coefCv then valueCoef = coefCv:GetFloat() or valueCoef end
    local valueScale = totalVal * valueCoef
    -- Soft compression only for enormous multi-prey totals (keeps 1 human ~ full belly).
    if valueScale > 1.8 then
        valueScale = 1.8 + math.pow(valueScale - 1.8, 0.62) * 0.72
    end

    -- Procedural size from measured prey geometry (dominates when available).
    local procScale = self:GetProceduralBellySizeFromPrey()
    local scale = valueScale
    if procScale and procScale > 0 then
        scale = math.max(valueScale * 0.55, procScale)
    end

    local globalMul = 1.0
    local mulCv = GetConVar("vnpcs_belly_size_scale")
    if mulCv then globalMul = math.max(0.1, mulCv:GetFloat() or 1) end
    scale = scale * globalMul

    if scale <= 0 and waterVal <= 0 and foodMealVal <= 0 then
        return self.BaseScale
    end

    local target = math.max(scale, self.BaseScale)
    local delta = target - self.BaseScale
    local blend = 1 - math.exp(-math.max(delta, 0.05) * 2.4)
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

    for _, info in ipairs(self.Prey or {}) do
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
    if not self.Prey or #self.Prey == 0 then return Vector(1, 1, 1) end

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
    local target = self:GetBellySize()
    self.VNPC_LastSetBellySize = target
    self:SetNWFloat("BellySize", target)
    self:SetNWVector("BellyShape", self:GetBellyShapeVector())

    -- Keep client-side GPU belly / weight paint in sync when that path is present.
    if SERVER and IsValid(self.NPC) and VNPC_SyncPaintBlobNW then
        local now = CurTime()
        if (self.VNPC_NextBlobSync or 0) <= now then
            self.VNPC_NextBlobSync = now + 0.35
            self.NPC.VNPC_BellyBlobMetrics = nil
            self.NPC.VNPC_BellyBlobs = nil
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
