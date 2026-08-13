if not CLIENT then return end

--[[
    V-NPC belly render-target texturing

    Each rendered belly owns a non-networked clientside duplicate of its predator.
    The duplicate is never simulated or drawn by the world.  It is copied into a
    neutral T-pose and rendered manually into a private RT, so the belly material
    samples the predator's live torso appearance instead of a hand-authored tint.
]]

VNPCS_BellyRT = VNPCS_BellyRT or {}

local BellyRT = VNPCS_BellyRT
local RT_SIZE = 512
local CAPTURES_PER_FRAME = 1
local SIGNATURE_POLL_RATE = 0.15
local DUPLICATE_ORIGIN = Vector(0, 0, 0)
local WHITE = Color(255, 255, 255, 255)
local ZERO_ANGLE = Angle(0, 0, 0)
local ONE_VECTOR = Vector(1, 1, 1)

-- Belly texture blending controls.  The render-target material is what makes
-- the belly sample the VNPC's own torso texture; these tweak how seamlessly
-- it blends with the body.
local vnpcs_belly_rt_enable = CreateClientConVar("vnpcs_belly_rt_enable", "1", true)
local vnpcs_belly_rt_size   = CreateClientConVar("vnpcs_belly_rt_size", "512", true)
local vnpcs_belly_lit       = CreateClientConVar("vnpcs_belly_lit", "1", true)
-- Where the capture frame centres on the body: 0 = feet, 1 = top of head.
-- 0.42 sits just below the navel - the belly hangs at the abdomen, and
-- framing the chest would bake the breast region onto the belly.
local vnpcs_belly_rt_center = CreateClientConVar("vnpcs_belly_rt_center", "0.42", true)
-- 0.6 = wider frame (more torso around the belly), 1.6 = tighter frame.
local vnpcs_belly_rt_zoom   = CreateClientConVar("vnpcs_belly_rt_zoom", "1.0", true)

RT_SIZE = math.Clamp(vnpcs_belly_rt_size:GetInt(), 128, 1024)

local states = {}
local captureQueue = {}
local nextUID = 0

local torsoBones = {
    "ValveBiped.Bip01_Pelvis",
    "ValveBiped.Bip01_Spine",
    "ValveBiped.Bip01_Spine1",
    "ValveBiped.Bip01_Spine2",
    "ValveBiped.Bip01_Spine4",
    "Pelvis",
    "Spine",
    "Spine1",
    "Spine2",
    "Bip01_Pelvis",
    "Bip01_Spine",
    "Bip01_Spine1",
    "Bip01_Spine2",
    "bip_pelvis",
    "bip_spine_0",
    "bip_spine_1",
    "bip_spine_2"
}

local tPoseSequences = {
    "reference",
    "ref",
    "ragdoll",
    "ragdoll_pose",
    "idle_all_01"
}

local function safeCall(ent, method, ...)
    if not IsValid(ent) or not ent[method] then return nil end
    local ok, result = pcall(ent[method], ent, ...)
    if ok then return result end
    return nil
end

local function safeSet(ent, method, ...)
    if not IsValid(ent) or not ent[method] then return end
    pcall(ent[method], ent, ...)
end

