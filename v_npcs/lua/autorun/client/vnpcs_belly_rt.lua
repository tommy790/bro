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

local function getRTSize()
    local cv_size = GetConVar("vnpcs_belly_rt_size")
    local sz = cv_size and cv_size:GetInt() or 512
    if sz < 128 then return 128 end
    if sz > 2048 then return 2048 end
    return sz
end

local DUPLICATE_ORIGIN = Vector(0, 0, 0)
local WHITE = Color(255, 255, 255, 255)
local ZERO_ANGLE = Angle(0, 0, 0)
local ONE_VECTOR = Vector(1, 1, 1)

local states = {}
local captureQueue = {}
local nextUID = 0

function BellyRT.ClearAll()
    for belly, state in pairs(states) do
        if IsValid(state.clone) then
            state.clone:Remove()
        end
    end
    table.Empty(states)
    table.Empty(captureQueue)
end

function BellyRT.RefreshAll()
    for belly, _ in pairs(states) do
        BellyRT.MarkDirty(belly)
    end
end

cvars.AddChangeCallback("vnpcs_belly_rt_size", function()
    BellyRT.ClearAll()
end, "VNPCS_BellyRT_SizeChanged")

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

local function createState(belly)
    nextUID = nextUID + 1

    local rtSize = getRTSize()
    local rtName = "vnpcs_belly_rt_" .. belly:EntIndex() .. "_" .. nextUID
    local matName = "vnpcs_belly_rt_mat_" .. belly:EntIndex() .. "_" .. nextUID
    local rt = GetRenderTarget(rtName, rtSize, rtSize)
    local mat = CreateMaterial(matName, "VertexLitGeneric", {
        ["$basetexture"] = rt:GetName(),
        ["$bumpmap"] = "models/wormonlooker/belly/normal",
        ["$ambientocclusion"] = "0",
        ["$surfaceprop"] = "Flesh",
        ["$halflambert"] = "1",
        ["$phong"] = "1",
        ["$phongboost"] = "0.5",
        ["$phongexponent"] = "10",
        ["$phongfresnelranges"] = "[0.05 0.3 1]",
        ["$ignorez"] = "0",
        ["$model"] = "1",
        ["$vertexcolor"] = "0"
    })
    mat:SetTexture("$basetexture", rt)

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

local function isInBattle(predator)
    if not IsValid(predator) then return false end
    local enemy = safeCall(predator, "GetEnemy")
    if IsValid(enemy) then return true end
    local drgEnemy = safeCall(predator, "GetNW2Entity", "DrGBaseEnemy")
    if IsValid(drgEnemy) then return true end
    local drgTarget = safeCall(predator, "GetNW2Entity", "DrGBaseTarget")
    if IsValid(drgTarget) then return true end
    local nwEnemy = safeCall(predator, "GetNWEntity", "Enemy")
    if IsValid(nwEnemy) then return true end
    if SCHED_CHASE_ENEMY and safeCall(predator, "IsCurrentSchedule", SCHED_CHASE_ENEMY) then return true end
    if SCHED_COMBAT_FACE and safeCall(predator, "IsCurrentSchedule", SCHED_COMBAT_FACE) then return true end
    local wep = safeCall(predator, "GetActiveWeapon")
    if IsValid(wep) and IsValid(enemy) then return true end
    return false
end

function BellyRT.IsPredatorInBattle(predator)
    return isInBattle(predator)
end

local function queueCapture(state, predator)
    if state.queued then return end
    state.queued = true
    if isInBattle(predator) then
        state.priority = true
        table.insert(captureQueue, 1, state)
    else
        state.priority = false
        table.insert(captureQueue, state)
    end
end

local function pollState(state, predator)
    local now = CurTime()
    if state.nextPoll > now then return end
    local battle_rate = GetConVar("vnpcs_belly_rt_battle_poll_rate")
    local idle_rate = GetConVar("vnpcs_belly_rt_poll_rate")
    local pollRate = isInBattle(predator) and (battle_rate and battle_rate:GetFloat() or 0.05) or (idle_rate and idle_rate:GetFloat() or 0.15)
    state.nextPoll = now + pollRate

    local signature = buildSignature(predator)
    if signature ~= state.signature then
        state.signature = signature
        queueCapture(state, predator)
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
    local distance = math.max(height * 0.5, width * 1.0, 26)
    local camPos = target + Vector(distance, 0, height * 0.01)
    local camAng = (target - camPos):Angle()
    local fov = math.Clamp(24 + (width / height) * 8, 20, 36)

    local oldX, oldY, oldW, oldH = 0, 0, ScrW(), ScrH()
    if render.GetViewPort then
        oldX, oldY, oldW, oldH = render.GetViewPort()
    end

    render.PushRenderTarget(state.rt)
    render.SetViewPort(0, 0, RT_SIZE, RT_SIZE)
    render.Clear(0, 0, 0, 255, true, true)
    render.ClearDepth()

    if render.FogMode then render.FogMode(MATERIAL_FOG_NONE) end
    render.SuppressEngineLighting(true)
    render.ResetModelLighting(0.95, 0.95, 0.95)
    render.SetModelLighting(BOX_FRONT, 1.05, 1.05, 1.05)
    render.SetModelLighting(BOX_BACK, 0.85, 0.85, 0.85)
    render.SetModelLighting(BOX_LEFT, 0.92, 0.92, 0.92)
    render.SetModelLighting(BOX_RIGHT, 0.92, 0.92, 0.92)
    render.SetModelLighting(BOX_TOP, 0.95, 0.95, 0.95)
    render.SetModelLighting(BOX_BOTTOM, 0.88, 0.88, 0.88)
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

    state.material:SetTexture("$basetexture", state.rt)
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
    local cv_en = GetConVar("vnpcs_belly_rt_enabled")
    if cv_en and not cv_en:GetBool() then return nil end
    if not IsValid(belly) then return nil end

    local predator = getPredatorForBelly(belly)
    if not IsValid(predator) then return nil end

    local state = states[belly] or createState(belly)
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
    local cv_max = GetConVar("vnpcs_belly_rt_max_captures")
    local cv_battle = GetConVar("vnpcs_belly_rt_battle_captures")
    local max_captures = cv_max and cv_max:GetInt() or 1
    local queueIndex = 1

    while captureQueue[queueIndex] and captures < max_captures do
        local state = table.remove(captureQueue, queueIndex)
        if state then
            state.queued = false
            local belly = state.belly
            local predator = IsValid(belly) and getPredatorForBelly(belly) or nil
            if IsValid(belly) and IsValid(predator) then
                if state.priority or isInBattle(predator) then
                    max_captures = math.max(max_captures, cv_battle and cv_battle:GetInt() or 4)
                end
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
