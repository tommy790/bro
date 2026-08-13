if not CLIENT then return end

--[[
    V-NPC BELLY TEXTURE BLENDING - MESH MODE (no camera)
    =====================================================

    The render-target camera approach (vnpcs_belly_rt.lua) photographs the
    torso every time the NPC changes appearance.  It works, but it has real
    downsides: capture lag, RT resolution limits, and the camera frame can
    include the wrong body region (e.g. the chest).

    This module replaces the camera entirely:

      1. Load the belly model's triangles (util.GetModelMeshes).
      2. Find the abdomen region of the PREDATOR's own skin texture: the
         triangles of the predator model whose 3D positions sit under the
         belly, projected into UV space.
      3. Remap every belly vertex's UV into that abdomen region.
      4. Render the belly mesh with a clone of the predator's own material
         ($basetexture = the actual skin texture, plus its $bumpmap /
         $phong / $halflambert / $surfaceprop params).

    Result: the belly IS the body's skin - same texture, same lighting,
    same shading.  No camera, no RT, no capture lag, no chest in frame.
    The belly's own spring/flex animations are applied to the mesh
    directly, so it still grows, wobbles and ripples like before.

    ConVars:
        vnpcs_belly_mesh      1   master switch (0 = old RT camera path)
        vnpcs_belly_mesh_flipu 0  flip the sampled texture horizontally
        vnpcs_belly_mesh_flipv 0  flip the sampled texture vertically
]]

VNPCS_BellyBlend = VNPCS_BellyBlend or {}

local Blend = VNPCS_BellyBlend

local vnpcs_belly_mesh       = CreateClientConVar("vnpcs_belly_mesh", "1", true)
local vnpcs_belly_mesh_flipu = CreateClientConVar("vnpcs_belly_mesh_flipu", "0", true)
local vnpcs_belly_mesh_flipv = CreateClientConVar("vnpcs_belly_mesh_flipv", "0", true)

local MIN_ABDOMEN_TRIANGLES = 24
local MAX_VERTS = 20000
local RIPPLE_AMP = 4
local SIGNATURE_POLL_RATE = 0.25

local states = {} -- belly -> state | false

-- Shader params that are safe to clone from the predator's material onto
-- the belly material.  $basetexture makes the belly use the real skin
-- texture; the rest makes it light up exactly like the body.
local VMT_WHITELIST = {
    ["$basetexture"] = true,
    ["$bumpmap"] = true,
    ["$phong"] = true,
    ["$phongboost"] = true,
    ["$phongfresnelranges"] = true,
    ["$phongexponent"] = true,
    ["$halflambert"] = true,
    ["$surfaceprop"] = true,
    ["$ambientocclusion"] = true,
    ["$basemapalphaphongmask"] = true,
    ["$normalmapalphaenvmapmask"] = true,
    ["$detail"] = true,
    ["$detailblendmode"] = true,
    ["$detailscale"] = true
}

local function cleanVerts(raw)
    local out = {}
    for i = 1, #raw do
        local v = raw[i]
        out[i] = {
            pos = v.pos,
            normal = v.normal,
            tangent = v.tangent,
            u = v.u,
            v = v.v,
            userdata = v.userdata,
            weights = v.weights
        }
    end
    return out
end

--- Reads a .vmt; returns (params, shaderName) or nil.
local function parseVmt(materialName)
    if not materialName or materialName == "" then return nil end

    local content = file.Read("materials/" .. materialName .. ".vmt", "GAME")
    if not content then return nil end

    local params = {}
    for key, value in string.gmatch(content, '"(%$[%w_]+)"%s*"([^"]*)"') do
        local lkey = string.lower(key)
        if VMT_WHITELIST[lkey] then
            params[lkey] = string.gsub(value, "\\", "/")
        end
    end

    local shader = content:match("^%s*([%w_]+)%s*{")

    return params, shader
end

local function getPredator(belly)
    local p = belly.NPC
    if not IsValid(p) then
        p = belly:GetNWEntity("NPCParent")
    end
    return IsValid(p) and p or nil
end

--[[ ======================= FLEX RIPPLE REGIONS ======================= ]]
-- The belly model's flexes (driven by the existing animation code) are
-- emulated on the mesh: each vertex is tagged with which flex regions it
-- belongs to, and flex weights push those regions outward.

