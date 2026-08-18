-- V-NPCs GPU Belly Bone Generator (sh_vnpc_gpu_belly.lua)
-- Builds a virtual belly bone chain from any humanoid skeleton and skins a
-- GPU mesh to it. Stock HL2 / citizen / combine models do not need belly bones.

CreateConVar("vnpcs_gpu_belly_enabled", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Auto-generate belly bones and a GPU belly mesh on models that have no belly bones")
CreateConVar("vnpcs_gpu_belly_mesh", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Draw the GPU-skinned belly mesh generated from virtual bones")
CreateConVar("vnpcs_gpu_belly_bonescale", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Scale existing spine/pelvis/thigh bones so the character mesh itself grows a belly")
CreateConVar("vnpcs_gpu_belly_debug", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Draw generated belly bones and the GPU mesh wireframe")
CreateConVar("vnpcs_gpu_belly_struggle", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Procedural 4-spot mesh deformations on the GPU belly per struggling prey")
CreateConVar("vnpcs_gpu_belly_struggle_amp", "1.0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Amplitude multiplier for GPU belly struggle lumps")
CreateConVar("vnpcs_gpu_belly_gulp", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "GPU mesh gulp bulge on the upper torso near the neck, sized by the swallowed prey scale")
CreateConVar("vnpcs_gpu_belly_gulp_amp", "1.0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Amplitude multiplier for GPU neck/upper-torso gulp bulges")
CreateConVar("vnpcs_gpu_belly_torso_hull", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Optional collar-to-chest GPU sleeve. Off by default so it does not cover the real belly")
CreateConVar("vnpcs_gpu_belly_jiggle", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Spring-damper jiggle on the GPU belly after kicks and movement")
CreateConVar("vnpcs_gpu_belly_jiggle_amp", "1.0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Amplitude multiplier for GPU belly jiggle")
CreateConVar("vnpcs_gpu_belly_preg_shape", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "High/round pregnancy belly vs low/heavy swallowed-prey belly")
CreateConVar("vnpcs_gpu_belly_hide_entity", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Hide the ent_vore_belly model when the GPU mesh is drawing. Keep off to use the real belly")
CreateConVar("vnpcs_gpu_belly_size_scale", "1.15", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Multiplier on procedural GPU belly half-extents from prey volume/shape")
CreateConVar("vnpcs_gpu_belly_prefer_prey_mesh", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Draw the procedural GPU belly mesh from prey shape even when ent_vore_belly exists")

VNPC_GPU_BELLY_BONE_NAMES = {
    "VNPC_Belly_Root",
    "VNPC_Belly_Upper",
    "VNPC_Belly_Mid",
    "VNPC_Belly_Lower",
    "VNPC_Belly_L",
    "VNPC_Belly_R"
}

local ANCHOR_ALTS = {
    pelvis = { "ValveBiped.Bip01_Pelvis", "Pelvis", "pelvis", "bip_pelvis", "Root", "root" },
    spine = { "ValveBiped.Bip01_Spine", "Spine", "spine", "bip_spine_0" },
    spine1 = { "ValveBiped.Bip01_Spine1", "Spine1", "spine1", "bip_spine_1" },
    spine2 = { "ValveBiped.Bip01_Spine2", "Spine2", "spine2", "bip_spine_2", "ValveBiped.Bip01_Spine4" },
    neck = { "ValveBiped.Bip01_Neck1", "Neck1", "Neck", "neck", "bip_neck" },
    head = { "ValveBiped.Bip01_Head1", "Head1", "Head", "head" },
    lthigh = { "ValveBiped.Bip01_L_Thigh", "L_Thigh", "l_thigh" },
    rthigh = { "ValveBiped.Bip01_R_Thigh", "R_Thigh", "r_thigh" }
}

local SCALE_TARGETS = {
    { names = { "ValveBiped.Bip01_Spine", "Spine", "spine" }, mul = Vector(0.28, 0.85, 0.22), paintKey = "spine" },
    { names = { "ValveBiped.Bip01_Spine1", "Spine1", "spine1" }, mul = Vector(0.22, 0.70, 0.18), paintKey = "spine1" },
    { names = { "ValveBiped.Bip01_Pelvis", "Pelvis", "pelvis" }, mul = Vector(0.20, 0.55, 0.16), paintKey = "pelvis" },
    { names = { "ValveBiped.Bip01_L_Thigh", "L_Thigh", "l_thigh" }, mul = Vector(0.06, 0.18, 0.10), paintKey = "thighL" },
    { names = { "ValveBiped.Bip01_R_Thigh", "R_Thigh", "r_thigh" }, mul = Vector(0.06, 0.18, 0.10), paintKey = "thighR" }
}

local function lookup(ent, names)
    if not IsValid(ent) or not ent.LookupBone then return nil end
    for _, name in ipairs(names) do
        local id = ent:LookupBone(name)
        if id and id >= 0 then return id, name end
    end
    return nil
end

local function boneWorld(ent, names)
    local id = lookup(ent, names)
    if not id or not ent.GetBonePosition then return nil, nil end
    local pos, ang = ent:GetBonePosition(id)
    return pos, ang
end

local function isPredCandidate(ent)
    if not IsValid(ent) then return false end
    if ent.Vored or ent.VNPC_Vored then return false end
    if ent.Predator or ent.VNPC_FemaleModelVore or ent.IsDrGNextbot or ent.VNPC_Belly or ent.Belly then
        return true
    end
    if ent:IsNPC() or ent:IsNextBot() then
        return IsValid(ent.VNPC_Belly or ent.Belly) or (ent.GetNWEntity and IsValid(ent:GetNWEntity("Belly")))
    end
    return false
end

local function liveSize(ent)
    local scale = 0
    if VNPC_GetLiveBellySize then
        scale = VNPC_GetLiveBellySize(ent) or 0
    end
    local pregR = 0
    if VNPC_GetPregnancyBellyRadius then
        pregR = VNPC_GetPregnancyBellyRadius(ent) or 0
    end
    local fromPreg = pregR / 18
    if fromPreg > scale then scale = fromPreg end

    -- Prefer measured / packed prey volume so GPU size is procedural, not stuck
    -- on the old compressed value curve.
    if VNPC_GetBellyDeformMetrics then
        local m = VNPC_GetBellyDeformMetrics(ent)
        if m then
            local meanHalf = ((m.rx or 0) + (m.ry or 0) + (m.rz or 0)) / 3
            if meanHalf > 0 then
                scale = math.max(scale, meanHalf / 18)
            end
            if m.volRadius and m.volRadius > 0 then
                scale = math.max(scale, m.volRadius / 18)
            end
            if m.totalMass and m.totalMass > 0 then
                -- Cube-root mass → radius, same family as weight-paint volume floor.
                local massR = (m.totalMass ^ (1 / 3)) * 2.55
                scale = math.max(scale, massR / 18)
            end
        end
    end

    if ent.GetNWFloat then
        local boneScale = (ent:GetNWFloat("Bonescale", 1) or 1) - 1
        if boneScale > 0 then
            scale = math.max(scale, boneScale * 0.35)
        end
        -- Networked belly half extents (server paint sync)
        local half = ent:GetNWVector("VNPC_BellyHalf", vector_origin)
        if isvector(half) and half:LengthSqr() > 1 then
            local mean = (half.x + half.y + half.z) / 3
            scale = math.max(scale, mean / 18)
        end
    end
    return math.max(0, scale)
end

function VNPC_ModelHasBellyBones(ent)
    if not IsValid(ent) or not ent.LookupBone then return false end
    local names = {
        "ValveBiped.Bip01_Belly", "Belly", "belly", "stomach",
        "ValveBiped.Bip01_Spinebut", "ValveBiped.Bip01_L_Breast0",
        "ValveBiped.Bip01_L_Breast", "L_Breast", "boob_l"
    }
    for _, name in ipairs(names) do
        local id = ent:LookupBone(name)
        if id and id >= 0 then return true end
    end
    local count = ent.GetBoneCount and (ent:GetBoneCount() or 0) or 0
    for i = 0, count - 1 do
        local n = string.lower(ent:GetBoneName(i) or "")
        if n:find("belly") or n:find("stomach") or n:find("womb") or n:find("breast") or n:find("boob") then
            return true
        end
    end
    return false
end

function VNPC_UpdateVirtualBellyBones(ent)
    if not IsValid(ent) then return nil end
    local enabled = GetConVar("vnpcs_gpu_belly_enabled")
    if enabled and not enabled:GetBool() then return ent.VNPC_VirtualBellyBones end

    if ent.SetupBones then pcall(ent.SetupBones, ent) end

    local pelvis = boneWorld(ent, ANCHOR_ALTS.pelvis)
    local spine = boneWorld(ent, ANCHOR_ALTS.spine)
    local spine1 = boneWorld(ent, ANCHOR_ALTS.spine1)
    local spine2 = boneWorld(ent, ANCHOR_ALTS.spine2)
    local neck = boneWorld(ent, ANCHOR_ALTS.neck)
    local head = boneWorld(ent, ANCHOR_ALTS.head)
    local lthigh = boneWorld(ent, ANCHOR_ALTS.lthigh)
    local rthigh = boneWorld(ent, ANCHOR_ALTS.rthigh)

    if not pelvis then
        pelvis = (ent.WorldSpaceCenter and ent:WorldSpaceCenter()) or ent:GetPos() + Vector(0, 0, 32)
    end
    spine1 = spine1 or spine or (pelvis + Vector(0, 0, 12))
    spine2 = spine2 or spine1
    spine = spine or pelvis

    local up = (spine2 - pelvis)
    if up:LengthSqr() < 4 then up = Vector(0, 0, 1) else up:Normalize() end
    local fwd = (ent.GetForward and ent:GetForward()) or Vector(1, 0, 0)
    local right = up:Cross(fwd)
    if right:LengthSqr() < 0.01 then
        right = Vector(0, 1, 0)
    else
        right:Normalize()
    end
    fwd = right:Cross(up)
    fwd:Normalize()

    local mdlScale = (ent.GetModelScale and ent:GetModelScale()) or 1
    local size = liveSize(ent)
    local sizeMul = 1.15
    local sizeMulCv = GetConVar("vnpcs_gpu_belly_size_scale")
    if sizeMulCv then sizeMul = math.max(0.25, sizeMulCv:GetFloat() or 1.15) end
    local radius = math.max(5.5, 18 * math.max(size, 0.12) * math.max(mdlScale, 0.25) * sizeMul)
    if size < 0.05 and not ent.VNPC_IsPregnant then
        -- Resting abdomen only when truly empty — not a hard cap while prey is present.
        local hasPrey = false
        local belly = ent.VNPC_Belly or ent.Belly
        if IsValid(belly) and istable(belly.Prey) and #belly.Prey > 0 then hasPrey = true end
        if not hasPrey then
            radius = math.max(4.5, (ent.VNPC_BodyParts and ent.VNPC_BodyParts.torso and ent.VNPC_BodyParts.torso.width or 14) * 0.28)
        end
    end

    -- Metaball / weight-paint metrics: per-axis half extents (not max-of-box),
    -- volume floor, and gravity sag via COM shift. Prey geometry drives size.
    local blobMetrics = nil
    if VNPC_GetBellyDeformMetrics then
        blobMetrics = VNPC_GetBellyDeformMetrics(ent)
    end
    local comShift = Vector(0, 0, 0)
    local halfW, halfD, halfH = radius, radius, radius
    if blobMetrics then
        -- Keep elongation: use each axis independently instead of max(rx,ry,rz).
        -- sizeMul scales the whole procedural field so one adult human reads large.
        local sm = sizeMul
        halfW = math.max(radius * 0.55, (blobMetrics.rx or radius) * 1.15 * sm)
        halfD = math.max(radius * 0.60, (blobMetrics.ry or radius) * 1.20 * sm)
        halfH = math.max(radius * 0.50, (blobMetrics.rz or radius) * 1.10 * sm)
        -- Volume-correct floor so more mass = bigger belly even if tightly packed
        if blobMetrics.volRadius and blobMetrics.volRadius > 0 then
            local vr = blobMetrics.volRadius * sm
            halfW = math.max(halfW, vr * 0.85)
            halfD = math.max(halfD, vr * 0.92)
            halfH = math.max(halfH, vr * 0.78)
        end
        -- Mass floor: 80 value-ish meals should never collapse to a fist-sized bump.
        if blobMetrics.totalMass and blobMetrics.totalMass > 0 then
            local massR = (blobMetrics.totalMass ^ (1 / 3)) * 3.1 * sm
            halfW = math.max(halfW, massR * 0.78)
            halfD = math.max(halfD, massR * 0.88)
            halfH = math.max(halfH, massR * 0.70)
        end
        radius = (halfW + halfD + halfH) / 3
        -- Re-derive size from true geometry so bone-scale / consumers see full belly.
        size = math.max(size, radius / 18)
        if VNPC_GetBellyComShift then
            comShift = VNPC_GetBellyComShift(ent)
        end
    end

    local root = LerpVector(0.38, pelvis, spine1) + fwd * (3.5 + halfD * 0.22) + comShift
    local mid = root + fwd * (halfD * 0.58)
    local upper = root + up * (halfH * 0.42) + fwd * (halfD * 0.18)
    local lower = root - up * (halfH * 0.48) + fwd * (halfD * 0.32)
    if lthigh and rthigh then
        local hip = LerpVector(0.5, lthigh, rthigh)
        lower = LerpVector(0.35, lower, hip + fwd * (halfD * 0.4))
    end
    local left = root - right * (halfW * 0.95) + fwd * (halfD * 0.22)
    local rightB = root + right * (halfW * 0.95) + fwd * (halfD * 0.22)
    local gulpNeck = (neck or head or spine2 or (pelvis + up * 28)) + fwd * (3.0 + halfD * 0.06)
    local gulpChest = (spine2 or spine1 or (gulpNeck - up * 8)) + fwd * (4.2 + halfD * 0.10)
    local ang = fwd:Angle()

    local function bone(name, pos, r, parent)
        return {
            name = name,
            pos = pos,
            ang = ang,
            radius = r,
            parent = parent,
            generated = true
        }
    end

    local chain = {
        hasModelBellyBones = VNPC_ModelHasBellyBones(ent),
        size = size,
        radius = radius,
        -- True packed bounding box extents (width = side-to-side of shelf pack).
        width = halfW * 2.05,
        height = halfH * 1.85,
        depth = halfD * 1.65,
        halfW = halfW,
        halfD = halfD,
        halfH = halfH,
        forward = fwd,
        up = up,
        rightDir = right,
        right = right,
        blobMetrics = blobMetrics,
        comShift = comShift,
        root = bone("VNPC_Belly_Root", root, math.max(halfW, halfD, halfH) * 0.55, nil),
        upper = bone("VNPC_Belly_Upper", upper, halfH * 0.55, "VNPC_Belly_Root"),
        mid = bone("VNPC_Belly_Mid", mid, math.max(halfW, halfD) * 0.95, "VNPC_Belly_Root"),
        lower = bone("VNPC_Belly_Lower", lower, halfH * 0.70, "VNPC_Belly_Root"),
        left = bone("VNPC_Belly_L", left, halfW * 0.55, "VNPC_Belly_Root"),
        right = bone("VNPC_Belly_R", rightB, halfW * 0.55, "VNPC_Belly_Root"),
        gulpNeck = bone("VNPC_Gulp_Neck", gulpNeck, math.max(3.4, 5.2), "VNPC_Belly_Upper"),
        gulpChest = bone("VNPC_Gulp_Chest", gulpChest, math.max(4.0, 6.0), "VNPC_Gulp_Neck")
    }
    chain.byName = {
        VNPC_Belly_Root = chain.root,
        VNPC_Belly_Upper = chain.upper,
        VNPC_Belly_Mid = chain.mid,
        VNPC_Belly_Lower = chain.lower,
        VNPC_Belly_L = chain.left,
        VNPC_Belly_R = chain.right,
        VNPC_Gulp_Neck = chain.gulpNeck,
        VNPC_Gulp_Chest = chain.gulpChest
    }

    ent.VNPC_VirtualBellyBones = chain
    ent.VNPC_GeneratedBellyBones = true
    return chain
end

function VNPC_GetVirtualBellyBones(ent)
    if not IsValid(ent) then return nil end
    return VNPC_UpdateVirtualBellyBones(ent)
end

function VNPC_GetVirtualBellyBone(ent, name)
    local chain = VNPC_GetVirtualBellyBones(ent)
    if not chain or not chain.byName then return nil end
    return chain.byName[name]
end

-- 4 unique local-space struggle lumps per prey (head, torso, left limb, right limb).
local STRUGGLE_SPOT_BASES = {
    { kind = "head",  pos = Vector(0.10, 0.58,  0.46), radius = 0.28, freq = 5.4 },
    { kind = "torso", pos = Vector(-0.08, 0.74,  0.04), radius = 0.36, freq = 3.7 },
    { kind = "lleg",  pos = Vector(0.50, 0.36, -0.40), radius = 0.26, freq = 6.2 },
    { kind = "rleg",  pos = Vector(-0.50, 0.40, -0.38), radius = 0.26, freq = 5.8 }
}
local GPU_STRUGGLE_MAX_PREY = 4

local function gpuHash01(a, b)
    local n = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
    return n - math.floor(n)
end

local function gpuClampLocal(v)
    v.x = math.Clamp(v.x, -0.85, 0.85)
    v.y = math.Clamp(v.y, 0.12, 0.95)
    v.z = math.Clamp(v.z, -0.78, 0.72)
    return v
end

function VNPC_SyncGPUBellyStruggle(pred)
    if not IsValid(pred) then return 0 end
    local belly = pred.VNPC_Belly or pred.Belly
    if not IsValid(belly) and pred.GetNWEntity then
        belly = pred:GetNWEntity("Belly")
    end
    local n = 0
    if IsValid(belly) and istable(belly.Prey) then
        for _, info in ipairs(belly.Prey) do
            if n >= GPU_STRUGGLE_MAX_PREY then break end
            local prey = info and info.Entity
            if not IsValid(prey) then continue end
            if info.Absorbing then continue end
            if info.WombPrey or info.NoDigest or prey.VNPC_IsWombPrey or prey.VNPC_IsUnbornBaby then continue end
            if info.Alive == false and not prey.VNPC_IsBeingSwallowed then continue end
            local mul = 1.0
            if VNPC_GetPreyPersonality then
                local _, data = VNPC_GetPreyPersonality(prey)
                if data and data.struggle_multiplier then
                    mul = data.struggle_multiplier
                end
            end
            if prey.VNPC_IsBeingSwallowed then
                mul = mul * 0.65
            end
            n = n + 1
            if pred.SetNWInt then pred:SetNWInt("VNPC_GPUStruggleID" .. n, prey:EntIndex()) end
            if pred.SetNWFloat then pred:SetNWFloat("VNPC_GPUStruggleMul" .. n, mul) end
            local headN, torsoN, hipN = 1, 1, 1
            if VNPC_MeasureBodyParts then
                local parts = VNPC_MeasureBodyParts(prey)
                if parts then
                    headN = ((parts.head and parts.head.width) or 7.2) / 7.2
                    torsoN = ((parts.torso and parts.torso.width) or 14) / 14
                    hipN = ((parts.pelvis and parts.pelvis.width) or 12) / 12
                end
            end
            if pred.SetNWFloat then
                pred:SetNWFloat("VNPC_GPUSilHead" .. n, headN)
                pred:SetNWFloat("VNPC_GPUSilTorso" .. n, torsoN)
                pred:SetNWFloat("VNPC_GPUSilHip" .. n, hipN)
            end
        end
    end
    if pred.VNPC_GPUStruggleTest then
        for _, row in ipairs(pred.VNPC_GPUStruggleTest) do
            if n >= GPU_STRUGGLE_MAX_PREY then break end
            n = n + 1
            if pred.SetNWInt then pred:SetNWInt("VNPC_GPUStruggleID" .. n, tonumber(row.id) or (pred:EntIndex() * 10 + n)) end
            if pred.SetNWFloat then pred:SetNWFloat("VNPC_GPUStruggleMul" .. n, tonumber(row.mul) or 1.2) end
        end
    end
    if pred.SetNWInt then pred:SetNWInt("VNPC_GPUStruggleN", n) end
    return n
end

function VNPC_GetGPUBellyStruggleSpots(ent, chain)
    if not IsValid(ent) then return {} end
    local cv = GetConVar("vnpcs_gpu_belly_struggle")
    if cv and not cv:GetBool() then return {} end
    local ampMul = 1.0
    local ampCv = GetConVar("vnpcs_gpu_belly_struggle_amp")
    if ampCv then ampMul = ampCv:GetFloat() or 1.0 end
    if ampMul <= 0 then return {} end

    local count = (ent.GetNWInt and ent:GetNWInt("VNPC_GPUStruggleN", 0)) or 0
    if count <= 0 and ent.VNPC_GPUStruggleTest then
        count = math.min(GPU_STRUGGLE_MAX_PREY, #ent.VNPC_GPUStruggleTest)
    end
    if count <= 0 then return {} end

    chain = chain or ent.VNPC_VirtualBellyBones
    local now = CurTime()
    local spots = {}
    for p = 1, math.min(count, GPU_STRUGGLE_MAX_PREY) do
        local preyId = (ent.GetNWInt and ent:GetNWInt("VNPC_GPUStruggleID" .. p, p * 17 + ent:EntIndex())) or (p * 17)
        local mul = (ent.GetNWFloat and ent:GetNWFloat("VNPC_GPUStruggleMul" .. p, 1.0)) or 1.0
        if mul <= 0.02 then continue end
        local side = (p % 2 == 0) and -1 or 1
        local slotShift = (p - 1) * 0.18
        for s = 1, 4 do
            local base = STRUGGLE_SPOT_BASES[s]
            local jx = (gpuHash01(preyId, s * 3.1) - 0.5) * 0.38
            local jy = (gpuHash01(preyId, s * 7.7) - 0.5) * 0.16
            local jz = (gpuHash01(preyId, s * 11.3) - 0.5) * 0.28
            local extraX = 0
            if s == 3 then extraX = slotShift elseif s == 4 then extraX = -slotShift end
            local lp = gpuClampLocal(Vector(
                base.pos.x * side + jx + extraX,
                base.pos.y + jy,
                base.pos.z + jz
            ))
            local phase = preyId * 0.73 + s * 1.31 + p * 0.41
            local kick = math.max(0, math.sin(now * base.freq + phase))
            kick = kick * kick
            local pulse = 0.35 + 0.65 * kick
            local amp = mul * ampMul * pulse * ((s == 2) and 0.34 or 0.26)
            local world = nil
            if chain and chain.mid then
                local rdir = chain.rightDir or chain.right
                world = chain.mid.pos
                    + rdir * (lp.x * chain.width * 0.5)
                    + chain.forward * (lp.y * chain.depth * 0.5)
                    + chain.up * (lp.z * chain.height * 0.5)
            end
            table.insert(spots, {
                kind = base.kind,
                preyId = preyId,
                lp = lp,
                radius = base.radius,
                amp = amp,
                world = world
            })
        end
    end
    ent.VNPC_GPUStruggleSpots = spots
    return spots
end

function VNPC_ApplyGPUBellyStruggleDeform(lp, spots)
    if not spots or #spots == 0 then return 0 end
    local push = 0
    for i = 1, #spots do
        local spot = spots[i]
        if (spot.amp or 0) <= 0.001 then continue end
        local dx = lp.x - spot.lp.x
        local dy = lp.y - spot.lp.y
        local dz = lp.z - spot.lp.z
        local d = math.sqrt(dx * dx + dy * dy + dz * dz)
        local r = spot.radius or 0.28
        if d < r then
            local g = math.exp(-(d * d) / (2 * r * r + 0.0001))
            push = push + spot.amp * (1 - d / r) * g
        end
    end
    return push
end

local GPU_GULP_MAX = 4

function VNPC_GuessPreySpeciesName(prey)
    if not IsValid(prey) then return "human" end
    if VNPC_GetPreySpecies then
        local ok, sp = pcall(VNPC_GetPreySpecies, prey)
        if ok and isstring(sp) and sp ~= "" then return sp end
    end
    local cls = string.lower(prey:GetClass() or "")
    local mdl = string.lower(prey:GetModel() or "")
    if cls:find("antlionguard") or mdl:find("antlion_guard") or mdl:find("antlionguard") then
        return "antlionguard"
    elseif cls:find("antlion") or mdl:find("antlion") then
        return "antlion"
    elseif cls:find("headcrab") or mdl:find("headcrab") then
        return "headcrab"
    elseif cls:find("zombie") or mdl:find("zombie") then
        return "zombie"
    elseif cls:find("vortigaunt") or mdl:find("vortigaunt") then
        return "vortigaunt"
    end
    return "human"
end

function VNPC_GetPreyGulpScale(prey)
    if not IsValid(prey) then return 1.0 end
    local mdlScale = (prey.GetModelScale and prey:GetModelScale()) or 1
    if not isnumber(mdlScale) or mdlScale <= 0 then mdlScale = 1 end
    local fromParts = mdlScale
    if VNPC_MeasureBodyParts then
        local parts = VNPC_MeasureBodyParts(prey)
        if parts then
            local torso = ((parts.torso and parts.torso.width) or 14) / 14
            local head = ((parts.head and parts.head.width) or 7.2) / 7.2
            local body = (parts.bodyHeight or 72) / 72
            fromParts = math.max(torso, head * 0.9, body, mdlScale)
        end
    elseif prey.GetModelBounds then
        local mins, maxs = prey:GetModelBounds()
        if mins and maxs then
            local h = math.abs(maxs.z - mins.z) * mdlScale
            local w = math.max(math.abs(maxs.x - mins.x), math.abs(maxs.y - mins.y)) * mdlScale
            fromParts = math.max(mdlScale, h / 72, w / 32)
        end
    end
    local speciesMul = 1.0
    local sp = VNPC_GuessPreySpeciesName(prey)
    if sp == "headcrab" then
        speciesMul = 0.42
    elseif sp == "antlion" then
        speciesMul = 0.82
    elseif sp == "antlionguard" then
        speciesMul = 1.85
    elseif sp == "vortigaunt" then
        speciesMul = 1.12
    elseif sp == "zombie" then
        speciesMul = 1.06
    end
    return math.Clamp(fromParts * speciesMul, 0.28, 2.8)
end

function VNPC_SyncGPUBellyGulp(pred)
    if not IsValid(pred) then return 0 end
    local cv = GetConVar("vnpcs_gpu_belly_gulp")
    if cv and not cv:GetBool() then
        if pred.SetNWInt then pred:SetNWInt("VNPC_GPUGulpN", 0) end
        return 0
    end
    local belly = pred.VNPC_Belly or pred.Belly
    if not IsValid(belly) and pred.GetNWEntity then
        belly = pred:GetNWEntity("Belly")
    end
    local n = 0
    local function writeGulp(prey, scale, prog)
        if n >= GPU_GULP_MAX then return end
        n = n + 1
        if pred.SetNWFloat then
            pred:SetNWFloat("VNPC_GPUGulpScale" .. n, scale)
            pred:SetNWFloat("VNPC_GPUGulpProg" .. n, math.Clamp(prog, 0, 1))
        end
        if pred.SetNWInt then pred:SetNWInt("VNPC_GPUGulpID" .. n, IsValid(prey) and prey:EntIndex() or (pred:EntIndex() * 20 + n)) end
    end
    if IsValid(belly) and istable(belly.Prey) then
        for _, info in ipairs(belly.Prey) do
            if n >= GPU_GULP_MAX then break end
            local prey = info and info.Entity
            if not IsValid(prey) then continue end
            if info.Absorbing then continue end
            local depth = tonumber(prey.VNPC_IngestionDepth)
            local swallowing = prey.VNPC_IsBeingSwallowed and true or false
            if not swallowing and (not depth or depth >= 0.98) then continue end
            if not depth then depth = swallowing and 0.45 or 1 end
            if depth >= 0.98 then continue end
            writeGulp(prey, VNPC_GetPreyGulpScale(prey), depth)
        end
    end
    if n == 0 and (pred.VNPC_IsHumanOralSwallow or pred.Swallowing or (pred.GetNWBool and pred:GetNWBool("VNPC_IsHumanOralSwallow"))) then
        for _, ent in ipairs(ents.FindInSphere(pred:GetPos(), 140)) do
            if n >= GPU_GULP_MAX then break end
            if not IsValid(ent) or ent == pred then continue end
            if not ent.VNPC_IsBeingSwallowed then continue end
            writeGulp(ent, VNPC_GetPreyGulpScale(ent), tonumber(ent.VNPC_IngestionDepth) or 0.45)
        end
    end
    if pred.VNPC_GPUGulpTest then
        for _, row in ipairs(pred.VNPC_GPUGulpTest) do
            if n >= GPU_GULP_MAX then break end
            writeGulp(nil, tonumber(row.scale) or 1.0, tonumber(row.prog) or 0.5)
            if pred.SetNWInt then pred:SetNWInt("VNPC_GPUGulpID" .. n, tonumber(row.id) or (pred:EntIndex() * 20 + n)) end
        end
    end
    if pred.SetNWInt then pred:SetNWInt("VNPC_GPUGulpN", n) end
    return n
end

function VNPC_GetGPUBellyGulpSpots(ent, chain)
    if not IsValid(ent) then return {} end
    local cv = GetConVar("vnpcs_gpu_belly_gulp")
    if cv and not cv:GetBool() then return {} end
    local ampMul = 1.0
    local ampCv = GetConVar("vnpcs_gpu_belly_gulp_amp")
    if ampCv then ampMul = ampCv:GetFloat() or 1.0 end
    if ampMul <= 0 then return {} end

    local count = (ent.GetNWInt and ent:GetNWInt("VNPC_GPUGulpN", 0)) or 0
    if count <= 0 and ent.VNPC_GPUGulpTest then
        count = math.min(GPU_GULP_MAX, #ent.VNPC_GPUGulpTest)
    end
    if count <= 0 then return {} end

    local frameKey = (CLIENT and FrameNumber and FrameNumber()) or math.floor(CurTime() * 40)
    if ent.VNPC_GPUGulpSpotFrame == frameKey and ent.VNPC_GPUGulpSpots then
        return ent.VNPC_GPUGulpSpots
    end
    ent.VNPC_GPUGulpSpotFrame = frameKey

    chain = chain or ent.VNPC_VirtualBellyBones
    if not chain and VNPC_UpdateVirtualBellyBones then
        chain = VNPC_UpdateVirtualBellyBones(ent)
    end
    if not chain then return {} end

    local neckPos = chain.gulpNeck and chain.gulpNeck.pos
    local chestPos = chain.gulpChest and chain.gulpChest.pos
    local upperPos = chain.upper and chain.upper.pos
    local midPos = chain.mid and chain.mid.pos
    if not neckPos then
        neckPos = ent:GetPos() + Vector(0, 0, 62)
    end
    if not chestPos then chestPos = LerpVector(0.42, neckPos, midPos or neckPos) end
    if not upperPos then upperPos = LerpVector(0.72, neckPos, midPos or chestPos) end
    if not midPos then midPos = chestPos end

    local now = CurTime()
    local spots = {}
    ent.VNPC_GPUGulpSmooth = ent.VNPC_GPUGulpSmooth or {}
    for p = 1, math.min(count, GPU_GULP_MAX) do
        local scale = (ent.GetNWFloat and ent:GetNWFloat("VNPC_GPUGulpScale" .. p, 1)) or 1
        local prog = (ent.GetNWFloat and ent:GetNWFloat("VNPC_GPUGulpProg" .. p, 0.5)) or 0.5
        if ent.VNPC_GPUGulpTest and ent.VNPC_GPUGulpTest[p] then
            local row = ent.VNPC_GPUGulpTest[p]
            scale = tonumber(row.scale) or scale
            if row.animate then
                prog = 0.32 + 0.50 * (0.5 + 0.5 * math.sin(now * 0.85 + p))
            else
                prog = tonumber(row.prog) or prog
            end
        else
            local sm = ent.VNPC_GPUGulpSmooth[p]
            if sm == nil then sm = prog end
            sm = Lerp(math.Clamp(FrameTime() * 10, 0, 1), sm, prog)
            ent.VNPC_GPUGulpSmooth[p] = sm
            prog = sm
        end
        scale = math.Clamp(tonumber(scale) or 1, 0.28, 2.8)
        prog = math.Clamp(tonumber(prog) or 0.5, 0, 1)

        local vis = 0
        if prog < 0.28 then
            vis = 0
        elseif prog < 0.40 then
            vis = (prog - 0.28) / 0.12
        elseif prog < 0.82 then
            vis = 1
        else
            vis = math.max(0, 1 - (prog - 0.82) / 0.18)
        end
        if vis <= 0.02 then continue end

        local world
        if prog < 0.48 then
            world = LerpVector(math.Clamp((prog - 0.28) / 0.20, 0, 1), neckPos, chestPos)
        elseif prog < 0.78 then
            world = LerpVector(math.Clamp((prog - 0.48) / 0.30, 0, 1), chestPos, upperPos)
        else
            world = LerpVector(math.Clamp((prog - 0.78) / 0.22, 0, 1), upperPos, midPos)
        end

        local wriggle = 1 + 0.08 * math.sin(now * 9.5 + p * 2.1)
        local radius = (4.6 + scale * 5.4) * wriggle
        local amp = vis * ampMul * (0.42 + scale * 0.38)
        table.insert(spots, {
            kind = "gulp",
            preyScale = scale,
            prog = prog,
            vis = vis,
            world = world,
            radius = radius,
            length = 7.5 + scale * 8.5,
            amp = amp
        })
    end
    ent.VNPC_GPUGulpSpots = spots
    return spots
end

function VNPC_ApplyGPUBellyGulpDeform(world, spots)
    if not spots or #spots == 0 or not world then return Vector(0, 0, 0) end
    local push = Vector(0, 0, 0)
    for i = 1, #spots do
        local spot = spots[i]
        if not spot.world or (spot.amp or 0) <= 0.001 then continue end
        local delta = world - spot.world
        local d = delta:Length()
        local r = spot.radius or 8
        if d < r then
            local g = math.exp(-(d * d) / (2 * r * r + 0.0001))
            local nrm = delta
            if nrm:LengthSqr() < 0.001 then
                nrm = Vector(0, 1, 0)
            else
                nrm:Normalize()
            end
            push = push + nrm * (spot.amp * (1 - d / r) * g * r * 0.55)
        end
    end
    return push
end

function VNPC_ApplyGeneratedBellyBoneScale(ent, chain)
    if not IsValid(ent) or not ent.ManipulateBoneScale then return end
    local cv = GetConVar("vnpcs_gpu_belly_bonescale")
    if cv and not cv:GetBool() then return end
    chain = chain or ent.VNPC_VirtualBellyBones
    if not chain then return end

    local extra = math.Clamp((chain.size or 0) * 0.85, 0, 1.35)
    -- Weight painting: when prey shape blobs are present, use the blob-driven
    -- per-axis / per-side bone scales instead of the flat multiplier.
    local painted = nil
    if VNPC_GetWeightPaintBoneScale then
        painted = VNPC_GetWeightPaintBoneScale(ent, chain)
        if painted then
            extra = painted.extra
        end
    end
    if extra < 0.03 then
        if ent.VNPC_GPUBellyScaled then
            for _, spec in ipairs(SCALE_TARGETS) do
                local id = lookup(ent, spec.names)
                if id then
                    ent:ManipulateBoneScale(id, Vector(1, 1, 1))
                end
            end
            ent.VNPC_GPUBellyScaled = nil
        end
        return
    end

    for _, spec in ipairs(SCALE_TARGETS) do
        local id = lookup(ent, spec.names)
        if id and spec.mul then
            local w = spec.mul
            local scaleVec
            if painted then
                local key = spec.paintKey
                scaleVec = painted[key] or Vector(1 + extra * w.x, 1 + extra * w.y, 1 + extra * w.z)
            else
                scaleVec = Vector(1 + extra * w.x, 1 + extra * w.y, 1 + extra * w.z)
            end
            ent:ManipulateBoneScale(id, scaleVec)
        end
    end
    ent.VNPC_GPUBellyScaled = true
end

if CLIENT then
    local LAT, LON = 11, 16
    local UNIT_VERTS, UNIT_TRIS

    local function buildUnitSphere()
        UNIT_VERTS = {}
        UNIT_TRIS = {}
        for i = 0, LAT do
            local phi = (i / LAT) * math.pi
            local sp, cp = math.sin(phi), math.cos(phi)
            for j = 0, LON - 1 do
                local th = (j / LON) * math.pi * 2
                -- local: x=right, y=forward, z=up; squash into a teardrop belly
                local x, y, z = sp * math.cos(th), sp * math.sin(th), cp
                local down = math.Clamp((-z + 0.15) * 0.55, 0, 1)
                table.insert(UNIT_VERTS, {
                    pos = Vector(x * (0.92 + down * 0.22), y * (1.05 + down * 0.18), z * 0.88 - 0.08),
                    nrm = Vector(x, y, z),
                    u = j / LON,
                    v = i / LAT
                })
            end
        end
        local function idx(i, j)
            return i * LON + (j % LON) + 1
        end
        for i = 0, LAT - 1 do
            for j = 0, LON - 1 do
                local a, b, c, d = idx(i, j), idx(i, j + 1), idx(i + 1, j), idx(i + 1, j + 1)
                table.insert(UNIT_TRIS, { a, b, c })
                table.insert(UNIT_TRIS, { b, d, c })
            end
        end
    end

    local function bellyMaterial(ent)
        if IsValid(ent) and ent.GetMaterials then
            local mats = ent:GetMaterials()
            if istable(mats) then
                for _, name in ipairs(mats) do
                    if isstring(name) and name ~= "" and not name:find("eyeball") and not name:find("eye") then
                        local mat = Material(name)
                        if mat and not mat:IsError() then
                            return mat
                        end
                    end
                end
            end
        end
        return Material("vnpcs/gpu_belly")
    end

    local function drawGeneratedBelly(ent, chain)
        if not UNIT_VERTS then buildUnitSphere() end
        local mid = chain.mid
        if not mid then return end
        local rx = chain.width * 0.5
        local ry = chain.depth * 0.5
        local rz = chain.height * 0.5
        local right, fwd, up = chain.right, chain.forward, chain.up
        local spots = VNPC_GetGPUBellyStruggleSpots(ent, chain)
        local gulps = VNPC_GetGPUBellyGulpSpots(ent, chain)
        local mat = bellyMaterial(ent)
        if mat and chain.mid then
            mat:SetVector("$gore_center", mid.pos)
            mat:SetFloat("$gore_radius", chain.radius or 8)
            mat:SetFloat("$gore_intensity", math.Clamp((chain.size or 0) * 14, 0, 80))
            for i = 1, 4 do
                local spot = spots[i]
                if spot and spot.world then
                    mat:SetVector("$gore_spot" .. i, spot.world)
                    mat:SetFloat("$gore_spotamp" .. i, spot.amp or 0)
                    mat:SetFloat("$gore_spotradius" .. i, (spot.radius or 0.28) * (chain.radius or 8))
                else
                    mat:SetVector("$gore_spot" .. i, mid.pos)
                    mat:SetFloat("$gore_spotamp" .. i, 0)
                    mat:SetFloat("$gore_spotradius" .. i, 0)
                end
            end
        end
        render.SetMaterial(mat)
        mesh.Begin(MATERIAL_TRIANGLES, #UNIT_TRIS)
        for t = 1, #UNIT_TRIS do
            local tri = UNIT_TRIS[t]
            for k = 1, 3 do
                local v = UNIT_VERTS[tri[k]]
                local lp = v.pos
                local world = mid.pos + right * (lp.x * rx) + fwd * (lp.y * ry) + up * (lp.z * rz)
                -- pull the sides toward the generated L/R bones so the mesh is actually skinned
                if chain.left and lp.x < -0.15 then
                    world = LerpVector((-lp.x) * 0.35, world, chain.left.pos + fwd * (lp.y * ry * 0.4) + up * (lp.z * rz * 0.4))
                elseif chain.right and lp.x > 0.15 then
                    world = LerpVector(lp.x * 0.35, world, chain.right.pos + fwd * (lp.y * ry * 0.4) + up * (lp.z * rz * 0.4))
                end
                if chain.lower and lp.z < -0.2 then
                    world = LerpVector((-lp.z) * 0.28, world, chain.lower.pos + fwd * (lp.y * ry * 0.25))
                end
                if chain.upper and lp.z > 0.35 then
                    world = LerpVector(lp.z * 0.18, world, chain.upper.pos)
                end
                local nrm = (right * v.nrm.x + fwd * v.nrm.y + up * v.nrm.z)
                nrm:Normalize()
                local push = VNPC_ApplyGPUBellyStruggleDeform(lp, spots)
                if push > 0 then
                    world = world + nrm * (push * (chain.radius or 8))
                end
                -- Metaball iso-surface deform (merged prey bulges) + field normals
                chain._lastMetaNormal = nil
                if VNPC_ApplyWeightPaintDeform then
                    local wd = VNPC_ApplyWeightPaintDeform(world, lp, ent, chain)
                    if wd and wd:LengthSqr() > 0.01 then
                        world = world + wd
                    end
                    if chain._lastMetaNormal then
                        nrm = chain._lastMetaNormal
                    end
                end
                local gpush = VNPC_ApplyGPUBellyGulpDeform(world, gulps)
                if gpush and gpush:LengthSqr() > 0.01 then
                    world = world + gpush
                end
                mesh.Position(world)
                mesh.Normal(nrm)
                mesh.TexCoord(0, v.u, v.v)
                mesh.Color(255, 255, 255, 255)
                mesh.AdvanceVertex()
            end
        end
        mesh.End()
    end

    local function drawGulpBulges(ent, chain)
        local spots = VNPC_GetGPUBellyGulpSpots(ent, chain)
        if not spots or #spots == 0 then return end
        if not UNIT_VERTS then buildUnitSphere() end
        local mat = bellyMaterial(ent)
        render.SetMaterial(mat)
        local fwd = (chain and chain.forward) or Vector(1, 0, 0)
        local up = (chain and chain.up) or Vector(0, 0, 1)
        local right = (chain and chain.rightDir) or up:Cross(fwd)
        if not isvector(right) or right:LengthSqr() < 0.01 then right = Vector(0, 1, 0) else right:Normalize() end
        for _, spot in ipairs(spots) do
            if not spot.world then continue end
            local rx = spot.radius * 0.72
            local ry = spot.radius * 0.95
            local rz = (spot.length or (spot.radius * 1.4)) * 0.42
            mesh.Begin(MATERIAL_TRIANGLES, #UNIT_TRIS)
            for t = 1, #UNIT_TRIS do
                local tri = UNIT_TRIS[t]
                for k = 1, 3 do
                    local v = UNIT_VERTS[tri[k]]
                    local lp = v.pos
                    local world = spot.world
                        + right * (lp.x * rx)
                        + fwd * (lp.y * ry * 0.85 + 0.18 * ry)
                        + up * (lp.z * rz)
                    local nrm = (right * v.nrm.x + fwd * v.nrm.y + up * v.nrm.z)
                    nrm:Normalize()
                    mesh.Position(world)
                    mesh.Normal(nrm)
                    mesh.TexCoord(0, v.u, v.v)
                    mesh.Color(255, 255, 255, 255)
                    mesh.AdvanceVertex()
                end
            end
            mesh.End()
        end
    end

    hook.Add("PreDrawOpaqueRenderables", "VNPC_GPUBelly_GenerateBones", function()
        local enabled = GetConVar("vnpcs_gpu_belly_enabled")
        if enabled and not enabled:GetBool() then return end
        for _, ent in ipairs(ents.FindByClass("npc_*")) do
            if isPredCandidate(ent) then
                local chain = VNPC_UpdateVirtualBellyBones(ent)
                if chain then
                    VNPC_ApplyGeneratedBellyBoneScale(ent, chain)
                end
            end
        end
    end)

    hook.Add("PostDrawOpaqueRenderables", "VNPC_GPUBelly_DrawMesh", function()
        local enabled = GetConVar("vnpcs_gpu_belly_enabled")
        if enabled and not enabled:GetBool() then return end
        local meshOn = GetConVar("vnpcs_gpu_belly_mesh")
        if meshOn and not meshOn:GetBool() then return end
        for _, ent in ipairs(ents.FindByClass("npc_*")) do
            if not isPredCandidate(ent) then continue end
            if ent:IsDormant() or (ent.GetNoDraw and ent:GetNoDraw()) then continue end
            local chain = ent.VNPC_VirtualBellyBones or VNPC_UpdateVirtualBellyBones(ent)
            if not chain then continue end
            local usedFX = false
            if VNPC_DrawGPUBellyFX then
                local ok, res = pcall(VNPC_DrawGPUBellyFX, ent, chain)
                usedFX = ok and res ~= false
            end
            if not usedFX and (chain.size or 0) >= 0.035 then
                local liveBelly = (VNPC_GetPredBelly and VNPC_GetPredBelly(ent)) or ent.VNPC_Belly or ent.Belly
                local preferGPU = true
                local preferCv = GetConVar("vnpcs_gpu_belly_prefer_prey_mesh")
                if preferCv then preferGPU = preferCv:GetBool() end
                -- Draw procedural mesh from prey volume even when the classic
                -- belly entity exists (unless prefer is off and a live belly is present).
                if preferGPU or not IsValid(liveBelly) then
                    pcall(drawGeneratedBelly, ent, chain)
                end
            end
            if VNPC_DrawGPUGulpFX then
                pcall(VNPC_DrawGPUGulpFX, ent, chain)
            else
                pcall(drawGulpBulges, ent, chain)
            end
        end
    end)

    hook.Add("PostDrawTranslucentRenderables", "VNPC_GPUBelly_Debug", function()
        local dbg = GetConVar("vnpcs_gpu_belly_debug")
        if not dbg or not dbg:GetBool() then return end
        render.SetColorMaterial()
        for _, ent in ipairs(ents.FindByClass("npc_*")) do
            local chain = IsValid(ent) and ent.VNPC_VirtualBellyBones or nil
            if not chain then continue end
            local cols = {
                VNPC_Belly_Root = Color(255, 255, 80),
                VNPC_Belly_Mid = Color(255, 120, 220),
                VNPC_Belly_Upper = Color(120, 200, 255),
                VNPC_Belly_Lower = Color(255, 160, 80),
                VNPC_Belly_L = Color(80, 255, 160),
                VNPC_Belly_R = Color(80, 255, 160),
                VNPC_Gulp_Neck = Color(255, 200, 70),
                VNPC_Gulp_Chest = Color(255, 160, 50)
            }
            for name, bone in pairs(chain.byName or {}) do
                local col = cols[name] or Color(255, 255, 255)
                render.DrawWireframeSphere(bone.pos, bone.radius or 4, 10, 10, Color(col.r, col.g, col.b, 180), true)
                render.DrawSphere(bone.pos, 1.6, 8, 8, col)
            end
            if chain.root and chain.mid then
                render.DrawLine(chain.root.pos, chain.mid.pos, Color(255, 200, 255), true)
                render.DrawLine(chain.mid.pos, chain.upper.pos, Color(180, 220, 255), true)
                render.DrawLine(chain.mid.pos, chain.lower.pos, Color(255, 180, 120), true)
                render.DrawLine(chain.left.pos, chain.right.pos, Color(120, 255, 180), true)
            end
            local spots = VNPC_GetGPUBellyStruggleSpots(ent, chain)
            for _, spot in ipairs(spots) do
                if spot.world then
                    local r = math.max(2.2, (spot.radius or 0.28) * (chain.radius or 8) * (0.45 + (spot.amp or 0)))
                    render.DrawWireframeSphere(spot.world, r, 8, 8, Color(255, 80, 140, 200), true)
                    render.DrawSphere(spot.world, 1.4 + (spot.amp or 0) * 3, 7, 7, Color(255, 60, 120, 220))
                end
            end
            if chain.gulpNeck and chain.gulpChest then
                render.DrawLine(chain.gulpNeck.pos, chain.gulpChest.pos, Color(255, 200, 80), true)
                if chain.upper then
                    render.DrawLine(chain.gulpChest.pos, chain.upper.pos, Color(255, 170, 60), true)
                end
            end
            local gulps = VNPC_GetGPUBellyGulpSpots(ent, chain)
            for _, spot in ipairs(gulps) do
                if spot.world then
                    render.DrawWireframeSphere(spot.world, spot.radius or 6, 9, 9, Color(255, 190, 70, 210), true)
                    render.DrawSphere(spot.world, 1.8 + (spot.preyScale or 1) * 1.4, 7, 7, Color(255, 160, 40, 230))
                end
            end
        end
    end)
end

if SERVER then
    hook.Add("Think", "VNPC_GPUBelly_SyncStruggle", function()
        local now = CurTime()
        if (VNPC_NextGPUStruggleSync or 0) > now then return end
        VNPC_NextGPUStruggleSync = now + 0.2
        local enabled = GetConVar("vnpcs_gpu_belly_struggle")
        if enabled and not enabled:GetBool() then return end
        for _, ent in ipairs(ents.FindByClass("npc_*")) do
            if isPredCandidate(ent) then
                VNPC_SyncGPUBellyStruggle(ent)
                if VNPC_SyncGPUBellyGulp then VNPC_SyncGPUBellyGulp(ent) end
            end
        end
    end)
    hook.Add("Think", "VNPC_GPUBelly_SyncGulp", function()
        local now = CurTime()
        if (VNPC_NextGPUGulpSync or 0) > now then return end
        VNPC_NextGPUGulpSync = now + 0.1
        local enabled = GetConVar("vnpcs_gpu_belly_gulp")
        if enabled and not enabled:GetBool() then return end
        for _, ent in ipairs(ents.FindByClass("npc_*")) do
            if isPredCandidate(ent) then
                VNPC_SyncGPUBellyGulp(ent)
            end
        end
    end)
end

-- Prefer generated belly-mid as the hold / measure center on models with no belly bones.
hook.Add("InitPostEntity", "VNPC_GPUBelly_HookMeasure", function()
    if not VNPC_GetBellyWorldMeasure or VNPC_GetBellyWorldMeasure_GPUWrapped then return end
    VNPC_GetBellyWorldMeasure_GPUWrapped = true
    local prev = VNPC_GetBellyWorldMeasure
    function VNPC_GetBellyWorldMeasure(ent)
        local info = prev(ent)
        if not info or not IsValid(ent) then return info end
        local chain = VNPC_UpdateVirtualBellyBones and VNPC_UpdateVirtualBellyBones(ent)
        if chain and chain.mid and chain.mid.pos then
            info.center = chain.mid.pos
            info.radius = math.max(info.radius or 0, chain.radius or 0)
            info.width = math.max(info.width or 0, chain.width or 0)
            info.height = math.max(info.height or 0, chain.height or 0)
            info.surface = info.radius + (info.handPad or 2)
            info.generatedBones = true
            ent.VNPC_BellyWorldMeasure = info
        end
        return info
    end
end)

if VNPC_GetBellyWorldMeasure and not VNPC_GetBellyWorldMeasure_GPUWrapped then
    VNPC_GetBellyWorldMeasure_GPUWrapped = true
    local prev = VNPC_GetBellyWorldMeasure
    function VNPC_GetBellyWorldMeasure(ent)
        local info = prev(ent)
        if not info or not IsValid(ent) then return info end
        local chain = VNPC_UpdateVirtualBellyBones and VNPC_UpdateVirtualBellyBones(ent)
        if chain and chain.mid and chain.mid.pos then
            info.center = chain.mid.pos
            info.radius = math.max(info.radius or 0, chain.radius or 0)
            info.width = math.max(info.width or 0, chain.width or 0)
            info.height = math.max(info.height or 0, chain.height or 0)
            info.surface = info.radius + (info.handPad or 2)
            info.generatedBones = true
            ent.VNPC_BellyWorldMeasure = info
        end
        return info
    end
end

concommand.Add("vnpcs_gpu_belly_status", function(ply)
    print("===============================================================")
    print("     V-NPCs GPU BELLY BONE GENERATOR STATUS                    ")
    print("===============================================================")
    print(" - Enabled: " .. tostring(GetConVar("vnpcs_gpu_belly_enabled"):GetBool()))
    print(" - GPU Mesh: " .. tostring(GetConVar("vnpcs_gpu_belly_mesh"):GetBool()))
    print(" - Bone Scale: " .. tostring(GetConVar("vnpcs_gpu_belly_bonescale"):GetBool()))
    print(" - Debug: " .. tostring(GetConVar("vnpcs_gpu_belly_debug"):GetBool()))
    print(" - Struggle Deform: " .. tostring(GetConVar("vnpcs_gpu_belly_struggle"):GetBool()) .. " amp=" .. tostring(GetConVar("vnpcs_gpu_belly_struggle_amp"):GetFloat()))
    print(" - Gulp Neck Deform: " .. tostring(GetConVar("vnpcs_gpu_belly_gulp"):GetBool()) .. " amp=" .. tostring(GetConVar("vnpcs_gpu_belly_gulp_amp"):GetFloat()))
    print(" - Torso Hull: " .. tostring(GetConVar("vnpcs_gpu_belly_torso_hull"):GetBool()))
    print(" - Jiggle: " .. tostring(GetConVar("vnpcs_gpu_belly_jiggle"):GetBool()) .. " amp=" .. tostring(GetConVar("vnpcs_gpu_belly_jiggle_amp"):GetFloat()))
    print(" - Preg/Prey Shape: " .. tostring(GetConVar("vnpcs_gpu_belly_preg_shape"):GetBool()))
    print(" - Hide Belly Entity: " .. tostring(GetConVar("vnpcs_gpu_belly_hide_entity"):GetBool()))
    print("-----------------------------------------")
    local count = 0
    for _, ent in ipairs(ents.FindByClass("npc_*")) do
        if isPredCandidate(ent) then
            local chain = VNPC_UpdateVirtualBellyBones(ent)
            if chain then
                count = count + 1
                local preyN = (ent.GetNWInt and ent:GetNWInt("VNPC_GPUStruggleN", 0)) or 0
                local gulpN = (ent.GetNWInt and ent:GetNWInt("VNPC_GPUGulpN", 0)) or 0
                print(string.format(" -> #%d [%s] size=%.3f radius=%.1f W/H %.1f/%.1f modelBellyBones=%s strugglePrey=%d spots=%d gulp=%d",
                    ent:EntIndex(), ent.PrintName or ent:GetClass(), chain.size, chain.radius,
                    chain.width, chain.height, tostring(chain.hasModelBellyBones), preyN, preyN * 4, gulpN))
            end
        end
    end
    print("Generated belly skeletons: " .. count)
    print("===============================================================")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] GPU belly bone status printed to console. Generated: " .. count)
    end
end)

concommand.Add("vnpcs_test_gpu_belly", function(ply)
    if not IsValid(ply) then return end
    local target = ply:GetEyeTrace().Entity
    if not IsValid(target) or not (target:IsNPC() or target:IsNextBot() or target.IsDrGNextbot) then
        ply:ChatPrint("[V-NPCs] Aim at a pred or NPC to generate GPU belly bones!")
        return
    end
    local chain = VNPC_UpdateVirtualBellyBones(target)
    if not chain then
        ply:ChatPrint("[V-NPCs] Failed to generate belly bones on " .. tostring(target))
        return
    end
    if target.SetFacialExpression then
        target:SetFacialExpression(2)
    elseif target.SetNWInt then
        target:SetNWInt("FacialPhase", 2)
    end
    ply:ChatPrint(string.format("[V-NPCs] Generated 6 GPU belly bones on %s (size=%.3f radius=%.1f, model had belly bones: %s)",
        tostring(target), chain.size, chain.radius, tostring(chain.hasModelBellyBones)))
    print(string.format("[V-NPCs] GPU belly bones for #%d:", target:EntIndex()))
    for _, name in ipairs(VNPC_GPU_BELLY_BONE_NAMES) do
        local b = chain.byName[name]
        if b then
            print(string.format("   %-18s  (%.1f, %.1f, %.1f)  r=%.1f", name, b.pos.x, b.pos.y, b.pos.z, b.radius))
        end
    end
end)

concommand.Add("vnpcs_test_gpu_struggle", function(ply)
    if not IsValid(ply) then return end
    local target = ply:GetEyeTrace().Entity
    if not IsValid(target) or not (target:IsNPC() or target:IsNextBot() or target.IsDrGNextbot) then
        ply:ChatPrint("[V-NPCs] Aim at a predator to test 4-spot GPU belly struggle deformations!")
        return
    end
    target.VNPC_GPUStruggleTest = {
        { id = target:EntIndex() * 13 + 1, mul = 1.35 },
        { id = target:EntIndex() * 17 + 2, mul = 1.10 }
    }
    if VNPC_SyncGPUBellyStruggle then
        VNPC_SyncGPUBellyStruggle(target)
    end
    if target.SetFacialExpression then
        target:SetFacialExpression(2)
    elseif target.SetNWInt then
        target:SetNWInt("FacialPhase", 2)
    end
    local spots = VNPC_GetGPUBellyStruggleSpots and VNPC_GetGPUBellyStruggleSpots(target, target.VNPC_VirtualBellyBones) or {}
    ply:ChatPrint(string.format("[V-NPCs] Forced 2 prey / %d unique GPU struggle lumps on %s. Enable vnpcs_gpu_belly_debug 1 to see them.", #spots, tostring(target)))
end)

concommand.Add("vnpcs_test_gpu_gulp", function(ply, _, args)
    if not IsValid(ply) then return end
    local target = ply:GetEyeTrace().Entity
    local scaleArg = tonumber(args and args[1])
    if IsValid(target) and (target:IsNPC() or target:IsNextBot() or target.IsDrGNextbot) then
        local looksLikePrey = target.Vored or target.VNPC_Vored or (not target.Predator and not target.VNPC_FemaleModelVore and not target.VNPC_Belly and not target.Belly)
        if looksLikePrey then
            scaleArg = scaleArg or VNPC_GetPreyGulpScale(target)
            local pred, best = nil, 1400 * 1400
            for _, ent in ipairs(ents.FindByClass("npc_*")) do
                if IsValid(ent) and ent ~= target and (ent.Predator or ent.VNPC_FemaleModelVore or ent.VNPC_Belly or ent.Belly or ent.IsDrGNextbot) then
                    local d = ent:GetPos():DistToSqr(target:GetPos())
                    if d < best then
                        pred = ent
                        best = d
                    end
                end
            end
            if IsValid(pred) then target = pred end
        end
    end
    if not IsValid(target) or not (target:IsNPC() or target:IsNextBot() or target.IsDrGNextbot) then
        ply:ChatPrint("[V-NPCs] Aim at a predator (or nearby prey) to test GPU neck/upper-torso gulp bulges!")
        return
    end
    if scaleArg then
        target.VNPC_GPUGulpTest = {
            { id = target:EntIndex() * 11 + 1, scale = math.Clamp(scaleArg, 0.28, 2.8), animate = true }
        }
    else
        target.VNPC_GPUGulpTest = {
            { id = target:EntIndex() * 11 + 1, scale = 0.55, animate = true },
            { id = target:EntIndex() * 13 + 2, scale = 1.45, animate = true }
        }
    end
    if VNPC_SyncGPUBellyGulp then
        VNPC_SyncGPUBellyGulp(target)
    end
    if target.SetFacialExpression then
        target:SetFacialExpression(1)
    elseif target.SetNWInt then
        target:SetNWInt("FacialPhase", 1)
    end
    local spots = VNPC_GetGPUBellyGulpSpots and VNPC_GetGPUBellyGulpSpots(target, target.VNPC_VirtualBellyBones) or {}
    ply:ChatPrint(string.format("[V-NPCs] Forced %d GPU gulp bulge(s) on %s (prey scale driven). Enable vnpcs_gpu_belly_debug 1 to see the neck path.", math.max(#spots, #target.VNPC_GPUGulpTest), tostring(target)))
end)
