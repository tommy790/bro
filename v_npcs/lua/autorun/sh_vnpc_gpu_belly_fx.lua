-- V-NPCs GPU belly FX (sh_vnpc_gpu_belly_fx.lua)
-- Loads after sh_vnpc_gpu_belly.lua.
-- 1) collar-to-pelvis torso hull  2) peristalsis gulp wave
-- 3) prey silhouette spots        4) spring-damper jiggle
-- 5) pregnancy vs swallowed shape 6) hide ent_vore_belly
-- 7) character bone-scale + material uniforms (engine VCS still optional)

local GPU_STRUGGLE_MAX_PREY = 4
local GPU_GULP_MAX = 4

local SILHOUETTE_BASES = {
    { kind = "head",      pos = Vector(0.00, 0.60,  0.50), radius = 0.22, freq = 5.4, amp = 0.28 },
    { kind = "shoulders", pos = Vector(0.00, 0.74,  0.10), radius = 0.40, freq = 3.4, amp = 0.34 },
    { kind = "hips",      pos = Vector(0.00, 0.58, -0.30), radius = 0.36, freq = 4.1, amp = 0.30 },
    { kind = "feet",      pos = Vector(0.00, 0.40, -0.58), radius = 0.24, freq = 6.0, amp = 0.24 }
}

local WAVE_LINKS = {
    { kind = "ghead",      off = -0.11, rad = 0.82, amp = 1.00 },
    { kind = "gshoulders", off = -0.02, rad = 1.18, amp = 1.22 },
    { kind = "gtorso",     off =  0.09, rad = 1.05, amp = 0.92 },
    { kind = "ghips",      off =  0.20, rad = 0.78, amp = 0.68 }
}

local EXTRA_SCALE = {
    { names = { "ValveBiped.Bip01_Neck1", "Neck1", "Neck", "neck" }, mul = Vector(0.18, 0.22, 0.10) },
    { names = { "ValveBiped.Bip01_Spine2", "Spine2", "spine2" }, mul = Vector(0.20, 0.42, 0.16) },
    { names = { "ValveBiped.Bip01_L_Clavicle", "L_Clavicle", "l_clavicle" }, mul = Vector(0.08, 0.12, 0.06) },
    { names = { "ValveBiped.Bip01_R_Clavicle", "R_Clavicle", "r_clavicle" }, mul = Vector(0.08, 0.12, 0.06) }
}

local function lookup(ent, names)
    if not IsValid(ent) or not ent.LookupBone then return nil end
    for _, name in ipairs(names) do
        local id = ent:LookupBone(name)
        if id and id >= 0 then return id end
    end
    return nil
end

local function gpuHash01(a, b)
    local n = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
    return n - math.floor(n)
end

local function gpuClampLocal(v)
    v.x = math.Clamp(v.x, -0.88, 0.88)
    v.y = math.Clamp(v.y, 0.10, 0.96)
    v.z = math.Clamp(v.z, -0.82, 0.74)
    return v
end

local function gulpVis(prog)
    if prog < 0.28 then return 0 end
    if prog < 0.40 then return (prog - 0.28) / 0.12 end
    if prog < 0.82 then return 1 end
    return math.max(0, 1 - (prog - 0.82) / 0.18)
end

local function pathPoint(chain, t)
    t = math.Clamp(t, 0, 1)
    local path = chain.spinePath
    if not istable(path) or #path < 2 then
        local a = chain.gulpNeck and chain.gulpNeck.pos or (chain.upper and chain.upper.pos)
        local b = chain.mid and chain.mid.pos or a
        if not a then return nil end
        return LerpVector(t, a, b)
    end
    local segs = #path - 1
    local f = t * segs
    local i = math.floor(f) + 1
    if i >= #path then return path[#path] end
    return LerpVector(f - (i - 1), path[i], path[i + 1])
end

