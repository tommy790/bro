if not CLIENT then return end

--[[
    V-NPC belly render-target texturing

    A belly samples its predator's live torso appearance instead of a
    hand-authored tint. To do that the predator is duplicated into a hidden
    clientside model, copied into a neutral T-pose and rendered into a render
    target, which is then bound as the belly's material.

    Resource ownership
    ------------------
    GetRenderTarget and CreateMaterial cache by name for the lifetime of the map
    and there is no way to free either from Lua. Anything that allocates one per
    entity therefore leaks permanently. This module instead uses:

      * a FIXED pool of render targets with deterministic names, so the number of
        RTs that can ever exist is bounded by (distinct sizes x max slot count)
        rather than by how many NPCs have been spawned over the session;

      * a cache keyed by the predator's *appearance signature*, so ten identical
        NPCs share one texture and one capture instead of ten of each;

      * a single shared clone entity reused across every capture, rather than one
        hidden ClientsideModel per belly.

    Slots are reclaimed by LRU. Work is entirely draw-driven: a belly that is not
    being rendered costs nothing, because GetMaterial is only called from Draw.
]]

VNPCS_BellyRT = VNPCS_BellyRT or {}

local BellyRT = VNPCS_BellyRT

local cvarEnabled = CreateClientConVar("vnpcs_belly_rt", "1", true, false,
    "Texture V-NPC bellies from the predator's own skin.")
local cvarSlots = CreateClientConVar("vnpcs_belly_rt_slots", "8", true, false,
    "How many belly render targets may exist at once. Distinct-looking predators beyond this share by least-recently-used.")
local cvarSize = CreateClientConVar("vnpcs_belly_rt_size", "512", true, false,
    "Belly render target resolution. 128, 256, 512 or 1024.")

local MIN_SLOTS, MAX_SLOTS = 1, 32
local ALLOWED_SIZES = {[128] = true, [256] = true, [512] = true, [1024] = true}
local DEFAULT_SIZE = 512

local CAPTURES_PER_FRAME = 2
local SIGNATURE_POLL_RATE = 0.15
local SWEEP_INTERVAL = 5
local EVICT_GRACE = 0.05 -- never evict something drawn this frame

local DUPLICATE_ORIGIN = Vector(0, 0, 0)
local WHITE = Color(255, 255, 255, 255)
local ZERO_ANGLE = Angle(0, 0, 0)
local ONE_VECTOR = Vector(1, 1, 1)

local pool = {}          -- array of { rt, material, key }
local poolSize = 0       -- resolution the current pool was built at
local cache = {}         -- signature -> entry { signature, slot, ready, lastUsed, predator }
local bellyStates = {}   -- belly -> { signature, nextPoll, lastEntry }
local captureQueue = {}  -- array of entries awaiting a capture
local sharedClone
local nextSweep = 0

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

--[[     APPEARANCE SIGNATURE     ]]

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

--[[
    Two predators producing the same signature are visually indistinguishable
    from the belly's point of view, so they can share a texture. This is what
    turns "one RT per NPC" into "one RT per distinct look".
]]
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

--[[     CLONE     ]]

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

--[[
    One clone is reused for every capture. Captures are sequential (they all run
    inside a single PostRender pass), so there is never a need for more than one,
    and it means a belly no longer owns a hidden entity for its whole lifetime.
]]
local function ensureClone(model)
    if not IsValid(sharedClone) then
        sharedClone = ClientsideModel(model or "models/error.mdl", RENDERGROUP_OTHER)
        if not IsValid(sharedClone) then return nil end

        sharedClone:SetNoDraw(true)
        safeSet(sharedClone, "SetPredictable", false)
        sharedClone:SetSolid(SOLID_NONE)
        sharedClone:SetMoveType(MOVETYPE_NONE)
        sharedClone:DrawShadow(false)
        safeSet(sharedClone, "SetLOD", 0)
    end

    return sharedClone
end

--[[     POOL     ]]

local function getConfiguredSize()
    local size = math.floor(cvarSize:GetInt() or DEFAULT_SIZE)
    if not ALLOWED_SIZES[size] then return DEFAULT_SIZE end
    return size
end

