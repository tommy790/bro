-- V-NPCs Adaptive Environment AI (vnpcs_env_ai.lua)
-- v0.7: predators analyze the map's custom props at runtime - no pre-baked
-- nodes. Tables/desks become cover + pinning surfaces, beds/mattresses become
-- camouflage spots, vents/ducts become ambush perches, cabinets/crates become
-- hiding spots. The hunter AI (vnpcs_hunter_ai.lua) consumes these through the
-- personality matrix: stealthy/shy predators stalk toward cover and go prone
-- near beds, aggressive ones pin targets against tables.

CreateConVar("vnpcs_env_ai_enabled", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Enable runtime map-prop analysis (cover, beds, vents, hiding spots)")
CreateConVar("vnpcs_env_scan_radius", "900", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "How far predators scan for environment props")
CreateConVar("vnpcs_env_debug", "0", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Draw analyzed environment spots")

-- prop model keywords -> spot kind
local PROP_KINDS = {
    cover = { "table", "desk", "bench", "counter", "pallet", "railing" },
    bed = { "bed", "mattress", "couch", "sofa", "blanket" },
    vent = { "vent", "duct", "grill" },
    hiding = { "cabinet", "locker", "crate", "fridge", "shelf", "barrel" }
}

local function classifyProp(ent)
    local mdl = string.lower(ent:GetModel() or "")
    if mdl == "" then return nil end
    for kind, keywords in pairs(PROP_KINDS) do
        for _, kw in ipairs(keywords) do
            if mdl:find(kw, 1, true) then
                return kind
            end
        end
    end
    return nil
end

local function spotHeight(ent)
    local mins, maxs = ent:GetModelBounds()
    if mins and maxs then
        return math.abs(maxs.z - mins.z) * (ent:GetModelScale() or 1)
    end
    return 40
end

-- Scans the area around an entity and caches classified spots for 6 seconds.
function VNPC_ScanEnvironment(pred, force)
    if not IsValid(pred) then return {} end
    local enabled = GetConVar("vnpcs_env_ai_enabled")
    if enabled and not enabled:GetBool() then return {} end

    local now = CurTime()
    if not force and pred.VNPC_EnvSpots and (pred.VNPC_EnvSpotsUntil or 0) > now then
        return pred.VNPC_EnvSpots
    end

    local radius = GetConVar("vnpcs_env_scan_radius")
    local range = radius and radius:GetFloat() or 900
    local spots = {}
    local myPos = pred:GetPos()

    for _, ent in ipairs(ents.FindInSphere(myPos, range)) do
        if not IsValid(ent) then continue end
        if ent == pred then continue end
        local cls = ent:GetClass()
        if cls ~= "prop_physics" and cls ~= "prop_dynamic" and cls ~= "func_breakable" then continue end
        local kind = classifyProp(ent)
        if not kind then continue end

        local pos = ent:GetPos() + Vector(0, 0, spotHeight(ent) * 0.5)
        table.insert(spots, {
            kind = kind,
            pos = pos,
            height = spotHeight(ent),
            ent = ent,
            dist = myPos:Distance(pos)
        })
    end

    table.sort(spots, function(a, b) return a.dist < b.dist end)
    pred.VNPC_EnvSpots = spots
    pred.VNPC_EnvSpotsUntil = now + 6
    return spots
end

-- Nearest spot of a kind near a reference position.
function VNPC_FindEnvSpot(pred, kind, nearPos, maxDist)
    local spots = VNPC_ScanEnvironment(pred)
    local best, bestD = nil, maxDist or 1e9
    for _, spot in ipairs(spots) do
        if spot.kind ~= kind then continue end
        local d = nearPos:Distance(spot.pos)
        if d < bestD then
            bestD = d
            best = spot
        end
    end
    return best
end

-- Hiding: a position behind a cover prop relative to the target's view.
function VNPC_GetCoverPoint(pred, target, coverSpot)
    if not IsValid(pred) or not IsValid(target) or not coverSpot or not IsValid(coverSpot.ent) then return nil end
    local cPos = coverSpot.ent:GetPos()
    -- stand on the far side of the cover from the target
    local away = (cPos - target:GetPos()):GetNormalized()
    local point = cPos + away * (coverSpot.height * 0.6)
    local tr = util.TraceLine({
        start = point + Vector(0, 0, 60),
        endpos = point - Vector(0, 0, 160),
        mask = MASK_SOLID,
        filter = { pred, target, coverSpot.ent }
    })
    if tr.Hit then
        point = tr.HitPos + Vector(0, 0, 2)
    end
    if VNPC_SnapToNav then
        point = VNPC_SnapToNav(point, 150)
    end
    return point
end

-- Pinning: position between the target and its escape so the table corners it.
function VNPC_GetPinPoint(pred, target, coverSpot)
    if not IsValid(pred) or not IsValid(target) or not coverSpot or not IsValid(coverSpot.ent) then return nil end
    local cPos = coverSpot.ent:GetPos()
    -- stand opposite the cover, slightly off to block the wide escape
    local dir = (target:GetPos() - cPos)
    dir.z = 0
    if dir:LengthSqr() < 1 then dir = Vector(1, 0, 0) else dir:Normalize() end
    local point = cPos - dir * 140
    local tr = util.TraceLine({
        start = point + Vector(0, 0, 60),
        endpos = point - Vector(0, 0, 160),
        mask = MASK_SOLID,
        filter = { pred, target, coverSpot.ent }
    })
    if tr.Hit then
        point = tr.HitPos + Vector(0, 0, 2)
    end
    if VNPC_SnapToNav then
        point = VNPC_SnapToNav(point, 150)
    end
    return point
end

-- ---------------------------------------------------------------------------
-- Integration with the hunter AI state machine (called from vnpcs_hunter_ai.lua)
-- ---------------------------------------------------------------------------

-- Returns an override ambush/stalk point when the environment offers cover or
-- a vent perch and the predator's matrix favors stealth. Returns nil to fall
-- back to the generic ambush search.
function VNPC_TryEnvStalkPoint(pred, target)
    if not IsValid(pred) or not IsValid(target) then return nil end
    local ambush = VNPC_GetBehaviorParam and VNPC_GetBehaviorParam(pred, "ambush") or 0
    if ambush < 0.45 then return nil end

    local cover = VNPC_FindEnvSpot(pred, "cover", target:GetPos(), 500)
    if cover then
        local point = VNPC_GetCoverPoint(pred, target, cover)
        if point then
            pred.VNPC_EnvStalkKind = "cover"
            return point
        end
    end
    local vent = VNPC_FindEnvSpot(pred, "vent", target:GetPos(), 600)
    if vent then
        pred.VNPC_EnvStalkKind = "vent"
        return vent.pos
    end
    return nil
end

-- Pin: if the target is backed against a table-like prop, take the open side.
function VNPC_TryPinPoint(pred, target)
    if not IsValid(pred) or not IsValid(target) then return nil end
    local pin = VNPC_GetBehaviorParam and VNPC_GetBehaviorParam(pred, "pin") or 0
    if pin < 0.5 then return nil end

    local cover = VNPC_FindEnvSpot(pred, "cover", target:GetPos(), 220)
    if not cover then return nil end
    return VNPC_GetPinPoint(pred, target, cover)
end

-- Camouflage: shy/stealthy predators use beds to go low while the target sleeps.
function VNPC_TryCamouflage(pred, target)
    if not IsValid(pred) or not IsValid(target) then return false end
    local camo = VNPC_GetBehaviorParam and VNPC_GetBehaviorParam(pred, "camouflage") or 0
    if camo < 0.55 then return false end
    if not target.VNPC_IsSleeping then return false end

    local bed = VNPC_FindEnvSpot(pred, "bed", target:GetPos(), 700)
    if not bed then return false end

    -- move onto the bed and go low (crouch = prone-ish camouflage)
    local d = pred:GetPos():Distance(bed.pos)
    if d > 110 then
        if VNPC_MoveEntTo then
            VNPC_MoveEntTo(pred, bed.pos, false, 0.8)
        end
    else
        if pred.SetCrouching then
            pcall(pred.SetCrouching, pred, true)
            pred.VNPC_EnvCamouflaged = true
            pred.VNPC_EnvCamouflageUntil = CurTime() + 4
        end
    end
    return true
end

-- Clear camouflage state when the target wakes or time passes.
function VNPC_UpdateEnvStates(pred, now)
    if pred.VNPC_EnvCamouflaged and (pred.VNPC_EnvCamouflageUntil or 0) < now then
        pred.VNPC_EnvCamouflaged = nil
        if pred.SetCrouching then
            pcall(pred.SetCrouching, pred, false)
        end
    end
end

if CLIENT then
    hook.Add("PostDrawTranslucentRenderables", "VNPC_EnvAI_Debug", function()
        local dbg = GetConVar("vnpcs_env_debug")
        if not dbg or not dbg:GetBool() then return end
        for _, pred in ipairs(ents.GetAll()) do
            if not IsValid(pred) then continue end
            local spots = pred.VNPC_EnvSpots
            if not spots then continue end
            for _, spot in ipairs(spots) do
                local col = Color(120, 200, 255)
                if spot.kind == "cover" then col = Color(255, 200, 80)
                elseif spot.kind == "bed" then col = Color(160, 120, 255)
                elseif spot.kind == "vent" then col = Color(90, 255, 180)
                elseif spot.kind == "hiding" then col = Color(255, 140, 90) end
                render.DrawWireframeSphere(spot.pos, 10, 6, 6, col, true)
                render.DrawText(spot.pos + Vector(0, 0, 14), string.upper(spot.kind), col, 1.4, 2)
            end
        end
    end)
end

concommand.Add("vnpcs_env_ai_status", function(ply)
    print("===============================================================")
    print("        V-NPCs ADAPTIVE ENVIRONMENT AI (v0.7) STATUS           ")
    print("===============================================================")
    print(" - Env AI Enabled: " .. tostring(GetConVar("vnpcs_env_ai_enabled"):GetBool()))
    print(" - Scan Radius: " .. tostring(GetConVar("vnpcs_env_scan_radius"):GetFloat()))
    local count = 0
    for _, pred in ipairs(ents.GetAll()) do
        if IsValid(pred) and (pred.Predator or pred.VNPC_FemaleModelVore or pred.IsDrGNextbot) then
            local spots = VNPC_ScanEnvironment(pred, true)
            local kinds = {}
            for _, s in ipairs(spots) do
                kinds[s.kind] = (kinds[s.kind] or 0) + 1
            end
            count = count + 1
            print(string.format(" -> #%d [%s] spots: cover=%d bed=%d vent=%d hiding=%d camo=%s pin=%.2f ambush=%.2f",
                pred:EntIndex(), pred.PrintName or pred:GetClass(),
                kinds.cover or 0, kinds.bed or 0, kinds.vent or 0, kinds.hiding or 0,
                tostring(pred.VNPC_EnvCamouflaged or false),
                VNPC_GetBehaviorParam and VNPC_GetBehaviorParam(pred, "pin") or 0,
                VNPC_GetBehaviorParam and VNPC_GetBehaviorParam(pred, "ambush") or 0))
        end
    end
    if count == 0 then print(" - No predators spawned.") end
    print("===============================================================")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Environment AI status printed to console. Predators: " .. count)
    end
end)