-- 5) Pregnancy (high/round) vs swallowed prey (low/heavy).
if not VNPC_UpdateVirtualBellyBones_FXWrapped and VNPC_UpdateVirtualBellyBones then
    VNPC_UpdateVirtualBellyBones_FXWrapped = true
    local prev = VNPC_UpdateVirtualBellyBones
    function VNPC_UpdateVirtualBellyBones(ent)
        local chain = prev(ent)
        if not chain or not IsValid(ent) then return chain end

        local pregR = 0
        if VNPC_GetPregnancyBellyRadius then
            pregR = VNPC_GetPregnancyBellyRadius(ent) or 0
        end
        local preySize = 0
        if VNPC_GetLiveBellySize then
            preySize = VNPC_GetLiveBellySize(ent) or 0
        end
        local preg = math.Clamp(pregR / 18, 0, 1.4)
        local prey = math.Clamp(preySize, 0, 2.2)
        local tot = preg + prey
        local pregF, preyF = 0, 1
        local shapeOn = GetConVar("vnpcs_gpu_belly_preg_shape")
        if (not shapeOn or shapeOn:GetBool()) and tot > 0.01 then
            pregF = preg / tot
            preyF = prey / tot
        elseif tot <= 0.01 then
            pregF, preyF = 0, 0
        end

        local up = chain.up or Vector(0, 0, 1)
        local fwd = chain.forward or Vector(1, 0, 0)
        local r = chain.radius or 8
        if chain.mid and chain.mid.pos then
            chain.mid.pos = chain.mid.pos + up * (pregF * r * 0.20) - up * (preyF * r * 0.14) + fwd * (preyF * r * 0.06)
        end
        if chain.upper and chain.upper.pos then
            chain.upper.pos = chain.upper.pos + up * (pregF * r * 0.24) + fwd * (pregF * r * 0.04)
        end
        if chain.lower and chain.lower.pos then
            chain.lower.pos = chain.lower.pos - up * (preyF * r * 0.22) + fwd * (preyF * r * 0.10)
        end
        chain.pregFactor = pregF
        chain.preyFactor = preyF
        chain.pregSize = preg
        chain.preySize = prey
        chain.spinePath = {
            chain.gulpNeck and chain.gulpNeck.pos,
            chain.gulpChest and chain.gulpChest.pos,
            chain.upper and chain.upper.pos,
            chain.mid and chain.mid.pos,
            chain.lower and chain.lower.pos
        }
        local cleaned = {}
        for _, p in ipairs(chain.spinePath) do
            if p then table.insert(cleaned, p) end
        end
        chain.spinePath = cleaned
        if VNPC_MeasureBodyParts then
            local parts = VNPC_MeasureBodyParts(ent)
            if parts and parts.torso then
                chain.torsoWidth = parts.torso.width or 14
                chain.bodyHeight = parts.bodyHeight or 72
            end
        end
        ent.VNPC_VirtualBellyBones = chain
        return chain
    end
end

