-- V-NPCs Dynamic Weight Painting & Procedural Mesh Deform (sh_vnpc_weight_paint.lua)
-- Replaces the rigid "one fixed belly shape" approach with a procedural deformation
-- model: every swallowed entity becomes a volumetric mass blob (from measured body
-- parts: torso width/depth, head size, pelvis, model scale). Blobs are simulated by
-- vnpcs_belly_physics.lua (server) and replicated, then the GPU belly mesh and the
-- character's own bones are deformed per-blob:
--   * the belly ellipsoid stretches to the bounding box of all blobs (long prey =
--     long belly, wide prey = wide belly, one-sided prey = asymmetric bulge),
--   * per-vertex gaussian weight painting adds local lumps that track each prey's
--     live position inside the belly ("weight painting" over the model surface),
--   * spine/pelvis/thigh bones are scaled asymmetrically from the blob layout so
--     even models without belly bones visibly stretch.

CreateConVar("vnpcs_weight_paint_enabled", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Enable dynamic weight-painted belly deformation from prey shape blobs")
CreateConVar("vnpcs_weight_paint_lumps", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Draw per-prey lumps on the GPU belly mesh (weight-painted gaussian deform)")
CreateConVar("vnpcs_weight_paint_amp", "1.0", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Amplitude of weight-painted per-prey lumps")
CreateConVar("vnpcs_weight_paint_asymmetry", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Shift generated belly bones toward the prey center-of-mass (asymmetric bellies)")

VNPC_MAX_PAINT_BLOBS = 8

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
    if VNPC_MeasureBodyParts then
        local parts = VNPC_MeasureBodyParts(prey)
        if parts then
            local torso = parts.torso
            local pelvis = parts.pelvis
            local head = parts.head
            local arm = parts.arm
            local leg = parts.leg
            -- Fetal curl: the belly wraps around a curled body, so the blob is
            -- roughly the widest measured cross-section (torso/pelvis/head) and a
            -- compressed length along the belly's front-back axis.
            rx = math.max(torso and torso.width or 14, pelvis and pelvis.width or 12, head and head.width or 7.2) * 0.52 * scale
            ry = math.max((torso and torso.length or 20) * 0.30, (leg and leg.length or 30) * 0.22, (arm and arm.length or 23) * 0.22) * scale
            rz = math.max((torso and torso.height or 16) * 0.42, (head and head.height or 8.5) * 0.55) * scale
        end
    end
    rx = math.Clamp(rx, 3.5, 60)
    ry = math.Clamp(ry, 3.5, 70)
    rz = math.Clamp(rz, 3.0, 55)

    -- Mass (kg-ish, drives physics + slowdown)
    local mass = 45 * scale
    if prey.GetPhysicsObject then
        local phys = prey:GetPhysicsObject()
        if IsValid(phys) and phys.GetMass then
            local m = phys:GetMass()
            if m and m > 1 then mass = m end
        end
    end
    if VNPC_CalculatePreyValue then
        local val = VNPC_CalculatePreyValue(prey)
        mass = math.max(mass * 0.8, (tonumber(val) or 0) * 0.22)
    end

    return {
        id = prey:EntIndex(),
        rx = rx,
        ry = ry,
        rz = rz,
        mass = mass,
        scale = scale
    }
end

-- Default stacked layout when physics has not run yet (server or client).
function VNPC_DefaultBlobLayout(pred, blobs)
    if not istable(blobs) then return end
    local n = #blobs
    for i, blob in ipairs(blobs) do
        if blob.pos then continue end
        -- Stack like oranges in a bag: first sits low-center, later ones pile up
        -- and slide sideways.
        local side = ((i % 2) == 0) and -1 or 1
        local layer = math.floor((i - 1) / 2)
        blob.pos = Vector(
            side * math.min(5, 2.5 + layer * 1.5),
            2.0 - math.min(6, (i - 1) * 2.2),
            -4.0 + layer * 7.5 - math.min(3, (i - 1) * 1.2)
        )
    end
end

-- Build the list of shape blobs currently inside a predator's belly.
-- SERVER: reads belly.Prey and the physics sim state.
-- CLIENT: reads replicated blob NW (written by the physics module).
function VNPC_ComputeBellyBlobs(pred)
    if not IsValid(pred) then return {} end
    local blobs = {}

    if SERVER then
        local belly = VNPC_GetPredBelly and VNPC_GetPredBelly(pred) or pred.VNPC_Belly or pred.Belly
        if not IsValid(belly) then
            blobs = pred.VNPC_BellyBlobs or {}
        elseif istable(belly.Prey) then
            for _, info in ipairs(belly.Prey) do
                if #blobs >= VNPC_MAX_PAINT_BLOBS then break end
                if not istable(info) then continue end
                if info.Absorbing then continue end
                if info.WombPrey or info.NoDigest or (IsValid(info.Entity) and (info.Entity.VNPC_IsWombPrey or info.Entity.VNPC_IsUnbornBaby)) then continue end
                local prey = info.Entity
                if not IsValid(prey) then
                    if info.Value and info.Value > 5 then
                        -- digested husk still taking space; keep a small phantom blob
                        table.insert(blobs, { id = info.preyId or (9000 + #blobs), rx = 4, ry = 5, rz = 3.5, mass = 8, phantom = true, alive = false })
                    end
                    continue
                end
                local blob = VNPC_GetPreyShapeBlob(prey)
                if not blob then continue end
                blob.alive = (prey:Health() > 0) and (info.Alive ~= false)
                blob.absorbing = info.Absorbing == true
                blob.swallowing = prey.VNPC_IsBeingSwallowed == true
                table.insert(blobs, blob)
            end
        end

        -- Blend in physics positions if the sim is running
        local phys = pred.VNPC_BellyPhysics
        if phys and istable(phys.masses) and #phys.masses > 0 then
            local byId = {}
            for i, m in ipairs(phys.masses) do
                byId[m.id] = m
            end
            for _, blob in ipairs(blobs) do
                local m = byId[blob.id]
                if m then
                    blob.pos = m.pos
                    blob.vel = m.vel
                    blob.kick = m.kick
                end
            end
        end
        VNPC_DefaultBlobLayout(pred, blobs)
        pred.VNPC_BellyBlobs = blobs
        return blobs
    end

    -- CLIENT: read replicated blob data
    local n = (pred.GetNWInt and pred:GetNWInt("VNPC_PaintBlobN", 0)) or 0
    if n > 0 then
        for i = 1, math.min(n, VNPC_MAX_PAINT_BLOBS) do
            local pos = (pred.GetNWVector and pred:GetNWVector("VNPC_PaintBlobPos" .. i, Vector(0, 0, 0))) or Vector(0, 0, 0)
            local radii = (pred.GetNWVector and pred:GetNWVector("VNPC_PaintBlobRadii" .. i, Vector(7, 9, 6))) or Vector(7, 9, 6)
            local mass = (pred.GetNWFloat and pred:GetNWFloat("VNPC_PaintBlobMass" .. i, 45)) or 45
            local flags = (pred.GetNWInt and pred:GetNWInt("VNPC_PaintBlobFlags" .. i, 0)) or 0
            table.insert(blobs, {
                id = (pred.GetNWInt and pred:GetNWInt("VNPC_PaintBlobID" .. i, i * 31)) or i * 31,
                pos = pos,
                rx = math.max(2.5, radii.x),
                ry = math.max(2.5, radii.y),
                rz = math.max(2.5, radii.z),
                mass = mass,
                alive = bit.band(flags, 1) ~= 0,
                swallowing = bit.band(flags, 2) ~= 0,
                phantom = bit.band(flags, 4) ~= 0
            })
        end
    end
    return blobs
end

-- Pregnancy contributes its own low, round womb blob.
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
        alive = true
    }
end

-- Aggregate blob bounding box + center of mass. Returns nil when the belly is
-- effectively empty (no shape to paint).
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

    local minX, maxX, minY, maxY, minZ, maxZ = 0, 0, 0, 0, 0, 0
    local com = Vector(0, 0, 0)
    local totalMass = 0
    for _, b in ipairs(blobs) do
        local px, py, pz = b.pos and b.pos.x or 0, b.pos and b.pos.y or 0, b.pos and b.pos.z or 0
        minX = math.min(minX, px - b.rx)
        maxX = math.max(maxX, px + b.rx)
        minY = math.min(minY, py - b.ry)
        maxY = math.max(maxY, py + b.ry)
        minZ = math.min(minZ, pz - b.rz)
        maxZ = math.max(maxZ, pz + b.rz)
        com = com + Vector(px, py, pz) * b.mass
        totalMass = totalMass + b.mass
    end
    if totalMass > 0 then
        com = com / totalMass
    end

    local metrics = {
        blobs = blobs,
        totalMass = totalMass,
        com = com,
        rx = math.max(4.0, (maxX - minX) * 0.52),
        ry = math.max(4.5, (maxY - minY) * 0.55),
        rz = math.max(3.5, (maxZ - minZ) * 0.5),
        width = math.max(9, maxX - minX),
        depth = math.max(10, maxY - minY),
        height = math.max(8, maxZ - minZ)
    }
    -- A single blob should inflate roughly to its own size, not a tight box.
    if #blobs == 1 then
        local b = blobs[1]
        metrics.rx = math.max(metrics.rx, b.rx * 0.92)
        metrics.ry = math.max(metrics.ry, b.ry * 0.95)
        metrics.rz = math.max(metrics.rz, b.rz * 0.9)
    end

    pred.VNPC_BellyBlobMetrics = metrics
    return metrics
end

-- Replicates the current blob layout to clients (called by the physics module).
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
        if pred.SetNWVector then
            pred:SetNWVector("VNPC_PaintBlobPos" .. i, pos)
            pred:SetNWVector("VNPC_PaintBlobRadii" .. i, Vector(b.rx, b.ry, b.rz))
        end
        if pred.SetNWFloat then pred:SetNWFloat("VNPC_PaintBlobMass" .. i, b.mass) end
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
end

-- Returns a normalized "how much does this vertex belong to prey X" weight for
-- a vertex local point (lp, in the -1..1 belly space) vs a blob's local center.
-- half = half-extents of the rendered mesh along (x, y, z) so the weight space
-- matches the mesh vertex space exactly.
local function blobWeight(lp, blob, half)
    if not blob or not blob.pos or not half then return 0 end
    local dx = (lp.x * half.x) - blob.pos.x
    local dy = (lp.y * half.y) - blob.pos.y
    local dz = (lp.z * half.z) - blob.pos.z
    local rx = math.max(blob.rx * 1.15, 4)
    local ry = math.max(blob.ry * 1.15, 4)
    local rz = math.max(blob.rz * 1.15, 3.5)
    local nd = (dx * dx) / (rx * rx) + (dy * dy) / (ry * ry) + (dz * dz) / (rz * rz)
    if nd > 4 then return 0 end
    return math.exp(-nd)
end

-- Weight-painted per-vertex displacement. worldPos is the undeformed vertex in
-- world space, lp is its position in the belly's local -1..1 ellipsoid space.
-- Returns a world-space offset vector (or nil for no change).
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
    if not metrics or #metrics.blobs == 0 then return nil end
    if not chain.mid or not chain.mid.pos then return nil end

    local right = chain.right or chain.rightDir
    local fwd = chain.forward
    local up = chain.up
    if not isvector(right) or not isvector(fwd) or not isvector(up) then return nil end

    -- half-extents of the rendered mesh, matching the vertex loop in sh_vnpc_gpu_belly.lua
    local half = Vector(
        (chain.width or (metrics.rx * 2)) * 0.5,
        (chain.depth or (metrics.ry * 2)) * 0.5,
        (chain.height or (metrics.rz * 2)) * 0.5
    )

    local offset = Vector(0, 0, 0)
    for _, blob in ipairs(metrics.blobs) do
        if blob.womb and not GetConVar("vnpcs_gpu_belly_preg_shape"):GetBool() then continue end
        local w = blobWeight(lp, blob, half)
        if w <= 0.02 then continue end

        -- Push the surface outward along the belly radial direction, scaled by
        -- the blob's size so bigger prey make bigger, softer lumps.
        local blobCenter = chain.mid.pos + right * blob.pos.x + fwd * blob.pos.y + up * blob.pos.z
        local radial = worldPos - (chain.mid.pos or blobCenter)
        if radial:LengthSqr() < 0.001 then
            radial = fwd
        else
            radial:Normalize()
        end
        local lumpR = math.max(blob.rx, blob.rz) * 0.55
        local push = w * w * amp * lumpR * (0.55 + 0.45 * w)
        offset = offset + radial * push
    end

    if offset:LengthSqr() < 0.04 then return nil end
    return offset
end

-- Per-blob gaussian influence used to nudge the generated belly bones toward the
-- center of mass (asymmetric bellies). Returns a local-space offset.
function VNPC_GetBellyComShift(ent)
    if not IsValid(ent) then return Vector(0, 0, 0) end
    local asym = GetConVar("vnpcs_weight_paint_asymmetry")
    if asym and not asym:GetBool() then return Vector(0, 0, 0) end
    local metrics = ent.VNPC_BellyBlobMetrics or VNPC_GetBellyDeformMetrics(ent)
    if not metrics or not metrics.com then return Vector(0, 0, 0) end
    -- Clamp so a lopsided meal shifts the belly a bit but never detaches it.
    return Vector(
        math.Clamp(metrics.com.x * 0.35, -4.5, 4.5),
        math.Clamp(metrics.com.y * 0.25, -3.0, 3.0),
        math.Clamp(metrics.com.z * 0.2, -3.0, 3.0)
    )
end

-- Scaled bone multipliers for the character's own skeleton (weight painting on
-- the model mesh): the spine/pelvis stretch is driven by the blob bounding box,
-- and one side of the hips gets more scale when the meal sits to that side.
function VNPC_GetWeightPaintBoneScale(ent, chain)
    if not IsValid(ent) or not istable(chain) then return nil end
    local enabled = GetConVar("vnpcs_weight_paint_enabled")
    if enabled and not enabled:GetBool() then return nil end
    local metrics = ent.VNPC_BellyBlobMetrics or VNPC_GetBellyDeformMetrics(ent)
    if not metrics or #metrics.blobs == 0 then return nil end

    local extra = math.Clamp(metrics.totalMass * 0.0011, 0.05, 1.4)
    local com = metrics.com
    -- Side heaviness: -1..1 (negative = prey sits to the left)
    local side = math.Clamp(com.x / math.max(metrics.rx, 6), -1, 1)
    local sideL = 1 + extra * 0.10 * math.max(0, -side)
    local sideR = 1 + extra * 0.10 * math.max(0, side)

    return {
        extra = extra,
        spine = Vector(1 + extra * 0.28, 1 + extra * 0.85, 1 + extra * 0.22),
        spine1 = Vector(1 + extra * 0.22, 1 + extra * 0.70, 1 + extra * 0.18),
        pelvis = Vector(1 + extra * 0.20, 1 + extra * 0.55, 1 + extra * 0.16),
        thighL = Vector(sideL * (1 + extra * 0.06), 1 + extra * 0.18, sideL * (1 + extra * 0.10)),
        thighR = Vector(sideR * (1 + extra * 0.06), 1 + extra * 0.18, sideR * (1 + extra * 0.10))
    }
end

concommand.Add("vnpcs_weight_paint_status", function(ply)
    print("===============================================================")
    print("      V-NPCs DYNAMIC WEIGHT PAINTING & MESH DEFORM STATUS      ")
    print("===============================================================")
    print(" - Weight Paint Enabled: " .. tostring(GetConVar("vnpcs_weight_paint_enabled"):GetBool()))
    print(" - Per-Prey Lumps: " .. tostring(GetConVar("vnpcs_weight_paint_lumps"):GetBool()) .. " amp=" .. tostring(GetConVar("vnpcs_weight_paint_amp"):GetFloat()))
    print(" - Asymmetric Bones: " .. tostring(GetConVar("vnpcs_weight_paint_asymmetry"):GetBool()))
    print("-----------------------------------------")
    local count = 0
    for _, ent in ipairs(ents.FindByClass("npc_*")) do
        if IsValid(ent) and (ent.Predator or ent.VNPC_FemaleModelVore or ent.IsDrGNextbot or ent.VNPC_Belly or ent.Belly) then
            local metrics = VNPC_GetBellyDeformMetrics(ent)
            if metrics and #metrics.blobs > 0 then
                count = count + 1
                print(string.format(" -> #%d [%s] blobs=%d mass=%.1f R(x/y/z)=%.1f/%.1f/%.1f com=(%.1f, %.1f, %.1f)",
                    ent:EntIndex(), ent.PrintName or ent:GetClass(), #metrics.blobs, metrics.totalMass,
                    metrics.rx, metrics.ry, metrics.rz, metrics.com.x, metrics.com.y, metrics.com.z))
                for i, b in ipairs(metrics.blobs) do
                    print(string.format("      blob[%d] id=%d pos=(%.1f,%.1f,%.1f) r=(%.1f,%.1f,%.1f) mass=%.1f %s%s",
                        i, b.id or 0, b.pos and b.pos.x or 0, b.pos and b.pos.y or 0, b.pos and b.pos.z or 0,
                        b.rx, b.ry, b.rz, b.mass, b.alive and "ALIVE" or "dead", b.womb and " WOMB" or ""))
                end
            end
        end
    end
    if count == 0 then print(" - No predators with belly content currently spawned.") end
    print("===============================================================")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Weight paint status printed to console. Painted predators: " .. count)
    end
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
        alive = true
    }
    target.VNPC_PaintTestBlob = testBlob
    -- make sure metrics pick it up on both realms
    target.VNPC_BellyBlobMetrics = nil
    if SERVER then
        target.VNPC_BellyBlobs = target.VNPC_BellyBlobs or {}
        table.insert(target.VNPC_BellyBlobs, testBlob)
        VNPC_SyncPaintBlobNW(target)
    end
    ply:ChatPrint(string.format("[V-NPCs] Attached test paint blob (WxHxD %.0fx%.0fx%.0f) to %s. Enable vnpcs_gpu_belly_debug 1 to see the mesh.",
        w, h, d, tostring(target)))
end)