local FLEX_BIT_TOP    = 1
local FLEX_BIT_BOTTOM = 2
local FLEX_BIT_RIGHT  = 4
local FLEX_BIT_LEFT   = 8
local FLEX_BIT_OUT    = 16

local function flexRegion(name)
    local low = string.lower(name or "")

    if string.find(low, "preyoutline") then
        return FLEX_BIT_OUT, Vector(0, 1, 0)
    end
    if string.find(low, "middletop") then
        return FLEX_BIT_TOP, Vector(0, 0.3, 1)
    end
    if string.find(low, "middlebottom") then
        return FLEX_BIT_BOTTOM, Vector(0, 0.3, -1)
    end
    if string.find(low, "middlelefttop") then
        return FLEX_BIT_LEFT + FLEX_BIT_TOP, Vector(-0.7, 0.3, 0.7)
    end
    if string.find(low, "middlerighttop") then
        return FLEX_BIT_RIGHT + FLEX_BIT_TOP, Vector(0.7, 0.3, 0.7)
    end
    if string.find(low, "middleleft") then
        return FLEX_BIT_LEFT, Vector(-1, 0.3, 0)
    end
    if string.find(low, "middleright") then
        return FLEX_BIT_RIGHT, Vector(1, 0.3, 0)
    end
    if string.find(low, "topleft") then
        return FLEX_BIT_LEFT + FLEX_BIT_TOP, Vector(-0.7, 0.3, 0.7)
    end
    if string.find(low, "topright") then
        return FLEX_BIT_RIGHT + FLEX_BIT_TOP, Vector(0.7, 0.3, 0.7)
    end
    if string.find(low, "bottomleft") then
        return FLEX_BIT_LEFT + FLEX_BIT_BOTTOM, Vector(-0.7, 0.3, -0.7)
    end
    if string.find(low, "bottomright") then
        return FLEX_BIT_RIGHT + FLEX_BIT_BOTTOM, Vector(0.7, 0.3, -0.7)
    end
    if string.find(low, "top") then
        return FLEX_BIT_TOP, Vector(0, 0.3, 1)
    end
    if string.find(low, "bottom") then
        return FLEX_BIT_BOTTOM, Vector(0, 0.3, -1)
    end
    if string.find(low, "left") then
        return FLEX_BIT_LEFT, Vector(-1, 0.3, 0)
    end
    if string.find(low, "right") then
        return FLEX_BIT_RIGHT, Vector(1, 0.3, 0)
    end

    return FLEX_BIT_OUT, Vector(0, 1, 0)
end

