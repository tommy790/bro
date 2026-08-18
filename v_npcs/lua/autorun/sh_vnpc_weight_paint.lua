-- V-NPCs Dynamic Weight Painting & Metaball Belly Deform (sh_vnpc_weight_paint.lua)
--
-- Prey become volumetric mass blobs (measured torso/head/limbs). Blobs pack into
-- a shelf layout, then the GPU belly surface is the iso-surface of a smooth
-- metaball field over those blobs (merged continuous bulges), not an AABB
-- ellipsoid with disconnected gaussians.
--
-- Upgrade points over the old AABB approach:
--   1. Metaball field F(p) = Σ w·wyvill(d)  → merged surface, arrangement-aware
--   2. Multi-blob fetal curl per prey (torso + head + limb mass)
--   3. Volume-correct base radius ∝ (Σ mass)^(1/3)
--   4. Gravity sag / heavy lean on COM
--   5. Client lerp of blob positions between NW syncs
--   6. Analytical field gradient as vertex normals

CreateConVar("vnpcs_weight_paint_enabled", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Enable dynamic weight-painted / metaball belly deformation from prey shape blobs")
CreateConVar("vnpcs_weight_paint_lumps", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Evaluate metaball field on the GPU belly mesh (merged prey bulges)")
CreateConVar("vnpcs_weight_paint_amp", "1.0", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Amplitude of metaball surface push")
CreateConVar("vnpcs_weight_paint_asymmetry", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Shift generated belly bones toward the prey center-of-mass (asymmetric bellies)")
CreateConVar("vnpcs_weight_paint_metaballs", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Use metaball iso-surface instead of independent gaussian lumps")
CreateConVar("vnpcs_weight_paint_curl", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Emit multi-blob fetal-curl chains per prey")
CreateConVar("vnpcs_weight_paint_volume", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Scale base belly radius with cube-root of total prey mass")
CreateConVar("vnpcs_weight_paint_sag", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Gravity sag: drop belly center and flatten bottom with mass")
CreateConVar("vnpcs_weight_paint_lerp", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Client-side lerp of blob positions between network syncs")

VNPC_MAX_PAINT_BLOBS = 12

-- ---------------------------------------------------------------------------
-- Prey measurement → one or more blobs
-- ---------------------------------------------------------------------------

-- Prey shape blob: radii are belly-local units (x = side-to-side, y = front-back, z = up-down)
-- Blob local space: +x right, +y forward (toward belly front), +z up. Origin = belly center.
function VNPC_GetPreyShapeBlob(prey)
    if not IsValid(prey) then return nil end

    local scale = 1
    if prey.GetModelScale then
        scale = prey:GetModelScale() or 1
    end
    if not isnumber(scale) or scale <= 0 then scale = 1 end

    local rx, ry, rz = 7.5 * scale, 9.0 * scale, 6.5 * scale
    local headR, limbR = 3.2 * scale, 2.4 * scale
    if VNPC_MeasureBodyParts then
        local parts = VNPC_MeasureBodyParts(prey)
        if parts then
            local torso = parts.torso
            local pelvis = parts.pelvis
            local head = parts.head
            local arm = parts.arm
            local leg = parts.leg
            -- Curled mass: torso cross-section dominates; length is compressed.
            rx = math.max(torso and torso.width or 14, pelvis and pelvis.width or 12, head and head.width or 7.2) * 0.48 * scale
            ry = math.max((torso and torso.length or 20) * 0.26, (leg and leg.length or 30) * 0.18, (arm and arm.length or 23) * 0.18) * scale
            rz = math.max((torso and torso.height or 16) * 0.38, (head and head.height or 8.5) * 0.48) * scale
            headR = math.max((head and head.width or 7.2) * 0.38, 2.4) * scale
            limbR = math.max((arm and arm.length or 20) * 0.08, 1.8) * scale
        end
    end
    rx = math.Clamp(rx, 3.2, 48)
    ry = math.Clamp(ry, 3.2, 55)
    rz = math.Clamp(rz, 2.8, 45)
    headR = math.Clamp(headR, 2.0, 14)
    limbR = math.Clamp(limbR, 1.5, 10)

    local mass = 55 * scale
    if prey.GetPhysicsObject then
        local phys = prey:GetPhysicsObject()
        if IsValid(phys) and phys.GetMass then
            local m = phys:GetMass()
            if m and m > 1 then mass = math.max(mass, m) end
        end
    end
    if VNPC_CalculatePreyValue then
        local val = VNPC_CalculatePreyValue(prey)
        -- Value units map more strongly into mass so an ~80-value human
        -- produces a full belly (was *0.22 → underfilled the volume floor).
        mass = math.max(mass * 0.85, (tonumber(val) or 0) * 0.55)
    end
    -- Body-part volume estimate as a floor (adult torso ≈ solid meal).
    if VNPC_MeasureBodyParts then
        local parts = VNPC_MeasureBodyParts(prey)
        if parts and parts.torso then
            local tw = parts.torso.width or 14
            local th = parts.torso.height or 16
            local tl = parts.torso.length or 20
            local partMass = (tw * th * tl) * 0.045 * scale
            mass = math.max(mass, partMass)
        end
    end

    local isPerson = prey:IsPlayer() or prey:IsNPC() or prey:IsNextBot() or prey.IsDrGNextbot
        or (VNPC_IsAnyFemale and VNPC_IsAnyFemale(prey))
        or (VNPC_IsAnyMale and VNPC_IsAnyMale(prey))

    return {
        id = prey:EntIndex(),
        rx = rx,
        ry = ry,
        rz = rz,
        headR = headR,
        limbR = limbR,
        mass = mass,
        scale = scale,
        person = isPerson and true or false,
    }
end

-- Deterministic shelf packing for root (torso) blobs.
function VNPC_DefaultBlobLayout(pred, blobs)
    if not istable(blobs) then return end

    local order = {}
    for _, blob in ipairs(blobs) do
        table.insert(order, blob)
    end
    if #order == 0 then return end

    table.sort(order, function(a, b)
        return (a.rx * a.ry * a.rz) > (b.rx * b.ry * b.rz)
    end)

    local totalWidth, biggestWidth = 0, 0
    for _, blob in ipairs(order) do
        local w = blob.rx * 2
        totalWidth = totalWidth + w
        biggestWidth = math.max(biggestWidth, w)
    end
    local avgWidth = totalWidth / #order
    local maxRowWidth = math.max(avgWidth * 3.0, biggestWidth * 1.05)

    local rows = {}
    local row = { blobs = {}, width = 0, depth = 0 }
    for _, blob in ipairs(order) do
        local w, d = blob.rx * 2, blob.ry * 2
        if #row.blobs > 0 and (row.width + w) > maxRowWidth then
            table.insert(rows, row)
            row = { blobs = {}, width = 0, depth = 0 }
        end
        table.insert(row.blobs, blob)
        row.width = row.width + w
        row.depth = math.max(row.depth, d)
    end
    table.insert(rows, row)

    local depthCursor = 0
    for _, r in ipairs(rows) do
        local cursor = -r.width * 0.5
        local rowY = 1.6 - depthCursor - r.depth * 0.5
        for i, blob in ipairs(r.blobs) do
            local w = blob.rx * 2
            local x = cursor + w * 0.5
            cursor = cursor + w
            local jitter = ((i % 2) == 0) and -1 or 1
            local z = -2.2 - jitter * math.min(1.8, blob.rz * 0.18)
            blob.pos = Vector(x, rowY, z)
        end
        depthCursor = depthCursor + r.depth * 0.92
    end
end

-- Expand each root prey blob into a short fetal-curl chain (torso + head + limb).
local function expandCurlChain(rootBlobs)
    local curlOn = GetConVar("vnpcs_weight_paint_curl")
    if curlOn and not curlOn:GetBool() then
        return rootBlobs
    end

    local out = {}
    local budget = VNPC_MAX_PAINT_BLOBS
    for _, root in ipairs(rootBlobs) do
        if #out >= budget then break end
        root.part = root.part or "torso"
        table.insert(out, root)

        if not root.person and not root.womb then
            continue
        end
        if root.phantom or root.womb then
            continue
        end

        -- Stable hash from id for curl side / lean variation
        local h = math.abs(tonumber(root.id) or 1)
        local side = ((h % 2) == 0) and -1 or 1
        local lean = ((h % 5) - 2) * 0.35
        local base = root.pos or Vector(0, 0, 0)

        -- Head sub-blob: curled toward upper-front of torso mass
        if #out < budget then
            local hr = root.headR or (math.min(root.rx, root.rz) * 0.55)
            table.insert(out, {
                id = (root.id or 0) + 100000,
                pos = base + Vector(side * root.rx * 0.22 + lean, root.ry * 0.35, root.rz * 0.55),
                rx = hr * 0.85,
                ry = hr * 0.95,
                rz = hr * 0.80,
                mass = (root.mass or 40) * 0.18,
                alive = root.alive,
                swallowing = root.swallowing,
                person = root.person,
                part = "head",
                parentId = root.id,
            })
        end

        -- Limb/hip mass: lower-back of the curl (fills the C)
        if #out < budget then
            local lr = root.limbR or (math.min(root.rx, root.ry) * 0.4)
            table.insert(out, {
                id = (root.id or 0) + 200000,
                pos = base + Vector(-side * root.rx * 0.28 + lean * 0.5, -root.ry * 0.15, -root.rz * 0.45),
                rx = lr * 1.15,
                ry = lr * 1.05,
                rz = lr * 0.9,
                mass = (root.mass or 40) * 0.22,
                alive = root.alive,
                swallowing = root.swallowing,
                person = root.person,
                part = "limb",
                parentId = root.id,
            })
        end
    end
    return out
end

function VNPC_ComputeBellyBlobs(pred)
    if not IsValid(pred) then return {} end
    local blobs = {}

    if SERVER then
        local belly = VNPC_GetPredBelly and VNPC_GetPredBelly(pred) or pred.VNPC_Belly or pred.Belly
        if not IsValid(belly) then
            blobs = pred.VNPC_BellyBlobs or {}
        elseif istable(belly.Prey) then
            local roots = {}
            for _, info in ipairs(belly.Prey) do
                if #roots >= 6 then break end -- leave room for curl sub-blobs
                if not istable(info) then continue end
                if info.WombPrey or info.NoDigest or (IsValid(info.Entity) and (info.Entity.VNPC_IsWombPrey or info.Entity.VNPC_IsUnbornBaby)) then
                    continue
                end
                local prey = info.Entity
                local absorbing = info.Absorbing == true
                local remain = 1
                if absorbing and info.TrueValue and info.TrueValue > 0 then
                    remain = math.Clamp((info.Value or 0) / info.TrueValue, 0, 1)
                end
                if remain < 0.04 then continue end

                if not IsValid(prey) then
                    if info.Value and info.Value > 5 then
                        local shrink = remain ^ (1 / 3)
                        table.insert(roots, {
                            id = info.preyId or (9000 + #roots),
                            rx = 4 * shrink, ry = 5 * shrink, rz = 3.5 * shrink,
                            mass = 8 * remain,
                            phantom = true,
                            alive = false,
                            person = true,
                        })
                    end
                    continue
                end

                local blob = VNPC_GetPreyShapeBlob(prey)
                if not blob then continue end
                local shrink = remain ^ (1 / 3)
                blob.rx = blob.rx * shrink
                blob.ry = blob.ry * shrink
                blob.rz = blob.rz * shrink
                if blob.headR then blob.headR = blob.headR * shrink end
                if blob.limbR then blob.limbR = blob.limbR * shrink end
                blob.mass = (blob.mass or 40) * math.max(0.15, remain)
                blob.alive = (prey:Health() > 0) and (info.Alive ~= false) and not absorbing
                blob.absorbing = absorbing
                blob.swallowing = prey.VNPC_IsBeingSwallowed == true
                blob.remain = remain
                table.insert(roots, blob)
            end
            VNPC_DefaultBlobLayout(pred, roots)
            blobs = expandCurlChain(roots)
        end

        pred.VNPC_BellyBlobs = blobs
        return blobs
    end

    -- CLIENT: read replicated blob data + optional lerp
    local n = (pred.GetNWInt and pred:GetNWInt("VNPC_PaintBlobN", 0)) or 0
    if n > 0 then
        pred.VNPC_ClientBlobLerp = pred.VNPC_ClientBlobLerp or {}
        local lerpOn = GetConVar("vnpcs_weight_paint_lerp")
        local doLerp = not lerpOn or lerpOn:GetBool()
        local now = CurTime()

        for i = 1, math.min(n, VNPC_MAX_PAINT_BLOBS) do
            local pos = (pred.GetNWVector and pred:GetNWVector("VNPC_PaintBlobPos" .. i, Vector(0, 0, 0))) or Vector(0, 0, 0)
            local radii = (pred.GetNWVector and pred:GetNWVector("VNPC_PaintBlobRadii" .. i, Vector(7, 9, 6))) or Vector(7, 9, 6)
            local mass = (pred.GetNWFloat and pred:GetNWFloat("VNPC_PaintBlobMass" .. i, 45)) or 45
            local flags = (pred.GetNWInt and pred:GetNWInt("VNPC_PaintBlobFlags" .. i, 0)) or 0
            local id = (pred.GetNWInt and pred:GetNWInt("VNPC_PaintBlobID" .. i, i * 31)) or i * 31

            local drawPos = pos
            if doLerp then
                local slot = pred.VNPC_ClientBlobLerp[id]
                if not slot then
                    slot = { prev = Vector(pos), target = Vector(pos), t0 = now, dur = 0.45 }
                    pred.VNPC_ClientBlobLerp[id] = slot
                else
                    if slot.target:DistToSqr(pos) > 0.01 then
                        slot.prev = Vector(slot.smooth or slot.target)
                        slot.target = Vector(pos)
                        slot.t0 = now
                        slot.dur = 0.45
                    end
                    local u = math.Clamp((now - slot.t0) / math.max(slot.dur, 0.05), 0, 1)
                    -- smoothstep
                    u = u * u * (3 - 2 * u)
                    drawPos = LerpVector(u, slot.prev, slot.target)
                    slot.smooth = drawPos
                end
            end

            table.insert(blobs, {
                id = id,
                pos = drawPos,
                rx = math.max(2.0, radii.x),
                ry = math.max(2.0, radii.y),
                rz = math.max(2.0, radii.z),
                mass = mass,
                alive = bit.band(flags, 1) ~= 0,
                swallowing = bit.band(flags, 2) ~= 0,
                phantom = bit.band(flags, 4) ~= 0,
                womb = bit.band(flags, 8) ~= 0,
                person = bit.band(flags, 16) ~= 0,
            })
        end
    end
    return blobs
end

function VNPC_GetPregnancyBlob(pred)
    if not IsValid(pred) then return nil end
    if not (pred.VNPC_IsPregnant or pred.VNPC_BabyGrowthValue or ((pred.VNPC_InChildbirthPose or 0) > CurTime())) then
        return nil
    end
    local r = VNPC_GetPregnancyBellyRadius and VNPC_GetPregnancyBellyRadius(pred) or 10
    return {
        id = pred:EntIndex() * 7 + 4000,
        pos = Vector(0, 1.5, -r * 0.42),
        rx = r * 0.62,
        ry = r * 0.55,
        rz = r * 0.48,
        mass = 20,
        womb = true,
        alive = true,
    }
end

-- ---------------------------------------------------------------------------
-- Metrics: volume-correct radius, AABB still kept for bone anchors, COM + sag
-- ---------------------------------------------------------------------------

function VNPC_GetBellyDeformMetrics(pred)
    if not IsValid(pred) then return nil end
    local enabled = GetConVar("vnpcs_weight_paint_enabled")
    if enabled and not enabled:GetBool() then return nil end

    local blobs = VNPC_ComputeBellyBlobs(pred)
    local womb = VNPC_GetPregnancyBlob(pred)
    if womb then table.insert(blobs, womb) end
    if #blobs == 0 then
        pred.VNPC_BellyBlobMetrics = nil
        return nil
    end

    local minX, maxX, minY, maxY, minZ, maxZ = 1e9, -1e9, 1e9, -1e9, 1e9, -1e9
    local com = Vector(0, 0, 0)
    local totalMass = 0
    local totalVol = 0
    for _, b in ipairs(blobs) do
        local px, py, pz = b.pos and b.pos.x or 0, b.pos and b.pos.y or 0, b.pos and b.pos.z or 0
        minX = math.min(minX, px - b.rx)
        maxX = math.max(maxX, px + b.rx)
        minY = math.min(minY, py - b.ry)
        maxY = math.max(maxY, py + b.ry)
        minZ = math.min(minZ, pz - b.rz)
        maxZ = math.max(maxZ, pz + b.rz)
        com = com + Vector(px, py, pz) * (b.mass or 1)
        totalMass = totalMass + (b.mass or 1)
        -- ellipsoid volume ~ 4/3 π r_x r_y r_z
        totalVol = totalVol + (b.rx * b.ry * b.rz)
    end
    if totalMass > 0 then
        com = com / totalMass
    end

    local boxRx = math.max(4.0, (maxX - minX) * 0.52)
    local boxRy = math.max(4.5, (maxY - minY) * 0.55)
    local boxRz = math.max(3.5, (maxZ - minZ) * 0.5)

    -- Volume-correct isotropic radius from total mass/volume (cube root).
    local volR = 0
    local volOn = GetConVar("vnpcs_weight_paint_volume")
    if not volOn or volOn:GetBool() then
        -- reference: ~45 mass ≈ radius ~11 (one adult human curled meal)
        volR = math.max(7.5, (totalMass ^ (1 / 3)) * 3.05)
        -- also respect packed volume so elongated meals aren't crushed to a sphere
        local packVolR = (totalVol > 0) and ((totalVol) ^ (1 / 3)) * 1.55 or 0
        volR = math.max(volR, packVolR)
    end

    -- Blend: extent-driven axes keep elongation; volume floor prevents underfill.
    -- Single full-size prey should fill a substantial belly, not a tiny bump.
    local rx = math.max(boxRx * 1.08, volR * 0.82)
    local ry = math.max(boxRy * 1.10, volR * 0.90)
    local rz = math.max(boxRz * 1.05, volR * 0.75)
    if #blobs >= 1 then
        -- Always honour the largest torso blob so measured prey drives size.
        local best = blobs[1]
        for _, b in ipairs(blobs) do
            if (b.rx * b.ry * b.rz) > (best.rx * best.ry * best.rz) then best = b end
        end
        rx = math.max(rx, best.rx * 1.15)
        ry = math.max(ry, best.ry * 1.20)
        rz = math.max(rz, best.rz * 1.10)
    end

    -- Gravity sag: drop COM and slightly squash height / stretch depth with mass
    local sag = 0
    local sagOn = GetConVar("vnpcs_weight_paint_sag")
    if not sagOn or sagOn:GetBool() then
        sag = math.Clamp(totalMass * 0.012, 0, 5.5)
        rz = rz * (1.0 - math.min(0.18, totalMass * 0.00035))
        ry = ry * (1.0 + math.min(0.14, totalMass * 0.00028))
        com = Vector(com.x, com.y + sag * 0.08, com.z - sag * 0.55)
    end

    -- Metaball iso threshold: scale lightly with mass so surface stays tight
    local iso = 0.42 + math.Clamp(totalMass * 0.0004, 0, 0.18)

    local metrics = {
        blobs = blobs,
        totalMass = totalMass,
        totalVol = totalVol,
        com = com,
        rx = rx,
        ry = ry,
        rz = rz,
        width = math.max(9, rx * 2),
        depth = math.max(10, ry * 2),
        height = math.max(8, rz * 2),
        volRadius = volR,
        sag = sag,
        iso = iso,
    }

    pred.VNPC_BellyBlobMetrics = metrics
    return metrics
end

function VNPC_SyncPaintBlobNW(pred)
    if not SERVER or not IsValid(pred) then return end
    local enabled = GetConVar("vnpcs_weight_paint_enabled")
    if enabled and not enabled:GetBool() then
        if pred.SetNWInt then pred:SetNWInt("VNPC_PaintBlobN", 0) end
        return
    end
    local blobs = VNPC_ComputeBellyBlobs(pred)
    local n = math.min(#blobs, VNPC_MAX_PAINT_BLOBS)
    for i = 1, n do
        local b = blobs[i]
        local pos = b.pos or Vector(0, 0, 0)
        local flags = 0
        if b.alive then flags = bit.bor(flags, 1) end
        if b.swallowing then flags = bit.bor(flags, 2) end
        if b.phantom then flags = bit.bor(flags, 4) end
        if b.womb then flags = bit.bor(flags, 8) end
        if b.person then flags = bit.bor(flags, 16) end
        if pred.SetNWVector then
            pred:SetNWVector("VNPC_PaintBlobPos" .. i, pos)
            pred:SetNWVector("VNPC_PaintBlobRadii" .. i, Vector(b.rx, b.ry, b.rz))
        end
        if pred.SetNWFloat then pred:SetNWFloat("VNPC_PaintBlobMass" .. i, b.mass or 40) end
        if pred.SetNWInt then
            pred:SetNWInt("VNPC_PaintBlobID" .. i, b.id or i)
            pred:SetNWInt("VNPC_PaintBlobFlags" .. i, flags)
        end
    end
    if pred.SetNWInt then
        pred:SetNWInt("VNPC_PaintBlobN", n)
        if n > 0 then
            pred:SetNWInt("VNPC_PaintBlobHead", bit.lshift(n, 8) + (blobs[1].id or 0) % 256)
        end
    end
    -- Replicate volume metrics for client bone/mesh sizing without full recompute
    local metrics = VNPC_GetBellyDeformMetrics(pred)
    if metrics and pred.SetNWVector then
        pred:SetNWVector("VNPC_BellyHalf", Vector(metrics.rx, metrics.ry, metrics.rz))
        pred:SetNWFloat("VNPC_BellyMass", metrics.totalMass or 0)
        pred:SetNWFloat("VNPC_BellySag", metrics.sag or 0)
        pred:SetNWFloat("VNPC_BellyIso", metrics.iso or 0.45)
    end
end

-- ---------------------------------------------------------------------------
-- Metaball field
-- Wyvill kernel: (1 - r²)³ for r < 1, else 0. Soft, cheap, merges cleanly.
-- ---------------------------------------------------------------------------

local function wyvill(nd)
    -- nd = squared normalized distance already (dx²/rx² + ...)
    if nd >= 1 then return 0 end
    local t = 1 - nd
    return t * t * t
end

-- Evaluate field and gradient at a belly-local point (x,y,z in same units as blob.pos).
-- Returns fieldValue, gradX, gradY, gradZ
local function metaballField(localPos, blobs)
    local f, gx, gy, gz = 0, 0, 0, 0
    for _, b in ipairs(blobs) do
        if not b.pos then continue end
        local rx = math.max(b.rx * 1.12, 2.5)
        local ry = math.max(b.ry * 1.12, 2.5)
        local rz = math.max(b.rz * 1.12, 2.2)
        local dx = localPos.x - b.pos.x
        local dy = localPos.y - b.pos.y
        local dz = localPos.z - b.pos.z
        local nd = (dx * dx) / (rx * rx) + (dy * dy) / (ry * ry) + (dz * dz) / (rz * rz)
        if nd >= 1 then continue end
        local w = (b.mass or 40) * 0.022
        if b.part == "head" then w = w * 0.85 end
        if b.part == "limb" then w = w * 0.75 end
        if b.womb then w = w * 1.15 end
        if b.phantom then w = w * 0.55 end
        local t = 1 - nd
        local kernel = t * t * t
        f = f + w * kernel
        -- d/d(nd) of (1-nd)³ = -3(1-nd)² ; chain through nd
        local dK = -3 * t * t * w
        gx = gx + dK * (2 * dx) / (rx * rx)
        gy = gy + dK * (2 * dy) / (ry * ry)
        gz = gz + dK * (2 * dz) / (rz * rz)
    end
    return f, gx, gy, gz
end

-- Radial march from undeformed ellipsoid surface point to metaball iso-surface.
-- lp = unit-sphere local (-1..1 belly space). half = mesh half-extents.
-- Returns world offset along radial + world normal (or nil).
function VNPC_ApplyWeightPaintDeform(worldPos, lp, ent, chain)
    if not IsValid(ent) or not isvector(worldPos) or not istable(chain) then return nil end
    local enabled = GetConVar("vnpcs_weight_paint_enabled")
    if enabled and not enabled:GetBool() then return nil end
    local lumps = GetConVar("vnpcs_weight_paint_lumps")
    if lumps and not lumps:GetBool() then return nil end
    local ampCv = GetConVar("vnpcs_weight_paint_amp")
    local amp = ampCv and ampCv:GetFloat() or 1.0
    if amp <= 0 then return nil end

    local metrics = ent.VNPC_BellyBlobMetrics or VNPC_GetBellyDeformMetrics(ent)
    if not metrics or not metrics.blobs or #metrics.blobs == 0 then return nil end
    if not chain.mid or not chain.mid.pos then return nil end

    local right = chain.right or chain.rightDir
    local fwd = chain.forward
    local up = chain.up
    if not isvector(right) or not isvector(fwd) or not isvector(up) then return nil end

    local half = Vector(
        (chain.width or (metrics.rx * 2)) * 0.5,
        (chain.depth or (metrics.ry * 2)) * 0.5,
        (chain.height or (metrics.rz * 2)) * 0.5
    )

    -- Local belly-space position of this vertex on the base ellipsoid
    local localP = Vector(lp.x * half.x, lp.y * half.y, lp.z * half.z)

    local useMeta = GetConVar("vnpcs_weight_paint_metaballs")
    if useMeta and not useMeta:GetBool() then
        -- Legacy independent gaussians (fallback)
        local offset = Vector(0, 0, 0)
        for _, blob in ipairs(metrics.blobs) do
            if blob.womb and GetConVar("vnpcs_gpu_belly_preg_shape") and not GetConVar("vnpcs_gpu_belly_preg_shape"):GetBool() then
                continue
            end
            if not blob.pos then continue end
            local dx = localP.x - blob.pos.x
            local dy = localP.y - blob.pos.y
            local dz = localP.z - blob.pos.z
            local rx = math.max(blob.rx * 1.15, 4)
            local ry = math.max(blob.ry * 1.15, 4)
            local rz = math.max(blob.rz * 1.15, 3.5)
            local nd = (dx * dx) / (rx * rx) + (dy * dy) / (ry * ry) + (dz * dz) / (rz * rz)
            if nd > 4 then continue end
            local w = math.exp(-nd)
            if w <= 0.02 then continue end
            local radial = worldPos - chain.mid.pos
            if radial:LengthSqr() < 0.001 then radial = fwd else radial:Normalize() end
            local lumpR = math.max(blob.rx, blob.rz) * 0.45
            offset = offset + radial * (w * w * amp * lumpR * (0.5 + 0.4 * w))
        end
        if offset:LengthSqr() < 0.04 then return nil end
        return offset
    end

    local iso = metrics.iso or 0.45
    -- Newton / radial march: move along the surface radial to reach F ≈ iso
    local p = Vector(localP)
    local radialDir = Vector(lp.x * half.x, lp.y * half.y, lp.z * half.z)
    if radialDir:LengthSqr() < 0.001 then
        radialDir = Vector(0, 1, 0)
    else
        radialDir:Normalize()
    end

    local f, gx, gy, gz = metaballField(p, metrics.blobs)
    -- If field is dead out here, mild pull toward any nearby mass still helps fill
    if f < 0.02 then
        -- small residual push from nearest blob only
        local bestW, bestB = 0, nil
        for _, b in ipairs(metrics.blobs) do
            if not b.pos then continue end
            local d = p:Distance(b.pos)
            local r = math.max(b.rx, b.ry, b.rz) * 1.4
            local w = 1 - math.Clamp(d / r, 0, 1)
            if w > bestW then bestW, bestB = w, b end
        end
        if bestB and bestW > 0.05 then
            local radial = worldPos - chain.mid.pos
            if radial:LengthSqr() < 0.001 then radial = fwd else radial:Normalize() end
            local push = bestW * bestW * amp * math.max(bestB.rx, bestB.rz) * 0.22
            if push > 0.08 then return radial * push end
        end
        return nil
    end

    for _ = 1, 3 do
        f, gx, gy, gz = metaballField(p, metrics.blobs)
        local err = f - iso
        if math.abs(err) < 0.02 then break end
        -- Step along radial (stable) using field slope along that direction
        local gDot = gx * radialDir.x + gy * radialDir.y + gz * radialDir.z
        local step
        if math.abs(gDot) > 1e-4 then
            step = err / gDot
        else
            step = err * 2.5
        end
        step = math.Clamp(step, -half.x * 0.35, half.x * 0.35)
        p = p - radialDir * step
    end

    local deltaLocal = p - localP
    -- Soft-clamp so a single strong field never explodes a vertex
    local maxPush = math.max(half.x, half.y, half.z) * 0.55 * amp
    if deltaLocal:Length() > maxPush then
        deltaLocal = deltaLocal:GetNormalized() * maxPush
    end

    -- Convert local delta to world
    local worldOff = right * deltaLocal.x + fwd * deltaLocal.y + up * deltaLocal.z

    -- Store gradient on chain for optional normal fix (caller may read)
    f, gx, gy, gz = metaballField(p, metrics.blobs)
    local gLen = math.sqrt(gx * gx + gy * gy + gz * gz)
    if gLen > 1e-4 then
        local gLocal = Vector(gx / gLen, gy / gLen, gz / gLen)
        -- outward normal ≈ -gradient (field decreases outside)
        local nWorld = right * (-gLocal.x) + fwd * (-gLocal.y) + up * (-gLocal.z)
        if nWorld:LengthSqr() > 0.001 then
            nWorld:Normalize()
            chain._lastMetaNormal = nWorld
        end
    end

    if worldOff:LengthSqr() < 0.03 then return nil end
    return worldOff
end

function VNPC_GetBellyComShift(ent)
    if not IsValid(ent) then return Vector(0, 0, 0) end
    local asym = GetConVar("vnpcs_weight_paint_asymmetry")
    if asym and not asym:GetBool() then return Vector(0, 0, 0) end
    local metrics = ent.VNPC_BellyBlobMetrics or VNPC_GetBellyDeformMetrics(ent)
    if not metrics or not metrics.com then return Vector(0, 0, 0) end
    local sag = metrics.sag or 0
    return Vector(
        math.Clamp(metrics.com.x * 0.38, -5.0, 5.0),
        math.Clamp(metrics.com.y * 0.22 + sag * 0.05, -3.5, 4.0),
        math.Clamp(metrics.com.z * 0.28 - sag * 0.35, -6.0, 2.5)
    )
end

function VNPC_GetWeightPaintBoneScale(ent, chain)
    if not IsValid(ent) or not istable(chain) then return nil end
    local enabled = GetConVar("vnpcs_weight_paint_enabled")
    if enabled and not enabled:GetBool() then return nil end
    local metrics = ent.VNPC_BellyBlobMetrics or VNPC_GetBellyDeformMetrics(ent)
    if not metrics or #metrics.blobs == 0 then return nil end

    local extra = math.Clamp(metrics.totalMass * 0.00105, 0.05, 1.35)
    -- Axis bias from packed extents so elongated meals stretch the right bones
    local ax = math.Clamp(metrics.rx / math.max(metrics.rz, 4), 0.7, 1.5)
    local ay = math.Clamp(metrics.ry / math.max(metrics.rz, 4), 0.7, 1.6)
    local com = metrics.com
    local side = math.Clamp(com.x / math.max(metrics.rx, 6), -1, 1)
    local sideL = 1 + extra * 0.11 * math.max(0, -side)
    local sideR = 1 + extra * 0.11 * math.max(0, side)
    local lean = 0
    if GetConVar("vnpcs_weight_paint_sag") and GetConVar("vnpcs_weight_paint_sag"):GetBool() then
        lean = math.Clamp((metrics.sag or 0) * 0.04, 0, 0.25)
    end

    return {
        extra = extra,
        spine = Vector(1 + extra * 0.26 * ax, 1 + extra * (0.82 + lean) * ay, 1 + extra * 0.20),
        spine1 = Vector(1 + extra * 0.20 * ax, 1 + extra * (0.68 + lean * 0.7) * ay, 1 + extra * 0.16),
        pelvis = Vector(1 + extra * 0.18 * ax, 1 + extra * 0.52 * ay, 1 + extra * 0.15),
        thighL = Vector(sideL * (1 + extra * 0.06), 1 + extra * 0.17, sideL * (1 + extra * 0.10)),
        thighR = Vector(sideR * (1 + extra * 0.06), 1 + extra * 0.17, sideR * (1 + extra * 0.10)),
        spineLean = lean, -- optional pitch hint for consumers
    }
end

concommand.Add("vnpcs_weight_paint_status", function(ply)
    print("===============================================================")
    print("   V-NPCs METABALL WEIGHT PAINT / MESH DEFORM STATUS           ")
    print("===============================================================")
    print(" - Enabled: " .. tostring(GetConVar("vnpcs_weight_paint_enabled"):GetBool()))
    print(" - Metaballs: " .. tostring(GetConVar("vnpcs_weight_paint_metaballs"):GetBool())
        .. "  curl=" .. tostring(GetConVar("vnpcs_weight_paint_curl"):GetBool())
        .. "  volume=" .. tostring(GetConVar("vnpcs_weight_paint_volume"):GetBool())
        .. "  sag=" .. tostring(GetConVar("vnpcs_weight_paint_sag"):GetBool())
        .. "  lerp=" .. tostring(GetConVar("vnpcs_weight_paint_lerp"):GetBool()))
    print(" - Lumps amp=" .. tostring(GetConVar("vnpcs_weight_paint_amp"):GetFloat())
        .. "  asymmetry=" .. tostring(GetConVar("vnpcs_weight_paint_asymmetry"):GetBool()))
    print("-----------------------------------------")
    local count = 0
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and (ent.Predator or ent.VNPC_FemaleModelVore or ent.IsDrGNextbot or ent.VNPC_Belly or ent.Belly) then
            local metrics = VNPC_GetBellyDeformMetrics(ent)
            if metrics and metrics.totalMass and metrics.totalMass > 0 then
                count = count + 1
                print(string.format(
                    " -> #%d [%s] blobs=%d mass=%.1f volR=%.1f half=(%.1f,%.1f,%.1f) sag=%.1f iso=%.2f",
                    ent:EntIndex(), ent.PrintName or ent:GetClass(),
                    #metrics.blobs, metrics.totalMass, metrics.volRadius or 0,
                    metrics.rx, metrics.ry, metrics.rz, metrics.sag or 0, metrics.iso or 0
                ))
            end
        end
    end
    if count == 0 then print(" - No predators with belly blobs.") end
    print("===============================================================")
    if IsValid(ply) then ply:ChatPrint("[V-NPCs] Weight paint status printed (" .. count .. " preds).") end
end)

concommand.Add("vnpcs_test_paint_blob", function(ply, _, args)
    if not IsValid(ply) then return end
    local target = ply:GetEyeTrace().Entity
    if not IsValid(target) or not (target:IsNPC() or target:IsNextBot() or target.IsDrGNextbot) then
        ply:ChatPrint("[V-NPCs] Aim at a predator to attach a test paint blob!")
        return
    end
    local w = tonumber(args and args[1]) or 14
    local h = tonumber(args and args[2]) or 18
    local d = tonumber(args and args[3]) or 22
    local testBlob = {
        id = target:EntIndex() * 5 + 7000,
        pos = Vector((math.random() - 0.5) * 6, 1, -2),
        rx = w * 0.5,
        ry = d * 0.5,
        rz = h * 0.5,
        mass = 70,
        alive = true,
        person = true,
    }
    target.VNPC_PaintTestBlob = testBlob
    target.VNPC_BellyBlobMetrics = nil
    if SERVER then
        target.VNPC_BellyBlobs = target.VNPC_BellyBlobs or {}
        table.insert(target.VNPC_BellyBlobs, testBlob)
        VNPC_SyncPaintBlobNW(target)
    end
    ply:ChatPrint(string.format("[V-NPCs] Attached test paint blob (WxHxD %.0fx%.0fx%.0f) to %s. Enable vnpcs_gpu_belly_debug 1 to see the mesh.",
        w, h, d, tostring(target)))
end)