-- 3) Prey silhouette: head / shoulders / hips / feet sized from measured parts.
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
        local headN = (ent.GetNWFloat and ent:GetNWFloat("VNPC_GPUSilHead" .. p, 1)) or 1
        local torsoN = (ent.GetNWFloat and ent:GetNWFloat("VNPC_GPUSilTorso" .. p, 1)) or 1
        local hipN = (ent.GetNWFloat and ent:GetNWFloat("VNPC_GPUSilHip" .. p, 1)) or 1
        if ent.VNPC_GPUStruggleTest and ent.VNPC_GPUStruggleTest[p] then
            headN = tonumber(ent.VNPC_GPUStruggleTest[p].head) or headN
            torsoN = tonumber(ent.VNPC_GPUStruggleTest[p].torso) or torsoN
            hipN = tonumber(ent.VNPC_GPUStruggleTest[p].hip) or hipN
        end
        local side = (p % 2 == 0) and -1 or 1
        local slot = (p - 1) * 0.22
        local partScale = { headN, torsoN, hipN, (headN + hipN) * 0.5 }
        for s = 1, 4 do
            local base = SILHOUETTE_BASES[s]
            local jx = (gpuHash01(preyId, s * 3.1) - 0.5) * 0.16
            local jy = (gpuHash01(preyId, s * 7.7) - 0.5) * 0.10
            local jz = (gpuHash01(preyId, s * 11.3) - 0.5) * 0.12
            local spread = 0
            if s == 2 then
                spread = 0.34 * math.Clamp(torsoN, 0.5, 2.2) * side
            elseif s == 3 then
                spread = 0.28 * math.Clamp(hipN, 0.5, 2.2) * side
            elseif s == 4 then
                spread = (0.16 + slot * 0.2) * side
            else
                spread = 0.08 * side + slot * 0.12
            end
            local lp = gpuClampLocal(Vector(
                base.pos.x + spread + jx,
                base.pos.y + jy,
                base.pos.z * (0.85 + 0.2 * math.Clamp(partScale[s], 0.5, 1.8)) + jz
            ))
            local phase = preyId * 0.73 + s * 1.31 + p * 0.41
            local kick = math.max(0, math.sin(now * base.freq + phase))
            kick = kick * kick
            local pulse = 0.32 + 0.68 * kick
            local amp = mul * ampMul * pulse * base.amp * (0.75 + 0.35 * math.Clamp(partScale[s], 0.4, 2.0))
            local rad = base.radius * (0.80 + 0.35 * math.Clamp(partScale[s], 0.4, 2.2))
            local world = nil
            if chain and chain.mid then
                local rdir = chain.rightDir
                if not rdir or not isvector(rdir) then
                    rdir = (chain.up or Vector(0, 0, 1)):Cross(chain.forward or Vector(1, 0, 0))
                end
                world = chain.mid.pos
                    + rdir * (lp.x * chain.width * 0.5)
                    + chain.forward * (lp.y * chain.depth * 0.5)
                    + chain.up * (lp.z * chain.height * 0.5)
            end
            table.insert(spots, {
                kind = base.kind,
                preyId = preyId,
                lp = lp,
                radius = rad,
                amp = amp,
                world = world
            })
        end
    end
    ent.VNPC_GPUStruggleSpots = spots
    return spots
end

-- 2) Peristalsis: 4 overlapping wave links along the swallow path.
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
        local spacing = 0.07 + scale * 0.06
        for w = 1, #WAVE_LINKS do
            local link = WAVE_LINKS[w]
            local lp = math.Clamp(prog + link.off * (spacing / 0.12), 0, 1)
            local vis = gulpVis(lp)
            if vis <= 0.02 then continue end
            local world = pathPoint(chain, math.Clamp((lp - 0.28) / 0.70, 0, 1))
            if not world then continue end
            local wriggle = 1 + 0.06 * math.sin(now * 10.2 + p * 2.1 + w)
            local radius = (3.4 + scale * 4.8) * link.rad * wriggle
            local amp = vis * ampMul * link.amp * (0.38 + scale * 0.34)
            table.insert(spots, {
                kind = link.kind,
                preyScale = scale,
                prog = lp,
                vis = vis,
                world = world,
                radius = radius,
                length = 6.0 + scale * 7.5,
                amp = amp
            })
        end
    end
    ent.VNPC_GPUGulpSpots = spots
    return spots
end

-- 4) Spring-damper jiggle from movement and struggle kicks.
function VNPC_UpdateGPUBellyJiggle(ent, spots)
    if not IsValid(ent) then return Vector(0, 0, 0) end
    local cv = GetConVar("vnpcs_gpu_belly_jiggle")
    if cv and not cv:GetBool() then
        ent.VNPC_GPUJiggle = nil
        return Vector(0, 0, 0)
    end
    local ampMul = 1.0
    local ampCv = GetConVar("vnpcs_gpu_belly_jiggle_amp")
    if ampCv then ampMul = ampCv:GetFloat() or 1.0 end
    if ampMul <= 0 then return Vector(0, 0, 0) end

    local st = ent.VNPC_GPUJiggle
    if not st then
        st = { x = 0, y = 0, z = 0, vx = 0, vy = 0, vz = 0, lastKick = 0, lastPos = ent:GetPos() }
        ent.VNPC_GPUJiggle = st
    end
    local dt = math.Clamp(FrameTime(), 0.001, 0.05)
    local pos = ent:GetPos()
    local move = (pos - (st.lastPos or pos)) / dt
    st.lastPos = pos
    -- inertia: belly lags behind the body
    st.vx = st.vx - move.x * 0.010 * ampMul
    st.vy = st.vy - move.y * 0.010 * ampMul
    st.vz = st.vz - move.z * 0.006 * ampMul

    local kick = 0
    if istable(spots) then
        for i = 1, #spots do
            kick = kick + (spots[i].amp or 0)
        end
    end
    local dk = kick - (st.lastKick or 0)
    if dk > 0.035 then
        st.vy = st.vy + dk * 9 * ampMul
        st.vz = st.vz + dk * 3.5 * ampMul
        st.vx = st.vx + (dk * 2.2 * ampMul) * (((ent:EntIndex() % 2 == 0) and 1) or -1)
    end
    st.lastKick = kick

    local k, damp = 46, 9.5
    st.vx = st.vx + (-k * st.x - damp * st.vx) * dt
    st.vy = st.vy + (-k * st.y - damp * st.vy) * dt
    st.vz = st.vz + (-k * 1.15 * st.z - damp * st.vz) * dt
    st.x = math.Clamp(st.x + st.vx * dt, -7, 7)
    st.y = math.Clamp(st.y + st.vy * dt, -7, 7)
    st.z = math.Clamp(st.z + st.vz * dt, -5, 5)
    ent.VNPC_GPUJiggleVec = Vector(st.x, st.y, st.z)
    return ent.VNPC_GPUJiggleVec
