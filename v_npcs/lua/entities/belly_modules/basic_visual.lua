ENT.BaseScale = 0 --AKA BELLY FAT LEFT OVER
ENT.MaxBaseScale = 0.5

--[[
    Prey-driven belly shape
    -----------------------
    Each swallowed prey contributes a measured size (body parts / model bounds).
    Occupants are packed shoulder-to-shoulder into rows; the packed footprint
    becomes a width/depth/height bias networked as BellyShape. Client bone scale
    applies that bias so 1 tall prey, 1 wide prey, or 2 side-by-side prey all
    read differently instead of one uniform balloon.
]]

local shape_enabled = CreateConVar("vnpcs_prey_belly_shape", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "Belly shape follows swallowed prey size/count")
local shape_intensity = CreateConVar("vnpcs_prey_belly_intensity", "1.25", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "How strongly multi-prey packing stretches belly axes (0.5-2.5)")
local shape_nest = CreateConVar("vnpcs_prey_belly_nest", "0.82", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "How tightly packed bodies nest (0.6 snug, 1.0 full sum)")

local MAX_SHAPE_BODIES = 8
local MIN_REMAIN = 0.04

function ENT:GetBellySize() --this gets the scale of all the stuff in the stomach
    -- Ensure consuming prop meals causes ZERO belly expansion ONLY for male prey who chew or explicitly flagged non-expanding eaters
    if IsValid(self.NPC) and self.NPC.VNPC_NoBellyExpansionFromMeal and not (self.Prey and #self.Prey > 0) and not ((self.NPC.VNPC_FoodMealWeight or 0) > 0) then
        return self.BaseScale
    end

    local waterVal = (self.VNPC_WaterWeight or 0) + (IsValid(self.NPC) and (self.NPC.VNPC_WaterDrank or 0) or 0)
    local foodMealVal = (self.VNPC_FoodMealWeight or 0) + (IsValid(self.NPC) and (self.NPC.VNPC_FoodMealWeight or 0) or 0)
    local totalVal = self:GetCollectivePreyValue() + waterVal + foodMealVal

    -- Multi-body occupancy: two similar-value prey should look fuller than one.
    if shape_enabled:GetBool() and istable(self.Prey) then
        local bodies = 0
        for _, info in ipairs(self.Prey) do
            if info and not info.WombPrey and not info.NoDigest then
                local rem = 1
                if info.Absorbing and info.TrueValue and info.TrueValue > 0 then
                    rem = math.Clamp((info.Value or 0) / info.TrueValue, 0, 1)
                end
                if rem >= MIN_REMAIN then bodies = bodies + 1 end
            end
        end
        if bodies >= 2 then
            totalVal = totalVal * (1.0 + math.min(0.5, (bodies - 1) * 0.16))
        end
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

-- Source model bounds: X = depth (front/back), Y = width (left/right), Z = height
local function remainingOf(info)
    if not info then return 0 end
    if info.Absorbing and info.TrueValue and info.TrueValue > 0 then
        return math.Clamp((info.Value or 0) / info.TrueValue, 0, 1)
    end
    if info.Alive == false and info.TrueValue and info.TrueValue > 0 then
        return math.Clamp(math.max(0.5, (info.Value or 0) / info.TrueValue), 0, 1)
    end
    return 1
end

local function resolvePreySize(info)
    -- Prefer snapshot taken at swallow time
    if info.PreySize and isvector(info.PreySize) then
        return info.PreySize
    end
    if info.HalfExtents and isvector(info.HalfExtents) then
        return info.HalfExtents
    end
    -- Live fallback
    local ent = info.Entity
    if IsValid(ent) then
        if VNPC_GetPreyShapeBlob then
            local blob = VNPC_GetPreyShapeBlob(ent)
            if blob then
                -- blob: rx=side, ry=front-back, rz=up  -> model half-extents x,y,z
                return Vector(blob.ry or 8, blob.rx or 8, blob.rz or 7)
            end
        end
        if ent.GetModelBounds then
            local ok, mins, maxs = pcall(ent.GetModelBounds, ent)
            if ok and mins and maxs then
                local sc = 1
                if ent.GetModelScale then
                    local sok, s = pcall(ent.GetModelScale, ent)
                    if sok and isnumber(s) and s > 0 then sc = s end
                end
                return (maxs - mins) * 0.5 * sc
            end
        end
    end
    local v = tonumber(info.TrueValue or info.Value) or 40
    local r = math.Clamp(v * 0.11, 4, 26)
    return Vector(r * 0.85, r, r * 0.9)
end

local function collectPreyBoxes(self)
    local boxes = {}
    for _, info in ipairs(self.Prey or {}) do
        if not info or info.WombPrey or info.NoDigest then continue end
        if IsValid(info.Entity) and (info.Entity.VNPC_IsWombPrey or info.Entity.VNPC_IsUnbornBaby) then
            continue
        end
        local rem = remainingOf(info)
        if rem < MIN_REMAIN then continue end

        local sz = resolvePreySize(info)
        local shrink = rem ^ (1 / 3)

        -- Fetal curl for person-like prey: wider shoulders, compressed depth
        local curl = tonumber(info.PreyCurl) or 0
        local hx, hy, hz = sz.x, sz.y, sz.z
        if curl > 0.2 then
            local shoulder = math.max(hy, hx * 0.9)
            local depth = math.max(hx, hy) * (0.40 + (1 - curl) * 0.18)
            local height = math.max(hz * 0.70, shoulder * 0.52)
            hx = Lerp(curl, hx, depth)
            hy = Lerp(curl, hy, shoulder * 1.06)
            hz = Lerp(curl, hz, height)
        end

        table.insert(boxes, {
            x = math.max(2.5, hx * shrink), -- depth half
            y = math.max(2.5, hy * shrink), -- width half
            z = math.max(2.0, hz * shrink), -- height half
            rem = rem,
            mass = tonumber(info.TrueValue or info.Value) or 40,
        })
    end

    table.sort(boxes, function(a, b)
        return (a.x * a.y * a.z * (0.4 + a.rem)) > (b.x * b.y * b.z * (0.4 + b.rem))
    end)
    return boxes
end

local function packRows(boxes)
    if #boxes == 0 then return {}, 0 end
    local nest = math.Clamp(shape_nest:GetFloat() or 0.82, 0.55, 1.0)

    local totalW, biggestW, fullN = 0, 0, 0
    for _, b in ipairs(boxes) do
        local w = b.y * 2
        totalW = totalW + w
        biggestW = math.max(biggestW, w)
        if b.rem >= 0.4 and (b.x * b.y * b.z) > 70 then fullN = fullN + 1 end
    end
    local avgW = totalW / #boxes
    -- Adults spill to a second row sooner so 2 people read wide, 4 people read deep
    local maxRowW = math.max(avgW * 2.7, biggestW * 1.08)

    local rows = {}
    local row = { w = 0, d = 0, h = 0, n = 0 }

    local function flush()
        if row.n > 0 then table.insert(rows, row) end
        row = { w = 0, d = 0, h = 0, n = 0 }
    end

    for i = 1, math.min(#boxes, MAX_SHAPE_BODIES) do
        local b = boxes[i]
        local w, d, h = b.y * 2, b.x * 2, b.z * 2
        if row.n > 0 and (row.w + w * nest) > maxRowW then
            flush()
        end
        if row.n == 0 then
            row.w = w
            row.h = h
        else
            row.w = row.w + w * nest
            row.h = math.max(row.h, h) + math.min(row.h, h) * 0.07
        end
        row.d = math.max(row.d, d)
        row.n = row.n + 1
    end
    flush()
    return rows, biggestW, fullN
end

function ENT:GetPreyBellyShape()
    if not shape_enabled:GetBool() then
        return Vector(1, 1, 1), 0, 0
    end
    if not self.Prey or #self.Prey == 0 then
        return Vector(1, 1, 1), 0, 0
    end

    local boxes = collectPreyBoxes(self)
    if #boxes == 0 then
        return Vector(1, 1, 1), 0, 0
    end

    local rows, biggestW, fullN = packRows(boxes)
    if #rows == 0 then
        return Vector(1, 1, 1), 0, #boxes
    end

    local packW, packD, packH = 0, 0, 0
    for ri, r in ipairs(rows) do
        packW = math.max(packW, r.w)
        packD = packD + r.d * (ri == 1 and 1.0 or 0.90)
        packH = math.max(packH, r.h + (ri - 1) * r.h * 0.18)
    end
    if packW <= 0 or packD <= 0 or packH <= 0 then
        return Vector(1, 1, 1), 0, #boxes
    end

    -- Shape bias relative to one largest body (not geometric mean alone),
    -- so two adults side-by-side clearly widen the belly.
    local refW = math.max(biggestW, packW * 0.34, 1)
    local refD = math.max(refW * 0.70, 1)
    local refH = math.max(refW * 0.82, 1)

    local rawW, rawD, rawH = packW / refW, packD / refD, packH / refH
    local mean = (packW * packD * packH) ^ (1 / 3)
    local gmW, gmD, gmH = packW / mean, packD / mean, packH / mean

    local w = Lerp(0.58, gmW, rawW)
    local d = Lerp(0.58, gmD, rawD)
    local h = Lerp(0.52, gmH, rawH)

    local bodies = math.max(fullN, math.min(#boxes, 5))
    if bodies >= 2 then
        local boost = 1.0 + math.min(0.85, (bodies - 1) * 0.32)
        w = w * boost
        d = d * (1.0 + (boost - 1.0) * 0.42)
        h = h * (1.0 + (boost - 1.0) * 0.18)
    end

    local intensity = math.Clamp(shape_intensity:GetFloat() or 1.25, 0.5, 2.5)
    w = 1 + (w - 1) * intensity
    d = 1 + (d - 1) * intensity
    h = 1 + (h - 1) * intensity

    -- Single long/tall prey still warps shape even without multi-body boost
    if #boxes == 1 then
        local b = boxes[1]
        local aspectW = (b.y * 2) / math.max(1, (b.x * 2 + b.z * 2) * 0.5)
        local aspectD = (b.x * 2) / math.max(1, (b.y * 2 + b.z * 2) * 0.5)
        local aspectH = (b.z * 2) / math.max(1, (b.x * 2 + b.y * 2) * 0.5)
        w = math.max(w, math.Clamp(aspectW * 0.85 + 0.15, 0.75, 1.55))
        d = math.max(d, math.Clamp(aspectD * 0.85 + 0.15, 0.75, 1.55))
        h = math.max(h, math.Clamp(aspectH * 0.85 + 0.15, 0.75, 1.45))
    end

    local sideBias = 0
    if rows[1] and rows[1].n >= 2 then
        sideBias = math.Clamp((rows[1].n - 1) * 0.14, 0, 0.4)
    end

    return Vector(
        math.Clamp(w, 0.60, 3.0),
        math.Clamp(d, 0.60, 2.4),
        math.Clamp(h, 0.60, 2.0)
    ), sideBias, #boxes
end

function ENT:SetBellySize()
    local target = self:GetBellySize()
    self.VNPC_LastSetBellySize = target
    self:SetNWFloat("BellySize", target)

    local shape, sideBias, occupants = self:GetPreyBellyShape()
    self:SetNWVector("BellyShape", shape or Vector(1, 1, 1))
    self:SetNWFloat("BellyShapeBias", sideBias or 0)
    self:SetNWInt("BellyOccupants", occupants or 0)
    self.VNPC_LastPreyShape = shape
    self.VNPC_LastPreyOccupants = occupants

    -- Keep GPU weight-paint blobs in sync when that system is present.
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
    concommand.Add("vnpcs_prey_belly_status", function(ply)
        print("===============================================================")
        print("           V-NPCs PREY-DRIVEN BELLY SHAPE STATUS              ")
        print("===============================================================")
        print(" Enabled: " .. tostring(GetConVar("vnpcs_prey_belly_shape"):GetBool()))
        print(" Intensity: " .. tostring(GetConVar("vnpcs_prey_belly_intensity"):GetFloat()))
        print(" Nest: " .. tostring(GetConVar("vnpcs_prey_belly_nest"):GetFloat()))
        local n = 0
        for _, cls in ipairs({ "ent_vore_belly", "ent_fernkarry_belly" }) do
            for _, belly in ipairs(ents.FindByClass(cls)) do
                if not IsValid(belly) or not belly.Prey or #belly.Prey == 0 then continue end
                n = n + 1
                local shape, bias, occ = Vector(1,1,1), 0, 0
                if belly.GetPreyBellyShape then
                    shape, bias, occ = belly:GetPreyBellyShape()
                end
                print(string.format(" -> %s #%d prey=%d occ=%s shape=(%.2f, %.2f, %.2f) bias=%.2f size=%.2f",
                    cls, belly:EntIndex(), #belly.Prey, tostring(occ),
                    shape.x, shape.y, shape.z, bias or 0,
                    belly:GetNWFloat("BellySize", 0)))
                for i, info in ipairs(belly.Prey) do
                    if i > 6 then print("    ..."); break end
                    local sz = info.PreySize
                    local s = sz and string.format("%.1fx%.1fx%.1f", sz.x, sz.y, sz.z) or "?"
                    print(string.format("    [%d] val=%.0f/%.0f abs=%s curl=%.2f size=%s %s",
                        i, info.Value or 0, info.TrueValue or 0, tostring(info.Absorbing),
                        info.PreyCurl or 0, s, IsValid(info.Entity) and (info.Entity:GetClass() or "?") or "gone"))
                end
            end
        end
        if n == 0 then print(" - No active bellies with prey.") end
        print("===============================================================")
        if IsValid(ply) then ply:ChatPrint("[V-NPCs] Prey belly shape status printed (" .. n .. " bellies).") end
    end)
end