local function buildRippleInfo(base, bellyBounds, flexNames)
    local flexes = {}
    for i = 1, #flexNames do
        local mask, dir = flexRegion(flexNames[i])
        flexes[i] = { mask = mask, dir = dir }
    end
    if #flexes == 0 then return nil end

    local w = math.max(bellyBounds.w, 1)
    local h = math.max(bellyBounds.h, 1)
    local d = math.max(bellyBounds.d, 1)

    local ripple = {}
    for i = 1, #base do
        local p = base[i].pos
        local nx = (p.x - bellyBounds.cx) / w
        local ny = (p.y - bellyBounds.cy) / d
        local nz = (p.z - bellyBounds.cz) / h

        local mask = 0
        if nz > 0.35 then mask = mask + FLEX_BIT_TOP end
        if nz < -0.35 then mask = mask + FLEX_BIT_BOTTOM end
        if nx > 0.35 then mask = mask + FLEX_BIT_RIGHT end
        if nx < -0.35 then mask = mask + FLEX_BIT_LEFT end
        if math.abs(ny) > 0.4 then mask = mask + FLEX_BIT_OUT end

        local list = {}
        for fi = 1, #flexes do
            local info = flexes[fi]
            if bit.band(mask, info.mask) == info.mask then
                list[#list + 1] = { fi, info.dir.x, info.dir.y, info.dir.z }
            end
        end
        ripple[i] = list
    end

    return ripple
end

--[[ ========================== STATE BUILD ========================== ]]

local function buildState(belly)
    local predator = getPredator(belly)
    if not predator then return false end

    local bellyModel = belly:GetModel()
    local predModel = predator:GetModel()
    if not bellyModel or bellyModel == "" or not predModel or predModel == "" then
        return false
    end

    -- 1. belly triangles
    local bellyBodies = util.GetModelMeshes(bellyModel)
    if not bellyBodies then return false end

    local rawBelly = nil
    for i = 1, #bellyBodies do
        local b = bellyBodies[i]
        if b and b.triangles and #b.triangles >= 3 then
            rawBelly = cleanVerts(b.triangles)
            break
        end
    end
    if not rawBelly or #rawBelly < 3 or #rawBelly > MAX_VERTS then return false end

    -- belly UV bounds + belly model bounds (for the ripple regions)
    local bu0, bv0, bu1, bv1 = 1e9, 1e9, -1e9, -1e9
    local mins, maxs = Vector(1e9, 1e9, 1e9), Vector(-1e9, -1e9, -1e9)
    for i = 1, #rawBelly do
        local p = rawBelly[i].pos
        local u, v = rawBelly[i].u, rawBelly[i].v
        if u < bu0 then bu0 = u end
        if v < bv0 then bv0 = v end
        if u > bu1 then bu1 = u end
        if v > bv1 then bv1 = v end
        if p.x < mins.x then mins.x = p.x end
        if p.y < mins.y then mins.y = p.y end
        if p.z < mins.z then mins.z = p.z end
        if p.x > maxs.x then maxs.x = p.x end
        if p.y > maxs.y then maxs.y = p.y end
        if p.z > maxs.z then maxs.z = p.z end
    end
    if bu1 <= bu0 or bv1 <= bv0 then return false end

    local bellyBounds = {
        cx = (mins.x + maxs.x) * 0.5,
        cy = (mins.y + maxs.y) * 0.5,
        cz = (mins.z + maxs.z) * 0.5,
        w = maxs.x - mins.x,
        h = maxs.z - mins.z,
        d = maxs.y - mins.y
    }

    -- 2. abdomen region in predator model space: a box under the belly
    local pmins, pmaxs = predator:GetModelBounds()
    local ph = math.max(pmaxs.z - pmins.z, 1)
    local bellyLocal = predator:WorldToLocal(belly:GetPos())

    local zCenter = math.Clamp(bellyLocal.z, pmins.z + ph * 0.3, pmins.z + ph * 0.6)
    local z0 = zCenter - ph * 0.09
    local z1 = zCenter + ph * 0.09

    -- the side of the body the belly sticks out from
    local axis, sign
    if math.abs(bellyLocal.x) >= math.abs(bellyLocal.y) then
        axis, sign = "x", bellyLocal.x >= 0 and 1 or -1
    else
        axis, sign = "y", bellyLocal.y >= 0 and 1 or -1
    end
    local axisMax = math.max(math.abs(pmins[axis]), math.abs(pmaxs[axis]))
    if axisMax <= 0.1 then return false end
    local a0 = sign * axisMax * 0.15
    local a1 = sign * axisMax * 0.98

    local other = axis == "x" and "y" or "x"
    local o0, o1 = pmins[other], pmaxs[other]

    -- 3. find the torso triangles inside that box -> abdomen UV bounds
    local torsoBodies = util.GetModelMeshes(predModel)
    if not torsoBodies then return false end

    local bestBody, bestCount, bestUs, bestVs = nil, 0, nil, nil
    for i = 1, #torsoBodies do
        local body = torsoBodies[i]
        if body and body.triangles and #body.triangles >= 3 then
            local count = 0
            local us, vs = {}, {}
            for ti = 1, #body.triangles - 2, 3 do
                local a = body.triangles[ti]
                local b = body.triangles[ti + 1]
                local c = body.triangles[ti + 2]
                local cx = (a.pos.x + b.pos.x + c.pos.x) / 3
                local cy = (a.pos.y + b.pos.y + c.pos.y) / 3
                local cz = (a.pos.z + b.pos.z + c.pos.z) / 3
                if cz >= z0 and cz <= z1 and cx >= a0 and cx <= a1
                    and cy >= o0 and cy <= o1 then
                    us[#us + 1] = a.u
                    vs[#vs + 1] = a.v
                    us[#us + 1] = b.u
                    vs[#vs + 1] = b.v
                    us[#us + 1] = c.u
                    vs[#vs + 1] = c.v
                    count = count + 1
                end
            end
            if count > bestCount then
                bestCount, bestBody, bestUs, bestVs = count, body, us, vs
            end
        end
    end

    if not bestBody or bestCount < MIN_ABDOMEN_TRIANGLES then return false end

    local au0, av0, au1, av1 = 1e9, 1e9, -1e9, -1e9
    for i = 1, #bestUs do
        local u, v = bestUs[i], bestVs[i]
        if u < au0 then au0 = u end
        if v < av0 then av0 = v end
        if u > au1 then au1 = u end
        if v > av1 then av1 = v end
    end
    if au1 <= au0 or av1 <= av0 then return false end

    -- 4. material: clone the predator's skin material (override first)
    local matSource = predator:GetMaterial()
    if not matSource or matSource == "" then
        matSource = bestBody.material
    end
    local params, shader = parseVmt(matSource)
    if not params or not params["$basetexture"] then
        params, shader = parseVmt(bestBody.material)
        if not params or not params["$basetexture"] then return false end
    end

    local mat = CreateMaterial(
        "vnpcs_belly_blend_mat_" .. belly:EntIndex(),
        shader or "VertexLitGeneric",
        { ["$basetexture"] = params["$basetexture"], ["$ignorez"] = "0" }
    )
    if not mat then return false end

    for k, v in pairs(params) do
        if k ~= "$basetexture" then
            mat:SetString(k, v)
        end
    end
    mat:SetTexture("$basetexture", params["$basetexture"])

    -- 5. remap belly UVs into the abdomen region of the skin texture
    local flipU = vnpcs_belly_mesh_flipu:GetBool() and -1 or 1
    local flipV = vnpcs_belly_mesh_flipv:GetBool() and -1 or 1
    local su = (au1 - au0) / (bu1 - bu0)
    local sv = (av1 - av0) / (bv1 - bv0)

    local work = {}
    for i = 1, #rawBelly do
        local src = rawBelly[i]
        local u = au0 + (src.u - bu0) * su
        local v = av0 + (src.v - bv0) * sv
        if flipU < 0 then u = au0 + (bu1 - src.u) * su end
        if flipV < 0 then v = av0 + (bv1 - src.v) * sv end

        work[i] = {
            pos = src.pos,
            normal = src.normal,
            tangent = src.tangent,
            u = u,
            v = v,
            userdata = src.userdata,
            weights = src.weights
        }
    end

    local mesh = Mesh()
    local ok = pcall(function()
        mesh:BuildFromTriangles(work)
    end)
    if not ok then return false end

    -- 6. flex ripple regions
    local ripple = buildRippleInfo(rawBelly, bellyBounds, belly.FlexNames or {})

    return {
        belly = belly,
        mesh = mesh,
        mat = mat,
        base = rawBelly,
        work = work,
        ripple = ripple,
        signature = nil,
        nextPoll = 0,
        hidden = false,
        lastSize = -1,
        lastRot = -1
    }
end

--[[ ========================== PER FRAME ========================== ]]

local function updateState(st, dt)
    local belly = st.belly
    if not IsValid(belly) or not IsValid(st.mesh) then return end

    local size = belly.BellySpring and belly.BellySpring.pos
        or belly:GetNWFloat("BellySize", 0)
    if not size or size ~= size then size = 0 end -- nan guard
    size = math.max(size, 0)

    if size <= 0.02 then
        st.hidden = true
        return
    end
    st.hidden = false

    local rot = belly.RotationSpring and belly.RotationSpring.pos or 0

    -- offsets mirroring the classic belly bone animation
    local ugh = math.min(-(1 - size) * 3.5, 0)
    local ox, oy, oz = 0, ugh * 1.2, ugh * 0.9

    -- flex weights (already animated by belly_modules/animations.lua)
    local names = belly.FlexNames or {}
    local flexW = {}
    local rippleActive = false
    if st.ripple then
        for i = 1, #names do
            local fid = belly:GetFlexIDByName(names[i])
            if fid and fid >= 0 then
                local w = belly:GetFlexWeight(fid) or 0
                flexW[i] = w
                if w ~= 0 then rippleActive = true end
            end
        end
    end

    local changed = math.abs(size - st.lastSize) > 0.004
        or math.abs(rot - st.lastRot) > 0.02
    if not changed and not rippleActive then return end
    st.lastSize = size
    st.lastRot = rot

    local cosR = math.cos(math.rad(rot))
    local sinR = math.sin(math.rad(rot))
    local base = st.base
    local work = st.work
    local ripple = st.ripple
    local n = #work

    for i = 1, n do
        local bp = base[i].pos
        local wp = work[i].pos

        local x, y, z = bp.x * size, bp.y * size, bp.z * size
        local rx = x * cosR - y * sinR
        local ry = x * sinR + y * cosR

        local rdx, rdy, rdz = 0, 0, 0
        if rippleActive and ripple and ripple[i] then
            local amp = size * RIPPLE_AMP
            local rl = ripple[i]
            for j = 1, #rl do
                local ri = rl[j]
                local w = flexW[ri[1]] or 0
                if w ~= 0 then
                    local push = w * amp
                    rdx = rdx + ri[2] * push
                    rdy = rdy + ri[3] * push
                    rdz = rdz + ri[4] * push
                end
            end
        end

        wp.x = rx + ox + rdx
        wp.y = ry + oy + rdy
        wp.z = z + oz + rdz

        -- keep normals in sync with the rotation
        local bn = base[i].normal
        local wn = work[i].normal
        wn.x = bn.x * cosR - bn.y * sinR
        wn.y = bn.x * sinR + bn.y * cosR
        wn.z = bn.z
    end

    pcall(function()
        st.mesh:BuildFromTriangles(work)
    end)
end

local function buildSignature(belly, predator)
    local parts = {
        belly:GetModel() or "",
        predator:GetModel() or "",
        tostring(predator:GetSkin() or 0),
        tostring(predator:GetMaterial() or "")
    }

    local bcount = predator:GetNumBodyGroups() or 0
    for i = 0, bcount - 1 do
        parts[#parts + 1] = i .. "=" .. tostring(predator:GetBodygroup(i) or 0)
    end

    local mats = predator:GetMaterials() or {}
    for i = 0, #mats - 1 do
        parts[#parts + 1] = tostring(predator:GetSubMaterial(i) or "")
    end

    parts[#parts + 1] = tostring(vnpcs_belly_mesh_flipu:GetBool())
    parts[#parts + 1] = tostring(vnpcs_belly_mesh_flipv:GetBool())

    return table.concat(parts, "|")
end

local function ensureState(belly)
    local existing = states[belly]
    if existing ~= nil then
        return existing == false and nil or existing
    end

    if not vnpcs_belly_mesh:GetBool() then return nil end

    local st = buildState(belly)
    states[belly] = st or false
    return st
end

local function removeState(belly)
    local st = states[belly]
    if st and st ~= false and IsValid(st.mesh) then
        -- IMesh has no explicit destructor; dropping the reference is enough.
    end
    states[belly] = nil
end

--[[ ========================== PUBLIC API ========================== ]]

--- Called from the belly ENT:Draw().  Returns true when the belly was
--- drawn with the blended skin mesh (skip the classic/RT path).
function Blend.Draw(belly)
    if not vnpcs_belly_mesh:GetBool() then return false end

    local st = ensureState(belly)
    if not st or st.hidden then return false end

    local color = belly:GetColor()
    belly:SetColor(Color(255, 255, 255, 255))

    -- DrawModel() makes the engine consult ENT:GetRenderMesh(), which
    -- returns our skin-textured mesh + material.
    belly:DrawModel()

    belly:SetColor(color)
    return true
end

--- Engine hook (defined on the belly entities): returns the blended mesh.
function Blend.GetRenderMesh(belly)
    if not vnpcs_belly_mesh:GetBool() then return nil end

    local st = states[belly]
    if not st or st == false or st.hidden then return nil end

    return { Mesh = st.mesh, Material = st.mat }
end

hook.Add("Think", "VNPCS_BellyBlend_Update", function()
    for belly, st in pairs(states) do
        if not IsValid(belly) then
            removeState(belly)
        elseif st ~= false then
            local now = CurTime()
            if now >= st.nextPoll then
                st.nextPoll = now + SIGNATURE_POLL_RATE
                local predator = getPredator(belly)
                if IsValid(predator) then
                    local sig = buildSignature(belly, predator)
                    if sig ~= st.signature then
                        -- appearance changed: rebuild the blend from scratch
                        removeState(belly)
                        local fresh = buildState(belly)
                        if fresh then
                            fresh.signature = sig
                            fresh.nextPoll = now + SIGNATURE_POLL_RATE
                        end
                        states[belly] = fresh or false
                    end
                end
            end

            local fresh = states[belly]
            if fresh and fresh ~= false then
                updateState(fresh, math.min(FrameTime(), 0.1))
            end
        end
    end
end)

hook.Add("EntityRemoved", "VNPCS_BellyBlend_Cleanup", function(ent)
    if states[ent] then
        removeState(ent)
    end
end)