end

-- 7) Character mesh deform: fixed bone-scale lookup + gulp-driven neck/chest/clavicle.
if not VNPC_ApplyGeneratedBellyBoneScale_FXWrapped then
VNPC_ApplyGeneratedBellyBoneScale_FXWrapped = true
local prevBoneScale = VNPC_ApplyGeneratedBellyBoneScale
function VNPC_ApplyGeneratedBellyBoneScale(ent, chain)
    if prevBoneScale then
        prevBoneScale(ent, chain)
    end
    if not IsValid(ent) or not ent.ManipulateBoneScale then return end
    local cv = GetConVar("vnpcs_gpu_belly_bonescale")
    if cv and not cv:GetBool() then return end
    chain = chain or ent.VNPC_VirtualBellyBones
    if not chain then return end

    local gulpAmp = 0
    local n = (ent.GetNWInt and ent:GetNWInt("VNPC_GPUGulpN", 0)) or 0
    for i = 1, math.min(n, GPU_GULP_MAX) do
        local prog = (ent.GetNWFloat and ent:GetNWFloat("VNPC_GPUGulpProg" .. i, 0)) or 0
        local sc = (ent.GetNWFloat and ent:GetNWFloat("VNPC_GPUGulpScale" .. i, 1)) or 1
        gulpAmp = math.max(gulpAmp, gulpVis(prog) * sc)
    end
    if ent.VNPC_GPUGulpTest then
        gulpAmp = math.max(gulpAmp, 0.85)
    end
    local pregF = chain.pregFactor or 0
    local extra = math.Clamp((chain.size or 0) * 0.35 + pregF * 0.15 + gulpAmp * 0.55, 0, 1.4)
    for _, spec in ipairs(EXTRA_SCALE) do
        local id = lookup(ent, spec.names)
        if id then
            local w = spec.mul
            if extra < 0.03 then
                ent:ManipulateBoneScale(id, Vector(1, 1, 1))
            else
                ent:ManipulateBoneScale(id, Vector(1 + extra * w.x, 1 + extra * w.y, 1 + extra * w.z))
            end
        end
    end
end
end

