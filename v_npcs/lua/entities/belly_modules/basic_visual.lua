ENT.BaseScale = 0 --AKA BELLY FAT LEFT OVER
ENT.MaxBaseScale = 0.5

--[[
    BOUNDING-BOX BELLY SHAPE SYSTEM (enhanced)

    Pure geometry — no physics sim. Every occupant contributes a bounding box
    (from model bounds and/or measured body parts at swallow time). Boxes pack
    shoulder-to-shoulder into adaptive shelves; overflow starts a new row that
    adds depth. The packed footprint is turned into a width/depth/height bias
    networked as BellyShape, applied client-side on the belly bone scale.

    Enhancements over the base packer:
      * fetal-curl humanoid extents (shoulder width vs curled depth)
      * soft nest packing (bodies share some volume instead of pure sum)
      * multi-body silhouette boost so 2 similar prey clearly reads as two
      * single-body reference normalization (shape relative to largest prey)
      * row stacking adds height as well as depth
      * live re-measure fallback if HalfExtents was missing
      * tunable intensity / nest / multi-body convars
]]

local shape_deform_enabled = CreateConVar("vnpcs_shape_deform", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "Shape-aware belly deform from packed prey bounding boxes")
local shape_intensity = CreateConVar("vnpcs_shape_intensity", "1.35", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "How strongly multi-prey packing stretches the belly shape (1 = mild, 2 = extreme)")
local shape_nest = CreateConVar("vnpcs_shape_nest", "0.78", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "How tightly packed bodies nest into each other (0.55 = snug, 1.0 = no nesting / pure sum)")
local shape_multibody = CreateConVar("vnpcs_shape_multibody", "1.45", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Extra silhouette boost when 2+ full-size bodies are inside")
local shape_max_width = CreateConVar("vnpcs_shape_max_width", "3.2", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Max width bias clamp for belly shape")
local shape_max_depth = CreateConVar("vnpcs_shape_max_depth", "2.4", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Max depth bias clamp for belly shape")
local shape_max_height = CreateConVar("vnpcs_shape_max_height", "2.0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Max height bias clamp for belly shape")

function ENT:GetBellySize() --this gets the scale of all the stuff in the stomach
    -- Ensure consuming prop meals causes ZERO belly expansion ONLY for male prey who chew or explicitly flagged non-expanding eaters
    if IsValid(self.NPC) and self.NPC.VNPC_NoBellyExpansionFromMeal and not (self.Prey and #self.Prey > 0) and not ((self.NPC.VNPC_FoodMealWeight or 0) > 0) then
        return self.BaseScale
    end

    local waterVal = (self.VNPC_WaterWeight or 0) + (IsValid(self.NPC) and (self.NPC.VNPC_WaterDrank or 0) or 0)
    local foodMealVal = (self.VNPC_FoodMealWeight or 0) + (IsValid(self.NPC) and (self.NPC.VNPC_FoodMealWeight or 0) or 0)
    local totalVal = self:GetCollectivePreyValue() + waterVal + foodMealVal

    -- Multi-body occupancy slightly boosts overall size so two people don't
    -- look like one slightly larger person when values are similar.
    local bodyCount = 0
    if istable(self.Prey) then
        for _, info in ipairs(self.Prey) do
            if info and not info.WombPrey and not info.NoDigest then
                local rem = 1
                if info.Absorbing and info.TrueValue and info.TrueValue > 0 then
                    rem = math.Clamp((info.Value or 0) / info.TrueValue, 0, 1)
                end
                if rem >= 0.08 then
                    bodyCount = bodyCount + 1
                end
            end
        end
    end
    if bodyCount >= 2 then
        totalVal = totalVal * (1.0 + math.min(0.55, (bodyCount - 1) * 0.18))
    end

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

-- Source model bounds: X = forward/back (depth), Y = left/right (width), Z = up/down (height).
local EXT_WIDTH, EXT_DEPTH, EXT_HEIGHT = "y", "x", "z"

local MAX_PACKED = 10
local MIN_REMAINING = 0.025

local function remainingFraction(info)
    if not info then return 0 end
    if info.Absorbing and info.TrueValue and info.TrueValue > 0 then
        return math.Clamp((info.Value or 0) / info.TrueValue, 0, 1)
    end
    -- Still struggling / object waiting: full bulk present.
    if info.Value and info.TrueValue and info.TrueValue > 0 and not info.Alive then
        -- Dead but not yet absorbing: shrink slightly with remaining value.
        return math.Clamp(math.max(0.55, (info.Value or 0) / info.TrueValue), 0, 1)
    end
    return 1
end

local function resolveHalfExtents(info)
    if info.HalfExtents and isvector(info.HalfExtents) then
        return info.HalfExtents
    end
    -- Live fallback if snapshot was missing (legacy prey entries).
    local ent = info.Entity
    if IsValid(ent) and ent.GetModelBounds then
        local ok, mins, maxs = pcall(ent.GetModelBounds, ent)
        if ok and mins and maxs then
            local scale = 1
            if ent.GetModelScale then
                local sok, s = pcall(ent.GetModelScale, ent)
                if sok and isnumber(s) and s > 0 then scale = s end
            end
            return (maxs - mins) * 0.5 * scale
        end
    end
    -- Value-based soft estimate so props without bounds still contribute.
    local v = tonumber(info.TrueValue or info.Value) or 40
    local r = math.Clamp(v * 0.12, 4, 28)
    return Vector(r * 0.85, r, r * 0.9)
end

local function getPackedPreyBoxes(self)
    local boxes = {}

    for _, info in ipairs(self.Prey or {}) do
        if not info or info.WombPrey or info.NoDigest then continue end
        if IsValid(info.Entity) and (info.Entity.VNPC_IsWombPrey or info.Entity.VNPC_IsUnbornBaby) then
            continue
        end

        local remaining = remainingFraction(info)
        if remaining < MIN_REMAINING then continue end

        local ext = resolveHalfExtents(info)
        local shrink = remaining ^ (1 / 3) -- volume-correct

        -- Fetal curl: humanoids sit wider than deep once curled in the gut.
        -- CurlProfile is set at swallow time (1 = biped, 0 = prop/quad).
        local curl = tonumber(info.CurlProfile) or 0
        local hx, hy, hz = ext.x, ext.y, ext.z
        if curl > 0.15 then
            -- Swap/boost so width (Y) leads, depth (X) is compressed curl thickness.
            local shoulder = math.max(hy, hx * 0.85)
            local curlDepth = math.max(hx, hy) * (0.42 + (1 - curl) * 0.2)
            local curlHeight = math.max(hz * 0.72, shoulder * 0.55)
            hx = Lerp(curl, hx, curlDepth)
            hy = Lerp(curl, hy, shoulder * 1.05)
            hz = Lerp(curl, hz, curlHeight)
        end

        table.insert(boxes, {
            x = hx * shrink,
            y = hy * shrink,
            z = hz * shrink,
            remaining = remaining,
            mass = tonumber(info.TrueValue or info.Value) or 40,
            curl = curl,
        })
    end

    -- Biggest full bodies define silhouette first.
    table.sort(boxes, function(a, b)
        local va = a.x * a.y * a.z * (0.5 + a.remaining)
        local vb = b.x * b.y * b.z * (0.5 + b.remaining)
        return va > vb
    end)

    return boxes
end

--[[
    Enhanced first-fit-decreasing shelf packing with soft nesting.
    Nest factor < 1 means adjacent bodies share some shoulder volume
    (they press into each other) so two adults aren't cartoonishly wide,
    while still clearly wider than one.
]]
local function packBoxesIntoRows(boxes)
    if #boxes == 0 then return {}, 0, 0 end

    local nest = math.Clamp(shape_nest:GetFloat() or 0.78, 0.5, 1.0)
    local totalWidth, biggestWidth, fullBodies = 0, 0, 0
    for _, b in ipairs(boxes) do
        local width = b.y * 2
        totalWidth = totalWidth + width
        biggestWidth = math.max(biggestWidth, width)
        if b.remaining >= 0.45 and (b.x * b.y * b.z) > 80 then
            fullBodies = fullBodies + 1
        end
    end

    local avgWidth = totalWidth / #boxes
    -- Slightly tighter row budget than pure 3x avg so adults spill sooner
    -- into a second row (reads as "two people deep" instead of a flat slab).
    local maxRowWidth = math.max(avgWidth * 2.85, biggestWidth * 1.08)

    local rows = {}
    local row = {width = 0, depth = 0, height = 0, count = 0, mass = 0, peakWidth = 0}

    local function flush()
        if row.count > 0 then
            table.insert(rows, row)
        end
        row = {width = 0, depth = 0, height = 0, count = 0, mass = 0, peakWidth = 0}
    end

    for i = 1, math.min(#boxes, MAX_PACKED) do
        local b = boxes[i]
        local width, depth, height = b.y * 2, b.x * 2, b.z * 2

        if row.count > 0 and (row.width + width * nest) > maxRowWidth then
            flush()
        end

        if row.count == 0 then
            row.width = width
        else
            -- Soft nest: only a fraction of the new body's width is additive.
            row.width = row.width + width * nest
        end
        row.depth = math.max(row.depth, depth)
        -- Mixed heights: tallest dominates, but shorter bodies still add a little.
        if row.count == 0 then
            row.height = height
        else
            row.height = math.max(row.height, height) + math.min(height, row.height) * 0.08
        end
        row.count = row.count + 1
        row.mass = row.mass + (b.mass or 40)
        row.peakWidth = math.max(row.peakWidth, width)
    end
    flush()

    return rows, fullBodies, biggestWidth
end

local function shapeFromPacked(rows, fullBodies, biggestWidth, boxCount)
    local packedWidth, packedDepth, packedHeight = 0, 0, 0
    local totalMass = 0
    for ri, r in ipairs(rows) do
        packedWidth = math.max(packedWidth, r.width)
        -- Later rows sit deeper and also stack slightly upward (bulge stack).
        local rowDepthGain = r.depth * (ri == 1 and 1.0 or 0.88)
        packedDepth = packedDepth + rowDepthGain
        local stackLift = (ri - 1) * r.height * 0.22
        packedHeight = math.max(packedHeight, r.height + stackLift)
        totalMass = totalMass + (r.mass or 0)
    end

    if packedWidth <= 0 or packedDepth <= 0 or packedHeight <= 0 then
        return Vector(1, 1, 1), 0
    end

    -- Reference: what ONE of the largest bodies would look like alone.
    -- Shape bias = packed / reference, so 2 side-by-side adults → ~2x width.
    local refW = math.max(biggestWidth, packedWidth * 0.35, 1)
    local refD = math.max(refW * 0.72, 1)
    local refH = math.max(refW * 0.85, 1)

    local intensity = math.Clamp(shape_intensity:GetFloat() or 1.35, 0.5, 3.0)
    local multi = math.Clamp(shape_multibody:GetFloat() or 1.45, 1.0, 2.5)

    local rawW = packedWidth / refW
    local rawD = packedDepth / refD
    local rawH = packedHeight / refH

    -- Pull toward geometric-mean-normalized shape for stability, then blend
    -- with reference ratios so multi-body width really shows.
    local mean = (packedWidth * packedDepth * packedHeight) ^ (1 / 3)
    local gmW = packedWidth / mean
    local gmD = packedDepth / mean
    local gmH = packedHeight / mean

    local w = Lerp(0.55, gmW, rawW)
    local d = Lerp(0.55, gmD, rawD)
    local h = Lerp(0.50, gmH, rawH)

    -- Multi-body silhouette: once 2+ substantial bodies are in, push width
    -- (and a bit of depth) so it can't collapse back toward a sphere.
    if fullBodies >= 2 or boxCount >= 2 then
        local bodies = math.max(fullBodies, math.min(boxCount, 4))
        local boost = 1.0 + (multi - 1.0) * math.min(1.0, (bodies - 1) * 0.55)
        w = w * boost
        d = d * (1.0 + (boost - 1.0) * 0.45)
        h = h * (1.0 + (boost - 1.0) * 0.20)
    end

    -- Apply artist intensity around 1,1,1.
    w = 1 + (w - 1) * intensity
    d = 1 + (d - 1) * intensity
    h = 1 + (h - 1) * intensity

    local maxW = math.Clamp(shape_max_width:GetFloat() or 3.2, 1.2, 4.5)
    local maxD = math.Clamp(shape_max_depth:GetFloat() or 2.4, 1.2, 3.5)
    local maxH = math.Clamp(shape_max_height:GetFloat() or 2.0, 1.2, 3.0)

    -- Side asymmetry hint: when 2 bodies pack in one row, bias slightly left
    -- so the silhouette isn't a perfect oval (reads more "two lumps").
    local sideBias = 0
    if rows[1] and rows[1].count >= 2 then
        sideBias = math.Clamp((rows[1].count - 1) * 0.12, 0, 0.35)
    end

    return Vector(
        math.Clamp(w, 0.55, maxW),
        math.Clamp(d, 0.55, maxD),
        math.Clamp(h, 0.55, maxH)
    ), sideBias
end

function ENT:GetBellyShapeVector()
    if not shape_deform_enabled:GetBool() then return Vector(1, 1, 1) end
    if not self.Prey or #self.Prey == 0 then return Vector(1, 1, 1) end

    local boxes = getPackedPreyBoxes(self)
    if #boxes == 0 then return Vector(1, 1, 1) end

    local rows, fullBodies, biggestWidth = packBoxesIntoRows(boxes)
    if #rows == 0 then return Vector(1, 1, 1) end

    local shape, sideBias = shapeFromPacked(rows, fullBodies, biggestWidth, #boxes)
    self.VNPC_LastShapeSideBias = sideBias or 0
    self.VNPC_LastPackInfo = {
        boxes = #boxes,
        rows = #rows,
        fullBodies = fullBodies,
        shape = shape,
        sideBias = sideBias,
    }
    return shape
end

function ENT:SetBellySize()
    local target = self:GetBellySize()
    self.VNPC_LastSetBellySize = target
    self:SetNWFloat("BellySize", target)

    local shape = self:GetBellyShapeVector()
    self:SetNWVector("BellyShape", shape)
    self:SetNWFloat("BellyShapeBias", self.VNPC_LastShapeSideBias or 0)

    -- Occupancy count helps client exaggerate multi-body flex / wobble.
    local n = 0
    if istable(self.Prey) then
        for _, info in ipairs(self.Prey) do
            if info and not info.WombPrey and remainingFraction(info) >= MIN_REMAINING then
                n = n + 1
            end
        end
    end
    self:SetNWInt("BellyOccupants", n)

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

if SERVER then
    concommand.Add("vnpcs_shape_status", function(ply)
        print("===============================================================")
        print("        V-NPCs BOUNDING-BOX BELLY SHAPE STATUS (enhanced)     ")
        print("===============================================================")
        print(" - Enabled: " .. tostring(GetConVar("vnpcs_shape_deform"):GetBool()))
        print(" - Intensity: " .. tostring(GetConVar("vnpcs_shape_intensity"):GetFloat()))
        print(" - Nest: " .. tostring(GetConVar("vnpcs_shape_nest"):GetFloat()))
        print(" - Multi-Body: " .. tostring(GetConVar("vnpcs_shape_multibody"):GetFloat()))
        local n = 0
        for _, belly in ipairs(ents.FindByClass("ent_vore_belly")) do
            if not IsValid(belly) or not belly.Prey or #belly.Prey == 0 then continue end
            n = n + 1
            local shape = belly.GetBellyShapeVector and belly:GetBellyShapeVector() or Vector(1,1,1)
            local info = belly.VNPC_LastPackInfo or {}
            print(string.format(" -> belly #%d prey=%d boxes=%s rows=%s shape=(%.2f, %.2f, %.2f) bias=%.2f",
                belly:EntIndex(), #belly.Prey,
                tostring(info.boxes or "?"), tostring(info.rows or "?"),
                shape.x, shape.y, shape.z, belly.VNPC_LastShapeSideBias or 0))
        end
        for _, belly in ipairs(ents.FindByClass("ent_fernkarry_belly")) do
            if not IsValid(belly) or not belly.Prey or #belly.Prey == 0 then continue end
            n = n + 1
            local shape = belly.GetBellyShapeVector and belly:GetBellyShapeVector() or Vector(1,1,1)
            print(string.format(" -> fernbelly #%d prey=%d shape=(%.2f, %.2f, %.2f)",
                belly:EntIndex(), #belly.Prey, shape.x, shape.y, shape.z))
        end
        if n == 0 then print(" - No active bellies with prey.") end
        print("===============================================================")
        if IsValid(ply) then ply:ChatPrint("[V-NPCs] Shape status printed. Active bellies: " .. n) end
    end)
end
