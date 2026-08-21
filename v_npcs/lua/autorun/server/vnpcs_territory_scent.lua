-- V-NPCs Dynamic Scent / Pheromone Trail & Predator Territory Marking Engine (vnpcs_territory_scent.lua)
-- Predators leave territory scent markers when digesting prey or walking full, alerting shy prey and attracting starving sisters

local scent_enabled = CreateConVar("vnpcs_territory_scent_enabled", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Enable predator territory scent marking and pheromone trails")
local scent_duration = CreateConVar("vnpcs_scent_duration", "60.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Duration in seconds for territory scent nodes to persist in the world")
local scent_radius = CreateConVar("vnpcs_scent_radius", "400.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Detection radius for prey to smell predator territory and starving sisters to forage")
local scent_hunger_attract = CreateConVar("vnpcs_scent_hunger_attract", "65.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Minimum hunger percentage for empty sister predators to be drawn to territory scent")

VNPC_ActiveTerritoryNodes = VNPC_ActiveTerritoryNodes or {}

function VNPC_CreateTerritoryScentNode(pred, pos, scentType)
    if not scent_enabled:GetBool() then return nil end
    if not IsValid(pred) then return nil end

    local now = CurTime()
    local origin = pos or pred:GetPos()

    -- Ensure we do not spam nodes at the exact same location
    for _, node in ipairs(VNPC_ActiveTerritoryNodes) do
        if node.pred == pred and node.pos:DistToSqr(origin) < (80 * 80) and (node.expireTime - now) > 10.0 then
            node.expireTime = now + scent_duration:GetFloat()
            return node
        end
    end

    local node = {
        pos = origin,
        pred = pred,
        scentType = scentType or "digestion",
        expireTime = now + scent_duration:GetFloat(),
        id = math.random(100000, 999999)
    }

    table.insert(VNPC_ActiveTerritoryNodes, node)

    -- Cap active nodes at 45 to prevent memory/CPU accumulation
    while #VNPC_ActiveTerritoryNodes > 45 do
        table.remove(VNPC_ActiveTerritoryNodes, 1)
    end

    if scentType == "digestion" and pred.EmitSound then
        pred:EmitSound("belly/snd_digeststart.wav", 45, math.random(110, 120))
    end

    return node
end

-- Hook into movement loop to leave trail scent when full and moving
hook.Add("Think", "VNPC_PredatorScentTrail_Loop", function()
    if not scent_enabled:GetBool() then return end

    local now = CurTime()
    for _, pred in ipairs(ents.GetAll()) do
        if not IsValid(pred) or pred:Health() <= 0 then continue end
        if not (pred.IsDrGNextbot or pred.VNPC_FemaleModelVore or pred.Predator) then continue end
        if (pred.VNPC_NextScentTrailTime or 0) > now then continue end

        local vel = pred:GetVelocity():Length2D()
        if vel < 50 then continue end

        local belly = pred.VNPC_Belly or pred.Belly
        if not IsValid(belly) then continue end

        local hasPrey = (belly.Prey and #belly.Prey > 0) or (belly.DigestionPhase and belly.DigestionPhase > 0) or (belly.BaseScale and belly.BaseScale > 0.1)
        if hasPrey then
            VNPC_CreateTerritoryScentNode(pred, pred:GetPos(), "trail")
            pred.VNPC_NextScentTrailTime = now + 6.0
        end
    end
end)

-- Main AI reaction loop for prey and sister predators
hook.Add("Think", "VNPC_TerritoryScent_AI_Loop", function()
    if not scent_enabled:GetBool() then return end

    local now = CurTime()
    local radius = scent_radius:GetFloat()
    local radiusSqr = radius * radius
    local hungerThresh = scent_hunger_attract:GetFloat()

    for i = #VNPC_ActiveTerritoryNodes, 1, -1 do
        local node = VNPC_ActiveTerritoryNodes[i]
        if now >= node.expireTime then
            table.remove(VNPC_ActiveTerritoryNodes, i)
            continue
        end

        for _, ent in ipairs(ents.FindInSphere(node.pos, radius)) do
            if not IsValid(ent) or ent:Health() <= 0 or ent == node.pred then continue end
            if ent.Vored or ent.VNPC_Vored then continue end

            -- 1. Starving sister predators are drawn to forage at territory nodes
            if ent.IsDrGNextbot or ent.VNPC_FemaleModelVore or ent.Predator then
                if not IsValid(VNPC_GetEntityEnemy and VNPC_GetEntityEnemy(ent) or nil) and (ent.VNPC_Hunger or 0) >= hungerThresh then
                    local belly = ent.VNPC_Belly or ent.Belly
                    local isEmpty = not IsValid(belly) or ((not belly.Prey or #belly.Prey == 0) and (belly.DigestionPhase or 0) == 0)
                    if isEmpty and (ent.VNPC_NextScentForageTime or 0) <= now then
                        ent.VNPC_NextScentForageTime = now + 12.0
                        if ent.SetSchedule then pcall(ent.SetSchedule, ent, SCHED_FORCED_GO_RUN) end
                        if ent.SetLastPosition then pcall(ent.SetLastPosition, ent, node.pos) end
                        if ent.EmitSound then
                            ent:EmitSound("belly/snd_digeststart.wav", 65, 108)
                        end
                    end
                end
                continue
            end

            -- 2. Shy / Civilian prey NPCs become anxious and flee the territory scent
            if ent:IsNPC() or ent:IsNextBot() then
                if (ent.VNPC_SmelledPredatorScent or 0) > now then continue end

                local cls = ent:GetClass() or ""
                local isCitizen = (ent.Classify and ent:Classify() == CLASS_CITIZEN) or cls:find("citizen") or cls:find("hostage")
                if isCitizen then
                    ent.VNPC_SmelledPredatorScent = now + 14.0

                    if ent.EmitSound then
                        local snd = math.random() < 0.5 and "npc/citizen/fear01.wav" or "npc/citizen/sigh01.wav"
                        ent:EmitSound(snd, 70, math.random(95, 105))
                    end

                    if IsValid(node.pred) and node.pred:Health() > 0 then
                        if VNPC_AI_SetSchedule then
                            VNPC_AI_SetSchedule(ent, SCHED_RUN_FROM_ENEMY, "flee", "scent_flee", {
                                enemy = node.pred, hold = 3.0
                            })
                        else
                            if ent.SetEnemy then pcall(ent.SetEnemy, ent, node.pred) end
                            if ent.SetSchedule then pcall(ent.SetSchedule, ent, SCHED_RUN_FROM_ENEMY) end
                        end
                    else
                        if VNPC_AI_SetSchedule then
                            VNPC_AI_SetSchedule(ent, SCHED_TAKE_COVER_FROM_ORIGIN, "flee", "scent_cover", { hold = 3.0 })
                        elseif ent.SetSchedule then
                            pcall(ent.SetSchedule, ent, SCHED_TAKE_COVER_FROM_ORIGIN)
                        end
                    end
                end
            end
        end
    end
end)

concommand.Add("vnpcs_territory_status", function(ply)
    print("=========================================")
    print("[V-NPCs] Predator Territory Scent & Pheromones Status")
    print("Enabled: " .. tostring(scent_enabled:GetBool()))
    print("Duration: " .. tostring(scent_duration:GetFloat()) .. "s")
    print("Detection Radius: " .. tostring(scent_radius:GetFloat()) .. " units")
    print("Hunger Attraction Threshold: " .. tostring(scent_hunger_attract:GetFloat()) .. "%")
    print("-----------------------------------------")
    local now = CurTime()
    for idx, node in ipairs(VNPC_ActiveTerritoryNodes) do
        print(string.format(" -> Scent Node [#%d] Type: %s | Owner: %s | Expiring in: %.1fs",
            idx, tostring(node.scentType), tostring(node.pred), math.max(0, node.expireTime - now)))
    end
    print("Total active territory scent nodes: " .. #VNPC_ActiveTerritoryNodes)
    print("=========================================")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Territory status printed to console. Active nodes: " .. #VNPC_ActiveTerritoryNodes)
    end
end)

concommand.Add("vnpcs_test_territory_scent", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local node = VNPC_CreateTerritoryScentNode(ply, tr.HitPos, "test")
    ply:ChatPrint("[V-NPCs] Created test territory scent node at aimed location (#" .. tostring(node and node.id or "N/A") .. ")!")
end)

concommand.Add("vnpcs_clear_territory", function(ply)
    local count = #VNPC_ActiveTerritoryNodes
    table.Empty(VNPC_ActiveTerritoryNodes)
    print("[V-NPCs] Cleared " .. count .. " territory scent nodes from the map.")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Cleared " .. count .. " territory scent nodes from the map.")
    end
end)