local function getConfiguredSlots()
    return math.Clamp(math.floor(cvarSlots:GetInt() or 8), MIN_SLOTS, MAX_SLOTS)
end

local function clearCache()
    cache = {}
    captureQueue = {}

    for _, state in pairs(bellyStates) do
        state.lastEntry = nil
    end
end

--[[
    Slot names are deterministic (`vnpcs_belly_rt_<size>_<index>`), so the set of
    render targets this addon can ever allocate is fixed and small. Rebuilding
    the pool after a convar change reuses any name that already exists.
]]
local function ensurePool()
    local size = getConfiguredSize()
    local slots = getConfiguredSlots()

    if poolSize == size and #pool == slots then return end

    clearCache()

    pool = {}
    poolSize = size

    for index = 1, slots do
        local name = string.format("vnpcs_belly_rt_%d_%d", size, index)
        local rt = GetRenderTarget(name, size, size)
        local material = CreateMaterial(name .. "_mat", "UnlitGeneric", {
            ["$basetexture"] = rt:GetName(),
            ["$ignorez"] = "0",
            ["$nolod"] = "1"
        })
        material:SetTexture("$basetexture", rt)

        pool[index] = { rt = rt, material = material, key = nil }
    end
end

local function releaseSlot(slot)
    if slot.key then
        cache[slot.key] = nil
        slot.key = nil
    end
end