local function getBodygroupSignature(ent)
    local parts = {}
    local count = ent:GetNumBodyGroups() or 0
    for id = 0, count - 1 do
        parts[#parts + 1] = id .. "=" .. tostring(ent:GetBodygroup(id) or 0)
    end
    return table.concat(parts, ",")
end

local function getSubMaterialSignature(ent)
    local parts = {}
    local mats = ent:GetMaterials() or {}

    for id = 0, #mats - 1 do
        parts[#parts + 1] = id .. "=" .. tostring(ent:GetSubMaterial(id) or "")
    end

    return table.concat(parts, ",")
end

local function getFlexSignature(ent)
    local flexNum = ent:GetFlexNum() or 0
    if flexNum <= 0 then return "" end

    local parts = { tostring(safeCall(ent, "GetFlexScale") or "") }
    for id = 0, flexNum - 1 do
        parts[#parts + 1] = id .. "=" .. string.format("%.3f", ent:GetFlexWeight(id) or 0)
    end

    return table.concat(parts, ",")
end

local function getPoseSignature(ent)
    local count = safeCall(ent, "GetNumPoseParameters") or 0
    if count <= 0 then return "" end

    local parts = {}
    for id = 0, count - 1 do
        local name = safeCall(ent, "GetPoseParameterName", id)
        if name then
            parts[#parts + 1] = name .. "=" .. string.format("%.3f", ent:GetPoseParameter(name) or 0)
        end
    end

    return table.concat(parts, ",")
end

local function getPlayerColorSignature(ent)
    local playerColor = safeCall(ent, "GetPlayerColor")
    if not playerColor then return "" end
    return string.format("%.3f/%.3f/%.3f", playerColor.x or 0, playerColor.y or 0, playerColor.z or 0)
end

local function buildSignature(predator)
    local color = predator:GetColor() or WHITE

    return table.concat({
        predator:GetModel() or "",
        tostring(predator:GetSkin() or 0),
        string.format("%.4f", predator:GetModelScale() or 1),
        getBodygroupSignature(predator),
        tostring(predator:GetMaterial() or ""),
        getSubMaterialSignature(predator),
        string.format("%d/%d/%d/%d", color.r or 255, color.g or 255, color.b or 255, color.a or 255),
        tostring(predator:GetRenderMode() or 0),
        tostring(predator:GetRenderFX() or 0),
        getPlayerColorSignature(predator),
        getFlexSignature(predator),
        getPoseSignature(predator)
    }, "|")
end

local function copyBodygroups(src, dst)
    local count = src:GetNumBodyGroups() or 0
    for id = 0, count - 1 do
        dst:SetBodygroup(id, src:GetBodygroup(id) or 0)
    end
end

local function copySubMaterials(src, dst)
    local srcMats = src:GetMaterials() or {}
    local dstMats = dst:GetMaterials() or {}
    local count = math.max(#srcMats, #dstMats)

    for id = 0, count - 1 do
        dst:SetSubMaterial(id, src:GetSubMaterial(id) or "")
    end
end

local function copyFlexes(src, dst)
    local srcFlexNum = src:GetFlexNum() or 0
    local dstFlexNum = dst:GetFlexNum() or 0
    local flexNum = math.min(srcFlexNum, dstFlexNum)

    safeSet(dst, "SetFlexScale", safeCall(src, "GetFlexScale") or 1)
    for id = 0, flexNum - 1 do
        dst:SetFlexWeight(id, src:GetFlexWeight(id) or 0)
    end
end

local function copyPoseParameters(src, dst)
    local count = safeCall(src, "GetNumPoseParameters") or 0
    if count <= 0 then return end

    for id = 0, count - 1 do
        local name = safeCall(src, "GetPoseParameterName", id)
        if name then
            safeSet(dst, "SetPoseParameter", name, src:GetPoseParameter(name) or 0)
        end
    end
end

local function copyVisualState(src, dst)
    local model = src:GetModel()
    if model and dst:GetModel() ~= model then
        dst:SetModel(model)
    end

    dst:SetSkin(src:GetSkin() or 0)
    dst:SetModelScale(src:GetModelScale() or 1, 0)
    dst:SetMaterial(src:GetMaterial() or "")
    dst:SetColor(src:GetColor() or WHITE)
    dst:SetRenderMode(src:GetRenderMode() or RENDERMODE_NORMAL)
    dst:SetRenderFX(src:GetRenderFX() or kRenderFxNone)

    local playerColor = safeCall(src, "GetPlayerColor")
    if playerColor then
        safeSet(dst, "SetPlayerColor", playerColor)
    end

    copyBodygroups(src, dst)
    copySubMaterials(src, dst)
    copyFlexes(src, dst)
    copyPoseParameters(src, dst)
end

local function forceTPose(ent)
    ent:SetPos(DUPLICATE_ORIGIN)
    ent:SetAngles(ZERO_ANGLE)
    ent:SetVelocity(vector_origin)
    ent:SetPlaybackRate(0)

    local foundSequence = false
    for _, seqName in ipairs(tPoseSequences) do
        local seq = ent:LookupSequence(seqName)
        if seq and seq >= 0 then
            ent:ResetSequence(seq)
            foundSequence = true
            break
        end
    end

    if not foundSequence then
        ent:ResetSequence(0)
    end

    ent:SetCycle(0)
    ent:FrameAdvance(0)

    local boneCount = ent:GetBoneCount() or 0
    for id = 0, boneCount - 1 do
        ent:ManipulateBonePosition(id, vector_origin)
        ent:ManipulateBoneAngles(id, ZERO_ANGLE)
        ent:ManipulateBoneScale(id, ONE_VECTOR)
    end

    ent:InvalidateBoneCache()
    ent:SetupBones()
end

local function getTorsoTarget(ent)
    ent:SetupBones()

    local mins, maxs = ent:GetModelBounds()
    local center = (mins + maxs) * 0.5
    local found = 0
    local sum = Vector(0, 0, 0)

    for _, name in ipairs(torsoBones) do
        local bone = ent:LookupBone(name)
        if bone then
            local pos = ent:GetBonePosition(bone)
            if pos then
                sum = sum + pos
                found = found + 1
            end
        end
    end

    if found > 0 then
        center = sum / found
    end

    local height = maxs.z - mins.z
    center.x = 0
    center.y = 0
    center.z = math.Clamp(center.z, mins.z + height * 0.35, mins.z + height * 0.68)

    return center, mins, maxs
end

local function ensureDuplicate(state, predator)
    if IsValid(state.clone) then return state.clone end

    state.clone = ClientsideModel(predator:GetModel() or "models/error.mdl", RENDERGROUP_OTHER)
    if not IsValid(state.clone) then return nil end

    state.clone:SetNoDraw(true)
    safeSet(state.clone, "SetPredictable", false)
    state.clone:SetSolid(SOLID_NONE)
    state.clone:SetMoveType(MOVETYPE_NONE)
    state.clone:DrawShadow(false)
    safeSet(state.clone, "SetLOD", 0)

    return state.clone
end

--[[
    Belly material construction.

    The old material was a flat UnlitGeneric: the captured torso photo got
    pasted onto the belly with no lighting response, which is exactly why it
    looked like a sticker instead of skin.  Now the belly uses a
    VertexLitGeneric material whose shader params ($bumpmap / $phong /
    $halflambert / $surfaceprop ...) are cloned from the PREDATOR'S OWN torso
    material, with only $basetexture swapped for the render target.  The
    belly therefore shades, bumps and highlights exactly like the VNPC body
    it is attached to - using the belly's own phong settings would give it a
    slightly different sheen (the "tint") than the body.
]]

local VMT_PARAM_WHITELIST = {
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

local PHONG_KEYS = {
    ["$phong"] = true,
    ["$phongboost"] = true,
    ["$phongfresnelranges"] = true,
    ["$phongexponent"] = true
}

local DEFAULT_BELLY_PARAMS = {
    ["$bumpmap"] = "models/wormonlooker/belly/normal",
    ["$halflambert"] = "1",
    ["$ambientocclusion"] = "1",
    ["$surfaceprop"] = "Flesh"
}

--- Reads a .vmt and returns the shader params that are safe to reuse on the
--- render-target material.  Returns nil when the file cannot be read.
local function parseBellyVmt(materialName)
    if not materialName or materialName == "" then return nil end

    local path = "materials/" .. materialName .. ".vmt"
    local content = file.Read(path, "GAME")
    if not content then return nil end

    local params = {}
    for key, value in string.gmatch(content, '"(%$[%w_]+)"%s*"([^"]*)"') do
        local lkey = string.lower(key)
        if VMT_PARAM_WHITELIST[lkey] then
            params[lkey] = string.gsub(value, "\\", "/")
        end
    end

    return params
end

--- The material the belly model uses by default (e.g. "models/wormonlooker/
--- belly/belly"), so the shader clone matches the actual belly model even
--- when the entity never called SetMaterial.
local function getBellyDefaultMaterial(belly)
    local model = belly:GetModel()
    if not model or model == "" then return "" end

    local meshes = util.GetModelMeshes(model)
    if meshes and meshes[1] and meshes[1].material then
        return meshes[1].material
    end

    return ""
end

--- The material the predator's body actually uses (SetMaterial override, or
--- the first material of its model), so the belly lights up like the body.
local function getTorsoMaterial(predator)
    if not IsValid(predator) then return "" end

    local mat = predator:GetMaterial()
    if mat and mat ~= "" then return mat end

    local meshes = util.GetModelMeshes(predator:GetModel() or "")
    if meshes and meshes[1] and meshes[1].material then
        return meshes[1].material
    end

    return ""
end

--- Merges param tables in order; earlier tables win.
local function mergeParams(...)
    local merged = {}
    for i = 1, select("#", ...) do
        local t = select(i, ...)
        if t then
            for k, v in pairs(t) do
                if merged[k] == nil then
                    merged[k] = v
                end
            end
        end
    end
    return merged
end

--- Drops phong keys: phong must only appear when the predator body itself
--- uses it, otherwise the belly gets a sheen the body does not have.
local function withoutPhong(t)
    local out = {}
    if not t then return out end
    for k, v in pairs(t) do
        if not PHONG_KEYS[k] then
            out[k] = v
        end
    end
    return out
end

--- Builds the render-target material for one belly.
local function makeBellyMaterial(belly, rt, predator)
    local params = {
        ["$basetexture"] = rt:GetName(),
        ["$ignorez"] = "0"
    }
    local shader = "UnlitGeneric"

    if vnpcs_belly_lit:GetBool() then
        shader = "VertexLitGeneric"
        local bellySource = belly:GetMaterial()
        if not bellySource or bellySource == "" then
            bellySource = getBellyDefaultMaterial(belly)
        end
        -- Priority: predator body params (blend), then belly params for the
        -- belly's own normal map, then generic skin defaults.  Phong only
        -- survives if the predator body uses it.
        local vmtParams = mergeParams(
            parseBellyVmt(getTorsoMaterial(predator)),
            withoutPhong(parseBellyVmt(bellySource)),
            withoutPhong(DEFAULT_BELLY_PARAMS)
        )
        for k, v in pairs(vmtParams) do
            params[k] = v
        end
    end

    local matName = "vnpcs_belly_blend_mat_" .. belly:EntIndex() .. "_" .. nextUID
    local ok, mat = pcall(CreateMaterial, matName, shader, params)
    if ok and mat then
        mat:SetTexture("$basetexture", rt)
        return mat
    end

    return nil
end

local function createState(belly, predator)
    nextUID = nextUID + 1

    local rtName = "vnpcs_belly_rt_" .. belly:EntIndex() .. "_" .. nextUID
    local rt = GetRenderTarget(rtName, RT_SIZE, RT_SIZE, IMAGE_FORMAT_RGBA8888)
    local mat = makeBellyMaterial(belly, rt, predator)
    if not mat then
        -- Last resort: the previous flat unlit material so the feature never
        -- hard-fails a belly.
        mat = CreateMaterial("vnpcs_belly_rt_mat_" .. belly:EntIndex() .. "_" .. nextUID, "UnlitGeneric", {
            ["$basetexture"] = rt:GetName(),
            ["$ignorez"] = "0"
        })
        if mat then
            mat:SetTexture("$basetexture", rt)
        end
    end

    local state = {
        belly = belly,
        rt = rt,
        material = mat,
        signature = nil,
        nextPoll = 0,
        queued = false,
        ready = false
    }

    states[belly] = state
    return state
end

local function queueCapture(state)
    if state.queued then return end
    state.queued = true
    captureQueue[#captureQueue + 1] = state
end

local function pollState(state, predator)
    local now = CurTime()
    if state.nextPoll > now then return end
    state.nextPoll = now + SIGNATURE_POLL_RATE

    local signature = buildSignature(predator)
    if signature ~= state.signature then
        state.signature = signature
        queueCapture(state)
    end
end

local function captureTorso(state, predator)
    local clone = ensureDuplicate(state, predator)
    if not IsValid(clone) then return false end

    copyVisualState(predator, clone)
    forceTPose(clone)

    local target, mins, maxs = getTorsoTarget(clone)
    local height = math.max(maxs.z - mins.z, 32)
    local width = math.max(maxs.y - mins.y, 24)
    -- Frame the STOMACH, not the chest: the belly hangs at the abdomen, so
    -- centring the capture on the mid-chest bakes the breast region of the
    -- model texture onto the belly.  The centre and tightness are tunable
    -- per model with vnpcs_belly_rt_center / vnpcs_belly_rt_zoom.
    local centerFrac = math.Clamp(vnpcs_belly_rt_center:GetFloat(), 0.1, 0.8)
    local zoom = math.Clamp(vnpcs_belly_rt_zoom:GetFloat(), 0.6, 1.6)
    target.z = mins.z + height * centerFrac
    local distance = math.max(height * 0.55 * zoom, width * 1.15 * zoom, 28)
    local camPos = target + Vector(distance, 0, height * 0.02)
    local camAng = (target - camPos):Angle()
    local fov = math.Clamp(34 + (width / height) * 12, 34, 52)

    local oldX, oldY, oldW, oldH = 0, 0, ScrW(), ScrH()
    if render.GetViewPort then
        oldX, oldY, oldW, oldH = render.GetViewPort()
    end

    render.PushRenderTarget(state.rt)
    render.SetViewPort(0, 0, RT_SIZE, RT_SIZE)
    -- Clear to a slightly darkened belly skin color: where the captured
    -- torso photo does not cover the belly surface, the rim reads as soft
    -- ambient shading instead of a tinted border or hard black edge.
    local bellyColor = state.belly:GetColor() or WHITE
    render.Clear(
        math.Clamp((bellyColor.r or 255) * 0.72, 0, 255),
        math.Clamp((bellyColor.g or 255) * 0.72, 0, 255),
        math.Clamp((bellyColor.b or 255) * 0.72, 0, 255),
        255, true, true)
    render.ClearDepth()

    if render.FogMode then render.FogMode(MATERIAL_FOG_NONE) end
    render.SuppressEngineLighting(true)
    render.ResetModelLighting(0.82, 0.82, 0.82)
    render.SetModelLighting(BOX_FRONT, 1.25, 1.25, 1.25)
    render.SetModelLighting(BOX_BACK, 0.35, 0.35, 0.35)
    render.SetModelLighting(BOX_LEFT, 0.7, 0.7, 0.7)
    render.SetModelLighting(BOX_RIGHT, 0.7, 0.7, 0.7)
    render.SetModelLighting(BOX_TOP, 0.55, 0.55, 0.55)
    render.SetModelLighting(BOX_BOTTOM, 0.35, 0.35, 0.35)
    render.SetColorModulation(1, 1, 1)
    render.SetBlend(1)

    cam.Start3D(camPos, camAng, fov, 0, 0, RT_SIZE, RT_SIZE, 1, distance + height * 2)
        cam.IgnoreZ(false)
        clone:DrawModel()
    cam.End3D()

    render.SuppressEngineLighting(false)
    render.SetColorModulation(1, 1, 1)
    render.SetBlend(1)
    if render.FogMode then render.FogMode(MATERIAL_FOG_LINEAR) end
    render.SetViewPort(oldX or 0, oldY or 0, oldW or ScrW(), oldH or ScrH())
    render.PopRenderTarget()

    if state.material then
        state.material:SetTexture("$basetexture", state.rt)
    end
    state.ready = true
    return true
end

local function removeState(belly)
    local state = states[belly]
    if not state then return end

    if IsValid(state.clone) then
        state.clone:Remove()
    end

    states[belly] = nil
end

local function getPredatorForBelly(belly)
    local predator = belly.NPC
    if not IsValid(predator) then
        predator = belly:GetNWEntity("NPCParent")
    end

    return predator
end

function BellyRT.GetMaterial(belly)
    if not vnpcs_belly_rt_enable:GetBool() then return nil end
    if not IsValid(belly) then return nil end

    local predator = getPredatorForBelly(belly)
    if not IsValid(predator) then return nil end

    local state = states[belly] or createState(belly, predator)
    pollState(state, predator)

    if state.ready then
        return state.material
    end

    return nil
end

function BellyRT.MarkDirty(belly)
    local state = states[belly]
    if state then
        state.signature = nil
        state.nextPoll = 0
    end
end

hook.Add("Think", "VNPCS_BellyRT_Update", function()
    for belly, state in pairs(states) do
        if not IsValid(belly) then
            removeState(belly)
        else
            local predator = getPredatorForBelly(belly)
            if IsValid(predator) then
                pollState(state, predator)
            end

            -- Keep the off-screen duplicate frozen in a reference/T-pose even
            -- between captures; it never participates in gameplay simulation.
            if IsValid(state.clone) then
                forceTPose(state.clone)
            end
        end
    end
end)

hook.Add("PostRender", "VNPCS_BellyRT_Capture", function()
    local captures = 0
    local queueIndex = 1

    while captureQueue[queueIndex] and captures < CAPTURES_PER_FRAME do
        local state = table.remove(captureQueue, queueIndex)
        if state then
            state.queued = false
            local belly = state.belly
            local predator = IsValid(belly) and getPredatorForBelly(belly) or nil
            if IsValid(belly) and IsValid(predator) then
                captureTorso(state, predator)
                captures = captures + 1
            end
        end
    end
end)

hook.Add("EntityRemoved", "VNPCS_BellyRT_Cleanup", function(ent)
    if states[ent] then
        removeState(ent)
        return
    end

    for belly, state in pairs(states) do
        if state and state.clone == ent then
            states[belly] = nil
        end
    end
end)
