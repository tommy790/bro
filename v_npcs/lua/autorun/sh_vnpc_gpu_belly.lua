-- V-NPCs GPU Belly Bone Generator (sh_vnpc_gpu_belly.lua)
-- Builds a virtual belly bone chain from any humanoid skeleton and skins a
-- GPU mesh to it. Stock HL2 / citizen / combine models do not need belly bones.

CreateConVar("vnpcs_gpu_belly_enabled", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Auto-generate belly bones and a GPU belly mesh on models that have no belly bones")
CreateConVar("vnpcs_gpu_belly_mesh", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Draw the GPU-skinned belly mesh generated from virtual bones")
CreateConVar("vnpcs_gpu_belly_bonescale", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Scale existing spine/pelvis/thigh bones so the character mesh itself grows a belly")
CreateConVar("vnpcs_gpu_belly_debug", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Draw generated belly bones and the GPU mesh wireframe")
CreateConVar("vnpcs_gpu_belly_struggle", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Procedural 4-spot mesh deformations on the GPU belly per struggling prey")
CreateConVar("vnpcs_gpu_belly_struggle_amp", "1.0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Amplitude multiplier for GPU belly struggle lumps")

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
    lthigh = { "ValveBiped.Bip01_L_Thigh", "L_Thigh", "l_thigh" },
    rthigh = { "ValveBiped.Bip01_R_Thigh", "R_Thigh", "r_thigh" }
}

local SCALE_TARGETS = {
    { names = { "ValveBiped.Bip01_Spine", "Spine", "spine" }, mul = Vector(0.28, 0.85, 0.22) },
    { names = { "ValveBiped.Bip01_Spine1", "Spine1", "spine1" }, mul = Vector(0.22, 0.70, 0.18) },
    { names = { "ValveBiped.Bip01_Pelvis", "Pelvis", "pelvis" }, mul = Vector(0.20, 0.55, 0.16) },
    { names = { "ValveBiped.Bip01_L_Thigh", "L_Thigh", "l_thigh" }, mul = Vector(0.06, 0.18, 0.10) },
    { names = { "ValveBiped.Bip01_R_Thigh", "R_Thigh", "r_thigh" }, mul = Vector(0.06, 0.18, 0.10) }
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
    if ent.GetNWFloat then
        local boneScale = (ent:GetNWFloat("Bonescale", 1) or 1) - 1
        if boneScale > 0 then
            scale = math.max(scale, boneScale * 0.35)
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
    local radius = math.max(4.5, 18 * math.max(size, 0.08) * math.max(mdlScale, 0.25))
    if size < 0.02 and not ent.VNPC_IsPregnant then
        radius = math.max(4.5, (ent.VNPC_BodyParts and ent.VNPC_BodyParts.torso and ent.VNPC_BodyParts.torso.width or 14) * 0.28)
    end

    local root = LerpVector(0.38, pelvis, spine1) + fwd * (3.5 + radius * 0.22)
    local mid = root + fwd * (radius * 0.58)
    local upper = root + up * (radius * 0.42) + fwd * (radius * 0.18)
    local lower = root - up * (radius * 0.48) + fwd * (radius * 0.32)
    if lthigh and rthigh then
        local hip = LerpVector(0.5, lthigh, rthigh)
        lower = LerpVector(0.35, lower, hip + fwd * (radius * 0.4))
    end
    local left = root - right * (radius * 0.52) + fwd * (radius * 0.22)
    local rightB = root + right * (radius * 0.52) + fwd * (radius * 0.22)
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
        width = radius * 2.05,
        height = radius * 1.75,
        depth = radius * 1.55,
        forward = fwd,
        up = up,
        right = right,
        root = bone("VNPC_Belly_Root", root, radius * 0.55, nil),
        upper = bone("VNPC_Belly_Upper", upper, radius * 0.42, "VNPC_Belly_Root"),
        mid = bone("VNPC_Belly_Mid", mid, radius, "VNPC_Belly_Root"),
        lower = bone("VNPC_Belly_Lower", lower, radius * 0.62, "VNPC_Belly_Root"),
        left = bone("VNPC_Belly_L", left, radius * 0.48, "VNPC_Belly_Root"),
        right = bone("VNPC_Belly_R", rightB, radius * 0.48, "VNPC_Belly_Root")
    }
    chain.byName = {
        VNPC_Belly_Root = chain.root,
        VNPC_Belly_Upper = chain.upper,
        VNPC_Belly_Mid = chain.mid,
        VNPC_Belly_Lower = chain.lower,
        VNPC_Belly_L = chain.left,
        VNPC_Belly_R = chain.right
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

function VNPC_ApplyGeneratedBellyBoneScale(ent, chain)
    if not IsValid(ent) or not ent.ManipulateBoneScale then return end
    local cv = GetConVar("vnpcs_gpu_belly_bonescale")
    if cv and not cv:GetBool() then return end
    chain = chain or ent.VNPC_VirtualBellyBones
    if not chain then return end

    local extra = math.Clamp((chain.size or 0) * 0.85, 0, 1.35)
    if extra < 0.03 then
        if ent.VNPC_GPUBellyScaled then
            for _, spec in ipairs(SCALE_TARGETS) do
                local id = lookup(ent, { spec[1], unpack(spec[2]) })
                if id then
                    ent:ManipulateBoneScale(id, Vector(1, 1, 1))
                end
            end
            ent.VNPC_GPUBellyScaled = nil
        end
        return
    end

    for _, spec in ipairs(SCALE_TARGETS) do
        local id = lookup(ent, { spec[1], unpack(spec[2]) })
        if id then
            local w = spec[3]
            ent:ManipulateBoneScale(id, Vector(1 + extra * w.x, 1 + extra * w.y, 1 + extra * w.z))
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
                mesh.Position(world)
                mesh.Normal(nrm)
                mesh.TexCoord(0, v.u, v.v)
                mesh.Color(255, 255, 255, 255)
                mesh.AdvanceVertex()
            end
        end
        mesh.End()
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
            if not chain or (chain.size or 0) < 0.035 then continue end
            pcall(drawGeneratedBelly, ent, chain)
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
                VNPC_Belly_R = Color(80, 255, 160)
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
    print("-----------------------------------------")
    local count = 0
    for _, ent in ipairs(ents.FindByClass("npc_*")) do
        if isPredCandidate(ent) then
            local chain = VNPC_UpdateVirtualBellyBones(ent)
            if chain then
                count = count + 1
                local preyN = (ent.GetNWInt and ent:GetNWInt("VNPC_GPUStruggleN", 0)) or 0
                print(string.format(" -> #%d [%s] size=%.3f radius=%.1f W/H %.1f/%.1f modelBellyBones=%s strugglePrey=%d spots=%d",
                    ent:EntIndex(), ent.PrintName or ent:GetClass(), chain.size, chain.radius,
                    chain.width, chain.height, tostring(chain.hasModelBellyBones), preyN, preyN * 4))
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