local function acquireSlot(now)
    for index = 1, #pool do
        if not pool[index].key then return pool[index] end
    end

    -- everything is in use: evict the least recently drawn entry
    local victim, victimTime
    for _, entry in pairs(cache) do
        if now - entry.lastUsed > EVICT_GRACE then
            if not victimTime or entry.lastUsed < victimTime then
                victim, victimTime = entry, entry.lastUsed
            end
        end
    end

    --[[
        Every slot is in use by something drawn this very frame. Rather than
        thrash (evict, recapture, evict again, every frame) the caller keeps its
        previous texture, or falls back to the plain belly material. Bounded and
        stable; the user can raise vnpcs_belly_rt_slots if they want more.
    ]]
    if not victim then
        if not BellyRT._warnedExhausted then
            BellyRT._warnedExhausted = true
            MsgN(string.format(
                "[V-NPCs] %d belly render target slots are all in use; extra predators will use their plain belly material. Raise vnpcs_belly_rt_slots to change this.",
                #pool))
        end

        return nil
    end

    local slot = victim.slot
    releaseSlot(slot)

    return slot
end

local function entryIsLive(entry)
    return entry ~= nil
        and entry.ready
        and cache[entry.signature] == entry
        and entry.slot.key == entry.signature
end

local function queueCapture(entry)
    if entry.queued then return end
    entry.queued = true
    captureQueue[#captureQueue + 1] = entry
end

--[[     CAPTURE     ]]

local function captureTorso(entry, predator)
    local clone = ensureClone(predator:GetModel())
    if not IsValid(clone) then return false end

    copyVisualState(predator, clone)
    forceTPose(clone)

    local size = poolSize
    local target, mins, maxs = getTorsoTarget(clone)
    local height = math.max(maxs.z - mins.z, 32)
    local width = math.max(maxs.y - mins.y, 24)
    local distance = math.max(height * 0.72, width * 1.45, 36)
    local camPos = target + Vector(distance, 0, height * 0.02)
    local camAng = (target - camPos):Angle()
    local fov = math.Clamp(32 + (width / height) * 10, 28, 46)

    render.PushRenderTarget(entry.slot.rt, 0, 0, size, size)
    render.Clear(0, 0, 0, 255, true, true)
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

    cam.Start3D(camPos, camAng, fov, 0, 0, size, size, 1, distance + height * 2)
        cam.IgnoreZ(false)
        clone:DrawModel()
    cam.End3D()

    render.SuppressEngineLighting(false)
    render.SetColorModulation(1, 1, 1)
    render.SetBlend(1)
    if render.FogMode then render.FogMode(MATERIAL_FOG_LINEAR) end
    render.PopRenderTarget()

    entry.slot.material:SetTexture("$basetexture", entry.slot.rt)
    entry.ready = true

    return true
end

--[[     PUBLIC     ]]

local function getPredatorForBelly(belly)
    local predator = belly.NPC
    if not IsValid(predator) then
        predator = belly:GetNWEntity("NPCParent")
    end

    return predator
end

function BellyRT.GetMaterial(belly)
    if not cvarEnabled:GetBool() then return nil end
    if not IsValid(belly) then return nil end

    local predator = getPredatorForBelly(belly)
    if not IsValid(predator) then return nil end

    ensurePool()

    local state = bellyStates[belly]
    if not state then
        state = { nextPoll = 0 }
        bellyStates[belly] = state
    end

    local now = RealTime()

    if state.nextPoll <= now then
        state.nextPoll = now + SIGNATURE_POLL_RATE
        state.signature = buildSignature(predator)
    end

    local signature = state.signature
    if not signature then return nil end

    local entry = cache[signature]

    if not entry then
        local slot = acquireSlot(now)

        if slot then
            slot.key = signature
            entry = {
                signature = signature,
                slot = slot,
                ready = false,
                lastUsed = now,
                predator = predator
            }
            cache[signature] = entry
        end
    end

    if entry then
        entry.lastUsed = now
        entry.predator = predator

        if entry.ready then
            state.lastEntry = entry
            return entry.slot.material
        end

        queueCapture(entry)
    end

    --[[
        Not captured yet. Keep showing the last texture this belly displayed, as
        long as its slot has not since been handed to a different look -- that
        avoids an untextured flash every time the predator blinks and changes
        its flex signature.
    ]]
    if entryIsLive(state.lastEntry) then
        state.lastEntry.lastUsed = now
        return state.lastEntry.slot.material
    end

    return nil
end

function BellyRT.MarkDirty(belly)
    local state = bellyStates[belly]
    if not state then return end

    if state.signature then
        local entry = cache[state.signature]
        if entry then
            entry.ready = false
            queueCapture(entry)
        end
    end

    state.nextPoll = 0
end

-- exposed for the console command below, and handy when profiling
function BellyRT.GetStats()
    local used, ready = 0, 0
    for _, entry in pairs(cache) do
        used = used + 1
        if entry.ready then ready = ready + 1 end
    end

    local tracked = 0
    for _ in pairs(bellyStates) do tracked = tracked + 1 end

    return {
        slots = #pool,
        size = poolSize,
        cached = used,
        ready = ready,
        queued = #captureQueue,
        bellies = tracked,
        clones = IsValid(sharedClone) and 1 or 0
    }
end

--[[     HOOKS     ]]

local function sweep(now)
    if nextSweep > now then return end
    nextSweep = now + SWEEP_INTERVAL

    for belly in pairs(bellyStates) do
        if not IsValid(belly) then
            bellyStates[belly] = nil
        end
    end
end

hook.Add("PostRender", "VNPCS_BellyRT_Capture", function()
    local now = RealTime()
    sweep(now)

    local captures = 0

    while captures < CAPTURES_PER_FRAME do
        local entry = table.remove(captureQueue, 1)
        if not entry then break end

        entry.queued = false

        -- the entry may have been evicted while it sat in the queue
        if cache[entry.signature] == entry and IsValid(entry.predator) then
            captureTorso(entry, entry.predator)
            captures = captures + 1
        end
    end
end)

hook.Add("EntityRemoved", "VNPCS_BellyRT_Cleanup", function(ent)
    if bellyStates[ent] then
        bellyStates[ent] = nil
        return
    end

    if ent == sharedClone then
        sharedClone = nil
    end
end)

concommand.Add("vnpcs_belly_rt_stats", function()
    local stats = BellyRT.GetStats()
    MsgN("[V-NPCs] belly render targets")
    MsgN(string.format("  pool        : %d slots @ %dx%d", stats.slots, stats.size, stats.size))
    MsgN(string.format("  looks cached: %d (%d captured)", stats.cached, stats.ready))
    MsgN(string.format("  queued      : %d", stats.queued))
    MsgN(string.format("  bellies     : %d", stats.bellies))
    MsgN(string.format("  clone ents  : %d", stats.clones))
end, nil, "Print V-NPCs belly render target pool usage.")