if CLIENT then
    local HULL_RINGS, HULL_SEGS = 8, 12
    local HULL_VERTS, HULL_TRIS
    local SPHERE_VERTS, SPHERE_TRIS

    local function buildHullUnit()
        HULL_VERTS = {}
        HULL_TRIS = {}
        for i = 0, HULL_RINGS - 1 do
            local t = i / (HULL_RINGS - 1)
            for j = 0, HULL_SEGS - 1 do
                local th = (j / HULL_SEGS) * math.pi * 2
                table.insert(HULL_VERTS, {
                    t = t,
                    cx = math.cos(th),
                    cy = math.sin(th),
                    u = j / HULL_SEGS,
                    v = t
                })
            end
        end
        local function idx(i, j)
            return i * HULL_SEGS + (j % HULL_SEGS) + 1
        end
        for i = 0, HULL_RINGS - 2 do
            for j = 0, HULL_SEGS - 1 do
                local a, b, c, d = idx(i, j), idx(i, j + 1), idx(i + 1, j), idx(i + 1, j + 1)
                table.insert(HULL_TRIS, { a, b, c })
                table.insert(HULL_TRIS, { b, d, c })
            end
        end
    end

    local function buildSphereUnit()
        SPHERE_VERTS, SPHERE_TRIS = {}, {}
        local LAT, LON = 8, 10
        for i = 0, LAT do
            local phi = (i / LAT) * math.pi
            local sp, cp = math.sin(phi), math.cos(phi)
            for j = 0, LON - 1 do
                local th = (j / LON) * math.pi * 2
                local x, y, z = sp * math.cos(th), sp * math.sin(th), cp
                table.insert(SPHERE_VERTS, {
                    pos = Vector(x, y, z),
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
                table.insert(SPHERE_TRIS, { a, b, c })
                table.insert(SPHERE_TRIS, { b, d, c })
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

    local function bindGore(mat, chain, spots, gulps, jiggle)
        if not mat or not chain or not chain.mid then return end
        mat:SetVector("$gore_center", chain.mid.pos)
        mat:SetFloat("$gore_radius", chain.radius or 8)
        mat:SetFloat("$gore_intensity", math.Clamp((chain.size or 0) * 14, 0, 80))
        mat:SetFloat("$gore_preg", chain.pregFactor or 0)
        mat:SetFloat("$gore_prey", chain.preyFactor or 0)
        if jiggle then
            mat:SetVector("$gore_jiggle", jiggle)
        end
        for i = 1, 4 do
            local spot = spots and spots[i]
            if spot and spot.world then
                mat:SetVector("$gore_spot" .. i, spot.world)
                mat:SetFloat("$gore_spotamp" .. i, spot.amp or 0)
                mat:SetFloat("$gore_spotradius" .. i, (spot.radius or 0.28) * (chain.radius or 8))
            else
                mat:SetVector("$gore_spot" .. i, chain.mid.pos)
                mat:SetFloat("$gore_spotamp" .. i, 0)
                mat:SetFloat("$gore_spotradius" .. i, 0)
            end
        end
        for i = 1, 4 do
            local g = gulps and gulps[i]
            if g and g.world then
                mat:SetVector("$gore_gulp" .. i, g.world)
                mat:SetFloat("$gore_gulpamp" .. i, g.amp or 0)
                mat:SetFloat("$gore_gulpradius" .. i, g.radius or 0)
            elseif chain.mid then
                mat:SetVector("$gore_gulp" .. i, chain.mid.pos)
                mat:SetFloat("$gore_gulpamp" .. i, 0)
                mat:SetFloat("$gore_gulpradius" .. i, 0)
            end
        end
    end

    local function hullOut(t, chain)
        local torsoW = chain.torsoWidth or 14
        local size = chain.size or 0
        local pregF = chain.pregFactor or 0
        local preyF = chain.preyFactor or 0
        local wrap = 3.0 + torsoW * 0.11
        local pregBump = pregF * math.max(size, 0.12) * 16 * math.exp(-((t - 0.36) * (t - 0.36)) / 0.055)
        local preyBump = preyF * math.max(size, 0.12) * 17 * math.exp(-((t - 0.68) * (t - 0.68)) / 0.065)
        if pregF == 0 and preyF == 0 then
            preyBump = math.max(size, 0.08) * 16 * math.exp(-((t - 0.62) * (t - 0.62)) / 0.07)
        end
        return wrap + pregBump + preyBump
    end

    local function hullWidth(t, chain)
        local torsoW = chain.torsoWidth or 14
        local size = chain.size or 0
        local neckW = torsoW * 0.36
        local chestW = torsoW * 0.56
        local bellyW = torsoW * 0.50 + size * 14
        local hipW = torsoW * 0.44
        if t < 0.22 then
            return Lerp(t / 0.22, neckW, chestW)
        elseif t < 0.55 then
            return Lerp((t - 0.22) / 0.33, chestW, bellyW)
        end
        return Lerp((t - 0.55) / 0.45, bellyW, hipW)
    end

    -- 1) Collar-to-pelvis hull skinned along the spine, front-weighted so it wraps the torso.
    function VNPC_DrawGPUBellyFX(ent, chain)
        if not IsValid(ent) or not chain then return end
        local hullOn = GetConVar("vnpcs_gpu_belly_torso_hull")
        if hullOn and not hullOn:GetBool() then
            return false
        end
        local hasGulp = ((ent.GetNWInt and ent:GetNWInt("VNPC_GPUGulpN", 0)) or 0) > 0 or ent.VNPC_GPUGulpTest
        if (chain.size or 0) < 0.02 and not hasGulp and (chain.pregSize or 0) < 0.04 then
            return
        end
        if not HULL_VERTS then buildHullUnit() end

        local eye = EyePos()
        local distSqr = eye:DistToSqr(ent:GetPos())
        if distSqr > (3200 * 3200) then return end

        local fwd = chain.forward or Vector(1, 0, 0)
        local up = chain.up or Vector(0, 0, 1)
        local right = chain.rightDir
        if not right or not isvector(right) then
            right = up:Cross(fwd)
            if right:LengthSqr() < 0.01 then right = Vector(0, 1, 0) else right:Normalize() end
        end

        local spots = VNPC_GetGPUBellyStruggleSpots(ent, chain)
        local gulps = VNPC_GetGPUBellyGulpSpots(ent, chain)
        local jiggle = VNPC_UpdateGPUBellyJiggle(ent, spots)
        local mat = bellyMaterial(ent)
        bindGore(mat, chain, spots, gulps, jiggle)
        render.SetMaterial(mat)

        local path = chain.spinePath
        if not istable(path) or #path < 2 then
            path = { chain.gulpNeck and chain.gulpNeck.pos, chain.mid and chain.mid.pos }
        end

        mesh.Begin(MATERIAL_TRIANGLES, #HULL_TRIS)
        for t = 1, #HULL_TRIS do
            local tri = HULL_TRIS[t]
            for k = 1, 3 do
                local v = HULL_VERTS[tri[k]]
                local center = pathPoint(chain, v.t) or (chain.mid and chain.mid.pos) or ent:WorldSpaceCenter()
                local front = math.max(0, v.cy)
                local out = hullOut(v.t, chain)
                local wid = hullWidth(v.t, chain) * 0.5
                local depthBack = 2.0 + out * 0.12
                local depthFront = 2.4 + out
                local depth = (v.cy >= 0) and (depthBack + (depthFront - depthBack) * front) or (depthBack * 0.85)
                local world = center
                    + right * (v.cx * wid)
                    + fwd * (v.cy * depth * ((v.cy >= 0) and 1 or 0.28) + 1.1)
                    + (jiggle or vector_origin)
                local lp = Vector(v.cx, math.max(0.05, front), (0.5 - v.t) * 1.6)
                local nrm = (right * v.cx + fwd * math.max(0.15, v.cy) + up * (0.35 - v.t))
                if nrm:LengthSqr() < 0.001 then nrm = fwd else nrm:Normalize() end
                local push = VNPC_ApplyGPUBellyStruggleDeform and VNPC_ApplyGPUBellyStruggleDeform(lp, spots) or 0
                if push > 0 then
                    world = world + nrm * (push * (chain.radius or 8))
                end
                local gpush = VNPC_ApplyGPUBellyGulpDeform and VNPC_ApplyGPUBellyGulpDeform(world, gulps)
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
        return true
    end

    -- Separate gulp orbs only when the hull is off (hull already carries the wave).
    function VNPC_DrawGPUGulpFX(ent, chain)
        local hullOn = GetConVar("vnpcs_gpu_belly_torso_hull")
        if not hullOn or hullOn:GetBool() then return end
        local spots = VNPC_GetGPUBellyGulpSpots(ent, chain)
        if not spots or #spots == 0 then return end
        if not SPHERE_VERTS then buildSphereUnit() end
        local mat = bellyMaterial(ent)
        render.SetMaterial(mat)
        local fwd = (chain and chain.forward) or Vector(1, 0, 0)
        local up = (chain and chain.up) or Vector(0, 0, 1)
        local right = (chain and chain.rightDir) or up:Cross(fwd)
        if not isvector(right) or right:LengthSqr() < 0.01 then right = Vector(0, 1, 0) else right:Normalize() end
        for _, spot in ipairs(spots) do
            if not spot.world then continue end
            local rx = spot.radius * 0.62
            local ry = spot.radius * 0.88
            local rz = (spot.length or (spot.radius * 1.3)) * 0.38
            mesh.Begin(MATERIAL_TRIANGLES, #SPHERE_TRIS)
            for t = 1, #SPHERE_TRIS do
                local tri = SPHERE_TRIS[t]
                for k = 1, 3 do
                    local v = SPHERE_VERTS[tri[k]]
                    local lp = v.pos
                    local world = spot.world
                        + right * (lp.x * rx)
                        + fwd * (lp.y * ry * 0.85 + 0.16 * ry)
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

    -- 6) Hide the belly entity visual when the GPU mesh is the live one.
    hook.Add("Think", "VNPC_GPUBelly_HideEntity", function()
        local now = CurTime()
        if (VNPC_NextGPUHideThink or 0) > now then return end
        VNPC_NextGPUHideThink = now + 0.25
        local hideCv = GetConVar("vnpcs_gpu_belly_hide_entity")
        local gpuCv = GetConVar("vnpcs_gpu_belly_enabled")
        local meshCv = GetConVar("vnpcs_gpu_belly_mesh")
        local hide = hideCv and hideCv:GetBool()
        local gpu = (not gpuCv) or gpuCv:GetBool()
        local meshOn = (not meshCv) or meshCv:GetBool()
        for _, ent in ipairs(ents.FindByClass("npc_*")) do
            if not IsValid(ent) then continue end
            if ent.Vored or ent.VNPC_Vored then continue end
            if not (ent.Predator or ent.VNPC_FemaleModelVore or ent.VNPC_Belly or ent.Belly or ent.IsDrGNextbot) then
                continue
            end
            local belly = ent.VNPC_Belly or ent.Belly
            if not IsValid(belly) and ent.GetNWEntity then
                belly = ent:GetNWEntity("Belly")
            end
            if not IsValid(belly) then continue end
            local chain = ent.VNPC_VirtualBellyBones
            local live = chain and ((chain.size or 0) > 0.02 or (chain.pregSize or 0) > 0.04)
            local gulp = (ent.GetNWInt and ent:GetNWInt("VNPC_GPUGulpN", 0) or 0) > 0
            local should = hide and gpu and meshOn and (live or gulp)
            if should then
                if not belly.VNPC_GPUHidden then
                    belly.VNPC_GPUHidden = true
                    belly:SetNoDraw(true)
                elseif not belly:GetNoDraw() then
                    belly:SetNoDraw(true)
                end
            elseif belly.VNPC_GPUHidden then
                belly.VNPC_GPUHidden = nil
                belly:SetNoDraw(false)
            end
        end
    end)
end

concommand.Add("vnpcs_test_gpu_fx", function(ply)
    if not IsValid(ply) then return end
    local target = ply:GetEyeTrace().Entity
    if not IsValid(target) or not (target:IsNPC() or target:IsNextBot() or target.IsDrGNextbot) then
        ply:ChatPrint("[V-NPCs] Aim at a predator to test the full GPU belly FX set!")
        return
    end
    target.VNPC_GPUStruggleTest = {
        { id = target:EntIndex() * 13 + 1, mul = 1.30, head = 1.05, torso = 1.15, hip = 1.08 },
        { id = target:EntIndex() * 17 + 2, mul = 1.05, head = 0.72, torso = 0.80, hip = 0.78 }
    }
    target.VNPC_GPUGulpTest = {
        { id = target:EntIndex() * 11 + 1, scale = 1.25, animate = true }
    }
    if VNPC_SyncGPUBellyStruggle then VNPC_SyncGPUBellyStruggle(target) end
    if VNPC_SyncGPUBellyGulp then VNPC_SyncGPUBellyGulp(target) end
    if target.SetFacialExpression then
        target:SetFacialExpression(2)
    elseif target.SetNWInt then
        target:SetNWInt("FacialPhase", 2)
    end
    ply:ChatPrint("[V-NPCs] GPU FX on " .. tostring(target) .. ": torso hull, peristalsis gulp, 2 prey silhouettes, jiggle. vnpcs_gpu_belly_debug 1 to overlay.")
end)
